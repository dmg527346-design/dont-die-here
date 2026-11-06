-- DreadLayer (child of LevelAmbienceClient, 2026-10-27 ScareSound). Owner request: "more idle effects, they need to feel
-- more scared, monsters should feel like they are going to get you, more sound effects". Monster AI is untouched: this
-- only changes what the player hears, sees and feels.
--  1. Idle-scare director: dead air never lasts. Something happens every ~15-27 s while nothing else is going on, lighter
--     on level 1 (only small things during the first-game tutorial), harder with every level and with every scare in a
--     row. Held off while a monster hunts close or chases, and for a calm spell after a chase, a hit or being spotted.
--  2. Monster dread: a monster's deep breathing that swells and is muffled by walls as it closes in, your flashlight
--     browning out near one, a gasp + edge slam when one sees you, a low boom + exhale when it loses you; DreadLevel /
--     DreadKickAt drive the vignette pulse and camera micro-shake (SprintController.MovementScreenFX), FlashlightFlicker /
--     FlashlightStutterUntil the beam (FlashlightController).
--  3. Room detail: quiet drips, settling creaks and pipe groans around you, per map, never constant.
-- All of it is local to this player. Nothing here flashes faster than 3 Hz.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Tween=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local CollectionService=game:GetService('CollectionService')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local player=Players.LocalPlayer
local M={}

-- ===== tuning =====
local RULES={ -- first: seconds into the level (or after the tutorial ends); gap: seconds between idle scares; tier: start tier
 [1]={first=16,gap={20,27},tier=0},
 [2]={first=13,gap={17,24},tier=1},
 [3]={first=12,gap={15,22},tier=1},
}
local LATE_RULES={first=10,gap={13,20},tier=2} -- level 4+
local TUTORIAL_RULES={first=30,gap={38,50},tier=0} -- first game, guide cards on screen: small things only
local TUTORIAL_KINDS={creak=true,flicker=true,scrape=true,thud=true}
local STREAK_TRIM,MIN_GAP=2,10 -- each idle scare in a row trims the next gap (more dread the longer it stays quiet)
local HOLD_THREAT=.35 -- a monster hunting this close is the scare: the director waits
local CALM_AFTER_CHASE,CALM_AFTER_HURT,CALM_AFTER_SPOTTED=18,14,12
local KINDS={ -- tier 0 subtle, 1 personal, 2 strong
 {'creak',0,3},{'flicker',0,3},{'scrape',0,2},{'knock',0,3},{'thud',0,2},
 {'steps',1,3},{'follow',1,3},{'sidewhisper',1,2},{'whisper',1,1.5},{'stutter',1,2},
 {'breath',2,2.5},{'shadow',2,2.5},{'roar',2,1.5},{'shriek',2,1.5},{'crash',2,1.5},
}
local DETAILS={ -- room detail one-shots: {cue, weight, volume, speed}
 house={{'StingCreak',4,.09,1},{'ScareDrip',2,.06,1},{'StingHull',1,.045,.5},{'StingBumps',1,.05,.8}},
 wet={{'ScareDrip',5,.085,1},{'StingHull',2,.05,.55},{'StingCreak',1,.07,.9}},
 hall={{'ScareDrip',2,.065,1},{'StingHull',3,.045,.6},{'StingCreak',2,.065,1},{'StingBumps',1,.045,.8}},
}
local MAP_DETAIL={Mansion='house',Hotel='house',Birthday='house',Dungeon='wet',Cruise='wet',Hospital='hall',School='hall',Mall='hall'}
local DETAIL_GAP,DETAIL_FIRST=NumberRange.new(7,15),10

local rng=Random.new()
local function flat(v)v=Vector3.new(v.X,0,v.Z);return v.Magnitude>.01 and v.Unit or Vector3.new(0,0,-1)end
local function rotY(v,deg)return CFrame.Angles(0,math.rad(deg),0):VectorToWorldSpace(v)end
local function muffle(sound,high,verb)
 if not sound then return end
 local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=2;eq.MidGain=-4;eq.HighGain=high or -12;eq.Parent=sound
 if verb then local r=Instance.new('ReverbSoundEffect');r.DecayTime=verb;r.Density=1;r.Diffusion=1;r.WetLevel=-3;r.DryLevel=-6;r.Parent=sound end
end
local function rayParams()
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude
 local list={player.Character};local lf=workspace:FindFirstChild('LocalFlashlight');if lf then table.insert(list,lf)end
 local rc=workspace:FindFirstChild('RoamingCreatures');if rc then table.insert(list,rc)end
 p.FilterDescendantsInstances=list;return p
end
-- A point on the other side of a nearby wall (the next room), else just far off.
local function beyondWall(root,minD,maxD)
 local params=rayParams();local start=root.Position+Vector3.new(0,2,0)
 local base=rng:NextNumber(0,360)
 for i=0,7 do
  local dir=rotY(Vector3.new(0,0,-1),base+i*45)
  local hit=workspace:Raycast(start,dir*maxD,params)
  if hit and hit.Distance>=2 and hit.Distance<maxD-4 then return hit.Position+dir*math.clamp(rng:NextNumber(minD,maxD)-hit.Distance,4,12),true end
 end
 return start+rotY(Vector3.new(0,0,-1),base)*maxD,false
end
local function monsterNear(pos,radius)
 local folder=workspace:FindFirstChild('RoamingCreatures');if not folder then return false end
 for _,m in folder:GetChildren()do local r=m:IsA('Model')and m.PrimaryPart;if r and(r.Position-pos).Magnitude<radius then return true end end
 return false
end

-- ===== new scare kinds (signature as LevelAmbienceClient's scares: (map, root, cam) -> true when it happened) =====
local function install(api)
 local scares=api.scares;local S=api.script

 -- A closed door you are looking at slowly creaks ajar by itself. Client-only: the server door never moves, and it eases
 -- back shut once you come close, walk away or the server swings it.
 local ajar=setmetatable({},{__mode='k'})
 scares.creak=function(map,root,cam)
  local interactive=map:FindFirstChild('Interactive');if not interactive then return false end
  local params=rayParams();local list={}
  for _,m in interactive:GetChildren()do
   if m:IsA('Model')and m:GetAttribute('Kind')=='door'and not m:GetAttribute('Closet')and not m:GetAttribute('Locked')and(m:GetAttribute('Open')or 0)<=.02 and not ajar[m]and m.PrimaryPart then
    local pos=m.PrimaryPart.Position;local d=(pos-root.Position).Magnitude
    if d>=9 and d<=38 then
     local v,on=cam:WorldToViewportPoint(pos)
     local vs=cam.ViewportSize
     if on and v.Z>0 and v.X>vs.X*.15 and v.X<vs.X*.85 then
      local hit=workspace:Raycast(cam.CFrame.Position,pos-cam.CFrame.Position,params)
      if not hit or hit.Instance:IsDescendantOf(m)or(hit.Position-pos).Magnitude<3 then table.insert(list,m)end
     end
    end
   end
  end
  if #list==0 then return false end
  local door=list[rng:NextInteger(1,#list)];local home=door:GetPivot()
  local swing=(door:GetAttribute('Swing')or 90)*(door:GetAttribute('SwingSign')or 1)
  local maxT=rng:NextNumber(.14,.2);ajar[door]=true
  Audio.Play('DoorOpen',door,{volume=.4,speed=rng:NextNumber(.5,.6)})
  task.spawn(function()
   local t0=os.clock();local open=0
   local function pose(t)if door.Parent and(door:GetAttribute('Open')or 0)<=.02 then door:PivotTo(home*CFrame.Angles(0,math.rad(swing*t),0))return true end return false end
   while os.clock()-t0<2.8 do open=maxT*math.sin(math.min(1,(os.clock()-t0)/2.8)*math.pi/2);if not pose(open)then ajar[door]=nil;return end;task.wait()end
   -- hold ajar until you come close (8 studs), 16 s pass, or the server takes the door over
   local held=os.clock()
   while door.Parent and(door:GetAttribute('Open')or 0)<=.02 do
    local r=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    if not r or(r.Position-home.Position).Magnitude<8 or os.clock()-held>16 then break end
    task.wait(.2)
   end
   if door.Parent and(door:GetAttribute('Open')or 0)<=.02 then
    local c=workspace.CurrentCamera;local _,seen=c:WorldToViewportPoint(home.Position)
    if seen then for i=10,0,-1 do if not pose(open*i/10)then break end;task.wait(.07)end;Audio.Play('DoorClose',door,{volume=.12,speed=.8})end
    if door.Parent and(door:GetAttribute('Open')or 0)<=.02 then door:PivotTo(home)end
   end
   ajar[door]=nil
  end)
  S:SetAttribute('LastScareTarget',door.Name);return true
 end

 -- The lights around you stutter for a moment (each off/on at least 0.36 s apart: under 3 Hz), with relay clicks.
 local lightCache,cacheMap,cacheAt={},nil,0
 scares.flicker=function(map,root,cam)
  if map:GetAttribute('CatCurse')==true or monsterNear(root.Position,45)then return false end
  if map~=cacheMap or os.clock()-cacheAt>30 then
   cacheMap=map;cacheAt=os.clock();table.clear(lightCache)
   for _,d in map:GetDescendants()do if d:IsA('Light')and d.Parent and d.Parent:IsA('BasePart')then table.insert(lightCache,d)end end
  end
  local near={}
  for _,l in lightCache do
   local part=l.Parent
   if part and l.Enabled and l.Brightness>0 and not CollectionService:HasTag(part,'MallFlicker')and(part.Position-root.Position).Magnitude<30 then table.insert(near,l)end
  end
  if #near==0 then return false end
  local saved={};for _,l in near do saved[l]={l.Enabled,l.Parent.Material}end
  local function set(on)
   for l,s in saved do if l.Parent then
    l.Enabled=on and s[1];local part=l.Parent
    if s[2]==Enum.Material.Neon then part.Material=on and Enum.Material.Neon or Enum.Material.SmoothPlastic end
   end end
  end
  local click=near[1].Parent
  task.spawn(function()
   for i=1,rng:NextInteger(3,4)do
    if monsterNear(root.Position,45)then break end
    set(false);Audio.Play('FlashlightClick',click,{volume=.16,speed=.55})
    task.wait(rng:NextNumber(.18,.42))
    set(true);task.wait(rng:NextNumber(.2,.5))
   end
   set(true)
  end)
  S:SetAttribute('LastScareTarget',#near..' lights');return true
 end

 -- Something heavy is dragged across the floor in the next room.
 scares.scrape=function(map,root,cam)
  local pos=beyondWall(root,10,24)
  muffle(Audio.Play('ScareScrape',pos,{volume=.42,speed=rng:NextNumber(.72,.88)}),-12,1.6)
  S:SetAttribute('LastScareTarget','next room');return true
 end

 -- Footsteps behind you: they walk when you walk and stop one step after you stop. Standing still, they come up behind
 -- you and stop.
 scares.follow=function(map,root,cam)
  local vel=root.AssemblyLinearVelocity;local moving=Vector3.new(vel.X,0,vel.Z).Magnitude>4
  task.spawn(function()
   local function step(pos)Audio.Play('PlayerFootstep',pos,{volume=.32,speed=rng:NextNumber(.82,.92)})end
   local function behind(dist)local c=workspace.CurrentCamera;local r=player.Character and player.Character:FindFirstChild('HumanoidRootPart');if not c or not r then return nil end;return r.Position-flat(c.CFrame.LookVector)*dist-Vector3.new(0,2.5,0)end
   if moving then
    local t0,last,stoppedAt=os.clock(),0,nil
    while os.clock()-t0<10 do
     local r=player.Character and player.Character:FindFirstChild('HumanoidRootPart');if not r then return end
     local v=r.AssemblyLinearVelocity;local go=Vector3.new(v.X,0,v.Z).Magnitude>3
     if go then stoppedAt=nil
      if os.clock()-last>.5 then last=os.clock();local p=behind(11);if p then step(p)end end
     else
      stoppedAt=stoppedAt or os.clock()
      if os.clock()-stoppedAt>.3 then local p=behind(10);if p then step(p)end;return end -- ...one more step. Then nothing.
     end
     task.wait(.05)
    end
   else
    for i=0,7 do local p=behind(24-i*2.4);if p then step(p)end;task.wait(.52)end
   end
  end)
  S:SetAttribute('LastScareTarget',moving and 'following you' or 'walking up behind you');return true
 end

 -- A whisper right at your left or right ear.
 scares.sidewhisper=function(map,root,cam)
  local side=rng:NextNumber()<.5 and -1 or 1
  Audio.Play('ScareWhisper',cam.CFrame.Position+cam.CFrame.RightVector*side*3-cam.CFrame.LookVector*.6,{volume=.22})
  S:SetAttribute('LastScareTarget',side<0 and 'left ear' or 'right ear');return true
 end

 -- Your flashlight stutters (2.5 Hz) with two dry clicks.
 scares.stutter=function(map,root,cam)
  local lf=workspace:FindFirstChild('LocalFlashlight');local lit=false
  if lf then for _,l in lf:GetChildren()do if l:IsA('Light')and l.Brightness>.05 then lit=true end end end
  if not lit then return false end
  player:SetAttribute('FlashlightStutterUntil',os.clock()+rng:NextNumber(1.2,1.8))
  Audio.Play('FlashlightClick',nil,{volume=.22,speed=.8});task.delay(1,function()Audio.Play('FlashlightClick',nil,{volume=.18,speed=.75})end)
  S:SetAttribute('LastScareTarget','flashlight');return true
 end

 -- Slow breathing right behind your head (only once you have stood still a few seconds).
 scares.breath=function(map,root,cam)
  if api.stillFor()<3 then return false end
  Audio.Play('ScareBreath',cam.CFrame.Position-flat(cam.CFrame.LookVector)*2+Vector3.new(0,.3,0),{volume=.32})
  S:SetAttribute('LastScareTarget','behind your head');return true
 end

 -- A tall black shape crosses the far end of the corridor you are looking down, then it is gone.
 local function figure()
  local m=Instance.new('Model');m.Name='DreadShadow'
  local function part(size,cf,shape)
   local p=Instance.new('Part');p.Size=size;p.CFrame=cf;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
   p.Material=Enum.Material.SmoothPlastic;p.Color=Color3.fromRGB(5,5,7);p.Transparency=.06;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
   if shape then p.Shape=shape end;p.Parent=m;return p
  end
  local body=part(Vector3.new(1.5,3.6,.8),CFrame.new(0,4.3,0))
  part(Vector3.new(1.25,1.4,1.25),CFrame.new(0,6.9,0),Enum.PartType.Ball)
  part(Vector3.new(.38,3.6,.38),CFrame.new(-1,4.1,0)*CFrame.Angles(0,0,math.rad(-4)))
  part(Vector3.new(.38,3.6,.38),CFrame.new(1,4.1,0)*CFrame.Angles(0,0,math.rad(4)))
  part(Vector3.new(.5,2.6,.5),CFrame.new(-.4,1.3,0));part(Vector3.new(.5,2.6,.5),CFrame.new(.4,1.3,0))
  m.PrimaryPart=body;m.WorldPivot=CFrame.new(0,0,0);return m
 end
 scares.shadow=function(map,root,cam)
  if player:GetAttribute('Hiding')then return false end
  local params=rayParams();local eye=cam.CFrame.Position;local look=flat(cam.CFrame.LookVector)
  for _=1,5 do
   local dir=rotY(look,rng:NextNumber(-12,12))
   local hit=workspace:Raycast(eye,dir*70,params);local dist=hit and hit.Distance or 70
   if dist>=22 then
    local center=eye+dir*math.min(dist-2.5,48)
    local floor=workspace:Raycast(center,Vector3.new(0,-14,0),params)
    if floor then
     local side=Vector3.new(-dir.Z,0,dir.X)
     local l=workspace:Raycast(center,-side*7,params);local r=workspace:Raycast(center,side*7,params)
     local a=l and l.Distance-.8 or 6;local b=r and r.Distance-.8 or 6
     if a+b>=2.5 then
      if rng:NextNumber()<.5 then side=-side;a,b=b,a end
      local base=Vector3.new(center.X,floor.Position.Y,center.Z)
      local from,to=base-side*math.min(a,5),base+side*math.min(b,5)
      local f=figure();local face=CFrame.lookAt(from,from+side)
      f:PivotTo(face);f.Parent=workspace
      local cfv=Instance.new('CFrameValue');cfv.Value=face
      cfv.Changed:Connect(function(v)if f.Parent then f:PivotTo(v)end end)
      local secs=(to-from).Magnitude/rng:NextNumber(9,12)+.25
      Tween:Create(cfv,TweenInfo.new(secs,Enum.EasingStyle.Linear),{Value=CFrame.lookAt(to,to+side)}):Play()
      Debris:AddItem(f,secs+.05);Debris:AddItem(cfv,secs+.1)
      muffle(Audio.Play('MonsterWhoosh',base+Vector3.new(0,4,0),{volume=.14,speed=.62}),-10)
      S:SetAttribute('LastScareTarget',('shadow %d studs'):format(math.floor((base-root.Position).Magnitude)))
      return true
     end
    end
   end
  end
  return false
 end

 -- A low growl rolls through the building from far away (no screams).
 scares.roar=function(map,root,cam)
  local pos=beyondWall(root,30,48)
  muffle(Audio.Play('MonsterNotice',pos,{volume=.26,speed=rng:NextNumber(.5,.6)}),-16,4)
  S:SetAttribute('LastScareTarget','far growl');return true
 end

 -- Something falls over just behind the nearest wall.
 scares.crash=function(map,root,cam)
  local pos=beyondWall(root,6,16)
  muffle(Audio.Play('ScareThud',pos,{volume=.45}),-8)
  if rng:NextNumber()<.5 then task.delay(.18,function()muffle(Audio.Play('GlassImpact',pos,{volume=.2,speed=.8}),-8)end)end
  S:SetAttribute('LastScareTarget','behind the wall');return true
 end
end

function M.Start(api)
 install(api)
 local scares,S=api.scares,api.script
 local recent={}
 local function choose(tier,tutorial,forced)
  local list={}
  for _,k in KINDS do
   local name=k[1]
   if forced then if name==forced then table.insert(list,{name,1})end
   elseif scares[name]and k[2]<=tier and(not tutorial or TUTORIAL_KINDS[name])and not table.find(recent,name)then
    table.insert(list,{name,k[3]*(k[2]==tier and 1.6 or 1)})
   end
  end
  return list
 end
 local function runScare(map,root,cam,tier,tutorial,forced)
  local list=choose(tier,tutorial,forced)
  while #list>0 do -- weighted random order until one has a real cause right now
   local total=0;for _,e in list do total+=e[2]end;local roll=rng:NextNumber(0,total);local idx=#list
   for i,e in list do roll-=e[2];if roll<=0 then idx=i break end end
   local name=list[idx][1];table.remove(list,idx)
   local ok,res=pcall(scares[name],map,root,cam)
   if ok and res then
    table.insert(recent,1,name);while #recent>2 do table.remove(recent)end
    S:SetAttribute('LastScare',name);return name
   elseif not ok then S:SetAttribute('LastScareError',name..': '..tostring(res))end
  end
  return nil
 end

 -- shared state between the director and the monster layer
 local calmUntil,lastReal=0,0
 local scareCount,log=0,{}
 local function record(kind)
  scareCount+=1;S:SetAttribute('ScareCount',scareCount)
  local rr=RS:FindFirstChild('RecoveryRound')
  table.insert(log,('L%d %s %.0f'):format(rr and rr:GetAttribute('Round')or 0,kind,workspace:GetServerTimeNow()%1000))
  while #log>12 do table.remove(log,1)end
  S:SetAttribute('ScareLog',table.concat(log,' | '))
 end

 -- ===== 1. idle-scare director =====
 local dMap,nextAt,streak,wasTutorial=nil,0,0,nil
 local acc=0
 Run.Heartbeat:Connect(function(dt)
  acc+=dt;if acc<.2 then return end;acc=0
  local map=workspace:FindFirstChild('Mansion');local round=RS:FindFirstChild('RecoveryRound')
  local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
  local cam=workspace.CurrentCamera;local now=os.clock()
  if not(map and root and hum and cam and round)or player:GetAttribute('MissionActive')~=true or player:GetAttribute('RoundDead')==true or hum.Health<=0 then dMap=nil;return end
  local level=round:GetAttribute('Round')or 1
  local tutorial=level<=1 and player:GetAttribute('TutorialDone')==false
  local rules=tutorial and TUTORIAL_RULES or RULES[level]or LATE_RULES
  if map~=dMap then dMap=map;streak=0;nextAt=now+rules.first;wasTutorial=tutorial end
  if wasTutorial and not tutorial then nextAt=math.min(nextAt,now+(RULES[level]or LATE_RULES).first*.6)end;wasTutorial=tutorial
  local forced=S:GetAttribute('ForceScare') -- Studio tests: a scare name, run now
  if forced and Run:IsStudio()then S:SetAttribute('ForceScare',nil);local name=runScare(map,root,cam,2,false,forced);if name then record(name)end;S:SetAttribute('ForcedOk',name~=nil);return end
  local tier=tutorial and 0 or math.min(2,rules.tier+(streak>=2 and 1 or 0)+(streak>=4 and 1 or 0))
  S:SetAttribute('DreadTier',tier)
  if round:GetAttribute('Phase')~='Searching'or player:GetAttribute('IntroPlaying')or player:GetAttribute('MonsterJumpscareActive')or player:GetAttribute('Hiding')or(api.inVan and api.inVan())then
   nextAt=math.max(nextAt,now+4);S:SetAttribute('NextScareIn',math.floor(nextAt-now));return
  end
  local threat=api.readThreat(root.Position)
  local chased=(player:GetAttribute('ChasedUntil')or 0)>workspace:GetServerTimeNow()
  if chased or threat>HOLD_THREAT then lastReal=now;streak=0;nextAt=math.max(nextAt,now+8)end -- the monster is the scare
  if now<calmUntil then nextAt=math.max(nextAt,calmUntil)end
  S:SetAttribute('NextScareIn',math.floor(nextAt-now))
  if now<nextAt then return end
  local name=runScare(map,root,cam,tier,tutorial)
  if name then
   streak+=1;record(name)
   local g=rules.gap;nextAt=now+math.max(MIN_GAP,rng:NextNumber(g[1],g[2])-(tutorial and 0 or STREAK_TRIM*math.min(streak,3)))
  else nextAt=now+3 end
 end)

 -- ===== 2. monster dread =====
 local HUNT={Chase=true,Search=true,Stalk=true,Suspicious=true}
 local BREATH_ID='rbxassetid://9113984056' -- Creature Mix Weird Deep Monster Breathing 3 (same as cue MonsterAmbience)
 local presence,presenceOn,presenceEq=nil,nil,nil
 local dread,lastChased,chaseStart,spottedAt=0,-100,nil,-100
 local lastHealth,occAt,occluded=nil,0,false
 local function stopPresence()if presence then presence:Destroy()end;presence,presenceOn,presenceEq=nil,nil,nil end
 local function clearAll()
  stopPresence();dread=0
  if player:GetAttribute('DreadLevel')then player:SetAttribute('DreadLevel',nil)end
  if player:GetAttribute('FlashlightFlicker')then player:SetAttribute('FlashlightFlicker',nil)end
 end
 local acc2=0
 Run.Heartbeat:Connect(function(dt)
  acc2+=dt;if acc2<.1 then return end;local step=acc2;acc2=0
  local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
  local cam=workspace.CurrentCamera;local folder=workspace:FindFirstChild('RoamingCreatures')
  if player:GetAttribute('MissionActive')~=true or not root or not hum or hum.Health<=0 or player:GetAttribute('RoundDead')==true then clearAll();lastHealth=nil;return end
  local now=os.clock()
  if lastHealth and hum.Health<lastHealth-1 then calmUntil=math.max(calmUntil,now+CALM_AFTER_HURT)end;lastHealth=hum.Health
  -- nearest monster
  local best,bestD,bestHunt=nil,math.huge,false
  if folder then for _,m in folder:GetChildren()do
   local r=m:IsA('Model')and m.PrimaryPart
   if r then local d=(r.Position-root.Position).Magnitude;if d<bestD then best,bestD,bestHunt=m,d,HUNT[m:GetAttribute('AIState')or'']==true end end
  end end
  local close=0
  if best then close=bestHunt and math.clamp(1-(bestD-6)/54,0,1)or .6*math.clamp(1-(bestD-6)/24,0,1)end
  local chased=(player:GetAttribute('ChasedUntil')or 0)>workspace:GetServerTimeNow()
  -- spotted: a monster just started chasing YOU
  if chased then
   if now-lastChased>4 then
    spottedAt=now;chaseStart=now;player:SetAttribute('DreadKickAt',now)
    Audio.Play('ScareGasp',nil,{volume=.3})
    if S:GetAttribute('MusicMode')=='chase'then Audio.Play('ScareSpotted',nil,{volume=.3})end -- the music's own hit already played otherwise
    calmUntil=math.max(calmUntil,now+CALM_AFTER_SPOTTED);S:SetAttribute('SpottedCount',(S:GetAttribute('SpottedCount')or 0)+1);record('spotted')
   end
   lastChased=now
  elseif chaseStart and now-lastChased>2.5 then
   -- it lost you: a low boom far off and your own shaky exhale, then a calm spell
   local anyChase=false
   if folder then for _,m in folder:GetChildren()do local r=m:IsA('Model')and m.PrimaryPart;if r and m:GetAttribute('AIState')=='Chase'and(r.Position-root.Position).Magnitude<40 then anyChase=true end end end
   if not anyChase then
    if lastChased-chaseStart>=1.5 then
     Audio.Play('ScareRelief',nil,{volume=.2});task.delay(.5,function()Audio.Play('SprintBreath',nil,{volume=.16,speed=.85,loop=false,duration=2.5})end)
     S:SetAttribute('LostCount',(S:GetAttribute('LostCount')or 0)+1);record('lost')
    end
    chaseStart=nil;calmUntil=math.max(calmUntil,now+CALM_AFTER_CHASE)
   end
  end
  -- vignette / shake driver
  local want=chased and math.max(.75,close)or close*.7
  dread+=(want-dread)*math.min(1,step*(want>dread and 4 or 1.2))
  local shown=math.floor(dread*50+.5)/50
  if shown~=(player:GetAttribute('DreadLevel')or 0)then player:SetAttribute('DreadLevel',shown>0 and shown or nil)end
  -- flashlight brown-out near any monster
  local flick=best and math.clamp((40-bestD)/28,0,1)*(bestHunt and 1 or .6)or 0
  flick=math.floor(flick*20+.5)/20
  if flick~=(player:GetAttribute('FlashlightFlicker')or 0)then player:SetAttribute('FlashlightFlicker',flick>0 and flick or nil)end
  -- presence: the nearest hunting (or very close) monster's slow breathing, louder as it closes, muffled through walls
  local wantPresence=best and bestD<50 and(bestHunt or bestD<25)and best.PrimaryPart or nil
  if wantPresence~=presenceOn then
   stopPresence()
   if wantPresence then
    local s=Instance.new('Sound');s.Name='DreadPresence';s.SoundId=BREATH_ID;s.Looped=true;s.Volume=0;s.PlaybackSpeed=.7
    s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=6;s.RollOffMaxDistance=60
    local g=game:GetService('SoundService'):FindFirstChild('GameplaySFX');if g then s.SoundGroup=g end
    presenceEq=Instance.new('EqualizerSoundEffect');presenceEq.Parent=s
    s.Parent=wantPresence;s:Play();presence,presenceOn=s,wantPresence
   end
  end
  if presence and cam then
   if now-occAt>.25 then occAt=now
    local hit=workspace:Raycast(cam.CFrame.Position,presenceOn.Position-cam.CFrame.Position,rayParams())
    occluded=hit~=nil and(hit.Position-presenceOn.Position).Magnitude>3
   end
   local k=close*close
   presence.Volume+=((.03+.42*k)-presence.Volume)*math.min(1,step*3)
   presence.PlaybackSpeed=.68+.2*close
   presenceEq.HighGain=occluded and -20 or -2;presenceEq.MidGain=occluded and -7 or 0;presenceEq.LowGain=occluded and 3 or 1
  end
 end)
 player.CharacterRemoving:Connect(clearAll)

 -- ===== 3. room detail =====
 local detailMap,nextDetail=nil,0
 local acc3=0
 Run.Heartbeat:Connect(function(dt)
  acc3+=dt;if acc3<.5 then return end;acc3=0
  local map=workspace:FindFirstChild('Mansion');local cam=workspace.CurrentCamera
  if player:GetAttribute('MissionActive')~=true or not map or not map:GetAttribute('RuntimeReady')or not cam then detailMap=nil;return end
  local now=os.clock()
  if map~=detailMap then detailMap=map;nextDetail=now+DETAIL_FIRST end
  if now<nextDetail then return end
  nextDetail=now+rng:NextNumber(DETAIL_GAP.Min,DETAIL_GAP.Max)
  if (player:GetAttribute('ChasedUntil')or 0)>workspace:GetServerTimeNow()or(api.inVan and api.inVan())then return end
  local set=DETAILS[MAP_DETAIL[map:GetAttribute('MapKind')or'Mansion']or'house']
  local total=0;for _,e in set do total+=e[2]end;local roll=rng:NextNumber(0,total);local pick=set[1]
  for _,e in set do roll-=e[2];if roll<=0 then pick=e break end end
  local a=rng:NextNumber(0,math.pi*2);local d=rng:NextNumber(12,32)
  local pos=cam.CFrame.Position+Vector3.new(math.cos(a)*d,rng:NextNumber(-2,6),math.sin(a)*d)
  muffle(Audio.Play(pick[1],pos,{volume=pick[3]*rng:NextNumber(.8,1.15),speed=pick[4]*rng:NextNumber(.88,1.1)}),-8)
  S:SetAttribute('LastDetail',pick[1])
 end)
end
return M
