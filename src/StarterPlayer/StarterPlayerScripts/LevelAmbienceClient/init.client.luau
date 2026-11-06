-- Level ambience: looping beds per map kind (faded in/out) plus random one-shot stingers placed around the listener.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local player=Players.LocalPlayer
-- beds: {cue, target volume, playback speed}; stingers: {cue, weight, positional}
local profiles={
 Hotel={beds={{'LevelDrone',.065,.38},{'LevelAir',.025,.22},{'AmbCreaks',.03,.9}},
  stingers={{'StingCreak',4,true},{'StingKnock',2,true},{'StingBumps',2,true},{'StingCave1',1,true}}},
 Hospital={beds={{'LevelAir',.026,.23},{'LevelDrone',.05,.32}},
  stingers={{'StingBumps',3,true},{'StingKnock',2,true},{'StingCreak',2,true},{'StingCave1',1,true},{'StingHull',1,true}}},
 -- Empty fluorescent halls, moving air, distant knocks and footsteps above.
 School={beds={{'LevelAir',.028,.22},{'LevelDrone',.055,.34},{'AmbCreaks',.025,.95}},
  stingers={{'StingKnock',3,true},{'StingBumps',3,true},{'StingCreak',3,true},{'StingCave2',1,true}}},
 Mansion={beds={{'LevelDrone',.085,.38},{'LevelAir',.028,.22},{'AmbWind',.05,1},{'AmbCreaks',.035,.9},{'AmbRain',.03,1}},
  stingers={{'StingCave1',2,true},{'StingCave2',2,true},{'StingCave3',2,true},{'StingCreak',5,true},{'StingBumps',2,true},{'StingKnock',1.5,true},{'StingThunder',2,false},{'StingChoir',.5,false}}},
 Dungeon={beds={{'LevelDrone',.10,.30},{'LevelAir',.045,.22},{'AmbWind',.035,.8}},
  stingers={{'StingCave1',2,true},{'StingCave2',2,true},{'StingCave3',2,true},{'StingHull',3,true},{'StingCreak',2,true},{'StingBumps',2,true},{'StingChoir',.7,false}}},
 Birthday={beds={{'LevelDrone',.065,.48},{'LevelAir',.025,.22},{'AmbCreaks',.03,1}},
  stingers={{'StingCave1',2,true},{'StingCave2',2,true},{'StingCave3',2,true},{'StingCreak',4,true},{'StingKnock',2,true}}},
 -- A low machinery bed, moving air and distant hull strain use existing cues.
 Cruise={beds={{'LevelDrone',.065,.30},{'LevelAir',.028,.22},{'AmbWind',.035,.8},{'AmbCreaks',.025,.85}},
  stingers={{'StingHull',5,true},{'StingCreak',3,true},{'StingBumps',2,true},{'StingKnock',1,true},{'StingCave1',1,true}}},
 -- Existing electrical drone and heavily muffled music suggest vacant fluorescent aisles.
 Mall={beds={{'LevelAir',.025,.25},{'DiscoMusic',.008,.86,'muzak'}},
  stingers={{'StingCave1',1,true},{'StingCave2',1,true},{'StingCave3',1,true},{'StingHull',3,true},{'StingBumps',3,true},{'StingKnock',1,true}}},
}
local STINGER_GAP=NumberRange.new(14,32) -- seconds between stingers
local FIRST_STINGER_DELAY=20
local STINGER_DISTANCE=NumberRange.new(18,40) -- studs from the listener
local rng=Random.new()
local sounds={};local activeMap;local activeKind;local timer=0;local nextStinger=0
local function clear()
 for _,s in sounds do Audio.Stop(s)end
 table.clear(sounds);activeMap=nil;activeKind=nil
 script:SetAttribute('AmbienceActive',false)
end
local function start(map,kind)
 clear();activeMap=map;activeKind=kind
 local profile=profiles[kind]or profiles.Mansion
 for _,entry in profile.beds do
  -- A distinct origin keeps the ambient muzak separate from an item's music loop.
  local origin=if entry[4]=='muzak' then game:GetService('SoundService') else nil
  local s=Audio.Play(entry[1],origin,{volume=0,speed=entry[3],loop=true})
  if s then
   if kind=='Mall' and (entry[1]=='NeonAmbient' or entry[4]=='muzak') then
    local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=if entry[4]=='muzak' then -12 else -3;eq.MidGain=-8;eq.HighGain=if entry[4]=='muzak' then -24 else -14;eq.Parent=s
   end
   if entry[1]=='LevelDrone'or entry[1]=='LevelAir'then local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=2;eq.MidGain=-6;eq.HighGain=-18;eq.Parent=s end
   table.insert(sounds,s);s:SetAttribute('AmbienceTargetVolume',entry[2])
  end
 end
 nextStinger=os.clock()+FIRST_STINGER_DELAY
 script:SetAttribute('AmbienceActive',true);script:SetAttribute('AmbienceMapKind',kind)
end
local function pick(list)
 local total=0;for _,s in list do total+=s[2]end
 local roll=rng:NextNumber(0,total)
 for _,s in list do roll-=s[2];if roll<=0 then return s end end
 return list[1]
end
local function stinger(kind)
 local profile=profiles[kind]or profiles.Mansion
 local choice=pick(profile.stingers)
 local cam=workspace.CurrentCamera;local sound
 if choice[3]and cam then
  local angle=rng:NextNumber(0,math.pi*2);local dist=rng:NextNumber(STINGER_DISTANCE.Min,STINGER_DISTANCE.Max)
  sound=Audio.Play(choice[1],cam.CFrame.Position+Vector3.new(math.cos(angle)*dist,rng:NextNumber(-2,6),math.sin(angle)*dist))
 else
  sound=Audio.Play(choice[1])
 end
 -- cave stingers: long echoing reverb and muffled highs so they sound far away inside the walls
 if sound and choice[1]:sub(1,9)=='StingCave' then
  local verb=Instance.new('ReverbSoundEffect');verb.DecayTime=6;verb.Density=1;verb.Diffusion=1;verb.WetLevel=-2;verb.DryLevel=-6;verb.Parent=sound
  local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=3;eq.MidGain=-2;eq.HighGain=-14;eq.Parent=sound
 end
 script:SetAttribute('LastStinger',choice[1])
end
Run.Heartbeat:Connect(function(dt)
 timer+=dt;if timer<.2 then return end;local elapsed=timer;timer=0
 local map=workspace:FindFirstChild('Mansion')
 if player:GetAttribute('MissionActive')~=true or not map or not map:GetAttribute('RuntimeReady')then
  if activeMap then clear()end;return
 end
 local kind=map:GetAttribute('MapKind')or 'Mansion'
 if map~=activeMap or kind~=activeKind then start(map,kind)end
 for _,s in sounds do
  if s.Parent and s:GetAttribute('PlaybackReady')then
   local target=s:GetAttribute('AmbienceTargetVolume')
   s.Volume+=(target-s.Volume)*math.min(1,elapsed*.65)
  end
 end
 if os.clock()>=nextStinger then nextStinger=os.clock()+rng:NextNumber(STINGER_GAP.Min,STINGER_GAP.Max);stinger(kind)end
end)
script.Destroying:Connect(clear)

-- Level music: a quiet score per map kind that reacts to the monsters.
-- Exploring plays a calm track; a hunting monster nearby muffles it and brings in a heartbeat that speeds up as it closes;
-- a chase cuts the music with a hit and a moment of silence, then chase music runs until the monster loses you.
local SoundService=game:GetService('SoundService')
local Debris=game:GetService('Debris')
local CALM={ -- Roblox-licensed tracks. 2026-10-23 owner-approved set only, every map: Forgotten Crypt Ambient (owner favourite), Saints and Sinners, Horror Cinematic Dark Scary Ambience Spooky. Removed: Dark Ambient Scary Horror Suspense, FEELING UNEASY, SPOOKY PLACE, Midnight Litany of Drones
 Mansion={139743346356072,105626914625386,89491279928499},
 Hotel={139743346356072,105626914625386,89491279928499},
 Dungeon={139743346356072,105626914625386,89491279928499},
 Birthday={139743346356072,105626914625386,89491279928499},
 Hospital={139743346356072,105626914625386,89491279928499},
 School={139743346356072,105626914625386,89491279928499},
 Cruise={139743346356072,105626914625386,89491279928499},
 Mall={139743346356072,105626914625386,89491279928499},
}
-- Chase: APM film-score dread (Growing Tension, Entrapment, Mortal Danger, The Creature); the first set sounded too friendly.
local CHASE={9040214335,1839852229,1841287588,1846429336}
local HEARTBEAT,CHASE_HIT='rbxassetid://9043365842','rbxassetid://104131914354223'
local CALM_VOLUME,CHASE_VOLUME,BEAT_VOLUME,HIT_VOLUME=.14,.3,.32,.4
local HUNT_RANGE,IDLE_RANGE,CHASE_RANGE=60,30,75 -- studs
local CHASE_HOLD,CUT_SILENCE=6,.6 -- seconds a chase lingers after the last sighting; dead air after the cut
local musicFolder=Instance.new('Folder');musicFolder.Name='LevelMusic';musicFolder.Parent=SoundService
local function musicGroup()
 local g=SoundService:FindFirstChild('GameplayMusic')
 if not g then g=Instance.new('SoundGroup');g.Name='GameplayMusic';g.Volume=.6;g.Parent=SoundService end
 return g
end
-- Level music fades out inside the van (the van radio plays there) and back in outside (owner 2026-10-26).
-- A child SoundGroup multiplies GameplayMusic, so the player's music setting still applies.
local function vanMix()
 local g=musicGroup();local m=g:FindFirstChild('LevelMusicVanFade')
 if not m then m=Instance.new('SoundGroup');m.Name='LevelMusicVanFade';m.Volume=1;m.Parent=g end
 return m
end
local VAN_FADE_SECONDS=1.2
local function inVan()
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan');local floor=van and van:FindFirstChild('Floor');local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if not root or not floor then return false end
 local q=floor.CFrame:PointToObjectSpace(root.Position);return math.abs(q.X)<11 and q.Y>0 and q.Y<12 and q.Z>-24.5 and q.Z<16
end
Run.Heartbeat:Connect(function(dt)
 local m=vanMix();local want=inVan()and 0 or 1
 if m.Volume~=want then m.Volume=want>m.Volume and math.min(want,m.Volume+dt/VAN_FADE_SECONDS)or math.max(want,m.Volume-dt/VAN_FADE_SECONDS)end
 script:SetAttribute('VanFade',m.Volume)
end)
local function musicSound(name,id,looped)
 local s=Instance.new('Sound');s.Name=name;s.SoundId=id;s.Looped=looped;s.Volume=0;s.SoundGroup=vanMix();s.Parent=musicFolder
 return s
end
local mrng=Random.new()
local calm,calmEq,chase,beat
local musicMap,musicKind,lastCalm=nil,nil,nil
local mode,lastChase,cutUntil,tension,threatTimer,near,chased='calm',0,0,0,0,0,false
local function stopMusic()
 musicFolder:ClearAllChildren();calm,calmEq,chase,beat=nil,nil,nil,nil
 musicMap,musicKind,mode,tension,near,chased=nil,nil,'calm',0,0,false
 script:SetAttribute('MusicMode',nil);script:SetAttribute('MusicTrack',nil)
end
local function nextCalm()
 local list=CALM[musicKind]or CALM.Mansion
 local id=list[mrng:NextInteger(1,#list)]
 if #list>1 and id==lastCalm then id=list[(table.find(list,id)::number)%#list+1]end
 lastCalm=id
 if calm then calm:Destroy()end
 local s=musicSound('Calm','rbxassetid://'..id,false);calm=s
 calmEq=Instance.new('EqualizerSoundEffect');calmEq.LowGain=0;calmEq.MidGain=0;calmEq.HighGain=0;calmEq.Parent=s
 s.Ended:Once(function()if calm==s then nextCalm()end end)
 s:Play();script:SetAttribute('MusicTrack',id)
end
local function startMusic(map,kind)
 stopMusic();musicMap,musicKind=map,kind
 beat=musicSound('Heartbeat',HEARTBEAT,true);beat:Play()
 nextCalm()
 task.spawn(function()
  local warm={}
  for _,id in CHASE do table.insert(warm,musicSound('Warm','rbxassetid://'..id,false))end
  table.insert(warm,musicSound('Warm',CHASE_HIT,false))
  pcall(function()game:GetService('ContentProvider'):PreloadAsync(warm)end)
  for _,s in warm do s:Destroy()end
 end)
end
local function enterChase()
 mode='chase';cutUntil=os.clock()+CUT_SILENCE
 if calm then calm.Volume=0 end -- the cut: the song stops dead
 local hit=musicSound('ChaseHit',CHASE_HIT,false);hit.Volume=HIT_VOLUME;hit:Play();Debris:AddItem(hit,5)
 if chase then chase:Destroy()end
 chase=musicSound('Chase','rbxassetid://'..CHASE[mrng:NextInteger(1,#CHASE)],true)
 -- Pitched down and bass-heavy so any cue reads as menace, not adventure.
 chase.PlaybackSpeed=.9
 local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=4;eq.MidGain=-2;eq.HighGain=-6;eq.Parent=chase
 local verb=Instance.new('ReverbSoundEffect');verb.DecayTime=2.2;verb.Density=1;verb.Diffusion=1;verb.WetLevel=-10;verb.DryLevel=0;verb.Parent=chase
end
local function readThreat(origin)
 local folder=workspace:FindFirstChild('RoamingCreatures');if not folder then return 0,false end
 local closest,seen=0,false
 for _,m in folder:GetChildren()do
  local r=m:IsA('Model')and m.PrimaryPart;if not r then continue end
  local d=(r.Position-origin).Magnitude;local state=m:GetAttribute('AIState')
  if state=='Chase'and d<CHASE_RANGE then seen=true end
  if state=='Chase'or state=='Search'or state=='Stalk'or state=='Suspicious'then closest=math.max(closest,1-d/HUNT_RANGE)
  else closest=math.max(closest,.5*(1-d/IDLE_RANGE))end
 end
 return math.clamp(closest,0,1),seen
end
local function ease(s,target,rate,dt)
 if s then s.Volume+=(target-s.Volume)*math.min(1,dt*rate)end
end
Run.Heartbeat:Connect(function(dt)
 local map=workspace:FindFirstChild('Mansion')
 if player:GetAttribute('MissionActive')~=true or not map or not map:GetAttribute('RuntimeReady')then
  if musicMap then stopMusic()end;return
 end
 local kind=map:GetAttribute('MapKind')or 'Mansion'
 if map~=musicMap or kind~=musicKind then startMusic(map,kind)end
 local char=player.Character;local hum=char and char:FindFirstChildOfClass('Humanoid')
 local root=char and char:FindFirstChild('HumanoidRootPart')
 threatTimer+=dt
 if threatTimer>=.2 then
  threatTimer=0
  local cam=workspace.CurrentCamera;local origin=root and root.Position or cam and cam.CFrame.Position
  if origin then near,chased=readThreat(origin)end
 end
 local now=os.clock()
 if chased then lastChase=now;if mode~='chase'then enterChase()end
 elseif mode=='chase'and now-lastChase>CHASE_HOLD then mode='calm'end
 local rr=RS:FindFirstChild('RecoveryRound')
 local quiet=(rr and rr:GetAttribute('Phase')=='Failed')or not hum or hum.Health<=0
 local hidden=player:GetAttribute('Hiding')==true
 tension+=((mode=='chase'and 1 or near)-tension)*math.min(1,dt*2)
 local calmTarget=(quiet or mode=='chase')and 0 or CALM_VOLUME*(1-.65*tension)*(hidden and .35 or 1)
 if calm then ease(calm,calmTarget,calmTarget<calm.Volume and 1.5 or .35,dt)end
 if calmEq then calmEq.HighGain=-22*tension;calmEq.MidGain=-8*tension end
 if chase then
  if mode=='chase'and not quiet then
   if now>=cutUntil and not chase.IsPlaying then chase.Volume=CHASE_VOLUME;chase:Play()end
  else
   ease(chase,0,.6,dt)
   if chase.Volume<.004 then chase:Destroy();chase=nil end
  end
 end
 if beat then
  ease(beat,quiet and 0 or BEAT_VOLUME*math.clamp((tension-.15)/.85,0,1)*(mode=='chase'and .5 or 1),2,dt)
  beat.PlaybackSpeed=.6+.65*tension
 end
 script:SetAttribute('MusicMode',mode);script:SetAttribute('MusicTension',math.floor(tension*100)/100)
end)
script.Destroying:Connect(stopMusic)

-- Level scares (owner 2026-10-25: "more quality scary noises", each with a real cause). Scheduled by DreadLayer (below),
-- never while a monster is hunting close (that is already scary, and the warning sounds matter):
--  knock   a real closed door near you, out of sight, is knocked on and rattles in its frame
--  steps   something creeps across the floor right above you (or the next room on a one-floor map)
--  thud    a real loot item in another room falls over (its sound comes from that item)
--  whisper you have stood still too long: a whisper right behind your head
--  shriek  a real monster far out of sight shrieks from where it actually is (also a warning)
local SCARE_NEAR,SCARE_FAR=12,38 -- studs: how close a door / item has to be
local STILL_SECONDS=7 -- standing this long arms the whisper
local FLOOR_HEIGHT=16
local srng=Random.new()
local stillSince,lastPos=os.clock(),nil
local function hidden(pos,cam)
 -- out of sight: behind the camera, or a wall in between
 local v,on=cam:WorldToViewportPoint(pos);if not on or v.Z<0 then return true end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={player.Character}
 local hit=workspace:Raycast(cam.CFrame.Position,pos-cam.CFrame.Position,params)
 return hit~=nil and (hit.Position-pos).Magnitude>3
end
local function candidates(map,root,cam,test)
 local list={};local interactive=map:FindFirstChild('Interactive');if not interactive then return list end
 for _,m in interactive:GetChildren()do
  local part=m:IsA('Model')and m.PrimaryPart
  if part and test(m)then local d=(part.Position-root.Position).Magnitude;if d>=SCARE_NEAR and d<=SCARE_FAR and hidden(part.Position,cam)then table.insert(list,m)end end
 end
 return list
end
local function rattle(door)
 -- the door shivers in its frame for a moment, then sits exactly where it was (doors only move when the server swings them)
 local home=door:GetPivot()
 task.spawn(function()
  for i=1,8 do if not door.Parent or (door:GetAttribute('Open')or 0)>.02 then return end
   door:PivotTo(home*CFrame.Angles(0,math.rad((i%2==0 and 1 or -1)*.9*(1-i/9)),0));task.wait(.05)end
  if door.Parent and (door:GetAttribute('Open')or 0)<=.02 then door:PivotTo(home)end
 end)
end
local function walker(from,to,seconds)
 -- an invisible point that walks from `from` to `to`; the creaking footsteps ride on it
 local p=Instance.new('Part');p.Name='ScareWalker';p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Transparency=1;p.Size=Vector3.one;p.Position=from;p.Parent=workspace
 game:GetService('TweenService'):Create(p,TweenInfo.new(seconds,Enum.EasingStyle.Linear),{Position=to}):Play()
 game:GetService('Debris'):AddItem(p,seconds+1)
 return p
end
local scares={}
scares.knock=function(map,root,cam)
 local doors=candidates(map,root,cam,function(m)return m:GetAttribute('Kind')=='door'and(m:GetAttribute('Open')or 0)<=.02 end)
 if #doors==0 then return false end
 local door=doors[srng:NextInteger(1,#doors)]
 local heavy=srng:NextNumber()<.3
 Audio.Play(heavy and 'ScarePound' or 'ScareKnock',door);rattle(door)
 if not heavy and srng:NextNumber()<.5 then task.delay(srng:NextNumber(2.2,3.4),function()if door.Parent then Audio.Play('ScareKnock',door,{volume=.4});rattle(door)end end)end
 script:SetAttribute('LastScareTarget',door.Name)
 return true
end
scares.steps=function(map,root,cam)
 local look=cam.CFrame.LookVector;local side=Vector3.new(-look.Z,0,look.X).Unit
 local above=workspace:Raycast(root.Position,Vector3.new(0,FLOOR_HEIGHT+4,0))
 local y=above and root.Position.Y+FLOOR_HEIGHT-1 or root.Position.Y
 local center=above and root.Position or root.Position-Vector3.new(look.X,0,look.Z).Unit*18
 local from=Vector3.new(center.X,y,center.Z)-side*10;local to=Vector3.new(center.X,y,center.Z)+side*10
 if srng:NextNumber()<.5 then from,to=to,from end
 local w=walker(from,to,5.5);Audio.Play('ScareSteps',w)
 script:SetAttribute('LastScareTarget',above and 'floor above' or 'next room')
 return true
end
scares.thud=function(map,root,cam)
 local items=candidates(map,root,cam,function(m)return m:GetAttribute('Kind')=='pickup'and not m:GetAttribute('HeldBy')and not m:GetAttribute('CargoStored')end)
 if #items==0 then return false end
 local item=items[srng:NextInteger(1,#items)];Audio.Play('ScareThud',item)
 script:SetAttribute('LastScareTarget',item.Name)
 return true
end
scares.whisper=function(map,root,cam)
 if os.clock()-stillSince<STILL_SECONDS then return false end
 local behind=cam.CFrame.Position-cam.CFrame.LookVector*2.5+cam.CFrame.RightVector*srng:NextNumber(-1,1)
 Audio.Play('ScareWhisper',behind)
 script:SetAttribute('LastScareTarget','behind you')
 return true
end
scares.shriek=function(map,root,cam)
 local folder=workspace:FindFirstChild('RoamingCreatures');if not folder then return false end
 local pick
 for _,m in folder:GetChildren()do local r=m:IsA('Model')and m.PrimaryPart
  if r then local d=(r.Position-root.Position).Magnitude;if d>70 and d<220 and m:GetAttribute('AIState')~='Chase'then pick=r break end end end
 if not pick then return false end
 -- heard far off, through the walls: from its real direction, 45 studs out, with a long muffled echo
 local dir=(pick.Position-root.Position)*Vector3.new(1,0,1);dir=dir.Magnitude>.1 and dir.Unit or Vector3.new(0,0,-1)
 local s=Audio.Play('WraithNotice',root.Position+dir*45+Vector3.new(0,4,0),{volume=.3,speed=.78})
 if s then
  local verb=Instance.new('ReverbSoundEffect');verb.DecayTime=5;verb.Density=1;verb.Diffusion=1;verb.WetLevel=-1;verb.DryLevel=-8;verb.Parent=s
  local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=2;eq.MidGain=-4;eq.HighGain=-16;eq.Parent=s
 end
 script:SetAttribute('LastScareTarget',pick.Parent and pick.Parent.Name or 'monster')
 return true
end
-- Dread layer (2026-10-27 ScareSound): LevelAmbienceClient.DreadLayer runs the idle-scare director (the scares above
-- plus creaking doors, flickering lights, footsteps behind you, breathing, a shadow down the corridor...) from level 1,
-- the monster-closeness tells (breathing, flashlight brown-out, spotted / lost stings, vignette and shake drivers) and
-- quiet room detail. Studio tests: set this script's ForceScare attribute to a scare name.
Run.Heartbeat:Connect(function()
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');if not root then return end
 -- still = has not left a 1.5-stud circle (a per-frame step is under 0.4 studs even when walking)
 if not lastPos or(root.Position-lastPos).Magnitude>1.5 then stillSince=os.clock();lastPos=root.Position end
end)
require(script:WaitForChild('DreadLayer')).Start({scares=scares,script=script,readThreat=readThreat,inVan=inVan,stillFor=function()return os.clock()-stillSince end})

-- World happenings (WorldB 2026-10-27; InteractServer.WorldHappenings): lightning flashes and the swinging chandelier.
-- Lightning: Mansion.LightningAt (server time) -> a faint 0.35 s blue-white lift that only fades (no white flash) and a pale
-- cyan through-wall outline on every monster for 1.5 s. Chandelier: Mansion.Happenings.SwingChandelier swings about its
-- ceiling rose from SwayAmp (degrees, set by the server at 4 Hz); this client animates the pendulum smoothly.
do
 local Lighting=game:GetService('Lighting')
 local flash=Instance.new('ColorCorrectionEffect');flash.Name='StormFlash';flash.Enabled=false;flash.Parent=Lighting
 local seenStrike,strikeAt=nil,-math.huge
 local outlines={}
 local CYAN=Color3.fromRGB(190,235,255)
 local swing={} -- chandelier model -> {phase, amp}
 Run.RenderStepped:Connect(function(dt)
  local map=workspace:FindFirstChild('Mansion');if not map then return end
  local at=map:GetAttribute('LightningAt')
  if type(at)=='number'and at~=seenStrike then
   seenStrike=at
   if workspace:GetServerTimeNow()-at<1.5 then
    strikeAt=os.clock()
    local f=workspace:FindFirstChild('RoamingCreatures')
    if f then for _,mon in f:GetChildren()do if mon:IsA('Model')then
     -- PlaytestFixes 2026-10-27 (owner: monsters seen through walls for brief moments): this was AlwaysOnTop on every
     -- monster on the map for 1.5 s at each strike (every 25-35 s from level 2). Now Occluded and within 70 studs: the
     -- flash only silhouettes a monster you could actually see.
     local cam=workspace.CurrentCamera;local pos=mon:GetPivot().Position
     if cam and (cam.CFrame.Position-pos).Magnitude<70 then
      local h=Instance.new('Highlight');h.Name='StormOutline';h.FillColor=CYAN;h.OutlineColor=CYAN;h.FillTransparency=.75;h.OutlineTransparency=0
      h.DepthMode=Enum.HighlightDepthMode.Occluded;h.Adornee=mon;h.Parent=cam;table.insert(outlines,h)
     end
    end end end
   end
  end
  local age=os.clock()-strikeAt
  if age<.35 then flash.Enabled=true;local k=1-age/.35;flash.Brightness=.12*k;flash.Contrast=.06*k;flash.TintColor=Color3.new(1,1,1):Lerp(CYAN,.3)
  elseif flash.Enabled then flash.Enabled=false end
  if #outlines>0 and age>1.5 then for _,h in outlines do h:Destroy()end;table.clear(outlines)
  elseif #outlines>0 then for _,h in outlines do h.OutlineTransparency=math.clamp((age-1)/.5,0,1)end end
  local folder=map:FindFirstChild('Happenings');local c=folder and folder:FindFirstChild('SwingChandelier')
  if c and c.PrimaryPart and not c:GetAttribute('Crashed')then
   local rest=c:GetAttribute('RestCF');local h=c:GetAttribute('HangHeight')or 5.4
   if typeof(rest)=='CFrame'then
    local s=swing[c];if not s then s={phase=0,amp=0};swing[c]=s end
    s.amp+=((c:GetAttribute('SwayAmp')or 0)-s.amp)*math.min(1,dt*3) -- ease toward the server's amplitude
    s.phase+=dt*2*math.pi/2.6 -- a 2.6 s pendulum
    local a=math.rad(s.amp)*math.sin(s.phase)
    local top=rest*CFrame.new(0,h,0)
    c:PivotTo(top*CFrame.Angles(a,0,a*.35)*CFrame.new(0,-h,0))
   end
  end
  for m in swing do if not m.Parent or m:GetAttribute('Crashed')then swing[m]=nil end end
 end)
end
