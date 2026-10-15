-- Shared numeric rules. Gameplay decisions remain in CruiseBoatServer.
local C={}
function C.Finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
function C.Input(throttle,steer)
 if not C.Finite(throttle)or not C.Finite(steer)or math.abs(throttle)>1 or math.abs(steer)>1 then return nil end
 return throttle,steer
end
local function inside(x,z,lo,hi,pad)
 return x>lo.X-pad and x<hi.X+pad and z>lo.Z-pad and z<hi.Z+pad
end
function C.Safe(x,z,b,radius)
 if not C.Finite(x)or not C.Finite(z)then return false end
 return x>=b.seaMin.X+radius and x<=b.seaMax.X-radius and z>=b.seaMin.Z+radius and z<=b.seaMax.Z-radius
  and not inside(x,z,b.hullMin,b.hullMax,radius+3)and not inside(x,z,b.pierMin,b.pierMax,radius)
end
function C.Project(x,z,b,radius)
 local xmin,xmax=b.seaMin.X+radius+.01,b.seaMax.X-radius-.01
 local zmin,zmax=b.seaMin.Z+radius+.01,b.seaMax.Z-radius-.01
 assert(xmin<xmax and zmin<zmax,'Sea too small for the launch')
 x,z=math.clamp(x,xmin,xmax),math.clamp(z,zmin,zmax)
 if C.Safe(x,z,b,radius)then return x,z end
 local xs={x,xmin,xmax,b.hullMin.X-radius-3.01,b.hullMax.X+radius+3.01,b.pierMin.X-radius-.01,b.pierMax.X+radius+.01}
 local zs={z,zmin,zmax,b.hullMin.Z-radius-3.01,b.hullMax.Z+radius+3.01,b.pierMin.Z-radius-.01,b.pierMax.Z+radius+.01}
 local bx,bz,best=nil,nil,math.huge
 for _,px in ipairs(xs)do for _,pz in ipairs(zs)do
  if C.Safe(px,pz,b,radius)then local d=(px-x)^2+(pz-z)^2;if d<best then bx,bz,best=px,pz,d end end
 end end
 assert(bx,'No navigable water within Sea bounds')
 return bx,bz
end
local function enter(x,z,dx,dz,lo,hi,pad)
 local first,last=0,1
 for _,axis in ipairs({{x,dx,lo.X-pad,hi.X+pad},{z,dz,lo.Z-pad,hi.Z+pad}})do
  local p,d,mn,mx=unpack(axis)
  if math.abs(d)<1e-9 then if p<=mn or p>=mx then return nil end
  else local a,c=(mn-p)/d,(mx-p)/d;if a>c then a,c=c,a end;first=math.max(first,a);last=math.min(last,c);if first>last then return nil end end
 end
 if last<=0 or first>1 then return nil end
 return math.max(0,first)
end
-- Sweep the entire segment, so a fast move cannot tunnel through the hull or pier.
function C.Clamp(x,z,nx,nz,b,radius)
 x,z=C.Project(x,z,b,radius)
 nx=math.clamp(nx,b.seaMin.X+radius+.01,b.seaMax.X-radius-.01)
 nz=math.clamp(nz,b.seaMin.Z+radius+.01,b.seaMax.Z-radius-.01)
 local dx,dz=nx-x,nz-z;local fraction=1
 for _,rect in ipairs({{b.hullMin,b.hullMax,radius+3},{b.pierMin,b.pierMax,radius}})do
  local t=enter(x,z,dx,dz,rect[1],rect[2],rect[3]);if t then fraction=math.min(fraction,math.max(0,t-.0001))end
 end
 return x+dx*fraction,z+dz*fraction,fraction<1
end
-- Preserve tangential movement at contact. A small skin avoids repeated physics
-- correction on the mathematical edge; each chosen target has a safe full sweep.
function C.Slide(x,z,nx,nz,b,radius)
 local clearance=radius+.2
 local px,pz=C.Project(x,z,b,clearance)
 local cx,cz,blocked=C.Clamp(px,pz,nx,nz,b,clearance)
 if not blocked then return cx,cz,math.abs(cx-nx)>.001 or math.abs(cz-nz)>.001 end
 local best=(cx-nx)^2+(cz-nz)^2
 local function consider(sx,sz)
  local error=(sx-nx)^2+(sz-nz)^2
  if error>=best then return end
  local tx,tz=C.Clamp(px,pz,sx,sz,b,clearance)
  if math.abs(tx-sx)<.001 and math.abs(tz-sz)<.001 then cx,cz,best=sx,sz,error end
 end
 local sx,sz=C.Clamp(cx,cz,nx,cz,b,clearance);consider(sx,sz)
 sx,sz=C.Clamp(cx,cz,cx,nz,b,clearance);consider(sx,sz)
 return cx,cz,true
end
function C.Step(state,throttle,steer,dt,b,radius,maxSpeed)
 dt=math.clamp(dt,0,.1)
 local target=throttle*(throttle<0 and maxSpeed*.5 or maxSpeed)
 local speed=state.speed+(target-state.speed)*math.min(1,dt*2.8)
 local yaw=state.yaw-steer*dt*.95*math.clamp(math.abs(speed)/10,.35,1)*(speed<-.1 and -1 or 1)
 local nx,nz=state.x-math.sin(yaw)*speed*dt,state.z-math.cos(yaw)*speed*dt
 local x,z,blocked=C.Slide(state.x,state.z,nx,nz,b,radius)
 return {x=x,z=z,yaw=yaw,speed=speed},blocked
end
function C.HeadingError(heading,target)
 if not C.Finite(heading)or not C.Finite(target)then return math.huge end
 return math.abs(math.atan2(math.sin(target-heading),math.cos(target-heading)))
end
function C.MoorEligible(speed,throttle,distance,radius,now,departUntil,heading,targetHeading)
 if departUntil and (not C.Finite(now)or not C.Finite(departUntil)or now<departUntil)then return false end
 return C.Finite(speed)and C.Finite(throttle)and C.Finite(distance)and C.Finite(radius)and radius>0
  and speed>=0 and speed<3 and math.abs(throttle)<.08 and distance>=0 and distance<=radius
  and C.HeadingError(heading,targetHeading)<=math.rad(30)+1e-9
end
-- Short smooth docking targets; the server's existing constraints move the boat.
function C.DockPose(from,to,fraction)
 local t=math.clamp(fraction,0,1);local ease=t*t*(3-2*t)
 local turn=math.atan2(math.sin(to.yaw-from.yaw),math.cos(to.yaw-from.yaw))
 return {x=from.x+(to.x-from.x)*ease,z=from.z+(to.z-from.z)*ease,yaw=from.yaw+turn*ease}
end
function C.NearestDock(position,docks)
 local best,distance=nil,math.huge
 for _,dock in ipairs(docks)do local d=(Vector3.new(position.X,0,position.Z)-Vector3.new(dock.point.X,0,dock.point.Z)).Magnitude
  if d<distance then best,distance=dock,d end
 end
 return best,distance
end
-- The authored Home-to-dock chains form a small route graph. Select a visible
-- entry node, then follow chain edges instead of drawing through the ship.
function C.Route(position,target,home,routes,b,radius)
 local nodes={{point=home.point,links={}}};local ends={[home.id]=1}
 local function connect(a,d)
  local p,q=nodes[a].point,nodes[d].point;local x,z=C.Clamp(p.X,p.Z,q.X,q.Z,b,radius)
  if math.abs(x-q.X)>.05 or math.abs(z-q.Z)>.05 then return end
  local distance=(p-q).Magnitude;nodes[a].links[d]=distance;nodes[d].links[a]=distance
 end
 for _,route in ipairs(routes)do
  local previous=1
  for _,point in ipairs(route.points)do
   if C.Safe(point.X,point.Z,b,radius)then table.insert(nodes,{point=point,links={}});local n=#nodes;connect(previous,n);previous=n end
  end
  ends[route.id]=previous
 end
 local goal=ends[target.id]
 if not goal then return {}end
 local dist,prev,done={[goal]=0},{},{}
 for _=1,#nodes do
  local at,cost=nil,math.huge;for i,value in pairs(dist)do if not done[i]and value<cost then at,cost=i,value end end
  if not at then break end;done[at]=true
  for nextNode,length in pairs(nodes[at].links)do local value=cost+length;if value<(dist[nextNode]or math.huge)then dist[nextNode]=value;prev[nextNode]=at end end
 end
 local entry,total=nil,math.huge
 for i,node in ipairs(nodes)do
  local x,z=C.Clamp(position.X,position.Z,node.point.X,node.point.Z,b,radius)
  if math.abs(x-node.point.X)<.05 and math.abs(z-node.point.Z)<.05 then
   local cost=(node.point-position).Magnitude+(dist[i]or math.huge);if cost<total then entry,total=i,cost end
  end
 end
 if not entry then return {}end
 local points={}
 for _=1,#nodes do table.insert(points,nodes[entry].point);if entry==goal then break end;entry=prev[entry];if not entry then break end end
 return points,total
end
return C
