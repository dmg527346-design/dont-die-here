-- Hotel map finish: a faded, haunted 1920s grand hotel. Carpet/damask/walnut textures, chandeliers and brass dome
-- lights (some dead, some flickering), brass room plaques and EXIT signs, scrawled (no blood or handprints),
-- messages, scattered letters, playing cards, water bottles and fallen plaster.
-- Cosmetic only: every added part is non-colliding, non-queryable and tagged NonBlockingDetail.
local M = {}
local TEX = {
	floor = "rbxassetid://128236799665339", -- red diamond carpet
	wall = "rbxassetid://113772508691571", -- burgundy damask
	ceiling = "rbxassetid://109990955161557", -- cracked cream plaster
	tile = "rbxassetid://122612592804739", -- walnut wainscot panels
	blood = "rbxassetid://72390053907846", -- black grime / handprints
}
local LIGHT = Color3.fromRGB(255, 196, 136) -- warm old incandescent
local DEAD = Color3.fromRGB(84, 70, 58)
local BRASS = Color3.fromRGB(176, 136, 64)
local BLOOD = Color3.fromRGB(14, 12, 12) -- old grime: near black
local FLOOR_H = 16

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("NonBlockingDetail", true)
	p.Parent = parent
	return p
end
local function texture(p, img, face, u, v, transp)
	local t = Instance.new("Texture")
	t.Texture = img; t.Face = face; t.StudsPerTileU = u; t.StudsPerTileV = v; t.Transparency = transp or 0
	t.Parent = p
	return t
end
local function decal(p, img, face, transp, color)
	local d = Instance.new("Decal")
	d.Texture = img; d.Face = face; d.Transparency = transp or 0
	if color then d.Color3 = color end
	d.Parent = p
	return d
end

-- Placement checks so dressing never clips: floor items stay out of furniture, wall marks only on solid
-- plain wall (not across doorways/windows), ceiling holes never cut through a light fixture.
-- Door swing keepout: every doorway (real or sealed) gets a disc of slab radius 5.75 + margin on both sides,
-- so an opening door never passes through floor dressing. Centres are cached once per mansion.
-- Door slabs are scaled by Rules.DoorWidth/6 (Hotel: 8 wide -> slab 7.67, hinge 3.87 off-centre); the tip of a
-- slab of width W hinged W/2 off-centre reaches ~1.19*W from the portal centre at a 100-degree swing.
local DOOR_W = 8
do
	local okR, R = pcall(function() return require(script.Parent:FindFirstChild("Rules")) end)
	if okR and type(R) == "table" and type(R.DoorWidth) == "number" then DOOR_W = R.DoorWidth end
end
local DOOR_KEEP = 1.2 * DOOR_W + 0.3
local doorCache = setmetatable({}, { __mode = "k" })
local currentPlan = nil
local function doorCentres(mansion)
	local list = doorCache[mansion]
	if list then return list end
	list = {}
	-- 1) architecture portals, 2) every real swinging door (Mover_RD* in Interactive, closed at build time),
	-- 3) every door edge in the plan (Builder hangs real doors on these even where no portal frame was cloned)
	for _, d in ipairs(mansion:GetDescendants()) do
		if d.Name == "DoorThreshold" or d.Name == "WallDoor" or d:GetAttribute("RemoteDoor")
			or (d:IsA("Model") and d.Name:match("^Mover_RD")) then
			local p = d:IsA("Model") and d:GetBoundingBox().Position or (d:IsA("BasePart") and d.Position)
			if p then table.insert(list, p) end
		end
	end
	for _, e in ipairs((currentPlan and currentPlan.edges) or {}) do
		if e.x and e.z then table.insert(list, Vector3.new(e.x, e.y or 0, e.z)) end
	end
	doorCache[mansion] = list
	return list
end
local function nearDoor(mansion, pos, size)
	local reach = DOOR_KEEP + Vector2.new(size.X, size.Z).Magnitude / 2 -- item may be rotated: use its half-diagonal
	for _, c in ipairs(doorCentres(mansion)) do
		if math.abs(c.Y - pos.Y) < 8 and Vector2.new(c.X - pos.X, c.Z - pos.Z).Magnitude < reach then return true end
	end
	return false
end
-- Diagonal corner cuts (MapGen.AngledCorners): nothing goes behind or through one.
local AngledCorners = require(script.Parent.AngledCorners)
local function floorClear(mansion, pos, size)
	if AngledCorners.Blocked(mansion, pos, Vector2.new(size.X, size.Z).Magnitude / 2) then return false end -- any yaw
	if nearDoor(mansion, pos, size) then return false end
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
local function ceilingClear(mansion, pos)
	local lights = mansion:FindFirstChild("Lights")
	if not lights then return true end
	local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Include; op.FilterDescendantsInstances = { lights }; op.RespectCanCollide = false
	-- light parts are CanQuery=false, so test their models' boxes directly
	for _, m in ipairs(lights:GetDescendants()) do
		if m:IsA("BasePart") and math.abs(m.Position.Y - pos.Y) < 2 and math.abs(m.Position.X - pos.X) < 4.5 and math.abs(m.Position.Z - pos.Z) < 4.5 then return false end
	end
	return true
end

function M.Surfaces(mansion)
	local n = 0
	for _, p in ipairs(mansion.Architecture:GetDescendants()) do
		if p:IsA("BasePart") then
			local s = p:GetAttribute("Surface")
			if s == "hotelfloor" then
				p.Material = Enum.Material.Fabric; p.Reflectance = 0
				texture(p, TEX.floor, Enum.NormalId.Top, 8, 8); n += 1
			elseif s == "hotelceiling" then
				texture(p, TEX.ceiling, Enum.NormalId.Bottom, 8, 8); n += 1
			elseif s == "hoteltile" then
				for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
					texture(p, TEX.tile, face, 6, 6)
				end
				n += 1
			elseif s == "hotelmetal" then
				p.Material = Enum.Material.Metal; p.Reflectance = 0.12
			elseif s == "wallpaper" and p.Transparency < 1 then
				for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
					texture(p, TEX.wall, face, 8, 8)
				end
				n += 1
			end
		end
	end
	return n
end

-- Hotel lights: a chandelier (ServerStorage.HotelKit.HotelChandelier when present) over each room and brass dome
-- ceiling lights along corridors. About one in four is dead (dark glass, no light), one in five flickers.
local function kitModel(name)
	local k = game:GetService("ServerStorage"):FindFirstChild("HotelKit")
	return k and k:FindFirstChild(name)
end

function M.Chandelier(parent, cf, rng, room)
	local model
	local t = kitModel("HotelChandelier")
	local dead = rng:NextNumber() < 0.25
	if t then
		model = t:Clone(); model.Name = "HotelChandelier"
		model:ScaleTo(0.78) -- bottom stays at ~10.5 above the floor, clear of tall monsters
		model:PivotTo(cf)
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
				p:SetAttribute("NonBlockingDetail", true)
			end
		end
		model.Parent = parent
	else
		model = Instance.new("Model"); model.Name = "HotelChandelier"; model.Parent = parent
		part(model, "Rod", Vector3.new(0.2, 1.4, 0.2), cf * CFrame.new(0, -0.7, 0), BRASS, Enum.Material.Metal)
		local ring = part(model, "Ring", Vector3.new(0.25, 3.4, 3.4), cf * CFrame.new(0, -1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), BRASS, Enum.Material.Metal); ring.Shape = Enum.PartType.Cylinder
		part(model, "Bulbs", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(0, -1.9, 0), LIGHT, Enum.Material.Neon)
	end
	model:SetAttribute("Room", room)
	local bulbs = model:FindFirstChild("Bulbs", true)
	if dead then
		for _, q in ipairs(model:GetDescendants()) do
			if q:IsA("BasePart") and q.Material == Enum.Material.Neon then q.Material = Enum.Material.SmoothPlastic; q.Color = DEAD end
			if q:IsA("Light") then q.Enabled = false end
		end
		return model, false
	end
	local host = bulbs or model:FindFirstChildWhichIsA("BasePart", true)
	if host then
		local l = Instance.new("PointLight"); l.Name = "SteadyRoomLight"; l.Range = 24; l.Brightness = 0.85; l.Color = LIGHT; l.Shadows = false
		l.Parent = host
		if rng:NextNumber() < 0.2 then host:AddTag("MallFlicker") end
	end
	return model, true
end

function M.DomeLight(parent, cf, rng, room)
	local model = Instance.new("Model"); model.Name = "HotelDomeLight"; model:SetAttribute("Room", room); model.Parent = parent
	local plate = part(model, "Plate", Vector3.new(1.6, 0.1, 1.6), cf, BRASS, Enum.Material.Metal)
	plate.Shape = Enum.PartType.Cylinder; plate.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	plate.Size = Vector3.new(0.1, 1.6, 1.6)
	local dead = rng:NextNumber() < 0.25
	local glass = part(model, "Glass", Vector3.new(1.1, 0.6, 1.1), cf * CFrame.new(0, -0.3, 0), dead and DEAD or Color3.fromRGB(255, 220, 170), dead and Enum.Material.SmoothPlastic or Enum.Material.Neon)
	glass.Shape = Enum.PartType.Ball
	model.PrimaryPart = plate
	if dead then return model, false end
	glass.Transparency = 0.1
	local l = Instance.new("PointLight"); l.Name = "SteadyRoomLight"; l.Range = 18; l.Brightness = 0.7; l.Color = LIGHT; l.Shadows = false; l.Parent = glass
	if rng:NextNumber() < 0.2 then glass:AddTag("MallFlicker") end
	return model, true
end

function M.Fixtures(mansion, plan, steady)
	local rng = Random.new((plan.seed or 1) + 4545)
	local count, lit = 0, 0
	for _, r in ipairs(plan.rooms or {}) do
		if not (r.x1 and r.x2 and r.z1 and r.z2) then continue end
		local y = (r.level or 0) * FLOOR_H + 14
		if r.type == "Stair" then
			local st = plan.stairs and r.stair and plan.stairs[r.stair]
			if st and st.cx and st.cz and st.yaw then
				local s = st.horizontalScale or 1
				local wall = CFrame.new(st.cx, (r.level or 0) * FLOOR_H + 8.5, st.cz) * CFrame.Angles(0, st.yaw, 0) * CFrame.new(11.1 * s, 0, 0)
				local model = Instance.new("Model"); model.Name = "HotelStairSconce"; model:SetAttribute("Room", r.name); model.Parent = steady
				local plate = part(model, "WallPlate", Vector3.new(0.2, 1.2, 1.2), wall, BRASS, Enum.Material.Metal)
				local lens = part(model, "Shade", Vector3.new(0.6, 0.8, 0.9), wall * CFrame.new(-0.35, 0, 0), Color3.fromRGB(255, 214, 160), Enum.Material.Neon)
				lens.Transparency = 0.15
				local l = Instance.new("PointLight"); l.Name = "SteadyRoomLight"; l.Range = 18; l.Brightness = 0.7; l.Color = LIGHT; l.Shadows = false; l.Parent = lens
				model.PrimaryPart = plate; count += 1; lit += 1
			end
		else
			local w, d = r.x2 - r.x1, r.z2 - r.z1
			if r.type == "Hall" then
				local alongX = w >= d
				local len = alongX and w or d
				local n = math.max(1, math.floor(len / 16 + 0.5))
				for i = 1, n do
					local t = (i - 0.5) / n
					local cf = alongX and CFrame.new(r.x1 + w * t, y - 0.05, (r.z1 + r.z2) / 2) or CFrame.new((r.x1 + r.x2) / 2, y - 0.05, r.z1 + d * t)
					local _, on = M.DomeLight(steady, cf, rng, r.name)
					count += 1; lit += on and 1 or 0
				end
			else
				local big = w * d > 900
				local spots = big and { { 0.3, 0.5 }, { 0.7, 0.5 } } or { { 0.5, 0.5 } }
				if big and d > w then spots = { { 0.5, 0.3 }, { 0.5, 0.7 } } end
				for _, sp in ipairs(spots) do
					local cf = CFrame.new(r.x1 + w * sp[1], y, r.z1 + d * sp[2])
					local small = math.min(w, d) < 9
					local _, on
					if small then _, on = M.DomeLight(steady, cf * CFrame.new(0, -0.05, 0), rng, r.name) else _, on = M.Chandelier(steady, cf, rng, r.name) end
					count += 1; lit += on and 1 or 0
				end
			end
		end
	end
	return count, lit
end

local function plaque(parent, text, cf, rng, color, glow)
	local board = part(parent, "RoomSign", Vector3.new(2.3, 0.85, 1.7), cf, Color3.fromRGB(176, 136, 64), Enum.Material.Metal) -- covers the portal SignBand brass plate
	if color then board.Color = color end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui"); gui.Face = face; gui.CanvasSize = Vector2.new(460, 170)
		gui.LightInfluence = glow and 0 or 1; gui.Brightness = glow and 1.6 or 1; gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.92, 0.78); label.Position = UDim2.fromScale(0.04, 0.11); label.BackgroundTransparency = 1
		label.Text = string.upper(tostring(text or "WARD")); label.Font = glow and Enum.Font.Arimo or Enum.Font.Garamond; label.TextScaled = true
		label.TextColor3 = glow and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(40, 24, 14)
		label.Parent = gui
	end
	if false then -- plates are screwed to the sign band (no crooked tilt in the hotel)
		board.CFrame = board.CFrame * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-14, 14)))
	end
	return board
end

-- Ward plaques over doors into rooms, and red EXIT signs over a few hall doorways.
function M.Signs(mansion, plan, folder)
	local by = {}
	for _, r in ipairs(plan.rooms or {}) do by[r.name] = r end
	local rng = Random.new((plan.seed or 1) + 919)
	local n = 0
	local roomNo, roomName = {}, {}
	for _, e in ipairs(plan.edges or {}) do
		if not (e.x and e.z and e.y) then continue end
		if e.kind == "door" or e.kind == "open" then
			local a, b = by[e.a], by[e.b]
			if a and b then
				local hall = (a.type == "Hall" and b.type ~= "Hall" and b.type ~= "Stair" and a) or (b.type == "Hall" and a.type ~= "Hall" and a.type ~= "Stair" and b)
				local cf = e.axis == "x" and CFrame.new(e.x, e.y + 11.6, e.z) or CFrame.new(e.x, e.y + 11.6, e.z) * CFrame.Angles(0, math.pi / 2, 0) -- on the portal SignBand plate
				if hall then
					local room = hall == a and b or a
					local text = room.purpose or room.type
					if text == "Guest Room" or text == "Suite" then
						if not roomName[room.name] then
							roomNo[room.level or 0] = (roomNo[room.level or 0] or 0) + 1
							roomName[room.name] = (text == "Suite" and "SUITE " or "ROOM ") .. tostring((room.level or 0) + 1) .. string.format("%02d", roomNo[room.level or 0])
						end
						text = roomName[room.name]
					end
					plaque(folder, text, cf, rng); n += 1
				elseif a.type == "Hall" and b.type == "Hall" and rng:NextNumber() < 0.35 then
					local s = plaque(folder, "EXIT", cf * CFrame.new(0, 1.25, 0), rng, Color3.fromRGB(30, 12, 12), true) -- above the SignBand (top at 12.2)
					s.Size = Vector3.new(2.6, 0.8, 1.8)
					if rng:NextNumber() < 0.5 then s:AddTag("MallFlicker") end
					local l = Instance.new("PointLight"); l.Color = Color3.fromRGB(255, 50, 40); l.Range = 9; l.Brightness = 0.8; l.Shadows = false; l.Parent = s
					n += 1
				end
			end
		end
	end
	return n
end

local SCRAWL = { "CHECK OUT", "THEY NEVER LEFT", "DO NOT DISTURB", "STAY FOREVER", "ROOM 237", "THE BELLHOP IS WATCHING", "NO VACANCY" }

-- Blood on walls and floors, plus the odd message scrawled in blood.
function M.Blood(mansion, plan, folder)
	local rng = Random.new((plan.seed or 1) + 666)
	local n = 0
	for _, r in ipairs(plan.rooms or {}) do
		if not (r.x1 and r.x2 and r.z1 and r.z2) then continue end -- legacy/fallback graphs can lack a rect
		if r.type ~= "Stair" and r.name ~= plan.start then
			local y = (r.level or 0) * FLOOR_H
			local w, d = r.x2 - r.x1, r.z2 - r.z1
			-- one wall smear/handprint in about half the rooms (on the inner face of a random wall, away from corners)
			if rng:NextNumber() < 0.55 then repeat
				local side = rng:NextInteger(1, 4)
				local along0 = rng:NextNumber(0.25, 0.75)
				local wallLen0 = (side <= 2) and w or d
				local s0 = math.min(rng:NextNumber(4, 6.5), wallLen0 - 2)
				local lo, hi = (s0 / 2 + 1) / wallLen0, 1 - (s0 / 2 + 1) / wallLen0
				if hi <= lo then break end
				local alongC = lo + (hi - lo) * along0
				local cf
				if side == 1 then cf = CFrame.new(r.x1 + w * alongC, y + rng:NextNumber(3.5, 6), r.z1 + 0.78)
				elseif side == 2 then cf = CFrame.new(r.x1 + w * alongC, y + rng:NextNumber(3.5, 6), r.z2 - 0.78) * CFrame.Angles(0, math.pi, 0)
				elseif side == 3 then cf = CFrame.new(r.x1 + 0.78, y + rng:NextNumber(3.5, 6), r.z1 + d * alongC) * CFrame.Angles(0, math.pi / 2, 0) -- Back face (decal) points +X into the room
				else cf = CFrame.new(r.x2 - 0.78, y + rng:NextNumber(3.5, 6), r.z1 + d * alongC) * CFrame.Angles(0, -math.pi / 2, 0) end -- Back face points -X into the room
				local wallLen = (side <= 2) and w or d
				local s = s0
				if s < 2.5 then break end
				local wantScrawl = rng:NextNumber() < 0.3
				if not wallClear(mansion, cf, s, s) then break end
				-- No blood smears or handprints (content maturity, 2026-10-07): only the scrawled message remains.
				local mw = math.min(9, 2 * math.min(alongC * wallLen, (1 - alongC) * wallLen) - 2)
				if wantScrawl and mw >= 3 and wallClear(mansion, cf * CFrame.new(0, s / 2 + 1.3, 0), mw, 2.2) then
					local msg = part(folder, "Scrawl", Vector3.new(mw, 2.2, 0.05), cf * CFrame.new(0, s / 2 + 1.3, 0.02), Color3.new(1, 1, 1))
					msg.Transparency = 1
					local gui = Instance.new("SurfaceGui"); gui.Face = Enum.NormalId.Back; gui.CanvasSize = Vector2.new(700, 170); gui.LightInfluence = 1; gui.Parent = msg
					local label = Instance.new("TextLabel"); label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 1
					label.Text = SCRAWL[rng:NextInteger(1, #SCRAWL)]; label.Font = Enum.Font.Creepster; label.TextScaled = true
					label.TextColor3 = BLOOD; label.TextTransparency = 0.1; label.Rotation = rng:NextNumber(-6, 6); label.Parent = gui
					n += 1
				end
			until true end
			-- floor pools and drag trails
			local pools = 0 -- no blood pools or drag trails (content maturity, 2026-10-07)) + (rng:NextNumber() < 0.45 and 1 or 0)) or 0
			for _ = 1, pools do
				local x, z, found
				local s = rng:NextNumber(2, 4)
				for _ = 1, 5 do
					x, z = rng:NextNumber(r.x1 + 3, r.x2 - 3), rng:NextNumber(r.z1 + 3, r.z2 - 3)
					if floorClear(mansion, Vector3.new(x, y, z), Vector3.new(s, 0.6, s)) then found = true; break end
				end
				if not found then continue end
				local pool = part(folder, "BloodPool", Vector3.new(0.04, s, s * rng:NextNumber(0.6, 1)), CFrame.new(x, y + 0.03, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.pi / 2), BLOOD, Enum.Material.Glass)
				pool.Shape = Enum.PartType.Cylinder; pool.Transparency = 0.2; pool.Reflectance = 0.25
				if rng:NextNumber() < 0.5 then -- a drag trail leading away
					local a = rng:NextNumber(0, math.pi * 2)
					local len = rng:NextNumber(6, 12)
					local ex2 = math.clamp(x + math.cos(a) * len, r.x1 + 1, r.x2 - 1)
					local ez2 = math.clamp(z + math.sin(a) * len, r.z1 + 1, r.z2 - 1)
					len = math.max(1, math.sqrt((ex2 - x) ^ 2 + (ez2 - z) ^ 2)); a = math.atan2(ez2 - z, ex2 - x)
					local mid = Vector3.new((x + ex2) / 2, y + 0.022, (z + ez2) / 2)
					if floorClear(mansion, mid, Vector3.new(len, 0.6, 1)) then
					local trail = part(folder, "BloodTrail", Vector3.new(len, 0.03, rng:NextNumber(0.5, 0.9)), CFrame.new(mid) * CFrame.Angles(0, -a, 0), BLOOD, Enum.Material.Glass)
					trail.Transparency = 0.35; trail.Reflectance = 0.2
					end
				end
				n += 1
			end
		end
	end
	return n
end

-- Papers, scattered x-ray films, pill bottles, fallen ceiling tiles with dark holes above.
function M.Debris(mansion, plan, folder)
	local rng = Random.new((plan.seed or 1) + 778)
	local n = 0
	for _, r in ipairs(plan.rooms or {}) do
		if not (r.x1 and r.x2 and r.z1 and r.z2) then continue end -- legacy/fallback graphs can lack a rect
		if r.type ~= "Stair" then
			local w, d = r.x2 - r.x1, r.z2 - r.z1
			local y = (r.level or 0) * FLOOR_H
			local area = w * d
			for _ = 1, (w > 5 and d > 5) and math.min(12, math.floor(area / 220)) or 0 do
				local x, z, found
				for _ = 1, 5 do -- door swings and furniture reject spots: retry so rooms stay as littered
					x, z = rng:NextNumber(r.x1 + 2, r.x2 - 2), rng:NextNumber(r.z1 + 2, r.z2 - 2)
					if floorClear(mansion, Vector3.new(x, y, z), Vector3.new(1.4, 0.6, 1.4)) then found = true; break end
				end
				if not found then continue end
				local roll = rng:NextNumber()
				if roll < 0.6 then
					part(folder, "Letter", Vector3.new(rng:NextNumber(0.6, 0.9), 0.03, rng:NextNumber(0.8, 1.1)), CFrame.new(x, y + 0.045, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber() < 0.75 and Color3.fromRGB(220, 214, 196) or Color3.fromRGB(196, 176, 140))
				elseif roll < 0.8 then
					for c = 1, 3 do part(folder, "PlayingCard", Vector3.new(0.45, 0.02, 0.65), CFrame.new(x + rng:NextNumber(-0.6, 0.6), y + 0.07 + c * 0.012, z + rng:NextNumber(-0.6, 0.6)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber() < 0.5 and Color3.fromRGB(236, 230, 214) or Color3.fromRGB(160, 30, 34)) end
				else
					-- A clear plastic water bottle (no alcohol anywhere in the game: content maturity, 2026-10-07).
					local b = part(folder, "WaterBottle", Vector3.new(1.0, 0.32, 0.32), CFrame.new(x, y + 0.16, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Color3.fromRGB(150, 205, 240), Enum.Material.Glass)
					b.Shape = Enum.PartType.Cylinder; b.Transparency = 0.35; b.Reflectance = 0.1
				end
				n += 1
			end
			if w > 9 and d > 9 and rng:NextNumber() < (r.type == "Hall" and 0.6 or 0.35) then
				local x, z = rng:NextNumber(r.x1 + 4, r.x2 - 4), rng:NextNumber(r.z1 + 4, r.z2 - 4)
				if not floorClear(mansion, Vector3.new(x, y, z), Vector3.new(4.4, 1.2, 4.4)) or not ceilingClear(mansion, Vector3.new(x, y + 13.96, z)) then continue end
				local tile = part(folder, "FallenPlaster", Vector3.new(rng:NextNumber(2.2, 3.4), 0.3, rng:NextNumber(1.8, 3)), CFrame.new(x, y + 0.35, z) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 6.28), rng:NextNumber(0.08, 0.2)), Color3.fromRGB(214, 210, 196))
				texture(tile, TEX.ceiling, Enum.NormalId.Top, 8, 8)
				part(folder, "CeilingHole", Vector3.new(3.2, 0.05, 2.8), CFrame.new(x, y + 13.96, z), Color3.fromRGB(14, 11, 9))
				n += 1
			end
		end
	end
	return n
end

function M.Apply(mansion, plan, kit)
	if plan.mapKind ~= "Hotel" then return end
	if mansion:GetAttribute("HotelDressingVersion") then return end
	doorCache[mansion] = nil -- the Mansion instance is reused across regenerations: never keep last map's doorways
	currentPlan = plan
	local folder = Instance.new("Folder"); folder.Name = "HotelDressing"; folder.Parent = mansion.Architecture
	local stats = {}
	stats.textured = M.Surfaces(mansion)
	local ok, v = pcall(M.Signs, mansion, plan, folder); stats.signs = ok and v or -1
	if not ok then warn("[HotelDressing] signs: " .. tostring(v)) end
	ok, v = pcall(M.Blood, mansion, plan, folder); stats.blood = ok and v or -1
	if not ok then warn("[HotelDressing] blood: " .. tostring(v)) end
	ok, v = pcall(M.Debris, mansion, plan, folder); stats.debris = ok and v or -1
	if not ok then warn("[HotelDressing] debris: " .. tostring(v)) end
	for k, val in pairs(stats) do mansion:SetAttribute("Hotel_" .. k, val) end
	mansion:SetAttribute("HotelDressingVersion", 1)
end

return M
