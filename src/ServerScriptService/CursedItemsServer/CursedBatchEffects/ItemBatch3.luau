-- Item batch 3 (2026-10-01): held leases, grab effects and level-long curses.
-- Owned by CursedBatchEffects: it calls Pickup(p,m) on every pickup and ClearPlayer(p) on level end / leave.
-- Clients render the voice, camera and face parts from the attributes set here.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Tween=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local M={}

-- Held items refresh a short lease (server time); the effect ends within half a second of letting go.
local LEASES={HeliumTank='HeliumUntil',GarlicBulb='GarlicUntil',Lemon='LemonUntil',PinocchioPuppet='PinocchioUntil',Hourglass='HourglassUntil',SpinningTop='SpinUntil',MusicBox='MusicBoxUntil',Kazoo='KazooUntil'}
-- Everything this module may leave on a player; cleared at level end.
local KEYS={'HeliumUntil','GarlicUntil','LemonUntil','PinocchioUntil','HourglassUntil','SpinUntil','MusicBoxUntil','KazooUntil','ClownNosed','Vampired','BlackCatCurse','PhotoOf','Confettied'}
-- Face anchor in Head space (+Z = face front): above the moustache (y .55) and between the eye stalks.
local NOSE_ANCHOR=CFrame.new(0,1.0,.42)
local NOSE_STEP,NOSE_MAX,NOSE_GROW_EVERY=.35,3.2,1.5
local GARLIC_RADIUS=11
local MUSIC_CALM_RADIUS=30
local PALE=Color3.fromRGB(222,222,232)
local VAMPIRE_EYES=Color3.fromRGB(255,25,35)
local fx={}

local function living(p)
 local c=p and p.Parent and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if h and h.Health>0 and p:GetAttribute('MissionActive')==true then return c end
end
local function slot(p) fx[p]=fx[p] or {};return fx[p] end
local function drop(t,k) local x=t[k];if typeof(x)=='Instance'then x:Destroy()elseif typeof(x)=='RBXScriptConnection'then x:Disconnect()end;t[k]=nil end
local function part(name,size,color,material,shape)
 local x=Instance.new('Part');x.Name=name;x.Size=size;x.Color=color;x.Material=material or Enum.Material.SmoothPlastic
 x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.Massless=true;x.CastShadow=false
 if shape then x.Shape=shape end;return x
end
local function weld(x,to,c0) local w=Instance.new('Weld');w.Name='Batch3Weld';w.Part0=to;w.Part1=x;w.C0=c0 or CFrame.identity;w.Parent=x;return w end

-- Noses: clown nose (level) wins over the Pinocchio nose (while held).
local function setNose(p,c,kind,length)
 local s=slot(p);local head=c:FindFirstChild('Head')
 if not head then return end
 if s.noseKind~=kind or not s.nose or not s.nose.Parent then
  drop(s,'nose');s.noseKind=kind
  if kind=='clown'then
   s.nose=part('ClownNoseWorn',Vector3.new(.44,.44,.44),Color3.fromRGB(225,20,30),Enum.Material.Glass,Enum.PartType.Ball)
   weld(s.nose,head,NOSE_ANCHOR*CFrame.new(0,0,.12))
  elseif kind=='wood'then
   s.nose=part('PinocchioNose',Vector3.new(.3,.17,.17),Color3.fromRGB(225,180,130),Enum.Material.SmoothPlastic,Enum.PartType.Cylinder)
   weld(s.nose,head,NOSE_ANCHOR)
  else return end
  s.nose.Parent=c
 end
 if kind=='wood'then
  local len=math.max(.3,length);s.nose.Size=Vector3.new(len,.17-.05*math.min(1,len/NOSE_MAX),.17-.05*math.min(1,len/NOSE_MAX))
  local w=s.nose:FindFirstChild('Batch3Weld');if w then w.C0=NOSE_ANCHOR*CFrame.new(0,0,len/2)*CFrame.Angles(0,math.pi/2,0)end
 end
end

-- Vampire: fangs on two upper teeth, pale body, glowing red pupils. Re-applied after a respawn.
local function applyVampire(p,c)
 local s=slot(p);local head=c:FindFirstChild('Head');if not head then return end
 if not s.fangs or not s.fangs.Parent then
  drop(s,'fangs');local f=Instance.new('Folder');f.Name='VampireFangs';f.Parent=c;s.fangs=f
  for _,n in ipairs({'UpperTooth2','UpperTooth6'})do
   local tooth=head:FindFirstChild(n)
   if tooth then local fang=part('Fang',Vector3.new(.26,.08,.08),Color3.fromRGB(250,250,245),Enum.Material.SmoothPlastic,Enum.PartType.Cylinder);weld(fang,tooth,CFrame.new(0,-.13,.03)*CFrame.Angles(0,0,math.pi/2));fang.Parent=f end
  end
  for _,side in ipairs({'Left','Right'})do
   local eye=head:FindFirstChild(side..'Eyeball')
   if eye then local l=Instance.new('PointLight');l.Name='VampireGlow';l.Color=VAMPIRE_EYES;l.Range=7;l.Brightness=2;l.Parent=eye;l:SetAttribute('Batch3',true)end
  end
 end
 for _,x in ipairs(c:GetDescendants())do
  if x:IsA('BasePart')then
   local region=x:GetAttribute('ColourRegion')
   if region=='body'or region=='feet'or region=='stalks'or region=='rings'then
    -- Mall tint owns the body while active; vampire still owns fangs and pupil glow.
    if p:GetAttribute('SelfTanned')==true or workspace:GetServerTimeNow()<(p:GetAttribute('MoodRingUntil')or 0)then continue end
    if x:GetAttribute('ColourOverride')~=PALE then x:SetAttribute('ColourOverride',PALE);x.Color=PALE end
    local surface=x:FindFirstChild('UniformBodySurface');if surface and surface.Color~=PALE then surface.Color=PALE end
   elseif region=='pupil'then
    if x:GetAttribute('ColourOverride')~=VAMPIRE_EYES then x:SetAttribute('VampireMaterial',x.Material.Name);x:SetAttribute('ColourOverride',VAMPIRE_EYES);x.Color=VAMPIRE_EYES;x.Material=Enum.Material.Neon end
   end
  end
 end
end
local function removeVampire(p)
 local s=slot(p);drop(s,'fangs')
 local c=p.Character;if not c then return end
 for _,x in ipairs(c:GetDescendants())do
  if x:IsA('PointLight')and x:GetAttribute('Batch3')then x:Destroy()
  elseif x:IsA('BasePart')and(x:GetAttribute('ColourOverride')==PALE or x:GetAttribute('ColourOverride')==VAMPIRE_EYES)then
   x:SetAttribute('ColourOverride',nil)
   local m=x:GetAttribute('VampireMaterial');if m then x.Material=Enum.Material[m];x:SetAttribute('VampireMaterial',nil)end
  end
 end
 -- CharacterAppearanceServer repaints colours (and body surfaces) on any descendant change.
 local nudge=Instance.new('Folder');nudge.Name='RepaintNudge';nudge.Parent=c;task.defer(function()nudge:Destroy()end)
end

-- Garlic: green stink cloud on the holder.
local function stink(p,c)
 local s=slot(p);if s.stink and s.stink.Parent then return end
 drop(s,'stink');local torso=c:FindFirstChild('UpperTorso');if not torso then return end
 local a=Instance.new('Attachment');a.Name='GarlicStink';a.Position=Vector3.new(0,torso.Size.Y*.4,0);a.Parent=torso
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/smoke_main.dds';e.Color=ColorSequence.new(Color3.fromRGB(150,200,70),Color3.fromRGB(110,150,50))
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.8),NumberSequenceKeypoint.new(1,2.4)});e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,1)})
 e.Lifetime=NumberRange.new(1.4,2.4);e.Rate=9;e.Speed=NumberRange.new(.6,1.6);e.SpreadAngle=Vector2.new(70,70);e.Acceleration=Vector3.new(0,1.2,0);e.LightInfluence=.4;e.Parent=a
 s.stink=a
end

-- Confetti: a burst, then a few stuck pieces and a light sprinkle for the rest of the level.
local CONFETTI={Color3.fromRGB(240,80,80),Color3.fromRGB(60,170,240),Color3.fromRGB(120,220,90),Color3.fromRGB(250,210,60),Color3.fromRGB(230,90,200)}
local function burst(at)
 local a=Instance.new('Attachment');a.Parent=at
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,CONFETTI[1]),ColorSequenceKeypoint.new(.33,CONFETTI[2]),ColorSequenceKeypoint.new(.66,CONFETTI[3]),ColorSequenceKeypoint.new(1,CONFETTI[4])})
 e.Size=NumberSequence.new(.25,.15);e.Lifetime=NumberRange.new(1,2);e.Speed=NumberRange.new(10,20);e.SpreadAngle=Vector2.new(50,50);e.Acceleration=Vector3.new(0,-18,0);e.Drag=1.5;e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-300,300);e.Rate=0;e.Parent=a
 e:Emit(90);task.delay(2.5,function()a:Destroy()end)
end
local function confetti(p,c)
 local s=slot(p);if s.confetti and s.confetti.Parent then return end
 drop(s,'confetti');local torso=c:FindFirstChild('UpperTorso');if not torso then return end
 local f=Instance.new('Folder');f.Name='ConfettiCovered';f.Parent=c;s.confetti=f
 local rng=Random.new(p.UserId)
 for i=1,14 do
  local dir=Vector3.new(rng:NextNumber(-1,1),rng:NextNumber(-.3,1),rng:NextNumber(-1,1)).Unit
  local bit=part('Confetti',Vector3.new(.16,.16,.03),CONFETTI[(i-1)%#CONFETTI+1]);bit.Parent=f
  weld(bit,torso,CFrame.new(dir*torso.Size*.46)*CFrame.Angles(rng:NextNumber(0,6),rng:NextNumber(0,6),rng:NextNumber(0,6)))
 end
 local a=Instance.new('Attachment');a.Position=Vector3.new(0,torso.Size.Y*.45,0);a.Parent=torso
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(CONFETTI[2],CONFETTI[4]);e.Size=NumberSequence.new(.12);e.Lifetime=NumberRange.new(1,1.6);e.Rate=3;e.Speed=NumberRange.new(.5,1.5);e.Acceleration=Vector3.new(0,-6,0);e.SpreadAngle=Vector2.new(80,80);e.Parent=a
 local tag=Instance.new('ObjectValue');tag.Name='SprinkleAttachment';tag.Value=a;tag.Parent=f
 f.Destroying:Connect(function()if a.Parent then a:Destroy()end end)
end

-- Black cat: a small black cat that trails the player along the floor.
local followers=workspace:FindFirstChild('CursedFollowers')or Instance.new('Folder');followers.Name='CursedFollowers';followers.Parent=workspace
local function cat(p,c)
 local s=slot(p);if s.cat and s.cat.Parent then return end
 drop(s,'cat');local kit=SS:FindFirstChild('CursedItemKit')and SS.CursedItemKit:FindFirstChild('BlackCatStatue');if not kit then return end
 local m=kit:Clone();m.Name='BlackCatFollower_'..p.UserId;m:SetAttribute('ItemId',nil);m:SetAttribute('Kind',nil)
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')then x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;if x.Name:find('__Base')then x.Transparency=1 end end end
 m:ScaleTo(.8);local root=c:FindFirstChild('HumanoidRootPart');if root then m:PivotTo(root.CFrame*CFrame.new(1.5,-2.5,3))end
 m.Parent=followers;s.cat=m;s.catPos=nil
end
local catRay=RaycastParams.new();catRay.FilterType=Enum.RaycastFilterType.Exclude

-- Cursed photo: a polaroid snapshot of a teammate (or yourself when alone) stuck on the stomach.
local function hideTattoo(c,hidden)
 local cos=c:FindFirstChild('ProgressCosmetics');local t=cos and cos:FindFirstChild('CosmeticTattoo')
 if t then for _,d in ipairs(t:GetDescendants())do if d:IsA('Decal')then if hidden then d:SetAttribute('PhotoShown',d:GetAttribute('PhotoShown')or d.Transparency);d.Transparency=1 elseif d:GetAttribute('PhotoShown')then d.Transparency=d:GetAttribute('PhotoShown');d:SetAttribute('PhotoShown',nil)end end end end
end
local function photo(p,c,replacePrevious)
 local s=slot(p);if s.photo and s.photo.Parent and not replacePrevious then return s.photo end
 local torso=c:FindFirstChild('UpperTorso');local root=c:FindFirstChild('HumanoidRootPart');if not torso or not root then return end
 drop(s,'photo')
 local subject=Players:GetPlayerByUserId(p:GetAttribute('PhotoOf')or 0)or p
 local card=part('CursedSnapshot',Vector3.new(1.05,1.25,.04),Color3.fromRGB(245,243,236))
 card.CFrame=CFrame.new(torso.Position)*root.CFrame.Rotation*CFrame.new(0,-.35,-.86)*CFrame.Angles(0,0,math.rad(-6))
 local w=Instance.new('WeldConstraint');w.Part0=torso;w.Part1=card;w.Parent=card
 local gui=Instance.new('SurfaceGui');gui.Name='PhotoGui';gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=160;gui.LightInfluence=.6;gui.Parent=card
 local view=Instance.new('ViewportFrame');view.Size=UDim2.new(1,-16,.78,-12);view.Position=UDim2.fromOffset(8,8);view.BackgroundColor3=Color3.fromRGB(40,36,44);view.Ambient=Color3.fromRGB(170,160,150);view.LightColor=Color3.fromRGB(255,240,220);view.Parent=gui
 local caption=Instance.new('TextLabel');caption.BackgroundTransparency=1;caption.Size=UDim2.new(1,-16,.2,0);caption.Position=UDim2.new(0,8,.8,0);caption.Font=Enum.Font.PermanentMarker;caption.TextScaled=true;caption.TextColor3=Color3.fromRGB(60,40,50);caption.Text=subject.DisplayName;caption.Parent=gui
 local sc=subject.Character
 if sc and sc:FindFirstChild('Head')then
  local was=sc.Archivable;sc.Archivable=true;local copy=sc:Clone();sc.Archivable=was
  if copy then
   for _,d in ipairs(copy:GetDescendants())do if d:IsA('LuaSourceContainer')or d:IsA('Sound')or d:IsA('ParticleEmitter')or d:IsA('Light')or d:IsA('Humanoid')or d:IsA('BillboardGui')or d:IsA('SurfaceGui')or d:IsA('Attachment')then d:Destroy()elseif d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false end end
   local world=Instance.new('WorldModel');world.Parent=view;copy.Parent=world
   local head=copy:FindFirstChild('Head');local cam=Instance.new('Camera');cam.FieldOfView=38
   local face=head.CFrame.LookVector;local up=head.CFrame.UpVector
   -- The head's +Z is the face front; LookVector is -Z, so look from +Z.
   local front=-face;local focus=head.Position+up*.8
   cam.CFrame=CFrame.lookAt(focus+front*5.2+up*.3,focus);cam.Parent=view;view.CurrentCamera=cam
  end
 end
 local image=Instance.new('ImageLabel');image.Name='LivePhoto';image.Visible=false;image.ZIndex=2;image.Size=UDim2.new(1,-16,.78,-12);image.Position=UDim2.fromOffset(8,8);image.BackgroundColor3=Color3.fromRGB(40,36,44);image.ScaleType=Enum.ScaleType.Crop;image.Parent=gui
 card:SetAttribute('PhotoOwner',p.UserId);card:SetAttribute('PhotoSubject',subject.UserId)
 card.Parent=c;s.photo=card;hideTattoo(c,true)
 local remote=RS:FindFirstChild('CursedEvent');if remote then remote:FireClient(p,'cameraPrint',card,subject)end
 return card
end

-- A real, replicated print exits the slot before falling; the stomach card remains the curse.
local function ejectPhoto(camera,snapshot)
 if not camera.PrimaryPart or not snapshot then return end
 local print=snapshot:Clone();print.Name='EjectedCameraPhoto'
 for _,joint in ipairs(print:GetChildren())do if joint:IsA('WeldConstraint')or joint:IsA('JointInstance')then joint:Destroy()end end
 print.Anchored=false;print.Massless=true;print.CanCollide=false;print.CanTouch=false;print.CanQuery=false
 print:SetAttribute('CameraPhoto',true)
 local root=camera.PrimaryPart
 local start=CFrame.new(0,-root.Size.Y*.25,-root.Size.Z*.5-.06)*CFrame.Angles(math.rad(-12),0,0)
 print.CFrame=root.CFrame*start;print.Parent=workspace
 local weld=Instance.new('Weld');weld.Name='PhotoEjection';weld.Part0=root;weld.Part1=print;weld.C0=start;weld.Parent=print
 Debris:AddItem(print,20)
 local tween=Tween:Create(weld,TweenInfo.new(.65,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{C0=start*CFrame.new(0,-1.1,0)})
 tween:Play()
 task.delay(.85,function()
  if not print.Parent then return end
  local cf=print.CFrame;weld:Destroy();print.CFrame=cf;print.Massless=false;print.CanCollide=true
  print.AssemblyLinearVelocity=root.Parent and root.AssemblyLinearVelocity+root.CFrame.LookVector*1.5 or Vector3.new(0,-1,0)
  print.AssemblyAngularVelocity=Vector3.new(0,.8,.4)
 end)
 camera:SetAttribute('PhotoPrinted',true)
end

-- One-shot sounds when these items are grabbed (catalog cues in GameplaySoundCatalog).
local GRAB_CUES={HeliumTank='HeliumHiss',Anvil='AnvilClang',Hourglass='SandSlide',ClownNose='ClownHonk'}
local TOOTH_PILLOW_MAX_TEETH,TOOTH_PILLOW_TOOTH_VALUE=5,12
function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId');local c=living(p)
 if not c and m:GetAttribute('LobbyToy')==true then
  local state=RS:FindFirstChild('LobbyState');local char=p.Character;local h=char and char:FindFirstChildOfClass('Humanoid')
  if p.Parent and p:GetAttribute('MissionActive')~=true and p:GetAttribute('LobbyReady')==true and state and state:GetAttribute('Mode')=='Menu' and h and h.Health>0 then c=char end
 end
 if not c then return end
 local head=c:FindFirstChild('Head')
 if GRAB_CUES[id]and m.PrimaryPart then Audio.Play(GRAB_CUES[id],m.PrimaryPart)end
 if id=='ToothPillow'then
  local broken=p:GetAttribute('BrokenTeeth')or 0
  if broken<14 then
   p:SetAttribute('BrokenTeeth',broken+1);if head then Audio.Play('GlassImpact',head)end
   -- The bonus is capped on the pillow itself: more players, deaths or revives (which reset BrokenTeeth)
   -- must never turn one pillow into an endless money source.
   local teeth=m:GetAttribute('PillowTeeth')or 0
   if teeth<TOOTH_PILLOW_MAX_TEETH then
    m:SetAttribute('PillowTeeth',teeth+1)
    m:SetAttribute('Value',(m:GetAttribute('Value')or 0)+TOOTH_PILLOW_TOOTH_VALUE);m:SetAttribute('LootValue',m:GetAttribute('Value'))
   end
  end
 elseif id=='ClownNose'then p:SetAttribute('ClownNosed',true)
 elseif id=='VampireTeeth'then p:SetAttribute('Vampired',true)
 elseif id=='BlackCatStatue'then p:SetAttribute('BlackCatCurse',true)
 elseif id=='PartyPopper'then
  if m.PrimaryPart then burst(m.PrimaryPart);Audio.Play('JarPop',m.PrimaryPart)end;p:SetAttribute('Confettied',true)
 elseif id=='GlueBottle'then
  m:SetAttribute('GluedUntil',os.clock()+10)
 elseif id=='CursedPhoto'then
  -- Film is spent on this physical item, not on the holder. Keep it in inventory for sale.
  if m:GetAttribute('CameraSpent')then return end
  local others={}
  for _,q in ipairs(Players:GetPlayers())do if q~=p and living(q)then table.insert(others,q)end end
  local subject=#others>0 and others[math.random(#others)]or p
  local previousSubject=p:GetAttribute('PhotoOf')
  p:SetAttribute('PhotoOf',subject.UserId)
  local card=photo(p,c,true)
  if not card then p:SetAttribute('PhotoOf',previousSubject);return end
  m:SetAttribute('CameraSpent',true)
  if m.PrimaryPart then
   local l=Instance.new('PointLight');l.Name='CameraFlash';l.Brightness=3;l.Range=10;l.Parent=m.PrimaryPart;Audio.Play('CameraShutter',m.PrimaryPart)
   task.delay(.12,function()if l.Parent then l:Destroy()end end)
  end
  ejectPhoto(m,card)
 end
end

function M.ClearPlayer(p)
 local s=fx[p]
 if s then
  removeVampire(p)
  for _,k in ipairs({'nose','stink','confetti','cat','photo','honk'})do drop(s,k)end
  if p.Character then hideTattoo(p.Character,false)end
  fx[p]=nil
 end
 for _,k in ipairs(KEYS)do p:SetAttribute(k,nil)end
end
Players.PlayerRemoving:Connect(function(p)local s=fx[p];if s then drop(s,'cat')end;fx[p]=nil end)

local acc=0
local function lobbyOnly()
 local state=RS:FindFirstChild('LobbyState')
 if not state or state:GetAttribute('Mode')~='Menu' then return false end
 for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('MissionActive')==true then return false end end
 return true
end
Run.Heartbeat:Connect(function(dt)
 if lobbyOnly()then return end
 -- Black cats follow every frame (smoothly, along the floor behind the player).
 for p,s in pairs(fx)do
  local cm=s.cat
  if cm and cm.Parent then
   local c=living(p);local root=c and c:FindFirstChild('HumanoidRootPart')
   if root then
    local goal=root.Position-root.CFrame.LookVector*3.2+root.CFrame.RightVector*1.4
    catRay.FilterDescendantsInstances={c,followers}
    local hit=workspace:Raycast(goal+Vector3.new(0,3,0),Vector3.new(0,-12,0),catRay)
    if hit then goal=Vector3.new(goal.X,hit.Position.Y,goal.Z)else goal=Vector3.new(goal.X,root.Position.Y-2.9,goal.Z)end
    s.catPos=s.catPos and s.catPos:Lerp(goal,math.clamp(dt*4,0,1))or goal
    local look=Vector3.new(root.Position.X-s.catPos.X,0,root.Position.Z-s.catPos.Z)
    local hop=math.abs(math.sin(os.clock()*9))*.12*math.clamp((goal-s.catPos).Magnitude,0,1)
    local size=cm:GetExtentsSize()
    cm:PivotTo(CFrame.lookAt(s.catPos+Vector3.new(0,size.Y/2+hop,0),s.catPos+Vector3.new(0,size.Y/2,0)+(look.Magnitude>.01 and look.Unit or Vector3.zAxis)))
   end
  end
 end
 acc+=dt;if acc<.25 then return end;acc=0
 local now=workspace:GetServerTimeNow();local clock=os.clock()
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 local holding={}
 if interactive then
  for _,m in ipairs(interactive:GetChildren())do
   local id=m:GetAttribute('ItemId')or''
   local key=LEASES[id]
   local p=key and Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
   if p and living(p)then
    p:SetAttribute(key,math.max(p:GetAttribute(key)or 0,now+.5));holding[p]=holding[p]or {};holding[p][id]=m
   end
   -- Music box: plays while held and still; sprinting stops it. Creatures nearby are lulled.
   if id=='MusicBox'and m.PrimaryPart then
    local song=m.PrimaryPart:FindFirstChild('MusicBoxSong')
    if not song then song=Instance.new('Sound');song.Name='MusicBoxSong';song.SoundId='rbxassetid://9047796475';song.Looped=true;song.Volume=.45;song.RollOffMaxDistance=55;song.Parent=m.PrimaryPart end
    local root=p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
    local speed=root and Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude or 0
    local playing=p~=nil and living(p)~=nil and speed<17
    if playing and not song.IsPlaying then song:Resume();if song.TimePosition==0 then song:Play()end elseif not playing and song.IsPlaying then song:Pause()end
    m:SetAttribute('MusicPlaying',playing)
    if playing then
     local creatures=workspace:FindFirstChild('RoamingCreatures')
     if creatures then for _,n in ipairs(creatures:GetChildren())do if n.PrimaryPart and(n.PrimaryPart.Position-m.PrimaryPart.Position).Magnitude<MUSIC_CALM_RADIUS then n:SetAttribute('CalmUntil',math.max(n:GetAttribute('CalmUntil')or 0,clock+.6))end end end
    end
   end
  end
 end
 for _,p in ipairs(Players:GetPlayers())do
  local c=living(p);local s=fx[p]
  if c then
   local held=holding[p]or {}
   -- Garlic: holder stinks, teammates close by tear up.
   if held.GarlicBulb then
    stink(p,c)
    local root=c:FindFirstChild('HumanoidRootPart')
    for _,q in ipairs(Players:GetPlayers())do
     local qc=q~=p and living(q);local qr=qc and qc:FindFirstChild('HumanoidRootPart')
     if root and qr and(qr.Position-root.Position).Magnitude<GARLIC_RADIUS then q:SetAttribute('CryingUntil',math.max(q:GetAttribute('CryingUntil')or 0,now+.6))end
    end
   elseif s then drop(s,'stink')end
   -- Noses.
   s=slot(p)
   if p:GetAttribute('ClownNosed')then setNose(p,c,'clown')
   else
    s.noseLen=s.noseLen or 0
    if held.PinocchioPuppet then
     if clock>=(s.noseGrowAt or 0)then s.noseGrowAt=clock+NOSE_GROW_EVERY;s.noseLen=math.min(NOSE_MAX,s.noseLen+NOSE_STEP)end
    else s.noseLen=math.max(0,s.noseLen-.2);s.noseGrowAt=nil end
    if s.noseLen>0 then setNose(p,c,'wood',s.noseLen)else drop(s,'nose');s.noseKind=nil end
   end
   -- Clown honk on every jump.
   if p:GetAttribute('ClownNosed')and not(s.honk and s.honkChar==c)then
    drop(s,'honk');local h=c:FindFirstChildOfClass('Humanoid');s.honkChar=c
    s.honk=h.StateChanged:Connect(function(_,new)
     if new==Enum.HumanoidStateType.Jumping and os.clock()-(s.honkAt or 0)>.35 and s.nose then s.honkAt=os.clock();Audio.Play('ClownHonk',s.nose)end
    end)
   end
   if p:GetAttribute('Vampired')then applyVampire(p,c)end
   if p:GetAttribute('BlackCatCurse')then cat(p,c)end
   if p:GetAttribute('PhotoOf')then photo(p,c)end
   if p:GetAttribute('Confettied')then confetti(p,c)end
  elseif s then
   -- Dead or spectating: nothing follows an empty spot.
   drop(s,'cat');drop(s,'stink')
  end
 end
end)
return M


