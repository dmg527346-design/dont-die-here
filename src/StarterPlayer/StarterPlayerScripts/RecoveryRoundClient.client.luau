local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local missionPlayer=game:GetService('Players').LocalPlayer
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
local RS=game:GetService('ReplicatedStorage');local Run=game:GetService('RunService');local Players=game:GetService('Players');local Tween=game:GetService('TweenService')
local p=Players.LocalPlayer;local state;repeat state=RS:FindFirstChild('RecoveryRound');if not state then task.wait(.2) end until state;local event=RS:WaitForChild('RecoveryEvent')
local gui=Instance.new('ScreenGui');gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Name='RecoveryQuota';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=false;gui.Parent=p:WaitForChild('PlayerGui')
local panel=Instance.new('Frame');panel.Name='QuotaPanel';panel.AnchorPoint=Vector2.new(.5,0);panel.Position=UDim2.new(.5,0,0,0);panel.Size=UDim2.fromOffset(640,82);panel.BackgroundTransparency=1;panel.BorderSizePixel=0;panel.Parent=gui
local function label(name,pos,size,font,textSize,color,align)
 local x=Instance.new('TextLabel');x.Name=name;x.Position=pos;x.Size=size;x.BackgroundTransparency=1;x.Font=font;x.TextSize=textSize;x.TextColor3=color;x.TextXAlignment=align or Enum.TextXAlignment.Left;x.TextStrokeColor3=Color3.fromRGB(8,12,12);x.TextStrokeTransparency=.65;x.Parent=panel;return x
end
local heading=label('Round',UDim2.fromOffset(0,0),UDim2.new(.22,0,0,28),Enum.Font.GothamMedium,14,Color3.fromRGB(189,202,191))
local amount=label('QuotaAmount',UDim2.new(.22,0,0,0),UDim2.new(.42,0,0,28),Enum.Font.GothamMedium,25,Color3.fromRGB(238,241,227))
local status=label('Status',UDim2.new(.64,0,0,0),UDim2.new(.36,0,0,28),Enum.Font.GothamMedium,13,Color3.fromRGB(197,208,195),Enum.TextXAlignment.Right)
status.TextTruncate=Enum.TextTruncate.AtEnd
local basket=label('CartValue',UDim2.new(0,0,0,128),UDim2.new(1,0,0,18),Enum.Font.Gotham,11,Color3.fromRGB(157,176,164),Enum.TextXAlignment.Right)
heading.AnchorPoint=Vector2.new(0,0);heading.Position=UDim2.fromOffset(0,12);heading.Size=UDim2.fromOffset(110,52);heading.TextXAlignment=Enum.TextXAlignment.Left
heading.FontFace=Font.fromName('FredokaOne',Enum.FontWeight.Medium);heading.TextSize=16;heading.ZIndex=5;heading.TextStrokeTransparency=.15;heading.TextColor3=Color3.fromRGB(242,244,218)
amount.AnchorPoint=Vector2.new(.5,0);amount.Position=UDim2.new(.5,0,0,-4);amount.Size=UDim2.new(.58,0,0,76);amount.TextXAlignment=Enum.TextXAlignment.Center;amount.TextSize=40 -- was 60; the pixel font read too big (2026-10-22)
amount.FontFace=Font.fromName('FredokaOne',Enum.FontWeight.Medium);amount.TextStrokeTransparency=1;amount.ZIndex=3
local outline=Instance.new('UIStroke');outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;outline.Thickness=3.5;outline.Color=Color3.fromRGB(23,32,25);outline.Parent=amount
local depth=amount:Clone();depth.Name='QuotaDepth';depth.Position=amount.Position+UDim2.fromOffset(0,5);depth.TextColor3=Color3.fromRGB(51,72,47);depth.ZIndex=2;depth.Parent=panel
depth.UIStroke.Thickness=4
local sheen=Instance.new('UIGradient');sheen.Rotation=90;sheen.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,240)),ColorSequenceKeypoint.new(.55,Color3.fromRGB(237,244,205)),ColorSequenceKeypoint.new(1,Color3.fromRGB(185,206,158))});sheen.Parent=amount
status.Position=UDim2.new(.79,0,0,12);status.Size=UDim2.new(.21,0,0,52);status.TextSize=16;status.FontFace=heading.FontFace;status.TextStrokeTransparency=.15
-- The panel shrinks on phones; let long states ("RETURN ITEMS · 9:33") wrap and shrink instead of cutting off.
status.TextWrapped=true;status.TextScaled=true;do local fit=Instance.new('UITextSizeConstraint');fit.MaxTextSize=16;fit.MinTextSize=9;fit.Parent=status end
local hudScale=Instance.new('UIScale');hudScale.Parent=panel
-- ObjectiveChip (2026-10-27): a small always-on line under the quota bars while the team searches,
-- "LOOT 2/4  ·  $64 / $100": items banked this level (sold, RecoveryRound.SoldItems, plus the ones in the cart) / items
-- the level needs (banked + what is still missing at this level's average item value), then sold + cart / quota.
-- The average is taken once per level from the loot on the map, so the target only moves when the haul does.
-- It sits inside QuotaPanel: hudScale shrinks it with the panel and the console safe area applies; the panel grows by
-- CHIP_H while it shows, so everything placed under the panel's real bottom edge moves down with it. Hidden once the
-- haul meets the quota (the van card and the path take over).
local PANEL_H,CHIP_H=82,32
local chip=Instance.new('Frame');chip.Name='ObjectiveChip';chip.AnchorPoint=Vector2.new(.5,0);chip.Position=UDim2.new(.5,0,0,PANEL_H+4);chip.Size=UDim2.fromOffset(0,CHIP_H-6);chip.AutomaticSize=Enum.AutomaticSize.X
chip.BackgroundColor3=Color3.fromRGB(24,34,30);chip.BackgroundTransparency=.2;chip.BorderSizePixel=0;chip.Visible=false;chip.Parent=panel
Instance.new('UICorner',chip).CornerRadius=UDim.new(1,0)
do local s=Instance.new('UIStroke');s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Color=Color3.fromRGB(139,159,142);s.Transparency=.45;s.Thickness=1;s.Parent=chip end
do local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,14);pad.PaddingRight=UDim.new(0,14);pad.Parent=chip end
local chipText=Instance.new('TextLabel');chipText.Name='Objective';chipText.BackgroundTransparency=1;chipText.AutomaticSize=Enum.AutomaticSize.X;chipText.Size=UDim2.fromScale(0,1)
chipText.FontFace=Font.fromName('FredokaOne',Enum.FontWeight.Medium);chipText.TextSize=17;chipText.TextColor3=Color3.fromRGB(242,244,218)
chipText.TextStrokeColor3=Color3.fromRGB(8,12,12);chipText.TextStrokeTransparency=.5;chipText.Text='';chipText.Parent=chip
local chipScanAt,chipInCart,chipLevel,chipAvg=0,0,nil,nil
local function scanLoot()
 local m=workspace:FindFirstChild('Mansion');local folder=m and m:FindFirstChild('Interactive')
 local inCart,total,count=0,0,0
 if folder then for _,x in folder:GetChildren()do
  if x:IsA('Model')and x:GetAttribute('ItemId')and not x:GetAttribute('Gear')and x:GetAttribute('CartValue')==nil then
   local v=x:GetAttribute('LootValue')or x:GetAttribute('Value')
   if type(v)=='number'and v>0 then
    total+=v;count+=1
    if x:GetAttribute('CargoStored')then inCart+=1 end
   end
  end
 end end
 chipInCart=inCart
 -- One average per level (a retry rebuilds the map, so the seed changes too): taken once the loot has spawned.
 local level=tostring(state:GetAttribute('Round'))..':'..tostring(state:GetAttribute('MapSeed'))..':'..tostring(state:GetAttribute('QuestGeneration'))
 if level~=chipLevel then chipLevel=level;chipAvg=nil end
 if not chipAvg and count>=3 then chipAvg=total/count end
end
local function drawChip(phase,quota,sold)
 local haul=sold+(state:GetAttribute('CartValue')or 0)
 local want=phase=='Searching'and quota>0 and haul<quota
 if want then
  if os.clock()>=chipScanAt then chipScanAt=os.clock()+.5;scanLoot()end
  want=chipAvg~=nil
 end
 if want then
  local banked=(state:GetAttribute('SoldItems')or 0)+chipInCart
  local need=banked+math.max(1,math.ceil((quota-haul)/math.max(1,chipAvg)))
  chipText.Text=('LOOT %d/%d  ·  $%d / $%d'):format(banked,need,math.floor(haul+.5),quota)
 end
 if chip.Visible~=want then chip.Visible=want;panel.Size=UDim2.fromOffset(640,want and PANEL_H+CHIP_H or PANEL_H)end
end
local bars={}
for index=1,5 do
 local height=10
 local shell=Instance.new('Frame');shell.Name='QuotaBar'..index;shell.AnchorPoint=Vector2.new(0,1);shell.Position=UDim2.new((index-1)/5,0,0,80);shell.Size=UDim2.new(.2,-8,0,height);shell.BackgroundColor3=Color3.fromRGB(24,34,30);shell.BackgroundTransparency=.2;shell.BorderSizePixel=0;shell.ClipsDescendants=true;shell.Parent=panel
 Instance.new('UICorner',shell).CornerRadius=UDim.new(0,4)
 local outline=Instance.new('UIStroke');outline.Color=Color3.fromRGB(139,159,142);outline.Transparency=.45;outline.Thickness=1;outline.Parent=shell
 local fill=Instance.new('Frame');fill.Name='Fill';fill.Size=UDim2.fromScale(0,1);fill.BackgroundColor3=Color3.fromRGB(171,201,157);fill.BorderSizePixel=0;fill.Parent=shell
 Instance.new('UICorner',fill).CornerRadius=UDim.new(0,4)
 local gradient=Instance.new('UIGradient');gradient.Color=ColorSequence.new(Color3.fromRGB(141,178,135),Color3.fromRGB(205,224,183));gradient.Parent=fill
 bars[index]={fill=fill,outline=outline}
end
local progress=Instance.new('NumberValue');progress.Value=0;progress.Parent=panel
local function drawProgress()
 for index,bar in ipairs(bars) do local fraction=math.clamp(progress.Value*5-(index-1),0,1);bar.fill.Visible=fraction>0;bar.fill.Size=UDim2.fromScale(fraction,1);bar.outline.Transparency=fraction>=1 and .15 or .45 end
end
progress.Changed:Connect(drawProgress);drawProgress()
-- First-find payoff (CursedBatchEffects.ItemBatch6 writes CartCheerAt when a first-find item lands in the cart): the
-- quota bars flash gold three times, the same moment the cart shoots confetti. No text, readable on every device.
local CHEER_GOLD=Color3.fromRGB(255,214,70)
state:GetAttributeChangedSignal('CartCheerAt'):Connect(function()
 local at=state:GetAttribute('CartCheerAt');if type(at)~='number'or workspace:GetServerTimeNow()-at>3 then return end
 for _,bar in ipairs(bars)do
  bar.outline.Color=CHEER_GOLD;bar.outline.Thickness=2.5;bar.outline.Transparency=0
  local flash=Tween:Create(bar.outline,TweenInfo.new(.25,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,2,true),{Transparency=.7})
  flash.Completed:Connect(function()bar.outline.Color=Color3.fromRGB(139,159,142);bar.outline.Thickness=1;drawProgress()end)
  flash:Play()
 end
end)
local progressTween;local oldFraction=-1
local shownSold=Instance.new('NumberValue');shownSold.Value=state:GetAttribute('Sold')or 0 -- counts up after a sale
local function update()
 local phase=state:GetAttribute('Phase');local quota=math.max(1,state:GetAttribute('Quota') or 1);local sold=state:GetAttribute('Sold') or 0;local seconds=state:GetAttribute('ExtractionSeconds');local sale=state:GetAttribute('SaleEnds')
 -- No quota until the server has a real one for a deployed level: before the first level ('Loading') or after a run
 -- ('Ended') Quota is 0 or stale, which showed '$0 / $1' for a moment on entry and on restarts.
 local live=(phase=='Deploying'or phase=='Searching'or phase=='Selling'or phase=='Returning'or phase=='Won'or phase=='Failed')and(state:GetAttribute('Quota')or 0)>0
 panel.Visible=live;if not live then drawChip(nil,1,0);return end
 heading.Text='LEVEL '..(state:GetAttribute('Round')or 1);basket.Text='';basket.Visible=false;amount.Text=('$%d  /  $%d'):format(math.floor(math.min(shownSold.Value,sold)+.5),quota)
 status.Text=phase=='Won' and 'LEVEL CLEARED' or phase=='Failed' and 'RESTARTING LEVEL 1' or seconds and ('LEAVING IN %.1fs'):format(seconds) or phase=='Returning' and ('RETURN · %d/%d IN VAN'):format(state:GetAttribute('InVan') or 0,state:GetAttribute('Alive') or 0) or sale and ('SELLING · %.1fs'):format(math.max(0,sale-workspace:GetServerTimeNow())) or ('RETURN ITEMS · %d:%02d'):format(math.floor(math.max(0,(state:GetAttribute('LevelEnds')or workspace:GetServerTimeNow())-workspace:GetServerTimeNow())/60),math.floor(math.max(0,(state:GetAttribute('LevelEnds')or workspace:GetServerTimeNow())-workspace:GetServerTimeNow())%60))
 status.Text=(status.Text:gsub(' · ','\n')) -- break deliberately, not mid-word, in the narrow status column
 depth.Text=amount.Text
 drawChip(phase,quota,sold)
 local fraction=math.clamp(math.min(shownSold.Value,sold)/quota,0,1);if fraction~=oldFraction then oldFraction=fraction;if progressTween then progressTween:Cancel() end;progressTween=Tween:Create(progress,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Value=fraction});progressTween:Play() end
end
local aimTimer,displayTimer=0,0
Run.RenderStepped:Connect(function(dt)
 gui.Enabled=p:GetAttribute('MissionActive')==true and p:GetAttribute('IntroPlaying')~=true;if not gui.Enabled then return end -- hidden while the monster intro plays
 aimTimer+=dt;displayTimer+=dt;if displayTimer>.1 then displayTimer=0;update() end
 -- Aim is only sent while pushing (the server ignores everyone else's): 10 Hz keeps the hold lease alive when this client
 -- drives the cart itself, 60 Hz in the short moment before the server hands it over.
 local pushing=false;local m=workspace:FindFirstChild('Mansion');local interactive=m and m:FindFirstChild('Interactive');local c=interactive and interactive:FindFirstChild('RecoveryCart')
 pushing=c~=nil and c:GetAttribute('HeldBy')==p.UserId
 if pushing and aimTimer>(c:GetAttribute('ClientDriven')==p.UserId and .1 or 1/60) then aimTimer=0;local cam=workspace.CurrentCamera;if cam then event:FireServer('aim',cam.CFrame) end end
end)

-- Cart pushing runs on the pusher's own screen. While RecoveryRoundServer has handed this client the cart (ClientDriven),
-- the hold target is set here every frame right before physics, so the cart answers immediately. Same rules as the
-- server's push code: 9.3 studs ahead on the ground, eased pick-up, and lined up with the level exit doorway near it.
local CART_PUSH_DISTANCE,CART_ACQUIRE_SECONDS=9.3,.3
-- Lead: the hold target is set slightly ahead along its own motion, which cancels most of the spring's follow delay.
local CART_LEAD_SECONDS,CART_LEAD_MAX=.08,3
local CART_DOOR_ZONE,CART_DOOR_FULL,CART_DOOR_HALF=14,6,2.8
-- Smoothing (owner 2026-10-25: pushing felt jerky, like lag): the aim follows the camera and the height follows the
-- floor through an ease, the way a held item eases to the hand, so a twitch of the mouse or a floor seam no longer
-- whips the cart. Per second; higher = snappier.
local CART_AIM_TIME,CART_HEIGHT_TIME,CART_FOLLOW_TIME=.22,.12,.07 -- seconds to (almost) catch up; lower = snappier
local CART_TURN_LEAD,CART_TURN_LEAD_MAX=.08,math.rad(35) -- s added to the spring's delay for the pull's own lag; cap
-- Spring-damper (smooth damp): shrugs off quick twitches far better than a plain ease for the same delay, and
-- speeds up and settles without a lurch. Works on numbers and Vector3s; vel is kept per value between frames.
local function smoothDamp(current,target,vel,time,dt)
 local omega=2/time;local x=omega*dt;local k=1/(1+x+.48*x*x+.235*x*x*x)
 local change=current-target;local temp=(vel+change*omega)*dt
 return target+(change+temp)*k,(vel-temp*omega)*k
end
local cartDrive -- {cart, started, position, rotation}
local cartParams=RaycastParams.new();cartParams.FilterType=Enum.RaycastFilterType.Exclude;cartParams.RespectCanCollide=true;cartParams.CollisionGroup='RecoveryCart'
Run.PreSimulation:Connect(function(dt)
 local m=workspace:FindFirstChild('Mansion');local interactive=m and m:FindFirstChild('Interactive');local cart=interactive and interactive:FindFirstChild('RecoveryCart')
 if not cart or not cart.PrimaryPart or cart:GetAttribute('ClientDriven')~=p.UserId then cartDrive=nil;return end
 local hold=cart.PrimaryPart:FindFirstChild('CartHold_Position');local turn=cart.PrimaryPart:FindFirstChild('CartHold_Orientation')
 local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart');local cam=workspace.CurrentCamera
 if not hold or not turn or not r or not cam then return end
 if not cartDrive or cartDrive.cart~=cart then cartDrive={cart=cart,started=os.clock(),position=cart.PrimaryPart.Position,rotation=cart.PrimaryPart.CFrame.Rotation} end
 local look=Vector3.new(cam.CFrame.LookVector.X,0,cam.CFrame.LookVector.Z);if look.Magnitude>.01 then look=look.Unit else look=r.CFrame.LookVector end
 -- Eased aim: the yaw turns toward the camera's by the shortest way round.
 -- Aim (owner 2026-10-25: on the crosshair, but not twitchy): a spring smooths the camera's yaw, which soaks up mouse
 -- twitches; the spring's own turn speed (already smooth) then pushes the aim ahead by the spring's delay plus the
 -- pull's, so in a steady turn the cart sits on the crosshair instead of trailing to one side.
 local camYaw=math.atan2(-look.X,-look.Z)
 if cartDrive.aimYaw then
  local goal=cartDrive.aimYaw+((camYaw-cartDrive.aimYaw+math.pi)%(2*math.pi)-math.pi)
  cartDrive.aimYaw,cartDrive.yawVel=smoothDamp(cartDrive.aimYaw,goal,cartDrive.yawVel or 0,CART_AIM_TIME,dt)
 else cartDrive.aimYaw=camYaw end
 local yaw=cartDrive.aimYaw+math.clamp((cartDrive.yawVel or 0)*(CART_AIM_TIME+CART_TURN_LEAD),-CART_TURN_LEAD_MAX,CART_TURN_LEAD_MAX)
 cartDrive.yaw=yaw;look=Vector3.new(-math.sin(yaw),0,-math.cos(yaw))
 cartParams.FilterDescendantsInstances={cart,p.Character,interactive}
 local target=r.Position+look*CART_PUSH_DISTANCE;local hit=workspace:Raycast(target+Vector3.new(0,5,0),Vector3.new(0,-20,0),cartParams)
 target=Vector3.new(target.X,hit and hit.Position.Y+(cart:GetAttribute('GroundOffset') or 1) or r.Position.Y-1.8,target.Z)
 if cartDrive.height then local y;y,cartDrive.heightVel=smoothDamp(cartDrive.height,target.Y,cartDrive.heightVel or 0,CART_HEIGHT_TIME,dt);target=Vector3.new(target.X,y,target.Z)end
 cartDrive.height=target.Y
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan');local doorZ=van and van:GetAttribute('ExteriorBoundary')
 if doorZ then
  local vanCF=van:GetPivot();local q=vanCF:PointToObjectSpace(target);local door=vanCF:PointToObjectSpace(Vector3.new(vanCF.X,vanCF.Y,doorZ)).Z
  if math.abs(q.Z-door)<CART_DOOR_ZONE and math.abs(q.X)<9 then local w=math.clamp((CART_DOOR_ZONE-math.abs(q.Z-door))/(CART_DOOR_ZONE-CART_DOOR_FULL),0,1);w=w*w*(3-2*w);target=vanCF:PointToWorldSpace(Vector3.new(q.X+(math.clamp(q.X,-CART_DOOR_HALF,CART_DOOR_HALF)-q.X)*w,q.Y,q.Z)) end
 end
 local rotation=CFrame.lookAt(Vector3.zero,look).Rotation*CFrame.Angles(0,math.pi,0)
 local t=math.clamp((os.clock()-cartDrive.started)/CART_ACQUIRE_SECONDS,0,1)
 if t<1 then local blend=t*t*(3-2*t);target=cartDrive.position:Lerp(target,blend);rotation=cartDrive.rotation:Lerp(rotation,blend) end
 -- Lead from the pusher's own walking velocity (smooth physics), not from the target's frame-to-frame change, which
 -- multiplied every small wobble about three times.
 local lead=r.AssemblyLinearVelocity*CART_LEAD_SECONDS;lead=Vector3.new(lead.X,0,lead.Z);if lead.Magnitude>CART_LEAD_MAX then lead=lead.Unit*CART_LEAD_MAX end
 -- Final ease, like a held item gliding to the hand: the hold point itself glides to its new spot, so a single odd
 -- frame (a floor probe catching a crate, the doorway centring) never reaches the cart as a jolt.
 local goal=target+lead
 if cartDrive.hold then cartDrive.hold,cartDrive.holdVel=smoothDamp(cartDrive.hold,goal,cartDrive.holdVel or Vector3.zero,CART_FOLLOW_TIME,dt)else cartDrive.hold=goal end
 hold.Position=cartDrive.hold;turn.CFrame=rotation
end)
update()
-- Sale payoff: the counter counts up, a "+$amount" pops in and flies into it, the counter punches, a QUOTA MET line
-- when this sale crossed the quota, and a coin burst from the cart. The cash register sound is GameplaySoundServer's.
local punch=Instance.new('UIScale');punch.Parent=amount
local depthPunch=Instance.new('UIScale');depthPunch.Parent=depth
local lastSold=state:GetAttribute('Sold')or 0
local saleStartSold,saleCrossed=nil,false -- while an item-by-item sale runs (SaleEnds set)
local function coinBurst()
 local m=workspace:FindFirstChild('Mansion');local items=m and m:FindFirstChild('Interactive');local cart=items and items:FindFirstChild('RecoveryCart')
 local at=cart and cart.PrimaryPart and cart.PrimaryPart.Position;if not at then return end
 local host=Instance.new('Part');host.Name='SaleBurst';host.Anchored=true;host.CanCollide=false;host.CanQuery=false;host.CanTouch=false;host.Transparency=1;host.Size=Vector3.new(3,1,4);host.CFrame=CFrame.new(at+Vector3.new(0,1.5,0));host.Parent=workspace
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Rate=0;e.Lifetime=NumberRange.new(.6,1.1);e.Speed=NumberRange.new(10,18);e.SpreadAngle=Vector2.new(35,35);e.Acceleration=Vector3.new(0,-30,0)
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,0)});e.Color=ColorSequence.new(Color3.fromRGB(255,214,90),Color3.fromRGB(150,230,120));e.LightEmission=.6;e.EmissionDirection=Enum.NormalId.Top;e.Parent=host
 e:Emit(45);task.delay(2,function()host:Destroy()end)
end
local function popup(gain,quotaMet)
 local pop=Instance.new('TextLabel');pop.Name='SalePopup';pop.AnchorPoint=Vector2.new(.5,0);pop.Position=UDim2.new(.5,0,0,(panel.AbsoluteSize.Y>0 and panel.AbsoluteSize.Y or 82)+18);pop.Size=UDim2.fromOffset(320,52)
 pop.BackgroundTransparency=1;pop.FontFace=heading.FontFace;pop.TextSize=46;pop.TextColor3=Color3.fromRGB(255,224,120);pop.Text='+$'..gain;pop.ZIndex=10;pop.Parent=gui
 local stroke=Instance.new('UIStroke');stroke.Thickness=3;stroke.Color=Color3.fromRGB(40,30,10);stroke.Parent=pop
 local sc=Instance.new('UIScale');sc.Scale=.4;sc.Parent=pop
 local sub
 if quotaMet then
  sub=pop:Clone();sub.Name='QuotaMet';sub.Text='QUOTA MET!';sub.TextSize=22;sub.TextColor3=Color3.fromRGB(170,240,150);sub.Position=pop.Position+UDim2.fromOffset(0,50);sub.Parent=gui
 end
 Tween:Create(sc,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.1}):Play()
 task.delay(.95,function()
  if not pop.Parent then return end
  local up=TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
  Tween:Create(pop,up,{Position=UDim2.new(.5,0,0,20),TextTransparency=1}):Play();Tween:Create(stroke,up,{Transparency=1}):Play();Tween:Create(sc,up,{Scale=.6}):Play()
  task.delay(.5,function()pop:Destroy()
   punch.Scale=1.18;depthPunch.Scale=1.18
   local back=TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
   Tween:Create(punch,back,{Scale=1}):Play();Tween:Create(depthPunch,back,{Scale=1}):Play()
  end)
 end)
 if sub then task.delay(2.2,function()if sub.Parent then Tween:Create(sub,TweenInfo.new(.5),{TextTransparency=1}):Play();task.delay(.5,function()sub:Destroy()end)end end)end
end
state:GetAttributeChangedSignal('Sold'):Connect(function()
 local now=state:GetAttribute('Sold')or 0
 local quota=state:GetAttribute('Quota')or 0
 if now>lastSold and p:GetAttribute('MissionActive')==true then
  local gain=now-lastSold
  if saleStartSold then
   -- one item sold: the counter ticks up at once with a small punch; the big +$total lands when the sale ends
   if quota>0 and lastSold<quota and now>=quota then saleCrossed=true end
   Tween:Create(shownSold,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Value=now}):Play()
   punch.Scale=1.1;depthPunch.Scale=1.1
   local back=TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
   Tween:Create(punch,back,{Scale=1}):Play();Tween:Create(depthPunch,back,{Scale=1}):Play()
  else
   Tween:Create(shownSold,TweenInfo.new(1.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Value=now}):Play()
   popup(gain,quota>0 and lastSold<quota and now>=quota);coinBurst()
  end
 else shownSold.Value=now end -- a new level or run resets the count instantly
 lastSold=now
end)
shownSold.Changed:Connect(update)
-- Item-by-item sale: the server sells one item at a time (cheapest first) and fires 'saleItem' for each; the item
-- vanishes, a "+$value" pops where it was with a rising tick, the SELLING $X tally and the quota count up, and when
-- the sale ends the big "+$total" (and QUOTA MET) lands with the coin burst. A cancelled sale fades.
local tickSound=Instance.new('Sound');tickSound.SoundId='rbxassetid://106586585181583';tickSound.Volume=.22;tickSound.Parent=gui
local tally=Instance.new('TextLabel');tally.Name='SaleTally';tally.AnchorPoint=Vector2.new(.5,0);tally.Size=UDim2.fromOffset(320,30);tally.BackgroundTransparency=1;tally.FontFace=heading.FontFace;tally.TextSize=24
tally.TextColor3=Color3.fromRGB(255,230,150);tally.TextTransparency=1;tally.Visible=false;tally.ZIndex=9;tally.Parent=gui
do local s=Instance.new('UIStroke');s.Thickness=2.5;s.Color=Color3.fromRGB(40,30,10);s.Parent=tally end
local saleRun,soldAtStart,saleRunning=0,0,0
local function itemPop(m,value,index)
 local root=m.PrimaryPart;if not root then return end
 local bb=Instance.new('BillboardGui');bb.Name='SaleItemPop';bb.Adornee=root;bb.AlwaysOnTop=true;bb.Size=UDim2.fromOffset(140,40);bb.StudsOffsetWorldSpace=Vector3.new(0,1.6,0);bb.LightInfluence=0;bb.MaxDistance=120;bb.Parent=gui
 local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.FontFace=heading.FontFace;t.TextScaled=true;t.TextColor3=Color3.fromRGB(255,224,120);t.Text='+$'..value;t.Parent=bb
 local s=Instance.new('UIStroke');s.Thickness=2;s.Color=Color3.fromRGB(40,30,10);s.Parent=t
 local sc=Instance.new('UIScale');sc.Scale=.3;sc.Parent=t
 Tween:Create(sc,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 Tween:Create(bb,TweenInfo.new(1.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{StudsOffsetWorldSpace=Vector3.new(0,4.2,0)}):Play()
 task.delay(.7,function()Tween:Create(t,TweenInfo.new(.4),{TextTransparency=1}):Play();Tween:Create(s,TweenInfo.new(.4),{Transparency=1}):Play()end)
 task.delay(1.15,function()bb:Destroy()end)
 tickSound.PlaybackSpeed=math.min(1.9,1+index*.07);tickSound.TimePosition=0;tickSound:Play()
end
state:GetAttributeChangedSignal('SaleEnds'):Connect(function()
 local ends=state:GetAttribute('SaleEnds')
 saleRun+=1;local run=saleRun
 if not ends then
  local gain=(state:GetAttribute('Sold')or 0)-soldAtStart
  if saleStartSold and gain>0 and p:GetAttribute('MissionActive')==true then popup(gain,saleCrossed);coinBurst() end
  saleStartSold=nil;saleCrossed=false
  -- the sale finished or was cancelled: a finished sale hands over to the big popup, a cancelled one says so
  task.delay(.15,function()
   if run~=saleRun then return end
   if tally.Visible and (state:GetAttribute('Sold')or 0)<=soldAtStart then tally.Text='SALE CANCELLED';tally.TextColor3=Color3.fromRGB(230,140,120)end
   Tween:Create(tally,TweenInfo.new(.4),{TextTransparency=1}):Play();task.delay(.45,function()if run==saleRun then tally.Visible=false end end)
  end)
  return
 end
 if p:GetAttribute('MissionActive')~=true then return end
 soldAtStart=state:GetAttribute('Sold')or 0;saleStartSold=soldAtStart;saleCrossed=false;saleRunning=0
 tally.Position=UDim2.new(.5,0,0,(panel.AbsoluteSize.Y>0 and panel.AbsoluteSize.Y or 82)+70);tally.TextColor3=Color3.fromRGB(255,230,150);tally.Text='SELLING  $0';tally.Visible=true
 Tween:Create(tally,TweenInfo.new(.2),{TextTransparency=0}):Play()
end)
event.OnClientEvent:Connect(function(action,at,value,index)
 if action~='saleItem' or typeof(at)~='Vector3' or type(value)~='number' or p:GetAttribute('MissionActive')~=true then return end
 local v=math.floor(value);saleRunning+=v;tally.Text='SELLING  $'..saleRunning
 -- the item is already gone: pop over the spot where it sat
 local host=Instance.new('Part');host.Name='SaleItemSpot';host.Anchored=true;host.CanCollide=false;host.CanQuery=false;host.CanTouch=false;host.Transparency=1;host.Size=Vector3.new(.2,.2,.2);host.CFrame=CFrame.new(at);host.Parent=workspace
 local fake={PrimaryPart=host}
 itemPop(fake,v,type(index)=='number' and index or 1)
 task.delay(1.3,function()host:Destroy()end)
end)
local function faceSpawn(c)
 -- No ladders in this game: the Climbing state was dragging fresh spawns through the van floor.
 task.spawn(function()local h=c:WaitForChild('Humanoid',10);if h then h:SetStateEnabled(Enum.HumanoidStateType.Climbing,false);if h:GetState()==Enum.HumanoidStateType.Climbing then h:ChangeState(Enum.HumanoidStateType.Running)end end end)
 local revision=-1
 local function apply()
  local nextRevision=c:GetAttribute('RecoverySpawnRevision');local facing=c:GetAttribute('RecoveryFacing')
  if not nextRevision or nextRevision==revision or not facing or p.Character~=c then return end
  revision=nextRevision
  local placement=c:GetAttribute('RecoverySpawnCFrame')
  -- StreamingEnabled: the van floor must exist on this client before physics is handed over,
  -- otherwise the character drops through the unloaded floor and is flung across the map.
  if placement then
   pcall(function()p:RequestStreamAroundAsync(placement.Position,8)end)
   local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={c};params.RespectCanCollide=true
   local waitUntil=os.clock()+8
   while os.clock()<waitUntil and p.Character==c and c:GetAttribute('RecoverySpawnRevision')==nextRevision do
    if workspace:Raycast(placement.Position+Vector3.new(0,2,0),Vector3.new(0,-14,0),params)then break end
    task.wait(.1)
   end
   if p.Character~=c or c:GetAttribute('RecoverySpawnRevision')~=nextRevision then return end
   c:PivotTo(placement);for _,part in ipairs(c:GetDescendants()) do if part:IsA('BasePart') then part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end end
  end
  event:FireServer('spawnReady',nextRevision)
  local cam=workspace.CurrentCamera;local head=c:FindFirstChild('Head')
  if cam and head then cam.CFrame=CFrame.lookAt(head.Position,head.Position+facing);cam.Focus=CFrame.new(head.Position+facing*10) end
 end
 c:GetAttributeChangedSignal('RecoverySpawnRevision'):Connect(apply);apply()
end
p.CharacterAdded:Connect(faceSpawn);if p.Character then faceSpawn(p.Character) end

local function resize()
 local cam=workspace.CurrentCamera;if not cam then return end
 hudScale.Scale=math.min(1,(cam.ViewportSize.X-32)/640,cam.ViewportSize.Y<500 and .65 or 1)
 panel.Size=UDim2.fromOffset(640,chip.Visible and PANEL_H+CHIP_H or PANEL_H) -- ObjectiveChip adds CHIP_H while it shows
end
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(resize);resize()

-- Spectating belongs to this mission HUD and ends only when the server revives us.
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local GuiService=game:GetService('GuiService')
local SPECTATOR_BAR_HEIGHT=138
local SPECTATOR_ACTION_Y=84
local SPECTATOR_BUTTON_HEIGHT=44
local SPECTATOR_LEAVE_WIDTH=102
local SPECTATOR_ACTION_GAP=8
local SPECTATOR_EDGE=10
local spectator=Instance.new('ScreenGui');spectator.Name='RecoverySpectator';spectator.ResetOnSpawn=false;spectator.DisplayOrder=980;spectator.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;spectator.Parent=p.PlayerGui;spectator.Enabled=false
local bar=Instance.new('Frame');bar.Name='Controls';bar.AnchorPoint=Vector2.new(.5,1);bar.Position=UDim2.new(.5,0,1,-22);bar.Size=UDim2.new(.9,0,0,SPECTATOR_BAR_HEIGHT);bar.BackgroundColor3=Color3.fromRGB(22,42,43);bar.BorderSizePixel=0;bar.Parent=spectator
local max=Instance.new('UISizeConstraint');max.MaxSize=Vector2.new(460,SPECTATOR_BAR_HEIGHT);max.Parent=bar
Instance.new('UICorner',bar).CornerRadius=UDim.new(0,14);local outline=Instance.new('UIStroke');outline.Thickness=3;outline.Color=Color3.fromRGB(8,18,22);outline.Parent=bar
local nameLabel=Instance.new('TextLabel');nameLabel.Name='Watching';nameLabel.Position=UDim2.new(0,52,0,8);nameLabel.Size=UDim2.new(1,-104,0,32);nameLabel.BackgroundTransparency=1;nameLabel.Font=Enum.Font.FredokaOne;nameLabel.TextSize=18;nameLabel.TextColor3=Color3.fromRGB(244,236,210);nameLabel.TextWrapped=true;nameLabel.Parent=bar
local help=nameLabel:Clone();help.Name='Help';help.Position=UDim2.new(0,10,0,44);help.Size=UDim2.new(1,-20,0,34);help.TextSize=15;help.TextWrapped=true;help.Text='You will revive when your team clears the level.';help.Parent=bar
local targetId;local targets={};local watching=false;local savedMode;local savedZoomMin,savedZoomMax;local refreshAt=0
local function valid(q)
 local h=q.Character and q.Character:FindFirstChildOfClass('Humanoid')
 return q~=p and q:GetAttribute('MissionActive')==true and q:GetAttribute('RoundDead')~=true and h and h.Health>0 and q.Character:FindFirstChild('HumanoidRootPart')
end
local function refreshTargets()
 table.clear(targets)
 for _,q in Players:GetPlayers()do if valid(q)then table.insert(targets,q)end end
 table.sort(targets,function(a,b)return a.UserId<b.UserId end)
 local found=false;for _,q in targets do if q.UserId==targetId then found=true end end
 if not found then targetId=targets[1]and targets[1].UserId end
end
local function cycle(direction)
 refreshTargets();if #targets==0 then return end
 local index=1;for i,q in targets do if q.UserId==targetId then index=i end end
 targetId=targets[(index-1+direction)%#targets+1].UserId
end
local function arrow(name,value,position,direction)
 local b=Instance.new('TextButton');b.Name=name;b.Text=value;b.Position=position;b.Size=UDim2.fromOffset(38,36);b.BackgroundColor3=Color3.fromRGB(167,202,127);b.TextColor3=Color3.fromRGB(8,18,22);b.Font=Enum.Font.FredokaOne;b.TextSize=22;b.BorderSizePixel=0;b.Parent=bar;Instance.new('UICorner',b).CornerRadius=UDim.new(0,10);b.Activated:Connect(function()cycle(direction)end);return b
end
local previous=arrow('Previous','<',UDim2.fromOffset(8,8),-1)
local nextButton=arrow('Next','>',UDim2.new(1,-46,0,8),1)

local reviveRemote=RS:WaitForChild('ReviveEvent')
local reviveButton=Instance.new('TextButton');reviveButton.Name='Revive';reviveButton.Size=UDim2.new(1,-(SPECTATOR_EDGE*2+SPECTATOR_LEAVE_WIDTH+SPECTATOR_ACTION_GAP),0,SPECTATOR_BUTTON_HEIGHT);reviveButton.Position=UDim2.fromOffset(SPECTATOR_EDGE,SPECTATOR_ACTION_Y);reviveButton.Font=Enum.Font.FredokaOne;reviveButton.TextSize=14;reviveButton.TextColor3=Color3.fromRGB(8,18,22);reviveButton.BackgroundColor3=Color3.fromRGB(167,202,127);reviveButton.BorderSizePixel=0;reviveButton.Parent=bar;Instance.new('UICorner',reviveButton).CornerRadius=UDim.new(0,10)
local leaveButton=Instance.new('TextButton');leaveButton.Name='Leave';leaveButton.AnchorPoint=Vector2.new(1,0);leaveButton.Position=UDim2.new(1,-SPECTATOR_EDGE,0,SPECTATOR_ACTION_Y);leaveButton.Size=UDim2.fromOffset(SPECTATOR_LEAVE_WIDTH,SPECTATOR_BUTTON_HEIGHT);leaveButton.Font=Enum.Font.FredokaOne;leaveButton.TextSize=14;leaveButton.Text='LEAVE';leaveButton.TextColor3=Color3.fromRGB(255,240,218);leaveButton.BackgroundColor3=Color3.fromRGB(145,58,42);leaveButton.BorderSizePixel=0;leaveButton.Selectable=true;leaveButton.Modal=true;leaveButton.Parent=bar;Instance.new('UICorner',leaveButton).CornerRadius=UDim.new(0,10)
reviveButton.TextScaled=true;reviveButton.Selectable=true
local reviveTextBounds=Instance.new('UITextSizeConstraint');reviveTextBounds.MinTextSize=10;reviveTextBounds.MaxTextSize=14;reviveTextBounds.Parent=reviveButton
reviveButton.NextSelectionRight=leaveButton;leaveButton.NextSelectionLeft=reviveButton
-- Controller: the same dark round Y badge as the lobby PLAY button (MainMenuClient PadKey), on the right of the button.
local padY=Instance.new('TextLabel');padY.Name='PadY';padY.AnchorPoint=Vector2.new(0,.5);padY.Position=UDim2.fromScale(.5,.5);padY.Size=UDim2.fromOffset(30,30);padY.BackgroundColor3=Color3.fromRGB(8,18,22);padY.TextColor3=Color3.fromRGB(255,214,90);padY.Font=Enum.Font.FredokaOne;padY.TextSize=18;padY.Text='Y';padY.Visible=false;padY.ZIndex=reviveButton.ZIndex+1;padY.Parent=reviveButton
Instance.new('UICorner',padY).CornerRadius=UDim.new(1,0)
local padYNudge=Instance.new('UIPadding');padYNudge.PaddingRight=UDim.new(0,2);padYNudge.Parent=padY -- FredokaOne's Y sits a hair right of centre
-- PlayStation pads have a triangle where Xbox has Y: same badge, gold outline triangle (same as the lobby PLAY badge).
local function padGlyph(label,nudge)
 if InputHints.Glyph(label,'ButtonY')then return end -- PlayStation: the real triangle button art
 local ok,name=pcall(function()return UIS:GetStringForKeyCode(Enum.KeyCode.ButtonY)end)
 local ps=ok and name=='ButtonTriangle'
 label.Text=ps and utf8.char(0x25B3)or'Y';label.Font=ps and Enum.Font.BuilderSansBold or Enum.Font.FredokaOne;label.TextSize=ps and 20 or 18;nudge.PaddingRight=UDim.new(0,ps and 0 or 2)
 -- triangle: dark frog green and raised a little; Y: gold
 label.TextColor3=ps and Color3.fromRGB(58,110,48)or Color3.fromRGB(255,214,90);nudge.PaddingBottom=UDim.new(0,ps and 3 or 0)
end
local revivePadding=Instance.new('UIPadding');revivePadding.Parent=reviveButton
local leaveConfirm=Instance.new('Frame');leaveConfirm.Name='LeaveConfirm';leaveConfirm.Size=UDim2.fromScale(1,1);leaveConfirm.BackgroundColor3=Color3.fromRGB(8,12,12);leaveConfirm.BackgroundTransparency=.35;leaveConfirm.BorderSizePixel=0;leaveConfirm.Visible=false;leaveConfirm.Active=true;leaveConfirm.ZIndex=10;leaveConfirm.Parent=spectator
local leaveCard=Instance.new('Frame');leaveCard.Name='Card';leaveCard.AnchorPoint=Vector2.new(.5,.5);leaveCard.Position=UDim2.fromScale(.5,.5);leaveCard.Size=UDim2.new(.9,0,0,194);leaveCard.BackgroundColor3=Color3.fromRGB(22,42,43);leaveCard.BorderSizePixel=0;leaveCard.ZIndex=11;leaveCard.Parent=leaveConfirm;Instance.new('UICorner',leaveCard).CornerRadius=UDim.new(0,14)
-- Phones: the spectator bar and the leave confirmation card are 20% smaller (35% made the text unreadable), in the same spot (scaled about their anchors).
local function phoneScale(target)
 local sc=Instance.new('UIScale');sc.Name='PhoneScale';sc.Parent=target
 local function apply()sc.Scale=InputHints.Get()=='touch'and .8 or 1 end
 apply();if InputHints.Changed then InputHints.Changed:Connect(apply)end
end
phoneScale(bar);phoneScale(leaveCard)
local leaveMax=Instance.new('UISizeConstraint');leaveMax.MaxSize=Vector2.new(380,194);leaveMax.Parent=leaveCard
local leaveQuestion=Instance.new('TextLabel');leaveQuestion.Name='Question';leaveQuestion.Position=UDim2.fromOffset(16,14);leaveQuestion.Size=UDim2.new(1,-32,0,62);leaveQuestion.BackgroundTransparency=1;leaveQuestion.Font=Enum.Font.FredokaOne;leaveQuestion.TextSize=21;leaveQuestion.TextColor3=Color3.fromRGB(244,236,210);leaveQuestion.TextWrapped=true;leaveQuestion.Text='Are you sure you want to leave?';leaveQuestion.ZIndex=12;leaveQuestion.Parent=leaveCard
local leaveStatus=leaveQuestion:Clone();leaveStatus.Name='Status';leaveStatus.Position=UDim2.fromOffset(16,78);leaveStatus.Size=UDim2.new(1,-32,0,44);leaveStatus.TextSize=13;leaveStatus.Text='Return to the lobby and leave this run.';leaveStatus.Parent=leaveCard
local function leaveChoice(name,text,x,color)
 local button=Instance.new('TextButton');button.Name=name;button.Text=text;button.Position=UDim2.new(x,12,1,-60);button.Size=UDim2.new(.5,-24,0,44);button.BackgroundColor3=color;button.TextColor3=Color3.fromRGB(255,240,218);button.Font=Enum.Font.FredokaOne;button.TextSize=16;button.BorderSizePixel=0;button.Selectable=true;button.ZIndex=12;button.Parent=leaveCard;Instance.new('UICorner',button).CornerRadius=UDim.new(0,10);return button
end
local stayButton=leaveChoice('Cancel','STAY',0,Color3.fromRGB(57,105,78));stayButton.Modal=true
local confirmLeaveButton=leaveChoice('Confirm','LEAVE',.5,Color3.fromRGB(145,58,42))
stayButton.NextSelectionRight=confirmLeaveButton;confirmLeaveButton.NextSelectionLeft=stayButton
local leavePending=false;local leaveAttempt=0;local previousSelection;local reviveMessage
local function closeLeave()
 leaveConfirm.Visible=false
 if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(leaveConfirm)then
  GuiService.SelectedObject=previousSelection and previousSelection.Parent and previousSelection.Visible and previousSelection or (watching and leaveButton or nil)
 end
 previousSelection=nil
end
local function openLeave()
 if not watching or leavePending then return false end
 previousSelection=GuiService.SelectedObject;leaveStatus.Text='Return to the lobby and leave this run.';leaveConfirm.Visible=true;GuiService.SelectedObject=stayButton;return true
end
local function cancelLeave()
 if leavePending then return false end
 closeLeave();return true
end
local function confirmLeave()
 if not watching or not leaveConfirm.Visible or leavePending or p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')~=true then return false end
 leavePending=true;leaveAttempt+=1;local attempt=leaveAttempt;stayButton.Active=false;confirmLeaveButton.Active=false;leaveStatus.Text='Returning to the lobby...';event:FireServer('leaveRun')
 task.delay(35,function()
  if watching and leavePending and leaveAttempt==attempt and p:GetAttribute('LeavingRun')~=true then leavePending=false;stayButton.Active=true;confirmLeaveButton.Active=true;leaveStatus.Text='No connection yet. Please try again.';GuiService.SelectedObject=stayButton end
 end)
 return true
end
leaveButton.Activated:Connect(openLeave);stayButton.Activated:Connect(cancelLeave);confirmLeaveButton.Activated:Connect(confirmLeave)
event.OnClientEvent:Connect(function(action,ok,message)
 if action~='leaveRun' or not watching or not leavePending then return end
 leaveStatus.Text=tostring(message or (ok and 'Returning to the lobby...' or 'Could not leave. Please try again.'))
 if not ok then if reviveMessage then reviveMessage(message)end;leavePending=false;leaveAttempt+=1;stayButton.Active=true;confirmLeaveButton.Active=true;GuiService.SelectedObject=stayButton end
end)
if Run:IsStudio()then
 local testApi=Instance.new('BindableFunction');testApi.Name='SpectatorTestApi';testApi.Parent=script
 testApi.OnInvoke=function(action)
  if action=='open'then return openLeave()elseif action=='cancel'then return cancelLeave()elseif action=='confirm'then return confirmLeave()end
  return false
 end
end
local revivePending=false
local helpExpires=0
reviveMessage=function(message)
 helpExpires=os.clock()+3;help.Text=tostring(message or '');help.TextTransparency=0
end
local function defaultHelp(message)
 local left=helpExpires-os.clock()
 if left>0 then help.TextTransparency=1-math.clamp(left/.35,0,1);return end
 helpExpires=0;help.TextTransparency=0;help.Text=message
end
local function requestRevive()
 if revivePending or leavePending or p:GetAttribute('LeavingRun')==true or leaveConfirm.Visible or p:GetAttribute('Reviving')then return end
 local free=p:GetAttribute('Pass_free_revive')and not p:GetAttribute('FreeReviveUsed')
 if free or(p:GetAttribute('ReviveTokens')or 0)>0 then
  revivePending=true;reviveRemote:FireServer();task.delay(25,function()revivePending=false end)
 else
  -- Tell the server a revive purchase is open so a team wipe waits for it (bounded server side).
  if p:GetAttribute('RoundDead')then reviveRemote:FireServer('checkout')end
  pcall(function()game:GetService('MarketplaceService'):PromptProductPurchase(p,3715702819)end)
 end
end
reviveButton.Activated:Connect(requestRevive)
-- A bought token revives right away; the server grants it first, so wait for ReviveTokens to arrive.
game:GetService('MarketplaceService').PromptProductPurchaseFinished:Connect(function(userId,productId,purchased)
 if userId~=p.UserId or productId~=3715702819 then return end
 if not purchased then reviveRemote:FireServer('checkoutDone');return end
 reviveMessage('Waiting for your revive token...')
 local t=os.clock();while(p:GetAttribute('ReviveTokens')or 0)<=0 and os.clock()-t<20 do task.wait(.25)end
 if p:GetAttribute('RoundDead')and(p:GetAttribute('ReviveTokens')or 0)>0 then requestRevive()end
 reviveRemote:FireServer('checkoutDone')
end)
reviveRemote.OnClientEvent:Connect(function(ok,message)revivePending=false;reviveMessage(message)end)

local savedIcon;local savedMouseBehavior
local function setSpectating(enabled)
 -- A cutscene can hide this HUD while dead, or restore it after revival.
 -- Always remove a stale living-player HUD; only enable on entering spectating.
 if not enabled then spectator.Enabled=false end
 if enabled==watching then return end;watching=enabled
 spectator.Enabled=enabled
 if enabled then
  savedMode=p.CameraMode;savedZoomMin=p.CameraMinZoomDistance;savedZoomMax=p.CameraMaxZoomDistance;savedIcon=UIS.MouseIconEnabled;savedMouseBehavior=UIS.MouseBehavior;p.CameraMode=Enum.CameraMode.Classic
  CAS:BindActionAtPriority('RecoverySpectatorMovement',function()return Enum.ContextActionResult.Sink end,false,4500,unpack(Enum.PlayerActions:GetEnumItems()))
  refreshTargets()
  if InputHints.Get()=='pad'then GuiService.SelectedObject=leaveButton end
 else
  CAS:UnbindAction('RecoverySpectatorMovement');targetId=nil;leavePending=false;leaveAttempt+=1;stayButton.Active=true;confirmLeaveButton.Active=true;closeLeave()
  revivePending=false;helpExpires=0;help.Text='';help.TextTransparency=0
  -- Back to the game's first person, not the mode saved on entry: the lobby menu (Classic) can come and go while
  -- spectating, and restoring a saved Classic left the next mission in third person. The lobby re-forces Classic itself.
  p.CameraMode=Enum.CameraMode.LockFirstPerson
  if savedZoomMin then p.CameraMinZoomDistance=savedZoomMin;p.CameraMaxZoomDistance=savedZoomMax end
  local camera=workspace.CurrentCamera;local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
  if camera and h and h.Health>0 then camera.CameraSubject=h;camera.CameraType=Enum.CameraType.Custom end
  -- spectating freed the mouse every frame; give first person its previous mouse icon setting back
  if savedIcon~=nil then UIS.MouseIconEnabled=savedIcon end
  if savedMouseBehavior~=nil then UIS.MouseBehavior=savedMouseBehavior end
  if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(spectator)then GuiService.SelectedObject=nil end
 end
end
UIS.InputBegan:Connect(function(i,processed)
 if not watching or UIS:GetFocusedTextBox()then return end
 if leaveConfirm.Visible then
  if i.KeyCode==Enum.KeyCode.Escape or i.KeyCode==Enum.KeyCode.ButtonB then cancelLeave()end
  return
 end
 if (i.KeyCode==Enum.KeyCode.R and not processed)or i.KeyCode==Enum.KeyCode.ButtonY then requestRevive()
 elseif i.KeyCode==Enum.KeyCode.ButtonL1 or(not processed and i.KeyCode==Enum.KeyCode.Left)then cycle(-1)
 elseif i.KeyCode==Enum.KeyCode.ButtonR1 or(not processed and i.KeyCode==Enum.KeyCode.Right)then cycle(1)end
end)
local spectateSince=nil
Run:BindToRenderStep('RecoverySpectatorCamera',Enum.RenderPriority.Last.Value+1,function()
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 local dead=p:GetAttribute('RoundDead')==true or(h and h.Health<=0)
 -- Not during a clear or the next-level rebuild: characters reload then, which used to flash 'NO SURVIVORS'.
 local roundPhase=state:GetAttribute('Phase')
 -- Mission start / character swaps can look 'dead' for a frame or two (MissionActive is set before the round resets
 -- RoundDead and enters Deploying), which flashed NO SURVIVORS. Only spectate once dead has held for 0.75 s.
 -- Only real play phases: at mission start the phase is 'Loading' while RoundDead doubles as the deploy flag,
 -- which showed the spectator screen ('you will revive...') before the player had even spawned.
 local playPhase=roundPhase=='Searching' or roundPhase=='Selling' or roundPhase=='Returning' or roundPhase=='Failed'
 local deploying=p.Character~=nil and p.Character:GetAttribute('RecoverySpawnReady')==false and(h==nil or h.Health>0)
 local wantSpectate=p:GetAttribute('MissionActive')==true and dead==true and playPhase and not deploying
 if wantSpectate then spectateSince=spectateSince or os.clock() else spectateSince=nil end
 setSpectating(spectateSince~=nil and os.clock()-spectateSince>=.75)
 if not watching then return end
 local free=p:GetAttribute('Pass_free_revive')and not p:GetAttribute('FreeReviveUsed')
 local tokens=p:GetAttribute('ReviveTokens')or 0
 local active=state:GetAttribute('Phase')
 local device=InputHints.Get();local padIcon=device=='pad'
 local reviveKey=padIcon and ''or device=='pad'and 'Y'or device=='touch'and ''or 'R'
 local busy=revivePending or p:GetAttribute('Reviving')
 local function keyed(text)return reviveKey~=''and(text..' · '..reviveKey)or text end
 reviveButton.Text=busy and'REVIVING…'or free and keyed('FREE REVIVE (THIS LEVEL)')or tokens>0 and keyed('USE A REVIVE ('..tokens..' LEFT)')or'BUY 1 REVIVE TOKEN'
 -- text + badge sit together as one centred group: the padding moves the text left by half the badge, the badge follows the text
 padY.Visible=padIcon and not busy;revivePadding.PaddingRight=UDim.new(0,padY.Visible and 38 or 0)
 if padY.Visible then padGlyph(padY,padYNudge);padY.Position=UDim2.new(.5,math.floor(reviveButton.TextBounds.X/2)+8,.5,0) end
 reviveButton.Visible=active~='Won'and active~='Deploying'and(active~='Failed'or state:GetAttribute('WipeRevivable')==true) -- a wipe can still be undone during the monster cutscene
 if os.clock()>refreshAt then refreshAt=os.clock()+.2;refreshTargets()end
 local camera=workspace.CurrentCamera;if not camera then return end
 local target=targetId and Players:GetPlayerByUserId(targetId)
 if target and valid(target)then
  local r=target.Character.HumanoidRootPart;local head=target.Character:FindFirstChild('Head');local focus=head and head.Position or r.Position+Vector3.new(0,2,0)
  local desired=focus-r.CFrame.LookVector*8+Vector3.new(0,3,0)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={target.Character,p.Character};params.RespectCanCollide=true
  local hit=workspace:Raycast(focus,desired-focus,params);if hit then desired=hit.Position+(focus-desired).Unit*.45 end
  camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=CFrame.lookAt(desired,focus);camera.Focus=CFrame.new(focus)
  nameLabel.Text='SPECTATING '..target.DisplayName
  defaultHelp('Clear the level to revive · '..(device=='pad'and InputHints.PadText('LB / RB')or device=='touch'and 'Tap < / >'or 'Left / Right'))
 else
  local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
  if van then local focus=van:GetPivot().Position;camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=CFrame.lookAt(focus+Vector3.new(14,10,18),focus);camera.Focus=CFrame.new(focus)end
  local finish=state:GetAttribute('TransitionEnds');local seconds=finish and math.max(0,math.ceil(finish-workspace:GetServerTimeNow()))or 0
  nameLabel.Text='NO SURVIVORS';if state:GetAttribute('WipeRevivable')then defaultHelp('Revive now'..(reviveKey~=''and' ('..reviveKey..')'or'')..' or the run is lost'..(seconds>0 and ' · '..seconds..'s'or '')) else defaultHelp((state:GetAttribute('FailureReason')=='TimeExpired'and 'Time expired · moving to a new map'or 'Restarting at level 1')..(seconds>0 and ' in '..seconds..'s'or '...')) end
 end
 previous.Visible=#targets>1;nextButton.Visible=#targets>1
 UIS.MouseBehavior=Enum.MouseBehavior.Default;UIS.MouseIconEnabled=true
end)

-- RunawayCart (WorldB 2026-10-27; RecoveryRoundServer Haunt): while the cart's HauntedUntil is ahead, every player sees the
-- cart glow pale cyan where it is in sight (pulsing Highlight, not through walls) and a banner with the device's grab hint; afterwards a 3 s result line.
do
 local CYAN=Color3.fromRGB(170,235,255)
 local banner=Instance.new('TextLabel');banner.Name='RunawayCartBanner';banner.AnchorPoint=Vector2.new(.5,0);banner.Position=UDim2.new(.5,0,0,104)
 banner.Size=UDim2.new(.92,0,0,34);banner.BackgroundTransparency=1;banner.Font=Enum.Font.FredokaOne
 banner.TextScaled=true;banner.TextColor3=CYAN;banner.Visible=false;banner.ZIndex=6;banner.Parent=gui
 local cap=Instance.new('UISizeConstraint');cap.MaxSize=Vector2.new(560,34);cap.Parent=banner
 local stroke=Instance.new('UIStroke');stroke.Thickness=2.5;stroke.Color=Color3.fromRGB(16,28,34);stroke.Parent=banner
 local glow,lastCart,shownResult,resultAt=nil,nil,nil,-math.huge
 local function grabHint()
  local d=InputHints.Get()
  return d=='touch'and'TAP GRAB ON IT'or d=='pad'and'HOLD R2 ON IT'or'HOLD LEFT CLICK ON IT'
 end
 task.spawn(function()
  while true do
   local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
   local cart=interactive and interactive:FindFirstChild('RecoveryCart')
   if cart~=lastCart then lastCart=cart;shownResult=nil;resultAt=-math.huge end
   local untilAt=cart and cart:GetAttribute('HauntedUntil')
   local haunted=type(untilAt)=='number'and untilAt>workspace:GetServerTimeNow()and p:GetAttribute('MissionActive')==true
   if not glow or not glow.Parent then
    glow=Instance.new('Highlight');glow.Name='RunawayCartGlow';glow.FillColor=CYAN;glow.OutlineColor=CYAN;glow.OutlineTransparency=0
    glow.DepthMode=Enum.HighlightDepthMode.Occluded;glow.Enabled=false;glow.Parent=workspace.CurrentCamera -- in sight only: no through-wall marker (lead 2026-10-27)
   end
   glow.Adornee=haunted and cart or nil;glow.Enabled=haunted==true
   if haunted then
    glow.FillTransparency=.65+.2*math.sin(os.clock()*6)
    banner.Text=('THE CART IS RUNNING AWAY!  %s  (%ds)'):format(grabHint(),math.max(0,math.ceil(untilAt-workspace:GetServerTimeNow())))
    banner.Visible=true
   else
    local result=cart and cart:GetAttribute('HauntResult')
    if result and result~=shownResult then
     shownResult=result;resultAt=os.clock()
     banner.Text=result=='caught'and('%s caught the cart!  +$%d'):format(cart:GetAttribute('HauntCaughtBy')or'Someone',cart:GetAttribute('HauntBonus')or 0)
      or'The ghost let go. Go find your cart!'
    end
    banner.Visible=os.clock()-resultAt<3
   end
   task.wait(.1)
  end
 end)
end
