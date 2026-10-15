-- Stateless, server-only crosshair placement helper owned by CursedItemsServer.
local P={}
local REACH,CAMERA_NEAR,MAX_CAMERA=11,3.5,6
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e7 end
local function vector(v)return typeof(v)=='Vector3'and finite(v.X)and finite(v.Y)and finite(v.Z)end
local function extent(cf,size)
 return Vector3.new(math.abs(cf.RightVector.X)*size.X+math.abs(cf.UpVector.X)*size.Y+math.abs(cf.LookVector.X)*size.Z,math.abs(cf.RightVector.Y)*size.X+math.abs(cf.UpVector.Y)*size.Y+math.abs(cf.LookVector.Y)*size.Z,math.abs(cf.RightVector.Z)*size.X+math.abs(cf.UpVector.Z)*size.Y+math.abs(cf.LookVector.Z)*size.Z)*.5
end
local function intersects(cf,size,at,half)
 local h=extent(cf,size);local d=cf.Position-at
 return math.abs(d.X)<h.X+half.X and math.abs(d.Y)<h.Y+half.Y and math.abs(d.Z)<h.Z+half.Z
end
function P.Find(player,item,ray,ctx)
 if type(ray)~='table'or ray.touch~=true or not vector(ray.origin)or not vector(ray.direction)then return nil,'payload'end
 local char=player.Character;local head=char and char:FindFirstChild('Head');local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
 if not head or not root or not hum or hum.Health<=0 or player:GetAttribute('Hiding')or not item.PrimaryPart or item:GetAttribute('HeldBy')~=player.UserId then return nil,'owner'end
 local offset=ray.origin-head.Position;local length=ray.direction.Magnitude
 if offset.Magnitude>MAX_CAMERA or length<.99 or length>1.01 then return nil,'camera'end
 local origin=head.Position+(offset.Magnitude>CAMERA_NEAR and offset.Unit*CAMERA_NEAR or offset)
 local map=ctx.Map
 if not map or not map.Parent or map:GetAttribute('Rebuilding')then return nil,'rebuilding'end
 -- Mission regeneration replaces rooms inside the same map instance.
 -- The owner's initial room cache must not authorize a spot in the previous layout.
 local rooms=ctx.Rooms;local graph=map:FindFirstChild('GeneratedGraph')
 if graph then
  local ok,plan=pcall(function()return game:GetService('HttpService'):JSONDecode(graph.Value)end)
  if not ok or type(plan)~='table'or type(plan.rooms)~='table'then return nil,'graph'end
  rooms=plan.rooms
 end
 local camp=workspace:FindFirstChild('RecoveryCamp');local ignored={item}
 for _,p in game.Players:GetPlayers()do if p.Character then ignored[#ignored+1]=p.Character end end
 for _,name in {'RoamingCreatures','CharacterEntities'}do local f=workspace:FindFirstChild(name);if f then ignored[#ignored+1]=f end end
 local physical=RaycastParams.new();physical.FilterType=Enum.RaycastFilterType.Exclude;physical.FilterDescendantsInstances=ignored;physical.RespectCanCollide=true
 local function los(a,b)
  local delta=b-a;if delta.Magnitude<.05 then return true end
  local hit=workspace:Raycast(a,delta,physical)
  return not hit or hit.Distance>=delta.Magnitude-.12
 end
 if not los(head.Position,origin)then return nil,'camera-wall'end
 local selectable=RaycastParams.new();selectable.FilterType=Enum.RaycastFilterType.Exclude;selectable.FilterDescendantsInstances=table.clone(ignored)
 local hit
 for _=1,16 do
  local nextHit=workspace:Raycast(origin,ray.direction.Unit*REACH,selectable)
  if not nextHit then break end
  local p=nextHit.Instance
  local backedGeometry=(p:IsDescendantOf(map.Architecture)or p:IsDescendantOf(map.Furniture))and not p:GetAttribute('Roof')
  if p:IsA('BasePart')and p.Transparency<.95 and not p:GetAttribute('NonBlockingDetail')and(p.CanCollide or backedGeometry)then hit=nextHit;break end
  selectable:AddToFilter(p)
 end
 if not hit or hit.Material==Enum.Material.Water or not(hit.Instance:IsDescendantOf(map)or camp and hit.Instance:IsDescendantOf(camp))then return nil,'surface'end
 if hit.Normal.Y<-.3 then return nil,'ceiling'end
 local bounds=ctx.Bounds(item);local size=bounds.size
 local cart=hit.Instance:FindFirstAncestorOfClass('Model')
 if not(cart and cart:GetAttribute('Kind')=='cart'and cart:FindFirstChild('BasketFloor'))then cart=nil end
 -- A basket rim can obscure its floor while the actual upright landing remains visible.
 -- The candidate's centre still has to pass the head LOS test below.
 if not cart and not los(head.Position,hit.Position)then return nil,'blocked'end
 local wall=not cart and hit.Normal.Y<.9
 local normal=Vector3.new(hit.Normal.X,0,hit.Normal.Z)
 local point=hit.Position
 if cart then
  -- Aim on the basket frame also means the basket, rather than the floor outside it.
  local floor=cart.BasketFloor;local localPoint=floor.CFrame:PointToObjectSpace(point)
  localPoint=Vector3.new(math.clamp(localPoint.X,-math.max(0,(floor.Size.X-size.X)*.5-.1),math.max(0,(floor.Size.X-size.X)*.5-.1)),floor.Size.Y*.5,math.clamp(localPoint.Z,-math.max(0,(floor.Size.Z-size.Z)*.5-.1),math.max(0,(floor.Size.Z-size.Z)*.5-.1)))
  point=floor.CFrame:PointToWorldSpace(localPoint)
 end
 if wall then
  if normal.Magnitude<.5 then return nil,'slope'end
  normal=normal.Unit;point+=normal*((math.abs(normal.X)*size.X+math.abs(normal.Z)*size.Z)*.5+.16)
 end
 local locked={}
 for _,door in map.Interactive:GetChildren()do if door:GetAttribute('Locked')then locked[door:GetAttribute('Room')or '']=true end end
 local function inRoom(room,x,z,y)
  -- Furniture tops share the room's floor; the next storey is 16 studs above it.
  return y>=room.level*16-1 and y<room.level*16+12 and x>=room.x1 and x<=room.x2 and z>=room.z1 and z<=room.z2
 end
 local function domain(surface,x,z,y)
  if cart and surface:IsDescendantOf(cart)then
   local below=RaycastParams.new();below.FilterType=Enum.RaycastFilterType.Include;below.RespectCanCollide=true
   local world=map:FindFirstChild('CruiseWorld');local pier=world and world:FindFirstChild('Pier')
   below.FilterDescendantsInstances={map.Collision};if camp then below:AddToFilter(camp)end;if pier then below:AddToFilter(pier)end
   local floor=workspace:Raycast(Vector3.new(x,cart.BasketFloor.Position.Y-.5,z),Vector3.new(0,-REACH,0),below)
   return floor and domain(floor.Instance,x,z,floor.Position.Y)or false
  end
  if camp and surface:IsDescendantOf(camp)then return true end
  local world=map:FindFirstChild('CruiseWorld');local pier=world and world:FindFirstChild('Pier')
  if pier and surface:IsDescendantOf(pier)then
   local a,b=world:GetAttribute('PierMin'),world:GetAttribute('PierMax')
   return typeof(a)=='Vector3'and typeof(b)=='Vector3'and x>=a.X and x<=b.X and z>=a.Z and z<=b.Z
  end
  for _,room in pairs(rooms)do if inRoom(room,x,z,y)then
   if not locked[room.name]or inRoom(room,root.Position.X,root.Position.Z,root.Position.Y-3)then return true end
  end end
  return false
 end
 local function clear(pos,surface)
  local at=pos+bounds.centre;local half=Vector3.new(math.max(.03,size.X*.5-.025),math.max(.03,size.Y*.5-.025),math.max(.03,size.Z*.5-.025))
  -- Physical solids include invisible wall proxies and CanQuery=false drawer/closet colliders.
  for _,respect in {true,false}do
   local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={item};params.RespectCanCollide=respect;params.MaxParts=100
   local parts=workspace:GetPartBoundsInBox(CFrame.new(at),half*2,params)
   if #parts>=100 then return false end
   for _,p in parts do
    if p~=surface and not p:GetAttribute('NonBlockingDetail')and(p.CanCollide or p.Transparency<.95 and p:IsDescendantOf(map.Furniture))then return false end
   end
  end
  -- Players and authored loot may have non-queryable meshes: also check their real bounds.
  for _,p in game.Players:GetPlayers()do if p.Character then local cf,s=p.Character:GetBoundingBox();if intersects(cf,s,at,half)then return false end end end
  for _,other in map.Interactive:GetChildren()do if other~=item and other:IsA('Model')and other.PrimaryPart and other:GetAttribute('ItemId')then
   local b=ctx.Bounds(other);if intersects(other:GetPivot()*CFrame.new(b.centre),b.size,at,half)then return false end
  end end
  return true
 end
 local ground=RaycastParams.new();ground.FilterType=Enum.RaycastFilterType.Include;ground.FilterDescendantsInstances=camp and {map.Collision,camp}or {map.Collision};ground.RespectCanCollide=true
 local stride=math.clamp(math.max(size.X,size.Z)*.5,.4,1.5)
 local offsets={Vector3.zero,Vector3.new(stride,0,0),Vector3.new(-stride,0,0),Vector3.new(0,0,stride),Vector3.new(0,0,-stride),Vector3.new(stride,0,stride),Vector3.new(-stride,0,stride),Vector3.new(stride,0,-stride),Vector3.new(-stride,0,-stride)}
 if cart then
  -- If a rim hit is too close to the side, try the visible, clear basket centre.
  table.insert(offsets,2,cart.BasketFloor.CFrame:PointToWorldSpace(Vector3.new(0,cart.BasketFloor.Size.Y*.5,0))-point)
 end
 for _,off in offsets do
  local q=point+off;local support=cart and cart.BasketFloor or hit.Instance;local top=point.Y+.4;local bottom=point.Y-.6
  if wall then
   local floor=workspace:Raycast(q+Vector3.new(0,.4,0),Vector3.new(0,-REACH,0),ground)
   if floor and floor.Normal.Y>.9 then support=floor.Instance;top=floor.Position.Y+.4;bottom=floor.Position.Y-.6 else continue end
  elseif support:IsDescendantOf(map.Architecture)or not support.CanCollide and support:IsDescendantOf(map.Furniture)then support=map.Collision end
  local pos,height=ctx.Supported(item,q.X,q.Z,support,top,bottom,true)
  if not pos then continue end
  local feet=Vector3.new(pos.X+bounds.centre.X,height,pos.Z+bounds.centre.Z)
  if(feet-head.Position).Magnitude>REACH or not los(head.Position,pos+bounds.centre)then continue end
  local on=workspace:Raycast(feet+Vector3.new(0,.2,0),Vector3.new(0,-.4,0),physical)
  if not on or on.Normal.Y<.9 then continue end
  local legal=true
  for _,corner in {Vector3.zero,Vector3.new(-size.X*.5,0,-size.Z*.5),Vector3.new(size.X*.5,0,-size.Z*.5),Vector3.new(-size.X*.5,0,size.Z*.5),Vector3.new(size.X*.5,0,size.Z*.5)}do if not domain(on.Instance,feet.X+corner.X,feet.Z+corner.Z,height)then legal=false;break end end
  if legal and clear(pos,on.Instance)then return CFrame.new(pos),'placed',on.Instance end
 end
 return nil,'no-clear-support'
end
return P
