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
local DOOR_TIME = 0.55 -- was 0.45 with Quad-Out; Sine in-out glides instead of jolting
local WALK_IN_TIME = 0.55
local TURN_TIME = 0.35
local STEP_OUT = 3.2 -- studs in front of the closet you are put when leaving
local HIP = 3 -- root part height above the closet floor
local SIT_BACK = 0.35 -- studs back from the hide point, so the camera isn't pressed against the doors

local event = ReplicatedStorage:FindFirstChild("InteractEvent") or Instance.new("RemoteEvent")
event.Name = "InteractEvent"
event.Parent = ReplicatedStorage
-- Clients draw each door/drawer move themselves every frame (InteractController MoverGlide); replicated
-- server steps arrive at network rate and look choppy. The server still moves the real parts below.
local animEvent = ReplicatedStorage:FindFirstChild("MoverAnimEvent") or Instance.new("RemoteEvent")
animEvent.Name = "MoverAnimEvent"
animEvent.Parent = ReplicatedStorage

local mansion = workspace:WaitForChild("Mansion")
while mansion:GetAttribute('Ready')~=true or mansion:GetAttribute('RuntimeReady')~=true do mansion:GetAttributeChangedSignal('RuntimeReady'):Wait() end

local interactive = mansion:WaitForChild("Interactive")
local closets = mansion:WaitForChild("Closets")

-- Closet doors are built non-solid (MapGen.Furnisher); shut ones become solid here, animate() keeps them in step.
for _, m in interactive:GetChildren() do
	if m:IsA("Model") and m:GetAttribute("Kind") == "door" and m:GetAttribute("Closet") and (m:GetAttribute("Open") or 0) <= .02 then
		for _, part in m:GetDescendants() do if part:IsA("BasePart") and part ~= m.PrimaryPart then part.CanCollide = true end end
	end
end

local busy = {} -- [Model|Part] = true while animating
local occupant = {} -- [closet Part] = Player
local hiddenIn = {} -- [Player] = closet Part
local crawling = {} -- [Player] = true while a crawl hatch slides them through (world features)

local function poseFor(model, t)
	local closed = model:GetAttribute("ClosedPivot")
	if model:GetAttribute("Kind") == "drawer" then
		return closed * CFrame.new(0, 0, -model:GetAttribute("Travel") * t)
	end
	return closed * CFrame.Angles(0, math.rad((model:GetAttribute("Swing") or 100) * (model:GetAttribute("SwingSign") or 1) * t), 0) -- 100: what MapGen U.Mover sets
end

-- Opening doors swing ~4% past open and settle back (a little weight); drawers and closing keep the smooth sine.
-- InteractController uses the same curve so every screen matches the server.
local function moverEase(t, opening)
	if opening then local u = t - 1; return 1 + 2 * u * u * u + u * u end
	return TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

-- Doors never sweep through the recovery cart. Checked only when a door is used (about 25 box queries), never per frame:
-- open the other way when the usual side would hit the cart, otherwise stop just short of it; closing stops short too.
local doorBoxes = setmetatable({}, { __mode = "k" }) -- [door] = { rel = box CFrame relative to its pivot, size }
local cartParams = OverlapParams.new()
cartParams.FilterType = Enum.RaycastFilterType.Include
local function carts()
	local list = {}
	for _, m in interactive:GetChildren() do if m:IsA("Model") and m:GetAttribute("Kind") == "cart" then table.insert(list, m) end end
	return list
end
local function doorHitsCart(model, sign, t)
	local box = doorBoxes[model]
	if not box then local cf, size = model:GetBoundingBox(); box = { rel = model:GetPivot():ToObjectSpace(cf), size = size }; doorBoxes[model] = box end
	local pose = model:GetAttribute("ClosedPivot") * CFrame.Angles(0, math.rad((model:GetAttribute("Swing") or 0) * sign * t), 0)
	return #workspace:GetPartBoundsInBox(pose * box.rel, box.size + Vector3.new(.6, 0, .6), cartParams) > 0
end
-- A cart caught inside a door (a slam, lag, a shove): slide it straight out of the doorway to the side it is on,
-- half a stud at a time, until the slab no longer touches it (owner 2026-10-25: cart stuck in the door).
local function freeCart(model, t)
	local list = carts(); if #list == 0 then return false end
	cartParams.FilterDescendantsInstances = list
	local sign = model:GetAttribute("SwingSign") or 1
	if not doorHitsCart(model, sign, t) then return false end
	local closed = model:GetAttribute("ClosedPivot")
	local out = closed.LookVector * Vector3.new(1, 0, 1); if out.Magnitude < .1 then return false end; out = out.Unit
	for _, cart in list do
		local side = (cart:GetPivot().Position - closed.Position):Dot(out) >= 0 and 1 or -1
		local start = cart:GetPivot()
		for i = 1, 20 do
			cart:PivotTo(start + out * side * i * .5)
			if not doorHitsCart(model, sign, t) then break end
		 end
		if cart.PrimaryPart then cart.PrimaryPart.AssemblyLinearVelocity = Vector3.zero end
	end
	return true
end
-- Furthest openness reachable from `from` toward `to` before the slab would touch a cart (4-degree steps).
local function clearTo(model, sign, from, to)
	local steps = math.max(1, math.ceil(math.abs(to - from) * math.abs(model:GetAttribute("Swing") or 90) / 4))
	local last = from
	for i = 1, steps do
		local t = from + (to - from) * i / steps
		if doorHitsCart(model, sign, t) then return last end
		last = t
	end
	return to
end
local function cartSafeDoor(model)
	return model:GetAttribute("Kind") == "door" and not model:GetAttribute("Closet") and typeof(model:GetAttribute("ClosedPivot")) == "CFrame"
end

-- Tween a mover to openness `target` (0..1); yields until done.
local function animate(model, target, duration)
	local from = model:GetAttribute("Open") or 0
	if math.abs(from - target) < 1e-3 then return end
	Audio.Play(model:GetAttribute('Kind')=='drawer' and (target>from and 'DrawerOpen' or 'DrawerClose') or (target>from and 'DoorOpen' or 'DoorClose'),model)
	animEvent:FireAllClients(model, from, target, workspace:GetServerTimeNow(), duration)
	local v = Instance.new("NumberValue")
	v.Value = 0
	local opening = target > from and model:GetAttribute("Kind") ~= "drawer"
	v.Changed:Connect(function(a) model:PivotTo(poseFor(model, from + (target - from) * moverEase(a, opening))) end)
	-- A swinging slab is not solid: it can never shove a cart (or a player) that is pushed into it mid-swing.
	local solid = {}
	if cartSafeDoor(model) then for _, part in model:GetDescendants() do if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false; table.insert(solid, part) end end end
	local closetDoor = model:GetAttribute("Closet") ~= nil and model:GetAttribute("Kind") == "door"
	if closetDoor then for _, part in model:GetDescendants() do if part:IsA("BasePart") and part ~= model.PrimaryPart then part.CanCollide = false end end end
	local tw = TweenService:Create(v, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Value = 1 })
	tw:Play()
	tw.Completed:Wait()
	model:PivotTo(poseFor(model, target))
	model:SetAttribute("Open", target)
	v:Destroy()
	-- Closet doors are solid while shut (owner 2026-10-22: players walked straight through cruise wardrobe doors).
	if closetDoor then for _, part in model:GetDescendants() do if part:IsA("BasePart") and part ~= model.PrimaryPart then part.CanCollide = target <= .02 end end end
	if #solid > 0 then
		cartParams.FilterDescendantsInstances = carts()
		if doorHitsCart(model, model:GetAttribute("SwingSign") or 1, target) then
			-- the cart was pushed into the swing: stay non-solid until it has moved off, then become solid again
			task.spawn(function()
				repeat task.wait(.5); cartParams.FilterDescendantsInstances = carts() until not model.Parent or not doorHitsCart(model, model:GetAttribute("SwingSign") or 1, model:GetAttribute("Open") or 0)
				for _, part in solid do part.CanCollide = true end
			end)
		else
			for _, part in solid do part.CanCollide = true end
		end
	end
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
	local current = model:GetAttribute("Open") or 0
	local safe = cartSafeDoor(model)
	if safe and current <= .02 then freeCart(model, current) end -- shut on the cart: get it out first
	local open = current > (safe and 0.02 or 0.5) -- a door held part-open by the cart counts as open
	local target = open and 0 or 1
	if safe then
		local list = carts()
		if #list > 0 then
			cartParams.FilterDescendantsInstances = list
			local sign = model:GetAttribute("SwingSign") or 1
			if open then
				target = clearTo(model, sign, current, 0)
			else
				local reach = clearTo(model, sign, 0, 1)
				if reach < 1 then local other = clearTo(model, -sign, 0, 1); if other > reach then sign, reach = -sign, other end end
				model:SetAttribute("SwingSign", sign)
				target = reach
			end
		end
	end
	if math.abs(target - current) > 0.01 then
		animate(model, target, model:GetAttribute("Kind") == "drawer" and DRAWER_TIME or DOOR_TIME * (safe and math.max(.4, math.abs(target - current)) or 1))
	end
	busy[model] = nil
end

-- The interaction server owns the held-input lease and pickup duration.
local GRAB_SECONDS=.1 -- owner 2026-10-29: grabbing felt laggy (was .22)
local HOLD_LEASE=2.5 -- a lag spike must not drop what a player carries; letting go still ends it at once (holdEnd)
local grabs={}
local function lobbyItem(player,model)
 local s=ReplicatedStorage:FindFirstChild('LobbyState');local world=workspace:FindFirstChild('LobbyWorld');local toys=world and world:FindFirstChild('Toys');local items=toys and toys:FindFirstChild('RuntimeToys')
 return s and s:GetAttribute('Mode')=='Menu' and player:GetAttribute('LobbyReady')==true and player:GetAttribute('MissionActive')~=true and typeof(model)=='Instance' and model:IsA('Model') and model.Parent==items and model:GetAttribute('LobbyToy')==true and model:GetAttribute('Kind')=='pickup'
end
local function grabAllowed(player,model)
 return typeof(model)=='Instance' and model:GetAttribute('InChute')~=true and (player:GetAttribute('MissionActive')==true and model.Parent==interactive or lobbyItem(player,model))
end
local function endGrab(player,dropRay)
 local g=grabs[player];grabs[player]=nil;player:SetAttribute('PhysicalGrabActive',nil)
 if not g then return end
 if g.phase=='held' then local api=game.ServerStorage:FindFirstChild(g.model:GetAttribute('Kind')=='cart' and 'RecoveryApi' or 'CursedItemApi');if api then api:Invoke('release',player,g.model,dropRay) end end
 if player.Parent then event:FireClient(player,'grabEnded',g.model) end
end
local function beginGrab(player,model)
 if player:GetAttribute('MonsterJumpscareActive') or grabs[player] or hiddenIn[player] or crawling[player] or (player:GetAttribute('CursedHeldCount') or 0)>0 then return end
 local root=rootOf(player)
 if not root or typeof(model)~='Instance' or not model:IsA('Model') or not grabAllowed(player,model) or not model.PrimaryPart or (model:GetAttribute('Kind')~='pickup' and model:GetAttribute('Kind')~='cart') or model:GetAttribute('HeldBy')==player.UserId then return end
 if (root.Position-model.PrimaryPart.Position).Magnitude>MAX_REACH then return end
 local g={model=model,phase='reach',last=os.clock()};grabs[player]=g
 local instant=model:GetAttribute('Kind')=='cart'
 event:FireClient(player,'grabStarted',model,instant and 0 or GRAB_SECONDS)
 local function finishGrab()
  if grabs[player]~=g then return end
  local r=rootOf(player)
  if not r or hiddenIn[player] or crawling[player] or os.clock()-g.last>HOLD_LEASE or not grabAllowed(player,model) or not model.PrimaryPart or (r.Position-model.PrimaryPart.Position).Magnitude>MAX_REACH then endGrab(player);return end
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

-- World features (2026-10-27, WorldA; MapGen.Furnisher.WorldFeatures places them; World_shared.md): laundry chute (Kind
-- 'chute'), crawl hatch ('hatch'), WorldB's wall safe ('safe'). 'use' (E / X / square / the phone button) lands in
-- useWorldFeature; partName is the part the client's aim ray hit (safe dials and handle). Everything is checked again here.
local featureState=setmetatable({},{__mode='k'}) -- [Model] = {flapBase, readyAt, ...}; the map is rebuilt with this script
local function stateOf(model) local st=featureState[model];if not st then st={};featureState[model]=st end;return st end
local function featureNoise(pos,loudness,kind,actor)
 local bus=game.ServerStorage:FindFirstChild('MonsterEvidence');if bus then bus:Fire(pos,loudness,kind,actor) end
end
-- The item in this player's hand: the grab this script holds, or (tests, gear) any pickup marked HeldBy them.
local function heldItem(player)
 local g=grabs[player];if g and g.phase=='held' and g.model.Parent==interactive then return g.model end
 for _,m in interactive:GetChildren() do if m:GetAttribute('Kind')=='pickup' and m:GetAttribute('HeldBy')==player.UserId then return m end end
 return nil
end
-- Top-hinged flaps (chute, hatch): angle > 0 swings the bottom edge out of the wall, < 0 into it.
local function swingFlap(model,angle,duration)
 local flap=model:FindFirstChild('Flap');if not flap or not flap:IsA('BasePart') then return end
 local st=stateOf(model);st.flapBase=st.flapBase or flap.CFrame
 local hinge=st.flapBase*CFrame.new(0,flap.Size.Y/2,0)
 TweenService:Create(flap,TweenInfo.new(duration,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{CFrame=hinge*CFrame.Angles(math.rad(angle),0,0)*hinge:ToObjectSpace(st.flapBase)}):Play()
end
-- A short grey dust puff at a feature (no lights, 1 burst).
local function featurePuff(part,count)
 if not part then return end
 local fx=Instance.new('ParticleEmitter');fx.Texture='rbxasset://textures/particles/smoke_main.dds';fx.Color=ColorSequence.new(Color3.fromRGB(170,165,160))
 fx.Size=NumberSequence.new(.6,1.8);fx.Transparency=NumberSequence.new(.45,1);fx.Lifetime=NumberRange.new(.5,.9);fx.Speed=NumberRange.new(3,6);fx.SpreadAngle=Vector2.new(60,60);fx.Rate=0;fx.Parent=part
 fx:Emit(count or 14);game:GetService('Debris'):AddItem(fx,1.5)
end

-- Laundry chute: 'use' on the top hatch while carrying an item sends that item down; 2 s later it shoots out of the
-- bottom hatch onto the floor with a clang the monsters hear (and yells WHEEE). One item per 5 s per chute.
local CHUTE_FALL,CHUTE_COOLDOWN=2,5
local function useChute(player,top)
 if top:GetAttribute('ChuteEnd')~='top' then return end
 local st=stateOf(top)
 local item=heldItem(player)
 local bottom=interactive:FindFirstChild(top:GetAttribute('Pair') or '')
 local api=game.ServerStorage:FindFirstChild('CursedItemApi')
 if not item or not api or not bottom or not bottom.PrimaryPart or os.clock()<(st.readyAt or 0) then Audio.Play('LockedAttempt',top);return end
 local exit=bottom.PrimaryPart.CFrame -- the bottom hatch's pivot, CHUTE_Y above its floor, facing into the room
 -- hide: anchored under the downstairs floor while it "falls"; out: in front of the bottom flap, a stud above the floor
 local route={hide=exit*CFrame.new(0,-7.5,0),out=exit*CFrame.new(0,-1.2,-2),delay=CHUTE_FALL}
 if not api:Invoke('chute',player,item,route) then Audio.Play('LockedAttempt',top);return end
 endGrab(player) -- the hand is empty now: clears the grab lease and tells the client (grabEnded)
 st.readyAt=os.clock()+CHUTE_COOLDOWN;top:SetAttribute('ChuteReadyAt',workspace:GetServerTimeNow()+CHUTE_COOLDOWN)
 player:SetAttribute('GrinUntil',workspace:GetServerTimeNow()+2.2) -- VoiceMouthClient: a proud grin
 swingFlap(top,70,.18);Audio.Play('SandSlide',top);featureNoise(top.PrimaryPart.Position,15,'laundry chute',player)
 task.delay(.7,function() if top.Parent then swingFlap(top,0,.3) end end)
 task.delay(CHUTE_FALL-.15,function()
  if not bottom.Parent then return end
  swingFlap(bottom,75,.12);Audio.Play('AnvilClang',bottom);featurePuff(bottom:FindFirstChild('Flap') or bottom.PrimaryPart,16) -- CursedItemsServer makes the landing noise
  task.delay(.9,function() if bottom.Parent then swingFlap(bottom,0,.3) end end)
 end)
end

-- Crawl hatch: 'use' with empty hands slides you through the wall to the paired hatch (1.05 s, root anchored like the
-- closet walk-in, monster-proof while it runs). The cart and monsters cannot follow; both flaps jam 3 s after a crawl.
local CRAWL_IN,CRAWL_THROUGH,CRAWL_JAM,HATCH_OUT=.3,.75,3,2.6 -- s to line up; s through the wall; s both flaps stay shut; studs out
local function useHatch(player,hatch)
 local other=interactive:FindFirstChild(hatch:GetAttribute('Pair') or '')
 local root,hum=rootOf(player)
 if not root or not other or not other.PrimaryPart or crawling[player] then return end
 if heldItem(player) or grabs[player] or (player:GetAttribute('CursedHeldCount') or 0)>0 then Audio.Play('LockedAttempt',hatch);return end -- grabs: a grab still reaching would finish mid-crawl -- client: HANDS FULL
 local now=workspace:GetServerTimeNow()
 if now<(hatch:GetAttribute('HatchJamUntil') or 0) then return end
 local jam=now+CRAWL_IN+CRAWL_THROUGH+CRAWL_JAM
 hatch:SetAttribute('HatchJamUntil',jam);other:SetAttribute('HatchJamUntil',jam)
 crawling[player]=true
 player:SetAttribute('ClosetProtectedUntil',now+CRAWL_IN+CRAWL_THROUGH+.6) -- MonsterProtection: no catch mid-crawl
 local a,b=hatch.PrimaryPart.CFrame,other.PrimaryPart.CFrame -- pivots on the floor, facing out of each hatch
 local front,mouth,out=a*CFrame.new(0,HIP,-HATCH_OUT),a*CFrame.new(0,HIP,0),b*CFrame.new(0,HIP,-HATCH_OUT)
 root.Anchored=true;hum.AutoRotate=false
 -- Failsafe (owner 2026-10-27, no stuck players): whatever breaks mid-crawl, the player is let go shortly after.
 task.delay(CRAWL_IN+CRAWL_THROUGH+3,function()if crawling[player]then crawling[player]=nil;local r3,h3=rootOf(player);if r3 then r3.Anchored=false;h3.AutoRotate=true end end end)
 event:FireClient(player,'crawl',nil,CRAWL_IN+CRAWL_THROUGH) -- InteractController: crawl-height camera + squeeze
 swingFlap(hatch,-55,.2);Audio.Play('ClothHandle',hatch);Audio.Play('DrawerClose',hatch);featureNoise(a.Position,18,'hatch flap',player)
 pcall(tweenRoot,root,CFrame.lookAt(front.Position,mouth.Position),CRAWL_IN) -- an error here must never skip the release below
 task.delay(CRAWL_THROUGH*.5,function()
  if other.Parent then swingFlap(other,60,.18);Audio.Play('DrawerClose',other);featureNoise(b.Position,18,'hatch flap',player);featurePuff(other:FindFirstChild('Flap') or other.PrimaryPart,12) end
 end)
 if root.Parent then pcall(tweenRoot,root,CFrame.lookAt(out.Position,out.Position+b.LookVector),CRAWL_THROUGH) end
 task.delay(.5,function() if hatch.Parent then swingFlap(hatch,0,.3) end;if other.Parent then swingFlap(other,0,.3) end end)
 crawling[player]=nil
 local r2,h2=rootOf(player)
 if r2 then r2.Anchored=false;h2.AutoRotate=true end
 player:SetAttribute('ClosetProtectedUntil',workspace:GetServerTimeNow()+.6)
 player:SetAttribute('GrinUntil',workspace:GetServerTimeNow()+1.8) -- popped out the other side: a cheeky grin
end

-- Shared dispatch (WorldB: assign useSafe / safeCodes below for the wall safe; World_shared.md).
local useSafe: ((Player, Model, string?) -> ())? = nil -- WorldB wall safe assigns it
local safeCodes: {[Instance]: string}? = nil -- WorldB wall safe: tests read it through WorldFeatureTestApi 'code'
-- Wall safe (WorldB 2026-10-27; World/WallSafe): three dials (1-6), one step per 'use' on that dial; 'use' on the handle
-- opens it when the dials match the code on the note (MapGen), else a loud rattle and a 2 s jam. Open: the door swings
-- and one sellable item from this level's list drops in front of it (CursedItemApi 'worldGift'). Funny beats: a wrong
-- pull = shocked face + "STUCK!"; the right code = grin + "CLICK! It opens!" for the opener.
local SAFE_JAM,SAFE_VALUE,SAFE_VALUE_L1=2,90,52 -- jam seconds; reward on level 2+ before valueScale; level 1
local codes=setmetatable({},{__mode='k'}) -- [safe] = code; read once, then taken off the replicated model
safeCodes=codes
local function dialGui(safe,i)
 local dial=safe:FindFirstChild('Dial'..i,true);if not dial then return end
 local gui=dial:FindFirstChild('DialDigit') or Instance.new('SurfaceGui')
 gui.Name='DialDigit';gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(100,100);gui.LightInfluence=1;gui.Parent=dial
 local label=gui:FindFirstChild('Digit') or Instance.new('TextLabel')
 label.Name='Digit';label.BackgroundTransparency=1;label.Size=UDim2.fromScale(.6,.6);label.Position=UDim2.fromScale(.2,.2)
 label.Font=Enum.Font.GothamBlack;label.TextScaled=true;label.TextColor3=Color3.fromRGB(34,36,42)
 label.Text=tostring(safe:GetAttribute('Dials') or '111'):sub(i,i);label.Parent=gui
end
local function wobble(part,degrees)
 if not part then return end
 local st=stateOf(part);st.base=st.base or part.CFrame
 TweenService:Create(part,TweenInfo.new(.08,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,true),{CFrame=st.base*CFrame.Angles(0,0,math.rad(degrees))}):Play()
end
local function safeReact(player,mood,seconds,text,shake) -- FaceBeat face + ReactPop word (shared contracts)
 local t=workspace:GetServerTimeNow();player:SetAttribute('FaceBeat',mood);player:SetAttribute('FaceBeatUntil',t+seconds)
 player:SetAttribute('ReactPop',text);player:SetAttribute('ReactPopShake',shake or 0);player:SetAttribute('ReactPopAt',t)
end
local function openSafe(player,safe)
 safe:SetAttribute('SafeOpen',true);codes[safe]=nil
 local pivot=safe:GetPivot();local depth=(safe:GetAttribute('Footprint') or Vector3.new(3.2,3.5,3.2)).Z
 Audio.Play('Unlock',safe);task.delay(.25,function() Audio.Play('DoorOpen',safe) end)
 featureNoise(pivot.Position,30,'safe opened',player)
 safeReact(player,'grin',3,'CLICK! It opens!')
 local door=safe:FindFirstChild('Door',true)
 if door then
  local side=safe:GetAttribute('HingeSide') or 1 -- which edge of the door has the hinges, in the safe's own X
  local hinge=door.CFrame*CFrame.new(side*door.Size.X/2,0,-door.Size.Z/2)
  local riders={}
  for _,name in {'Door','Dial1','Dial2','Dial3','Handle'} do local p=safe:FindFirstChild(name,true);if p then riders[p]=hinge:ToObjectSpace(stateOf(p).base or p.CFrame) end end
  local v=Instance.new('NumberValue')
  v.Changed:Connect(function(a) local h=hinge*CFrame.Angles(0,math.rad(-side*105*a),0);for p,rel in riders do p.CFrame=h*rel end end)
  local tw=TweenService:Create(v,TweenInfo.new(.9,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Value=1});tw:Play()
  tw.Completed:Once(function() v:Destroy() end)
 end
 local round=ReplicatedStorage:FindFirstChild('RecoveryRound');local level=math.max(1,round and round:GetAttribute('Round') or 1)
 local value=level==1 and SAFE_VALUE_L1 or math.floor(SAFE_VALUE*(1+.12*(level-1))) -- LootBudget.Plan's valueScale
 local api=game.ServerStorage:FindFirstChild('CursedItemApi')
 local base=(pivot*CFrame.new(0,0,-(depth/2+1.6))).Position
 task.delay(.6,function() if api and safe.Parent then api:Invoke('worldGift',player,base,value) end end)
end
useSafe=function(player,safe,partName)
 if safe:GetAttribute('SafeOpen') then return end
 local st=stateOf(safe)
 local dial=type(partName)=='string' and tonumber(partName:match('^Dial([123])$'))
 if dial then
  if os.clock()<(st.dialAt or 0) then return end;st.dialAt=os.clock()+.12
  local digits=tostring(safe:GetAttribute('Dials') or '111')
  local d=(tonumber(digits:sub(dial,dial)) or 1)%6+1
  safe:SetAttribute('Dials',digits:sub(1,dial-1)..d..digits:sub(dial+1))
  dialGui(safe,dial);wobble(safe:FindFirstChild('Dial'..dial,true),-20)
  Audio.Play('ClockTick',safe);featureNoise(safe:GetPivot().Position,6,'safe dial',player)
  return
 end
 if partName~='Handle' or os.clock()<(st.jamUntil or 0) then return end -- door / body: the prompt explains, nothing happens
 if codes[safe] and safe:GetAttribute('Dials')==codes[safe] then openSafe(player,safe);return end
 st.jamUntil=os.clock()+SAFE_JAM;safe:SetAttribute('SafeJamUntil',workspace:GetServerTimeNow()+SAFE_JAM)
 wobble(safe:FindFirstChild('Handle',true),35);Audio.Play('LockedAttempt',safe);Audio.Play('MetalImpact',safe)
 featureNoise(safe:GetPivot().Position,40,'safe rattle',player)
 safeReact(player,'gasp',1.2,'STUCK! Wrong code',.35)
end
for _,m in interactive:GetChildren() do
 if m:IsA('Model') and m:GetAttribute('Kind')=='safe' then
  codes[m]=m:GetAttribute('SafeCode');m:SetAttribute('SafeCode',nil);m:SetAttribute('Dials','111')
  for i=1,3 do dialGui(m,i) end
 end
end
local function useWorldFeature(player,model,partName)
 local kind=model:GetAttribute('Kind')
 if kind~='chute' and kind~='safe' and kind~='hatch' then return false end
 if crawling[player] then return true end
 if kind=='chute' then useChute(player,model)
 elseif kind=='safe' and useSafe then useSafe(player,model,partName)
 elseif kind=='hatch' then useHatch(player,model) end
 return true
end
-- Studio tests (rbxdev scenarios): drive a feature as `player` without a client ('code' reads a safe's code).
if game:GetService('RunService'):IsStudio() then
 local testApi=Instance.new('BindableFunction');testApi.Name='WorldFeatureTestApi';testApi.Parent=script
 testApi.OnInvoke=function(player,model,partName)
  if typeof(model)~='Instance' or model.Parent~=interactive then return false end
  if partName=='code' then return safeCodes and safeCodes[model] end
  return useWorldFeature(player,model,partName)
 end
end

event.OnServerEvent:Connect(function(player, action, target, partName)
 if player:GetAttribute('MonsterJumpscareActive') then endGrab(player);return end
 if action=='holdEnd' then
  local ray=type(target)=='table'and AntiCheat.Allow(player,'touchDrop',6,10)and target or nil
  endGrab(player,ray);return
 end
 if type(action)~='string' or (action~='holdKeep' and action~='holdBegin' and action~='leave' and action~='use') then return end
 if not AntiCheat.Allow(player,action=='holdKeep' and 'grabLease' or 'interact',action=='holdKeep' and 15 or 10,action=='holdKeep' and 30 or 20) then return end
 -- While the field map is out nothing new starts, but what is in hand stays (holdKeep still refreshes it).
 if player:GetAttribute('MapOpen') and action~='holdKeep' then return end
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
	if useWorldFeature(player,target,partName) then return end
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
	elseif target:GetAttribute("Kind") == "door" or target:GetAttribute("Kind") == "drawer" then
		toggleMover(target) -- only movers swing: a 'use' on a close-up choice prop (Kind 'choice') crashed poseFor (live V1249)
	end
end)

local function forget(player)
 player:SetAttribute("ClosetState",nil)
 player:SetAttribute("ClosetProtectedUntil",nil)
 endGrab(player)
 crawling[player]=nil
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
 -- Door Wedge gear (GearShopServer): a wedged door holds against monsters; each refused try is a bash that wears it down.
 if (model:GetAttribute('WedgedUntil')or 0)>workspace:GetServerTimeNow()then model:SetAttribute('WedgeBumpAt',os.clock());return false end
 if (model:GetAttribute('Open')or 0)>.02 then return true end -- part-open (held by the cart) is open enough
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


-- Door slam (owner 2026-10-25): on every 5th level, once the next sale would meet the quota (the same check as the
-- CART READY TO SELL banner), an open door near the spawn slams shut by itself, as if the monsters got mad. A shut
-- one rattles hard instead. Every player's camera shakes (CurseEffectsClient), seen or not.
-- Owner 2026-10-25: the slam happens right by a player (was: within 70 studs of the spawn). It stays queued, retried
-- every second, until a door that close can shut without touching the cart or anyone standing in the doorway.
local SLAM_EVERY,SLAM_RADIUS,SLAM_CHANCE,SLAM_DOORWAY=5,30,.2,4.5 -- every 5th level; studs from a player; per-second chance once ready; doorway clearance
local slamEvent=ReplicatedStorage:FindFirstChild('DoorSlamEvent')or Instance.new('RemoteEvent')
slamEvent.Name='DoorSlamEvent';slamEvent.Parent=ReplicatedStorage
local slammedRound
local function slamDoor(force)
 local s=ReplicatedStorage:FindFirstChild('RecoveryRound');if not s then return false end
 local round=s:GetAttribute('Round')or 1
 if not force then
  if round%SLAM_EVERY~=0 or slammedRound==round then return false end
  local cart=s:GetAttribute('CartValue')or 0
  if s:GetAttribute('Phase')~='Searching'or s:GetAttribute('SaleEnds')~=nil or cart<=0 or(s:GetAttribute('Sold')or 0)+cart<(s:GetAttribute('Quota')or math.huge)then return false end
  if math.random()>SLAM_CHANCE then return false end -- a few seconds after the cart is ready, never on the same frame
 end
 local map=workspace:FindFirstChild('Mansion');local folder=map and map:FindFirstChild('Interactive')
 if not folder then return false end
 local roots={}
 for _,p in Players:GetPlayers()do
  local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
  if r and h and h.Health>0 and p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true then table.insert(roots,r.Position)end
 end
 if #roots==0 then return false end
 local function nearest(pos)local best=math.huge;for _,q in roots do best=math.min(best,(q-pos).Magnitude)end;return best end
 local open,shut={},{}
 for _,m in folder:GetChildren()do
  if m:IsA('Model')and m:GetAttribute('Kind')=='door'and not m:GetAttribute('Closet')and not m:GetAttribute('Locked')and not busy[m]and m.PrimaryPart
   and typeof(m:GetAttribute('ClosedPivot'))=='CFrame'and nearest(m.PrimaryPart.Position)<=SLAM_RADIUS
   and nearest(m:GetAttribute('ClosedPivot').Position)>SLAM_DOORWAY then
   cartParams.FilterDescendantsInstances=carts();local sign=m:GetAttribute('SwingSign')or 1;local cur=m:GetAttribute('Open')or 0
   -- never a door that would close on the cart, or rattle into it
   if cur>.3 then if clearTo(m,sign,cur,0)<=.02 then table.insert(open,m)end elseif not doorHitsCart(m,sign,.2)then table.insert(shut,m)end
  end
 end
 local list=#open>0 and open or shut;if #list==0 then return false end -- nothing safe yet: tried again next second
 table.sort(list,function(a,b)return nearest(a.PrimaryPart.Position)<nearest(b.PrimaryPart.Position)end)
 local door=list[math.random(1,math.min(2,#list))] -- one of the two closest
 slammedRound=round;busy[door]=true
 local pos=door.PrimaryPart.Position
 task.spawn(function()
  if(door:GetAttribute('Open')or 0)>.3 then animate(door,0,.14)else animate(door,.2,.18);task.wait(.05);animate(door,0,.09)end
  -- the bang comes from the door itself, in 3D: loud close by, fading with distance (owner 2026-10-25)
  local at=door:FindFirstChild('Door')or door:FindFirstChild('Slab')or door.PrimaryPart
  local bang=Instance.new('Sound');bang.Name='DoorSlamBang';bang.SoundId='rbxassetid://82228025681045';bang.Volume=2;bang.PlaybackSpeed=.92
  bang.RollOffMode=Enum.RollOffMode.InverseTapered;bang.RollOffMinDistance=12;bang.RollOffMaxDistance=160;bang.Parent=at;bang:Play()
  game:GetService('Debris'):AddItem(bang,5)
  local dust=Instance.new('ParticleEmitter');dust.Texture='rbxasset://textures/particles/smoke_main.dds';dust.Color=ColorSequence.new(Color3.fromRGB(150,140,130))
  dust.Size=NumberSequence.new(1.5,4);dust.Transparency=NumberSequence.new(.5,1);dust.Lifetime=NumberRange.new(.8,1.4);dust.Speed=NumberRange.new(4,9);dust.SpreadAngle=Vector2.new(70,70);dust.Rate=0;dust.Parent=at
  dust:Emit(30);game:GetService('Debris'):AddItem(dust,2)
  Audio.Play('StingThunder',door)
  slamEvent:FireAllClients(pos)
  freeCart(door,door:GetAttribute('Open')or 0) -- belt and braces: the cart moved in during the swing
  busy[door]=nil
 end)
 return true
end
task.spawn(function()while true do task.wait(1);pcall(slamDoor,false)end end)
local slamApi=Instance.new('BindableFunction');slamApi.Name='DoorSlamApi';slamApi.Parent=script
slamApi.OnInvoke=function()slammedRound=nil;return slamDoor(true)end -- tests: slam one now
-- World happenings (WorldB 2026-10-27): flood valve, storm window, swinging chandelier, hero rosettes (runtime-placed props).
require(script:WaitForChild('WorldHappenings')).Init()
