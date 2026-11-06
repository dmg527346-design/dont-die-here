-- Close-up choice panel (owner requests 2026-10-24). Grab a choice prop like any item (InteractController sends the
-- claim): the server gives it to the first player only, the prop turns to stare at them, and a real 3D panel rises
-- out of it, spins round to face them and floats there in the world (a lit slab with a glowing rim, not screen UI).
-- The camera settles on the prop and its panel, colour drains, a heartbeat speeds up as the timer runs out.
-- Everyone else sees the same panel floating over the prop, turned toward the player who is deciding.
--   Keyboard: Y / N (or click the panel; the mouse is freed).  Controller: A = YES, B = NO.  Phone / tablet: tap it.
-- CloseUpChoices (server, under CursedItemsServer) validates everything and sends back results, fortune cards and
-- the pup's wake-up cinematic. This script also animates every choice prop and the walking tea-party dolls on
-- every screen.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local TweenService=game:GetService('TweenService')
local Lighting=game:GetService('Lighting')
local SoundService=game:GetService('SoundService')
local RS=game:GetService('ReplicatedStorage')
local InputHints=require(RS:WaitForChild('InputHints'))
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local player=Players.LocalPlayer

-- Card layout, drawn on the panel's face (old -> new values are reported on every nudge)
local CARD_SIZE=Vector2.new(470,300) -- was 470x262: room for bigger text
local CANVAS_SCALE=2 -- the panel is drawn at 2x so the pixel font stays sharp
local BUTTON_W,BUTTON_H=176,112 -- was 210x150 (owner: too big at rest; the hover pop grows it)
local BUTTON_SIZE=UDim2.fromOffset(BUTTON_W,BUTTON_H)
local BUTTON_Y=96 -- was 82
local HOVER_SCALE,PRESS_SCALE=1.14,.93 -- was 1.08, then 1.14 (its key badge left the panel): the hovered button pops up
local HOVER_LIFT=12 -- pixels the hovered button rises
local PIXEL=Font.new('rbxasset://fonts/families/PressStart2P.json')
local GREEN,GREEN_HOVER=Color3.fromRGB(52,178,94),Color3.fromRGB(86,224,128)
local RED,RED_HOVER=Color3.fromRGB(196,52,64),Color3.fromRGB(240,86,96)
local CARD_TOP,CARD_BOTTOM=Color3.fromRGB(40,30,62),Color3.fromRGB(12,10,20)
local TEXT=Color3.fromRGB(246,240,226)
local WHISPER=Color3.fromRGB(226,218,250) -- was 176,164,214: too dim to read
local GOOD_TONE,BAD_TONE=Color3.fromRGB(140,236,170),Color3.fromRGB(236,120,140)
-- 3D panel (owner 2026-10-24: "a 3D panel in the game that looks at you, not a UI element")
local PANEL_SIZE=Vector2.new(3.76,2.4) -- studs (the 470 x 300 card)
local PANEL_DEPTH,PANEL_RIM=.12,.09 -- slab thickness / glowing rim width (studs)
local PANEL_RISE=.5 -- studs between the top of the prop and the bottom of the panel (was 1.3: it ran into the HUD)
local PANEL_TOWARD=1.1 -- studs from the prop toward the viewer
local PANEL_MAX_DIST=4.2 -- studs from the viewer at most (about 36% of the screen width on every device)
local PANEL_MIN_DIST=2.2 -- studs from the viewer at least (owner 2026-10-25: the card vanished when pulled closer)
local PANEL_VIEW_DIST=3.6 -- (was 4.6: it read too small) nearer than this to the camera the panel shrinks, so it always reads the same size
local PANEL_POP=.5 -- seconds to rise out of the prop and spin round
local HOVER_DIP,HOVER_PUSH=math.rad(2.5),math.rad(4) -- was 7 / 12: a gentle lean toward the hovered side
local PRESS_DIP,PRESS_PUSH=math.rad(5),math.rad(8) -- was 11 / 18: a choice made: that side presses down
local RIM_COLOR=Color3.fromRGB(150,110,240)
local GOLD=Color3.fromRGB(226,188,92)
local TAROT_SIZE=Vector2.new(1.45,2.08) -- studs (the 230 x 330 card canvas)
local TAROT_RISE,TAROT_HOLD,TAROT_FLIP,TAROT_SHOW,TAROT_OUT=.45,.9,.5,4.2,.35 -- seconds of each beat
-- Cinematic
local FOCUS_IN,FOCUS_OUT=.45,.35 -- seconds to settle the camera / give it back
local TYPE_SECONDS=.035 -- per letter of the title
local CAT_TURN_RADIUS=16
local DOLL_WALK_REF=7 -- studs per second that plays the walk clip at normal speed

local event=RS:WaitForChild('CloseUpChoiceEvent',math.huge)
local controls
-- Movement is frozen by the server while you decide (CloseUpChoices.SpeedScale); this also stops Roblox's default
-- controls when the place has them (this game's custom characters do not).
pcall(function()local module=player.PlayerScripts:FindFirstChild('PlayerModule');if module then controls=require(module):GetControls()end end)
local function lockMovement(on)if controls then pcall(function()if on then controls:Disable()else controls:Enable()end end)end end
local function now()return workspace:GetServerTimeNow()end
local function mode()return InputHints.Get()end
local function headOf(userId)
 local q=userId and Players:GetPlayerByUserId(userId);local c=q and q.Character
 local h=c and(c:FindFirstChild('Head')or c:FindFirstChild('HumanoidRootPart'));return h and h.Position
end

-- Screen effects (vignette, shade, toast) -------------------------------------------------------------------------
local gui=Instance.new('ScreenGui');gui.Name='CloseUpChoice';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.DisplayOrder=1000
gui.Parent=player:WaitForChild('PlayerGui')
local shade=Instance.new('Frame');shade.Name='Shade';shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new(0,0,0)
shade.BackgroundTransparency=1;shade.BorderSizePixel=0;shade.Parent=gui
local vignette={}
for i,spec in {{UDim2.fromScale(1,.34),UDim2.fromScale(0,0),90},{UDim2.fromScale(1,.34),UDim2.fromScale(0,.66),-90},{UDim2.fromScale(.3,1),UDim2.fromScale(0,0),0},{UDim2.fromScale(.3,1),UDim2.fromScale(.7,0),180}}do
 local f=Instance.new('Frame');f.Name='Vignette'..i;f.Size=spec[1];f.Position=spec[2];f.BackgroundColor3=Color3.new(0,0,0);f.BorderSizePixel=0
 f.BackgroundTransparency=1;f.Parent=gui
 local g=Instance.new('UIGradient');g.Rotation=spec[3];g.Transparency=NumberSequence.new(0,1);g.Parent=f
 vignette[i]=f
end
-- In first person the mouse is locked: a Modal button on the screen frees it while the panel is up (keyboard + mouse).
local mouseFree=Instance.new('TextButton');mouseFree.Name='MouseFree';mouseFree.BackgroundTransparency=1;mouseFree.Text=''
mouseFree.Size=UDim2.fromOffset(1,1);mouseFree.Parent=gui

local function label(parent,name,size,pos,h,color,align)
 local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.FontFace=PIXEL;t.Text='';t.TextColor3=color or TEXT
 t.TextSize=size;t.TextWrapped=true;t.AnchorPoint=Vector2.new(.5,0);t.Position=pos;t.Size=UDim2.new(1,-32,0,h)
 t.TextXAlignment=align or Enum.TextXAlignment.Center;t.Parent=parent
 local s=Instance.new('UIStroke');s.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;s.Thickness=2;s.Color=Color3.new(0,0,0);s.Transparency=0;s.Parent=t -- was .35: solid outline reads better
 return t
end
local toast=label(gui,'Toast',20,UDim2.new(.5,0,.3,0),80,TEXT);toast.Size=UDim2.new(.8,0,0,80) -- was 14;toast.TextTransparency=1
local function showToast(text,tone,seconds)
 toast.Text=text;toast.TextColor3=tone=='good'and GOOD_TONE or tone=='bad'and BAD_TONE or TEXT;toast.Visible=true
 toast.TextTransparency=1;TweenService:Create(toast,TweenInfo.new(.35),{TextTransparency=0}):Play()
 local stamp=os.clock();toast:SetAttribute('Stamp',stamp)
 task.delay(seconds or 3.2,function()
  if toast:GetAttribute('Stamp')~=stamp then return end
  TweenService:Create(toast,TweenInfo.new(.6),{TextTransparency=1}):Play()
  task.delay(.6,function()if toast:GetAttribute('Stamp')==stamp then toast.Visible=false end end) -- its outline would stay
 end)
end

-- 3D slabs -----------------------------------------------------------------------------------------------------------
-- A lit slab with a glowing rim and its own light; the card UI is drawn on `face`. Parts are local (camera folder).
local holder=Instance.new('Folder');holder.Name='CloseUpChoicePanels'
local function makeSlab(name,size,rimColor,lightColor)
 local model=Instance.new('Model');model.Name=name
 local function part(n,sz,color,mat)
  local p=Instance.new('Part');p.Name=n;p.Size=sz;p.Color=color;p.Material=mat;p.Anchored=true;p.CanCollide=false;p.CanTouch=false
  p.CastShadow=false;p.CanQuery=n=='Face';p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=model;return p
 end
 local face=part('Face',Vector3.new(size.X,size.Y,PANEL_DEPTH),CARD_BOTTOM,Enum.Material.SmoothPlastic)
 local rim=part('Rim',Vector3.new(size.X+PANEL_RIM*2,size.Y+PANEL_RIM*2,PANEL_DEPTH*.6),rimColor,Enum.Material.Neon)
 local light=Instance.new('PointLight');light.Color=lightColor;light.Brightness=1.3;light.Range=10;light.Shadows=false;light.Parent=face
 model.PrimaryPart=face
 return {model=model,face=face,rim=rim,size=size,light=light}
end
-- Place a slab: `s` grows it from nothing (0) to full size (1).
local function placeSlab(slab,cf,s)
 s=math.max(s,.02)
 slab.face.Size=Vector3.new(slab.size.X*s,slab.size.Y*s,PANEL_DEPTH)
 slab.rim.Size=Vector3.new((slab.size.X+PANEL_RIM*2)*s,(slab.size.Y+PANEL_RIM*2)*s,PANEL_DEPTH*.6)
 slab.face.CFrame=cf;slab.rim.CFrame=cf -- thinner than the face and centred in it: an edge on both sides (cards flip)
end
local function surface(name,face,canvas,side,input)
 local sg=Instance.new('SurfaceGui');sg.Name=name;sg.Face=side or Enum.NormalId.Front;sg.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
 sg.CanvasSize=canvas;sg.LightInfluence=0;sg.Brightness=1.25;sg.MaxDistance=90;sg.ResetOnSpawn=false;sg.ClipsDescendants=true
 sg.Adornee=face;sg.Parent=input and player:WaitForChild('PlayerGui')or face -- clickable / tappable panels live in PlayerGui
 -- AlwaysOnTop removed 2026-10-28: with it the card drew as an empty black panel (no title, no YES/NO); the panel already
 -- stands in front of the prop, so a tall prop poking through is the smaller problem.
 return sg
end

-- The panel and its card -------------------------------------------------------------------------------------------
local panel=makeSlab('ChoicePanel',PANEL_SIZE,RIM_COLOR,Color3.fromRGB(176,150,255))
local panelGui=surface('CloseUpChoicePanel',panel.face,CARD_SIZE*CANVAS_SCALE,Enum.NormalId.Front,true)
local card=Instance.new('Frame');card.Name='Card';card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.5);card.Size=UDim2.fromOffset(CARD_SIZE.X,CARD_SIZE.Y)
local cardSharp=Instance.new('UIScale');cardSharp.Scale=CANVAS_SCALE;cardSharp.Parent=card
card.BackgroundColor3=Color3.new(1,1,1);card.BorderSizePixel=0;card.Visible=false;card.Parent=panelGui
local grad=Instance.new('UIGradient');grad.Rotation=90;grad.Color=ColorSequence.new(CARD_TOP,CARD_BOTTOM);grad.Parent=card
local stroke=Instance.new('UIStroke');stroke.Thickness=4;stroke.Color=Color3.fromRGB(150,120,230);stroke.Parent=card
-- Sizes were title 22 / line 10 / hint 9: too small to read on the panel.
-- The size limits count real canvas pixels, which are CANVAS_SCALE times the layout pixels.
local function fit(t,max,min)t.TextScaled=true;local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=max*CANVAS_SCALE;c.MinTextSize=min*CANVAS_SCALE;c.Parent=t end
local title=label(card,'Title',24,UDim2.new(.5,0,0,14),32);fit(title,24,14)
local whisper=label(card,'Whisper',14,UDim2.new(.5,0,0,52),22,WHISPER);fit(whisper,14,10)
local hint=label(card,'Hint',14,UDim2.new(.5,0,0,240),18,Color3.fromRGB(208,200,232))
local timerBack=Instance.new('Frame');timerBack.Name='Timer';timerBack.AnchorPoint=Vector2.new(.5,1);timerBack.Position=UDim2.new(.5,0,1,-10)
timerBack.Size=UDim2.new(1,-40,0,5);timerBack.BackgroundColor3=Color3.fromRGB(40,34,58);timerBack.BorderSizePixel=0;timerBack.Parent=card
Instance.new('UICorner',timerBack).CornerRadius=UDim.new(1,0)
local timerFill=Instance.new('Frame');timerFill.Name='Fill';timerFill.Size=UDim2.fromScale(1,1);timerFill.BackgroundColor3=Color3.fromRGB(170,140,240);timerFill.BorderSizePixel=0;timerFill.Parent=timerBack
Instance.new('UICorner',timerFill).CornerRadius=UDim.new(1,0)

local function makeButton(parent,name,x,base,lit)
 local b=Instance.new('TextButton');b.Name=name;b.AutoButtonColor=false;b.Text='';b.AnchorPoint=Vector2.new(.5,0);b.Position=UDim2.new(x,0,0,BUTTON_Y)
 b.Size=BUTTON_SIZE;b.BackgroundColor3=base;b.BorderSizePixel=0;b.Selectable=false;b.Parent=parent
 Instance.new('UICorner',b).CornerRadius=UDim.new(0,14)
 local s=Instance.new('UIStroke');s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Thickness=3;s.Color=Color3.new(1,1,1);s.Transparency=.75;s.Parent=b
 local sc=Instance.new('UIScale');sc.Parent=b
 local word=label(b,'Word',26,UDim2.new(.5,0,0,8),30,Color3.new(1,1,1)) -- was 32
 local line=label(b,'Line',13,UDim2.new(.5,0,0,44),60,Color3.new(1,1,1)) -- was 15
 local key=Instance.new('TextLabel');key.Name='Key';key.AnchorPoint=Vector2.new(.5,.5);key.Position=UDim2.new(0,8,0,8);key.Size=UDim2.fromOffset(32,32)
 key.BackgroundColor3=Color3.fromRGB(20,16,30);key.TextColor3=Color3.new(1,1,1);key.FontFace=PIXEL;key.TextSize=16;key.Text='';key.Parent=b
 Instance.new('UICorner',key).CornerRadius=UDim.new(1,0)
 local ks=Instance.new('UIStroke');ks.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;ks.Thickness=2;ks.Color=Color3.new(1,1,1);ks.Parent=key
 return {button=b,scale=sc,stroke=s,word=word,line=line,key=key,base=base,lit=lit,x=x}
end
local yes=makeButton(card,'Yes',.26,GREEN,GREEN_HOVER)
local no=makeButton(card,'No',.74,RED,RED_HOVER)
local quick=TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local function hover(e,on)
 TweenService:Create(e.scale,quick,{Scale=on and HOVER_SCALE or 1}):Play()
 TweenService:Create(e.button,quick,{Position=UDim2.new(e.x,0,0,BUTTON_Y-(on and HOVER_LIFT or 0))}):Play() -- the hovered button pops up
 TweenService:Create(e.button,quick,{BackgroundColor3=on and e.lit or e.base}):Play()
 TweenService:Create(e.stroke,quick,{Transparency=on and .05 or .75}):Play()
end
for _,e in {yes,no}do
 e.button.MouseEnter:Connect(function()hover(e,true)end)
 e.button.MouseLeave:Connect(function()hover(e,false)end)
 e.button.MouseButton1Down:Connect(function()TweenService:Create(e.scale,quick,{Scale=PRESS_SCALE}):Play()end)
end

-- The fortune card: a real card in front of you. Its back faces you, then it flips over to show its face.
local tarotSlab=makeSlab('FortuneCard',TAROT_SIZE,GOLD,Color3.fromRGB(255,214,140))
local tarotBackGui=surface('CardBack',tarotSlab.face,Vector2.new(230,330)*CANVAS_SCALE,Enum.NormalId.Front,false)
local tarotFrontGui=surface('CardFace',tarotSlab.face,Vector2.new(230,330)*CANVAS_SCALE,Enum.NormalId.Back,false)
local function sharp(f)f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(230,330);local u=Instance.new('UIScale');u.Scale=CANVAS_SCALE;u.Parent=f end
local cardBack=Instance.new('Frame');cardBack.BackgroundColor3=Color3.fromRGB(30,22,52);cardBack.Parent=tarotBackGui;sharp(cardBack)
local backStroke=Instance.new('UIStroke');backStroke.Thickness=6;backStroke.Color=GOLD;backStroke.Parent=cardBack
local backEmblem=Instance.new('Frame');backEmblem.AnchorPoint=Vector2.new(.5,.5);backEmblem.Position=UDim2.fromScale(.5,.5);backEmblem.Size=UDim2.fromOffset(110,110)
backEmblem.Rotation=45;backEmblem.BackgroundColor3=Color3.fromRGB(18,14,30);backEmblem.Parent=cardBack
local backEmblemStroke=Instance.new('UIStroke');backEmblemStroke.Thickness=5;backEmblemStroke.Color=GOLD;backEmblemStroke.Parent=backEmblem
local backMark=label(cardBack,'Mark',46,UDim2.new(.5,0,.5,-24),50,GOLD)
backMark.Text='?'
local tarot=Instance.new('Frame');tarot.Name='Tarot'
tarot.BackgroundColor3=Color3.fromRGB(30,22,52);tarot.BorderSizePixel=0;tarot.Parent=tarotFrontGui;sharp(tarot)
local tarotStroke=Instance.new('UIStroke');tarotStroke.Thickness=6;tarotStroke.Color=GOLD;tarotStroke.Parent=tarot
-- The emblem: a gold diamond with the card's letter in it (pixel glyphs like ~ read as specks at this size).
local emblem=Instance.new('Frame');emblem.Name='Emblem';emblem.AnchorPoint=Vector2.new(.5,.5);emblem.Position=UDim2.new(.5,0,0,120)
emblem.Size=UDim2.fromOffset(92,92);emblem.Rotation=45;emblem.BackgroundColor3=Color3.fromRGB(18,14,30);emblem.Parent=tarot
local emblemStroke=Instance.new('UIStroke');emblemStroke.Thickness=4;emblemStroke.Color=GOLD;emblemStroke.Parent=emblem
local tarotSymbol=label(tarot,'CardSymbol',40,UDim2.new(.5,0,0,100),44,GOLD)
local tarotName=label(tarot,'CardName',16,UDim2.new(.5,0,0,22),22,TEXT) -- was 13
local tarotText=label(tarot,'CardText',14,UDim2.new(.5,0,0,190),120,WHISPER) -- was 9
local tarotShow -- {start}
local function showCard(c)
 tarot.BackgroundColor3=c.good and Color3.fromRGB(30,52,46)or Color3.fromRGB(56,22,40)
 tarotName.Text=c.name;tarotSymbol.Text=c.symbol;tarotText.Text=c.text
 tarotSymbol.TextColor3=c.good and GOOD_TONE or BAD_TONE;emblemStroke.Color=c.good and GOOD_TONE or BAD_TONE
 tarotSlab.rim.Color=c.good and GOOD_TONE or GOLD
 tarotShow={start=os.clock()};tarotSlab.model.Parent=holder
end

-- Grade, heartbeat --------------------------------------------------------------------------------------------
local grade=Instance.new('ColorCorrectionEffect');grade.Name='CloseUpChoiceGrade';grade.Enabled=true;grade.Parent=Lighting
-- The grade also tints the panel (it is part of the world), so it drains colour gently; `dark` adds a flat shade.
local function setGrade(on,seconds,dark)
 TweenService:Create(grade,TweenInfo.new(seconds or .4),on and{Saturation=-.3,Contrast=.14,Brightness=-.03,TintColor=Color3.fromRGB(222,222,244)}or{Saturation=0,Contrast=0,Brightness=0,TintColor=Color3.new(1,1,1)}):Play()
 TweenService:Create(shade,TweenInfo.new(seconds or .4),{BackgroundTransparency=on and 1-(dark or 0)or 1}):Play()
 for _,f in vignette do TweenService:Create(f,TweenInfo.new(seconds or .4),{BackgroundTransparency=on and 0 or 1}):Play()end
end
local heart=Instance.new('Sound');heart.Name='ChoiceHeartbeat';heart.SoundId=Sounds.Heartbeat and Sounds.Heartbeat.id or '';heart.Looped=true;heart.Volume=.5;heart.Parent=SoundService
local sting=Instance.new('Sound');sting.Name='ChoiceSting';sting.SoundId=Sounds.MirrorSting and Sounds.MirrorSting.id or '';sting.Volume=.35;sting.Parent=SoundService

-- Camera ------------------------------------------------------------------------------------------------------
-- One override after the camera module: blend toward a cinematic CFrame, then give control back smoothly.
local cine={weight=0,target=0,get=nil,shake=0}
local panelCam -- {type, start, t0}: the held camera while the panel is up
local panelAnim={alpha=0,target=0,prop=nil,spot=nil,yaw=0,roll=0,base=nil,pressed=nil} -- the panel grows out of the prop (0 = gone, 1 = full size, facing you)
local wakeLast -- where the pup was, after it burst
Run:BindToRenderStep('CloseUpChoiceCamera',Enum.RenderPriority.Camera.Value+1,function(dt)
 local cam=workspace.CurrentCamera;if not cam then return end
 if panelCam then
  local spot=panelAnim.spot
  if spot then
   local w=math.clamp((os.clock()-panelCam.t0)/FOCUS_IN,0,1);w=w*w*(3-2*w)
   cam.CFrame=panelCam.start:Lerp(CFrame.lookAt(panelCam.start.Position,spot.top:Lerp(spot.final,.8)),w)
  end
  return
 end
 local rate=cine.target>cine.weight and 1/FOCUS_IN or 1/FOCUS_OUT
 cine.weight=math.clamp(cine.weight+math.sign(cine.target-cine.weight)*rate*dt,0,1)
 if cine.weight<=0 or not cine.get then return end
 local goal=cine.get(cam);if not goal then return end
 local w=cine.weight;w=w*w*(3-2*w)
 local cf=cam.CFrame:Lerp(goal,w)
 if cine.shake>0 then local t=os.clock();cf*=CFrame.Angles(math.noise(t*21,1)*cine.shake,math.noise(t*25,2)*cine.shake,math.noise(t*17,3)*cine.shake*.5)end
 cam.CFrame=cf
end)
local function focusOn(getPoint,dolly)
 cine.get=function(cam)
  local p=getPoint();if not p then return nil end
  local from=cam.CFrame.Position;local dir=p-from
  if dir.Magnitude<.5 then return nil end
  return CFrame.lookAt(from+dir.Unit*math.min(dolly or 0,dir.Magnitude-2),p)
 end
 cine.target=1
end
-- Panel open: look between the prop and its panel.
local panelPos
local function focusPanel(prop)
 cine.get=function(cam)
  local spot=panelAnim.spot;if not spot or not panelPos then return nil end
  return CFrame.lookAt(cam.CFrame.Position,spot.top:Lerp(spot.final,.8)) -- a fixed point: the camera never moves (walls)
 end
 cine.target=1
end
local function releaseCamera()cine.target=0;cine.shake=0 end
-- While the panel is up the camera is fully ours (Scriptable) and does not move at all: the first-person camera
-- re-locks the mouse and turns the character every frame, and fighting it made the view tremble (owner: "shaky").
local function holdCamera(on)
 local cam=workspace.CurrentCamera;if not cam then return end
 if on and not panelCam then
  panelCam={type=cam.CameraType,start=cam.CFrame,t0=os.clock()};cam.CameraType=Enum.CameraType.Scriptable
 elseif not on and panelCam then
  cam.CameraType=panelCam.type==Enum.CameraType.Scriptable and Enum.CameraType.Custom or panelCam.type;panelCam=nil
 end
end

-- The open panel -------------------------------------------------------------------------------------------------
local open -- {prop, deadline, total}
local function setKeys()
 local m=mode()
 yes.key.Visible=m~='touch';no.key.Visible=m~='touch'
 yes.key.Text=m=='pad'and InputHints.Button('ButtonA')or 'Y'
 no.key.Text=m=='pad'and InputHints.Button('ButtonB')or 'N'
 -- PlayStation: the keys show the real cross / circle art, so the hint line does not spell out 'Cross' / 'Circle'.
 local ps=m=='pad'and InputHints.Glyph(yes.key,'ButtonA');if m=='pad'then InputHints.Glyph(no.key,'ButtonB')else InputHints.Glyph(yes.key,'Unknown');InputHints.Glyph(no.key,'Unknown')end
 hint.Text=ps and 'Press a button to choose'or m=='pad'and(InputHints.Button('ButtonA')..' = YES     '..InputHints.Button('ButtonB')..' = NO')or m=='touch'and 'Tap YES or NO'or 'Press Y or N'
end
local function typeTitle(text)
 local stamp=os.clock();title:SetAttribute('Stamp',stamp)
 title.Text=''
 task.spawn(function()
  for i=1,#text do
   if title:GetAttribute('Stamp')~=stamp then return end
   title.Text=text:sub(1,i);task.wait(TYPE_SECONDS)
  end
 end)
end
-- Cinematic: the HUD (quota, tutorial tip, grab prompt, crosshair) would draw over the panel, so every other screen
-- GUI is hidden while you decide and exactly those are shown again afterwards.
local hiddenHud={}
local function hudPrompt(on)
 if on then
  for g in hiddenHud do if g.Parent then g.Enabled=true end end
  table.clear(hiddenHud)
 else
  for _,g in player.PlayerGui:GetChildren()do
   if g:IsA('ScreenGui')and g~=gui and g.Enabled then hiddenHud[g]=true;g.Enabled=false end
  end
 end
end
local function closeCard(silent)
 if not open then return end
 open=nil
 CAS:UnbindAction('ChoiceYes');CAS:UnbindAction('ChoiceNo');CAS:UnbindAction('ChoiceFreeze')
 mouseFree.Modal=false;UIS.MouseIconEnabled=true
 hover(yes,false);hover(no,false)
 panelAnim.target=0
 heart:Stop();setGrade(false,.5);releaseCamera();holdCamera(false);lockMovement(false);hudPrompt(true)
 if not silent then sting:Play()end
end
local function answer(choice)
 local o=open;if not o then return end
 local e=choice=='yes'and yes or no
 TweenService:Create(e.scale,quick,{Scale=PRESS_SCALE}):Play()
 panelAnim.pressed=choice -- that side slams down as the panel sinks away
 closeCard(true)
 event:FireServer('answer',o.prop,choice)
end
local function bindKeys()
 -- No walking or jumping while the card is up (owner 2026-10-25: a controller could still walk; admin speed skips
 -- the server's SpeedScale freeze). Sinks every move input above the default controls.
 local K=Enum.KeyCode
 CAS:BindActionAtPriority('ChoiceFreeze',function()return Enum.ContextActionResult.Sink end,false,3001,K.W,K.A,K.S,K.D,K.Up,K.Down,K.Left,K.Right,K.Space,K.Thumbstick1,K.DPadUp,K.DPadDown,K.DPadLeft,K.DPadRight)
 local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid');if h then h:Move(Vector3.zero)end
 CAS:BindActionAtPriority('ChoiceYes',function(_,st)if st==Enum.UserInputState.Begin then answer('yes')end;return Enum.ContextActionResult.Sink end,false,3000,Enum.KeyCode.Y,Enum.KeyCode.ButtonA)
 CAS:BindActionAtPriority('ChoiceNo',function(_,st)if st==Enum.UserInputState.Begin then answer('no')end;return Enum.ContextActionResult.Sink end,false,3000,Enum.KeyCode.N,Enum.KeyCode.ButtonB)
end
yes.button.Activated:Connect(function()answer('yes')end)
no.button.Activated:Connect(function()answer('no')end)
-- Pointing at the panel ourselves: a ray from the cursor / finger to the panel's face, then which button is under it.
-- (SurfaceGui input does not reach this panel reliably; this works the same for mouse and touch.)
local BUTTON_RECTS={yes={.26*CARD_SIZE.X-BUTTON_W/2,BUTTON_Y,.26*CARD_SIZE.X+BUTTON_W/2,BUTTON_Y+BUTTON_H},no={.74*CARD_SIZE.X-BUTTON_W/2,BUTTON_Y,.74*CARD_SIZE.X+BUTTON_W/2,BUTTON_Y+BUTTON_H}}
local function buttonAt(viewportPoint)
 local cam=workspace.CurrentCamera;local face=panel.face
 if not open or not cam or not face.Parent then return nil end
 local ray=cam:ViewportPointToRay(viewportPoint.X,viewportPoint.Y)
 -- the panel at rest, before the hover tilt: a tilted side must not slide out from under the pointer and flap
 local base=panelAnim.base or face.CFrame
 local normal=base.LookVector;local planePoint=base.Position+normal*face.Size.Z*.5
 local denom=ray.Direction:Dot(normal);if math.abs(denom)<1e-4 then return nil end
 local dist=(planePoint-ray.Origin):Dot(normal)/denom;if dist<0 then return nil end
 local p=base:PointToObjectSpace(ray.Origin+ray.Direction*dist)
 local x,y=(.5-p.X/face.Size.X)*CARD_SIZE.X,(.5-p.Y/face.Size.Y)*CARD_SIZE.Y -- canvas pixels (x runs toward -X on the front)
 for name,r in BUTTON_RECTS do if x>=r[1]and x<=r[3]and y>=r[2]and y<=r[4]then return name end end
end
local hovered
local function setHovered(name)
 if name==hovered then return end
 if hovered then hover(hovered=='yes'and yes or no,false)end
 hovered=name
 if name then hover(name=='yes'and yes or no,true)end
end
UIS.InputBegan:Connect(function(input)
 if not open then return end
 local point
 if input.UserInputType==Enum.UserInputType.MouseButton1 then point=UIS:GetMouseLocation()
 elseif input.UserInputType==Enum.UserInputType.Touch then point=Vector2.new(input.Position.X,input.Position.Y)+game:GetService('GuiService'):GetGuiInset()end
 local name=point and buttonAt(point)
 if name then answer(name)end
end)

local function openCard(prop,copy)
 if open then closeCard(true)end
 open={prop=prop,deadline=copy.deadline,total=math.max(1,copy.deadline-now())}
 whisper.Text=copy.whisper or '';whisper.TextTransparency=1
 yes.word.Text=copy.yes[1];yes.line.Text=copy.yes[2];no.word.Text=copy.no[1];no.line.Text=copy.no[2]
 setKeys();typeTitle(copy.title)
 card.Visible=true;panelAnim.prop=prop;panelAnim.target=1;panelAnim.alpha=0;panelAnim.spot=nil;panelAnim.pressed=nil;panelAnim.yaw=0;panelAnim.roll=0;panel.model.Parent=holder
 task.delay(.5,function()if open and open.prop==prop then TweenService:Create(whisper,TweenInfo.new(.6),{TextTransparency=0}):Play()end end)
 mouseFree.Modal=mode()=='kb';UIS.MouseIconEnabled=true
 bindKeys();lockMovement(true);setGrade(true,.45);hudPrompt(false)
 heart.PlaybackSpeed=.7;heart.TimePosition=0;heart:Play();sting:Play()
 holdCamera(true)
end

-- Second set (2026-10-25): the hungry chest's 15-second countdown and the jack-in-the-box crank. Both feel like the
-- Lantern chase: a big countdown on a steady card, a racing heartbeat and ticking. The crank is wound by LOOKING
-- up, then down (the camera itself: mouse, right stick or a finger drag, owner 2026-10-25); a vertical bar fills
-- from red to green.
local CRANK_PITCH_PAD=math.rad(2.5) -- controllers: a much smaller look counts (owner 2026-10-25)
local CRANK_PITCH=math.rad(6) -- look this far above / below level for one stroke (was 16: owner wanted it a lot tighter)
local raceCard=Instance.new('Frame');raceCard.Name='ChoiceRace';raceCard.AnchorPoint=Vector2.new(.5,0);raceCard.Position=UDim2.new(.5,0,0,70)
raceCard.Size=UDim2.fromOffset(440,112);raceCard.BackgroundColor3=Color3.fromRGB(14,12,22);raceCard.BackgroundTransparency=.2;raceCard.BorderSizePixel=0;raceCard.Visible=false;raceCard.Parent=gui
Instance.new('UICorner',raceCard).CornerRadius=UDim.new(0,14)
local raceStroke=Instance.new('UIStroke');raceStroke.Thickness=3;raceStroke.Color=Color3.fromRGB(150,120,230);raceStroke.Parent=raceCard
local raceSize=Instance.new('UISizeConstraint');raceSize.Parent=raceCard
local urgent=label(raceCard,'Count',52,UDim2.new(.5,0,0,8),56,TEXT);urgent.TextWrapped=false
local urgentScale=Instance.new('UIScale');urgentScale.Parent=urgent
local urgentSub=label(raceCard,'Line',16,UDim2.new(.5,0,0,70),34,TEXT)
-- The crank bar: a tall bar at the right of the screen, filled from the bottom, red when empty and green when full.
local bar=Instance.new('Frame');bar.Name='CrankBar';bar.AnchorPoint=Vector2.new(.5,.5);bar.Position=UDim2.new(.78,0,.55,0);bar.Size=UDim2.fromOffset(54,250)
bar.BackgroundColor3=Color3.fromRGB(20,16,30);bar.BorderSizePixel=0;bar.Visible=false;bar.Parent=gui
Instance.new('UICorner',bar).CornerRadius=UDim.new(0,12)
local barStroke=Instance.new('UIStroke');barStroke.Thickness=3;barStroke.Color=Color3.new(1,1,1);barStroke.Parent=bar
local barFill=Instance.new('Frame');barFill.Name='Fill';barFill.AnchorPoint=Vector2.new(.5,1);barFill.Position=UDim2.new(.5,0,1,-5);barFill.Size=UDim2.new(1,-10,0,0)
barFill.BorderSizePixel=0;barFill.Parent=bar
Instance.new('UICorner',barFill).CornerRadius=UDim.new(0,8)
local arrowUp=label(bar,'Up',22,UDim2.new(.5,0,0,-40),30,TEXT);arrowUp.Size=UDim2.fromOffset(160,30);arrowUp.Text='UP'
local arrowDown=label(bar,'Down',22,UDim2.new(.5,0,1,10),30,TEXT);arrowDown.Size=UDim2.fromOffset(160,30);arrowDown.Text='DOWN'
local EMPTY_COLOR,FULL_COLOR=Color3.fromRGB(220,62,62),Color3.fromRGB(70,224,112)
local dots=label(gui,'ChoiceDots',90,UDim2.new(.5,0,.16,0),110,TEXT);dots.Size=UDim2.new(.9,0,0,110);dots.Visible=false
local dotsScale=Instance.new('UIScale');dotsScale.Parent=dots
local tickSound=Instance.new('Sound');tickSound.Name='ChoiceTick';tickSound.SoundId=Sounds.ClockTick and Sounds.ClockTick.id or '';tickSound.Volume=.7;tickSound.Parent=SoundService
local race -- {kind, prop, deadline, total, need, lastSecond, want ('up'|'down'), push}
-- Third set (2026-10-27): the staring owl. A ring in the middle of the screen; keep the flying owl inside it. The
-- owl's path is computed from attributes the server set (OwlFrame, OwlStart, OwlRadius, OwlHeight, OwlToward), so
-- every screen and the server agree on where it is without sending its position.
local OWL_AIM_KB,OWL_AIM_PAD=1.6,2.3 -- studs between the screen-centre ray and the owl that still count as looking
local owlRing=Instance.new('Frame');owlRing.Name='OwlRing';owlRing.AnchorPoint=Vector2.new(.5,.5);owlRing.Position=UDim2.fromScale(.5,.5)
owlRing.Size=UDim2.fromOffset(84,84);owlRing.BackgroundTransparency=1;owlRing.Visible=false;owlRing.Parent=gui
Instance.new('UICorner',owlRing).CornerRadius=UDim.new(1,0)
local owlRingStroke=Instance.new('UIStroke');owlRingStroke.Thickness=4;owlRingStroke.Color=Color3.new(1,1,1);owlRingStroke.Parent=owlRing
local owlRingScale=Instance.new('UIScale');owlRingScale.Parent=owlRing
local function owlSpot(m,e) -- the same point as ExtraChoices2's owlSpot
 local frame=m:GetAttribute('OwlFrame');if typeof(frame)~='CFrame'then return nil,nil end
 local radius,height,toward=m:GetAttribute('OwlRadius')or 3,m:GetAttribute('OwlHeight')or 2,m:GetAttribute('OwlToward')or 1
 local lift=math.min(1,e/.7);local a=e*(1.1+e*.12)
 return frame*Vector3.new(math.sin(a)*radius*lift,height*lift+math.sin(a*2)*.9*lift,-toward*lift),frame
end
local function stepOwlRace(cam)
 local prop=race.prop;local start=prop:GetAttribute('OwlStart')or now()
 local f=math.clamp((prop:GetAttribute('OwlStare')or 0)/(race.need or 5),0,1)
 barFill.Size=UDim2.new(1,-10,f,-10*f);barFill.BackgroundColor3=EMPTY_COLOR:Lerp(FULL_COLOR,f)
 arrowUp.Text='STARE';arrowDown.Text='';arrowUp.TextColor3=FULL_COLOR
 local spot=owlSpot(prop,math.max(0,now()-start));local on=false
 if cam and spot then
  local rel=spot-cam.CFrame.Position;local look=cam.CFrame.LookVector;local along=rel:Dot(look)
  on=along>0 and(rel-look*along).Magnitude<=(mode()=='kb'and OWL_AIM_KB or OWL_AIM_PAD)
 end
 owlRingStroke.Color=on and FULL_COLOR or Color3.new(1,1,1);owlRingScale.Scale=on and 1+.08*math.sin(os.clock()*12)or 1
 if on and os.clock()-(race.lastStare or 0)>=.2 then race.lastStare=os.clock();event:FireServer('stare',prop)end
 local m=mode()
 urgentSub.Text=m=='touch'and'Drag to keep the OWL in the circle!'or m=='pad'and'Keep the OWL in the circle with the right stick!'or'Keep the OWL in the circle with the mouse!'
end
local function crank(dir) -- one half-turn: the next stroke must go the other way
 if not race or race.kind~='jack'or dir~=race.want then return end
 race.want=dir=='up'and 'down'or 'up';race.push=0
 event:FireServer('wind',race.prop)
end
-- Controller: a flick of the right stick up or down counts on its own (the camera turns slowly on a stick).
UIS.InputChanged:Connect(function(input)
 if race and race.kind=='jack'and input.KeyCode==Enum.KeyCode.Thumbstick2 then
  local y=input.Position.Y;if y>.45 then crank('up')elseif y<-.45 then crank('down')end
 end
end)
local function endRace()
 if not race then return end
 race=nil;raceCard.Visible=false;bar.Visible=false;owlRing.Visible=false
 heart:Stop();setGrade(false,.4);releaseCamera()
end
local function startRace(kind,prop,data)
 endRace()
 race={kind=kind,prop=prop,deadline=data.deadline,total=math.max(1,data.deadline-now()),need=data.need,lastSecond=nil,want='up',push=0}
 raceCard.Visible=true;heart.PlaybackSpeed=.9;heart.TimePosition=0;heart:Play();sting:Play();setGrade(true,.3)
 if kind=='jack'or kind=='owl'then
  bar.Visible=true
 end
 owlRing.Visible=kind=='owl'
end
local function showDots()
 dots.Text='';dots.Visible=true;dots.TextTransparency=0
 task.spawn(function()
  task.wait(.3)
  for i=1,3 do
   dots.Text=string.rep('.',i);tickSound.PlaybackSpeed=1.4;tickSound:Play()
   dotsScale.Scale=1.25;TweenService:Create(dotsScale,TweenInfo.new(.2,Enum.EasingStyle.Back),{Scale=1}):Play()
   task.wait(.6)
  end
  task.wait(1.6);TweenService:Create(dots,TweenInfo.new(.8),{TextTransparency=1}):Play();task.wait(.8);dots.Visible=false
 end)
end
local function extraCinematic(what,prop,data)
 data=data or {}
 if what=='chestTimer'then startRace('chest',prop,data);return true
 elseif what=='mailTimer'then startRace('mail',prop,data);return true
 elseif what=='owlStare'then startRace('owl',prop,data);return true
 elseif what=='owlDone'then endRace();if not data.won then sting:Play()end;return true
 elseif what=='jackWind'then startRace('jack',prop,data);return true
 elseif what=='chestDone'or what=='jackDone'or what=='mailDone'then endRace();return true end
 return false
end
Run.RenderStepped:Connect(function()
 if not race then return end
 local t=os.clock();local left=math.max(0,race.deadline-now());local k=left/race.total
 if race.prop and not race.prop.Parent then endRace();return end
 local cam=workspace.CurrentCamera;raceSize.MaxSize=Vector2.new(cam and cam.ViewportSize.X*.9 or 440,112)
 local sec=math.ceil(left)
 if sec~=race.lastSecond then
  race.lastSecond=sec;tickSound.PlaybackSpeed=1+(1-k)*.6;tickSound:Play()
  urgentScale.Scale=1.3;TweenService:Create(urgentScale,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=1}):Play()
 end
 urgent.Text=tostring(sec);urgent.TextColor3=TEXT:Lerp(BAD_TONE,1-k);raceStroke.Color=Color3.fromRGB(150,120,230):Lerp(BAD_TONE,1-k)
 heart.PlaybackSpeed=.9+(1-k)*1.5
 if race.kind=='owl'then stepOwlRace(cam)
 elseif race.kind=='mail'then
  urgentSub.Text=mode()=='touch'and'MAIL IT! Drop an item by its door!'or'MAIL IT! Hold an item up to its door!'
 elseif race.kind=='chest'then
  urgentSub.Text='FEED THE CHEST! Put an item in its mouth!'
 else
  local winds=race.prop:GetAttribute('JackWinds')or 0;local need=race.need or 24;local f=math.clamp(winds/need,0,1)
  barFill.Size=UDim2.new(1,-10,f,-10*f);barFill.BackgroundColor3=EMPTY_COLOR:Lerp(FULL_COLOR,f)
  local m=mode();local up=race.want=='up'
  arrowUp.TextColor3=up and FULL_COLOR or Color3.fromRGB(120,114,140);arrowDown.TextColor3=up and Color3.fromRGB(120,114,140)or FULL_COLOR
  arrowUp.Text='LOOK UP';arrowDown.Text='LOOK DOWN'
  local pitch=cam and math.asin(math.clamp(cam.CFrame.LookVector.Y,-1,1))or 0
  local need=m=='pad'and CRANK_PITCH_PAD or CRANK_PITCH
  if up and pitch>need then crank('up')elseif not up and pitch<-need then crank('down')end
  urgentSub.Text=m=='touch'and 'Drag to LOOK UP and DOWN to wind it!'or m=='pad'and 'LOOK UP and DOWN with the right stick!'or 'LOOK UP and DOWN with the mouse to wind it!'
 end
 if left<=0 and(race.kind=='chest'or race.kind=='mail')then endRace()end
end)
-- Danger marks: monsters the bird found and the item the ghost found glow for a few seconds on every screen.
local marks={} -- model -> Highlight
local markAcc=0
Run.Heartbeat:Connect(function(dt)
 markAcc+=dt;if markAcc<.25 then return end;markAcc=0
 local t=now();local want={}
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,m in folder:GetChildren()do
  if t<(m:GetAttribute('DangerMarkUntil')or 0)then want[m]='danger'elseif t<(m:GetAttribute('IceMarkUntil')or 0)then want[m]='ice'end -- ice: the Frosty Fridge froze it
 end end
 local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
 if items then for _,m in items:GetChildren()do if t<(m:GetAttribute('GhostMarkUntil')or 0)then want[m]='ghost'end end end
 for m,h in marks do if not want[m]or not m.Parent then h:Destroy();marks[m]=nil end end
 for m,kind in want do
  if not marks[m]then
   local h=Instance.new('Highlight');h.Adornee=m;h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
   h.FillColor=kind=='ice'and Color3.fromRGB(170,225,255)or kind=='danger'and Color3.fromRGB(255,190,70)or Color3.fromRGB(120,240,255);h.FillTransparency=kind=='ice'and .35 or .55;h.OutlineColor=Color3.new(1,1,1)
   h.Parent=holder;marks[m]=h
  end
 end
end)

-- Frosty fridge: an ice cube player stands in a block of ice on every screen; your own cold tints your screen.
local ICE_SIZE=Vector3.new(4,6,4)
local cubes={} -- player -> local Part
local chill=Instance.new('ColorCorrectionEffect');chill.Name='ChoiceChill';chill.Enabled=true;chill.Parent=Lighting
Run.RenderStepped:Connect(function(dt)
 local t=now()
 for _,q in Players:GetPlayers()do
  local r=q.Character and q.Character:FindFirstChild('HumanoidRootPart')
  local on=r and t<(q:GetAttribute('IceCubeUntil')or 0);local c=cubes[q]
  if on and not c then
   c=Instance.new('Part');c.Name='IceCube';c.Size=ICE_SIZE;c.Material=Enum.Material.Glass;c.Color=Color3.fromRGB(190,232,255);c.Transparency=.45
   c.Anchored=true;c.CanCollide=false;c.CanQuery=false;c.CanTouch=false;c.CastShadow=false;c.Parent=holder;cubes[q]=c
  elseif not on and c then c:Destroy();cubes[q]=nil;c=nil end
  if c and r then c.CFrame=r.CFrame*CFrame.new(0,.4,0)end
 end
 for q,c in cubes do if not q.Parent then c:Destroy();cubes[q]=nil end end
 local cold=t<(player:GetAttribute('ChillyUntil')or 0)or t<(player:GetAttribute('IceCubeUntil')or 0)
 local k=1-math.exp(-dt*3)
 chill.TintColor=chill.TintColor:Lerp(cold and Color3.fromRGB(214,232,255)or Color3.new(1,1,1),k)
 chill.Saturation+=((cold and -.15 or 0)-chill.Saturation)*k
end)
-- Funny beats (owner 2026-10-27): the server sets ScreenBeat ('WORD|style') and ScreenBeatAt on this player; the word
-- pops in near the top of the screen with a short tint, wobble or shake. 1.6 s at most, nothing flashes.
local BEAT_SECONDS=1.6
local BEAT_TINTS={frost=Color3.fromRGB(200,230,255),gold=Color3.fromRGB(255,234,176),pink=Color3.fromRGB(255,216,238),dark=Color3.fromRGB(150,150,170)}
local BEAT_TEXT={frost=Color3.fromRGB(190,235,255),gold=Color3.fromRGB(255,214,90),pink=Color3.fromRGB(255,176,224),dark=Color3.fromRGB(230,230,240),shake=Color3.fromRGB(255,226,120),wobble=Color3.fromRGB(200,220,255)}
local beatWord=label(gui,'ChoiceBeat',40,UDim2.new(.5,0,.55,0),56,TEXT);beatWord.Size=UDim2.new(.9,0,0,56);beatWord.Visible=false -- UI pass 2026-10-27: was .2 (sat on the quota HUD on phones); below the choice's message line
local beatScale=Instance.new('UIScale');beatScale.Parent=beatWord
local beatGrade=Instance.new('ColorCorrectionEffect');beatGrade.Name='ChoiceBeatGrade';beatGrade.Enabled=true;beatGrade.Parent=Lighting
local beatFx -- {t0, style}
local function playBeat()
 local raw=player:GetAttribute('ScreenBeat');if type(raw)~='string'then return end
 if now()-(player:GetAttribute('ScreenBeatAt')or 0)>2 then return end -- stale (a late join, a respawn)
 local word,style=raw:match('^(.-)|(%w+)$');word=word or raw;style=style or'plain'
 beatWord.Text=word;beatWord.TextColor3=BEAT_TEXT[style]or TEXT;beatWord.Visible=true;beatWord.TextTransparency=0
 beatScale.Scale=.4;TweenService:Create(beatScale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 beatFx={t0=os.clock(),style=style}
end
player:GetAttributeChangedSignal('ScreenBeatAt'):Connect(playBeat)
Run:BindToRenderStep('ChoiceBeat',Enum.RenderPriority.Camera.Value+2,function()
 if not beatFx then return end
 local e=os.clock()-beatFx.t0;local cam=workspace.CurrentCamera
 if e>BEAT_SECONDS then beatFx=nil;beatWord.Visible=false;beatGrade.TintColor=Color3.new(1,1,1);beatGrade.Brightness=0;return end
 local k=math.sin(e/BEAT_SECONDS*math.pi) -- in and out once
 beatWord.TextTransparency=1-math.clamp((BEAT_SECONDS-e)/.4,0,1)
 local tint=BEAT_TINTS[beatFx.style]
 beatGrade.TintColor=tint and Color3.new(1,1,1):Lerp(tint,k)or Color3.new(1,1,1)
 beatGrade.Brightness=beatFx.style=='dark'and -.2*k or 0
 if cam and not panelCam and(beatFx.style=='wobble'or beatFx.style=='shake')then
  local amp=1-e/BEAT_SECONDS
  if beatFx.style=='wobble'then cam.CFrame*=CFrame.Angles(0,0,math.sin(e*7)*math.rad(5)*amp)
  else local t=os.clock();cam.CFrame*=CFrame.Angles(math.noise(t*18,1)*math.rad(2.5)*amp,math.noise(t*18,2)*math.rad(2.5)*amp,0)end
 end
end)

-- Server messages ------------------------------------------------------------------------------------------------
local function hunterFor(userId)
 local folder=workspace:FindFirstChild('RoamingCreatures');if not folder then return nil end
 for _,m in folder:GetChildren()do if m:GetAttribute('HuntUserId')==userId then return m end end
end
event.OnClientEvent:Connect(function(kind,a,b,c)
 if kind=='open'then openCard(a,b)
 elseif kind=='close'then if open and open.prop==a then closeCard()end
 elseif kind=='deny'then showToast(b,nil,1.8)
 elseif kind=='result'then showToast(a,b,3.4)
 elseif kind=='card'then showCard(a)
 elseif kind=='dots'then showDots()
 elseif kind=='cinematic'and extraCinematic(a,b,c)then return
 elseif kind=='cinematic'then
  if a=='pupWake'then
   local prop=b;local data=c or {}
   lockMovement(true);setGrade(true,.3,.35);heart.PlaybackSpeed=1.1;heart:Play()
   local t0=os.clock()
   cine.get=function(cam)
    local p=prop.Parent and prop.PrimaryPart and prop.PrimaryPart.Position or wakeLast
    if not p then return nil end;wakeLast=p
    local flat=(cam.CFrame.Position-p)*Vector3.new(1,0,1);flat=flat.Magnitude>.1 and flat.Unit or Vector3.new(0,0,1)
    local eye=p+flat*5.5+Vector3.new(0,1.2,0)
    local hunter=hunterFor(player.UserId);local look=p
    if hunter and hunter.PrimaryPart then look=hunter.PrimaryPart.Position+Vector3.new(0,2.5,0)end
    return CFrame.lookAt(eye,look)
   end
   cine.target=1
   task.spawn(function()
    while os.clock()-t0<(data.wake or 2.2)do cine.shake=math.rad(.4+2.2*(os.clock()-t0)/(data.wake or 2.2));task.wait()end
    cine.shake=math.rad(3.5);sting:Play()
    shade.BackgroundColor3=Color3.fromRGB(70,40,120);shade.BackgroundTransparency=.15
    TweenService:Create(shade,TweenInfo.new(.6),{BackgroundTransparency=.55}):Play()
   end)
  elseif a=='hunterOut'then
   local data=c or {}
   task.delay((data.rise or 1.2)+.4,function()
    releaseCamera();setGrade(false,.4);heart.PlaybackSpeed=1.4;lockMovement(false);shade.BackgroundColor3=Color3.new(0,0,0)
    task.delay(8,function()heart:Stop()end)
   end)
  elseif a=='tea'then
   local prop=b;local data=c or {}
   lockMovement(true);setGrade(true,.5)
   focusOn(function()local p=prop.Parent and prop.PrimaryPart and prop.PrimaryPart.Position;return p and p+Vector3.new(0,.3,0)end,.4)
   showToast('Having tea with the dolls...',nil,data.seconds or 5)
   task.delay(data.seconds or 5,function()releaseCamera();setGrade(false,.5);lockMovement(false)end)
  end
 end
end)

-- Panels in the world --------------------------------------------------------------------------------------------
-- Where a prop's panel floats: above the prop, a little toward `viewer`, facing them, bobbing slightly; it spins
-- round to face them as it rises.
local wallParams=RaycastParams.new();wallParams.FilterType=Enum.RaycastFilterType.Exclude;wallParams.RespectCanCollide=true
-- Returns the panel's CFrame, its centre, the rise 0..1 and a size scale (nearer than PANEL_VIEW_DIST it shrinks).
-- Fixed once when the panel opens (owner: "it shakes a lot"): the prop breathes and turns and the camera follows
-- the head, so re-aiming every frame made the panel and the camera chase each other.
local function panelSpot(prop,viewer)
 local cf,size=prop:GetBoundingBox()
 local top=cf.Position+Vector3.new(0,size.Y*.5,0)
 local toward=(viewer-top)*Vector3.new(1,0,1);toward=toward.Magnitude>.1 and toward.Unit or Vector3.zero
 local pos=top+toward*PANEL_TOWARD+Vector3.new(0,PANEL_RISE+PANEL_SIZE.Y*.5,0)
 -- Grabbed from far away (the reach is 11 studs) it read as a stamp, worst on phones: it flies toward the viewer
 -- and stops PANEL_MAX_DIST from them, so it is the same size on screen wherever the grab came from.
 if (pos-viewer).Magnitude>PANEL_MAX_DIST then pos=viewer+(pos-viewer).Unit*PANEL_MAX_DIST end
 -- Never behind a wall or a ceiling as seen from the viewer: slide it toward them until it is in the open.
 -- Monsters are not walls either (owner 2026-10-25: a monster in view pulled the card into the camera and it vanished).
 local skip={holder,prop,workspace:FindFirstChild('ChoiceDolls'),workspace:FindFirstChild('RoamingCreatures',true),workspace:FindFirstChild('ChoiceFx')}
 for _,q in Players:GetPlayers()do if q.Character then skip[#skip+1]=q.Character end end
 wallParams.FilterDescendantsInstances=skip
 local hit=workspace:Raycast(viewer,pos-viewer,wallParams)
 -- ...but never closer than PANEL_MIN_DIST: an invisible collider (furniture box) right in front of the camera
 -- pulled the panel into the near clip or behind the camera, and the card vanished half a second after it opened.
 if hit and hit.Distance>PANEL_MIN_DIST+.4 then pos=hit.Position-(pos-viewer).Unit*.4 end
 return {top=top,final=pos,viewer=viewer,scale=math.clamp((pos-viewer).Magnitude/PANEL_VIEW_DIST,.35,1)}
end
-- Returns the panel's CFrame, its centre, the rise 0..1 and its size scale.
local function panelFrame(spot,alpha,t)
 local k=1-(1-alpha)^3
 local pos=spot.top:Lerp(spot.final,k)+Vector3.new(0,math.sin(t*1.1)*.025,0) -- slow, small bob
 return CFrame.lookAt(pos,spot.viewer)*CFrame.Angles(0,(1-k)*math.pi*.75,0),pos,k,spot.scale
end
local function easeBack(x)local c=1.6;return 1+(c+1)*(x-1)^3+c*(x-1)^2 end
Run.RenderStepped:Connect(function(dt)
 local cam=workspace.CurrentCamera;if not cam then return end
 if holder.Parent~=cam then holder.Parent=cam end -- local only: other players never get these parts
 local t=os.clock()
 -- my panel
 panelAnim.alpha=math.clamp(panelAnim.alpha+(panelAnim.target>panelAnim.alpha and dt/PANEL_POP or -dt/.22),0,1)
 local prop=panelAnim.prop
 -- The prop can vanish while the card is up (map rebuilt between levels, prop streamed out, Studio van props re-placed):
 -- close the card too, or the dim, the frozen camera and the locked movement stayed with no panel (owner 2026-10-25).
 if open and open.prop==prop and(not prop or not prop.Parent)then closeCard(true)end
 if panelAnim.alpha<=0 or not prop or not prop.Parent then
  panel.model.Parent=nil;panelPos=nil;if panelAnim.target==0 then card.Visible=false end
 else
  if not panelAnim.spot then panelAnim.spot=panelSpot(prop,panelCam and panelCam.start.Position or cam.CFrame.Position)end
  local cf,pos,k,scale=panelFrame(panelAnim.spot,panelAnim.alpha,t)
  -- seesaw: the side under the pointer (or the side just chosen) goes down and back
  local side=panelAnim.pressed or hovered
  local dip=panelAnim.pressed and PRESS_DIP or HOVER_DIP;local push=panelAnim.pressed and PRESS_PUSH or HOVER_PUSH
  local wantRoll=side=='yes'and -dip or side=='no'and dip or 0
  local wantYaw=side=='yes'and -push or side=='no'and push or 0
  local a=1-math.exp(-dt*16)
  panelAnim.roll+=(wantRoll-panelAnim.roll)*a;panelAnim.yaw+=(wantYaw-panelAnim.yaw)*a
  panelAnim.base=cf
  placeSlab(panel,cf*CFrame.Angles(0,panelAnim.yaw,panelAnim.roll),(panelAnim.target==1 and easeBack(panelAnim.alpha)or k)*scale);panelPos=pos
  panel.rim.Transparency=.15+.3*(.5+.5*math.sin(t*3));panel.light.Brightness=1.1+.4*math.sin(t*2.3)
 end
 -- the fortune card: rises in front of you, waits, flips face up, then sinks away
 if tarotShow then
  local e=t-tarotShow.start
  local total=TAROT_RISE+TAROT_HOLD+TAROT_FLIP+TAROT_SHOW+TAROT_OUT
  if e>total then tarotShow=nil;tarotSlab.model.Parent=nil
  else
   local grow=math.clamp(e/TAROT_RISE,0,1);local out=math.clamp((e-(total-TAROT_OUT))/TAROT_OUT,0,1)
   local flip=math.clamp((e-TAROT_RISE-TAROT_HOLD)/TAROT_FLIP,0,1);flip=flip*flip*(3-2*flip)
   local base=cam.CFrame*CFrame.new(0,-.2-(1-grow)*1.2-out*1.5+math.sin(e*1.7)*.04+math.sin(flip*math.pi)*.35,-3.2)
   local cf=CFrame.lookAt(base.Position,cam.CFrame.Position)*CFrame.Angles(0,flip*math.pi,math.sin(e*1.1)*.03)
   placeSlab(tarotSlab,cf,easeBack(grow)*(1-out))
  end
 end
 -- timer and heartbeat
 if open then
  local left=math.max(0,open.deadline-now());local k=left/open.total
  timerFill.Size=UDim2.fromScale(k,1)
  timerFill.BackgroundColor3=Color3.fromRGB(170,140,240):Lerp(Color3.fromRGB(236,96,110),1-k)
  heart.PlaybackSpeed=.7+(1-k)*.8
  stroke.Transparency=.1+.25*(.5+.5*math.sin(t*3))
  if left<=0 then local p=open.prop;closeCard();event:FireServer('cancel',p);showToast('Too slow!',nil,2)end
 end
end)
player.CharacterRemoving:Connect(function()if open then closeCard(true)end;endRace();releaseCamera();holdCamera(false);lockMovement(false);setGrade(false,.2)end)
-- Camera safety (owner 2026-10-27): a player who dies with the panel up stays dead and spectates (no respawn), so close the
-- panel and hand the camera back on death too, not only when the character is removed.
local function watchDeath(c)local h=c:WaitForChild('Humanoid',10);if h then h.Died:Connect(function()if open then closeCard(true)end;endRace();releaseCamera();holdCamera(false);lockMovement(false);setGrade(false,.2)end)end end
if player.Character then task.spawn(watchDeath,player.Character)end;player.CharacterAdded:Connect(function(c)task.spawn(watchDeath,c)end)
-- This game's first-person camera locks the mouse every frame; while the panel is up (keyboard + mouse) the cursor
-- is released after it, so the panel's buttons can be pointed at and clicked. Closing hands the lock back.
Run:BindToRenderStep('CloseUpChoiceMouse',Enum.RenderPriority.Last.Value+5,function()
 if open and mode()=='kb'then UIS.MouseBehavior=Enum.MouseBehavior.Default;UIS.MouseIconEnabled=true;setHovered(buttonAt(UIS:GetMouseLocation()))
 elseif hovered then setHovered(nil)end
end)

-- Everyone else: the deciding player's panel floats over the prop, turned toward them.
local spectators={} -- prop -> {slab, alpha}
local function spectatorPanel(prop)
 local sp=spectators[prop];if sp then return sp end
 local slab=makeSlab('ChoicePanelSeen',PANEL_SIZE,RIM_COLOR,Color3.fromRGB(176,150,255))
 local sg=surface('Seen',slab.face,CARD_SIZE*CANVAS_SCALE,Enum.NormalId.Front,false)
 local copy=card:Clone();copy.Visible=true;copy.Parent=sg
 copy.Title.Text=prop:GetAttribute('DisplayName')or'';copy.Whisper.Text='Someone is picking...';copy.Hint.Text=''
 copy.Yes.Word.Text=prop:GetAttribute('ChoiceYes')or'YES';copy.No.Word.Text=prop:GetAttribute('ChoiceNo')or'NO'
 copy.Yes.Line.Text='';copy.No.Line.Text='';copy.Yes.Key.Visible=false;copy.No.Key.Visible=false;copy.Timer.Visible=false
 sp={slab=slab,alpha=0};spectators[prop]=sp;slab.model.Parent=holder
 return sp
end
Run.RenderStepped:Connect(function(dt)
 local t=os.clock()
 for prop,sp in spectators do
  local by=prop.Parent and prop:GetAttribute('ClaimedBy')
  local viewer=by and by~=player.UserId and headOf(by)
  sp.alpha=math.clamp(sp.alpha+(viewer and dt/PANEL_POP or -dt/.25),0,1)
  if sp.alpha<=0 and not viewer then sp.slab.model:Destroy();spectators[prop]=nil
  elseif viewer then sp.spot=sp.spot or panelSpot(prop,viewer);local cf,_,_,scale=panelFrame(sp.spot,sp.alpha,t);placeSlab(sp.slab,cf,easeBack(sp.alpha)*scale)end
 end
 local map=workspace:FindFirstChild('Mansion');local folder=map and map:FindFirstChild('Interactive')
 if not folder then return end
 for _,m in folder:GetChildren()do
  local by=m:GetAttribute('ClaimedBy')
  if by and by~=player.UserId and m:GetAttribute('ChoiceId')and m.PrimaryPart then spectatorPanel(m)end
 end
end)

-- Every screen: the props look alive and stare at whoever is deciding ------------------------------------------
local base=setmetatable({},{__mode='k'})
local function nearestHead(pos,radius)
 local best,bd
 for _,q in Players:GetPlayers()do local c=q.Character;local h=c and c:FindFirstChild('Head');if h then local d=(h.Position-pos).Magnitude;if d<radius and(not bd or d<bd)then best,bd=h.Position,d end end end
 return best
end
local function yawToward(cf,target)
 local look=cf:VectorToObjectSpace((target-cf.Position)*Vector3.new(1,0,1))
 if look.Magnitude<.1 then return nil end
 return math.atan2(-look.X,-look.Z)
end
local function turnTo(cur,want,k)return cur+math.atan2(math.sin(want-cur),math.cos(want-cur))*k end
-- Second set of props (owner 2026-10-25): lids, cranks, doors and ghosts move on every screen. A part that moves is
-- unwelded here (locally) and placed relative to the prop's pivot each frame.
local function moving(b,m,name)
 local p=m:FindFirstChild(name);if not p or not p:IsA('BasePart')then return nil end
 local pb=b.parts[p]
 if not pb then
  for _,w in p:GetChildren()do if w:IsA('WeldConstraint')then w.Enabled=false end end
  pb={off=m:GetPivot():ToObjectSpace(p.CFrame),half=p.Size*.5,kids={}};b.parts[p]=pb
  for _,k in m:GetChildren()do if k:IsA('BasePart')and k.Name:sub(1,#name+1)==name..'_'then
   for _,w in k:GetChildren()do if w:IsA('WeldConstraint')then w.Enabled=false end end;pb.kids[k]=p.CFrame:ToObjectSpace(k.CFrame)
  end end
 end
 return p,pb
end
local function set(p,pb,cf)p.CFrame=cf;for k,rel in pb.kids do k.CFrame=cf*rel end end
-- A lid hinged on its back edge (+Z), opened by `a` radians (positive lifts the front).
local function hinge(m,p,pb,a,drop)
 set(p,pb,m:GetPivot()*pb.off*CFrame.new(0,-(drop or 0),pb.half.Z)*CFrame.Angles(a,0,0)*CFrame.new(0,drop or 0,-pb.half.Z))
end
local CHEST_SHUT=-.16 -- radians: the model is built with its mouth a little open; this closes it
local function animateExtra(m,id,b,t,dt,stare)
 local want=stare and yawToward(b.cf,stare);if want then b.yaw=turnTo(b.yaw,want,math.min(1,dt*3))end
 if id=='HungryChest'then
  local mood=m:GetAttribute('ChestMood')
  -- idle: slow breathing, a sly peek every few seconds, a little hop and wiggle when someone is near (owner: idle was bad)
  local cyc=(t+(b.seed or 0))%5.5;if not b.seed then b.seed=math.random()*5 end
  local peek=cyc<.9 and math.sin(cyc/.9*math.pi)^2*.42 or 0
  local a=.04+.035*math.sin(t*1.3)+peek
  local shake=Vector3.new(0,stare and math.abs(math.sin(t*3.2))*.14 or 0,0)
  if stare then a+=.08*math.abs(math.sin(t*3.2))end
  if mood=='hungry'then a=.35+.3*math.abs(math.sin(t*4.5))
  elseif mood=='chew'then a=.15+.25*math.abs(math.sin(t*12));shake=Vector3.new(math.noise(t*20,1),0,math.noise(t*20,2))*.08
  elseif mood=='angry'then a=.9*math.abs(math.sin(t*9));shake=Vector3.new(math.noise(t*30,1),math.abs(math.noise(t*30,3))*.4,math.noise(t*30,2))*.12
   -- each bite: it leaps at the player (up to 5 studs, a hop), jaws wide, and lands back (owner: jump at you and bite)
   local e=now()-(m:GetAttribute('ChestBite')or -9)
   if e<.42 and stare then local k=math.sin(e/.42*math.pi);local d=(stare-b.cf.Position)*Vector3.new(1,0,1)
    if d.Magnitude>.1 then shake+=b.cf:VectorToObjectSpace(d.Unit*math.min(d.Magnitude-1.5,5)*k)+Vector3.new(0,1.6*k,0)end;a=1.3*k end
  elseif mood=='happy'then a=.25;shake=Vector3.new(0,math.abs(math.sin(t*8))*.25,0)
  elseif mood=='sleep'then a=CHEST_SHUT;shake=Vector3.zero end -- asleep: lid shut tight
  m:PivotTo(b.cf*CFrame.new(shake)*CFrame.Angles(0,b.yaw,0))
  local lid,pb=moving(b,m,'Lid');if lid then hinge(m,lid,pb,a,.08)end
 elseif id=='Toilet'then
  local f=m:GetAttribute('Flushing');local e=f and now()-f
  local shake=e and e<1.6 and Vector3.new(math.noise(t*25,1),0,math.noise(t*25,2))*.12*(1-e/1.6)or Vector3.zero
  m:PivotTo(b.cf*CFrame.new(shake))
  local h,pb=moving(b,m,'Handle');if h then set(h,pb,m:GetPivot()*pb.off*CFrame.Angles(0,0,(e and e<.6)and -.6 or 0))end
 elseif id=='LonelyBalloon'then
  local away=m:GetAttribute('FloatAway');local rise=away and math.max(0,now()-away)^1.6*3 or 0
  m:PivotTo(b.cf*CFrame.new(0,math.sin(t*1.8)*.18+rise,0)*CFrame.Angles(0,b.yaw+math.sin(t*.7)*.15,math.sin(t*1.2)*.06))
 elseif id=='JackInTheBox'then
  local state=m:GetAttribute('JackState');local winds=m:GetAttribute('JackWinds')or 0
  local wob=state=='wind'and Vector3.new(math.noise(t*14,1),0,math.noise(t*14,2))*.03*(1+winds/10)or Vector3.zero
  m:PivotTo(b.cf*CFrame.new(wob)*CFrame.Angles(0,b.yaw,0))
  local crank,cb=moving(b,m,'Crank')
  if crank then b.crank=(b.crank or 0)+((state=='wind'and(winds-(b.lastWinds or 0))*.9 or 0));b.lastWinds=winds;set(crank,cb,m:GetPivot()*cb.off*CFrame.Angles(b.crank,0,0))end
  local lid,lb=moving(b,m,'Lid');local clown,kb=moving(b,m,'Clown')
  if state=='pop'or state=='won'then
   b.popAt=b.popAt or t;local e=t-b.popAt
   if lid then hinge(m,lid,lb,math.min(2,e*14))end
   if clown then local up=math.min(1,e*6)*1.4+math.sin(e*18)*.25*math.exp(-e*3);set(clown,kb,m:GetPivot()*kb.off*CFrame.new(0,up,0)*CFrame.Angles(0,math.sin(e*9)*.4*math.exp(-e*2),0))end
  else
   if lid then hinge(m,lid,lb,0)end
   if clown then set(clown,kb,m:GetPivot()*kb.off)end
  end
 elseif id=='Birdcage'then
  m:PivotTo(b.cf*CFrame.Angles(0,0,math.sin(t*1.1)*.02))
  local door,db=moving(b,m,'Door')
  if door then b.door=(b.door or 0)+((m:GetAttribute('CageOpen')and 1.8 or 0)-(b.door or 0))*math.min(1,dt*6);set(door,db,m:GetPivot()*db.off*CFrame.new(-db.half.X,0,0)*CFrame.Angles(0,b.door,0)*CFrame.new(db.half.X,0,0))end
 elseif id=='GhostJar'then
  local open=m:GetAttribute('JarOpen')
  m:PivotTo(b.cf*CFrame.new(Vector3.new(math.noise(t*6,1),0,math.noise(t*6,2))*(stare and .04 or .01)))
  local g,gb=moving(b,m,'GhostInside');if g then set(g,gb,m:GetPivot()*gb.off*CFrame.new(0,math.sin(t*2.4)*.12,0)*CFrame.Angles(0,t*.8,0));g.Transparency=open and 1 or .1+.2*math.sin(t*3)end
  local lid,lb=moving(b,m,'Lid')
  if lid then b.lidUp=open and math.min(3,(b.lidUp or 0)+dt*6)or 0;set(lid,lb,m:GetPivot()*lb.off*CFrame.new(0,b.lidUp*.6,0)*CFrame.Angles(b.lidUp*.8,0,b.lidUp*.5))end
 elseif id=='FrostyFridge'then
  -- shivers (harder when stared at); eyes slide side to side; the mouth-door breathes; answered: it bangs open
  local opened=m:GetAttribute('FridgeOpen');local e=opened and now()-opened
  local shiver=Vector3.new(math.noise(t*18,1),0,math.noise(t*18,2))*(stare and .03 or .008)
  m:PivotTo(b.cf*CFrame.new(shiver)*CFrame.Angles(0,b.yaw,0))
  local swing=e and(e<2.4 and math.min(1.6,e*8)or math.max(0,1.6-(e-2.4)*2))or .04+.03*math.sin(t*1.1)
  local d,db=moving(b,m,'Door') -- hinged on its left edge (the handle is on the right)
  if d then set(d,db,m:GetPivot()*db.off*CFrame.new(-db.half.X,0,0)*CFrame.Angles(0,-swing,0)*CFrame.new(db.half.X,0,0))end
  local ey,eb=moving(b,m,'Eyes');if ey then set(ey,eb,m:GetPivot()*eb.off*CFrame.new(math.sin(t*.7)*.05,0,0))end
 elseif id=='ShyMailbox'then
  -- shy: when someone stares, the eyes sink behind the door and peek back up now and then; the door breathes
  local mood=m:GetAttribute('MailMood')
  local peek=stare and(math.sin(t*1.6)>.3 and .02 or .3)or .05+.05*math.sin(t*1.2)
  local door,flag,shake=.12+.08*math.sin(t*1.3),0,Vector3.zero
  if mood=='open'then door,peek,flag=-.9,0,.9*math.abs(math.sin(t*5))
  elseif mood=='gulp'then door,peek=.38,.3;shake=Vector3.new(math.noise(t*20,1),0,math.noise(t*20,2))*.08
  elseif mood=='happy'then door,peek,flag=-.3,0,1.4
  elseif mood=='sleep'then door,peek=.38,.3 end
  m:PivotTo(b.cf*CFrame.new(shake)*CFrame.Angles(0,b.yaw,0))
  local d,db=moving(b,m,'Door') -- hinged on its bottom edge (negative opens it wider)
  if d then set(d,db,m:GetPivot()*db.off*CFrame.new(0,-db.half.Y,0)*CFrame.Angles(door,0,0)*CFrame.new(0,db.half.Y,0))end
  local e,eb=moving(b,m,'Eyes');if e then set(e,eb,m:GetPivot()*eb.off*CFrame.new(0,-peek,0))end
  local f,fb=moving(b,m,'Flag') -- turns on its pin at the bottom of the arm
  if f then set(f,fb,m:GetPivot()*fb.off*CFrame.new(0,-fb.half.Y,0)*CFrame.Angles(flag,0,0)*CFrame.new(0,fb.half.Y,0))end
 elseif id=='SleepyLamp'then
  -- dozing: the shade nods forward and snaps back, the bulb is dim; a stare wakes it (shade up, bulb bright)
  local mood=m:GetAttribute('LampMood')
  if not b.seed then b.seed=math.random()*4 end;local cyc=(t+b.seed)%4
  local nod=stare and .03*math.sin(t*3)or(cyc<3.4 and .28*(cyc/3.4)^2 or .28*(1-(cyc-3.4)/.6))
  local dim=stare and 0 or .45+.15*math.sin(t*.9)
  if mood=='dark'then nod,dim=.3,.85 elseif mood=='gulp'then nod,dim=-.18+.05*math.sin(t*25),0 end
  m:PivotTo(b.cf*CFrame.Angles(0,b.yaw,0))
  local s,sb=moving(b,m,'Shade') -- tips on its bottom rim (positive nods forward toward the face side)
  if s then set(s,sb,m:GetPivot()*sb.off*CFrame.new(0,-sb.half.Y,0)*CFrame.Angles(nod,0,0)*CFrame.new(0,sb.half.Y,0))end
  local bulb=m:FindFirstChild('Bulb');if bulb and bulb:IsA('BasePart')then bulb.Transparency=dim end
 elseif id=='TwinTeddies'then
  m:PivotTo(b.cf) -- the bench stays put; each teddy turns on its own (TeddyA to the first voter, TeddyB to the second)
  local mood=m:GetAttribute('TeddyMood');local first=headOf(m:GetAttribute('TeddyFirst'))
  for i,name in {'TeddyA','TeddyB'}do
   local p,pb=moving(b,m,name)
   if p then
    local rest=m:GetPivot()*pb.off
    local target=i==1 and(first or stare)or stare
    if not target and not mood then target=nearestHead(rest.Position,16)end
    local aim=(mood~='hug'and target)and yawToward(rest,target)or 0
    pb.yaw=turnTo(pb.yaw or 0,math.clamp(aim,-1.3,1.3),math.min(1,dt*4))
    local dir=m:GetPivot():PointToObjectSpace(rest.Position).X<0 and 1 or -1 -- toward the other teddy
    local extra=CFrame.identity
    if mood=='wait'and i==2 then extra=CFrame.new(0,math.abs(math.sin(t*3))*.12,0) -- the free one bounces: come and pick!
    elseif mood=='think'and i==2 then extra=CFrame.Angles(0,0,math.sin(t*2)*.15)
    elseif mood=='hug'then extra=CFrame.new(dir*.12,0,0)*CFrame.Angles(0,0,-dir*.22)
    elseif mood=='treat'then extra=CFrame.new(0,math.abs(math.sin(t*7+i))*.25,0)
    elseif mood=='cry'then extra=CFrame.new(math.noise(t*25,i)*.08,math.abs(math.sin(t*14))*.06,0)end
    set(p,pb,rest*extra*CFrame.Angles(0,pb.yaw,0))
   end
  end
 elseif id=='PadlockKing'then
  local open=m:GetAttribute('PadlockOpen')
  local hop=stare and math.abs(math.sin(t*5))*.12 or 0
  m:PivotTo(b.cf*CFrame.new(0,math.sin(t*1.6)*.02+hop,0)*CFrame.Angles(0,b.yaw,0))
  local sh,sb=moving(b,m,'Shackle') -- YES: the shackle (and its crown) springs up and swings open on its left leg
  if sh then
   local k=open and math.min(1,math.max(0,now()-open)*3)or 0
   set(sh,sb,m:GetPivot()*sb.off*CFrame.new(0,k*.7,0)*CFrame.new(-sb.half.X*.55,0,0)*CFrame.Angles(0,k*1.2,0)*CFrame.new(sb.half.X*.55,0,0))
  end
  local keys,kb=moving(b,m,'Keys') -- the keyring sways, wildly once it said YES
  if keys then
   local sw=math.sin(t*(open and 14 or 2.4))*(open and .35 or .08)
   set(keys,kb,m:GetPivot()*kb.off*CFrame.new(0,kb.half.Y,0)*CFrame.Angles(sw,0,0)*CFrame.new(0,-kb.half.Y,0))
  end
 elseif id=='StaringOwl'then
  m:PivotTo(b.cf) -- the perch stays; only the owl (and its glowing eyes, Owl_neon) moves
  local owl,ob=moving(b,m,'Owl')
  if owl then
   local rest=m:GetPivot()*ob.off;local state=m:GetAttribute('OwlState')
   if state=='fly'then
    local spot,frame=owlSpot(m,math.max(0,now()-(m:GetAttribute('OwlStart')or now())))
    if spot and frame then
     b.lastSpot=spot
     set(owl,ob,CFrame.lookAt(spot,stare or spot+frame.LookVector)*CFrame.Angles(0,0,math.sin(t*9)*.18)) -- rocking: flapping
    end
   elseif state=='won'or state=='leave'then -- up and away, spinning
    b.awayT=b.awayT or t;local e=t-b.awayT;local from=b.lastSpot or rest.Position
    set(owl,ob,CFrame.new(from+Vector3.new(0,e*e*6+e*2,0))*rest.Rotation*CFrame.Angles(0,e*5,0))
   elseif state=='lost'then -- it swoops right into your face, then off
    b.awayT=b.awayT or t;local e=t-b.awayT;local from=b.lastSpot or rest.Position
    local face=stare and stare+(from-stare).Unit*1.6 or from
    local k=math.min(1,e/.35);local pos=from:Lerp(face,k*k)
    if e>.7 then pos=face+Vector3.new(0,(e-.7)*12,0)end
    set(owl,ob,CFrame.lookAt(pos,stare or pos+rest.LookVector))
   else -- on its perch: turns its head to whoever is near
    local target=stare or nearestHead(rest.Position,20)
    local aim=target and yawToward(rest,target);if aim then ob.yaw=turnTo(ob.yaw or 0,aim,math.min(1,dt*4))end
    set(owl,ob,rest*CFrame.new(0,math.abs(math.sin(t*1.7))*.03,0)*CFrame.Angles(0,ob.yaw or 0,0))
   end
  end
 elseif id=='BirthdayCake'then
  m:PivotTo(b.cf*CFrame.Angles(0,b.yaw*.2,0))
 end
end
local spentMarks={} -- strong keys (see liveMarks); cleared on Destroying
-- Owner 2026-10-25: an unanswered custom item gets a bold, pulsing purple outline (the card's colour) so it can't
-- be mistaken for loot or furniture. Seen through nothing (Occluded); it gives way to SpentOutline once used.
local liveMarks={} -- strong keys: a weak Instance key can drop while the model lives, stacking outlines
local LIVE_COLOR=Color3.fromRGB(190,120,255)
local function liveOutline(m,on)
 local h=liveMarks[m]
 if on and not h then
  h=Instance.new('Highlight');h.Name='ChoiceOutline';h.Adornee=m;h.DepthMode=Enum.HighlightDepthMode.Occluded
  h.OutlineColor=LIVE_COLOR;h.FillColor=LIVE_COLOR;h.Parent=holder;liveMarks[m]=h
  m.Destroying:Once(function()h:Destroy();liveMarks[m]=nil end)
 elseif not on and h then h:Destroy();liveMarks[m]=nil end
 if on then local k=.5+.5*math.sin(os.clock()*4);h.OutlineTransparency=.15*k;h.FillTransparency=.72+.2*k end
end
local function animateProp(m,dt)
 local b=base[m];if not b then b={cf=m:GetPivot(),yaw=0,parts={}};base[m]=b end
 liveOutline(m,not m:GetAttribute('ChoiceSpent')and not m:GetAttribute('ChoiceDone'))
 if m:GetAttribute('ChoiceSpent')then
  if not spentMarks[m]then
   -- back to its rest pose first (a lid left open, a leap or hop mid-air), then still for good
   m:PivotTo(b.cf*CFrame.Angles(0,b.yaw or 0,0))
   for p,pb in b.parts do if p.Parent and pb.off then p.CFrame=m:GetPivot()*pb.off;if pb.kids then for k,rel in pb.kids do k.CFrame=p.CFrame*rel end end end end
   if m:GetAttribute('ChoiceId')=='HungryChest'then local lid,lb=moving(b,m,'Lid');if lid then hinge(m,lid,lb,CHEST_SHUT,.08)end end -- spent chests sleep shut
   local h=Instance.new('Highlight');h.Name='SpentOutline';h.Adornee=m;h.FillTransparency=1;h.OutlineColor=Color3.fromRGB(200,196,220);h.OutlineTransparency=.35
   h.DepthMode=Enum.HighlightDepthMode.Occluded;h.Parent=holder;spentMarks[m]=h
   m.Destroying:Once(function()h:Destroy();spentMarks[m]=nil end)
  end
  return
 end
 local id=m:GetAttribute('ChoiceId');local t=os.clock();local stare=headOf(m:GetAttribute('StareAt'))
 if id=='StrayCat'then
  local target=stare or(m:GetAttribute('ChoiceDone')==nil and nearestHead(b.cf.Position,CAT_TURN_RADIUS))
  local want=target and yawToward(b.cf,target);if want then b.yaw=turnTo(b.yaw,want,math.min(1,dt*(stare and 6 or 3)))end
  local hop=m:GetAttribute('ChoiceAnswer')=='yes'and math.abs(math.sin(t*7))*.25 or 0
  m:PivotTo(b.cf*CFrame.new(0,math.sin(t*2.2)*.025+hop,0)*CFrame.Angles(0,b.yaw,0))
 elseif id=='SleepingPup'then
  local eyes=m:FindFirstChild('Eyes')
  local waking=m:GetAttribute('Waking')==true
  if eyes then eyes.Transparency=(waking or stare)and 0 or 1 end
  local jitter=waking and Vector3.new(math.noise(t*30,1),math.noise(t*30,2),math.noise(t*30,3))*.16 or Vector3.zero
  local want=stare and yawToward(b.cf,stare);if want then b.yaw=turnTo(b.yaw,want,math.min(1,dt*2))end
  m:PivotTo(b.cf*CFrame.new(jitter+Vector3.new(0,math.sin(t*1.4)*.02,0))*CFrame.Angles(0,b.yaw,0))
 elseif id=='TeaParty'then
  for i=1,3 do
   local d=m:FindFirstChild('Doll'..i)
   if d then
    local pb=b.parts[d];if not pb then pb={cf=d.CFrame,yaw=0};b.parts[d]=pb end
    local want=stare and yawToward(pb.cf,stare)or 0
    pb.yaw=turnTo(pb.yaw,want,math.min(1,dt*(stare and 5 or 1.5)))
    local tilt=stare and math.rad(14)*math.sin(i)or 0
    d.CFrame=pb.cf*CFrame.Angles(0,pb.yaw,0)*CFrame.Angles(0,0,tilt)
   end
  end
 elseif id=='FortuneTeller'then
  local core=m:FindFirstChild('Core');if core then core.Transparency=.15+.25*(.5+.5*math.sin(t*(stare and 6 or 2)))end
  local eye=m:FindFirstChild('Eye')
  if eye then
   local pb=b.parts[eye];if not pb then pb={cf=eye.CFrame};b.parts[eye]=pb end
   local target=stare or nearestHead(pb.cf.Position,24)or(pb.cf.Position+Vector3.new(math.sin(t*.7)*3,0,-3))
   eye.CFrame=CFrame.lookAt(pb.cf.Position,target) -- the eye's front is its -Z side
  end
 else animateExtra(m,id,b,t,dt,stare)
 end
end

-- Walking dolls: the walk clip (rbxanim AnyRig) on every screen, sped up and slowed with their real speed; their
-- heads keep turning to the player they follow.
local AnyRig,walk
pcall(function()AnyRig=require(RS:WaitForChild('RbxAnim',10):WaitForChild('AnyRig',10));walk=require(RS.RbxAnim:WaitForChild('DollWalk',10))end)
local dollRigs=setmetatable({},{__mode='k'})
Run.Stepped:Connect(function(_,dt)
 local folder=workspace:FindFirstChild('ChoiceDolls');if not folder or not AnyRig or not walk then return end
 for _,d in folder:GetChildren()do
  local root=d:FindFirstChild('HumanoidRootPart');local torso=d:FindFirstChild('Torso')
  if root and torso and d:FindFirstChild('Head')and d:FindFirstChild('Left Leg')and d:FindFirstChild('Right Leg')then
   local r=dollRigs[d]
   if not r then local ok,rig=pcall(AnyRig.analyse,d);if ok then r={rig=rig,phase=math.random()};dollRigs[d]=r end end
   if r then
    local v=root.AssemblyLinearVelocity*Vector3.new(1,0,1)
    local speed=v.Magnitude
    local neck=torso:FindFirstChild('Neck')
    if speed>.4 then
     r.phase=(r.phase+dt*speed/DOLL_WALK_REF)%1
     AnyRig.apply(r.rig,walk,1+math.floor(r.phase*(walk.frames-1)+.5))
    else -- standing: ease every joint back to rest (the neck is set below)
     for _,j in torso:GetChildren()do if j:IsA('Motor6D')and j~=neck then j.Transform=j.Transform:Lerp(CFrame.identity,math.min(1,dt*6))end end
     if neck then neck.Transform=CFrame.identity end
    end
    local target=headOf(d:GetAttribute('FollowUserId'))
    local want=neck and target and yawToward(torso.CFrame,target)
    if want then neck.Transform=neck.Transform*CFrame.Angles(0,math.clamp(want,-1.1,1.1),0)*CFrame.Angles(0,0,math.rad(10))end
   end
  end
 end
end)

Run.RenderStepped:Connect(function(dt)
 local map=workspace:FindFirstChild('Mansion');local folder=map and map:FindFirstChild('Interactive')
 if not folder then return end
 for m in pairs(base)do if m.Parent~=folder then base[m]=nil end end
 for _,m in folder:GetChildren()do
  if m:IsA('Model')and m:GetAttribute('ChoiceId')and m.PrimaryPart then animateProp(m,math.min(dt,.1))end
 end
end)
