-- One owner for steady map fixtures and the minimum no-flashlight visibility.

local M={}

local VERSION=11 -- 11: owner 2026-10-27 darker maps (fewer working fixtures, dead + flickering ones)

local SPACING=48
local EXTRA_EXPOSURE=.07 -- owner 2026-10-27 playtest: too hard to see far; middle ground (was .03, before that .1) -- was .1 (owner 2026-10-27: darker maps, the flashlight finds things)
local SHADOW_AMBIENT_LIFT=11/255 -- owner 2026-10-27 playtest: shapes readable at mid range (was 8, before that 14) -- 2026-10-27 darker maps: 14 -> 8. History:  -- was 8/255: owner 2026-10-25, even out the view so the beam isn't the only thing you can see

local palettes={

 Mansion={light=Color3.fromRGB(255,204,139),housing=Color3.fromRGB(43,35,29),trim=Color3.fromRGB(116,89,53),brightness=.85,range=24},

 Dungeon={light=Color3.fromRGB(255,204,139),housing=Color3.fromRGB(35,38,34),trim=Color3.fromRGB(89,82,61),brightness=.85,range=24},

 Cruise={light=Color3.fromRGB(255,206,150),housing=Color3.fromRGB(58,40,28),trim=Color3.fromRGB(184,145,63),brightness=1.05,range=28},

 Birthday={light=Color3.fromRGB(255,204,139),housing=Color3.fromRGB(48,32,47),trim=Color3.fromRGB(111,74,88),brightness=1.1,range=28},

}

local stoneColors={Color3.fromRGB(112,119,106),Color3.fromRGB(105,115,119),Color3.fromRGB(124,114,99)}

local oldColors={Color3.fromRGB(65,70,61),Color3.fromRGB(57,63,65),Color3.fromRGB(72,64,55)}

function M.Global(kind)

 local L=game:GetService('Lighting')
 -- LobbyLighting owns the menu; map preparation must not flash mission lighting over it.
 local lobby=game:GetService('ReplicatedStorage'):FindFirstChild('LobbyState')
 if lobby and lobby:GetAttribute('Mode')=='Menu' and not(game.PrivateServerId~='' and game.PrivateServerOwnerId==0) then return end


 L.ClockTime=0;L.Brightness=.2

 L.Ambient=Color3.fromRGB(16,17,23)

 L.OutdoorAmbient=Color3.fromRGB(22,24,32)

 L.ExposureCompensation=.162

 L.EnvironmentDiffuseScale=.22;L.EnvironmentSpecularScale=.25

 L.GlobalShadows=true;L.ShadowSoftness=.32

 if true then L.Ambient=Color3.fromRGB(70,56,42);L.OutdoorAmbient=Color3.fromRGB(28,27,32);L.ExposureCompensation=.42;L.EnvironmentDiffuseScale=.45 end
 

 
 -- Mall: sickly fluorescent grade and dusty air; every other kind resets to the shared look.
 local grade=L:FindFirstChild('MallGrade') or Instance.new('ColorCorrectionEffect');grade.Name='MallGrade';grade.Parent=L
 local air=L:FindFirstChildOfClass('Atmosphere')
 if kind=='Cruise' then
  -- night at sea: warm interiors, moonlit blue exterior so the hull reads from the water
  L.Ambient=Color3.fromRGB(62,52,44);L.OutdoorAmbient=Color3.fromRGB(62,80,112);L.ExposureCompensation+=.08
  grade.Enabled=true;grade.TintColor=Color3.fromRGB(236,246,255);grade.Saturation=.04;grade.Contrast=.08;grade.Brightness=0
  if air then air.Density=.32;air.Haze=1.4;air.Color=Color3.fromRGB(34,52,74);air.Glare=0;air.Offset=.1 end
 elseif kind=='Hotel' then
  -- faded grand hotel at night: warm amber lamps, deep shadows, dusty air
  L.Ambient=Color3.fromRGB(52,38,30);L.OutdoorAmbient=Color3.fromRGB(22,18,16);L.ExposureCompensation-=.1
  grade.Enabled=true;grade.TintColor=Color3.fromRGB(255,236,214);grade.Saturation=-.14;grade.Contrast=.12;grade.Brightness=-.01
  if air then air.Density=.46;air.Haze=2.0;air.Color=Color3.fromRGB(58,42,34);air.Glare=0;air.Offset=0 end
 elseif kind=='Hospital' then
  -- abandoned hospital: cold green-grey, desaturated, thick stale air
  L.Ambient=Color3.fromRGB(40,48,44);L.OutdoorAmbient=Color3.fromRGB(20,24,22);L.ExposureCompensation-=.18
  grade.Enabled=true;grade.TintColor=Color3.fromRGB(226,255,236);grade.Saturation=-.32;grade.Contrast=.14;grade.Brightness=-.01
  if air then air.Density=.52;air.Haze=2.4;air.Color=Color3.fromRGB(44,56,50);air.Glare=0;air.Offset=0 end
 elseif kind=='School' then
  -- abandoned elementary school: dusty, sour yellow-grey, dim and still
  L.Ambient=Color3.fromRGB(50,48,40);L.OutdoorAmbient=Color3.fromRGB(24,24,22);L.ExposureCompensation-=.16
  grade.Enabled=true;grade.TintColor=Color3.fromRGB(255,244,220);grade.Saturation=-.28;grade.Contrast=.13;grade.Brightness=-.01
  if air then air.Density=.5;air.Haze=2.3;air.Color=Color3.fromRGB(58,54,44);air.Glare=0;air.Offset=0 end
 elseif kind=='Mall' then
  L.Ambient=Color3.fromRGB(54,52,41);L.OutdoorAmbient=Color3.fromRGB(26,26,23);L.ExposureCompensation-=.12
  grade.Enabled=true;grade.TintColor=Color3.fromRGB(255,249,228);grade.Saturation=-.16;grade.Contrast=.07;grade.Brightness=0
  if air then air.Density=.48;air.Haze=2.1;air.Color=Color3.fromRGB(62,58,44) end
 else
  -- owner 2026-10-28 "more ominous": the mansion gets a cold, drained grade with heavier contrast; fog distance and
  -- exposure stay as the 2026-10-27 playtest set them, so it reads as dread, not as darkness.
  grade.Enabled=true;grade.TintColor=Color3.fromRGB(230,236,255);grade.Saturation=-.24;grade.Contrast=.14;grade.Brightness=0
  if air then air.Density=.45;air.Haze=1.5;air.Color=Color3.fromRGB(28,28,32);air.Offset=0 end -- 2026-10-27: back to the old fog distance (the darker .52/1.8 hid everything past mid range)
 end
 -- The open sea needs the void baseplate gone (its top sits at y=-1, above the water); every other map keeps it.
 local base=workspace:FindFirstChild('Baseplate')
 if base and base:IsA('BasePart') then local sea=kind=='Cruise';base.Transparency=sea and 1 or 0;base.CanCollide=not sea;base.CanQuery=not sea end
 -- owner 2026-10-28 "more ominous": every map a little more drained and contrasty (Cruise keeps its moonlit blue).
 if grade.Enabled and kind~='Cruise' then grade.Saturation-=.06;grade.Contrast+=.04 end
 -- Keep shadow detail visible when higher graphics settings render full shadows.
 L.ExposureCompensation+=EXTRA_EXPOSURE
 local a=L.Ambient
 L.Ambient=Color3.new(math.min(1,a.R+SHADOW_AMBIENT_LIFT),math.min(1,a.G+SHADOW_AMBIENT_LIFT),math.min(1,a.B+SHADOW_AMBIENT_LIFT))

 L:SetAttribute('StartupLightingMode','Mission')
end

function M.Stone(mansion)

 if mansion:GetAttribute('MapKind')~='Dungeon' then return end

 for _,object in ipairs(mansion.Architecture:GetChildren()) do

  local wall=object.Name=='Wall' or object.Name=='WallDoor' or object.Name=='WallWindow' or object.Name=='PortalUpperFrieze'

  if not wall then continue end

  local parts=object:IsA('BasePart') and {object} or object:GetDescendants()

  for _,p in ipairs(parts) do if p:IsA('BasePart') and p:GetAttribute('Surface')~='glass' then

   p.MaterialVariant='';p.Material=Enum.Material.SmoothPlastic;p.Reflectance=0

   if not p:GetAttribute('DungeonBlocks') then p.Color=Color3.fromRGB(87,84,78) end

   if p:IsA('MeshPart') then p.TextureID='' end

   for _,d in ipairs(p:GetChildren()) do if d:IsA('SurfaceAppearance') or d:IsA('Texture') or d:IsA('Decal') then d:Destroy() end end

  end end

 end

 for _,p in ipairs(mansion.Furniture:GetDescendants()) do if p:IsA('MeshPart') and (p:GetAttribute('Surface')=='masonry' or p:GetAttribute('Surface')=='brick_old') then p.TextureID='';p.MaterialVariant='';p.Material=Enum.Material.SmoothPlastic end end

 mansion:SetAttribute('StoneFinishVersion',VERSION)

end

function M.Apply(mansion,plan,kit)

 M.Global(plan.mapKind);require(script.Parent.DungeonWalls).Apply(mansion);M.Stone(mansion)

 M.Fixtures(mansion,plan,kit)
 require(script.Parent.MaterialFinish).Apply(mansion)
 require(script.Parent.ManorReferenceFinish).Apply(mansion,plan)
 local okCruise,whyCruise=pcall(require(script.Parent.CruiseWorld).Apply,mansion,plan,kit)
 if not okCruise then warn('[MapLighting] cruise world failed: '..tostring(whyCruise)) end
 local okMall,whyMall=pcall(require(script.Parent.MallDressing).Apply,mansion,plan,kit)
 if not okMall then warn('[MapLighting] mall dressing failed: '..tostring(whyMall)) end
 local okHotel,whyHotel=pcall(require(script.Parent.HotelDressing).Apply,mansion,plan,kit)
 if not okHotel then warn('[MapLighting] hotel dressing failed: '..tostring(whyHotel)) end
 local okHosp,whyHosp=pcall(require(script.Parent.HospitalDressing).Apply,mansion,plan,kit)
 if not okHosp then warn('[MapLighting] hospital dressing failed: '..tostring(whyHosp)) end
 local okSchool,whySchool=pcall(require(script.Parent.SchoolDressing).Apply,mansion,plan,kit)
 if not okSchool then warn('[MapLighting] school dressing failed: '..tostring(whySchool)) end
 local okRevamp,whyRevamp=pcall(require(script.Parent.RevampDressing).Apply,mansion,plan)
 if not okRevamp then warn('[MapLighting] revamp dressing failed: '..tostring(whyRevamp)) end
 pcall(M.UnblockDrawers,mansion)
end

-- A furniture collision box (desk, kiosk, dresser) can enclose a drawer front, so the interact aim ray
-- hits the invisible box and the drawer cannot be opened. Such boxes stay solid but stop catching rays.
function M.UnblockDrawers(mansion)
 local col,inter=mansion:FindFirstChild('Collision'),mansion:FindFirstChild('Interactive')
 if not col or not inter then return end
 local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Include;op.FilterDescendantsInstances={col};op.RespectCanCollide=false
 for _,mv in ipairs(inter:GetChildren())do
  if mv:GetAttribute('Kind')=='drawer' then
   for _,q in ipairs(mv:GetChildren())do
    if q:IsA('BasePart') and q.Transparency<1 then
     for _,box in ipairs(workspace:GetPartBoundsInBox(q.CFrame,q.Size,op))do if box:GetAttribute('Furniture') then box.CanQuery=false end end
    end
   end
  end
 end
end

local function buildFixtures(mansion,plan,kit)
 if mansion:GetAttribute('SteadyLightingVersion')==VERSION and mansion:FindFirstChild('Lights') and mansion.Lights:FindFirstChild('Steady') then return end
 local steadyBefore=mansion:FindFirstChild('Lights') and mansion.Lights:FindFirstChild('Steady')
 for _,l in ipairs(mansion:GetDescendants()) do
  if l:IsA('Light') and not (steadyBefore and l:IsDescendantOf(steadyBefore)) then
   l.Brightness=math.min(l.Brightness,.38)
   l.Range=math.min(l.Range,12);l.Shadows=not(l.Parent.Name=='Shade'or l.Parent.Name=='Diffuser') -- perf: lamp shades/ceiling diffusers light without shadows
   l.Parent:SetAttribute('Flicker',nil)
  end
 end

 local folder=mansion:FindFirstChild('Lights')

 if not folder then folder=Instance.new('Folder');folder.Name='Lights';folder.Parent=mansion end

 local old=folder:FindFirstChild('Steady');if old then old:Destroy() end

 local steady=Instance.new('Folder');steady.Name='Steady';steady.Parent=folder

 local palette=palettes[plan.mapKind or mansion:GetAttribute('MapKind')] or palettes.Mansion
 if (plan.mapKind or mansion:GetAttribute('MapKind'))=='Hotel' then
  local c,lit=require(script.Parent.HotelDressing).Fixtures(mansion,plan,steady)
  mansion:SetAttribute('SteadyFixtureCount',c);mansion:SetAttribute('HotelLitFixtures',lit);mansion:SetAttribute('SteadyLightingVersion',VERSION)
  return
 end
 if (plan.mapKind or mansion:GetAttribute('MapKind'))=='School' then
  -- same failing fluorescent troffers as the hospital: a school corridor ceiling
  local c,lit=require(script.Parent.HospitalDressing).Fixtures(mansion,plan,steady)
  mansion:SetAttribute('SteadyFixtureCount',c);mansion:SetAttribute('SchoolLitFixtures',lit);mansion:SetAttribute('SteadyLightingVersion',VERSION)
  return
 end
 if (plan.mapKind or mansion:GetAttribute('MapKind'))=='Hospital' then
  local c,lit=require(script.Parent.HospitalDressing).Fixtures(mansion,plan,steady)
  mansion:SetAttribute('SteadyFixtureCount',c);mansion:SetAttribute('HospitalLitFixtures',lit);mansion:SetAttribute('SteadyLightingVersion',VERSION)
  return
 end
 if (plan.mapKind or mansion:GetAttribute('MapKind'))=='Mall' then
  local c,lit=require(script.Parent.MallDressing).Fixtures(mansion,plan,steady)
  mansion:SetAttribute('SteadyFixtureCount',c);mansion:SetAttribute('MallLitFixtures',lit);mansion:SetAttribute('SteadyLightingVersion',VERSION)
  return
 end

 local count=0

 local function part(name,size,cf,color,material,parent)

  local p=kit.Table.PrimaryPart:Clone()

  p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material

  p.Transparency=0;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false

  p.Parent=parent;return p

 end

 local function fixture(r,x,y,z,wall,yaw)

  count+=1

  local model=Instance.new('Model');model.Name=r.name..'_Steady_'..count;model:SetAttribute('Room',r.name);model.Parent=steady

  local cf=CFrame.new(x,y,z)*CFrame.Angles(0,yaw or 0,0)

  local housing
  local trim=palette.trim or palette.housing
  local function disk(name,diameter,height,offset,color)
   local p=part(name,Vector3.new(height,diameter,diameter),cf*CFrame.new(0,offset,0)*CFrame.Angles(0,0,math.pi/2),color,Enum.Material.SmoothPlastic,model)
   p.Shape=Enum.PartType.Cylinder;return p
  end
  local glow
  if wall then
   housing=part('WallPlate',Vector3.new(.16,2,1),cf,palette.housing,Enum.Material.SmoothPlastic,model)
   part('Bracket',Vector3.new(.65,.14,.2),cf*CFrame.new(-.35,-.55,0),trim,Enum.Material.SmoothPlastic,model)
   local center=cf*CFrame.new(-.62,.05,0)
   part('LanternRoof',Vector3.new(.8,.18,.8),center*CFrame.new(0,.65,0),palette.housing,Enum.Material.SmoothPlastic,model)
   part('LanternFoot',Vector3.new(.75,.16,.75),center*CFrame.new(0,-.65,0),trim,Enum.Material.SmoothPlastic,model)
   for _,zoff in ipairs({-.32,.32}) do part('LanternFrame',Vector3.new(.1,1.2,.1),center*CFrame.new(-.3,0,zoff),palette.housing,Enum.Material.SmoothPlastic,model) end
   glow=part('WarmGlass',Vector3.new(.5,1,.5),center,palette.light,Enum.Material.SmoothPlastic,model)
  else
   housing=disk('CeilingRose',1.55,.13,.32,palette.housing)
   disk('Stem',.18,.45,.06,trim)
   disk('UpperRim',1.4,.16,-.18,palette.housing)
   disk('GlassShade',1.22,.28,-.38,Color3.fromRGB(155,139,112))
   disk('LowerRim',1.35,.08,-.55,trim)
   glow=disk('Diffuser',1.1,.04,-.595,palette.light)
  end
  -- A small luminous core gives the fixture a glow without a glaring white panel.
  if true then
   local core=part('LightCore',Vector3.new(.16,.12,.16),glow.CFrame,palette.light,Enum.Material.Neon,model)
   core.Transparency=.15
  end
  local light=Instance.new(wall and 'PointLight' or 'SpotLight');light.Name='SteadyRoomLight'
  if light:IsA('SpotLight') then light.Face=Enum.NormalId.Left;light.Angle=115 end
  light.Color=palette.light;light.Brightness=palette.brightness or .32
  light.Range=wall and 24 or (palette.range or 22);light.Shadows=false;light.Parent=glow -- perf: room fixtures skip shadows (phones)

  model.PrimaryPart=housing

 end

 for _,r in ipairs(plan.rooms) do

  if r.type=='Stair' then

   -- Mount along the outer stair wall rather than across the open stair shaft.

   local st=plan.stairs and r.stair and plan.stairs[r.stair]
   if st then
    local p=(CFrame.new(st.cx,r.level*16+9,st.cz)*CFrame.Angles(0,st.yaw,0)*CFrame.new(11.1,0,0)).Position
    fixture(r,p.X,p.Y,p.Z,true,st.yaw)
   else fixture(r,29.1,r.level*16+9,-18,true) end

  else

   local w,d=r.x2-r.x1,r.z2-r.z1

   local nx,nz=math.max(1,math.ceil(w/SPACING)),math.max(1,math.ceil(d/SPACING))

   for ix=1,nx do for iz=1,nz do

    fixture(r,r.x1+w*(ix-.5)/nx,r.level*16+12.9,r.z1+d*(iz-.5)/nz,false)

   end end

  end

 end

 mansion:SetAttribute('SteadyFixtureCount',count);mansion:SetAttribute('SteadyLightingVersion',VERSION)

end

-- Owner 2026-10-27 "less lights around the map, the person finds stuff themselves": after the fixtures are built,
-- many go dead (no light, dark glass) and a few flicker (MallFlicker tag, MallFlickerClient), the rest burn dimmer.
-- The start room / foyer and every stair keep all their lights so the way out and the way up stay findable.
-- Maps whose dressing already has dead fixtures (Hotel, Hospital, School, Mall) lose fewer extra ones.
local DEAD_SHARE,FLICKER_SHARE=.3,.1 -- owner playtest 2026-10-27: was .45/.12, too dark -- Mansion / Dungeon (every fixture was lit)
local DRESSED_DEAD_SHARE,DRESSED_FLICKER_SHARE=.12,.05 -- was .22 -- extra on top of the dressing's own dead/flicker rolls
local LIT_BRIGHTNESS,LIT_RANGE=1,1 -- was .85/.9: working lights burn at full strength again -- what the surviving fixtures outside the safe rooms keep
local function darkenFixtures(mansion,plan,steady)
 local kind=plan.mapKind or mansion:GetAttribute('MapKind')
 local dressed=kind=='Hotel'or kind=='Hospital'or kind=='School'or kind=='Mall'
 local deadShare,flickerShare=dressed and DRESSED_DEAD_SHARE or DEAD_SHARE,dressed and DRESSED_FLICKER_SHARE or FLICKER_SHARE
 local types={}
 for _,r in ipairs(plan.rooms or {})do if r.name then types[r.name]=r.type end end
 local rng=Random.new((plan.seed or 1)+2710)
 local dead,flicker,kept=0,0,0
 for _,model in ipairs(steady:GetChildren())do
  local room=model:GetAttribute('Room')
  local safe=room==nil or room==plan.start or types[room]=='Foyer'or types[room]=='Stair'or model.Name:find('Stair')~=nil
  local lights={}
  for _,l in ipairs(model:GetDescendants())do if l:IsA('Light')and l.Enabled and l.Brightness>0 then table.insert(lights,l)end end
  if safe or #lights==0 then continue end
  local roll=rng:NextNumber()
  if roll<deadShare then
   dead+=1
   for _,l in ipairs(lights)do l:Destroy()end
   for _,p in ipairs(model:GetDescendants())do
    if p:IsA('BasePart')then
     p:RemoveTag('MallFlicker')
     if p.Material==Enum.Material.Neon or p.Name=='Diffuser'or p.Name=='WarmGlass'or p.Name=='LightCore'then
      p.Material=Enum.Material.SmoothPlastic;p.Color=p.Color:Lerp(Color3.fromRGB(20,18,16),.6);p.Transparency=math.min(p.Transparency,.05)
     end
    end
   end
   model:SetAttribute('DeadFixture',true)
  else
   kept+=1
   for _,l in ipairs(lights)do l.Brightness*=LIT_BRIGHTNESS;l.Range*=LIT_RANGE end
   if roll<deadShare+flickerShare then
    local host=lights[1].Parent
    if host and host:IsA('BasePart')and not host:HasTag('MallFlicker')then host:AddTag('MallFlicker');flicker+=1 end
   end
  end
 end
 steady:SetAttribute('Darkened',VERSION)
 mansion:SetAttribute('DeadFixtures',dead);mansion:SetAttribute('FlickerFixtures',flicker);mansion:SetAttribute('DimmedFixtures',kept)
end

function M.Fixtures(mansion,plan,kit)
 buildFixtures(mansion,plan,kit)
 local folder=mansion:FindFirstChild('Lights');local steady=folder and folder:FindFirstChild('Steady')
 if steady and steady:GetAttribute('Darkened')~=VERSION then darkenFixtures(mansion,plan,steady)end
end

return M
