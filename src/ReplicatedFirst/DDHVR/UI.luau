local M={}
function M.Start()
 local player=game:GetService('Players').LocalPlayer
 local gui=player:WaitForChild('PlayerGui')
 local support=require(script.Parent:WaitForChild('Support'))
 local neon=require(game.ReplicatedStorage:WaitForChild('NeonUI'))
 local fitted=setmetatable({},{__mode='k'})
 local function limitScale(scale,maximum)
  if fitted[scale] then return end
  fitted[scale]=true
  local function clamp()
   if scale.Parent and scale.Scale>maximum then scale.Scale=maximum end
  end
  scale:GetPropertyChangedSignal('Scale'):Connect(clamp);clamp()
 end
 -- Preserve the existing ScreenGui hierarchy and callbacks. Roblox renders these on its native VR panel.
 local function prepare(object)
  if not object.Parent then return end -- Deferred descendant events can outlive a rebuilt menu.
  if object:IsA('GuiButton') then object.Selectable=true end
  if object:IsA('ProximityPrompt') then object.ClickablePrompt=true end
  if object:IsA('TextLabel') and object.Name=='PadHints' and object:FindFirstAncestor('CharacterColourGui') then
   task.defer(function()if object.Parent then object.Text='GRIPS: tab  B: close' end end)
  end
  if object:IsA('UIScale') and object.Name=='PlatePop' and not object:FindFirstAncestor('CharacterColourGui') then
   limitScale(object,.84) -- Keep modal edges inside the headset's central view.
  end
  if object:IsA('UIScale') and object.Parent.Name=='Root' and object:FindFirstAncestor('CharacterColourGui') then
   local root=object.Parent;root.AnchorPoint=Vector2.new(.5,.5);root.Position=UDim2.fromScale(.5,.5)
   limitScale(object,.84)
  end
  if object:IsA('GuiObject') and object.Parent.Name=='HorrorMainMenu' and (object.Name=='MenuGrid' or object.Name=='NavQuests' or object.Name=='NavQuestsDrop') then
   task.defer(function()if object.Parent then object.Position+=UDim2.fromOffset(56,0)end end)
  end
 end
 for _,object in gui:GetDescendants() do prepare(object) end
 gui.DescendantAdded:Connect(prepare)
 for _,object in workspace:GetDescendants() do if object:IsA('ProximityPrompt') then prepare(object) end end
 workspace.DescendantAdded:Connect(function(object)if object:IsA('ProximityPrompt') then prepare(object) end end)
 local screen=Instance.new('ScreenGui')
 screen.Name='DDHVRControls';screen.ResetOnSpawn=false;screen.DisplayOrder=900
 screen.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
 local toggle=Instance.new('TextButton')
 toggle.Name='VRHelp';toggle.Text='VR CONTROLS';toggle.Font=Enum.Font.FredokaOne;toggle.TextSize=18
 toggle.Size=UDim2.fromOffset(160,44);toggle.Position=UDim2.fromOffset(68,222)
 toggle.BackgroundColor3=Color3.fromRGB(22,42,43);toggle.TextColor3=Color3.fromRGB(244,236,210)
 toggle.Parent=screen
 local round=Instance.new('UICorner');round.CornerRadius=UDim.new(0,12);round.Parent=toggle
 local panel=Instance.new('Frame');panel.Name='Controls';panel.AnchorPoint=Vector2.new(.5,.5)
 panel.Position=UDim2.fromScale(.5,.5);panel.Size=UDim2.fromOffset(620,440)
 panel.BackgroundColor3=Color3.fromRGB(22,42,43);panel.Visible=false;panel.Parent=screen
 local scale=Instance.new('UIScale');scale.Parent=panel
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,16);corner.Parent=panel
 local text=Instance.new('TextLabel');text.Name='Instructions';text.BackgroundTransparency=1
 text.Position=UDim2.fromOffset(28,24);text.Size=UDim2.new(1,-56,1,-100)
 text.Font=Enum.Font.FredokaOne;text.TextSize=23;text.TextWrapped=true;text.TextXAlignment=Enum.TextXAlignment.Left;text.TextYAlignment=Enum.TextYAlignment.Top
 text.TextColor3=Color3.fromRGB(244,236,210)
 text.Text='VR CONTROLS\n\nReach with your RIGHT HAND. Hold RIGHT GRIP to pick up; release to drop.\n\nLEFT GRIP: hold the wrist map\nX: use a door / hide / leave closet\nB: flashlight     Left stick click: run\nRight stick click: crouch\n\nUse the native VR pointer and trigger to select menus. Your Roblox comfort settings control turning and movement.'
 text.Parent=panel
 local close=Instance.new('TextButton');close.Name='Close';close.Text='GOT IT';close.Size=UDim2.fromOffset(150,48);close.Position=UDim2.new(.5,-75,1,-64)
 close.Font=Enum.Font.FredokaOne;close.TextSize=22;close.BackgroundColor3=Color3.fromRGB(167,202,127);close.TextColor3=Color3.fromRGB(22,42,43);close.Parent=panel
 close.Selectable=true;toggle.Selectable=true
 local GS=game:GetService('GuiService')
 local function setOpen(value)
  panel.Visible=value
  player:SetAttribute('DDHVRHelpOpen',value or nil)
  if value then GS.SelectedObject=close elseif GS.SelectedObject==close then GS.SelectedObject=nil end
 end
 toggle.Activated:Connect(function()setOpen(not panel.Visible)end)
 close.Activated:Connect(function()setOpen(false)end)
 game:GetService('RunService').PreRender:Connect(function()
  local menu=gui:FindFirstChild('HorrorMainMenu')
  local focused=neon.IsFocused() or player:GetAttribute('VanShopOpen') or player:GetAttribute('AppearanceOpen')
   or player:GetAttribute('QuestLogOpen') or player:GetAttribute('VanRewardsOpen')
  toggle.Visible=not panel.Visible and not focused and not(menu and menu.Enabled and menu:FindFirstChild('Canvas'))
   and player:GetAttribute('MissionActive')~=true
 end)
 local function layout()
  local camera=workspace.CurrentCamera
  if camera then scale.Scale=math.min(.84,(camera.ViewportSize.X-100)/620,(camera.ViewportSize.Y-80)/440) end
 end
 layout();workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(layout)
 local camera=workspace.CurrentCamera;if camera then camera:GetPropertyChangedSignal('ViewportSize'):Connect(layout) end
 -- A help panel blocks grabs, while UI interaction remains owned by the native VR pointer.
 local previous=support.MenuOpen
 support.MenuOpen=function()return panel.Visible or previous()end
 screen.Parent=gui
end
return M
