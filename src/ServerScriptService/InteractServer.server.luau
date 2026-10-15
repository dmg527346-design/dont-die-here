local QuestService=require(game:GetService('ServerScriptService'):WaitForChild('QuestService'))
local QuestHttp=game:GetService('HttpService')
local function questContext(eventId,model)
 local s=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 local map=workspace:FindFirstChild('Mansion')
 return {eventId=eventId,runId=s and s:GetAttribute('QuestRunId'),round=s and s:GetAttribute('Round'),generation=s and s:GetAttribute('QuestGeneration'),mapKind=map and map:GetAttribute('MapKind'),admin=model and (model:GetAttribute('AdminEffect')==true or model:GetAttribute('AdminSpawned')==true),lobbyToy=model and model:GetAttribute('LobbyToy')==true,itemId=model and model:GetAttribute('ItemId')}
end
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

-- Interaction server: the one owner of drawer / door / closet state.
-- Clients ask through InteractEvent; the server validates distance and animates.
--   workspace.Mansion.Interactive.Mover_<id>: Model, PrimaryPart "Pivot", attributes
--     Kind ("drawer"|"door"), Travel, Swing, Open (0..1), ClosedPivot (CFrame), Closet (name, doors only)
--   workspace.Mansion.Closets.Closet_<i>: Part at the hide spot (facing out), attribute Doors "id,id"
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local MAX_REACH = 11 -- studs from the root part to the pivot, a little over the client's reach
local DRAWER_TIME = 0.35
local DOOR_TIME = 0.45
local WALK_IN_TIME = 0.55
local TURN_TIME = 0.35
local STEP_OUT = 3.2 -- studs in front of the closet you are put when leaving
local HIP = 3 -- root part height above the closet floor
local SIT_BACK = 0.35 -- studs back from the hide point, so the camera isn't pressed against the doors

local event = ReplicatedStorage:FindFirstChild("InteractEvent") or Instance.new("RemoteEvent")
event.Name = "InteractEvent"
event.Parent = ReplicatedStorage

local mansion = workspace:WaitForChild("Mansion")
while mansion:GetAttribute('Ready')~=true or mansion:GetAttribute('RuntimeReady')~=true do mansion:GetAttributeChangedSignal('RuntimeReady'):Wait() end

local interactive = mansion:WaitForChild("Interactive")
local closets = mansion:WaitForChild("Closets")

local busy = {} -- [Model|Part] = true while animating
local occupant = {} -- [closet Part] = Player
local hiddenIn = {} -- [Player] = closet Part

local function poseFor(model, t)
	local closed = model:GetAttribute("ClosedPivot")
	if model:GetAttribute("Kind") == "drawer" then
		return closed * CFrame.new(0, 0, -model:GetAttribute("Travel") * t)
	end
	return closed * CFrame.Angles(0, math.rad(model:GetAttribute("Swing") * t), 0)
end

-- Tween a mover to openness `target` (0..1); yields until done.
local function animate(model, target, duration)
	local from = model:GetAttribute("Open") or 0
	if math.abs(from - target) < 1e-3 then return end
	Audio.Play(model:GetAttribute('Kind')=='drawer' and (target>from and 'DrawerOpen' or 'DrawerClose') or (target>from and 'DoorOpen' or 'DoorClose'),model)
	local v = Instance.new("NumberValue")
	v.Value = from
	v.Changed:Connect(function(x) model:PivotTo(poseFor(model, x)) end)
	local tw = TweenService:Create(v, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	tw:Play()
	tw.Completed:Wait()
	model:PivotTo(poseFor(model, target))
	model:SetAttribute("Open", target)
	v:Destroy()
end

local function closetDoors(closet)
	local out = {}
	for _, id in string.split(closet:GetAttribute("Doors") or "", ",") do
		local m = interactive:FindFirstChild("Mover_" .. id)
		if m then table.insert(out, m) end
	end
	return out
end

local function setDoors(closet, t)
	local doors = closetDoors(closet)
	local left = #doors
	local done = Instance.new("BindableEvent")
	for _, d in doors do
		task.spawn(function()
			animate(d, t, DOOR_TIME)
			left -= 1
			if left == 0 then done:Fire() end
		end)
	end
	if left > 0 then done.Event:Wait() end
	done:Destroy()
end

local function tweenRoot(root, cf, duration)
	local tw = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = cf })
	tw:Play()
	tw.Completed:Wait()
end

local function rootOf(player)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then return root, hum end
end

local function hide(player, closet)
	local root, hum = rootOf(player)
	if not root or hiddenIn[player] or occupant[closet] or busy[closet] then return end
	local evidence=game.ServerStorage:FindFirstChild('MonsterEvidence')
 if evidence then evidence:Fire(root.Position,0,'HideObserved',player,closet)end
 occupant[closet], hiddenIn[player], busy[closet] = player, closet, true
	event:FireClient(player, "hiding")
	player:SetAttribute("ClosetState", "Entering")
 player:SetAttribute("ClosetProtectedUntil", nil)
 player:SetAttribute("Hiding", true) -- Protection starts before any animation yields.
	-- sit square behind the crack where the two doors meet, facing out
	local mid, doors = Vector3.zero, closetDoors(closet)
	for _, d in doors do mid += d:GetAttribute("ClosedPivot").Position end
	local crackX = #doors > 0 and closet.CFrame:PointToObjectSpace(mid / #doors).X or 0
	local inside = closet.CFrame * CFrame.new(crackX, HIP, SIT_BACK)
	local front = inside * CFrame.new(0, 0, -STEP_OUT)
	root.Anchored = true
	hum.AutoRotate = false
	task.spawn(setDoors, closet, 1)
	-- step up to the doors facing in, walk in, turn round, pull the doors shut
	tweenRoot(root, CFrame.lookAt(front.Position, inside.Position), 0.35)
	tweenRoot(root, CFrame.lookAt(inside.Position, inside.Position + front.LookVector * -1), WALK_IN_TIME)
	event:FireClient(player, "turning", closet, TURN_TIME) -- the first-person camera turns with the body
	tweenRoot(root, inside, TURN_TIME)
	setDoors(closet, 0)
	busy[closet] = nil
	if hiddenIn[player] == closet then
  player:SetAttribute("ClosetState", "Hidden");event:FireClient(player, "hidden", closet)
  local character=player.Character;local episode=QuestHttp:GenerateGUID(false)
  task.delay(3,function()
   local _,h=rootOf(player)
   if player.Character==character and h and hiddenIn[player]==closet and player:GetAttribute('ClosetState')=='Hidden' then
    local id=closet:GetAttribute('QuestClosetGUID');if not id then id=QuestHttp:GenerateGUID(false);closet:SetAttribute('QuestClosetGUID',id)end
    local ctx=questContext('closet:'..id..':'..tostring((questContext()).round));ctx.episode=episode;QuestService.Record(player,'ClosetHide',1,ctx)
   end
  end)
 end
end

local function release(player, closet)
	occupant[closet], hiddenIn[player] = nil, nil
	player:SetAttribute("ClosetProtectedUntil", workspace:GetServerTimeNow()+.6)
 player:SetAttribute("ClosetState", nil)
 player:SetAttribute("Hiding", nil)
 local root, hum = rootOf(player)
	if root then
		root.Anchored = false
		hum.AutoRotate = true
	end
	event:FireClient(player, "free")
end

local function leave(player)
	local closet = hiddenIn[player]
	if not closet or busy[closet] then return end
	busy[closet] = true
 player:SetAttribute("ClosetState", "Exiting")
 local root = rootOf(player)
	setDoors(closet, 1)
	if root then
		tweenRoot(root, closet.CFrame * CFrame.new(0, HIP, -STEP_OUT), WALK_IN_TIME)
	end
	release(player, closet)
	task.delay(0.6, function()
		if not occupant[closet] then setDoors(closet, 0.35) end
		busy[closet] = nil
	end)
end

local function toggleMover(model)
	if busy[model] then return end
	busy[model] = true
	local open = (model:GetAttribute("Open") or 0) > 0.5
	animate(model, open and 0 or 1, model:GetAttribute("Kind") == "drawer" and DRAWER_TIME or DOOR_TIME)
	busy[model] = nil
end

-- The interaction server owns the held-input lease and pickup duration.
local GRAB_SECONDS=.22
local HOLD_LEASE=.85
local grabs={}
local function lobbyItem(player,model)
 local s=ReplicatedStorage:FindFirstChild('LobbyState');local world=workspace:FindFirstChild('LobbyWorld');local toys=world and world:FindFirstChild('Toys');local items=toys and toys:FindFirstChild('RuntimeToys')
 return s and s:GetAttribute('Mode')=='Menu' and player:GetAttribute('LobbyReady')==true and player:GetAttribute('MissionActive')~=true and typeof(model)=='Instance' and model:IsA('Model') and model.Parent==items and model:GetAttribute('LobbyToy')==true and model:GetAttribute('Kind')=='pickup'
end
local function grabAllowed(player,model)
 return typeof(model)=='Instance' and (player:GetAttribute('MissionActive')==true and model.Parent==interactive or lobbyItem(player,model))
end
local function endGrab(player,dropRay)
 local g=grabs[player];grabs[player]=nil;player:SetAttribute('PhysicalGrabActive',nil)
 if not g then return end
 if g.phase=='held' then local api=game.ServerStorage:FindFirstChild(g.model:GetAttribute('Kind')=='cart' and 'RecoveryApi' or 'CursedItemApi');if api then api:Invoke('release',player,g.model,dropRay) end end
 if player.Parent then event:FireClient(player,'grabEnded',g.model) end
end
local function beginGrab(player,model)
 if player:GetAttribute('MonsterJumpscareActive') or grabs[player] or hiddenIn[player] or (player:GetAttribute('CursedHeldCount') or 0)>0 then return end
 local root=rootOf(player)
 if not root or typeof(model)~='Instance' or not model:IsA('Model') or not grabAllowed(player,model) or not model.PrimaryPart or (model:GetAttribute('Kind')~='pickup' and model:GetAttribute('Kind')~='cart') or model:GetAttribute('HeldBy')==player.UserId then return end
 if (root.Position-model.PrimaryPart.Position).Magnitude>MAX_REACH then return end
 local g={model=model,phase='reach',last=os.clock()};grabs[player]=g
 local instant=model:GetAttribute('Kind')=='cart'
 event:FireClient(player,'grabStarted',model,instant and 0 or GRAB_SECONDS)
 local function finishGrab()
  if grabs[player]~=g then return end
  local r=rootOf(player)
  if not r or hiddenIn[player] or os.clock()-g.last>HOLD_LEASE or not grabAllowed(player,model) or not model.PrimaryPart or (r.Position-model.PrimaryPart.Position).Magnitude>MAX_REACH then endGrab(player);return end
  local api=game.ServerStorage:FindFirstChild(model:GetAttribute('Kind')=='cart' and 'RecoveryApi' or 'CursedItemApi');player:SetAttribute('PhysicalGrabActive',true)
  if not api or not api:Invoke('pickup',player,model) then endGrab(player);return end
  g.phase='held';event:FireClient(player,'grabHeld',model)
 end
 if instant then finishGrab() else task.delay(GRAB_SECONDS,finishGrab) end
end
task.spawn(function()
 while true do
  task.wait(.15)
  for player,g in pairs(grabs) do
   local root=rootOf(player)
   if not root or os.clock()-g.last>HOLD_LEASE or hiddenIn[player] or not g.model.Parent or (g.phase=='held' and g.model:GetAttribute('HeldBy')~=player.UserId) then endGrab(player) end
  end
 end
end)

event.OnServerEvent:Connect(function(player, action, target)
 if player:GetAttribute('MonsterJumpscareActive') then endGrab(player);return end
 if action=='holdEnd' then
  local ray=type(target)=='table'and AntiCheat.Allow(player,'touchDrop',6,10)and target or nil
  endGrab(player,ray);return
 end
 if type(action)~='string' or (action~='holdKeep' and action~='holdBegin' and action~='leave' and action~='use') then return end
 if not AntiCheat.Allow(player,action=='holdKeep' and 'grabLease' or 'interact',action=='holdKeep' and 15 or 10,action=='holdKeep' and 30 or 20) then return end
 -- Both hands are busy while the field map is out (FieldMapServer).
 if player:GetAttribute('MapOpen') then endGrab(player);return end
 if action=='holdKeep' then local g=grabs[player];if g then g.last=os.clock() end;return end
 if action=='holdBegin' then beginGrab(player,target);return end
	if player:GetAttribute('MissionActive')~=true then return end
	if action == "leave" then
		leave(player)
		return
	end
	if action ~= "use" or typeof(target) ~= "Instance" or hiddenIn[player] then return end
	if target.Parent ~= interactive or not target:IsA("Model") or not target.PrimaryPart then return end
	local root = rootOf(player)
	if not root or (root.Position - target.PrimaryPart.Position).Magnitude > MAX_REACH then return end
	if target:GetAttribute('Kind')=='sell' then local api=game.ServerStorage:FindFirstChild('RecoveryApi');if api then api:Invoke('sell',player) end;return end
 if target:GetAttribute('Kind')=='pickup' or target:GetAttribute('Kind')=='cart' then
		return -- Physical items require holdBegin and the completed grab animation.
	end
	local keyApi = game:GetService("ServerStorage"):FindFirstChild("KeyDoorApi") -- owned by KeyDoorServer
	if target:GetAttribute("Kind") == "key" then
		if keyApi then keyApi:Invoke("pickup", player, target) end
		return
	end
	if target:GetAttribute("Locked") and not (keyApi and keyApi:Invoke("unlock", player, target)) then Audio.Play("LockedAttempt",target);return end
	local closetName = target:GetAttribute("Closet")
	if closetName then
		local closet = closets:FindFirstChild(closetName)
		if closet then hide(player, closet) end
	else
		toggleMover(target)
	end
end)

local function forget(player)
 player:SetAttribute("ClosetState",nil)
 player:SetAttribute("ClosetProtectedUntil",nil)
 endGrab(player)
	local closet = hiddenIn[player]
	if closet then
		occupant[closet], hiddenIn[player] = nil, nil
		player:SetAttribute("Hiding", nil)
		busy[closet] = nil
		task.spawn(setDoors, closet, 0.35)
	end
end
Players.PlayerRemoving:Connect(forget)
Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function() forget(player) end)
end)
for _, p in Players:GetPlayers() do
	p.CharacterRemoving:Connect(function() forget(p) end)
end

-- starting poses (some drawers / wardrobe doors start ajar)
for _, m in interactive:GetChildren() do
	if m:IsA("Model") and m:GetAttribute("ClosedPivot") then
		m:PivotTo(poseFor(m, m:GetAttribute("Open") or 0))
	end
end
-- The interaction owner also handles NPC requests to open ordinary unlocked doors.
local monsterDoors=Instance.new('BindableFunction')
monsterDoors.Name='MonsterDoorApi'
monsterDoors.OnInvoke=function(model)
 if typeof(model)~='Instance'or not model:IsDescendantOf(interactive)or model:GetAttribute('Kind')~='door'or model:GetAttribute('Locked')or model:GetAttribute('Closet')or busy[model]then return false end
 if (model:GetAttribute('Open')or 0)>.5 then return true end
 model:SetAttribute('MonsterOpenedUntil',os.clock()+2)
 task.spawn(toggleMover,model)
 return true
end
monsterDoors.Parent=script

-- A check reveals a physical closet; the AI never receives the hidden occupant registry.
local monsterClosets=Instance.new('BindableFunction')
monsterClosets.Name='MonsterClosetApi';monsterClosets.Parent=script
monsterClosets.OnInvoke=function(closet,monsterRoot)
 if typeof(closet)~='Instance'or closet.Parent~=closets or not closet:IsA('BasePart')or typeof(monsterRoot)~='Instance'or not monsterRoot:IsA('BasePart')or not monsterRoot:IsDescendantOf(workspace.RoamingCreatures)or (monsterRoot.Position-closet.Position).Magnitude>10 or busy[closet]then return false end
 local p=occupant[closet]
 if p then
  leave(p)
 else
  busy[closet]=true;setDoors(closet,1)
  task.delay(2,function()if closet.Parent and not occupant[closet]then setDoors(closet,.35)end;busy[closet]=nil end)
 end
 return true
end
