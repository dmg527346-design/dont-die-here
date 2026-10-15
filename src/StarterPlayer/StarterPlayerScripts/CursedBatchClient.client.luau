
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Preferences=require(RS:WaitForChild('HorrorPreferences'))
local Audio=require(RS:WaitForChild('GameplayAudio'))
local HoldPose=require(RS:WaitForChild('HoldPose'))
local localPlayer=Players.LocalPlayer
local folder=Instance.new('Folder');folder.Name='CursedBatchLocalVFX';folder.Parent=workspace
local tracks={}
local playerFX={}
local droplets={}
local index=0
local random=Random.new()
local function stopTrack(t,m)
 if m and m.Parent then for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')then part.LocalTransparencyModifier=0 end end end
 if t.liquid and t.liquid.Parent then t.liquid.Transparency=1 end
 if t.rain then Audio.Stop(t.rain)end
 if t.sob then Audio.Stop(t.sob)end
 if t.buzz then Audio.Stop(t.buzz)end
end
local function drop(origin,velocity,size,life,color)
 index=index%140+1
 local s=droplets[index]
 if not s then
  local p=Instance.new('Part');p.Name='FakeRainOrTear';p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Material=Enum.Material.Glass;p.Shape=Enum.PartType.Ball;p.Parent=folder
  s={part=p};droplets[index]=s
 end
 s.origin=origin;s.velocity=velocity;s.born=workspace:GetServerTimeNow();s.life=life
 s.part.Size=size;s.part.Color=color;s.part.Transparency=.25;s.part.Position=origin
end
local function note(head)
 local p=Instance.new('Part');p.Name='WhistleMusicNote';p.Size=Vector3.one*.1;p.Transparency=1;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Parent=folder
 local gui=Instance.new('BillboardGui');gui.Size=UDim2.fromOffset(32,40);gui.MaxDistance=80;gui.Parent=p
 local label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.Text=random:NextNumber()<.5 and '♫'or'♪';label.Font=Enum.Font.FredokaOne;label.TextSize=30;label.TextColor3=Color3.fromRGB(240,163,205);label.TextStrokeTransparency=.45;label.Parent=gui
 local born=workspace:GetServerTimeNow();local origin=head.Position+head.CFrame.ZVector*.85
 local connection;connection=Run.RenderStepped:Connect(function()
  local age=workspace:GetServerTimeNow()-born
  if age>1.5 or not p.Parent then connection:Disconnect();p:Destroy();return end
  p.Position=origin+head.CFrame.ZVector*age*.8+Vector3.new(math.sin(age*5)*.18,age*1.6,0)
  label.TextTransparency=math.clamp((age-.6)/.9,0,1);label.TextStrokeTransparency=.45+.55*label.TextTransparency;label.Rotation=math.sin(age*3)*12
 end)
end
local function aura(head)
 local a=Instance.new('Attachment');a.Name='CursedPerfumeAura';a.Position=Vector3.new(0,-1,0);a.Parent=head
 local e=Instance.new('ParticleEmitter');e.Name='SubtlePinkAura';e.Texture='rbxasset://textures/particles/smoke_main.dds';e.Color=ColorSequence.new(Color3.fromRGB(237,153,190))
 e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,.94),NumberSequenceKeypoint.new(1,1)})
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,1.15)});e.Rate=7;e.Lifetime=NumberRange.new(1.2,1.8);e.Speed=NumberRange.new(.15,.4);e.SpreadAngle=Vector2.new(160,160);e.Acceleration=Vector3.new(0,.25,0);e.LightEmission=.12;e.Parent=a
 return a
end
local function follow(m,head,offset,role,now,t)
 local cf=head.CFrame*offset
 if role=='Cloud'then cf*=CFrame.new(0,math.sin(now*2)*.1,0)
 elseif role=='PerfumeSpray'then
  local age=now-(m:GetAttribute('ItemWearStart')or now)
  cf*=CFrame.Angles(0,0,math.sin(age*math.pi*4)*.12)
 elseif role=='Fly'then
  local age=now-(m:GetAttribute('CosmeticBorn')or now);local seed=(m:GetAttribute('FlySeed')or 1)*.01
  local center=head.Position+Vector3.new(0,.5,0)
  local point=center+Vector3.new(math.sin(age*2.7+seed)*2.5+math.sin(age*7)*.35,math.sin(age*4.1+seed)*1.1,math.cos(age*3.3+seed)*2.1)
  local prior=t.flyPoint or point+head.CFrame.ZVector;t.flyPoint=point
  cf=(point-prior).Magnitude>.001 and CFrame.lookAt(point,point-(point-prior).Unit)or CFrame.new(point)

 end
 if role=='PerfumeSpray'and m:GetAttribute('ItemWearOwner')==localPlayer.UserId and workspace.CurrentCamera and (workspace.CurrentCamera.CFrame.Position-head.Position).Magnitude<2 then
  cf=HoldPose.Item(workspace.CurrentCamera.CFrame,CFrame.identity,m)
 end
 if role=='PartyBlower'and m:GetAttribute('CosmeticOwner')==localPlayer.UserId and workspace.CurrentCamera and (workspace.CurrentCamera.CFrame.Position-head.Position).Magnitude<2 then
  cf=workspace.CurrentCamera.CFrame*CFrame.new(0,-.44,-.62)*CFrame.Angles(0,math.pi,0)
 end
 m:PivotTo(cf)
 if role=='Fly'then
  local age=now-(m:GetAttribute('CosmeticBorn')or now)
  for _,part in ipairs(m:GetChildren())do if part:IsA('BasePart')and part.Name=='FlyWing'then
   local side=part:GetAttribute('FlySide')or 1
   part.CFrame=cf*(part:GetAttribute('FlyWingRest')or CFrame.new(side*.39,.25,-.14))*CFrame.Angles(0,0,math.sin(age*80)*side*.8)
   for _,vein in m:GetChildren()do if vein:IsA('BasePart')and vein:GetAttribute('FlyWingLocal')and vein:GetAttribute('FlySide')==side then vein.CFrame=part.CFrame*vein:GetAttribute('FlyWingLocal')end end
  end end
 end
 if role=='PartyBlower'then
  local age=now-(m:GetAttribute('CosmeticBorn')or now)
  local phase=age%1.65;local extend=math.clamp(phase/.18,0,1)*math.clamp((.95-phase)/.25,0,1)
  local length=.22+1.55*extend
  local tube=m:FindFirstChild('PaperTube');if tube then tube.Size=Vector3.new(.25,.16,length);tube.CFrame=cf*CFrame.new(0,0,.32+length*.5)end
  local n=0;for _,part in ipairs(m:GetChildren())do if part.Name=='PaperStripe'then n+=1;part.CFrame=cf*CFrame.new(0,0,.35+length*n/4)end end
  local curl=m:FindFirstChild('RolledTip');if curl then curl.Transparency=extend>.8 and 1 or 0;curl.CFrame=cf*CFrame.new(0,.07,.32+length)end
  if now>(t.nextBlow or 0)then t.nextBlow=now+1.65;Audio.Play('PartyBlower',m.PrimaryPart,{duration=1.1})end
 end
 local own=m:GetAttribute('CosmeticOwner')==localPlayer.UserId or m:GetAttribute('ItemWearOwner')==localPlayer.UserId
 local first=own and workspace.CurrentCamera and (workspace.CurrentCamera.CFrame.Position-head.Position).Magnitude<2
 for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')then
  part.LocalTransparencyModifier=first and(role=='Sunglasses'or role=='CoolHat'or role=='BirthdayHat')and 1 or 0
 end end
end
local function itemModels()
 local list={}
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 local current=RS:FindFirstChild('LobbyState')
 if (not current or current:GetAttribute('Mode')~='Menu') and interactive then for _,m in ipairs(interactive:GetChildren())do table.insert(list,m)end end
 local state=RS:FindFirstChild('LobbyState');local world=workspace:FindFirstChild('LobbyWorld');local toys=world and world:FindFirstChild('Toys');local runtime=toys and toys:FindFirstChild('RuntimeToys')
 if state and state:GetAttribute('Mode')=='Menu' and runtime then for _,m in ipairs(runtime:GetChildren())do if m:GetAttribute('LobbyToy')==true then table.insert(list,m)end end end
 return list
end
local acc=0
Run:BindToRenderStep('CursedBatchCosmetics',Enum.RenderPriority.Camera.Value+6,function(dt)
 local now=workspace:GetServerTimeNow()
 local cosmetics=workspace:FindFirstChild('CursedLevelCosmetics')
 local live={}
 local function process(m,cosmetic)
  local id=m:GetAttribute(cosmetic and 'CosmeticOwner'or'ItemWearOwner')
  local p=id and Players:GetPlayerByUserId(id);local head=p and p.Character and p.Character:FindFirstChild('Head')
  if not head then return end
  live[m]=true;local t=tracks[m]or{};tracks[m]=t
  local role=m:GetAttribute(cosmetic and 'CosmeticRole'or'ItemWearRole');local offset=m:GetAttribute(cosmetic and 'CosmeticOffset'or'ItemWearOffset')or CFrame.identity
  follow(m,head,offset,role,now,t)
  if role=='Cloud'then
   if not t.rain then t.rain=Audio.Play('CloudRain',m.PrimaryPart)end
   if not t.sob then t.sob=Audio.Play('CloudSob',head)end
  elseif role=='Fly'then
   if not t.buzz then t.buzz=Audio.Play('FlyBuzz',m.PrimaryPart)end
  elseif role=='PerfumeSpray'then
   local age=now-(m:GetAttribute('ItemWearStart')or now)
   local pump=m:FindFirstChild('Pump')
   if pump then pump.CFrame=m.PrimaryPart.CFrame*(pump:GetAttribute('PumpRest')or CFrame.new(0,.52,0))*CFrame.new(0,-math.max(0,math.sin(age*math.pi*4))*.07,0)end
   local nozzle=m:FindFirstChild('Nozzle')
   if nozzle then nozzle.CFrame=m.PrimaryPart.CFrame*(nozzle:GetAttribute('NozzleRest')or CFrame.new(0,.52,.22))*CFrame.new(0,-math.max(0,math.sin(age*math.pi*4))*.07,0)end
   local liquid=m:FindFirstChild('PerfumeLiquid')
   if liquid then
    t.liquid=liquid;local size=liquid:GetAttribute('FullSize')or liquid.Size;local remaining=math.clamp(1-age/1.65,0,1)
    liquid.Transparency=remaining>0 and .22 or 1
    liquid.Size=Vector3.new(size.X,math.max(.025,size.Y*remaining),size.Z)
    liquid.CFrame=m.PrimaryPart.CFrame*(liquid:GetAttribute('LiquidRest')or CFrame.new(0,-.25,0))*CFrame.new(0,-(size.Y-liquid.Size.Y)*.5,0)
   end
   local pulse=math.floor(age/.48)
   if pulse~=(t.sprayPulse or -1)and age>.18 then
    t.sprayPulse=pulse;Audio.Play('PerfumeSpray',m.PrimaryPart)
    for _=1,8 do
     local root=p.Character.HumanoidRootPart
     drop(nozzle and nozzle.Position or m.PrimaryPart.Position,(root.Position+Vector3.new(0,1,0)-(nozzle and nozzle.Position or m.PrimaryPart.Position)).Unit*4+Vector3.new(random:NextNumber(-.3,.3),random:NextNumber(-.3,.3),random:NextNumber(-.3,.3)),Vector3.one*.055,.35,Color3.fromRGB(244,174,207))
    end
   end
  end
 end
 for _,m in ipairs(itemModels())do
  if m:GetAttribute('ItemWearOwner')then process(m,false)end
  if m:GetAttribute('ItemId')=='FlyJar'and m:GetAttribute('FlyEscaped')then
   for _,part in ipairs(m:GetChildren())do if part:IsA('BasePart')and (part.Name:sub(1,3)=='Fly'or part.Name=='Antenna')then part.LocalTransparencyModifier=1 end end
   -- The server hides the entire welded cap, including trim; no loose local cap animation.
   for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')and (part.Name:lower():find('lid')or part.Name:lower():find('jarcap'))then part.LocalTransparencyModifier=1 end end
  end
 end
 if cosmetics then for _,m in ipairs(cosmetics:GetChildren())do process(m,true)end end
 for m,t in pairs(tracks)do if not live[m]then stopTrack(t,m);tracks[m]=nil end end
 acc+=dt
 if acc>.10 then
  acc=0
  for _,p in ipairs(Players:GetPlayers())do
   local c=p.Character;local head=c and c:FindFirstChild('Head');local hum=c and c:FindFirstChildOfClass('Humanoid')
   local fx=playerFX[p]or{};playerFX[p]=fx
   local alive=head and hum and hum.Health>0
   if alive and now<(p:GetAttribute('CryingUntil')or 0)then
    for _,side in ipairs({'Left','Right'})do
     local eye=head:FindFirstChild(side..'Eyeball')
     if eye and Preferences.Get('SpitEffects')then drop(eye.Position+head.CFrame.ZVector*.3,Vector3.new(0,-1,0)+head.CFrame.ZVector*.3,Vector3.new(.065,.11,.065),.7,Color3.fromRGB(151,213,245))end
    end
    for _=1,2 do
     local origin=head.Position+Vector3.new(random:NextNumber(-1,1),3.3,random:NextNumber(-.6,.6))
     drop(origin,Vector3.new(0,-4,0),Vector3.new(.027,.25,.027),.7,Color3.fromRGB(158,205,232))
    end
   end
   local hasAura=alive and p:GetAttribute('PerfumedLevel')~=nil and now>=(p:GetAttribute('PerfumeAuraStart')or 0)
   if hasAura and not fx.aura then fx.aura=aura(head)
   elseif not hasAura and fx.aura then fx.aura:Destroy();fx.aura=nil end
   local untilAt=p:GetAttribute('WhistleUntil')or 0
   if alive and untilAt>now and fx.whistle~=untilAt then fx.whistle=untilAt;note(head);task.delay(.3,function()if head.Parent then note(head)end end)end
  end
  for p,fx in pairs(playerFX)do if not p.Parent then if fx.aura then fx.aura:Destroy()end;playerFX[p]=nil end end
 end
 for _,s in ipairs(droplets)do
  local age=now-s.born
  if age<s.life then
   s.part.Position=s.origin+s.velocity*age+Vector3.new(0,-9*age*age,0)
   s.part.Transparency=.25+.75*(age/s.life)^2
  else s.part.Transparency=1 end
 end
end)

