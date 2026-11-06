-- Dungeon / Birthday / Cruise revamp (2026-10-21): dresses those three map kinds with the rbxkit props in
-- ServerStorage.RevampKit (Dng_*, Bday_*, Crz_*). Every kit model has an invisible Pivot at its bottom centre and
-- faces -Z (front into the room, back against the wall).
-- Cosmetic only, like SchoolDressing: nothing collides, nothing is queryable, every part is NonBlockingDetail.
-- Exception: tables and desks (SOLID) get an invisible collider in mansion.Collision.
-- Upright pieces stand against walls, clear of doorways, furniture, closets, windows and angled corners; flat
-- pieces (rugs, flagstones, tiles) lie on the floor. A few fixtures get a soft light.
local AngledCorners = require(script.Parent.AngledCorners)
local M = {}
local FLOOR_H, CEIL = 16, 14
local DOOR_CLEAR = 7
local MAX_LIGHTS = 10 -- extra soft lights per map (was 40: Cruise frame rate dropped hard, 2026-10-22)
local MAX_PROPS = 140 -- all dressing props per map

local function kitModel(kit, name) return kit and kit:FindFirstChild(name) end

local function floorClear(mansion, pos, size)
	if AngledCorners.Blocked(mansion, pos, Vector2.new(size.X, size.Z).Magnitude / 2) then return false end
	local col = mansion:FindFirstChild("Collision")
	if not col then return true end
	local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Include; op.FilterDescendantsInstances = { col }
	for _, hit in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, size.Y / 2 + 0.05, 0)), size, op)) do
		if hit:GetAttribute("Furniture") or hit.Name ~= "Floor" and hit.Name ~= "Wall" and hit.Name ~= "Ceiling" then return false end
	end
	return true
end
-- cf: on the wall surface, LookVector INTO the wall (SchoolDressing's convention).
local function wallClear(mansion, cf, width, height, folder)
	if AngledCorners.Blocked(mansion, cf.Position, width / 2 + 0.3) then return false end
	local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Include; op.RespectCanCollide = false
	op.FilterDescendantsInstances = { mansion.Furniture, mansion.Interactive, mansion.Closets }
	if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0, 1.2), Vector3.new(width + 0.4, height + 0.4, 2.2), op) > 0 then return false end
	local arch = mansion:FindFirstChild("Architecture")
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include; rp.FilterDescendantsInstances = { arch }
	local inward = -cf.LookVector
	for _, dx in ipairs({ -width / 2 + 0.3, 0, width / 2 - 0.3 }) do
		for _, dy in ipairs({ -height / 2 + 0.3, height / 2 - 0.3 }) do
			local from = (cf * Vector3.new(dx, dy, 0)) + inward * 1.5
			local hit = workspace:Raycast(from, -inward * 3, rp)
			if not hit or not hit.Instance.Parent or hit.Instance.Parent.Name ~= "Wall" or math.abs(hit.Distance - 1.5) > 0.5 then return false end
		end
	end
	return true
end
local function doorways(plan)
	local list = {}
	for _, e in ipairs(plan.edges or {}) do
		if e.kind ~= "stairs" and e.x and e.z then table.insert(list, Vector3.new(e.x, e.y or 0, e.z)) end
	end
	if plan.entrance then table.insert(list, Vector3.new(plan.entrance.x, 0, plan.entrance.z)) end
	return list
end
local function nearDoorway(list, pos, clear)
	for _, p in ipairs(list) do
		if math.abs(p.Y - pos.Y) < 8 and Vector2.new(p.X - pos.X, p.Z - pos.Z).Magnitude < (clear or DOOR_CLEAR) then return true end
	end
	return false
end

-- A spot against one of room r's walls for a model `size` wide (X) and `depth` deep: returns the model CFrame
-- (front -Z facing into the room) and the wall-surface CFrame (LookVector into the wall) for wallClear.
local function wallSpot(r, rng, y, size, side)
	side = side or rng:NextInteger(1, 4)
	local inset = 0.7 -- wall half-thickness inside the room bounds
	local half = size.X / 2 + 0.8
	local back = size.Z / 2
	local cf
	if side == 1 then
		if r.x2 - r.x1 < size.X + 2 then return nil end
		cf = CFrame.new(rng:NextNumber(r.x1 + half, r.x2 - half), y, r.z1 + inset + back) * CFrame.Angles(0, math.pi, 0)
	elseif side == 2 then
		if r.x2 - r.x1 < size.X + 2 then return nil end
		cf = CFrame.new(rng:NextNumber(r.x1 + half, r.x2 - half), y, r.z2 - inset - back)
	elseif side == 3 then
		if r.z2 - r.z1 < size.X + 2 then return nil end
		cf = CFrame.new(r.x1 + inset + back, y, rng:NextNumber(r.z1 + half, r.z2 - half)) * CFrame.Angles(0, -math.pi / 2, 0)
	else
		if r.z2 - r.z1 < size.X + 2 then return nil end
		cf = CFrame.new(r.x2 - inset - back, y, rng:NextNumber(r.z1 + half, r.z2 - half)) * CFrame.Angles(0, math.pi / 2, 0)
	end
	-- cf faces -Z into the room, so +Z (its back) is toward the wall
	local wall = cf * CFrame.new(0, 0, back)
	return cf, wall
end

local placedBoxes = {}
local function overlapsPlaced(pos, size)
	for _, b in ipairs(placedBoxes) do
		if math.abs(b.p.Y - pos.Y) < 6 and math.abs(b.p.X - pos.X) < (b.r + size) and math.abs(b.p.Z - pos.Z) < (b.r + size) then return true end
	end
	return false
end

local lights = 0
local SOLID = { Dng_Table = true, Dng_AlchemyDesk = true, Bday_PartyTable = true, Crz_DiningTable = true } -- the only dressing that collides
-- Owner 2026-10-25: a solid table dropped in a walkway failed MapGen's circulation check and rebuilt the whole map
-- (Birthday loads took up to 30 s). Solid pieces now skip spots that touch the room's keepouts (Furnisher.Keepouts).
local Furnisher = require(script.Parent.Furnisher)
local keepFor -- the current room's keepout boxes, set by M.Apply for SOLID specs
local function blocksWalkway(m)
	if not keepFor then return false end
	local bcf, bsize = m:GetBoundingBox()
	local r = bcf.Rotation
	local ex = math.abs(r.XVector.X) * bsize.X / 2 + math.abs(r.ZVector.X) * bsize.Z / 2
	local ez = math.abs(r.XVector.Z) * bsize.X / 2 + math.abs(r.ZVector.Z) * bsize.Z / 2
	for _, k in ipairs(keepFor) do
		if math.abs(bcf.X - k.x) < ex + k.w / 2 and math.abs(bcf.Z - k.z) < ez + k.d / 2 then return true end
	end
	return false
end
local function place(t, cf, folder, light)
	local m = t:Clone(); m:PivotTo(cf)
	if SOLID[t.Name] and blocksWalkway(m) then m:Destroy(); return nil end
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false -- dressing never casts shadows (frame rate)
			p:SetAttribute("NonBlockingDetail", true)
			if p.Name == "Pivot" then p.Transparency = 1; p.CastShadow = false end
		end
	end
	if light and lights < MAX_LIGHTS then
		local src = m:FindFirstChild("Flame", true) or m:FindFirstChild("Shade", true) or m:FindFirstChild("Glow", true)
		if src and src:IsA("BasePart") then
			local l = Instance.new("PointLight"); l.Name = "RevampLight"; l.Color = light.color; l.Range = light.range or 12; l.Brightness = light.brightness or 0.8; l.Shadows = false
			l.Parent = src; lights += 1
		end
	end
	m.Parent = folder
	if SOLID[t.Name] then
		-- Tables are solid like every other map's (owner 2026-10-22): an invisible box in Collision, as Furnisher does.
		local home = folder;while home and not home:FindFirstChild("Collision") do home = home.Parent end
		if home then
			local bcf, bsize = m:GetBoundingBox()
			local c = Instance.new("Part"); c.Name = t.Name; c.Size = bsize; c.CFrame = bcf; c.Transparency = 1
			c.Anchored = true; c.CanCollide = true; c.CanQuery = true; c.CanTouch = false; c.CastShadow = false
			c:SetAttribute("Furniture", true); c.Parent = home.Collision
		end
	end
	local _, size = m:GetBoundingBox()
	table.insert(placedBoxes, { p = cf.Position, r = math.max(size.X, size.Z) / 2 })
	return m
end
local function sizeOf(t) return t:GetAttribute("KitSize") or select(2, t:GetBoundingBox()) end

-- kinds: wall (stands on the floor, back to the wall), mount (hung on the wall at `h`), ceiling (hangs from the
-- ceiling), flat (lies on the floor, may go mid-room), beam (spans the room at the ceiling).
-- rooms: room types it belongs in ("*" = any non-hall room, "Hall" = halls); n = how many per matching room
-- (fractions are chances); light = soft light on its Flame / Shade / Glow part.
local WARM = Color3.fromRGB(255, 190, 110)
local SPECS = {
	Dungeon = {
		{ "Dng_WallTorch", "mount", { "*", "Hall" }, 1.2, h = 6.2, light = { color = WARM, range = 14, brightness = 0.9 } },
		{ "Dng_StoneWallBlock", "wall", { "*" }, 1.4 },
		{ "Dng_StonePillar", "wall", { "*", "Hall" }, 0.8 },
		{ "Dng_BarredSlit", "mount", { "*" }, 0.6, h = 5.5 },
		{ "Dng_PlankDoor", "wall", { "Storage", "Pantry", "Servants", "AtticStorage", "Hall" }, 0.35 },
		{ "Dng_CellBars", "wall", { "Bedroom", "Servants", "Nursery" }, 1 },
		{ "Dng_Table", "wall", { "Dining", "Kitchen", "Parlor", "Servants" }, 0.7 },
		{ "Dng_Bench", "wall", { "Dining", "Parlor", "Servants", "Hall", "Foyer" }, 0.8 },
		{ "Dng_Stool", "wall", { "Kitchen", "Pantry", "Dining", "Study", "Sewing" }, 0.8 },
		{ "Dng_Barrels", "wall", { "Pantry", "Storage", "Kitchen", "AtticStorage", "Laundry", "Dining" }, 1 },
		{ "Dng_Sacks", "wall", { "Pantry", "Storage", "Kitchen", "AtticStorage" }, 0.8 },
		{ "Dng_ScrollShelf", "wall", { "Library", "Study", "Gallery" }, 1.2 },
		{ "Dng_AlchemyDesk", "wall", { "Study", "Sewing", "Library", "Conservatory" }, 0.8, light = { color = Color3.fromRGB(150, 220, 170), range = 9, brightness = 0.6 } },
		{ "Dng_Rubble", "wall", { "*", "Hall" }, 0.45 },
		{ "Dng_GlowShrooms", "wall", { "Conservatory", "Playroom", "Nursery", "Bath", "AtticStorage", "Laundry" }, 1.2, light = { color = Color3.fromRGB(120, 200, 220), range = 10, brightness = 0.7 } },
		{ "Dng_Chains", "ceiling", { "Bedroom", "Servants", "Storage", "Music", "Hall" }, 0.6 },
		{ "Dng_Cobweb", "corner", { "*", "Hall" }, 0.9 },
		{ "Dng_Chandelier", "ceiling", { "Dining", "Ballroom", "Foyer", "Gallery", "Parlor", "Master" }, 0.8, light = { color = WARM, range = 18, brightness = 0.8 } },
		{ "Dng_Flagstones", "flat", { "*", "Hall" }, 1 },
	},
	Birthday = {
		{ "Bday_WallpaperPanel_Stripe", "wall", { "*" }, 2 },
		{ "Bday_WallpaperPanel_Dots", "wall", { "*" }, 0.8 },
		{ "Bday_Bunting", "mount", { "*", "Hall" }, 0.8, h = 11.2 },
		{ "Bday_Balloons", "wall", { "*", "Hall" }, 0.8 },
		{ "Bday_PartyTable", "wall", { "Dining", "Ballroom", "Parlor", "Foyer", "Kitchen" }, 1 },
		{ "Bday_KidChair", "wall", { "Dining", "Ballroom", "Playroom", "Parlor", "Library" }, 1.2 },
		{ "Bday_Clown", "wall", { "*" }, 0.35 },
		{ "Bday_JackInBox", "wall", { "Playroom", "Nursery", "Gallery", "Storage", "AtticStorage" }, 0.6 },
		{ "Bday_ToyChest", "wall", { "Playroom", "Nursery", "Bedroom", "Storage" }, 0.7 },
		{ "Bday_BallPit", "wall", { "Playroom", "Nursery", "Conservatory" }, 0.7 },
		{ "Bday_Stage", "wall", { "Music", "Ballroom" }, 1 },
		{ "Bday_LollipopLamp", "wall", { "*" }, 0.5, light = { color = Color3.fromRGB(255, 232, 205), range = 10, brightness = 0.7 } },
		{ "Bday_HatLight", "ceiling", { "*" }, 0.5, light = { color = Color3.fromRGB(255, 226, 170), range = 14, brightness = 0.7 } },
		{ "Bday_DoorArch", "wall", { "Foyer", "Ballroom", "Playroom", "Hall" }, 0.35 },
		{ "Bday_GiftTower", "wall", { "*" }, 0.5 },
		{ "Bday_RockingHorse", "wall", { "Playroom", "Nursery", "Bedroom", "Gallery" }, 0.6 },
		{ "Bday_PrizeShelf", "wall", { "Gallery", "Storage", "Playroom", "Study", "Library" }, 0.8 },
		-- Bday_FloorTile (checkered floor mat) removed 2026-10-25 (owner).
	},
	Cruise = {
		{ "Crz_Wainscot", "wall", { "*" }, 1 },
		{ "Crz_Porthole", "mount", { "*" }, 0.4, h = 6.5 },
		{ "Crz_WallSconce", "mount", { "*", "Hall" }, 0.35, h = 6.8, light = { color = Color3.fromRGB(255, 220, 160), range = 13, brightness = 0.8 } },
		{ "Crz_DiningTable", "wall", { "Dining", "Kitchen", "Music" }, 1.2 },
		{ "Crz_DiningChair", "wall", { "Dining", "Study", "Library", "Music" }, 1.2 },
		{ "Crz_BunkBed", "wall", { "Servants", "Bedroom", "Nursery" }, 1 },
		{ "Crz_Luggage", "wall", { "Foyer", "Storage", "Bedroom", "Master", "AtticStorage" }, 0.4 },
		{ "Crz_LifeJacketRack", "mount", { "Hall", "Gallery", "Conservatory", "Foyer" }, 0.5, h = 3.4 },
		{ "Crz_LifebuoyMount", "mount", { "Hall", "Gallery", "Conservatory", "Foyer", "Laundry" }, 0.6, h = 5.5 },
		{ "Crz_ShipBell", "mount", { "Foyer", "Study", "Gallery", "Conservatory" }, 0.5, h = 5.2 },
		{ "Crz_Telegraph", "wall", { "Study", "Foyer", "Storage", "AtticStorage" }, 0.6 },
		{ "Crz_EnginePipes", "wall", { "Storage", "AtticStorage", "Laundry", "Kitchen" }, 0.5 },
		{ "Crz_TheaterSeats", "wall", { "Ballroom" }, 1 },
		{ "Crz_StageArch", "wall", { "Ballroom" }, 1 },
		{ "Crz_Piano", "wall", { "Music", "Ballroom", "Parlor" }, 0.8 },
		{ "Crz_NewelPost", "wall", { "Foyer", "Stair" }, 0.6, light = { color = WARM, range = 12, brightness = 0.7 } },
		{ "Crz_Rug", "flat", { "*" }, 0.4 },
		{ "Crz_CarpetRunner", "flat", { "Hall" }, 0.5 },
	},
}

local function matches(list, r)
	for _, t in ipairs(list) do
		if t == r.type or t == "*" and r.type ~= "Hall" and r.type ~= "Stair" then return true end
	end
	return false
end
local function count(rng, n)
	local whole = math.floor(n)
	return whole + (rng:NextNumber() < n - whole and 1 or 0)
end

local function placeOne(mansion, plan, r, rng, t, spec, folder, doors)
	local size = sizeOf(t)
	local kind = spec[2]
	local y0 = (r.level or 0) * FLOOR_H
	for _ = 1, 10 do
		if kind == "wall" or kind == "mount" then
			local y = kind == "mount" and y0 + spec.h - size.Y / 2 or y0
			local cf, wall = wallSpot(r, rng, y, size)
			if not cf then return nil end
			local pos = cf.Position
			if nearDoorway(doors, Vector3.new(pos.X, y0, pos.Z), kind == "mount" and 4 or DOOR_CLEAR) or overlapsPlaced(pos, math.max(size.X, size.Z) / 2 + 0.5) then continue end
			local wallCf = wall * CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0) -- surface CFrame, LookVector into the wall
			wallCf = CFrame.lookAt(wallCf.Position, wallCf.Position + (wall.Position - cf.Position).Unit)
			if not wallClear(mansion, wallCf, math.max(1, size.X - 0.4), math.max(1, size.Y - 0.4)) then continue end
			if kind == "wall" and not floorClear(mansion, pos + Vector3.new(0, 0.05, 0), Vector3.new(size.X, math.min(size.Y, 3), size.Z) * 0.95) then continue end
			return place(t, cf, folder, spec.light)
		elseif kind == "ceiling" or kind == "corner" then
			local x, z, yaw
			if kind == "corner" then
				local c = rng:NextInteger(1, 4)
				x = (c == 1 or c == 3) and r.x1 + 0.9 + size.X / 2 or r.x2 - 0.9 - size.X / 2
				z = (c <= 2) and r.z1 + 0.9 + size.Z / 2 or r.z2 - 0.9 - size.Z / 2
				yaw = ({ math.pi * 0.75, -math.pi * 0.75, math.pi * 0.25, -math.pi * 0.25 })[c]
			else
				x = rng:NextNumber(r.x1 + 4, math.max(r.x1 + 4, r.x2 - 4)); z = rng:NextNumber(r.z1 + 4, math.max(r.z1 + 4, r.z2 - 4)); yaw = rng:NextNumber(0, math.pi * 2)
			end
			local pos = Vector3.new(x, y0 + CEIL - size.Y - 0.05, z)
			if overlapsPlaced(pos, math.max(size.X, size.Z) / 2) then continue end
			return place(t, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), folder, spec.light)
		elseif kind == "beam" then
			local w, d = r.x2 - r.x1, r.z2 - r.z1
			local along = w >= d and d or w -- the beam spans the short side
			if along < size.X + 1 then return nil end
			local cx, cz = (r.x1 + r.x2) / 2, (r.z1 + r.z2) / 2
			local yaw = w >= d and math.pi / 2 or 0
			return place(t, CFrame.new(cx, y0 + CEIL - size.Y - 0.02, cz) * CFrame.Angles(0, yaw, 0), folder, spec.light)
		elseif kind == "flat" then
			local hall = r.type == "Hall"
			local w, d = r.x2 - r.x1, r.z2 - r.z1
			local yaw = (hall and (w >= d and math.pi / 2 or 0)) or (rng:NextInteger(0, 3) * math.pi / 2)
			local fx = (yaw % math.pi < 0.1) and size.X or size.Z
			local fz = (yaw % math.pi < 0.1) and size.Z or size.X
			if w < fx + 3 or d < fz + 3 then return nil end
			local x = hall and (w >= d and rng:NextNumber(r.x1 + fx / 2 + 1, r.x2 - fx / 2 - 1) or (r.x1 + r.x2) / 2) or rng:NextNumber(r.x1 + fx / 2 + 1.5, r.x2 - fx / 2 - 1.5)
			local z = hall and (w >= d and (r.z1 + r.z2) / 2 or rng:NextNumber(r.z1 + fz / 2 + 1, r.z2 - fz / 2 - 1)) or rng:NextNumber(r.z1 + fz / 2 + 1.5, r.z2 - fz / 2 - 1.5)
			local pos = Vector3.new(x, y0 + 0.02, z)
			if AngledCorners.Blocked(mansion, pos, Vector2.new(fx, fz).Magnitude / 2) then continue end
			return place(t, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), folder, spec.light)
		end
	end
	return nil
end

function M.Apply(mansion, plan)
	local specs = SPECS[plan.mapKind]
	if not specs or mansion:GetAttribute("RevampDressingVersion") then return end
	local kit = game:GetService("ServerStorage"):FindFirstChild("RevampKit")
	if not kit then return end
	local folder = Instance.new("Folder"); folder.Name = "RevampDressing"; folder.Parent = mansion.Architecture
	table.clear(placedBoxes); lights = 0
	local rng = Random.new((plan.seed or 1) + 7717)
	local doors = doorways(plan)
	local total = 0
	local cap = plan.mapKind == "Cruise" and 60 or MAX_PROPS -- Cruise's ship exterior is already heavy
	-- Big pieces first, so the small ones fill around them.
	local order = table.clone(specs)
	table.sort(order, function(a, b)
		local ta, tb = kitModel(kit, a[1]), kitModel(kit, b[1])
		local sa, sb = ta and sizeOf(ta) or Vector3.zero, tb and sizeOf(tb) or Vector3.zero
		return sa.X * sa.Z > sb.X * sb.Z
	end)
	for _, spec in ipairs(order) do
		local t = kitModel(kit, spec[1])
		if not t then continue end
		for _, r in ipairs(plan.rooms or {}) do
			if not (r.x1 and r.x2 and r.z1 and r.z2) or not matches(spec[3], r) then continue end
			if (r.x2 - r.x1) < 8 or (r.z2 - r.z1) < 8 then continue end
			for _ = 1, count(rng, spec[4]) do
				if total >= cap then break end
				keepFor = SOLID[spec[1]] and Furnisher.Keepouts(plan, r) or nil
				local ok, m = pcall(placeOne, mansion, plan, r, rng, t, spec, folder, doors)
				keepFor = nil
				if ok and m then total += 1 elseif not ok then warn("[RevampDressing] " .. spec[1] .. ": " .. tostring(m)) end
			end
		end
	end
	mansion:SetAttribute("RevampProps", total); mansion:SetAttribute("RevampLights", lights)
	mansion:SetAttribute("RevampDressingVersion", 1)
	return total
end

return M
