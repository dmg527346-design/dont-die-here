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
	white = Color3.fromRGB(226, 222, 212), navy = Color3.fromRGB(31, 45, 74), red = Color3.fromRGB(40, 58, 66), -- hull bottom band: slate, not red (red rule, 2026-10-22)
	gold = Color3.fromRGB(201, 165, 74), teak = Color3.fromRGB(106, 90, 70), dark = Color3.fromRGB(26, 28, 34),
	lit = Color3.fromRGB(255, 178, 96), glass = Color3.fromRGB(22, 30, 36), teal = Color3.fromRGB(61, 224, 208),
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
			if s == "cruisefloor" then -- plain navy carpet: the patterned carpet texture was bright red (red rule, 2026-10-21)
				p.Color = Color3.fromRGB(38, 52, 92); p.Material = Enum.Material.Fabric; p.MaterialVariant = ""; if p:IsA("MeshPart") then p.TextureID = "" end; n += 1
			elseif s == "cruiseceiling" then texture(p, TEX.ceiling, Enum.NormalId.Bottom, 6, 6); n += 1
			elseif s == "wallpaper" and p.Transparency < 1 then
				texture(p, TEX.wall, Enum.NormalId.Front, 6, 7); texture(p, TEX.wall, Enum.NormalId.Back, 6, 7); n += 1
				-- end caps show beside open doorways: panel them too instead of leaving a flat untextured strip
				texture(p, TEX.wall, Enum.NormalId.Left, 6, 7); texture(p, TEX.wall, Enum.NormalId.Right, 6, 7)
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
	local g = part(folder, "BiolumWaterline", Vector3.new(d.Magnitude, 1.3, 0.2), cf, C.teal, Enum.Material.Neon)
	g.Transparency = 0.84 -- a faint glow where the sea laps the hull, not a neon stripe
	g.CastShadow = false
	return g
end

function M.Exterior(mansion, plan, world, rng)
	-- Ship frame: length along X (bow at -X, transom at +X), beam along Z. The level entrance and the
	-- pier are on the +Z (port) side; the boat gangways are on the far -Z (starboard) side.
	local hull = Instance.new("Folder"); hull.Name = "Hull"; hull.Parent = world
	local deck = Instance.new("Folder"); deck.Name = "Deck"; deck.Parent = world
	-- The open deck sits just above the top floor's roof and wall tops, so it never cuts into the
	-- upper rooms' ceilings (it used to overlap them and z-fight).
	local top = 0
	for _, p in ipairs(mansion.Architecture:GetDescendants()) do
		if p:IsA("BasePart") then
			local cf, sz = p.CFrame, p.Size
			local halfY = math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z
			top = math.max(top, cf.Position.Y + halfY / 2)
		end
	end
	DECK = math.max(31, top + 1.1)
	local x1, x2, z1, z2 = bounds(plan)
	local hx1, hx2, hz1, hz2 = x1 - HULL_OFFSET, x2 + HULL_OFFSET, z1 - HULL_OFFSET, z2 + HULL_OFFSET
	local beam = hz2 - hz1
	local len = hx2 - hx1
	local cz = (hz1 + hz2) / 2
	local cx = (hx1 + hx2) / 2
	local bowLen = math.clamp(beam * 0.9, 40, 110)
	-- The gangway must line up with THIS layout's entrance. Take it from the plan: during a level change the
	-- workspace SpawnLocation still sits in the previous level's van, so it pointed the gap at the wrong place.
	-- (SpawnLocation sits 2.5 below plan.spawn, which is what the old code read.)
	local sp = workspace:FindFirstChildOfClass("SpawnLocation")
	local spawnPos = (type(plan.spawn) == "table" and plan.spawn[1] and Vector3.new(plan.spawn[1], plan.spawn[2] - 2.5, plan.spawn[3]))
		or (sp and sp.Position) or Vector3.new(cx, 0, z2)
	local ex = spawnPos.X
	local info = { hx1 = hx1, hx2 = hx2, hz1 = hz1, hz2 = hz2, bowLen = bowLen, cx = cx, cz = cz, ex = ex, ey = spawnPos.Y,
		exteriorZ = z2, maxZ = z2, minZ = z1, minX = x1, maxX = x2, beam = beam, len = len }
	local tip = Vector3.new(hx1 - bowLen, 0, cz)
	info.tip = tip

	-- starboard (-Z) side, full length
	hullSlab(hull, Vector3.new(cx, 0, hz1 - 0.5), nil, len + 1, -Vector3.zAxis)
	portholes(hull, Vector3.new(hx1 + 3, 0, hz1 - 1), Vector3.new(hx2 - 3, 0, hz1 - 1), 7, -Vector3.zAxis, rng, 6)
	portholes(hull, Vector3.new(hx1 + 3, 0, hz1 - 1), Vector3.new(hx2 - 3, 0, hz1 - 1), 23, -Vector3.zAxis, rng, 6)
	waterGlow(hull, Vector3.new(hx1, 0, hz1 - 1), Vector3.new(hx2, 0, hz1 - 1), -Vector3.zAxis)
	-- port (+Z) side with the gangway opening at the level entrance
	local gap1, gap2 = ex - 9, ex + 9
	local pz = hz2 + 0.5
	if gap1 - hx1 > 1 then hullSlab(hull, Vector3.new((hx1 + gap1) / 2, 0, pz), nil, gap1 - hx1, Vector3.zAxis) end
	if hx2 - gap2 > 1 then hullSlab(hull, Vector3.new((gap2 + hx2) / 2, 0, pz), nil, hx2 - gap2, Vector3.zAxis) end
	part(hull, "GangwayUnder", Vector3.new(gap2 - gap1, -1 - KEEL, 1), CFrame.new(ex, (KEEL - 1) / 2, pz), C.navy)
	local over = part(hull, "GangwayOver", Vector3.new(gap2 - gap1, DECK - 12, 1), CFrame.new(ex, (12 + DECK) / 2, pz), C.white)
	texture(over, TEX.hull, Enum.NormalId.Back, 32, 32)
	for _, s in ipairs({ -1, 1 }) do part(hull, "GangwayPost", Vector3.new(0.6, 12, 0.8), CFrame.new(ex + s * 9, 6, pz + 0.6), C.gold, Enum.Material.Metal) end
	part(hull, "GangwayLintel", Vector3.new(18.6, 0.6, 0.8), CFrame.new(ex, 12, pz + 0.6), C.gold, Enum.Material.Metal)
	portholes(hull, Vector3.new(hx1 + 3, 0, hz2 + 1), Vector3.new(gap1 - 3, 0, hz2 + 1), 7, Vector3.zAxis, rng, 6)
	portholes(hull, Vector3.new(gap2 + 3, 0, hz2 + 1), Vector3.new(hx2 - 3, 0, hz2 + 1), 7, Vector3.zAxis, rng, 6)
	portholes(hull, Vector3.new(hx1 + 3, 0, hz2 + 1), Vector3.new(hx2 - 3, 0, hz2 + 1), 23, Vector3.zAxis, rng, 6)
	waterGlow(hull, Vector3.new(hx2, 0, hz2 + 1), Vector3.new(hx1, 0, hz2 + 1), Vector3.zAxis)
	-- transom (+X) with the ship's name
	hullSlab(hull, Vector3.new(hx2 + 0.5, 0, cz), nil, beam + 1, Vector3.xAxis)
	local plaque = part(hull, "NamePlaque", Vector3.new(0.4, 5, math.min(46, beam * 0.6)), CFrame.new(hx2 + 1.2, 22, cz), C.dark)
	label(plaque, Enum.NormalId.Right, "S.S. NOCTURNE", C.gold, Enum.Font.Bodoni)
	portholes(hull, Vector3.new(hx2 + 1, 0, hz1 + 3), Vector3.new(hx2 + 1, 0, hz2 - 3), 7, Vector3.xAxis, rng, 6)
	waterGlow(hull, Vector3.new(hx2 + 1, 0, hz1), Vector3.new(hx2 + 1, 0, hz2), Vector3.xAxis)

	-- bow (pointed, -X): the kit bow faces -Z, so turn it a quarter to face -X
	local bow = clone("CruiseBow", CFrame.new(hx1 - bowLen / 2, KEEL, cz) * CFrame.Angles(0, math.pi / 2, 0), hull, beam / 40, (DECK - KEEL) / 45, bowLen / 40)
	if not bow then
		for k = 0, 4 do
			local w = beam * (1 - k / 5)
			local seg = bowLen / 5
			part(hull, "BowFallback", Vector3.new(seg + 0.2, DECK - KEEL, w), CFrame.new(hx1 - seg * (k + 0.5), (KEEL + DECK) / 2, cz), C.white).CastShadow = true
		end
	end
	waterGlow(hull, tip, Vector3.new(hx1, 0, hz1), (Vector3.new(-0.5, 0, -1)).Unit)
	waterGlow(hull, Vector3.new(hx1, 0, hz2), tip, (Vector3.new(-0.5, 0, 1)).Unit)

	-- top deck, deckhouse with lit windows, bridge forward, funnels
	part(deck, "TopDeck", Vector3.new(len, 1, beam), CFrame.new(cx, DECK - 0.5, cz), C.teak, Enum.Material.WoodPlanks).CastShadow = true
	local dhB = beam * 0.56
	local dhX1, dhX2 = hx1 + 18, hx2 - 16
	local house = part(deck, "Deckhouse", Vector3.new(dhX2 - dhX1, 8, dhB), CFrame.new((dhX1 + dhX2) / 2, DECK + 4, cz), C.white)
	texture(house, TEX.hull, Enum.NormalId.Front, 32, 32); texture(house, TEX.hull, Enum.NormalId.Back, 32, 32)
	part(deck, "DeckhouseRoof", Vector3.new(dhX2 - dhX1 + 2, 0.6, dhB + 2), CFrame.new((dhX1 + dhX2) / 2, DECK + 8.3, cz), C.teak, Enum.Material.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		local band = part(deck, "WindowBand", Vector3.new(dhX2 - dhX1 - 4, 2.6, 0.3), CFrame.new((dhX1 + dhX2) / 2, DECK + 4.5, cz + s * (dhB / 2 + 0.1)), C.glass, Enum.Material.Glass)
		band.Reflectance = 0.3
		for x = dhX1 + 4, dhX2 - 4, 4 do
			if rng:NextNumber() < 0.38 then
				part(deck, "WindowLit", Vector3.new(3, 2.2, 0.2), CFrame.new(x, DECK + 4.5, cz + s * (dhB / 2 + 0.22)), C.lit, Enum.Material.Neon).CastShadow = false
			end
		end
	end
	local bridge = clone("CruiseBridge", CFrame.new(dhX1 - 7, DECK, cz) * CFrame.Angles(0, math.pi / 2, 0), deck, (beam * 0.84) / 36, 1, 1)
	if not bridge then
		part(deck, "Bridge", Vector3.new(14, 9, beam * 0.84), CFrame.new(dhX1 - 7, DECK + 4.5, cz), C.white)
		part(deck, "BridgeWindows", Vector3.new(0.3, 2.5, beam * 0.82), CFrame.new(dhX1 - 14.1, DECK + 6.5, cz), C.glass, Enum.Material.Glass)
	end
	local funnelCount = len > 230 and 2 or 1
	local fs = math.clamp(beam / 60, 1, 1.8)
	local funnelTop
	for i = 1, funnelCount do
		local fx = funnelCount == 1 and dhX1 + (dhX2 - dhX1) * 0.45 or dhX1 + (dhX2 - dhX1) * (i == 1 and 0.36 or 0.66)
		-- the kit funnel is long along its Z (front -Z, raked toward +Z): turn it to run along the ship, raked aft (+X)
		local f = clone("CruiseFunnel", CFrame.new(fx, DECK + 8.6, cz) * CFrame.Angles(0, -math.pi / 2, 0), deck, fs, fs, fs)
		if not f then
			part(deck, "Funnel", Vector3.new(16 * fs, 18 * fs, 10 * fs), CFrame.new(fx, DECK + 8.6 + 9 * fs, cz), Color3.fromRGB(58, 74, 96))
			part(deck, "FunnelTop", Vector3.new(16.2 * fs, 3 * fs, 10.2 * fs), CFrame.new(fx, DECK + 8.6 + 17 * fs, cz), C.dark)
		end
		funnelTop = funnelTop or Vector3.new(fx, DECK + 8.6 + 17 * fs, cz)
	end
	local mastPos = Vector3.new(hx1 - bowLen * 0.32, DECK, cz)
	if not clone("CruiseMast", CFrame.new(mastPos), deck, 1, 1, 1) then part(deck, "Mast", Vector3.new(1.2, 26, 1.2), CFrame.new(mastPos + Vector3.new(0, 13, 0)), C.white) end
	part(deck, "Flagstaff", Vector3.new(0.5, 14, 0.5), CFrame.new(hx2 - 2, DECK + 7, cz), C.white)
	part(deck, "Flag", Vector3.new(5, 3, 0.1), CFrame.new(hx2 + 0.6, DECK + 12.5, cz), Color3.fromRGB(40, 60, 90), Enum.Material.Fabric)
	local function bulbs(a, b, n)
		for i = 0, n do
			local p = a:Lerp(b, i / n) - Vector3.new(0, math.sin(math.pi * i / n) * 2.5, 0)
			local blb = part(deck, "DeckBulb", Vector3.new(0.6, 0.6, 0.6), CFrame.new(p), (i % 3 == 0) and C.teal or C.lit, Enum.Material.Neon)
			blb.Shape = Enum.PartType.Ball
			blb.CastShadow = false
			if rng:NextNumber() < 0.15 then blb.Color = C.dark; blb.Material = Enum.Material.SmoothPlastic end
		end
	end
	bulbs(mastPos + Vector3.new(0, 25, 0), funnelTop, 20)
	bulbs(funnelTop, Vector3.new(hx2 - 2, DECK + 14, cz), 20)
	-- lifeboats on davits along both sides (kept clear of the gangway)
	local boats = 0
	for x = hx1 + 24, hx2 - 20, 26 do
		for _, s in ipairs({ -1, 1 }) do
			if boats < 14 and not (s > 0 and math.abs(x - ex) < 16) then
				local edgeZ = s < 0 and hz1 or hz2
				clone("CruiseDavit", CFrame.new(x, DECK, edgeZ - s * 2.5) * CFrame.Angles(0, s < 0 and math.pi / 2 or -math.pi / 2, 0), deck, 1, 1, 1)
				if not clone("CruiseLifeboat", CFrame.new(x, DECK + 1.2, edgeZ + s * 2.2) * CFrame.Angles(0, math.pi / 2, 0), deck, 1, 1, 1) then
					part(deck, "Lifeboat", Vector3.new(12, 4, 4.5), CFrame.new(x, DECK + 3, edgeZ + s * 2.2), Color3.fromRGB(226, 116, 46))
				end
				boats += 1
			end
		end
	end
	local function railRun(a, b)
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / 8))
		for i = 0, n - 1 do
			local p = a + d * ((i + 0.5) / n)
			local perp = Vector3.new(-d.Z, 0, d.X)
			if not clone("CruiseRailing", CFrame.lookAt(Vector3.new(p.X, DECK, p.Z), Vector3.new(p.X, DECK, p.Z) + perp), deck, d.Magnitude / n / 8, 1, 1) then
				part(deck, "Rail", Vector3.new(d.Magnitude / n, 0.25, 0.25), CFrame.lookAt(Vector3.new(p.X, DECK + 3.4, p.Z), Vector3.new(p.X, DECK + 3.4, p.Z) + perp) * CFrame.Angles(0, math.pi / 2, 0), C.white)
			end
		end
	end
	railRun(Vector3.new(hx1, 0, hz1 + 0.4), Vector3.new(hx2 - 0.4, 0, hz1 + 0.4))
	railRun(Vector3.new(hx2 - 0.4, 0, hz2 - 0.4), Vector3.new(hx1, 0, hz2 - 0.4))
	railRun(Vector3.new(hx2 - 0.4, 0, hz1 + 0.4), Vector3.new(hx2 - 0.4, 0, hz2 - 0.4))
	railRun(Vector3.new(hx1, 0, hz2 - 0.4), tip + Vector3.new(3, 0, 0))
	railRun(tip + Vector3.new(3, 0, 0), Vector3.new(hx1, 0, hz1 + 0.4))

	local function flood(pos, color, range, bright)
		local h = part(deck, "Floodlight", Vector3.new(0.8, 0.8, 0.8), CFrame.new(pos), color, Enum.Material.Neon)
		h.CastShadow = false
		local l = Instance.new("PointLight"); l.Color = color; l.Range = range; l.Brightness = bright; l.Shadows = false; l.Parent = h
	end
	for _, x in ipairs({ hx1 + 10, cx, hx2 - 10 }) do
		flood(Vector3.new(x, DECK + 1.5, hz1 - 1.5), C.lit, 34, 0.9)
		flood(Vector3.new(x, DECK + 1.5, hz2 + 1.5), C.lit, 34, 0.9)
	end
	for x = hx1, hx2, math.max(30, len / 5) do
		flood(Vector3.new(x, W.Level + 2.2, hz1 - 2), C.teal, 22, 1.2)
		flood(Vector3.new(x, W.Level + 2.2, hz2 + 2), C.teal, 22, 1.2)
	end
	flood(tip + Vector3.new(-3, W.Level + 2.2, 0), C.teal, 22, 1.2)
	return info
end

-- Pier + courtyard dressing behind the stern (RecoveryModels.Van owns the invisible courtyard walls).
function M.Pier(world, info, rng)
	local f = Instance.new("Model"); f.Name = "Pier"; f.Parent = world
	local ex = info.ex
	local ey = 0.35 -- deck top 0.3: just under the van floor (0.45), about level with the L0 floor (0), no step up
	local zA, zB = info.maxZ, info.exteriorZ + 12 + 25 + 29 + 1
	local deckY = ey - 0.55 -- under the courtyard apron (top at ey-0.05)
	local deckPart = part(f, "PierDeck", Vector3.new(40, 1, zB - zA), CFrame.new(ex, deckY, (zA + zB) / 2), C.pier, Enum.Material.WoodPlanks, true)
	deckPart.CastShadow = true
	for _, s in ipairs({ -1, 1 }) do
		part(f, "PierStringer", Vector3.new(1, 1.6, zB - zA), CFrame.new(ex + s * 20, deckY - 0.8, (zA + zB) / 2), C.piling, Enum.Material.Wood)
		for z = zA + 4, zB - 2, 12 do
			local pile = part(f, "Piling", Vector3.new(22, 1.6, 1.6), CFrame.new(ex + s * 20, deckY - 9, z) * CFrame.Angles(0, 0, math.pi / 2), C.piling, Enum.Material.Wood)
			pile.Shape = Enum.PartType.Cylinder
			local ring = part(f, "BarnacleGlow", Vector3.new(0.6, 2.4, 2.4), CFrame.new(ex + s * 20, W.Level + 0.4, z) * CFrame.Angles(0, 0, math.pi / 2), C.teal, Enum.Material.Neon)
			ring.Shape = Enum.PartType.Cylinder; ring.Transparency = 0.7; ring.CastShadow = false
			local pc = clone("CruisePiling", CFrame.new(ex + s * 21.2, ey - 0.05, z), f, 0.62, 0.62, 0.62) -- on the deck edge, clear of the railing
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
			local r = clone("CruiseRailing", CFrame.new(ex + s * 19.05, ey - 0.05, z) * CFrame.Angles(0, math.pi / 2, 0), f, 1, 1, 1) -- on the van courtyard boundary line, so the railing is where you actually stop
			if not r then part(f, "PierRail", Vector3.new(0.3, 0.3, 8), CFrame.new(ex + s * 19.05, ey + 3.3, z), C.white) end
		end
	end
	info.pierMin = Vector3.new(ex - 21, 0, info.maxZ)
	info.pierMax = Vector3.new(ex + 21, 0, zB)
	info.pierEnd = zB
	return f
end

-- Docks: Home (pier slip) + ship gangways. Far side (-Z, starboard) gets 1-2 gangways, the near side
-- (+Z) one more on long ships, well away from the pier. Only public halls (never behind a lock).
function M.Docks(world, plan, info, rng)
	local docks = Instance.new("Folder"); docks.Name = "Docks"; docks.Parent = world
	local beacons = Instance.new("Folder"); beacons.Name = "Beacons"; beacons.Parent = world
	local hatches = Instance.new("Folder"); hatches.Name = "Hatches"; hatches.Parent = world
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
		local bpos = moor.Position + outward * 9
		local b = clone("CruiseDockBeacon", CFrame.new(bpos.X, W.Level - 1, bpos.Z), beacons, 1, 1, 1)
		local host = b and b.PrimaryPart or part(beacons, "BeaconPost", Vector3.new(1, 10, 1), CFrame.new(bpos.X, W.Level + 4, bpos.Z), C.white)
		if b then
			b:AddTag("CruiseFloat")
			for _, q in ipairs(b:GetDescendants()) do
				if q:IsA("BasePart") then q.CanCollide, q.CanQuery, q.CanTouch = false, false, false end
			end
		end
		local bb = Instance.new("BillboardGui")
		bb.Name = "DockLabel"; bb.Size = UDim2.new(14, 0, 2.6, 0); bb.StudsOffsetWorldSpace = Vector3.new(0, 12.5, 0)
		bb.AlwaysOnTop = false; bb.MaxDistance = 260; bb.LightInfluence = 0; bb.Adornee = host; bb.Parent = host
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextScaled = true
		t.Text = string.upper(labelText); t.TextColor3 = home and Color3.fromRGB(167, 202, 127) or C.teal; t.TextStrokeTransparency = 0.4
		t.Parent = bb
		local glow = Instance.new("PointLight"); glow.Color = C.teal; glow.Range = 16; glow.Brightness = 1.2; glow.Parent = host
		local ring = part(beacons, "MoorRing", Vector3.new(0.4, 12, 12), CFrame.new(moor.Position.X, W.Level + 0.25, moor.Position.Z) * CFrame.Angles(0, 0, math.pi / 2), home and Color3.fromRGB(167, 202, 127) or C.teal, Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder; ring.Transparency = 0.72; ring.CastShadow = false
		ring:AddTag("CruiseFloat")
		return p
	end
	-- Home: the pier slip; the boat lies bow out to open water (+Z)
	local slip = info.slip
	dock("Home", "Pier Slip", CFrame.lookAt(Vector3.new(slip.X, W.Level, slip.Z), Vector3.new(slip.X, W.Level, slip.Z + 1)), -- bow to open water so W drives straight out
		CFrame.new(info.ex + 14, info.ey + 3, slip.Z), CFrame.new(info.ex + 17.5, info.ey + 2.5, slip.Z), true, Vector3.xAxis)

	local byName = {}
	for _, r in ipairs(plan.rooms) do byName[r.name] = r end
	local lockedRoom = {}
	for _, e in ipairs(plan.edges) do
		if e.locked then lockedRoom[e.a] = true; lockedRoom[e.b] = true end
	end
	-- the ground deck can be narrower than the upper deck: measure the hull sides on L0 only
	local minZ0, maxZ0 = math.huge, -math.huge
	for _, r in ipairs(plan.rooms) do if r.level == 0 then minZ0 = math.min(minZ0, r.z1); maxZ0 = math.max(maxZ0, r.z2) end end
	local function touches(r, side)
		-- within 20 studs of the hull side (corridors often run just inside the outer cabins)
		return side < 0 and r.z1 - minZ0 < 20 or (side > 0 and maxZ0 - r.z2 < 20)
	end
	local function usable(r)
		return r and r.level == 0 and r.type ~= "Stair" and r.name ~= plan.start and not lockedRoom[r.name]
	end
	-- public rooms on this hull side: halls first, then rooms opening (unlocked) onto a hall, then one more hop
	local function edgeHalls(side)
		local list, seen = {}, {}
		local function add(r) if r and not seen[r.name] then seen[r.name] = true; table.insert(list, r) end end
		for _, r in ipairs(plan.rooms) do
			if usable(r) and r.type == "Hall" and touches(r, side) then add(r) end
		end
		if #list > 0 then return list end
		local nearHall = {}
		for _, e in ipairs(plan.edges) do
			if not e.locked and e.kind ~= "stairs" then
				local a, b = byName[e.a], byName[e.b]
				if a and b then
					if a.type == "Hall" and usable(b) then nearHall[b.name] = b end
					if b.type == "Hall" and usable(a) then nearHall[a.name] = a end
				end
			end
		end
		for _, r in pairs(nearHall) do if touches(r, side) then add(r) end end
		if #list > 0 then return list end
		for _, e in ipairs(plan.edges) do
			if not e.locked and e.kind ~= "stairs" then
				local a, b = byName[e.a], byName[e.b]
				if a and b then
					if nearHall[a.name] and usable(b) and touches(b, side) then add(b) end
					if nearHall[b.name] and usable(a) and touches(a, side) then add(a) end
				end
			end
		end
		if #list > 0 then return list end
		-- last resort: any unlocked room on this side (every room is reachable through unlocked doors)
		for _, r in ipairs(plan.rooms) do if usable(r) and touches(r, side) then add(r) end end
		return list
	end
	local plans = {
		{ side = -1, want = info.len > 230 and 2 or 1, base = "Starboard" },
		{ side = 1, want = info.len > 260 and 1 or 0, base = "Port" },
	}
	for _, sp in ipairs(plans) do
		local used = {}
		local list = edgeHalls(sp.side)
		-- spread docks along the ship: try points at 30% and 70% of the length first
		local targets = sp.want == 2 and { info.hx1 + info.len * 0.3, info.hx1 + info.len * 0.72 } or { info.hx1 + info.len * 0.45 }
		for _, tx in ipairs(targets) do
			if #used >= sp.want then break end
			local best, bestD
			for _, r in ipairs(list) do
				local xc = math.clamp(tx, r.x1 + 5, r.x2 - 5)
				local d = math.abs(xc - tx)
				local clash = false
				for _, u in ipairs(used) do if math.abs(u - xc) < 45 then clash = true end end
				if sp.side > 0 and math.abs(xc - info.ex) < 70 then clash = true end -- keep clear of the pier
				if not clash and r.x2 - r.x1 >= 10 and (not bestD or d < bestD) then best, bestD = r, d end
			end
			if best then
				local xc = math.clamp(tx, best.x1 + 5, best.x2 - 5)
				table.insert(used, xc)
				local id = sp.base .. (#used > 1 and "Aft" or "")
				local hullZ = sp.side < 0 and info.hz1 or info.hz2
				local moorZ = hullZ + sp.side * 14 -- boat circle radius ~9.8 + 3 hull clearance
				local moor = CFrame.lookAt(Vector3.new(xc, W.Level, moorZ), Vector3.new(xc - 1, W.Level, moorZ)) -- alongside, bow forward (-X)
				local inZ = math.clamp(best.navz or (best.z1 + best.z2) / 2, best.z1 + 3, best.z2 - 3)
				local spawnCF = CFrame.new(xc, 3, inZ)
				local boardCF = CFrame.new(xc, 2.5, sp.side < 0 and best.z1 + 2.2 or best.z2 - 2.2)
				local labelText = sp.base .. " Gangway" .. (#used > 1 and " (Aft)" or "")
				dock(id, labelText, moor, spawnCF, boardCF, false, Vector3.new(0, 0, sp.side))
				-- hatch on the hull: dark door, teal frame, ladder down to the water
				part(hatches, "Hatch", Vector3.new(5, 8, 0.4), CFrame.new(xc, 4, hullZ + sp.side * 1.2), C.dark)
				for _, dx in ipairs({ -2.7, 2.7 }) do part(hatches, "HatchFrame", Vector3.new(0.4, 8.6, 0.5), CFrame.new(xc + dx, 4.1, hullZ + sp.side * 1.3), C.teal, Enum.Material.Neon).CastShadow = false end
				part(hatches, "HatchLintel", Vector3.new(5.8, 0.4, 0.5), CFrame.new(xc, 8.4, hullZ + sp.side * 1.3), C.teal, Enum.Material.Neon).CastShadow = false
				local lad = clone("CruiseLadder", CFrame.new(xc, W.Level - 3, hullZ + sp.side * 1.6) * CFrame.Angles(0, sp.side < 0 and math.pi or 0, 0), hatches, 1, 1, 1)
				if not lad then
					for y = W.Level, 0, 1.2 do part(hatches, "Rung", Vector3.new(3, 0.3, 0.3), CFrame.new(xc, y, hullZ + sp.side * 1.6), C.gold, Enum.Material.Metal) end
				end
				-- an inside marker so players can find the boarding point from the deck
				local sign = part(hatches, "BoatStationSign", Vector3.new(5, 1.2, 0.2), CFrame.new(xc, 9.5, hullZ - sp.side * 2.6), C.dark)
				label(sign, sp.side < 0 and Enum.NormalId.Back or Enum.NormalId.Front, "BOAT STATION", C.teal, Enum.Font.GothamBold)
			end
		end
	end
	return made
end

-- Guide loop around bow, far side, stern and pier; routes from Home to each dock; channel + boundary buoys.
function M.Guide(world, info, docks)
	local guide = Instance.new("Folder"); guide.Name = "Guide"; guide.Parent = world
	local buoys = Instance.new("Folder"); buoys.Name = "Buoys"; buoys.Parent = world
	local R = 20
	local y = W.Level
	local tip = info.tip
	-- clockwise seen from above, starting at the pier end
	local ring = {
		Vector3.new(info.pierMax.X + R, y, info.pierEnd + R),
		Vector3.new(info.hx2 + R, y, info.hz2 + R),
		Vector3.new(info.hx2 + R, y, info.hz1 - R),
		-- round the bow's whole keep-out rectangle (the boat bounds treat the bow as its bounding box)
		Vector3.new(tip.X - R, y, info.hz1 - R),
		Vector3.new(tip.X - R, y, info.hz2 + R),
		Vector3.new(info.pierMin.X - R, y, info.hz2 + R),
		Vector3.new(info.pierMin.X - R, y, info.pierEnd + R),
	}
	-- densify: a point every ~40 studs so the nearest loop point to a dock is on that dock's side
	do
		local dense = {}
		for i = 1, #ring do
			local a, b = ring[i], ring[i % #ring + 1]
			local n = math.max(1, math.ceil((b - a).Magnitude / 40))
			for k = 0, n - 1 do table.insert(dense, a:Lerp(b, k / n)) end
		end
		ring = dense
	end
	local function nearestIndex(p)
		local best, bi = math.huge, 1
		for i, q in ipairs(ring) do
			local d = (Vector3.new(q.X, 0, q.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
			if d < best then best, bi = d, i end
		end
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
			local function plen(path) local s = 0; for k = 2, #path do s += (path[k] - path[k - 1]).Magnitude end; return s end
			local path = plen(fwd) <= plen(back) and fwd or back
			local pts = { home.Position }
			for _, q in ipairs(path) do table.insert(pts, q) end
			table.insert(pts, d.Position)
			for k, q in ipairs(pts) do
				local wp = part(guide, "R_" .. d.Name .. "_" .. k, Vector3.new(1, 1, 1), CFrame.new(q.X, W.Level, q.Z), C.teal)
				wp.Transparency = 1
			end
		end
	end
	local function buoy(p, kind, lit)
		local m = clone(kind == "red" and "CruiseBuoyRed" or "CruiseBuoyGreen", CFrame.new(p.X, W.Level, p.Z), buoys, 1, 1, 1)
		local host
		if m then
			host = m.PrimaryPart; m:AddTag("CruiseFloat")
			-- markers only: a solid buoy would pin the launch's bow (it cannot turn at zero speed)
			for _, q in ipairs(m:GetDescendants()) do
				if q:IsA("BasePart") then q.CanCollide, q.CanQuery, q.CanTouch = false, false, false end
			end
		else
			host = part(buoys, "Buoy", Vector3.new(3, 3, 3), CFrame.new(p.X, W.Level + 0.5, p.Z), kind == "red" and Color3.fromRGB(222, 218, 206) or (kind == "amber" and Color3.fromRGB(200, 140, 40) or Color3.fromRGB(40, 160, 70)), Enum.Material.SmoothPlastic)
			host.Shape = Enum.PartType.Ball
			host:AddTag("CruiseFloat")
		end
		if not lit then return end
		local l = Instance.new("PointLight"); l.Range = 12; l.Brightness = 1.5
		l.Color = kind == "red" and Color3.fromRGB(255, 236, 214) or Color3.fromRGB(80, 255, 120)
		l.Parent = host
	end
	-- channel buoys on the open-water side of the loop
	for i = 1, #ring do
		local a, b = ring[i], ring[i % #ring + 1]
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / 44))
		local outward = Vector3.new(-d.Z, 0, d.X).Unit -- clockwise loop: the left of travel is open water
		for k = 0, n - 1 do
			local p = a + d * ((k + 0.5) / n)
			buoy(p + outward * 11, (k % 2 == 0) and "green" or "red", true)
		end
	end
	-- sea limit: amber buoys along the boundary (unlit to save lights)
	local smin, smax = info.seaMin, info.seaMax
	local corners = { Vector3.new(smin.X, 0, smin.Z), Vector3.new(smax.X, 0, smin.Z), Vector3.new(smax.X, 0, smax.Z), Vector3.new(smin.X, 0, smax.Z) }
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / 50))
		for k = 0, n - 1 do buoy(a + d * (k / n), "amber", false) end
	end
	return guide
end

-- Background scenery: nearby tropical islands, a lit lighthouse and distant mountain ranges, scattered by the
-- map seed in angle slots around the ship (outside the sea bounds), so every cruise has its own skyline.
function M.Scenery(world, info, rng)
	local f = Instance.new("Folder"); f.Name = "Scenery"; f.Parent = world
	local cx = (info.tip.X + info.hx2) / 2
	local cz = (info.hz1 + info.hz2) / 2
	local base = W.Level - 2.5
	local slots = {}
	for i = 0, 11 do table.insert(slots, i / 12 * math.pi * 2) end
	for i = #slots, 2, -1 do local j = rng:NextInteger(1, i); slots[i], slots[j] = slots[j], slots[i] end
	local slot = 0
	local function place(name, dist, scale, yawJitter)
		slot += 1
		local a = slots[(slot - 1) % #slots + 1] + rng:NextNumber(-0.18, 0.18)
		local pos = Vector3.new(cx + math.cos(a) * dist, base, cz + math.sin(a) * dist)
		local cf = CFrame.new(pos) * CFrame.Angles(0, (yawJitter and rng:NextNumber(0, math.pi * 2)) or (-a - math.pi / 2), 0)
		local m = clone(name, cf, f, scale, scale, scale)
		if not m then return end
		for _, q in ipairs(m:GetDescendants()) do
			if q:IsA("BasePart") then q.Anchored = true; q.CanCollide = false; q.CanQuery = false; q.CanTouch = false; q.CastShadow = false end
		end
		return m
	end
	-- the far side of the scene: two mountain ranges facing the ship
	place("CruiseMountains", rng:NextNumber(820, 980), rng:NextNumber(1.3, 1.7))
	place("CruiseMountains", rng:NextNumber(860, 1040), rng:NextNumber(1.2, 1.6))
	-- big volcanic islands mid-distance
	place("CruiseIslandPeak", rng:NextNumber(470, 620), rng:NextNumber(0.9, 1.3), true)
	place("CruiseIslandPeak", rng:NextNumber(520, 700), rng:NextNumber(0.8, 1.2), true)
	-- small palm islands closer in
	for _ = 1, 3 do place("CruiseIslandPalm", rng:NextNumber(300, 460), rng:NextNumber(0.9, 1.5), true) end
	-- a lighthouse with a warm lamp and a slowly sweeping beam
	local lh = place("CruiseLighthouse", rng:NextNumber(330, 430), 1.2, true)
	local lamp = lh and lh:FindFirstChild("Lamp")
	if lamp then
		local glow = Instance.new("PointLight"); glow.Color = Color3.fromRGB(255, 220, 150); glow.Range = 60; glow.Brightness = 2; glow.Parent = lamp
		local beam = Instance.new("SpotLight"); beam.Color = Color3.fromRGB(255, 232, 170); beam.Range = 60; beam.Angle = 25; beam.Brightness = 6; beam.Face = Enum.NormalId.Front; beam.Parent = lamp
		lamp:SetAttribute("Sweep", true)
	end
	return f
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
	pcall(M.Scenery, world, info, Random.new((plan.seed or 1) + 9191))
	-- The ship's outside (hull plating, bow, stern, top deck, deckhouse, funnels, bridge) is solid, so nobody can
	-- walk or glitch into the hull or onto the roof. Lights, glows and thin trims stay non-colliding.
	for _, folderName in ipairs({ "Hull", "Deck" }) do
		local folder = world:FindFirstChild(folderName)
		if folder then
			for _, q in ipairs(folder:GetDescendants()) do
				if q:IsA("BasePart") and q.Material ~= Enum.Material.Neon and q.Transparency < 0.9
					and math.min(q.Size.X, q.Size.Y, q.Size.Z) >= 0.3 and math.max(q.Size.X, q.Size.Y, q.Size.Z) >= 2 then
					q.CanCollide = true
				end
			end
		end
	end
	info.seaMin = Vector3.new(info.tip.X - 70, 0, info.hz1 - 70)
	info.seaMax = Vector3.new(math.max(info.hx2, info.pierMax.X + 40) + 70, 0, math.max(info.pierEnd, info.hz2) + 60)
	-- No boat: the sea is scenery. Anyone who ends up in the water is lifted back onto the pier, and anyone who
	-- glitches up onto or into the ship above the top floor's roof is put back in the start room.
	local rescue = CFrame.new(info.ex, info.ey + 3.5, (info.pierMin.Z + info.pierMax.Z) / 2)
	local roofY = DECK - 1.1 -- top of the top floor's roof / wall tops (see M.Exterior)
	local shipMin = Vector3.new(info.tip.X - 4, 0, info.hz1 - 4)
	local shipMax = Vector3.new(info.hx2 + 4, 0, info.hz2 + 4)
	task.spawn(function()
		local Players = game:GetService("Players")
		while world.Parent do
			for _, p in ipairs(Players:GetPlayers()) do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local pos = root.Position
					local overShip = pos.X > shipMin.X and pos.X < shipMax.X and pos.Z > shipMin.Z and pos.Z < shipMax.Z
					if pos.Y < W.Level + 1 then
						p.Character:PivotTo(rescue)
						root.AssemblyLinearVelocity = Vector3.zero
					elseif overShip and pos.Y > roofY + 1.5 then
						local sp = mansion:GetAttribute("SpawnPosition")
						p.Character:PivotTo(sp and CFrame.new(sp + Vector3.new(0, 1, 0)) or rescue)
						root.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
			task.wait(0.25)
		end
	end)
	world:SetAttribute("WaterLevel", W.Level)
	world:SetAttribute("HullMin", Vector3.new(info.tip.X, 0, info.hz1 - 1))
	world:SetAttribute("HullMax", Vector3.new(info.hx2 + 1, 0, info.hz2 + 1))
	world:SetAttribute("SeaMin", info.seaMin)
	world:SetAttribute("SeaMax", info.seaMax)
	world:SetAttribute("PierMin", info.pierMin)
	world:SetAttribute("PierMax", info.pierMax)
	for k, v in pairs(stats) do mansion:SetAttribute("Cruise_" .. k, v) end
	mansion:SetAttribute("CruiseWorldVersion", 1)
end

return M
