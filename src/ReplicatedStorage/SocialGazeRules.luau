local M={}
M.RANGE=26
function M.EyePoint(c)
 local h=c and c:FindFirstChild('Head')
 if not h then return nil end
 local left,right=h:FindFirstChild('LeftEyeball'),h:FindFirstChild('RightEyeball')
 return left and right and (left.Position+right.Position)/2 or h.Position
end
local function context(p)
 if p:GetAttribute('MissionActive')==true then return 'mission' end
 local state=game:GetService('ReplicatedStorage'):FindFirstChild('LobbyState')
 if p:GetAttribute('LobbyReady')==true
  and(p:GetAttribute('ReturnedToLobby')==true or state and state:GetAttribute('Mode')=='Menu')then
  return 'lobby'
 end
 return nil
end
function M.Available(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return context(p)~=nil and h~=nil and h.Health>0 and not p:GetAttribute('RoundDead')
  and not p:GetAttribute('Hiding') and not p:GetAttribute('ClosetState')
  and not p:GetAttribute('MonsterJumpscareActive')
end
function M.CanLook(p,other)
 if p==other or not M.Available(p) or not M.Available(other)or context(p)~=context(other)then return false end
 local origin=M.EyePoint(p.Character);local target=M.EyePoint(other.Character)
 local root=p.Character:FindFirstChild('HumanoidRootPart')
 if not origin or not target or not root then return false end
 local delta=target-origin;local distance=delta.Magnitude
 if distance<1 or distance>M.RANGE or root.CFrame.LookVector:Dot(delta.Unit)<.15 then return false end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances={p.Character,other.Character};params.RespectCanCollide=true
 return workspace:Raycast(origin,delta,params)==nil
end
return M
