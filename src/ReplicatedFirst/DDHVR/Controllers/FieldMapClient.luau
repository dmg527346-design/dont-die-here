-- VR-only version of the existing owner. Original source remains untouched.
return function(script, VRSupport)
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
-- Field map client: hold M (keyboard), LB / L1 (gamepad) or the MAP button (phone)
-- to pull the radar out of the left pocket with the left hand. While it is out
-- nothing can be interacted with (MapOpen; servers enforce it too).
-- Items show only after this player has actually seen them on this map.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local GuiService=game:GetService('GuiService')
local RS=game:GetService('ReplicatedStorage')
local HttpService=game:GetService('HttpService')
local player=Players.LocalPlayer
-- The Roblox player list never shows in this game (Tab is the map key). ReplicatedFirst.MansionLoading turns it
-- off at join; this repeats it before anything below can yield.
local StarterGui=game:GetService('StarterGui')
pcall(StarterGui.SetCoreGuiEnabled,StarterGui,Enum.CoreGuiType.PlayerList,false)
while player:GetAttribute('MissionActive')~=true do player:GetAttributeChangedSignal('MissionActive'):Wait() end
local HoldPose=require(RS:WaitForChild('HoldPose'))
local Device=require(RS:WaitForChild('FieldMapDevice'))
local event=RS:WaitForChild('FieldMapEvent')
local mansion=workspace:WaitForChild('Mansion',math.huge)

-- Layout / tuning (named so screenshot nudges stay readable)
local RANGE=80 -- studs from the scope centre to its edge
local SCOPE_PX=380 -- scope diameter on the screen canvas
local CANVAS=Vector2.new(640,450)
local SWEEP_SECONDS=2.4
local TRAIL=9 -- fading lines behind the sweep
local SEEN_RANGE=60
local SEEN_INTERVAL=.15
local FLOOR=16
local GREEN=Color3.fromRGB(80,255,150)
local DIM=Color3.fromRGB(34,120,76)
local INK=Color3.fromRGB(4,14,9)
local KEY_COLOR=Color3.fromRGB(255,214,90)
local ITEM_COLOR=Color3.fromRGB(110,230,255)
local CART_COLOR=Color3.fromRGB(255,150,70)
local MATE_COLOR=Color3.fromRGB(235,245,235)
local LOCK_COLOR=Color3.fromRGB(255,96,80)
local SCALE=SCOPE_PX/2/RANGE
local TOUCH_SIDE,TOUCH_SIDE_SMALL=64,54

local function levelOf(y) return math.max(0,math.floor((y+FLOOR*.375)/FLOOR)) end

-- First-person device ---------------------------------------------------------
local view=Instance.new('Folder');view.Name='FieldMapView'
local device,screen=Device.Build(1)
for _,p in device:GetDescendants() do if p:IsA('BasePart') then p:SetAttribute('Shown',p.Transparency);p.Transparency=1 end end
device.PrimaryPart.Anchored=true
device.Parent=view
local tip=device:FindFirstChild('AntennaTip')
local deviceShown=false
local function showDevice(v)
 if v==deviceShown then return end
 deviceShown=v
 for _,p in device:GetDescendants() do if p:IsA('BasePart') then p.Transparency=v and p:GetAttribute('Shown') or 1 end end
end

-- Radar screen ------------------------------------------------------------------
local surface=Instance.new('SurfaceGui');surface.Name='FieldMapScreen';surface.Face=Enum.NormalId.Front
surface.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;surface.CanvasSize=CANVAS;surface.LightInfluence=0;surface.Brightness=1.6
surface.ClipsDescendants=true;surface.ResetOnSpawn=false;surface.Adornee=screen;surface.Enabled=false
surface.Parent=player:WaitForChild('PlayerGui')
local function frame(parent,props) local f=Instance.new('Frame');f.BorderSizePixel=0;for k,v in props do f[k]=v end;f.Parent=parent;return f end
local function text(parent,props) local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Font=Enum.Font.Code;t.TextColor3=GREEN;for k,v in props do t[k]=v end;t.Parent=parent;return t end
local function round(f) local c=Instance.new('UICorner');c.CornerRadius=UDim.new(.5,0);c.Parent=f end
local function stroke(f,color,thickness,transparency) local s=Instance.new('UIStroke');s.Color=color;s.Thickness=thickness or 1;s.Transparency=transparency or 0;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=f;return s end
local centre=UDim2.fromScale(.5,.5);local mid=Vector2.new(.5,.5)

local bg=frame(surface,{Size=UDim2.fromScale(1,1),BackgroundColor3=INK})
-- Circular scope. The map is a top-down 3D view in a ViewportFrame, which can never draw outside its own square:
-- rotated 2D frames escape ClipsDescendants, and a CanvasGroup inside this SurfaceGui sometimes let rooms spill off
-- the screen. Labels and blips are placed by projection and hidden outside the disc; the corner mask rounds it off.
local scopePos=UDim2.fromOffset(26,(CANVAS.Y-SCOPE_PX)/2)
local scope=frame(bg,{Name='Scope',Size=UDim2.fromOffset(SCOPE_PX,SCOPE_PX),Position=scopePos,BackgroundColor3=Color3.fromRGB(5,28,16),ClipsDescendants=true});round(scope)
local CAM_H=2000 -- a high, narrow camera is close to orthographic
local SCOPE_BG=Color3.fromRGB(5,28,16)
local vf=Instance.new('ViewportFrame');vf.Name='MapView';vf.Size=UDim2.fromScale(1,1);vf.BackgroundTransparency=1;vf.ZIndex=2
-- Neon parts under full ambient and no light render as flat, unlit colours, matching the old 2D radar.
vf.Ambient=Color3.new(1,1,1);vf.LightColor=Color3.new(0,0,0);vf.LightDirection=Vector3.new(0,-1,0);vf.Parent=scope
local vfCam=Instance.new('Camera');vfCam.FieldOfView=math.deg(2*math.atan(RANGE/CAM_H));vfCam.Parent=vf;vf.CurrentCamera=vfCam
local overlay=frame(scope,{Name='Overlay',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=4})
for i=1,3 do
 local d=SCOPE_PX*i/3
 local r=frame(scope,{AnchorPoint=mid,Position=centre,Size=UDim2.fromOffset(d,d),BackgroundTransparency=1,ZIndex=5});round(r);stroke(r,GREEN,1,.72)
end
frame(scope,{AnchorPoint=mid,Position=centre,Size=UDim2.new(1,0,0,1),BackgroundColor3=GREEN,BackgroundTransparency=.82,ZIndex=5})
frame(scope,{AnchorPoint=mid,Position=centre,Size=UDim2.new(0,1,1,0),BackgroundColor3=GREEN,BackgroundTransparency=.82,ZIndex=5})
-- Sweep: a bright arm and a fading trail, each a full-size rotating carrier.
local sweeps={}
for i=0,TRAIL do
 local carrier=frame(scope,{AnchorPoint=mid,Position=centre,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=6})
 frame(carrier,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(.5,0),Size=UDim2.new(0,i==0 and 3 or 6,.5,0),BackgroundColor3=GREEN,BackgroundTransparency=i==0 and .05 or .55+i*.05,ZIndex=6})
 sweeps[i]=carrier
end
local me=text(scope,{AnchorPoint=mid,Position=centre,Size=UDim2.fromOffset(22,22),Text='\u{25B2}',TextSize=20,TextColor3=Color3.new(1,1,1),ZIndex=8})
-- CanvasGroup clips square, so a background-coloured ring masks the corners.
local mask=frame(bg,{Size=scope.Size,Position=scopePos,BackgroundTransparency=1,ZIndex=8});round(mask);stroke(mask,INK,math.ceil(SCOPE_PX*(math.sqrt(2)-1)/2)+2,0)
local rim=frame(bg,{Size=scope.Size,Position=scopePos,BackgroundTransparency=1,ZIndex=9});round(rim);stroke(rim,GREEN,3,.05)
for i=0,11 do -- bearing ticks around the rim
 local carrier=frame(bg,{AnchorPoint=mid,Position=UDim2.fromOffset(scopePos.X.Offset+SCOPE_PX/2,scopePos.Y.Offset+SCOPE_PX/2),Size=UDim2.fromOffset(SCOPE_PX+16,SCOPE_PX+16),BackgroundTransparency=1,Rotation=i*30,ZIndex=9})
 frame(carrier,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(.5,0),Size=UDim2.fromOffset(i%3==0 and 4 or 2,i%3==0 and 12 or 7),BackgroundColor3=GREEN,ZIndex=9})
end
-- Side panel
local panelX=scopePos.X.Offset+SCOPE_PX+24
local panel=frame(bg,{Position=UDim2.fromOffset(panelX,28),Size=UDim2.fromOffset(CANVAS.X-panelX-18,CANVAS.Y-56),BackgroundTransparency=1})
text(panel,{Size=UDim2.new(1,0,0,22),Text='FIELD RADAR',TextSize=20,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Arcade})
local floorText=text(panel,{Position=UDim2.fromOffset(0,34),Size=UDim2.new(1,0,0,64),Text='F1',TextSize=64,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Arcade})
local floorHint=text(panel,{Position=UDim2.fromOffset(0,100),Size=UDim2.new(1,0,0,18),Text='GROUND FLOOR',TextSize=15,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=DIM})
local counts=text(panel,{Position=UDim2.fromOffset(0,136),Size=UDim2.new(1,0,0,60),Text='',TextSize=17,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top})
local legendY=208
for i,entry in {{KEY_COLOR,'KEY'},{ITEM_COLOR,'LOOT'},{CART_COLOR,'CART'},{MATE_COLOR,'CREW'},{LOCK_COLOR,'LOCKED'}} do
 local dot=frame(panel,{Position=UDim2.fromOffset(2,legendY+(i-1)*24+4),Size=UDim2.fromOffset(12,12),BackgroundColor3=entry[1]});round(dot)
 text(panel,{Position=UDim2.fromOffset(22,legendY+(i-1)*24),Size=UDim2.fromOffset(120,20),Text=entry[2],TextSize=15,TextXAlignment=Enum.TextXAlignment.Left})
end
local live=text(panel,{AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,0,1,0),Size=UDim2.new(1,0,0,20),Text='\u{25CF} LIVE   RNG '..RANGE,TextSize=15,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.fromRGB(255,90,80)})
for _,o in panel:GetDescendants() do if o:IsA('GuiObject') then o.ZIndex=12 end end -- above the corner mask
for y=0,CANVAS.Y,6 do frame(bg,{Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,2),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.82,ZIndex=20}) end
local glare=frame(bg,{Size=UDim2.fromScale(1,1),BackgroundColor3=GREEN,BackgroundTransparency=.96,ZIndex=21})

-- Map layout from the published graph ---------------------------------------------------
local graph:any={} -- decoded GeneratedGraph JSON
local rooms,labels,doors={},{},{}
local visited={}
local shownLevel
local function px(v) return v*SCALE end
local function mapPart(size,pos,color,transparency)
 local p=Instance.new('Part');p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
 p.Material=Enum.Material.Neon;p.Size=size;p.Position=pos;p.Color=color;p.Transparency=transparency;p.Parent=vf
 return p
end
local function build()
 for _,r in rooms do r.edge:Destroy();r.fill:Destroy() end
 for _,d in doors do d.part:Destroy() end
 for _,l in labels do l.label:Destroy() end
 table.clear(rooms);table.clear(labels);table.clear(doors);table.clear(visited)
 local value=mansion:FindFirstChild('GeneratedGraph')
 local ok,decoded=pcall(function() return HttpService:JSONDecode(value.Value) end)
 graph=ok and decoded or {rooms={},edges={}}
 for _,r in graph.rooms do
  local hall=r.type=='Hall'
  local w,d=r.x2-r.x1,r.z2-r.z1;local cx,cz=(r.x1+r.x2)/2,(r.z1+r.z2)/2
  -- Outline = a full-size slab under a slightly smaller fill (about the old 1.5 px stroke at this scale).
  local edgeT=hall and .6 or .3
  local edge=mapPart(Vector3.new(w,.1,d),Vector3.new(cx,0,cz),GREEN,edgeT)
  local fillColor=SCOPE_BG:Lerp(hall and DIM or GREEN,.1)
  local fill=mapPart(Vector3.new(math.max(.2,w-1.3),.1,math.max(.2,d-1.3)),Vector3.new(cx,.15,cz),fillColor,0)
  local tag=r.type=='Stair' and '\u{21C5}' or r.name==graph.start and 'EXIT' or nil
  if tag then
   local l=text(overlay,{AnchorPoint=mid,Position=centre,Size=UDim2.fromOffset(60,24),Text=tag,TextSize=r.type=='Stair' and 22 or 15,Font=Enum.Font.Arcade,ZIndex=4,Visible=false})
   table.insert(labels,{label=l,x=cx,z=cz,level=r.level})
  end
  table.insert(rooms,{edge=edge,fill=fill,edgeT=edgeT,visitedColor=SCOPE_BG:Lerp(hall and DIM or GREEN,.28),room=r})
 end
 for _,e in graph.edges do if e.kind~='stairs' and e.x then
  local thick=(e.kind=='open' and 6 or 4)/SCALE
  local span=e.width or 8
  local t=e.locked and .1 or .35
  local part=mapPart(e.axis=='x' and Vector3.new(span,.1,thick) or Vector3.new(thick,.1,span),Vector3.new(e.x,.3,e.z),e.locked and LOCK_COLOR or GREEN,t)
  table.insert(doors,{part=part,t=t,edge=e,level=levelOf(e.y or 0)})
 end end
 shownLevel=nil -- re-apply floor visibility to the new parts
end
local function rebuild()
 local ok,err=pcall(build)
 if not ok then warn('[FieldMap] map layout failed: '..tostring(err));shownLevel=nil end
end
rebuild()

-- Items: remembered only once this player has seen them --------------------------------
-- Looked up live: a missing or late folder must never stall the map (and the key bindings below).
local interactive,collision
local function folders()
 interactive=mansion:FindFirstChild('Interactive');collision=mansion:FindFirstChild('Collision')
 return interactive~=nil and collision~=nil
end
folders()
local seen,blips={}, {}
local function itemStyle(m)
 local k=m:GetAttribute('Kind')
 if k=='key' then return KEY_COLOR,9 elseif k=='pickup' then return ITEM_COLOR,8 elseif k=='cart' then return CART_COLOR,12 end
end
local sight=RaycastParams.new();sight.FilterType=Enum.RaycastFilterType.Include;sight.RespectCanCollide=false
local function scan()
 local cam=workspace.CurrentCamera;if not cam or not folders() then return end
 local origin=VRSupport.Head().Position
 sight.FilterDescendantsInstances={collision,interactive}
 for _,m in interactive:GetChildren() do
  if not seen[m] and itemStyle(m) and m.PrimaryPart and not m:GetAttribute('HeldBy') and not m:GetAttribute('CargoStored') then
   local pos=m.PrimaryPart.Position;local delta=pos-origin;local d=delta.Magnitude
   if d<6 then seen[m]=true
   elseif d<SEEN_RANGE then
    local _,onScreen=cam:WorldToViewportPoint(pos)
    if onScreen then
     local hit=workspace:Raycast(origin,delta,sight)
     if not hit or hit.Instance:IsDescendantOf(m) or hit.Distance>d-.6 then seen[m]=true end
    end
   end
  end
 end
end
local function forget()
 for _,b in blips do b:Destroy() end
 table.clear(seen);table.clear(blips)
end
local function onLayout() forget();rebuild() end
local graphValue=mansion:FindFirstChild('GeneratedGraph')
local function watchGraph(v) if v and v:IsA('StringValue') and v.Name=='GeneratedGraph' then graphValue=v;v.Changed:Connect(onLayout) end end
watchGraph(graphValue)
mansion.ChildAdded:Connect(function(c) if c.Name=='GeneratedGraph' then watchGraph(c);onLayout() end end)
mansion:GetAttributeChangedSignal('WorldRevision'):Connect(onLayout)
local mates={}
local function dot(color,size)
 local f=frame(overlay,{AnchorPoint=mid,Size=UDim2.fromOffset(size,size),BackgroundColor3=color,ZIndex=4,Visible=false});round(f);stroke(f,Color3.new(0,0,0),1,.4);return f
end
Players.PlayerRemoving:Connect(function(p) if mates[p] then mates[p]:Destroy();mates[p]=nil end end)

-- Holding ---------------------------------------------------------------------------
local holding={}
local open=false
local function canOpen()
 local c=player.Character;local hum=c and c:FindFirstChildOfClass('Humanoid')
 local panel=player:GetAttribute('VanShopOpen') or player:GetAttribute('AdminPassPanelOpen') or player:GetAttribute('AppearanceOpen')
 return hum~=nil and hum.Health>0 and player:GetAttribute('MissionActive')==true and not player:GetAttribute('RoundDead')
  and not player:GetAttribute('Hiding') and not player:GetAttribute('MonsterJumpscareActive') and not panel and not GuiService.MenuIsOpen
end
local function apply()
 local want=next(holding)~=nil and canOpen()
 if want==open then return end
 open=want
 player:SetAttribute('MapOpen',open or nil) -- instant local gate; FieldMapServer replicates the same value
 HoldPose.SetMap(open)
 event:FireServer(open)
end
-- High priority + Sink keeps Tab from also toggling the player list while reading.
CAS:BindActionAtPriority('FieldMapHold',function(_,state,input)
 if state==Enum.UserInputState.Begin then
  -- L2 is BANK (CursedItemsClient); L1 passes through for spectating when the map cannot open.
  if UIS:GetFocusedTextBox() or not canOpen() then return Enum.ContextActionResult.Pass end
  holding[input.KeyCode]=true
 elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then
  holding[input.KeyCode]=nil
 end
 apply()
 return Enum.ContextActionResult.Sink
end,false,Enum.ContextActionPriority.High.Value+1000,Enum.KeyCode.ButtonL1)
-- Keyboard: hold Tab or M. The player list is always off, so Tab only opens the map.
local MAP_KEYS={[Enum.KeyCode.Tab]='Tab',[Enum.KeyCode.M]='M'}
UIS.InputBegan:Connect(function(input)
 local key=MAP_KEYS[input.KeyCode]
 if key and not UIS:GetFocusedTextBox() and player:GetAttribute('MissionActive')==true then holding[key]=true;apply() end
end)
UIS.InputEnded:Connect(function(input)
 local key=MAP_KEYS[input.KeyCode]
 if key then holding[key]=nil;apply() end
end)
UIS.WindowFocusReleased:Connect(function() table.clear(holding);apply() end)

-- Phone: a hold button on the left, styled like LIGHT / USE / GRAB on the right.
local hud=Instance.new('ScreenGui');hud.Name='FieldMapGui';hud.ResetOnSpawn=false;hud.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;hud.Parent=player.PlayerGui
local button=Instance.new('TextButton');button.Name='MapAction';button.AnchorPoint=Vector2.new(0,1)
button.BackgroundColor3=Color3.fromRGB(20,28,26);button.BackgroundTransparency=.15;button.AutoButtonColor=true
button.Font=Enum.Font.GothamMedium;button.TextSize=12;button.TextColor3=Color3.fromRGB(231,236,221);button.Text='MAP';button.Visible=false;button.Parent=hud
Instance.new('UICorner',button).CornerRadius=UDim.new(0,16)
local buttonStroke=stroke(button,Color3.new(1,1,1),1,.7)
button.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then holding.touch=true;apply() end end)
button.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then holding.touch=nil;apply() end end)
-- Keyboard / gamepad hint under the flashlight indicator.
local hint=Instance.new('TextLabel');hint.Name='MapIndicator';hint.BackgroundTransparency=1;hint.Font=Enum.Font.FredokaOne
hint.TextColor3=Color3.fromRGB(244,236,210);hint.TextXAlignment=Enum.TextXAlignment.Left;hint.TextScaled=true;hint.TextTransparency=.28;hint.Parent=hud
local hintLimit=Instance.new('UITextSizeConstraint');hintLimit.MinTextSize=10;hintLimit.MaxTextSize=15;hintLimit.Parent=hint
local function touchMode() return InputHints.Get()=='touch' end
local function layout()
 local cam=workspace.CurrentCamera;if not cam then return end
 local small=cam.ViewportSize.Y<500;local side=small and TOUCH_SIDE_SMALL or TOUCH_SIDE
 button.Size=UDim2.fromOffset(side,side)
 -- small screens: above the flashlight indicator (which sits at 62% height), clear of the thumbstick
 button.Position=UDim2.new(0,22,1,small and -230 or -356)
 hint.Position=UDim2.new(0,18,.62,30);hint.Size=UDim2.fromOffset(small and 186 or 218,28)
end
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout);layout()

-- Frame update --------------------------------------------------------------------------
local scanAt=0
local blink=0
RunService:BindToRenderStep('FieldMapView',Enum.RenderPriority.Camera.Value+2,function(dt)
 local cam=workspace.CurrentCamera;if not cam then return end
 local now=os.clock()
 if not canOpen() and open then apply() end
 -- HUD
 local playing=player:GetAttribute('MissionActive')==true and not player:GetAttribute('RoundDead')
 local touch=touchMode()
 button.Visible=touch and playing
 button.BackgroundTransparency=open and .05 or .35;buttonStroke.Transparency=open and .55 or .8
 local pad=InputHints.Get()=='pad'
 hint.Visible=playing and not touch
 hint.Text='LEFT GRIP: HOLD FOR WRIST MAP'
 -- Remember items as they come into view.
 if now>=scanAt then scanAt=now+SEEN_INTERVAL;if playing then scan() end end
 -- Device in the left hand (pose from HoldPose, placed by SprintController this frame).
 view.Parent=cam
 local left=VRSupport.Hand(Enum.UserCFrame.LeftHand)
 local cf=left and left*CFrame.new(0,.14,-.24)*CFrame.Angles(-math.pi/2,0,0) or VRSupport.Head()*CFrame.new(0,-.5,-2.5)
 local visible=open
 if cf then device.PrimaryPart.CFrame=cf end
 visible=visible and cf~=nil
 showDevice(visible)
 surface.Enabled=visible
 local character=player.Character
 local hand=character and character:FindFirstChild('LeftHand')
 local own=hand and hand:FindFirstChild('FieldMapDevice')
 if own then for _,p in own:GetDescendants() do if p:IsA('BasePart') then p.LocalTransparencyModifier=1 end end end
 if not visible then return end
 blink+=dt
 if tip then tip.Transparency=(blink%1)<.5 and 0 or .7 end
 live.TextTransparency=(blink%1.2)<.6 and 0 or .6
 glare.BackgroundTransparency=.955+math.sin(now*23)*.008
 -- Radar: heading-up, centred on the player.
 local root=character and character:FindFirstChild('HumanoidRootPart')
 if not root then return end
 local pos=root.Position;local level=levelOf(pos.Y-2.5)
 local look=VRSupport.Head().LookVector;local heading=math.atan2(look.X,-look.Z)
 -- Heading-up: the map camera looks straight down with the player's facing as screen-up.
 local fwd=Vector3.new(look.X,0,look.Z);if fwd.Magnitude<1e-3 then fwd=Vector3.new(0,0,-1) end
 vfCam.CFrame=CFrame.lookAt(Vector3.new(pos.X,CAM_H,pos.Z),Vector3.new(pos.X,0,pos.Z),fwd.Unit)
 local ch,sh=math.cos(heading),math.sin(heading)
 local LIMIT=SCOPE_PX/2-6
 -- 2D overlay items use the same projection as the camera and hide outside the disc.
 local function place(g,x,z)
  local dx,dz=x-pos.X,z-pos.Z
  local sx,sy=px(dx*ch+dz*sh),px(-dx*sh+dz*ch)
  if sx*sx+sy*sy>LIMIT*LIMIT then return false end
  g.Position=UDim2.new(.5,sx,.5,sy);return true
 end
 for _,l in labels do l.label.Visible=l.level==level and place(l.label,l.x,l.z) end
 if level~=shownLevel then
  shownLevel=level
  for _,r in rooms do local on=r.room.level==level;r.edge.Transparency=on and r.edgeT or 1;r.fill.Transparency=on and 0 or 1 end
  for _,d in doors do d.part.Transparency=d.level==level and d.t or 1 end
  floorText.Text='F'..(level+1);floorHint.Text=level==0 and 'GROUND FLOOR' or 'UPPER FLOOR'
 end
 for _,r in rooms do
  local room=r.room
  if room.level==level and pos.X>=room.x1 and pos.X<=room.x2 and pos.Z>=room.z1 and pos.Z<=room.z2 and not visited[room.name] then
   visited[room.name]=true;r.fill.Color=r.visitedColor
  end
 end
 local sweep=(now/SWEEP_SECONDS%1)*math.pi*2
 for i,carrier in sweeps do carrier.Rotation=math.deg(sweep)-i*4 end
 -- Seen items: blips at their current position, pinged by the sweep.
 local items,keys=0,0
 for m in seen do
  if interactive==nil or m.Parent~=interactive or not m.PrimaryPart then seen[m]=nil;if blips[m] then blips[m]:Destroy();blips[m]=nil end;continue end
  local color,size=itemStyle(m)
  local b=blips[m];if not b then b=dot(color,size);blips[m]=b end
  local p=m.PrimaryPart.Position
  local onFloor=not m:GetAttribute('HeldBy') and not m:GetAttribute('CargoStored') and levelOf(p.Y-.5)==level
  if onFloor then if m:GetAttribute('Kind')=='key' then keys+=1 elseif m:GetAttribute('Kind')=='pickup' then items+=1 end end
  local shown=onFloor and place(b,p.X,p.Z)
  b.Visible=shown
  if shown then
   local bearing=math.atan2(p.X-pos.X,-(p.Z-pos.Z))-heading
   local behind=(sweep-bearing)%(math.pi*2)
   b.BackgroundTransparency=.1+.55*(behind/(math.pi*2))
  end
 end
 counts.Text=('KEYS  %02d\nLOOT  %02d'):format(keys,items)
 -- Crew on this floor.
 for _,p in Players:GetPlayers() do if p~=player then
  local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
  local d=mates[p];if not d then d=dot(MATE_COLOR,8);mates[p]=d end
  local show=r~=nil and p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead') and levelOf(r.Position.Y-2.5)==level
  if show then show=place(d,r.Position.X,r.Position.Z) end
  d.Visible=show
 end end
end)
player.CharacterAdded:Connect(function() table.clear(holding);apply() end)

end
