local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local missionPlayer=game:GetService('Players').LocalPlayer
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
-- Flashlight client: the flashlight lives here.
--   * F (keyboard), B / Circle (gamepad) or the phone button toggles it, instantly, with no server round trip.
--   * Your own light is a local light that follows the camera every frame.
--   * Other players' lights are drawn here too, from the "FlashlightOn" attribute FlashlightServer keeps on
--     their characters; FlashlightServer is only told your choice so everyone else can see it.
-- Nothing here waits on the server or the character before the key works, and nothing resets your choice.
-- Every flashlight light (yours and everyone else's) is created as soon as possible and left Enabled at
-- Brightness 0, so the lighting engine has it queued from the start; on / off only changes the brightness.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- your light (camera space: near the right hand)
local LIGHT_OFFSET = CFrame.new(0.4, -0.3, 0)
-- Owner 2026-10-25: less glare, more even. Softer hot spot (was 2.2 / 50) and a stronger wide fill (was .55), so what
-- the beam lands on stays readable instead of washing out to white.
local INNER_BRIGHTNESS, INNER_ANGLE = 1.45, 58
local OUTER_BRIGHTNESS, OUTER_ANGLE = .8, 84
local LIGHT_RANGE = 52
-- Upgrades buy coverage, not glare: brightness stays almost flat while the cone widens and reaches further.
-- Roblox caps light Range at 60 studs.
local MAX_RANGE = 60
local UPGRADE_ANGLE_GAIN = .55 -- fully upgraded cone is 55% wider
local UPGRADE_BRIGHTNESS_GAIN = .15 -- fully upgraded beam is only 15% brighter

-- other players' beams (relative to their Head: slightly right, low, in front)
-- turned 180 degrees about Y: a SpotLight in an Attachment shone backwards, so other players saw the beam
-- behind the character instead of where they look
local OTHER_OFFSET = CFrame.new(0.6, -0.3, -1) * CFrame.Angles(0, math.pi, 0)
local OTHER_RANGE, OTHER_ANGLE, OTHER_BRIGHTNESS = 52, 55, 2
local TORCH_TINT={torch_candle=Color3.fromRGB(255,222,170),torch_lantern=Color3.fromRGB(255,196,120),torch_glowstick=Color3.fromRGB(170,255,120),torch_pumpkin=Color3.fromRGB(255,160,70)}

-- HUD: tiny icon above the sprint bar (PC / console), round button (touch)
local ICON_POSITION = UDim2.new(0, 14, 1, -26)
local ICON_SIZE = 20
local TOUCH_BUTTON_SIZE = 56
local TOUCH_BUTTON_POSITION = UDim2.new(1, -40, 1, -175)
local KEYS = { [Enum.KeyCode.F] = true, [Enum.KeyCode.ButtonB] = true }

local player = Players.LocalPlayer
local GuiService=game:GetService('GuiService')
local on = true -- the flashlight starts ON when a mission begins (user request 2026-10-22); F / B / LIGHT still toggle it

-- own light: a local part (never replicated) moved to the *current* camera each frame
local lightPart = Instance.new("Part")
lightPart.Name = "LocalFlashlight"
lightPart.Size = Vector3.new(0.2, 0.2, 0.2)
lightPart.Transparency = 1
lightPart.Anchored = true
lightPart.CanCollide = false
lightPart.CanQuery = false
lightPart.CanTouch = false
lightPart.Parent = workspace

local function makeLight(parent, brightness, angle, range)
	local l = Instance.new("SpotLight")
	l.Face = Enum.NormalId.Front
	l.Range = range
	l.Brightness = 0 -- "off": stays Enabled so it is already live in the lighting engine
	l.Angle = angle
	l.Shadows = true
	l.Enabled = true
	l:SetAttribute("OnBrightness", brightness)
	l:SetAttribute("BaseAngle", angle)
	l.Parent = parent
	return l
end

-- Only clamp the emitter position. One center hit must not shorten the whole cone.
local originParams=RaycastParams.new()
originParams.FilterType=Enum.RaycastFilterType.Include
originParams.RespectCanCollide=true
local function safeEmitter(reference,desired)
 local map=workspace:FindFirstChild('Mansion')
 if not map then return desired end
 originParams.FilterDescendantsInstances={map}
 local delta=desired.Position-reference.Position
 local length=delta.Magnitude
 if length<.001 then return desired end
 local hit=workspace:Raycast(reference.Position,delta,originParams)
 if not hit then return desired end
 local position=reference.Position+delta.Unit*math.max(0,hit.Distance-.12)
 return desired+(position-desired.Position)
end
local nearDim=1 -- your own beam's close-to-the-floor dimming (updateNearDim, below)
-- Dread (LevelAmbienceClient.DreadLayer): a monster close by browns your beam out (FlashlightFlicker 0..1, smooth dips),
-- an idle scare makes it stutter (FlashlightStutterUntil, 2.5 Hz). Only your own beam; others see theirs as usual.
local function dreadFactor()
 local t=os.clock()
 if t<(player:GetAttribute('FlashlightStutterUntil')or 0)then return math.floor(t*5)%2==0 and .06 or .9 end
 local f=player:GetAttribute('FlashlightFlicker')or 0
 if f<=0 then return 1 end
 local dip=math.clamp((math.noise(t*2.2,.37)-(.32-.3*f))/.12,0,1)
 return 1-.8*f*dip-.06*f
end
local function setLit(l, lit, owner)
	owner=owner or player
 -- Sleepy Lamp (CloseUpChoices.ExtraChoices2): NO = the lamp ate this flashlight's light for a while; YES = a big golden beam.
 local lampT=workspace:GetServerTimeNow()
 if lampT<(owner:GetAttribute('LampAteLightUntil')or 0)then lit=false end
 local lampBoost=lampT<(owner:GetAttribute('LampBoostUntil')or 0)
 local tint=owner:GetAttribute('FlashlightColor')
 -- A torch skin (Torch cosmetic slot) warms the beam to match the lamp, unless a Flashlight Colors pick is set.
 local torch=TORCH_TINT[owner:GetAttribute('EquippedTorch') or '']
 l.Color=typeof(tint)=='Color3' and tint or torch or Color3.new(1,1,1)
 -- FlashlightStrength runs 1 (no upgrade) to 4 (max); turn it into 0..1 upgrade progress.
 -- Flashlight run boost (GearShopServer): each tier adds a quarter of an upgrade's width and 6 studs of reach.
 local runBoost=owner:GetAttribute('RunBoostFlashlight')or 0
 local upgrade=math.clamp(((owner:GetAttribute('FlashlightStrength')or 1)-1)/3,0,1)+.25*runBoost
 l.Range=math.clamp(((owner:GetAttribute('FlashlightRange')or LIGHT_RANGE)+6*runBoost)*(game.ReplicatedStorage:FindFirstChild('RecoveryRound')and game.ReplicatedStorage.RecoveryRound:GetAttribute('Omen')=='DimBatteries'and .75 or 1),1,MAX_RANGE) -- omen DimBatteries: 25% shorter beam
 l.Angle=math.min(170,l:GetAttribute("BaseAngle")*(1+UPGRADE_ANGLE_GAIN*upgrade))
 l.Brightness = lit and l:GetAttribute("OnBrightness")*(1+UPGRADE_BRIGHTNESS_GAIN*upgrade)*(l.Parent==lightPart and nearDim or 1) or 0
 if lampBoost then l.Range=MAX_RANGE;l.Angle=math.min(170,l.Angle*1.35);l.Brightness*=1.35;l.Color=Color3.fromRGB(255,214,140)end
end
local innerLight = makeLight(lightPart, INNER_BRIGHTNESS, INNER_ANGLE, LIGHT_RANGE)
local outerLight = makeLight(lightPart, OUTER_BRIGHTNESS, OUTER_ANGLE, LIGHT_RANGE)
-- Up close the beam washes out what lies on the floor (loot, keys): when your own beam lands on the ground,
-- or on something lying on it, within NEAR_START studs it dims smoothly, down to NEAR_MIN at NEAR_END studs.
-- Walls and anything at eye height keep the full beam; other players' beams are never dimmed.
-- Owner 2026-10-25: walls, doors and props up close dim too (down to NEAR_WALL_MIN), not only the floor.
local NEAR_START,NEAR_END,NEAR_MIN,NEAR_WALL_MIN=12,3,.3,.5
local nearParams=RaycastParams.new();nearParams.FilterType=Enum.RaycastFilterType.Exclude
local function updateNearDim(dt)
 local target=1
 local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
 if on and root then
  nearParams.FilterDescendantsInstances={character,lightPart}
  local cf=lightPart.CFrame
  local hit=workspace:Raycast(cf.Position,cf.LookVector*NEAR_START,nearParams)
  if hit then
   local low=hit.Position.Y<root.Position.Y-1.5 and NEAR_MIN or NEAR_WALL_MIN -- below the waist: the floor or something on it
   target=low+(1-low)*math.clamp((hit.Distance-NEAR_END)/(NEAR_START-NEAR_END),0,1)
  end
 end
 nearDim+=(target-nearDim)*math.min(1,dt*10)
end

-- HUD
local gui = Instance.new("ScreenGui")
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
gui.Name = "FlashlightGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false

local icon = Instance.new("TextLabel")
icon.AnchorPoint = Vector2.new(0, 1)
icon.Position = ICON_POSITION
icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
icon.BackgroundTransparency = 1
icon.Name='FlashlightIndicator';icon.Text='[F] FLASHLIGHT · OFF';icon.Font=Enum.Font.FredokaOne
icon.TextColor3=Color3.fromRGB(244,236,210);icon.TextXAlignment=Enum.TextXAlignment.Left
icon.TextScaled=true;local textLimit=Instance.new('UITextSizeConstraint');textLimit.MinTextSize=10;textLimit.MaxTextSize=15;textLimit.Parent=icon
icon.TextSize = ICON_SIZE - 4
icon.Parent = gui

local touchButton = Instance.new("TextButton")
touchButton.AnchorPoint = Vector2.new(1, 1)
touchButton.Position = TOUCH_BUTTON_POSITION
touchButton.Size = UDim2.fromOffset(TOUCH_BUTTON_SIZE, TOUCH_BUTTON_SIZE)
touchButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
touchButton.AutoButtonColor = true
touchButton.Name='LightAction';touchButton.Font=Enum.Font.GothamMedium;touchButton.Text = 'LIGHT'
touchButton.TextSize = 12
touchButton.TextColor3 = Color3.fromRGB(231, 236, 221) -- was dark-on-dark and unreadable
touchButton.Parent = gui
Instance.new("UICorner", touchButton).CornerRadius = UDim.new(0,16)
local touchStroke = Instance.new("UIStroke")
touchStroke.Thickness = 1
touchStroke.Color = Color3.new(1, 1, 1)
touchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
touchStroke.Parent = touchButton

local function refresh()
	setLit(innerLight, on)
	setLit(outerLight, on)
 local device=InputHints.Get();local pad=device=='pad';local touch=device=='touch'
 local control=pad and '[B / ○]'or touch and 'TAP LIGHT'or '[F]'
 icon.Text=control..' FLASHLIGHT · '..(on and 'ON'or 'OFF')
	icon.Visible = player:GetAttribute('MissionActive')==true and not player:GetAttribute('RoundDead')
	icon.TextTransparency = on and .08 or .28
	touchButton.Visible = touch
	touchButton.BackgroundTransparency = on and 0.15 or 0.45
	touchStroke.Transparency = on and .65 or .85
end

-- tell the server (for everyone else) whenever it is reachable; the local light never waits for this
local event = ReplicatedStorage:FindFirstChild("FlashlightEvent")
local function tellServer(toggled)
	if event then event:FireServer(on, toggled == true) end -- only a real press plays the click
end
if not event then
	task.spawn(function()
		event = ReplicatedStorage:WaitForChild("FlashlightEvent")
		tellServer()
	end)
end

local function toggle()
	on = not on
	refresh()
	tellServer(true)
end

UserInputService.InputBegan:Connect(function(input,processed)
 if processed or player:GetAttribute('AppearanceOpen')or player:GetAttribute('VanShopOpen')or player:GetAttribute('AdminPassPanelOpen')then return end
	if not KEYS[input.KeyCode] then return end
	if UserInputService:GetFocusedTextBox() then return end -- typing in chat
	toggle()
end)
touchButton.Activated:Connect(toggle)
InputHints.Changed:Connect(refresh)
refresh()
tellServer() -- other players see the beam that starts on

-- a new character keeps your choice; the server learns it again once the character exists
player.CharacterAdded:Connect(function() tellServer();refresh()end)
player:GetAttributeChangedSignal('RoundDead'):Connect(refresh)
player:GetAttributeChangedSignal('MissionActive'):Connect(refresh)

task.spawn(function()
	gui.Parent = player:WaitForChild("PlayerGui")
end)

-- other players' beams, drawn locally from their FlashlightOn attribute
local beams = {} -- [Player] = { head = BasePart, light = SpotLight, att = Attachment }
local function beamFor(p)
	local character = p.Character
	local head = character and character:FindFirstChild("Head")
	local b = beams[p]
	if b and b.head ~= head then
		b.att:Destroy()
		beams[p], b = nil, nil
	end
	if not b and head then
		local att = Instance.new("Attachment")
		att.Name = "FlashlightBeam"
		att.CFrame = OTHER_OFFSET
		att.Parent = head
		b = { head = head, att = att, light = makeLight(att, OTHER_BRIGHTNESS, OTHER_ANGLE, OTHER_RANGE) }
		beams[p] = b
	end
	return b
end
Players.PlayerRemoving:Connect(function(p)
	local b = beams[p]
	if b then b.att:Destroy() end
	beams[p] = nil
end)

RunService:BindToRenderStep("FlashlightFollow", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local camera = workspace.CurrentCamera
	if camera then
		-- the beam rides the hand (SprintController: lag on turns, breathing, fear tremor); centre springs back to the crosshair
		local hands = camera:FindFirstChild('FakeHands'); local sway = hands and hands:GetAttribute('BeamSway')
		lightPart.CFrame = safeEmitter(camera.CFrame, camera.CFrame * (typeof(sway) == 'CFrame' and sway or CFrame.identity) * LIGHT_OFFSET)
	end
 updateNearDim(dt)
 setLit(innerLight,on,player)
 setLit(outerLight,on,player)
 local dreadK=dreadFactor();if dreadK<1 then innerLight.Brightness*=dreadK;outerLight.Brightness*=dreadK end
	-- in first person we see the fake-hands flashlight (SprintController) instead of our real one
	local character = player.Character
	local handle = character and character:FindFirstChild("FlashlightHandle")
	if handle then
		handle.LocalTransparencyModifier = 1
		local ring = handle:FindFirstChild("RingPart")
		if ring then ring.LocalTransparencyModifier = 1 end
	end
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local b = beamFor(p)
			if b then
    local desired=b.head.CFrame*OTHER_OFFSET
    b.att.WorldCFrame=safeEmitter(b.head.CFrame,desired)
    setLit(b.light, p.Character:GetAttribute("FlashlightOn") == true, p)
   end
		end
	end
end)

local function layout()
 local cam=workspace.CurrentCamera;if not cam then return end
 local small=cam.ViewportSize.Y<500;touchButton.Size=UDim2.fromOffset(small and 54 or 64,small and 54 or 64)
 touchButton.Position=UDim2.new(1,-(small and 84 or 96),1,small and -166 or -356)
 icon.Position=UDim2.new(0,18,.62,0)
 icon.Size=UDim2.fromOffset(small and 186 or 218,28)
 refresh()
end
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout);layout()
