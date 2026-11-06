local R=require(script.Parent.Rules)
local P=require(script.Parent.Planner)
local Profiles=require(script.Parent.Profiles)
local V={}
local function area(r) return (r.x2-r.x1)*(r.z2-r.z1) end
function V.Plan(plan)
 local errors={};local by={}
 local function fail(s) table.insert(errors,s) end
 if plan.generationFailure then fail('generation failed: '..plan.generationFailure);return false,errors end
 if plan.doorSpacingFailure then fail('opposing doorway constraint unsatisfied') end
 local scale=Profiles.Scale[plan.sizeClass]
 if not table.find(Profiles.Kinds,plan.mapKind) then fail('unknown map kind') end
 if not Profiles.Scale[plan.sizeClass] then fail('unknown size class') end
 if plan.mapKind=='Cruise' then
  if plan.sizeClass=='Compact' then fail('Cruise Compact must normalize to Small') end
  if plan.horizontalScale~=1 or plan.openAreaMultiplier~=1 then fail('Cruise must use normal scale') end
 end
 if (plan.mapKind=='Hospital' or plan.mapKind=='Hotel' or plan.mapKind=='School') and (plan.horizontalScale~=1 or plan.openAreaMultiplier~=1) then fail(plan.mapKind..' must use normal scale') end
 for _,r in ipairs(plan.rooms) do
  if by[r.name] then fail('duplicate room '..r.name) end;by[r.name]=r
  local t=R.Types[r.type]
  if not t then fail('unknown type '..r.type) elseif area(r)<t.min or area(r)>t.max then fail('size '..r.name) end
  if r.type=='Kitchen' and r.level~=0 then fail('upstairs kitchen') end
  if r.type=='Bath' and r.level==0 then fail('ground public bath') end
  if r.type=='Conservatory' and not r.exterior then fail('interior conservatory') end
  if r.level<0 or r.level>1 then fail('floor out of range '..r.name) end
  local supported=0
  for _,o in ipairs(plan.rooms) do
   local w=math.min(r.x2,o.x2)-math.max(r.x1,o.x1);local d=math.min(r.z2,o.z2)-math.max(r.z1,o.z1)
   if o~=r and o.level==r.level and w>0 and d>0 then fail('room overlap '..r.name..' '..o.name) end
   if o.level==r.level-1 and w>0 and d>0 then supported+=w*d end
  end
  -- True 3D: every upper room stands entirely on ground-floor rooms.
  if r.level>0 and supported<area(r)-.01 then fail('unsupported upper room '..r.name) end
  if r.type=='Stair' then
   local twin=false
   for _,o in ipairs(plan.rooms) do if o.type=='Stair' and o.level~=r.level and o.x1==r.x1 and o.x2==r.x2 and o.z1==r.z1 and o.z2==r.z2 then twin=true end end
   if not twin then fail('stair shaft not reserved on both floors '..r.name) end
  end
 end
 if plan.mapKind=='Cruise' then
  local x1,x2,z1,z2=math.huge,-math.huge,math.huge,-math.huge
  for _,room in ipairs(plan.rooms)do x1=math.min(x1,room.x1);x2=math.max(x2,room.x2);z1=math.min(z1,room.z1);z2=math.max(z2,room.z2)end
  local aspect=(x2-x1)/(z2-z1)
  if aspect<2.4 or aspect>3.1 then fail('Cruise footprint must be long on X') end
 end
 -- Extraction: the start room is the front of the building, where the van parks.
 local start=by[plan.start]
 if not start then fail('start room missing') else
  for _,r in ipairs(plan.rooms) do if r.z2>start.z2 then fail('room in front of entrance '..r.name) end end
 end
 if scale and scale.f1 then
  local f1,f2=0,0
  for _,r in ipairs(plan.rooms) do if (R.Types[r.type] or {}).zone~='hall' and r.type~='Foyer' then if r.level==0 then f1+=1 else f2+=1 end end end
  if f1<scale.f1-1 then fail('ground floor too small '..f1) end
  if f2<4 then fail('upper floor too small '..f2) end
 end
 local stairs=0
 local adj={};for _,r in ipairs(plan.rooms) do adj[r.name]={} end
 for _,e in ipairs(plan.edges) do
  local a,b=by[e.a],by[e.b]
  if not a or not b then fail('orphan edge') else
   table.insert(adj[e.a],e);table.insert(adj[e.b],e)
   if e.kind=='stairs' then stairs+=1;if a.level==b.level then fail('stairs on same floor') end
    if not e.waypoints or #e.waypoints<2 then fail('stair without traversal path') end
   elseif a.level~=b.level then fail('door between floors')
   elseif e.stairAccess then
    local lo,hi
    if e.axis=='x' then lo,hi=math.max(a.x1,b.x1),math.min(a.x2,b.x2) else lo,hi=math.max(a.z1,b.z1),math.min(a.z2,b.z2) end
    local v=if e.axis=='x' then e.x else e.z
    if v-e.width/2<lo or v+e.width/2>hi then fail('stair opening outside wall '..a.name) end
   elseif e.axis=='x' then
    if e.x<math.max(a.x1,b.x1)+4 or e.x>math.min(a.x2,b.x2)-4 then fail('corner door '..a.name) end
   elseif e.z<math.max(a.z1,b.z1)+4 or e.z>math.min(a.z2,b.z2)-4 then fail('corner door '..a.name) end
   if e.kind=='door' and (a.type=='Bath' or b.type=='Bath') then
    local other=if a.type=='Bath' then b else a
    if R.Types[other.type].zone=='public' or R.Types[other.type].zone=='service' then fail('bath opens to public') end
   end
  end
 end
 local required=scale and scale.stairs or 1
 local maximum=required+((scale and (scale.secondStair or 0)>0)and 1 or 0)
 if stairs<required or stairs>maximum then fail('stair connections '..stairs..'; required '..required..'..'..maximum)end
 if #(plan.stairs or {})~=stairs then fail('stair descriptor/edge count mismatch')end
 local all=P.Reach(plan,{})
 for _,r in ipairs(plan.rooms) do if not all[r.name] then fail('unreachable '..r.name) end end
 local open=P.Reach(plan,plan.closed)
 for _,r in ipairs(plan.rooms) do if not plan.closed[r.name] and not open[r.name] then fail('open area severed '..r.name) end end
 if #plan.locks~=R.LockCount then fail('lock count '..#plan.locks) end
 if #plan.keyRooms~=R.KeyCount then fail('key count') end
 for _,n in ipairs(plan.keyRooms) do if not open[n] then fail('key behind lock '..n) end end
 for _,lock in ipairs(plan.locks) do
  local n=0;for _,e in ipairs(adj[lock.room]) do if not e.boarded then n+=1 end end
  if n~=1 or not lock.door.locked then fail('lock bypass '..lock.room) end
 end
 local bathClosed={};for _,r in ipairs(plan.rooms) do if r.type=='Bath' then bathClosed[r.name]=true end end
 local noBath=P.Reach(plan,bathClosed)
 for _,r in ipairs(plan.rooms) do if r.type~='Bath' and not noBath[r.name] then fail('bath transit '..r.name) end end
 local function pair(typeA,typeB)
  for _,e in ipairs(plan.edges) do local a,b=by[e.a],by[e.b];if a and b and ((a.type==typeA and b.type==typeB) or (b.type==typeA and a.type==typeB)) then return true end end
  return false
 end
 if not pair('Kitchen','Dining') then fail('kitchen dining adjacency') end
 if not pair('Master','Bath') then fail('master suite') end
 if not pair('Nursery','Playroom') then fail('nursery playroom') end
 return #errors==0,errors
end
function V.Kit(kit,allowReference)
 local errors={}
 if not allowReference and kit:GetAttribute('ImportVerified')~=true then table.insert(errors,'FBX kit import not verified') end
 for _,name in ipairs({'Wall','WallDoor','WallWindow','Floor','Ceiling','StairStep','Landing','Door','Board','Post','Trim','Bed','Nightstand','Wardrobe','Dresser','Desk','Table','Chair','Sofa','Bookshelf','Piano','Billiard','Bathtub','Sink','Toilet','Stove','Counter','Shelf','Crate','Candle','Lamp','StoneWall','StonePortal','StoneVent','StoneFloor','StoneCeiling','StoneStep','StoneLanding','IronDoor','StoneTable','StoneCounter','StoneBed','BoneShelf','CageLocker','MushroomCluster','OrganicPod','BonePile','WebNest','PartyWall','PartyPortal','PartyWindow','PartyFloor','PartyCeiling','PartyDoor','PartyTable','PartyChair','ToyLocker','PartyBed','BalloonCluster','BirthdayCake','GiftStack','ToyClown','PartyBanner'}) do
  local t=kit:FindFirstChild(name)
  if not t or not t:IsA('Model') or not t.PrimaryPart then table.insert(errors,'missing template '..name)
  elseif not t:GetAttribute('Footprint') or not t:GetAttribute('Clearance') then table.insert(errors,'metadata '..name) end
 end
 -- Validate themed mappings against their own optional template or base fallback.
 local checked={}
 for _,mapping in pairs(Profiles.TemplateMaps) do for base,name in pairs(mapping) do
  local t=kit:FindFirstChild(name) or kit:FindFirstChild(base)
  if not checked[t or name] then
   checked[t or name]=true
   if not t or not t:IsA('Model') or not t.PrimaryPart then table.insert(errors,'missing template '..name..' / '..base)
   elseif not t:GetAttribute('Footprint') or not t:GetAttribute('Clearance') then table.insert(errors,'metadata '..t.Name) end
  end
 end
 end
 for _,name in ipairs(Profiles.Decor.Cruise or {})do
  local t=kit:FindFirstChild(name)
  if not t or not t:IsA('Model') or not t.PrimaryPart then table.insert(errors,'missing Cruise decor '..name)
  elseif not t:GetAttribute('Footprint') or not t:GetAttribute('Clearance') then table.insert(errors,'metadata '..name)end
 end
 for _,name in ipairs(Profiles.Decor.Hospital or {})do
  local t=kit:FindFirstChild(name)
  if t and (not t:IsA('Model') or not t.PrimaryPart) then table.insert(errors,'invalid Hospital decor '..name)
  elseif t and (not t:GetAttribute('Footprint') or not t:GetAttribute('Clearance')) then table.insert(errors,'metadata '..name)end
 end
 for _,name in ipairs(Profiles.Decor.Hotel or {})do
  local t=kit:FindFirstChild(name)
  if t and (not t:IsA('Model') or not t.PrimaryPart) then table.insert(errors,'invalid Hotel decor '..name)
  elseif t and (not t:GetAttribute('Footprint') or not t:GetAttribute('Clearance')) then table.insert(errors,'metadata '..name)end
 end
 return #errors==0,errors
end
function V.Built(plan,mansion)
 local errors={};local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={mansion}
 -- Query actual blocking bodies along every reserved circulation segment.
 -- A successful navmesh path alone can take a different route around a prop.
 local furnitureParams=OverlapParams.new();furnitureParams.FilterType=Enum.RaycastFilterType.Include;furnitureParams.FilterDescendantsInstances={mansion.Collision}
 local F=require(script.Parent.Furnisher)
 for _,room in ipairs(plan.rooms) do for _,box in ipairs(F.Keepouts(plan,room)) do
  for _,p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(box.x,room.level*16+2.6,box.z),Vector3.new(math.max(.1,box.w-.1),4.8,math.max(.1,box.d-.1)),furnitureParams)) do
   if p.CanCollide and p:GetAttribute('Furniture') then table.insert(errors,'circulation blocked '..room.name..' '..p.Name) end
  end
 end end
 for _,e in ipairs(plan.edges) do if e.kind~='stairs' and not e.boarded then
  local size=if e.axis=='x' then Vector3.new(4.6,8,5) else Vector3.new(5,8,4.6)
  for _,p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(e.x,e.y+4.5,e.z),size,params)) do
   if not p:GetAttribute('DoorSlab') and p.Transparency<0.98 and not p:GetAttribute('NonBlockingDetail') then table.insert(errors,'visible door blockage '..e.a..' '..p.Name) end
  end
 end end
 if plan.mapKind=='Hotel' then
  local probe
  local swingOK,swingError=xpcall(function()
   local queries=OverlapParams.new();queries.FilterType=Enum.RaycastFilterType.Include;queries.FilterDescendantsInstances={mansion.Collision};queries.RespectCanCollide=true
   for _,door in ipairs(mansion.Interactive:GetChildren())do
    if door:IsA('Model') and door.PrimaryPart and door:GetAttribute('Kind')=='door' and not door:GetAttribute('Closet')then
     local closed=door:GetAttribute('ClosedPivot');local slab=door:FindFirstChild('Slab')
     if typeof(closed)~='CFrame' or not slab or not slab:IsA('BasePart') then table.insert(errors,'door swing missing slab '..door.Name);continue end
     local offset=door:GetPivot():ToObjectSpace(slab.CFrame)
     probe=slab:Clone();probe:ClearAllChildren();probe.Name='HotelDoorSwingProbe'
     probe.Size=slab.Size+Vector3.new(.6,.6,.6);probe.Transparency=1;probe.Anchored=true
     probe.CanCollide=false;probe.CanTouch=false;probe.CanQuery=false;probe.CastShadow=false;probe.Parent=workspace
     local swing=door:GetAttribute('Swing')or 100;local steps=math.max(1,math.ceil(math.abs(swing)/5));local seen={}
     for index=0,steps do
      probe.CFrame=closed*CFrame.Angles(0,math.rad(swing*index/steps),0)*offset
      for _,part in ipairs(workspace:GetPartsInPart(probe,queries))do
       if part.CanCollide and part:GetAttribute('Furniture') and not seen[part]then
        seen[part]=true;table.insert(errors,'door swing '..door.Name..' '..part.Name)
       end
      end
     end
     probe:Destroy();probe=nil
    end
   end
  end,debug.traceback)
  if probe then probe:Destroy()end
  if not swingOK then table.insert(errors,'door swing validation error '..tostring(swingError))end
 end
 -- Furniture footprints are recorded independently of visual/collision status.
 for _,name in ipairs(plan.furnitureFailures or {}) do table.insert(errors,'recipe incomplete '..name) end
 local placements=plan.placements or {}
 for _,a in ipairs(placements) do if a.tall then for _,r in ipairs(plan.rooms) do if r.name==a.room then for _,b in ipairs(r.windowKeepouts or {}) do
  if math.abs(a.x-b.x)<(a.w+b.w)/2 and math.abs(a.z-b.z)<(a.d+b.d)/2 then table.insert(errors,'tall furniture blocks window '..a.name) end
 end end end end end
 for i,a in ipairs(placements) do for j=i+1,#placements do local b=placements[j]
  if a.level==b.level and math.abs(a.x-b.x)<(a.w+b.w)/2-0.05 and math.abs(a.z-b.z)<(a.d+b.d)/2-0.05 then table.insert(errors,'furniture overlap '..a.name..' '..b.name) end
 end end
 -- Floor support and wall continuity test the built geometry, rather than collision alone.
 local floors={};for _,p in ipairs(mansion.Collision:GetChildren()) do if p.Name=='Floor' then table.insert(floors,p) end end
 local rays=RaycastParams.new();rays.FilterType=Enum.RaycastFilterType.Include;rays.FilterDescendantsInstances=floors
 for _,a in ipairs(placements) do
  local hit=workspace:Raycast(Vector3.new(a.x,a.level*16+1,a.z),Vector3.new(0,-3,0),rays)
  if not hit or math.abs(hit.Position.Y-a.level*16)>0.15 then table.insert(errors,'unsupported furniture '..a.name) end
 end
 for _,w in ipairs(plan.wallSegments or {}) do
  local visual=RaycastParams.new();visual.FilterType=Enum.RaycastFilterType.Include;visual.FilterDescendantsInstances={mansion.Architecture}
  for t=0.5,w.length-0.1,2 do
   local p=w.cf:PointToWorldSpace(Vector3.new(t-w.length/2,7,-2))
   if not workspace:Raycast(p,w.cf.LookVector*-4,visual) then table.insert(errors,'wall gap '..w.room);break end
  end
 end
 return #errors==0,errors
end
function V.Paths(plan,mansion)
 local errors={};local service=game:GetService('PathfindingService')
 local start=Vector3.new(unpack(plan.spawn));local targets={}
 for _,r in ipairs(plan.rooms) do table.insert(targets,{name=r.name,p=Vector3.new(r.navx or (r.x1+r.x2)/2,r.level*16+2,r.navz or (r.z1+r.z2)/2)}) end
 for _,e in ipairs(plan.edges) do if e.kind~='stairs' and not e.boarded then
  table.insert(targets,{name='doorway '..e.a..' '..e.b,p=Vector3.new(e.x,e.y+2,e.z)})
 end end
 for _,k in ipairs(mansion.Interactive:GetChildren()) do if k:GetAttribute('Kind')=='key' then
  local p=k.PrimaryPart.Position;local cf=k:GetAttribute('Approach');table.insert(targets,{name=k.Name,p=cf and cf.Position or Vector3.new(p.X,math.floor(p.Y/16)*16+2,p.Z)+k.PrimaryPart.CFrame.LookVector*3})
 end end
 -- Validate unlocked traversal; door slabs are restored even on API failure.
 local doors={};for _,p in ipairs(mansion.Interactive:GetDescendants()) do if p:IsA('BasePart') and p:GetAttribute('DoorSlab') then doors[p]=p.CanCollide;p.CanCollide=false end end
 local workers=12;local done=0 -- path checks run side by side (4 workers plus a frame wait per path took 2.8 s, 2026-10-22)
 for worker=1,workers do task.spawn(function()
  local path
  local ok,err=pcall(function()
   path=service:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4})
   for index=worker,#targets,workers do
    local t=targets[index]
    if (Vector3.new(start.X,0,start.Z)-Vector3.new(t.p.X,0,t.p.Z)).Magnitude<.5 and math.abs(start.Y-t.p.Y)<2 then continue end
    path:ComputeAsync(start,t.p);if path.Status~=Enum.PathStatus.Success then table.insert(errors,'path '..t.name..' '..path.Status.Name) end
   end
  end)
  if path then path:Destroy() end;if not ok then table.insert(errors,tostring(err)) end;done+=1
 end) end
 repeat task.wait() until done==workers
 for p,value in pairs(doors) do if p.Parent then p.CanCollide=value end end
 return #errors==0,errors
end
return V



