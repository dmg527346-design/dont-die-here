local R=require(script.Parent.Rules)
local U=require(script.Parent.KitUtil)
local F=require(script.Parent.Furnisher)
local M=require(script.Parent.MapLighting)
local A=require(script.Parent.ArtDressing)
local B={}
function B.BindKeyFollowers(mansion)
 for _,key in ipairs(mansion.Interactive:GetChildren()) do if key:GetAttribute('Kind')=='key' then
  local moverName=key:GetAttribute('DrawerMover');local offset=key:GetAttribute('DrawerOffset')
  local mover=moverName and mansion.Interactive:FindFirstChild(moverName)
  if mover and mover.PrimaryPart and offset then
   mover.PrimaryPart:GetPropertyChangedSignal('CFrame'):Connect(function() if key.PrimaryPart then key.PrimaryPart.CFrame=mover.PrimaryPart.CFrame*offset end end)
  end
 end end
end
local function folders(m)
 for _,n in ipairs({'Architecture','Collision','Furniture','Interactive','Closets','Lights','KeyDoors'}) do local f=Instance.new('Folder');f.Name=n;f.Parent=m end
end
function B.Build(plan,kit,parent)
 local mansion
 local ok,result=xpcall(function()
 local started=os.clock();mansion=Instance.new('Model');mansion.Name='MansionBuild';folders(mansion)
 mansion:SetAttribute('Ready',false);mansion:SetAttribute('Seed',plan.seed);mansion:SetAttribute('Shape',plan.shape)
 mansion:SetAttribute('MapKind',plan.mapKind);mansion:SetAttribute('SizeClass',plan.sizeClass)
 mansion:SetAttribute('SpawnPosition',Vector3.new(unpack(plan.spawn)))
 mansion.Parent=parent or workspace
 local n=0
 local function batch() n+=1;if n%R.BatchSize==0 then task.wait() end end
 local function clone(name,cf,target,theme,x,y,z)
  local m=U.Clone(kit,name,cf,target,theme)
  if x then U.Stretch(m,x,y or 1,z or 1) end
  batch();return m
 end
 local function colliders(m,name)
  -- The collision owner retains all blocking parts; render meshes remain independently testable.
  for _,p in ipairs(m:GetChildren()) do if p:IsA('BasePart') and p~=m.PrimaryPart then
   if (m.Name=='Wall' and p.Name~='Wallpaper') or p:GetAttribute('Surface')=='trim' then p.CanCollide=false;continue end
   local c=kit.Table.PrimaryPart:Clone();c.Name=name or p.Name;c.Size=p.Size;c.CFrame=p.CFrame;c.Transparency=1;c.CanQuery=true;c.CanCollide=p.CanCollide;c.Material=p.Material;c.Parent=mansion.Collision
   p.CanCollide=false
  end end
 end
 for _,r in ipairs(plan.rooms) do
  local cf=CFrame.new((r.x1+r.x2)/2,r.level*16,(r.z1+r.z2)/2);local theme=R.Themes[r.theme]
  if r.type~='Stair' or r.level==0 then
   local floor=clone('Floor',cf,mansion.Architecture,theme,(r.x2-r.x1)/4,1,(r.z2-r.z1)/4);floor.Name=r.name..'_Floor';A.Floor(plan,r,floor);colliders(floor,'Floor')
  else
   -- Upper landing strip beside the open stair shaft, in the stair module's frame.
   local st=plan.stairs and plan.stairs[r.stair]
   local horizontalScale=if st then st.horizontalScale or 1 else 1
   local patch=if st then CFrame.new(st.cx,16,st.cz)*CFrame.Angles(0,st.yaw,0)*CFrame.new(-7.6*horizontalScale,0,0) else CFrame.new(10.4,16,-18)
   local floor=clone('Floor',patch,mansion.Architecture,theme,2.2*horizontalScale,1,6*horizontalScale);A.Floor(plan,r,floor);colliders(floor,'Floor')
  end
  if r.type~='Stair' or r.level==1 then
   local ceiling=clone('Ceiling',cf,mansion.Architecture,theme,(r.x2-r.x1)/4,1,(r.z2-r.z1)/4);ceiling.Name=r.name..'_Ceiling';colliders(ceiling,'Ceiling')
  end
  if r.level==1 then
   local roof=clone('Floor',cf*CFrame.new(0,16,0),mansion.Architecture,theme,(r.x2-r.x1)/4,1,(r.z2-r.z1)/4)
   roof.Name=r.name..'_Roof';for _,p in ipairs(roof:GetChildren()) do if p:IsA('BasePart') then p:SetAttribute('Roof',true);p.CanCollide=false;p.MaterialVariant='';p.Material=Enum.Material.Slate;p.Color=Color3.fromRGB(64,68,71) end end
  end
 end
 -- Collect coincident wall runs once, split by every room boundary and portal bay.
 local lines={}
 local function line(r,axis,c,lo,hi)
  local key=r.level..':'..axis..':'..c
  local l=lines[key];if not l then l={level=r.level,axis=axis,c=c,runs={},cuts={}};lines[key]=l end
  table.insert(l.runs,{lo=lo,hi=hi,room=r})
 end
 for _,r in ipairs(plan.rooms) do
  line(r,'x',r.z1,r.x1,r.x2);line(r,'x',r.z2,r.x1,r.x2);line(r,'z',r.x1,r.z1,r.z2);line(r,'z',r.x2,r.z1,r.z2)
 end
 for _,e in ipairs(plan.edges) do if e.kind~='stairs' then
  local key=math.floor(e.y/16)..':'..e.axis..':'..(e.axis=='x' and e.z or e.x)
  local l=assert(lines[key],'portal has no wall run')
  local v=e.axis=='x' and e.x or e.z
  local span=(e.width or R.DoorWidth)+2*(R.DoorWidth/6)
  if e.kind=='open' and e.a:find('Cross') or e.kind=='open' and e.b:find('Cross') then
   local a,b
   for _,r in ipairs(plan.rooms) do if r.name==e.a then a=r elseif r.name==e.b then b=r end end
   span=if e.axis=='x' then math.min(a.x2,b.x2)-math.max(a.x1,b.x1) else math.min(a.z2,b.z2)-math.max(a.z1,b.z1)
  end
  if e.span then span=e.span end
  table.insert(l.cuts,{lo=v-span/2,hi=v+span/2,edge=e})
 end end
 -- Front entry is a proper open bay in the exterior shell.
 local entrance=plan.entrance or {x=0,z=plan.length,width=12}
 table.insert(lines['0:x:'..entrance.z].cuts,{lo=entrance.x-entrance.width/2,hi=entrance.x+entrance.width/2,entrance=true})
 local keys={};for k in pairs(lines) do table.insert(keys,k) end;table.sort(keys)
 plan.wallSegments={}
 for _,r in ipairs(plan.rooms) do r.windowKeepouts={} end
 for _,key in ipairs(keys) do
  local l=lines[key];local endpoints={};local seen={}
  local function endpoint(v) if not seen[v] then seen[v]=true;table.insert(endpoints,v) end end
  for _,a in ipairs(l.runs) do endpoint(a.lo);endpoint(a.hi) end
  for _,a in ipairs(l.cuts) do endpoint(a.lo);endpoint(a.hi) end
  table.sort(endpoints)
  for i=1,#endpoints-1 do
   local lo,hi=endpoints[i],endpoints[i+1];local mid=(lo+hi)/2;local owners={};local cut
   for _,a in ipairs(l.runs) do if mid>a.lo and mid<a.hi then table.insert(owners,a.room) end end
   for _,a in ipairs(l.cuts) do if mid>a.lo and mid<a.hi then cut=a;break end end
   if #owners>0 and not cut then
    local length=hi-lo
    local cf=if l.axis=='x' then CFrame.new(mid,l.level*16,l.c) else CFrame.new(l.c,l.level*16,mid)*CFrame.Angles(0,math.pi/2,0)
    local window=#owners==1 and length>=12 and owners[1].type~='Stair' and owners[1].type~='Hall'
    -- Mall shop fronts reuse the existing blocking window kit. Cuts are already
    -- removed above, so glass cannot cover a working doorway or open hall bay.
    local shop
    if plan.mapKind=='Mall' and #owners==2 and length>=12 then
     local a,b=owners[1],owners[2]
     if a.type=='Hall' and b.type~='Hall' and b.type~='Stair' then shop=b
     elseif b.type=='Hall' and a.type~='Hall' and a.type~='Stair' then shop=a end
    end
    local windowOwner=shop or owners[1]
    if shop then window=true end
    -- One window wall per room keeps solid exterior walls for tall furniture.
    if window and not shop and plan.generatorVersion then
     if owners[1].windowWall and owners[1].windowWall~=key then window=false else owners[1].windowWall=key end
    end
    if window then
     local m=clone('WallWindow',cf,mansion.Architecture,R.Themes[windowOwner.theme],length/8,16/14);colliders(m,'Wall')
     local glass=m:FindFirstChild('Glass')
     if glass then local barrier=glass:Clone();barrier.Name='WindowBarrier';barrier.Transparency=1;barrier.Size=Vector3.new(glass.Size.X,glass.Size.Y,1.4);barrier.CanCollide=true;barrier.CanQuery=true;barrier.Parent=mansion.Collision end
     local r=windowOwner
     table.insert(r.windowKeepouts,if l.axis=='x' then {x=mid,z=math.clamp(l.c,r.z1+1.5,r.z2-1.5),w=length*.75,d=3} else {x=math.clamp(l.c,r.x1+1.5,r.x2-1.5),z=mid,w=3,d=length*.75})
    else
     local m=clone('Wall',cf,mansion.Architecture,R.Themes[owners[1].theme],length/4,16/14);colliders(m,'Wall')
     table.insert(plan.wallSegments,{cf=cf,length=length,room=owners[1].name})
    end
   end
  end
  for _,a in ipairs(l.cuts) do
   local v=(a.lo+a.hi)/2;local cf=if l.axis=='x' then CFrame.new(v,l.level*16,l.c) else CFrame.new(l.c,l.level*16,v)*CFrame.Angles(0,math.pi/2,0)
   local theme=R.Themes[plan.rooms[1].theme]
   local cap=kit.Wall.Wallpaper:Clone();cap.Name='PortalUpperFrieze';cap.Size=Vector3.new(a.hi-a.lo,1.94,1.4);cap.CFrame=cf*CFrame.new(0,14.97,0) --[[top 0.06 under the upstairs floor so it never shows through the floor seam]];cap.Color=theme.wall;cap.Material=theme.wallMaterial or Enum.Material.Plaster;cap.Parent=mansion.Architecture
   local collider=cap:Clone();collider.Transparency=1;collider.Parent=mansion.Collision;cap.CanCollide=false
   if a.edge and a.edge.kind=='open' or a.entrance then continue end
   local m=clone('WallDoor',cf,mansion.Architecture,theme,R.DoorWidth/6);colliders(m,'DoorFrame')
   local threshold=clone('Floor',cf*CFrame.new(0,-.015,0),mansion.Architecture,theme,(a.hi-a.lo)/4,.2,.35)
   threshold.Name='DoorThreshold';A.Floor(plan,{name='DoorThreshold',type='Hall'},threshold);colliders(threshold,'DoorThreshold')
   if a.edge.boarded then
    local b=clone('Board',cf,mansion.KeyDoors,theme,R.DoorWidth/6);colliders(b,'Board')
   end
  end
 end
 -- A full-width traversable stair ramp below separate visible treads. The
 -- authored bay (centre 18,-18) is placed at each generated stair's frame.
 local theme=R.Themes[plan.rooms[1].theme]
 for _,st in ipairs(plan.stairs or {{cx=18,cz=-18,yaw=0}}) do
  local horizontalScale=st.horizontalScale or 1
  local base=CFrame.new(st.cx,0,st.cz)*CFrame.Angles(0,st.yaw or 0,0)
  local function at(x,y,z) return base*CFrame.new((x-18)*horizontalScale,y,(z+18)*horizontalScale) end
  for flight=1,2 do
   for i=1,12 do
    local cf=if flight==1 then at(18,(i-1)*2/3,-24+i-.5) else at(26,8+(i-1)*2/3,-12-i+.5)
    local m=clone('StairStep',flight==2 and cf*CFrame.Angles(0,math.pi,0) or cf,mansion.Architecture,theme,.8*horizontalScale,2/3,horizontalScale)
    for _,p in ipairs(m:GetChildren()) do if p:IsA('BasePart') then p.CanCollide=false end end
   end
   -- Rise stays 8 studs per flight; increasing run lowers slope while matching
   -- the scaled tread centers and landings (simple model scaling tilts wrong).
   local rise,run=8,12*horizontalScale
   local slope=math.atan(rise/run)
   local cf=if flight==1 then at(18,4,-18)*CFrame.Angles(-slope,0,0) else at(26,12,-18)*CFrame.Angles(slope,0,0)
   local ramp=clone('Floor',cf,mansion.Architecture,theme,1.6*horizontalScale,.4,math.sqrt(run*run+rise*rise)/4)
   ramp.Name='StairRamp';colliders(ramp,'StairRamp')
   for _,p in ipairs(ramp:GetChildren()) do if p:IsA('BasePart') then p.Transparency=1 end end
  end
  for _,p in ipairs({{22,8,-9.4},{22,16,-26.6}}) do local landing=clone('Landing',at(p[1],p[2],p[3]),mansion.Architecture,theme,1.8*horizontalScale,1,1.3*horizontalScale);A.Floor(plan,{name='StairLanding_'..p[2],type='Stair'},landing);colliders(landing,'Landing') end
 end
 -- Doors are selected in the plan; Builder only instantiates that decision.
 local rng=Random.new(plan.seed+3329);local door=0
 local by={};for _,r in ipairs(plan.rooms) do by[r.name]=r end
 for _,e in ipairs(plan.edges) do if e.kind=='door' and not e.boarded and (e.locked or rng:NextNumber()<R.DoorChance) then
  door+=1;local a,b=by[e.a],by[e.b];local into=if R.Types[b.type].zone=='hall' then a else b
  local direction=Vector3.new((into.x1+into.x2)/2-e.x,0,(into.z1+into.z2)/2-e.z)
  local cf=CFrame.lookAt(Vector3.new(e.x,e.y,e.z),Vector3.new(e.x,e.y,e.z)+direction)
  -- Axis-aligned hinge so the leaf fills precisely the 6-stud hole.
  if e.axis=='x' then cf=CFrame.new(e.x,e.y,e.z)*CFrame.Angles(0,into.z1>=e.z and math.pi or 0,0)
  else cf=CFrame.new(e.x,e.y,e.z)*CFrame.Angles(0,into.x1>=e.x and -math.pi/2 or math.pi/2,0) end
  local hinge=cf*CFrame.new(-2.9*R.DoorWidth/6,0,0)
  local m=clone('Door',hinge,mansion.Interactive,R.Themes[into.theme],R.DoorWidth/6);U.Mover(m,'Mover_RD'..door,hinge,'door',mansion.Interactive)
  m:SetAttribute('Room',into.name);m:SetAttribute('Locked',e.locked and true or nil)
  for _,p in ipairs(m:GetChildren()) do if p:IsA('BasePart') and p~=m.PrimaryPart then p:SetAttribute('DoorSlab',true);p.CanCollide=p.Name=='Slab' end end
  if e.locked then
   local pad=kit.Crate.Crate:Clone();pad.Name='Padlock';pad.Size=Vector3.new(.9,1,.4);pad.CFrame=cf*CFrame.new(2,4.4,-.5);pad.Color=Color3.fromRGB(212,165,60);pad.Material=Enum.Material.Metal;pad.CanCollide=false;pad:SetAttribute('DoorSlab',true);pad.Parent=m
  end
 end end
 F.Build(plan,mansion,kit)
 A.Decorate(plan,mansion)
 assert(#plan.furnitureFailures==0,'incomplete furniture: '..table.concat(plan.furnitureFailures,', '))
 local slotGroups={};for _,s in ipairs(plan.keySlots) do if not plan.closed[s.room] then slotGroups[s.room]=slotGroups[s.room] or {};table.insert(slotGroups[s.room],s) end end
 local keyRng=Random.new(plan.seed+7043)
 for i,room in ipairs(plan.keyRooms) do
  local slots=slotGroups[room];assert(slots and #slots>0,'no key slot '..room)
  local drawers,tables={},{}
  for _,s in ipairs(slots) do table.insert(s.kind=='table' and tables or drawers,s) end
  local choice=if keyRng:NextNumber()<.3 and #tables>0 then tables else drawers
  if #choice==0 then choice=tables end
  local slot=table.remove(choice,keyRng:NextInteger(1,#choice))
  for j,s in ipairs(slots) do if s==slot then table.remove(slots,j);break end end
  local m=Instance.new('Model');m.Name='Mover_Key'..i;local scale=slot.scale*(R.KeyScale or 1);local pivot=kit.Table.PrimaryPart:Clone();pivot.Name='Pivot';pivot.Size=Vector3.new(1.72*scale+.1,.35,3.485*scale+.1);pivot.CanQuery=true;pivot.Parent=m;m.PrimaryPart=pivot
  pivot.CFrame=if slot.kind=='drawer' then slot.mover.PrimaryPart.CFrame*slot.offset else slot.cf
  m:SetAttribute('Kind','key');m:SetAttribute('Room',room);m:SetAttribute('KeyColor',Color3.fromRGB(212,165,60));m:SetAttribute('KeyScale',scale);m:SetAttribute('Approach',slot.approach);m.Parent=mansion.Interactive
  if slot.kind=='drawer' then
   m:SetAttribute('DrawerMover',slot.mover.Name);m:SetAttribute('DrawerOffset',slot.offset)
  end
 end
 -- Static templates no longer need their invisible editing pivot after placement.
 for _,folder in ipairs({mansion.Architecture,mansion.Furniture}) do for _,model in ipairs(folder:GetChildren()) do
  if model:IsA('Model') and model.PrimaryPart then
   local pivot=model.PrimaryPart
   if pivot.Transparency==1 and not pivot.CanCollide and not pivot.CanQuery then
    local cf=model:GetPivot();model.PrimaryPart=nil;model.WorldPivot=cf;pivot:Destroy()
   end
  end
 end end
 M.Apply(mansion,plan,kit)
 mansion:SetAttribute('NavigationVersion',plan.navigationVersion or 2);mansion:SetAttribute('MainHallWidth',plan.mainHallWidth or R.HallWidth);mansion:SetAttribute('RequestedHallWidth',R.HallWidth);mansion:SetAttribute('HorizontalScale',plan.horizontalScale or 1);mansion:SetAttribute('OpenAreaMultiplier',plan.openAreaMultiplier or 1);mansion:SetAttribute('DoorClearWidth',R.DoorWidth)
 mansion:SetAttribute('BuildSeconds',os.clock()-started);mansion:SetAttribute('RoomCount',#plan.rooms)
 mansion:SetAttribute('FurnitureSkipped',#plan.furnitureFailures)
 B.BindKeyFollowers(mansion)
 return mansion
 end,debug.traceback)
 if not ok then if mansion then mansion:Destroy() end;error(result,0) end
 return result
end
return B