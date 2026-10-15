-- Reference manor dressing. Cosmetic parts never block the circulation graph.
local M={}
local function part(parent,name,size,cf,color,material)
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.Wood;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p:SetAttribute('NonBlockingDetail',true);p.Parent=parent;return p
end
local function sign(parent,text,cf,width)
 local board=part(parent,'RoomPlaque',Vector3.new(width or 5,1.1,.12),cf,Color3.fromRGB(45,31,24))
 for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back})do
  local gui=Instance.new('SurfaceGui');gui.Face=face;gui.CanvasSize=Vector2.new(600,110);gui.Parent=board
  local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Text=text;label.TextColor3=Color3.fromRGB(229,202,145);label.Font=Enum.Font.FredokaOne;label.TextScaled=true;label.Parent=gui
 end
end
function M.Apply(mansion,plan)
 if plan.mapKind~='Mansion' then return end
 if mansion.Architecture:FindFirstChild('ManorReferenceDressing') then return end
 local f=Instance.new('Folder');f.Name='ManorReferenceDressing';f.Parent=mansion.Architecture
 local by={};for _,r in ipairs(plan.rooms)do by[r.name]=r end
 local length=plan.length or (by.L0_Starter and by.L0_Starter.z2) or 64
 -- Warm two-sided wood paneling and restrained geometric wallpaper motifs.
 for _,model in ipairs(mansion.Architecture:GetChildren())do
  if model:IsA('Model') and model.Name=='Wall' then
   local wall=model:FindFirstChild('Wallpaper')
   if wall then
    local cf=wall.CFrame;local w=wall.Size.X
    for _,old in ipairs(model:GetChildren())do if old:IsA('BasePart')and(old.Name=='Wainscot'or old.Name=='Trim')then old.Transparency=1;old.CanQuery=false;old.CanCollide=false end end
    wall.Color=Color3.fromRGB(120,103,77)
    for _,side in ipairs({-1,1})do
     part(f,'WoodPaneling',Vector3.new(w,3.1,.06),cf*CFrame.new(0,-5.35,side*.79),Color3.fromRGB(72,47,31))
     part(f,'ChairRail',Vector3.new(w,.17,.09),cf*CFrame.new(0,-3.75,side*.844),Color3.fromRGB(141,108,59))
     part(f,'CrownMolding',Vector3.new(w,.22,.09),cf*CFrame.new(0,6.2,side*.8),Color3.fromRGB(97,67,38))
     for x=-w/2+2,w/2-1,4 do
      part(f,'PanelStile',Vector3.new(.10,2.7,.08),cf*CFrame.new(x,-5.35,side*.8),Color3.fromRGB(108,76,43))
      for _,y in ipairs({-.5,3})do
       local d=part(f,'WallpaperDiamond',Vector3.new(.28,.28,.025),cf*CFrame.new(x,y,side*.735)*CFrame.Angles(0,0,math.pi/4),Color3.fromRGB(145,126,89),Enum.Material.SmoothPlastic)
       d.Transparency=.35
      end
     end
    end
   end
  end
 end
 -- A muted carpet route leads to the entry without adding obstacles.
 for _,r in ipairs(plan.rooms)do
  if r.type=='Hall' or r.type=='Foyer' then
   local w,d=r.x2-r.x1,r.z2-r.z1
   local sx,sz=if w>d then w-2 else math.min(4,w-2),if w>d then math.min(4,d-2) else d-2
   local cf=CFrame.new((r.x1+r.x2)/2,r.level*16+.018,(r.z1+r.z2)/2)
   part(f,'BurgundyRunner',Vector3.new(sx,.025,sz),cf,Color3.fromRGB(81,35,31),Enum.Material.Fabric)
   if r.name:find('_Spine') or r.type=='Foyer' then
    for _,side in ipairs({-1,1})do part(f,'RunnerBorder',Vector3.new(.08,.026,sz),cf*CFrame.new(side*(sx/2-.18),.006,0),Color3.fromRGB(161,124,67),Enum.Material.Fabric)end
   end
  end
 end
 -- Open stair railings follow the existing two flights and never narrow their ramps.
 local brass=Color3.fromRGB(133,98,53);local wood=Color3.fromRGB(73,46,29)
 local function beam(a,b)
  local delta=b-a
  part(f,'StairHandrail',Vector3.new(.20,.20,delta.Magnitude),CFrame.lookAt((a+b)/2,b),wood)
 end
 -- Each generated stair uses the authored bay (centre 18,-18) in its own frame.
 local stairs=plan.stairs or {{cx=18,cz=-18,yaw=0}}
 local function frame(st) local base=CFrame.new(st.cx,0,st.cz)*CFrame.Angles(0,st.yaw or 0,0);return function(x,y,z) return base*CFrame.new(x-18,y,z+18) end end
 for _,st in ipairs(stairs) do
  local at=frame(st)
  for flight=1,2 do
   local x=if flight==1 then 18 else 26
   for _,side in ipairs({-1,1})do
    local first,last
    for i=0,12,2 do
     local y=if flight==1 then i*2/3 else 8+i*2/3
     local z=if flight==1 then -24+i else -12-i
     local p=at(x+side*3.2,y+2.9,z).Position
     part(f,'StairBaluster',Vector3.new(.12,2.9,.12),at(x+side*3.2,y+1.45,z),brass)
     first=first or p;last=p
    end
    beam(first,last)
   end
  end
 end
 -- Hanging candle chandeliers at the entrance and main junctions.
 local function chandelier(x,z)
  local cf=CFrame.new(x,11.5,z);local brass=Color3.fromRGB(111,81,39)
  part(f,'ChandelierChain',Vector3.new(.12,2.2,.12),cf*CFrame.new(0,1.2,0),brass,Enum.Material.Metal)
  local hub=part(f,'ChandelierHub',Vector3.new(.6,.4,.6),cf,brass,Enum.Material.Metal);hub.Shape=Enum.PartType.Ball
  for i=0,5 do
   local rot=CFrame.Angles(0,i*math.pi/3,0)
   part(f,'ChandelierArm',Vector3.new(1.8,.1,.12),cf*rot*CFrame.new(.9,0,0),brass,Enum.Material.Metal)
   local candle=cf*rot*CFrame.new(1.8,.35,0)
   part(f,'Candle',Vector3.new(.18,.65,.18),candle,Color3.fromRGB(223,201,161),Enum.Material.SmoothPlastic)
   local flame=part(f,'CandleFlame',Vector3.new(.12,.24,.12),candle*CFrame.new(0,.43,0),Color3.fromRGB(255,193,86),Enum.Material.Neon);flame.Shape=Enum.PartType.Ball
  end
  local light=Instance.new('PointLight');light.Color=Color3.fromRGB(255,203,135);light.Brightness=.45;light.Range=23;light.Shadows=true;light.Parent=hub
 end
 local start=by[plan.start]
 local entrance=plan.entrance or {x=0,z=length}
 if plan.entrance and start then
  chandelier((start.x1+start.x2)/2,(start.z1+start.z2)/2)
  -- Second chandelier over the first hall off the foyer.
  for _,e in ipairs(plan.edges)do local o=(e.a==start.name and by[e.b])or(e.b==start.name and by[e.a])
   if o and o.type=='Hall' then chandelier((o.x1+o.x2)/2,(o.z1+o.z2)/2);break end
  end
 else chandelier(-6,length-8);chandelier(-6,0) end
 sign(f,'VAN / EXIT',CFrame.new(entrance.x,11.5,entrance.z-.8),8)
 for _,st in ipairs(stairs) do
  local at=frame(st)
  sign(f,'UPSTAIRS',at(5.28,12.4,-18)*CFrame.Angles(0,math.pi/2,0),6)
  for _,side in ipairs({-1,1})do part(f,'UpstairsSignHanger',Vector3.new(.07,1.08,.07),at(5.34,13.48,-18+side*2.3),Color3.fromRGB(103,80,44),Enum.Material.Metal)end
 end
 for _,e in ipairs(plan.edges)do if e.kind=='door' and not e.boarded then
  local a,b=by[e.a],by[e.b];local r=if a.type=='Hall' then b elseif b.type=='Hall' then a else nil
  if r then local cf=if e.axis=='x' then CFrame.new(e.x,e.y+11.25,e.z) else CFrame.new(e.x,e.y+11.25,e.z)*CFrame.Angles(0,math.pi/2,0)
   sign(f,string.upper(r.purpose or r.type),cf,6)
  end
 end end
 -- Paneling and wallpaper motifs inside the sealed space behind a diagonal corner cut would never be seen.
 local AngledCorners=require(script.Parent.AngledCorners)
 for _,p in ipairs(f:GetChildren())do if p:IsA('BasePart') and AngledCorners.Blocked(mansion,p.Position,-0.15) then p:Destroy() end end
 mansion:SetAttribute('ManorReferenceVersion',2)
end
return M