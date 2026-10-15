local M={}
local ART='rbxassetid://117655302204322'
local dark=Color3.fromRGB(35,40,42);local trim=Color3.fromRGB(94,99,83);local amber=Color3.fromRGB(215,174,63)
local function part(model,name,size,cf,color,collide,shape)
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color or dark;p.Material=Enum.Material.SmoothPlastic;p.Anchored=true;p.CanCollide=collide~=false;p.CanTouch=false;p.Shape=shape or Enum.PartType.Block;p.Parent=model;return p
end
local function display(p,name,text,color)
 local g=Instance.new('SurfaceGui');g.Name=name;g.Face=Enum.NormalId.Front;g.CanvasSize=Vector2.new(900,450);g.LightInfluence=0;g.Parent=p
 if name=='QuotaDisplay' then local image=Instance.new('ImageLabel');image.Size=UDim2.fromScale(1,1);image.BackgroundColor3=Color3.fromRGB(12,17,28);image.Image=ART;image.Parent=g end
 local t=Instance.new('TextLabel');t.Name='Readout';t.Size=UDim2.fromScale(.94,.72);t.Position=UDim2.fromScale(.03,.2);t.BackgroundColor3=Color3.fromRGB(12,17,28);t.BackgroundTransparency=name=='QuotaDisplay' and 1 or 0;t.TextColor3=color or amber;t.Font=Enum.Font.Code;t.TextScaled=true;t.Text=text;t.Parent=g;return t,g
end
function M.Cart(parent,cf)
 local m=Instance.new('Model');m.Name='RecoveryCart';m:SetAttribute('Kind','cart');m:SetAttribute('DisplayName','Recovery cart');m.Parent=parent
 local root=part(m,'Chassis',Vector3.new(5.6,.45,7.8),cf,dark);m.PrimaryPart=root
 part(m,'BasketFloor',Vector3.new(5,.3,7),cf*CFrame.new(0,.4,0),trim)
 for _,s in ipairs({-1,1}) do
  part(m,'BasketSide',Vector3.new(.3,2.2,7.4),cf*CFrame.new(s*2.55,1.65,0),dark)
  part(m,'TopRail',Vector3.new(.4,.22,7.6),cf*CFrame.new(s*2.55,2.85,0),trim)
  for z=-3,3,2 do part(m,'SideRib',Vector3.new(.4,1.65,.15),cf*CFrame.new(s*2.75,1.7,z),trim,false) end
  for _,z in ipairs({-2.6,2.6}) do local w=part(m,'Wheel',Vector3.new(.55,1.35,1.35),cf*CFrame.new(s*2.9,-.4,z),Color3.fromRGB(18,21,23),true,Enum.PartType.Cylinder);w.CustomPhysicalProperties=PhysicalProperties.new(1,.35,.05) end
 end
 for _,s in ipairs({-1,1}) do part(m,'BasketEnd',Vector3.new(5.3,2.2,.3),cf*CFrame.new(0,1.65,s*3.6),dark);for _,x in ipairs({-2.2,2.2}) do local l=part(m,'Marker',Vector3.new(.6,.2,.09),cf*CFrame.new(x,2.6,s*3.78),Color3.fromRGB(163,50,38),false);l.Material=Enum.Material.Neon end end
 local screen=part(m,'ValueMonitor',Vector3.new(4.7,1.5,.25),cf*CFrame.new(0,1.55,-3.83),trim,false);local label=display(screen,'CartValue','$0',amber)
 part(m,'Handle',Vector3.new(4.6,.22,.22),cf*CFrame.new(0,3.25,-4.1),trim,false)
 local grab=part(m,'GrabHandle',Vector3.new(5.5,4.5,.6),cf*CFrame.new(0,2.2,-4.2),trim,false);grab.Transparency=1;grab.CanQuery=true
 for _,s in ipairs({-1,1}) do part(m,'HandleStem',Vector3.new(.2,.65,.2),cf*CFrame.new(s*2.2,2.95,-4.1),trim,false) end
 for _,p in ipairs(m:GetChildren()) do if p:IsA('BasePart') and p~=root then
  if p.Name=='Wheel' then local a=Instance.new('Attachment');a.CFrame=root.CFrame:ToObjectSpace(p.CFrame);a.Parent=root;local b=Instance.new('Attachment');b.Parent=p;local h=Instance.new('HingeConstraint');h.Attachment0=a;h.Attachment1=b;h.Parent=root
  else local w=Instance.new('WeldConstraint');w.Part0=root;w.Part1=p;w.Parent=root;p.Massless=true end
 end end
 root.CustomPhysicalProperties=PhysicalProperties.new(2,.25,.02)
 m:SetAttribute('BasketOffset',Vector3.new(0,1.65,0));m:SetAttribute('BasketSize',Vector3.new(4.8,2.5,6.8))
 -- Longer and deeper basket; narrow enough for the six-stud map doors.
 m:ScaleTo(1.1)
 for _,x in ipairs(m:GetDescendants()) do if x:IsA('WeldConstraint') then x:Destroy() end end
 for _,x in ipairs(m:GetDescendants()) do
  if x:IsA('BasePart') then local localCF=root.CFrame:ToObjectSpace(x.CFrame);local wheel=x.Name=='Wheel';x.Size=Vector3.new(x.Size.X*.8,x.Size.Y*(wheel and .82 or .58),x.Size.Z*(wheel and .82 or 1));local pos=localCF.Position;x.CFrame=root.CFrame*CFrame.new(pos.X*.8,pos.Y*(wheel and .82 or .58),pos.Z)*localCF.Rotation
  elseif x:IsA('Attachment') and x.Parent==root then x.Position=x.Position*Vector3.new(.8,.82,1) end
 end
 for _,x in ipairs(m:GetChildren()) do if x:IsA('BasePart') and x~=root and x.Name~='Wheel' then local w=Instance.new('WeldConstraint');w.Part0=root;w.Part1=x;w.Parent=root end end
 m:SetAttribute('BasketOffset',Vector3.new(0,1.65*.58,0)*1.1);m:SetAttribute('BasketSize',Vector3.new(4.8*.8,2.5*.58,6.8)*1.1)
 m:SetAttribute('GroundOffset',.96965)
 -- Collision proxies for the rigid basket; wheel axles must not collide with it.
 for _,x in ipairs(m:GetDescendants()) do if x:IsA('BasePart') then x.CollisionGroup='RecoveryCart';x.CanCollide=x.Name=='Chassis' or x.Name=='BasketFloor' or x.Name=='BasketSide' or x.Name=='BasketEnd' or x.Name=='Wheel' end end
 return m,label
end
function M.Van(parent,entrance,exteriorZ)
 local rearZ=math.max(exteriorZ or entrance.Z,entrance.Z)+12
 local cf=CFrame.new(entrance.X,entrance.Y-.3,rearZ+25)
 local m=Instance.new('Model');m.Name='AnomalyRecoveryVan'
 -- Always fully streamed on every client: the cart guide outlines the whole van through walls from anywhere.
 m.ModelStreamingMode=Enum.ModelStreamingMode.Persistent;m.Parent=parent
 local endZ=cf.Position.Z+29;local startZ=entrance.Z-1
 local apronEnd=rearZ-4
 -- Enclose the recovery courtyard; the central level entrance remains the only opening.
 for _,side in ipairs({-1,1}) do
  part(m,'CourtyardBoundary',Vector3.new(.8,16,endZ-exteriorZ),CFrame.new(entrance.X+side*19,entrance.Y+7.95,(endZ+exteriorZ)/2),dark)
  part(m,'EntryBoundary',Vector3.new(13,16,.8),CFrame.new(entrance.X+side*12.5,entrance.Y+7.95,exteriorZ+.4),dark)
 end
 part(m,'CourtyardRearBoundary',Vector3.new(38,16,.8),CFrame.new(entrance.X,entrance.Y+7.95,endZ+.4),dark)
 part(m,'Apron',Vector3.new(38,.5,apronEnd-startZ),CFrame.new(entrance.X,entrance.Y-.3,(apronEnd+startZ)/2),Color3.fromRGB(50,53,52))
 for _,side in ipairs({-1,1}) do part(m,'ApronShoulder',Vector3.new(7,.5,endZ-apronEnd),CFrame.new(entrance.X+side*15.5,entrance.Y-.3,(endZ+apronEnd)/2),Color3.fromRGB(50,53,52)) end
 part(m,'ApronFront',Vector3.new(24,.5,4),cf*CFrame.new(0,0,27),Color3.fromRGB(50,53,52))
 -- A quiet return landmark at the level exit, visible from the foyer without blocking it.
 local returnSign=part(m,'VanReturnSign',Vector3.new(6.4,1.5,.16),CFrame.new(entrance.X,entrance.Y+11.2,exteriorZ+.7),Color3.fromRGB(22,42,43),false)
 returnSign.CanQuery=false;returnSign.CastShadow=false
 local returnText=display(returnSign,'ReturnMarker','VAN / RETURN',Color3.fromRGB(167,202,127));returnText.Font=Enum.Font.FredokaOne;returnText.BackgroundTransparency=1;returnText.Position=UDim2.fromScale(.03,.12);returnText.Size=UDim2.fromScale(.94,.76)
 local marker=part(m,'ReturnMarkerLamp',Vector3.new(6.1,.08,.1),returnSign.CFrame*CFrame.new(0,-.64,-.12),Color3.fromRGB(167,202,127),false);marker.Material=Enum.Material.Neon;marker.CanQuery=false;marker.CastShadow=false
 local beacon=Instance.new('PointLight');beacon.Color=Color3.fromRGB(167,202,127);beacon.Brightness=.3;beacon.Range=10;beacon.Shadows=false;beacon.Parent=marker
 for _,z in {2,5,8}do for _,side in {-1,1}do
  local paint=part(m,'ReturnChevron',Vector3.new(.14,.012,1.6),CFrame.new(entrance.X+side*.55,entrance.Y-.039,exteriorZ+z)*CFrame.Angles(0,-side*math.pi/4,0),Color3.fromRGB(132,155,106),false);paint.CanQuery=false;paint.CastShadow=false
 end end
 local floor=part(m,'Floor',Vector3.new(24,.5,50),cf,Color3.fromRGB(65,71,67));m.PrimaryPart=floor
 part(m,'Roof',Vector3.new(24,.5,54),cf*CFrame.new(0,12.5,1),trim)
 for _,side in ipairs({-1,1}) do
  part(m,'VanSide',Vector3.new(.5,12,51),cf*CFrame.new(side*11.75,6.25,0),dark)
  part(m,'SideStripe',Vector3.new(.08,.7,47),cf*CFrame.new(side*12.05,4.3,0),amber,false)
  for _,z in ipairs({-16,16}) do part(m,'Tyre',Vector3.new(1.5,4.5,4.5),cf*CFrame.new(side*12,-1,z),Color3.fromRGB(18,20,22),false,Enum.PartType.Cylinder) end
  part(m,'RearDoorFrame',Vector3.new(1.6,12,.5),cf*CFrame.new(side*10.9,6.25,-25),trim)
 end
 part(m,'CabBulkhead',Vector3.new(23.5,12,.45),cf*CFrame.new(0,6.25,17),dark)
 part(m,'CabFront',Vector3.new(23.5,5,.5),cf*CFrame.new(0,2.5,27),trim)
 local glass=part(m,'Windshield',Vector3.new(21,4,.25),cf*CFrame.new(0,7,27),Color3.fromRGB(39,65,69),false);glass.Material=Enum.Material.Glass;glass.Transparency=.25
 local porch=part(m,'RearHeader',Vector3.new(20,1,.55),cf*CFrame.new(0,12,-25),trim)
 local porchLight=Instance.new('PointLight');porchLight.Color=Color3.fromRGB(212,194,142);porchLight.Brightness=.55;porchLight.Range=26;porchLight.Shadows=true;porchLight.Parent=porch
 -- Level entry avoids the old vertical step and lets the cart roll straight in.
 part(m,'LoadingThreshold',Vector3.new(24,.5,4),cf*CFrame.new(0,0,-27),trim)
 part(m,'ConsoleDesk',Vector3.new(21,1.3,3.5),cf*CFrame.new(0,2.5,14.5),trim)
 local monitor=part(m,'QuotaMonitor',Vector3.new(12,4.5,.3),cf*CFrame.new(0,6.7,16.5),dark,false)
 local label,gui=display(monitor,'QuotaDisplay','ANOMALY RECOVERY',Color3.fromRGB(171,221,189))
 for _,x in ipairs({-8,8}) do local screen=part(m,'ScanMonitor',Vector3.new(3,2,.3),cf*CFrame.new(x,5,16)*CFrame.Angles(0,-x*.025,0),dark,false);display(screen,'Scan','SIGNAL\nSCAN ACTIVE',Color3.fromRGB(116,166,149)) end
 for i=1,12 do part(m,'ConsoleButton',Vector3.new(.4,.12,.4),cf*CFrame.new(i*1.2-7.8,3.22,13.5),i%2==0 and amber or Color3.fromRGB(85,131,109),false) end
 for _,side in ipairs({-1,1}) do
  part(m,'Bench',Vector3.new(2.3,1,12),cf*CFrame.new(side*9.7,1,3),trim)
  part(m,'BenchBack',Vector3.new(.4,2.5,12),cf*CFrame.new(side*10.8,2,3),dark)
  for i=1,4 do part(m,'EquipmentCrate',Vector3.new(1.6,1.5,2),cf*CFrame.new(side*10.4,4.8,-3+i*3),trim,false) end
 end
 for _,z in ipairs({-15,1,13}) do
  local lamp=part(m,'VanLight',Vector3.new(8,.1,1),cf*CFrame.new(0,12.05,z),Color3.fromRGB(197,204,170),false);lamp.Material=Enum.Material.Neon
  local light=Instance.new('PointLight');light.Brightness=.45;light.Range=20;light.Color=Color3.fromRGB(214,216,186);light.Shadows=true;light.Parent=lamp
 end
 local overhead=part(m,'EntranceQuota',Vector3.new(16,3,.4),cf*CFrame.new(0,14.5,-25.2),dark,false);local outside=display(overhead,'QuotaDisplay','RECOVERY QUOTA',amber)
 local notice=part(m,'Notice',Vector3.new(8,1.2,.15),cf*CFrame.new(0,10.5,16.25),dark,false);display(notice,'Rules','RETURN CART / SELL / EXTRACT',Color3.fromRGB(191,194,177))
 -- Flat paint marks, with no raised geometry to snag wheels or feet.
 -- Bay stripes follow the cart park outside the rear doors (CARTPARK_OFFSET in RecoveryRoundServer).
 

 -- Interior fittings stay against the shell and clear of spawn, cart bay and aisle.
 local fittings=Instance.new('Folder');fittings.Name='InteriorDetails';fittings.Parent=m
 local function detail(name,size,offset,color,material)
  local p=part(m,name,size,cf*offset,color,false);p.Parent=fittings;p.CanQuery=false;p.CastShadow=true;p.Material=material or Enum.Material.SmoothPlastic;return p
 end
 local panelColor=Color3.fromRGB(67,76,73);local cushion=Color3.fromRGB(54,72,66)
 for _,side in ipairs({-1,1}) do
  for _,z in ipairs({-19,-11,-3,5,13}) do
   detail('InsetWallPanel',Vector3.new(.1,8.2,7.3),CFrame.new(side*11.44,6.2,z),panelColor)
   detail('PanelJoin',Vector3.new(.14,9.8,.09),CFrame.new(side*11.35,6.2,z+3.75),Color3.fromRGB(32,43,40))
   for _,y in ipairs({2.3,10.1}) do
    for _,dz in ipairs({-3.2,3.2}) do detail('PanelFastener',Vector3.new(.08,.12,.12),CFrame.new(side*11.34,y,z+dz),Color3.fromRGB(118,129,116),Enum.Material.Metal) end
   end
  end
  detail('LowerWallRail',Vector3.new(.18,.25,39),CFrame.new(side*11.3,1.9,-4),Color3.fromRGB(92,106,92))
  detail('CeilingConduit',Vector3.new(.2,.2,39),CFrame.new(side*10.9,11.7,-4),Color3.fromRGB(104,116,105))
  for _,z in ipairs({-1.5,2.5,6.5}) do
   detail('BenchCushion',Vector3.new(2.15,.35,3.7),CFrame.new(side*9.7,1.675,z),cushion)
   detail('BenchBackCushion',Vector3.new(.22,1.8,3.7),CFrame.new(side*10.48,2.35,z),cushion)
   detail('SeatStitch',Vector3.new(.03,.02,3.3),CFrame.new(side*9.7,1.86,z),Color3.fromRGB(130,148,123))
  end
  detail('StorageShelf',Vector3.new(2.4,.16,12),CFrame.new(side*10.2,3.95,3),Color3.fromRGB(79,91,78))
  for _,z in ipairs({-1,5}) do detail('ShelfBracket',Vector3.new(.14,1.1,.14),CFrame.new(side*11.1,3.4,z),Color3.fromRGB(117,126,106),Enum.Material.Metal) end
  detail('AirVent',Vector3.new(.14,1.8,3),CFrame.new(side*11.27,9.1,-18),Color3.fromRGB(25,33,32))
  for y=8.45,9.75,.22 do detail('VentLouvre',Vector3.new(.12,.07,2.7),CFrame.new(side*11.15,y,-18),Color3.fromRGB(111,123,108)) end
 end
 for _,z in ipairs({-8,0,8}) do detail('CeilingRib',Vector3.new(22.4,.18,.35),CFrame.new(0,12.1,z),Color3.fromRGB(53,62,57)) end
 -- Matte traction floor and a flush central runner.
 floor.Material=Enum.Material.Metal;floor.Color=Color3.fromRGB(46,54,52);floor.Reflectance=0
 detail('AisleRunner',Vector3.new(5.5,.015,31),CFrame.new(1,.259,-4),Color3.fromRGB(30,38,36),Enum.Material.Slate)
 for _,z in ipairs({-19,-11,-3,5,11}) do
  detail('FloorSeam',Vector3.new(22.5,.01,.025),CFrame.new(0,.263,z),Color3.fromRGB(33,43,40))
 end
 -- Raised bezels, console legs, keyboard and instruments.
 for _,x in ipairs({-8,8}) do
  detail('ConsoleSupport',Vector3.new(.6,1.85,2.7),CFrame.new(x,1.175,14.5),Color3.fromRGB(40,49,46))
  detail('MonitorPedestal',Vector3.new(.3,1,.4),CFrame.new(x,3.65,15.8),Color3.fromRGB(88,103,87),Enum.Material.Metal)
 end
 detail('KeyboardBase',Vector3.new(4,.15,1.25),CFrame.new(0,3.225,13.3),Color3.fromRGB(28,36,34))
 -- Decor: the two alien cats (heart tails) sit on the console desk's right front corner, facing the aisle.
 local CATS_OFFSET=CFrame.new(9.55,3.15,13.6) -- desk top y=3.15, front edge z=12.75, side edge x=10.5
 local catsTemplate=game:GetService('ServerStorage'):FindFirstChild('AlienCatsDecor')
 if catsTemplate then local cats=catsTemplate:Clone();cats:ScaleTo(1.3);cats:PivotTo(cf*CATS_OFFSET);cats.Parent=fittings end -- 30% bigger
 for row=1,3 do for key=1,12 do detail('KeyboardKey',Vector3.new(.23,.06,.22),CFrame.new(-1.65+key*.26,3.33,12.85+row*.26),Color3.fromRGB(140,151,129)) end end
 detail('RadioUnit',Vector3.new(2.3,.9,1.3),CFrame.new(-6,3.6,14.5),Color3.fromRGB(27,35,33))
 for _,x in ipairs({-6.7,-5.3}) do local p=detail('RadioDial',Vector3.new(.18,.35,.35),CFrame.new(x,3.6,13.81)*CFrame.Angles(0,math.pi/2,0),Color3.fromRGB(154,164,139));p.Shape=Enum.PartType.Cylinder end
 local board=detail('SurveyBoard',Vector3.new(.2,4.2,6),CFrame.new(-11.18,7,-9)*CFrame.Angles(0,-math.pi/2,0),Color3.fromRGB(39,49,42))
 -- Board thickness is along local X; mount a front-facing plate separately.
 board.Size=Vector3.new(6,4.2,.2)
 display(board,'Survey','ANOMALY SURVEY\nSECTOR SCAN\nRECOVER / RETURN',Color3.fromRGB(160,186,152))
 local safety=detail('SafetyCabinet',Vector3.new(.5,2,1.8),CFrame.new(11.05,4.4,-13),Color3.fromRGB(126,62,47))
 detail('SafetyCrossA',Vector3.new(.06,.3,1),CFrame.new(10.76,4.4,-13),Color3.fromRGB(228,228,200))
 detail('SafetyCrossB',Vector3.new(.06,1,.3),CFrame.new(10.76,4.4,-13),Color3.fromRGB(228,228,200))
 for _,x in ipairs({-7,7}) do
  local lamp=detail('ConsoleTaskLamp',Vector3.new(1.8,.12,.4),CFrame.new(x,8.8,16.2),Color3.fromRGB(177,193,155),Enum.Material.Neon)
  local light=Instance.new('PointLight');light.Color=Color3.fromRGB(206,220,177);light.Brightness=.25;light.Range=12;light.Shadows=true;light.Parent=lamp
 end
 for _,lamp in ipairs(m:GetChildren()) do if lamp.Name=='VanLight' then
  lamp.Color=Color3.fromRGB(167,181,151)
  local light=lamp:FindFirstChildOfClass('PointLight');if light then light.Brightness=.32;light.Color=Color3.fromRGB(217,220,193) end
 end end
 -- Viewed from the aisle, right of SurveyBoard runs toward the rear doors (-Z).
 local TERMINAL_Y,TERMINAL_W,TERMINAL_H=7,3,2.4
 local function terminal(name,z,titleText,subtitleText,promptName,section)
  local p=detail(name,Vector3.new(TERMINAL_W,TERMINAL_H,.24),CFrame.new(-11.05,TERMINAL_Y,z)*CFrame.Angles(0,-math.pi/2,0),Color3.fromRGB(22,42,43))
  p.CanQuery=true;p.CanCollide=false;p:SetAttribute('ShopSection',section)
  local face=Instance.new('SurfaceGui');face.Name='TerminalFace';face.Face=Enum.NormalId.Front;face.CanvasSize=Vector2.new(600,420);face.LightInfluence=0;face.Parent=p
  local bg=Instance.new('Frame');bg.Size=UDim2.fromScale(.94,.9);bg.Position=UDim2.fromScale(.03,.05);bg.BackgroundColor3=Color3.fromRGB(31,55,53);bg.Parent=face
  local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,30);corner.Parent=bg
  local title=Instance.new('TextLabel');title.Name='Title';title.Size=UDim2.fromScale(.94,.5);title.Position=UDim2.fromScale(.03,.12);title.BackgroundTransparency=1;title.Text=titleText;title.Font=Enum.Font.FredokaOne;title.TextScaled=true;title.TextColor3=Color3.fromRGB(244,236,210);title.Parent=bg
  local subtitle=title:Clone();subtitle.Name='Subtitle';subtitle.Size=UDim2.fromScale(.94,.22);subtitle.Position=UDim2.fromScale(.03,.68);subtitle.Text=subtitleText;subtitle.TextColor3=Color3.fromRGB(167,202,127);subtitle.Parent=bg
  local prompt=Instance.new('ProximityPrompt');prompt.Name=promptName;prompt.ObjectText=titleText;prompt.ActionText=section=='Cosmetics'and 'Customize'or 'Open shop'
  prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=0;prompt.MaxActivationDistance=6;prompt.RequiresLineOfSight=true;prompt.ClickablePrompt=true;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton;prompt.Parent=p
  return p
 end
 terminal('VanTokenTerminal',-14.2,'TOKENS','UPGRADES / UNLOCKS','VanTokenShopPrompt','Tokens')
 terminal('VanRobuxTerminal',-17.8,'ROBUX','PASSES / PRODUCTS','VanRobuxShopPrompt','Robux')
 terminal('VanAppearanceTerminal',-21.4,'COSMETICS','COLORS / OWNED ITEMS','VanAppearancePrompt','Cosmetics')
 -- Fourth panel sits under the middle ROBUX panel so it doesn't cover SurveyBoard: opens the Gift a Revive teammate picker (MissionShopClient).
 local gift=terminal('VanGiftReviveTerminal',-17.8,'GIFT A REVIVE','BRING BACK A TEAMMATE','VanGiftRevivePrompt','GiftRevive')
 local giftPrompt=gift:FindFirstChild('VanGiftRevivePrompt');if giftPrompt then giftPrompt.ActionText='Gift a revive'end
 gift.CFrame*=CFrame.new(0,-(TERMINAL_H+.3),0)
 -- Daily and Timed reward panels on the right wall, opposite the shops (VanRewardsClient opens them and
 -- writes the live Status line; ProgressService owns the rewards). Neon bezel behind each face.
 local REWARD_Y,REWARD_W,REWARD_H=6.55,3.3,2.7
 local function rewardPanel(kind,z,accentA,accentB,titleText,icon,statusText)
  local bezel=detail(kind..'RewardsBezel',Vector3.new(REWARD_W+.2,REWARD_H+.2,.08),CFrame.new(11.2,REWARD_Y,z)*CFrame.Angles(0,math.pi/2,0),accentA,Enum.Material.Neon)
  bezel.CastShadow=false
  local p=detail(kind..'RewardsTerminal',Vector3.new(REWARD_W,REWARD_H,.24),CFrame.new(11.05,REWARD_Y,z)*CFrame.Angles(0,math.pi/2,0),Color3.fromRGB(14,16,22))
  p.CanQuery=true;p.CanCollide=false;p:SetAttribute('RewardKind',kind)
  local glow=Instance.new('SurfaceLight');glow.Face=Enum.NormalId.Front;glow.Color=accentA;glow.Brightness=1.4;glow.Range=7;glow.Angle=100;glow.Parent=p
  local face=Instance.new('SurfaceGui');face.Name='RewardFace';face.Face=Enum.NormalId.Front;face.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;face.CanvasSize=Vector2.new(660,540);face.LightInfluence=0;face.Brightness=1.6;face.Parent=p
  local function round(o,r)local c=Instance.new('UICorner');c.CornerRadius=r;c.Parent=o end
  local function rim(o,color,thickness)local s=Instance.new('UIStroke');s.Color=color;s.Thickness=thickness;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=o;return s end
  local function words(name,text,y,h,color,max)
   local t=Instance.new('TextLabel');t.Name=name;t.Text=text;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=color;t.Position=UDim2.fromScale(.06,y);t.Size=UDim2.fromScale(.88,h)
   local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=max;c.Parent=t
   local o=Instance.new('UIStroke');o.Color=Color3.fromRGB(5,5,8);o.Thickness=3;o.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;o.Parent=t
   return t
  end
  local bg=Instance.new('Frame');bg.Name='Frame';bg.Size=UDim2.fromScale(.96,.95);bg.Position=UDim2.fromScale(.02,.025);bg.BackgroundColor3=Color3.new(1,1,1);bg.Parent=face;round(bg,UDim.new(0,36))
  local fill=Instance.new('UIGradient');fill.Rotation=90;fill.Color=ColorSequence.new(Color3.fromRGB(30,30,40),Color3.fromRGB(10,10,14));fill.Parent=bg
  local edge=rim(bg,Color3.new(1,1,1),8);edge.Name='Rim';local edgeColor=Instance.new('UIGradient');edgeColor.Color=ColorSequence.new(accentA,accentB);edgeColor.Parent=edge
  local halo=Instance.new('Frame');halo.Name='IconGlow';halo.AnchorPoint=Vector2.new(.5,.5);halo.Position=UDim2.fromScale(.5,.36);halo.Size=UDim2.fromOffset(210,210);halo.BackgroundColor3=accentA;halo.BackgroundTransparency=.72;halo.Parent=bg;round(halo,UDim.new(1,0))
  local art=Instance.new('ImageLabel');art.Name='Icon';art.AnchorPoint=Vector2.new(.5,.5);art.Position=UDim2.fromScale(.5,.36);art.Size=UDim2.fromOffset(190,190);art.BackgroundTransparency=1;art.Image=icon;art.ScaleType=Enum.ScaleType.Crop;art.Parent=bg;round(art,UDim.new(1,0));rim(art,accentA,6)
  words('Title',titleText,.6,.17,Color3.fromRGB(255,244,214),90).Parent=bg
  words('Status',statusText,.78,.13,accentA,60).Parent=bg
  local prompt=Instance.new('ProximityPrompt');prompt.Name=kind..'RewardsPrompt';prompt.ObjectText=titleText;prompt.ActionText='Open'
  prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=0;prompt.MaxActivationDistance=6;prompt.RequiresLineOfSight=true;prompt.ClickablePrompt=true;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton;prompt.Parent=p
  return p
 end
 rewardPanel('Daily',-20.8,Color3.fromRGB(255,200,70),Color3.fromRGB(255,110,150),'DAILY REWARD','rbxassetid://130605175910404','CLAIM YOUR GIFT')
 rewardPanel('Timed',-17,Color3.fromRGB(80,220,255),Color3.fromRGB(140,110,255),'TIMED REWARDS','rbxassetid://116174307880260','PLAY TO UNLOCK')
 -- Quest Log terminal: one wide panel under Daily + Timed (they span z -22.45..-15.35, bezel bottom y 5.10).
 -- Each client writes its own progress into this face (QuestLogClient); the prompt opens the Quest Log screen.
 do
  local QY,QW,QH,QZ=3.95,7.1,1.6,-18.9
  local A,B=Color3.fromRGB(150,80,255),Color3.fromRGB(255,140,40)
  local bezel=detail('QuestsRewardsBezel',Vector3.new(QW+.2,QH+.2,.08),CFrame.new(11.2,QY,QZ)*CFrame.Angles(0,math.pi/2,0),A,Enum.Material.Neon)
  bezel.CastShadow=false
  local p=detail('QuestsRewardsTerminal',Vector3.new(QW,QH,.24),CFrame.new(11.05,QY,QZ)*CFrame.Angles(0,math.pi/2,0),Color3.fromRGB(14,16,22))
  p.CanQuery=true;p.CanCollide=false;p:SetAttribute('RewardKind','Quests')
  local glow=Instance.new('SurfaceLight');glow.Face=Enum.NormalId.Front;glow.Color=A;glow.Brightness=1.2;glow.Range=6;glow.Angle=100;glow.Parent=p
  local face=Instance.new('SurfaceGui');face.Name='RewardFace';face.Face=Enum.NormalId.Front;face.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;face.CanvasSize=Vector2.new(1320,300);face.LightInfluence=0;face.Brightness=1.6;face.Parent=p
  local bg=Instance.new('Frame');bg.Name='Frame';bg.Size=UDim2.fromScale(.98,.92);bg.Position=UDim2.fromScale(.01,.04);bg.BackgroundColor3=Color3.new(1,1,1);bg.Parent=face
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,36);c.Parent=bg
  local fill=Instance.new('UIGradient');fill.Rotation=90;fill.Color=ColorSequence.new(Color3.fromRGB(34,24,46),Color3.fromRGB(12,10,16));fill.Parent=bg
  local edge=Instance.new('UIStroke');edge.Name='Rim';edge.Color=Color3.new(1,1,1);edge.Thickness=8;edge.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;edge.Parent=bg
  local eg=Instance.new('UIGradient');eg.Color=ColorSequence.new(A,B);eg.Parent=edge
  local function words(name,text,x,y,w,h,color,max)
   local t=Instance.new('TextLabel');t.Name=name;t.Text=text;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=color
   t.TextXAlignment=Enum.TextXAlignment.Left;t.Position=UDim2.fromScale(x,y);t.Size=UDim2.fromScale(w,h);t.Parent=bg
   local k=Instance.new('UITextSizeConstraint');k.MaxTextSize=max;k.Parent=t
   local o=Instance.new('UIStroke');o.Color=Color3.fromRGB(5,5,8);o.Thickness=3;o.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;o.Parent=t
   return t
  end
  words('Title','QUEST LOG',.04,.1,.4,.42,Color3.fromRGB(255,244,214),110)
  words('Status','DAILY + WEEKLY QUESTS',.04,.58,.4,.3,B,64)
  -- Three daily progress bars (QuestLogClient fills Bar1..Bar3 for the local player).
  for i=1,3 do
   local bar=Instance.new('Frame');bar.Name='Bar'..i;bar.BackgroundColor3=Color3.fromRGB(8,8,12);bar.Position=UDim2.fromScale(.48,.14+(i-1)*.27);bar.Size=UDim2.fromScale(.48,.18);bar.Parent=bg
   local bc=Instance.new('UICorner');bc.CornerRadius=UDim.new(1,0);bc.Parent=bar
   local f=Instance.new('Frame');f.Name='Fill';f.BackgroundColor3=Color3.new(1,1,1);f.Size=UDim2.fromScale(0,1);f.Parent=bar
   local fc=Instance.new('UICorner');fc.CornerRadius=UDim.new(1,0);fc.Parent=f
   local fg=Instance.new('UIGradient');fg.Color=ColorSequence.new(A,B);fg.Parent=f
  end
  local prompt=Instance.new('ProximityPrompt');prompt.Name='QuestsRewardsPrompt';prompt.ObjectText='QUEST LOG';prompt.ActionText='Open'
  prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=0;prompt.MaxActivationDistance=6;prompt.RequiresLineOfSight=true;prompt.ClickablePrompt=true;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton;prompt.Parent=p
 end
 -- Gift a Revive, Jumpscare Everyone and Instant Win are bought and used from the ROBUX panel (VanShopClient).
 m:SetAttribute('InteriorDetailVersion',2)
 m:SetAttribute('InteriorSize',Vector3.new(23,12,41));m:SetAttribute('ExteriorBoundary',exteriorZ or entrance.Z)
 -- CruiseExterior supplies the visible pier; preserve the existing support/collision.
 local map=workspace:FindFirstChild('Mansion')
 if map and map:GetAttribute('MapKind')=='Cruise' then
  local hidden={CourtyardBoundary=true,EntryBoundary=true,CourtyardRearBoundary=true,Apron=true,ApronShoulder=true,ApronFront=true}
  for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')and hidden[part.Name]then
   part.Transparency=1;part.CastShadow=false
   for _,detail in ipairs(part:GetChildren())do if detail:IsA('Decal')or detail:IsA('Texture')then detail.Transparency=1 end end
  end end
 end
 return m,cf,{label,outside},gui
end
return M