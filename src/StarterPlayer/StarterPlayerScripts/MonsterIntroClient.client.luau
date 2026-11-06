local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Tween=game:GetService('TweenService')
local UIS=game:GetService('UserInputService')
local SoundService=game:GetService('SoundService')
local Lighting=game:GetService('Lighting')
local Debris=game:GetService('Debris')
local p=Players.LocalPlayer


local REVEAL=3.56 -- the beam whips back onto the Wraith
local LUNGE=3.78 -- it lunges
local CUT=4.26 -- it reaches the lens: hard black
local END=5.4 -- dread line gone; then FADE_OUT back to the level (about 6 s in all)
local FADE_OUT=.45
local LINE='IT HEARD YOU.'
-- Every sound is an existing GameplaySoundCatalog id (no new uploads).
local S={heart='rbxassetid://9043365842',breath='rbxassetid://101395573137763',hiss='rbxassetid://9125475729',
 creak='rbxassetid://9125563505',whisper='rbxassetid://9043347151',giggle='rbxassetid://9116239118',
 click='rbxassetid://128570293170805',screech='rbxassetid://9125474229',scare='rbxassetid://109961399514238',
 sting='rbxassetid://104131914354223',impact='rbxassetid://9117314713',steps='rbxassetid://9120836780'}
local BEAM=Color3.fromRGB(255,238,212)

local function eligible()
 local state=RS:FindFirstChild('RecoveryRound')
 if p:GetAttribute('MissionActive')~=true or not state or(state:GetAttribute('Round')or 1)~=1 then return false end
 if p:GetAttribute('IntroPlayed')then return false end
 return p:GetAttribute('IntroSeen')==false or Run:IsStudio()and RS:GetAttribute('IntroPreview')==true
end
local function ready()
 local state=RS:FindFirstChild('RecoveryRound')
 return eligible()and state:GetAttribute('Phase')=='Searching'and p.Character~=nil and p.Character:FindFirstChild('HumanoidRootPart')~=nil and not p.PlayerGui:FindFirstChild('MansionLoading')
end

local gui,back,cleanup
local function cover() -- solid black at once: nothing of the level shows before the scene
 if gui and gui.Parent then return end
 gui=Instance.new('ScreenGui');gui.Name='MonsterIntro';gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.ResetOnSpawn=false;gui.DisplayOrder=9000
 back=Instance.new('Frame');back.Size=UDim2.fromScale(1,1);back.BackgroundColor3=Color3.new(0,0,0);back.BorderSizePixel=0;back.BackgroundTransparency=0;back.Parent=gui
 gui.Parent=p.PlayerGui
 p:SetAttribute('IntroPlaying',true) -- the guided tutorial waits from the first black frame
end
local function uncover()
 if cleanup then local c=cleanup;cleanup=nil;pcall(c)end
 if gui then gui:Destroy();gui=nil;back=nil end;p:SetAttribute('IntroPlaying',nil)
end

local function edge(parent,anchor,pos,size,rot)
 local f=Instance.new('Frame');f.BackgroundColor3=Color3.new(0,0,0);f.BorderSizePixel=0;f.AnchorPoint=anchor;f.Position=pos;f.Size=size;f.ZIndex=5;f.Parent=parent
 local g=Instance.new('UIGradient');g.Rotation=rot;g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(.55,.55),NumberSequenceKeypoint.new(1,1)});g.Parent=f
end
local function seg(t,a,b)return math.clamp((t-a)/(b-a),0,1)end
local function smooth(a)return a*a*(3-2*a)end
local function rot(v,a)return CFrame.Angles(0,a,0):VectorToWorldSpace(v)end


local function play()
 local folder=RS:WaitForChild('IntroMonsters',15);if not folder then return end
 local char=p.Character;local root=char and char:FindFirstChild('HumanoidRootPart');if not root then return end
 local function pick(...)for _,n in {...}do local m=folder:FindFirstChild(n);if m then return m end end;return nil end
 local srcLunge=pick('TearWraith_BlackNPC','HauntedBellhop_NPC','CollarCrawler_BlackNPC')
 if not srcLunge then return end
 p:SetAttribute('IntroPlaying',true)
 local report=RS:FindFirstChild('TutorialStepEvent') -- analytics (PlayerMetricsServer '1 Tutorial' funnel)
 if report then report:FireServer('introStart')end
 local controls;pcall(function()local pm=p.PlayerScripts:FindFirstChild('PlayerModule');if pm then controls=(require :: any)(pm):GetControls();controls:Disable()end end)
 -- Silence the world (radio, level music, ambience): every SoundGroup goes quiet; the scene's sounds use their own
 -- group (PreferenceAudioMixer would otherwise file them under the muted GameplaySFX).
 local introGroup=SoundService:FindFirstChild('IntroCutscene')or Instance.new('SoundGroup');introGroup.Name='IntroCutscene';introGroup.Volume=1;introGroup.Parent=SoundService
 local muted={};for _,g in SoundService:GetDescendants()do if g:IsA('SoundGroup')and g~=introGroup and g.Volume>0 then muted[g]=g.Volume;g.Volume=0 end end
 cover()
 local skippable=p:GetAttribute('IntroSeen')==true -- shown again: let them skip

 -- Local stage: everything below lives on this client only and is undone by cleanup().
 local cam=workspace.CurrentCamera
 local camType,camFov=cam.CameraType,cam.FieldOfView
 local stage=Instance.new('Folder');stage.Name='MonsterIntroStage';stage.Parent=workspace
 local conns,hiddenGui,hiddenLights,ghost={},{},{},{}
 local grade=Instance.new('ColorCorrectionEffect');grade.Name='MonsterIntroGrade';grade.Saturation=-.5;grade.Contrast=.2;grade.Brightness=-.02;grade.TintColor=Color3.fromRGB(206,220,236);grade.Parent=Lighting
 local blur=Instance.new('BlurEffect');blur.Name='MonsterIntroBlur';blur.Size=0;blur.Parent=Lighting -- speed smear on fast motion
 local lightSet={Ambient=Color3.fromRGB(6,7,10),OutdoorAmbient=Color3.fromRGB(6,7,10),Brightness=0,ExposureCompensation=0}
 local lightOld={};for k,v in lightSet do lightOld[k]=(Lighting :: any)[k];(Lighting :: any)[k]=v end
 local here=root.Position
 -- Every lamp and glowing sign near the player goes dark (spawn camp, boards, map), behind the black cover.
 local skipRoots={};for _,pl in Players:GetPlayers()do if pl.Character then skipRoots[pl.Character]=true end end
 local lf0=workspace:FindFirstChild('LocalFlashlight');if lf0 then skipRoots[lf0]=true end
 local function near(holder)
  local at=holder and(holder:IsA('BasePart')and holder.Position or holder:IsA('Attachment')and holder.WorldPosition)
  return at and(at-here).Magnitude<120
 end
 for _,top in workspace:GetChildren()do
  if not skipRoots[top]and top~=stage and not top:IsA('Terrain')and not top:IsA('Camera')then
   for _,d in top:GetDescendants()do
    if d:IsA('Light')then
     if d.Enabled and near(d.Parent)then d.Enabled=false;hiddenLights[#hiddenLights+1]=d end
    elseif d:IsA('SurfaceGui')or d:IsA('BillboardGui')then
     if d.Enabled and near((d :: any).Adornee or d.Parent)then d.Enabled=false;hiddenGui[d]=true end
    elseif d:IsA('Highlight')then -- loot outlines: nothing glows but your beam
     if d.Enabled then d.Enabled=false;hiddenGui[d]=true end
    elseif d:IsA('BasePart')and d.Material==Enum.Material.Neon and d.Color.R>.45 and d.Color.G<.35 and near(d)then
     ghost[#ghost+1]=d -- red neon (tail lights) would read as red eyes in the dark: hidden locally
    end
   end
  end
 end
 for _,pl in Players:GetPlayers()do
  if pl.Character then for _,d in pl.Character:GetDescendants()do if d:IsA('BasePart')or d:IsA('Decal')then ghost[#ghost+1]=d end end end
 end
 cleanup=function(keepMute:boolean?)
  for _,c in conns do c:Disconnect()end
  pcall(function()Run:UnbindFromRenderStep('MonsterIntroCam')end)
  pcall(function()Run:UnbindFromRenderStep('MonsterIntroLight')end)
  stage:Destroy();grade:Destroy();blur:Destroy()
  for k,v in lightOld do if(Lighting :: any)[k]==lightSet[k]then(Lighting :: any)[k]=v end end
  for _,l in hiddenLights do if l.Parent then l.Enabled=true end end
  for g in hiddenGui do if g.Parent then g.Enabled=true end end
  for _,d in ghost do if d.Parent then d.LocalTransparencyModifier=0 end end
  cam.CameraType=camType==Enum.CameraType.Scriptable and Enum.CameraType.Custom or camType;cam.FieldOfView=camFov
  if not keepMute then for g,v in muted do if g.Parent then g.Volume=v end end end -- aborted: sound back at once
 end


 -- Read the room: the longest open line near where you already look is "down the hall"; the longest opening off to
 -- the side is where the beam drifts while it is quiet.
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
 local ex:{Instance}={stage};for _,pl in Players:GetPlayers()do if pl.Character then ex[#ex+1]=pl.Character end end
 local lf=workspace:FindFirstChild('LocalFlashlight');if lf then ex[#ex+1]=lf end
 params.FilterDescendantsInstances=ex
 local eye=root.Position+Vector3.new(0,1.05,0) -- a little under eye height: crouched, small
 local function clear(from:Vector3,dir:Vector3,max:number)local d=max;for _,h in {0,-1.4}do local r=workspace:Raycast(from+Vector3.new(0,h,0),dir*max,params);if r then d=math.min(d,r.Distance)end end;return d end
 local look=cam.CFrame.LookVector;look=Vector3.new(look.X,0,look.Z);if look.Magnitude<.1 then look=root.CFrame.LookVector*Vector3.new(1,0,1)end;look=look.Unit
 local dirs={}
 for i=0,15 do local a=i*math.pi/8;local d=Vector3.new(math.sin(a),0,math.cos(a));dirs[#dirs+1]={d=d,len=clear(eye,d,60)}end
 table.sort(dirs,function(x,y)return x.len*(1+.35*x.d:Dot(look))>y.len*(1+.35*y.d:Dot(look))end)
 local fwd,dF=dirs[1].d,dirs[1].len
 local side,dS=nil,0
 for _,e in dirs do local c=e.d:Dot(fwd);if c<.5 and c>-.6 and e.len>dS then side,dS=e.d,e.len end end
 if not side then side=fwd:Cross(Vector3.yAxis);dS=clear(eye,side,60)end
 local sideYaw=math.acos(math.clamp(fwd:Dot(side),-1,1));if rot(fwd,-sideYaw):Dot(side)>rot(fwd,sideYaw):Dot(side)then sideYaw=-sideYaw end
 local right=fwd:Cross(Vector3.yAxis).Unit
 local function floorAt(pos:Vector3,fallback:number):number
  local r=workspace:Raycast(Vector3.new(pos.X,eye.Y+1,pos.Z),Vector3.new(0,-16,0),params)
  return r and r.Position.Y or fallback
 end
 local floorY=floorAt(root.Position,root.Position.Y-3)

 -- A real, rigged monster: its root is moved here, CreatureAnimateClient poses its body from the attributes.
 type Mon={m:Model,root:BasePart,lift:number,h:number,y:number,face:Vector3}
 local function prep(src:Instance?,attrs:{[string]:any}):Mon?
  if not src then return nil end
  local m=(src :: Model):Clone()
  local r=m:FindFirstChild('CreatureRoot')
  if not(r and r:IsA('BasePart'))then m:Destroy();return nil end
  m.PrimaryPart=r;r.Anchored=true
  local inv=r.CFrame:Inverse();local low,top,feet=math.huge,-math.huge,math.huge
  for _,d in m:GetDescendants()do
   if d:IsA('BasePart')then
    d.CanCollide=false;d.CanQuery=false;d.CanTouch=false
    if d~=r and d.Transparency<.95 then -- rest-pose height of everything you can see, in root space
     local c=inv*d.CFrame;local s=d.Size*.5
     local ext=math.abs(c.RightVector.Y)*s.X+math.abs(c.UpVector.Y)*s.Y+math.abs(c.LookVector.Y)*s.Z
     low=math.min(low,c.Position.Y-ext);top=math.max(top,c.Position.Y+ext)
     if d.Name:match('^Leg')then feet=math.min(feet,c.Position.Y-ext)end -- stand on the feet, not on hanging hands
    end
   elseif d:IsA('BillboardGui')or d:IsA('Highlight')then d:Destroy()end
  end
  if low==math.huge then low,top=0,6 end
  if feet<math.huge then low=feet end
  if m:GetAttribute('CreatureKind')=='Crawler'then low-=.6 end -- its chase frenzy pitches the body and digs the front feet in
  for k,v in attrs do m:SetAttribute(k,v)end
  return {m=m,root=r,lift=-low,h=top-low,y=floorY,face=fwd}
 end
 -- Feet on the floor: the floor under the root is ray-cast each step (smoothed so a seam never pops it).
 local function move(e:Mon?,pos:Vector3,face:Vector3,dt:number)
  if not e then return end
  local fy=floorAt(pos,e.y);if math.abs(fy-e.y)>2.5 then e.y=fy else e.y+=(fy-e.y)*math.min(1,dt*20)end
  local f=Vector3.new(face.X,0,face.Z);if f.Magnitude>.05 then e.face=f.Unit end
  local at=Vector3.new(pos.X,e.y+e.lift,pos.Z)
  local cf=CFrame.lookAt(at,at+e.face)
  if e.m.Parent~=stage then e.m:PivotTo(cf);e.m.Parent=stage -- whole rig first, so welded fingers keep their offsets
  else e.root.CFrame=cf end
 end
 local function gone(e:Mon?)if e and e.m.Parent then e.m:Destroy()end end

 local crawler=prep(pick('CollarCrawler_BlackNPC','NeonTripod_NPC'),{Walking=true,AIState='Chase',MoveSpeed=26})
 local lunger=prep(srcLunge,{Walking=true,AIState='Chase',MoveSpeed=16})

 -- Beat 1: across the far end of the beam, wall to wall (it comes out of the dark and goes back into it).
 local crossD=math.clamp(dF*.55,8,15)
 local crossMid=eye+fwd*crossD
 local reachL=math.min(clear(crossMid,-right,12)+2.5,9)
 local reachR=math.min(clear(crossMid,right,12)+2.5,9)
 local crossFrom,crossTo=crossMid-right*reachL,crossMid+right*reachR
 local CROSS0=1.48
 local CROSS1=CROSS0+math.clamp((reachL+reachR)/24,.4,.8) -- about 24 studs/s
 -- Beat 2: right there when the beam comes back, then into the lens.
 local wraithAt=math.clamp(dF-1.5,3.2,5.5)
 local lensAt=1.3

 -- Your flashlight, held low in the right hand and lagging the head a touch.
 local lamp=Instance.new('Part');lamp.Name='IntroLamp';lamp.Size=Vector3.one*.2;lamp.Transparency=1;lamp.Anchored=true;lamp.CanCollide=false;lamp.CanQuery=false;lamp.CanTouch=false;lamp.Parent=stage
 local beam=Instance.new('SpotLight');beam.Face=Enum.NormalId.Front;beam.Angle=44;beam.Range=48;beam.Brightness=0;beam.Color=BEAM;beam.Shadows=true;beam.Parent=lamp
 local spill=Instance.new('SpotLight');spill.Face=Enum.NormalId.Front;spill.Angle=92;spill.Range=22;spill.Brightness=0;spill.Color=BEAM;spill.Shadows=false;spill.Parent=lamp

 -- Screen: vignette, cinema bars, film grain, the dread line, the skip hint.
 edge(back,Vector2.new(0,.5),UDim2.fromScale(0,.5),UDim2.fromScale(.36,1),0)
 edge(back,Vector2.new(1,.5),UDim2.fromScale(1,.5),UDim2.fromScale(.36,1),180)
 edge(back,Vector2.new(.5,0),UDim2.fromScale(.5,0),UDim2.fromScale(1,.34),90)
 edge(back,Vector2.new(.5,1),UDim2.fromScale(.5,1),UDim2.fromScale(1,.34),270)
 for _,y in {0,1}do local bar=Instance.new('Frame');bar.AnchorPoint=Vector2.new(0,y);bar.Position=UDim2.fromScale(0,y);bar.Size=UDim2.fromScale(1,.085);bar.BackgroundColor3=Color3.new(0,0,0);bar.BorderSizePixel=0;bar.ZIndex=7;bar.Parent=back end
 local grain={};for i=1,22 do local g=Instance.new('Frame');g.BorderSizePixel=0;g.BackgroundColor3=Color3.fromRGB(200,205,200);g.ZIndex=6;g.Parent=back;grain[i]=g end
 local line=Instance.new('TextLabel');line.Name='DreadLine';line.AnchorPoint=Vector2.new(.5,.5);line.Position=UDim2.fromScale(.5,.5);line.Size=UDim2.new(.86,0,.075,24);line.BackgroundTransparency=1
 line.Font=Enum.Font.SpecialElite;line.TextScaled=true;line.TextColor3=Color3.fromRGB(190,198,192);line.TextTransparency=1;line.ZIndex=9;line.Text=LINE;line.Parent=back
 local lineSize=Instance.new('UITextSizeConstraint');lineSize.MaxTextSize=48;lineSize.Parent=line
 local skip=false
 if skippable then
  local hint=Instance.new('TextLabel');hint.Name='SkipHint';hint.AnchorPoint=Vector2.new(1,1);hint.Position=UDim2.new(1,-24,1,-8);hint.Size=UDim2.fromOffset(150,26);hint.BackgroundTransparency=1
  hint.Font=Enum.Font.SpecialElite;hint.TextScaled=true;hint.TextXAlignment=Enum.TextXAlignment.Right;hint.TextColor3=Color3.fromRGB(150,156,152);hint.TextTransparency=.35;hint.ZIndex=10
  hint.Text=UIS.TouchEnabled and not UIS.KeyboardEnabled and 'TAP TO SKIP'or UIS.GamepadEnabled and not UIS.KeyboardEnabled and 'PRESS A TO SKIP'or 'PRESS ANY KEY TO SKIP';hint.Parent=back
  local hs=Instance.new('UITextSizeConstraint');hs.MaxTextSize=16;hs.Parent=hint
  conns[#conns+1]=UIS.InputBegan:Connect(function(input)
   local k=input.UserInputType
   if k==Enum.UserInputType.Keyboard or k==Enum.UserInputType.MouseButton1 or k==Enum.UserInputType.Touch or k==Enum.UserInputType.Gamepad1 and input.KeyCode~=Enum.KeyCode.Thumbstick1 and input.KeyCode~=Enum.KeyCode.Thumbstick2 then skip=true end
  end)
 end

 local function sfx(id,vol,speed,at:Vector3?)
  local s=Instance.new('Sound');s.SoundId=id;s.Volume=vol;s.PlaybackSpeed=speed or 1;s.SoundGroup=introGroup
  if at then
   local ear=Instance.new('Part');ear.Size=Vector3.one*.2;ear.Transparency=1;ear.Anchored=true;ear.CanCollide=false;ear.CanQuery=false;ear.CanTouch=false;ear.Position=at;ear.Parent=stage
   s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=20;s.RollOffMaxDistance=180;s.Parent=ear
  else s.Parent=gui end
  s:Play();Debris:AddItem(s,7);return s
 end
 local breath=sfx(S.breath,0,.92);breath.Looped=true
 local events={
  {.9,function()sfx(S.creak,.45,.8,eye+fwd*math.min(dF,30)*.8)end},
  {1.2,function()sfx(S.hiss,.8,1.1,crossFrom)end}, -- you hear it before you see it
  {CROSS0+.1,function()sfx(S.steps,.55,1.6,crossMid)end},
  {3.18,function()sfx(S.whisper,.6,.85,eye+fwd*3)end},
  {REVEAL-.04,function()sfx(S.scare,.8,1);sfx(S.screech,.75,1.04,eye+fwd*wraithAt)end},
  {LUNGE,function()if lunger then lunger.m:SetAttribute('AttackPose','Lunge');lunger.m:SetAttribute('AttackPoseAt',workspace:GetServerTimeNow())end end},
  {CUT,function()sfx(S.sting,.5,1);sfx(S.impact,.4,.8)end},
 }
 local nextBeat=.15

 local t,last=0,os.clock()
 local lampCF=cam.CFrame
 local follow=0 -- the head tracks the crawler a little (lags behind it)
 local function frame()
  local now=os.clock();local dt=math.min(now-last,.1);last=now
  local freeze=Run:IsStudio()and RS:GetAttribute('IntroFreezeAt')or nil
  if typeof(freeze)=='number'then t=freeze else t+=dt end
  if skip and t<END then t=END end
  -- world mute, HUDs off, characters hidden (others may switch these back on mid-scene)
  for g in muted do if g.Volume>0 then g.Volume=0 end end
  for _,g in p.PlayerGui:GetChildren()do if g:IsA('LayerCollector')and g~=gui and g.Enabled then g.Enabled=false;hiddenGui[g]=true end end
  for _,d in ghost do d.LocalTransparencyModifier=1 end
  for _,e in events do if not e[3]and t>=e[1]then e[3]=true;pcall(e[2])end end
  -- heartbeat quickens from about 65 to 140 bpm; breathing swells in the silence, catches at the reveal
  if t>=nextBeat and t<CUT+.6 then local s=sfx(S.heart,.3+.3*seg(t,1,REVEAL),.62);s.Name='Beat';nextBeat=t+(.92-.5*seg(t,.5,REVEAL))end
  breath.Volume=t<CUT and .1+.34*seg(t,2.1,3.3)or math.max(0,breath.Volume-dt*.6)
  breath.PlaybackSpeed=.92+.25*seg(t,REVEAL,REVEAL+.2)

  -- Beat 1: the crawler scuttles across (its legs and arms are CreatureAnimateClient's chase cycle).
  local ca=seg(t,CROSS0,CROSS1)
  if crawler and t>=CROSS0-.15 and t<CROSS1+.1 then move(crawler,crossFrom:Lerp(crossTo,ca),crossTo-crossFrom,dt)
  elseif crawler and t>=CROSS1+.1 then gone(crawler);crawler=nil end
  -- Beat 2: the Wraith waits in the dark while you look away, creeps in, then lunges into the lens.
  if lunger then
   if t>=3.2 and t<CUT then
    local k=seg(t,LUNGE,CUT-.04);k=k*k
    local d=t<LUNGE and wraithAt+.9*(1-smooth(seg(t,REVEAL-.3,LUNGE)))or wraithAt+(lensAt-wraithAt)*k
    move(lunger,eye+fwd*d,-fwd,dt)
   elseif t>=CUT then gone(lunger);lunger=nil end
  end

  -- Camera: crouched, handheld, breathing. Follows the crawler a touch, drifts to the side in the quiet, whips back,
  -- flinches from what is there, recoils from the lunge.
  local crawlYaw=0
  if t>=CROSS0 and t<CROSS1+.4 then
   local at=crossFrom:Lerp(crossTo,ca)-eye;crawlYaw=math.clamp(math.atan2(-at:Dot(right),at:Dot(fwd)),-.35,.35)*.45
  end
  follow+=(crawlYaw-follow)*math.min(1,dt*(t<CROSS1 and 7 or 2.5))
  local yaw=follow
  if t>=2.35 and t<3.4 then yaw+=sideYaw*.8*smooth(seg(t,2.35,3.25))
  elseif t>=3.4 and t<REVEAL then yaw+=sideYaw*.8*(1-seg(t,3.4,REVEAL))^3 end -- whip back
  local flinch=seg(t,REVEAL,REVEAL+.07)*(1-.6*seg(t,REVEAL+.12,LUNGE))
  local lunge=seg(t,LUNGE,CUT)
  local passJolt=seg(t,CROSS0+.05,CROSS0+.15)*(1-seg(t,CROSS0+.2,CROSS1+.3))
  local amp=.012+.022*passJolt+.03*seg(t,3.4,3.5)*(1-seg(t,3.5,3.6))+.06*flinch+.05*lunge
  local nx,ny,nz=math.noise(t*1.6,1.3)*1.3+math.noise(t*9,4.1)*.25,math.noise(2.7,t*1.4)*1.3+math.noise(5.2,t*9)*.25,math.noise(t*1.2,8.8)
  local pitch=-.04+.03*passJolt+.11*flinch+.06*lunge
  if lunger and lunger.m.Parent and t>=REVEAL-.05 then -- look UP into its face: it towers over you
   local d=Vector3.new(lunger.root.Position.X-eye.X,0,lunger.root.Position.Z-eye.Z).Magnitude
   local up=math.atan2(lunger.y+lunger.h*.8-eye.Y,math.max(d,1))
   pitch+=math.clamp(up,0,.95)*.8*smooth(seg(t,REVEAL-.05,REVEAL+.12))
  end
  local pos=eye+Vector3.new(0,math.sin(t*2.6)*.05+.05*flinch,0)-fwd*(.4*flinch+.3*smooth(lunge))
  cam.CameraType=Enum.CameraType.Scriptable
  cam.FieldOfView=64+4*flinch-12*smooth(lunge)
  cam.CFrame=CFrame.lookAt(pos,pos+rot(fwd,yaw))*CFrame.Angles(pitch+nx*amp,ny*amp,nz*amp*.8+.06*flinch)
  lampCF=lampCF:Lerp(cam.CFrame*CFrame.new(.45,-.42,-.2)*CFrame.Angles(.03-.05*flinch,0,0),math.min(1,dt*(t>=3.4 and 22 or 12)))
  lamp.CFrame=lampCF
  -- Speed smear on the fast moments only.
  blur.Size=4*passJolt*(1-ca*.6)+6*seg(t,3.42,3.5)*(1-seg(t,3.52,REVEAL+.1))+10*lunge

  -- The beam: steady, a slow brown-out in the quiet, back at the reveal. Nothing faster than 3 Hz.
  local L=1
  if t>=2.95 and t<3.42 then L=1-.7*smooth(seg(t,2.95,3.25))end
  if t>=3.42 and t<REVEAL then L=.3+.7*seg(t,3.42,REVEAL)end
  beam.Brightness=2.3*L;spill.Brightness=.3*L

  -- Screen layers.
  back.BackgroundTransparency=(t<.35 or t>=CUT)and 0 or(t<.85 and smooth(seg(t,.35,.85))or 1)
  line.TextTransparency=1-seg(t,4.45,4.7)+seg(t,5.15,5.35)
  line.Position=UDim2.new(.5,math.random(-1,1),.5,math.random(-1,1))
  for _,g in grain do local s=math.random(1,3);g.Size=UDim2.fromOffset(s,s);g.Position=UDim2.fromScale(math.random(),math.random());g.BackgroundTransparency=.6+math.random()*.35 end
 end
 Run:BindToRenderStep('MonsterIntroCam',Enum.RenderPriority.Camera.Value+1,function()
  local ok,err=pcall(frame)
  if not ok then warn('[MonsterIntro] '..tostring(err));t=END end -- never strand the player on a black screen
 end)
 -- After FlashlightController (Camera+2): every other flashlight stays dark so yours is the only light.
 Run:BindToRenderStep('MonsterIntroLight',Enum.RenderPriority.Camera.Value+3,function()
  local own=workspace:FindFirstChild('LocalFlashlight')
  if own then for _,l in own:GetChildren()do if l:IsA('Light')then l.Brightness=0 end end end
  for _,pl in Players:GetPlayers()do
   local h=pl~=p and pl.Character and pl.Character:FindFirstChild('Head');local a=h and h:FindFirstChild('FlashlightBeam')
   if a then for _,l in a:GetChildren()do if l:IsA('Light')then l.Brightness=0 end end end
  end
 end)

 local started=os.clock()
 while t<END and gui and(os.clock()-started<12 or Run:IsStudio()and RS:GetAttribute('IntroFreezeAt')~=nil)do Run.Heartbeat:Wait()end
 -- Behind the black: give the level back, then fade in on it.
 back.BackgroundTransparency=0
 for _,d in back:GetChildren()do d:Destroy()end
 local c=cleanup;cleanup=nil;if c then c(true)end
 Tween:Create(breath,TweenInfo.new(1),{Volume=0}):Play()
 Tween:Create(back,TweenInfo.new(FADE_OUT),{BackgroundTransparency=1}):Play()
 task.wait(FADE_OUT)
 local done=gui;back.Visible=false;gui=nil;back=nil
 for g,v in muted do if g.Parent then Tween:Create(g,TweenInfo.new(1.2),{Volume=v}):Play()end end
 if controls then pcall(function()controls:Enable()end)end
 p:SetAttribute('IntroPlaying',nil)
 if report then report:FireServer('introDone')end
 task.delay(1.2,function()done:Destroy()end) -- let the last sounds fade
end

task.spawn(function()
 while p.Parent do
  task.wait(.05)
  if eligible()then
   cover()
   if ready()then
    task.wait(.3)
    if eligible()then
     p:SetAttribute('IntroPlayed',true)
     local ok,err=pcall(play)
     if not ok then warn('[MonsterIntro] '..tostring(err));uncover();p:SetAttribute('IntroPlaying',nil)
      pcall(function()(require :: any)(p.PlayerScripts:FindFirstChild('PlayerModule')):GetControls():Enable()end)end
     if gui and p:GetAttribute('IntroPlaying')~=true then uncover()end
     if not(Run:IsStudio()and RS:GetAttribute('IntroPreview')==true)then
      RS:WaitForChild('LobbyEvent'):FireServer(900000000+math.random(1,99999),'introSeen',{})
     end
    end
   end
  elseif gui and not p:GetAttribute('IntroPlayed')then uncover() -- left before it played
  end
  -- Studio preview replays on each new run's level 1.
  if p:GetAttribute('IntroPlayed')and p:GetAttribute('MissionActive')~=true then p:SetAttribute('IntroPlayed',nil)end
 end
end)
