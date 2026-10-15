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
 Hospital={beds={{'NeonAmbient',.024,.68},{'LevelAir',.026,.23},{'LevelDrone',.05,.32}},
  stingers={{'StingBumps',3,true},{'StingKnock',2,true},{'StingCreak',2,true},{'StingCave1',1,true},{'StingHull',1,true}}},
 -- Empty fluorescent halls, moving air, distant knocks and footsteps above.
 School={beds={{'NeonAmbient',.02,.62},{'LevelAir',.028,.22},{'LevelDrone',.055,.34},{'AmbCreaks',.025,.95}},
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
 Mall={beds={{'NeonAmbient',.022,.72},{'LevelAir',.025,.25},{'DiscoMusic',.008,.86,'muzak'}},
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


