-- Mall map finish: textures, fluorescent troffers, dead store signs, hall furniture and litter.
-- Cosmetic only: every added part is non-blocking except hall furniture, which stands
-- against the long hall walls and keeps clear of every opening (the hall centre stays free).
local M={}
local AC=require(script.Parent.AngledCorners)
local TEX={wall='rbxassetid://88597261093552',floor='rbxassetid://115476577835717',ceiling='rbxassetid://118464665144425',stain='rbxassetid://127146470627454'}
local LIGHT=Color3.fromRGB(236,230,196)
local DEAD=Color3.fromRGB(118,116,104)

local function part(parent,name,size,cf,color,material)
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 p:SetAttribute('NonBlockingDetail',true);p.Parent=parent;return p
end
local function texture(p,img,face,u,v,transp)
 local t=Instance.new('Texture');t.Texture=img;t.Face=face;t.StudsPerTileU=u;t.StudsPerTileV=v;t.Transparency=transp or 0;t.Parent=p;return t
end

function M.Surfaces(mansion)
 local n=0
 for _,p in ipairs(mansion.Architecture:GetDescendants()) do if p:IsA('BasePart') then
  local s=p:GetAttribute('Surface')
  if s=='mallfloor' then p.Material=Enum.Material.SmoothPlastic;p.Reflectance=.06;texture(p,TEX.floor,Enum.NormalId.Top,4,4);n+=1
  elseif s=='mallceiling' then texture(p,TEX.ceiling,Enum.NormalId.Bottom,4,4);n+=1
  elseif s=='wallpaper' and p.Transparency<1 then
   for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do texture(p,TEX.wall,face,4,4) end;n+=1
  end
 end end
 return n
end

-- 2x4 recessed troffers. About one in eight is dead, one in six flickers (MallFlickerClient).
function M.Troffer(parent,cf,rng,room)
 local model=Instance.new('Model');model.Name='MallTroffer';model:SetAttribute('Room',room);model.Parent=parent
 local frame=part(model,'TrofferFrame',Vector3.new(2.3,.12,4.3),cf,Color3.fromRGB(190,186,170))
 local roll=rng:NextNumber()
 local dead=roll<.12
 local lens=part(model,'Diffuser',Vector3.new(2,.06,4),cf*CFrame.new(0,-.07,0),dead and DEAD or LIGHT,dead and Enum.Material.SmoothPlastic or Enum.Material.Neon)
 for _,x in ipairs({-.5,.5}) do part(model,'Louver',Vector3.new(.06,.08,4),cf*CFrame.new(x,-.1,0),Color3.fromRGB(170,166,150)) end
 model.PrimaryPart=frame
 if dead then return model,false end
 lens.Transparency=.12
 local l=Instance.new('SurfaceLight');l.Name='SteadyRoomLight';l.Face=Enum.NormalId.Bottom;l.Angle=120;l.Range=22;l.Brightness=.7;l.Color=LIGHT;l.Shadows=false;l.Parent=lens
 if roll>.84 then lens:AddTag('MallFlicker') end
 return model,true
end

function M.Fixtures(mansion,plan,steady)
 local rng=Random.new(plan.seed+4242);local count,lit=0,0
 for _,r in ipairs(plan.rooms) do
  if r.type=='Stair' then
   local st=plan.stairs and r.stair and plan.stairs[r.stair]
   if st then
    local s=st.horizontalScale or 1
    local cf=CFrame.new(st.cx,r.level*16+13.9,st.cz)*CFrame.Angles(0,st.yaw,0)*CFrame.new(4*s,0,0)
    -- no panel over the steps; a dim wall-mounted fixture on the outer stair wall instead
    local wall=CFrame.new(st.cx,r.level*16+8.5,st.cz)*CFrame.Angles(0,st.yaw,0)*CFrame.new(11.1*s,0,0)
    local model=Instance.new('Model');model.Name='MallStairLight';model:SetAttribute('Room',r.name);model.Parent=steady
    local plate=part(model,'WallPlate',Vector3.new(.2,1.2,2.4),wall,Color3.fromRGB(150,146,130))
    local lens=part(model,'Diffuser',Vector3.new(.12,.8,2),wall*CFrame.new(-.14,0,0),LIGHT,Enum.Material.Neon);lens.Transparency=.15
    local l=Instance.new('PointLight');l.Name='SteadyRoomLight';l.Range=20;l.Brightness=.75;l.Color=LIGHT;l.Shadows=false;l.Parent=lens
    model.PrimaryPart=plate;count+=1;lit+=1
   end
  else
   local w,d=r.x2-r.x1,r.z2-r.z1
   local spacing=r.type=='Hall' and 22 or 23
   local nx,nz=math.max(1,math.floor(w/spacing+.5)),math.max(1,math.floor(d/spacing+.5))
   local alongX=w>=d
   for ix=1,nx do for iz=1,nz do
    local cf=CFrame.new(r.x1+w*(ix-.5)/nx,r.level*16+13.94,r.z1+d*(iz-.5)/nz)*(alongX and CFrame.Angles(0,math.pi/2,0) or CFrame.new())
    local _,on=M.Troffer(steady,cf,rng,r.name);count+=1;lit+=on and 1 or 0
   end end
  end
 end
 return count,lit
end

local function sign(parent,text,cf,rng)
 local board=part(parent,'StoreSign',Vector3.new(5.4,1.05,1.7),cf,Color3.fromRGB(38,36,34))
 local dead=rng:NextNumber()<.3
 for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
  local gui=Instance.new('SurfaceGui');gui.Face=face;gui.CanvasSize=Vector2.new(640,124);gui.LightInfluence=dead and 1 or .25;gui.Brightness=dead and 1 or 1.4;gui.Parent=board
  local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(.94,.8);label.Position=UDim2.fromScale(.03,.1);label.BackgroundTransparency=1
  label.Text=string.upper(text);label.Font=Enum.Font.Michroma;label.TextScaled=true
  label.TextColor3=dead and Color3.fromRGB(92,88,80) or Color3.fromRGB(226,206,150);label.Parent=gui
 end
 if not dead and rng:NextNumber()<.35 then board:AddTag('MallFlicker') end
end

function M.Signs(mansion,plan,folder)
 local by={};for _,r in ipairs(plan.rooms) do by[r.name]=r end
 local rng=Random.new(plan.seed+911);local n=0
 for _,e in ipairs(plan.edges) do if e.kind=='door' then
  local a,b=by[e.a],by[e.b]
  if a and b then
   local hall=(a.type=='Hall' and b.type~='Hall' and b.type~='Stair' and a) or (b.type=='Hall' and a.type~='Hall' and a.type~='Stair' and b)
   if hall then
    local shop=hall==a and b or a
    local cf=e.axis=='x' and CFrame.new(e.x,e.y+11.6,e.z) or CFrame.new(e.x,e.y+11.6,e.z)*CFrame.Angles(0,math.pi/2,0)
    sign(folder,shop.purpose or shop.type,cf,rng);n+=1
   end
  end
 end end
 return n
end

-- Hall furniture against the long hall walls, facing the concourse.
-- Creature routes run hall centre -> a strip ~3.2 studs inside a doorway wall -> along it to the
-- door, so a wall only takes props outside [centre..door] on that wall, never across the centre
-- projection, never near any opening, and never over a Furnisher keepout (rotated AABB).
local HALL={'MallBench','MallPlanter','MallTrash','MallBench','MallVending','MallPlanter','MallArcade','MallLamp','MallMannequin','MallCart','MallWetSign'}
function M.HallFurniture(mansion,plan,kit,folder)
 local F=require(script.Parent.Furnisher)
 local rng=Random.new(plan.seed+5150);local count=0;local lamps=0
 for _,r in ipairs(plan.rooms) do if r.type=='Hall' and r.name~=plan.start then
  local w,d=r.x2-r.x1,r.z2-r.z1
  local alongX=w>=d;local len=if alongX then w else d;local wide=if alongX then d else w
  if wide<14 or len<20 then continue end
  local a0=if alongX then r.x1 else r.z1
  local a1=if alongX then r.x2 else r.z2
  local centre=(a0+a1)/2
  local okKeep,keep=pcall(F.Keepouts,plan,r);if not okKeep then keep={} end
  for _,side in ipairs({-1,1}) do
   local wallLine=if side<0 then (if alongX then r.z1 else r.x1) else (if alongX then r.z2 else r.x2)
   -- forbidden intervals along this wall
   local bans={}
   for _,e in ipairs(plan.edges) do
    if math.abs((e.y or 0)-r.level*16)<1 and (e.a==r.name or e.b==r.name) then
     local ea=if alongX then e.x else e.z
     local ec=if alongX then e.z else e.x
     local half=(e.span or e.width or 8)/2
     local parallel=(alongX and e.axis=='x') or (not alongX and e.axis=='z')
     if parallel and math.abs(ec-wallLine)<2.5 then
      table.insert(bans,{math.min(ea-half,centre)-3,math.max(ea+half,centre)+3})
     elseif not parallel then
      table.insert(bans,{ea-half-8,ea+half+8}) -- an opening in an end wall
     end
    end
   end
   table.insert(bans,{centre-6,centre+6})
   local t=a0+5+rng:NextNumber()*4
   while t<a1-5 do
    local name=HALL[rng:NextInteger(1,#HALL)]
    local template=kit:FindFirstChild(name)
    if not template then t+=4;continue end
    local fp=template:GetAttribute('Footprint');local fw,fd=fp.X,fp.Z
    local along=t+fw/2
    if along+fw/2>a1-5 then break end
    local clear=true
    for _,b in ipairs(bans) do if along+fw/2>b[1] and along-fw/2<b[2] then clear=false;break end end
    local across=wallLine-side*(fd/2+.9)
    local x=if alongX then along else across
    local z=if alongX then across else along
    if clear then
     local box={x=x,z=z,w=if alongX then fw else fd,d=if alongX then fd else fw}
     for _,k in ipairs(keep) do
      if k.x and k.w and math.abs(box.x-k.x)<(box.w+k.w)/2+.2 and math.abs(box.z-k.z)<(box.d+k.d)/2+.2 then clear=false;break end
     end
    end
    if clear then
     -- template front is -Z; LookVector of yaw y is (-sin y,0,-cos y)
     local yaw=if alongX then (if side<0 then math.pi else 0) else (if side<0 then -math.pi/2 else math.pi/2)
     if name=='MallCart' or name=='MallWetSign' then yaw+=rng:NextNumber(-.5,.5) end
     local finalCF=CFrame.new(x,r.level*16,z)*CFrame.Angles(0,yaw,0)
     if AC.FootprintBlocked(mansion,finalCF,fp,0.5) then t+=3;continue end
     local m=template:Clone();m.Name='Hall_'..name;m:PivotTo(finalCF);m:SetAttribute('Room',r.name);m:SetAttribute('MallHallProp',true)
     for _,p in ipairs(m:GetDescendants()) do if p:IsA('BasePart') then
      p.Anchored=true;p.CanTouch=false;p.CanQuery=false;p:SetAttribute('Room',r.name);p:SetAttribute('NonBlockingDetail',true)
      if name=='MallWetSign' or name=='MallLamp' or name=='MallCart' then p.CanCollide=false end
     end end
     if name=='MallLamp' and lamps<10 then local shade=m:FindFirstChild('Shade');if shade then local l=Instance.new('PointLight');l.Color=Color3.fromRGB(255,214,150);l.Range=14;l.Brightness=.6;l.Shadows=false;l.Parent=shade;lamps+=1 end end
     m.Parent=folder;count+=1
     t+=fw+5+rng:NextNumber()*9
    else t+=3 end
   end
  end
 end end
 return count
end

-- Neglect: paper litter, dark puddles, fallen ceiling tiles and water stains overhead.
function M.Litter(mansion,plan,folder)
 local rng=Random.new(plan.seed+777);local n=0
 for _,r in ipairs(plan.rooms) do if r.type~='Stair' then
  local w,d=r.x2-r.x1,r.z2-r.z1;local y=r.level*16
  local area=w*d
  for _=1,math.min(10,math.floor(area/260)) do
   local x,z=rng:NextNumber(r.x1+2,r.x2-2),rng:NextNumber(r.z1+2,r.z2-2)
   local size=Vector3.new(rng:NextNumber(.6,1.1),.03,rng:NextNumber(.8,1.3))
   if AC.Blocked(mansion,Vector3.new(x,y,z),math.sqrt(size.X*size.X+size.Z*size.Z)/2) then continue end
   local p=part(folder,'Litter',size,CFrame.new(x,y+.02,z)*CFrame.Angles(0,rng:NextNumber(0,6.28),0),rng:NextNumber()<.7 and Color3.fromRGB(214,208,190) or Color3.fromRGB(150,120,84))
   n+=1
  end
  for _=1,math.min(3,math.floor(area/900)) do
   local x,z=rng:NextNumber(r.x1+3,r.x2-3),rng:NextNumber(r.z1+3,r.z2-3)
   local s=rng:NextNumber(2.5,5)
   if AC.Blocked(mansion,Vector3.new(x,y,z),s/2+0.3) then continue end
   local puddle=part(folder,'Puddle',Vector3.new(.03,s,s*rng:NextNumber(.6,1)),CFrame.new(x,y+.015,z)*CFrame.Angles(0,rng:NextNumber(0,6.28),math.pi/2),Color3.fromRGB(86,88,80),Enum.Material.Glass)
   puddle.Shape=Enum.PartType.Cylinder;puddle.Transparency=.55;puddle.Reflectance=.5
   local stain=part(folder,'CeilingStain',Vector3.new(s*1.2,.02,s*1.2),CFrame.new(x,y+13.98,z),Color3.new(1,1,1))
   stain.Transparency=1;local dcl=Instance.new('Decal');dcl.Texture=TEX.stain;dcl.Face=Enum.NormalId.Bottom;dcl.Parent=stain
   n+=1
  end
  if r.type=='Hall' and rng:NextNumber()<.5 then
   local x,z=rng:NextNumber(r.x1+4,r.x2-4),rng:NextNumber(r.z1+4,r.z2-4)
   if AC.Blocked(mansion,Vector3.new(x,y,z),3.8*0.7072+0.3) then continue end
   local tile=part(folder,'FallenCeilingTile',Vector3.new(3.8,.35,3.8),CFrame.new(x,y+.4,z)*CFrame.Angles(rng:NextNumber(-.15,.15),rng:NextNumber(0,6.28),rng:NextNumber(.08,.2)),Color3.fromRGB(214,208,186))
   texture(tile,TEX.ceiling,Enum.NormalId.Top,4,4)
   local hole=part(folder,'CeilingHole',Vector3.new(3.9,.05,3.9),CFrame.new(x,y+13.96,z),Color3.fromRGB(16,15,14))
   n+=1
  end
 end end
 return n
end

-- Shop fill: big Mall rooms get extra wall-side fixtures so the 1.85x floor area never reads
-- empty. Same route rules as the hall props: nothing between the room centre and a door on a
-- doorway wall, nothing near a door or corner door, nothing over existing furniture/movers.
local FILL={Dining={'MallVending','MallTrash','MallBench','MallPlanter','MallVending'},Kitchen={'MallCounter','MallShelf','MallCrate'},Pantry={'MallShelf','MallCrate','MallShelf'},Storage={'MallShelf','MallCrate','MallWetSign'},AtticStorage={'MallShelf','MallCrate'},Laundry={'MallShelf','MallCrate','MallWetSign'},Music={'MallArcade','MallArcade','MallVending'},Library={'MallRack','MallShelf','MallDisplay'},Conservatory={'MallPlanter','MallPlanter','MallBench'},Servants={'MallVending','MallBench','MallTrash'},Study={'MallShelf','MallCrate'},Foyer={'MallPlanter','MallBench','MallTrash'}}
local SHOP={'MallRack','MallShelf','MallDisplay','MallMannequin','MallRack','MallPlanter'}
local function worldBox(m)
 local cf,size=m:GetBoundingBox()
 local flip=math.abs(cf.RightVector.X)<.5
 return {x=cf.X,z=cf.Z,w=flip and size.Z or size.X,d=flip and size.X or size.Z}
end
function M.RoomFill(mansion,plan,kit,folder)
 local F=require(script.Parent.Furnisher)
 local rng=Random.new(plan.seed+6061);local count=0
 for _,r in ipairs(plan.rooms) do if r.type~='Hall' and r.type~='Stair' and r.name~=plan.start then
  local w,d=r.x2-r.x1,r.z2-r.z1;local area=w*d
  local want=math.min(6,math.floor(area/480));if want<1 then continue end
  local pool=FILL[r.type] or SHOP
  local okKeep,keep=pcall(F.Keepouts,plan,r);if not okKeep then keep={} end
  local boxes={}
  for _,folderName in ipairs({'Furniture','Interactive'}) do local f=mansion:FindFirstChild(folderName)
   if f then for _,m in ipairs(f:GetChildren()) do if m:IsA('Model') and (m:GetAttribute('Room')==r.name or m.Name:sub(1,#r.name+1)==r.name..'_') then table.insert(boxes,worldBox(m)) end end end
  end
  local cx,cz=(r.x1+r.x2)/2,(r.z1+r.z2)/2
  local walls={{alongX=true,line=r.z1,side=-1},{alongX=true,line=r.z2,side=1},{alongX=false,line=r.x1,side=-1},{alongX=false,line=r.x2,side=1}}
  for i=#walls,2,-1 do local j=rng:NextInteger(1,i);walls[i],walls[j]=walls[j],walls[i] end
  local placed=0
  for _,wall in ipairs(walls) do
   if placed>=want then break end
   local alongX=wall.alongX
   local a0=if alongX then r.x1 else r.z1
   local a1=if alongX then r.x2 else r.z2
   local centre=if alongX then cx else cz
   local bans={}
   for _,e in ipairs(plan.edges) do
    if math.abs((e.y or 0)-r.level*16)<1 and (e.a==r.name or e.b==r.name) then
     local ea=if alongX then e.x else e.z
     local ec=if alongX then e.z else e.x
     local half=(e.span or e.width or 8)/2
     local parallel=(alongX and e.axis=='x') or (not alongX and e.axis=='z')
     if parallel and math.abs(ec-wall.line)<2.5 then
      table.insert(bans,{math.min(ea-half,centre)-3,math.max(ea+half,centre)+3})
     elseif not parallel and math.abs(ea-wall.line)<half+9 then
      -- a door in the adjoining wall close to this corner
      if math.abs(ec-a0)<math.abs(ec-a1) then table.insert(bans,{a0-1,a0+10}) else table.insert(bans,{a1-10,a1+1}) end
     end
    end
   end
   local t=a0+3+rng:NextNumber()*4
   while t<a1-3 and placed<want do
    local name=pool[rng:NextInteger(1,#pool)]
    local template=kit:FindFirstChild(name)
    if not template then t+=4;continue end
    local fp=template:GetAttribute('Footprint');local fw,fd=fp.X,fp.Z
    local along=t+fw/2
    if along+fw/2>a1-3 then break end
    local clear=true
    for _,b in ipairs(bans) do if along+fw/2>b[1] and along-fw/2<b[2] then clear=false;break end end
    local across=wall.line-wall.side*(fd/2+.9)
    local x=if alongX then along else across
    local z=if alongX then across else along
    local box={x=x,z=z,w=if alongX then fw else fd,d=if alongX then fd else fw}
    if clear then for _,k in ipairs(keep) do if k.x and k.w and math.abs(box.x-k.x)<(box.w+k.w)/2+.3 and math.abs(box.z-k.z)<(box.d+k.d)/2+.3 then clear=false;break end end end
    if clear then for _,k in ipairs(boxes) do if math.abs(box.x-k.x)<(box.w+k.w)/2+1 and math.abs(box.z-k.z)<(box.d+k.d)/2+1 then clear=false;break end end end
    if clear then
     local yaw=if alongX then (if wall.side<0 then math.pi else 0) else (if wall.side<0 then -math.pi/2 else math.pi/2)
     local finalCF=CFrame.new(x,r.level*16,z)*CFrame.Angles(0,yaw,0)
     if AC.FootprintBlocked(mansion,finalCF,fp,0.5) then t+=2;continue end
     local m=template:Clone();m.Name='Fill_'..name;m:PivotTo(finalCF);m:SetAttribute('Room',r.name);m:SetAttribute('MallHallProp',true)
     for _,p in ipairs(m:GetDescendants()) do if p:IsA('BasePart') then
      p.Anchored=true;p.CanTouch=false;p.CanQuery=false;p:SetAttribute('Room',r.name);p:SetAttribute('NonBlockingDetail',true)
      if p:GetAttribute('Role')~='static' then p:SetAttribute('Role','static') end
      if name=='MallWetSign' then p.CanCollide=false end
     end end
     m.Parent=folder;table.insert(boxes,box);count+=1;placed+=1
     t+=fw+2+rng:NextNumber()*6
    else t+=2 end
   end
  end
 end end
 return count
end

-- Storefront windows run into the corner walls; a wall-coloured pillar at each end hides the
-- overlapping glass/bulkhead ends so every corner reads as one clean wall.
function M.WindowEnds(mansion,folder)
 local n=0
 for _,w in ipairs(mansion.Architecture:GetChildren()) do if w:IsA('Model') and w.Name=='WallWindow' then
  local header=w:FindFirstChild('Header');local cf,size=w:GetBoundingBox()
  local color=header and header.Color or Color3.fromRGB(200,196,180)
  for _,e in ipairs({-1,1}) do
   local p=part(folder,'WindowEndPillar',Vector3.new(1.7,size.Y,1.62),cf*CFrame.new(e*(size.X/2-.55),0,0),color,Enum.Material.SmoothPlastic)
   p.CastShadow=true;texture(p,TEX.wall,Enum.NormalId.Front,4,4);texture(p,TEX.wall,Enum.NormalId.Back,4,4);texture(p,TEX.wall,Enum.NormalId.Left,4,4);texture(p,TEX.wall,Enum.NormalId.Right,4,4)
   local base=part(folder,'WindowEndBase',Vector3.new(1.78,1.1,1.7),cf*CFrame.new(e*(size.X/2-.55),-size.Y/2+.55,0),Color3.fromRGB(207,200,184))
   n+=1
  end
 end end
 return n
end

function M.Apply(mansion,plan,kit,steady)
 if plan.mapKind~='Mall' then return end
 if mansion:GetAttribute('MallDressingVersion') then return end
 local folder=Instance.new('Folder');folder.Name='MallDressing';folder.Parent=mansion.Architecture
 local stats={}
 stats.textured=M.Surfaces(mansion)
 stats.signs=M.Signs(mansion,plan,folder)
 stats.windowEnds=M.WindowEnds(mansion,folder)
 local furniture=mansion:FindFirstChild('Furniture') or folder
 stats.hall=M.HallFurniture(mansion,plan,kit,furniture)
 local okFill,filled=pcall(M.RoomFill,mansion,plan,kit,furniture)
 stats.fill=okFill and filled or -1
 if not okFill then warn('[MallDressing] room fill failed: '..tostring(filled)) end
 stats.litter=M.Litter(mansion,plan,folder)
 for k,v in pairs(stats) do mansion:SetAttribute('Mall_'..k,v) end
 mansion:SetAttribute('MallDressingVersion',1)
end
return M
