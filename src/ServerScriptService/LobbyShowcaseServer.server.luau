-- Lobby showcase (2026-10-22): one lit display stand per offer along the two side walls of the lobby hall.
-- West wall, COSMETIC BOUTIQUE: the VIP pass and every aura on statues, every trail. East wall, POWER-UPS & PASSES:
-- the Robux wearables and every other Robux offer. This script builds the static stands; LobbyShowcaseClient spins
-- the items, flies the trail comets, draws each plaque with its BUY button and handles the purchase.
local RS=game:GetService('ReplicatedStorage')
local C=require(RS:WaitForChild('LobbyShopCatalog'))
local Rig=require(RS:WaitForChild('CosmeticRig'))
-- Reserved (mission) servers never show the lobby: building the showcase there only costs every player in the
-- mission ~2,500 always-loaded parts, ~165 lights and running particles 1,200 studs away (frame-cost audit 2026-10-22).
if game.PrivateServerId~=''and game.PrivateServerOwnerId==0 then return end
local world=workspace:WaitForChild('LobbyWorld')
while world:GetAttribute('Ready')~=true do task.wait(.1)end
local PIXEL=Font.new('rbxasset://fonts/families/PressStart2P.json')
local GOLD=Color3.fromRGB(214,168,72)

-- Hall interior: x 1126..1274, z -64..86 (walls), doors in the side walls at z 8 (west) and z 14 (east).
local WALLS={
 {x=1131.5,face=Vector3.new(1,0,0),door=8,title='COSMETIC BOUTIQUE',list='west'},
 {x=1268.5,face=Vector3.new(-1,0,0),door=14,title='POWER-UPS & PASSES',list='east'},
 -- South wall, centred (2026-10-22): one statue per rank aura. Runs along X; min/max are the x range.
 {z=80.5,alongX=true,face=Vector3.new(0,0,-1),min=1171,max=1225,xs={1171,1180,1189,1198,1207,1216,1225},title='RANK AURAS',list='ranks',frame=true}, -- 9-stud steps centred on the wall (the south door was removed 2026-10-22)
 -- North wall, opposite the rank auras (2026-10-22): the rank trails on running statues, same gallery (north door removed).
 {z=-58.5,alongX=true,face=Vector3.new(0,0,1),min=1189,max=1207,xs={1189,1198,1207},title='RANK TRAILS',list='rankTrails',frame=true},
}
local Z_MIN,Z_MAX,DOOR_GAP=-58,80,8
local function offerFor(id)
 return C.RobuxById[id] or C.ById[id]
end
-- What stands on each wall, in order. kind: statue (aura on a statue), comet (trail), model (wearable), card (icon).
local AURA_IDS={'aura_mint','aura_frost','aura_rose','aura_amber','aura_violet','aura_ghost'}
local TRAIL_IDS={'trail_sparks','trail_ectoplasm','trail_glitter','trail_speed','trail_coins','trail_hearts','trail_pumpkinseeds'}
-- Haunted VIP is shown by its overhead HAUNTED VIP tag (title_vip), the way players see it in game.
local west={{id='vip',kind='statue',title='title_vip'}}
for _,id in AURA_IDS do table.insert(west,{id=id,kind='statue',aura=id})end
for _,id in TRAIL_IDS do table.insert(west,{id=id,kind='comet'})end
-- Rank auras, lowest rank first (statues wearing each one; plaques say which rank earns it).
local ranks,rankTrails={},{}
for _,t in require(RS:WaitForChild('RankCatalog')).Tiers do
 for _,id in {t.reward,t.reward2,t.reward3}do local c=id and C.ById[id];if c and c.kind=='Aura'then table.insert(ranks,{id=id,kind='statue',aura=id})elseif c and c.kind=='Trail'then table.insert(rankTrails,{id=id,kind='comet'})end end
end
local east={}
-- East wall follows the Robux shop order (LobbyShopCatalog ROBUX_ORDER); VIP is on the west wall.
for _,o in C.RobuxOffers do
 if o.grants then table.insert(east,{id=o.id,kind=RS.CosmeticKit:FindFirstChild(o.grants)and'model'or'card',model=o.grants,wear=o.grants})
 elseif o.id~='vip'then table.insert(east,{id=o.id,kind='card'})end
end

local folder=Instance.new('Folder');folder.Name='Showcase';folder.Parent=world
local function part(parent,name,size,cf,color,material,props)
 local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
 p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.CastShadow=false
 for k,v in props or {}do p[k]=v end
 p.Parent=parent;return p
end
local function floorY(x,z)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={folder}
 local hit=workspace:Raycast(Vector3.new(x,30,z),Vector3.new(0,-60,0),params)
 return hit and hit.Position.Y or .5
end
-- Even spacing along the wall, skipping the door.
local function slots(n,door,lo,hi)
 lo,hi=lo or Z_MIN,hi or Z_MAX
 local segs=door and{{lo,door-DOOR_GAP},{door+DOOR_GAP,hi}}or{{lo,hi}}
 local total=0;for _,sg in segs do total+=sg[2]-sg[1]end
 local step=total/n;local out={};local walked=step/2
 for _=1,n do
  local d=walked
  for _,sg in segs do local len=sg[2]-sg[1];if d<=len then table.insert(out,sg[1]+d);break end;d-=len end
  walked+=step
 end
 return out
end

local function buildStand(entry,wall,z)
 local offer=offerFor(entry.id);if not offer then return end
 local tint=Color3.fromRGB(unpack(offer.color or {200,200,200}))
 local px,pz=if wall.alongX then z else wall.x,if wall.alongX then wall.z else z
 local f=wall.face;local y=floorY(px,pz)
 local base=CFrame.lookAt(Vector3.new(px,y,pz),Vector3.new(px,y,pz)+f) -- LookVector faces into the room
 local m=Instance.new('Model');m.Name='Stand_'..entry.id
 m:SetAttribute('OfferId',entry.id);m:SetAttribute('Robux',C.RobuxById[entry.id]~=nil);m:SetAttribute('Kind',entry.kind)
 local wood,cap=Color3.fromRGB(52,36,46),Color3.fromRGB(34,30,42)
 part(m,'Plinth',Vector3.new(3.4,2.4,3.4),base*CFrame.new(0,1.2,0),wood,Enum.Material.Wood)
 part(m,'Band',Vector3.new(3.55,.18,3.55),base*CFrame.new(0,2.3,0),GOLD,Enum.Material.Metal)
 part(m,'Cap',Vector3.new(3.9,.3,3.9),base*CFrame.new(0,2.55,0),cap,Enum.Material.Marble)
 local pad=part(m,'Pad',Vector3.new(.06,2.7,2.7),base*CFrame.new(0,2.72,0)*CFrame.Angles(0,0,math.pi/2),tint,Enum.Material.Neon,{Shape=Enum.PartType.Cylinder,Transparency=.35,CanCollide=false})
 pad.CanQuery=false
 -- Velvet backboard in the offer's colour, framed in gold, against the wall.
 local back=base*CFrame.new(0,5.3,2.55)
 part(m,'Backboard',Vector3.new(4.6,9.8,.3),back,tint:Lerp(Color3.new(0,0,0),.72),Enum.Material.Fabric)
 part(m,'FrameTop',Vector3.new(5,.3,.45),back*CFrame.new(0,5,0),GOLD,Enum.Material.Metal)
 part(m,'FrameL',Vector3.new(.3,10.3,.45),back*CFrame.new(-2.35,0,0),GOLD,Enum.Material.Metal)
 part(m,'FrameR',Vector3.new(.3,10.3,.45),back*CFrame.new(2.35,0,0),GOLD,Enum.Material.Metal)
 -- Name on the backboard above the item.
 local nameGui=Instance.new('SurfaceGui');nameGui.Face=Enum.NormalId.Front;nameGui.CanvasSize=Vector2.new(460,120);nameGui.LightInfluence=0
 nameGui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
 local holder=part(m,'NamePlate',Vector3.new(4.2,1.1,.05),back*CFrame.new(0,4.15,-.18),cap,Enum.Material.SmoothPlastic,{Transparency=1,CanCollide=false})
 nameGui.Adornee=holder;nameGui.Parent=holder
 local nameLabel=Instance.new('TextLabel');nameLabel.BackgroundTransparency=1;nameLabel.Size=UDim2.fromScale(1,1);nameLabel.FontFace=PIXEL;nameLabel.TextScaled=true
 nameLabel.Text=string.upper(offer.name);nameLabel.TextColor3=Color3.fromRGB(255,236,180);nameLabel.Parent=nameGui
 local ns=Instance.new('UIStroke');ns.Thickness=4;ns.Color=Color3.new(0,0,0);ns.Parent=nameLabel
 local np=Instance.new('UIPadding');np.PaddingLeft=UDim.new(0,10);np.PaddingRight=UDim.new(0,10);np.PaddingTop=UDim.new(0,14);np.PaddingBottom=UDim.new(0,14);np.Parent=nameLabel
 -- Lamp over the item: a warm spotlight down, plus a soft light in the offer's colour.
 local lamp=part(m,'Lamp',Vector3.new(.9,.3,.9),base*CFrame.new(0,10.7,1.2),Color3.fromRGB(28,26,32),Enum.Material.Metal,{CanCollide=false})
 local spot=Instance.new('SpotLight');spot.Face=Enum.NormalId.Bottom;spot.Brightness=3;spot.Range=14;spot.Angle=60;spot.Color=Color3.fromRGB(255,236,205);spot.Shadows=false;spot.Parent=lamp
 local anchor=part(m,'ItemAnchor',Vector3.new(.2,.2,.2),base*(entry.wear and CFrame.new(1.2,3.45,-1.15)or CFrame.new(0,4.7,0)),tint,Enum.Material.SmoothPlastic,{Transparency=1,CanCollide=false,CanQuery=false,CanTouch=false})
 local glow=Instance.new('PointLight');glow.Color=tint;glow.Brightness=1.1;glow.Range=8;glow.Shadows=false;glow.Parent=anchor
 -- Lectern in front: the client draws the plaque (name, price, BUY) on its face; the prompt buys with E / tap / gamepad.
 local lecternAt=base*CFrame.new(0,0,-2.9)
 part(m,'LecternPost',Vector3.new(.35,2.1,.35),lecternAt*CFrame.new(0,1.05,0),wood,Enum.Material.Wood)
 local plaque=part(m,'Plaque',Vector3.new(2.8,1.75,.14),lecternAt*CFrame.new(0,2.35,0)*CFrame.Angles(math.rad(38),0,0),cap,Enum.Material.Marble)
 part(m,'PlaqueTrim',Vector3.new(2.95,1.9,.08),plaque.CFrame*CFrame.new(0,0,.06),GOLD,Enum.Material.Metal)
 local prompt=Instance.new('ProximityPrompt');prompt.Name='BuyPrompt';prompt.ObjectText=offer.name;prompt.ActionText='Buy'
 prompt.HoldDuration=0;prompt.MaxActivationDistance=5.5;prompt.RequiresLineOfSight=false;prompt.KeyboardKeyCode=Enum.KeyCode.E
 prompt.Enabled=not offer.nonPurchasable;prompt:SetAttribute('OfferId',entry.id);prompt.Parent=plaque
 -- The item.
 if entry.kind=='statue'then
  local statue=RS.LobbyCharacterPreview:Clone();statue.Name='Statue'
  for _,d in statue:GetDescendants()do
   if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false
   elseif d:IsA('Script')or d:IsA('LocalScript')then d:Destroy()end
  end
  statue:ScaleTo(.68)
  statue:PivotTo(CFrame.lookAt(Vector3.zero,f))
  local cf,size=statue:GetBoundingBox()
  local root=statue:FindFirstChild('HumanoidRootPart')
  statue:PivotTo(statue:GetPivot()+(Vector3.new(px,y+2.7,pz)-Vector3.new(cf.X,cf.Y-size.Y/2,cf.Z)))
  statue.Parent=m
  if root and entry.aura then Rig.Aura(root,entry.aura)end
  local title=entry.title and C.ById[entry.title]
  local head=statue:FindFirstChild('Head')
  if title and head then -- the same overhead tag row ProgressService draws above a player, a little larger
   local tag=Instance.new('BillboardGui');tag.Name='TitleTag';tag.Adornee=head;tag.Size=UDim2.fromOffset(320,40);tag.StudsOffsetWorldSpace=Vector3.new(0,1.5,0)
   tag.MaxDistance=60;tag.LightInfluence=0;tag.Parent=head
   local label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.Font=Enum.Font.FredokaOne;label.TextSize=22
   label.Text=title.text or title.name;label.TextColor3=Color3.fromRGB(unpack(title.color or {230,204,140}));label.TextStrokeTransparency=.15;label.Parent=tag
  end
 elseif entry.kind=='comet'then
  -- A character running in place, side-on so the trail shows streaming out behind it.
  local runner=game:GetService('StarterPlayer').StarterCharacter:Clone();runner.Name='Runner'
  -- The voice mouth joints are posed at runtime for real players (their rest C0 puts the lips and teeth at the head's
  -- centre). Rebind them to the modelled face so the runner's mouth sits where it should.
  for _,j in runner:GetDescendants()do
   if j:IsA('Motor6D')and(j.Name=='VoiceLipJoint'or j.Name=='VoiceMouthJoint')and j.Part0 and j.Part1 then
    j.C0=j.Part0.CFrame:ToObjectSpace(j.Part1.CFrame)*j.C1
   end
  end
  for _,d in runner:GetDescendants()do
   if d:IsA('BasePart')then d.Anchored=d.Name=='HumanoidRootPart';d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true
   elseif d:IsA('Script')or d:IsA('LocalScript')or d:IsA('ModuleScript')then d:Destroy()end
  end
  local hum=runner:FindFirstChildOfClass('Humanoid')
  if hum then hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None;hum.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOff;hum.EvaluateStateMachine=false end
  runner:ScaleTo(.68)
  local facing=(Vector3.new(-f.Z,0,f.X)+f*.45).Unit -- side-on along the wall, turned a little toward the room
  runner:PivotTo(CFrame.lookAt(Vector3.zero,facing))
  local cf,size=runner:GetBoundingBox()
  runner:PivotTo(runner:GetPivot()+(Vector3.new(px,y+2.75,pz)-Vector3.new(cf.X,cf.Y-size.Y/2,cf.Z)))
  runner.Parent=m
  Rig.RunnerTrail(runner,entry.id,14) -- 14 studs/s: a player's normal run
  local animator=hum and hum:FindFirstChildOfClass('Animator');if hum and not animator then animator=Instance.new('Animator');animator.Parent=hum end
  -- Owner 2026-10-29 'the spawn is really laggy': the server no longer plays the run cycle. 10 runners x 57 animated
  -- parts were replicated to every player all the time (~90 KB/s at the spawn). Each client plays it on its own
  -- screen, only for runners near its camera (LobbyShowcaseClient, RunnerAnim).
  runner:SetAttribute('RunnerAnim','rbxassetid://913376220') -- the run cycle players use (Animate/run)
 elseif entry.kind=='model'then
  local model=RS.CosmeticKit[entry.model]:Clone();model.Name='Item'
  for _,d in model:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false end end
  local _,size=model:GetBoundingBox();model:ScaleTo(model:GetScale()*(entry.wear and .95 or 3)/math.max(size.X,size.Y,size.Z))
  model:PivotTo(anchor.CFrame);model:SetAttribute('Spin',true);model.Parent=m
 elseif entry.kind=='card'then
  local cardSize=entry.wear and .95 or 2.7
  local card=part(m,'Item',Vector3.new(cardSize,cardSize,.1),anchor.CFrame,cap,Enum.Material.SmoothPlastic,{Transparency=1,CanCollide=false,CanQuery=false})
  card:SetAttribute('Spin',true)
  for _,face in {Enum.NormalId.Front,Enum.NormalId.Back}do
   local g=Instance.new('SurfaceGui');g.Face=face;g.CanvasSize=Vector2.new(400,400);g.LightInfluence=0;g.Brightness=1.3;g.Parent=card
   local img=Instance.new('ImageLabel');img.Size=UDim2.fromScale(1,1);img.BackgroundColor3=cap;img.Image=offer.image or C.OfferImages[entry.id]or'';img.Parent=g
   local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(.14,0);corner.Parent=img
   local rim=Instance.new('UIStroke');rim.Thickness=12;rim.Color=GOLD;rim.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rim.Parent=img
  end
 end
 if entry.wear then -- a statue wearing the cosmetic, under the floating item
  local cosmetic=C.ById[entry.wear]
  local statue=RS.LobbyCharacterPreview:Clone();statue.Name='Statue'
  for _,d in statue:GetDescendants()do
   if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false
   elseif d:IsA('Script')or d:IsA('LocalScript')then d:Destroy()end
  end
  -- Worn at full size first (CosmeticRig places hats, rings and shoes for a full-size rig), then scaled together.
  statue:PivotTo(CFrame.lookAt(Vector3.zero,f));statue.Parent=m
  local worn=Instance.new('Folder');worn.Name='Worn';worn.Parent=statue
  if cosmetic then pcall(Rig.Wear,statue,{[cosmetic.kind]=entry.wear},worn)end
  statue:ScaleTo(.68)
  local cf,size=statue:GetBoundingBox()
  statue:PivotTo(statue:GetPivot()+(Vector3.new(px,y+2.7,pz)-Vector3.new(cf.X,cf.Y-size.Y/2,cf.Z)))
 end
 m.PrimaryPart=m:FindFirstChild('Plinth')
 m.ModelStreamingMode=Enum.ModelStreamingMode.Atomic -- streams in and out whole (owner 2026-10-25: lobby lag on weak devices); LobbyShowcaseClient sets each one up when it arrives
 m.Parent=folder
end

for _,wall in WALLS do
 local list=wall.list=='west'and west or wall.list=='east'and east or wall.list=='rankTrails'and rankTrails or ranks
 local zs=wall.xs or slots(#list,wall.door,wall.min,wall.max)
 for i,entry in list do
  local ok,err=pcall(buildStand,entry,wall,zs[i]);if not ok then warn('[Showcase] '..entry.id..': '..tostring(err))end
 end
 if wall.frame then -- a framed gallery behind the stands: velvet backdrop, gold trim, a raised dais and a warm wash of light
  local cx=(wall.min+wall.max)/2;local w=wall.max-wall.min+9;local y=floorY(cx,wall.z)
  local inward=wall.face
  local back=CFrame.lookAt(Vector3.new(cx,y+6.3,wall.z-inward.Z*3.05),Vector3.new(cx,y+6.3,wall.z-inward.Z*3.05)+inward)
  part(folder,'GalleryBackdrop',Vector3.new(w,12.4,.3),back,Color3.fromRGB(44,24,64),Enum.Material.Fabric)
  part(folder,'GalleryTrimTop',Vector3.new(w+1,.45,.6),back*CFrame.new(0,6.3,-.1),GOLD,Enum.Material.Metal)
  part(folder,'GalleryTrimL',Vector3.new(.45,12.9,.6),back*CFrame.new(-w/2-.2,0,-.1),GOLD,Enum.Material.Metal)
  part(folder,'GalleryTrimR',Vector3.new(.45,12.9,.6),back*CFrame.new(w/2+.2,0,-.1),GOLD,Enum.Material.Metal)
  local dais=part(folder,'GalleryDais',Vector3.new(w,.35,7.6),CFrame.lookAt(Vector3.new(cx,y+.175,wall.z+inward.Z*.6),Vector3.new(cx,y+.175,wall.z+inward.Z*.6)+inward),Color3.fromRGB(34,26,44),Enum.Material.Marble)
  part(folder,'GalleryDaisEdge',Vector3.new(w,.12,.3),dais.CFrame*CFrame.new(0,.12,-3.8),GOLD,Enum.Material.Metal)
  for i=-2,2 do
   local lamp=part(folder,'GalleryWash',Vector3.new(.6,.3,.6),back*CFrame.new(i*w/5.2,5.9,-1),Color3.fromRGB(28,26,32),Enum.Material.Metal,{CanCollide=false})
   local l=Instance.new('SpotLight');l.Face=Enum.NormalId.Bottom;l.Brightness=1.6;l.Range=16;l.Angle=75;l.Color=Color3.fromRGB(235,215,255);l.Shadows=false;l.Parent=lamp
  end
 end
 -- Section signs high on the wall above the stands.
 local signs={}
 if wall.alongX then local y=floorY((wall.min+wall.max)/2,wall.z);table.insert(signs,Vector3.new((wall.min+wall.max)/2,y+13.6,wall.z-wall.face.Z*4.85))
 else local y=floorY(wall.x,0);for _,zc in {-30,50}do table.insert(signs,Vector3.new(wall.x-wall.face.X*4.85,y+13.6,zc))end end
 for _,at in signs do
  local s=part(folder,'Sign',Vector3.new(26,2.6,.3),CFrame.lookAt(at,at+wall.face),Color3.fromRGB(26,22,32),Enum.Material.Wood)
  local g=Instance.new('SurfaceGui');g.Face=Enum.NormalId.Front;g.CanvasSize=Vector2.new(2600,260);g.LightInfluence=0;g.Brightness=1.4;g.Parent=s
  local frame=Instance.new('Frame');frame.BackgroundTransparency=1;frame.Size=UDim2.fromScale(1,1);frame.Parent=g
  local trim=Instance.new('UIStroke');trim.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;trim.Thickness=10;trim.Color=GOLD;trim.Parent=frame
  local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.FontFace=PIXEL;t.TextScaled=true;t.Text=wall.title
  t.TextColor3=Color3.fromRGB(255,214,96);t.Parent=frame
  local st=Instance.new('UIStroke');st.Thickness=8;st.Color=Color3.fromRGB(60,30,10);st.Parent=t
  local pad=Instance.new('UIPadding');pad.PaddingTop=UDim.new(0,40);pad.PaddingBottom=UDim.new(0,40);pad.Parent=t
 end
end
-- ===== Lobby retention features (2026-10-26): Curio Cabinet, Spook-o-Meter, Crew Trophy =====
-- Models: ServerStorage.LobbyFeatureKit.<Name> (rbxkit meshes, pivot bottom centre, front = -Z). Spot: a hand-placed
-- anchored part LobbyWorld.FeatureSpots.<Name> (CanQuery=false, front = LookVector) or the fallback below. Each
-- model gets an invisible 'FeatureBase' part at its spot, so the clients find lane, slot and plate positions without
-- knowing FEATURE_TURN.
local SS=game:GetService('ServerStorage')
local FEATURE_TURN=CFrame.identity -- if a kit model shows its back to the room when first placed, use CFrame.Angles(0,math.pi,0)
local FEATURE_SPOTS={
 CurioCabinet=CFrame.lookAt(Vector3.new(1155,0,-62.2),Vector3.new(1155,0,0)), -- north wall, west half (rank trails gallery is x 1184..1212)
 SpookOMeter=CFrame.lookAt(Vector3.new(1245,0,-61.5),Vector3.new(1245,0,0)),  -- north wall, east half
 CrewTrophy=CFrame.lookAt(Vector3.new(1200,0,-48),Vector3.new(1200,0,0)),      -- in front of the rank trails dais
}
local HIDDEN={Transparency=1,CanCollide=false,CanQuery=false,CanTouch=false}
local function featureSpot(name)
 local spots=world:FindFirstChild('FeatureSpots');local s=spots and spots:FindFirstChild(name)
 local cf=s and s:IsA('BasePart')and s.CFrame or FEATURE_SPOTS[name]
 local look=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z);if look.Magnitude<.01 then look=Vector3.new(0,0,1)end
 local at=Vector3.new(cf.X,floorY(cf.X,cf.Z),cf.Z)
 return CFrame.lookAt(at,at+look.Unit)
end
local function placeFeature(name,base,modelName)
 local kitFolder=SS:FindFirstChild('LobbyFeatureKit');local template=kitFolder and kitFolder:FindFirstChild(name)
 if not template or not template:IsA('Model')then warn('[Showcase] ServerStorage.LobbyFeatureKit.'..name..' is missing');return nil end
 local m=template:Clone();m.Name=modelName or name
 for _,d in m:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CastShadow=false end end
 m:PivotTo(base*FEATURE_TURN);m.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
 part(m,'FeatureBase',Vector3.new(.2,.2,.2),base,Color3.new(),Enum.Material.SmoothPlastic,HIDDEN)
 return m
end
-- Curio Cabinet: one cubby per cursed item type, 36 per rbxkit section (6 x 6, 1.7-stud pitch; cubby centre in section
-- space: x = 5.1-(c-.5)*1.7 from the viewer's left, up = 1+(6-r)*1.7+.82, z = -.15). Every cubby holds an inert copy
-- of the item AND a grey dust sheet; LobbyShowcaseClient hides one of the two per player from their Museum save.
local Cursed=require(RS:WaitForChild('CursedCatalog'))
local CURIO_PITCH,CURIO_FIT,CURIO_SECTION_W,CURIO_PER=1.7,1.25,11.8,36
local KEEP={Model=true,Folder=true,Decal=true,Texture=true,SurfaceAppearance=true,SpecialMesh=true}
local function inert(m)
 for _,d in m:GetDescendants()do
  if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.CastShadow=false
  elseif not KEEP[d.ClassName]then d:Destroy()end -- scripts, prompts, sounds, lights, particles, welds, attachments
 end
 for _,d in m:GetDescendants()do for k in d:GetAttributes()do d:SetAttribute(k,nil)end end
 for k in m:GetAttributes()do m:SetAttribute(k,nil)end -- no ItemId/Kind: the item owners must never see a pickup here
end
local function curioIds(kit)
 local loot,rare,seen={},{},{}
 for _,id in Cursed.Order do
  local meta=Cursed.Items[id];local t=kit:FindFirstChild(id)
  if not seen[id]and meta and t and t:IsA('Model')and t.PrimaryPart then seen[id]=true;table.insert(meta.noLoot and rare or loot,id)end
 end
 for _,id in rare do table.insert(loot,id)end
 return loot
end
local function buildCurioCabinet()
 local kit=SS:WaitForChild('CursedItemKit',60);if not kit then warn('[Showcase] CursedItemKit missing: no Curio Cabinet');return end
 -- Some item meshes are built at runtime; the same call LobbyServer uses on mission servers (it waits for a build in progress).
 local ok,err=pcall(function()require(SS:WaitForChild('CursedBlenderHydration')).Build()end);if not ok then warn('[Showcase] curio meshes: '..tostring(err))end
 local ids=curioIds(kit);local sections=math.max(1,math.ceil(#ids/CURIO_PER))
 local base=featureSpot('CurioCabinet')
 local cab=Instance.new('Model');cab.Name='CurioCabinet';cab:SetAttribute('CurioCount',#ids)
 -- Owner 2026-10-29 'everything loads at the same time': the 147 cubbies (~1,600 instances) used to appear in one
 -- frame. The empty cabinet goes up first (Building=true), then 4 cubbies a frame; the client draws it when done.
 local pending={}
 for s=1,sections do
  local sb=base*CFrame.new(((sections+1)/2-s)*CURIO_SECTION_W,0,0) -- section 1 on the viewer's left
  local m=placeFeature('CurioCabinet',sb,'Section'..s);if not m then cab:Destroy();return end
  m.ModelStreamingMode=Enum.ModelStreamingMode.Default;m.Parent=cab
  if s==math.ceil(sections/2)then
   local holder=part(m,'TitlePlate',Vector3.new(3.3,.75,.05),sb*CFrame.new(0,12.2,-1.0),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN)
   local g=Instance.new('SurfaceGui');g.Face=Enum.NormalId.Front;g.CanvasSize=Vector2.new(440,100);g.LightInfluence=0;g.Adornee=holder;g.Parent=holder
   local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.FontFace=PIXEL;t.TextScaled=true;t.Text='CURSED CURIOS'
   t.TextColor3=Color3.fromRGB(70,40,20);t.Parent=g
   -- lectern for the per-player card (drawn by LobbyShowcaseClient), same shape as the shop stands' lecterns
   local lecternAt=sb*CFrame.new(0,0,-3.4)
   part(cab,'CurioLecternPost',Vector3.new(.35,2.1,.35),lecternAt*CFrame.new(0,1.05,0),Color3.fromRGB(52,36,46),Enum.Material.Wood)
   local card=part(cab,'CurioCard',Vector3.new(2.8,1.75,.14),lecternAt*CFrame.new(0,2.35,0)*CFrame.Angles(math.rad(38),0,0),Color3.fromRGB(34,30,42),Enum.Material.Marble)
   part(cab,'CurioCardTrim',Vector3.new(2.95,1.9,.08),card.CFrame*CFrame.new(0,0,.06),GOLD,Enum.Material.Metal)
  end
  for i=1,CURIO_PER do
   local n=(s-1)*CURIO_PER+i;local id=ids[n];if not id then break end
   table.insert(pending,function()
   local c,r=(i-1)%6+1,(i-1)//6+1
   local cf=sb*CFrame.new(5.1-(c-.5)*CURIO_PITCH,1+(6-r)*CURIO_PITCH+.82,-.15)
   local slot=Instance.new('Model');slot.Name='Slot_'..id;slot:SetAttribute('CurioId',id);slot:SetAttribute('CurioIndex',n)
   slot:SetAttribute('Rare',Cursed.Items[id].noLoot==true)
   local item=kit[id]:Clone();inert(item);item.Name='Item'
   local _,size=item:GetBoundingBox();item:ScaleTo(item:GetScale()*CURIO_FIT/math.max(size.X,size.Y,size.Z,.05))
   item:PivotTo(cf) -- owner 2026-10-28: the half-turn left every item facing the wall; unturned they face the room
   local bb=item:GetBoundingBox();item:PivotTo(item:GetPivot()+(cf.Position-bb.Position))
   item.Parent=slot
   local sheet=part(slot,'DustSheet',Vector3.new(1.5,1.4,1.5),cf*CFrame.new(0,-.05,0),Color3.fromRGB(122,120,130),Enum.Material.Fabric,{CanCollide=false,CanQuery=false,CanTouch=false})
   local mesh=Instance.new('SpecialMesh');mesh.MeshType=Enum.MeshType.Sphere;mesh.Parent=sheet -- a soft lump of cloth
   slot.Parent=m
   end)
  end
 end
 cab.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
 cab:SetAttribute('Building',true);cab.Parent=folder
 for k,build in pending do build();if k%4==0 then task.wait()end end
 cab:SetAttribute('Building',nil)
end
task.spawn(buildCurioCabinet) -- waits for the item meshes; the client picks it up through Showcase.ChildAdded
-- Crew Trophy: the rbxkit model plus an invisible engraving face over its brass plate (plate front at z -1.67, up 1.6).
local function buildCrewTrophy()
 local base=featureSpot('CrewTrophy');local m=placeFeature('CrewTrophy',base);if not m then return end
 part(m,'EngraveFace',Vector3.new(2.5,1.6,.05),base*CFrame.new(0,1.6,-1.7),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN)
 local glow=m:FindFirstChild('Glow',true);if glow and glow:IsA('BasePart')then glow.Transparency=.8;glow.CanCollide=false end -- each client lights it for a record set today
 m.Parent=folder
end
buildCrewTrophy()
-- Spook-o-Meter (WorldB 2026-10-27): the rbxkit model plus invisible lane pads and text faces; LobbyWorldClient draws
-- everything per viewer. Lane and face positions are measured from the model's own Puck template (rbxkit FBX arrives
-- X-mirrored, and its pivot is the bbox bottom centre), so they hold whichever way the model is turned.
local function buildSpookOMeter()
 local base=featureSpot('SpookOMeter');local m=placeFeature('SpookOMeter',base);if not m then return end
 local puck=m:FindFirstChild('Puck',true)
 local rel=puck and puck:IsA('BasePart')and base:ToObjectSpace(puck.CFrame)or CFrame.new(3,1.95,.1)
 local tubeZ,x1=rel.Z,rel.X;local step=x1>0 and -2 or 2 -- lane 1 is the template's tube; lanes are 2 studs apart
 m:SetAttribute('TubeZ',tubeZ)
 if puck and puck:IsA('BasePart')then puck.Transparency=1;puck.CanCollide=false;puck.CanQuery=false end -- template: the client clones one per lane
 local lamp=m:FindFirstChild('Lamp',true);if lamp and lamp:IsA('BasePart')then lamp.CanCollide=false;lamp.Color=Color3.fromRGB(60,56,52)end -- dark until a client lights its own
 for i=1,4 do
  local x=x1+(i-1)*step
  local pad=part(m,'LanePad'..i,Vector3.new(1.6,.2,1.6),base*CFrame.new(x,.45,tubeZ-2.15),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN)
  pad:SetAttribute('Lane',i);pad:SetAttribute('LaneX',x)
 end
 part(m,'TitleFace',Vector3.new(5.2,.9,.05),base*CFrame.new(0,11,tubeZ+.47),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN) -- title board front = tube + 0.5 (it sits behind the tubes)
 part(m,'LaneFace',Vector3.new(8.4,.7,.05),base*CFrame.new(0,.7,tubeZ-.73),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN) -- cabinet front = tube - 0.7
 m.Parent=folder
end
buildSpookOMeter()
-- Crew Photo Booth (WorldB 2026-10-27): a walk-in booth; a crew inside for 1.5 s gets a 3-2-1 on the marquee, a white
-- flash, a hop, grins and a pop line, then a little printed strip of rank-coloured ghost doodles slides out of the slot.
-- No real photo, nothing stored, nothing user-made (owner rule). Server-run so every viewer sees the same countdown.
-- Offsets come from CrewPhotoBooth.py (built at height 10.2 = x0.933, pivot at the bbox bottom centre, X-mirrored FBX).
local function buildCrewPhotoBooth()
 FEATURE_SPOTS.CrewPhotoBooth=FEATURE_SPOTS.CrewPhotoBooth or CFrame.lookAt(Vector3.new(1225,0,-60.6),Vector3.new(1225,0,0)) -- north wall, between the rank trails and the Spook-o-Meter
 local base=featureSpot('CrewPhotoBooth');local m=placeFeature('CrewPhotoBooth',base);if not m then return end
 local Catalog=require(RS:WaitForChild('GameplaySoundCatalog'))
 local RankCatalog=require(RS:WaitForChild('RankCatalog'))
 local Players=game:GetService('Players');local Tween=game:GetService('TweenService')
 local zone=part(m,'BoothZone',Vector3.new(8.2,6,4.6),base*CFrame.new(0,3.4,-.1),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN)
 local marquee=part(m,'MarqueeFace',Vector3.new(4.8,1.15,.05),base*CFrame.new(0,9.42,-2.64),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN)
 local slot=part(m,'StripSlot',Vector3.new(.2,.2,.2),base*CFrame.new(-4.38,3.05,-2.88),Color3.new(),Enum.Material.SmoothPlastic,HIDDEN)
 local g=Instance.new('SurfaceGui');g.Name='Marquee';g.Face=Enum.NormalId.Front;g.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;g.CanvasSize=Vector2.new(480,115);g.LightInfluence=0;g.MaxDistance=80;g.Parent=marquee
 local sign=Instance.new('TextLabel');sign.Name='Text';sign.BackgroundTransparency=1;sign.Size=UDim2.fromScale(.94,.9);sign.Position=UDim2.fromScale(.03,.05)
 sign.Font=Enum.Font.FredokaOne;sign.TextScaled=true;sign.TextColor3=Color3.fromRGB(255,220,120);sign.Text='PHOTO BOOTH';sign.Parent=g
 local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(40,20,60);stroke.Thickness=3;stroke.Parent=sign
 local glow=Instance.new('PointLight');glow.Name='FlashLight';glow.Color=Color3.new(1,1,1);glow.Brightness=0;glow.Range=16;glow.Shadows=false;glow.Parent=zone
 -- Look (owner 2026-10-28 "make the photobooth work and look cool"): a violet glow inside and a glowing camera lens on
 -- the back wall. During the countdown LobbyShowcaseClient turns the crew's view into that lens (viewfinder, 3-2-1,
 -- flash, then a printed card on screen). Still nothing stored, nothing user-made.
 local mood=Instance.new('PointLight');mood.Name='BoothGlow';mood.Color=Color3.fromRGB(170,110,255);mood.Brightness=1.4;mood.Range=10;mood.Shadows=false;mood.Parent=zone
 local lensAt=zone.CFrame*CFrame.new(0,1.8,2.3) -- back wall at face height (zone +Z; the booth opens to -Z)
 local lens=Instance.new('Part');lens.Name='BoothLens';lens.Shape=Enum.PartType.Cylinder;lens.Size=Vector3.new(.35,1.1,1.1);lens.CFrame=lensAt*CFrame.Angles(0,math.rad(90),0)
 lens.Color=Color3.fromRGB(18,16,24);lens.Material=Enum.Material.Glass;lens.Reflectance=.3;lens.Anchored=true;lens.CanCollide=false;lens.CanQuery=false;lens.CanTouch=false;lens.CastShadow=false;lens.Parent=m
 local ring=lens:Clone();ring.Name='BoothLensRing';ring.Size=Vector3.new(.2,1.45,1.45);ring.Material=Enum.Material.Neon;ring.Color=Color3.fromRGB(190,140,255);ring.Reflectance=0;ring.Parent=m
 local function sound(key)
  local c=Catalog[key];if not c then return end
  local s=Instance.new('Sound');s.SoundId=c.id;s.Volume=(c.volume or .2)*1.6;s.PlaybackSpeed=c.speed or 1;s.RollOffMaxDistance=60;s.Parent=zone;s:Play()
  task.delay(4,function()s:Destroy()end)
 end
 local function inside(p)
  local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
  if not r or not h or h.Health<=0 then return false end
  local q=zone.CFrame:PointToObjectSpace(r.Position)
  return math.abs(q.X)<=zone.Size.X/2 and math.abs(q.Y)<=zone.Size.Y/2+1 and math.abs(q.Z)<=zone.Size.Z/2
 end
 local LINES={'SAY BOO!','SPOOKY!','CHEESE!'}
 local shots=0
 local function printStrip(crew)
  local strip=Instance.new('Part');strip.Name='PhotoStrip';strip.Size=Vector3.new(.62,1.7,.04);strip.Anchored=true;strip.CanCollide=false;strip.CanQuery=false;strip.CanTouch=false
  strip.Color=Color3.fromRGB(246,240,226);strip.Material=Enum.Material.SmoothPlastic;strip.CFrame=slot.CFrame*CFrame.new(0,.6,0);strip.Parent=m
  strip:SetAttribute('Crew',#crew)
  local sg=Instance.new('SurfaceGui');sg.Face=Enum.NormalId.Front;sg.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;sg.CanvasSize=Vector2.new(124,340);sg.LightInfluence=.3;sg.MaxDistance=40;sg.Parent=strip
  local title=Instance.new('TextLabel');title.BackgroundTransparency=1;title.Size=UDim2.new(1,0,0,30);title.Font=Enum.Font.FredokaOne;title.TextScaled=true;title.Text='SPOOK CREW';title.TextColor3=Color3.fromRGB(70,40,110);title.Parent=sg
  for i,p in crew do if i<=4 then
   local r=RankCatalog.Get(p:GetAttribute('RR')or 0)
   local ghost=Instance.new('Frame');ghost.Name='Ghost'..i;ghost.Size=UDim2.fromOffset(52,58);ghost.Position=UDim2.fromOffset(i%2==1 and 8 or 64,36+math.floor((i-1)/2)*68);ghost.BackgroundColor3=r.color;ghost.Parent=sg
   local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(.5,0);corner.Parent=ghost
   for _,ex in{.3,.62}do local eye=Instance.new('Frame');eye.Size=UDim2.fromOffset(8,11);eye.Position=UDim2.fromScale(ex,.32);eye.BackgroundColor3=Color3.fromRGB(20,16,28);eye.Parent=ghost;local ec=Instance.new('UICorner');ec.CornerRadius=UDim.new(.5,0);ec.Parent=eye end
  end end
  local foot=title:Clone();foot.Position=UDim2.new(0,0,1,-34);foot.Text='CREW OF '..#crew;foot.Parent=sg
  Tween:Create(strip,TweenInfo.new(.8,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{CFrame=slot.CFrame*CFrame.new(0,-.35,0)}):Play()
  sound('PresentOpen')
  task.delay(10,function()if strip.Parent then Tween:Create(strip,TweenInfo.new(.6),{Transparency=1}):Play();task.wait(.65);strip:Destroy()end end)
 end
 local occupiedSince,busy=nil,false
 task.spawn(function()
  task.wait() -- m is parented at the end of this builder: wait for it, or the loop ends at once
  while m.Parent do
   task.wait(.25)
   if not busy then
    local any=false;for _,p in Players:GetPlayers()do if inside(p)then any=true;break end end
    if any then occupiedSince=occupiedSince or os.clock()else occupiedSince=nil end
    if occupiedSince and os.clock()-occupiedSince>=1.5 then
     busy=true;occupiedSince=nil
     task.spawn(function()
      for n=3,1,-1 do m:SetAttribute('BoothCountdown',n);sign.Text=tostring(n);sound('ClockTick');mood.Brightness=2.4;Tween:Create(mood,TweenInfo.new(.8),{Brightness=1.4}):Play();task.wait(1)end
      m:SetAttribute('BoothCountdown',0);sign.Text='FLASH!'
      local crew={};for _,p in Players:GetPlayers()do if inside(p)then table.insert(crew,p)end end
      shots+=1;local line=LINES[(shots-1)%#LINES+1];local t=workspace:GetServerTimeNow()
      m:SetAttribute('BoothFlashAt',t);m:SetAttribute('BoothCrew',#crew);sound('CameraShutter')
      glow.Brightness=3;Tween:Create(glow,TweenInfo.new(.5),{Brightness=0}):Play()
      for _,p in crew do
       p:SetAttribute('FaceBeat','grin');p:SetAttribute('FaceBeatUntil',t+3)
       p:SetAttribute('ReactPop',line);p:SetAttribute('ReactPopShake',0);p:SetAttribute('ReactPopAt',t)
       local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if h then h.Jump=true end
      end
      task.wait(.6);if #crew>0 then printStrip(crew)end
      task.wait(1.4);sign.Text='PHOTO BOOTH';task.wait(6);busy=false
     end)
    end
   end
  end
 end)
 if game:GetService('RunService'):IsStudio()then
  local test=Instance.new('BindableFunction');test.Name='CrewPhotoBoothTest';test.Parent=script
  test.OnInvoke=function(action,p)
   if action=='zone'then return zone.CFrame end
   if action=='inside'then return inside(p)end
   return {busy=busy,flashAt=m:GetAttribute('BoothFlashAt'),crew=m:GetAttribute('BoothCrew'),strip=m:FindFirstChild('PhotoStrip')~=nil}
  end
 end
 m.Parent=folder
end
buildCrewPhotoBooth()
folder:SetAttribute('Ready',true)
-- PlaytestFixes 2026-10-27 (lag): the 10 trail-showcase Runners run their animation on the server all mission long:
-- 570 animated limb parts = ~810 moving primitives, server physics 7.2 ms -> 2.3 ms per step with them frozen
-- (measured in a Hotel mission). While a mission runs nobody is in the lobby, so they stand still (anchored, track
-- stopped) and start running again when the server is back in the lobby.
do
 local paused={} -- Runner -> stopped tracks
 local function apply()
  local stop=workspace:GetAttribute('MissionRunning')==true
  for _,stand in folder:GetChildren()do
   local runner=stand:FindFirstChild('Runner')
   if runner and stop~=(paused[runner]~=nil)then
    local hum=runner:FindFirstChildOfClass('Humanoid');local animator=hum and hum:FindFirstChildOfClass('Animator')
    if stop then
     local saved={tracks={},loose={}}
     if animator then for _,t in animator:GetPlayingAnimationTracks()do t:Stop(0);table.insert(saved.tracks,t)end end
     for _,d in runner:GetDescendants()do if d:IsA('BasePart')and not d.Anchored then d.Anchored=true;table.insert(saved.loose,d)end end
     paused[runner]=saved
    else
     local saved=paused[runner];paused[runner]=nil
     for _,d in saved.loose do d.Anchored=false end
     for _,t in saved.tracks do t:Play(.1,1,1.1)end
    end
   end
  end
 end
 workspace:GetAttributeChangedSignal('MissionRunning'):Connect(apply);apply()
end
