-- Room-graph topology shared by generation, validation and monster AI.
-- High-level reasoning uses route distance through doors and stairs, never
-- straight-line distance across floors. Movement stays with the AI owners.
local Rules=require(script.Parent.Rules)
local T={}
T.Version=1
T.FloorHeight=Rules.FloorStep
local INF=math.huge
-- Same threshold the AI always used (level 1 from 10 studs at FloorHeight 16).
function T.Level(y) return math.max(0,math.floor((y+T.FloorHeight*.375)/T.FloorHeight)) end
function T.Center(r) return Vector3.new(r.navx or (r.x1+r.x2)/2,r.level*T.FloorHeight,r.navz or (r.z1+r.z2)/2) end
local function stairEnds(e)
 local w=e.waypoints
 if w and #w>=2 then
  local length=0;for i=2,#w do length+=(Vector3.new(unpack(w[i]))-Vector3.new(unpack(w[i-1]))).Magnitude end
  return Vector3.new(unpack(w[1])),Vector3.new(unpack(w[#w])),length
 end
 local p=Vector3.new(e.x,e.y,e.z);return p,p+Vector3.new(0,T.FloorHeight,0),T.FloorHeight*2.5
end
-- Portal nodes: one per doorway, two per staircase (bottom and top).
local function portals(graph)
 local by={};for _,r in ipairs(graph.rooms) do by[r.name]=r end
 local nodes,roomNodes,links={},{},{}
 for _,r in ipairs(graph.rooms) do roomNodes[r.name]={} end
 for _,e in ipairs(graph.edges) do
  local a,b=by[e.a],by[e.b]
  if a and b and not e.boarded then
   if e.kind=='stairs' then
    local low,high=a,b;if low.level>high.level then low,high=b,a end
    local p1,p2,length=stairEnds(e)
    local n1={pos=p1,edge=e,room=low.name};local n2={pos=p2,edge=e,room=high.name}
    table.insert(nodes,n1);table.insert(nodes,n2)
    table.insert(roomNodes[low.name],#nodes-1);table.insert(roomNodes[high.name],#nodes)
    table.insert(links,{#nodes-1,#nodes,length})
   else
    table.insert(nodes,{pos=Vector3.new(e.x,e.y,e.z),edge=e})
    table.insert(roomNodes[e.a],#nodes);table.insert(roomNodes[e.b],#nodes)
   end
  end
 end
 return nodes,roomNodes,links
end
-- Route-distance oracle. `blocked(edge)` is optional and re-checked lazily, so
-- locking or opening a door changes routes without rebuilding the graph.
function T.New(graph,blocked)
 local nodes,roomNodes,links=portals(graph)
 local self={graph=graph,nodes=nodes,roomNodes=roomNodes}
 local matrix,signature
 local function currentSignature()
  if not blocked then return '' end
  local bits=table.create(#nodes)
  for i,n in ipairs(nodes) do bits[i]=blocked(n.edge) and '1' or '0' end
  return table.concat(bits)
 end
 local function build(sig)
  local n=#nodes;local d=table.create(n)
  local open=table.create(n)
  for i=1,n do open[i]=sig=='' or sig:sub(i,i)=='0' end
  for i=1,n do d[i]=table.create(n,INF);d[i][i]=open[i] and 0 or INF end
  for _,list in pairs(roomNodes) do
   for _,i in ipairs(list) do for _,j in ipairs(list) do
    if i~=j and open[i] and open[j] then d[i][j]=math.min(d[i][j],(nodes[i].pos-nodes[j].pos).Magnitude) end
   end end
  end
  for _,l in ipairs(links) do if open[l[1]] and open[l[2]] then d[l[1]][l[2]]=math.min(d[l[1]][l[2]],l[3]);d[l[2]][l[1]]=d[l[1]][l[2]] end end
  for k=1,n do local dk=d[k]
   for i=1,n do local di=d[i];local ik=di[k]
    if ik<INF then for j=1,n do local v=ik+dk[j];if v<di[j] then di[j]=v end end end
   end
  end
  matrix,signature=d,sig
 end
 function self:Matrix()
  local sig=currentSignature()
  if sig~=signature then build(sig) end
  return matrix
 end
 -- Route length in studs between two points in known rooms; math.huge if severed.
 function self:Distance(posA,roomA,posB,roomB)
  if roomA==roomB then return (posA-posB).Magnitude end
  local d=self:Matrix();local best=INF
  for _,i in ipairs(roomNodes[roomA] or {}) do
   local head=(posA-nodes[i].pos).Magnitude;local row=d[i]
   if head<best then for _,j in ipairs(roomNodes[roomB] or {}) do
    local v=head+row[j]+(nodes[j].pos-posB).Magnitude
    if v<best then best=v end
   end end
  end
  return best
 end
 function self:RoomDistance(a,b)
  local by=self.by;if not by then by={};for _,r in ipairs(graph.rooms) do by[r.name]=r end;self.by=by end
  return self:Distance(T.Center(by[a]),a,T.Center(by[b]),b)
 end
 return self
end
-- Static shape facts for the published graph and the stress harness.
function T.Analyze(graph)
 local by,adj={},{}
 for _,r in ipairs(graph.rooms) do by[r.name]=r;adj[r.name]={} end
 local edgeCount,vertical=0,0
 for _,e in ipairs(graph.edges) do if not e.boarded and by[e.a] and by[e.b] then
  edgeCount+=1;table.insert(adj[e.a],e);table.insert(adj[e.b],e)
  if e.kind=='stairs' or by[e.a].level~=by[e.b].level then vertical+=1 end
 end end
 local depth={[graph.start]=0};local q={graph.start};local head=1
 while q[head] do local n=q[head];head+=1
  for _,e in ipairs(adj[n] or {}) do local o=e.a==n and e.b or e.a
   if depth[o]==nil then depth[o]=depth[n]+1;table.insert(q,o) end
  end
 end
 local seen,components={},0
 for _,r in ipairs(graph.rooms) do if not seen[r.name] then
  components+=1;local stack={r.name};seen[r.name]=true
  while #stack>0 do local n=table.remove(stack)
   for _,e in ipairs(adj[n]) do local o=e.a==n and e.b or e.a;if not seen[o] then seen[o]=true;table.insert(stack,o) end end
  end
 end end
 local rooms={};local floors={};local deadEnds,maxDepth,unreachable=0,0,0
 for _,r in ipairs(graph.rooms) do
  local neighbors,verticals={},{}
  for _,e in ipairs(adj[r.name]) do local o=e.a==r.name and e.b or e.a
   table.insert(neighbors,o)
   if e.kind=='stairs' or by[o].level~=r.level then table.insert(verticals,o) end
  end
  floors[r.level+1]=(floors[r.level+1] or 0)+1
  if #neighbors==1 and r.type~='Stair' and r.name~=graph.start then deadEnds+=1 end
  if depth[r.name] then maxDepth=math.max(maxDepth,depth[r.name]) else unreachable+=1 end
  rooms[r.name]={floorIndex=r.level,depth=depth[r.name] or -1,neighbors=neighbors,verticalConnections=verticals,entrances=#neighbors}
 end
 for i=1,#floors do floors[i]=floors[i] or 0 end
 return {rooms=rooms,metrics={rooms=#graph.rooms,edges=edgeCount,floors=floors,deadEnds=deadEnds,loops=edgeCount-#graph.rooms+components,
  components=components,verticalConnections=vertical,maxDepth=maxDepth,unreachable=unreachable,
  averageConnectivity=#graph.rooms>0 and 2*edgeCount/#graph.rooms or 0}}
end
-- Annotates graph rooms in place with AI-facing metadata and returns metrics.
-- Route figures use the route oracle, so stairs cost their real climb.
function T.Annotate(graph)
 local result=T.Analyze(graph)
 for _,r in ipairs(graph.rooms) do local info=result.rooms[r.name]
  r.floorIndex=info.floorIndex;r.depth=info.depth;r.neighbors=info.neighbors;r.verticalConnections=info.verticalConnections
 end
 local oracle=T.New(graph);local longest,deepest=0,nil
 local start
 for _,r in ipairs(graph.rooms) do if r.name==graph.start then start=r end end
 if start then for _,r in ipairs(graph.rooms) do
  local d=oracle:RoomDistance(start.name,r.name)
  if d<INF and d>longest then longest,deepest=d,r.name end
 end end
 result.metrics.longestRouteFromStart=math.floor(longest+.5);result.metrics.deepestRoom=deepest
 graph.floorHeight=T.FloorHeight;graph.topologyVersion=T.Version;graph.metrics=result.metrics
 return result.metrics
end
return T
