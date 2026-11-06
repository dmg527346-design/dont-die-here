-- First-game tutorial and the cart guide.
-- First game (save says TutorialDone=false): grab the cart, push it, then fill it with loot. After that the card stays
-- quiet while the player explores. When the cart holds enough to meet the quota the cart gets a soft outline; once
-- someone pushes it, the outline moves to the van and a dotted floor path leads back. The first sale completes the
-- tutorial (saved through LobbyEvent).
-- Every later level: when the cart is ready the van shows white through walls and a banner says so at the top.
-- Everything here is local, silent and steps back while a creature is close.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Tween=game:GetService('TweenService')
local PathService=game:GetService('PathfindingService')
local InputHints=require(RS:WaitForChild('InputHints'))
local Guided=require(script:WaitForChild('GuidedTutorial'));Guided.Start()
-- The shop chapter (team boost, then Movement Speed) is off (owner 2026-10-27): after the tutorial players just play.
local p=Players.LocalPlayer
local event=RS:WaitForChild('LobbyEvent')
-- Analytics: the side menus set these attributes on the client only, so report the first open to PlayerMetricsServer.
task.spawn(function()
 local report=RS:WaitForChild('TutorialStepEvent',30);if not report then return end
 for _,name in {'QuestLogOpen','VanRewardsOpen','VanShopOpen'}do
  local sent=false
  p:GetAttributeChangedSignal(name):Connect(function()if not sent and p:GetAttribute(name)==true then sent=true;report:FireServer('open:'..name)end end)
 end
end)

local CARD_W,CARD_H=300,92
local CARD_BOTTOM=96 -- bottom centre, above the stamina bar and Roblox's own bottom bar
local ink,panel,cream,muted,green=Color3.fromRGB(8,18,22),Color3.fromRGB(22,42,43),Color3.fromRGB(244,236,210),Color3.fromRGB(157,181,171),Color3.fromRGB(167,202,127)
local DOT_SPACING,DOT_COUNT=3,22 -- the path shows the next ~65 studs
local MONSTER_NEAR=40 -- studs: the guide steps back while a creature is this close
local PATH_REFRESH=1.2
local SALE_SPOT=CFrame.new(0,1,-18) -- inside the rear of the van floor, where a parked cart sells
local VAN_SHELL={Roof=true,VanSide=true,CabFront=true,Windshield=true,RearDoorFrame=true,RearHeader=true,Tyre=true,Floor=true}

local function state()return RS:FindFirstChild('RecoveryRound')end
local function attr(k)local s=state();return s and s:GetAttribute(k)end
local function cartModel()local m=workspace:FindFirstChild('Mansion');local i=m and m:FindFirstChild('Interactive');return i and i:FindFirstChild('RecoveryCart')end
local function vanModel()local c=workspace:FindFirstChild('RecoveryCamp');return c and c:FindFirstChild('AnomalyRecoveryVan')end
local function root()return p.Character and p.Character:FindFirstChild('HumanoidRootPart')end
local function cartHeld()local c=cartModel();return c~=nil and c:GetAttribute('HeldBy')~=nil end
local function cartMine()local c=cartModel();return c~=nil and c:GetAttribute('HeldBy')==p.UserId end
local function sold()return (attr('Sold')or 0)>0 end
-- Ready: what is in the cart would meet the quota if it were sold now.
local function cartReady()
 local cartValue=attr('CartValue')or 0
 return attr('Phase')=='Searching' and attr('SaleEnds')==nil and cartValue>0 and (attr('Sold')or 0)+cartValue>=(attr('Quota')or math.huge)
end
-- First game only: a quarter of the quota (about two items) is enough for a first sale, so new players see the van
-- pay out early instead of wandering until the cart is full.
local FIRST_SALE_SHARE=.25
local function firstSaleReady()
 local cartValue=attr('CartValue')or 0
 return attr('Phase')=='Searching' and attr('SaleEnds')==nil and not sold() and cartValue>=(attr('Quota')or math.huge)*FIRST_SALE_SHARE
end
local function monsterDistance()
 local r=root();local folder=workspace:FindFirstChild('RoamingCreatures')
 if not r or not folder then return math.huge end
 local best=math.huge
 for _,m in folder:GetChildren()do if m:IsA('Model')then local d=(m:GetPivot().Position-r.Position).Magnitude;if d<best then best=d end end end
 return best
end

-- Intro steps run once, in order; each ends when done() or after its timer. Then the card is silent until the cart is ready.
local moved,movedFrom=0,nil
-- Flashlight step: F / gamepad B (FlashlightController's keys) or the touch LIGHT button.
local lightUsed=false
game:GetService('UserInputService').InputBegan:Connect(function(input)
 if input.KeyCode==Enum.KeyCode.F or input.KeyCode==Enum.KeyCode.ButtonB then lightUsed=true end
end)
task.spawn(function()
 local b;repeat b=p.PlayerGui:FindFirstChild('LightAction',true);task.wait(1)until b
 if b:IsA('GuiButton')then b.Activated:Connect(function()lightUsed=true end)end
end)
local INTRO={
 {title='GRAB THE CART',kb='The cart is in front of you, highlighted. Hold left click on it to grab it.',pad='The cart is in front of you, highlighted. Hold RT on it to grab it.',touch='The cart is in front of you, highlighted. Aim at it and tap GRAB.',cart=true,timer=45,done=function()return cartMine()or(attr('CartValue')or 0)>0 end},
 {title='PUSH IT',kb='Walk while you hold left click to push the cart. Let go to leave it.',pad='Walk while you hold RT to push the cart. Let go to leave it.',touch='Walk to push the cart. Tap DROP to leave it.',timer=20,minimum=1.5,done=function()return moved>=10 end},
 {title='CROUCH',kb='Press C or Ctrl to crouch. Press it again to stand up.',pad='Press down on the right joystick to crouch. Press it again to stand up.',touch='Tap CROUCH to crouch. Tap STAND to get up.',timer=20,minimum=1.5,done=function()return p:GetAttribute('Crouching')==true end},
 {title='HIDE UNDER TABLES',kb='Crouch under a table to hide. Monsters cannot see you while you are tucked under it.',timer=5},
 {title='CLOSETS',kb='Closets hide you too. Look at one and press E to step inside.',pad='Closets hide you too. Look at one and press X to step inside.',touch='Closets hide you too. Aim at one and tap HIDE to step inside.',timer=5},
 {title='FILL THE CART',kb='Look inside the rooms: loot hides on shelves, in drawers and behind doors. Hold left click to carry it to the cart.',pad='Look inside the rooms: loot hides on shelves, in drawers and behind doors. Hold RT to carry it to the cart.',touch='Look inside the rooms: loot hides on shelves, in drawers and behind doors. Aim at it and tap GRAB to carry it to the cart.',timer=12},
}
local READY={title='CART IS READY',kb='The cart has enough to meet the quota. Go back and grab it.'}
local CASH_IN={title='CASH IN',kb='The van buys loot any time. Grab the cart and push it into the van to sell what you have.'}
local TO_VAN={title='TO THE VAN',kb='Push the cart into the van. Follow the dots, then let go of left click to sell.',pad='Push the cart into the van. Follow the dots, then let go of RT to sell.',touch='Push the cart into the van. Follow the dots, then tap DROP to sell.'}
local SOLD={title='SOLD!',kb='Nice work. Everyone still alive climbs into the van to leave.'}
-- A first sale below the quota: show progress so nobody thinks the level is done.
local SOLD_PART={title='SOLD',kb=''}
local function soldStep()
 local s,q=attr('Sold')or 0,attr('Quota')or 0
 if s>=q then return SOLD end
 SOLD_PART.title='SOLD $'..s..' / $'..q;SOLD_PART.kb='Keep collecting! Bring more loot to the van until you reach $'..q..'.'
 return SOLD_PART
end

local gui,card,titleLabel,bodyLabel,banner
local function build()
 gui=Instance.new('ScreenGui');gui.Name='FirstGameTutorial';gui.ResetOnSpawn=false;gui.DisplayOrder=150;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=p:WaitForChild('PlayerGui')
 card=Instance.new('Frame');card.Name='Tip';card.AnchorPoint=Vector2.new(.5,1);card.Size=UDim2.fromOffset(CARD_W,CARD_H);card.BackgroundColor3=panel;card.BackgroundTransparency=.2;card.BorderSizePixel=0;card.Visible=false;card.Parent=gui
 Instance.new('UICorner',card).CornerRadius=UDim.new(0,12)
 local outline=Instance.new('UIStroke');outline.Color=ink;outline.Thickness=2;outline.Parent=card
 Instance.new('UIScale',card).Name='Scale'
 titleLabel=Instance.new('TextLabel');titleLabel.BackgroundTransparency=1;titleLabel.Position=UDim2.fromOffset(12,8);titleLabel.Size=UDim2.new(1,-74,0,20);titleLabel.Font=Enum.Font.FredokaOne;titleLabel.TextSize=17;titleLabel.TextColor3=green;titleLabel.TextXAlignment=Enum.TextXAlignment.Left;titleLabel.Parent=card
 bodyLabel=titleLabel:Clone();bodyLabel.Position=UDim2.fromOffset(12,32);bodyLabel.Size=UDim2.new(1,-24,1,-38);bodyLabel.TextSize=14;bodyLabel.TextColor3=cream;bodyLabel.TextWrapped=true;bodyLabel.TextYAlignment=Enum.TextYAlignment.Top;bodyLabel.Parent=card
 local skip=Instance.new('TextButton');skip.Name='Skip';skip.Text='SKIP';skip.Position=UDim2.new(1,-56,0,5);skip.Size=UDim2.fromOffset(50,28);skip.BackgroundColor3=ink;skip.BackgroundTransparency=.3;skip.TextColor3=muted;skip.Font=Enum.Font.FredokaOne;skip.TextSize=13;skip.AutoButtonColor=true;skip.Parent=card
 Instance.new('UICorner',skip).CornerRadius=UDim.new(0,6)
 -- Top banner under the quota HUD: the cart is ready to sell.
 banner=Instance.new('Frame');banner.Name='CartReady';banner.AnchorPoint=Vector2.new(.5,0);banner.Size=UDim2.fromOffset(320,46);banner.BackgroundColor3=panel;banner.BackgroundTransparency=.3;banner.BorderSizePixel=0;banner.Visible=false;banner.Parent=gui
 Instance.new('UICorner',banner).CornerRadius=UDim.new(0,10)
 local bannerOutline=Instance.new('UIStroke');bannerOutline.Color=ink;bannerOutline.Thickness=2;bannerOutline.Parent=banner
 Instance.new('UIScale',banner).Name='Scale'
 local head=titleLabel:Clone();head.Name='Title';head.Text='CART READY TO SELL';head.Position=UDim2.fromOffset(0,4);head.Size=UDim2.new(1,0,0,22);head.TextSize=18;head.TextColor3=Color3.fromRGB(240,240,232);head.TextXAlignment=Enum.TextXAlignment.Center;head.Parent=banner
 local sub=bodyLabel:Clone();sub.Name='Hint';sub.Text='Push the cart into the van and let go';sub.Position=UDim2.fromOffset(0,25);sub.Size=UDim2.new(1,0,0,16);sub.TextSize=12;sub.TextColor3=muted;sub.TextXAlignment=Enum.TextXAlignment.Center;sub.Parent=banner
 return skip
end
local skipButton=build()
-- Phones and tablets get a compact card: about a third of the width and a sixth of the height on a phone, sitting
-- just above the centred stamina bar (220x10 at 28 px from the bottom on touch) and clear of the thumbstick and
-- the GRAB/USE/RUN buttons on the right. Text stays at a readable size instead of being scaled down.
local function layout()
 local cam=workspace.CurrentCamera;local v=cam and cam.ViewportSize or Vector2.new(1280,720)
 local touch=InputHints.Get()=='touch'
 local compact=touch or v.Y<600
 if compact then
  card.Size=UDim2.fromOffset(math.min(250,v.X*.36),v.Y<500 and 58 or 66);card.Scale.Scale=1
  titleLabel.TextSize=13;titleLabel.Position=UDim2.fromOffset(10,5);titleLabel.Size=UDim2.new(1,-70,0,16)
  bodyLabel.TextSize=v.Y<500 and 11 or 12;bodyLabel.Position=UDim2.fromOffset(10,23);bodyLabel.Size=UDim2.new(1,-20,1,-26)
  skipButton.Size=UDim2.fromOffset(46,22);skipButton.Position=UDim2.new(1,-52,0,4)
  card.BackgroundTransparency=.3
 else
  card.Size=UDim2.fromOffset(CARD_W,CARD_H);card.Scale.Scale=math.clamp(math.min(v.X/1280,v.Y/720),.75,1)
  titleLabel.TextSize=17;titleLabel.Position=UDim2.fromOffset(12,8);titleLabel.Size=UDim2.new(1,-74,0,20)
  bodyLabel.TextSize=14;bodyLabel.Position=UDim2.fromOffset(12,32);bodyLabel.Size=UDim2.new(1,-24,1,-38)
  skipButton.Size=UDim2.fromOffset(50,28);skipButton.Position=UDim2.new(1,-56,0,5)
 end
 bodyLabel.TextScaled=compact;local fit=bodyLabel:FindFirstChild('Fit')or Instance.new('UITextSizeConstraint');fit.Name='Fit';fit.MaxTextSize=bodyLabel.TextSize;fit.MinTextSize=9;fit.Parent=bodyLabel
 banner.Scale.Scale=compact and(v.Y<500 and .7 or .85)or math.clamp(v.X/1280,.75,1)
 card.Position=UDim2.new(.5,0,1,-(touch and 64 or CARD_BOTTOM))
 banner.Position=UDim2.new(.5,0,0,v.Y<500 and 58 or 90) -- under the 82 px quota HUD (0.65 scale on short screens)
end
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout);InputHints.Changed:Connect(layout);layout()

-- World guides: one outline for the cart, one box for the van, a pool of floor dots. All local.
local cartGlow=Instance.new('Highlight');cartGlow.Name='CartGuide';cartGlow.FillColor=Color3.new(1,1,1);cartGlow.OutlineColor=Color3.new(1,1,1);cartGlow.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;cartGlow.Enabled=false;cartGlow.Parent=gui
-- The van: Highlight skipped most of a near-invisible copy of the van body, so the van is marked with one box fitted
-- around its body parts (not the courtyard walls and apron in the same model), drawn on top of everything.
local vanAnchor=Instance.new('Part');vanAnchor.Name='VanGuideBox';vanAnchor.Anchored=true;vanAnchor.CanCollide=false;vanAnchor.CanQuery=false;vanAnchor.CanTouch=false;vanAnchor.CastShadow=false;vanAnchor.Transparency=1
-- Fill plus 12 edge bars, all AlwaysOnTop so the van shows through walls (SelectionBox and Highlight do not here).
-- Note: Studio's screen_capture leaves these adornments out; judge them in the play window.
local VAN_GREEN=Color3.fromRGB(110,240,150)
-- The van stays visible: an almost clear green tint, a glowing green wireframe, and a second wireframe that keeps
-- swelling out of the van and fading (a sonar ripple), so it reads as "bring it here" (owner, 2026-10-22: the white box hid the van).
local vanFill=Instance.new('BoxHandleAdornment');vanFill.Name='VanGuideFill';vanFill.AlwaysOnTop=true;vanFill.ZIndex=1;vanFill.Color3=VAN_GREEN;vanFill.Adornee=vanAnchor;vanFill.Visible=false;vanFill.Parent=gui
local vanEdges,vanRipple={},{}
for i=1,12 do local e=vanFill:Clone();e.Name='VanGuideEdge';e.ZIndex=3;e.Parent=gui;vanEdges[i]=e end
for i=1,12 do local e=vanFill:Clone();e.Name='VanGuideRipple';e.ZIndex=2;e.Parent=gui;vanRipple[i]=e end
local function placeEdges(list,s,thick,transparency)
 local i=0
 for axis=1,3 do -- 4 edges along each axis
  for _,a in{-1,1}do for _,b in{-1,1}do
   i+=1;local e=list[i];e.Transparency=transparency
   if axis==1 then e.Size=Vector3.new(s.X+thick,thick,thick);e.CFrame=CFrame.new(0,a*s.Y/2,b*s.Z/2)
   elseif axis==2 then e.Size=Vector3.new(thick,s.Y+thick,thick);e.CFrame=CFrame.new(a*s.X/2,0,b*s.Z/2)
   else e.Size=Vector3.new(thick,thick,s.Z+thick);e.CFrame=CFrame.new(a*s.X/2,b*s.Y/2,0)end
  end end
 end
end
local vanGlow={} -- set(visible, fillTransparency, edgeTransparency, edgeThickness)
function vanGlow.set(visible,fillT,edgeT,thick)
 -- adornments live under the camera (they draw from there in every Studio and client build)
 local cam=workspace.CurrentCamera
 if cam and vanFill.Parent~=cam then vanFill.Parent=cam;for _,e in vanEdges do e.Parent=cam end;for _,e in vanRipple do e.Parent=cam end end
 vanFill.Visible=visible;for _,e in vanEdges do e.Visible=visible end;for _,e in vanRipple do e.Visible=visible end
 if not visible then return end
 local s=vanAnchor.Size;vanFill.Size=s;vanFill.Transparency=math.max(fillT,.9)
 local pulse=.5+.5*math.sin(os.clock()*4)
 placeEdges(vanEdges,s,thick*(1.4+.4*pulse),math.clamp(edgeT*.8+.1*(1-pulse),0,1))
 local wave=(os.clock()/1.3)%1 -- 0 -> 1 every 1.3 s
 placeEdges(vanRipple,s*(1+wave*.35),thick*.9,math.clamp(edgeT+(1-edgeT)*wave,0,1))
end
local boxOf,boxCount=nil,0
local function fitVanBox(van)
 -- refit when the van is rebuilt for a new level or more of it has streamed in
 local parts={};for _,x in van:GetChildren()do if x:IsA('BasePart')and VAN_SHELL[x.Name]then table.insert(parts,x)end end
 if boxOf==van and boxCount==#parts and vanAnchor.Parent then return end
 boxOf,boxCount=van,#parts
 local base=van.PrimaryPart and van.PrimaryPart.CFrame or van:GetPivot()
 local lo,hi=Vector3.one*math.huge,-Vector3.one*math.huge
 for _,x in parts do
  local h=x.Size/2
  for _,sx in{-1,1}do for _,sy in{-1,1}do for _,sz in{-1,1}do
   local q=base:PointToObjectSpace(x.CFrame*Vector3.new(h.X*sx,h.Y*sy,h.Z*sz));lo=lo:Min(q);hi=hi:Max(q)
  end end end
 end
 if #parts==0 then return end
 vanAnchor.Size=hi-lo+Vector3.new(.2,.2,.2);vanAnchor.CFrame=base*CFrame.new((lo+hi)/2)
 vanAnchor.Parent=workspace.CurrentCamera
end
-- Cart Beacon gear (GearShopServer fits it and sets the cart's BeaconFitted): a cyan CART tag with the distance, drawn
-- through walls for every player while it is fitted. Hidden up close and for whoever is pushing the cart.
do
 local BEACON_TAG_NEAR=14 -- studs: closer than this the cart is plainly in view
 local tag=Instance.new('BillboardGui');tag.Name='CartBeaconTag';tag.AlwaysOnTop=true;tag.LightInfluence=0;tag.ResetOnSpawn=false
 tag.Size=UDim2.fromOffset(110,40);tag.StudsOffsetWorldSpace=Vector3.new(0,4.2,0);tag.Enabled=false
 local icon=Instance.new('Frame');icon.Name='Diamond';icon.AnchorPoint=Vector2.new(.5,0);icon.Position=UDim2.fromScale(.5,0);icon.Size=UDim2.fromOffset(13,13)
 icon.Rotation=45;icon.BackgroundColor3=Color3.fromRGB(120,230,255);icon.BorderSizePixel=0;icon.Parent=tag
 local iconStroke=Instance.new('UIStroke');iconStroke.Thickness=1.5;iconStroke.Color=Color3.fromRGB(20,40,50);iconStroke.Parent=icon
 local text=Instance.new('TextLabel');text.Name='Distance';text.Position=UDim2.fromOffset(0,16);text.Size=UDim2.new(1,0,0,24);text.BackgroundTransparency=1
 text.Font=Enum.Font.FredokaOne;text.TextScaled=true;text.TextColor3=Color3.fromRGB(205,245,255);text.Text='CART';text.Parent=tag
 local stroke=Instance.new('UIStroke');stroke.Thickness=1.5;stroke.Transparency=.3;stroke.Parent=text
 tag.Parent=p:WaitForChild('PlayerGui')
 task.spawn(function()
  while true do
   local cart=cartModel();local r=root()
   local on=cart~=nil and cart.PrimaryPart~=nil and cart:GetAttribute('BeaconFitted')==true and r~=nil and not cartMine()
   local d=on and(cart.PrimaryPart.Position-r.Position).Magnitude or 0
   on=on and d>BEACON_TAG_NEAR
   tag.Adornee=on and cart.PrimaryPart or nil;tag.Enabled=on
   if on then
    text.Text=('CART  %dm'):format(math.floor(d*.28+.5))
    icon.BackgroundTransparency=.25*(.5+.5*math.sin(os.clock()*3)) -- the same slow pulse as the lamp
   end
   task.wait(.2)
  end
 end)
end
local dotFolder=Instance.new('Folder');dotFolder.Name='CartGuideDots'
local dots={}
local function dotPart(name,size,color,material)
 local d=Instance.new('Part');d.Name=name;d.Shape=Enum.PartType.Cylinder;d.Size=size;d.Color=color;d.Material=material
 d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.CastShadow=false
 return d
end
for i=1,DOT_COUNT do
 local dot=dotPart('Dot',Vector3.new(.05,.5,.5),Color3.fromRGB(226,226,220),Enum.Material.Neon)
 local stroke=dotPart('Stroke',Vector3.new(.04,.82,.82),Color3.fromRGB(12,14,16),Enum.Material.SmoothPlastic)
 dot.Parent=dotFolder;stroke.Parent=dotFolder
 dots[i]={dot=dot,stroke=stroke}
end
local flat=CFrame.Angles(0,0,math.pi/2) -- cylinder axis X -> up
local pathPoints,pathBusy,pathAt,pathFrom=nil,false,0,nil
local agent=PathService:CreatePath({AgentRadius=2.2,AgentHeight=5,AgentCanJump=false,WaypointSpacing=DOT_SPACING})
local function computePath(from,to)
 pathBusy=true
 task.spawn(function()
  local ok=pcall(function()agent:ComputeAsync(from,to)end)
  local points={}
  if ok and agent.Status==Enum.PathStatus.Success then
   for _,w in agent:GetWaypoints()do table.insert(points,w.Position)end
  else
   -- No path (map still streaming in): a straight line toward the van on the floor under the player.
   local start=from-Vector3.new(0,2.6,0);local dir=Vector3.new(to.X,start.Y,to.Z)-start;local len=dir.Magnitude
   if len>.5 then for d=0,math.min(len,DOT_SPACING*DOT_COUNT),DOT_SPACING do table.insert(points,start+dir.Unit*d)end end
  end
  pathPoints=points;pathBusy=false
 end)
end
local function hideDots()dotFolder.Parent=nil;pathPoints=nil;pathFrom=nil end
local function drawDots(fade)
 local r=root();if not r or not pathPoints then return end
 -- Start at the waypoint nearest the player so the line never trails behind them.
 local start,best=1,math.huge
 for i,pt in ipairs(pathPoints)do local d=(pt-r.Position).Magnitude;if d<best then best,start=d,i end end
 for i=1,DOT_COUNT do
  local pt=pathPoints[start+i];local pair=dots[i]
  if pt then
   local cf=CFrame.new(pt+Vector3.new(0,.06,0))*flat
   pair.dot.CFrame=cf*CFrame.new(.02,0,0);pair.stroke.CFrame=cf
   local t=math.clamp(.35+(i/DOT_COUNT)*.45+fade,0,1) -- dim, dimmer further along
   pair.dot.Transparency=t;pair.stroke.Transparency=math.clamp(t-.2,0,1)
  else pair.dot.Transparency=1;pair.stroke.Transparency=1 end
 end
 dotFolder.Parent=workspace.CurrentCamera
end

-- Studio preview: set ReplicatedStorage attribute TutorialPreview to "first" (first-game flow, nothing saved)
-- or "veteran" (later-level van mark and banner), then press Play. Ignored in live servers.
local function preview()
 local v=game:GetService('RunService'):IsStudio()and RS:GetAttribute('TutorialPreview')
 return(v=='first'or v=='veteran')and v or nil
end
-- Owner (live servers and Studio): replay the first-game tutorial on level 1 of every save, to see what a new player
-- sees. Nothing is saved for a replay.
local function ownerReplay()
 return p:GetAttribute('AdminOwner')==true and(attr('Round')or 1)<=1
end
local finished,replaying=false,false
local function finish()
 if finished then return end;finished=true
 if preview()or replaying then return end
 p:SetAttribute('TutorialDone',true) -- local echo; the server publishes the saved value
 event:FireServer(900000000+math.random(1,99999),'tutorialDone',{})
end
-- stage: 1..#INTRO = intro steps, 'wait' = silent until the cart is ready, 'sold' = closing card, nil = tutorial over
local stage,stageAt,shownStep=nil,0,nil
local function enter(s)stage=s;stageAt=os.clock()end
skipButton.Activated:Connect(function()finish();stage=nil;card.Visible=false end)

local function show(step)
 if step~=shownStep then
  shownStep=step
  card.BackgroundTransparency=.6;Tween:Create(card,TweenInfo.new(.25),{BackgroundTransparency=.2}):Play()
 end
 titleLabel.Text=step.title
 local device=InputHints.Get()
 local body=step[device]or step.kb
 bodyLabel.Text=device=='pad'and InputHints.PadText(body)or body -- RT on Xbox, R2 on PlayStation
end

local wasActive,bannerWasShown,lastGoalKind=false,false,nil
while true do
 task.wait(.1)
 local active=p:GetAttribute('MissionActive')==true
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 local alive=active and h~=nil and h.Health>0 and p:GetAttribute('RoundDead')~=true
 if active and not wasActive then
  moved,movedFrom,shownStep,lightUsed=0,nil,nil,false
  replaying=false -- GuidedTutorial owns the new first-game flow.
  local firstTime=false -- First-game steps are handled by this owner's GuidedTutorial child.
  if replaying then finished=false end
  if not finished and(firstTime or replaying)then enter(1)else stage=nil end
 elseif not active and wasActive then stage=nil end
 wasActive=active

 local cart=cartModel()
 if cart and cart.PrimaryPart and cartMine()then -- how far this player has pushed the cart
  local pos=cart.PrimaryPart.Position;if movedFrom then moved+=(pos-movedFrom).Magnitude end;movedFrom=pos
 else movedFrom=nil end

 -- Any sale (by anyone) means the cart made it back: close the tutorial.
 if stage and stage~='sold' and sold()then finish();enter('sold')end
 local elapsed=os.clock()-stageAt
 local step,wantCart,wantVanPath=nil,false,false
 if type(stage)=='number'then
  local s=INTRO[stage]
  if (s.done and s.done()and elapsed>=(s.minimum or .5))or elapsed>=s.timer then
   if stage<#INTRO then enter(stage+1)else enter('wait')end
   if stage==2 and not cartMine()then enter(3)end -- never grabbed it (a teammate has it): skip the push tip
   s=type(stage)=='number'and INTRO[stage]or nil
  end
  step=s;wantCart=s~=nil and s.cart==true
 end
 if stage=='wait'and(cartReady()or firstSaleReady())then
  if cartHeld()then step,wantVanPath=TO_VAN,true else step,wantCart=cartReady()and READY or CASH_IN,true end
 elseif stage=='sold'then
  if elapsed<7 then step=soldStep()else stage=nil end
 end
 card.Visible=alive and step~=nil and not p.PlayerGui:FindFirstChild('RoundRecap') -- the level-cleared screen owns the moment
 if step then show(step)end
 local firstGame=stage~=nil or Guided.IsActive()

 local fade=monsterDistance()<MONSTER_NEAR and .4 or 0
 local ready=active and cartReady()
 -- After the first game: through-wall van mark and a banner while the cart is ready.
 local wantVanMark=ready and not firstGame and(p:GetAttribute('TutorialDone')==true or preview()~=nil)
 local showBanner=alive and wantVanMark
 if showBanner and not bannerWasShown then banner.BackgroundTransparency=.7;Tween:Create(banner,TweenInfo.new(.4),{BackgroundTransparency=.3}):Play()end
 banner.Visible=showBanner;bannerWasShown=showBanner

 cartGlow.Adornee=alive and wantCart and cart or nil;cartGlow.Enabled=cartGlow.Adornee~=nil
 -- Owner 2026-10-29: hard to see on phones (small screen, thin outline line). Phones: a solid outline and a soft white
 -- fill that pulses so the whole cart lights up; other devices: a stronger outline too. Still fades near a monster.
 local touchCart=InputHints.Get()=='touch';local pulse=(math.sin(os.clock()*4)+1)/2
 cartGlow.FillTransparency=math.min(1,(touchCart and .6+.2*pulse or .82)+fade);cartGlow.OutlineTransparency=math.min(1,(touchCart and 0 or .2)+fade)

 local van=vanModel();local r=root();local floor=van and van.PrimaryPart
 local goal=floor and(floor.CFrame*SALE_SPOT).Position
 local vanDist=(goal and r)and(goal-r.Position).Magnitude or 0
 local near=math.clamp((40-vanDist)/25,0,1) -- fades away as you arrive
 local guidedVan=Guided.GoalIsVan()
 if alive and floor and(wantVanPath or wantVanMark or guidedVan)then
  fitVanBox(van)
  local thick=math.clamp(vanDist*.006,.15,1.2) -- edges stay a couple of pixels wide at any distance
  if wantVanMark then vanGlow.set(true,math.clamp(.55+near*.4+fade,0,1),math.clamp(near*.8+fade,0,1),thick)
  else vanGlow.set(true,math.clamp(.9+fade,0,1),math.clamp(.35+near*.5+fade,0,1),thick)end
 else vanGlow.set(false)end

 -- The same dotted line leads to the cart while it is the target, and to the van while the cart is pushed.
 local pathGoal=wantVanPath and goal or(wantCart and cart and cart.PrimaryPart and cart.PrimaryPart.Position)or nil
 local goalKind=pathGoal and(wantVanPath and 'van'or 'cart')
 if goalKind~=lastGoalKind then lastGoalKind=goalKind;pathAt=0;pathPoints=nil end
 if alive and pathGoal and r and(pathGoal-r.Position).Magnitude>10 then
  if not pathBusy and(os.clock()-pathAt>PATH_REFRESH or not pathFrom or(r.Position-pathFrom).Magnitude>8)then
   pathAt=os.clock();pathFrom=r.Position;computePath(r.Position,pathGoal)
  end
  drawDots(fade)
 else hideDots()end
end
