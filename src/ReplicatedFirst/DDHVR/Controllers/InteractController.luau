-- VR-only version of the existing owner. Original source remains untouched.
return function(script, VRSupport)
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
-- Prompts are key-only (E / X / square) on keyboard and controller: a clickable prompt takes the hidden first-person
-- mouse when the camera passes over it and stops the player looking around. Touch keeps tap-to-use.
do
 local function keyOnly(prompt)prompt.ClickablePrompt=true end -- Native VR pointer can use world prompts.
 local function all()for _,d in workspace:GetDescendants()do if d:IsA('ProximityPrompt')then keyOnly(d)end end end
 all()
 workspace.DescendantAdded:Connect(function(d)if d:IsA('ProximityPrompt')then keyOnly(d)end end)
 InputHints.Changed:Connect(all)
end
local missionPlayer=game:GetService('Players').LocalPlayer

-- Interaction client: look at a drawer or wardrobe and press E, X / Square (gamepad), or the phone button.
-- Inside a closet the same input leaves it. You sit right behind the crack where the doors meet; holding
-- A or D (stick / phone thumbstick) snaps the camera up to the crack to peek left or right, and letting go
-- springs it back to the middle. Only the camera moves (Humanoid.CameraOffset), and only on your screen.
-- InteractServer owns all state; this only aims, asks, and moves the local view while hidden.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REACH = 8 -- studs from the camera
local PICKUP_AIM_RADIUS=.35 -- gentle assistance for thin floor items
local GRAB_AIM_GRACE=.15 -- tolerate a brief aim slip while reaching
local grabAimLost=0
local WALL_SLACK = 2 -- an interactive part may sit this far behind its own furniture collider
local KEYS = { [Enum.KeyCode.E] = true, [Enum.KeyCode.ButtonX] = true }
local function touchMode() return InputHints.Get()=='touch' end

-- peeking (studs, relative to where you sit)
local PEEK_SIDE = 0.22 -- camera slides this far left / right while peeking
local PEEK_GAP = 0.45 -- at a full peek the camera stops this far behind the doors
local PEEK_SPEED = 22 -- how fast the camera snaps out and back (higher = snappier)
local CRACK_SWING = 0.09 -- the doors part this much (of fully open) at a full peek

-- HUD layout (the phone button sits directly above the flashlight button)
local PROMPT_POSITION = UDim2.new(0.5, 0, 0.5, 46)
local TOUCH_BUTTON_SIZE = 56
local TOUCH_BUTTON_POSITION = UDim2.new(1, -40, 1, -241)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local GuiService=game:GetService('GuiService')
local RETICLE_DIAMETER,RETICLE_OPACITY=12,.28
local event = ReplicatedStorage:WaitForChild("InteractEvent")
local mansion = workspace:WaitForChild("Mansion")
while mansion:GetAttribute('Ready')~=true or mansion:GetAttribute('RuntimeReady')~=true do mansion:GetAttributeChangedSignal('RuntimeReady'):Wait() end

local interactive = mansion:WaitForChild("Interactive")
local collision = mansion:WaitForChild("Collision")
local missionItems,missionCollision=interactive,collision
local function lobbyMode()
 local s=ReplicatedStorage:FindFirstChild('LobbyState')
 return s and s:GetAttribute('Mode')=='Menu' and player:GetAttribute('LobbyReady')==true and player:GetAttribute('MissionActive')~=true
end
local function interactionContext()
 if player:GetAttribute('MissionActive')==true then interactive=missionItems;collision=missionCollision;return true end
 local w=workspace:FindFirstChild('LobbyWorld');local t=w and w:FindFirstChild('Toys');local f=t and t:FindFirstChild('RuntimeToys')
 if lobbyMode() and f then interactive=f;collision=w;return true end
 return false
end

local state = "free" -- "free" | "hiding" (animating in) | "hidden"
local cursed=ReplicatedStorage:WaitForChild('CursedEvent')
local HoldPose=require(ReplicatedStorage:WaitForChild('HoldPose'))
local grabStartedAt=0
local grabTarget,grabPhase,grabPressed,grabPulse=nil,nil,false,0
-- The server must confirm a grab (grabStarted/grabHeld). At the very start of a level the interaction server is still
-- rebooting with the new map and a holdBegin can be lost: the cart showed as held but never moved. Resend until
-- confirmed, then give up cleanly instead of pretending to hold.
local grabConfirmed,grabSentAt,grabTries=false,0,0
local grabTouch
local endInteraction
local target -- Model currently aimed at
local hide -- while hidden: {doors, lean, side}

-- sideways input while hidden: A/D or arrows, gamepad left stick, else the humanoid's move direction (phone thumbstick)
local STICK_DEADZONE = 0.25
local function sideInput()
	if UserInputService:GetFocusedTextBox() then return 0 end -- typing in chat
	local x = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then x += 1 end
	if x ~= 0 then return x end
	for _, s in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if s.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(s.Position.X) > STICK_DEADZONE then
			return s.Position.X
		end
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.MoveDirection.Magnitude > 0.1 then
		return hum.MoveDirection:Dot(camera.CFrame.RightVector)
	end
	return 0
end

-- HUD
local gui = Instance.new("ScreenGui")
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
gui.Name = "InteractGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local prompt = Instance.new("Frame")
prompt.AnchorPoint = Vector2.new(0.5, 0)
prompt.Position = PROMPT_POSITION
prompt.Size = UDim2.fromOffset(0, 22)
prompt.AutomaticSize = Enum.AutomaticSize.X
prompt.BackgroundTransparency = 1
prompt.Visible = false
prompt.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 7)
layout.Parent = prompt

local keycap = Instance.new("TextLabel")
keycap.Size = UDim2.fromOffset(110, 30)
keycap.BackgroundColor3 = Color3.new(0, 0, 0)
keycap.BackgroundTransparency = 0.4
keycap.TextColor3 = Color3.new(1, 1, 1)
keycap.Font = Enum.Font.GothamBold
keycap.TextSize = 13
keycap.Parent = prompt
Instance.new("UICorner", keycap).CornerRadius = UDim.new(0, 5)
local capStroke = Instance.new("UIStroke")
capStroke.Color = Color3.new(1, 1, 1)
capStroke.Transparency = 0.5
capStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
capStroke.Parent = keycap

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(0, 22)
label.AutomaticSize = Enum.AutomaticSize.X
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(230, 225, 215)
label.TextStrokeTransparency = 0 -- black outline: readable over bright loot and lit floors (2026-10-22)
label.TextStrokeColor3 = Color3.new(0, 0, 0)
label.Font = Enum.Font.GothamMedium
label.TextSize = 16
label.RichText = true
label.Parent = prompt

local touchButton = Instance.new("TextButton")
touchButton.AnchorPoint = Vector2.new(1, 1)
touchButton.Position = TOUCH_BUTTON_POSITION
touchButton.Size = UDim2.fromOffset(TOUCH_BUTTON_SIZE, TOUCH_BUTTON_SIZE)
touchButton.BackgroundColor3 = Color3.fromRGB(20, 28, 26)
touchButton.BackgroundTransparency = 0.15
touchButton.TextColor3 = Color3.new(1, 1, 1)
touchButton.Font = Enum.Font.GothamMedium
touchButton.TextSize = 13
touchButton.TextWrapped=true;touchButton.TextScaled=true
local touchTextLimit=Instance.new('UITextSizeConstraint');touchTextLimit.MinTextSize=9;touchTextLimit.MaxTextSize=13;touchTextLimit.Parent=touchButton
touchButton.Visible = false
touchButton.Parent = gui
Instance.new("UICorner", touchButton).CornerRadius = UDim.new(0, 16)
local touchStroke = Instance.new("UIStroke")
touchStroke.Thickness = 1
touchStroke.Color = Color3.new(1, 1, 1)
touchStroke.Transparency = 0.7
touchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
touchStroke.Parent = touchButton

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(255, 235, 200)
highlight.OutlineTransparency = 0.55
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
highlight.Parent = gui

-- The camera aims through the actual viewport center, outside top-bar/safe-area offsets.
local reticleGui=Instance.new('ScreenGui');reticleGui.Name='GameplayReticle';reticleGui.ResetOnSpawn=false;reticleGui.ScreenInsets=Enum.ScreenInsets.None;reticleGui.IgnoreGuiInset=true;reticleGui.DisplayOrder=10;reticleGui.Parent=player.PlayerGui
local reticle=Instance.new('Frame');reticle.Name='CenterCircle';reticle.AnchorPoint=Vector2.new(.5,.5);reticle.Position=UDim2.fromScale(.5,.5);reticle.Size=UDim2.fromOffset(RETICLE_DIAMETER,RETICLE_DIAMETER);reticle.BackgroundTransparency=1;reticle.BorderSizePixel=0;reticle.Visible=false;reticle.Active=false;reticle.Parent=reticleGui
local reticleRound=Instance.new('UICorner');reticleRound.CornerRadius=UDim.new(.5,0);reticleRound.Parent=reticle
local reticleOutline=Instance.new('UIStroke');reticleOutline.Color=Color3.fromRGB(244,236,210);reticleOutline.Thickness=1.2;reticleOutline.Transparency=1-RETICLE_OPACITY;reticleOutline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;reticleOutline.Parent=reticle
-- Every panel that takes the mouse (admin, shops, rewards, gift picker, NeonUI focus) shows the cursor.
local NeonUI=require(game:GetService('ReplicatedStorage'):WaitForChild('NeonUI'))
local panelLook,lookMuted=false,{}
local hintGui=Instance.new('ScreenGui');hintGui.Name='PanelLookHint';hintGui.ResetOnSpawn=false;hintGui.DisplayOrder=1000;hintGui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;hintGui.Parent=player.PlayerGui
local lookHint=Instance.new('TextLabel');lookHint.Name='Hint';lookHint.AnchorPoint=Vector2.new(.5,1);lookHint.Position=UDim2.new(.5,0,1,-14);lookHint.Size=UDim2.fromOffset(260,22);lookHint.BackgroundColor3=Color3.new(0,0,0);lookHint.BackgroundTransparency=.45;lookHint.TextColor3=Color3.fromRGB(230,225,215);lookHint.Font=Enum.Font.GothamMedium;lookHint.TextSize=13;lookHint.Text='Hold right click to look around';lookHint.Visible=false;lookHint.Active=false;lookHint.Parent=hintGui
Instance.new('UICorner',lookHint).CornerRadius=UDim.new(0,6)
RunService:BindToRenderStep('GameplayCursor',Enum.RenderPriority.Last.Value+2,function()
 local cam=workspace.CurrentCamera
 if cam then
  local inset=GuiService:GetGuiInset();local center=cam.ViewportSize*.5-reticleGui.AbsolutePosition-inset
  local position=UDim2.fromOffset(center.X,center.Y);if reticle.Position~=position then reticle.Position=position end
 end
 local ch=player.Character;local hum=ch and ch:FindFirstChildOfClass('Humanoid')
 local colours=player.PlayerGui:FindFirstChild('CharacterColourGui');local picker=colours and colours:FindFirstChild('Picker')
 local gift=player.PlayerGui:FindFirstChild('MissionShop');gift=gift and gift:FindFirstChild('GiftReviveMenu')
 local panelOpen=(player:GetAttribute('AdminPassPanelOpen')or player:GetAttribute('AdminPowersPanelOpen')or player:GetAttribute('AppearanceOpen'))==true or player:GetAttribute('VanShopOpen')==true or player:GetAttribute('VanRewardsOpen')==true or picker and picker.Visible or gift and gift.Visible or NeonUI.IsFocused()
 local ui=panelOpen or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()~=nil
 local playing=player:GetAttribute('MissionActive')==true and player:GetAttribute('RoundDead')~=true and hum and hum.Health>0 and not player:GetAttribute('MonsterJumpscareActive')
 -- Hold right click with a panel open to keep looking around: the camera takes the mouse while the panel
 -- under the crosshair stops taking input (Interactable), and both come back on release.
 local look=panelOpen and playing==true and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
 if look and not panelLook then
  panelLook=true
  local c=cam and cam.ViewportSize*.5 or Vector2.zero
  for _,o in player.PlayerGui:GetGuiObjectsAtPosition(c.X,c.Y)do
   local top=o;while top.Parent and top.Parent:IsA('GuiObject')do top=top.Parent end
   if top.Interactable and not lookMuted[top]then lookMuted[top]=true;top.Interactable=false end
  end
 elseif not look and panelLook then
  panelLook=false
  for o in lookMuted do if o.Parent then o.Interactable=true end end;table.clear(lookMuted)
 end
 -- The hint only on the cosmetics panel (appearance terminal / colour picker), where looking at yourself matters;
 -- hold-right-click still works on the other panels, it just is not advertised there.
 local cosmeticsOpen=player:GetAttribute('AppearanceOpen')==true or picker and picker.Visible
 lookHint.Visible=cosmeticsOpen==true and playing==true and not panelLook and InputHints.Get()=='kb'
 reticle.Visible=false -- Native VR pointer and tracked controllers replace the flat crosshair.
 UserInputService.MouseIconEnabled=not reticle.Visible
 if panelOpen and not panelLook then UserInputService.MouseBehavior=Enum.MouseBehavior.Default end
end)

-- aiming
local moverParams = RaycastParams.new()
moverParams.FilterType = Enum.RaycastFilterType.Include
moverParams.FilterDescendantsInstances = { interactive }
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Include
blockParams.FilterDescendantsInstances = { collision }

local function keyAccessible(m)
 if m:GetAttribute('Kind')~='key' then return true end
 local name=m:GetAttribute('DrawerMover');if not name then return true end
 local drawer=interactive:FindFirstChild(name)
 return drawer~=nil and drawer:GetAttribute('Kind')=='drawer' and (drawer:GetAttribute('Open')or 0)>.5
end
local LOBBY_REACH=9.5
local LOBBY_AIM_RADIUS=.14 -- fraction of viewport height, clamped for phone/TV
local function lobbyReachable(model)
 local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local head=char and char:FindFirstChild('Head')
 if not root or not head or not model.PrimaryPart or model.Parent~=interactive or (root.Position-model.PrimaryPart.Position).Magnitude>LOBBY_REACH then return false end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={collision};params.RespectCanCollide=true
 local delta=model.PrimaryPart.Position-head.Position
 local hit=workspace:Raycast(head.Position,delta,params)
 return not hit or hit.Instance:IsDescendantOf(model) or hit.Distance+.8>=delta.Magnitude
end
local function lobbyAim(screenPoint,device)
 return VRSupport.Nearby(interactive)
end
local function legacyLobbyAim(screenPoint,device)
 device=device or InputHints.Get()
 local inset=GuiService:GetGuiInset()
 local point=screenPoint and Vector2.new(screenPoint.X,screenPoint.Y)-inset
 if not point then point=device=='kb' and UserInputService:GetMouseLocation()-inset or camera.ViewportSize*.5 end
 local radius=math.clamp(camera.ViewportSize.Y*LOBBY_AIM_RADIUS,56,120)
 local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart')
 if not root then return nil end
 local best,bestScore=nil,math.huge
 for _,model in interactive:GetChildren()do
  if model:IsA('Model') and model:GetAttribute('LobbyToy')==true and model:GetAttribute('HeldBy')~=player.UserId and not model:GetAttribute('ItemWearOwner') and lobbyReachable(model)then
   local projected,onScreen=camera:WorldToViewportPoint(model.PrimaryPart.Position)
   if onScreen then
    local offset=(Vector2.new(projected.X,projected.Y)-point).Magnitude
    local distance=(model.PrimaryPart.Position-root.Position).Magnitude
    local delta=model.PrimaryPart.Position-root.Position
    local forward=delta.Magnitude>.01 and root.CFrame.LookVector:Dot(delta.Unit) or 1
    local assisted=not screenPoint and device~='kb' and forward>.55
    if offset<=radius or assisted then
     local score=offset/radius+distance*.02
     if assisted and offset>radius then score=2+distance*.1 end
     if score<bestScore then best,bestScore=model,score end
    end
   end
  end
 end
 return best
end
-- Phones: thumbs aim loosely, so pick the pickup or cart nearest the screen centre inside a wide cone,
-- within the server's reach and with nothing solid in between.
local TOUCH_ASSIST_ANGLE=math.rad(35)
local function touchAssist(candidates,origin,look)
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');if not root then return nil end
 local best,bestAngle=nil,TOUCH_ASSIST_ANGLE
 for _,m in candidates do
  local kind=m:GetAttribute('Kind')
  if(kind=='pickup'and not m:GetAttribute('FaceOwner')and not m:GetAttribute('ItemWearOwner')and not m:GetAttribute('HeldBy')or kind=='cart')and m.PrimaryPart then
   local point=kind=='cart'and m.PrimaryPart.Position or m:GetPivot().Position
   local to=point-origin;local d=to.Magnitude
   if d>.1 and d<=REACH+3 and(root.Position-m:GetPivot().Position).Magnitude<=9.5 then
    local angle=math.acos(math.clamp(to.Unit:Dot(look),-1,1))
    if angle<bestAngle then
     local block=workspace:Raycast(origin,to,blockParams)
     if not block or block.Distance+WALL_SLACK>=d then best,bestAngle=m,angle end
    end
   end
  end
 end
 return best
end
local function aim()
 local near=VRSupport.Nearby(interactive)
 if near then return near end
 if lobbyMode()then return lobbyAim()end
 for _,m in interactive:GetChildren()do if m:GetAttribute('FaceOwner')==player.UserId then return m end end
	local candidates={};for _,m in ipairs(interactive:GetChildren()) do if m:GetAttribute('HeldBy')~=player.UserId and keyAccessible(m) then table.insert(candidates,m) end end;moverParams.FilterDescendantsInstances=candidates
	local origin = VRSupport.Head().Position
 local dir = VRSupport.Head().LookVector * REACH
 if lobbyMode()then
  local ray
  if InputHints.Get()=='kb'then local mouse=UserInputService:GetMouseLocation();ray=camera:ScreenPointToRay(mouse.X,mouse.Y)
  else ray=camera:ViewportPointToRay(camera.ViewportSize.X*.5,camera.ViewportSize.Y*.5)end
  origin=ray.Origin;dir=ray.Direction*80
 end
	local hit = workspace:Raycast(origin, dir, moverParams)
 if not hit then
  local pickups={};for _,m in candidates do if m:GetAttribute('Kind')=='pickup'and not m:GetAttribute('FaceOwner')and not m:GetAttribute('ItemWearOwner')then table.insert(pickups,m)end end
  moverParams.FilterDescendantsInstances=pickups;hit=workspace:Spherecast(origin,PICKUP_AIM_RADIUS,dir,moverParams)
 end
 if not hit and touchMode()and not lobbyMode()then
  local camp=workspace:FindFirstChild('RecoveryCamp');blockParams.FilterDescendantsInstances=camp and {collision,camp} or {collision};blockParams.RespectCanCollide=true
  local assisted=touchAssist(candidates,origin,camera.CFrame.LookVector);if assisted then return assisted end
 end
	if not hit then return nil end
 local stored={};for _,m in ipairs(interactive:GetChildren()) do if m:GetAttribute('CargoStored') and not m:GetAttribute('HeldBy') then table.insert(stored,m) end end
 if #stored>0 then local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=stored;local cargoHit=workspace:Raycast(origin,dir,params);if cargoHit then local first=hit.Instance:FindFirstAncestorOfClass('Model');if first and first:GetAttribute('Kind')=='cart' and (hit.Instance.Name=='BasketSide' or hit.Instance.Name=='BasketEnd' or hit.Instance.Name=='BasketFloor' or hit.Instance.Name=='TopRail' or hit.Instance.Name=='SideRib') then hit=cargoHit end end end
	local block
 local camp=not lobbyMode() and workspace:FindFirstChild('RecoveryCamp');blockParams.FilterDescendantsInstances=camp and {collision,camp} or {collision}
 blockParams.RespectCanCollide=true
 block = workspace:Raycast(origin, dir, blockParams)
	if block and block.Distance + WALL_SLACK < hit.Distance then return nil end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
 if model and model.Parent==interactive then
  if model:GetAttribute('Kind')=='pickup' or model:GetAttribute('Kind')=='cart' then return nil end
  if lobbyMode()then local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');if not root or (root.Position-model.PrimaryPart.Position).Magnitude>8 then return nil end end
  return model
 end
	return nil
end

local ItemNames=require(ReplicatedStorage:WaitForChild('CursedCatalog')).Items
local function promptDevice()
 return InputHints.Get()
end
local function escapePrompt(text)
 return(tostring(text):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;'))
end
local function heldPrompt(text,name,holdingItem)
 if not holdingItem or not name or name==''then return escapePrompt(text)end
 local first,last=text:find(name,1,true)
 if not first then return escapePrompt(text)end
 return escapePrompt(text:sub(1,first-1))..'<font color="#A7E38A">'..escapePrompt(name)..'</font>'..escapePrompt(text:sub(last+1))
end
local function displayName(model)
 local name=model:GetAttribute('DisplayName')
 if type(name)=='string'and name~=''then return name end
 local id=model:GetAttribute('ItemId');local entry=id and ItemNames[id]
 return entry and entry.name or model.Name
end
local function isOpen(model)
 local value=model:GetAttribute('Open')
 return value==true or type(value)=='number'and value>.5
end
local function targetPrompt(model)
 local kind=model:GetAttribute('Kind')
 if model:GetAttribute('FaceOwner')==player.UserId then
  return model:GetAttribute('ItemId')=='CoolSunglasses'and 'REMOVE SUNGLASSES'or 'REMOVE MOUSTACHE','Hold grab for 3 seconds'
 end
 if kind=='cart'then return 'GRAB CART',promptDevice()=='touch'and 'Tap to push'or 'Hold to push' end
 if kind=='sell'then
  local round=ReplicatedStorage:FindFirstChild('RecoveryRound')
  return round and round:GetAttribute('Phase')=='Returning'and 'RETURN ITEMS'or 'SELL ITEMS','Keep cart at van (3 seconds)'
 end
 if kind=='pickup'then
  local value=math.floor(tonumber(model:GetAttribute('Value'))or 0)
  return 'GRAB '..displayName(model),(model:GetAttribute('CargoStored')and 'From cart'or promptDevice()=='touch'and 'Tap to grab'or 'Hold to grab')..' \u{00B7} $'..value
 end
 if kind=='key'then return 'PICK UP KEY' end
 if model:GetAttribute('Locked')then
  if(tonumber(player:GetAttribute('Keys'))or 0)>0 then return 'UNLOCK'end
  return 'LOCKED','Find a key'
 end
 if model:GetAttribute('Closet')then return 'HIDE' end
 if kind=='drawer'then return isOpen(model)and 'CLOSE DRAWER'or 'OPEN DRAWER' end
 if kind=='door'then return isOpen(model)and 'CLOSE DOOR'or 'OPEN DOOR' end
 -- Other interactions keep their own verb, including native proximity prompts.
 local verb=model:GetAttribute('InteractVerb')or model:GetAttribute('ActionText')or model:GetAttribute('Verb')
 if type(verb)=='string'and verb~=''then return verb:upper()end
 local native=model:FindFirstChildWhichIsA('ProximityPrompt',true)
 if native and native.ActionText~=''then return native.ActionText:upper(),native.ObjectText~=''and native.ObjectText or nil end
 if kind=='revive'then return 'REVIVE' end
 if kind=='shop'or kind=='gearshop'then return 'OPEN SHOP' end
 if model:GetAttribute('Open')~=nil then return(isOpen(model)and 'CLOSE 'or 'OPEN ')..displayName(model)end
 return 'INTERACT '..displayName(model)
end
local function actionText(model)
 local verb,hint=targetPrompt(model)
 return verb..(hint and '\n'..hint or '')
end
local function carryHint(device)
 if device=='touch'then return nil end
 if device=='pad'then return 'Release '..'RIGHT GRIP'end
 return 'Release LMB \u{00B7} Scroll to move'
end
local function keyText(action)
 local device=promptDevice()
 if action=='drop'then return device=='pad'and 'RIGHT GRIP'or device=='touch'and 'DROP'or 'LMB'end
 if action~='use'and target and(target:GetAttribute('Kind')=='pickup'or target:GetAttribute('Kind')=='cart')then
  return device=='pad'and 'RIGHT GRIP'or device=='touch'and 'GRAB'or 'LMB'
 end
 if device=='pad'then return UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonX)=='ButtonSquare'and '\u{25A1}'or 'X'end
 return 'E'
end
local function buttonText(text)
 return(text:gsub('^(%u+)%s+','%1\n',1))
end

-- Gear shop items: the door key fires the held gear (throw / place / shoot) with the camera aim.
local GEAR_VERB={Grenade='THROW',ProxMine='PLACE',HypnoGun='SHOOT',SlayerGun='SHOOT',MedKit='HEAL',BigMedKit='HEAL'} -- med kits: held like gear, used with this key (2026-10-22)
local function heldGear()return GEAR_VERB[player:GetAttribute('CursedActive')or '']end
-- selene: allow(if_same_then_else)
local function activate()
 if player:GetAttribute('VanShopOpen')or player:GetAttribute('MapOpen')or (player:GetAttribute('AdminPassPanelOpen')or player:GetAttribute('AppearanceOpen'))then return end
	if state == "hidden" then
		event:FireServer("leave")
 elseif state=='free' and heldGear() then cursed:FireServer('use',workspace.CurrentCamera.CFrame)
	elseif state == "free" and target then
		event:FireServer("use", target)
 elseif state=='free' and (player:GetAttribute('CursedHeldCount') or 0)>0 then cursed:FireServer('use',workspace.CurrentCamera.CFrame)
	end
end

-- Co-op curse stuck on you (plunger/teddy/hair) and every teammate is dead: grab pulls it off yourself.
-- The server re-checks this (ItemBatch4.CanRemove), so this only picks the target.
local function ownStuckCurse()
 local curse=player:GetAttribute('CursedAttach');if not curse or curse==''then return nil end
 for _,q in ipairs(game:GetService('Players'):GetPlayers())do
  local h=q~=player and q:GetAttribute('MissionActive')==true and q:GetAttribute('RoundDead')~=true and q.Character and q.Character:FindFirstChildOfClass('Humanoid')
  if h and h.Health>0 then return nil end
 end
 local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
 if items then for _,m in ipairs(items:GetChildren())do if m:GetAttribute('AttachedTo')==player.UserId then return m end end end
end
local function beginInteraction(screenPoint,device)
 if VRSupport.MenuOpen() then return end
 target=VRSupport.Nearby(interactive)
 if not interactionContext()then return end
 if lobbyMode()then target=lobbyAim(screenPoint,device)end
 if player:GetAttribute('VanShopOpen')or player:GetAttribute('MapOpen')or (player:GetAttribute('AdminPassPanelOpen')or player:GetAttribute('AppearanceOpen'))or grabPressed or UserInputService:GetFocusedTextBox() then return end
 if state=='free' and not (target and (target:GetAttribute('Kind')=='pickup' or target:GetAttribute('Kind')=='cart'))then
  local own=ownStuckCurse();if own then target=own end
 end
 if state=='free' and target and (target:GetAttribute('Kind')=='pickup' or target:GetAttribute('Kind')=='cart') then
  if not VRSupport.Contact(target) then return end
  grabAimLost=0;grabPressed=true;grabTarget=target;grabPhase=target:GetAttribute('Kind')=='cart' and 'hold' or 'reach';grabPulse=0;grabStartedAt=os.clock()
  if touchMode() and target:GetAttribute('Kind')=='pickup' then HoldPose.BeginGrab(target,.22) end
  grabConfirmed,grabSentAt,grabTries=false,os.clock(),1
  event:FireServer('holdBegin',target)
 end
end
endInteraction=function(dropRay)
 if grabPressed or grabTarget then
  VRSupport.Release()
  grabPressed=false;grabTarget=nil;grabPhase=nil;grabTouch=nil
  HoldPose.EndGrab();event:FireServer('holdEnd',dropRay)
 end
end
-- Letting go of left click / the grab trigger drops what you carry, but only once the button has stayed up for
-- RELEASE_GRACE: a trigger easing off for a frame or a mouse switch chattering no longer throws the item away.
local RELEASE_GRACE=.025
local releaseToken=0
local function grabButtonDown()
 -- Only the physical grip holds loot. UI trigger clicks never grab it.
 for _,pad in UserInputService:GetConnectedGamepads()do
  if UserInputService:IsGamepadButtonDown(pad,Enum.KeyCode.ButtonR1)then return true end
 end
 return false
end
local function isGrabButton(input)return input.KeyCode==Enum.KeyCode.ButtonR1 end
-- selene: allow(if_same_then_else)
UserInputService.InputBegan:Connect(function(input,processed)
 if isGrabButton(input)and releaseToken>0 then releaseToken=0;if grabPressed then return end end -- pressed again inside the grace: keep holding
 if processed or UserInputService:GetFocusedTextBox() then return end
 if input.KeyCode==Enum.KeyCode.ButtonR1 and not grabPressed and ((target and (target:GetAttribute('Kind')=='pickup' or target:GetAttribute('Kind')=='cart')) or ownStuckCurse()) then
  beginInteraction()
 elseif KEYS[input.KeyCode] and not VRSupport.MenuOpen() then
  activate()
 end
end)
UserInputService.InputEnded:Connect(function(input)
 if not isGrabButton(input)or not grabPressed then return end
 releaseToken+=1;local mine=releaseToken
 task.delay(RELEASE_GRACE,function()
  if releaseToken~=mine then return end
  releaseToken=0
  if not grabButtonDown()then endInteraction()end
 end)
end)
-- Alt-tab, overlays and notifications keep the item in hand; back in the window, it drops only if the button is up.
UserInputService.WindowFocused:Connect(function()if grabPressed and not touchMode()and not grabButtonDown()then endInteraction()end end)
UserInputService.TextBoxFocused:Connect(endInteraction)
UserInputService.GamepadDisconnected:Connect(endInteraction)
touchButton.Activated:Connect(activate)
local grabButton=touchButton:Clone();grabButton.Name='GrabDrop';touchButton.Name='UseAction';grabButton.Parent=gui;grabButton.Text='GRAB';grabButton.Visible=false
local function touchGrabDrop()
 if grabPressed or(player:GetAttribute('CursedHeldCount')or 0)>0 then
  local camera=workspace.CurrentCamera;local ray=camera:ViewportPointToRay(camera.ViewportSize.X*.5,camera.ViewportSize.Y*.5)
  local suggestion=touchMode()and{touch=true,origin=ray.Origin,direction=ray.Direction}or nil
  if grabPressed then endInteraction(suggestion)else cursed:FireServer('drop',suggestion)end
 else beginInteraction()end
end
grabButton.Activated:Connect(touchGrabDrop)


local function doorPose(model, t)
	return model:GetAttribute("ClosedPivot") * CFrame.Angles(0, math.rad(model:GetAttribute("Swing") * (model:GetAttribute("SwingSign") or 1) * t), 0)
end

-- Doors and drawers glide on this screen every frame: InteractServer announces each move (from, to, server
-- start time, length) on MoverAnimEvent and still moves the real parts for collisions. Same curve as the server.
local moverAnims = {}
local function moverPose(model, t)
	local closed = model:GetAttribute("ClosedPivot")
	if typeof(closed) ~= "CFrame" then return nil end
	if model:GetAttribute("Kind") == "drawer" then return closed * CFrame.new(0, 0, -(model:GetAttribute("Travel") or 0) * t) end
	return closed * CFrame.Angles(0, math.rad((model:GetAttribute("Swing") or 0) * (model:GetAttribute("SwingSign") or 1) * t), 0) -- SwingSign: InteractServer may open a door the other way to miss the cart
end
task.spawn(function()
	local animEvent = ReplicatedStorage:WaitForChild("MoverAnimEvent", 60)
	if not animEvent then return end
	animEvent.OnClientEvent:Connect(function(model, from, to, start, duration)
		if typeof(model) == "Instance" and model:IsA("Model") and type(from) == "number" and type(to) == "number" and type(start) == "number" and type(duration) == "number" and duration > 0 then
			moverAnims[model] = { from = from, to = to, start = start, duration = duration }
		end
	end)
end)
RunService:BindToRenderStep("MoverGlide", Enum.RenderPriority.Camera.Value - 1, function()
	if not next(moverAnims) then return end
	local now = workspace:GetServerTimeNow()
	for model, a in moverAnims do
		if not model.Parent or (hide and table.find(hide.doors, model)) then moverAnims[model] = nil; continue end
		local t = math.clamp((now - a.start) / a.duration, 0, 1)
		local eased
		if a.to > a.from and model:GetAttribute("Kind") ~= "drawer" then local u = t - 1; eased = 1 + 2 * u * u * u + u * u -- opening doors settle (same curve as InteractServer)
		else eased = game:GetService("TweenService"):GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) end
		local pose = moverPose(model, a.from + (a.to - a.from) * eased)
		if pose then model:PivotTo(pose) end
		if t >= 1 then moverAnims[model] = nil end
	end
end)

local turn -- {from, to, t, duration}: swing the camera to face out of the closet

local function humanoid()
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

local function endPeek()
	local hum = humanoid()
	if hum then hum.CameraOffset = Vector3.zero end
	hide = nil
end

event.OnClientEvent:Connect(function(s, closet, duration)
 if (s=='grabStarted' or s=='grabHeld')and grabPressed and grabTarget==closet then grabConfirmed=true end
 if s=='grabStarted' then
  if grabPressed and grabTarget==closet then grabPhase=closet:GetAttribute('Kind')=='cart' and 'hold' or 'reach' else event:FireServer('holdEnd') end
  return
 elseif s=='grabHeld' then
  if grabPressed and grabTarget==closet then grabPhase='hold';if touchMode() then HoldPose.ConfirmGrab(closet) end; else event:FireServer('holdEnd') end
  return
 elseif s=='grabEnded' then endInteraction();return end
	if s == "turning" then return end
 if s == "VR_UNUSED_TURN" then
		local look = camera.CFrame.LookVector
		turn = { from = Vector3.new(look.X, 0, look.Z).Unit, to = closet.CFrame.LookVector, t = 0, duration = duration }
		return
	end
	state = s
	endPeek()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if s == "hidden" and closet and root then
		local doors, mid = {}, Vector3.zero
		for _, id in string.split(closet:GetAttribute("Doors") or "", ",") do
			local m = interactive:FindFirstChild("Mover_" .. id)
			if m then
				table.insert(doors, m)
				mid += m:GetAttribute("ClosedPivot").Position
			end
		end
		if #doors == 0 then return end
		-- how far the camera can lean forward before it would touch the doors
		local toDoors = -root.CFrame:PointToObjectSpace(mid / #doors).Z
		hide = { doors = doors, lean = math.max(0, toDoors - PEEK_GAP), side = 0 }
	end
end)
player.CharacterAdded:Connect(function() endInteraction();state = "free" hide = nil end)
player.CharacterRemoving:Connect(endInteraction)

-- camera-only peek: hold A / D to snap up to the crack, release to spring back (local view only)
local function updatePeek(dt)
 if true then return end -- The headset owns head movement. Never slide the view with the stick.
	local h, hum = hide, humanoid()
	if not h or not hum then return end
	local want = math.clamp(sideInput(), -1, 1)
	h.side += (want - h.side) * math.clamp(dt * PEEK_SPEED, 0, 1)
	local amount = math.abs(h.side)
	hum.CameraOffset = Vector3.new(h.side * PEEK_SIDE, 0, -h.lean * amount)
	for _, d in h.doors do
		d:PivotTo(doorPose(d, CRACK_SWING * amount))
	end
end

RunService:BindToRenderStep("ClosetTurn", Enum.RenderPriority.Camera.Value + 3, function(dt)
	if true then return end -- No forced closet camera rotation in a headset.
	turn.t = math.min(1, turn.t + dt / turn.duration)
	local a = (1 - math.cos(turn.t * math.pi)) / 2
	local y0 = math.atan2(-turn.from.X, -turn.from.Z)
	local y1 = math.atan2(-turn.to.X, -turn.to.Z)
	local d = (y1 - y0 + math.pi) % (2 * math.pi) - math.pi -- shortest way round
	camera.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.Angles(0, y0 + d * a, 0)
	if turn.t >= 1 then turn = nil end
end)

RunService.RenderStepped:Connect(function(dt)
 camera=workspace.CurrentCamera
 if not interactionContext()then endInteraction();target=nil;highlight.Adornee=nil;prompt.Visible=false;touchButton.Visible=false;grabButton.Visible=false;return end
 -- Reading the field map keeps what is in hand (CursedItemsServer keeps it following the aim) but starts nothing new.
 if player:GetAttribute('MapOpen')and not(player:GetAttribute('VanShopOpen')or player:GetAttribute('AdminPassPanelOpen')or player:GetAttribute('AppearanceOpen'))then
  target=nil;highlight.Adornee=nil;prompt.Visible=false;touchButton.Visible=false;grabButton.Visible=false
  if grabPressed then grabPulse+=dt;if grabPulse>=.2 then grabPulse=0;event:FireServer('holdKeep')end end
  return
 end
 if player:GetAttribute('VanShopOpen')or (player:GetAttribute('AdminPassPanelOpen')or player:GetAttribute('AppearanceOpen'))then endInteraction();target=nil;highlight.Adornee=nil;prompt.Visible=false;touchButton.Visible=false;grabButton.Visible=false;return end
 if grabPressed then
  grabPulse+=dt
  if grabPulse>=.2 then grabPulse=0;event:FireServer('holdKeep') end
  if not grabConfirmed and grabTarget and os.clock()-grabSentAt>.5 then
   if grabTries<20 then grabTries+=1;grabSentAt=os.clock();event:FireServer('holdBegin',grabTarget)else endInteraction()end
  end
  if grabPhase=='reach'then if state~='free'then endInteraction()elseif false and grabTarget:GetAttribute('AttachedTo')~=player.UserId then grabAimLost+=dt;if grabAimLost>GRAB_AIM_GRACE then endInteraction()end else grabAimLost=0 end end
 end
	if state == "hidden" then updatePeek(dt) end
	target = state == "free" and aim() or nil
	highlight.Adornee = target
 local device=promptDevice();local touch=device=='touch'
 local heldCount=player:GetAttribute('CursedHeldCount')or 0
 local carrying=grabPressed and grabPhase=='hold'or heldCount>0
 local gearVerb=state=='free'and heldGear()
 local entry=ItemNames[player:GetAttribute('CursedActive')]
 local heldName=grabTarget and(grabTarget:GetAttribute('Kind')=='cart'and 'CART'or displayName(grabTarget))or entry and entry.name or 'ITEM'
 local dropAction=carrying and state~='hidden'and not gearVerb
 local text,verb,hint
 if state=='hidden'then
  verb='LEAVE'
  if hide then hint=device=='kb'and 'A / D to peek'or device=='pad'and 'Left stick to peek'or 'Thumbstick to peek'end
 elseif gearVerb then
  local entry=ItemNames[player:GetAttribute('CursedActive')]
  verb=gearVerb..' '..(entry and entry.name or '')
 elseif grabPressed and grabPhase=='reach'then
  verb='GRABBING '..(grabTarget and displayName(grabTarget)or 'item')
  hint=math.floor(math.clamp((os.clock()-grabStartedAt)/.22,0,1)*100)..'%'
 elseif carrying then
  verb='DROP '..heldName
 elseif target and target~=grabTarget then
  verb,hint=targetPrompt(target)
 end
 if carrying and state~='hidden'then
  hint=gearVerb and((device=='pad'and '[RT: release] 'or device=='kb'and '[LMB: release] 'or '')..'DROP '..heldName)or carryHint(device)
 end
 if verb then text=verb..(hint and '\n'..hint or '')end
 if grabTarget and grabTarget:GetAttribute('FaceOwner')==player.UserId then text='REMOVING '..(grabTarget:GetAttribute('ItemId')=='CoolSunglasses'and 'SUNGLASSES'or 'MOUSTACHE')..'\n'..math.floor((grabTarget:GetAttribute('MoustachePullProgress')or 0)*100)..'% - keep holding'end
 -- Context stays in the same HUD location on every platform; buttons keep their existing actions.
 prompt.Visible=text~=nil
 touchButton.Visible=touch and(gearVerb~=nil and gearVerb~=false or not(grabPressed and grabTarget and grabTarget:GetAttribute('Kind')=='cart')and(state=='hidden'or(target~=nil and target:GetAttribute('Kind')~='pickup'and target:GetAttribute('Kind')~='cart')))
 grabButton.Visible=touch
 grabButton.TextColor3=grabPressed and Color3.fromRGB(246,220,184)or Color3.fromRGB(231,236,221)
 local grabVerb=target and(target:GetAttribute('Kind')=='pickup'or target:GetAttribute('Kind')=='cart')and select(1,targetPrompt(target))or 'GRAB'
 grabButton.Text=carrying and 'DROP'or buttonText(grabVerb)
 grabButton.BackgroundTransparency=(grabPressed or target and(target:GetAttribute('Kind')=='pickup'or target:GetAttribute('Kind')=='cart'))and .15 or .6
 if text then
  label.Text=heldPrompt(text,heldName,heldCount>0 and carrying)
  local useAction=gearVerb or state=='hidden'or target and target:GetAttribute('Kind')~='pickup'and target:GetAttribute('Kind')~='cart'
  keycap.Text=keyText(dropAction and 'drop'or useAction and 'use'or 'grab')
  keycap.Visible=not touch and(dropAction or useAction or not grabPressed and target~=nil)and true or false
  local touchVerb=gearVerb or(state=='hidden'and 'LEAVE')or(target and select(1,targetPrompt(target)))or verb
  touchButton.Text=touchVerb=='LOCKED'and 'LOCKED\nFind a key'or buttonText(touchVerb)
 end
end)
local function layoutTouch()
 local cam=workspace.CurrentCamera;if not cam then return end
 local small=cam.ViewportSize.Y<500
 local side=small and 54 or 64
 touchButton.Size=UDim2.fromOffset(side,side);grabButton.Size=UDim2.fromOffset(side,side)
 touchButton.Position=UDim2.new(1,-22,1,small and -166 or -356) -- large screens: above Roblox's 120px jump button
 grabButton.Position=UDim2.new(1,-22,1,small and -104 or -282)
 label.AutomaticSize=Enum.AutomaticSize.None;label.Size=UDim2.fromOffset(math.min(360,cam.ViewportSize.X-110),42);label.TextWrapped=true;label.TextSize=small and 13 or 15
 prompt.Position=UDim2.new(.5,0,.5,42)
end
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layoutTouch);layoutTouch()

if RunService:IsStudio()then
 local test=Instance.new('BindableFunction');test.Name='LobbyGrabTestApi';test.Parent=script
 test.OnInvoke=function(action,screenPoint,device)
  if not interactionContext()then return nil end
  if action=='aim'then local model=lobbyMode() and lobbyAim(screenPoint,device) or aim();return model
  elseif action=='begin'then beginInteraction(screenPoint,device);return grabTarget
  elseif action=='end'then endInteraction();return true end
  return nil
 end
end

end
