local QuestService=require(game:GetService('ServerScriptService'):WaitForChild('QuestService'))
local QuestHttp=game:GetService('HttpService')
local function questContext(eventId,model)
 local s=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 local map=workspace:FindFirstChild('Mansion')
 return {eventId=eventId,runId=s and s:GetAttribute('QuestRunId'),round=s and s:GetAttribute('Round'),generation=s and s:GetAttribute('QuestGeneration'),mapKind=map and map:GetAttribute('MapKind'),admin=model and (model:GetAttribute('AdminEffect')==true or model:GetAttribute('AdminSpawned')==true),lobbyToy=model and model:GetAttribute('LobbyToy')==true,itemId=model and model:GetAttribute('ItemId')}
end
-- Only owner of held keys and the unlock API. MapGen owns placement and lock decisions.
local Players=game:GetService('Players')
local SS=game:GetService('ServerStorage')
local mansion=workspace:WaitForChild('Mansion',math.huge)
while mansion:GetAttribute('Ready')~=true or mansion:GetAttribute('RuntimeReady')~=true do mansion:GetAttributeChangedSignal('RuntimeReady'):Wait() end
local interactive=mansion:WaitForChild('Interactive')
local held={}
local function publish(p) p:SetAttribute('Keys',#(held[p] or {})) end
local api=Instance.new('BindableFunction');api.Name='KeyDoorApi'
api.OnInvoke=function(action,player,model)
 if typeof(player)~='Instance' or not player:IsA('Player') or player.Parent~=Players or typeof(model)~='Instance' or not model:IsA('Model') or model.Parent~=interactive or not model.PrimaryPart then return false end
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if not root or (root.Position-model.PrimaryPart.Position).Magnitude>11 then return false end
 if action=='pickup' then
  if model:GetAttribute('Kind')~='key' then return false end
  local drawerName=model:GetAttribute('DrawerMover')
  if drawerName then
   local drawer=interactive:FindFirstChild(drawerName)
   if not drawer or drawer:GetAttribute('Kind')~='drawer' or (drawer:GetAttribute('Open')or 0)<=.5 then return false end
  end
  held[player]=held[player] or {};table.insert(held[player],model);model.Parent=nil;publish(player);return true
 elseif action=='unlock' then
  if not model:GetAttribute('Locked') then return true end
  local keys=held[player];if not keys or #keys==0 then return false end
  local consumed=table.remove(keys);if not consumed then return false end;consumed:Destroy();publish(player)
  for _,p in ipairs(model:GetChildren()) do if p.Name=='Padlock' then p:Destroy() end end
  model:SetAttribute('Locked',nil);local id=model:GetAttribute('QuestDoorGUID');if not id then id=QuestHttp:GenerateGUID(false);model:SetAttribute('QuestDoorGUID',id)end;QuestService.Record(player,'DoorUnlocked',1,questContext('unlock:'..id,model));return true
 end
 return false
end
api.Parent=SS
Players.PlayerRemoving:Connect(function(p)
 for _,k in ipairs(held[p] or {}) do k.Parent=interactive end;held[p]=nil
end)
Players.PlayerAdded:Connect(publish);for _,p in ipairs(Players:GetPlayers()) do publish(p) end

