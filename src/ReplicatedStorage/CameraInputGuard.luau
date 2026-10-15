-- When a Modal panel closes in first person, Roblox re-locks the cursor to screen centre and reads that
-- warp as one huge mouse delta, snapping the camera toward where the cursor was. Muting camera rotation
-- for a moment around the close swallows the warp. Client only.
local M={}
local muteUntil=0;local restoring=false
local function rotationAction()
 local module=game:GetService('StarterPlayer'):FindFirstChild('PlayerModule')
 local contexts=module and module:FindFirstChild('InputContexts')
 local context=contexts and contexts:FindFirstChild('CameraContext')
 return context and context:FindFirstChild('CameraRotationAction')
end
function M.Mute(seconds)
 local action=rotationAction();if not action or not action:IsA('InputAction')then return end
 -- Only restore what we changed, so CameraInput.setInputEnabled keeps ownership of the real state.
 if action:GetAttribute('GuardMuted')~=true then
  if not action.Enabled then return end
  action:SetAttribute('GuardMuted',true);action.Enabled=false
 end
 muteUntil=math.max(muteUntil,os.clock()+(seconds or .35))
 if restoring then return end;restoring=true
 task.spawn(function()
  while os.clock()<muteUntil do task.wait()end
  restoring=false
  if action:GetAttribute('GuardMuted')then action:SetAttribute('GuardMuted',nil);action.Enabled=true end
 end)
end
return M
