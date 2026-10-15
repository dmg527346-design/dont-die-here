-- Cruise map world: dresses the generated interior (carpet/wood/ceiling textures) and builds the
-- ship exterior, the pier, the boat docks, the sea guide route and buoys around the plan.
-- Contract: code/cruise/INTERFACE.md. Visual pieces come from ServerStorage.CruiseKit when present
-- (rbxkit meshes); every piece has a primitive fallback so the map always builds.
local W = require(game:GetService("ReplicatedStorage"):WaitForChild("CruiseWater"))
local M = {}

local TEX = {
	carpet = "rbxassetid://138674610627666",
	wall = "rbxassetid://131439582168473",
	ceiling = "rbxassetid://92591585745357",
	hull = "rbxassetid://111540839726615",
}
local KEEL, RED_TOP, NAVY_TOP, GOLD_TOP, DECK = -14, -9, -3, -2.75, 31
local HULL_OFFSET = 2 -- hull plating sits this far outside the outermost interior wall
local C = {
	white = Color3.fromRGB(226, 222, 212), navy = Color3.fromRGB(31, 45, 74), red = Color3.fromRGB(122, 38, 34),
	gold = Color3.fromRGB(201, 165, 74), teak = Color3.fromRGB(120, 80, 48), dark = Color3.fromRGB(26, 28, 34),
	lit = Color3.fromRGB(255, 214, 140), glass = Color3.fromRGB(22, 30, 36), teal = Color3.fromRGB(61, 224, 208),
	pier = Color3.fromRGB(92, 66, 44), piling = Color3.fromRGB(52, 40, 30),
}

local function part(parent, name, size, cf, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function texture(p, img, face, u, v, transp)
	local t = Instance.new("Texture")
	t.Texture, t.Face, t.StudsPerTileU, t.StudsPerTileV, t.Transparency = img, face, u, v, transp or 0
	t.Parent = p
	return t
end
local function label(p, face, text, color, font)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.CanvasSize = Vector2.new(800, 160)
	g.LightInfluence = 0.2
	g.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = font or Enum.Font.Bodoni
	l.TextColor3 = color or C.gold
	l.Parent = g
	return g
end

-- Clone a CruiseKit model, pivot it and (optionally) stretch it non-uniformly about its pivot.
local kit
local function clone(name, cf, parent, sx, sy, sz)
	local t = kit and kit:FindFirstChild(name)
	if not t then return nil end
	local m = t:Clone()
	if sx and (sx ~= 1 or sy ~= 1 or sz ~= 1) then
		local pivot = m:GetPivot()
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and p ~= m.PrimaryPart then
				local rel = pivot:ToObjectSpace(p.CFrame)
				p.Size = Vector3.new(p.Size.X * sx, p.Size.Y * sy, p.Size.Z * sz)
				p.CFrame = pivot * CFrame.new(rel.X * sx, rel.Y * sy, rel.Z * sz) * rel.Rotation
			end
		end
	end
	m:PivotTo(cf)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true; p.CanTouch = false end
	end
	m.Parent = parent
	return m
end

-- Interior: carpet floors, wood-panel walls, coffered ceilings.
function M.Surfaces(mansion)
	local n = 0
	for _, p in ipairs(mansion.Architecture:GetDescendants()) do
		if p:IsA("BasePart") then
			local s = p:GetAttribute("Surface")
			if s == "cruisefloor" then texture(p, TEX.carpet, Enum.NormalId.Top, 8, 8); n += 1
			elseif s == "cruiseceiling" then texture(p, TEX.ceiling, Enum.NormalId.Bottom, 6, 6); n += 1
			elseif s == "wallpaper" and p.Transparency < 1 then
				texture(p, TEX.wall, Enum.NormalId.Front, 6, 7); texture(p, TEX.wall, Enum.NormalId.Back, 6, 7); n += 1
			end
		end
	end
	return n
end

local function bounds(plan)
	local x1, x2, z1, z2 = math.huge, -math.huge, math.huge, -math.huge
	for _, r in ipairs(plan.rooms) do
		x1, x2, z1, z2 = math.min(x1, r.x1), math.max(x2, r.x2), math.min(z1, r.z1), math.max(z2, r.z2)
	end
	return x1, x2, z1, z2
end

-- One vertical slice of hull plating with the four colour bands (keel..deck), facing `out`.
local function hullSlab(folder, center, along, length, outDir, plateColor)
	local up = Vector3.yAxis
	local back = -outDir -- the part's +Z; its Front face (-Z) looks outward
	local right = up:Cross(back) -- right x up = back keeps the basis right-handed
	local function band(name, y0, y1, color, mat)
		local cf = CFrame.fromMatrix(Vector3.new(center.X, (y0 + y1) / 2, center.Z), right, up, back)
		local p = part(folder, name, Vector3.new(length, y1 - y0, 1), cf, color, mat)
		p.CastShadow = true
		return p
	end
	band("Antifouling", KEEL, RED_TOP, C.red)
	band("WaterlineBand", RED_TOP, NAVY_TOP, C.navy)
	band("Pinstripe", NAVY_TOP, GOLD_TOP, C.gold, Enum.Material.Metal).Size += Vector3.new(0, 0, 0.1)
	local white = band("Topsides", GOLD_TOP, DECK, plateColor or C.white)
	texture(white, TEX.hull, Enum.NormalId.Front, 32, 32)
	return white
end

-- Porthole row along a hull side: some warmly lit, most dark glass.
local function portholes(folder, a, b, y, outDir, rng, spacing)
	local d = (b - a)
	local n = math.floor(d.Magnitude / spacing)
	for i = 1, n - 1 do
		local p = a + d * (i / n)
		local lit = rng:NextNumber() < 0.32
		local disc = part(folder, lit and "PortholeLit" or "Porthole", Vector3.new(0.4, 1.9, 1.9),
			CFrame.lookAt(Vector3.new(p.X, y, p.Z) + outDir * 0.55, Vector3.new(p.X, y, p.Z) + outDir * 2) * CFrame.Angles(0, math.pi / 2, 0),
			lit and C.lit or C.glass, lit and Enum.Material.Neon or Enum.Material.Glass)
		disc.Shape = Enum.PartType.Cylinder
		disc.CastShadow = false
		if not lit then disc.Reflectance = 0.25 end
		local rim = part(folder, "PortholeRim", Vector3.new(0.3, 2.3, 2.3), disc.CFrame * CFrame.new(-0.05, 0, 0), C.gold, Enum.Material.Metal)
		rim.Shape = Enum.PartType.Cylinder
		rim.CastShadow = false
	end
end

local function waterGlow(folder, a, b, outDir)
	local d = b - a
	local mid = (a + b) / 2
	local back = -outDir
	local cf = CFrame.fromMatrix(Vector3.new(mid.X, W.Level + 0.2, mid.Z) + outDir * 0.9, Vector3.yAxis:Cross(back), Vector3.yAxis, back)
	local g = part(folder, "BiolumWaterline", Vector3.new(d.Magnitude, 2.4, 0.3), cf, C.teal, Enum.Material.Neon)
	g.Transparency = 0.55
	g.CastShadow = false
	return g
end

function M.Exterior(mansion, plan, world, rng)
	local hull = Instance.new("Folder"); hull.Name = "Hull"; hull.Parent = world
	local deck = Instance.new("Folder"); deck.Name = "Deck"; deck.Parent = world
	local x1, x2, z1, z2 = bounds(plan)
	local hx1, hx2, hz1, hz2 = x1 - HULL_OFFSET, x2 + HULL_OFFSET, z1 - HULL_OFFSET, z2 + HULL_OFFSET
	local Wd = hx2 - hx1
	local cx = (hx1 + hx2) / 2
	local bowLen = math.clamp(Wd * 0.55, 40, 90)
	local spawnPos = workspace:FindFirstChildOfClass("SpawnLocation") and workspace:FindFirstChildOfClass("SpawnLocation").Position or Vector3.new(cx, 0, z2)
	local ex = spawnPos.X
	local info = { hx1 = hx1, hx2 = hx2, hz1 = hz1, hz2 = hz2, bowLen = bowLen, cx = cx, ex = ex, ey = spawnPos.Y, exteriorZ = z2, maxZ = z2, minX = x1, maxX = x2, minZ = z1 }

	-- port (-X) and starboard (+X) sides
	hullSlab(hull, Vector3.new(hx1 - 0.5, 0, (hz1 + hz2) / 2), Vector3.zAxis, hz2 - hz1 + 1, -Vector3.xAxis)
	hullSlab(hull, Vector3.new(hx2 + 0.5, 0, (hz1 + hz2) / 2), -Vector3.zAxis, hz2 - hz1 + 1, Vector3.xAxis)
	portholes(hull, Vector3.new(hx1 - 1, 0, hz1 + 3), Vector3.new(hx1 - 1, 0, hz2 - 3), 7, -Vector3.xAxis, rng, 6)
	portholes(hull, Vector3.new(hx1 - 1, 0, hz1 + 3), Vector3.new(hx1 - 1, 0, hz2 - 3), 23, -Vector3.xAxis, rng, 6)
	portholes(hull, Vector3.new(hx2 + 1, 0, hz1 + 3), Vector3.new(hx2 + 1, 0, hz2 - 3), 7, Vector3.xAxis, rng, 6)
	portholes(hull, Vector3.new(hx2 + 1, 0, hz1 + 3), Vector3.new(hx2 + 1, 0, hz2 - 3), 23, Vector3.xAxis, rng, 6)
	waterGlow(hull, Vector3.new(hx1 - 1, 0, hz1), Vector3.new(hx1 - 1, 0, hz2), -Vector3.xAxis)
	waterGlow(hull, Vector3.new(hx2 + 1, 0, hz2), Vector3.new(hx2 + 1, 0, hz1), Vector3.xAxis)

	-- transom (stern, +Z) with the gangway opening at the level entrance
	local gap1, gap2 = ex - 9, ex + 9
	local tz = hz2 + 0.5
	if gap1 - hx1 > 1 then hullSlab(hull, Vector3.new((hx1 + gap1) / 2, 0, tz), Vector3.xAxis, gap1 - hx1, Vector3.zAxis) end
	if hx2 - gap2 > 1 then hullSlab(hull, Vector3.new((gap2 + hx2) / 2, 0, tz), Vector3.xAxis, hx2 - gap2, Vector3.zAxis) end
	-- below and above the opening
	local under = part(hull, "TransomUnder", Vector3.new(gap2 - gap1, -1 - KEEL, 1), CFrame.new(ex, (KEEL - 1) / 2, tz), C.navy)
	local over = part(hull, "TransomOver", Vector3.new(gap2 - gap1, DECK - 12, 1), CFrame.new(ex, (12 + DECK) / 2, tz), C.white)
	texture(over, TEX.hull, Enum.NormalId.Back, 32, 32)
	for _, s in ipairs({ -1, 1 }) do part(hull, "GangwayPost", Vector3.new(0.6, 12, 0.8), CFrame.new(ex + s * 9, 6, tz + 0.6), C.gold, Enum.Material.Metal) end
	part(hull, "GangwayLintel", Vector3.new(18.6, 0.6, 0.8), CFrame.new(ex, 12, tz + 0.6), C.gold, Enum.Material.Metal)
	local plaque = part(hull, "NamePlaque", Vector3.new(math.min(46, Wd * 0.5), 5, 0.4), CFrame.new(cx, 22, tz + 0.7), C.dark)
	label(plaque, Enum.NormalId.Back, "S.S. NOCTURNE", C.gold, Enum.Font.Bodoni) -- +Z (Back) faces away from the ship at the stern
	portholes(hull, Vector3.new(hx1 + 3, 0, tz + 0.5), Vector3.new(gap1 - 2, 0, tz + 0.5), 7, Vector3.zAxis, rng, 6)
	portholes(hull, Vector3.new(gap2 + 2, 0, tz + 0.5), Vector3.new(hx2 - 3, 0, tz + 0.5), 7, Vector3.zAxis, rng, 6)
	waterGlow(hull, Vector3.new(hx2, 0, tz + 0.5), Vector3.new(hx1, 0, tz + 0.5), Vector3.zAxis)

	-- bow (pointed, -Z)
	local bowCF = CFrame.new(cx, KEEL, hz1 - bowLen / 2)
	local bow = clone("CruiseBow", bowCF, hull, Wd / 40, (DECK - KEEL) / 45, bowLen / 40)
	if not bow then
		for k = 0, 4 do
			local w = Wd * (1 - k / 5)
			local seg = bowLen / 5
			local p = part(hull, "BowFallback", Vector3.new(w, DECK - KEEL, seg + 0.2), CFrame.new(cx, (KEEL + DECK) / 2, hz1 - seg * (k + 0.5)), C.white)
			p.CastShadow = true
		end
	end
	-- forward waterline glow following the bow flanks
	local tip = Vector3.new(cx, 0, hz1 - bowLen)
	waterGlow(hull, tip, Vector3.new(hx1, 0, hz1), (Vector3.new(-1, 0, 0.55)).Unit)
	waterGlow(hull, Vector3.new(hx2, 0, hz1), tip, (Vector3.new(1, 0, 0.55)).Unit)

	-- top deck
	local slab = part(deck, "TopDeck", Vector3.new(Wd, 1, hz2 - hz1), CFrame.new(cx, DECK - 0.5, (hz1 + hz2) / 2), C.teak, Enum.Material.WoodPlanks)
	slab.CastShadow = true
	-- deckhouse with lit windows, bridge forward, funnels on top
	local dhW = Wd * 0.56
	local dhZ1, dhZ2 = hz1 + 16, hz2 - 14
	local house = part(deck, "Deckhouse", Vector3.new(dhW, 8, dhZ2 - dhZ1), CFrame.new(cx, DECK + 4, (dhZ1 + dhZ2) / 2), C.white)
	texture(house, TEX.hull, Enum.NormalId.Left, 32, 32); texture(house, TEX.hull, Enum.NormalId.Right, 32, 32)
	part(deck, "DeckhouseRoof", Vector3.new(dhW + 2, 0.6, dhZ2 - dhZ1 + 2), CFrame.new(cx, DECK + 8.3, (dhZ1 + dhZ2) / 2), C.teak, Enum.Material.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		local band = part(deck, "WindowBand", Vector3.new(0.3, 2.6, dhZ2 - dhZ1 - 4), CFrame.new(cx + s * (dhW / 2 + 0.1), DECK + 4.5, (dhZ1 + dhZ2) / 2), C.glass, Enum.Material.Glass)
		band.Reflectance = 0.3
		for z = dhZ1 + 4, dhZ2 - 4, 4 do
			if rng:NextNumber() < 0.38 then
				part(deck, "WindowLit", Vector3.new(0.2, 2.2, 3), CFrame.new(cx + s * (dhW / 2 + 0.22), DECK + 4.5, z), C.lit, Enum.Material.Neon).CastShadow = false
			end
		end
	end
	local bridge = clone("CruiseBridge", CFrame.new(cx, DECK, dhZ1 - 7), deck, (Wd * 0.8) / 36, 1, 1)
	if not bridge then
		local b = part(deck, "Bridge", Vector3.new(Wd * 0.8, 9, 14), CFrame.new(cx, DECK + 4.5, dhZ1 - 7), C.white)
		part(deck, "BridgeWindows", Vector3.new(Wd * 0.78, 2.5, 0.3), CFrame.new(cx, DECK + 6.5, dhZ1 - 14.1), C.glass, Enum.Material.Glass)
	end
	local funnelCount = (hz2 - hz1) > 150 and 2 or 1
	local fs = math.clamp(Wd / 90, 1, 1.7)
	for i = 1, funnelCount do
		local fz = funnelCount == 1 and (dhZ1 + dhZ2) / 2 or dhZ1 + (dhZ2 - dhZ1) * (i == 1 and 0.36 or 0.68)
		local f = clone("CruiseFunnel", CFrame.new(cx, DECK + 8.6, fz), deck, fs, fs, fs)
		if not f then
			local p = part(deck, "Funnel", Vector3.new(10 * fs, 18 * fs, 16 * fs), CFrame.new(cx, DECK + 8.6 + 9 * fs, fz), Color3.fromRGB(179, 52, 43))
			part(deck, "FunnelTop", Vector3.new(10.2 * fs, 3 * fs, 16.2 * fs), CFrame.new(cx, DECK + 8.6 + 17 * fs, fz), C.dark)
		end
	end
	-- mast at the bow, string lights from mast to funnel to stern flagstaff
	local mastPos = Vector3.new(cx, DECK, hz1 - bowLen * 0.3)
	local mast = clone("CruiseMast", CFrame.new(mastPos), deck, 1, 1, 1)
	if not mast then part(deck, "Mast", Vector3.new(1.2, 26, 1.2), CFrame.new(mastPos + Vector3.new(0, 13, 0)), C.white) end
	local staff = part(deck, "Flagstaff", Vector3.new(0.5, 14, 0.5), CFrame.new(cx, DECK + 7, hz2 - 2), C.white)
	local flag = part(deck, "Flag", Vector3.new(0.1, 3, 5), CFrame.new(cx, DECK + 12.5, hz2 + 0.6), Color3.fromRGB(70, 22, 30), Enum.Material.Fabric)
	local function bulbs(a, b, n)
		for i = 0, n do
			local p = a:Lerp(b, i / n) - Vector3.new(0, math.sin(math.pi * i / n) * 2.5, 0)
			local blb = part(deck, "DeckBulb", Vector3.new(0.6, 0.6, 0.6), CFrame.new(p), (i % 3 == 0) and C.teal or C.lit, Enum.Material.Neon)
			blb.Shape = Enum.PartType.Ball
			blb.CastShadow = false
			if rng:NextNumber() < 0.15 then blb.Color = C.dark; blb.Material = Enum.Material.SmoothPlastic end
		end
	end
	local mastTop = mastPos + Vector3.new(0, 25, 0)
	local funnelTop = Vector3.new(cx, DECK + 8.6 + 17 * fs, dhZ1 + (dhZ2 - dhZ1) * 0.36)
	bulbs(mastTop, funnelTop, 18)
	bulbs(funnelTop, Vector3.new(cx, DECK + 14, hz2 - 2), 18)
	-- lifeboats on davits along both sides
	local boats = 0
	for z = hz1 + 22, hz2 - 20, 26 do
		for _, s in ipairs({ -1, 1 }) do
			if boats >= 12 then break end
			local edgeX = s < 0 and hx1 or hx2
			local dav = clone("CruiseDavit", CFrame.new(edgeX - s * 2.5, DECK, z) * CFrame.Angles(0, s < 0 and math.pi or 0, 0), deck, 1, 1, 1)
			local lb = clone("CruiseLifeboat", CFrame.new(edgeX + s * 2.2, DECK + 1.2, z), deck, 1, 1, 1)
			if not lb then
				part(deck, "Lifeboat", Vector3.new(4.5, 4, 12), CFrame.new(edgeX + s * 2.2, DECK + 3, z), Color3.fromRGB(226, 116, 46))
			end
			boats += 1
		end
	end
	-- railings around the deck edge (sides + stern)
	local function railRun(a, b)
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / 8))
		for i = 0, n - 1 do
			local p = a + d * ((i + 0.5) / n)
			local r = clone("CruiseRailing", CFrame.lookAt(Vector3.new(p.X, DECK, p.Z), Vector3.new(p.X, DECK, p.Z) + Vector3.new(-d.Z, 0, d.X)), deck, d.Magnitude / n / 8, 1, 1)
			if not r then
				part(deck, "Rail", Vector3.new(d.Magnitude / n, 0.25, 0.25), CFrame.lookAt(Vector3.new(p.X, DECK + 3.4, p.Z), Vector3.new(p.X, DECK + 3.4, p.Z) + Vector3.new(-d.Z, 0, d.X)) * CFrame.Angles(0, math.pi / 2, 0), C.white)
			end
		end
	end
	railRun(Vector3.new(hx1 + 0.4, 0, hz1), Vector3.new(hx1 + 0.4, 0, hz2 - 0.4))
	railRun(Vector3.new(hx2 - 0.4, 0, hz2 - 0.4), Vector3.new(hx2 - 0.4, 0, hz1))
	railRun(Vector3.new(hx1 + 0.4, 0, hz2 - 0.4), Vector3.new(hx2 - 0.4, 0, hz2 - 0.4))
	railRun(Vector3.new(hx1 + 0.4, 0, hz1), tip + Vector3.new(0, 0, 3))
	railRun(tip + Vector3.new(0, 0, 3), Vector3.new(hx2 - 0.4, 0, hz1))

	-- a few deck floodlights so the ship reads from the water, and teal glow under the waterline
	local function flood(pos, color, range, bright)
		local h = part(deck, "Floodlight", Vector3.new(0.8, 0.8, 0.8), CFrame.new(pos), color, Enum.Material.Neon)
		h.CastShadow = false
		local l = Instance.new("PointLight"); l.Color = color; l.Range = range; l.Brightness = bright; l.Shadows = false; l.Parent = h
	end
	for i, z in ipairs({ hz1 + 8, (hz1 + hz2) / 2, hz2 - 8 }) do
		flood(Vector3.new(hx1 - 1.5, DECK + 1.5, z), C.lit, 34, 0.9)
		flood(Vector3.new(hx2 + 1.5, DECK + 1.5, z), C.lit, 34, 0.9)
	end
	for z = hz1, hz2, math.max(30, (hz2 - hz1) / 4) do
		flood(Vector3.new(hx1 - 2, W.Level + 2.2, z), C.teal, 22, 1.2)
		flood(Vector3.new(hx2 + 2, W.Level + 2.2, z), C.teal, 22, 1.2)
	end
	flood(tip + Vector3.new(0, W.Level + 2.2, -3), C.teal, 22, 1.2)
	return info
end

-- Pier + courtyard dressing behind the stern (RecoveryModels.Van owns the invisible courtyard walls).
function M.Pier(world, info, rng)
	local f = Instance.new("Model"); f.Name = "Pier"; f.Parent = world
	local ex, ey = info.ex, info.ey
	local zA, zB = info.maxZ + 0.2, info.exteriorZ + 12 + 25 + 29 + 1
	local deckY = ey - 0.55 -- under the courtyard apron (top at ey-0.05)
	local deckPart = part(f, "PierDeck", Vector3.new(40, 1, zB - zA), CFrame.new(ex, deckY, (zA + zB) / 2), C.pier, Enum.Material.WoodPlanks, true)
	deckPart.CastShadow = true
	for _, s in ipairs({ -1, 1 }) do
		part(f, "PierStringer", Vector3.new(1, 1.6, zB - zA), CFrame.new(ex + s * 20, deckY - 0.8, (zA + zB) / 2), C.piling, Enum.Material.Wood)
		for z = zA + 4, zB - 2, 12 do
			local pile = part(f, "Piling", Vector3.new(22, 1.6, 1.6), CFrame.new(ex + s * 20, deckY - 9, z) * CFrame.Angles(0, 0, math.pi / 2), C.piling, Enum.Material.Wood)
			pile.Shape = Enum.PartType.Cylinder
			local ring = part(f, "BarnacleGlow", Vector3.new(0.6, 2.4, 2.4), CFrame.new(ex + s * 20, W.Level + 0.4, z) * CFrame.Angles(0, 0, math.pi / 2), C.teal, Enum.Material.Neon)
			ring.Shape = Enum.PartType.Cylinder; ring.Transparency = 0.45; ring.CastShadow = false
			local pc = clone("CruisePiling", CFrame.new(ex + s * 20, ey - 0.05, z), f, 1, 1, 1)
			if not pc then
				local lamp = part(f, "PierLamp", Vector3.new(0.8, 0.8, 0.8), CFrame.new(ex + s * 20, ey + 3.4, z), C.lit, Enum.Material.Neon)
				lamp.CastShadow = false
			end
		end
		local lightHost = part(f, "PierLightHost", Vector3.new(0.2, 0.2, 0.2), CFrame.new(ex + s * 20, ey + 4, (zA + zB) / 2), C.lit)
		lightHost.Transparency = 1
		local l = Instance.new("PointLight"); l.Range = 30; l.Brightness = 0.8; l.Color = C.lit; l.Shadows = false; l.Parent = lightHost
	end
	-- railings along both pier edges (visual; the courtyard boundary keeps players on the pier)
	for _, s in ipairs({ -1, 1 }) do
		for z = zA + 4, zB - 4, 8 do
			local r = clone("CruiseRailing", CFrame.new(ex + s * 19.6, ey - 0.05, z) * CFrame.Angles(0, math.pi / 2, 0), f, 1, 1, 1)
			if not r then part(f, "PierRail", Vector3.new(0.3, 0.3, 8), CFrame.new(ex + s * 19.6, ey + 3.3, z), C.white) end
		end
	end
	-- boarding arch at the stern end of the pier
	local arch = part(f, "BoardingSign", Vector3.new(16, 2.4, 0.4), CFrame.new(ex, ey + 13.5, zA + 6), C.dark)
	label(arch, Enum.NormalId.Back, "BOARDING  ·  S.S. NOCTURNE", C.gold)
	label(arch, Enum.NormalId.Front, "VAN  ·  RECOVERY", Color3.fromRGB(167, 202, 127))
	for _, s in ipairs({ -1, 1 }) do part(f, "ArchPost", Vector3.new(0.8, 14, 0.8), CFrame.new(ex + s * 8.5, ey + 6.9, zA + 6), C.gold, Enum.Material.Metal) end

	-- boat slip on the starboard (+X) side of the pier with a finger pier
	local slipX = ex + 20 + 9
	local slipZ = info.exteriorZ + 34
	local finger = part(f, "FingerPier", Vector3.new(4, 1, 30), CFrame.new(slipX + 8, deckY, slipZ), C.pier, Enum.Material.WoodPlanks)
	for _, dz in ipairs({ -13, 0, 13 }) do
		local pile = part(f, "FingerPiling", Vector3.new(20, 1.2, 1.2), CFrame.new(slipX + 8, deckY - 9, slipZ + dz) * CFrame.Angles(0, 0, math.pi / 2), C.piling, Enum.Material.Wood)
		pile.Shape = Enum.PartType.Cylinder
	end
	local slipGlow = part(f, "SlipGlow", Vector3.new(0.4, 9, 9), CFrame.new(slipX, W.Level + 0.3, slipZ) * CFrame.Angles(0, 0, math.pi / 2), C.teal, Enum.Material.Neon)
	slipGlow.Shape = Enum.PartType.Cylinder; slipGlow.Transparency = 0.6; slipGlow.CastShadow = false
	local slipSign = part(f, "SlipSign", Vector3.new(6, 1.6, 0.3), CFrame.new(ex + 19.2, ey + 4.5, slipZ) * CFrame.Angles(0, math.pi / 2, 0), C.dark)
	label(slipSign, Enum.NormalId.Front, "BOAT SLIP", C.teal, Enum.Font.GothamBold)
	label(slipSign, Enum.NormalId.Back, "BOAT SLIP", C.teal, Enum.Font.GothamBold)
	info.pierMin = Vector3.new(ex - 21, 0, info.maxZ)
	info.pierMax = Vector3.new(ex + 21, 0, zB)
	info.pierEnd = zB
	info.slip = Vector3.new(slipX, W.Level, slipZ)
	return f
end

-- Docks: Home (pier slip) + ship gangways on hull sides, choosing public L0 rooms on the edge.
function M.Docks(world, plan, info, rng)
	local docks = Instance.new("Folder"); docks.Name = "Docks"; docks.Parent = world
	local beacons = Instance.new("Folder"); beacons.Name = "Beacons"; beacons.Parent = world
	local made = {}
	local function dock(id, labelText, moor, spawnCF, boardCF, home, outward)
		local p = part(docks, id, Vector3.new(2, 2, 2), moor, C.teal)
		p.Transparency = 1
		p:SetAttribute("Label", labelText)
		p:SetAttribute("BoatMoor", moor)
		p:SetAttribute("DeckSpawn", spawnCF)
		p:SetAttribute("BoardSpot", boardCF)
		p:SetAttribute("Radius", 16)
		p:SetAttribute("Home", home == true)
		table.insert(made, p)
		-- floating beacon next to the moor point with a readable label
		local bpos = moor.Position + (outward or Vector3.xAxis) * 9
		local b = clone("CruiseDockBeacon", CFrame.new(bpos.X, W.Level - 1, bpos.Z), beacons, 1, 1, 1)
		local host = b and b.PrimaryPart or part(beacons, "BeaconPost", Vector3.new(1, 10, 1), CFrame.new(bpos.X, W.Level + 4, bpos.Z), C.white)
		local bb = Instance.new("BillboardGui")
		bb.Name = "DockLabel"; bb.Size = UDim2.fromOffset(200, 46); bb.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
		bb.AlwaysOnTop = false; bb.MaxDistance = 220; bb.LightInfluence = 0; bb.Adornee = host; bb.Parent = host
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextScaled = true
		t.Text = string.upper(labelText); t.TextColor3 = home and Color3.fromRGB(167, 202, 127) or C.teal; t.TextStrokeTransparency = 0.4
		t.Parent = bb
		local glow = Instance.new("PointLight"); glow.Color = C.teal; glow.Range = 16; glow.Brightness = 1.2; glow.Parent = host
		return p
	end
	-- Home: the pier slip (boat faces the ship, -Z)
	local slip = info.slip
	dock("Home", "Pier Slip", CFrame.new(slip.X, W.Level, slip.Z),
		CFrame.new(info.ex + 14, info.ey + 3, slip.Z), CFrame.new(info.ex + 17.5, info.ey + 2.5, slip.Z), true, Vector3.xAxis)

	-- ship gangways: prefer halls, then unlocked public rooms, on the hull sides at L0
	local locked = {}
	for _, e in ipairs(plan.edges) do if e.locked or e.lock then locked[e.a] = true; locked[e.b] = true end end
	local function candidates(side)
		local list, halls = {}, {}
		for _, r in ipairs(plan.rooms) do
			if r.level == 0 and r.type ~= "Stair" and r.name ~= plan.start and not locked[r.name] then
				local touch = side < 0 and math.abs(r.x1 - info.minX) < 0.6 or (side > 0 and math.abs(r.x2 - info.maxX) < 0.6)
				if touch then table.insert(list, r); if r.type == "Hall" then table.insert(halls, r) end end
			end
		end
		table.sort(list, function(a, b)
			local ah, bh = a.type == "Hall" and 0 or 1, b.type == "Hall" and 0 or 1
			if ah ~= bh then return ah < bh end
			return math.abs((a.z1 + a.z2) / 2 - (info.hz1 + info.hz2) / 2) < math.abs((b.z1 + b.z2) / 2 - (info.hz1 + info.hz2) / 2)
		end)
		if #halls > 0 then return halls end -- public spine first: never drop players behind a lock
		return list
	end
	local wantPerSide = (info.hz2 - info.hz1) > 170 and 2 or 1
	local hatches = Instance.new("Folder"); hatches.Name = "Hatches"; hatches.Parent = world
	local names = { [-1] = "Port", [1] = "Starboard" }
	for _, side in ipairs({ -1, 1 }) do
		local used = {}
		for _, r in ipairs(candidates(side)) do
			if #used >= wantPerSide then break end
			local zc = math.clamp(r.navz or (r.z1 + r.z2) / 2, r.z1 + 4, r.z2 - 4)
			local clash = false
			for _, z in ipairs(used) do if math.abs(z - zc) < 40 then clash = true end end
			if not clash and zc > info.hz1 + 10 and zc < info.hz2 - 10 then
				table.insert(used, zc)
				local id = names[side] .. (#used > 1 and "Aft" or "")
				local hullX = side < 0 and info.hx1 or info.hx2
				local moorX = hullX + side * (1 + 4 + 4.5)
				local moor = CFrame.new(moorX, W.Level, zc) -- moored alongside the hull, bow forward (-Z)
				local sx = r.navx or (r.x1 + r.x2) / 2
				local spawnCF = CFrame.new(sx, 3, zc)
				local boardCF = CFrame.new((side < 0 and r.x1 + 2.2 or r.x2 - 2.2), 2.5, zc)
				local labelText = (names[side] .. " Gangway") .. (#used > 1 and " (Aft)" or "")
				dock(id, labelText, moor, spawnCF, boardCF, false, Vector3.new(side, 0, 0))
				-- hatch on the hull: dark door, teal frame, ladder down to the water
				local outward = Vector3.new(side, 0, 0)
				local door = part(hatches, "Hatch", Vector3.new(0.4, 8, 5), CFrame.new(hullX + side * 1.2, 4, zc), C.dark)
				for _, dz in ipairs({ -2.7, 2.7 }) do part(hatches, "HatchFrame", Vector3.new(0.5, 8.6, 0.4), CFrame.new(hullX + side * 1.3, 4.1, zc + dz), C.teal, Enum.Material.Neon).CastShadow = false end
				part(hatches, "HatchLintel", Vector3.new(0.5, 0.4, 5.8), CFrame.new(hullX + side * 1.3, 8.4, zc), C.teal, Enum.Material.Neon).CastShadow = false
				local lad = clone("CruiseLadder", CFrame.new(hullX + side * 1.6, W.Level - 3, zc) * CFrame.Angles(0, side < 0 and -math.pi / 2 or math.pi / 2, 0), hatches, 1, 1, 1)
				if not lad then
					for y = W.Level, 0, 1.2 do part(hatches, "Rung", Vector3.new(0.3, 0.3, 3), CFrame.new(hullX + side * 1.6, y, zc), C.gold, Enum.Material.Metal) end
				end
			end
		end
	end
	return made
end

-- Guide ring around ship + pier, routes from Home to each dock, channel and boundary buoys.
function M.Guide(world, info, docks)
	local guide = Instance.new("Folder"); guide.Name = "Guide"; guide.Parent = world
	local buoys = Instance.new("Folder"); buoys.Name = "Buoys"; buoys.Parent = world
	local R = 18
	local tip = Vector3.new(info.cx, W.Level, info.hz1 - info.bowLen)
	local y = W.Level
	-- loop: slip -> starboard stern -> starboard bow -> bow tip -> port bow -> port stern -> pier end west -> pier end east -> slip
	local ring = {
		Vector3.new(info.hx2 + R, y, info.hz2 + R),
		Vector3.new(info.hx2 + R, y, info.hz1),
		Vector3.new(info.cx + (info.hx2 - info.cx) * 0.55, y, tip.Z + info.bowLen * 0.35),
		tip - Vector3.new(0, 0, R),
		Vector3.new(info.cx - (info.cx - info.hx1) * 0.55, y, tip.Z + info.bowLen * 0.35),
		Vector3.new(info.hx1 - R, y, info.hz1),
		Vector3.new(info.hx1 - R, y, info.hz2 + R),
		Vector3.new(info.pierMin.X - R, y, info.pierEnd + R),
		Vector3.new(info.pierMax.X + R, y, info.pierEnd + R),
	}
	local function nearestIndex(p)
		local best, bi = math.huge, 1
		for i, q in ipairs(ring) do local d = (Vector3.new(q.X, 0, q.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude; if d < best then best, bi = d, i end end
		return bi
	end
	local home
	for _, d in ipairs(docks) do if d:GetAttribute("Home") then home = d end end
	local homeIdx = nearestIndex(home.Position)
	for _, d in ipairs(docks) do
		if not d:GetAttribute("Home") then
			local target = nearestIndex(d.Position)
			local n = #ring
			local fwd, back = {}, {}
			local i = homeIdx
			while true do table.insert(fwd, ring[i]); if i == target then break end; i = i % n + 1 end
			i = homeIdx
			while true do table.insert(back, ring[i]); if i == target then break end; i = (i - 2) % n + 1 end
			local function len(path) local s = 0; for k = 2, #path do s += (path[k] - path[k - 1]).Magnitude end; return s end
			local path = len(fwd) <= len(back) and fwd or back
			local pts = { home.Position }
			for _, q in ipairs(path) do table.insert(pts, q) end
			table.insert(pts, d.Position)
			for k, q in ipairs(pts) do
				local wp = part(guide, "R_" .. d.Name .. "_" .. k, Vector3.new(1, 1, 1), CFrame.new(q.X, W.Level, q.Z), C.teal)
				wp.Transparency = 1
			end
		end
	end
	-- channel buoys just outside the ring: green to starboard of the loop direction, red to port
	local function buoy(p, kind, lit)
		local m = clone(kind == "red" and "CruiseBuoyRed" or "CruiseBuoyGreen", CFrame.new(p.X, W.Level, p.Z), buoys, 1, 1, 1)
		local host
		if m then host = m.PrimaryPart; m:AddTag("CruiseFloat")
		else
			host = part(buoys, "Buoy", Vector3.new(3, 3, 3), CFrame.new(p.X, W.Level + 0.5, p.Z), kind == "red" and Color3.fromRGB(190, 40, 40) or Color3.fromRGB(40, 160, 70))
			host.Shape = Enum.PartType.Ball
			host:AddTag("CruiseFloat")
		end
		if not lit then return end
		local l = Instance.new("PointLight"); l.Range = 12; l.Brightness = 1.5
		l.Color = kind == "red" and Color3.fromRGB(255, 70, 60) or (kind == "amber" and Color3.fromRGB(255, 180, 60) or Color3.fromRGB(80, 255, 120))
		l.Parent = host
	end
	for i = 1, #ring do
		local a, b = ring[i], ring[i % #ring + 1]
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / 42))
		local outward = Vector3.new(-d.Z, 0, d.X).Unit -- this loop runs clockwise from above: left of travel is open water
		for k = 0, n - 1 do
			local p = a + d * ((k + 0.5) / n)
			buoy(p + outward * 10, (k % 2 == 0) and "green" or "red", true)
		end
	end
	-- sea limit: amber buoys along the boundary
	local smin, smax = info.seaMin, info.seaMax
	local corners = { Vector3.new(smin.X, 0, smin.Z), Vector3.new(smax.X, 0, smin.Z), Vector3.new(smax.X, 0, smax.Z), Vector3.new(smin.X, 0, smax.Z) }
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / 50))
		for k = 0, n - 1 do buoy(a + d * (k / n), "amber") end
	end
	return guide
end

function M.Apply(mansion, plan, kitFolder)
	if plan.mapKind ~= "Cruise" then return end
	if mansion:GetAttribute("CruiseWorldVersion") then return end
	kit = game:GetService("ServerStorage"):FindFirstChild("CruiseKit")
	local rng = Random.new((plan.seed or 1) + 7070)
	local world = Instance.new("Folder"); world.Name = "CruiseWorld"; world.Parent = mansion
	local stats = {}
	stats.textured = M.Surfaces(mansion)
	local info = M.Exterior(mansion, plan, world, rng)
	M.Pier(world, info, rng)
	info.seaMin = Vector3.new(info.hx1 - 70, 0, info.hz1 - info.bowLen - 70)
	info.seaMax = Vector3.new(math.max(info.hx2, info.pierMax.X + 40) + 70, 0, info.pierEnd + 60)
	local docks = M.Docks(world, plan, info, rng)
	M.Guide(world, info, docks)
	world:SetAttribute("WaterLevel", W.Level)
	world:SetAttribute("HullMin", Vector3.new(info.hx1 - 1, 0, info.hz1 - info.bowLen))
	world:SetAttribute("HullMax", Vector3.new(info.hx2 + 1, 0, info.hz2 + 1))
	world:SetAttribute("SeaMin", info.seaMin)
	world:SetAttribute("SeaMax", info.seaMax)
	world:SetAttribute("PierMin", info.pierMin)
	world:SetAttribute("PierMax", info.pierMax)
	stats.docks = #docks
	for k, v in pairs(stats) do mansion:SetAttribute("Cruise_" .. k, v) end
	mansion:SetAttribute("CruiseWorldVersion", 1)
end

return M
