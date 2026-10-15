local Run=game:GetService('RunService')
assert(Run:IsClient(),'GameplayAudio is client presentation only')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('SoundService')
local Debris=game:GetService('Debris')
local C=require(RS:WaitForChild('GameplaySoundCatalog'))
local M={Catalog=C}
local Pref=require(RS:WaitForChild('HorrorPreferences'))
local function soundGroup(name,base)
 local g=SS:FindFirstChild(name)or Instance.new('SoundGroup');g.Name=name;g.Parent=SS
 g.Volume=base*Pref.Get('MasterVolume')*Pref.Get('EffectsVolume');return g
end
local group=soundGroup('GameplaySFX',2.4)
local uiGroup=soundGroup('GameplayUI',2.25)
local folder=Instance.new('Folder');folder.Name='GameplaySFXPlayback';folder.Parent=SS
local currentCount=0;local lastUI={};local lastVariant={};local rng=Random.new()
local Content=game:GetService('ContentProvider')
local LOAD_TIMEOUT=8
local fetchStatus={}
local failedAssets={};local activeSounds={};local loopSounds={};local requested,peak=0,0
local function bundledFor(key)
 return (key:find('Footstep')or key:find('Run')or key=='CartRoll')and 'rbxasset://sounds/action_footsteps_plastic.mp3'
  or(key=='Spit'or key=='Wash'or key=='CloudRain'or key=='LevelAir')and 'rbxasset://sounds/impact_water.mp3'
  or 'rbxasset://sounds/action_jump_land.mp3'
end
-- Creator Store effects and bundled sounds keep failed private uploads from silencing essential cues.
local fallback={
 HypnoShot='rbxassetid://9116768228',HypnoShotLocal='rbxassetid://9116768228',HypnoHit='rbxassetid://9114597147',
 PlayerRunWood='rbxasset://sounds/action_footsteps_plastic.mp3',PlayerRunStone='rbxasset://sounds/action_footsteps_plastic.mp3',MonsterRun='rbxasset://sounds/action_jump_land.mp3',
 CrawlerBreath='rbxassetid://9113973128',CrawlerNotice='rbxassetid://9113980319',CrawlerRush='rbxassetid://9113980319',CrawlerSearch='rbxassetid://9113973128',
 WraithBreath='rbxassetid://9043347151',WraithNotice='rbxassetid://9113988191',WraithRush='rbxassetid://9113988191',WraithSearch='rbxassetid://9043347151',
 LevelDrone='rbxasset://sounds/impact_water.mp3',LevelAir='rbxasset://sounds/impact_water.mp3',
 DoorOpen='rbxassetid://9120839010',DoorClose='rbxassetid://9120839010',
 DrawerOpen='rbxassetid://9113658569',DrawerClose='rbxassetid://9113658569',
 ItemPickup='rbxassetid://9113837941',ItemRelease='rbxasset://sounds/action_jump_land.mp3',
 PlayerFootstep='rbxasset://sounds/action_footsteps_plastic.mp3',PlayerStoneFootstep='rbxasset://sounds/action_footsteps_plastic.mp3',
 UiClick='rbxassetid://9116725218',UiOpen='rbxassetid://9116725218',UiClose='rbxassetid://9116725218',UiError='rbxassetid://9116725218',
 FlashlightClick='rbxassetid://9116725218',SaleStart='rbxassetid://9116725218',SaleComplete='rbxassetid://9116725218',SaleCancelled='rbxassetid://9116725218',
 RoundStart='rbxassetid://9116725218',RoundWin='rbxassetid://9116725218',QuotaMet='rbxassetid://9116725218',
 CartRoll='rbxassetid://9119088927',Spit='rbxasset://sounds/impact_water.mp3',FrostingSquish='rbxasset://sounds/impact_water.mp3',
 SprintBreath='rbxassetid://9113984056',MonsterNotice='rbxassetid://9113973128',MonsterRush='rbxassetid://9113980319',
 MonsterIdle='rbxassetid://9113984056',MonsterJumpscare='rbxassetid://9113988191',MonsterJumpscareHit='rbxassetid://9113980319',
 ClockTick='rbxassetid://9116725218',TelephoneRing='rbxassetid://9116725218',DinnerBell='rbxassetid://9116725218',
 TeamWipe='rbxassetid://9113984056',Heartbeat='rbxassetid://9113984056',DollCry='rbxassetid://9043347151',CloudSob='rbxassetid://9043347151',
 ItemRattle='rbxassetid://9119088927',VacuumMotor='rbxassetid://9114505206',KeyJingle='rbxassetid://9116725218',
 Whistle='rbxassetid://9120689345',PartyHorn='rbxassetid://9120689345',PartyBlower='rbxassetid://9120689345',
 MusicBox='rbxassetid://1835617224',DiscoMusic='rbxassetid://1835617224',CloudRain='rbxasset://sounds/impact_water.mp3',
 JarPop='rbxassetid://9114597147'
}
local function loaded(sound)
 local deadline=os.clock()+LOAD_TIMEOUT
 while sound.Parent and not sound.IsLoaded and os.clock()<deadline do
  local status=Content:GetAssetFetchStatus(sound.SoundId)
  if status==Enum.AssetFetchStatus.Failure or status==Enum.AssetFetchStatus.TimedOut then return false end
  task.wait(.05)
 end
 return sound.Parent~=nil and sound.IsLoaded
end
function M.Play(key,origin,options)
 local cue=key=='SoundTest'and {id='rbxasset://sounds/action_jump_land.mp3',name='Bundled sound test',volume=.7,speed=1,range=55,duration=.8}or C[key]
 if not cue then script:SetAttribute('UnknownCue',tostring(key));return end

 if key:sub(1,2)=='Ui' then local now=os.clock();if now-(lastUI[key] or 0)<.05 then return end;lastUI[key]=now end
 options=options or {}
 requested+=1
 local looping=if options.loop~=nil then options.loop else cue.loop==true
 local loopOrigin=typeof(origin)=='Vector3'and tostring(origin)or origin or 'global'
 local loopEntry=looping and loopSounds[loopOrigin]
 local prior=loopEntry and loopEntry[key]
 if prior and prior.Parent then return prior end
 local asset=cue
 if cue.pool and #cue.pool>0 then
  local index=rng:NextInteger(1,#cue.pool)
  if #cue.pool>1 and index==lastVariant[key]then index=index%#cue.pool+1 end
  lastVariant[key]=index;asset=cue.pool[index]
 end
 local originalAsset=asset.id
 local remembered=failedAssets[originalAsset]or fetchStatus[originalAsset]
 if remembered==true or remembered==Enum.AssetFetchStatus.Failure or remembered==Enum.AssetFetchStatus.TimedOut then
  local id=fallback[key]or bundledFor(key)
  if failedAssets[id]then id=bundledFor(key)end
  asset={id=id,name=asset.name}
 end
 local parent=folder;local holder
 if typeof(origin)=='Vector3' then
  local camera=workspace.CurrentCamera;if camera and (camera.CFrame.Position-origin).Magnitude>cue.range+10 then return end
  holder=Instance.new('Part');holder.Name='AudioOrigin_'..key;holder.Size=Vector3.one;holder.Transparency=1;holder.Anchored=true;holder.CanCollide=false;holder.CanTouch=false;holder.CanQuery=false;holder.Position=origin;holder.Parent=workspace
  local attachment=Instance.new('Attachment');attachment.Parent=holder;parent=attachment
 elseif typeof(origin)=='Instance' then
  if not origin.Parent then return end
  if origin:IsA('Model') then origin=origin.PrimaryPart end
  if not origin then return end
  if origin:IsA('BasePart') then holder=Instance.new('Attachment');holder.Name='AudioOrigin_'..key;holder.Parent=origin;parent=holder
  else parent=origin end
 end
 local sound=Instance.new('Sound');sound.Name=key;sound.SoundId=asset.id;sound:SetAttribute('AssetName',asset.name or cue.name);sound.Volume=options.volume or cue.volume;sound.PlaybackSpeed=options.speed or cue.speed
 sound.Looped=if options.loop~=nil then options.loop else cue.loop==true;sound.RollOffMode=Enum.RollOffMode.InverseTapered;sound.RollOffMinDistance=cue.minDistance or 4;sound.RollOffMaxDistance=cue.range
 if key=='HypnoShot'or key=='HypnoShotLocal'then
  local wobble=Instance.new('ChorusSoundEffect');wobble.Name='HypnoWobble';wobble.Depth=.3;wobble.Mix=.18;wobble.Rate=5;wobble.Parent=sound
 end
 sound.SoundGroup=key:sub(1,2)=='Ui' and uiGroup or group;sound.Parent=parent
 currentCount+=1;peak=math.max(peak,currentCount);activeSounds[sound]=os.clock()
 if looping then local entry=loopSounds[loopOrigin]or {};loopSounds[loopOrigin]=entry;entry[key]=sound end
 if asset.id~=originalAsset then sound:SetAttribute('UsedFallback',true)end
 sound.Destroying:Once(function()
  if looping then local entry=loopSounds[loopOrigin];if entry and entry[key]==sound then entry[key]=nil;if not next(entry)then loopSounds[loopOrigin]=nil end end end
  activeSounds[sound]=nil;currentCount=math.max(0,currentCount-1);if holder and holder.Parent then task.defer(function()if holder.Parent then holder:Destroy()end end) end end)
 sound.Ended:Once(function()if sound.Parent and not sound.Looped then sound:Destroy()end end)
 task.spawn(function()
  -- Wait for loading before starting; a short sound must not end during the load check.
  if not loaded(sound)then
   if not sound.Parent then return end
   failedAssets[sound.SoundId]=true
   local replacement=fallback[key]
   script:SetAttribute('LastFailedCue',key);script:SetAttribute('LastFailedAsset',sound.SoundId)
   script:SetAttribute('LoadFailureCount',(script:GetAttribute('LoadFailureCount')or 0)+1)
   local function tryAsset(id)
    if not id or id==sound.SoundId or not sound.Parent then return false end
    sound:Stop();sound.SoundId=id;sound:SetAttribute('UsedFallback',true)
    local ready=loaded(sound);if not ready then failedAssets[id]=true end;return ready
   end
   local recovered=tryAsset(replacement)
   if not recovered then
    local bundled=bundledFor(key)
    recovered=tryAsset(bundled)
    if recovered then sound:SetAttribute('UsedBundledFallback',true)end
   end
   if not recovered then
    script:SetAttribute('UnrecoverableCue',key)
    if sound.Parent then sound:Destroy()end;return
   end
  end
  if not sound.Parent then return end
  sound.TimePosition=0;sound:SetAttribute('PlaybackReady',true);sound:Play()
  -- Cue duration starts at audible playback, rather than at the start of a network download.
  if not sound.Looped then Debris:AddItem(sound,math.max(options.duration or cue.duration or 0,sound.TimeLength/math.max(sound.PlaybackSpeed,.05)+.25,1))end
 end)
 return sound
end
function M.Stats()
 local active,ready,playing,loops=0,0,0,0
 for sound in activeSounds do if sound.Parent then active+=1;if sound:GetAttribute('PlaybackReady')then ready+=1 end;if sound.IsPlaying then playing+=1 end;if sound.Looped then loops+=1 end end end
 return {active=active,ready=ready,playing=playing,loops=loops,peak=peak,requested=requested}
end
function M.Test()return M.Play('SoundTest',nil,{duration=.8})end
function M.Stop(sound)
 if sound and sound.Parent then sound:Stop();sound:Destroy()end
end
-- Named cue previews allow one sound to be reviewed without triggering gameplay.
local preview=Instance.new('BindableEvent');preview.Name='Preview';preview.Parent=script
preview.Event:Connect(function(key) local cue=C[key];if cue then M.Play(key,nil,{loop=false,duration=math.min(cue.duration or 5,5)})end end)
task.spawn(function()
 local sounds,seen={},{}
 for _,cue in pairs(C)do if type(cue)=='table'then
  for _,asset in cue.pool or {cue}do if asset.id and not seen[asset.id]then
   seen[asset.id]=true;local s=Instance.new('Sound');s.SoundId=asset.id;s.Parent=folder;table.insert(sounds,s)
  end end
 end end
 for _,asset in pairs(fallback)do if not seen[asset]then
  seen[asset]=true;local s=Instance.new('Sound');s.SoundId=asset;s.Parent=folder;table.insert(sounds,s)
 end end
 local status={}
 pcall(function()Content:PreloadAsync(sounds,function(id,state)
  fetchStatus[id]=state;status[id]=tostring(state)
  script:SetAttribute('PreloadStatus',game:GetService('HttpService'):JSONEncode(status))
 end)end)
 for _,s in sounds do s:Destroy()end
 script:SetAttribute('PreloadFinished',true)
end)
return M
