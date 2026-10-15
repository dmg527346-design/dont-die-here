return function(mansion)
-- Key & door server: owns room doors, locked rooms, keys and who holds them.
-- Door movement goes through InteractServer (the one owner of mover state); it asks this script,
-- through ServerStorage.KeyDoorApi, whether a locked door may open and to hand out keys.
-- Every server start: LOCK_COUNT random rooms get one padlocked door and their other doorways boarded up,
-- so the key is the only way in. The rest of the mansion must stay reachable from the start without keys.
-- Every other clear doorway gets an ordinary door (DOOR_CHANCE), which opens with the normal use input.
-- KEY_COUNT plain gold keys, any key opens any locked door. All keys sit in the open area, so a player
-- can never spend keys in a bad order and get stuck (KEY_COUNT >= LOCK_COUNT).
-- Each key is hidden in a random drawer (it slides with the drawer) or, sometimes, lies on a table top.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local graph = require(game.ServerStorage.MapGenBackup.CreatureRoamServer.MansionRoomGraph)

local LOCK_COUNT = 9
local DOOR_CHANCE = 0.85
local START_ROOM = "L0_Starter"
local DOOR_W, DOOR_H, WALL_T = 6, 10, 1.4
local TABLE_CHANCE = 0.45 -- share of keys left on table tops instead of in drawers
local KEY_SIZE = Vector3.new(1.72, 0.26, 3.485) -- the BrassKey mesh at scale 1 (long along Z)
local TABLE_SCALE = 0.55
local DRAWER_SHRINK = 0.75 -- drawer keys are drawn this much smaller than the biggest key that fits
local MIN_DRAWER_SCALE = 0.5 -- drawers too small to fit the key at this scale are skipped
local EXCLUDE = { Spine = true, CrossW = true, CrossE = true, Starter = true, Foyer = true, Stair = true, Stair_top = true }
local KEY_COUNT = 22
local GOLD = Color3.fromRGB(212, 165, 60)
local WOOD = Color3.fromRGB(53, 33, 26)
local WOOD_LIGHT = Color3.fromRGB(122, 85, 53)
local BRASS = Color3.fromRGB(140, 106, 44)

local rng = Random.new()

local interactive = mansion:WaitForChild("Interactive")
local collision = mansion:WaitForChild("Collision")
local folder = Instance.new("Folder")
folder.Name = "KeyDoors"
folder.Parent = mansion


local rooms, adj = {}, {}
for _, r in graph.rooms do rooms[r.name] = r; adj[r.name] = {} end
for _, e in graph.edges do
	table.insert(adj[e.a], e)
	table.insert(adj[e.b], e)
end
local function other(e, n) return e.a == n and e.b or e.a end
local function lockable(n)
	local s = n:match("^L%d_(.+)$")
	return not EXCLUDE[s] and not EXCLUDE[s:match("^(.-)_[NS][EW][io]%d$") or s]
end

local function reach(closed)
	local seen, q = { [START_ROOM] = true }, { START_ROOM }
	while #q > 0 do
		local n = table.remove(q)
		for _, e in adj[n] do
			local o = other(e, n)
			if not seen[o] and not closed[o] then seen[o] = true; table.insert(q, o) end
		end
	end
	return seen
end

-- doorway centre on the floor, LookVector pointing from room a into room b
local function doorwayCF(e)
	local a, b = rooms[e.a], rooms[e.b]
	local base = Vector3.new(e.x, e.y, e.z)
	local dir
	if math.abs(a.x2 - b.x1) < 0.01 then dir = Vector3.xAxis
	elseif math.abs(a.x1 - b.x2) < 0.01 then dir = -Vector3.xAxis
	elseif math.abs(a.z2 - b.z1) < 0.01 then dir = Vector3.zAxis
	else dir = -Vector3.zAxis end
	return CFrame.lookAt(base, base + dir)
end

local blockParams = OverlapParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Include
blockParams.FilterDescendantsInstances = { collision, interactive }

-- nothing in the doorway or the 5 studs either side of it (that is also the swing area)
local function clearDoorway(e)
	local cf = doorwayCF(e)
	for _, side in { -1, 1 } do
		for _, p in workspace:GetPartBoundsInBox(cf * CFrame.new(0, 4.6, side * 3.4), Vector3.new(DOOR_W - 1.2, 8, 5), blockParams) do
			if p.Parent ~= collision or p.CanCollide then return false end
		end
	end
	return true
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props do p[k] = v end
	return p
end

local function boardUp(e)
	local cf = doorwayCF(e) * CFrame.new(0, DOOR_H / 2, 0)
	local m = Instance.new("Model")
	m.Name = "Boarded_" .. e.a .. "_" .. e.b
	part({ Name = "Fill", Size = Vector3.new(DOOR_W, DOOR_H, WALL_T), CFrame = cf, Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = m })
	for i, y in { -3.2, -0.6, 2.2 } do
		for _, face in { -1, 1 } do
			part({ Name = "Plank", Size = Vector3.new(DOOR_W + 0.6, 0.9, 0.25), Color = WOOD_LIGHT, Material = Enum.Material.Wood,
				CFrame = cf * CFrame.new(0, y, face * (WALL_T / 2 + 0.12)) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 8 or -8)), Parent = m })
		end
	end
	m.Parent = folder
end

-- a door mover in InteractServer's format. swingDir: the side the door opens toward (LookVector of cf).
local doorCount = 0
local function makeDoor(e, swingInto)
	local cf = doorwayCF(e)
	if swingInto == e.a then cf = cf * CFrame.Angles(0, math.pi, 0) end
	local hinge = cf * CFrame.new(-DOOR_W / 2 + 0.1, 0, 0)
	doorCount += 1
	local m = Instance.new("Model")
	m.Name = "Mover_RD" .. doorCount
	local pivot = part({ Name = "Pivot", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = hinge, Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
	local slabCF = cf * CFrame.new(0, DOOR_H / 2, 0)
	part({ Name = "Slab", Size = Vector3.new(DOOR_W - 0.25, DOOR_H - 0.1, 0.4), CFrame = slabCF, Color = WOOD, Material = Enum.Material.Wood, Parent = m })
	for _, face in { -1, 1 } do
		for _, y in { -2.3, 2.1 } do
			part({ Name = "Panel", Size = Vector3.new(DOOR_W - 1.8, 3.6, 0.08), CFrame = slabCF * CFrame.new(0, y, face * 0.22),
				Color = WOOD_LIGHT, Material = Enum.Material.Wood, CanCollide = false, Parent = m })
		end
		part({ Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4), CFrame = slabCF * CFrame.new(DOOR_W / 2 - 0.7, -0.6, face * 0.4),
			Color = BRASS, Material = Enum.Material.Metal, CanCollide = false, Parent = m })
	end
	m.PrimaryPart = pivot
	m:SetAttribute("Kind", "door")
	m:SetAttribute("Swing", 100)
	m:SetAttribute("Open", 0)
	m:SetAttribute("ClosedPivot", hinge)
	return m, slabCF
end

local function addPadlock(m, slabCF)
	local color = GOLD
	for _, face in { -1, 1 } do
		local body = part({ Name = "Padlock", Size = Vector3.new(0.9, 1, 0.4), CFrame = slabCF * CFrame.new(DOOR_W / 2 - 1.1, -0.6, face * 0.55),
			Color = color, Material = Enum.Material.Metal, CanCollide = false, Parent = m })
		part({ Name = "Padlock", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 0.75, 0.75), Color = Color3.fromRGB(170, 170, 175), Material = Enum.Material.Metal,
			CFrame = body.CFrame * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(90), 0), CanCollide = false, Parent = m })
		part({ Name = "Padlock", Size = Vector3.new(DOOR_W - 0.4, 0.35, 0.1), CFrame = slabCF * CFrame.new(0, 1.6, face * 0.25),
			Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
		local glow = Instance.new("PointLight")
		glow.Color, glow.Range, glow.Brightness = color, 7, 0.7
		glow.Parent = body
	end
	m:SetAttribute("Locked", true)
end

-- key model: invisible hit box (PrimaryPart) that KeyHud draws the mesh onto, lying flat at `scale`
local function makeKey(i, cf, scale, glow)
	local m = Instance.new("Model")
	m.Name = "Mover_Key" .. i
	local size = KEY_SIZE * scale
	local hit = part({ Name = "Pivot", Size = Vector3.new(size.X + 0.1, 0.35, size.Z + 0.1), CFrame = cf, Transparency = 1, CanCollide = false, CanTouch = false, Parent = m })
	if glow then
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = GOLD, 4, 0.5
		light.Parent = hit
	end
	m.PrimaryPart = hit
	m:SetAttribute("Kind", "key")
	m:SetAttribute("KeyColor", GOLD)
	m:SetAttribute("KeyScale", scale)
	m.Parent = interactive
	return m
end

local function roomAt(pos)
	local level = pos.Y >= 14 and 1 or 0
	for _, r in graph.rooms do
		if r.level == level and pos.X >= r.x1 and pos.X <= r.x2 and pos.Z >= r.z1 and pos.Z <= r.z2 then return r.name end
	end
end

-- drawers: the body is the biggest part that isn't the thin front panel; the key lies on its inner floor
local function drawerSlot(d)
	local pivot = d.PrimaryPart
	local body
	for _, p in d:GetChildren() do
		if p:IsA("BasePart") and p ~= pivot and p.Size.Z > 0.4 and (not body or p.Size.Magnitude > body.Size.Magnitude) then body = p end
	end
	if not body then return end
	local scale = math.min(1, (body.Size.X - 0.5) / KEY_SIZE.Z, (body.Size.Z - 0.3) / KEY_SIZE.X)
	if scale < MIN_DRAWER_SCALE then return end
	scale *= DRAWER_SHRINK
	local inBody = pivot.CFrame:ToObjectSpace(body.CFrame)
	local slack = math.max(0, (body.Size.X - 0.5 - KEY_SIZE.Z * scale) / 2)
	local floorY = -body.Size.Y / 2 + 0.2 + KEY_SIZE.Y * scale / 2 + 0.05
	-- lie along the drawer's width, random side-to-side spot and flipped either way
	local offset = inBody * CFrame.new(rng:NextNumber(-slack, slack), floorY, 0) * CFrame.Angles(0, math.rad(90 + (rng:NextNumber() < 0.5 and 180 or 0)), 0)
	return offset, scale
end

local function drawerKey(i, d)
	local offset, scale = drawerSlot(d)
	local m = makeKey(i, d.PrimaryPart.CFrame * offset, scale, false)
	local pivot = d.PrimaryPart
	-- InteractServer slides the drawer with PivotTo; the key rides along
	pivot:GetPropertyChangedSignal("CFrame"):Connect(function()
		m.PrimaryPart.CFrame = pivot.CFrame * offset
	end)
	return m
end

-- table tops: flat furniture colliders at table height with room for the key
local surfParams = RaycastParams.new()
surfParams.FilterType = Enum.RaycastFilterType.Include
surfParams.FilterDescendantsInstances = { collision, interactive }
local function tableSpot(r)
	local base = r.level * 16
	for _ = 1, 60 do
		local x = rng:NextNumber(r.x1 + 2, r.x2 - 2)
		local z = rng:NextNumber(r.z1 + 2, r.z2 - 2)
		local hit = workspace:Raycast(Vector3.new(x, base + 7, z), Vector3.new(0, -8, 0), surfParams)
		if hit and hit.Instance.Parent == collision and hit.Normal.Y > 0.95 and hit.Position.Y > base + 2.2 and hit.Position.Y < base + 4 then
			local flat = true
			for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1.4), Vector3.new(0, 0, -1.4) } do
				local h2 = workspace:Raycast(Vector3.new(x, base + 7, z) + d, Vector3.new(0, -8, 0), surfParams)
				if not h2 or math.abs(h2.Position.Y - hit.Position.Y) > 0.05 then flat = false; break end
			end
			if flat then
				return CFrame.new(hit.Position + Vector3.new(0, KEY_SIZE.Y * TABLE_SCALE / 2 + 0.03, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			end
		end
	end
end

-- choose rooms --------------------------------------------------------------
local function plan()
	local order = {}
	for n in rooms do if lockable(n) then table.insert(order, n) end end
	for i = #order, 2, -1 do local j = rng:NextInteger(1, i); order[i], order[j] = order[j], order[i] end
	local closed, picks = {}, {}
	for _, n in order do
		if #picks == LOCK_COUNT then break end
		closed[n] = true
		local seen = reach(closed)
		local ok = true
		for m in rooms do if not closed[m] and not seen[m] then ok = false; break end end
		local entries = {}
		for _, e in adj[n] do
			local o = other(e, n)
			-- only onto the free area: a later pick may lock that room too, but its own entrance then
			-- leads further out, so chains always end in the open (never two locked rooms facing each other)
			if e.kind == "door" and seen[o] and clearDoorway(e) then table.insert(entries, e) end
		end
		if ok and #entries > 0 then
			table.insert(picks, { room = n, door = entries[rng:NextInteger(1, #entries)] })
		else
			closed[n] = nil
		end
	end
	return picks, closed
end

local picks, closed = plan()
if #picks < LOCK_COUNT then warn("[KeyDoors] only found", #picks, "lockable rooms") end
local done = {}
for i, p in picks do
	local m, slabCF = makeDoor(p.door, p.room)
	addPadlock(m, slabCF)
	m.Parent = interactive
	done[p.door] = true
	for _, e in adj[p.room] do
		if not done[e] and e.kind == "door" then done[e] = true; boardUp(e) end
	end
end

-- ordinary doors on most remaining clear doorways, swinging into the room (not the hallway)
local plain = 0
for _, e in graph.edges do
	if e.kind == "door" and not done[e] and rng:NextNumber() < DOOR_CHANCE and clearDoorway(e) then
		local into = (e.b:find("Spine") or e.b:find("Cross")) and e.a or e.b
		local m = makeDoor(e, into)
		m.Parent = interactive
		plain += 1
	end
end

local open = {}
for n in reach(closed) do if not n:find("Foyer") then table.insert(open, n) end end
-- every drawer in an open room that the key fits in, shuffled; one key per drawer
local isOpen = {}
for _, n in open do isOpen[n] = true end
local drawers = {}
for _, d in interactive:GetChildren() do
	if d:GetAttribute("Kind") == "drawer" and d.PrimaryPart and isOpen[roomAt(d.PrimaryPart.Position)] and drawerSlot(d) then
		table.insert(drawers, d)
	end
end
for i = #drawers, 2, -1 do local j = rng:NextInteger(1, i); drawers[i], drawers[j] = drawers[j], drawers[i] end

local inDrawers, onTables = 0, 0
local usedRoom = {}
local function placeOnTable(i)
	for try = 1, 30 do
		local n = open[rng:NextInteger(1, #open)]
		if not usedRoom[n] or try > 20 then
			local cf = tableSpot(rooms[n])
			if cf then usedRoom[n] = true; onTables += 1; return makeKey(i, cf, TABLE_SCALE, true) end
		end
	end
end
for i = 1, KEY_COUNT do
	local placed = rng:NextNumber() < TABLE_CHANCE and placeOnTable(i)
	if not placed and #drawers > 0 then
		placed = drawerKey(i, table.remove(drawers))
		inDrawers += 1
	end
	if not placed then placed = placeOnTable(i) end
	if not placed then warn("[KeyDoors] could not place key", i) end
end
print(("[KeyDoors] keys: %d in drawers, %d on tables"):format(inDrawers, onTables))
print(("[KeyDoors] %d locked rooms, %d doors, keys placed"):format(#picks, plain))


end


