-- Halloween event world dressing (lobby only). Does NOTHING while ReplicatedStorage.EventConfig.Halloween.Enabled is false.
-- When the event is on, the pumpkin cart stall (ServerStorage.EventKit.PumpkinCartStall) stands on the plaza between the
-- Robux store and the leaderboard; its prompt (EventStallPrompt) opens the Quest Log on the HALLOWEEN tab (QuestLogClient).
-- Candy Corn earning, the shop and event quests belong to QuestService; this script only places the stall.
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local EventConfig
local function enabled()
	if not EventConfig then
		local module = RS:FindFirstChild("EventConfig")
		local ok, cfg = pcall(function() return module and require(module) end)
		EventConfig = ok and type(cfg) == "table" and cfg or nil
	end
	if not EventConfig or type(EventConfig.Halloween) ~= "table" then return false end
	local h = EventConfig.Halloween
	if h.Enabled ~= true then return false end
	-- Same rule as the quest server: a real window is required (EndsAt after StartsAt, now inside it).
	local starts, ends, now = tonumber(h.StartsAt), tonumber(h.EndsAt), os.time()
	return starts ~= nil and ends ~= nil and ends > starts and now >= starts and now < ends
end
local function place()
	local world = workspace:FindFirstChild("LobbyWorld"); local stores = world and world:FindFirstChild("Stores")
	local kit = SS:FindFirstChild("EventKit"); local template = kit and kit:FindFirstChild("PumpkinCartStall")
	if not stores or not template then return end
	local existing = stores:FindFirstChild("EventStall")
	if not enabled() then if existing then existing:Destroy() end return end
	if existing then return end
	local C = world:GetAttribute("Center") or Vector3.new(1200, 0, 0)
	local stall = template:Clone(); stall.Name = "EventStall"
	local pos = Vector3.new(C.X + 34.6, 0.7, C.Z - 21)
	stall:PivotTo(CFrame.lookAt(pos, Vector3.new(C.X, 0.7, C.Z)))
	local anchor = Instance.new("Part"); anchor.Name = "PromptAnchor"; anchor.Size = Vector3.new(4, 4, 4); anchor.Transparency = 1
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false
	anchor.CFrame = stall:GetPivot() * CFrame.new(0, 3, -4); anchor.Parent = stall
	local light = Instance.new("PointLight"); light.Color = Color3.fromRGB(255, 150, 60); light.Range = 16; light.Brightness = 1.6; light.Parent = anchor
	local prompt = Instance.new("ProximityPrompt"); prompt.Name = "EventStallPrompt"; prompt.ObjectText = "PUMPKIN CART"
	prompt.ActionText = "Shop"; prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false; prompt.Parent = anchor
	stall.Parent = stores
end
-- The lobby world may load after this script; check now, then once a minute (StartsAt / EndsAt).
task.spawn(function()
	while true do
		pcall(place)
		task.wait(60)
	end
end)
