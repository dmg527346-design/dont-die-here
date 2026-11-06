-- AnyRig: play rig-free clips on any two-legged Roblox character, fingers included.
-- Works on part rigs (Motor6D), current Roblox avatars (AnimationConstraint) and skinned meshes (Bone), with any joint names it can recognise, any joint
-- orientation, any rest pose (T, A, arms down), any proportions. Joints it does not recognise are left alone;
-- parts a character does not have (elbows, hands, fingers) are skipped.
--
--   local rig = AnyRig.analyse(model)          -- once, while the model is in its rest pose
--   AnyRig.apply(rig, clip, frame)             -- set every joint's Transform for one frame (frame counts from 1)
--   local ks = AnyRig.keyframes(rig, clip)     -- or build a KeyframeSequence for this model (Studio: preview / publish)
--
-- A clip is { fps, frames, loop, hips = {x,y,z, ...}, turn = { Role = {qx,qy,qz,qw, ...} } } in Roblox axes:
-- how far each body part has turned from a palms-down T-pose, in the character's own space, per frame.
local AnyRig = {}

local SIDES, FINGERS = { "Left", "Right" }, { "Thumb", "Index", "Middle", "Ring", "Pinky" }
local ROLES, CHILD, FOLLOW, TPOSE, IS_FINGER = { "LowerTorso", "UpperTorso", "Head" }, {}, {}, {}, {}
for _, s in SIDES do
	local sx = s == "Left" and 1 or -1   -- a character facing -Z has its left at -X
	for _, p in { "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" } do
		table.insert(ROLES, s .. p)
	end
	CHILD[s .. "UpperArm"], CHILD[s .. "LowerArm"], CHILD[s .. "UpperLeg"], CHILD[s .. "LowerLeg"] = s .. "LowerArm", s .. "Hand", s .. "LowerLeg", s .. "Foot"
	FOLLOW[s .. "Hand"], FOLLOW[s .. "LowerArm"], FOLLOW[s .. "Foot"], FOLLOW[s .. "LowerLeg"] = s .. "LowerArm", s .. "UpperArm", s .. "LowerLeg", s .. "UpperLeg"
	TPOSE[s .. "UpperArm"], TPOSE[s .. "LowerArm"] = Vector3.new(-sx, 0, 0), Vector3.new(-sx, 0, 0)
	TPOSE[s .. "UpperLeg"], TPOSE[s .. "LowerLeg"] = Vector3.new(0, -1, 0), Vector3.new(0, -1, 0)
	for _, f in FINGERS do
		for n = 1, 3 do
			local r = s .. f .. n
			table.insert(ROLES, r)
			IS_FINGER[r] = true
			TPOSE[r] = if f == "Thumb" then Vector3.new(-0.70 * sx, -0.14, -0.70) else Vector3.new(-sx, 0, 0)
			if n < 3 then
				CHILD[r] = s .. f .. (n + 1)
			end
			FOLLOW[r] = if n > 1 then s .. f .. (n - 1) else s .. "Hand"
		end
	end
end
local PALM_DOWN, REF_LEG = Vector3.new(0, -1, 0), 1.9
AnyRig.Roles, AnyRig.Child = ROLES, CHILD

-- ---------------------------------------------------------------- names

local function classify(name)
	local n = string.lower((string.gsub((string.gsub((string.gsub(name, "^.*:", "")), "(%l)(%u)", "%1 %2")), "(%d)(%u)", "%1 %2")))
	local t = {}
	for w in string.gmatch(n, "%w+") do
		table.insert(t, w)
	end
	local side
	for i, w in t do
		if w == "left" or w == "right" then
			side = w == "left" and "Left" or "Right"
			table.remove(t, i)
			break
		end
	end
	if not side and #t > 1 then
		for _, i in { 1, #t } do
			if t[i] == "l" or t[i] == "r" then
				side = t[i] == "l" and "Left" or "Right"
				table.remove(t, i)
				break
			end
		end
	end
	return side, table.concat(t)
end

-- role -> joint name, from the names alone: R15, R6, Mixamo, Blender (.L/.R), Unreal (_l/_r) and their fingers
function AnyRig.map(names)
	local info, mp, used = {}, {}, {}
	for _, nm in names do
		local s, b = classify(nm)
		table.insert(info, { nm, s, b })
	end
	local function pick(role, side, bases)
		for _, base in bases do
			for _, it in info do
				if it[2] == side and it[3] == base and not used[it[1]] then
					mp[role], used[it[1]] = it[1], true
					return true
				end
			end
		end
		return false
	end
	for _, side in SIDES do
		pick(side .. "UpperArm", side, { "upperarm", "uparm", "arm", "bicep" })
		pick(side .. "LowerArm", side, { "lowerarm", "forearm" })
		pick(side .. "Hand", side, { "hand" })
		local up = pick(side .. "UpperLeg", side, { "upperleg", "upleg", "thigh" })
		pick(side .. "LowerLeg", side, if up then { "lowerleg", "shin", "calf", "leg" } else { "lowerleg", "shin", "calf" })
		if not up then
			pick(side .. "UpperLeg", side, { "leg" })
		end
		pick(side .. "Foot", side, { "foot" })
		local chains = {}
		for _, it in info do
			if it[2] == side then
				for _, word in { "thumb", "index", "middle", "ring", "pinky", "little" } do
					local pre, num = string.match(it[3], "^(%a*)" .. word .. "0*(%d)$")
					if num and (pre == "" or pre == "hand" or pre == "f" or pre == "finger") then
						local f = if word == "little" then "Pinky" else string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
						chains[f] = chains[f] or {}
						table.insert(chains[f], { tonumber(num), it[1] })
					end
				end
			end
		end
		for f, list in chains do   -- the first three joints, whatever number the rig starts counting from
			table.sort(list, function(a, b)
				return a[1] < b[1]
			end)
			for n = 1, math.min(3, #list) do
				mp[side .. f .. n], used[list[n][2]] = list[n][2], true
			end
		end
	end
	pick("Head", nil, { "head" })
	pick("LowerTorso", nil, { "lowertorso", "hips", "hip", "pelvis" })
	if not pick("UpperTorso", nil, { "uppertorso", "upperchest", "chest" }) then
		local best, bestN
		for _, it in info do
			local num = it[2] == nil and string.match(it[3], "^spine0*(%d*)$")
			if num and (not bestN or (tonumber(num) or 0) > bestN) then
				best, bestN = it[1], tonumber(num) or 0
			end
		end
		if best then
			mp.UpperTorso, used[best] = best, true
		end
	end
	for _, it in info do   -- a rig with one torso piece: it plays the hips, so the legs and the bob hang off it
		if it[2] == nil and it[3] == "torso" and not used[it[1]] then
			if not mp.LowerTorso then
				mp.LowerTorso = it[1]
			elseif not mp.UpperTorso then
				mp.UpperTorso = it[1]
			end
		end
	end
	return mp
end

-- ---------------------------------------------------------------- reading the rig

local function collect(model)
	local J, byPart, order, seen = {}, {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			local j = { kind = "motor", inst = d, name = d.Part1.Name, frame = d.Part0.CFrame * d.C0, body = d.Part1.CFrame, anchor = d.Part0, part1 = d.Part1, c0 = d.C0, c1 = d.C1 }
			J[j.name], byPart[d.Part1] = j, j
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 and d.Attachment0.Parent:IsA("BasePart") and d.Attachment1.Parent:IsA("BasePart") then
			-- Current Roblox avatars are joined by AnimationConstraints: a Motor6D in all but name, with the two attachments in place of C0 and C1.
			local p0, p1 = d.Attachment0.Parent, d.Attachment1.Parent
			local j = { kind = "motor", inst = d, name = p1.Name, frame = p0.CFrame * d.Attachment0.CFrame, body = p1.CFrame, anchor = p0, part1 = p1, c0 = d.Attachment0.CFrame, c1 = d.Attachment1.CFrame }
			J[j.name], byPart[p1] = j, j
		elseif d:IsA("Bone") then
			J[d.Name] = { kind = "bone", inst = d, name = d.Name }
		end
	end
	local function world(bone)   -- rest transform of a bone; worked out by hand so it does not depend on engine state
		local p = bone.Parent
		return (if p:IsA("Bone") then world(p) else p.CFrame) * bone.CFrame
	end
	for _, j in J do
		if j.kind == "motor" then
			j.parent = byPart[j.anchor]
		else
			local p = j.inst.Parent
			j.frame = world(j.inst)
			j.body = j.frame
			if p:IsA("Bone") then
				j.parent = J[p.Name]
			else
				j.anchor = p
			end
		end
	end
	local function visit(j)
		if not seen[j] then
			seen[j] = true
			if j.parent then
				visit(j.parent)
			end
			table.insert(order, j)
		end
	end
	local names = {}
	for nm in J do
		table.insert(names, nm)
	end
	table.sort(names)
	for _, nm in names do
		visit(J[nm])
	end
	return J, order, names
end

local function frameOf(x, n)   -- orientation from a pointing direction and a palm normal
	x = x.Unit
	n = n - x * n:Dot(x)
	if n.Magnitude < 1e-5 then
		return nil
	end
	n = n.Unit
	return CFrame.fromMatrix(Vector3.zero, x, n, x:Cross(n))
end

local function swing(from, to)   -- the shortest turn that takes one direction to another
	local axis, dot = from:Cross(to), math.clamp(from:Dot(to), -1, 1)
	if axis.Magnitude < 1e-6 then
		if dot > 0 then
			return CFrame.identity
		end
		return CFrame.fromAxisAngle(from:Cross(if math.abs(from.X) < 0.9 then Vector3.xAxis else Vector3.yAxis).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

function AnyRig.analyse(model, mapping)
	local J, order, names = collect(model)
	local mp = mapping or AnyRig.map(names)
	local function pos(r)
		return J[mp[r]].frame.Position
	end
	-- which way it faces: from its left and right limbs
	local F = CFrame.identity
	local a, b = "LeftUpperArm", "RightUpperArm"
	if not (mp[a] and mp[b]) then
		a, b = "LeftUpperLeg", "RightUpperLeg"
	end
	if mp[a] and mp[b] then
		local left = (pos(a) - pos(b)) * Vector3.new(1, 0, 1)
		if left.Magnitude > 1e-4 then
			local right = -left.Unit
			F = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis, right:Cross(Vector3.yAxis))
		end
	end
	local Fi = F:Inverse()
	-- how its rest pose differs from a palms-down T-pose
	local fix, palm = {}, {}
	for _, s in SIDES do
		local sx = s == "Left" and 1 or -1
		if mp[s .. "Hand"] then
			local bases, sum = {}, Vector3.zero
			for i = 2, 5 do
				local r = s .. FINGERS[i] .. "1"
				if mp[r] then
					table.insert(bases, pos(r))
					sum += pos(r)
				end
			end
			if #bases >= 2 then
				local w = pos(s .. "Hand")
				local n = (bases[1] - w):Cross(bases[#bases] - w) * -sx
				if n.Magnitude > 1e-9 then
					palm[s] = Fi * n.Unit
					local want = frameOf(Fi * (sum / #bases - w), palm[s])
					if want then
						fix[s .. "Hand"] = want * frameOf(Vector3.new(-sx, 0, 0), PALM_DOWN):Inverse()
					end
				end
			end
		end
	end
	for r, c in TPOSE do
		local j = mp[r] and J[mp[r]]
		if j then
			local d
			if CHILD[r] and mp[CHILD[r]] then
				d = pos(CHILD[r]) - j.frame.Position
			elseif not IS_FINGER[r] and j.kind == "motor" then
				d = j.part1.Position - j.frame.Position   -- a one-piece limb: from its joint to its middle
			end
			if d and d.Magnitude > 1e-4 then
				local dc, cu = (Fi * d).Unit, c.Unit
				local s = string.sub(r, 1, 4) == "Left" and "Left" or "Right"
				local fa, ft = IS_FINGER[r] and palm[s] and frameOf(cu, PALM_DOWN), IS_FINGER[r] and palm[s] and frameOf(dc, palm[s])
				fix[r] = if fa and ft then ft * fa:Inverse() else swing(cu, dc)
			end
		end
	end
	local goal, byJoint = {}, {}
	for _, r in ROLES do
		local src = r
		while not fix[src] and FOLLOW[src] do
			src = FOLLOW[src]
		end
		fix[r] = fix[src] or CFrame.identity
		if mp[r] then
			goal[r] = F * fix[r]:Inverse() * Fi * J[mp[r]].body.Rotation
			byJoint[mp[r]] = r
		end
	end
	local leg = 0
	for _, s in SIDES do
		local u, l, ft = s .. "UpperLeg", s .. "LowerLeg", s .. "Foot"
		if mp[u] then
			if mp[l] and mp[ft] then
				leg = math.max(leg, (pos(l) - pos(u)).Magnitude + (pos(ft) - pos(l)).Magnitude)
			elseif J[mp[u]].kind == "motor" then
				leg = math.max(leg, 2 * (J[mp[u]].part1.Position - pos(u)).Magnitude)
			end
		end
	end
	return { joints = J, order = order, map = mp, byJoint = byJoint, F = F, fix = fix, goal = goal, leg = if leg > 0 then leg else REF_LEG,
		hips = if mp.LowerTorso then "LowerTorso" elseif mp.UpperTorso then "UpperTorso" else nil }
end

-- ---------------------------------------------------------------- posing

-- Transform for every recognised joint at one frame (1-based). Also returns where every joint ends up, for checks.
function AnyRig.pose(rig, clip, f)
	local F, Fi = rig.F, rig.F:Inverse()
	local posed, out, pivots = {}, {}, {}
	for _, j in rig.order do
		local base   -- the joint's own frame if only its parents had moved
		if j.kind == "motor" then
			base = (if j.parent then posed[j.parent] else j.anchor.CFrame) * j.c0
		else
			base = (if j.parent then posed[j.parent] else j.anchor.CFrame) * j.inst.CFrame
		end
		local r, t = rig.byJoint[j.name], CFrame.identity
		if r and clip.turn[r] then
			local q, i = clip.turn[r], (f - 1) * 4
			local want = F * CFrame.new(0, 0, 0, q[i + 1], q[i + 2], q[i + 3], q[i + 4]) * Fi * rig.goal[r]
			t = base.Rotation:Inverse() * want
			if j.kind == "motor" then
				t = t * j.c1.Rotation
			end
			if r == rig.hips then
				local h, k = clip.hips, (f - 1) * 3
				t = CFrame.new(base.Rotation:Inverse() * (F * (Vector3.new(h[k + 1], h[k + 2], h[k + 3]) * rig.leg))) * t
			end
			out[j.name] = t
		end
		pivots[j.name] = (base * t).Position
		posed[j] = if j.kind == "motor" then base * t * j.c1:Inverse() else base * t
	end
	return out, pivots
end

function AnyRig.apply(rig, clip, f)
	for name, t in AnyRig.pose(rig, clip, f) do
		rig.joints[name].inst.Transform = t
	end
end

-- A KeyframeSequence made for this particular model. Joints the clip does not drive get weight 0.
function AnyRig.keyframes(rig, clip)
	local ks = Instance.new("KeyframeSequence")
	ks.Loop = clip.loop
	ks.Priority = Enum.AnimationPriority.Action
	for f = 1, clip.frames do
		local T = AnyRig.pose(rig, clip, f)
		local kf = Instance.new("Keyframe")
		kf.Time = (f - 1) / clip.fps
		local poses, tops = {}, {}
		for _, j in rig.order do
			local p = Instance.new("Pose")
			p.Name, p.CFrame, p.Weight = j.name, T[j.name] or CFrame.identity, if T[j.name] then 1 else 0
			poses[j] = p
			if j.parent then
				poses[j.parent]:AddSubPose(p)
			else
				local top = tops[j.anchor]
				if not top then
					top = Instance.new("Pose")
					top.Name, top.Weight = j.anchor.Name, 0
					kf:AddPose(top)
					tops[j.anchor] = top
				end
				top:AddSubPose(p)
			end
		end
		ks:AddKeyframe(kf)
	end
	return ks
end

return AnyRig
