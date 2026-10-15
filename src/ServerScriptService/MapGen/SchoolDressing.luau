-- School map finish: a trashed, long-abandoned elementary school. Reuses the hospital shell (tiles, troffers, door
-- plaques) and adds chalkboard scrawl, alphabet banners, kids' drawings, graffiti, hall lockers, scattered papers,
-- crayons, books and backpacks, fallen ceiling tiles, puddles and broken glass.
-- Cosmetic only: every added part is non-queryable and tagged NonBlockingDetail; only the hall lockers collide.
local H = require(script.Parent.HospitalDressing)
local M = {}
local FLOOR_H = 16
local CHALK = Color3.fromRGB(232, 230, 220)

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("NonBlockingDetail", true)
	p.Parent = parent
	return p
end

local function label(p, face, text, font, color, canvas, rotation)
	local gui = Instance.new("SurfaceGui"); gui.Face = face; gui.CanvasSize = canvas or Vector2.new(400, 200); gui.LightInfluence = 1
	gui.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(0.94, 0.9); t.Position = UDim2.fromScale(0.03, 0.05); t.BackgroundTransparency = 1
	t.Text = text; t.Font = font; t.TextScaled = true; t.TextColor3 = color; t.Rotation = rotation or 0; t.TextWrapped = true
	t.Parent = gui
	return gui, t
end

-- Same checks the hospital uses: floor items stay out of furniture, wall items only on plain wall.
-- Diagonal corner cuts (MapGen.AngledCorners): nothing goes behind or through one.
local AngledCorners = require(script.Parent.AngledCorners)
local function floorClear(mansion, pos, size)
	if AngledCorners.Blocked(mansion, pos, Vector2.new(size.X, size.Z).Magnitude / 2) then return false end -- any yaw
	local col = mansion:FindFirstChild("Collision")
	if not col then return true end
	local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Include; op.FilterDescendantsInstances = { col }
	for _, hit in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, size.Y / 2 + 0.05, 0)), size, op)) do
		if hit:GetAttribute("Furniture") or hit.Name ~= "Floor" and hit.Name ~= "Wall" and hit.Name ~= "Ceiling" then return false end
	end
	return true
end
local function wallClear(mansion, cf, width, height)
	if AngledCorners.Blocked(mansion, cf.Position, width / 2 + 0.3) then return false end
	-- Nothing standing in front of this wall patch (chalkboards, lockers, shelves, closets, doors).
	local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Include; op.RespectCanCollide = false
	op.FilterDescendantsInstances = { mansion.Furniture, mansion.Interactive, mansion.Closets }
	if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0, 1.2), Vector3.new(width + 0.4, height + 0.4, 2.2), op) > 0 then return false end
	-- Hall locker banks are dressing (not queryable): test their boxes directly.
	local dressing = mansion.Architecture:FindFirstChild("SchoolDressing")
	if dressing then
		local probe = cf * Vector3.new(0, 0, 1.2)
		for _, m in ipairs(dressing:GetChildren()) do
			if m.Name == "SchoolHallLockers" then
				local bcf, bsize = m:GetBoundingBox()
				local d = bcf:PointToObjectSpace(probe)
				local reach = math.max(width, height) / 2 + 1.2
				if math.abs(d.X) < bsize.X / 2 + reach and math.abs(d.Y) < bsize.Y / 2 + reach and math.abs(d.Z) < bsize.Z / 2 + reach then return false end
			end
		end
	end
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
local function occupied(list, pos, gap)
	for _, q in ipairs(list) do if (q - pos).Magnitude < gap then return true end end
	return false
end

-- A wall slot in room r: a CFrame on the wall surface whose LookVector points INTO the wall (the hospital's
-- wallClear convention); the face that shows in the room is Back.
local function wallSpot(r, rng, y)
	local side = rng:NextInteger(1, 4)
	local inset = 0.72
	if side == 1 then return CFrame.new(rng:NextNumber(r.x1 + 4, r.x2 - 4), y, r.z1 + inset)
	elseif side == 2 then return CFrame.new(rng:NextNumber(r.x1 + 4, r.x2 - 4), y, r.z2 - inset) * CFrame.Angles(0, math.pi, 0)
	elseif side == 3 then return CFrame.new(r.x1 + inset, y, rng:NextNumber(r.z1 + 4, r.z2 - 4)) * CFrame.Angles(0, math.pi / 2, 0)
	else return CFrame.new(r.x2 - inset, y, rng:NextNumber(r.z1 + 4, r.z2 - 4)) * CFrame.Angles(0, -math.pi / 2, 0) end
end

local BOARD = {
	"DON'T DIE HERE", "2 + 2 = RUN", "WE ARE STILL IN CLASS", "RECESS IS CANCELLED\nFOREVER", "Today's lesson:\nhide",
	"Mrs. Hollow sees you", "NO TALKING\nIT LISTENS", "Homework due: never", "Class of 1994\nnever graduated",
	"HE TOOK TOMMY", "ABCDEFG\nHELP ME", "IIII IIII IIII IIII II",
}
local DRAWINGS = { "MY FAMILY", "my dog", "ME AT SCHOOL", "the tall man", "SUNNY DAY", "my teacher", "HOME", "I miss mom", "the basement" }
local GRAFFITI = { "GET OUT", "SKOOL'S OUT", "NO ONE LEFT", "IT'S IN THE VENTS", "RIP", "JAKE + EMMA", "DON'T GO TO THE GYM", "LOOK BEHIND YOU", "class dismissed" }
local PAPER = { Color3.fromRGB(226, 222, 206), Color3.fromRGB(214, 206, 180), Color3.fromRGB(232, 228, 214) }
local CRAYON = { Color3.fromRGB(196, 40, 28), Color3.fromRGB(13, 105, 172), Color3.fromRGB(245, 205, 48), Color3.fromRGB(75, 151, 75), Color3.fromRGB(170, 85, 0), Color3.fromRGB(107, 50, 124) }
local SPRAY = { Color3.fromRGB(200, 30, 40), Color3.fromRGB(30, 30, 30), Color3.fromRGB(40, 110, 200), Color3.fromRGB(60, 160, 60), Color3.fromRGB(230, 120, 30) }

-- Chalk scrawl on every placed chalkboard plus an alphabet banner above it, letters missing or hanging.
function M.Boards(mansion, plan, folder)
	local rng = Random.new((plan.seed or 1) + 2201)
	local n = 0
	for _, m in ipairs(mansion.Furniture:GetChildren()) do
		if m:IsA("Model") and m.Name:sub(-16) == "SchoolChalkboard" then
			local cf = m:GetPivot() -- the Furnisher drops the Pivot part; the model keeps its pivot
			local slate = part(folder, "ChalkWriting", Vector3.new(7.2, 3.2, 0.05), cf * CFrame.new(0, 5.05, -0.22), Color3.new(), Enum.Material.SmoothPlastic)
			slate.Transparency = 1
			local _, t = label(slate, Enum.NormalId.Front, BOARD[rng:NextInteger(1, #BOARD)], Enum.Font.PermanentMarker, CHALK, Vector2.new(720, 320), rng:NextNumber(-4, 4))
			t.TextTransparency = 0.12
			local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
			for i = 1, 13 do
				if rng:NextNumber() < 0.18 then continue end -- torn off
				local x = 7.2 - i * 1.03 -- the board faces -Z, so A starts at local +X (viewer left)
				local hang = rng:NextNumber() < 0.15
				local card = part(folder, "AlphabetCard", Vector3.new(0.9, 1.0, 0.04), cf * CFrame.new(x, 8.6 - (hang and 0.4 or 0), -0.12) * CFrame.Angles(0, 0, hang and math.rad(rng:NextNumber(-60, 60)) or 0), CRAYON[(i - 1) % #CRAYON + 1])
				local idx = (i - 1) * 2 + 1
				label(card, Enum.NormalId.Front, letters:sub(idx, idx) .. letters:sub(idx + 1, idx + 1):lower(), Enum.Font.FredokaOne, Color3.new(1, 1, 1), Vector2.new(100, 110))
			end
			n += 1
		end
	end
	return n
end

-- Kids' crayon drawings taped up in rooms (some fallen), spray-paint graffiti in halls.
function M.Walls(mansion, plan, folder)
	local rng = Random.new((plan.seed or 1) + 3307)
	local n = 0
	local used = {}
	for _, r in ipairs(plan.rooms or {}) do
		if not (r.x1 and r.x2 and r.z1 and r.z2) or r.type == "Stair" then continue end
		local w, d = r.x2 - r.x1, r.z2 - r.z1
		if w < 10 or d < 10 then continue end
		local y0 = (r.level or 0) * FLOOR_H
		local hall = r.type == "Hall"
		local count = hall and math.min(4, math.floor((w + d) / 40)) or rng:NextInteger(2, 5)
		for _ = 1, count * 3 do
			if count <= 0 then break end
			if hall then
				local cf = wallSpot(r, rng, y0 + rng:NextNumber(5.6, 7.2)) -- between the chair rail (~3.4) and the map rail (~8.85)
				local size = Vector3.new(rng:NextNumber(6, 10), 3, 0.05)
				if occupied(used, cf.Position, 9) or not wallClear(mansion, cf, size.X, size.Y) then continue end
				local p = part(folder, "Graffiti", size, cf * CFrame.new(0, 0, 0.04), Color3.new(), Enum.Material.SmoothPlastic)
				p.Transparency = 1
				label(p, Enum.NormalId.Back, GRAFFITI[rng:NextInteger(1, #GRAFFITI)], Enum.Font.PermanentMarker, SPRAY[rng:NextInteger(1, #SPRAY)], Vector2.new(600, 180), rng:NextNumber(-8, 8))
				table.insert(used, cf.Position); count -= 1; n += 1
			else
				local cf = wallSpot(r, rng, y0 + rng:NextNumber(5.3, 7.5)) -- the whole sheet stays above the chair rail
				if occupied(used, cf.Position, 3) or not wallClear(mansion, cf, 2, 2.4) then continue end
				local tilt = math.rad(rng:NextNumber(-12, 12))
				local sheet = part(folder, "KidDrawing", Vector3.new(1.8, 2.3, 0.04), cf * CFrame.new(0, 0, 0.04) * CFrame.Angles(0, 0, tilt), PAPER[rng:NextInteger(1, #PAPER)])
				local gui = Instance.new("SurfaceGui"); gui.Face = Enum.NormalId.Back; gui.CanvasSize = Vector2.new(180, 230); gui.LightInfluence = 1; gui.Parent = sheet
				local sun = Instance.new("Frame"); sun.Size = UDim2.fromOffset(40, 40); sun.Position = UDim2.fromOffset(rng:NextInteger(100, 130), 12)
				sun.BackgroundColor3 = CRAYON[3]; sun.BorderSizePixel = 0; sun.Parent = gui
				Instance.new("UICorner", sun).CornerRadius = UDim.new(1, 0)
				local house = Instance.new("Frame"); house.Size = UDim2.fromOffset(70, 60); house.Position = UDim2.fromOffset(rng:NextInteger(14, 40), 110)
				house.BackgroundColor3 = CRAYON[rng:NextInteger(1, #CRAYON)]; house.BorderSizePixel = 0; house.BackgroundTransparency = 0.2; house.Parent = gui
				local grass = Instance.new("Frame"); grass.Size = UDim2.new(1, 0, 0, 16); grass.Position = UDim2.fromOffset(0, 172); grass.BackgroundColor3 = CRAYON[4]; grass.BorderSizePixel = 0; grass.Parent = gui
				local cap = Instance.new("TextLabel"); cap.Size = UDim2.new(1, -10, 0, 34); cap.Position = UDim2.fromOffset(5, 192); cap.BackgroundTransparency = 1
				cap.Text = DRAWINGS[rng:NextInteger(1, #DRAWINGS)]; cap.Font = Enum.Font.IndieFlower; cap.TextScaled = true; cap.TextColor3 = CRAYON[rng:NextInteger(1, #CRAYON)]; cap.Parent = gui
				part(folder, "Tape", Vector3.new(0.5, 0.18, 0.05), sheet.CFrame * CFrame.new(0, 1.12, 0.01), Color3.fromRGB(214, 200, 150)).Transparency = 0.3
				table.insert(used, cf.Position); count -= 1; n += 1
			end
		end
	end
	return n
end

-- Banks of lockers along plain hall walls. These collide (a 32-stud hall keeps plenty of room) but never
-- catch interact rays, and the wall check keeps them off doorways.
function M.Lockers(mansion, plan, kit, folder)
	local t = kit:FindFirstChild("SchoolLockerBank")
	if not t then return 0 end
	local rng = Random.new((plan.seed or 1) + 5151)
	local n = 0
	for _, r in ipairs(plan.rooms or {}) do
		if r.type ~= "Hall" or not (r.x1 and r.x2 and r.z1 and r.z2) then continue end
		local w, d = r.x2 - r.x1, r.z2 - r.z1
		local alongX = w >= d
		local length = alongX and w or d
		local y0 = (r.level or 0) * FLOOR_H
		for _, side in ipairs({ 1, -1 }) do
			local pos = (alongX and r.x1 or r.z1) + 4
			while pos < (alongX and r.x2 or r.z2) - 4 and length > 14 do
				local cf
				if alongX then
					local z = side == 1 and r.z2 - 1.95 or r.z1 + 1.95
					cf = CFrame.new(pos, y0, z) * CFrame.Angles(0, side == 1 and 0 or math.pi, 0)
				else
					local x = side == 1 and r.x2 - 1.95 or r.x1 + 1.95
					cf = CFrame.new(x, y0, pos) * CFrame.Angles(0, side == 1 and math.pi / 2 or -math.pi / 2, 0)
				end
				local wallCf = cf * CFrame.new(0, 4, 1.25) * CFrame.Angles(0, math.pi, 0)
				if rng:NextNumber() < 0.38 and wallClear(mansion, wallCf, 4.6, 6.5) and floorClear(mansion, cf.Position + cf.LookVector * 0.3, Vector3.new(4.4, 1, 2.2)) then
					local m = t:Clone(); m.Name = "SchoolHallLockers"; m:PivotTo(cf)
					for _, p in ipairs(m:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true; p.CanQuery = false; p.CanTouch = false; p:SetAttribute("NonBlockingDetail", true) end end
					if rng:NextNumber() < 0.15 then m:PivotTo(cf * CFrame.new(0, 0, -0.4) * CFrame.Angles(math.rad(-8), 0, 0)) end -- one leaning off the wall
					m.Parent = folder
					n += 1
					pos += 4.6
				else
					pos += 2.5
				end
			end
		end
	end
	return n
end

-- Floor clutter from the rbxkit meshes in ServerStorage.SchoolClutterKit. Two classes so walkways stay readable
-- (players push the loot cart through here): FLAT pieces lie on the floor anywhere; BULKY upright pieces only stand
-- against room walls, at least DOOR_CLEAR studs from any doorway, and never in halls.
local FLAT = { -- name, weight
	{ "SchoolPaperPile", 10 }, { "SchoolOpenBook", 4 }, { "SchoolCrayonSpill", 3 }, { "Puddle", 3 }, { "Glass", 2 },
}
local BULKY = {
	{ "SchoolBackpack", 5 }, { "SchoolBookStack", 5 }, { "SchoolLunchTray", 3 }, { "SchoolKidChair", 4 },
	{ "SchoolTrashCan", 3 }, { "SchoolGlobe", 2 }, { "SchoolTeddy", 2 }, { "SchoolWetSign", 1 },
}
local DOOR_CLEAR = 7
local function pick(rng, list)
	local total = 0
	for _, c in ipairs(list) do total += c[2] end
	local roll = rng:NextNumber() * total
	for _, c in ipairs(list) do roll -= c[2]; if roll <= 0 then return c[1] end end
	return list[1][1]
end
local function prop(t, cf, folder)
	local m = t:Clone(); m:PivotTo(cf)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p:SetAttribute("NonBlockingDetail", true) end
	end
	m.Parent = folder
	return m
end
-- Every doorway, open bay and the front entrance, so upright clutter never sits in an approach.
local function doorways(plan)
	local list = {}
	for _, e in ipairs(plan.edges or {}) do
		if e.kind ~= "stairs" and e.x and e.z then table.insert(list, Vector3.new(e.x, e.y or 0, e.z)) end
	end
	if plan.entrance then table.insert(list, Vector3.new(plan.entrance.x, 0, plan.entrance.z)) end
	return list
end
local function nearDoorway(list, pos)
	for _, p in ipairs(list) do
		if math.abs(p.Y - pos.Y) < 8 and Vector2.new(p.X - pos.X, p.Z - pos.Z).Magnitude < DOOR_CLEAR then return true end
	end
	return false
end
-- A spot against one of room r's walls for an item `size` across: its back to the wall, facing the room.
local function floorWallSpot(r, rng, y, size)
	local depth = math.max(size.X, size.Z)
	local inset = 0.7 + depth / 2 + 0.3
	local side = rng:NextInteger(1, 4)
	local margin = depth / 2 + 1.5
	if side == 1 then return CFrame.new(rng:NextNumber(r.x1 + margin, r.x2 - margin), y, r.z1 + inset) * CFrame.Angles(0, math.pi, 0)
	elseif side == 2 then return CFrame.new(rng:NextNumber(r.x1 + margin, r.x2 - margin), y, r.z2 - inset)
	elseif side == 3 then return CFrame.new(r.x1 + inset, y, rng:NextNumber(r.z1 + margin, r.z2 - margin)) * CFrame.Angles(0, math.pi / 2, 0)
	else return CFrame.new(r.x2 - inset, y, rng:NextNumber(r.z1 + margin, r.z2 - margin)) * CFrame.Angles(0, -math.pi / 2, 0) end
end

function M.Trash(mansion, plan, folder)
	local kit = game:GetService("ServerStorage"):FindFirstChild("SchoolClutterKit")
	if not kit then return 0 end
	local rng = Random.new((plan.seed or 1) + 7717)
	local doors = doorways(plan)
	local n = 0
	for _, r in ipairs(plan.rooms or {}) do
		if not (r.x1 and r.x2 and r.z1 and r.z2) or r.type == "Stair" then continue end
		local w, d = r.x2 - r.x1, r.z2 - r.z1
		if w < 6 or d < 6 then continue end
		local y = (r.level or 0) * FLOOR_H
		local area = w * d
		local hall = r.type == "Hall"
		-- Flat pieces anywhere (rooms and halls).
		for _ = 1, math.min(hall and 4 or 12, math.floor(area / (hall and 240 or 130))) do
			local name = pick(rng, FLAT)
			local t = kit:FindFirstChild(name)
			local size = if t then t:GetExtentsSize() else Vector3.new(4, 0.1, 4)
			local half = math.max(size.X, size.Z) / 2 + 0.5
			if w < half * 2 + 1 or d < half * 2 + 1 then continue end
			local x, z = rng:NextNumber(r.x1 + half, r.x2 - half), rng:NextNumber(r.z1 + half, r.z2 - half)
			if not floorClear(mansion, Vector3.new(x, y, z), Vector3.new(half * 2 - 0.6, 0.6, half * 2 - 0.6)) then continue end
			local spin = CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			if t then
				prop(t, CFrame.new(x, y, z) * spin, folder)
			elseif name == "Puddle" then
				local pud = part(folder, "Puddle", Vector3.new(rng:NextNumber(2.5, 5), 0.02, rng:NextNumber(2, 4)), CFrame.new(x, y + 0.02, z) * spin, Color3.fromRGB(28, 30, 28), Enum.Material.Glass)
				pud.Transparency = 0.35; pud.Reflectance = 0.3
				local drip = part(folder, "CeilingStain", Vector3.new(pud.Size.X + 1, 0.04, pud.Size.Z + 1), CFrame.new(x, y + 13.9, z) * spin, Color3.fromRGB(70, 58, 40))
				drip.Transparency = 0.45
			else
				for _ = 1, rng:NextInteger(4, 8) do
					local g = part(folder, "GlassShard", Vector3.new(rng:NextNumber(0.2, 0.6), 0.03, rng:NextNumber(0.2, 0.5)), CFrame.new(x + rng:NextNumber(-1.2, 1.2), y + 0.03, z + rng:NextNumber(-1.2, 1.2)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Color3.fromRGB(180, 200, 200), Enum.Material.Glass)
					g.Transparency = 0.5; g.Reflectance = 0.25
				end
			end
			n += 1
		end
		-- Upright pieces: rooms only, against a wall, clear of doorways.
		if not hall then
			for _ = 1, math.min(5, math.floor(area / 300)) do
				local name = if r.type == "Dining" and rng:NextNumber() < 0.5 then "SchoolLunchTray" else pick(rng, BULKY)
				local t = kit:FindFirstChild(name)
				if not t then continue end
				local size = t:GetExtentsSize()
				local reach = math.max(size.X, size.Z)
				if w < reach + 4 or d < reach + 4 then continue end
				for _ = 1, 4 do -- a few tries along the walls
					local cf = floorWallSpot(r, rng, y, size) * CFrame.Angles(0, rng:NextNumber(-0.35, 0.35), 0)
					if not nearDoorway(doors, cf.Position) and floorClear(mansion, cf.Position, Vector3.new(reach, 0.6, reach)) then
						prop(t, cf, folder); n += 1
						break
					end
				end
			end
		end
		-- Loose sheets and dark grime: flat, so they may cover any floor.
		for _ = 1, math.min(35, math.floor(area / 45)) do
			local x, z = rng:NextNumber(r.x1 + 1, r.x2 - 1), rng:NextNumber(r.z1 + 1, r.z2 - 1)
			if not floorClear(mansion, Vector3.new(x, y, z), Vector3.new(1, 0.4, 1)) then continue end
			part(folder, "Sheet", Vector3.new(rng:NextNumber(0.8, 0.95), 0.02, rng:NextNumber(1.05, 1.2)), CFrame.new(x, y + rng:NextNumber(0.012, 0.04), z) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), rng:NextNumber(0, 6.28), rng:NextNumber(-0.05, 0.05)), PAPER[rng:NextInteger(1, #PAPER)])
		end
		for _ = 1, math.min(10, math.floor(area / 160)) do
			local x, z = rng:NextNumber(r.x1 + 2, r.x2 - 2), rng:NextNumber(r.z1 + 2, r.z2 - 2)
			local dia = rng:NextNumber(3, 6.5)
			if AngledCorners.Blocked(mansion, Vector3.new(x, y, z), dia / 2 + 0.2) then continue end
			local g = part(folder, "Grime", Vector3.new(0.02, dia, dia), CFrame.new(x, y + 0.008, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(46, 40, 30))
			g.Shape = Enum.PartType.Cylinder; g.Transparency = 0.72
		end
		-- Collapsed ceiling: a hole with dangling wires; in rooms the fallen debris pile lies against a wall below it.
		-- Halls keep only the hole and wires, so nothing sits in the corridor.
		local debris = kit:FindFirstChild("SchoolCeilingDebris")
		for _ = 1, (w > 10 and d > 10) and rng:NextInteger(0, hall and 2 or 1) or 0 do
			local x, z
			if hall then
				x, z = rng:NextNumber(r.x1 + 4, r.x2 - 4), rng:NextNumber(r.z1 + 4, r.z2 - 4)
			elseif debris then
				local size = debris:GetExtentsSize()
				local cf = floorWallSpot(r, rng, y, size)
				local reach = math.max(size.X, size.Z)
				if nearDoorway(doors, cf.Position) or not floorClear(mansion, cf.Position, Vector3.new(reach, 1.2, reach)) then continue end
				x, z = cf.X, cf.Z
			else
				continue
			end
			local blocked = false
			for _, l in ipairs((mansion:FindFirstChild("Lights") or mansion):GetDescendants()) do
				if l:IsA("BasePart") and math.abs(l.Position.Y - (y + 13.9)) < 2 and math.abs(l.Position.X - x) < 4.5 and math.abs(l.Position.Z - z) < 4.5 then blocked = true; break end
			end
			if blocked or AngledCorners.Blocked(mansion, Vector3.new(x, y, z), 2.8) then continue end
			if not hall then prop(debris, CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), folder) end
			part(folder, "CeilingHole", Vector3.new(4, 0.05, 3.8), CFrame.new(x, y + 13.96, z), Color3.fromRGB(12, 12, 11))
			for _ = 1, rng:NextInteger(1, 3) do
				local len = rng:NextNumber(2, 4.5)
				part(folder, "HangingWire", Vector3.new(0.06, len, 0.06), CFrame.new(x + rng:NextNumber(-1.5, 1.5), y + 13.9 - len / 2, z + rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), Color3.fromRGB(25, 25, 25))
			end
			n += 1
		end
	end
	return n
end

-- Hospital surfaces first (ceiling tiles, wall base tile), then the school's own painted cinder block and
-- speckled classroom floor tiles. The block texture is near-white, so tinting it with the theme colour keeps
-- each room's paint colour.
local HOSP_WALL, HOSP_FLOOR = "rbxassetid://72153221483318", "rbxassetid://123767087934872"
local SCHOOL_WALL, SCHOOL_FLOOR = "rbxassetid://122503028812888", "rbxassetid://120537211339534"
function M.Surfaces(mansion)
	local n = H.Surfaces(mansion)
	for _, t in ipairs(mansion.Architecture:GetDescendants()) do
		if t:IsA("Texture") and t.Parent:IsA("BasePart") then
			if t.Texture == HOSP_WALL then
				t.Texture = SCHOOL_WALL; t.StudsPerTileU = 6; t.StudsPerTileV = 6
				t.Color3 = t.Parent.Color:Lerp(Color3.new(1, 1, 1), 0.25)
			elseif t.Texture == HOSP_FLOOR then
				t.Texture = SCHOOL_FLOOR; t.StudsPerTileU = 5; t.StudsPerTileV = 5
			end
		elseif t:IsA("BasePart") then
			local s = t:GetAttribute("Surface")
			if s == "schooldado" then -- glossy enamel paint, scuffed
				t.Material = Enum.Material.SmoothPlastic; t.Reflectance = 0.06
			elseif s == "schoolwood" then
				t.Material = Enum.Material.Wood
			end
		end
	end
	return n
end

function M.Apply(mansion, plan, kit)
	if plan.mapKind ~= "School" then return end
	if mansion:GetAttribute("SchoolDressingVersion") then return end
	local folder = Instance.new("Folder"); folder.Name = "SchoolDressing"; folder.Parent = mansion.Architecture
	local stats = {}
	stats.textured = M.Surfaces(mansion)
	for _, step in ipairs({
		{ "signs", function() return H.Signs(mansion, plan, folder) end },
		{ "boards", function() return M.Boards(mansion, plan, folder) end },
		{ "lockers", function() return M.Lockers(mansion, plan, kit, folder) end },
		{ "walls", function() return M.Walls(mansion, plan, folder) end }, -- after lockers, so marks never hide behind them
		{ "trash", function() return M.Trash(mansion, plan, folder) end },
	}) do
		local ok, v = pcall(step[2])
		stats[step[1]] = ok and v or -1
		if not ok then warn("[SchoolDressing] " .. step[1] .. ": " .. tostring(v)) end
	end
	for k, val in pairs(stats) do mansion:SetAttribute("School_" .. k, val) end
	mansion:SetAttribute("SchoolDressingVersion", 1)
end

return M
