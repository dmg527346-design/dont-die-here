-- Cruise map sea: a custom animated wave surface (EditableMesh) that follows the camera, a far
-- horizon plane, bioluminescent plankton sparkles, and glowing wakes behind boats.
-- Heights come from ReplicatedStorage.CruiseWater, the same function the boat floats on.
-- Live servers (owner 2026-10-27): Cruise is out of the map pool, so the sea stays off there (MapGen publishes the pool
-- as the ReplicatedStorage attribute MapPool). Studio keeps it for forced-map tests; no pool after 15 s = run as before.
do local RS_=game:GetService('ReplicatedStorage');local pool,t0=RS_:GetAttribute('MapPool'),os.clock();if not game:GetService('RunService'):IsStudio()then while pool==nil and os.clock()-t0<15 do task.wait(.5);pool=RS_:GetAttribute('MapPool')end;if pool and not table.find(string.split(pool,','),'Cruise')then return end end end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local W = require(ReplicatedStorage:WaitForChild("CruiseWater"))
local player = Players.LocalPlayer

-- Phones and tablets get a quarter of the vertices (same 320-stud area) updated half as often: the full mesh ran
-- out of their EditableMesh memory budget and cost a large share of the frame.
local UIS = game:GetService("UserInputService")
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local LIGHT = InputHints.IsMobile()
local N = LIGHT and 32 or 64 -- grid cells per side
local S = LIGHT and 10 or 5 -- studs per cell (320 x 320 studs of moving sea around the camera)
local HALF = N * S / 2
local EDGE = LIGHT and 5 or 10 -- cells over which the waves fade flat into the horizon plane
local FAR_Y = W.Level - 3.2 -- the wave mesh edge slopes down into the horizon plane
local DEEP = Color3.fromRGB(18, 62, 86)
local CREST = Color3.fromRGB(58, 140, 160)
local GLOW = Color3.fromRGB(110, 255, 232)
local HORIZON = Color3.fromRGB(8, 26, 40)
local BED = Color3.fromRGB(10, 84, 92) -- glow bed centre
local BED_EDGE = Color3.fromRGB(6, 22, 32) -- outermost ring, close to the dark horizon
local BED_RINGS = 10
local UPDATE_HZ = LIGHT and 15 or 30 -- whole-mesh updates on alternate frames: half the mesh uploads of a per-frame update
local FQ, LQ = 10, 40 -- colour palette steps: edge fade x crest lift

local active, sea
local function mapIsCruise()
	local m = workspace:FindFirstChild("Mansion")
	return m and m:GetAttribute("MapKind") == "Cruise" and m:GetAttribute("Ready") == true
end

-- The wave surface is optional: when the device has no EditableMesh budget left, CreateEditableMesh returns nil
-- and the sea is the flat horizon, glow bed and plankton only.
local function buildWaves(folder)
	local em = AssetService:CreateEditableMesh()
	if not em then return nil end
	local ids, colors = {}, {}
	for i = 0, N do
		ids[i], colors[i] = {}, {}
		for j = 0, N do
			local y = 0
			if i == 0 and j == 0 then y = -3 elseif i == N and j == N then y = 3 end -- symmetric bounds
			ids[i][j] = em:AddVertex(Vector3.new(i * S - HALF, y, j * S - HALF))
		end
	end
	local faces = {}
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			table.insert(faces, em:AddTriangle(ids[i][j], ids[i][j + 1], ids[i + 1][j]))
			table.insert(faces, em:AddTriangle(ids[i + 1][j], ids[i][j + 1], ids[i + 1][j + 1]))
		end
	end
	-- One colour per vertex; faces reference the vertex colours so shading follows the crests.
	local colorIds = {}
	for i = 0, N do
		colorIds[i] = {}
		for j = 0, N do
			colorIds[i][j] = em:AddColor(DEEP, 1)
		end
	end
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			local f1 = faces[(i * N + j) * 2 + 1]
			local f2 = faces[(i * N + j) * 2 + 2]
			em:SetFaceColors(f1, { colorIds[i][j], colorIds[i][j + 1], colorIds[i + 1][j] })
			em:SetFaceColors(f2, { colorIds[i + 1][j], colorIds[i][j + 1], colorIds[i + 1][j + 1] })
		end
	end

	local mesh = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	mesh.Name = "WaveSurface"
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = false
	mesh.Material = Enum.Material.Glass
	mesh.Color = Color3.new(1, 1, 1)
	mesh.Transparency = 0.32
	mesh.Reflectance = 0.12
	mesh.Parent = folder
	return em, mesh, ids, colorIds
end

local function build(folder)
	local okWaves, em, mesh, ids, colorIds = pcall(buildWaves, folder)
	if not okWaves then em, mesh = nil, nil end

	local far = Instance.new("Part")
	far.Name = "HorizonSea"
	far.Anchored, far.CanCollide, far.CanQuery, far.CanTouch, far.CastShadow = true, false, false, false, false
	far.Size = Vector3.new(4096, 0.2, 4096)
	far.Material = Enum.Material.SmoothPlastic
	far.Color = HORIZON
	far.Reflectance = 0.08
	far.Parent = folder

	-- Bioluminescent bed: a teal glow under the translucent waves, so the sea glows from below. Stacked
	-- opaque neon discs shading out to near black (Glass hides transparent things behind it, so a
	-- gradient image cannot be used): the glow fades in rings instead of ending in a hard square edge.
	local bed = {}
	for k = 0, BED_RINGS - 1 do
		local f = k / (BED_RINGS - 1)
		local disc = Instance.new("Part")
		disc.Name = "GlowBed" .. k
		disc.Shape = Enum.PartType.Cylinder
		disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.CastShadow = true, false, false, false, false
		local d = N * S * (0.62 + 0.37 * f) -- full glow out to ~100 studs, gone by ~158
		disc.Size = Vector3.new(0.2, d, d)
		disc.Material = Enum.Material.Neon
		disc.Color = BED:Lerp(BED_EDGE, f ^ 1.2)
		disc.Parent = folder
		bed[k + 1] = { part = disc, y = W.Level - 2.6 - k * 0.05 }
	end

	-- Bioluminescent plankton: short-lived teal specks scattered over the sea around the camera.
	local sparkHost = Instance.new("Part")
	sparkHost.Name = "PlanktonField"
	sparkHost.Anchored, sparkHost.CanCollide, sparkHost.CanQuery, sparkHost.CanTouch, sparkHost.CastShadow = true, false, false, false, false
	sparkHost.Transparency = 1
	sparkHost.Size = Vector3.new(220, 0.2, 220)
	sparkHost.Parent = folder
	local spark = Instance.new("ParticleEmitter")
	spark.Name = "Plankton"
	spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spark.Color = ColorSequence.new(Color3.fromRGB(80, 255, 230), Color3.fromRGB(40, 170, 255))
	spark.LightEmission = 1
	spark.LightInfluence = 0
	spark.Brightness = 2.2
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, 0.32), NumberSequenceKeypoint.new(1, 0) })
	spark.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spark.Lifetime = NumberRange.new(1.2, 3.2)
	spark.Rate = 260
	spark.Speed = NumberRange.new(0)
	spark.Shape = Enum.ParticleEmitterShape.Box
	spark.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	spark.Orientation = Enum.ParticleOrientation.FacingCamera
	spark.Parent = sparkHost

	-- Flat per-vertex tables for the update loop: vertex id, colour id, local offset, edge fade.
	local vid, cid, fade, fq, last = {}, {}, {}, {}, {}
	for i = 0, em and N or -1 do
		local ei = math.min(i, N - i)
		for j = 0, N do
			local v = i * (N + 1) + j + 1
			vid[v], cid[v] = ids[i][j], colorIds[i][j]
			local edge = math.min(ei, math.min(j, N - j)) / EDGE
			local f = edge >= 1 and 1 or edge * edge * (3 - 2 * edge)
			fade[v], fq[v], last[v] = f, math.floor(f * FQ + 0.5), -1
		end
	end
	return { folder = folder, em = em, mesh = mesh, far = far, bed = bed, spark = sparkHost, wakes = {},
		vid = vid, cid = cid, fade = fade, fq = fq, last = last, snapX = nil, snapZ = nil, ringDone = false }
end

-- Colour palette: crests lift toward a lighter teal, the very tops catch a bioluminescent glow;
-- the edge fade blends back to deep water. Quantized so a vertex colour is only rewritten when its band changes.
local PAL = {}
do
	local function lerpColor(a, b, t) return a:Lerp(b, math.clamp(t, 0, 1)) end
	for f = 0, FQ do
		PAL[f] = {}
		for l = 0, LQ do
			local lift = l / LQ * 2 - 1
			local c = lerpColor(DEEP, CREST, (lift + 0.6) * 0.75)
			if lift > 0.62 then c = lerpColor(c, GLOW, (lift - 0.62) * 1.6) end
			PAL[f][l] = lerpColor(DEEP, c, f / FQ)
		end
	end
end

local WAVE = W.Params()
local OFF = {}
for i = 0, N do OFF[i] = i * S - HALF end
-- Per-row and per-column wave terms: sin(kx*x + kz*z - om*t + ph) = sinA*cosB + cosA*sinB with
-- A = kx*x - om*t + ph (row) and B = kz*z (column), so the trig is O(N) per wave instead of O(N^2).
local sA, cA, sB, cB = {}, {}, {}, {}
for w = 1, #WAVE do sA[w], cA[w], sB[w], cB[w] = {}, {}, {}, {} end

local seaCost, seaFrames = 0, 0
local function updateSea()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local clock = os.clock()
	local cp = cam.CFrame.Position
	local cx = math.floor(cp.X / S + 0.5) * S
	local cz = math.floor(cp.Z / S + 0.5) * S
	sea.spark.CFrame = CFrame.new(cp.X, W.Level + 0.35, cp.Z)
	local full = cx ~= sea.snapX or cz ~= sea.snapZ or not sea.ringDone
	if full then
		sea.snapX, sea.snapZ = cx, cz
		if sea.mesh then sea.mesh.CFrame = CFrame.new(cx, 0, cz) end
		sea.far.CFrame = CFrame.new(cx, FAR_Y - 0.1, cz)
		for _, ring in ipairs(sea.bed) do ring.part.CFrame = CFrame.new(cx, ring.y, cz) * CFrame.Angles(0, 0, math.pi / 2) end
	end
	if not sea.em then sea.ringDone = true return end
	local first, step = 0, 1
	local t = W.Time()
	for w = 1, #WAVE do
		local p = WAVE[w]
		local rs, rc, cs, cc = sA[w], cA[w], sB[w], cB[w]
		local base = p.ph - p.om * t
		for i = first, N, step do
			local a = p.kx * (cx + OFF[i]) + base
			rs[i], rc[i] = math.sin(a), math.cos(a)
		end
		if full or not cs[0] then -- column terms only depend on the snap position
			for j = 0, N do
				local b = p.kz * (cz + OFF[j])
				cs[j], cc[j] = math.sin(b), math.cos(b)
			end
		end
	end
	local a1, a2, a3, a4 = WAVE[1].a, WAVE[2].a, WAVE[3].a, WAVE[4].a
	local s1, c1, s2, c2, s3, c3, s4, c4 = sA[1], cA[1], sA[2], cA[2], sA[3], cA[3], sA[4], cA[4]
	local S1, C1, S2, C2, S3, C3, S4, C4 = sB[1], cB[1], sB[2], cB[2], sB[3], cB[3], sB[4], cB[4]
	local em, vid, cid, fade, fq, last = sea.em, sea.vid, sea.cid, sea.fade, sea.fq, sea.last
	local level, inv = W.Level, 1 / W.MaxAmplitude
	local ring = not sea.ringDone
	for i = first, N, step do
		local ox = OFF[i]
		local r1, q1, r2, q2, r3, q3, r4, q4 = s1[i], c1[i], s2[i], c2[i], s3[i], c3[i], s4[i], c4[i]
		local row = i * (N + 1)
		for j = 0, N do
			local v = row + j + 1
			local f = fade[v]
			if f > 0 or ring then
				local h = level + a1 * (r1 * C1[j] + q1 * S1[j]) + a2 * (r2 * C2[j] + q2 * S2[j])
					+ a3 * (r3 * C3[j] + q3 * S3[j]) + a4 * (r4 * C4[j] + q4 * S4[j])
				em:SetPosition(vid[v], Vector3.new(ox, FAR_Y + (h - FAR_Y) * f, OFF[j]))
				local l = math.floor(((h - level) * inv + 1) * 0.5 * LQ + 0.5)
				l = l < 0 and 0 or (l > LQ and LQ or l)
				local key = fq[v] * 1000 + l
				if key ~= last[v] then
					last[v] = key
					em:SetColor(cid[v], PAL[fq[v]][l])
				end
			end
		end
	end
	sea.ringDone = true
	seaCost += os.clock() - clock
	seaFrames += 1
	if seaFrames >= 120 then
		script:SetAttribute("SeaMs", math.floor(seaCost / seaFrames * 10000 + 0.5) / 10)
		seaCost, seaFrames = 0, 0
	end
end

-- Glowing wakes: any boat model tagged 'CruiseBoat' gets a teal trail + churn at the stern when moving.
local CollectionService = game:GetService("CollectionService")
local function boatParts()
	local list = {}
	for _, m in ipairs(CollectionService:GetTagged("CruiseBoat")) do
		if m:IsA("Model") and m.PrimaryPart and m:IsDescendantOf(workspace) then table.insert(list, m) end
	end
	return list
end

local function ensureWake(boat)
	local w = sea.wakes[boat]
	if w and w.root.Parent then return w end
	local root = boat.PrimaryPart
	local len = boat:GetAttribute("Length") or 18
	local wid = boat:GetAttribute("Width") or 7.5
	local a0 = Instance.new("Attachment")
	a0.Name = "WakeL"
	a0.Position = Vector3.new(-wid * 0.42, -1.2, len * 0.46)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "WakeR"
	a1.Position = Vector3.new(wid * 0.42, -1.2, len * 0.46)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 2.6
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = false
	trail.Color = ColorSequence.new(Color3.fromRGB(110, 255, 235), Color3.fromRGB(30, 120, 200))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.6) })
	trail.Parent = root
	local churn = Instance.new("ParticleEmitter")
	churn.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	churn.Color = ColorSequence.new(Color3.fromRGB(120, 255, 240))
	churn.LightEmission, churn.LightInfluence, churn.Brightness = 1, 0, 3
	churn.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	churn.Lifetime = NumberRange.new(0.6, 1.4)
	churn.Speed = NumberRange.new(2, 6)
	churn.SpreadAngle = Vector2.new(35, 35)
	churn.Rate = 0
	local ca = Instance.new("Attachment")
	ca.Name = "Churn"
	ca.Position = Vector3.new(0, -1.3, len * 0.5)
	ca.Parent = root
	churn.Parent = ca
	w = { root = root, trail = trail, churn = churn, last = root.Position }
	sea.wakes[boat] = w
	return w
end

local wakeScan = 0
local function updateWakes(dt)
	wakeScan += dt
	if wakeScan > 1 then
		wakeScan = 0
		for boat, w in pairs(sea.wakes) do if not boat.Parent then sea.wakes[boat] = nil end end
		for _, boat in ipairs(boatParts()) do ensureWake(boat) end
	end
	for boat, w in pairs(sea.wakes) do
		if w.root.Parent then
			local p = w.root.Position
			local speed = (Vector3.new(p.X, 0, p.Z) - Vector3.new(w.last.X, 0, w.last.Z)).Magnitude / math.max(dt, 1 / 240)
			w.last = p
			w.trail.Enabled = speed > 1.5
			w.churn.Rate = math.clamp(speed * 6, 0, 160)
		end
	end
end

-- Buoys, beacons and moor rings tagged 'CruiseFloat' bob on the swell (client-side only).
local floats = {}
local floatAcc = 0
local floatCost, floatFrames = 0, 0
local floatScan, floatList = 0, {}
local function updateFloats(dt)
	floatAcc += dt
	if floatAcc < 1 / 20 then return end
	floatAcc = 0
	local clock = os.clock()
	local t = W.Time()
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero
	floatScan -= 1
	if floatScan <= 0 then floatScan, floatList = 40, CollectionService:GetTagged("CruiseFloat") end
	for _, inst in ipairs(floatList) do
		if inst:IsDescendantOf(workspace) then
			local f = floats[inst]
			if not f then
				local cf = inst:IsA("Model") and inst:GetPivot() or inst.CFrame
				f = { base = cf, phase = (cf.Position.X * 0.37 + cf.Position.Z * 0.21) % 6.28 }
				floats[inst] = f
			end
			local p = f.base.Position
			if (p - cp).Magnitude < 300 then
				local h, dx, dz = W.Sample(p.X, p.Z, t)
				local tilt = CFrame.Angles(math.clamp(dz * 0.6, -0.25, 0.25), 0, math.clamp(-dx * 0.6, -0.25, 0.25))
				local cf = CFrame.new(p.X, p.Y + (h - W.Level), p.Z) * tilt * f.base.Rotation
				if inst:IsA("Model") then inst:PivotTo(cf) else inst.CFrame = cf end
			end
		end
	end
	for inst in pairs(floats) do if not inst.Parent then floats[inst] = nil end end
	floatCost += os.clock() - clock
	floatFrames += 1
	if floatFrames >= 60 then
		script:SetAttribute("FloatMs", math.floor(floatCost / floatFrames * 10000 + 0.5) / 10)
		floatCost, floatFrames = 0, 0
	end
end

-- Lighthouse: the lamp's spotlight and a faint light cone sweep around slowly (client-side only).
local sweeps, sweepScan = {}, 0
local function updateSweeps(dt)
	sweepScan -= dt
	if sweepScan <= 0 then
		sweepScan = 2
		local map = workspace:FindFirstChild("Mansion")
		local scenery = map and map:FindFirstChild("CruiseWorld") and map.CruiseWorld:FindFirstChild("Scenery")
		if scenery then
			for _, d in ipairs(scenery:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("Sweep") and not sweeps[d] then
					local cone = Instance.new("Part")
					cone.Name = "LighthouseBeam"
					cone.Anchored, cone.CanCollide, cone.CanQuery, cone.CanTouch, cone.CastShadow = true, false, false, false, false
					cone.Material = Enum.Material.Neon
					cone.Color = Color3.fromRGB(255, 236, 180)
					cone.Transparency = 0.86
					cone.Size = Vector3.new(4, 4, 140)
					cone.Parent = sea and sea.folder or workspace
					sweeps[d] = { base = d.CFrame, cone = cone, angle = math.random() * math.pi * 2 }
				end
			end
		end
		for d, sw in pairs(sweeps) do if not d.Parent then sw.cone:Destroy(); sweeps[d] = nil end end
	end
	for d, sw in pairs(sweeps) do
		sw.angle += dt * 0.55
		local cf = CFrame.new(sw.base.Position) * CFrame.Angles(0, sw.angle, 0)
		d.CFrame = cf * (sw.base - sw.base.Position)
		sw.cone.CFrame = cf * CFrame.Angles(math.rad(-4), 0, 0) * CFrame.new(0, 0, -72)
	end
end

local acc = 0
local building = false
local retryAt = 0
RunService.RenderStepped:Connect(function(dt)
	local want = mapIsCruise()
	if want and not active and not building and os.clock() >= retryAt then
		building = true
		task.spawn(function() -- CreateMeshPartAsync yields: build once, off the render step
			local folder = Instance.new("Folder")
			folder.Name = "CruiseSeaClient"
			folder.Parent = workspace
			local ok, built = pcall(build, folder)
			building = false
			-- A failed build must not retry every frame (it did, tens of thousands of times on phones) or leave parts behind.
			if not ok then folder:Destroy();retryAt = os.clock() + 30;warn("[CruiseWater] " .. tostring(built)) return end
			if mapIsCruise() then sea, active = built, true else built.folder:Destroy() end
		end)
	elseif not want and active then
		active = false
		if sea and sea.folder then sea.folder:Destroy() end
		sea = nil
	end
	if not active then return end
	acc += dt
	if acc >= 1 / UPDATE_HZ then
		updateSea()
		acc = 0
	end
	updateWakes(dt)
	updateFloats(dt)
	updateSweeps(dt)
end)
