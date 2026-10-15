local M={}
M.RANGE=26
function M.EyePoint(c)
 local h=c and c:FindFirstChild('Head')
 if not h then return nil end
 local left,right=h:FindFirstChild('LeftEyeball'),h:FindFirstChild('RightEyeball')
 return left and right and (left.Position+right.Position)/2 or h.Position
end
function M.Available(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return p:GetAttribute('MissionActive')==true and h~=nil and h.Health>0
  and not p:GetAttribute('Hiding') and not p:GetAttribute('ClosetState')
  and not p:GetAttribute('MonsterJumpscareActive')
end
function M.CanLook(p,other)
 if p==other or not M.Available(p) or not M.Available(other) then return false end
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