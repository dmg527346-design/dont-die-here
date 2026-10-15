-- Real client screenshot on the printed stomach card. Temporary capture content stays local;
-- it is neither an uploaded asset nor a replicated screenshot for other players.
local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local Run = game:GetService('RunService')
local Capture = game:GetService('CaptureService')
local player = Players.LocalPlayer
local CAPTURE_TIMEOUT = 4
local PHOTO_DISTANCE = 5.2
local PHOTO_FOV = 38
local cachedSubject, cachedContent
local requestGeneration = 0
local activeRestore

RS:WaitForChild('CursedEvent').OnClientEvent:Connect(function(action, card, subject)
 if action ~= 'cameraPrint' then return end
 if typeof(card) ~= 'Instance' or not card:IsA('BasePart') then return end
 if typeof(subject) ~= 'Instance' or not subject:IsA('Player') then return end
 requestGeneration+=1
 local request=requestGeneration
 if activeRestore then activeRestore()end
 local surface = card:FindFirstChild('PhotoGui') or card:WaitForChild('PhotoGui',3)
 local image = surface and (surface:FindFirstChild('LivePhoto') or surface:WaitForChild('LivePhoto',3))
 if request~=requestGeneration or not image or not image:IsA('ImageLabel') then return end
 if cachedSubject == subject.UserId and cachedContent then image.Image=cachedContent;image.Visible=true;return end
 local character = subject.Character
 local head = character and character:FindFirstChild('Head')
 local camera = workspace.CurrentCamera
 if not head or not camera then return end
 local oldType,oldCF,oldFocus,oldFOV,oldSubject = camera.CameraType,camera.CFrame,camera.Focus,camera.FieldOfView,camera.CameraSubject
 image:SetAttribute('CameraTypeBeforeCapture',oldType.Name)
 local closed = false
 local renderConnection
 local visibility = {}
 for _,part in ipairs(character:GetDescendants())do
  if part:IsA('BasePart')then visibility[part]=part.LocalTransparencyModifier end
 end
 local function restore()
  if closed then return end
  closed=true
  if renderConnection then renderConnection:Disconnect()end
  for part,previous in pairs(visibility)do if part.Parent then part.LocalTransparencyModifier=previous end end
  if workspace.CurrentCamera == camera then
   camera.CFrame=oldCF;camera.Focus=oldFocus;camera.FieldOfView=oldFOV
   if oldSubject and oldSubject.Parent then camera.CameraSubject=oldSubject end
   camera.CameraType=oldType
  end
  if image.Parent then image:SetAttribute('CameraRestoreAttempted',true);image:SetAttribute('CameraRestored',workspace.CurrentCamera==camera and camera.CameraType==oldType)end
  if activeRestore==restore then activeRestore=nil end
 end
 activeRestore=restore
 local function pose()
  if closed or request~=requestGeneration or not head.Parent then return end
  -- This game's face front is local +Z. Use the actual live head and scene, never a clone.
  local focus = head.Position + head.CFrame.UpVector*.8
  camera.CFrame=CFrame.lookAt(focus-head.CFrame.LookVector*PHOTO_DISTANCE+head.CFrame.UpVector*.3,focus)
  camera.Focus=CFrame.new(focus)
  for part in pairs(visibility)do if part.Parent then part.LocalTransparencyModifier=0 end end
 end
 camera.CameraType=Enum.CameraType.Scriptable;camera.FieldOfView=PHOTO_FOV
 pose()
 renderConnection=Run.PreRender:Connect(pose)
 task.delay(CAPTURE_TIMEOUT,function()
  if not closed and request==requestGeneration then
   restore()
   if image.Parent then image:SetAttribute('CaptureFailed',true)end
  end
 end)
 -- Two frames let the real scene render at the portrait camera before capture.
 Run.PreRender:Wait();Run.PreRender:Wait()
 if closed or request~=requestGeneration or not card.Parent or not head.Parent then restore();return end
 local ok=pcall(function()
  Capture:CaptureScreenshot(function(contentId)
   if closed or request~=requestGeneration then return end
   if typeof(contentId)=='string' and #contentId>0 then
    cachedSubject,cachedContent=subject.UserId,contentId
    if image.Parent then image.Image=contentId;image.Visible=true;image:SetAttribute('CaptureReady',true)end
   elseif image.Parent then image:SetAttribute('CaptureFailed',true)end
   restore()
  end)
 end)
 if not ok and not closed and request==requestGeneration then
  if image.Parent then image:SetAttribute('CaptureFailed',true)end
  restore()
 end
end)

player:GetAttributeChangedSignal('PhotoOf'):Connect(function()
 if player:GetAttribute('PhotoOf')==nil then
  requestGeneration+=1;if activeRestore then activeRestore()end
  cachedSubject=nil;cachedContent=nil
 end
end)

