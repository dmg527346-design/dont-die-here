-- Lobby movement is initialized by SprintController before its mission-only gate.
-- It never changes the camera or creates first-person hands.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local RS=game:GetService('ReplicatedStorage')
local InputHints=require(RS:WaitForChild('InputHints'))
local WALK_SPEED=24
local SPRINT_SPEED=40
local BASE_STAMINA=100
local DRAIN_PER_SEC=25
local REGEN_PER_SEC=15
local REGEN_DELAY=1
local MIN_TO_START=10
local BAR_WIDTH=220
local BAR_HEIGHT=10
local DESKTOP_BAR_BOTTOM=64
local SMALL_VIEW_HEIGHT=500
local TOUCH_SMALL_SIZE=54
local TOUCH_SIZE=64
local TOUCH_SMALL_X=-84
local TOUCH_X=-96
local TOUCH_SMALL_Y=-104
local TOUCH_Y=-282
local Module={}
local started=false
function Module.Start(owner)
 if started then return end;started=true
 local player=Players.LocalPlayer
 local state=RS:WaitForChild('LobbyState')
 local held=false;local sprinting=false;local stamina=BASE_STAMINA;local lastUse=0;local lastActive=false
 local function active()
  return state:GetAttribute('Mode')=='Menu' and player:GetAttribute('MissionActive')~=true and player:GetAttribute('LobbyReady')==true
 end
 local function maxStamina()
  local value=player:GetAttribute('MaxStamina')
  return type(value)=='number' and value==value and value>0 and value<math.huge and value or BASE_STAMINA
 end
 local function reset()
  held=false;sprinting=false;stamina=maxStamina();lastUse=0
 end
 local function setSprintHeld(value)
  if not active()then held=false;return false end
  held=value==true;return true
 end
 local gui=Instance.new('ScreenGui');gui.Name='LobbySprintHud';gui.ResetOnSpawn=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.DisplayOrder=20;gui.Enabled=false;gui.Parent=player:WaitForChild('PlayerGui')
 local back=Instance.new('Frame');back.Name='Stamina';back.AnchorPoint=Vector2.new(0,1);back.Size=UDim2.fromOffset(BAR_WIDTH,BAR_HEIGHT);back.BackgroundColor3=Color3.fromRGB(16,22,20);back.BackgroundTransparency=.35;back.BorderSizePixel=0;back.Parent=gui;Instance.new('UICorner',back).CornerRadius=UDim.new(0,5)
 local fill=Instance.new('Frame');fill.Name='Fill';fill.Size=UDim2.fromScale(1,1);fill.BackgroundColor3=Color3.fromRGB(224,146,57);fill.BorderSizePixel=0;fill.Parent=back;Instance.new('UICorner',fill).CornerRadius=UDim.new(0,5)
 local caption=Instance.new('TextLabel');caption.Name='Caption';caption.Position=UDim2.fromOffset(0,-23);caption.Size=UDim2.fromOffset(BAR_WIDTH,18);caption.BackgroundTransparency=1;caption.Font=Enum.Font.GothamMedium;caption.TextSize=11;caption.TextColor3=Color3.fromRGB(244,222,184);caption.TextXAlignment=Enum.TextXAlignment.Left;caption.Text='STAMINA';caption.Parent=back
 local runButton=Instance.new('TextButton');runButton.Name='LobbyRunAction';runButton.AnchorPoint=Vector2.new(1,1);runButton.BackgroundColor3=Color3.fromRGB(30,35,27);runButton.BackgroundTransparency=.35;runButton.AutoButtonColor=true;runButton.Font=Enum.Font.GothamMedium;runButton.TextSize=12;runButton.TextColor3=Color3.fromRGB(244,222,184);runButton.Text='RUN';runButton.Visible=false;runButton.Parent=gui;Instance.new('UICorner',runButton).CornerRadius=UDim.new(0,16)
 local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(224,146,57);stroke.Transparency=.55;stroke.Thickness=1;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=runButton
 if game:GetService('GuiService'):IsTenFootInterface()then local tv=Instance.new('UIScale');tv.Name='TvScale';tv.Scale=1.4;tv.Parent=back end -- consoles: 40% bigger on a TV
 local function layout()
  local camera=workspace.CurrentCamera
  local small=camera and camera.ViewportSize.Y<SMALL_VIEW_HEIGHT
  local touch=InputHints.Get()=='touch'
  caption.Visible=not touch
  back.Position=touch and UDim2.new(.5,-BAR_WIDTH/2,1,-28) or UDim2.new(0,16,1,-DESKTOP_BAR_BOTTOM)
  runButton.Size=UDim2.fromOffset(small and TOUCH_SMALL_SIZE or TOUCH_SIZE,small and TOUCH_SMALL_SIZE or TOUCH_SIZE)
  runButton.Position=UDim2.new(1,small and TOUCH_SMALL_X or TOUCH_X,1,small and TOUCH_SMALL_Y or TOUCH_Y)
  runButton.Visible=gui.Enabled and touch
 end
 UIS.InputBegan:Connect(function(input,processed)
  if processed or UIS:GetFocusedTextBox()then return end
  if input.KeyCode==Enum.KeyCode.LeftShift or input.KeyCode==Enum.KeyCode.ButtonL3 then setSprintHeld(true)end
 end)
 UIS.InputEnded:Connect(function(input)
  if input.KeyCode==Enum.KeyCode.LeftShift or input.KeyCode==Enum.KeyCode.ButtonL3 then setSprintHeld(false)end
 end)
 UIS.WindowFocusReleased:Connect(function()setSprintHeld(false)end)
 runButton.Activated:Connect(function()setSprintHeld(not held)end)
 player.CharacterAdded:Connect(reset)
 local function modeChanged()
  local enabled=active()
  if not enabled or not lastActive then reset()end
  lastActive=enabled;gui.Enabled=enabled;layout()
 end
 state:GetAttributeChangedSignal('Mode'):Connect(modeChanged)
 player:GetAttributeChangedSignal('MissionActive'):Connect(modeChanged)
 player:GetAttributeChangedSignal('LobbyReady'):Connect(modeChanged)
 InputHints.Changed:Connect(layout)
 Run.RenderStepped:Connect(function(dt)
  if not active()then gui.Enabled=false;return end
  local character=player.Character
  local humanoid=character and character:FindFirstChildOfClass('Humanoid')
  if not humanoid or humanoid.Health<=0 then reset();gui.Enabled=false;return end
  gui.Enabled=player:GetAttribute('InspectActive')~=true -- the lobby inspect camera (InspectCamera) hides the HUD
  local max=maxStamina();stamina=math.min(stamina,max)
  local moving=humanoid.MoveDirection.Magnitude>.1
  local blocked=player:GetAttribute('SprintBlocked') or player:GetAttribute('Crouching')
  if sprinting then
   if not(held and moving) or stamina<=0 or blocked then sprinting=false end
  elseif held and moving and stamina>=MIN_TO_START and not blocked then sprinting=true end
  if sprinting then
   stamina=player:GetAttribute('Pass_infinite_stamina') and max or math.max(0,stamina-DRAIN_PER_SEC*dt);lastUse=os.clock()
  elseif os.clock()-lastUse>=REGEN_DELAY then stamina=math.min(max,stamina+REGEN_PER_SEC*dt)end
  local multiplier=player:GetAttribute('CursedSpeedMultiplier')
  if type(multiplier)~='number' or multiplier~=multiplier or multiplier<=0 or multiplier==math.huge then multiplier=1 end
  humanoid.WalkSpeed=(sprinting and SPRINT_SPEED or WALK_SPEED)*multiplier
  fill.Size=UDim2.fromScale(stamina/max,1)
  runButton.Text=held and 'WALK' or 'RUN';runButton.BackgroundTransparency=held and .05 or .35
  layout()
 end)
 if Run:IsStudio()then
  local api=Instance.new('BindableFunction');api.Name='LobbySprintTestApi';api.Parent=owner
  api.OnInvoke=function(action,value)
   if action=='sprint'then return setSprintHeld(value)
   elseif action=='state'then return {active=active(),held=held,sprinting=sprinting,stamina=stamina,maxStamina=maxStamina()}end
   return false
  end
 end
 modeChanged()
end
return Module
