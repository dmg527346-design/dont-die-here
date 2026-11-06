-- Client half of CursedBatchEffects.ItemBatch6 (CursedA build 2026-10-27). Required once (task.spawn) by
-- CurseEffectsClient. Reads only replicated attributes; no remotes, no images.
--  * Reactions: ItemReact/ItemReactAt on the local player -> a soft colour wash and a short camera hop / wobble
--    (<= 2.5 s, never a full-screen block, nothing flashing; camera motion honours HorrorPreferences CameraMotion).
--    The popping word + jolt come from CurseEffectsClient's ReactPop renderer (ItemBatch6.Feedback sets ReactPop*);
--    faces are drawn by VoiceMouthClient / CharacterMotionClient from FaceBeat/FaceBeatUntil.
--  * First-find: client-only glow on unheld first-find items, foam-finger warmth sparkle + crowd, step boing/squish.
--  * HiccupBubbleBath: the bubbled holder floats (BubbledUntil), tagged creatures glow (BubbleTagUntil).
--  * PopUpToaster: the DING hop (ToastPopAt).  * HomesickYoyo: rides the string (YoyoZipTo/YoyoZipUntil).
--  * HideyBox: see-through box, peephole vignette, budget bar.  * PocketFogger: whiteout veil, carts fade in fog.
--  * HungryLunchbox: "CHOMP! ate X +$N" pop.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local SoundService=game:GetService('SoundService')
local Lighting=game:GetService('Lighting')
local TweenService=game:GetService('TweenService')
local InputHints=require(RS:WaitForChild('InputHints'))
local SoundCatalog=require(RS:WaitForChild('GameplaySoundCatalog'))
local p=Players.LocalPlayer
local M={}

local function leased(q,key)return workspace:GetServerTimeNow()<(q:GetAttribute(key)or 0)end
local function alive(q)local c=q.Character;local h=c and c:FindFirstChildOfClass('Humanoid');return h~=nil and h.Health>0 and q:GetAttribute('MissionActive')==true end
local function interactive()
 local map=workspace:FindFirstChild('Mansion');return map and map:FindFirstChild('Interactive')
end
local function monsterNear(radius)
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local f=workspace:FindFirstChild('RoamingCreatures')
 if not r or not f then return false end
 for _,n in ipairs(f:GetChildren())do local pp=n:IsA('Model')and n.PrimaryPart;if pp and(pp.Position-r.Position).Magnitude<radius then return true end end
 return false
end

-- Reactions ---------------------------------------------------------------------------------------------------------
-- colour, tint strength (0..1 of a 14% wash), camera: hop (studs), shake (rad, only for word-less keys), wobble (rad roll), seconds
local GOLD,CYAN,LIME,PURPLE,ORANGE,WHITE,GREY,MINT=Color3.fromRGB(255,214,70),Color3.fromRGB(120,220,255),Color3.fromRGB(150,230,90),Color3.fromRGB(180,140,255),Color3.fromRGB(255,160,60),Color3.fromRGB(240,245,250),Color3.fromRGB(175,180,190),Color3.fromRGB(110,225,195)
local REACT={
 FoamCheer={color=GOLD,tint=1,hop=.5,seconds=1.6},
 BobbleBoing={color=MINT,tint=.6,hop=.9,seconds=1.2},
 JellySplat={color=LIME,tint=.8,wobble=.09,seconds=1.6},
 CartCheer={color=GOLD,tint=.7,seconds=1.4},
 BathGrab={color=CYAN,tint=.4,seconds=1},
 HicSmall={color=CYAN,tint=.3,hop=.45,seconds=.7},
 Hiccup={color=CYAN,tint=.9,hop=1,wobble=.05,seconds=1.6},
 BubblePop={color=CYAN,tint=.6,seconds=.9},
 ToastGrab={color=ORANGE,tint=.3,seconds=1.2},
 ToastDing={color=GOLD,tint=.8,hop=.6,seconds=1.1},
 YoyoZip={color=PURPLE,tint=.6,seconds=1.2},
 YoyoCaught={color=PURPLE,tint=.4,seconds=1},
 YoyoBonk={color=PURPLE,tint=.6,wobble=.07,seconds=2.5},
 YoyoSleepy={color=PURPLE,tint=.2,seconds=1},
 BoxIn={color=Color3.fromRGB(221,188,128),tint=.4,seconds=1.2},
 BoxHidden={color=Color3.fromRGB(221,188,128),tint=0,seconds=1},
 BoxKicked={color=ORANGE,tint=.6,seconds=1.1},
 BoxKick={color=ORANGE,tint=.3,seconds=.8},
 BoxCollapse={color=ORANGE,tint=.6,seconds=1.4},
 BoxSquashed={color=GREY,tint=.2,seconds=1},
 FogPuff={color=WHITE,tint=1,seconds=1.2},
 FogWheeze={color=GREY,tint=.3,seconds=1},
 LunchSnap={color=LIME,tint=.6,seconds=1},
 LunchChomp={color=LIME,tint=.3,seconds=.8},
 -- ItemBatch7
 DustyAdopt={color=CYAN,tint=.5,hop=.4,seconds=1.6},
 DustyGulp={color=CYAN,tint=.3,seconds=.9},
 DustyPanic={color=ORANGE,tint=.5,seconds=1.1},
 DustyDeliver={color=GOLD,tint=.6,hop=.4,seconds=1.4},
 SockAdopt={color=PURPLE,tint=.4,seconds=1.5},
 SockPeek={color=PURPLE,tint=.35,shake=.02,seconds=.8},
 PagerStart={color=LIME,tint=.6,seconds=1},
 PagerCollected={color=GOLD,tint=1,hop=.6,seconds=1.6},
 PagerCancelled={color=ORANGE,tint=.6,seconds=1.4},
 PassGrab={color=MINT,tint=.4,seconds=1.2},
 PassWhistle={color=ORANGE,tint=.7,seconds=1.2},
 PassTardy={color=GREY,tint=.4,seconds=1.4},
 IdolLift={color=GOLD,tint=1,hop=.5,seconds=1.8},
 IdolDark={color=GREY,tint=0,shake=.025,seconds=.8},
 IdolWake={color=PURPLE,tint=.4,seconds=1.8},
 CrownOn={color=GOLD,tint=1,hop=.4,seconds=1.8},
}
M.REACT=REACT
local fxGui=Instance.new('ScreenGui');fxGui.Name='ItemReactFx';fxGui.ResetOnSpawn=false;fxGui.IgnoreGuiInset=true;fxGui.DisplayOrder=6;fxGui.Parent=p:WaitForChild('PlayerGui')
local wash=Instance.new('Frame');wash.Name='Wash';wash.Size=UDim2.fromScale(1,1);wash.BorderSizePixel=0;wash.BackgroundTransparency=1;wash.Active=false;wash.Parent=fxGui
local Prefs=require(RS:WaitForChild('HorrorPreferences'))
local function cameraMotion()local ok,v=pcall(Prefs.Get,'CameraMotion');return not ok or v~=false end
local cam={at=0,hop=0,shake=0,wobble=0,seconds=1}
local tweens={}
local function play(key)
 local r=REACT[key];if not r then return end
 for _,t in ipairs(tweens)do t:Cancel()end;table.clear(tweens)
 local seconds=r.seconds or 1
 -- A monster close by: keep the wash faint so nothing ever hides it.
 local tint=(r.tint or 0)*(monsterNear(20)and .4 or 1)
 wash.BackgroundColor3=r.color;wash.BackgroundTransparency=1-.14*tint
 table.insert(tweens,TweenService:Create(wash,TweenInfo.new(math.min(seconds,1),Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}))
 for _,t in ipairs(tweens)do t:Play()end
 cam.at=os.clock();cam.hop=r.hop or 0;cam.shake=r.shake or 0;cam.wobble=r.wobble or 0;cam.seconds=seconds
 p:SetAttribute('ItemReactPlayed',key) -- local only: test probe
end
M.Play=play
p:GetAttributeChangedSignal('ItemReactAt'):Connect(function()
 local at=p:GetAttribute('ItemReactAt');if type(at)~='number'or workspace:GetServerTimeNow()-at>2 then return end
 play(p:GetAttribute('ItemReact'))
end)
-- Camera layer: removed again before the camera module runs (never accumulates), like CurseEffectsClient's roll.
local applied,appliedCam=nil,nil
Run:BindToRenderStep('ItemReactReset',Enum.RenderPriority.Camera.Value-3,function()
 if applied and appliedCam and appliedCam==workspace.CurrentCamera then appliedCam.CFrame*=applied:Inverse()end
 applied=nil;appliedCam=nil
end)
Run:BindToRenderStep('ItemReactCamera',Enum.RenderPriority.Camera.Value+3,function()
 local c=workspace.CurrentCamera;if not c or not cameraMotion()then return end
 local now=os.clock();local age=now-cam.at
 local offset=CFrame.identity
 if age<.6 and cam.hop>0 then offset*=CFrame.new(0,math.sin(math.min(age/.6,1)*math.pi)*cam.hop*math.exp(-age*2),0)end
 if age<cam.seconds and cam.shake>0 then local a=cam.shake*(1-age/cam.seconds);offset*=CFrame.Angles(math.noise(now*21,1)*a*2,math.noise(now*19,2)*a*2,math.noise(now*23,3)*a)end
 -- Yo-yo bonk: dizzy wobble for the whole lease; caught: a small jolt.
 local wob=age<cam.seconds and cam.wobble>0 and cam.wobble*(1-age/cam.seconds)or 0
 if alive(p)and leased(p,'YoyoBonkUntil')then wob=math.max(wob,.06)end
 if wob>0 then offset*=CFrame.Angles(0,0,math.sin(now*5)*wob)end
 if offset~=CFrame.identity then c.CFrame*=offset;applied=offset;appliedCam=c end
end)

-- First-find ----------------------------------------------------------------------------------------------------------
local FIRST_FIND={FoamFinger=true,BobbleBuddy=true,WobbleJelly=true}
local GLOW=Color3.fromRGB(255,226,150)
local STEP_SECONDS=.42
local function localSound(key,name)
 local cue=SoundCatalog[key];if not cue then return nil,nil end
 local s=Instance.new('Sound');s.Name=name;s.SoundId=cue.id;s.Volume=cue.volume or .3;s.PlaybackSpeed=cue.speed or 1;s.Parent=SoundService
 return s,cue.volume or .3
end
local crowd,crowdVolume=localSound('FirstFindCrowd','FoamFingerCrowd');if crowd then crowd.Looped=true end
local boing,boingVolume=localSound('DraftSelected_SpringyWhisk','BobbleStep')
local squish=localSound('FrostingSquish','JellyStep');if squish then squish.Volume=.35 end
local glows={}
local heldFinger
local sparkle
local nextStep=0
local function basketPoint(inter)
 local cart=inter:FindFirstChild('RecoveryCart')
 if not cart then for _,x in ipairs(inter:GetChildren())do if x:GetAttribute('Kind')=='cart'or x:GetAttribute('Kind')=='boat'then cart=x;break end end end
 if not cart or not cart:IsA('Model')or not cart.PrimaryPart then return nil end
 local offset=cart:GetAttribute('BasketOffset')
 return typeof(offset)=='Vector3'and(cart.PrimaryPart.CFrame*CFrame.new(offset*cart:GetScale())).Position or cart.PrimaryPart.Position
end
local function dropGlow(m)
 local g=glows[m];glows[m]=nil
 if g then for _,x in ipairs(g)do if x.Parent then x:Destroy()end end end
end
local function addGlow(m)
 local light=Instance.new('PointLight');light.Name='FirstFindGlow';light.Color=GLOW;light.Range=9;light.Brightness=1.2;light.Shadows=false;light.Parent=m.PrimaryPart
 local a=Instance.new('Attachment');a.Name='FirstFindTwinkle';a.Parent=m.PrimaryPart
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(GLOW);e.LightEmission=1
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.5,.35),NumberSequenceKeypoint.new(1,0)})
 e.Lifetime=NumberRange.new(.8,1.3);e.Rate=6;e.Speed=NumberRange.new(.4,1.2);e.SpreadAngle=Vector2.new(180,180);e.Parent=a
 glows[m]={light,a}
end

-- HiccupBubbleBath / PopUpToaster -------------------------------------------------------------------------------------
local BUBBLE_FLOAT,BUBBLE_BOB=3,.25
local bubbleBaseY
local bubbleTags={}
local TOAST_POP_SPEED,TOAST_STALE=58,.6
p:GetAttributeChangedSignal('ToastPopAt'):Connect(function()
 local at=p:GetAttribute('ToastPopAt')
 if not at or workspace:GetServerTimeNow()-at>TOAST_STALE or not alive(p)then return end
 if p:GetAttribute('Hiding')or p:GetAttribute('MonsterJumpscareActive')then return end
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
 if not h or not r or r.Anchored or h.Sit then return end
 h:ChangeState(Enum.HumanoidStateType.Jumping)
 local v=r.AssemblyLinearVelocity
 r.AssemblyLinearVelocity=Vector3.new(v.X,TOAST_POP_SPEED,v.Z)
 p:SetAttribute('ToastHopped',(p:GetAttribute('ToastHopped')or 0)+1) -- local only: test probe
end)
Run.PreSimulation:Connect(function()
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
 if not(r and alive(p)and leased(p,'BubbledUntil'))or r.Anchored then bubbleBaseY=nil;return end
 bubbleBaseY=bubbleBaseY or r.Position.Y
 local goal=bubbleBaseY+BUBBLE_FLOAT+math.sin(os.clock()*2.2)*BUBBLE_BOB
 r.AssemblyLinearVelocity=Vector3.new(0,math.clamp((goal-r.Position.Y)*6,-10,10),0)
end)

-- HomesickYoyo --------------------------------------------------------------------------------------------------------
local YOYO_ZIP_SPEED,YOYO_ARRIVE=58,4.5
local zip=nil
local lastZipStamp=0
local function endZip(root,direction)
 if zip then if zip.lv then zip.lv:Destroy()end;if zip.att then zip.att:Destroy()end end
 zip=nil
 if root and direction then root.AssemblyLinearVelocity=direction*8 end
end

-- HideyBox ------------------------------------------------------------------------------------------------------------
local CARD=Color3.fromRGB(221,188,128)
local SHADOW=Color3.fromRGB(28,22,14)
local BOX_BUDGET=25
local boxGui=Instance.new('ScreenGui');boxGui.Name='HideyBoxHud';boxGui.ResetOnSpawn=false;boxGui.IgnoreGuiInset=true;boxGui.DisplayOrder=4;boxGui.Enabled=false;boxGui.Parent=p:WaitForChild('PlayerGui')
local function edge(rotation,position,size)
 local f=Instance.new('Frame');f.BackgroundColor3=SHADOW;f.BorderSizePixel=0;f.AnchorPoint=Vector2.new(.5,.5);f.Position=position;f.Size=size;f.Parent=boxGui
 local g=Instance.new('UIGradient');g.Rotation=rotation
 g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(1,1)});g.Parent=f
 return f
end
local edges={
 edge(90,UDim2.fromScale(.5,.14),UDim2.fromScale(1,.28)),edge(270,UDim2.fromScale(.5,.86),UDim2.fromScale(1,.28)),
 edge(0,UDim2.fromScale(.12,.5),UDim2.fromScale(.24,1)),edge(180,UDim2.fromScale(.88,.5),UDim2.fromScale(.24,1)),
}
local bar=Instance.new('Frame');bar.Name='Budget';bar.AnchorPoint=Vector2.new(.5,0);bar.Size=UDim2.fromOffset(260,32)
bar.BackgroundColor3=Color3.fromRGB(40,32,22);bar.BackgroundTransparency=.15;bar.Parent=boxGui
Instance.new('UICorner',bar).CornerRadius=UDim.new(0,8)
local fill=Instance.new('Frame');fill.BackgroundColor3=CARD;fill.BorderSizePixel=0;fill.Size=UDim2.fromScale(1,1);fill.Parent=bar
Instance.new('UICorner',fill).CornerRadius=UDim.new(0,8)
local boxLabel=Instance.new('TextLabel');boxLabel.BackgroundTransparency=1;boxLabel.Size=UDim2.fromScale(1,1);boxLabel.ZIndex=3
boxLabel.Font=Enum.Font.GothamBold;boxLabel.TextScaled=true;boxLabel.TextColor3=Color3.new(1,1,1);boxLabel.TextStrokeTransparency=.35;boxLabel.Parent=bar
local boxPad=Instance.new('UIPadding');boxPad.PaddingLeft=UDim.new(0,8);boxPad.PaddingRight=UDim.new(0,8);boxPad.PaddingTop=UDim.new(0,5);boxPad.PaddingBottom=UDim.new(0,5);boxPad.Parent=boxLabel
local function releaseHint()
 local mode=InputHints.Get()
 if mode=='touch'then return 'tap GRAB to climb out' elseif mode=='pad'then return 'hold RT to stay in' end
 return 'hold LMB to stay in'
end
local box,faded=nil,{}
local function unfade()
 for part in pairs(faded)do if part.Parent then part.LocalTransparencyModifier=0 end end
 table.clear(faded)
end

-- PocketFogger --------------------------------------------------------------------------------------------------------
local FOG=Color3.fromRGB(214,224,230)
local FOG_HEIGHT=12
local fogGui=Instance.new('ScreenGui');fogGui.Name='FogWhiteout';fogGui.ResetOnSpawn=false;fogGui.IgnoreGuiInset=true;fogGui.DisplayOrder=3;fogGui.Parent=p:WaitForChild('PlayerGui')
local veil=Instance.new('Frame');veil.Size=UDim2.fromScale(1,1);veil.BackgroundColor3=FOG;veil.BorderSizePixel=0;veil.BackgroundTransparency=1;veil.Parent=fogGui
local blur=Lighting:FindFirstChild('FogMachineBlur')or Instance.new('BlurEffect');blur.Name='FogMachineBlur';blur.Size=0;blur.Enabled=false;blur.Parent=Lighting
local fogDepth=0
local fadedCarts={}
local function fadeCart(cart,amount)
 for _,part in ipairs(cart:GetDescendants())do if part:IsA('BasePart')then part.LocalTransparencyModifier=amount end end
end

-- HungryLunchbox ------------------------------------------------------------------------------------------------------
local hookedLunch=setmetatable({},{__mode='k'})
local function chompPop(m)
 local root=m.PrimaryPart;if not root then return end
 local net=m:GetAttribute('LunchboxNet')or 0;local ate=m:GetAttribute('LunchboxAteName')or 'something'
 local bb=Instance.new('BillboardGui');bb.Name='LunchboxChompPop';bb.Adornee=root;bb.Size=UDim2.fromOffset(190,52)
 bb.StudsOffsetWorldSpace=Vector3.new(0,2,0);bb.AlwaysOnTop=true;bb.MaxDistance=70;bb.LightInfluence=0;bb.ResetOnSpawn=false
 local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true
 t.TextColor3=net>=0 and Color3.fromRGB(150,240,120)or Color3.fromRGB(255,190,90)
 t.Text=('CHOMP! ate %s\n%s$%d'):format(ate,net>=0 and '+' or '-',math.abs(net));t.Parent=bb
 local st=Instance.new('UIStroke');st.Thickness=2;st.Color=Color3.fromRGB(28,36,28);st.Parent=t
 bb.Parent=p:WaitForChild('PlayerGui')
 local info=TweenInfo.new(1.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
 TweenService:Create(bb,info,{StudsOffsetWorldSpace=Vector3.new(0,4,0)}):Play()
 TweenService:Create(t,info,{TextTransparency=1}):Play();TweenService:Create(st,info,{Transparency=1}):Play()
 task.delay(1.5,function()bb:Destroy()end)
end

-- 4 Hz scan: glows, foam warmth, crowd, lunchbox hooks, faded carts ------------------------------------------------------
local scanElapsed=0
Run.Heartbeat:Connect(function(dt)
 scanElapsed+=dt
 if scanElapsed>=.25 then
  scanElapsed=0
  local inter=interactive();heldFinger=nil
  for m in pairs(glows)do if not m.Parent or m.Parent~=inter then dropGlow(m)end end
  local serverNow=workspace:GetServerTimeNow();local seenCarts={}
  if inter then for _,m in ipairs(inter:GetChildren())do
   local id=m:GetAttribute('ItemId')
   if FIRST_FIND[id]and m:IsA('Model')and m.PrimaryPart then
    local free=not m:GetAttribute('HeldBy')and not m:GetAttribute('CargoStored')and not m:GetAttribute('Selling')
    if free and not glows[m]then addGlow(m)elseif not free and glows[m]then dropGlow(m)end
    if id=='FoamFinger'and m:GetAttribute('HeldBy')==p.UserId then heldFinger=m end
   elseif id=='HungryLunchbox'and not hookedLunch[m]and m:IsA('Model')then
    hookedLunch[m]=true;m:GetAttributeChangedSignal('LunchboxAteAt'):Connect(function()chompPop(m)end)
   elseif m:GetAttribute('Kind')=='cart'and serverNow<(m:GetAttribute('FogLostUntil')or 0)then
    seenCarts[m]=true;if not fadedCarts[m]then fadedCarts[m]=true;fadeCart(m,.85)end
   end
  end end
  for m in pairs(fadedCarts)do if not seenCarts[m]then fadedCarts[m]=nil;if m.Parent then fadeCart(m,0)end end end
  -- Foam finger warmth: 0 far (40+ studs) .. 1 at the basket.
  local warm=0
  local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
  local point=heldFinger and inter and basketPoint(inter)
  if heldFinger and root and point and alive(p)then warm=math.clamp(1-((root.Position-point).Magnitude-4)/36,0,1)end
  if heldFinger and heldFinger.PrimaryPart then
   if not sparkle or sparkle.Parent==nil or sparkle.Parent.Parent~=heldFinger.PrimaryPart then
    if sparkle and sparkle.Parent then sparkle.Parent:Destroy()end
    local a=Instance.new('Attachment');a.Name='FoamFingerWarmth';a.Position=Vector3.new(0,heldFinger.PrimaryPart.Size.Y*.45,0);a.Parent=heldFinger.PrimaryPart
    sparkle=Instance.new('ParticleEmitter');sparkle.Texture='rbxasset://textures/particles/sparkles_main.dds'
    sparkle.Color=ColorSequence.new(Color3.fromRGB(250,210,60),Color3.fromRGB(60,170,240));sparkle.LightEmission=.8
    sparkle.Size=NumberSequence.new(.22,.08);sparkle.Lifetime=NumberRange.new(.6,1);sparkle.Speed=NumberRange.new(2,5);sparkle.SpreadAngle=Vector2.new(40,40);sparkle.Parent=a
   end
   sparkle.Rate=3+warm*40
  elseif sparkle then
   if sparkle.Parent then sparkle.Parent:Destroy()end;sparkle=nil
  end
  if crowd then
   if heldFinger then crowd.Volume=crowdVolume*(.25+.75*warm);if not crowd.IsPlaying then crowd:Play()end
   elseif crowd.IsPlaying then crowd:Stop()end
  end
  -- Bubble bath scouting: tagged creatures glow through walls for every player.
  for n,h in pairs(bubbleTags)do
   if not n.Parent or serverNow>=(n:GetAttribute('BubbleTagUntil')or 0)then h:Destroy();bubbleTags[n]=nil end
  end
  local f=workspace:FindFirstChild('RoamingCreatures')
  if f then for _,n in ipairs(f:GetChildren())do
   if not bubbleTags[n]and serverNow<(n:GetAttribute('BubbleTagUntil')or 0)then
    local h=Instance.new('Highlight');h.Name='BubbleTag';h.Adornee=n;h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
    h.FillColor=Color3.fromRGB(150,220,255);h.FillTransparency=.78;h.OutlineColor=Color3.fromRGB(235,250,255);h.OutlineTransparency=.1
    h.Parent=n;bubbleTags[n]=h
   end
  end end
 end
 -- Step sounds for the local carrier only.
 local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
 if root and alive(p)and os.clock()>=nextStep then
  local speed=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude
  if speed>4 then
   local sound=leased(p,'BobbleUntil')and boing or leased(p,'JellyUntil')and squish or nil
   if sound then
    nextStep=os.clock()+STEP_SECONDS*math.clamp(16/speed,.6,1.4)
    sound.PlaybackSpeed=(sound==boing and 1 or .7)*(.9+math.random()*.25)
    if sound==boing then sound.Volume=(boingVolume or .5)*.45 end
    sound:Play()
   end
  end
 end
 -- Yo-yo zip: a constraint push like MonsterAbilityClient's knock.
 local now=workspace:GetServerTimeNow()
 local stamp=p:GetAttribute('YoyoZipUntil')or 0
 local c=p.Character;local hum=c and c:FindFirstChildOfClass('Humanoid')
 if stamp~=lastZipStamp and now<stamp and alive(p)and root and hum and not root.Anchored then
  lastZipStamp=stamp;endZip()
  local target=Players:GetPlayerByUserId(p:GetAttribute('YoyoZipTo')or 0)
  if target then
   hum:ChangeState(Enum.HumanoidStateType.Freefall)
   local att=Instance.new('Attachment');att.Name='YoyoZipAttachment';att.Parent=root
   local lv=Instance.new('LinearVelocity');lv.Name='YoyoZip';lv.Attachment0=att;lv.MaxForce=math.huge
   lv.RelativeTo=Enum.ActuatorRelativeTo.World;lv.VectorVelocity=Vector3.zero;lv.Parent=root
   zip={stamp=stamp,target=target,lv=lv,att=att,best=math.huge,checkAt=os.clock()+.3}
  end
 end
 if zip then
  local tc=zip.target.Character;local tr=tc and tc:FindFirstChild('HumanoidRootPart')
  if now>=zip.stamp or not alive(p)or not root or not tr or zip.lv.Parent~=root then endZip()
  else
   local delta=tr.Position-root.Position;local d=delta.Magnitude
   if d<=YOYO_ARRIVE then endZip(root,delta.Unit)
   elseif os.clock()>=zip.checkAt and d>zip.best-.5 then endZip(root,nil)
   else
    if os.clock()>=zip.checkAt then zip.best=d;zip.checkAt=os.clock()+.3 end
    zip.lv.VectorVelocity=delta.Unit*YOYO_ZIP_SPEED+Vector3.new(0,2,0)
   end
  end
 end
end)

-- Per-frame: Hidey box HUD + fog veil -----------------------------------------------------------------------------------
local boxScanAt=0
Run.RenderStepped:Connect(function(dt)
 local now=os.clock()
 if now>=boxScanAt then
  boxScanAt=now+.1
  local found
  local inter=interactive()
  if inter then for _,m in ipairs(inter:GetChildren())do if m:GetAttribute('ItemId')=='HideyBox'and m:GetAttribute('HideyWornBy')==p.UserId then found=m;break end end end
  if found~=box then unfade();box=found end
 end
 if box and box.Parent and box:GetAttribute('HideyWornBy')==p.UserId then
  for _,part in ipairs(box:GetDescendants())do
   if part:IsA('BasePart')and not faded[part]then faded[part]=true;part.LocalTransparencyModifier=.6 end
  end
  local hidden=box:GetAttribute('HideyHidden')==true
  local left=box:GetAttribute('HideyBudget')or 0
  boxGui.Enabled=true
  for _,f in ipairs(edges)do f.Visible=hidden end
  bar.Position=UDim2.new(.5,0,1,-118) -- owner UI pass 2026-10-27: phones too (at the top it covered the quota HUD)
  fill.Size=UDim2.fromScale(math.clamp(left/BOX_BUDGET,0,1),1)
  boxLabel.Text=if hidden then ('HIDDEN %ds  (%s)'):format(math.ceil(left),releaseHint())else 'Stand still to hide  ('..releaseHint()..')'
 else
  if box then unfade();box=nil end
  boxGui.Enabled=false
 end
 local camera=workspace.CurrentCamera;local folder=workspace:FindFirstChild('FogClouds')
 local target=0
 if camera and folder and p:GetAttribute('MissionActive')==true then
  local eye=camera.CFrame.Position
  for _,cloud in ipairs(folder:GetChildren())do
   local r=cloud:GetAttribute('FogRadius')or 0
   if r>0 and cloud:IsA('BasePart')then
    local flat=Vector3.new(eye.X-cloud.Position.X,0,eye.Z-cloud.Position.Z).Magnitude
    if flat<r and math.abs(eye.Y-cloud.Position.Y)<FOG_HEIGHT then target=math.max(target,math.clamp((1-flat/r)*2.2,0,1))end
   end
  end
 end
 fogDepth+=(target-fogDepth)*math.clamp(dt*4,0,1)
 veil.BackgroundTransparency=1-.72*fogDepth
 blur.Size=10*fogDepth
 blur.Enabled=fogDepth>.01
end)
return M
