-- Socket-driven multi-floor generator. One connectivity graph spans both floors:
-- halls, rooms, suites and two-floor stair modules join only through sockets.
-- Output keeps the plan contract used by Builder, Furnisher, Validator and the AI.
local Rules=require(script.Parent.Rules)
local Profiles=require(script.Parent.Profiles)
local Modules=require(script.Parent.RoomModules)
local P={}
P.Version=3
local FLOOR=Rules.FloorStep
local HALL=Modules.HallWidth
-- Mall keeps the same topology/gameplay; enlarge only this plan's horizontal
-- geometry after solving sockets. Linear sqrt(area) yields 1.85x floor area.
local MALL_AREA_MULTIPLIER=1.85
local MALL_HORIZONTAL_SCALE=math.sqrt(MALL_AREA_MULTIPLIER)
-- Wider halls reject more socket candidates; retain constraints and allow a
-- bounded retry budget instead of returning incomplete enlarged layouts.
local MAX_LAYOUT_ATTEMPTS=32
local MAX_SOCKET_ATTEMPTS=3
local MAX_ROOM_PLACEMENT_ATTEMPTS=10
local MAX_GROWTH_STEPS=600
local OPP={N='S',S='N',E='W',W='E'}
local SIDES={'N','E','S','W'}
local function shuffle(a,rng)
 for i=#a,2,-1 do local j=rng:NextInteger(1,i);a[i],a[j]=a[j],a[i] end
 return a
end
local function pick(rng,list)
 local total=0;for _,c in ipairs(list) do total+=c.w end
 if total<=0 then return nil end
 local x=rng:NextNumber()*total
 for i,c in ipairs(list) do x-=c.w;if x<=0 then return c,i end end
 return list[#list],#list
end
-- One quarter turn: N->E->S->W. Offsets follow the world axis convention below.
local TURN={N={'E',1},E={'S',-1},S={'W',1},W={'N',-1}}
local function rotateSide(side,t,k)
 for _=1,k%4 do local r=TURN[side];side=r[1];t*=r[2] end
 return side,t
end
local function rotateVec(x,z,k)
 for _=1,k%4 do x,z=-z,x end
 return x,z
end
P.RotateVec=rotateVec
-- Socket point on a rectangle side; t runs along +X (N/S) or +Z (E/W).
local function socketAt(r,side,t)
 local cx,cz=(r.x1+r.x2)/2,(r.z1+r.z2)/2
 if side=='N' then return cx+t,r.z1,'x' elseif side=='S' then return cx+t,r.z2,'x'
 elseif side=='E' then return r.x2,cz+t,'z' else return r.x1,cz+t,'z' end
end
-- Rectangle that grows outward from a parent socket on `side`.
local function attach(side,px,pz,along,depth,t)
 if side=='E' then local zc=pz-t;return {x1=px,x2=px+depth,z1=zc-along/2,z2=zc+along/2}
 elseif side=='W' then local zc=pz-t;return {x1=px-depth,x2=px,z1=zc-along/2,z2=zc+along/2}
 elseif side=='S' then local xc=px-t;return {x1=xc-along/2,x2=xc+along/2,z1=pz,z2=pz+depth}
 else local xc=px-t;return {x1=xc-along/2,x2=xc+along/2,z1=pz-depth,z2=pz} end
end
local function overlaps(a,b)
 return a.level==b.level and math.min(a.x2,b.x2)>math.max(a.x1,b.x1) and math.min(a.z2,b.z2)>math.max(a.z1,b.z1)
end
local function sharedSpan(a,b,axis)
 if axis=='x' then return math.max(a.x1,b.x1),math.min(a.x2,b.x2) end
 return math.max(a.z1,b.z1),math.min(a.z2,b.z2)
end
function P.Reach(plan,closed)
 local adj={};for _,r in ipairs(plan.rooms) do adj[r.name]={} end
 for _,e in ipairs(plan.edges) do
  if not e.boarded and adj[e.a] and adj[e.b] then table.insert(adj[e.a],e.b);table.insert(adj[e.b],e.a) end
 end
 local seen={[plan.start]=true};local q={plan.start};local head=1
 while q[head] do
  local n=q[head];head+=1
  for _,o in ipairs(adj[n] or {}) do if not closed[o] and not seen[o] then seen[o]=true;table.insert(q,o) end end
 end
 return seen
end

-- Layout state ------------------------------------------------------------
local function newState(seed,attempt,mapKind,sizeClass)
 local scale=Profiles.Scale[sizeClass]
 local rng=Random.new(seed*31+attempt*7919)
 local plan={seed=seed,shape='socket',generatorVersion=P.Version,layoutAttempt=attempt,rooms={},edges={},start='L0_Starter',
  locks={},keyRooms={},stairs={},rejections={}}
 local foyerZ2=60
 local s={plan=plan,rng=rng,scale=scale,by={},id=0,frontier={},typeCount={},hallCount={[0]=0,[1]=0},roomCount={[0]=0,[1]=0},
  bounds={x1=-scale.width,x2=scale.width,z1=foyerZ2-2*scale.outer-16,z2=foyerZ2},foyerZ2=foyerZ2,
  stairsNeeded=scale.stairs+((rng:NextNumber()<scale.secondStair) and 1 or 0),suites={}}
 if mapKind=='Cruise' then
  s.cruise=true
  local dims=({Small={142,104},Medium={160,112},Large={184,124}})[sizeClass] -- bigger ships (was 112x84/132x96/152x108)
  local jx,jz=dims[1]*(0.94+s.rng:NextNumber()*0.12),dims[2]*(0.94+s.rng:NextNumber()*0.12) -- each ship's footprint varies a little
   s.bounds={x1=-jx,x2=jx,z1=foyerZ2-jz,z2=foyerZ2}
 end
 return s
end
local function reject(s,reason) s.plan.rejections[reason]=(s.plan.rejections[reason] or 0)+1 end
local function covered(s,r)
 local area=0
 for _,o in ipairs(s.plan.rooms) do if o.level==r.level-1 then
  local w=math.min(r.x2,o.x2)-math.max(r.x1,o.x1);local d=math.min(r.z2,o.z2)-math.max(r.z1,o.z1)
  if w>0 and d>0 then area+=w*d end
 end end
 return area
end
-- 3D validation: bounds, same-level overlap, and full support for upper floors.
local function fits(s,rect,level)
 rect.level=level
 local b=s.bounds
 if rect.x1<b.x1 or rect.x2>b.x2 or rect.z1<b.z1 or rect.z2>b.z2 then reject(s,'bounds');return false end
 for _,o in ipairs(s.plan.rooms) do if overlaps(o,rect) then reject(s,'overlap');return false end end
 if level>0 and covered(s,rect)<(rect.x2-rect.x1)*(rect.z2-rect.z1)-.01 then reject(s,'unsupported upper floor');return false end
 return true
end
-- A doorway's cut must sit inside the wall both rooms share.
local function portalFits(s,a,b,axis,v,half)
 local lo,hi=sharedSpan(a,b,axis)
 if v-half<lo or v+half>hi then reject(s,'portal outside shared wall');return false end
 return true
end
local function addRoom(s,t,level,rect,depth,name)
 s.id+=1
 local r={name=name or ('L'..level..'_'..t..'_'..s.id),type=t,level=level,x1=rect.x1,x2=rect.x2,z1=rect.z1,z2=rect.z2,theme=1,graphDepth=depth,order=s.id}
 table.insert(s.plan.rooms,r);s.by[r.name]=r
 s.typeCount[t]=(s.typeCount[t] or 0)+1
 if t=='Hall' then s.hallCount[level]+=1 elseif t~='Stair' and t~='Foyer' then s.roomCount[level]+=1 end
 return r
end
local function removeRoom(s,r)
 for i=#s.plan.rooms,1,-1 do if s.plan.rooms[i]==r then table.remove(s.plan.rooms,i) end end
 for i=#s.plan.edges,1,-1 do local e=s.plan.edges[i];if e.a==r.name or e.b==r.name then table.remove(s.plan.edges,i) end end
 for i=#s.frontier,1,-1 do if s.frontier[i].room==r then table.remove(s.frontier,i) end end
 s.by[r.name]=nil;s.typeCount[r.type]-=1
 if r.type=='Hall' then s.hallCount[r.level]-=1 elseif r.type~='Stair' and r.type~='Foyer' then s.roomCount[r.level]-=1 end
end
local function link(s,a,b,kind,px,pz,axis,width,extra)
 local e={a=a.name,b=b.name,kind=kind,x=px,y=a.level*FLOOR,z=pz,axis=axis,width=width}
 if extra then for k,v in pairs(extra) do e[k]=v end end
 table.insert(s.plan.edges,e);return e
end
local function addSocket(s,r,side,t,class)
 table.insert(s.frontier,{room=r,side=side,t=t,class=class,level=r.level,depth=r.graphDepth,tries=0})
end
-- Hall sockets derive from geometry: open ends on the short sides, room slots on the long sides.
local function hallSockets(s,r,skipSide,skipT)
 local w,d=r.x2-r.x1,r.z2-r.z1
 local function add(side,t,class) if not (side==skipSide and math.abs(t-(skipT or 0))<.01) then addSocket(s,r,side,t,class) end end
 if w==d then for _,side in ipairs(SIDES) do add(side,0,'hallEnd') end;return end
 local longX=w>d
 local ends=longX and {'W','E'} or {'N','S'};local sides=longX and {'N','S'} or {'W','E'}
 for _,side in ipairs(ends) do add(side,0,'hallEnd') end
 for _,side in ipairs(sides) do for _,t in ipairs(Modules.Slots(longX and w or d)) do add(side,t,'roomDoor') end end
end

-- Candidates ---------------------------------------------------------------
local function typeWeight(s,t,level,parent,depth)
 local def=Modules.Rooms[t]
 if not def or def.weight<=0 or not def.floors[level] then return 0 end
 local count=s.typeCount[t] or 0
 if count>=def.max then return 0 end
 local repetition=.45^count
 -- Neighbour rule: the same type twice off one hall reads as copy-paste.
 local neighbor=1
 for _,e in ipairs(s.plan.edges) do
  local other=(e.a==parent.name and e.b) or (e.b==parent.name and e.a)
  if other and s.by[other] and s.by[other].type==t then neighbor*=.35 end
 end
 local depthMod=1
 if def.danger and def.danger>.6 then depthMod=math.clamp(depth/4,.35,1.4) end
 return def.weight*repetition*neighbor*depthMod
end
-- Place one room against a hall slot; returns the room or nil.
-- Rooms whose furniture layout needs doors on their north/south walls only.
local NS_DOORS={Dining=true}
local function tryRoom(s,f,t)
 local def=Modules.Rooms[t];local parent=f.room
 if NS_DOORS[t] and f.side~='N' and f.side~='S' then reject(s,'door wall not allowed for '..t);return end
 local px,pz,axis=socketAt(parent,f.side,f.t)
 local options={}
 for _,size in ipairs(def.sizes) do
  for _,o in ipairs({{size[1],size[2]},{size[2],size[1]}}) do
   local along,depth=o[1],o[2]
   for _,t in ipairs({0,along/2-8,-(along/2-8)}) do table.insert(options,{along=along,depth=depth,t=t}) end
  end
 end
 shuffle(options,s.rng)
 for i=1,math.min(#options,MAX_ROOM_PLACEMENT_ATTEMPTS) do
  local o=options[i]
  local rect=attach(f.side,px,pz,o.along,o.depth,o.t)
  rect.level=parent.level
  if fits(s,rect,parent.level) and portalFits(s,parent,rect,axis,axis=='x' and px or pz,6) then
   local r=addRoom(s,t,parent.level,rect,f.depth+1)
   link(s,r,parent,'door',px,pz,axis,Rules.DoorWidth)
   r.entrySide=OPP[f.side]
   return r
  end
 end
end
-- Second suite member hangs off the primary on any side but its entry.
local function trySecondary(s,primary,t)
 local def=Modules.Rooms[t]
 local sides=shuffle(NS_DOORS[primary.type] and not s.cruise and {'N','S'} or {'N','E','S','W'},s.rng)
 for _,side in ipairs(sides) do if side~=primary.entrySide then
  for _,size in ipairs(def.sizes) do for _,o in ipairs({{size[1],size[2]},{size[2],size[1]}}) do
   local along,depth=o[1],o[2]
   local offset=0
   if s.cruise and primary.type=='Dining' and (side=='E' or side=='W') then offset=(primary.z2-primary.z1)/2-6 end
   local px,pz,axis=socketAt(primary,side,offset)
   local rect=attach(side,px,pz,along,depth,offset)
   if fits(s,rect,primary.level) and portalFits(s,primary,rect,axis,axis=='x' and px or pz,6) then
    local r=addRoom(s,t,primary.level,rect,primary.graphDepth+1)
    link(s,primary,r,'door',px,pz,axis,Rules.DoorWidth,{suite=true})
    primary.suite=r.name;r.suite=primary.name
    return r
   end
  end end
 end end
end
local function trySuite(s,f,suite)
 local primary=tryRoom(s,f,suite.primary)
 if not primary then return end
 if trySecondary(s,primary,suite.secondary) then s.suites[suite.primary]=true;return primary end
 removeRoom(s,primary);reject(s,'suite secondary did not fit')
end
-- Parallel corridors must leave a room's depth between them, or no room fits.
local ROOM_BAND=24
local function crowded(s,rect,parent)
 local w,d=rect.x2-rect.x1,rect.z2-rect.z1
 if w==d then return false end
 local long=w>d
 local zone={x1=rect.x1-(long and 0 or ROOM_BAND),x2=rect.x2+(long and 0 or ROOM_BAND),z1=rect.z1-(long and ROOM_BAND or 0),z2=rect.z2+(long and ROOM_BAND or 0),level=rect.level}
 for _,o in ipairs(s.plan.rooms) do
  if o~=parent and (o.type=='Hall' or (o.type=='Foyer' and not s.cruise)) and overlaps(o,zone) then reject(s,'hall crowding');return true end
 end
 return false
end
-- Straight hall or junction growing out of an open hall end or a side slot.
local function tryHall(s,f,module)
 local parent=f.room
 local px,pz,axis=socketAt(parent,f.side,f.t)
 local rect=attach(f.side,px,pz,HALL,module.length,0)
 if not fits(s,rect,parent.level) or not portalFits(s,parent,rect,axis,axis=='x' and px or pz,HALL/2) or crowded(s,rect,parent) then return end
 local r=addRoom(s,'Hall',parent.level,rect,f.depth+1)
 link(s,parent,r,'open',px,pz,axis,HALL,{span=HALL})
 hallSockets(s,r,OPP[f.side],0)
 return r
end
-- Upper hall laid along a stair top so one of its side slots meets the opening.
local function tryHallAlong(s,f,module)
 local parent=f.room
 local px,pz,axis=socketAt(parent,f.side,f.t)
 local slots=shuffle(Modules.Slots(module.length),s.rng)
 for _,t in ipairs(slots) do
  local rect=attach(f.side,px,pz,module.length,HALL,t)
  if fits(s,rect,parent.level) and portalFits(s,parent,rect,axis,axis=='x' and px or pz,Modules.Stair.socketWidth/2+1.34) and not crowded(s,rect,parent) then
   local r=addRoom(s,'Hall',parent.level,rect,f.depth+1)
   link(s,r,parent,'open',px,pz,axis,Modules.Stair.socketWidth,{stairAccess=true})
   hallSockets(s,r,OPP[f.side],t)
   return r
  end
 end
end
-- Two-floor stair: reserves the full 24x24 shaft on both levels before committing.
local function tryStair(s,f)
 local parent=f.room;if parent.level~=0 then return end
 local S=Modules.Stair;local entry=OPP[f.side]
 local k;for i=0,3 do if rotateSide('W',0,i)==entry then k=i end end
 local _,t=rotateSide('W',S.socketT,k)
 local px,pz,axis=socketAt(parent,f.side,f.t)
 local rect=attach(f.side,px,pz,S.size,S.size,t)
 if not fits(s,rect,0) then return end
 local upper={x1=rect.x1,x2=rect.x2,z1=rect.z1,z2=rect.z2,level=1}
 for _,o in ipairs(s.plan.rooms) do if overlaps(o,upper) then reject(s,'stair shaft blocked upstairs');return end end
 if not portalFits(s,parent,rect,axis,axis=='x' and px or pz,S.socketWidth/2+1.34) then return end
 -- Keep a second staircase away from the first so the routes can flank.
 local cx,cz=(rect.x1+rect.x2)/2,(rect.z1+rect.z2)/2
 for _,st in ipairs(s.plan.stairs) do if Vector3.new(st.cx-cx,0,st.cz-cz).Magnitude<56 then reject(s,'stairs too close');return end end
 local n=#s.plan.stairs+1
 local low=addRoom(s,'Stair',0,rect,f.depth+1,'L0_Stair_'..n)
 local high=addRoom(s,'Stair',1,upper,f.depth+2,'L1_Stair_'..n)
 link(s,parent,low,'open',px,pz,axis,S.socketWidth,{stairAccess=true})
 local stair={lower=low.name,upper=high.name,cx=cx,cz=cz,k=k,yaw=-k*math.pi/2,index=n}
 local points={}
 for _,p in ipairs(S.waypoints) do local x,z=rotateVec(p[1],p[3],k);table.insert(points,{cx+x,p[2],cz+z}) end
 table.insert(s.plan.edges,{a=low.name,b=high.name,kind='stairs',x=points[1][1],y=0,z=points[1][3],waypoints=points,stair=n})
 for _,pair in ipairs({{low,S.nav.lower},{high,S.nav.upper}}) do
  local x,z=rotateVec(pair[2][1],pair[2][2],k);pair[1].navx=cx+x;pair[1].navz=cz+z;pair[1].stair=n
 end
 table.insert(s.plan.stairs,stair)
 -- The upper opening becomes a socket on the shared frontier.
 local side,ut=rotateSide('W',S.socketT,k)
 addSocket(s,high,side,ut,'stairTop')
 return low
end

-- Growth ---------------------------------------------------------------------
local function consume(s,f)
 for i,o in ipairs(s.frontier) do if o==f then table.remove(s.frontier,i);return end end
end
-- Open run in front of a socket, in 12-stud probes (0..5). Steers corridors into empty space.
local OUT={N={0,-1},S={0,1},E={1,0},W={-1,0}}
local function freeAhead(s,f)
 local px,pz=socketAt(f.room,f.side,f.t);local d=OUT[f.side];local b=s.bounds
 for step=0,4 do
  local cx,cz=px+d[1]*(6+12*step),pz+d[2]*(6+12*step)
  local probe={x1=cx-6,x2=cx+6,z1=cz-6,z2=cz+6,level=f.level}
  if probe.x1<b.x1 or probe.x2>b.x2 or probe.z1<b.z1 or probe.z2>b.z2 then return step end
  for _,o in ipairs(s.plan.rooms) do if overlaps(o,probe) then return step end end
 end
 return 5
end
-- Main path: a straight-ish spine from `from` before any branching.
local PERP={N={'E','W'},S={'E','W'},E={'N'},W={'N'}} -- never turn south, back toward the entrance side
local function spine(s,from,count)
 local f=from;local added=0;local dir=from.side
 local foyer=s.by[s.plan.start]
 while f and added<count do
  local placed
  for _,id in ipairs(if s.varied then shuffle({'Hall48','Hall36','Hall24'},s.rng) else {'Hall48','Hall36','Hall24'}) do -- varied opening lengths per seed
   for _,m in ipairs(Modules.Halls) do if m.id==id and not placed then placed=tryHall(s,f,m) end end
  end
  if not placed then break end
  consume(s,f);added+=1
  -- Bent main corridor: turn 90 degrees through the side slot farthest from the foyer, then keep going that way.
  if (s.turnAt==added or s.turnAt2==added) and added<count and foyer then
   local fx,fz=(foyer.x1+foyer.x2)/2,(foyer.z1+foyer.z2)/2
   local sides=PERP[dir];local side=sides[s.rng:NextInteger(1,#sides)]
   -- Side slots farthest from the foyer first; the very end slots usually lack the 8 studs of shared wall a hall
   -- opening needs, so fall back toward the middle of the piece.
   local slots={}
   for _,o in ipairs(s.frontier) do if o.room==placed and o.class=='roomDoor' and o.side==side then
    local px,pz=socketAt(placed,o.side,o.t);table.insert(slots,{o=o,d=(px-fx)^2+(pz-fz)^2})
   end end
   table.sort(slots,function(a,b) return a.d>b.d end)
   for _,slot in ipairs(slots) do
    for _,id in ipairs({'Hall48','Hall36'}) do
     for _,m in ipairs(Modules.Halls) do if m.id==id and slot then
      local h=tryHall(s,slot.o,m)
      if h then consume(s,slot.o);added+=1;placed=h;dir=side;slot=nil;s.plan.spineTurned=side end
     end end
    end
    if s.plan.spineTurned then break end
   end
  end
  f=nil
  for _,o in ipairs(s.frontier) do if o.room==placed and o.class=='hallEnd' and o.side==dir then f=o end end
 end
 return added
end
-- Corridor skeleton first, so rooms never wall off the main path.
local function corridor(s,level,count)
 local added=0
 for _=1,count*10 do
  if added>=count then break end
  local list={}
  for _,f in ipairs(s.frontier) do if f.level==level and f.tries<MAX_SOCKET_ATTEMPTS then
   local open=freeAhead(s,f)
   if open>=2 or f.class=='stairTop' then
    -- Per-seed corridor style: branchy seeds favour side branches (grid-like), others long straight runs (comb-like).
    local w=if f.class=='stairTop' then 100 elseif f.class=='hallEnd' then 1.5*open*(s.straight or 1) else .25*open*(s.branchy or 1)
    table.insert(list,{w=w/(1+f.tries),f=f})
   end
  end end
  local c=pick(s.rng,list);if not c then break end
  local f=c.f;local placed
  local mods={};for _,m in ipairs(Modules.Halls) do table.insert(mods,{w=m.weight,m=m}) end
  for _=1,#mods do
   local choice,i=pick(s.rng,mods);if not choice then break end;table.remove(mods,i)
   local m=choice.m
   if f.class=='stairTop' then if not m.junction then placed=tryHallAlong(s,f,m) end
   elseif f.class=='roomDoor' then if not m.junction then placed=tryHall(s,f,m) end
   else placed=tryHall(s,f,m) end
   if placed then break end
  end
  if placed then consume(s,f);added+=1 else f.tries+=1 end
 end
 -- Side slots that refused a branch stay available for rooms.
 for _,f in ipairs(s.frontier) do if f.class=='roomDoor' then f.tries=0 end end
 return added
end
-- Tries `place` on each matching open socket (shuffled); consumes the one that works.
local function placeOn(s,level,filter,place)
 local list={}
 for _,f in ipairs(s.frontier) do if f.level==level and filter(f) then table.insert(list,f) end end
 shuffle(list,s.rng)
 table.sort(list,function(a,b) return a.depth>b.depth end)
 for _,f in ipairs(list) do if place(f) then consume(s,f);return true end end
 return false
end
local function slot(f) return f.class=='roomDoor' end
local function fillRooms(s,level,target)
 local banned={}
 while s.roomCount[level]<target do
  local types={}
  for t in pairs(Modules.Rooms) do if not banned[t] then
   local w=typeWeight(s,t,level,{name=''},4);if w>0 then table.insert(types,{w=w,t=t}) end
  end end
  table.sort(types,function(a,b) return a.t<b.t end)
  local c=pick(s.rng,types);if not c then return false end
  local placed=placeOn(s,level,function(f) return slot(f) or (f.class=='hallEnd' and s.hallCount[level]>=2) end,function(f)
   if typeWeight(s,c.t,level,f.room,f.depth)<=0 then return false end
   return tryRoom(s,f,c.t)
  end)
  if not placed then banned[c.t]=true end
 end
 return true
end
local function grow(s,level,target)
 local hallTarget=math.max(2,math.floor(s.scale.halls*(level==0 and 1 or .6)*(s.hallMul or 1)+.5))
 -- Main path first: from the foyer on the ground floor, from each stair top upstairs.
 local roots={}
 for _,f in ipairs(s.frontier) do if f.level==level and ((level==0 and f.room.name==s.plan.start and f.side==(s.rootSide or 'N')) or f.class=='stairTop') then table.insert(roots,f) end end
 for _,f in ipairs(roots) do
  if f.class=='stairTop' then
   local placed
   for _,m in ipairs(Modules.Halls) do if not placed and not m.junction then placed=tryHallAlong(s,f,m) end end
   if placed then consume(s,f) end
  else spine(s,f,level==0 and (s.spineLength or 2) or 1) end
 end
 for round=1,5 do
  corridor(s,level,round==1 and math.max(0,hallTarget-s.hallCount[level]) or 2)
  if level==0 then
   while #s.plan.stairs<s.stairsNeeded do
    if not placeOn(s,0,function(f) return slot(f) and f.depth>=2 end,function(f) return tryStair(s,f) end) then break end
   end
  end
  for _,suite in ipairs(Modules.Suites) do if suite.floor==level and not s.suites[suite.primary] then
   placeOn(s,level,function(f) return slot(f) and f.depth+1>=suite.minDepth end,function(f) return trySuite(s,f,suite) end)
  end end
  fillRooms(s,level,target)
  local done=s.roomCount[level]>=target and (level~=0 or #s.plan.stairs>=s.stairsNeeded)
  for _,suite in ipairs(Modules.Suites) do if suite.floor==level and not s.suites[suite.primary] then done=false end end
  if done then return true end
 end
 return false
end
-- Upper floor: grows from each stair top over the ground-floor footprint. Halls
-- and rooms reuse the rectangles below, so every upper room is fully supported
-- and wall lines stay continuous between floors. Two stairs that reach the same
-- upper halls form a vertical loop.
local function upperFloor(s,target)
 local up={};local queue={};local lowerEdges={}
 for _,e in ipairs(s.plan.edges) do if e.y==0 and e.kind~='stairs' then table.insert(lowerEdges,e) end end
 local function other(e,name) return (e.a==name and e.b) or (e.b==name and e.a) end
 local function copy(r,t)
  local c=addRoom(s,t,1,r,r.graphDepth+1);up[r.name]=c;return c
 end
 for _,st in ipairs(s.plan.stairs) do
  local high=s.by[st.upper]
  for _,e in ipairs(lowerEdges) do if e.stairAccess and (e.a==st.lower or e.b==st.lower) then
   local hall=s.by[other(e,st.lower)]
   if hall and hall.type=='Hall' then
    if not up[hall.name] then copy(hall,'Hall');table.insert(queue,hall) end
    link(s,up[hall.name],high,'open',e.x,e.z,e.axis,e.width,{stairAccess=true})
   end
  end end
 end
 if #queue==0 then return false end
 -- Cruise keeps the full longitudinal upper spine so adjacent cabins never detour via the lower deck.
 local hallBudget=if s.cruise then s.hallCount[0] else math.max(#queue,math.floor(s.hallCount[0]*.75+.5))
 local head=1
 while queue[head] do
  local h=queue[head];head+=1
  for _,e in ipairs(shuffle(table.clone(lowerEdges),s.rng)) do
   local o=other(e,h.name);local r=o and s.by[o]
   if r and r.type=='Hall' and e.kind=='open' and not e.stairAccess then
    if not up[r.name] and s.hallCount[1]<hallBudget then copy(r,'Hall');table.insert(queue,r) end
    if up[r.name] and not e.copied then e.copied=true;link(s,up[h.name],up[r.name],'open',e.x,e.z,e.axis,e.width,{span=e.span}) end
   end
  end
 end
 -- Rooms that open onto a copied hall can be copied with the same doorway.
 local candidates={}
 for _,e in ipairs(lowerEdges) do if e.kind=='door' and not e.loop and not e.suite then
  for _,pair in ipairs({{e.a,e.b},{e.b,e.a}}) do
   local hall,room=s.by[pair[1]],s.by[pair[2]]
   if hall and room and hall.type=='Hall' and up[hall.name] and room.type~='Hall' and room.type~='Stair' and room.type~='Foyer' then
    table.insert(candidates,{room=room,hall=hall,edge=e})
   end
  end
 end end
 shuffle(candidates,s.rng)
 local function free(r) return not up[r.name] and r.type~='Hall' and r.type~='Stair' and r.type~='Foyer' end
 local function doorway(c,t)
  local u=copy(c.room,t);link(s,u,up[c.hall.name],'door',c.edge.x,c.edge.z,c.edge.axis,Rules.DoorWidth);u.entrySide=true;return u
 end
 -- Required suites first, over two ground rooms that share a wall.
 for _,suite in ipairs(Modules.Suites) do if suite.floor==1 then
  for _,c in ipairs(candidates) do if free(c.room) then
   local mate,axis,lo,hi,wall
   for _,o in ipairs(s.plan.rooms) do if o.level==0 and o~=c.room and free(o) then
    local a,b=c.room,o
    local ax,cc
    if a.x2==b.x1 or b.x2==a.x1 then ax='z';cc=a.x2==b.x1 and a.x2 or a.x1
    elseif a.z2==b.z1 or b.z2==a.z1 then ax='x';cc=a.z2==b.z1 and a.z2 or a.z1 end
    if ax then local l,h=sharedSpan(a,b,ax);if h-l>=20 then mate,axis,lo,hi,wall=o,ax,l,h,cc;break end end
   end end
   if mate then
    local primary=doorway(c,suite.primary);local second=copy(mate,suite.secondary)
    local v=(lo+hi)/2
    local x,z=if axis=='x' then v else wall,if axis=='x' then wall else v
    link(s,primary,second,'door',x,z,axis,Rules.DoorWidth,{suite=true})
    primary.suite=second.name;second.suite=primary.name;s.suites[suite.primary]=true
    break
   end
  end end
 end end
 -- Remaining rooms take upper-floor types by weight.
 for _,c in ipairs(candidates) do
  if s.roomCount[1]>=target then break end
  if free(c.room) then
   local types={}
   for t in pairs(Modules.Rooms) do local w=typeWeight(s,t,1,up[c.hall.name],c.hall.graphDepth+1);if w>0 then table.insert(types,{w=w,t=t}) end end
   table.sort(types,function(a,b) return a.t<b.t end)
   local choice=pick(s.rng,types)
   if choice then doorway(c,choice.t) end
  end
 end
 return s.roomCount[1]>=math.min(target,4)
end
-- Empty leaf halls are pruned so every corridor leads somewhere.
local function prune(s)
 local changed=true
 while changed do
  changed=false
  for _,r in ipairs(table.clone(s.plan.rooms)) do if r.type=='Hall' then
   local degree,stair=0,false
   for _,e in ipairs(s.plan.edges) do if e.a==r.name or e.b==r.name then degree+=1;stair=stair or e.stairAccess end end
   if degree<=1 and not stair then removeRoom(s,r);changed=true end
  end end
 end
end
-- Loop pass: extra doors between touching rooms, and open links between touching halls.
local function connectLoops(s)
 local rooms=s.plan.rooms;local made=0
 local linked={}
 for _,e in ipairs(s.plan.edges) do linked[e.a..'|'..e.b]=true;linked[e.b..'|'..e.a]=true end
 local pairsList={}
 for i,a in ipairs(rooms) do for j=i+1,#rooms do local b=rooms[j]
  if a.level==b.level and not linked[a.name..'|'..b.name] then
   local axis,c
   if a.x2==b.x1 or b.x2==a.x1 then axis='z';c=a.x2==b.x1 and a.x2 or a.x1
   elseif a.z2==b.z1 or b.z2==a.z1 then axis='x';c=a.z2==b.z1 and a.z2 or a.z1 end
   if axis then
    local lo,hi=sharedSpan(a,b,axis)
    if hi-lo>=20 then table.insert(pairsList,{a=a,b=b,axis=axis,c=c,lo=lo,hi=hi}) end
   end
  end
 end end
 shuffle(pairsList,s.rng)
 local function eligible(r) return r.type~='Stair' and r.type~='Bath' and r.type~='Foyer' and not NS_DOORS[r.type] end
 for _,p in ipairs(pairsList) do
  local a,b=p.a,p.b
  if not eligible(a) or not eligible(b) then continue end
  local hallPair=a.type=='Hall' and b.type=='Hall'
  if not hallPair and made>=s.scale.loops then continue end
  if hallPair and p.hi-p.lo<HALL then continue end
  local v=4*math.floor((p.lo+p.hi)/8)
  if hallPair or v-6<p.lo or v+6>p.hi then v=(p.lo+p.hi)/2 end
  local x,z=if p.axis=='x' then v else p.c,if p.axis=='x' then p.c else v
  if hallPair then link(s,a,b,'open',x,z,p.axis,HALL,{span=math.min(HALL,p.hi-p.lo),loop=true})
  else link(s,a,b,'door',x,z,p.axis,Rules.DoorWidth,{loop=true});made+=1 end
 end
 s.plan.loopDoors=made
end

-- Post-processing shared with the original generator ---------------------------
local function finish(s)
 local plan=s.plan;local rng=s.rng;local by=s.by
 for _,r in ipairs(plan.rooms) do if r.type=='Dining' then r.navx=(r.x1+r.x2)/2;r.navz=r.z2-5 end end
 -- Exterior status derives from actual neighbours, never just a room label.
 for _,r in ipairs(plan.rooms) do
  r.exterior=false
  for _,side in ipairs(SIDES) do
   local covered=0
   for _,o in ipairs(plan.rooms) do if o~=r and o.level==r.level then
    if (side=='N' and o.z2==r.z1) or (side=='S' and o.z1==r.z2) then covered+=math.max(0,math.min(r.x2,o.x2)-math.max(r.x1,o.x1)) end
    if (side=='W' and o.x2==r.x1) or (side=='E' and o.x1==r.x2) then covered+=math.max(0,math.min(r.z2,o.z2)-math.max(r.z1,o.z1)) end
   end end
   local length=if side=='N' or side=='S' then r.x2-r.x1 else r.z2-r.z1
   if covered<length then r.exterior=true end
  end
 end
 for _,r in ipairs(plan.rooms) do if r.type=='Conservatory' and not r.exterior then
  for _,o in ipairs(plan.rooms) do if o.level==0 and o.exterior and o.type=='Parlor' then r.type,o.type=o.type,r.type;break end end
  if not r.exterior and r.type=='Conservatory' then r.type='Gallery' end
 end end
 -- Same lock safety rule as the original: removing locked rooms leaves all open rooms reachable.
 local order={};for _,r in ipairs(plan.rooms) do if Rules.Types[r.type].zone~='hall' and r.type~='Foyer' and not r.suite then table.insert(order,r) end end
 shuffle(order,rng);local closed={}
 for _,r in ipairs(order) do
  if #plan.locks==Rules.LockCount then break end
  closed[r.name]=true;local seen=P.Reach(plan,closed);local safe=true
  for _,o in ipairs(plan.rooms) do if not closed[o.name] and not seen[o.name] then safe=false;break end end
  local entries={}
  for _,e in ipairs(plan.edges) do if e.kind=='door' and not e.boarded and (e.a==r.name or e.b==r.name) then
   local other=if e.a==r.name then e.b else e.a
   if seen[other] and Rules.Types[by[other].type].zone=='hall' then table.insert(entries,e) end
  end end
  if safe and #entries>0 then
   local chosen=entries[rng:NextInteger(1,#entries)];chosen.locked=r.name
   table.insert(plan.locks,{room=r.name,door=chosen})
   for _,e in ipairs(plan.edges) do if e~=chosen and e.kind=='door' and (e.a==r.name or e.b==r.name) then e.boarded=true end end
  else closed[r.name]=nil end
 end
 local seen=P.Reach(plan,closed);local candidates={}
 for _,r in ipairs(plan.rooms) do if seen[r.name] and Rules.Types[r.type].zone~='hall' and r.type~='Foyer' and r.type~='Pantry' and r.type~='Storage' then table.insert(candidates,r.name) end end
 shuffle(candidates,rng)
 for i=1,Rules.KeyCount do plan.keyRooms[i]=candidates[(i-1)%#candidates+1] end
 -- Horror metadata rides on each room for pacing and the AI.
 for _,r in ipairs(plan.rooms) do
  local def=Modules.Rooms[r.type]
  if def then r.danger=def.danger;r.visibility=def.visibility;r.hiding=def.hiding;r.loot=def.loot;r.spawnRating=def.spawn;r.search=def.search or .5;r.chase=def.chase or .5 end
 end
 local foyer=by[plan.start]
 local ex=(foyer.x1+foyer.x2)/2
 plan.entrance={x=ex,z=foyer.z2,level=0,width=12}
 plan.closed=closed;plan.spawn={ex,3,foyer.z2-8};plan.navigationVersion=3
 plan.length=foyer.z2
 local width=0;for _,r in ipairs(plan.rooms) do width=math.max(width,math.abs(r.x1),math.abs(r.x2)) end
 plan.width=width
end

local function layout(seed,attempt,mapKind,sizeClass)
 local s=newState(seed,attempt,mapKind,sizeClass)
 local F=Modules.Foyer
 -- Early attempts move the foyer (and so the entrance and spawn) off-centre, so the building grows lopsided in
 -- different directions; later attempts keep the original centred foyer so success stays at its old rate.
 local fx=0
 if mapKind~='Cruise' and attempt<24 and s.rng:NextNumber()<.7 then
  fx=4*math.floor(s.rng:NextNumber(-.34,.34)*s.scale.width/4+.5)
 end
 s.plan.foyerOffset=fx
 local foyer=addRoom(s,'Foyer',0,{x1=fx-F.w/2,x2=fx+F.w/2,z1=s.foyerZ2-F.d,z2=s.foyerZ2},0,'L0_Starter')
 addSocket(s,foyer,'N',0,'hallEnd')
 addSocket(s,foyer,'E',0,'hallEnd');addSocket(s,foyer,'W',0,'hallEnd')
 s.frontier[2].tries=1;s.frontier[3].tries=1
 -- The opening differs per seed: the main corridor leaves the foyer north, east or west (north most often)
 -- and runs one to three hall pieces before branching, so the view from spawn is not the same every map.
 -- Varied openings on early attempts; later attempts keep the original two-piece north spine so success stays
 -- at its old rate. East/west openings fail often (the foyer hugs the south edge), so they only get early tries.
 if not s.cruise and attempt<24 then
  s.rootSide=if attempt<8 and s.rng:NextNumber()<.5 then ({'E','W'})[s.rng:NextInteger(1,2)] else 'N'
  s.spineLength=s.rng:NextInteger(2,3);s.varied=true
  if s.rootSide=='N' and s.rng:NextNumber()<.55 then
   s.turnAt=s.rng:NextInteger(1,2);s.spineLength=math.max(s.spineLength,s.turnAt+1)
   -- zig-zag: after one straight piece in the new direction, turn again
   if s.rng:NextNumber()<.4 then s.turnAt2=s.turnAt+2;s.spineLength=math.max(s.spineLength,s.turnAt2+1) end
  end
  local style=s.rng:NextInteger(1,3) -- 1 comb (long straight corridors), 2 balanced, 3 grid (many cross corridors)
  s.branchy=({.35,1,2.6})[style];s.straight=({1.6,1,.7})[style];s.hallMul=({.85,1,1.3})[s.rng:NextInteger(1,3)]
  s.plan.layoutStyle=({'comb','balanced','grid'})[style]
  for _,f in ipairs(s.frontier) do f.tries=if f.side==s.rootSide then 0 else 1 end
 end
 if s.cruise then
  -- A transverse spine behind the +Z entrance creates two cabin bands.
  local entry=s.frontier[1]
  local junction=assert(tryHall(s,entry,{id='CruiseJunction',length=HALL,junction=true}))
  consume(s,entry)
  for _,side in ipairs({'E','W'})do
   local from
   for _,f in ipairs(s.frontier)do if f.room==junction and f.side==side then from=f;break end end
   if from then spine(s,from,3)end
  end
 end
 local scale=s.scale
 local f1=scale.f1+s.rng:NextInteger(-1,1);local f2=scale.f2+s.rng:NextInteger(-1,1)
 if s.cruise then local small=scale.f1<=10;f1+=s.rng:NextInteger(small and 1 or 3,small and 4 or 6);f2+=s.rng:NextInteger(small and 1 or 2,small and 3 or 5) end -- more, and more varied, cabins per deck
 local ok1=grow(s,0,f1)
 if #s.plan.stairs<s.stairsNeeded then return nil,'vertical transition not placed',s end
 if not s.suites.Dining then return nil,'required kitchen/dining missing',s end
 if not ok1 then return nil,'ground floor incomplete',s end
 local ok2=upperFloor(s,f2)
 for _,suite in ipairs(Modules.Suites) do if not s.suites[suite.primary] then return nil,'required '..suite.primary..' suite missing',s end end
 if not ok2 then return nil,'upper floor incomplete',s end
 prune(s)
 connectLoops(s)
 finish(s)
 s.plan.targets={f1=f1,f2=f2,stairs=s.stairsNeeded}
 if s.cruise then
  local x1,x2,z1,z2=math.huge,-math.huge,math.huge,-math.huge
  for _,r in ipairs(s.plan.rooms)do x1=math.min(x1,r.x1);x2=math.max(x2,r.x2);z1=math.min(z1,r.z1);z2=math.max(z2,r.z2)end
  local aspect=(x2-x1)/(z2-z1)
  if aspect<2.4 or aspect>3.1 then return nil,'Cruise aspect ratio outside target band',s end
  s.plan.cruiseFootprint={width=x2-x1,depth=z2-z1,aspect=aspect}
 end
 return s.plan
end
-- This does not write to Modules or Profiles: generating a Mall cannot change
-- a later Mansion/Dungeon/Birthday. Vertical rise and door slab size stay fixed.
-- Builder consumes each stair's horizontalScale for the authored physical bay.
local function applyGeometry(plan,mapKind)
 local scale=if mapKind=='Mall' then MALL_HORIZONTAL_SCALE else 1
 plan.horizontalScale=scale
 plan.openAreaMultiplier=if mapKind=='Mall' then MALL_AREA_MULTIPLIER else 1
 plan.mainHallWidth=HALL*scale
 if scale==1 or plan.generationFailure then return plan end
 for _,r in ipairs(plan.rooms) do
  r.x1*=scale;r.x2*=scale;r.z1*=scale;r.z2*=scale
  if r.navx then r.navx*=scale end
  if r.navz then r.navz*=scale end
 end
 local scaledPoints={}
 for _,e in ipairs(plan.edges) do
  e.x*=scale;e.z*=scale
  -- Working doors match the existing kit and interaction system. Open portals
  -- and stair entrances grow with their halls; no additional door mechanics.
  if e.kind~='door' then
   if e.width then e.width*=scale end
   if e.span then e.span*=scale end
  end
  for _,point in ipairs(e.waypoints or {}) do
   if not scaledPoints[point] then
    point[1]*=scale;point[3]*=scale;scaledPoints[point]=true
   end
  end
 end
 for _,st in ipairs(plan.stairs) do
  st.cx*=scale;st.cz*=scale;st.horizontalScale=scale
 end
 if plan.entrance then
  plan.entrance.x*=scale;plan.entrance.z*=scale;plan.entrance.width*=scale
 end
 plan.spawn[1]*=scale;plan.spawn[3]*=scale
 plan.width*=scale;plan.length*=scale
 return plan
end
function P.Generate(seed,players,mapKind,sizeClass)
 mapKind,sizeClass=Profiles.Select(seed,mapKind,sizeClass)
 assert(Profiles.Scale[sizeClass],'unknown size class')
 local reasons={}
 local attemptLimit=if mapKind=='Cruise' then 96 else MAX_LAYOUT_ATTEMPTS
 for attempt=0,attemptLimit-1 do
  local plan,why,state=layout(seed,attempt,mapKind,sizeClass)
  P.LastFailedState=state
  if plan then plan.layoutFailures=reasons;return Profiles.Apply(applyGeometry(plan,mapKind),mapKind,sizeClass) end
  table.insert(reasons,why)
 end
 -- Exhausted: return an explicit failed plan so validation reports the exact reasons.
 local failed={seed=seed,shape='socket',generatorVersion=P.Version,rooms={},edges={},start='L0_Starter',locks={},keyRooms={},stairs={},closed={},
  spawn={0,3,52},length=60,width=0,generationFailure=table.concat(reasons,'; '),layoutFailures=reasons}
 return Profiles.Apply(failed,mapKind,sizeClass)
end
function P.Hash(plan)
 local fields={plan.shape,tostring(plan.seed),plan.mapKind or 'Mansion',plan.sizeClass or 'Medium'}
 for _,r in ipairs(plan.rooms) do table.insert(fields,table.concat({r.name,r.type,r.level,r.x1,r.x2,r.z1,r.z2,r.theme,r.navx or '',r.navz or '',r.purpose or ''},':')) end
 for _,e in ipairs(plan.edges) do table.insert(fields,table.concat({e.a,e.b,e.kind,e.x,e.z,tostring(e.locked),tostring(e.boarded)},':')) end
 local hash=2166136261
 for _,s in ipairs(fields) do for i=1,#s do hash=bit32.bxor(hash,string.byte(s,i));hash=(hash*16777619)%4294967296 end end
 return string.format('%08x',hash)
end
-- Prefers diverse rooms, real loops and two vertical routes; penalises corridor-heavy plans.
function P.Score(plan)
 local types={};local hallArea,total=0,0;local loops=0
 for _,r in ipairs(plan.rooms) do types[r.type]=true;local area=(r.x2-r.x1)*(r.z2-r.z1);total+=area;if r.type=='Hall' then hallArea+=area end end
 for _,e in ipairs(plan.edges) do if e.loop and not e.boarded then loops+=1 end end
 local diversity=0;for _ in pairs(types) do diversity+=1 end
 return diversity*100-hallArea/math.max(1,total)*200+math.min(loops,6)*25+#(plan.stairs or {})*40
end
function P.Best(seed,count,validate,players,mapKind,sizeClass)
 local best,bestScore
 for i=0,count-1 do local p=P.Generate(seed+i*7919,players,mapKind,sizeClass);local ok=validate(p)
  if ok then local score=P.Score(p);if not bestScore or score>bestScore then best,bestScore=p,score end end
 end
 return best or P.Generate(seed,players,mapKind,sizeClass)
end
return P