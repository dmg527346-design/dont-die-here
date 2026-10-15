-- Monster victory cutscene. When the team is wiped (RecoveryRound Phase 'Failed',
-- FailureReason 'TeamWipe'), after this player's jumpscare ends, a short cinematic
-- shows each active monster wrapped in a red aura, then a title card. Local only;
-- RecoveryRoundServer holds the restart long enough for it to finish.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local Lighting=game:GetService('Lighting')
local TweenService=game:GetService('TweenService')
local player=Players.LocalPlayer
local Audio=require(RS:WaitForChild('GameplayAudio'))

-- Timing (seconds) and framing
local INTRO=.55
local SHOT=1.55
local OUTRO=1.6
local MAX_MONSTERS=3
local JUMPSCARE_WAIT=4.5 -- longest wait for this player's jumpscare to clear
local FOV_START,FOV_END=58,38
local AURA=Color3.fromRGB(200,20,24)
local NAMES={Crawler='THE COLLAR CRAWLER',Wraith='THE TEAR WRAITH',Bellhop='THE HAUNTED BELLHOP',Lantern='THE LANTERN WATCHER',Neon='THE NEON TRIPOD'}

local state;repeat state=RS:FindFirstChild('RecoveryRound');if not state then task.wait(.25) end until state
local playing=false

local function smooth(t) t=math.clamp(t,0,1);return t*t*(3-2*t) end
local function activeMonsters()
 local folder=workspace:FindFirstChild('RoamingCreatures');local list={}
 if folder then for _,m in folder:GetChildren() do if m:IsA('Model') and m.PrimaryPart then table.insert(list,m) end end end
 table.sort(list,function(a,b) return a.Name<b.Name end)
 while #list>MAX_MONSTERS do table.remove(list) end
 return list
end

-- Red aura: outline, rising dark smoke, embers and a pulsing light (all local instances).
local function aura(model)
 local made={}
 local h=Instance.new('Highlight');h.FillColor=AURA;h.FillTransparency=.78;h.OutlineColor=Color3.fromRGB(255,70,60);h.OutlineTransparency=0
 h.DepthMode=Enum.HighlightDepthMode.Occluded;h.Adornee=model;h.Parent=model;table.insert(made,h)
 local cf,size=model:GetBoundingBox()
 local anchor=Instance.new('Part');anchor.Name='WinAura';anchor.Anchored=true;anchor.CanCollide=false;anchor.CanQuery=false;anchor.CanTouch=false;anchor.Transparency=1
 anchor.Size=Vector3.new(size.X*1.1,.2,size.Z*1.1);anchor.CFrame=CFrame.new(cf.Position-Vector3.new(0,size.Y/2-.1,0));anchor.Parent=workspace;table.insert(made,anchor)
 local smoke=Instance.new('ParticleEmitter');smoke.Texture='rbxasset://textures/particles/smoke_main.dds'
 smoke.Color=ColorSequence.new(Color3.fromRGB(120,8,12),Color3.fromRGB(18,2,4));smoke.LightEmission=.35
 smoke.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,size.X*.35),NumberSequenceKeypoint.new(1,size.X*.9)})
 smoke.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,.45),NumberSequenceKeypoint.new(1,1)})
 smoke.Lifetime=NumberRange.new(1.2,1.8);smoke.Rate=26;smoke.Speed=NumberRange.new(1.5,3.5);smoke.SpreadAngle=Vector2.new(25,25)
 smoke.Acceleration=Vector3.new(0,size.Y*.6,0);smoke.Rotation=NumberRange.new(-180,180);smoke.RotSpeed=NumberRange.new(-40,40);smoke.Parent=anchor
 local embers=Instance.new('ParticleEmitter');embers.Texture='rbxasset://textures/particles/sparkles_main.dds'
 embers.Color=ColorSequence.new(Color3.fromRGB(255,90,60));embers.LightEmission=1;embers.Size=NumberSequence.new(.18,0)
 embers.Lifetime=NumberRange.new(.8,1.4);embers.Rate=40;embers.Speed=NumberRange.new(2,5);embers.SpreadAngle=Vector2.new(35,35);embers.Acceleration=Vector3.new(0,4,0);embers.Parent=anchor
 local light=Instance.new('PointLight');light.Color=AURA;light.Range=math.max(16,size.Y*2.2);light.Brightness=3;light.Shadows=true;light.Parent=anchor
 return made,light
end

local function buildGui()
 local gui=Instance.new('ScreenGui');gui.Name='MonsterWinCutscene';gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.DisplayOrder=950;gui.ResetOnSpawn=false
 local function bar(y)
  local f=Instance.new('Frame');f.BackgroundColor3=Color3.new(0,0,0);f.BorderSizePixel=0;f.Size=UDim2.new(1,0,0,0);f.AnchorPoint=Vector2.new(0,y);f.Position=UDim2.fromScale(0,y);f.ZIndex=3;f.Parent=gui;return f
 end
 local top,bottom=bar(0),bar(1)
 local fade=Instance.new('Frame');fade.BackgroundColor3=Color3.new(0,0,0);fade.BorderSizePixel=0;fade.Size=UDim2.fromScale(1,1);fade.ZIndex=5;fade.Parent=gui
 local name=Instance.new('TextLabel');name.BackgroundTransparency=1;name.AnchorPoint=Vector2.new(.5,1);name.Position=UDim2.new(.5,0,.86,0);name.Size=UDim2.new(.8,0,0,54)
 name.Font=Enum.Font.Creepster;name.TextScaled=true;name.TextColor3=Color3.fromRGB(235,40,36);name.TextTransparency=1;name.TextStrokeTransparency=1;name.ZIndex=4;name.Parent=gui
 local title=name:Clone();title.AnchorPoint=Vector2.new(.5,.5);title.Position=UDim2.fromScale(.5,.46);title.Size=UDim2.new(.7,0,.2,0);title.Text='THEY WIN';title.Parent=gui
 local sub=name:Clone();sub.AnchorPoint=Vector2.new(.5,0);sub.Position=UDim2.fromScale(.5,.58);sub.Size=UDim2.new(.6,0,0,34);sub.Font=Enum.Font.GothamMedium;sub.TextColor3=Color3.fromRGB(220,200,196);sub.Text='THE HOUSE CLAIMS YOU';sub.Parent=gui
 for _,t in {name,title,sub} do local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=t==title and 120 or t==sub and 26 or 48;limit.Parent=t end
 gui.Parent=player:WaitForChild('PlayerGui')
 return {gui=gui,top=top,bottom=bottom,fade=fade,name=name,title=title,sub=sub}
end

local collisionParams=RaycastParams.new();collisionParams.FilterType=Enum.RaycastFilterType.Include;collisionParams.RespectCanCollide=true
local function framing(model,index)
 local cf,size=model:GetBoundingBox()
 local root=model.PrimaryPart
 local forward=Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z)
 forward=forward.Magnitude>.01 and forward.Unit or Vector3.new(0,0,-1)
 local right=forward:Cross(Vector3.yAxis)
 local side=index%2==0 and 1 or -1
 local height=size.Y
 local focus=cf.Position+Vector3.new(0,height*.12,0)
 local dist=math.max(7,height*1.3)
 local from=focus+forward*dist+right*side*dist*.7-Vector3.new(0,height*.35,0)
 local to=focus+forward*dist*.6+right*side*dist*.2-Vector3.new(0,height*.22,0)
 local map=workspace:FindFirstChild('Mansion');collisionParams.FilterDescendantsInstances={map and map:FindFirstChild('Collision')}
 local function clear(p) local hit=workspace:Raycast(focus,p-focus,collisionParams);return hit and focus+(p-focus).Unit*math.max(2.5,hit.Distance-.6) or p end
 return focus,clear(from),clear(to)
end

local function play()
 if playing then return end
 playing=true
 -- Let this player's own jumpscare finish first.
 local waited=0
 while player:GetAttribute('MonsterJumpscareActive') and waited<JUMPSCARE_WAIT do waited+=task.wait(.1) end
 task.wait(.35)
 if state:GetAttribute('Phase')~='Failed' then playing=false;return end
 local list=activeMonsters()
 local ui=buildGui()
 local camera=workspace.CurrentCamera
 local savedFov=camera.FieldOfView
 -- Every other HUD steps aside for the cutscene and comes back afterwards.
 local hidden={}
 for _,g in player.PlayerGui:GetChildren() do if g:IsA('ScreenGui') and g~=ui.gui and g.Enabled then g.Enabled=false;table.insert(hidden,g) end end
 local grade=Instance.new('ColorCorrectionEffect');grade.Name='MonsterWinGrade';grade.TintColor=Color3.fromRGB(255,196,190);grade.Contrast=.25;grade.Saturation=-.35;grade.Parent=Lighting
 local cleanup={}
 local lights={}
 for _,m in list do local made,light=aura(m);for _,x in made do table.insert(cleanup,x) end;table.insert(lights,light) end
 local shots={}
 for i,m in list do local focus,from,to=framing(m,i);table.insert(shots,{model=m,focus=focus,from=from,to=to}) end
 local total=INTRO+#shots*SHOT+OUTRO
 local started=os.clock()
 local barHeight=.11
 Run:BindToRenderStep('MonsterWinCutscene',Enum.RenderPriority.Last.Value+5,function()
  local t=os.clock()-started
  camera.CameraType=Enum.CameraType.Scriptable
  local shotIndex=math.clamp(math.floor((t-INTRO)/SHOT)+1,1,math.max(1,#shots))
  local shot=shots[shotIndex]
  if shot and t<INTRO+#shots*SHOT then
   local a=smooth((t-INTRO-(shotIndex-1)*SHOT)/SHOT)
   local pos=shot.from:Lerp(shot.to,a)
   local shake=Vector3.new(math.noise(t*6,1),math.noise(t*6,2),0)*.06
   camera.CFrame=CFrame.lookAt(pos,shot.focus+shake)
   camera.FieldOfView=FOV_START+(FOV_END-FOV_START)*a
   ui.name.Text=NAMES[shot.model:GetAttribute('CreatureKind')] or 'THE THING IN THE HOUSE'
   local local_=(t-INTRO-(shotIndex-1)*SHOT)
   ui.name.TextTransparency=1-smooth(local_/.3)*smooth((SHOT-local_)/.25)
  elseif shot then
   -- Hold on the last monster while the title lands.
   local a=smooth((t-INTRO-#shots*SHOT)/OUTRO)
   camera.CFrame=CFrame.lookAt(shot.to:Lerp(shot.to+(shot.to-shot.focus)*.45,a),shot.focus)
   camera.FieldOfView=FOV_END-6*a
   ui.name.TextTransparency=1
  end
  -- Fade in from black, bars slide in, title card in the outro, fade back to black.
  local outroAt=INTRO+#shots*SHOT
  ui.fade.BackgroundTransparency=math.clamp(t/INTRO,0,1)*(1-smooth((t-(total-.45))/.45))
  if t>total-.45 then ui.fade.BackgroundTransparency=1-smooth((t-(total-.45))/.45) end
  local bars=smooth(t/.4)*barHeight;ui.top.Size=UDim2.new(1,0,bars,0);ui.bottom.Size=UDim2.new(1,0,bars,0)
  local titleIn=smooth((t-outroAt)/.35)
  ui.title.TextTransparency=1-titleIn;ui.sub.TextTransparency=1-smooth((t-outroAt-.3)/.4)
  ui.title.Rotation=0;ui.title.Size=UDim2.new(.7+.06*titleIn,0,.2,0)
  for i,l in lights do l.Brightness=2.5+math.sin(t*9+i)*1.2 end
  grade.TintColor=Color3.fromRGB(255,196-30*titleIn,190-30*titleIn)
 end)
 for i=1,#shots do
  task.delay(INTRO+(i-1)*SHOT,function() Audio.Play(i==1 and 'MonsterNotice' or 'MonsterRush') end)
 end
 -- Revive prompt on top of the cutscene while the wipe can still be undone; a revive ends the cutscene early.
 local revive=Instance.new('ScreenGui');revive.Name='MonsterWinRevive';revive.IgnoreGuiInset=true;revive.DisplayOrder=10050;revive.ResetOnSpawn=false;revive.Parent=player.PlayerGui
 local prompt=Instance.new('TextButton');prompt.Name='RevivePrompt';prompt.AnchorPoint=Vector2.new(.5,1);prompt.Position=UDim2.new(.5,0,1,-42);prompt.Size=UDim2.fromOffset(340,46)
 prompt.BackgroundColor3=Color3.fromRGB(167,202,127);prompt.TextColor3=Color3.fromRGB(8,18,22);prompt.Font=Enum.Font.FredokaOne;prompt.TextSize=18;prompt.AutoButtonColor=true;prompt.Parent=revive
 Instance.new('UICorner',prompt).CornerRadius=UDim.new(0,12)
 prompt.Activated:Connect(function()
  local free=player:GetAttribute('Pass_free_revive')and not player:GetAttribute('FreeReviveUsed')
  if free or(player:GetAttribute('ReviveTokens')or 0)>0 then RS:WaitForChild('ReviveEvent'):FireServer()
  else pcall(function()game:GetService('MarketplaceService'):PromptProductPurchase(player,3715702819)end)end
 end)
 local started=os.clock()
 while os.clock()-started<total and state:GetAttribute('Phase')=='Failed' do
  local dead=player:GetAttribute('RoundDead')==true
  local finish=state:GetAttribute('TransitionEnds');local seconds=finish and math.max(0,math.ceil(finish-workspace:GetServerTimeNow()))or 0
  prompt.Visible=state:GetAttribute('WipeRevivable')==true and dead
  prompt.Text=player:GetAttribute('Reviving')and 'REVIVING…' or ('TEAM DOWN - REVIVE (R / Y)'..(seconds>0 and '  '..seconds..'s' or ''))
  task.wait(.1)
 end
 revive:Destroy()
 Run:UnbindFromRenderStep('MonsterWinCutscene')
 for _,x in cleanup do x:Destroy() end
 grade:Destroy();ui.gui:Destroy()
 camera.FieldOfView=savedFov
 -- Revived mid-cutscene: hand the camera back to normal first person (a level change would otherwise reset it).
 local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
 if h and h.Health>0 and player:GetAttribute('RoundDead')~=true then
  camera.CameraType=Enum.CameraType.Custom;camera.CameraSubject=h;player.CameraMode=Enum.CameraMode.LockFirstPerson
 end
 for _,g in hidden do if g.Parent then g.Enabled=true end end
 playing=false
end

local function check()
 if state:GetAttribute('Phase')=='Failed' and state:GetAttribute('FailureReason')=='TeamWipe' and player:GetAttribute('MissionActive')==true then task.spawn(play) end
end
state:GetAttributeChangedSignal('Phase'):Connect(check)
