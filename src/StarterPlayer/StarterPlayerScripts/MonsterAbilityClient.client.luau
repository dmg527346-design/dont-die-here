-- Client side of the monster roles (server: CreatureRoamServer.MonsterAbilities, 2026-10-22).
-- Draws the Neon Tripod's spinning laser, the hurt flash and knockback, the "RUN" countdown after the Lantern pulls you out
-- of a closet, the picked-up banner, a monster's health bar once thrown items have hurt it, and the hit flash on a monster.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Tween=game:GetService('TweenService')
local CAS=game:GetService('ContextActionService')
local player=Players.LocalPlayer
local event=RS:WaitForChild('MonsterAbilityEvent')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local Preferences=require(RS:WaitForChild('HorrorPreferences'))

local gui=Instance.new('ScreenGui');gui.Name='MonsterAbilityHud';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.DisplayOrder=40;gui.Parent=player:WaitForChild('PlayerGui')

-- ===== Hurt: a dark vignette pulse, a white hit flash and a short shake =====
-- Edge darkening from four gradient strips (no image asset needed).
local vignette=Instance.new('Frame');vignette.Name='HurtVignette';vignette.Size=UDim2.fromScale(1,1);vignette.BackgroundTransparency=1;vignette.Parent=gui
local edges={}
for i,spec in {{UDim2.fromScale(1,.28),UDim2.fromScale(0,0),90},{UDim2.fromScale(1,.28),UDim2.fromScale(0,.72),-90},{UDim2.fromScale(.22,1),UDim2.fromScale(0,0),0},{UDim2.fromScale(.22,1),UDim2.fromScale(.78,0),180}}do
 local f=Instance.new('Frame');f.Size=spec[1];f.Position=spec[2];f.BackgroundColor3=Color3.fromRGB(30,6,48);f.BorderSizePixel=0;f.BackgroundTransparency=1;f.Parent=vignette
 local g=Instance.new('UIGradient');g.Rotation=spec[3];g.Transparency=NumberSequence.new(0,1);g.Parent=f
 edges[i]=f
end
local function setVignette(alpha)for _,f in edges do f.BackgroundTransparency=1-alpha end end
local flash=Instance.new('Frame');flash.Name='HitFlash';flash.Size=UDim2.fromScale(1,1);flash.BackgroundColor3=Color3.new(1,1,1);flash.BackgroundTransparency=1;flash.BorderSizePixel=0;flash.Parent=gui
local shakeUntil,shakePower=0,0
local function hurt(amount)
 flash.BackgroundTransparency=.55;Tween:Create(flash,TweenInfo.new(.25),{BackgroundTransparency=1}):Play()
 setVignette(.9);for _,f in edges do Tween:Create(f,TweenInfo.new(1.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()end
 shakeUntil=os.clock()+.35;shakePower=math.clamp(amount/100,.2,.5)
 local pop=Instance.new('TextLabel');pop.BackgroundTransparency=1;pop.AnchorPoint=Vector2.new(.5,.5);pop.Position=UDim2.fromScale(.5,.42);pop.Size=UDim2.fromOffset(240,70)
 pop.Font=Enum.Font.FredokaOne;pop.TextSize=46;pop.TextColor3=Color3.fromRGB(255,236,200);pop.Text='-'..amount;pop.TextStrokeTransparency=.3;pop.Parent=gui
 Tween:Create(pop,TweenInfo.new(.9,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.34),TextTransparency=1,TextStrokeTransparency=1}):Play()
 task.delay(1,function()pop:Destroy()end)
end
Run:BindToRenderStep('MonsterHurtShake',Enum.RenderPriority.Camera.Value+2,function()
 if os.clock()>shakeUntil or not Preferences.Get('CameraMotion')then return end
 local cam=workspace.CurrentCamera;local k=(shakeUntil-os.clock())/.35*shakePower
 cam.CFrame*=CFrame.Angles(math.sin(os.clock()*61)*.03*k,math.cos(os.clock()*53)*.03*k,math.sin(os.clock()*47)*.04*k)
end)

-- ===== Banner (picked up / escaped) =====
local banner=Instance.new('TextLabel');banner.Name='MonsterBanner';banner.AnchorPoint=Vector2.new(.5,0);banner.Position=UDim2.new(.5,0,0,96);banner.Size=UDim2.fromOffset(520,44)
banner.BackgroundTransparency=1;banner.Font=Enum.Font.FredokaOne;banner.TextSize=30;banner.TextColor3=Color3.fromRGB(255,240,205);banner.TextStrokeTransparency=.25;banner.TextTransparency=1;banner.TextStrokeColor3=Color3.fromRGB(20,10,30);banner.Parent=gui
local function say(text,seconds)
 -- Always under the quota panel (owner 2026-10-22: on console it overlapped the quota); its height differs per device.
 local q=player.PlayerGui:FindFirstChild('RecoveryQuota');local panel=q and q.Enabled and q:FindFirstChild('QuotaPanel')
 local top=96;if panel and panel.Visible then top=math.max(top,panel.AbsolutePosition.Y+panel.AbsoluteSize.Y-gui.AbsolutePosition.Y+10)end
 banner.Position=UDim2.new(.5,0,0,top)
 banner.Text=text;banner.TextTransparency=0;banner.TextStrokeTransparency=.25
 local token={};banner:SetAttribute('Token',tostring(token))
 task.delay(seconds or 2,function()if banner:GetAttribute('Token')==tostring(token)then Tween:Create(banner,TweenInfo.new(.4),{TextTransparency=1,TextStrokeTransparency=1}):Play()end end)
end
-- While a monster holds you, the camera turns to face it (its head), easing in so it doesn't snap.
local function holderHead()
 local char=player.Character;local r=char and char:FindFirstChild('HumanoidRootPart');if not r then return nil end
 local best,bestD
 for _,m in workspace:WaitForChild('RoamingCreatures'):GetChildren()do
  if m:GetAttribute('AttackPose')=='Carry'and m.PrimaryPart then
   local d=(m.PrimaryPart.Position-r.Position).Magnitude
   if not bestD or d<bestD then best,bestD=m,d end
  end
 end
 if not best then return nil end
 local head=best:FindFirstChild('Head')
 if head then return head.Position end
 local cf,size=best:GetBoundingBox();return cf.Position+Vector3.new(0,size.Y*.3,0)
end
local heldLook=0
local function lookAtHolder(dt)
 if not player:GetAttribute('MonsterHeld')then heldLook=0;return end
 local target=holderHead();if not target then return end
 local cam=workspace.CurrentCamera
 heldLook=math.min(1,heldLook+dt*4)
 local want=CFrame.lookAt(cam.CFrame.Position,target)
 cam.CFrame=cam.CFrame:Lerp(want,heldLook)
end
player:GetAttributeChangedSignal('MonsterHeld'):Connect(function()
 if player:GetAttribute('MonsterHeld')then
  say('IT PICKED YOU UP!',2.6)
  CAS:BindActionAtPriority('MonsterHeldMovement',function()return Enum.ContextActionResult.Sink end,false,2900,unpack(Enum.PlayerActions:GetEnumItems()))
  Run:BindToRenderStep('MonsterHeldLook',Enum.RenderPriority.Camera.Value+3,lookAtHolder)
 else
  CAS:UnbindAction('MonsterHeldMovement')
  pcall(function()Run:UnbindFromRenderStep('MonsterHeldLook')end)
 end
end)

-- ===== RUN countdown =====
local runFrame=Instance.new('Frame');runFrame.Name='RunCountdown';runFrame.AnchorPoint=Vector2.new(.5,.5);runFrame.Position=UDim2.fromScale(.5,.3);runFrame.Size=UDim2.fromOffset(420,170);runFrame.BackgroundTransparency=1;runFrame.Visible=false;runFrame.Parent=gui
local runTitle=Instance.new('TextLabel');runTitle.Size=UDim2.new(1,0,0,90);runTitle.BackgroundTransparency=1;runTitle.Font=Enum.Font.FredokaOne;runTitle.TextSize=84;runTitle.Text='RUN!';runTitle.TextColor3=Color3.fromRGB(255,214,90);runTitle.TextStrokeTransparency=0;runTitle.TextStrokeColor3=Color3.fromRGB(25,10,35);runTitle.Parent=runFrame
local runCount=Instance.new('TextLabel');runCount.Position=UDim2.fromOffset(0,88);runCount.Size=UDim2.new(1,0,0,70);runCount.BackgroundTransparency=1;runCount.Font=Enum.Font.FredokaOne;runCount.TextSize=56;runCount.TextColor3=Color3.new(1,1,1);runCount.TextStrokeTransparency=.1;runCount.Parent=runFrame
local runHint=Instance.new('TextLabel');runHint.Position=UDim2.fromOffset(0,150);runHint.Size=UDim2.new(1,0,0,24);runHint.BackgroundTransparency=1;runHint.Font=Enum.Font.GothamBold;runHint.TextSize=18;runHint.TextColor3=Color3.fromRGB(230,220,255);runHint.TextStrokeTransparency=.3;runHint.Text='Get away from it before the count ends!';runHint.Parent=runFrame
local runDeadline,lastBeat=0,0
event.OnClientEvent:Connect(function(action,a,b,c)
 if action=='hurt'then hurt(a)
 elseif action=='knock'then
  local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
  if root and hum and not root.Anchored then
   -- A short constraint push: the humanoid controller would cancel a plain velocity change within a frame.
   hum:ChangeState(Enum.HumanoidStateType.Freefall)
   local att=Instance.new('Attachment');att.Name='MonsterKnockAttachment';att.Parent=root
   local lv=Instance.new('LinearVelocity');lv.Name='MonsterKnock';lv.Attachment0=att;lv.MaxForce=math.huge;lv.RelativeTo=Enum.ActuatorRelativeTo.World
   lv.VectorVelocity=a*b+Vector3.new(0,c or 16,0);lv.Parent=root
   task.delay(.16,function()lv:Destroy();att:Destroy()end)
  end
 elseif action=='run'then runDeadline=a;lastBeat=0;Audio.Play('MonsterNotice')
 elseif action=='escaped'then say('It let you go... this time.',2.4)
 end
end)

-- ===== Laser and monster hit feedback =====
local folder=workspace:WaitForChild('RoamingCreatures',math.huge)
local beams={}
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.RespectCanCollide=true
local closetRay=RaycastParams.new();closetRay.FilterType=Enum.RaycastFilterType.Include;closetRay.RespectCanCollide=false
local function newPart(name,size,color,transparency,material)
 local x=Instance.new('Part');x.Name=name;x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false
 x.Size=size;x.Color=color;x.Transparency=transparency or 0;x.Material=material or Enum.Material.Neon;x.Parent=workspace;return x
end
local function beamFor(model)
 local b=beams[model];if b then return b end
 b={}
 b.core=newPart('LaserCore',Vector3.new(.32,.32,1),Color3.fromRGB(235,250,255))
 b.glow=newPart('LaserGlow',Vector3.new(1.05,1.05,1),Color3.fromRGB(110,200,255),.55)
 b.orb=newPart('LaserOrb',Vector3.new(1,1,1),Color3.fromRGB(150,225,255),.15);b.orb.Shape=Enum.PartType.Ball
 -- The feed: a bright beam from the Tripod's eye down into the sweep, so the laser visibly comes out of its eye.
 -- The bend: one smooth curved beam from the eye, arcing down into the sweep (Roblox Beam between two attachments).
 b.curveRoot=newPart('LaserCurve',Vector3.new(.1,.1,.1),Color3.new(1,1,1),1)
 b.a0=Instance.new('Attachment');b.a0.Parent=b.curveRoot;b.a1=Instance.new('Attachment');b.a1.Parent=b.curveRoot
 local function curve(name,w0,w1,color,transparency)
  local bm=Instance.new('Beam');bm.Name=name;bm.Attachment0=b.a0;bm.Attachment1=b.a1;bm.Width0=w0;bm.Width1=w1;bm.FaceCamera=true;bm.Segments=24
  bm.LightEmission=1;bm.LightInfluence=0;bm.Color=ColorSequence.new(color);bm.Transparency=NumberSequence.new(transparency);bm.CurveSize0=1.8;bm.CurveSize1=2.2
  bm.Enabled=false;bm.Parent=b.curveRoot;return bm
 end
 b.curveCore=curve('CurveCore',.22,.32,Color3.fromRGB(235,250,255),0)
 b.curveGlow=curve('CurveGlow',.7,1.05,Color3.fromRGB(110,200,255),.55)
 b.eyeGlow=newPart('LaserEye',Vector3.new(1.2,1.2,1.2),Color3.fromRGB(170,235,255),.2);b.eyeGlow.Shape=Enum.PartType.Ball
 b.tip=newPart('LaserTip',Vector3.new(.2,.2,.2),Color3.new(1,1,1),1)
 local light=Instance.new('PointLight');light.Color=Color3.fromRGB(120,210,255);light.Range=14;light.Brightness=3;light.Parent=b.tip
 local sparks=Instance.new('ParticleEmitter');sparks.Texture='rbxasset://textures/particles/sparkles_main.dds';sparks.Color=ColorSequence.new(Color3.fromRGB(200,240,255),Color3.fromRGB(120,170,255))
 sparks.Size=NumberSequence.new(.5,0);sparks.Speed=NumberRange.new(6,14);sparks.SpreadAngle=Vector2.new(70,70);sparks.Lifetime=NumberRange.new(.2,.45);sparks.Rate=70;sparks.LightEmission=1;sparks.Parent=b.tip
 local orbLight=Instance.new('PointLight');orbLight.Color=Color3.fromRGB(120,210,255);orbLight.Range=18;orbLight.Brightness=4;orbLight.Parent=b.orb
 beams[model]=b;return b
end
-- Laser audio (2026-10-22): a rising charge whine at the eye orb, then a looping beam hum at the orb plus a quieter one riding
-- the beam's end, so you can hear the sweep coming round. Creator Store SFX: 'Laser charge up', 'Laser Beam Loop V2'.
local LASER_CHARGE_SOUND,LASER_LOOP_SOUND='rbxassetid://8392900771','rbxassetid://126321934365548'
local function laserSound(parent,id,volume,speed,looped)
 local s=Instance.new('Sound');s.SoundId=id;s.Volume=volume;s.PlaybackSpeed=speed;s.Looped=looped
 s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=6;s.RollOffMaxDistance=80;s.Parent=parent;s:Play()
 return s
end
task.spawn(function()
 local list={};for _,id in {LASER_CHARGE_SOUND,LASER_LOOP_SOUND}do local s=Instance.new('Sound');s.SoundId=id;table.insert(list,s)end
 pcall(function()game:GetService('ContentProvider'):PreloadAsync(list)end)
end)
-- When the beam stops, its hum spins down (pitch and volume slide away over ~1 s) instead of cutting off.
local function windDown(b)
 local sounds={}
 for _,key in {'humSound','tipSound','chargeSound'}do local s=b[key];if s and s.Parent then table.insert(sounds,s)end;b[key]=nil end
 if #sounds==0 then return end
 local holder=Instance.new('Part');holder.Name='LaserWindDown';holder.Anchored=true;holder.CanCollide=false;holder.CanQuery=false;holder.CanTouch=false;holder.Transparency=1
 holder.Size=Vector3.one;holder.CFrame=b.orb and b.orb.Parent and b.orb.CFrame or CFrame.new();holder.Parent=workspace
 for _,s in sounds do
  s.Parent=holder
  Tween:Create(s,TweenInfo.new(1.1,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{PlaybackSpeed=s.PlaybackSpeed*.3,Volume=0}):Play()
 end
 task.delay(1.2,function()holder:Destroy()end)
end
local function dropBeam(model)local b=beams[model];if not b then return end;windDown(b);for _,x in b do if typeof(x)=='Instance'then x:Destroy()end end;beams[model]=nil end
folder.ChildRemoved:Connect(dropBeam)

local bars={}
local function barFor(model)
 local b=bars[model];if b then return b end
 local root=model:FindFirstChild('CreatureRoot');if not root then return end
 local _,size=model:GetBoundingBox()
 -- PlaytestFixes 2026-10-27: no longer AlwaysOnTop (a hurt monster's bar showed through walls up to 90 studs).
 local bb=Instance.new('BillboardGui');bb.Name='MonsterHealth';bb.Size=UDim2.fromOffset(120,14);bb.StudsOffsetWorldSpace=Vector3.new(0,size.Y+1.2,0);bb.AlwaysOnTop=false;bb.MaxDistance=60;bb.Adornee=root;bb.Parent=gui
 local back=Instance.new('Frame');back.Size=UDim2.fromScale(1,1);back.BackgroundColor3=Color3.fromRGB(15,12,20);back.BackgroundTransparency=.2;back.BorderSizePixel=0;back.Parent=bb
 Instance.new('UICorner',back).CornerRadius=UDim.new(1,0)
 local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(255,240,210);stroke.Transparency=.4;stroke.Thickness=1.5;stroke.Parent=back
 local fill=Instance.new('Frame');fill.Size=UDim2.fromScale(1,1);fill.BackgroundColor3=Color3.fromRGB(190,120,255);fill.BorderSizePixel=0;fill.Parent=back
 Instance.new('UICorner',fill).CornerRadius=UDim.new(1,0)
 b={gui=bb,fill=fill};bars[model]=b;return b
end
folder.ChildRemoved:Connect(function(m)local b=bars[m];if b then b.gui:Destroy();bars[m]=nil end end)
local function watchHits(model)
 model:GetAttributeChangedSignal('HitFlashAt'):Connect(function()
  local h=Instance.new('Highlight');h.FillColor=Color3.new(1,1,1);h.OutlineColor=Color3.new(1,1,1);h.FillTransparency=.15;h.OutlineTransparency=0;h.DepthMode=Enum.HighlightDepthMode.Occluded;h.Adornee=model;h.Parent=model
  Tween:Create(h,TweenInfo.new(.35),{FillTransparency=1,OutlineTransparency=1}):Play();task.delay(.4,function()h:Destroy()end)
  local root=model:FindFirstChild('CreatureRoot');Audio.Play('ItemImpact',root)
 end)
 -- Stunned by a thrown item: little yellow stars circle its head for a second.
 model:GetAttributeChangedSignal('StunnedVisualUntil'):Connect(function()
  local untilT=model:GetAttribute('StunnedVisualUntil');if not untilT then return end
  local _,size=model:GetBoundingBox()
  local stars={}
  for i=1,4 do local s=newPart('StunStar',Vector3.new(.45,.45,.45),Color3.fromRGB(255,226,110));s.Shape=Enum.PartType.Ball;stars[i]=s end
  local conn;conn=Run.RenderStepped:Connect(function()
   local root=model:FindFirstChild('CreatureRoot')
   if not model.Parent or not root or workspace:GetServerTimeNow()>untilT then conn:Disconnect();for _,s in stars do s:Destroy()end;return end
   local top=root.Position+Vector3.new(0,size.Y+.4,0);local t=os.clock()*5
   for i,s in stars do local a=t+i*math.pi/2;s.CFrame=CFrame.new(top+Vector3.new(math.cos(a)*1.3,math.sin(t*2+i)*.2,math.sin(a)*1.3))end
  end)
 end)
end
-- Readable warning: a mad Wraith (about to rush) gets a pale outline that shows through walls nearby.
local function watchMad(model)
 local function apply()
  local old=model:FindFirstChild('MadOutline')
  if model:GetAttribute('Mad')and not old then
   local h=Instance.new('Highlight');h.Name='MadOutline';h.FillTransparency=1;h.OutlineColor=Color3.fromRGB(205,170,255);h.OutlineTransparency=.15;h.DepthMode=Enum.HighlightDepthMode.Occluded;h.Adornee=model;h.Parent=model
  elseif not model:GetAttribute('Mad')and old then old:Destroy()end
 end
 model:GetAttributeChangedSignal('Mad'):Connect(apply);apply()
end
for _,m in folder:GetChildren()do watchHits(m);watchMad(m)end
folder.ChildAdded:Connect(function(m)watchHits(m);watchMad(m)end)

local function eyeOf(model,fallback)
 local e=model:FindFirstChild('TopEye')or model:FindFirstChild('Head')
 return e and e:IsA('BasePart')and e.Position or fallback
end
-- Curve from the eye (leaving forward along the sweep direction) to the elbow, arriving level with the sweep.
local function placeCurve(b,eye,elbow,dir,on)
 b.a0.WorldCFrame=CFrame.fromMatrix(eye,dir,Vector3.yAxis);b.a1.WorldCFrame=CFrame.fromMatrix(elbow,dir,Vector3.yAxis)
 b.curveCore.Enabled=on;b.curveGlow.Enabled=on
 b.eyeGlow.CFrame=CFrame.new(eye);b.eyeGlow.Transparency=on and .2 or .5
end
Run.RenderStepped:Connect(function()
 local now=workspace:GetServerTimeNow()
 -- RUN countdown
 local left=runDeadline-now
 if left>0 and player:GetAttribute('RunWarningUntil')then
  runFrame.Visible=true
  local n=math.ceil(left);runCount.Text=tostring(n)
  local beat=1-(left%1);runTitle.TextSize=84+math.max(0,1-beat*3)*18
  if n~=lastBeat then lastBeat=n;Audio.Play('Heartbeat')end
  if Preferences.Get('CameraMotion')then shakeUntil=math.max(shakeUntil,os.clock()+.05);shakePower=.12 end
 else runFrame.Visible=false end
 -- Lasers
 for _,model in folder:GetChildren()do
  local state=model:GetAttribute('LaserState')
  local root=model:FindFirstChild('CreatureRoot')
  if state and root then
   local b=beamFor(model)
   local h=model:GetAttribute('LaserHeight')or root.Position.Y+6.3
   local origin=Vector3.new(root.Position.X,h,root.Position.Z)
   if state=='Charge'then
    local t=1-math.clamp(((model:GetAttribute('LaserStart')or now)-now)/1.15,0,1)
    local s=.6+t*1.8+math.sin(now*40)*.12
    local eye=eyeOf(model,origin+Vector3.new(0,5,0))
    b.orb.Size=Vector3.new(s,s,s);b.orb.CFrame=CFrame.new(eye);b.orb.Transparency=.15
    placeCurve(b,eye,origin,Vector3.new(0,0,-1),false)
    b.core.Transparency=1;b.glow.Transparency=1;b.tip.CFrame=CFrame.new(origin)
    b.tip.ParticleEmitter.Enabled=false
    if not b.chargeSound then
     -- Only the clip's rising tail, timed to end as the beam fires (the charge lasts ~1.15 s).
     local s=laserSound(b.orb,LASER_CHARGE_SOUND,.32,1.3,false);b.chargeSound=s
     local fireAt=model:GetAttribute('LaserStart')or now
     task.spawn(function()
      local t=os.clock();while s.Parent and not s.IsLoaded and os.clock()-t<.5 do task.wait()end
      local left=math.max(.2,fireAt-workspace:GetServerTimeNow())
      if s.Parent and s.TimeLength>0 then s.TimePosition=math.max(0,s.TimeLength-left*1.3)end
     end)
    end
   else
    local a=(model:GetAttribute('LaserYaw0')or 0)+(model:GetAttribute('LaserSpin')or 0)*math.max(0,now-(model:GetAttribute('LaserStart')or now))
    local dir=Vector3.new(math.sin(a),0,-math.cos(a))
    local mansion=workspace:FindFirstChild('Mansion');local collision=mansion and mansion:FindFirstChild('Collision')
    params.FilterDescendantsInstances={collision}
    local range=model:GetAttribute('LaserRange')or 58
    local eye=eyeOf(model,origin+Vector3.new(0,5,0))
    local elbow=origin+dir*3.2
    local hit=collision and workspace:Raycast(elbow,dir*(range-3.2),params)
    local length=hit and (hit.Position-elbow).Magnitude or range-3.2
    -- Closets stop the beam (same rule as the server's kill check).
    local inter=mansion and mansion:FindFirstChild('Interactive');local blockers={mansion and mansion:FindFirstChild('Closets')}
    if inter then for _,d in inter:GetChildren()do if d:GetAttribute('Closet')then table.insert(blockers,d)end end end
    closetRay.FilterDescendantsInstances=blockers
    local box=workspace:Raycast(elbow,dir*length,closetRay)
    if box then hit=box;length=(box.Position-elbow).Magnitude end
    origin=elbow
    local mid=origin+dir*length/2;local cf=CFrame.lookAt(mid,mid+dir)
    local pulse=1+math.sin(now*55)*.12
    b.core.Size=Vector3.new(.32*pulse,.32*pulse,length);b.core.CFrame=cf;b.core.Transparency=0
    b.glow.Size=Vector3.new(1.05*pulse,1.05*pulse,length);b.glow.CFrame=cf;b.glow.Transparency=.55
    b.orb.Size=Vector3.new(1.1,1.1,1.1)*pulse;b.orb.CFrame=CFrame.new(eye)
    placeCurve(b,eye,elbow,dir,true)
    b.tip.CFrame=CFrame.lookAt(origin+dir*(length-.2),origin);b.tip.ParticleEmitter.Enabled=hit~=nil
    if b.chargeSound then b.chargeSound:Destroy();b.chargeSound=nil end
    if not b.humSound then b.humSound=laserSound(b.orb,LASER_LOOP_SOUND,.35,1,true);b.tipSound=laserSound(b.tip,LASER_LOOP_SOUND,.16,1.15,true)end
   end
  elseif beams[model]then dropBeam(model)end
  -- Health bar once thrown items have hurt it
  local hp=model:GetAttribute('GearHealth')
  if hp and hp<100 and hp>0 then
   local bar=barFor(model);if bar then bar.fill.Size=UDim2.fromScale(math.clamp(hp/100,0,1),1)end
  end
 end
end)

-- ===== Lonely Mittens and the Wind-Up Dancer (Monsters build 2026-10-27) =====
-- Mittens: cold lavender edges + a whisper while you are alone near it (server lease LonelyUntil); led by the hand
-- (HandHeldBy) = movement locked + banner, and a HELP! marker over you on every teammate's screen.
-- Dancer: her music-box tune rides on the model (slows as she winds down, silent while she looks); FREEZE! while she looks
-- near you; 'spotted' banner; the twirl leaves you dizzy. First meeting of each: a name + rule banner.
local chill=Instance.new('Frame');chill.Name='LonelyChill';chill.Size=UDim2.fromScale(1,1);chill.BackgroundTransparency=1;chill.Parent=gui
local chillEdges={}
for i,spec in {{UDim2.fromScale(1,.24),UDim2.fromScale(0,0),90},{UDim2.fromScale(1,.24),UDim2.fromScale(0,.76),-90},{UDim2.fromScale(.18,1),UDim2.fromScale(0,0),0},{UDim2.fromScale(.18,1),UDim2.fromScale(.82,0),180}}do
 local f=Instance.new('Frame');f.Size=spec[1];f.Position=spec[2];f.BackgroundColor3=Color3.fromRGB(150,160,255);f.BorderSizePixel=0;f.BackgroundTransparency=1;f.Parent=chill
 local g=Instance.new('UIGradient');g.Rotation=spec[3];g.Transparency=NumberSequence.new(0,1);g.Parent=f
 chillEdges[i]=f
end
local chillAlpha,nextWhisper=0,0
local freeze=Instance.new('TextLabel');freeze.Name='DancerFreeze';freeze.AnchorPoint=Vector2.new(.5,.5);freeze.Position=UDim2.fromScale(.5,.24);freeze.Size=UDim2.fromScale(.6,.11)
freeze.BackgroundTransparency=1;freeze.Font=Enum.Font.FredokaOne;freeze.TextScaled=true;freeze.TextColor3=Color3.fromRGB(190,240,255);freeze.TextStrokeTransparency=0;freeze.TextStrokeColor3=Color3.fromRGB(20,10,40);freeze.Visible=false;freeze.Parent=gui
local freezeSize=Instance.new('UITextSizeConstraint');freezeSize.MaxTextSize=80;freezeSize.MinTextSize=28;freezeSize.Parent=freeze
local RULES={Mittens={'NEW: LONELY MITTENS','Never wander off alone!'},Dancer={'NEW: THE WIND-UP DANCER','Music stops? FREEZE!'},Yoyo={'NEW: THE YO-YO KID','He wants his toys back. Keep moving!'}}
local seenKinds,tunes,helpMarks={},{},{}
local dizzyUntil=0
local lastDance,nextPad={},{}
local DANCER_CREEPY,MITTENS_STEPS=60,45
player:GetAttributeChangedSignal('HandHeldBy'):Connect(function()
 if player:GetAttribute('HandHeldBy')then
  say('IT HAS YOUR HAND! Get help!',3)
  player:SetAttribute('DreadKickAt',os.clock());player:SetAttribute('FlashlightStutterUntil',os.clock()+1.4) -- DreadLayer pulse + beam stutter
  CAS:BindActionAtPriority('MonsterHandMovement',function()return Enum.ContextActionResult.Sink end,false,2900,unpack(Enum.PlayerActions:GetEnumItems()))
 else CAS:UnbindAction('MonsterHandMovement')end
end)
event.OnClientEvent:Connect(function(action,a)
 if action=='freed'then say('Freed! It let go.',2.2)
 elseif action=='rescuer'then say('You saved '..tostring(a)..'!',2.2)
 elseif action=='spotted'then say('SHE SAW YOU MOVE!',2.4);Audio.Play('StingChoir');shakeUntil=os.clock()+.3;shakePower=.25;player:SetAttribute('DreadKickAt',os.clock())
 elseif action=='twirl'then dizzyUntil=(tonumber(a)or workspace:GetServerTimeNow())+2.5
 end
end)
-- Dizzy after the twirl: a slow roll and sway that fades out (off when the player turned camera motion off).
Run:BindToRenderStep('DancerDizzy',Enum.RenderPriority.Camera.Value+4,function()
 local left=dizzyUntil-workspace:GetServerTimeNow()
 if left<=0 or not Preferences.Get('CameraMotion')then return end
 local k=math.clamp(left/2.5,0,1);local t=os.clock()
 workspace.CurrentCamera.CFrame*=CFrame.Angles(math.sin(t*2.1)*.05*k,math.sin(t*1.7)*.06*k,math.sin(t*2.6)*.14*k)
end)
Run.Heartbeat:Connect(function(dt)
 local now=workspace:GetServerTimeNow()
 -- Lonely chill
 local lonely=(player:GetAttribute('LonelyUntil')or 0)>now and not player:GetAttribute('HandHeldBy')
 chillAlpha+=((lonely and .5 or 0)-chillAlpha)*(1-math.exp(-dt*(lonely and 1.5 or 3)))
 for _,f in chillEdges do f.BackgroundTransparency=1-chillAlpha end
 if lonely and os.clock()>nextWhisper then nextWhisper=os.clock()+math.random(6,9);Audio.Play('ScareWhisper',nil,{volume=.22})end
 -- HELP! over a teammate whose hand is held (through walls, so the team can find them)
 for _,q in Players:GetPlayers()do
  local head=q.Character and q.Character:FindFirstChild('Head')
  local held=q~=player and q:GetAttribute('HandHeldBy')~=nil and head~=nil
  local mark=helpMarks[q]
  if held and not mark then
   local bb=Instance.new('BillboardGui');bb.Name='HandHelpMark';bb.Size=UDim2.fromOffset(170,46);bb.StudsOffsetWorldSpace=Vector3.new(0,3,0);bb.AlwaysOnTop=true;bb.MaxDistance=160;bb.Adornee=head;bb.Parent=gui
   local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.Text='HELP! Run to them';t.TextColor3=Color3.fromRGB(255,236,150);t.TextStrokeTransparency=0;t.Parent=bb
   helpMarks[q]=bb
  elseif not held and mark then mark:Destroy();helpMarks[q]=nil end
 end
 for q,mark in helpMarks do if not q.Parent then mark:Destroy();helpMarks[q]=nil end end
 -- Dancer tunes, FREEZE, first-meeting banners
 local myRoot=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 local cue
 for _,m in folder:GetChildren()do
  local kind=m:GetAttribute('CreatureKind');local root=m:FindFirstChild('CreatureRoot')
  local near=root and myRoot and (root.Position-myRoot.Position).Magnitude<60
  if near and RULES[kind]and not seenKinds[kind]then
   seenKinds[kind]=true;local r=RULES[kind];say(r[1],2.2);task.delay(2.4,function()say(r[2],3)end)
  end
  local dist=root and myRoot and (root.Position-myRoot.Position).Magnitude or math.huge
  -- Lonely Mittens: while you are alone you hear its soft padding steps behind you, out of step with yours, before you see it.
  if kind=='Mittens'and root and lonely and m:GetAttribute('Walking')and dist>8 and dist<MITTENS_STEPS and os.clock()>(nextPad[m]or 0)then
   nextPad[m]=os.clock()+math.random(70,110)/100
   local pad=Audio.Play('PlayerFootstep',root.Position,{volume=.16*(1-dist/MITTENS_STEPS)+.04,speed=.72})
   if pad then local eq=Instance.new('EqualizerSoundEffect');eq.HighGain=-14;eq.MidGain=-3;eq.LowGain=2;eq.Parent=pad end
  end
  if kind=='Dancer'and root then
   -- The tune stops and her porcelain neck creaks round: within reach of her look your own flashlight stutters out.
   local st=m:GetAttribute('DanceState')
   if st=='Look'and lastDance[m]~='Look'and dist<DANCER_CREEPY then
    Audio.Play('StingCreak',root,{volume=.45,speed=.55});player:SetAttribute('FlashlightStutterUntil',os.clock()+1.2)
   end
   lastDance[m]=st
   local t=tunes[m]or{retry=0};tunes[m]=t
   if (not t.sound or not t.sound.Parent)and os.clock()>t.retry then t.retry=os.clock()+1;t.sound=Audio.Play('MusicBox',root,{loop=true,volume=.35})end
   local state=m:GetAttribute('DanceState');local left=(m:GetAttribute('DanceUntil')or now)-now
   if t.sound and t.sound.Parent then
    local speed,volume=1,.35
    if state=='Winding'then local k=math.clamp(left/1.6,0,1);speed=.45+.55*k;volume=.35*(.4+.6*k)
    elseif state=='Look'then speed=.45;volume=0 end
    t.sound.PlaybackSpeed=speed;t.sound.Volume=volume
   end
   if near and state=='Look'then cue='look' elseif near and state=='Winding'and cue==nil then cue='wind' end
  end
 end
 for m,t in tunes do if not m.Parent then if t.sound then Audio.Stop(t.sound)end;tunes[m]=nil;lastDance[m]=nil end end
 for m in nextPad do if not m.Parent then nextPad[m]=nil end end
 local inMission=player:GetAttribute('MissionActive')==true
 freeze.Visible=inMission and cue~=nil
 if cue=='look'then freeze.Text='FREEZE!';freeze.TextTransparency=0;freeze.Rotation=math.sin(os.clock()*10)*2
 elseif cue=='wind'then freeze.Text='...the music is slowing';freeze.TextTransparency=.25;freeze.Rotation=0 end
end)
