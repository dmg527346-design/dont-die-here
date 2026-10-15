local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local Preferences=require(game.ReplicatedStorage:WaitForChild('HorrorPreferences'))
local missionPlayer=game:GetService('Players').LocalPlayer
require(script:WaitForChild('LobbySprint')).Start(script)
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WALK_SPEED = 12
local SPRINT_SPEED = 20
local MAX_STAMINA = missionPlayer:GetAttribute('MaxStamina')or 100
local DRAIN_PER_SEC = 25
local REGEN_PER_SEC = 15
local REGEN_DELAY = 1
local MIN_TO_START = 10

local HoldPose=require(game.ReplicatedStorage:WaitForChild("HoldPose"))
-- Character first-person hands (camera-space offsets, studs)
local HAND_X = 1.8 -- distance left/right of center
local HAND_Y = -1.35 -- vertical rest position (more negative = lower)
local HAND_Z = -1.7 -- distance in front of camera
local HAND_PITCH = 12 -- degrees the forearm tilts up toward the front
local HAND_IN = 8 -- degrees the forearm angles inward
local BOB_SPEED = 11 -- sprint swing speed
local BOB_SWING = 0.28 -- forward/back swing distance while sprinting
local BOB_LIFT = 0.12 -- up/down swing while sprinting
local SPRINT_RAISE = 0.15 -- hands rise a little while sprinting
local FADE_SPEED = 8

-- Strafe sway: moving left / right tilts the view into the move and the hands lag a little behind.
-- Applied here, before FlashlightController (Camera+2) reads the camera, so the beam tilts with it.
local SWAY_ROLL = 3.5 -- degrees of camera roll at walking speed
local SWAY_HANDS = 0.14 -- studs the hands trail sideways at walking speed
local SWAY_SPEED = 7 -- how quickly the sway eases in / out

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
player.CameraMode = Enum.CameraMode.LockFirstPerson

-- Sprint bar (thin, bottom left)
local gui = Instance.new("ScreenGui")
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
gui.Name = "SprintGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")
local function missionUi()gui.Enabled=player:GetAttribute('MissionActive')==true end
player:GetAttributeChangedSignal('MissionActive'):Connect(missionUi);missionUi()

local back = Instance.new("Frame")
back.AnchorPoint = Vector2.new(0, 1)
back.Position = UDim2.new(0, 16, 1, -16)
back.Size = UDim2.fromOffset(160, 4)
back.BackgroundColor3 = Color3.new(0, 0, 0)
back.BackgroundTransparency = 0.5
back.BorderSizePixel = 0
back.Parent = gui

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.new(1, 1, 1)
fill.BorderSizePixel = 0
fill.Parent = back

Instance.new('UICorner',back).CornerRadius=UDim.new(0,5);Instance.new('UICorner',fill).CornerRadius=UDim.new(0,5)
fill.BackgroundColor3=Color3.fromRGB(185,211,171)
local caption=Instance.new('TextLabel');caption.Size=UDim2.fromOffset(220,18);caption.Position=UDim2.fromOffset(0,-23);caption.BackgroundTransparency=1;caption.Font=Enum.Font.GothamMedium;caption.TextSize=11;caption.TextColor3=Color3.fromRGB(201,216,199);caption.TextXAlignment=Enum.TextXAlignment.Left;caption.Text='STAMINA';caption.Parent=back
local stamina = MAX_STAMINA
local shiftHeld = false
local sprinting = false
local lastUse = 0
player.CharacterAdded:Connect(function()
 MAX_STAMINA=player:GetAttribute('MaxStamina')or 100;stamina=MAX_STAMINA;sprinting=false;shiftHeld=false;lastUse=0
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute('MissionActive')~=true then return end
	if (input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3) then shiftHeld = true end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then shiftHeld = false end
end)

-- Viewmodel hands
local viewFolder = Instance.new("Folder")
viewFolder.Name = "FakeHands"
viewFolder.Parent = camera

local leftHand,rightHand
local rigParts={};local sourceCharacter
-- First-person arms are laid out from the rig's REST pose (the joint attachments), never from the live arm,
-- which arm physics can be bending at the moment the hands are built (that baked in "crumpled" arms).
local function restOffset(char,side,name)
 local function joint(partName,jointName)
  local part=char:FindFirstChild(partName);local j=part and part:FindFirstChild(jointName)
  if j and j:IsA('Constraint')and j.Attachment0 and j.Attachment1 then return j.Attachment0,j.Attachment1 end
  if j and j:IsA('JointInstance')then return j end
 end
 local function step(parentFrame,partName,jointName)
  local a0,a1=joint(partName,jointName)
  if typeof(a0)=='Instance'and a0:IsA('Attachment')then
   -- child = parent * A0 * A1^-1 (whichever side each attachment sits on)
   if a1.Parent and a1.Parent.Name==partName then return parentFrame*a0.CFrame*a1.CFrame:Inverse()end
   return parentFrame*a1.CFrame*a0.CFrame:Inverse()
  elseif a0 and a0:IsA('JointInstance')then return parentFrame*a0.C0*a0.C1:Inverse()end
 end
 local upper=CFrame.identity
 local lower=step(upper,side..'LowerArm',side..'Elbow')
 local hand=lower and step(lower,side..'Hand',side..'Wrist')
 if not hand then return nil end
 local frames={[side..'UpperArm']=upper,[side..'LowerArm']=lower,[side..'Hand']=hand}
 return frames[name]and hand:Inverse()*frames[name]
end
local function buildHands(char)
 for _,p in ipairs(rigParts) do p.clone:Destroy() end;table.clear(rigParts)
 leftHand=nil;rightHand=nil;sourceCharacter=char
 for _,side in ipairs({'Left','Right'}) do
  local hand=char:FindFirstChild(side..'Hand');if not hand then continue end
  local handCopy
  for _,name in ipairs({side..'Hand',side..'LowerArm',side..'UpperArm'}) do
   local source=char:FindFirstChild(name);if source and source:IsA('BasePart') then
    local clone=source:Clone();for _,d in ipairs(clone:GetDescendants()) do if d:IsA('JointInstance') or d:IsA('Constraint') or d:IsA('LuaSourceContainer') then d:Destroy() end end
    clone.Name=name;clone.Anchored=true;clone.Massless=true;clone.CanCollide=false;clone.CanQuery=false;clone.CanTouch=false;clone.CastShadow=false;clone.LocalTransparencyModifier=0;clone.Parent=viewFolder
    table.insert(rigParts,{clone=clone,source=source,side=side,offset=restOffset(char,side,name)or hand.CFrame:ToObjectSpace(source.CFrame)})
    if name==side..'Hand' then handCopy=clone end
   end
  end
  if side=='Left' then leftHand=handCopy else rightHand=handCopy end
 end
 -- Equipped ring (CosmeticRig puts it on the left hand): copy it onto the first-person hand too.
 local leftSource=char:FindFirstChild('LeftHand');local ring=char:FindFirstChild('CosmeticRing',true)
 if leftSource and ring then
  for _,source in ipairs(ring:GetDescendants())do if source:IsA('BasePart')and source.Transparency<1 then
   local clone=source:Clone();for _,d in ipairs(clone:GetDescendants())do if d:IsA('JointInstance')or d:IsA('WeldConstraint')or d:IsA('NoCollisionConstraint')or d:IsA('Constraint')or d:IsA('LuaSourceContainer')then d:Destroy()end end
   clone.Name='Ring_'..source.Name;clone.Anchored=true;clone.Massless=true;clone.CanCollide=false;clone.CanQuery=false;clone.CanTouch=false;clone.CastShadow=false;clone.LocalTransparencyModifier=0;clone.Parent=viewFolder
   table.insert(rigParts,{clone=clone,source=source,side='Left',offset=leftSource.CFrame:ToObjectSpace(source.CFrame)})
  end end
 end
 viewFolder:SetAttribute('CharacterHands',true)
 -- Rebuild when a ring is equipped or changed after spawn.
 if not char:GetAttribute('RingWatch')then
  char:SetAttribute('RingWatch',true)
  char.DescendantAdded:Connect(function(d)if d.Name=='CosmeticRing'then task.defer(function()if sourceCharacter==char then buildHands(char)end end)end end)
  char.DescendantRemoving:Connect(function(d)if d.Name=='CosmeticRing'then task.defer(function()if sourceCharacter==char then buildHands(char)end end)end end)
 end
end

local HIDE = {}
for _, n in { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "Left Arm", "Right Arm" } do
	HIDE[n] = true
end

-- Held flashlight: visual copy of Lighting.Handle (the V2 flashlight model), always in the right hand.
-- The light itself is FlashlightController; FlashlightServer puts the model in other players' hands.
local HELD_SCALE = 1.0 -- flashlight size in the hand
local HELD_OFFSET = CFrame.new(-0.08, 0.12, 0) * CFrame.Angles(math.rad(-3), math.rad(8), 0) -- grip in the fist, body pointing forward
local heldFlashlight, heldRing, heldRingOffset

task.spawn(function()
	local src = game.Lighting:WaitForChild("Handle", 10)
	if not src then return end
	local clone = src:Clone()
	local motor = clone:FindFirstChildOfClass("Motor6D")
	local ring
	for _, c in clone:GetChildren() do
		if c:IsA("BasePart") then ring = c end
	end
	if motor and ring then
		local off = motor.C0 * motor.C1:Inverse()
		heldRingOffset = CFrame.new(off.Position * HELD_SCALE) * (off - off.Position)
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("Light") or d:IsA("Sound") or d:IsA("JointInstance") then d:Destroy() end
	end
	for _, p in { clone, ring } do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		for _, m in p:GetChildren() do
			if m:IsA("SpecialMesh") then m.Scale *= HELD_SCALE end
		end
	end
	clone.Name = "HeldFlashlight"
	clone.Parent = viewFolder
	if ring then ring.Parent = viewFolder end
	heldFlashlight, heldRing = clone, ring
end)

local function updateHeld(fist)
	if not heldFlashlight then return end
	local shown = true
	heldFlashlight.Transparency = shown and 0 or 1
	heldFlashlight.CFrame = fist.CFrame * HELD_OFFSET
	if heldRing then
		heldRing.Transparency = shown and 0 or 1
		if heldRingOffset then heldRing.CFrame = heldFlashlight.CFrame * heldRingOffset end
	end
end

local bobClock = 0
local sprintBlend = 0
local sway = 0 -- -1..1-ish: sideways speed relative to walking speed
-- Remove the last disco offset before Roblox reads the camera's look direction.
-- This prevents the forced pitch from accumulating or fighting mouse input.
local DISCO_BOB_HZ = 2
local DISCO_BOB_PITCH = math.rad(10)
local DISCO_BOB_HEIGHT = .10
local balloonBlend=0
local BALLOON_MIN_PITCH=20 -- degrees: holding the balloon never lets the view drop below this (was a fixed 70)
local discoCamera
local discoOffset = CFrame.identity
RunService:BindToRenderStep("DiscoBobReset", Enum.RenderPriority.Camera.Value - 1, function()
 if player:GetAttribute('MissionActive')~=true then discoCamera=nil;discoOffset=CFrame.identity;return end
 if discoCamera and discoCamera==workspace.CurrentCamera then
  discoCamera.CFrame *= discoOffset:Inverse()
 end
 discoCamera=nil
 discoOffset=CFrame.identity
end)


local function placeHand(hand, sideSign, phase)
 if not hand then return end
 local swing=math.sin(bobClock*BOB_SPEED+phase)*BOB_SWING*sprintBlend
 local lift=math.abs(math.cos(bobClock*BOB_SPEED+phase))*BOB_LIFT*sprintBlend+math.sin(bobClock*1.6+phase)*.03*(1-sprintBlend)+SPRINT_RAISE*sprintBlend
 local pose=HoldPose.Hand(camera.CFrame,sideSign,sway*SWAY_HANDS,lift,swing)
 local side=sideSign<0 and 'Left' or 'Right'
 for _,part in ipairs(rigParts) do if part.side==side then part.clone.CFrame=pose*part.offset;part.clone.Color=part.source.Color;local surface=part.clone:FindFirstChild('UniformBodySurface');local original=part.source:FindFirstChild('UniformBodySurface');if surface and original then surface.Color=original.Color end end end
 if sideSign<0 and HoldPose.IsAnimating() then
  local upper=viewFolder:FindFirstChild('LeftUpperArm');local lower=viewFolder:FindFirstChild('LeftLowerArm')
  local u,l=HoldPose.ArmFrames(camera.CFrame,pose,hand,upper,lower)
  if u then upper.CFrame=u;lower.CFrame=l end
 end
 local att=hand:FindFirstChild(side..'GripAttachment');local grip=att and att.WorldCFrame or pose
 if sideSign<0 then viewFolder:SetAttribute('LeftGrip',grip) else
  viewFolder:SetAttribute('RightGrip',grip)
  -- Keep the flashlight's original camera-facing orientation and hand position.
  updateHeld({CFrame=CFrame.new(grip.Position)*camera.CFrame.Rotation*CFrame.Angles(math.rad(HAND_PITCH),math.rad(-HAND_IN),0)})
 end
end

RunService:BindToRenderStep("SprintAndHands", Enum.RenderPriority.Camera.Value + 1, function(dt)
 if player:GetAttribute('MissionActive')~=true then
  viewFolder.Parent=nil;sprinting=false;shiftHeld=false
  local avatar=player.Character
  if avatar then for _,part in avatar:GetChildren()do if HIDE[part.Name]and part:IsA('BasePart')then part.LocalTransparencyModifier=0 end end end
  return
 end
	camera=workspace.CurrentCamera;if not camera then return end
	local char = player.Character
	if char and (sourceCharacter~=char or not leftHand or not rightHand) and char:FindFirstChild("LeftHand") and char:FindFirstChild("RightHand") and char:FindFirstChild("LeftLowerArm") and char:FindFirstChild("RightLowerArm") then buildHands(char) end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	-- no hands while dead or hiding in a closet (they would poke through the doors)
	if not hum or hum.Health <= 0 or player:GetAttribute("Hiding") then
		viewFolder.Parent = nil
		return
	end
	viewFolder.Parent = camera

	-- hide the real arms completely
	for _, part in char:GetChildren() do
		if HIDE[part.Name] and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end

	local moving = hum.MoveDirection.Magnitude > 0.1
	if sprinting then
		if not (shiftHeld and moving) or stamina <= 0 or (player:GetAttribute('SprintBlocked') or player:GetAttribute('Crouching')) then sprinting = false end
	elseif shiftHeld and moving and stamina >= MIN_TO_START and not (player:GetAttribute('SprintBlocked') or player:GetAttribute('Crouching')) then -- the heavy anvil blocks sprinting
		sprinting = true
	end

	if sprinting then
		stamina = player:GetAttribute('Pass_infinite_stamina')and MAX_STAMINA or math.max(0, stamina - DRAIN_PER_SEC * dt)
		lastUse = os.clock()
	elseif os.clock() - lastUse >= REGEN_DELAY then
		stamina = math.min(MAX_STAMINA, stamina + REGEN_PER_SEC * dt)
	end

	WALK_SPEED=player:GetAttribute('UpgradeWalkSpeed')or 12
 SPRINT_SPEED=player:GetAttribute('UpgradeSprintSpeed')or 20
 MAX_STAMINA=player:GetAttribute('MaxStamina')or 100
 stamina=math.min(stamina,MAX_STAMINA)
 local adminSpeed = player:GetAttribute('AdminWalkSpeed') -- owner-panel override (set only by AdminPowersServer)
	hum.WalkSpeed = adminSpeed and (sprinting and adminSpeed*1.6 or adminSpeed) or (sprinting and SPRINT_SPEED or WALK_SPEED) * (player:GetAttribute('CursedSpeedMultiplier') or 1) * (player:GetAttribute('Crouching') and .5 or 1)
	fill.Size = UDim2.fromScale(stamina / MAX_STAMINA, 1)

	local target = sprinting and 1 or 0
	sprintBlend += (target - sprintBlend) * math.clamp(dt * FADE_SPEED, 0, 1)
	bobClock += dt

	-- strafe sway (the camera module rebuilds the camera from its look direction every frame, so the roll
	-- added here never accumulates)
	local root = char:FindFirstChild("HumanoidRootPart")
	local side = 0
	if root and not root.Anchored then
		side = math.clamp(root.AssemblyLinearVelocity:Dot(camera.CFrame.RightVector) / WALK_SPEED, -1.5, 1.5)
	end
	sway += (side - sway) * math.clamp(dt * SWAY_SPEED, 0, 1)
	camera.CFrame *= CFrame.Angles(0, 0, math.rad(Preferences.Get('CameraMotion') and -sway * SWAY_ROLL or 0))

 -- Forced disco nod affects the first-person view as well as the visible neck.
 if Preferences.Get('CameraMotion') and player:GetAttribute('CursedActive')=='DiscoBall' and camera.CameraType==Enum.CameraType.Custom then
  local beat=math.sin(workspace:GetServerTimeNow()*math.pi*2*DISCO_BOB_HZ)
  discoOffset=CFrame.new(0,beat*DISCO_BOB_HEIGHT,0)*CFrame.Angles(beat*DISCO_BOB_PITCH,0,0)
  camera.CFrame *= discoOffset
  discoCamera=camera
 end
 -- The existing camera offset reset also removes this forced gaze before the next input update.
 balloonBlend+=( (player:GetAttribute('BalloonHeld')and 1 or 0)-balloonBlend)*math.clamp(dt*7,0,1)
 if balloonBlend>.001 and not player:GetAttribute('MonsterJumpscareActive')then
  local original=camera.CFrame
  local look=original.LookVector;local horizontal=Vector3.new(look.X,0,look.Z)
  if horizontal.Magnitude<.01 then horizontal=root and root.CFrame.LookVector or Vector3.new(0,0,-1)end
  horizontal=horizontal.Unit
  -- The balloon keeps the view tilted up, but only as a floor: the player can turn and look higher freely.
  local pitch=math.max(math.asin(math.clamp(look.Y,-1,1)),math.rad(BALLOON_MIN_PITCH))
  local target=CFrame.lookAt(original.Position,original.Position+horizontal*math.cos(pitch)+Vector3.yAxis*math.sin(pitch))
  local gaze=original:Lerp(target,balloonBlend)
  local offset=original:ToObjectSpace(gaze)
  camera.CFrame=gaze;discoOffset*=offset;discoCamera=camera
 end
	placeHand(leftHand, -1, 0)
	placeHand(rightHand, 1, math.pi)
end)
local CAS=game:GetService('ContextActionService')
-- Touch RUN lives in the same bottom-right grid as LIGHT/GRAB (bottom row, beside GRAB)
-- so it never overlaps them; the default ContextAction button floated over that grid on phones.
local runButton=Instance.new('TextButton');runButton.Name='RunAction';runButton.AnchorPoint=Vector2.new(1,1)
runButton.BackgroundColor3=Color3.fromRGB(20,28,26);runButton.BackgroundTransparency=.15;runButton.AutoButtonColor=true
runButton.Font=Enum.Font.GothamMedium;runButton.TextSize=12;runButton.TextColor3=Color3.new(1,1,1);runButton.Text='RUN';runButton.Visible=false;runButton.Parent=gui
Instance.new('UICorner',runButton).CornerRadius=UDim.new(0,16)
local runStroke=Instance.new('UIStroke');runStroke.Thickness=1;runStroke.Color=Color3.new(1,1,1);runStroke.Transparency=.8;runStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;runStroke.Parent=runButton
runButton.Activated:Connect(function()if player:GetAttribute('MissionActive')==true then shiftHeld=not shiftHeld end end)
RunService.RenderStepped:Connect(function()
 local small=camera.ViewportSize.Y<500
 runButton.Visible=player:GetAttribute('MissionActive')==true and InputHints.Get()=='touch'
 runButton.Size=UDim2.fromOffset(small and 54 or 64,small and 54 or 64)
 runButton.Position=UDim2.new(1,small and -84 or -96,1,small and -104 or -282)
 runButton.Text=shiftHeld and 'WALK' or 'RUN';runButton.BackgroundTransparency=shiftHeld and .05 or .35
end)

local function layoutStamina()
 local touch=InputHints.Get()=='touch'
 caption.Visible=not touch;back.Position=touch and UDim2.new(.5,-110,1,-28) or UDim2.new(0,16,1,-20);back.Size=UDim2.fromOffset(220,10)
end
InputHints.Changed:Connect(layoutStamina);layoutStamina()

