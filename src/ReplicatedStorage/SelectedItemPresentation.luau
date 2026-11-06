-- Stateless scheduling: called by the existing CursedItemsClient render owner.
local M={}
local Players=game:GetService('Players')
local self=Players.LocalPlayer
local active={}
local nextScan=0
local function remove(m,s)
 if m.Parent then m:SetAttribute('SelectedVisualAtHand',nil)end
 for e,old in s.emitters do if e.Parent then e.Enabled=old end end
 for q,old in s.hidden do if q.Parent then q.LocalTransparencyModifier=old end end
 if s.copy then s.copy:Destroy()end;active[m]=nil
end
local function make(m)
 local copy=m:Clone();copy.Name='SelectedHeldVisual';local pairsList={};local hidden={}
 for _,q in copy:GetDescendants()do
  if q:IsA('LuaSourceContainer')or q:IsA('Sound')or q:IsA('ParticleEmitter')or q:IsA('Beam')or q:IsA('JointInstance')or q:IsA('Constraint')or q:IsA('BillboardGui')or q:IsA('Highlight')then q:Destroy()
  elseif q:IsA('BasePart')then q.Anchored=true;q.CanCollide=false;q.CanTouch=false;q.CanQuery=false
   local original=m:FindFirstChild(q.Name,true)
   if original and original:IsA('BasePart')then pairsList[#pairsList+1]={real=original,copy=q}end
  end
 end
 for _,q in m:GetDescendants()do if q:IsA('BasePart')then hidden[q]=q.LocalTransparencyModifier;q.LocalTransparencyModifier=1 end end
 if m:GetAttribute('ItemId')=='BackwardsHairdryer'then
  local nozzle=copy:FindFirstChild('Nozzle',true)
  if nozzle then
   local a=Instance.new('Attachment');a.Name='PresentationWind';a.Position=Vector3.new(0,0,-nozzle.Size.Z*.45);a.Parent=nozzle
   local e=Instance.new('ParticleEmitter');e.Name='Wind';e.Texture='rbxasset://textures/particles/smoke_main.dds';e.EmissionDirection=Enum.NormalId.Front
   e.Speed=NumberRange.new(12,18);e.Lifetime=NumberRange.new(.18,.35);e.Rate=42;e.SpreadAngle=Vector2.new(8,8)
   e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.08),NumberSequenceKeypoint.new(.45,.25),NumberSequenceKeypoint.new(1,.42)})
   e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,1)});e.Color=ColorSequence.new(Color3.fromRGB(210,241,250));e.LightEmission=.25;e.Parent=a
  end
 end
 copy.Parent=workspace
 return {copy=copy,pairs=pairsList,hidden=hidden,emitters={}}
end
function M.Update()
 local now=workspace:GetServerTimeNow()
 if now>=nextScan then
  nextScan=now+.1
  local mansion=workspace:FindFirstChild('Mansion');local folder=mansion and mansion:FindFirstChild('Interactive')
  if folder then for _,m in folder:GetChildren()do
   if m:IsA('Model')and m.PrimaryPart and m:GetAttribute('SelectedItem')==true then
    local holder=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
    if holder and holder~=self and holder:GetAttribute('DraftSelectedItem')==m:GetAttribute('ItemId')and now<(holder:GetAttribute('DraftSelectedUntil')or 0)then
     if not active[m]then active[m]=make(m)end
    end
   end
  end end
 end
 for m,s in active do
  local holder=m.Parent and Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
  local c=holder and holder.Character;local hand=c and c:FindFirstChild('LeftHand');local root=c and c:FindFirstChild('HumanoidRootPart')
  if not hand or not root or holder==self or now>=(holder:GetAttribute('DraftSelectedUntil')or 0)or holder:GetAttribute('DraftSelectedItem')~=m:GetAttribute('ItemId')or m:GetAttribute('CargoStored')then remove(m,s);continue end
  for _,e in m:GetDescendants()do if e:IsA('ParticleEmitter')then if s.emitters[e]==nil then s.emitters[e]=e.Enabled end;e.Enabled=false end end
  local pose=CFrame.new(hand.Position)*root.CFrame.Rotation
  local id=m:GetAttribute('ItemId')
  if id=='BackwardsHairdryer'then pose*=CFrame.Angles(0,math.pi,0)
  elseif id=='NoseyMagnifier'then pose*=CFrame.new(0,.08,-.12)
  else pose*=CFrame.new(0,.03,-.12)end
  local realRoot=m.PrimaryPart.CFrame
  for _,q in s.pairs do if q.copy.Parent and q.real.Parent then q.copy.Size=q.real.Size;q.copy.CFrame=pose*realRoot:ToObjectSpace(q.real.CFrame);q.copy.Transparency=q.real.Transparency end end
  m:SetAttribute('SelectedVisualAtHand',true)
 end
end
return M
