-- Crouch input (C / Left Ctrl, right-stick click, touch CROUCH button) and the mini-body waddle for
-- every crouched player. CrouchServer owns the state; this only asks and animates.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local RunService=game:GetService('RunService')
local player=Players.LocalPlayer
local event=RS:WaitForChild('CrouchEvent')

local function toggle()
 if player:GetAttribute('MissionActive')~=true then return end
 event:FireServer(not player:GetAttribute('Crouching'))
end
UIS.InputBegan:Connect(function(input,processed)
 if processed then return end
 if input.KeyCode==Enum.KeyCode.C or input.KeyCode==Enum.KeyCode.LeftControl or input.KeyCode==Enum.KeyCode.ButtonR3 then toggle() end
end)

-- Touch CROUCH: free slot in the bottom-right grid (third column, bottom row, beside RUN).
local gui=Instance.new('ScreenGui');gui.Name='CrouchGui';gui.ResetOnSpawn=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=player:WaitForChild('PlayerGui')
local button=Instance.new('TextButton');button.Name='CrouchAction';button.AnchorPoint=Vector2.new(1,1)
button.BackgroundColor3=Color3.fromRGB(20,28,26);button.BackgroundTransparency=.35;button.AutoButtonColor=true
button.Font=Enum.Font.GothamMedium;button.TextSize=11;button.TextColor3=Color3.new(1,1,1);button.Text='CROUCH';button.Visible=false;button.Parent=gui
Instance.new('UICorner',button).CornerRadius=UDim.new(0,16)
local stroke=Instance.new('UIStroke');stroke.Thickness=1;stroke.Color=Color3.new(1,1,1);stroke.Transparency=.8;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=button
button.Activated:Connect(toggle)

-- 'No room to stand' when trying to stand up under a desk
local toast=Instance.new('TextLabel');toast.Name='CrouchToast';toast.AnchorPoint=Vector2.new(.5,1);toast.Position=UDim2.new(.5,0,1,-120)
toast.Size=UDim2.fromOffset(240,24);toast.BackgroundTransparency=1;toast.Font=Enum.Font.GothamMedium;toast.TextSize=14
toast.TextColor3=Color3.fromRGB(236,217,176);toast.TextStrokeTransparency=.6;toast.Text='No room to stand up here';toast.Visible=false;toast.Parent=gui
local toastUntil=0
local toastAlpha=0
event.OnClientEvent:Connect(function(what) if what=='blocked' then toastUntil=os.clock()+1.6 end end)

-- The camera follows the root, not the head, so it is lowered separately (Y only; the closet peek owns X/Z).
local CAMERA_DROP=1.75
local camDrop=0
local camDropVel=0 -- spring velocity: the drop starts and stops softly instead of jumping to full speed
local spin=0
local function lerpRate(move) return 3+move*6 end
RunService.RenderStepped:Connect(function(dt)
 do
  local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
  local target=player:GetAttribute('Crouching') and CAMERA_DROP or 0
  if hum and (target>0 or camDrop>.001) then
   local step=math.min(dt,.05);camDropVel+=((target-camDrop)*144-24*camDropVel)*step;camDrop+=camDropVel*step
   if target==0 and camDrop<.01 and math.abs(camDropVel)<.05 then camDrop=0;camDropVel=0 end
   local o=hum.CameraOffset;hum.CameraOffset=Vector3.new(o.X,-camDrop,o.Z)
  end
 end
 local camera=workspace.CurrentCamera
 local small=camera and camera.ViewportSize.Y<500
 button.Visible=player:GetAttribute('MissionActive')==true and InputHints.IsMobile()
 button.Size=UDim2.fromOffset(small and 54 or 64,small and 54 or 64)
 button.Position=UDim2.new(1,small and -146 or -170,1,small and -104 or -282)
 local crouched=player:GetAttribute('Crouching')==true
 button.Text=crouched and 'STAND' or 'CROUCH';button.BackgroundTransparency=crouched and .05 or .35
 toastAlpha+=((os.clock()<toastUntil and 1 or 0)-toastAlpha)*math.min(1,dt*10);toast.Visible=toastAlpha>.01;toast.TextTransparency=1-toastAlpha;toast.TextStrokeTransparency=1-toastAlpha*.4
 -- every crouched player's mini body waddles: a side-to-side rock and a little squash bob, livelier when moving
 spin+=dt
 for _,p in Players:GetPlayers() do
  local c=p.Character
  local body=c and c:FindFirstChild('CrouchBody')
  local motor=body and body:FindFirstChild('CrouchBodyJoint')
  if motor then
   local root=c:FindFirstChild('HumanoidRootPart')
   local speed=root and Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude or 0
   local move=math.clamp(speed/6,0,1)
   local t=spin+(p.UserId%97)
   local rate=lerpRate(move)
   motor.Transform=CFrame.new(0,math.abs(math.sin(t*rate))*.12*move+math.sin(t*1.6)*.02,0)*CFrame.Angles(0,math.sin(t*rate*.5)*.12*move,math.sin(t*rate)*(.05+.13*move))
  end
 end
end)
