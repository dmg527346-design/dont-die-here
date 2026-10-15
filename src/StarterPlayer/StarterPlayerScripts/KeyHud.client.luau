local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local missionPlayer=game:GetService('Players').LocalPlayer
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
-- Client side of KeyDoorServer: draws the brass key mesh on every key pickup and lists held keys.
-- The key is the permanent uploaded Blender mesh in ReplicatedStorage.BrassKey.KeyMesh.
local RunService = game:GetService("RunService")
local player = game:GetService("Players").LocalPlayer
local mansion=workspace:WaitForChild("Mansion")
while mansion:GetAttribute('Ready')~=true or mansion:GetAttribute('RuntimeReady')~=true do mansion:GetAttributeChangedSignal('RuntimeReady'):Wait() end
local interactive=mansion:WaitForChild("Interactive")


local template=game:GetService("ReplicatedStorage"):WaitForChild("BrassKey"):WaitForChild("KeyMesh")

local visuals = {} -- [key Model] = MeshPart
local function attach(m)
	if visuals[m] or m:GetAttribute("Kind") ~= "key" or not template then return end
	local hit = m.PrimaryPart or m:WaitForChild("Pivot", 5)
	if not hit then return end
	local mesh = template:Clone()
	mesh.Name = "KeyVisual"
	mesh.Color = m:GetAttribute("KeyColor") or mesh.Color
	mesh.Size = template.Size * (m:GetAttribute("KeyScale") or 1)
	mesh.Anchored, mesh.CanCollide, mesh.CanTouch, mesh.CanQuery = true, false, false, false
	mesh.CFrame = hit.CFrame
	mesh.Parent = m
	visuals[m] = mesh
end
local function detach(m)
	if visuals[m] then visuals[m]:Destroy(); visuals[m] = nil end
end
for _, m in interactive:GetChildren() do task.spawn(attach, m) end
interactive.ChildAdded:Connect(function(m) task.defer(attach, m) end)
interactive.ChildRemoved:Connect(detach)

RunService.RenderStepped:Connect(function()
	for m, mesh in visuals do
		local hit = m.PrimaryPart
		if hit then mesh.CFrame = hit.CFrame end -- keys lie still in drawers / on tables; the hit box follows drawers
	end
end)

local gui = Instance.new("ScreenGui")
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
gui.Enabled=false
gui.Name = "KeyHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0, 1)
label.Position = UDim2.new(0, 16, 1, -40)
label.Size = UDim2.new(0, 360, 0, 28)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.TextSize = 15
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextColor3 = Color3.fromRGB(225, 210, 170)
label.TextStrokeTransparency = 1
label.Parent = gui
local function refresh()
	local k = tonumber(player:GetAttribute("Keys")) or 0
	label.Text = k == 0 and "" or ("Keys: " .. k)
end
player:GetAttributeChangedSignal("Keys"):Connect(refresh)
refresh()
local UIS=game:GetService('UserInputService')
local function layout()
 local cam=workspace.CurrentCamera;if not cam then return end
 local touch=InputHints.Get()=='touch'
 label.AnchorPoint=Vector2.new(0,touch and 0 or 1);label.Position=touch and UDim2.new(0,16,0,124) or UDim2.new(0,16,1,-48)
 label.Size=UDim2.fromOffset(math.min(220,cam.ViewportSize.X*.4),26)
end
InputHints.Changed:Connect(layout);workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout);layout()
