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
     -- PlaytestFixes 2026-10-27 (owner: "drawer with nothing there"): the key lay at the floor's centre and drawers slid
     -- out 1.12 studs, so an opened key drawer still hid the key under the furniture top (0/9 sight rays reached it on
     -- Hotel). The key now lies at the floor's front edge and each drawer slides out far enough to show that spot.
     local bodyLocal=hinge:ToObjectSpace(body.CFrame)
     local keyDepth=1.72*math.max(scale,.5)*(R.KeyScale or 1)
     local front;for _,p in ipairs(pieces) do if p~=body and p.Size.Z<=.4 and (not front or p.Size.X*p.Size.Y>front.Size.X*front.Size.Y) then front=p end end
     local frontFace=front and hinge:ToObjectSpace(front.CFrame).Z+front.Size.Z/2 or bodyLocal.Z-body.Size.Z/2
     local keyBack=bodyLocal.Z-body.Size.Z/2+.12+keyDepth
     mover:SetAttribute('Travel',math.clamp(keyBack-frontFace+.3,1.12,math.min(2.8,body.Size.Z+.4)))
     if scale>=.5 then
      local offset=bodyLocal*CFrame.new(0,.35,-body.Size.Z/2+.12+keyDepth/2)*CFrame.Angles(0,math.pi/2,0)
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
-- World features (2026-10-27, WorldA; World_shared.md): laundry chute pairs, crawl hatch pairs (+ WorldB's wall safe,
-- the puzzle props). InteractServer runs them. Optional: no template in MapKit (LaundryChute / CrawlHatch / ...) or no
-- room for one means fewer of them, never a rejected seed. Own RNG; runs after furnishing and before art (A.Decorate keeps
-- clear of plan.placements, AngledCorners keeps clear of Interactive/Furniture parts). Shared helpers, used by every feature:
local FEATURE_PUSH=.28 -- wall-mounted: from the 1-stud furniture gap to 0.02 off the wall face (walls are 0.7 deep per side)
local CHUTE_Y=2.2 -- the chute hatch hangs this high, so its mouth is at chest height
local function shuffle(t,rng) for i=#t,2,-1 do local j=rng:NextInteger(1,i);t[i],t[j]=t[j],t[i] end;return t end
local function featureRoom(plan,r) return r.type~='Stair' and not (plan.closed and plan.closed[r.name]) end -- never into a locked room
local function placedIn(plan,r) local t={};for _,a in ipairs(plan.placements) do if a.room==r.name then table.insert(t,a) end end;return t end
local function roomAt(plan,level,x,z) for _,o in ipairs(plan.rooms) do if o.level==level and x>o.x1 and x<o.x2 and z>o.z1 and z<o.z2 then return o end end;return nil end
local function frameOf(a,r,push,y) return CFrame.new(a.x,r.level*16+(y or 0),a.z)*CFrame.Angles(0,math.rad(a.angle),0)*CFrame.new(0,0,push or 0) end
local function claim(plan,a,r,label) a.room=r.name;a.level=r.level;a.name=r.name..'_'..label;a.template=label;a.optional=true;table.insert(plan.placements,a) end
-- Same front rectangle as the furnishing passes; tall=true makes legal() keep it off window walls too.
local function frontOf(a,fp,clearance)
 local cf=CFrame.new(a.x,0,a.z)*CFrame.Angles(0,math.rad(a.angle),0)
 local front=cf:PointToWorldSpace(Vector3.new(0,0,-fp.Z/2-clearance/2))
 a.front={x=front.X,z=front.Z,w=if a.angle%180==0 then fp.X else clearance,d=if a.angle%180==0 then clearance else fp.X}
 a.tall=true
 return a
end
-- Wall-side candidates exactly like F.Build's WallSide branch (1 stud off the wall line), shuffled.
local function wallSpots(r,fp,clearance,rng)
 local out={}
 for _,angle in ipairs({0,90,180,270}) do
  local w,d=if angle%180==0 then fp.X else fp.Z,if angle%180==0 then fp.Z else fp.X
  if angle%180==0 then
   for x=r.x1+w/2+1,r.x2-w/2-1,2 do table.insert(out,frontOf({x=x,z=if angle==0 then r.z2-d/2-1 else r.z1+d/2+1,w=w,d=d,angle=angle},fp,clearance)) end
  else
   for z=r.z1+d/2+1,r.z2-d/2-1,2 do table.insert(out,frontOf({x=if angle==90 then r.x2-w/2-1 else r.x1+w/2+1,z=z,w=w,d=d,angle=angle},fp,clearance)) end
  end
 end
 return shuffle(out,rng)
end
-- Plain solid wall (the 'Wall' template, not a window, portal or open bay) behind the whole width, y1..y2 above the floor.
local function solidBehind(mansion,cf,width,y1,y2,depth)
 local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={mansion.Architecture}
 for _,x in ipairs({-width/2+.2,0,width/2-.2}) do for _,y in ipairs({y1+.2,(y1+y2)/2,y2-.2}) do
  local hit=workspace:Raycast(cf:PointToWorldSpace(Vector3.new(x,y,0)),cf.LookVector*-(depth/2+2),rp)
  if not hit or not hit.Instance.Parent or hit.Instance.Parent.Name~='Wall' then return false end
 end end
 return true
end
local function findSpot(plan,mansion,r,fp,clearance,rng,y1,y2)
 local keep,placed=F.Keepouts(plan,r),placedIn(plan,r)
 for _,a in ipairs(wallSpots(r,fp,clearance,rng)) do
  if legal(a,r,keep,placed) and solidBehind(mansion,frameOf(a,r),fp.X,y1,y2,fp.Z) then return a end
 end
 return nil
end
local function placeFeature(kit,mansion,name,cf,r,label)
 local m=U.Clone(kit,name,cf,mansion.Interactive);m.Name=label;m:SetAttribute('Room',r.name)
 for _,p in ipairs(m:GetDescendants()) do if p:IsA('BasePart') then p:SetAttribute('Room',r.name);p.CanCollide=false end end
 return m
end
-- One invisible box in Collision, like configure() gives furniture (the aim ray treats it as the feature's own face).
local function featureCollider(kit,mansion,m,r,name)
 local cf,size=m:GetBoundingBox();local c=kit.Table.PrimaryPart:Clone()
 c.Name=name;c.Size=size;c.CFrame=cf;c.Transparency=1;c.Anchored=true;c.CanCollide=true;c.CanQuery=true;c:SetAttribute('Room',r.name);c.Parent=mansion.Collision
 return c
end
local function footprintOf(t) return t:GetAttribute('Footprint') or t:GetExtentsSize() end
F.WorldHelpers={shuffle=shuffle,featureRoom=featureRoom,placedIn=placedIn,roomAt=roomAt,frameOf=frameOf,claim=claim,frontOf=frontOf,
 wallSpots=wallSpots,solidBehind=solidBehind,findSpot=findSpot,placeFeature=placeFeature,featureCollider=featureCollider,footprintOf=footprintOf,
 legal=legal,FEATURE_PUSH=FEATURE_PUSH}

-- Laundry chutes (World/LaundryChute): a hatch in an upstairs room, its exit in the downstairs room nearest below it.
local function placeChutes(plan,mansion,kit,rng,rooms)
 local t=kit:FindFirstChild('LaundryChute');if not t then return 0 end
 local fp=footprintOf(t);local clearance=math.max(t:GetAttribute('Clearance') or 3,3)
 local upper,lower={},{}
 for _,r in ipairs(rooms) do if r.level>=1 then table.insert(upper,r) else table.insert(lower,r) end end
 shuffle(upper,rng)
 local want=1;local made=0
 for _,top in ipairs(upper) do
  if made>=want then break end
  local a=findSpot(plan,mansion,top,fp,clearance,rng,CHUTE_Y,CHUTE_Y+fp.Y)
  if not a then continue end
  local best,bestRoom,bestD
  for _,low in ipairs(lower) do
   local b=findSpot(plan,mansion,low,fp,clearance,rng,CHUTE_Y,CHUTE_Y+fp.Y)
   if b then local d=Vector2.new(b.x-a.x,b.z-a.z).Magnitude;if not bestD or d<bestD then best,bestRoom,bestD=b,low,d end end
  end
  if best then
   made+=1
   claim(plan,a,top,'ChuteTop'..made);claim(plan,best,bestRoom,'ChuteBottom'..made)
   local up=placeFeature(kit,mansion,'LaundryChute',frameOf(a,top,FEATURE_PUSH,CHUTE_Y),top,'Chute_'..made..'_Top')
   local down=placeFeature(kit,mansion,'LaundryChute',frameOf(best,bestRoom,FEATURE_PUSH,CHUTE_Y),bestRoom,'Chute_'..made..'_Bottom')
   for _,pair in ipairs({{up,down,'top'},{down,up,'bottom'}}) do
    pair[1]:SetAttribute('Kind','chute');pair[1]:SetAttribute('ChuteEnd',pair[3]);pair[1]:SetAttribute('Pair',pair[2].Name);pair[1]:SetAttribute('DisplayName','Laundry Chute')
   end
   featureCollider(kit,mansion,up,top,'LaundryChute');featureCollider(kit,mansion,down,bestRoom,'LaundryChute')
  end
 end
 return made
end

-- Crawl hatches (World/CrawlHatch): the same hatch on both faces of one plain wall between two rooms that have no door
-- between them (Compact maps one pair, others two, 30+ studs apart). Players crawl through; the cart and monsters cannot.
local function placeHatches(plan,mansion,kit,rng,rooms)
 local t=kit:FindFirstChild('CrawlHatch');if not t then return 0 end
 local fp=footprintOf(t);local clearance=math.max(t:GetAttribute('Clearance') or 4,4)
 local want=plan.sizeClass=='Compact' and 1 or 2;local made,spots=0,{}
 local linked={};for _,e in ipairs(plan.edges) do linked[e.a..'|'..e.b]=true;linked[e.b..'|'..e.a]=true end
 for _,r in ipairs(shuffle(table.clone(rooms),rng)) do
  if made>=want then break end
  local keep,placed=F.Keepouts(plan,r),placedIn(plan,r)
  for _,a in ipairs(wallSpots(r,fp,clearance,rng)) do
   -- the room on the other face of this wall, and this spot mirrored into it
   local wall,probe,mirror,shares
   if a.angle==0 then wall=r.z2;probe=Vector2.new(a.x,wall+1.5);mirror={x=a.x,z=2*wall-a.z,angle=180};shares=function(o) return o.z1==wall end
   elseif a.angle==180 then wall=r.z1;probe=Vector2.new(a.x,wall-1.5);mirror={x=a.x,z=2*wall-a.z,angle=0};shares=function(o) return o.z2==wall end
   elseif a.angle==90 then wall=r.x2;probe=Vector2.new(wall+1.5,a.z);mirror={x=2*wall-a.x,z=a.z,angle=270};shares=function(o) return o.x1==wall end
   else wall=r.x1;probe=Vector2.new(wall-1.5,a.z);mirror={x=2*wall-a.x,z=a.z,angle=90};shares=function(o) return o.x2==wall end end
   local o=roomAt(plan,r.level,probe.X,probe.Y)
   local far=true;for _,s in ipairs(spots) do if s.level==r.level and Vector2.new(s.x-a.x,s.z-a.z).Magnitude<30 then far=false;break end end
   if far and o and o~=r and featureRoom(plan,o) and shares(o) and not linked[r.name..'|'..o.name] and legal(a,r,keep,placed) then
    mirror.w,mirror.d=a.w,a.d;frontOf(mirror,fp,clearance)
    if legal(mirror,o,F.Keepouts(plan,o),placedIn(plan,o)) and solidBehind(mansion,frameOf(a,r),fp.X,.3,fp.Y,fp.Z) and solidBehind(mansion,frameOf(mirror,o),fp.X,.3,fp.Y,fp.Z) then
     made+=1;table.insert(spots,{x=a.x,z=a.z,level=r.level})
     claim(plan,a,r,'HatchA'..made);claim(plan,mirror,o,'HatchB'..made)
     local ha=placeFeature(kit,mansion,'CrawlHatch',frameOf(a,r,FEATURE_PUSH),r,'Hatch_'..made..'A')
     local hb=placeFeature(kit,mansion,'CrawlHatch',frameOf(mirror,o,FEATURE_PUSH),o,'Hatch_'..made..'B')
     for _,pair in ipairs({{ha,hb},{hb,ha}}) do pair[1]:SetAttribute('Kind','hatch');pair[1]:SetAttribute('Pair',pair[2].Name);pair[1]:SetAttribute('DisplayName','Crawl Hatch') end
     break
    end
   end
  end
 end
 return made
end

-- Puzzle props (draft 2026-10-26; World/CatShelf, World/LullabyGramophone, World/SlothToyChest): one of each per map
-- when a room has wall space. CursedItemsServer's PuzzleBatch prunes the ones whose level gate is not met and spawns
-- the loose pieces; InteractServer runs the toy chest and the sloth. Optional: no MapKit template, no prop.
local PUZZLE_ROOMS={
 CatShelf={Parlor=true,Sewing=true,Bedroom=true,Master=true,Library=true,Study=true,Conservatory=true},
 LullabyGramophone={Music=true,Ballroom=true,Parlor=true,Gallery=true,Library=true,Dining=true},
 ToyChest={Nursery=true,Playroom=true,Bedroom=true,AtticStorage=true},
 NappingSloth={Nursery=true,Playroom=true,Bedroom=true,Master=true,Parlor=true,Library=true,Conservatory=true}}
local SLOTH_FROM,SLOTH_TO,SLOTH_BEST=30,100,50 -- studs from the chest to the sloth's room centre (other floor +40)
local function puzzleOrder(rooms,want,rng)
 local order=shuffle(table.clone(rooms),rng)
 table.sort(order,function(x,y) return (want[x.type] and 0 or 1)<(want[y.type] and 0 or 1) end)
 return order
end
local function puzzleSpot(plan,mansion,kit,rng,r,name)
 local t=kit:FindFirstChild(name);if not t then return nil end
 local fp=footprintOf(t)
 return findSpot(plan,mansion,r,fp,math.max(t:GetAttribute('Clearance') or 2.5,2.5),rng,.4,math.min(fp.Y,4))
end
local function puzzleProp(plan,mansion,kit,r,a,name,label,set)
 claim(plan,a,r,name)
 local m=placeFeature(kit,mansion,name,frameOf(a,r,FEATURE_PUSH),r,label);m:SetAttribute('PuzzleSet',set)
 featureCollider(kit,mansion,m,r,label)
 local c=mansion.Collision:FindFirstChild(label);if c then c:SetAttribute('PuzzleSet',set) end -- PuzzleBatch prunes by PuzzleSet
 return m
end
local function placePuzzles(plan,mansion,kit,rng,rooms)
 local count=0
 local function usable(r) return r.name~=plan.start and R.Types[r.type].zone~='hall' end
 -- single props: {template, label, PuzzleSet, Kind, DisplayName}
 for _,d in ipairs({{'CatShelf','CatShelf_1','CatShelf','catshelf','Cat Shelf'},{'LullabyGramophone','Gramophone_1','LullabyGramophone','gramophone','Lullaby Gramophone'}}) do
  for _,r in ipairs(puzzleOrder(rooms,PUZZLE_ROOMS[d[1]],rng)) do
   local a=usable(r) and puzzleSpot(plan,mansion,kit,rng,r,d[1])
   if a then
    local m=puzzleProp(plan,mansion,kit,r,a,d[1],d[2],d[3]);m:SetAttribute('Kind',d[4]);m:SetAttribute('DisplayName',d[5])
    count+=1;break
   end
  end
 end
 -- toy chest + the sloth holding its key, 30-100 studs apart (best ~50): both or neither
 for _,r in ipairs(puzzleOrder(rooms,PUZZLE_ROOMS.ToyChest,rng)) do
  local a=usable(r) and puzzleSpot(plan,mansion,kit,rng,r,'ToyChest')
  if not a then continue end
  local best,bestRoom,bestScore
  for _,o in ipairs(rooms) do if o~=r and usable(o) then
   local d=Vector2.new((o.x1+o.x2)/2-a.x,(o.z1+o.z2)/2-a.z).Magnitude+math.abs(o.level-r.level)*40
   local score=math.abs(d-SLOTH_BEST)-(PUZZLE_ROOMS.NappingSloth[o.type] and 15 or 0)
   if d>=SLOTH_FROM and d<=SLOTH_TO and (not bestScore or score<bestScore) then
    local s=puzzleSpot(plan,mansion,kit,rng,o,'NappingSloth');if s then best,bestRoom,bestScore=s,o,score end
   end
  end end
  if best then
   local chest=puzzleProp(plan,mansion,kit,r,a,'ToyChest','ToyChest_1','SlothToyChest')
   chest:SetAttribute('Kind','toychest');chest:SetAttribute('ChestLocked',true);chest:SetAttribute('DisplayName','Toy Chest');chest:SetAttribute('Sloth','NappingSloth_1')
   local sloth=puzzleProp(plan,mansion,kit,bestRoom,best,'NappingSloth','NappingSloth_1','SlothToyChest')
   sloth:SetAttribute('Kind','sloth');sloth:SetAttribute('HasKey',true);sloth:SetAttribute('Chest','ToyChest_1');sloth:SetAttribute('DisplayName','Napping sloth')
   count+=2;break
  end
 end
 return count
end

-- Wall safe (WorldB 2026-10-27; World/WallSafe): one safe per map against a plain wall (a study / library / bedroom when
-- one has space) and its code note pinned 30+ studs away (best ~60, other floor +40). The note reads by flashlight.
local NOTE_Y=4.6 -- centre height of the safe's code note
local SAFE_ROOMS={Study=true,Library=true,Master=true,Bedroom=true,Gallery=true,Parlor=true,Sewing=true}
local function codeNote(mansion,a,r,code,name,rng)
 local note=Instance.new('Part');note.Name=name;note.Size=Vector3.new(1.8,1.3,.06)
 note.Anchored=true;note.CanCollide=false;note.CanQuery=false;note.CanTouch=false;note.CastShadow=false
 note.Material=Enum.Material.SmoothPlastic;note.Color=Color3.fromRGB(226,216,190)
 note.CFrame=frameOf(a,r,.2+1-.75,NOTE_Y)*CFrame.Angles(0,0,math.rad(rng:NextNumber(-7,7))) -- flat on the wall face, a little crooked
 note:SetAttribute('Room',r.name);note:SetAttribute('SafeNote',true);note:SetAttribute('NonBlockingDetail',true)
 local gui=Instance.new('SurfaceGui');gui.Name='NoteText';gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=80;gui.LightInfluence=1;gui.Parent=note
 local title=Instance.new('TextLabel');title.Name='Title';title.BackgroundTransparency=1;title.Size=UDim2.fromScale(1,.34);title.Font=Enum.Font.PermanentMarker
 title.TextScaled=true;title.TextColor3=Color3.fromRGB(78,80,88);title.Text='the old safe:';title.Parent=gui
 local digits=title:Clone();digits.Name='Code';digits.Position=UDim2.fromScale(0,.32);digits.Size=UDim2.fromScale(1,.64);digits.TextColor3=Color3.fromRGB(44,46,54)
 digits.Text=code:sub(1,1)..'  '..code:sub(2,2)..'  '..code:sub(3,3);digits.Parent=gui
 note.Parent=mansion.Furniture
 return note
end
local function placeSafe(plan,mansion,kit,rng,rooms)
 local t=kit:FindFirstChild('WallSafe');if not t then return 0 end
 local fp=footprintOf(t);local clearance=math.max(t:GetAttribute('Clearance') or 3,3)
 local order=shuffle(table.clone(rooms),rng)
 table.sort(order,function(x,y) return (SAFE_ROOMS[x.type] and 0 or 1)<(SAFE_ROOMS[y.type] and 0 or 1) end)
 local noteFp=Vector3.new(1.8,1.3,.4)
 for _,r in ipairs(order) do
  if r.name==plan.start or (R.Types[r.type] and R.Types[r.type].zone=='hall') then continue end
  local a=findSpot(plan,mansion,r,fp,clearance,rng,.4,fp.Y)
  if not a then continue end
  local best,bestRoom,bestScore
  for _,o in ipairs(rooms) do if o~=r then
   local n=findSpot(plan,mansion,o,noteFp,2,rng,NOTE_Y-.8,NOTE_Y+.8)
   if n then
    local d=Vector2.new(n.x-a.x,n.z-a.z).Magnitude+math.abs(o.level-r.level)*40
    if d>=30 and (not bestScore or math.abs(d-60)<bestScore) then best,bestRoom,bestScore=n,o,math.abs(d-60) end
   end
  end end
  if best then
   claim(plan,a,r,'WallSafe');claim(plan,best,bestRoom,'SafeNote')
   local code=('%d%d%d'):format(rng:NextInteger(1,6),rng:NextInteger(1,6),rng:NextInteger(1,6))
   if code=='111' then code='4'..code:sub(2) end -- the dials start on 1 1 1
   local m=placeFeature(kit,mansion,'WallSafe',frameOf(a,r,FEATURE_PUSH),r,'WallSafe_1')
   m:SetAttribute('Kind','safe');m:SetAttribute('SafeCode',code);m:SetAttribute('DisplayName','Old Safe')
   m:SetAttribute('HingeSide',t:GetAttribute('HingeSide') or 1);m:SetAttribute('Note','SafeNote_1')
   featureCollider(kit,mansion,m,r,'WallSafe')
   codeNote(mansion,best,bestRoom,code,'SafeNote_1',rng)
   return 1
  end
 end
 return 0
end

-- Entry point (MapGen.Builder calls it inside pcall). Each line is optional and template-gated. WorldB adds its own
-- feature lines (wall safe, ...) above the marker; the puzzle props (World/CatShelf etc.) add theirs the same way.
function F.WorldFeatures(plan,mansion,kit)
 local rng=Random.new(plan.seed+48611)
 local rooms={};for _,r in ipairs(plan.rooms) do if featureRoom(plan,r) then table.insert(rooms,r) end end
 mansion:SetAttribute('FeatureChutes',placeChutes(plan,mansion,kit,rng,rooms)) -- World/LaundryChute
 mansion:SetAttribute('FeatureHatches',placeHatches(plan,mansion,kit,rng,rooms)) -- World/CrawlHatch
 mansion:SetAttribute('FeaturePuzzles',placePuzzles(plan,mansion,kit,rng,rooms)) -- World/CatShelf (+ WorldB LullabyGramophone, SlothToyChest)
 local SAFES_ON=false -- World/WallSafe (WorldB): OFF until its test passes (lead 2026-10-27, pre-publish)
 mansion:SetAttribute('FeatureSafes',SAFES_ON and placeSafe(plan,mansion,kit,rng,rooms) or 0)
 -- world features end
end
return F