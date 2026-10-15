-- Hospital map finish: abandoned, haunted 1970s hospital. Textures, failing fluorescent troffers, ward plaques and
-- EXIT signs, scrawled messages (no blood), papers, x-ray films and fallen ceiling tiles.
-- Cosmetic only: every added part is non-colliding, non-queryable and tagged NonBlockingDetail.
local M = {}
local TEX = {
	floor = "rbxassetid://123767087934872",
	wall = "rbxassetid://72153221483318",
	ceiling = "rbxassetid://74048050620689",
	tile = "rbxassetid://71715566036896",
	blood = "rbxassetid://135676916041630",
}
local LIGHT = Color3.fromRGB(214, 236, 222) -- cold, slightly green fluorescent
local DEAD = Color3.fromRGB(112, 118, 110)
local BLOOD = Color3.fromRGB(14, 12, 12) -- old dried blood: near black
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
			if s == "hospitalfloor" then
				p.Material = Enum.Material.SmoothPlastic; p.Reflectance = 0.04
				texture(p, TEX.floor, Enum.NormalId.Top, 8, 8); n += 1
			elseif s == "hospitalceiling" then
				texture(p, TEX.ceiling, Enum.NormalId.Bottom, 8, 8); n += 1
			elseif s == "hospitaltile" then
				for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
					texture(p, TEX.tile, face, 4, 4)
				end
				n += 1
			elseif s == "hospitalmetal" then
				p.Material = Enum.Material.Metal; p.Reflectance = 0.08
			elseif s == "wallpaper" and p.Transparency < 1 then
				for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
					texture(p, TEX.wall, face, 10, 10)
				end
				n += 1
			end
		end
	end
	return n
end

-- 2x4 troffer. About three in ten are dead, one in four flickers (MallFlickerClient handles the 'MallFlicker' tag).
function M.Troffer(parent, cf, rng, room)
	local model = Instance.new("Model"); model.Name = "HospitalTroffer"; model:SetAttribute("Room", room); model.Parent = parent
	local frame = part(model, "TrofferFrame", Vector3.new(2.3, 0.12, 4.3), cf, Color3.fromRGB(178, 180, 170))
	local roll = rng:NextNumber()
	local dead = roll < 0.3
	local lens = part(model, "Diffuser", Vector3.new(2, 0.06, 4), cf * CFrame.new(0, -0.07, 0), dead and DEAD or LIGHT, dead and Enum.Material.SmoothPlastic or Enum.Material.Neon)
	for _, x in ipairs({ -0.5, 0.5 }) do part(model, "Louver", Vector3.new(0.06, 0.08, 4), cf * CFrame.new(x, -0.1, 0), Color3.fromRGB(150, 152, 142)) end
	model.PrimaryPart = frame
	if dead then
		if rng:NextNumber() < 0.4 then -- a dead panel hanging by one corner
			lens.CFrame = cf * CFrame.new(0.6, -0.9, 1.2) * CFrame.Angles(math.rad(rng:NextNumber(25, 50)), 0, math.rad(rng:NextNumber(-10, 10)))
		end
		return model, false
	end
	lens.Transparency = 0.15
	local l = Instance.new("SurfaceLight")
	l.Name = "SteadyRoomLight"; l.Face = Enum.NormalId.Bottom; l.Angle = 120; l.Range = 20; l.Brightness = 0.55; l.Color = LIGHT; l.Shadows = false
	l.Parent = lens
	if roll > 0.75 then lens:AddTag("MallFlicker") end
	return model, true
end

function M.Fixtures(mansion, plan, steady)
	local rng = Random.new((plan.seed or 1) + 4343)
	local count, lit = 0, 0
	for _, r in ipairs(plan.rooms or {}) do
		if not (r.x1 and r.x2 and r.z1 and r.z2) then continue end -- legacy/fallback graphs can lack a rect
		if r.type == "Stair" then
			local st = plan.stairs and r.stair and plan.stairs[r.stair]
			if st and st.cx and st.cz and st.yaw then
				local s = st.horizontalScale or 1
				local wall = CFrame.new(st.cx, (r.level or 0) * FLOOR_H + 8.5, st.cz) * CFrame.Angles(0, st.yaw, 0) * CFrame.new(11.1 * s, 0, 0)
				local model = Instance.new("Model"); model.Name = "HospitalStairLight"; model:SetAttribute("Room", r.name); model.Parent = steady
				local plate = part(model, "WallPlate", Vector3.new(0.2, 1.2, 2.4), wall, Color3.fromRGB(150, 152, 142))
				local lens = part(model, "Diffuser", Vector3.new(0.12, 0.8, 2), wall * CFrame.new(-0.14, 0, 0), LIGHT, Enum.Material.Neon)
				lens.Transparency = 0.15
				local l = Instance.new("PointLight"); l.Name = "SteadyRoomLight"; l.Range = 18; l.Brightness = 0.6; l.Color = LIGHT; l.Shadows = false; l.Parent = lens
				model.PrimaryPart = plate; count += 1; lit += 1
			end
		else
			local w, d = r.x2 - r.x1, r.z2 - r.z1
			local spacing = r.type == "Hall" and 20 or 22
			local nx, nz = math.max(1, math.floor(w / spacing + 0.5)), math.max(1, math.floor(d / spacing + 0.5))
			local alongX = w >= d
			local roomLit = 0
			for ix = 1, nx do
				for iz = 1, nz do
					local cf = CFrame.new(r.x1 + w * (ix - 0.5) / nx, (r.level or 0) * FLOOR_H + 13.94, r.z1 + d * (iz - 0.5) / nz) * (alongX and CFrame.Angles(0, math.pi / 2, 0) or CFrame.new())
					local tm, on = M.Troffer(steady, cf, rng, r.name)
					if on then
						roomLit += 1
						if roomLit > 4 then local sl = tm:FindFirstChildWhichIsA("SurfaceLight", true); if sl then sl:Destroy() end end
					end
					count += 1; lit += on and 1 or 0
				end
			end
		end
	end
	return count, lit
end

local function plaque(parent, text, cf, rng, color, glow)
	local board = part(parent, "WardSign", Vector3.new(5, 0.9, 1.8), cf, Color3.fromRGB(26, 52, 40))
	if color then board.Color = color end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui"); gui.Face = face; gui.CanvasSize = Vector2.new(600, 108)
		gui.LightInfluence = glow and 0 or 1; gui.Brightness = glow and 1.6 or 1; gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.92, 0.78); label.Position = UDim2.fromScale(0.04, 0.11); label.BackgroundTransparency = 1
		label.Text = string.upper(tostring(text or "WARD")); label.Font = Enum.Font.Arimo; label.TextScaled = true
		label.TextColor3 = glow and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(226, 232, 214)
		label.Parent = gui
	end
	if rng:NextNumber() < 0.25 and not glow then -- hanging crooked
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
	for _, e in ipairs(plan.edges or {}) do
		if not (e.x and e.z and e.y) then continue end
		if e.kind == "door" or e.kind == "open" then
			local a, b = by[e.a], by[e.b]
			if a and b then
				local hall = (a.type == "Hall" and b.type ~= "Hall" and b.type ~= "Stair" and a) or (b.type == "Hall" and a.type ~= "Hall" and a.type ~= "Stair" and b)
				local cf = e.axis == "x" and CFrame.new(e.x, e.y + 10.8, e.z) or CFrame.new(e.x, e.y + 10.8, e.z) * CFrame.Angles(0, math.pi / 2, 0)
				if hall then
					local room = hall == a and b or a
					plaque(folder, room.purpose or room.type, cf, rng); n += 1
				elseif a.type == "Hall" and b.type == "Hall" and rng:NextNumber() < 0.35 then
					local s = plaque(folder, "EXIT", cf * CFrame.new(0, 1.2, 0), rng, Color3.fromRGB(30, 12, 12), true)
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

local SCRAWL = { "HELP US", "IT CRAWLS", "DON'T LOOK UP", "GET OUT", "WARD 6 NEVER LEFT", "IT HEARS YOU", "NO ONE LEAVES" }

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
			if rng:NextNumber() < 0.55 then
				local side = rng:NextInteger(1, 4)
				local along = rng:NextNumber(0.25, 0.75)
				local cf
				if side == 1 then cf = CFrame.new(r.x1 + w * along, y + rng:NextNumber(3.5, 6), r.z1 + 0.78)
				elseif side == 2 then cf = CFrame.new(r.x1 + w * along, y + rng:NextNumber(3.5, 6), r.z2 - 0.78) * CFrame.Angles(0, math.pi, 0)
				elseif side == 3 then cf = CFrame.new(r.x1 + 0.78, y + rng:NextNumber(3.5, 6), r.z1 + d * along) * CFrame.Angles(0, math.pi / 2, 0) -- Back face (decal) points +X into the room
				else cf = CFrame.new(r.x2 - 0.78, y + rng:NextNumber(3.5, 6), r.z1 + d * along) * CFrame.Angles(0, -math.pi / 2, 0) end -- Back face points -X into the room
				local wallLen = (side <= 2) and w or d
				local s = math.min(rng:NextNumber(4, 6.5), wallLen - 2)
				if s < 2.5 then continue end
				local wantScrawl = rng:NextNumber() < 0.3
				if not wallClear(mansion, cf, s, s) then continue end
				-- No blood smears or handprints (content maturity, 2026-10-07): only the scrawled message remains.
				local mw = math.min(9, wallLen - 2)
				if wantScrawl and wallClear(mansion, cf * CFrame.new(0, 2.6, 0), mw, 2.2) then
					local msg = part(folder, "Scrawl", Vector3.new(mw, 2.2, 0.05), cf * CFrame.new(0, 2.6, 0), Color3.new(1, 1, 1))
					msg.Transparency = 1
					local gui = Instance.new("SurfaceGui"); gui.Face = Enum.NormalId.Back; gui.CanvasSize = Vector2.new(700, 170); gui.LightInfluence = 1; gui.Parent = msg
					local label = Instance.new("TextLabel"); label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 1
					label.Text = SCRAWL[rng:NextInteger(1, #SCRAWL)]; label.Font = Enum.Font.Creepster; label.TextScaled = true
					label.TextColor3 = BLOOD; label.TextTransparency = 0.1; label.Rotation = rng:NextNumber(-6, 6); label.Parent = gui
					n += 1
				end
			end
			-- floor pools and drag trails
			local pools = 0 -- no blood pools or drag trails (content maturity, 2026-10-07)) + (rng:NextNumber() < 0.45 and 1 or 0)) or 0
			for _ = 1, pools do
				local x, z = rng:NextNumber(r.x1 + 3, r.x2 - 3), rng:NextNumber(r.z1 + 3, r.z2 - 3)
				local s = rng:NextNumber(2, 4)
				if not floorClear(mansion, Vector3.new(x, y, z), Vector3.new(s, 0.6, s)) then continue end
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
				local x, z = rng:NextNumber(r.x1 + 2, r.x2 - 2), rng:NextNumber(r.z1 + 2, r.z2 - 2)
				if not floorClear(mansion, Vector3.new(x, y, z), Vector3.new(1.4, 0.6, 1.4)) then continue end
				local roll = rng:NextNumber()
				if roll < 0.6 then
					part(folder, "Paper", Vector3.new(rng:NextNumber(0.7, 1.0), 0.03, rng:NextNumber(0.9, 1.3)), CFrame.new(x, y + 0.045, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber() < 0.75 and Color3.fromRGB(220, 214, 196) or Color3.fromRGB(196, 176, 140))
				elseif roll < 0.8 then
					local film = part(folder, "XRayFilm", Vector3.new(1.4, 0.03, 1.7), CFrame.new(x, y + 0.04, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Color3.fromRGB(30, 46, 66), Enum.Material.Glass)
					film.Transparency = 0.25; film.Reflectance = 0.35
				else
					local b = part(folder, "PillBottle", Vector3.new(0.5, 0.26, 0.26), CFrame.new(x, y + 0.13, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Color3.fromRGB(196, 120, 40), Enum.Material.Glass)
					b.Shape = Enum.PartType.Cylinder; b.Transparency = 0.3
				end
				n += 1
			end
			if w > 9 and d > 9 and rng:NextNumber() < (r.type == "Hall" and 0.6 or 0.35) then
				local x, z = rng:NextNumber(r.x1 + 4, r.x2 - 4), rng:NextNumber(r.z1 + 4, r.z2 - 4)
				if not floorClear(mansion, Vector3.new(x, y, z), Vector3.new(4.4, 1.2, 4.4)) or not ceilingClear(mansion, Vector3.new(x, y + 13.96, z)) then continue end
				local tile = part(folder, "FallenCeilingTile", Vector3.new(3.8, 0.3, 3.8), CFrame.new(x, y + 0.35, z) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 6.28), rng:NextNumber(0.08, 0.2)), Color3.fromRGB(214, 210, 196))
				texture(tile, TEX.ceiling, Enum.NormalId.Top, 8, 8)
				part(folder, "CeilingHole", Vector3.new(3.9, 0.05, 3.9), CFrame.new(x, y + 13.96, z), Color3.fromRGB(12, 12, 11))
				n += 1
			end
		end
	end
	return n
end

function M.Apply(mansion, plan, kit)
	if plan.mapKind ~= "Hospital" then return end
	if mansion:GetAttribute("HospitalDressingVersion") then return end
	local folder = Instance.new("Folder"); folder.Name = "HospitalDressing"; folder.Parent = mansion.Architecture
	local stats = {}
	stats.textured = M.Surfaces(mansion)
	local ok, v = pcall(M.Signs, mansion, plan, folder); stats.signs = ok and v or -1
	if not ok then warn("[HospitalDressing] signs: " .. tostring(v)) end
	ok, v = pcall(M.Blood, mansion, plan, folder); stats.blood = ok and v or -1
	if not ok then warn("[HospitalDressing] blood: " .. tostring(v)) end
	ok, v = pcall(M.Debris, mansion, plan, folder); stats.debris = ok and v or -1
	if not ok then warn("[HospitalDressing] debris: " .. tostring(v)) end
	for k, val in pairs(stats) do mansion:SetAttribute("Hospital_" .. k, val) end
	mansion:SetAttribute("HospitalDressingVersion", 1)
end

return M
