-- Cruise only (frame rate, 2026-10-22). Local to this client: nothing replicates, collisions are unaffected.
-- Live servers (owner 2026-10-27): Cruise is out of the map pool, so the ship cull loop stays off there (MapGen publishes the pool
-- as the ReplicatedStorage attribute MapPool). Studio keeps it for forced-map tests; no pool after 15 s = run as before.
do local RS_=game:GetService('ReplicatedStorage');local pool,t0=RS_:GetAttribute('MapPool'),os.clock();if not game:GetService('RunService'):IsStudio()then while pool==nil and os.clock()-t0<15 do task.wait(.5);pool=RS_:GetAttribute('MapPool')end;if pool and not table.find(string.split(pool,','),'Cruise')then return end end end
-- 1. While the camera is inside the ship, its outside (Mansion.CruiseWorld: hull, deck, pier, scenery, ~870 parts) cannot
--    be seen, so it is not drawn and its lights are off. Near the entrance (pier and van in view) and outside, it is drawn.
-- 2. Map lights farther from the camera than their range + LIGHT_MARGIN light nothing you can see: they are switched off
--    and back on when you come near (measured on Cruise at the van: 43 -> 56 FPS). Only lights this script switched off
--    are ever switched back on, so lights other scripts turn off stay off; the monster flicker (32 studs) is never in range.
local HttpService=game:GetService('HttpService')
local ENTRANCE_CLEAR=40 -- studs around the front entrance where the outside stays drawn
local LIGHT_MARGIN=30 -- studs past a light's range before it is switched off
local cache={parts={},lights={},exterior={},rooms={}}
local hidden=false
local culled={} -- [Light]=true: switched off by this script
local function setHidden(h)
	if hidden==h then return end
	hidden=h
	for _,p in cache.parts do if p.Parent then p.LocalTransparencyModifier=h and 1 or 0 end end
end
local function restoreAll()
	setHidden(false)
	for l in culled do if l.Parent then l.Enabled=true end end
	table.clear(culled)
end
local function rebuild(m)
	restoreAll()
	cache={key=tostring(m:GetAttribute('Seed'))..'/'..tostring(m:GetAttribute('WorldRevision')),parts={},lights={},exterior={},rooms={}}
	local w=m:FindFirstChild('CruiseWorld',true)
	if w then for _,d in w:GetDescendants() do if d:IsA('BasePart') then table.insert(cache.parts,d) elseif d:IsA('Light') then cache.exterior[d]=true end end end
	for _,d in m:GetDescendants() do if d:IsA('Light') then table.insert(cache.lights,d) end end
	local ok,g=pcall(function()return HttpService:JSONDecode(m.GeneratedGraph.Value)end)
	if ok and type(g)=='table' then
		for _,r in g.rooms or {} do if r.x1 and r.x2 and r.z1 and r.z2 then table.insert(cache.rooms,r) end end
		if g.entrance and g.entrance.x and g.entrance.z then cache.entrance=Vector3.new(g.entrance.x,0,g.entrance.z) end
	end
end
local function inside(pos)
	if cache.entrance and Vector3.new(pos.X-cache.entrance.X,0,pos.Z-cache.entrance.Z).Magnitude<ENTRANCE_CLEAR then return false end
	for _,r in cache.rooms do
		local y0=(r.level or 0)*16
		if pos.X>r.x1 and pos.X<r.x2 and pos.Z>r.z1 and pos.Z<r.z2 and pos.Y>y0-2 and pos.Y<y0+16 then return true end
	end
	return false
end
local function lightPosition(l)
	local p=l.Parent
	if p and p:IsA('BasePart') then return p.Position elseif p and p:IsA('Attachment') then return p.WorldPosition end
	return nil
end
while true do
	task.wait(.4)
	local m=workspace:FindFirstChild('Mansion')
	if not(m and m:GetAttribute('MapKind')=='Cruise' and m:GetAttribute('Ready')==true) then
		if hidden or next(culled) then restoreAll() end
		cache={parts={},lights={},exterior={},rooms={}}
	else
		local key=tostring(m:GetAttribute('Seed'))..'/'..tostring(m:GetAttribute('WorldRevision'))
		if cache.key~=key then rebuild(m) end
		local cam=workspace.CurrentCamera
		local at=cam and cam.CFrame.Position
		if at then
			setHidden(inside(at))
			for _,l in cache.lights do
				if l.Parent then
					local pos=lightPosition(l)
					local want=not(hidden and cache.exterior[l]) and(pos==nil or(pos-at).Magnitude<=l.Range+LIGHT_MARGIN)
					if not want and l.Enabled then l.Enabled=false;culled[l]=true
					elseif want and culled[l] then l.Enabled=true;culled[l]=nil end
				end
			end
		end
	end
end
