-- Cosmetic loudness relay only. Never stores, transcribes, or relays microphone audio.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Voice=game:GetService('VoiceChatService')
local event=RS:WaitForChild('VoiceMouthLevel')
local states={}
local MIN_INTERVAL=1/15

-- Server-owned voice permissions. Dead mission players neither send nor receive live team voice.
local function voiceAlive(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true
  and not (states[p] and states[p].removing) and h~=nil and h.Health>0
end
local function updateVoice()
 for p,s in pairs(states)do
  for input,original in pairs(s.inputs)do
   if not input.Parent then s.inputs[input]=nil;continue end
   if p:GetAttribute('MissionActive')==true then
    local allowed={}
    if voiceAlive(p)then
     for _,listener in Players:GetPlayers()do
      local listed=table.find(original.ids,listener.UserId)~=nil
      local permitted=original.access==Enum.AccessModifierType.Allow and listed or original.access==Enum.AccessModifierType.Deny and not listed
      if voiceAlive(listener)and permitted then table.insert(allowed,listener.UserId)end
     end
    end
    input.AccessType=Enum.AccessModifierType.Allow;input:SetUserIdAccessList(allowed);original.gated=true
    p:SetAttribute('MissionVoiceBlocked',not voiceAlive(p))
   elseif original.gated then
    input:SetUserIdAccessList(original.ids);input.AccessType=original.access;original.gated=false
    p:SetAttribute('MissionVoiceBlocked',false)
   end
  end
 end
end
local function silence(p)
 p:SetAttribute('VoiceNoiseLevel',0);p:SetAttribute('VoiceNoiseAt',0)
 event:FireAllClients(p,0,workspace:GetServerTimeNow(),0)
end

local function join(player)
    local state={eligible=false,last=-math.huge,sequence=-1,inputs={}}
    states[player]=state
    local function inputAdded(input)
     if not input:IsA('AudioDeviceInput')or state.inputs[input]then return end
     state.inputs[input]={access=input.AccessType,ids=input:GetUserIdAccessList()}
     updateVoice()
    end
    player.ChildAdded:Connect(inputAdded)
    for _,input in player:GetChildren()do inputAdded(input)end
    player:GetAttributeChangedSignal('RoundDead'):Connect(function()if player:GetAttribute('RoundDead')then silence(player)end;updateVoice()end)
    player:GetAttributeChangedSignal('MissionActive'):Connect(updateVoice)
    local function characterAdded(c)
     state.removing=false
     local h=c:WaitForChild('Humanoid',12)
     if player.Character~=c or not h then return end
     h.Died:Once(function()if player.Character==c then silence(player);updateVoice()end end)
     updateVoice()
    end
    player.CharacterAdded:Connect(function(c)task.spawn(characterAdded,c)end)
    player.CharacterRemoving:Connect(function()state.removing=true;silence(player);updateVoice()end)
    if player.Character then task.spawn(characterAdded,player.Character)end
    task.spawn(function()
        local ok,enabled=pcall(function() return Voice:IsVoiceEnabledForUserIdAsync(player.UserId) end)
        if states[player]~=state then return end
        state.eligible=ok and enabled==true
        player:SetAttribute('VoiceMouthEligible',state.eligible)
    end)
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player) states[player]=nil;task.defer(updateVoice) end)
for _,player in Players:GetPlayers() do join(player) end
event.OnServerEvent:Connect(function(player,level,sequence,emphasis)
    local state=states[player]
    if not state or not state.eligible then return end
    if type(level)~='number' or level~=level or level<0 or level>1 then return end
    if emphasis==nil then emphasis=0 end
    if type(emphasis)~='number' or emphasis~=emphasis or emphasis<0 or emphasis>1 then return end
    if type(sequence)~='number' or sequence~=sequence or sequence%1~=0 or sequence<0 or sequence>9007199254740991 or sequence<=state.sequence then return end
    local now=os.clock()
    if now-state.last<MIN_INTERVAL then return end
    local character=player.Character
    if not character or not character:GetAttribute('CustomCharacterVersion') then return end
    local humanoid=character:FindFirstChildOfClass('Humanoid')
    if not humanoid or humanoid.Health<=0 or player:GetAttribute('RoundDead')==true then return end
    local input=player:FindFirstChildOfClass('AudioDeviceInput')
    if not input or input.Muted then level=0 end
    player:SetAttribute('VoiceNoiseLevel',level);player:SetAttribute('VoiceNoiseAt',now)
    state.last=now;state.sequence=sequence
    event:FireAllClients(player,level,workspace:GetServerTimeNow(),emphasis)
end)




local trails=Instance.new('Folder');trails.Name='SpitTrails';trails.Parent=workspace
local lastTrail={};local tick=0
game.RunService.Heartbeat:Connect(function(dt)
 tick+=dt;if tick<.5 then return end;tick=0
 local map=workspace:FindFirstChild('Mansion');if not map or not map:GetAttribute('RuntimeReady') then return end
 for _,p in ipairs(Players:GetPlayers()) do
  local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
  local now=os.clock();local voice=(p:GetAttribute('VoiceNoiseLevel') or 0)>.2 and now-(p:GetAttribute('VoiceNoiseAt') or 0)<1
  local running=r and Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude>18
  if r and h and h.Health>0 and not p:GetAttribute('Hiding') and (voice or running) and now-(lastTrail[p] or 0)>(voice and 1.4 or 3) then
   local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map.Collision};params.RespectCanCollide=true
   local hit=workspace:Raycast(r.Position+r.CFrame.LookVector*2,Vector3.new(0,-8,0),params)
   if hit then
    lastTrail[p]=now
    if #trails:GetChildren()>=80 then trails:GetChildren()[1]:Destroy() end
    local mark=Instance.new('Part');mark.Name='SpitTrail';mark.Size=Vector3.new(.05,.65,.45);mark.Shape=Enum.PartType.Cylinder;mark.CFrame=CFrame.new(hit.Position+Vector3.new(0,.032,0))*CFrame.Angles(0,0,math.pi/2);mark.Color=Color3.fromRGB(170,195,173);mark.Material=Enum.Material.SmoothPlastic;mark.Transparency=.42;mark.Anchored=true;mark.CastShadow=false;mark.CanCollide=false;mark.CanQuery=false;mark.CanTouch=false;mark:SetAttribute('BornAt',now);mark:SetAttribute('OwnerUserId',p.UserId);mark.Parent=trails
    task.delay(20,function()if mark.Parent then game.TweenService:Create(mark,TweenInfo.new(10),{Transparency=1}):Play() end end);game.Debris:AddItem(mark,30)
   end
  end
 end
end)
Players.PlayerRemoving:Connect(function(p)lastTrail[p]=nil end)
