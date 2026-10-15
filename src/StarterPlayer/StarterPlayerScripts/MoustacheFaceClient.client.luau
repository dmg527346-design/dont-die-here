local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local p=Players.LocalPlayer
local model,copy
local function clear()if model and model.Parent then for _,x in model:GetDescendants()do if x:IsA('BasePart')then x.LocalTransparencyModifier=0 end end end;if copy then copy:Destroy()end;copy=nil;model=nil end
Run:BindToRenderStep('MoustacheFaceView',Enum.RenderPriority.Camera.Value+5,function()
 local map=workspace:FindFirstChild('Mansion')
 if map and map:FindFirstChild('Interactive')then for _,item in map.Interactive:GetChildren()do local id=item:GetAttribute('FaceOwner');local owner=id and Players:GetPlayerByUserId(id);local head=owner and owner.Character and owner.Character:FindFirstChild('Head');if head then item:PivotTo(head.CFrame*CFrame.new(0,.55,.75)*CFrame.Angles(0,math.pi,0))end end end
 local cam=workspace.CurrentCamera;local ch=p.Character;local h=ch and ch:FindFirstChildOfClass('Humanoid')
 local map=workspace:FindFirstChild('Mansion');local target
 if cam and h and h.Health>0 and map then for _,m in map.Interactive:GetChildren()do if m:GetAttribute('FaceOwner')==p.UserId then target=m;break end end end
 if not target then clear();return end
 if model~=target then
  clear();model=target;copy=target:Clone();copy.Name='MoustacheFaceView'
  for _,x in copy:GetDescendants()do
   if x:IsA('JointInstance')or x:IsA('Constraint')or x:IsA('LuaSourceContainer')or x:IsA('LayerCollector')or x:IsA('Highlight')then x:Destroy()
   elseif x:IsA('BasePart')then x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.LocalTransparencyModifier=0 end
  end
  copy.Parent=cam
 end
 local first=(cam.CFrame.Position-ch.Head.Position).Magnitude<2
 copy.Parent=first and cam or nil
 if first then
  local distance=1.35
  local bottom=math.tan(math.rad(cam.FieldOfView*.5))*distance*.87
  copy:PivotTo(cam.CFrame*CFrame.new(0,-bottom,-distance))
  for _,x in target:GetDescendants()do if x:IsA('BasePart')then x.LocalTransparencyModifier=1 end end
 else
  for _,x in target:GetDescendants()do if x:IsA('BasePart')then x.LocalTransparencyModifier=0 end end
 end
end)
p.CharacterRemoving:Connect(clear)
