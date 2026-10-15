local R=require(script.Parent.Rules)
local U=require(script.Parent.KitUtil)
local Profiles=require(script.Parent.Profiles)
local F={}
local function rectOverlap(a,b,pad)
 return math.abs(a.x-b.x)<(a.w+b.w)/2+(pad or 0) and math.abs(a.z-b.z)<(a.d+b.d)/2+(pad or 0)
end
-- Match Builder's selected regular doors without consuming furnishing RNG.
-- Rectangles cover the whole swing, including angular gaps between 5-degree samples.
local function hotelDoorArcs(plan)
 if plan.hotelDoorArcs then return plan.hotelDoorArcs end
 local by={};for _,room in ipairs(plan.rooms)do by[room.name]=room end
 local rng=Random.new(plan.seed+3329);local arcs={}
 local length=5.75*R.DoorWidth/6
 local inflation=.3+2*length*math.sin(math.rad(2.5)/2)
 for _,edge in ipairs(plan.edges)do
  if edge.kind=='door' and not edge.boarded and (edge.locked or rng:NextNumber()<R.DoorChance)then
   local a,b=by[edge.a],by[edge.b]
   local into=if R.Types[b.type].zone=='hall' then a else b
   local yaw=if edge.axis=='x' then (into.z1>=edge.z and math.pi or 0) else (into.x1>=edge.x and -math.pi/2 or math.pi/2)
   local hinge=CFrame.new(edge.x,edge.y,edge.z)*CFrame.Angles(0,yaw,0)*CFrame.new(-2.9*R.DoorWidth/6,0,0)
   local arc={level=math.floor(edge.y/16),samples={},minx=math.huge,maxx=-math.huge,minz=math.huge,maxz=-math.huge}
   for degrees=0,100,5 do
    local cf=hinge*CFrame.Angles(0,math.rad(degrees),0)
    local centre=cf:PointToWorldSpace(Vector3.new(length/2,0,0))
    local u,v=cf.RightVector,cf.LookVector
    local box={x=centre.X,z=centre.Z,ux=u.X,uz=u.Z,vx=v.X,vz=v.Z,hx=length/2+inflation,hz=.24+inflation}
    local ex=math.abs(box.ux)*box.hx+math.abs(box.vx)*box.hz
    local ez=math.abs(box.uz)*box.hx+math.abs(box.vz)*box.hz
    arc.minx=math.min(arc.minx,box.x-ex);arc.maxx=math.max(arc.maxx,box.x+ex)
    arc.minz=math.min(arc.minz,box.z-ez);arc.maxz=math.max(arc.maxz,box.z+ez)
    table.insert(arc.samples,box)
   end
   table.insert(arcs,arc)
  end
 end
 plan.hotelDoorArcs=arcs
 return arcs
end
local function intersectsDoorArc(a,arc)
 local ax,az=a.w/2,a.d/2
 if a.x+ax<arc.minx or a.x-ax>arc.maxx or a.z+az<arc.minz or a.z-az>arc.maxz then return false end
 for _,b in ipairs(arc.samples)do
  local dx,dz=a.x-b.x,a.z-b.z
  if math.abs(dx)<=ax+math.abs(b.ux)*b.hx+math.abs(b.vx)*b.hz
   and math.abs(dz)<=az+math.abs(b.uz)*b.hx+math.abs(b.vz)*b.hz
   and math.abs(dx*b.ux+dz*b.uz)<=ax*math.abs(b.ux)+az*math.abs(b.uz)+b.hx
   and math.abs(dx*b.vx+dz*b.vz)<=ax*math.abs(b.vx)+az*math.abs(b.vz)+b.hz then return true end
 end
 return false
end

function F.Keepouts(plan,room)
 local keep={}
 -- The front entry stays clear from the doorway into the room.
 if plan.entrance then
  if room.name==plan.start then table.insert(keep,{x=plan.entrance.x,z=plan.entrance.z-12,w=12,d=24}) end
 elseif room.level==0 and room.z2==plan.length then table.insert(keep,{x=0,z=plan.length-12,w=12,d=24}) end
 local cx,cz=room.navx or (room.x1+room.x2)/2,room.navz or (room.z1+room.z2)/2
 -- A central circulation spine remains clear for creatures and players.
 table.insert(keep,{x=cx,z=cz,w=6,d=6})
 for _,e in ipairs(plan.edges) do if (e.a==room.name or e.b==room.name) and e.kind~='stairs' and not e.boarded then
  local x=math.clamp(e.x,room.x1+3.2,room.x2-3.2);local z=math.clamp(e.z,room.z1+3.2,room.z2-3.2)
  table.insert(keep,{x=x,z=z,w=9,d=9})
  -- Axis-aligned two-segment route from the doorway to the centre, 3 studs wide.
  if room.type=='Dining' then
   local edge=room.x2-2.8
   table.insert(keep,{x=edge,z=(z+cz)/2,w=4,d=math.abs(z-cz)+4})
   table.insert(keep,{x=(edge+cx)/2,z=cz,w=math.abs(edge-cx)+4,d=4})
   table.insert(keep,{x=(x+edge)/2,z=z,w=math.abs(x-edge)+4.5,d=4.5})
  else
   table.insert(keep,{x=(x+cx)/2,z=z,w=math.abs(x-cx)+6,d=6})
   table.insert(keep,{x=cx,z=(z+cz)/2,w=6,d=math.abs(z-cz)+6})
  end
 end end
 if plan.mapKind=='Hotel' then
  keep.doorArcs={}
  for _,arc in ipairs(hotelDoorArcs(plan))do
   if arc.level==room.level and arc.maxx>room.x1 and arc.minx<room.x2 and arc.maxz>room.z1 and arc.minz<room.z2 then table.insert(keep.doorArcs,arc)end
  end
 end
 return keep
end
local function legal(a,r,keep,placed)
 if a.front and (a.front.x-a.front.w/2<r.x1+.75 or a.front.x+a.front.w/2>r.x2-.75 or a.front.z-a.front.d/2<r.z1+.75 or a.front.z+a.front.d/2>r.z2-.75) then return false end
 if a.x-a.w/2<r.x1+1 or a.x+a.w/2>r.x2-1 or a.z-a.d/2<r.z1+1 or a.z+a.d/2>r.z2-1 then return false end
 if a.tall then for _,b in ipairs(r.windowKeepouts or {}) do if rectOverlap(a,b,.25) then return false end end end
 for _,b in ipairs(keep) do if rectOverlap(a,b,.25) then return false end end
 for _,arc in ipairs(keep.doorArcs or {})do if intersectsDoorArc(a,arc)then return false end end
 for _,b in ipairs(placed) do if rectOverlap(a,b,.25) or (b.front and rectOverlap(a,b.front,.2)) or (a.front and rectOverlap(a.front,b,.2)) then return false end end
 return true
end
function F.Build(plan,mansion,kit)
 local rng=Random.new(plan.seed+5917);local by={};local id=0;local lightCount=0
 plan.placements={};plan.keySlots={};plan.furnitureFailures={}
 local function configure(t,cf,r,name)
  local m=U.Clone(kit,name,cf,mansion.Furniture,R.Themes[r.theme]);m.Name=r.name..'_'..name
  for _,p in ipairs(m:GetDescendants()) do if p:IsA('BasePart') then p:SetAttribute('Room',r.name) end end
  local roleGroups={}
  for _,p in ipairs(m:GetChildren()) do if p:IsA('BasePart') and p~=m.PrimaryPart then
   local role=p:GetAttribute('Role') or 'static'
   if role~='static' then roleGroups[role]=roleGroups[role] or {};table.insert(roleGroups[role],p) end
  end end
  local closetIds={};local closetName=r.name..'_Closet'..id -- unique per wardrobe: a room may hold several hiding closets
  local roles={};for role in pairs(roleGroups) do table.insert(roles,role) end;table.sort(roles)
  for _,role in ipairs(roles) do
   local pieces=roleGroups[role];id+=1
   local mover=Instance.new('Model');local pivot=m.PrimaryPart:Clone();pivot.Parent=mover;mover.PrimaryPart=pivot
   local localPivot
   if role=='closetLeft' then localPivot=CFrame.new(-3.35,0,-1.9)
   elseif role=='closetRight' then localPivot=CFrame.new(3.35,0,-1.9)
   else localPivot=CFrame.new(0,0,0) end
   local hinge=cf*localPivot;pivot.CFrame=hinge
   for _,p in ipairs(pieces) do p.Parent=mover;p.CanCollide=false end
   U.Mover(mover,'Mover_'..id,hinge,role:find('drawer') and 'drawer' or 'door',mansion.Interactive)
   mover:SetAttribute('Room',r.name)
   if role:find('closet') then
    mover:SetAttribute('Closet',closetName);mover:SetAttribute('Swing',role=='closetLeft' and (plan.mapKind=='Hotel' and 90 or 100) or (plan.mapKind=='Hotel' and -90 or -100));table.insert(closetIds,tostring(id))
   elseif role:find('drawer') then
    local body
    for _,p in ipairs(pieces) do if p.Size.Z>.4 and (not body or p.Size.Magnitude>body.Size.Magnitude) then body=p end end
    if body then
     local scale=math.min(1,(body.Size.X-.5)/3.485,(body.Size.Z-.3)/1.72)
     if scale>=.5 then
      local offset=hinge:ToObjectSpace(body.CFrame)*CFrame.new(0,.35,0)*CFrame.Angles(0,math.pi/2,0)
      table.insert(plan.keySlots,{room=r.name,kind='drawer',mover=mover,offset=offset,scale=scale,approach=cf*CFrame.new(0,2,-t:GetAttribute('Footprint').Z/2-2)})
     end
    end
   end
  end
  if #closetIds>0 then
   local p=m.PrimaryPart:Clone();p.Name=closetName;p.CFrame=cf*CFrame.new(0,.6,0);p:SetAttribute('Doors',table.concat(closetIds,','));p.Parent=mansion.Closets
  end
  if name=='Table' or name=='Desk' or name=='Counter' then
   table.insert(plan.keySlots,{room=r.name,kind='table',cf=cf*CFrame.new(0,3.42,0),scale=.75,approach=cf*CFrame.new(0,2,-t:GetAttribute('Footprint').Z/2-2)})
  end
  if plan.mapKind=='Birthday' and name=='Table' and (r.type=='Dining' or r.type=='Ballroom') then
   local cake=U.Clone(kit,'BirthdayCake',cf*CFrame.new(-2,3.2,0),mansion.Furniture)
   cake.Name=r.name..'_BirthdayCake';cake:SetAttribute('Room',r.name)
   for _,p in ipairs(cake:GetDescendants()) do if p:IsA('BasePart') then p.CanCollide=false;p:SetAttribute('NonBlockingDetail',true) end end
  end
  if t:GetAttribute('Light') and lightCount<R.LightCap*#plan.rooms then
   local p=m:FindFirstChild('Shade') or m:FindFirstChild('Wax');if p then
    p:SetAttribute('Flicker',true);local l=Instance.new('PointLight');l.Color=Color3.fromRGB(255,190,112);l.Range=24;l.Brightness=1.3;l.Shadows=false;l.Parent=p;lightCount+=1
   end
  end
  if name=='Wardrobe' then
   for _,p in ipairs(m:GetChildren()) do if p:IsA('BasePart') and p~=m.PrimaryPart then
    local collider=kit.Table.PrimaryPart:Clone();collider.Size=p.Size;collider.CFrame=p.CFrame;collider.Name=p.Name;collider.Transparency=1;collider.CanCollide=true;collider.CanQuery=true;collider:SetAttribute('Furniture',true);collider:SetAttribute('Room',r.name);collider.Parent=mansion.Collision;p.CanCollide=false
   end end
  else
   local cf,size=m:GetBoundingBox();local collider=kit.Table.PrimaryPart:Clone()
   collider.Name=name;collider.Size=size;collider.CFrame=cf;collider.CanCollide=true;collider.CanQuery=true;collider:SetAttribute('Furniture',true);collider:SetAttribute('Room',r.name);collider.Parent=mansion.Collision
   for _,p in ipairs(m:GetChildren()) do if p:IsA('BasePart') then p.CanCollide=false end end
  end
  return m
 end
 for _,r in ipairs(plan.rooms) do
  by[r.name]=r
  local recipe=Profiles.GetRecipe(plan,r);local keep=F.Keepouts(plan,r);local placed={};local lights=0
  local items=table.clone(recipe)
  -- Key rooms must have a usable, deliberately placed surface, never a floor fallback.
  local keyCount=0;for _,name in ipairs(plan.keyRooms) do if name==r.name then keyCount+=1 end end
  local needsKey=keyCount>0
  if keyCount>1 and not table.find(items,'Dresser') then table.insert(items,1,'Dresser') end
  if needsKey then
   local index=table.find(items,'Table') or table.find(items,'Desk') or table.find(items,'Counter') or table.find(items,'Dresser')
   if index then local item=table.remove(items,index);table.insert(items,1,item) else table.insert(items,1,'Table') end
  end
  local best,bestMissing={},{}
  for attempt=1,30 do
   placed={};lights=0;local missing={};local attached={}
  for _,name in ipairs(items) do
   if (attached[name] or 0)>0 then attached[name]-=1;continue end
   local t=U.Resolve(kit,name,R.Themes[r.theme]);local fp=t:GetAttribute('Footprint');local candidates={}
   if t:GetAttribute('Light') and lights>=R.LightCap then continue end
   local wall=t:GetAttribute('WallSide');local y=r.level*16
   for _,angle in ipairs({0,90,180,270}) do
    local w,d=if angle%180==0 then fp.X else fp.Z,if angle%180==0 then fp.Z else fp.X
    if wall then
     if angle==0 or angle==180 then
      for x=r.x1+w/2+1,r.x2-w/2-1,2 do
       table.insert(candidates,{x=x,z=if angle==0 then r.z2-d/2-1 else r.z1+d/2+1,w=w,d=d,angle=angle})
      end
     else
      for z=r.z1+d/2+1,r.z2-d/2-1,2 do
       table.insert(candidates,{x=if angle==90 then r.x2-w/2-1 else r.x1+w/2+1,z=z,w=w,d=d,angle=angle})
      end
     end
    else
     for x=r.x1+w/2+1,r.x2-w/2-1,2 do for z=r.z1+d/2+1,r.z2-d/2-1,2 do table.insert(candidates,{x=x,z=z,w=w,d=d,angle=angle}) end end
    end
   end
   for i=#candidates,2,-1 do local j=rng:NextInteger(1,i);candidates[i],candidates[j]=candidates[j],candidates[i] end
   if not t:GetAttribute('WallSide') and not (name=='Table' and r.type=='Dining') then
    table.sort(candidates,function(a,b)local function edge(c)return math.min(c.x-r.x1-c.w/2,r.x2-c.x-c.w/2,c.z-r.z1-c.d/2,r.z2-c.z-c.d/2)end return edge(a)<edge(b)end)
   end
   if name=='Table' and r.type=='Dining' then
    candidates={{x=(r.x1+r.x2)/2,z=(r.z1+r.z2)/2,w=fp.X,d=fp.Z,angle=0}}
   end
   local chosen
   for _,a in ipairs(candidates) do
    a.tall=t:GetExtentsSize().Y>5.5
    local clearance=math.max(t:GetAttribute('Clearance'),3)
    local cf=CFrame.new(a.x,0,a.z)*CFrame.Angles(0,math.rad(a.angle),0)
    local front=cf:PointToWorldSpace(Vector3.new(0,0,-fp.Z/2-clearance/2))
    a.front={x=front.X,z=front.Z,w=if a.angle%180==0 then fp.X else clearance,d=if a.angle%180==0 then clearance else fp.X}
    local children={};local childType=if name=='Bed' then 'Nightstand' elseif name=='Table' and r.type=='Dining' then 'Chair' else nil
    local good=legal(a,r,keep,placed)
    if good and childType then
     local count=0;for _,item in ipairs(items) do if item==childType then count+=1 end end
     local childFP=U.Resolve(kit,childType,R.Themes[r.theme]):GetAttribute('Footprint')
     for index=1,count do
      local side=index==1 and -1 or 1
      local pos=cf:PointToWorldSpace(Vector3.new(side*(fp.X/2+childFP.X/2+.3),0,name=='Bed' and fp.Z/2-childFP.Z/2 or 0))
      local angle=if name=='Bed' then a.angle else (a.angle+(side==-1 and 270 or 90))%360
      local c={x=pos.X,z=pos.Z,w=if angle%180==0 then childFP.X else childFP.Z,d=if angle%180==0 then childFP.Z else childFP.X,angle=angle,template=childType,name=r.name..'_'..childType,level=r.level,room=r.name}
      if not legal(c,r,keep,placed) then if plan.mapKind=='Hotel' and name=='Bed' and attempt==30 then children={} else good=false end;break end;table.insert(children,c)
     end
    end
    if good then chosen=a;chosen.children=children;break end
   end
   if chosen then
    chosen.name=r.name..'_'..name;chosen.level=r.level;chosen.room=r.name;chosen.template=name
    table.insert(placed,chosen)
    for _,c in ipairs(chosen.children or {}) do table.insert(placed,c);attached[c.template]=(attached[c.template] or 0)+1 end
    if t:GetAttribute('Light') then lights+=1 end
   else table.insert(missing,r.name..':'..name) end
  end
   if #placed>#best or attempt==1 then best=placed;bestMissing=missing end
   if #missing==0 then best=placed;bestMissing={};break end
  end
  for _,a in ipairs(best) do
   table.insert(plan.placements,a)
   configure(U.Resolve(kit,a.template,R.Themes[r.theme]),CFrame.new(a.x,r.level*16,a.z)*CFrame.Angles(0,math.rad(a.angle),0),r,a.template)
  end
  for _,name in ipairs(bestMissing) do table.insert(plan.furnitureFailures,name) end
  if #recipe>0 and #best==0 then error('No furniture fits '..r.name) end
 end
 -- Optional dressing uses a separate generator after required furnishing, so
 -- it cannot displace a required item or change another room's recipe layout.
 local decor=Random.new(plan.seed+99317)
 for _,r in ipairs(plan.rooms) do
  local placed={};for _,a in ipairs(plan.placements) do if a.room==r.name then table.insert(placed,a) end end
  local keep=F.Keepouts(plan,r)
  local optional=table.clone(R.Optional[r.type] or {})
  if R.Types[r.type].zone~='hall' and r.type~='Foyer' then
   for _,name in ipairs(Profiles.GetDecor(plan,r)) do table.insert(optional,name) end
  end
  for _,name in ipairs(optional) do if decor:NextNumber()<(name=='Wardrobe' and (R.WardrobeChance or .35) or .35) then
   local t=U.Resolve(kit,name,R.Themes[r.theme]);local fp=t:GetAttribute('Footprint');local options={}
   for _,angle in ipairs({0,90,180,270}) do
    local w,d=if angle%180==0 then fp.X else fp.Z,if angle%180==0 then fp.Z else fp.X
    local function steps(a,b) local t={};if b<a then return t end;for v=a,b,4 do t[#t+1]=v end;if b-t[#t]>.01 then t[#t+1]=b end;return t end -- grid + wall-flush ends (the 4-stud grid alone often never reached the far wall, so wall-only lockers found no slot)
    for _,x in ipairs(steps(r.x1+w/2+1,r.x2-w/2-1)) do for _,z in ipairs(steps(r.z1+d/2+1,r.z2-d/2-1)) do
     local against=if angle==0 then r.z2-z-d/2 elseif angle==180 then z-d/2-r.z1 elseif angle==90 then r.x2-x-w/2 else x-w/2-r.x1
     -- Extra hiding wardrobes may stand a little off the wall when the walls are taken (windows/doors/furniture).
     if not t:GetAttribute('WallSide') or against<1.1 or (name=='Wardrobe' and against<(R.WardrobeWallSlack or 1.1)) then
      table.insert(options,{x=x,z=z,w=w,d=d,angle=angle,level=r.level,room=r.name,name=r.name..'_'..name,template=name,optional=true})
     end
    end end
   end
   for i=#options,2,-1 do local j=decor:NextInteger(1,i);options[i],options[j]=options[j],options[i] end
   for _,a in ipairs(options) do
    a.tall=t:GetExtentsSize().Y>5.5
    local clearance=math.max(t:GetAttribute('Clearance'),2)
    local cf=CFrame.new(a.x,0,a.z)*CFrame.Angles(0,math.rad(a.angle),0)
    local front=cf:PointToWorldSpace(Vector3.new(0,0,-fp.Z/2-clearance/2))
    a.front={x=front.X,z=front.Z,w=if a.angle%180==0 then fp.X else clearance,d=if a.angle%180==0 then clearance else fp.X}
    if legal(a,r,keep,placed) then
     table.insert(placed,a);table.insert(plan.placements,a)
     configure(t,CFrame.new(a.x,r.level*16,a.z)*CFrame.Angles(0,math.rad(a.angle),0),r,name)
     break
    end
   end
  end end
 end
 return plan.placements
end
return F