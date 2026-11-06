-- One owner for player health (2026-10-22). Every player has 100 HP, Roblox's own health bars are hidden (the HP bar is
-- ours, in SprintController) and every change goes through Damage / Heal / Restore with a source, so the game always knows
-- what hurt or healed someone: the player carries LastHealthSource / LastHealthChange / LastHealthAt, and the last 20
-- changes are kept in History(p). A kill is still presented by the monster's jumpscare (MonsterJumpscare.Start sets 0).
local Players=game:GetService('Players')
local Workspace=game:GetService('Workspace')
local MAX_HEALTH=100

local M={MaxHealth=MAX_HEALTH}
local history=setmetatable({},{__mode='k'})

local function humanoidOf(p)
 local c=p and p.Character
 return c and c:FindFirstChildOfClass('Humanoid')
end
local function record(p,h,delta,source)
 p:SetAttribute('LastHealthSource',source);p:SetAttribute('LastHealthChange',delta);p:SetAttribute('LastHealthAt',Workspace:GetServerTimeNow())
 local list=history[p] or {};history[p]=list
 table.insert(list,{at=Workspace:GetServerTimeNow(),delta=delta,source=source,health=h.Health})
 if #list>20 then table.remove(list,1)end
end

-- Takes `amount` HP. Returns the new health, or nil when nothing was applied (no character, already dead).
function M.Damage(p,amount,source)
 local h=humanoidOf(p);if not h or h.Health<=0 or type(amount)~='number' or amount<=0 then return nil end
 h.Health=math.max(0,h.Health-amount)
 record(p,h,-amount,tostring(source or 'unknown'))
 return h.Health
end
-- Gives back up to `amount` HP (never above MaxHealth). Returns the HP actually restored.
function M.Heal(p,amount,source)
 local h=humanoidOf(p);if not h or h.Health<=0 or type(amount)~='number' or amount<=0 then return 0 end
 local before=h.Health
 h.Health=math.min(h.MaxHealth,h.Health+amount)
 local gained=h.Health-before
 if gained>0 then record(p,h,gained,tostring(source or 'unknown'))end
 return gained
end
-- Full health (revives, new levels).
function M.Restore(p,source)
 local h=humanoidOf(p);if not h then return end
 local before=h.Health;h.Health=h.MaxHealth
 record(p,h,h.Health-before,tostring(source or 'restore'))
end
function M.History(p)return table.clone(history[p] or {})end

-- Every character: 100 max HP and no Roblox overhead health bar.
local function setup(character)
 local h=character:WaitForChild('Humanoid',10);if not h then return end
 h.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOff
 if h.MaxHealth~=MAX_HEALTH then local frac=h.Health/math.max(1,h.MaxHealth);h.MaxHealth=MAX_HEALTH;h.Health=MAX_HEALTH*frac end
end
local function watch(p)
 p.CharacterAdded:Connect(setup)
 if p.Character then task.spawn(setup,p.Character)end
end
Players.PlayerAdded:Connect(watch) -- a ModuleScript runs once per server, so this is wired once
for _,p in Players:GetPlayers()do watch(p)end
return M
