-- Client half of CursedBatchEffects.ItemBatch8 / ItemBatch9 (CursedB build 2026-10-27). Renders only: every rule,
-- value, lease and sound that matters is on the server. Reads replicated player / item attributes, no remotes.
-- Camera offsets follow CurseEffectsClient: removed before the camera module runs, so they never accumulate, and
-- they obey HorrorPreferences CameraMotion. Screen effects stay short and never flash faster than 3 Hz.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local Lighting=game:GetService('Lighting')
local HS=game:GetService('HttpService')
local GameplayAudio=require(RS:WaitForChild('GameplayAudio'))
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local Prefs=require(RS:WaitForChild('HorrorPreferences'))
local InputHints=require(RS:WaitForChild('InputHints'))
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')
local random=Random.new()

local GOLD=Color3.fromRGB(255,214,60)
local CREAM=Color3.fromRGB(255,244,220)
local CYAN=Color3.fromRGB(110,230,255)
local PINK=Color3.fromRGB(255,150,205)

local function now()return workspace:GetServerTimeNow()end
local function leased(q,key)return now()<(q:GetAttribute(key)or 0)end
local function alive(q)
 local c=q.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return h and h.Health>0 and q:GetAttribute('MissionActive')==true and c or nil
end
local function cue(key,fallback)return Sounds[key]and key or fallback end
local function itemModels()
 local map=workspace:FindFirstChild('Mansion');local i=map and map:FindFirstChild('Interactive')
 return i and i:GetChildren()or{}
end
local function monsterNear(pos,radius)
 local f=workspace:FindFirstChild('RoamingCreatures');if not f then return false end
 for _,e in ipairs(f:GetChildren())do local pp=e:IsA('Model')and e.PrimaryPart;if pp and(pp.Position-pos).Magnitude<radius then return true end end
 return false
end
local function makeGui(name,order)
 local g=Instance.new('ScreenGui');g.Name=name;g.ResetOnSpawn=false;g.DisplayOrder=order;g.IgnoreGuiInset=true
 g.ScreenInsets=Enum.ScreenInsets.None;g.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;g.Parent=playerGui;return g
end
local function label(parent,name,text,size,color)
 local l=Instance.new('TextLabel');l.Name=name;l.BackgroundTransparency=1;l.Font=Enum.Font.FredokaOne;l.Text=text;l.TextSize=size
 l.TextColor3=color or CREAM;l.TextStrokeTransparency=.35;l.TextStrokeColor3=Color3.fromRGB(20,14,26);l.Parent=parent;return l
end

-- Popping text (one at a time, centre-top, 0.9 s) -----------------------------------------------------------
local popGui=makeGui('CursedBatchBPop',6)
local pop=label(popGui,'Pop','',46,GOLD);pop.AnchorPoint=Vector2.new(.5,.5);pop.Position=UDim2.fromScale(.5,.3);pop.Size=UDim2.fromOffset(420,70);pop.Visible=false
local popAt=-1
local function popText(text,color)popAt=os.clock();pop.Text=text;pop.TextColor3=color or GOLD;pop.Visible=true end
-- Short full-screen tint flash (white x-ray flash, pink eraser puff).
local flash=Instance.new('Frame');flash.Name='Flash';flash.Size=UDim2.fromScale(1,1);flash.BorderSizePixel=0;flash.BackgroundTransparency=1;flash.ZIndex=0;flash.Parent=popGui
local flashAt,flashPeak,flashFade=-1,0,.35
local function flashScreen(color,peak,fade)flashAt=os.clock();flash.BackgroundColor3=color;flashPeak=peak;flashFade=fade end
Run.RenderStepped:Connect(function()
 local age=os.clock()-popAt
 if pop.Visible then
  if age>.9 then pop.Visible=false
  else
   local s=age<.12 and .6+.4*(age/.12)*1.15 or 1+.15*math.max(0,1-(age-.12)/.2)
   pop.Size=UDim2.fromOffset(420*s,70*s);pop.TextSize=46*s;pop.TextTransparency=math.clamp((age-.6)/.3,0,1);pop.TextStrokeTransparency=.35+.65*pop.TextTransparency
  end
 end
 local fa=os.clock()-flashAt
 flash.BackgroundTransparency=fa<flashFade and 1-flashPeak*(1-fa/flashFade)or 1
end)
-- One-shot reactions to server stamps on the local player.
local function onStamp(key,fn)
 local last=player:GetAttribute(key)
 player:GetAttributeChangedSignal(key):Connect(function()
  local v=player:GetAttribute(key)
  if type(v)=='number'and v~=last and alive(player)then fn(v)end
  last=v
 end)
end

-- Camera offsets (giggle bounce, pogo squash, racer dizzy, bumps) -------------------------------------------
local applied,appliedCam,appliedFov=nil,nil,0
local bumpAt,bumpAmp=-1,0
local function bump(amp)bumpAt=os.clock();bumpAmp=amp end
local squashAt=-1
local zoom={on=false,start=0,dir=Vector3.zero,speed=0,bonked=false}
Run:BindToRenderStep('CursedBatchBReset',Enum.RenderPriority.Camera.Value-3,function()
 if appliedCam and appliedCam==workspace.CurrentCamera then
  if applied then appliedCam.CFrame*=applied:Inverse()end
  if appliedFov~=0 then appliedCam.FieldOfView-=appliedFov end
 end
 applied=nil;appliedCam=nil;appliedFov=0
end)
Run:BindToRenderStep('CursedBatchBCamera',Enum.RenderPriority.Camera.Value+4,function()
 local cam=workspace.CurrentCamera
 if not cam or cam.CameraType==Enum.CameraType.Scriptable or not alive(player)then return end
 local t=now();local clock=os.clock();local offset=CFrame.identity;local fov=0
 local motion=Prefs.Get('CameraMotion')
 -- GiggleFeather: the giggler's camera bounces with the laugh (fade in .15 s, out .4 s).
 local gUntil=player:GetAttribute('GiggleUntil')or 0
 if motion and t<gUntil then
  local age=t-(player:GetAttribute('GiggleStart')or t)
  local fade=math.clamp((gUntil-t)/.4,0,1)*math.clamp(age/.15,0,1)
  offset*=CFrame.new(0,math.abs(math.sin(age*14))*.12*fade,0)*CFrame.Angles(math.sin(age*9)*.015*fade,0,math.sin(age*7)*.03*fade)
 end
 -- PogoSpring: a squash on every landing (dip + FOV punch).
 local sq=clock-squashAt
 if sq<.28 then local k=math.sin(math.pi*sq/.28);if motion then offset*=CFrame.new(0,-.35*k,0)end;fov+=6*k end
 -- PullbackRacer: speed FOV while zooming, a dizzy roll after.
 if zoom.on then fov+=18*math.clamp((clock-zoom.start)/.12,0,1)end
 local dUntil=player:GetAttribute('RacerDizzyUntil')or 0
 if motion and not zoom.on and t<dUntil then
  local left=math.clamp((dUntil-t)/1.2,0,1)
  offset*=CFrame.Angles(math.sin(clock*9.4)*.03*left,0,math.sin(clock*9.4)*math.rad(6)*left)
 end
 -- Bumps (cart clang, snapped string, wall bonk).
 local ba=clock-bumpAt
 if motion and ba<.35 then local k=(1-ba/.35)^2*bumpAmp;offset*=CFrame.Angles(math.noise(clock*20,1)*k,math.noise(clock*23,2)*k,math.noise(clock*17,3)*k)end
 if offset~=CFrame.identity then cam.CFrame*=offset;applied=offset;appliedCam=cam end
 if fov~=0 then cam.FieldOfView+=fov;appliedFov=fov;appliedCam=cam end
end)

-- Giggle text over every giggler (everyone sees it) -------------------------------------------------------
local giggleTags={}
local GIGGLES={'hee hee!','hehehe!','teehee!','HAHA!'}
-- TinCanPhone marker + SnoringSuitcase tip -----------------------------------------------------------------
local hud=makeGui('CursedBatchBHud',5);hud.IgnoreGuiInset=false
local call=Instance.new('Frame');call.Name='CanCallMarker';call.AnchorPoint=Vector2.new(.5,1);call.BackgroundTransparency=1;call.Size=UDim2.fromOffset(240,74);call.Visible=false;call.Parent=hud
local callIcon=label(call,'Icon','!',40,GOLD);callIcon.Position=UDim2.new(.5,-16,0,0);callIcon.Size=UDim2.fromOffset(32,34)
local callTitle=label(call,'Title','',18,GOLD);callTitle.Position=UDim2.fromOffset(0,32);callTitle.Size=UDim2.new(1,0,0,22)
local callDetail=label(call,'Detail','A MONSTER IS NEAR THEM',14);callDetail.Position=UDim2.fromOffset(0,54);callDetail.Size=UDim2.new(1,0,0,18)
local tip=Instance.new('Frame');tip.Name='SuitcaseTip';tip.AnchorPoint=Vector2.new(.5,0);tip.Position=UDim2.new(.5,0,0,166);tip.Size=UDim2.new(.92,0,0,40)
tip.BackgroundColor3=Color3.fromRGB(26,16,30);tip.BackgroundTransparency=.15;tip.Visible=false;tip.Parent=hud
Instance.new('UICorner',tip).CornerRadius=UDim.new(0,12)
local cap=Instance.new('UISizeConstraint');cap.MaxSize=Vector2.new(460,40);cap.Parent=tip
local tipText=label(tip,'Text','',17,CREAM);tipText.Position=UDim2.fromOffset(10,6);tipText.Size=UDim2.new(1,-20,1,-12);tipText.TextScaled=true
local tagMap=Instance.new('TextLabel');tagMap.Name='MapErasedTag';tagMap.Size=UDim2.fromOffset(230,30);tagMap.BackgroundColor3=Color3.fromRGB(245,150,190)
tagMap.BackgroundTransparency=.1;tagMap.Font=Enum.Font.GothamBold;tagMap.TextSize=15;tagMap.TextColor3=Color3.new(1,1,1);tagMap.TextStrokeTransparency=.4;tagMap.Visible=false;tagMap.Parent=hud
Instance.new('UICorner',tagMap).CornerRadius=UDim.new(0,8)
local tagStroke=Instance.new('UIStroke');tagStroke.Color=Color3.fromRGB(61,132,245);tagStroke.Thickness=2;tagStroke.Parent=tagMap
local chip=label(hud,'XRayChip','X-RAY: monsters show through walls',18,CYAN);chip.AnchorPoint=Vector2.new(.5,0);chip.Position=UDim2.new(.5,0,0,64);chip.Size=UDim2.fromOffset(360,26);chip.Visible=false
local EDGE=40
local function project(cam,pos)
 local vp=cam.ViewportSize;local inset=hud.AbsolutePosition
 local sp=cam:WorldToViewportPoint(pos);local x,y=sp.X,sp.Y
 if sp.Z<0 then x,y=vp.X-x,vp.Y-y end
 if sp.Z<0 or x<EDGE or x>vp.X-EDGE or y<EDGE or y>vp.Y-EDGE then
  local cx,cy=vp.X/2,vp.Y/2;local dx,dy=x-cx,y-cy;if math.abs(dx)<1e-3 and math.abs(dy)<1e-3 then dy=1 end
  local s=math.min((cx-EDGE)/math.max(math.abs(dx),1e-3),(cy-EDGE)/math.max(math.abs(dy),1e-3));x,y=cx+dx*s,cy+dy*s
 end
 return UDim2.fromOffset(x-inset.X,y-inset.Y)
end
local hudAcc=0
Run.RenderStepped:Connect(function(dt)
 local t=now();local cam=workspace.CurrentCamera
 -- TinCanPhone: point at the teammate whose can is ringing yours.
 local caller=t<(player:GetAttribute('CanCallUntil')or 0)and Players:GetPlayerByUserId(player:GetAttribute('CanCallFrom')or 0)or nil
 local cc=caller and alive(caller);local head=cc and cc:FindFirstChild('Head')
 call.Visible=head~=nil and cam~=nil and alive(player)~=nil
 if call.Visible and head and cam and caller then
  call.Position=project(cam,head.Position+Vector3.new(0,6,0))
  callTitle.Text=string.upper(caller.DisplayName)..'\'S CAN IS RINGING!'
  local pulse=1+.18*math.abs(math.sin(os.clock()*5));call.Size=UDim2.fromOffset(240*pulse,74*pulse)
 end
 hudAcc+=dt;if hudAcc<.15 then return end;hudAcc=0
 -- SnoringSuitcase: one tip line for the holder, the helper and empty-handed teammates nearby.
 local mine=alive(player);local me=mine and mine:FindFirstChild('HumanoidRootPart');local msg
 if not me then msg=nil
 elseif leased(player,'SuitcaseHelpUntil')then msg='YOU HAVE THE OTHER HANDLE. STAY CLOSE!'
 elseif leased(player,'SuitcaseDuoUntil')then msg='TEAM CARRY! THE SUITCASE IS FAST ASLEEP.'
 elseif leased(player,'SuitcaseHeavyUntil')then
  local alone=true;for _,q in ipairs(Players:GetPlayers())do if q~=player and alive(q)then alone=false;break end end
  msg=alone and'TOO HEAVY! IT SNORES WHILE YOU CARRY IT ALONE.'or'TOO HEAVY! A TEAMMATE WITH EMPTY HANDS CAN TAKE THE END HANDLE.'
 elseif(player:GetAttribute('CursedHeldCount')or 0)==0 then
  for _,q in ipairs(Players:GetPlayers())do
   local c=q~=player and leased(q,'SuitcaseHeavyUntil')and alive(q);local r=c and c:FindFirstChild('HumanoidRootPart')
   if r and(r.Position-me.Position).Magnitude<30 then msg='HELP '..string.upper(q.DisplayName)..': STAND AT THE SUITCASE END WITH EMPTY HANDS.';break end
  end
 end
 tip.Visible=msg~=nil;if msg then tipText.Text=msg end
 -- TrailEraser: MAP RUBBED OUT countdown.
 local left=(player:GetAttribute('MapErasedUntil')or 0)-t
 tagMap.Visible=left>0 and me~=nil
 if tagMap.Visible then
  if InputHints.IsMobile()then tagMap.AnchorPoint=Vector2.new(.5,0);tagMap.Position=UDim2.new(.5,0,0,100)
  else tagMap.AnchorPoint=Vector2.new(0,0);tagMap.Position=UDim2.new(0,16,0,120)end
  tagMap.Text=('MAP RUBBED OUT  %ds'):format(math.ceil(left))
 end
 -- Giggle text over every giggler.
 for _,q in ipairs(Players:GetPlayers())do
  local c=alive(q);local h=c and c:FindFirstChild('Head');local on=h~=nil and leased(q,'GiggleUntil')
  local tag=giggleTags[q]
  if on and h and(not tag or tag.Parent~=h)then
   if tag then tag:Destroy()end
   tag=Instance.new('BillboardGui');tag.Name='GiggleTag';tag.Size=UDim2.fromOffset(140,40);tag.StudsOffset=Vector3.new(0,3.2,0);tag.MaxDistance=80;tag.LightInfluence=0
   local l=label(tag,'Text',GIGGLES[random:NextInteger(1,#GIGGLES)],26,PINK);l.Size=UDim2.fromScale(1,1);tag.Parent=h;giggleTags[q]=tag
  elseif not on and tag then tag:Destroy();giggleTags[q]=nil end
  if on and tag then local l=tag:FindFirstChild('Text');if l then l.Rotation=math.sin(os.clock()*12)*8 end end
 end
 for q,tg in pairs(giggleTags)do if q.Parent~=Players then tg:Destroy();giggleTags[q]=nil end end
end)
onStamp('GiggleStart',function()popText('HEE HEE HEE!',PINK)end)
onStamp('CanSnapAt',function()popText('SNAP!',GOLD);bump(math.rad(2.5))end)
onStamp('PuppetSnapAt',function()popText('SNAP!',Color3.fromRGB(200,160,255));bump(math.rad(3))end)
onStamp('MagnetNudgeAt',function()popText('CLANG!',PINK);bump(math.rad(2.2))end)
onStamp('PaperStuckAt',function()popText('STUCK TO YOUR SHOE!',CREAM)end)
onStamp('EraserRubAt',function()popText('WHO? ME?',PINK);flashScreen(PINK,.35,.6)end)

-- PumpkinGrin candle flicker / TreatSack candy pop / SongbirdMusicBox wind meter ---------------------------
local pumpkinSeed={}
local sackCandy={}
local meters={}
local CANDY_COLORS={Color3.fromRGB(245,144,182),Color3.fromRGB(154,210,63),Color3.fromRGB(247,201,62),Color3.fromRGB(66,201,240)}
local fxFolder=Instance.new('Folder');fxFolder.Name='CursedBatchBFx';fxFolder.Parent=workspace
local function candyPop(m,count)
 local root=m.PrimaryPart;if not root then return end
 local a=random:NextNumber(0,math.pi*2);local start=root.Position+Vector3.new(math.cos(a)*3,2.5,math.sin(a)*3)
 local candy=Instance.new('Part');candy.Name='TreatSackCandy';candy.Shape=Enum.PartType.Ball;candy.Size=Vector3.new(.3,.3,.3)
 candy.Material=Enum.Material.SmoothPlastic;candy.Color=CANDY_COLORS[count%#CANDY_COLORS+1]
 candy.Anchored=true;candy.CanCollide=false;candy.CanQuery=false;candy.CanTouch=false;candy.CastShadow=false;candy.Position=start;candy.Parent=fxFolder
 local gui=Instance.new('BillboardGui');gui.Size=UDim2.fromOffset(130,36);gui.StudsOffsetWorldSpace=Vector3.new(0,1.4,0);gui.MaxDistance=70;gui.Parent=candy
 local l=label(gui,'Text','CANDY '..count..'/12',24,GOLD);l.Size=UDim2.fromScale(1,1)
 local born=os.clock();local conn
 conn=Run.RenderStepped:Connect(function()
  local age=os.clock()-born
  if age>1.3 or not candy.Parent or not root.Parent then conn:Disconnect();candy:Destroy();return end
  local k=math.clamp(age/.45,0,1);local target=root.Position+Vector3.new(0,.7,0)
  candy.Position=start:Lerp(target,k)+Vector3.new(0,math.sin(k*math.pi)*1.2,0)
  candy.Transparency=k>=1 and 1 or 0
  l.TextTransparency=math.clamp((age-.7)/.6,0,1);l.TextStrokeTransparency=.35+.65*l.TextTransparency
 end)
end
local function windMeter(m)
 local ui=meters[m];if ui and ui.gui.Parent then return ui end
 local gui=Instance.new('BillboardGui');gui.Name='SongbirdWindMeter';gui.Size=UDim2.fromOffset(120,36);gui.StudsOffsetWorldSpace=Vector3.new(0,1.1,0) -- UI pass 2026-10-27: held close to the camera, 1.9 put it over the quota bars
 gui.MaxDistance=70;gui.LightInfluence=0;gui.Parent=m.PrimaryPart
 local back=Instance.new('Frame');back.Name='Back';back.Size=UDim2.new(1,0,0,12);back.Position=UDim2.new(0,0,1,-12);back.BackgroundColor3=Color3.fromRGB(28,24,36);back.BorderSizePixel=0;back.Parent=gui
 Instance.new('UICorner',back).CornerRadius=UDim.new(1,0)
 local fill=Instance.new('Frame');fill.Name='Fill';fill.Size=UDim2.fromScale(1,1);fill.BackgroundColor3=Color3.fromRGB(245,186,34);fill.BorderSizePixel=0;fill.Parent=back
 Instance.new('UICorner',fill).CornerRadius=UDim.new(1,0)
 local l=label(gui,'Call','',20,Color3.fromRGB(255,236,180));l.Size=UDim2.new(1,0,0,22);l.TextScaled=true
 ui={gui=gui,fill=fill,label=l};meters[m]=ui;return ui
end
local itemAcc=0
Run.RenderStepped:Connect(function(dt)
 local clock=os.clock();local t=now()
 local models=itemModels()
 for _,m in ipairs(models)do
  if m:GetAttribute('ItemId')=='PumpkinGrin'and m.PrimaryPart then
   local seed=pumpkinSeed[m];if not seed then seed=random:NextNumber(0,100);pumpkinSeed[m]=seed end
   local light=m.PrimaryPart:FindFirstChild('PumpkinGlow');local base=light and light:GetAttribute('GlowBase')
   if light and type(base)=='number'then light.Brightness=base*(.9+.35*math.noise(clock*5,seed))end
   local f=m:FindFirstChild('FaceScared',true)
   if f and f:IsA('BasePart')then f.LocalTransparencyModifier=(m:GetAttribute('PumpkinFace')=='Scared'and math.noise(clock*4,seed)>.2)and .6 or 0 end
  end
 end
 itemAcc+=dt;if itemAcc<.1 then return end;itemAcc=0
 local live={}
 for _,m in ipairs(models)do
  local id=m:GetAttribute('ItemId')
  if id=='TreatSack'then
   local n=m:GetAttribute('Candy')or 0
   if sackCandy[m]~=nil and n>sackCandy[m]then candyPop(m,n)end
   sackCandy[m]=n
  elseif id=='SongbirdMusicBox'and m.PrimaryPart and m:GetAttribute('WindEndsAt')and not m:GetAttribute('Selling')then
   live[m]=true;local ui=windMeter(m)
   local left=math.max(0,m:GetAttribute('WindEndsAt')-t);local full=m:GetAttribute('WindFull')or 25;local low=left<6
   ui.fill.Size=UDim2.fromScale(math.clamp(left/full,0,1),1)
   ui.fill.BackgroundColor3=if low then Color3.fromRGB(170,110,255)else Color3.fromRGB(245,186,34)
   ui.label.Text=if left<=0 then'SHRIEKING!'elseif low then'WIND ME!'else''
   ui.label.TextTransparency=if low and math.floor(t*2)%2==1 then .45 else 0
  end
 end
 for m in pairs(pumpkinSeed)do if not m.Parent then pumpkinSeed[m]=nil end end
 for m in pairs(sackCandy)do if not m.Parent then sackCandy[m]=nil end end
 for m,ui in pairs(meters)do if not live[m]then ui.gui:Destroy();meters[m]=nil end end
end)

-- RunawayToiletPaper: shoe streamers flutter behind every player ------------------------------------------
local paperRest={}
Run.Heartbeat:Connect(function()
 local clock=os.clock()
 for _,q in ipairs(Players:GetPlayers())do
  local x=q.Character and q.Character:FindFirstChild('ShoePaper')
  local w=x and x:FindFirstChild('ShoePaperWeld')
  if w and w:IsA('Weld')then
   if not paperRest[w]then paperRest[w]=w.C0;w.Destroying:Connect(function()paperRest[w]=nil end)end
   local r=q.Character:FindFirstChild('HumanoidRootPart')
   local v=r and Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude or 0
   local flap=math.sin(clock*(6+v*.6)+q.UserId%7)*math.rad(4+math.min(v,24)*.6)
   w.C0=paperRest[w]*CFrame.Angles(flap,0,flap*.4)
  end
 end
end)

-- SnowGlobe: frosted rim, drifting flakes, whiteout when running, the giant eye (server-timed SnowEyeAt) --------
local GLOBE_FADE,GLOBE_FLAKES,GLOBE_WHITEOUT=.6,70,.6
local EYE_SECONDS,EYE_SLIDE,EYE_BLINK_AT=3.2,.6,1.7
local globeGui=makeGui('SnowGlobeView',-4);globeGui.Enabled=false
local function roundFrame(parent,name,color,z)
 local f=Instance.new('Frame');f.Name=name;f.BackgroundColor3=color;f.BorderSizePixel=0;f.AnchorPoint=Vector2.new(.5,.5);f.ZIndex=z;f.Parent=parent
 local k=Instance.new('UICorner');k.CornerRadius=UDim.new(.5,0);k.Parent=f;return f
end
local eye=roundFrame(globeGui,'GiantEye',Color3.fromRGB(226,232,238),1);eye.ClipsDescendants=true;eye.Visible=false
local iris=roundFrame(eye,'Iris',Color3.fromRGB(112,72,205),1)
local pupil=roundFrame(iris,'Pupil',Color3.fromRGB(20,20,26),1);pupil.Position=UDim2.fromScale(.5,.5)
local glint=roundFrame(pupil,'Glint',Color3.new(1,1,1),1);glint.Size=UDim2.fromScale(.3,.3);glint.Position=UDim2.fromScale(.32,.3)
local lid=roundFrame(eye,'Lid',Color3.fromRGB(28,29,34),2)
local rim=Instance.new('Frame');rim.Name='GlassRim';rim.BackgroundTransparency=1;rim.AnchorPoint=Vector2.new(.5,.5);rim.Position=UDim2.fromScale(.5,.5);rim.ZIndex=2;rim.Parent=globeGui
local rimCorner=Instance.new('UICorner');rimCorner.Parent=rim
local rimStroke=Instance.new('UIStroke');rimStroke.Color=Color3.fromRGB(205,232,255);rimStroke.Transparency=1;rimStroke.Parent=rim
local white=Instance.new('Frame');white.Name='Whiteout';white.BackgroundColor3=Color3.fromRGB(240,246,255);white.BorderSizePixel=0
white.Size=UDim2.fromScale(1,1);white.BackgroundTransparency=1;white.ZIndex=3;white.Parent=globeGui
local flakes={}
for i=1,GLOBE_FLAKES do
 local f=roundFrame(globeGui,'Flake',Color3.new(1,1,1),4)
 flakes[i]={frame=f,x=random:NextNumber(),y=random:NextNumber(),size=random:NextInteger(3,8),fall=.04+random:NextNumber()*.06,phase=random:NextNumber()*6.28}
end
local globeFade,wind,windOn,lastEye=0,nil,false,nil
Run.RenderStepped:Connect(function(dt)
 local c=alive(player)
 local on=c~=nil and leased(player,'SnowGlobeUntil')
 globeFade=math.clamp(globeFade+(on and dt or-dt)/GLOBE_FADE,0,1)
 if on and not windOn then windOn=true;wind=GameplayAudio.Play('AmbWind',nil,{loop=true})
 elseif not on and windOn then windOn=false;if wind then GameplayAudio.Stop(wind)end;wind=nil end
 globeGui.Enabled=globeFade>0
 if globeFade<=0 then eye.Visible=false;return end
 local cam=workspace.CurrentCamera;local view=cam and cam.ViewportSize or Vector2.new(1280,720)
 local sx,sy=view.X,view.Y
 local root=c and c:FindFirstChild('HumanoidRootPart')
 local v=root and root.AssemblyLinearVelocity or Vector3.zero
 local shake=math.clamp((Vector3.new(v.X,0,v.Z).Magnitude-8)/10,0,1)
 local danger=root~=nil and monsterNear(root.Position,25)
 local thick=math.max(sx,sy)*.7;local hole=Vector2.new(sx*.94,sy*.9)
 rim.Size=UDim2.fromOffset(hole.X+thick,hole.Y+thick);rimCorner.CornerRadius=UDim.new(0,(math.min(hole.X,hole.Y)+thick)/2)
 rimStroke.Thickness=thick;rimStroke.Transparency=1-.45*globeFade
 -- Never blind the holder while a monster is close: the whiteout caps at 20 % then.
 white.BackgroundTransparency=1-(danger and .2 or GLOBE_WHITEOUT)*shake*globeFade
 local count=math.floor(GLOBE_FLAKES*(.35+.65*shake)+.5);local clock=os.clock()
 for i,f in ipairs(flakes)do
  local show=i<=count;f.frame.Visible=show
  if show then
   f.y+=dt*f.fall*(1+shake*5);f.x+=dt*(math.sin(clock*1.3+f.phase)*.02+shake*.25)
   if f.y>1.05 then f.y=-.05;f.x=random:NextNumber()end
   if f.x>1.05 then f.x=-.05 elseif f.x<-.05 then f.x=1.05 end
   local px=f.size*sy/600
   f.frame.Size=UDim2.fromOffset(px,px);f.frame.Position=UDim2.fromScale(f.x,f.y);f.frame.BackgroundTransparency=1-.85*globeFade
  end
 end
 local eyeAt=player:GetAttribute('SnowEyeAt');local te=type(eyeAt)=='number'and now()-eyeAt or 99
 if not on or te<0 or te>=EYE_SECONDS or danger then eye.Visible=false;return end
 if lastEye~=eyeAt then lastEye=eyeAt;GameplayAudio.Play('ScareWhisper')end
 local side=player:GetAttribute('SnowEyeSide')or 1
 local H=sy*.34;local W=H*1.8
 eye.Size=UDim2.fromOffset(W,H);lid.Size=UDim2.fromOffset(W,H)
 iris.Size=UDim2.fromOffset(H*.8,H*.8);pupil.Size=UDim2.fromOffset(H*.36,H*.36)
 local slide=math.clamp(math.min(te,EYE_SECONDS-te)/EYE_SLIDE,0,1);slide=slide*slide*(3-2*slide)
 local away,peek
 if side==1 then away=Vector2.new(-W*.5,sy*.45);peek=Vector2.new(W*.12,sy*.45)
 elseif side==2 then away=Vector2.new(sx+W*.5,sy*.4);peek=Vector2.new(sx-W*.12,sy*.4)
 else away=Vector2.new(sx*.5,-H*.5);peek=Vector2.new(sx*.5,H*.2)end
 local at=away:Lerp(peek,slide)
 eye.Visible=true;eye.Position=UDim2.fromOffset(at.X,at.Y)
 local look=Vector2.new(sx*.5,sy*.5)-at;look=look.Magnitude>0 and look.Unit or Vector2.zero
 iris.Position=UDim2.new(.5,look.X*W*.22,.5,look.Y*H*.12)
 local blink=math.clamp(1-math.abs(te-EYE_BLINK_AT)/.18,0,1)
 lid.Position=UDim2.fromOffset(W*.5,-H*.5+H*blink)
end)

-- XRayLightBox: cyan film, monsters glow through walls (this room + next rooms), flash; teammates glow on a flash --
local film=Instance.new('ColorCorrectionEffect');film.Name='XRayFilm';film.Enabled=false;film.TintColor=Color3.fromRGB(190,235,255);film.Saturation=-.55;film.Contrast=.15;film.Parent=Lighting
local graphRaw,graphData=nil,nil
local function roomAt(pos)
 local map=workspace:FindFirstChild('Mansion');local v=map and map:FindFirstChild('GeneratedGraph');if not v then return nil end
 if graphRaw~=v.Value then graphRaw=v.Value;local ok,g=pcall(HS.JSONDecode,HS,v.Value);graphData=ok and g or nil end
 local g=graphData;if not g then return nil end
 local fh=g.floorHeight or 16;local level=math.floor((pos.Y+2)/fh);local other
 for _,r in ipairs(g.rooms or{})do
  if r.x1 and pos.X>=r.x1 and pos.X<=r.x2 and pos.Z>=r.z1 and pos.Z<=r.z2 then if(r.level or 0)==level then return r end;other=other or r end
 end
 return other
end
local glows={}
local function glow(model,on)
 local h=glows[model]
 if on and not h then
  h=Instance.new('Highlight');h.Name='XRayGlow';h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.FillTransparency=.55;h.OutlineTransparency=0
  h.FillColor=CYAN;h.OutlineColor=CYAN;h.Adornee=model;h.Parent=workspace.CurrentCamera;glows[model]=h
 end
 if h then h.Enabled=on end
end
local lastFlash=player:GetAttribute('XRayFlashAt')
player:GetAttributeChangedSignal('XRayFlashAt'):Connect(function()
 local v=player:GetAttribute('XRayFlashAt')
 if type(v)=='number'and v~=lastFlash and leased(player,'XRayUntil')then flashScreen(Color3.new(1,1,1),.8,.35);popText('FLASH!',CYAN)end
 lastFlash=v
end)
local xrayAcc=0
Run.Heartbeat:Connect(function(dt)
 xrayAcc+=dt;if xrayAcc<.1 then return end;xrayAcc=0
 local c=alive(player);local r=c and c:FindFirstChild('HumanoidRootPart')
 local xray=r~=nil and leased(player,'XRayUntil')
 film.Enabled=xray;chip.Visible=xray
 local set={}
 if xray and r then local here=roomAt(r.Position);if here then set[here.name]=true;for _,n in ipairs(here.neighbors or{})do set[n]=true end end end
 local seen={}
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,enemy in ipairs(folder:GetChildren())do
  local primary=enemy:IsA('Model')and enemy.PrimaryPart
  local at=xray and primary and roomAt(primary.Position)
  local on=type(at)=='table' and set[at.name]==true;seen[enemy]=true
  if on or glows[enemy]then glow(enemy,on)end
 end end
 local t=now()
 for _,q in ipairs(Players:GetPlayers())do
  local qc=q.Character
  if qc then
   local on=alive(q)~=nil and t-(q:GetAttribute('XRayFlashAt')or-1e9)<1.5 and leased(q,'XRayUntil');seen[qc]=true
   if on or glows[qc]then glow(qc,on)end
  end
 end
 for model,h in pairs(glows)do if not seen[model]or not model.Parent then h:Destroy();glows[model]=nil end end
end)

-- PogoSpring: auto-hop for the local holder, super-boing every 4th, boing + squash on every pogo landing ------
local hops,superRestore=0,nil
local fallSpeed={} -- [Player]=most negative vertical speed since the last landing
local function hookHumanoid(c)
 local hum=c:WaitForChild('Humanoid',10);if not hum then return end
 hum.StateChanged:Connect(function(_,new)
  if new==Enum.HumanoidStateType.Jumping and leased(player,'PogoUntil')then
   hops+=1;c:SetAttribute('PogoHops',hops)
  elseif new==Enum.HumanoidStateType.Landed then
   if superRestore then superRestore();superRestore=nil end
  end
 end)
end
if player.Character then task.spawn(hookHumanoid,player.Character)end
player.CharacterAdded:Connect(hookHumanoid)
Run.Heartbeat:Connect(function()
 local c=alive(player);local hum=c and c:FindFirstChildOfClass('Humanoid')
 if hum and leased(player,'PogoUntil')and player:GetAttribute('Crouching')~=true and hum.FloorMaterial~=Enum.Material.Air
  and hum.MoveDirection.Magnitude>.1 and hum:GetState()~=Enum.HumanoidStateType.Jumping and hum:GetState()~=Enum.HumanoidStateType.Freefall then
  local power=hum.UseJumpPower and hum.JumpPower or hum.JumpHeight
  if power>0 then
   if hops%4==3 and not superRestore then
    -- Super-boing: 1.35x height for this one hop, then put back exactly what was there (owner 2026-10-28: the old 1.7x
    -- cleared walls and got players out of the map; RecoveryRoundServer also brings anyone outside the map back).
    local useP=hum.UseJumpPower;local was=power
    if useP then hum.JumpPower=was*1.16 else hum.JumpHeight=was*1.35 end
    superRestore=function()if hum.Parent then if useP then if hum.JumpPower==was*1.16 then hum.JumpPower=was end elseif hum.JumpHeight==was*1.35 then hum.JumpHeight=was end end end
    task.delay(1.5,function()if superRestore then superRestore();superRestore=nil end end)
    popText('SUPER BOING!',Color3.fromRGB(180,240,90))
   end
   hum:ChangeState(Enum.HumanoidStateType.Jumping) -- not hum.Jump: the ControlModule rewrites Jump every RenderStepped
  end
 end
 -- Boing on landing for every pogo player (replicated root velocity), so everyone hears the hops.
 for _,q in ipairs(Players:GetPlayers())do
  local qc=leased(q,'PogoUntil')and alive(q);local r=qc and qc:FindFirstChild('HumanoidRootPart')
  if r then
   local vy=r.AssemblyLinearVelocity.Y
   if vy<-4 then fallSpeed[q]=math.min(fallSpeed[q]or 0,vy)
   elseif(fallSpeed[q]or 0)<-4 and vy>-1 then
    fallSpeed[q]=nil
    GameplayAudio.Play(cue('PogoBoing','ClownHonk'),r)
    if q==player then squashAt=os.clock()end
   end
  else fallSpeed[q]=nil end
 end
end)

-- PullbackRacer: the zoom (the client owns its character physics), wall bonk ------------------------------
Run.Heartbeat:Connect(function()
 local c=alive(player);local r=c and c:FindFirstChild('HumanoidRootPart')
 local t=now();local untilAt=player:GetAttribute('RacerZoomUntil')or 0
 if r and t<untilAt and not zoom.bonked then
  if not zoom.on then
   local dir=player:GetAttribute('RacerZoomDir');local hum=c:FindFirstChildOfClass('Humanoid')
   local move=hum and hum.MoveDirection or Vector3.zero
   if move.Magnitude>.1 then dir=Vector3.new(move.X,0,move.Z).Unit end
   zoom.on=true;zoom.start=os.clock();zoom.dir=typeof(dir)=='Vector3'and dir or r.CFrame.LookVector;zoom.speed=player:GetAttribute('RacerZoomSpeed')or 30
   popText('ZOOM!',Color3.fromRGB(255,170,60))
  end
  local v=r.AssemblyLinearVelocity
  local flat=Vector3.new(v.X,0,v.Z).Magnitude
  if os.clock()-zoom.start>.18 and flat<zoom.speed*.4 then
   zoom.bonked=true;zoom.on=false;bump(math.rad(4));popText('BONK!',GOLD);GameplayAudio.Play('ItemImpact',r)
  else
   r.AssemblyLinearVelocity=zoom.dir*zoom.speed+Vector3.new(0,v.Y,0)
  end
 elseif zoom.on or zoom.bonked then
  if t>=untilAt then zoom.on=false;zoom.bonked=false end
 end
end)

-- Leftovers when the character goes away.
player.CharacterRemoving:Connect(function()
 zoom.on=false;zoom.bonked=false;superRestore=nil;hops=0
end)
