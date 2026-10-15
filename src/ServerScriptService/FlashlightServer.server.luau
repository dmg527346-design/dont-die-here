-- Anti-cheat boundary helpers; kept within this system's existing owner.
-- Server boundary protection. Reject requests; never ban, kick or correct movement.
local Players=game:GetService('Players')
local AntiCheat={}
local buckets={}
local counters={}
local function record(channel,reason)
 local key=channel..':'..reason
 counters[key]=math.min((counters[key] or 0)+1,1000000000)
end
function AntiCheat.Finite(n)
 return type(n)=='number' and n==n and math.abs(n)<math.huge
end
function AntiCheat.Allow(player,channel,rate,burst)
 if typeof(player)~='Instance' or not player:IsA('Player') or player.Parent~=Players then return false end
 local now=os.clock()
 local user=buckets[player]
 if not user then user={};buckets[player]=user end
 local bucket=user[channel]
 if not bucket then bucket={tokens=burst,last=now};user[channel]=bucket end
 bucket.tokens=math.min(burst,bucket.tokens+math.max(0,now-bucket.last)*rate)
 bucket.last=now
 if bucket.tokens<1 then record(channel,'rate');return false end
 bucket.tokens-=1
 return true
end
function AntiCheat.Payload(value)
 -- Lobby requests are small records. Bound work, nesting, strings and numbers.
 local remaining=64
 local bytes=0
 local seen={}
 local function valid(v,depth)
  remaining-=1
  if remaining<0 then return false end
  local t=typeof(v)
  if t=='nil' or t=='boolean' then return true end
  if t=='number' then return AntiCheat.Finite(v) end
  if t=='string' then
   bytes+=#v
   return #v<=1024 and bytes<=4096 and utf8.len(v)~=nil
  end
  if t~='table' or depth>=3 or seen[v] then return false end
  seen[v]=true
  for key,item in pairs(v) do
   if (type(key)~='string' and type(key)~='number') or not valid(key,depth+1) or not valid(item,depth+1) then return false end
  end
  seen[v]=nil
  return true
 end
 return valid(value,0)
end
function AntiCheat.Stats()
 return table.clone(counters)
end
Players.PlayerRemoving:Connect(function(player)buckets[player]=nil end)

-- Flashlight server (small on purpose): the flashlight is run by each player's FlashlightController.
-- The server only
--   * puts the flashlight model in every character's right hand (so everyone sees it held),
--   * records each player's on/off choice as the character attribute "FlashlightOn" (replicates to all),
--   * plays the click sound on the handle so nearby players hear it - only for a real toggle; joining,
--     spawning and the client's start-up sync set the state silently.
-- Every client draws the beams itself from that attribute, so no light is ever waited on here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local MIN_TOGGLE_GAP = 0.08 -- seconds; ignores spam faster than a human can press

local event = ReplicatedStorage:FindFirstChild("FlashlightEvent") or Instance.new("RemoteEvent")
event.Name = "FlashlightEvent"
event.Parent = ReplicatedStorage

local wanted = {} -- [Player] = bool, the player's current choice (kept across respawns)
local lastToggle = {} -- [Player] = os.clock()

local function giveHandle(character)
	local hand = character:WaitForChild("RightHand", 10)
	if not hand or character:FindFirstChild("FlashlightHandle") then return end
	local handle = Lighting.Handle:Clone()
	handle.Name = "FlashlightHandle"
	-- the model has a Part and a Motor6D both named "Ring"; rename the part so lookups are unambiguous
	for _, child in handle:GetChildren() do
		if child.Name == "Ring" and child:IsA("BasePart") then child.Name = "RingPart" end
	end
	for _, d in handle:GetDescendants() do
		if d:IsA("Light") then d:Destroy() end
	end
	for _, part in { handle, handle:FindFirstChild("RingPart") } do
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end
	local weld = Lighting.Weld:Clone()
	weld.Part0 = hand
	weld.Part1 = handle
	weld.Parent = handle
	handle.Parent = character
end

-- set up silently for every character the moment it exists, so everyone's clients can prepare its beam
local function onCharacter(player, character)
	character:SetAttribute("FlashlightOn", wanted[player] == true)
	giveHandle(character)
end

-- (on, toggled): toggled is true only for a real press; start-up / respawn syncs send false and stay silent
event.OnServerEvent:Connect(function(player, on, toggled)
	if type(on) ~= "boolean" or not AntiCheat.Allow(player,"flashlight",15,30) then return end
	toggled = toggled == true
	if toggled then
		local now = os.clock()
		if lastToggle[player] and now - lastToggle[player] < MIN_TOGGLE_GAP then return end
		lastToggle[player] = now
	end
	local changed = toggled and wanted[player] ~= nil and wanted[player] ~= on
	wanted[player] = on
	local character = player.Character
	if not character then return end
	character:SetAttribute("FlashlightOn", on)
	local handle = character:FindFirstChild("FlashlightHandle")
	local sound = handle and handle:FindFirstChildOfClass("Sound")
	if changed and handle then Audio.Play('FlashlightClick',handle) end
end)

local function onPlayer(player)
	wanted[player] = false
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
	if player.Character then task.spawn(onCharacter, player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	wanted[player] = nil
	lastToggle[player] = nil
end)
for _, p in Players:GetPlayers() do onPlayer(p) end
