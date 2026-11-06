-- VR client extension. Required only after the headset-only bootstrap gate.
local Players = game:GetService('Players')
local VR = game:GetService('VRService')
local Run = game:GetService('RunService')
local RS = game:GetService('ReplicatedStorage')
local GS = game:GetService('GuiService')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer
local M = {}
local remote
local contact, contactOffset
local contactHeld,contactAt=false,0
local started = false
local lastSend = 0

function M.Head()
 local camera = workspace.CurrentCamera
 return camera and camera:GetRenderCFrame() or CFrame.identity
end

function M.Hand(side)
 local camera = workspace.CurrentCamera
 if not camera or not VR:GetUserCFrameEnabled(side) then return nil end
 local tracking = VR:GetUserCFrame(side)
 return camera.CFrame * (CFrame.new(tracking.Position * camera.HeadScale) * tracking.Rotation)
end

function M.MenuOpen()
 if GS.MenuIsOpen or UIS:GetFocusedTextBox() then return true end
 local selected=GS.SelectedObject
 if selected then
  local visible=true
  local object=selected
  while object and object~=player.PlayerGui do
   if object:IsA('GuiObject') and not object.Visible or object:IsA('LayerCollector') and not object.Enabled then visible=false;break end
   object=object.Parent
  end
  if visible and object==player.PlayerGui then return true end
 end
 for _, key in {'AppearanceOpen','VanShopOpen','VanRewardsOpen','AdminPassPanelOpen','AdminPowersPanelOpen','MapOpen'} do
  if player:GetAttribute(key) then return true end
 end
 local neon = RS:FindFirstChild('NeonUI')
 return neon ~= nil and require(neon).IsFocused()
end

function M.ClearContact()
 contact,contactOffset=nil,nil
 contactHeld=false
end

local function distanceToPart(part, point)
 local q = part.CFrame:PointToObjectSpace(point)
 local half = part.Size * .5
 local closest = Vector3.new(math.clamp(q.X,-half.X,half.X), math.clamp(q.Y,-half.Y,half.Y), math.clamp(q.Z,-half.Z,half.Z))
 return (q-closest).Magnitude
end

function M.Nearby(folder)
 local hand = M.Hand(Enum.UserCFrame.RightHand)
 if not hand or M.MenuOpen() then return nil end
 local best, distance = nil, .45 -- Palm-sized contact, rather than distance grabbing.
 local params = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances = {player.Character, workspace.CurrentCamera}
 params.RespectCanCollide = true
 for _, model in folder:GetChildren() do
  local kind = model:GetAttribute('Kind')
  if model:IsA('Model') and model.PrimaryPart and (model.PrimaryPart.Position-M.Head().Position).Magnitude<10 and (kind=='pickup' or kind=='cart') and not model:GetAttribute('HeldBy') and not model:GetAttribute('ItemWearOwner') then
   for _, part in model:GetDescendants() do
    if part:IsA('BasePart') and part.Transparency < 1 then
     local d = distanceToPart(part,hand.Position)
     if d < distance then
      local delta = part.Position-hand.Position
      local hit = workspace:Raycast(hand.Position,delta,params)
      if not hit or hit.Instance:IsDescendantOf(model) then best,distance=model,d end
     end
    end
   end
  end
 end
 return best
end

function M.Contact(model)
 local hand = M.Hand(Enum.UserCFrame.RightHand)
 if not hand or not model or not model.PrimaryPart then return false end
 contact,contactOffset = model,hand:ToObjectSpace(model.PrimaryPart.CFrame)
 contactHeld=false;contactAt=os.clock()
 remote:FireServer('contact',M.Head(),hand,model)
 return true
end

function M.Release()
 if not contact then return end
 local hand = M.Hand(Enum.UserCFrame.RightHand)
 if hand then remote:FireServer('release',M.Head(),hand,contact) end
 -- Glued/stuck items keep following the hand until the original item owner confirms release.
 if not contactHeld then M.ClearContact() end
end

function M.ItemPose(model)
 local hand = M.Hand(Enum.UserCFrame.RightHand)
 if hand and contact==model and contactOffset then return hand*contactOffset end
 return nil
end

function M.Start()
 if started then return end
 started=true
 remote=RS:WaitForChild('DDHVRTracking')
 local hints=require(RS:WaitForChild('InputHints'))
 -- Keep the existing owners' controller paths active even if a mouse moves in the headset mirror.
 hints.Get=function() return 'pad' end
 local originalButton=hints.Button
 hints.Button=function(key)
  if key=='ButtonR2' or key=='ButtonR1' then return 'RIGHT GRIP' end
  if key=='ButtonL1' then return 'LEFT GRIP' end
  return originalButton(key)
 end
 -- The existing PadText tokenizer calls hints.Button, so whole button tokens get VR names.
 local hold=require(RS:WaitForChild('HoldPose'))
 local original=hold.Item
 hold.Item=function(camera,grip,model)
  return M.ItemPose(model) or original(camera,grip,model)
 end
 local preferences=require(RS:WaitForChild('HorrorPreferences'))
 local originalGet=preferences.Get
 preferences.Get=function(key)
  if key=='CameraMotion' or key=='FlashingLights' or key=='SpitEffects' then return false end
  return originalGet(key)
 end
 VR.LaserPointer=Enum.VRLaserPointerMode.Pointer
 VR.ControllerModels=Enum.VRControllerModelMode.Transparent
 VR.FadeOutViewOnCollision=true
 Run.PreRender:Connect(function()
  local now=os.clock()
  if contact then
   if contact.Parent and contact:GetAttribute('HeldBy')==player.UserId then contactHeld=true
   elseif contactHeld or not contact.Parent or now-contactAt>1 then M.ClearContact() end
  end
  if now-lastSend>=1/30 then
   lastSend=now
   local hand=M.Hand(Enum.UserCFrame.RightHand)
   if hand then remote:FireServer('tracking',M.Head(),hand) end
  end
 end)
 -- Losing tracking releases through the existing item owner; no item remains attached to a stale hand.
 VR.UserCFrameEnabled:Connect(function(side,enabled)
  if side==Enum.UserCFrame.RightHand and not enabled then M.Release() end
 end)
 player.CharacterRemoving:Connect(M.Release)
end

return M
