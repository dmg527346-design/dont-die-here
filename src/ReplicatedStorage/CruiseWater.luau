-- Shared sea surface for the Cruise map. Server (boat buoyancy, fall-in checks) and every client
-- (wave mesh, boat bob, wake) evaluate the SAME deterministic function on server time, so the
-- boat always sits on the waves the players see.
local W = {}

W.Level = -8 -- mean sea level (studs). Ship deck L0 is y=0, the pier deck top is y=0.
W.MaxAmplitude = 1.95 -- sum of the wave amplitudes below

-- Gentle night swell: long rollers plus two short chop layers.
-- { amplitude, wavelength, direction x, direction z, speed (studs/s), phase }
local WAVES = {
	{ 0.90, 92, 1.00, 0.30, 8.0, 0.0 },
	{ 0.55, 47, -0.40, 1.00, 6.0, 1.7 },
	{ 0.32, 23, 0.80, -0.60, 4.4, 4.1 },
	{ 0.18, 11, -1.00, -0.25, 3.1, 2.6 },
}
local PRE = {}
for i, w in ipairs(WAVES) do
	local len = math.sqrt(w[3] * w[3] + w[4] * w[4])
	local k = 2 * math.pi / w[2]
	PRE[i] = { a = w[1], kx = k * w[3] / len, kz = k * w[4] / len, om = k * w[5], ph = w[6] }
end

-- Read-only wave constants for renderers that evaluate the sum in bulk (same function as W.Height).
function W.Params()
	local out = {}
	for i, p in ipairs(PRE) do out[i] = { a = p.a, kx = p.kx, kz = p.kz, om = p.om, ph = p.ph } end
	return out
end

function W.Time()
	return workspace:GetServerTimeNow()
end

-- Surface height at (x, z) and time t (server time; defaults to now).
function W.Height(x, z, t)
	t = t or workspace:GetServerTimeNow()
	local h = W.Level
	for i = 1, #PRE do
		local p = PRE[i]
		h += p.a * math.sin(p.kx * x + p.kz * z - p.om * t + p.ph)
	end
	return h
end

-- Height plus the slope (dh/dx, dh/dz), for normals and boat pitch/roll.
function W.Sample(x, z, t)
	t = t or workspace:GetServerTimeNow()
	local h, dx, dz = W.Level, 0, 0
	for i = 1, #PRE do
		local p = PRE[i]
		local arg = p.kx * x + p.kz * z - p.om * t + p.ph
		local s, c = math.sin(arg), math.cos(arg)
		h += p.a * s
		dx += p.a * p.kx * c
		dz += p.a * p.kz * c
	end
	return h, dx, dz
end

function W.Normal(x, z, t)
	local _, dx, dz = W.Sample(x, z, t)
	return Vector3.new(-dx, 1, -dz).Unit
end

-- A CFrame sitting on the water at (x, z) with the given heading (yaw), tilted to the swell over a
-- hull of the given length/width (samples bow/stern/sides so short chop does not jitter the boat).
function W.Float(x, z, yaw, length, width, t)
	t = t or workspace:GetServerTimeNow()
	local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local hl, hw = (length or 16) / 2, (width or 7) / 2
	local hb = W.Height(x + fwd.X * hl, z + fwd.Z * hl, t)
	local hs = W.Height(x - fwd.X * hl, z - fwd.Z * hl, t)
	local hr = W.Height(x + right.X * hw, z + right.Z * hw, t)
	local hp = W.Height(x - right.X * hw, z - right.Z * hw, t)
	local y = (hb + hs + hr + hp) / 4
	local pitch = math.atan2(hb - hs, hl * 2)
	local roll = math.atan2(hr - hp, hw * 2) -- +roll raises the starboard (+X) side
	return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
end

return W
