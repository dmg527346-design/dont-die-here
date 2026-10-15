-- Diagonal walls across room and hall corners, so generated spaces read less boxy. Runs inside Builder after the
-- furniture and art and before validation (V.Built / V.Paths judge the result). A corner is cut only where both walls
-- meeting there are plain, solid wall for the cut length plus a margin (no door, portal, window or open bay) and no
-- object of any kind (furniture, art, closet, door, key, interactive) reaches into the cut. The cut uses the room's
-- own themed Wall template; the sealed triangle behind it is filled with an invisible solid wedge so nothing
-- (loot, clutter, monsters) can be placed or spawn where players cannot reach.
local R = require(script.Parent.Rules)
local U = require(script.Parent.KitUtil)
local M = {}
M.Debug = false -- true shows the sealed-corner wedges in red (audits and screenshots)
local FLOOR_H = 16
local HALF = 0.7 -- half the wall thickness: inner wall faces sit 0.7 inside each room boundary
local MARGIN = 2.5 -- extra solid wall required beyond the cut, keeps door approaches clear
local CLEAR = 1.0 -- free space required between the cut's face and any object

local function solidWall(mansion, origin, dir)
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { mansion.Architecture }
	local hit = workspace:Raycast(origin, dir * 3, rp)
	return hit ~= nil and hit.Instance.Parent ~= nil and hit.Instance.Parent.Name == "Wall" and hit.Distance > 0.6 and hit.Distance < 1.9
end

-- Both walls at corner (cx, cz) of room r, which opens toward +sx / +sz, must be solid for `len` studs.
local function wallsSolid(mansion, r, cx, cz, sx, sz, len)
	local y0 = (r.level or 0) * FLOOR_H
	for _, t in ipairs({ 0.9, len * 0.33, len * 0.66, len }) do
		for _, h in ipairs({ 2, 6.5, 11 }) do
			if not solidWall(mansion, Vector3.new(cx + sx * t, y0 + h, cz + sz * 2.0), Vector3.new(0, 0, -sz)) then return false end
			if not solidWall(mansion, Vector3.new(cx + sx * 2.0, y0 + h, cz + sz * t), Vector3.new(-sx, 0, 0)) then return false end
		end
	end
	return true
end

-- World-axis box of every part that could sit in a corner, gathered once per build. Bounds are taken from the
-- part's own CFrame and size, so parts that spatial queries skip (CanQuery=false art and dressing) still count.
local function obstacleBoxes(mansion)
	local boxes = {}
	for _, folder in ipairs({ mansion.Furniture, mansion.Interactive, mansion.Closets, mansion.KeyDoors }) do
		for _, p in ipairs(folder:GetDescendants()) do
			if p:IsA("BasePart") and p.Size.Magnitude > 0.05 then
				local cf, s = p.CFrame, p.Size / 2
				local ex = math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z
				local ey = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
				local ez = math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
				local c = cf.Position
				table.insert(boxes, { x1 = c.X - ex, x2 = c.X + ex, y1 = c.Y - ey, y2 = c.Y + ey, z1 = c.Z - ez, z2 = c.Z + ez })
			end
		end
	end
	return boxes
end

-- In corner coordinates u (along +sx) and v (along +sz) from the room corner, the cut removes u + v < c + 2*HALF.
-- An object blocks when the closest point of its box to the corner lies inside that triangle plus CLEAR.
local function cornerEmpty(boxes, r, cx, cz, sx, sz, c)
	local y0 = (r.level or 0) * FLOOR_H
	local limit = c + 2 * HALF + CLEAR
	for _, b in ipairs(boxes) do
		if b.y2 > y0 + 0.05 and b.y1 < y0 + 15 then
			local u1, u2 = if sx > 0 then b.x1 - cx else cx - b.x2, if sx > 0 then b.x2 - cx else cx - b.x1
			local v1, v2 = if sz > 0 then b.z1 - cz else cz - b.z2, if sz > 0 then b.z2 - cz else cz - b.z1
			if u2 > 0 and v2 > 0 and math.max(u1, 0) + math.max(v1, 0) < limit then return false end
		end
	end
	return true
end

-- Right-triangle wedge filling the sealed space between the cut and the corner.
local function fill(mansion, r, cx, cz, sx, sz, c)
	local y0 = (r.level or 0) * FLOOR_H
	local leg = c -- from the inner corner (u = v = HALF) this puts the slope exactly on the cut's face (u + v = c + 2*HALF)
	local up = Vector3.new(0, 1, 0)
	local yAxis, zAxis -- wedge local Y and Z; its right angle sits at local (-Y/2, +Z/2)
	if sx == sz then yAxis, zAxis = Vector3.new(sx, 0, 0), Vector3.new(0, 0, -sz)
	else yAxis, zAxis = Vector3.new(0, 0, sz), Vector3.new(-sx, 0, 0) end
	local vertex = Vector3.new(cx + sx * HALF, y0 + 7, cz + sz * HALF)
	local centre = vertex + yAxis * (leg / 2) - zAxis * (leg / 2)
	local w = Instance.new("WedgePart")
	w.Name = "AngledWall"; w.Size = Vector3.new(14, leg, leg)
	w.CFrame = CFrame.fromMatrix(centre, up, yAxis, zAxis)
	w.Anchored = true; w.CanCollide = true; w.CanQuery = true; w.CanTouch = false; w.CastShadow = false
	w.Transparency = if M.Debug then 0.4 else 1
	w.Color = Color3.fromRGB(255, 40, 40)
	w:SetAttribute("AngledCorner", r.name)
	w.Parent = mansion.Collision
	return w
end

local function build(mansion, kit, r, cx, cz, sx, sz, c)
	local y0 = (r.level or 0) * FLOOR_H
	-- ends on the two inner wall faces, the wall's face on the line between them, its back toward the corner
	local e1 = Vector3.new(cx + sx * (HALF + c), y0, cz + sz * HALF)
	local e2 = Vector3.new(cx + sx * HALF, y0, cz + sz * (HALF + c))
	local d = e2 - e1
	local mid = (e1 + e2) / 2 - Vector3.new(sx, 0, sz).Unit * HALF
	local length = d.Magnitude + 2 * HALF
	local cf = CFrame.new(mid) * CFrame.Angles(0, math.atan2(-d.Z, d.X), 0)
	local m = U.Clone(kit, "Wall", cf, mansion.Architecture, R.Themes[r.theme])
	U.Stretch(m, length / 4, 16 / 14, 1)
	m.Name = "Wall"; m:SetAttribute("AngledCorner", r.name)
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and p ~= m.PrimaryPart then
			p:SetAttribute("AngledCorner", true)
			if p.Name == "Wallpaper" then
				local col = p:Clone(); col.Name = "AngledWall"; col.Transparency = 1; col.CanQuery = true; col.CanCollide = true
				for _, x in ipairs(col:GetChildren()) do x:Destroy() end
				col.Parent = mansion.Collision
			end
			p.CanCollide = false
		end
	end
	fill(mansion, r, cx, cz, sx, sz, c)
	return m
end

function M.Apply(plan, mansion, kit)
	if plan.mapKind == "Cruise" then
		-- Publish empty data so a persistent map that was cut before never keeps stale corners.
		mansion:SetAttribute("AngledCorners", 0); mansion:SetAttribute("AngledCornerData", "[]")
		plan.angledCorners = {}
		return 0
	end
	local rng = Random.new((plan.seed or 1) + 5113)
	local boxes = obstacleBoxes(mansion)
	local n = 0
	plan.angledCorners = {}
	for _, r in ipairs(plan.rooms or {}) do
		if r.type == "Stair" or not (r.x1 and r.x2 and r.z1 and r.z2) then continue end
		local w, d = r.x2 - r.x1, r.z2 - r.z1
		if math.min(w, d) < 14 then continue end
		local hall = r.type == "Hall"
		local chance = hall and 0.85 or 0.75
		for _, corner in ipairs({ { r.x1, r.z1, 1, 1 }, { r.x2, r.z1, -1, 1 }, { r.x1, r.z2, 1, -1 }, { r.x2, r.z2, -1, -1 } }) do
			if rng:NextNumber() > chance then continue end
			local c = if hall then 4 else math.clamp(math.floor(math.min(w, d) * 0.2), 4, 8)
			local cx, cz, sx, sz = corner[1], corner[2], corner[3], corner[4]
			if wallsSolid(mansion, r, cx, cz, sx, sz, c + MARGIN) and cornerEmpty(boxes, r, cx, cz, sx, sz, c) then
				build(mansion, kit, r, cx, cz, sx, sz, c)
				table.insert(plan.angledCorners, { room = r.name, x = cx, z = cz, sx = sx, sz = sz, c = c, level = r.level or 0 })
				n += 1
			end
		end
	end
	mansion:SetAttribute("AngledCorners", n)
	-- Published on the map (copied onto workspace.Mansion with the other build attributes) so placement code in
	-- other scripts can ask M.Blocked / M.FootprintBlocked without the plan.
	local list = {}
	for _, a in ipairs(plan.angledCorners) do table.insert(list, { a.x, a.z, a.sx, a.sz, a.c, a.level }) end
	mansion:SetAttribute("AngledCornerData", game:GetService("HttpService"):JSONEncode(list))
	return n
end

-- Corner list from a built map, decoded once per attribute value.
local cache = setmetatable({}, { __mode = "k" })
function M.List(mansion)
	local raw = mansion and mansion:GetAttribute("AngledCornerData")
	if not raw then return {} end
	local hit = cache[mansion]
	if hit and hit.raw == raw then return hit.list end
	local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
	local list = {}
	if ok then for _, a in ipairs(data) do table.insert(list, { x = a[1], z = a[2], sx = a[3], sz = a[4], c = a[5], level = a[6] }) end end
	cache[mansion] = { raw = raw, list = list }
	return list
end

-- True when world point p lies in the sealed space behind a cut, or within `pad` studs in front of its face.
-- Accepts a plan (has angledCorners) or a built map model.
function M.Blocked(source, p, pad)
	pad = pad or 0
	local list = if typeof(source) == "Instance" then M.List(source) else (source and source.angledCorners or {})
	for _, a in ipairs(list) do
		if p.Y > a.level * FLOOR_H - 1 and p.Y < a.level * FLOOR_H + 15 then
			local u, v = a.sx * (p.X - a.x), a.sz * (p.Z - a.z)
			if u > -pad and v > -pad and u + v < a.c + 2 * HALF + pad * 1.4143 then return true end
		end
	end
	return false
end
M.Inside = function(plan, p) return M.Blocked(plan, p, 0) end

-- True when any corner or the centre of a footprint (CFrame at its centre, size X/Z) is blocked.
function M.FootprintBlocked(source, cf, size, pad)
	local hx, hz = size.X / 2, size.Z / 2
	for _, o in ipairs({ { 0, 0 }, { hx, hz }, { -hx, hz }, { hx, -hz }, { -hx, -hz } }) do
		if M.Blocked(source, cf:PointToWorldSpace(Vector3.new(o[1], 0, o[2])), pad) then return true end
	end
	return false
end

-- Move a point that falls behind a cut out onto the room side of its face, `pad` studs clear.
function M.Clear(source, p, pad)
	pad = pad or 2
	local list = if typeof(source) == "Instance" then M.List(source) else (source and source.angledCorners or {})
	for _, a in ipairs(list) do
		if p.Y > a.level * FLOOR_H - 1 and p.Y < a.level * FLOOR_H + 15 then
			local u, v = a.sx * (p.X - a.x), a.sz * (p.Z - a.z)
			local need = a.c + 2 * HALF + pad * 1.4143
			if u > -pad and v > -pad and u + v < need then
				local push = (need - (u + v)) / 2
				p = Vector3.new(p.X + a.sx * push, p.Y, p.Z + a.sz * push)
			end
		end
	end
	return p
end

return M
