-- World happenings (WorldB 2026-10-27): map props that make a level react, placed at runtime from
-- Mansion.GeneratedGraph + raycasts (no MapGen change). Required once by InteractServer, which reboots every level:
-- Init runs again each level and drops the previous level's connections.
--   FloodValve      level 2+: one ground-floor room floods ankle-deep (wading x0.7 via WadingUntil, loud splashes);
--                   GRAB the wall valve 6 times to drain it; it refloods once, 90 s later.
--   StormWindow     level 2+: lightning every 25-35 s (map LightningAt: clients flash + outline monsters 1.5 s);
--                   the storm window's shutters bang before each strike (noise 30 there); GRAB to latch = quiet, no flashes.
--   SwingChandelier every level: sprint under it to make it sway; a monster under a hard swing -> it crashes, stun 6 s.
--   HeroRosette     ServerStorage.HeroMomentEvent(rescuer, rescued, reason): a rosette pops at the rescued player and
--                   pins to the rescuer's chest for the level (gift revive, co-op curse rescue).
-- Claims: props are Kind='choice' with ChoiceVerb in Mansion.Interactive (InteractController shows the verb and sends
-- CloseUpChoiceEvent 'claim'; CloseUpChoices ignores them: no ChoiceId). Reactions use the shared player leases
-- FaceBeat/FaceBeatUntil faces (VoiceMouthClient) and ReactPop/ReactPopShake/ReactPopAt words + jolt (CurseEffectsClient).
-- Models: ServerStorage.WorldPropKit.<FloodValve|StormWindow|SwingChandelier|HeroRosette> (rbxkit, pivot bottom centre,
-- front -Z; HeroRosette pivot = centre). Missing model = that happening is skipped.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local HttpService=game:GetService('HttpService')
local M={}

local TICK=.25
local FLOOD={minLevel=2,depth=.9,slow=.7,turns=6,turnGap=.35,reach=9,reflood=90,rise=5,splashEvery=1.2,splashNoise=22,minArea=90} -- minArea 150 -> 90 (owner 2026-10-28): only walled-in rooms flood now, and Mansion/Dungeon big rooms open on arches
local STORM={minLevel=2,first=20,gapMin=25,gapMax=35,bangLead=1.2,bangNoise=30,nearWindow=30}
local CHANDELIER={minLevel=1,radius=7,sprint=18,push=2.2,cap=26,decay=1.2,crashAmp=14,crashRadius=6,stunRadius=10,stun=6,creakAt=8,minCeiling=10.5}
local HERO={pinScale=.32,maxPins=3}

local conns={}
local map,roundState
local level=0
local built=nil -- Round number the props were built for
local happen={} -- per-level state
local rng=Random.new()

local function now()return workspace:GetServerTimeNow()end
local function Audio()return require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))end
local function living(p)
 local c=p and p.Parent and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if h and h.Health>0 and p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true then return c:FindFirstChild('HumanoidRootPart')end
 return nil
end
local function fx(p,mood,seconds)if p and p.Parent then p:SetAttribute('FaceBeat',mood);p:SetAttribute('FaceBeatUntil',now()+seconds)end end
local function pop(p,text,shake)if p and p.Parent then p:SetAttribute('ReactPop',text);p:SetAttribute('ReactPopShake',shake or 0);p:SetAttribute('ReactPopAt',now())end end
local function noise(pos,loud,label,source)local bus=SS:FindFirstChild('MonsterEvidence');if bus then bus:Fire(pos,loud,label,source)end end
local function monsters()
 local out={};local f=workspace:FindFirstChild('RoamingCreatures')
 if f then for _,c in f:GetChildren()do if c:IsA('Model')and c.PrimaryPart then table.insert(out,c)end end end
 return out
end
local function folder()
 local f=map:FindFirstChild('Happenings');if not f then f=Instance.new('Folder');f.Name='Happenings';f.Parent=map end;return f
end
local function template(name)local kit=SS:FindFirstChild('WorldPropKit');return kit and kit:FindFirstChild(name)end
local function prepare(m,collide)
 for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.Anchored=true;x.CanCollide=collide==true;x.CanTouch=false;x.CastShadow=false end end
 for k in m:GetAttributes()do m:SetAttribute(k,nil)end
 return m
end
local function graph()
 local g=map:FindFirstChild('GeneratedGraph');if not g then return nil end
 local ok,v=pcall(function()return HttpService:JSONDecode(g.Value)end);return ok and v or nil
end
local function locked(g)local set={};for _,e in g.edges or {}do if e.locked then set[e.locked]=true end end;return set end
local function exclude()
 local list={}
 for _,x in{map:FindFirstChild('Interactive'),map:FindFirstChild('Furniture'),map:FindFirstChild('Happenings'),map:FindFirstChild('DeadAirFx'),workspace:FindFirstChild('RoamingCreatures'),workspace:FindFirstChild('RecoveryCamp')}do if x then table.insert(list,x)end end
 for _,q in Players:GetPlayers()do if q.Character then table.insert(list,q.Character)end end
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude;p.FilterDescendantsInstances=list;return p
end
local function floorAt(x,y,z,params)
 local hit=workspace:Raycast(Vector3.new(x,y+6,z),Vector3.new(0,-14,0),params);return hit and hit.Position.Y or nil
end
local function roomCentre(r)return (r.x1+r.x2)/2,(r.level or 0)*16,(r.z1+r.z2)/2 end
-- Owner 2026-10-29 'the valve water spawns half way up the wall, you can see below it': the floor was read by one ray at
-- the room centre, which lands on the furniture collider there (a dining table: water 3.2 studs up). The room floor is
-- now the LOWEST ground hit on a 5x5 grid across the room (nothing below the storey's own base counts).
local function roomFloor(r,params)
 local cx,cy,cz=roomCentre(r);local low
 for i=0,4 do for j=0,4 do
  local y=floorAt(r.x1+(r.x2-r.x1)*(.1+.2*i),cy,r.z1+(r.z2-r.z1)*(.1+.2*j),params)
  if y and y>=cy-2 and(not low or y<low)then low=y end
 end end
 return low or floorAt(cx,cy,cz,params)or cy
end
-- A tall wall face in `dir` from the room centre: position, normal (pointing into the room).
-- Owner 2026-10-28: valves spawned right beside doors and the storm window behind closets (the wall rays skip furniture,
-- so a wall hidden by a wardrobe still read as free). A wall-mounted happening now needs open floor in front of it (no
-- furniture, hiding closet or door there) and no doorway close by.
local function clearSpot(pos,normal,fy,width,height)
 if not map then return true end
 -- Doorways from the plan (every map kind: the kit pieces are HotelPortal, SchoolPortal, ... not 'Door'), kept at
 -- least 7 studs away like the dressing props (MapGen RevampDressing DOOR_CLEAR); a wide mount keeps its half-width more.
 local g=graph()
 if g then
  local doors={};for _,e in g.edges or{}do if e.kind~='stairs'and e.x and e.z then table.insert(doors,Vector3.new(e.x,e.y or 0,e.z))end end
  if g.entrance and g.entrance.x then table.insert(doors,Vector3.new(g.entrance.x,0,g.entrance.z))end
  for _,d in doors do if math.abs(d.Y-fy)<8 and Vector2.new(d.X-pos.X,d.Z-pos.Z).Magnitude<math.max(7,width/2+4.5)then return false end end
 end
 local inc={};for _,n in{'Furniture','Closets','KeyDoors'}do local f=map:FindFirstChild(n);if f then table.insert(inc,f)end end
 local ip=map:FindFirstChild('Interactive');if ip then for _,x in ip:GetChildren()do if x.Name:sub(1,6)=='Mover_'then table.insert(inc,x)end end end
 local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Include;op.FilterDescendantsInstances=inc
 local centre=Vector3.new(pos.X,fy+height/2+.3,pos.Z)+normal*1.6
 if #workspace:GetPartBoundsInBox(CFrame.lookAt(centre,centre+normal),Vector3.new(width+1,height,3),op)>0 then return false end
 local dinc={};for _,n in{'Collision','Architecture','KeyDoors'}do local f=map:FindFirstChild(n);if f then table.insert(dinc,f)end end
 local dp=OverlapParams.new();dp.FilterType=Enum.RaycastFilterType.Include;dp.FilterDescendantsInstances=dinc
 for _,part in workspace:GetPartBoundsInRadius(Vector3.new(pos.X,fy+3,pos.Z),width/2+3,dp)do
  if part.Name:find('Door')or(part.Parent and part.Parent.Name:find('Door'))then return false end
 end
 return true
end
local function wallFrom(r,dir,params,minWidth,slide,check)
 local cx,cy,cz=roomCentre(r);local fy=roomFloor(r,params)
 local reach=(math.abs(dir.X)>0 and(r.x2-r.x1)or(r.z2-r.z1))/2+3
 local along=Vector3.new(-dir.Z,0,dir.X);local span=(math.abs(dir.X)>0 and(r.z2-r.z1)or(r.x2-r.x1))
 -- slide: also try points a quarter / a third of the wall to each side (doors and windows often sit in the middle)
 for _,k in slide and{0,-.25,.25,-.34,.34}or{0}do
  local origin=Vector3.new(cx,fy+3,cz)+along*span*k
  local hit=workspace:Raycast(origin,dir*reach,params)
  -- Map walls are stacks of short 'Wall' collision slabs (4.6 tall): a wall = named Wall (or a tall part) and still there 3.5 studs higher.
  local tall=hit and hit.Instance:IsA('BasePart')and(string.find(hit.Instance.Name,'Wall')~=nil or hit.Instance.Size.Y>=6)
  if tall and hit then local up=workspace:Raycast(origin+Vector3.new(0,3.5,0),dir*reach,params);tall=up~=nil and math.abs(up.Distance-hit.Distance)<=.6 end
  if hit and tall and math.abs(hit.Normal.Y)<=.2 then
   local ok=true
   if minWidth then -- both sides of the mount spot must also be wall
    local side=Vector3.new(-hit.Normal.Z,0,hit.Normal.X)
    for _,sd in{-1,1}do local o=origin+side*sd*minWidth/2;local h2=workspace:Raycast(o,dir*reach,params);if not h2 or math.abs(h2.Distance-hit.Distance)>.6 then ok=false end end
   end
   if ok and(not check or check(hit.Position,hit.Normal,fy))then return hit.Position,hit.Normal,fy end
  end
 end
 return nil
end
local function mountOnWall(m,pos,normal,floorY,lift)
 local depth=m:GetExtentsSize().Z
 local base=Vector3.new(pos.X,floorY+(lift or 0),pos.Z)+normal*(depth/2+.03)
 m:PivotTo(CFrame.lookAt(base,base+normal)) -- front (-Z) faces into the room, back flush on the wall
end
local function choice(m,verb,kind)
 m:SetAttribute('Kind','choice');m:SetAttribute('ChoiceVerb',verb);m:SetAttribute('Happening',kind)
 for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.CanQuery=true end end -- the grab aim must hit it
 m.Parent=map:FindFirstChild('Interactive')
end
local function reach(p,m,dist)local r=living(p);return r~=nil and m.Parent~=nil and(m:GetPivot().Position-r.Position).Magnitude<=dist end

-- FloodValve ---------------------------------------------------------------------------------------------------
local function waterLevel(f,frac)
 local w=f.water;if not w then return end
 local h=math.max(.02,FLOOD.depth*frac)
 w.Size=Vector3.new(w.Size.X,h,w.Size.Z);w.CFrame=CFrame.new(w.Position.X,f.floorY+h/2,w.Position.Z)
 w.Transparency=frac<=0 and 1 or .35
end
local function floodTween(f,from,to,seconds)
 local v=Instance.new('NumberValue');v.Value=from
 v.Changed:Connect(function(x)waterLevel(f,x)end)
 local t=TweenService:Create(v,TweenInfo.new(seconds,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Value=to});t:Play()
 f.rise=t -- turnValve stops it: a turn during the reflood must lower the water, not be undone by the rise
 t.Completed:Once(function()v:Destroy()end)
end
-- Owner 2026-10-28: the flood water stopped half way across open rooms (the plan rectangle ends at a wide archway) and
-- poked into the walls. Only a room walled in on all four sides floods (one door gap per side is fine), and the water is
-- cut to its real inner walls. Rays sample three points per side; the farthest hit is the wall (furniture colliders in
-- Collision stop short of it).
local function walledIn(r,params)
 local cx,cy,cz=roomCentre(r);local fy=roomFloor(r,params)
 local ext={}
 for _,d in{Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1)}do
  local half=math.abs(d.X)>0 and(r.x2-r.x1)/2 or(r.z2-r.z1)/2
  local span=math.abs(d.X)>0 and(r.z2-r.z1)or(r.x2-r.x1)
  -- a ray every 1.5 studs along the side: the open stretch (a doorway) may be at most 7 studs; a wide arch fails
  local along=Vector3.new(-d.Z,0,d.X);local far,run,widest=nil,0,0;local n=math.max(3,math.floor(span*.9/1.5))
  for i=0,n do
   local hit=workspace:Raycast(Vector3.new(cx,fy+1.5,cz)+along*span*(-.45+.9*i/n),d*(half+2),params)
   if hit and math.abs(hit.Normal.Y)<.3 then far=math.max(far or 0,hit.Distance);run=0 else run+=1;widest=math.max(widest,run)end
  end
  if not far or widest*span*.9/n>10 then return nil end -- the widest single gap counts (doors measure 6-9.3, the archways that cut the water 16+); two doors on one wall are fine
  ext[#ext+1]=far
 end
 return{px=ext[1],nx=ext[2],pz=ext[3],nz=ext[4],cx=cx,cz=cz}
end
local function buildFlood(g)
 local t=template('FloodValve');if not t then return end
 local params=exclude();local lock=locked(g);local rooms={}
 for _,r in g.rooms do
  if r.x1 and(r.level or 0)==0 and r.name~=g.start and r.type~='Stair'and r.type~='Hall'and r.type~='Foyer'and not lock[r.name]then
   local area=(r.x2-r.x1)*(r.z2-r.z1)
   if area>=FLOOD.minArea then table.insert(rooms,{r,area})end
  end
 end
 table.sort(rooms,function(a,b)return a[2]>b[2]end) -- the biggest room first; the next one when it has no clear wall
 local best,pos,normal,fy
 local function valveClear(p2,n2,f2)return clearSpot(p2,n2,f2,2.4,3.5)end
 local box
 for _,c in rooms do
  box=walledIn(c[1],params)
  if box then
   for _,d in{Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1)}do pos,normal,fy=wallFrom(c[1],d,params,2.4,true,valveClear);if pos then break end end
   if pos then best=c[1];break end
  end
 end
 if not best then return end
 local valve=prepare(t:Clone(),false);valve.Name='FloodValve'
 mountOnWall(valve,pos,normal,fy,0)
 choice(valve,'TURN THE VALVE','FloodValve');valve:SetAttribute('Turns',0)
 local wheel=valve:FindFirstChild('Wheel',true)
 local water=Instance.new('Part');water.Name='FloodWater';water.Anchored=true;water.CanCollide=false;water.CanQuery=false;water.CanTouch=false;water.CastShadow=false
 water.Material=Enum.Material.SmoothPlastic;water.Color=Color3.fromRGB(70,150,175);water.Reflectance=.15;water.Transparency=.35
 water.Size=Vector3.new(box.px+box.nx-.1,FLOOD.depth,box.pz+box.nz-.1);water.Position=Vector3.new(box.cx+(box.px-box.nx)/2,fy+FLOOD.depth/2,box.cz+(box.pz-box.nz)/2);water.Parent=folder()
 map:SetAttribute('FloodRoom',best.name)
 happen.flood={room=best,floorY=fy,water=water,valve=valve,wheel=wheel,wheelBase=wheel and wheel.CFrame,turns=0,phase='flooded',turnAt={},turners={},wet={},lastPos={},splashAt={},refloodAt=nil}
end
local function turnValve(p)
 local f=happen.flood;if not f or f.phase~='flooded'or not f.valve.Parent then return false end
 if os.clock()<(f.turnAt[p]or 0)then return false end;f.turnAt[p]=os.clock()+FLOOD.turnGap
 f.turns+=1;f.turners[p]=true;f.valve:SetAttribute('Turns',f.turns)
 -- Owner 2026-10-28: turning while the room was refilling left it full for good (the rise tween overwrote the level,
 -- then the final drain counted as done). A turn now stops the rise first.
 if f.rise then f.rise:Cancel();f.rise=nil end
 if f.wheel and f.wheelBase then -- the wheel spins about its own axis (it faces the room: local Z)
  TweenService:Create(f.wheel,TweenInfo.new(.25,Enum.EasingStyle.Back),{CFrame=f.wheelBase*CFrame.Angles(0,0,math.rad(-60*f.turns))}):Play()
 end
 Audio().Play('LanternLift',f.valve)
 waterLevel(f,1-f.turns/FLOOD.turns)
 if f.turns>=FLOOD.turns then
  f.phase=f.refloodAt==false and 'done'or 'drained';Audio().Play('DrainGurgle',f.valve)
  for q in f.turners do if q.Parent then fx(q,'grin',3);pop(q,'DRAINED!')end end
  table.clear(f.turners)
  if f.phase=='drained'then f.refloodAt=os.clock()+FLOOD.reflood end
  f.valve:SetAttribute('ChoiceVerb','VALVE (DRAINED)')
 end
 return true
end
local function floodTick()
 local f=happen.flood;if not f then return end
 if f.phase=='drained'and f.refloodAt and os.clock()>=f.refloodAt then
  f.phase='flooded';f.turns=0;f.refloodAt=false;f.valve:SetAttribute('Turns',0);f.valve:SetAttribute('ChoiceVerb','TURN THE VALVE') -- the second drain is final
  floodTween(f,0,1,FLOOD.rise);Audio().Play('ScareThud',f.valve)
  for _,q in Players:GetPlayers()do local r=living(q);if r and math.abs(r.Position.X-f.water.Position.X)<f.water.Size.X/2+10 and math.abs(r.Position.Z-f.water.Position.Z)<f.water.Size.Z/2+10 then pop(q,"It's flooding again!");fx(q,'gasp',1)end end
 end
 if f.phase~='flooded'then return end
 local w=f.water;local t=now()
 for _,q in Players:GetPlayers()do
  local r=living(q)
  if r and math.abs(r.Position.X-w.Position.X)<w.Size.X/2 and math.abs(r.Position.Z-w.Position.Z)<w.Size.Z/2 and r.Position.Y-f.floorY<5 then
   q:SetAttribute('WadingUntil',t+.5)
   if not f.wet[q]then f.wet[q]=true;pop(q,'Brrr! Wet socks!');fx(q,'gasp',.8)end
   local last=f.lastPos[q];f.lastPos[q]=r.Position
   if last and(r.Position-last).Magnitude>1 and os.clock()>=(f.splashAt[q]or 0)then
    f.splashAt[q]=os.clock()+FLOOD.splashEvery;Audio().Play('Wash',r);noise(r.Position,FLOOD.splashNoise,'splash',q.Character)
   end
  end
 end
end

-- StormWindow --------------------------------------------------------------------------------------------------
local function buildStorm(g)
 happen.storm={nextAt=os.clock()+STORM.first,banged=false,latched=false}
 local t=template('StormWindow');if not t then return end
 local params=exclude();local lock=locked(g)
 local minX,maxX,minZ,maxZ=math.huge,-math.huge,math.huge,-math.huge
 for _,r in g.rooms do if r.x1 and(r.level or 0)==0 then minX=math.min(minX,r.x1);maxX=math.max(maxX,r.x2);minZ=math.min(minZ,r.z1);maxZ=math.max(maxZ,r.z2)end end
 local tries={}
 for _,r in g.rooms do
  if r.x1 and(r.level or 0)==0 and r.name~=g.start and r.type~='Stair'and not lock[r.name]then
   if r.x1<=minX+.5 then table.insert(tries,{r,Vector3.new(-1,0,0)})end
   if r.x2>=maxX-.5 then table.insert(tries,{r,Vector3.new(1,0,0)})end
   if r.z1<=minZ+.5 then table.insert(tries,{r,Vector3.new(0,0,-1)})end
   if r.z2>=maxZ-.5 then table.insert(tries,{r,Vector3.new(0,0,1)})end
  end
 end
 for _,try in tries do
  local pos,normal,fy=wallFrom(try[1],try[2],params,9.2,true,function(p2,n2,f2)return clearSpot(p2,n2,f2,9.2,5.5)end)
  if pos then
   local w=prepare(t:Clone(),false);w.Name='StormWindow'
   mountOnWall(w,pos,normal,fy,.8);choice(w,'LATCH THE SHUTTERS','StormWindow')
   local base={};for _,n in{'ShutterL','ShutterR'}do local s=w:FindFirstChild(n,true);if s then base[s]=s.CFrame end end
   happen.storm.window=w;happen.storm.shutters=base;return
  end
 end
end
local function bang(s)
 local w=s.window;if not w or not w.Parent or s.latched then return end
 local pivot=w:GetPivot()
 for part,cf in s.shutters do
  local rel=pivot:ToObjectSpace(cf);local side=rel.X>0 and 1 or -1
  local hinge=pivot*CFrame.new(rel.X-side*part.Size.X/2,rel.Y,rel.Z) -- inner long edge, next to the frame
  local open=hinge*CFrame.Angles(0,math.rad(side*38),0)*hinge:ToObjectSpace(cf)
  local tw=TweenService:Create(part,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,1,true,.05),{CFrame=open});tw:Play()
 end
 Audio().Play('ScarePound',w);noise(pivot.Position,STORM.bangNoise,'storm shutters bang',w)
end
local function strike()
 local s=happen.storm;if not s then return false end
 if s.latched then Audio().Play('StingThunder',s.window);return false end -- latched: only a far rumble, no flash
 map:SetAttribute('LightningAt',now());Audio().Play('StingThunder',nil)
 local w=s.window
 if w and w.Parent then
  local at=w:GetPivot().Position
  for _,q in Players:GetPlayers()do local r=living(q);if r and(r.Position-at).Magnitude<STORM.nearWindow then fx(q,'gasp',1);pop(q,'BOOM!',.3)end end
 end
 return true
end
local function latch(p)
 local s=happen.storm;if not s or s.latched or not s.window then return false end
 s.latched=true;map:SetAttribute('StormLatched',true);s.window:SetAttribute('ChoiceVerb','SHUTTERS LATCHED')
 for part,cf in s.shutters do part.CFrame=cf end
 Audio().Play('Unlock',s.window)
 if p then pop(p,'Shutters latched. Quiet now...');fx(p,'grin',2)end
 return true
end
local function stormTick(phaseOk)
 local s=happen.storm;if not s or not phaseOk then return end
 local t=os.clock()
 if not s.banged and t>=s.nextAt-STORM.bangLead then s.banged=true;bang(s)end
 if t>=s.nextAt then strike();s.banged=false;s.nextAt=t+rng:NextNumber(STORM.gapMin,STORM.gapMax)end
end

-- SwingChandelier ----------------------------------------------------------------------------------------------
local function buildChandelier(g)
 local t=template('SwingChandelier');if not t then return end
 local params=exclude();local best,bestArea
 for _,r in g.rooms do
  if r.x1 and r.name~=g.start and r.type~='Stair'then local area=(r.x2-r.x1)*(r.z2-r.z1);if not bestArea or area>bestArea then best,bestArea=r,area end end
 end
 if not best then return end
 local cx,cy,cz=roomCentre(best);local fy=roomFloor(best,params)
 local up=workspace:Raycast(Vector3.new(cx,fy+3,cz),Vector3.new(0,20,0),params)
 local ceil=up and up.Position.Y or fy+14
 if ceil-fy<CHANDELIER.minCeiling then return end
 local m=prepare(t:Clone(),false);m.Name='SwingChandelier'
 local h=m:GetExtentsSize().Y
 local rest=CFrame.new(cx,ceil-h,cz)
 m:PivotTo(rest);m:SetAttribute('Happening','SwingChandelier');m:SetAttribute('RestCF',rest);m:SetAttribute('HangHeight',h);m:SetAttribute('SwayAmp',0)
 for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.CanQuery=false end end
 local light=Instance.new('PointLight');light.Name='CandleGlow';light.Color=Color3.fromRGB(255,210,140);light.Brightness=.35;light.Range=10;light.Shadows=false;light.Parent=m.PrimaryPart
 m.Parent=folder()
 happen.chandelier={model=m,rest=rest,floorY=fy,amp=0,creakAt=0,crashed=false}
end
local function crash()
 local c=happen.chandelier;if not c or c.crashed or not c.model.Parent then return false end
 c.crashed=true;local m=c.model;m:SetAttribute('Crashed',true);m:SetAttribute('SwayAmp',0)
 local fall=CFrame.new(c.rest.X,c.floorY+.05,c.rest.Z)*CFrame.Angles(0,math.rad(rng:NextNumber(-25,25)),math.rad(8))
 local v=Instance.new('CFrameValue');v.Value=m:GetPivot()
 v.Changed:Connect(function(cf)if m.Parent then m:PivotTo(cf)end end)
 local tw=TweenService:Create(v,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Value=fall});tw:Play()
 tw.Completed:Once(function()
  v:Destroy();if not m.Parent then return end
  Audio().Play('ScareThud',m);Audio().Play('BulbCrack',m);noise(fall.Position,45,'chandelier crash',m)
  for _,x in m:GetDescendants()do if x:IsA('BasePart')and x.Material==Enum.Material.Neon then x.Material=Enum.Material.SmoothPlastic;x.Color=Color3.fromRGB(70,64,58)end;if x:IsA('PointLight')then x.Enabled=false end end
  local a=Instance.new('Attachment');a.Name='CrashDust';a.Parent=m.PrimaryPart
  local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/smoke_main.dds';e.Color=ColorSequence.new(Color3.fromRGB(150,146,140))
  e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.5),NumberSequenceKeypoint.new(1,5)});e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.4),NumberSequenceKeypoint.new(1,1)})
  e.Lifetime=NumberRange.new(1,1.8);e.Speed=NumberRange.new(4,9);e.SpreadAngle=Vector2.new(180,40);e.Rate=0;e.Parent=a;e:Emit(36)
  local pos=fall.Position;local o=os.clock()
  for _,mon in monsters()do local d=mon:GetPivot().Position-pos;if Vector3.new(d.X,0,d.Z).Magnitude<CHANDELIER.stunRadius then mon:SetAttribute('StunnedUntil',o+CHANDELIER.stun)end end
  for _,q in Players:GetPlayers()do
   local r=living(q)
   if r then local d=(r.Position-pos).Magnitude
    if d<45 then fx(q,'gasp',1.2)end
    if d<70 then pop(q,'CRASH! The monster is dazed!',d<45 and math.clamp(1-d/60,.3,.9)or 0);task.delay(1,function()fx(q,'grin',2.5)end)end
   end
  end
 end)
 return true
end
local function chandelierTick(dt)
 local c=happen.chandelier;if not c or c.crashed or not c.model.Parent then return end
 local pos=c.rest.Position
 for _,q in Players:GetPlayers()do
  local r=living(q)
  if r then local d=r.Position-pos;local v=r.AssemblyLinearVelocity
   if Vector3.new(d.X,0,d.Z).Magnitude<CHANDELIER.radius and Vector3.new(v.X,0,v.Z).Magnitude>CHANDELIER.sprint then c.amp=math.min(CHANDELIER.cap,c.amp+CHANDELIER.push)end
  end
 end
 c.amp=math.max(0,c.amp-CHANDELIER.decay*dt)
 if math.abs((c.model:GetAttribute('SwayAmp')or 0)-c.amp)>.2 then c.model:SetAttribute('SwayAmp',math.floor(c.amp*10)/10)end
 if c.amp>=CHANDELIER.creakAt and os.clock()>=c.creakAt then
  c.creakAt=os.clock()+math.max(1,2.4-c.amp/20);Audio().Play('LanternLift',c.model);noise(pos,c.amp>16 and 26 or 18,'chandelier creak',c.model)
 end
 if c.amp>=CHANDELIER.crashAmp then
  for _,mon in monsters()do local d=mon:GetPivot().Position-pos;if Vector3.new(d.X,0,d.Z).Magnitude<CHANDELIER.crashRadius then crash();return end end
 end
end

-- HeroRosette --------------------------------------------------------------------------------------------------
local pinned={} -- rescuer -> count this level
local function hero(rescuer,rescued,_reason)
 if typeof(rescuer)~='Instance'or not rescuer:IsA('Player')then return end
 local t=template('HeroRosette');local from=living(rescued)or living(rescuer);if not t or not from then return end
 local count=(pinned[rescuer]or 0)+1;pinned[rescuer]=count;rescuer:SetAttribute('HeroRosettes',count)
 local m=prepare(t:Clone(),false);m.Name='HeroRosettePop';for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.CanQuery=false end end
 local start=CFrame.new(from.Position-Vector3.new(0,3,0));m:PivotTo(start);m.Parent=folder()
 local a=Instance.new('Attachment');a.Parent=m.PrimaryPart
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds'
 e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,214,90)),ColorSequenceKeypoint.new(.5,Color3.fromRGB(80,220,200)),ColorSequenceKeypoint.new(1,Color3.fromRGB(170,120,255))})
 e.Size=NumberSequence.new(.35);e.Lifetime=NumberRange.new(.8,1.4);e.Speed=NumberRange.new(8,14);e.SpreadAngle=Vector2.new(70,70);e.Rate=0;e.Parent=a
 Audio().Play('PartyHorn',m);e:Emit(40)
 fx(rescuer,'grin',3);pop(rescuer,count>1 and('HERO x'..count..'!')or'HERO!')
 if rescued and rescued~=rescuer then
  fx(rescued,'grin',3)
  local ev=RS:FindFirstChild('CursedEvent');local head=rescued.Character and rescued.Character:FindFirstChild('Head')
  if ev and head then ev:FireAllClients('speech',head.Position+Vector3.new(0,2.2,0),'THANK YOU!')end
 end
 local v=Instance.new('NumberValue');local top=from.Position+Vector3.new(0,2.5,0)
 v.Changed:Connect(function(k)if m.Parent then m:PivotTo(CFrame.new(start.Position:Lerp(top,k))*CFrame.Angles(0,k*math.pi*4,0))end end)
 local rise=TweenService:Create(v,TweenInfo.new(.8,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Value=1});rise:Play()
 task.delay(1.1,function()
  v:Destroy()
  local c=rescuer.Character;local torso=c and(c:FindFirstChild('UpperTorso')or c:FindFirstChild('HumanoidRootPart'))
  if not m.Parent or not torso then if m.Parent then m:Destroy()end;return end
  local slot=math.min(count,HERO.maxPins)
  local offset=CFrame.new((slot-2)*.55,.25,-(torso.Size.Z/2+.08))
  local w=Instance.new('NumberValue');local from2=m:GetPivot()
  w.Changed:Connect(function(k)if m.Parent and torso.Parent then m:PivotTo(from2:Lerp(torso.CFrame*offset,k))end end)
  local fly=TweenService:Create(w,TweenInfo.new(.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Value=1});fly:Play()
  fly.Completed:Wait();w:Destroy()
  if not m.Parent or not torso.Parent then if m.Parent then m:Destroy()end;return end
  if count>HERO.maxPins then m:Destroy();Audio().Play('BalloonPop',torso);return end -- the chest is full: the count still goes up
  m:ScaleTo(HERO.pinScale);m:PivotTo(torso.CFrame*offset);m.Name='HeroRosettePin'
  for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.Anchored=false;x.Massless=true;x.CanCollide=false;x.CanTouch=false end end
  local weld=Instance.new('WeldConstraint');weld.Part0=torso;weld.Part1=m.PrimaryPart;weld.Parent=m.PrimaryPart
  m.Parent=c;Audio().Play('BalloonPop',torso)
 end)
end

-- level lifecycle ----------------------------------------------------------------------------------------------
-- StoryNote (owner 2026-10-29) ---------------------------------------------------------------------------------
-- Every level one paper note (StoryLore.NoteForLevel) lies on a floor or table in a random ground-floor room, glowing
-- faintly. READ THE NOTE saves it (ProgressService.NoteStory -> StoryNotes) and StoryEvent 'note' opens it on that
-- player's screen (StoryClient), which also hides notes the player already has. Any player can read it.
local Story=require(RS:WaitForChild('StoryLore'))
local NOTE_REACH=10
local function buildStoryNote(g)
 local note=Story.NoteForLevel(level)
 local params=exclude();local lock=locked(g);local rooms={}
 for _,r in g.rooms do if r.x1 and(r.level or 0)==0 and r.name~=g.start and r.type~='Stair'and not lock[r.name]then table.insert(rooms,r)end end
 if #rooms==0 then return end
 for _=1,30 do
  local r=rooms[rng:NextInteger(1,#rooms)];local _,cy=roomCentre(r)
  local x,z=r.x1+(r.x2-r.x1)*rng:NextNumber(.2,.8),r.z1+(r.z2-r.z1)*rng:NextNumber(.2,.8)
  local hit=workspace:Raycast(Vector3.new(x,cy+7,z),Vector3.new(0,-12,0),params)
  if hit and hit.Normal.Y>.9 and hit.Position.Y<=cy+4.5 then
   local m=Instance.new('Model');m.Name='StoryNote'
   local paper=Instance.new('Part');paper.Name='Paper';paper.Size=Vector3.new(1.4,.05,1.8);paper.Color=Color3.fromRGB(232,226,204);paper.Material=Enum.Material.SmoothPlastic
   paper.CFrame=CFrame.new(hit.Position+Vector3.new(0,.03,0))*CFrame.Angles(0,rng:NextNumber(0,math.pi*2),0);paper.Parent=m
   local ink=Instance.new('SurfaceGui');ink.Name='Ink';ink.Face=Enum.NormalId.Top;ink.CanvasSize=Vector2.new(140,180);ink.LightInfluence=1;ink.Parent=paper
   local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.new(1,-16,1,-16);t.Position=UDim2.fromOffset(8,8);t.TextWrapped=true;t.TextScaled=true
   t.TextColor3=Color3.fromRGB(40,44,52);t.Text=note.title..'\n\n'..string.sub(note.text,1,60)..'...';t.Parent=ink
   local hitbox=Instance.new('Part');hitbox.Name='Hit';hitbox.Size=Vector3.new(2.8,1.6,3);hitbox.Transparency=1;hitbox.CFrame=paper.CFrame*CFrame.new(0,.75,0);hitbox.Parent=m
   local glow=Instance.new('PointLight');glow.Name='NoteGlow';glow.Color=Color3.fromRGB(190,255,214);glow.Brightness=.9;glow.Range=8;glow.Parent=paper
   m.PrimaryPart=paper;prepare(m,false)
   choice(m,'READ THE NOTE','StoryNote');m:SetAttribute('NoteId',note.id);m:SetAttribute('NoteTitle',note.title)
   happen.note={model=m,id=note.id}
   return
  end
 end
end
local function readNote(p)
 local n=happen.note;if not n then return end
 local ok,Progress=pcall(require,game.ServerScriptService:WaitForChild('ProgressService'))
 local ev=RS:FindFirstChild('StoryEvent')
 -- Owner 2026-10-29: a note counts for everyone in the run with the reader (alive, dead or spectating). The reader
 -- gets the page; the rest get a short 'NAME found a note' line (StoryClient 'noteShared'), never a page mid-chase.
 for _,q in Players:GetPlayers()do
  if q==p or(q:GetAttribute('MissionActive')==true and not q:GetAttribute('ReturnedToLobby'))then
   if ok and Progress.NoteStory then Progress.NoteStory(q,n.id)end
   if ev then if q==p then ev:FireClient(q,'note',n.id)else ev:FireClient(q,'noteShared',n.id,p.DisplayName)end end
  end
 end
end
local function clear()
 for _,s in{'flood','storm','chandelier','note'}do happen[s]=nil end
 local f=map and map:FindFirstChild('Happenings');if f then f:ClearAllChildren()end
 local items=map and map:FindFirstChild('Interactive')
 if items then for _,x in items:GetChildren()do if x:GetAttribute('Happening')then x:Destroy()end end end
 if map then for _,k in{'FloodRoom','LightningAt','StormLatched'}do map:SetAttribute(k,nil)end end
 for _,q in Players:GetPlayers()do
  for _,k in{'WadingUntil','HeroRosettes'}do if q:GetAttribute(k)~=nil then q:SetAttribute(k,nil)end end
  local c=q.Character;if c then for _,x in c:GetChildren()do if x.Name=='HeroRosettePin'then x:Destroy()end end end
 end
 table.clear(pinned);built=nil
end
local function build(lvl)
 local g=graph();if not g then return end
 level=lvl;built=lvl
 for _,step in{{FLOOD.minLevel,buildFlood},{STORM.minLevel,buildStorm},{CHANDELIER.minLevel,buildChandelier},{1,buildStoryNote}}do
  if lvl>=step[1]then local ok,err=pcall(step[2],g);if not ok then warn('[WorldHappenings] '..tostring(err))end end
 end
end
local acc=0
local function tick(dt)
 acc+=dt;if acc<TICK then return end;local step=acc;acc=0
 if not roundState or not map then return end
 local phase=roundState:GetAttribute('Phase');local live=phase=='Searching'or phase=='Returning'or phase=='Selling'
 if phase=='Searching'and built~=(roundState:GetAttribute('Round')or 1)then clear();build(roundState:GetAttribute('Round')or 1)end
 if not built then return end
 for _,f in{function()floodTick()end,function()stormTick(phase=='Searching'or phase=='Returning')end,function()if live then chandelierTick(step)end end}do
  local ok,err=pcall(f);if not ok then warn('[WorldHappenings] '..tostring(err))end
 end
end

function M.Init()
 for _,c in conns do c:Disconnect()end;table.clear(conns)
 map=workspace:WaitForChild('Mansion');happen={};built=nil;table.clear(pinned)
 local heroEvent=SS:FindFirstChild('HeroMomentEvent')or Instance.new('BindableEvent');heroEvent.Name='HeroMomentEvent';heroEvent.Parent=SS
 table.insert(conns,heroEvent.Event:Connect(function(rescuer,rescued,reason)local ok,err=pcall(hero,rescuer,rescued,reason);if not ok then warn('[WorldHappenings] hero: '..tostring(err))end end))
 local storyEvent=RS:FindFirstChild('StoryEvent')or Instance.new('RemoteEvent');storyEvent.Name='StoryEvent';storyEvent.Parent=RS -- StoryClient listens
 table.insert(conns,Run.Heartbeat:Connect(tick))
 task.spawn(function()
  roundState=RS:WaitForChild('RecoveryRound',math.huge)
  table.insert(conns,roundState:GetAttributeChangedSignal('Phase'):Connect(function()
   local phase=roundState:GetAttribute('Phase');if phase=='Won'or phase=='Failed'or phase=='Deploying'then clear()end
  end))
 end)
 task.spawn(function()
  local ev=RS:WaitForChild('CloseUpChoiceEvent',60);if not ev then warn('[WorldHappenings] CloseUpChoiceEvent missing');return end
  table.insert(conns,ev.OnServerEvent:Connect(function(p,action,prop)
   if action~='claim'or typeof(prop)~='Instance'or not prop:IsA('Model')or not prop:GetAttribute('Happening')then return end
   local kind=prop:GetAttribute('Happening')
   if kind=='FloodValve'and happen.flood and prop==happen.flood.valve and reach(p,prop,FLOOD.reach)then turnValve(p)
   elseif kind=='StormWindow'and happen.storm and prop==happen.storm.window and reach(p,prop,11)then latch(p)
   elseif kind=='StoryNote'and happen.note and prop==happen.note.model and reach(p,prop,NOTE_REACH)then readNote(p)end
  end))
 end)
 -- Studio tests (rbxdev scenarios): drive every happening without a client.
 local api=SS:FindFirstChild('WorldHappeningsApi')or Instance.new('BindableFunction');api.Name='WorldHappeningsApi';api.Parent=SS
 api.OnInvoke=function(action,a,b)
  if action=='state'then
   local f,s,c=happen.flood,happen.storm,happen.chandelier
   return {built=built,level=level,flood=f and{phase=f.phase,turns=f.turns,room=f.room.name,water=f.water.Parent~=nil and f.water.Size.Y or 0,valve=f.valve.Parent~=nil}or nil,
    storm=s and{window=s.window~=nil,latched=s.latched,nextIn=s.nextAt-os.clock()}or nil,chandelier=c and{amp=c.amp,crashed=c.crashed}or nil,note=happen.note and{id=happen.note.id,pos=happen.note.model.PrimaryPart and tostring(happen.note.model.PrimaryPart.Position)}or nil}
  end
  if not Run:IsStudio()then return nil end
  if action=='readNote'then if happen.note and typeof(a)=='Instance'then readNote(a);return happen.note.id end;return nil end
  if action=='force'then clear();build(tonumber(a)or 2);local ok=built~=nil;if ok and roundState then built=roundState:GetAttribute('Round')or 1 end;return ok -- keep the forced level: the tick only rebuilds for a new round
  elseif action=='turn'then return turnValve(a)
  elseif action=='strike'then return strike()
  elseif action=='latch'then return latch(a)
  elseif action=='sway'then local c=happen.chandelier;if c then c.amp=tonumber(a)or 20;return true end;return false
  elseif action=='crash'then return crash()
  elseif action=='hero'then hero(a,b,'test');return true end
  return nil
 end
end

return M
