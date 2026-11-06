local missionPlayer=game:GetService('Players').LocalPlayer
-- Bind shared sound events immediately, including for slower and late-joining clients.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local player=Players.LocalPlayer

local vocalSounds=setmetatable({},{__mode='k'})
local vocalNext=setmetatable({},{__mode='k'})
local function monsterVoice(model,action)
 local root=model and model.PrimaryPart;if not root then return end
 local prior=vocalSounds[model]
 if prior and prior.Parent and prior.IsPlaying then
  if action=='Breath' or action=='Search' then return end
  Audio.Stop(prior)
 end
 local kind=model:GetAttribute('CreatureKind')
 if kind=='Dancer' or kind=='Mittens' then return end -- Monsters build: the Dancer's voice is her tune; Mittens stays quiet (MonsterAbilities plays its notice)
 if kind~='Crawler' and kind~='Bellhop' and kind~='Lantern' and kind~='Neon' then kind='Wraith' end
 local sound=Audio.Play(kind..action,root)
 vocalSounds[model]=sound
 vocalNext[model]=os.clock()+((sound and sound.TimeLength>0 and sound.TimeLength/sound.PlaybackSpeed)or 6)+math.random(3,6)
end
local draftSounds = {}
RS:WaitForChild('GameplaySoundEvent').OnClientEvent:Connect(function(key,origin)
 if key=='ItemDraftAudio' then
  if type(origin)~='table' or type(origin.token)~='string' then return end
  local token=origin.token
  local previous=draftSounds[token];if previous then Audio.Stop(previous);draftSounds[token]=nil end
  if origin.action=='play' then
   local sound=Audio.Play(origin.key,origin.origin,{loop=origin.loop==true})
   if sound then
    draftSounds[token]=sound
    local readyConnection: RBXScriptConnection? = nil
    local capThread: thread? = nil
    local capped=false
    local function capAtPlayback()
     if capped or not sound:GetAttribute('PlaybackReady')or draftSounds[token]~=sound then return end
     capped=true
     if readyConnection then readyConnection:Disconnect();readyConnection=nil end
     capThread=task.delay(math.clamp(tonumber(origin.duration)or .8,.05,type(origin.key)=='string'and origin.key:sub(1,14)=='DraftSelected_'and 60 or 2),function()
      capThread=nil -- Clear before Stop/Destroy so cleanup never cancels this callback.
      if draftSounds[token]==sound then Audio.Stop(sound);draftSounds[token]=nil end
     end)
    end
    readyConnection=sound:GetAttributeChangedSignal('PlaybackReady'):Connect(capAtPlayback)
    sound.Destroying:Once(function()
     if capThread then task.cancel(capThread);capThread=nil end
     if readyConnection then readyConnection:Disconnect();readyConnection=nil end
     if draftSounds[token]==sound then draftSounds[token]=nil end
    end)
    capAtPlayback()
   end
  end
  return
 end
 if key=='MonsterNotice' or key=='MonsterRush' or key=='MonsterSearch' then
  local folder=workspace:FindFirstChild('RoamingCreatures');local closest,distance=nil,4
  if folder and typeof(origin)=='Vector3' then for _,model in folder:GetChildren()do
   local root=model.PrimaryPart;local d=root and(root.Position-origin).Magnitude or math.huge
   if d<distance then closest,distance=model,d end
  end end
  if closest then monsterVoice(closest,key:sub(8));return end
 end
 Audio.Play(key,origin)
end)

script:SetAttribute('SoundListenerReady',true)
local gui=player:WaitForChild('PlayerGui')
local watched=setmetatable({},{__mode='k'})
local lastClick=0
local function watchUI(x)
 if watched[x] then return end;watched[x]=true
 if x:IsA('GuiButton') then x.Activated:Connect(function()
  if os.clock()-lastClick>.06 then lastClick=os.clock();Audio.Play('UiClick')end
 end)
 elseif x:IsA('Frame') and x.Name=='Picker' then
  x:GetPropertyChangedSignal('Visible'):Connect(function()Audio.Play(x.Visible and 'UiOpen' or 'UiClose')end)
 elseif x:IsA('TextBox') then x.FocusLost:Connect(function()Audio.Play('UiClick')end)end
end
gui.DescendantAdded:Connect(watchUI);for _,x in gui:GetDescendants()do watchUI(x)end
-- World audio polling starts only after admission; event and UI listeners above are already active.
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
local monsters,items=setmetatable({},{__mode='k'}),setmetatable({},{__mode='k'})
local cartSounds=setmetatable({},{__mode='k'});local musicSounds=setmetatable({},{__mode='k'})
local breath,sprintTime= nil,0
local footsteps=setmetatable({},{__mode='k'})
local map=workspace:WaitForChild('Mansion',math.huge);while not map:GetAttribute('RuntimeReady') do map:GetAttributeChangedSignal('RuntimeReady'):Wait()end;local interactive=map:WaitForChild('Interactive')
local creatures=workspace:WaitForChild('RoamingCreatures')
local timer=0
Run.Heartbeat:Connect(function(dt)
 if player:GetAttribute('MissionActive')~=true then
  Audio.Stop(breath);breath=nil
  for model,sound in pairs(vocalSounds)do Audio.Stop(sound);vocalSounds[model]=nil;vocalNext[model]=nil end
  for _,sounds in {cartSounds,musicSounds}do for model,sound in pairs(sounds)do Audio.Stop(sound);sounds[model]=nil end end
  return
 end
 timer+=dt;if timer<.1 then return end;local elapsed=timer;timer=0
 local currentMap=workspace:FindFirstChild('Mansion');local currentCreatures=workspace:FindFirstChild('RoamingCreatures')
 if not currentMap or not currentMap:GetAttribute('RuntimeReady') or not currentCreatures then return end
 if map~=currentMap or creatures~=currentCreatures then
  for _,sounds in {vocalSounds,cartSounds,musicSounds}do for model,sound in pairs(sounds)do Audio.Stop(sound);sounds[model]=nil end end
  map=currentMap;interactive=map:WaitForChild('Interactive');creatures=currentCreatures
  monsters=setmetatable({},{__mode='k'});items=setmetatable({},{__mode='k'})
 end
 local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
 local alive=root and hum and hum.Health>0 and not player:GetAttribute('MonsterJumpscareActive')
 local camera=workspace.CurrentCamera
 if alive and not player:GetAttribute('Hiding') and not root.Anchored and Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude>18 then sprintTime+=elapsed else sprintTime=math.max(0,sprintTime-elapsed*2)end
 if alive and sprintTime>1.2 then if not breath then breath=Audio.Play('SprintBreath')end
 elseif breath then Audio.Stop(breath);breath=nil end
 if not camera then return end
 local now=os.clock()
 for _,model in creatures:GetChildren()do
  local r=model.PrimaryPart;if not r then continue end
  local data=monsters[model] or {pos=r.Position,distance=0,nextIdle=now+8};monsters[model]=data
  local moved=(r.Position-data.pos).Magnitude;data.pos=r.Position
  local range=(r.Position-camera.CFrame.Position).Magnitude
  -- The Neon Tripod's looping song ('NeonAmbient') was removed at the owner's request (2026-10-22).
  -- Bellhop and Lantern footfalls are synced to their animated feet in CreatureAnimateClient.
  local kind=model:GetAttribute('CreatureKind')
  if moved<10 and model:GetAttribute('Walking') and range<85 and kind~='Bellhop' and kind~='Lantern' and kind~='Neon' and kind~='Dancer' then
   data.distance+=moved
   local chase=model:GetAttribute('AIState')=='Chase';local stride=chase and 3.4 or 6
   if data.distance>stride and now>(data.nextStep or 0)then data.distance%=stride;data.nextStep=now+(chase and .14 or .2);Audio.Play(chase and 'MonsterRun'or 'MonsterFootstep',r,{volume=chase and .36 or .23,speed=(model:GetAttribute('CreatureKind')=='Crawler'and .94 or 1.08)*(chase and 1.08 or 1)})end
  else data.distance=0 end
  -- Whispery breath only from a monster that is hunting, or one standing right next to you.
  local state=model:GetAttribute('AIState')
  local hunting=state=='Chase' or state=='Search' or state=='Stalk' or state=='Suspicious'
  if range<60 and (hunting or range<25) and now>(vocalNext[model]or data.nextIdle) then
   monsterVoice(model,'Breath')
  end
 end
 for _,model in interactive:GetChildren()do
  local r=model:IsA('Model') and model.PrimaryPart;if not r then continue end
  local close=(r.Position-camera.CFrame.Position).Magnitude<65
  if model:GetAttribute('Kind')=='cart' then
   local speed=Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude
   local sound=cartSounds[model]
   if close and speed>1 then
    if not sound or not sound.Parent then sound=Audio.Play('CartRoll',r);cartSounds[model]=sound end
    if sound then sound.Volume=math.clamp(speed/16,.15,1)*.12;sound.PlaybackSpeed=math.clamp(speed/10,.65,1.4)end
   elseif sound then Audio.Stop(sound);cartSounds[model]=nil end
  elseif model:GetAttribute('ItemId') and close then
   local data=items[model] or {vy=0,nextTick=0,lastImpact=0};items[model]=data
   if model:GetAttribute('ItemId')=='MusicBox' then
    local sound=musicSounds[model]
    if model:GetAttribute('Playing') then
     if not sound or not sound.Parent then musicSounds[model]=Audio.Play('MusicBox',r,{loop=true})end
    elseif sound then Audio.Stop(sound);musicSounds[model]=nil end
   end
   local velocity=r.AssemblyLinearVelocity
   if not model:GetAttribute('HeldBy') and not model:GetAttribute('CargoStored') and data.vy< -6 and velocity.Y> -2 and now-data.lastImpact>.5 then
    data.lastImpact=now
    local id=model:GetAttribute('ItemId')
    local cue=(id=='DiscoBall' or id=='Lantern' or id=='Telephone') and 'GlassImpact' or (id=='Bell' or id=='Chain' or id=='Keyring' or id=='Vacuum') and 'MetalImpact' or 'ItemImpact'
    Audio.Play(cue,r)
   end
   data.vy=velocity.Y
   if model:GetAttribute('ItemId')=='Clock' and model:GetAttribute('HeldBy') and now>data.nextTick then data.nextTick=now+1;Audio.Play('ClockTick',r)end
  end
 end
 for model,sound in pairs(vocalSounds)do if not model.Parent or not model.PrimaryPart then Audio.Stop(sound);vocalSounds[model]=nil;vocalNext[model]=nil end end
 for model,sound in pairs(cartSounds)do if not model.Parent then Audio.Stop(sound);cartSounds[model]=nil end end
 for model,sound in pairs(musicSounds)do if not model.Parent or not model.PrimaryPart or not model:GetAttribute('Playing') or (model.PrimaryPart.Position-camera.CFrame.Position).Magnitude>65 then Audio.Stop(sound);musicSounds[model]=nil end end
end)
player.CharacterRemoving:Connect(function()Audio.Stop(breath);breath=nil;sprintTime=0;footsteps[player]=nil end)
-- Player footsteps, every frame (2026-10-22). The step samples ring for 0.4-0.7 s, so a sprint (a step every ~0.17 s) used to
-- stack 4-5 copies into a smeared rattle: each step now fades the previous one out and is trimmed to a short, clean hit.
local function fadeStep(sound,after)
 if not sound then return end
 task.delay(after,function()
  if not sound.Parent then return end
  local start=sound.Volume
  for i=1,4 do task.wait(.015);if not sound.Parent then return end;sound.Volume=start*(1-i/4)end
  if sound.Parent then sound:Destroy()end
 end)
end
Run.Heartbeat:Connect(function(dt)
 if player:GetAttribute('MissionActive')~=true then return end
 local camera=workspace.CurrentCamera;if not camera then return end
 local now=os.clock()
 for _,p in Players:GetPlayers()do
  local ch=p.Character;local r=ch and ch:FindFirstChild('HumanoidRootPart');local h=ch and ch:FindFirstChildOfClass('Humanoid')
  if not r or not h then footsteps[p]=nil;continue end
  local data=footsteps[p]
  if not data or data.character~=ch then data={character=ch,pos=r.Position,distance=0,nextStep=0,speed=0};footsteps[p]=data end
  local delta=r.Position-data.pos;data.pos=r.Position
  local moved=Vector3.new(delta.X,0,delta.Z).Magnitude
  local running=r:FindFirstChild('Running');if running and running:IsA('Sound')and running.Volume~=0 then running.Volume=0 end
  -- Smoothed ground speed, so one long frame doesn't flip walk/run sounds back and forth.
  data.speed+=(math.min(moved/math.max(dt,1/240),40)-data.speed)*math.min(1,dt*10)
  if h.Health>0 and h.FloorMaterial~=Enum.Material.Air and not r.Anchored and not p:GetAttribute('Hiding')and not p:GetAttribute('MonsterJumpscareActive')and moved<10 and data.speed>1.5 then
   data.distance+=moved
   local runningFast=data.speed>17
   local stepDistance=runningFast and 3.4 or 4
   if data.distance>=stepDistance and now>data.nextStep and(r.Position-camera.CFrame.Position).Magnitude<42 then
    data.distance%=stepDistance;data.nextStep=now+(runningFast and .14 or .22)
    local wood=h.FloorMaterial==Enum.Material.Wood or h.FloorMaterial==Enum.Material.WoodPlanks
    local cue=runningFast and(wood and 'PlayerRunWood'or 'PlayerRunStone')or(wood and 'PlayerFootstep'or 'PlayerStoneFootstep')
    if data.last then fadeStep(data.last,0)end
    local sound=Audio.Play(cue,r,{volume=p:GetAttribute('QuietSteps')and .06 or runningFast and .27 or .25,speed=(runningFast and 1.06 or .96)+math.random()*.08})
    data.last=sound
    fadeStep(sound,runningFast and .17 or .3)
   end
  else data.distance=math.min(data.distance,1) end
 end
end)
