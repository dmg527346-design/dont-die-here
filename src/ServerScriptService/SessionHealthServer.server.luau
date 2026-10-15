-- Runtime health survives mission-owner restarts; RunSavesService owns durable run-slot snapshots.
local Players=game:GetService('Players')
local RunSaves=require(game.ServerScriptService:WaitForChild('RunSavesService'))
local HEALTH_ATTRIBUTE='RecoverySessionHealth'
local bound={}
local function bindPlayer(p)
 if bound[p]then return end
 bound[p]=true
 local function characterAdded(c)
  local function stopNaturalRegen(child)
   if child.Name=='Health'and child:IsA('Script')then child.Enabled=false end
  end
  for _,child in c:GetChildren()do stopNaturalRegen(child)end
  c.ChildAdded:Connect(stopNaturalRegen)
  local h=c:WaitForChild('Humanoid',12)
  if not h or p.Character~=c then return end
  local saved=p:GetAttribute(HEALTH_ATTRIBUTE)
  -- A living survivor keeps damage; a dead player still uses the existing respawn/revive rules.
  if type(saved)=='number'and saved==saved and saved>0 then h.Health=math.min(h.MaxHealth,saved)end
  p:SetAttribute(HEALTH_ATTRIBUTE,h.Health)
  h.HealthChanged:Connect(function()
   if p.Character==c then p:SetAttribute(HEALTH_ATTRIBUTE,h.Health);RunSaves.MarkHealthChanged(p)end
  end)
 end
 p.CharacterAdded:Connect(characterAdded)
 p.CharacterRemoving:Connect(function(c)
  if p.Character~=c then return end
  local h=c:FindFirstChildOfClass('Humanoid')
  if h then p:SetAttribute(HEALTH_ATTRIBUTE,h.Health);RunSaves.MarkHealthChanged(p)end
 end)
 if p.Character then task.spawn(characterAdded,p.Character)end
end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(p)bound[p]=nil end)
for _,p in Players:GetPlayers()do bindPlayer(p)end
