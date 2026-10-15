local Players=game:GetService('Players')
local M={}
local function params(mansion)
 local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include
 ray.FilterDescendantsInstances={mansion.Collision,mansion.Interactive};ray.RespectCanCollide=true
 local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include
 overlap.FilterDescendantsInstances={mansion.Collision,mansion.Interactive,mansion:FindFirstChild('Furniture')};overlap.RespectCanCollide=true
 return ray,overlap
end
-- routeDistance (optional) measures through doors and stairs instead of straight lines.
function M.Select(mansion,graph,anchor,center,shortest,waypoints,rng,allowed,routeDistance)
 local function travel(a,b)return routeDistance and routeDistance(a,b)or (a-b).Magnitude end
 local ray,overlap=params(mansion)
 local function clear(p)
  local floor=workspace:Raycast(p+Vector3.new(0,2,0),Vector3.new(0,-4,0),ray)
  if not floor or floor.Normal.Y<.9 or math.abs(floor.Position.Y-p.Y)>.25 then return false end
  -- Clearance for the largest creature (~9.4 tall): nothing may overlap its body at spawn.
  return #workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,5,0)),Vector3.new(6,9.6,6),overlap)==0
 end
 local function routeClear(points)
  for i=1,#points-1 do
   local delta=points[i+1]-points[i]
   -- Authored stair waypoints climb the treads. A horizontal capsule cast
   -- across sloped segments would falsely classify those treads as a wall.
   if math.abs(delta.Y)<.3 and delta.Magnitude>.01 and workspace:Blockcast(CFrame.new(points[i]+Vector3.new(0,2.4,0)),Vector3.new(2.4,4.4,2.4),delta,ray)then return false end
  end
  return true
 end
 local upstairs,ground={},{}
 local origin=mansion:GetAttribute('SpawnPosition')or workspace.SpawnLocation.Position
 for _,room in graph.rooms do
  if room.type~='Stair'and not room.name:find('Starter')and not(graph.closed and graph.closed[room.name])then
   local links=shortest(room.name,anchor.name)
   if links and #links>0 then
    local base=center(room)
    local samples={base}
    if room.type=='Hall'then
     for _,fraction in {.15,.85}do
      if room.x2-room.x1>room.z2-room.z1 then table.insert(samples,Vector3.new(room.x1+(room.x2-room.x1)*fraction,base.Y,base.Z))
      else table.insert(samples,Vector3.new(base.X,base.Y,room.z1+(room.z2-room.z1)*fraction))end
     end
    end
    for _,p in samples do
     local distance=math.huge
     for _,player in Players:GetPlayers()do
      local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
      -- Route distance keeps spawns out of reach; the straight-line floor stops spawns right under a player.
      if root and hum and hum.Health>0 then distance=math.min(distance,travel(p,root.Position),(p-root.Position).Magnitude*1.75)end
     end
     local separated=true
     local monsters=workspace:FindFirstChild('RoamingCreatures')
     if monsters then for _,monster in monsters:GetChildren()do if monster.PrimaryPart and(p-monster.PrimaryPart.Position).Magnitude<10 then separated=false;break end end end
     local spawnDistance=travel(p,origin)
     if distance>=35 and spawnDistance>=45 and separated and(not allowed or allowed(p))and clear(p)then
      local points=waypoints(room,links,center(anchor));table.insert(points,1,p)
      if routeClear(points)then
       local candidate={room=room,point=p,distance=distance,spawnDistance=spawnDistance}
       table.insert(room.level>0 and upstairs or ground,candidate)
      end
     end
    end
   end
  end
 end
 local candidates=#upstairs>0 and upstairs or ground
 if #candidates==0 then return nil end
 table.sort(candidates,function(a,b)
  if math.abs(a.spawnDistance-b.spawnDistance)>.01 then return a.spawnDistance>b.spawnDistance end
  return a.distance>b.distance
 end)
 return candidates[1],#candidates
end
return M
