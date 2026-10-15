local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local event=RS:WaitForChild('MonsterJumpscare')
local DURATION=1.3
local active={}
local serial=0
local M={}
local Protection=require(game.ServerScriptService:WaitForChild('MonsterProtection'))
local function finish(p,s)
 if active[p]~=s then return end
 active[p]=nil
 if s.root.Parent then s.root.Anchored=s.anchored end
 if s.hum.Parent then s.hum.AutoRotate=s.autoRotate end
 if p.Parent then p:SetAttribute('MonsterJumpscareActive',nil);event:FireClient(p,'end',s.token) end
 if s.connection then s.connection:Disconnect() end
end
-- Reach is measured flat (tall creatures like the Neon Tripod carry their root far above a player's) and
-- matches CreatureRoamServer's CATCH_RANGE, so a grab the AI starts is never refused here.
function M.InReach(a,b)return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude<=7.5 and math.abs(a.Y-b.Y)<12 end
function M.Start(p,monster)
 if active[p] or Protection.IsProtected(p) then return false end
 local c=p.Character;local root=c and c:FindFirstChild('HumanoidRootPart');local hum=c and c:FindFirstChildOfClass('Humanoid')
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if not root or not hum or hum.Health<=0 or not monster or monster.Parent~=folder or not monster.PrimaryPart or not M.InReach(root.Position,monster.PrimaryPart.Position) then return false end
 serial+=1
 local round=RS:FindFirstChild('RecoveryRound')
 local s={character=c,root=root,hum=hum,anchored=root.Anchored,autoRotate=hum.AutoRotate,token=serial,round=round and round:GetAttribute('Round'),started=workspace:GetServerTimeNow()}
 active[p]=s;p:SetAttribute('MonsterJumpscareActive',true)
 local items=SS:FindFirstChild('CursedItemApi');if items then items:Invoke('release',p) end
 local recovery=SS:FindFirstChild('RecoveryApi');if recovery then recovery:Invoke('release',p) end
 p:SetAttribute('PhysicalGrabActive',nil)
 root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero;root.Anchored=true;hum.AutoRotate=false
 s.connection=p.CharacterRemoving:Connect(function(removing)if removing==c then finish(p,s) end end)
 event:FireClient(p,'start',s.token,monster,s.started,DURATION)
 task.spawn(function()
  while active[p]==s and workspace:GetServerTimeNow()-s.started<DURATION do
   if Protection.IsProtected(p) or not p.Parent or p.Character~=c or not c.Parent or hum.Health<=0 or not monster.Parent or (round and round:GetAttribute('Round')~=s.round) then finish(p,s);return end
   task.wait(.04)
  end
  if active[p]~=s then return end
  if not Protection.IsProtected(p) and p.Character==c and hum.Parent and hum.Health>0 then hum.Health=0 end
  finish(p,s)
 end)
 return true
end
-- Nuisance hit presentation: no kill, forced release, anchoring or movement lock.
function M.Hit(p,monster)
 if active[p]or Protection.IsProtected(p)then return false end
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local root=c and c:FindFirstChild('HumanoidRootPart')
 if not h or h.Health<=0 or not root or not monster or not monster.Parent or not monster.PrimaryPart
  or monster:GetAttribute('CreatureKind')~='Skitter'or not M.InReach(root.Position,monster.PrimaryPart.Position)then return false end
 serial+=1;event:FireClient(p,'hit',serial,monster,workspace:GetServerTimeNow(),.45)
 return true
end
Players.PlayerRemoving:Connect(function(p)local s=active[p];if s then finish(p,s) end end)
return M
