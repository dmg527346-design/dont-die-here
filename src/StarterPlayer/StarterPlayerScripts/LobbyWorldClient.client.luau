-- Local presentation/input for the server-owned 3D lobby. MainMenuClient owns panels.
-- Circles: a translucent zone box around each pad. Walking into a Free zone hosts, into an Open zone joins (no button).
-- While the player belongs to a circle (LobbyCircle attr) they are kept inside its box until they cancel or leave.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local RankCatalog=require(RS:WaitForChild('RankCatalog'))
local player=Players.LocalPlayer
local state=RS:WaitForChild('LobbyState')
local bridge
local MIN_ZOOM,MAX_ZOOM=7,26
local CIRCLE_COUNT,PROMPT_DISTANCE,REFRESH_SECONDS=20,12,.2
local ZONE_RADIUS,ZONE_HEIGHT,LOCK_MARGIN=8,10.5,.8    -- LobbyZone is a cylinder: radius 8, 10 studs tall
local ENTRY_RADIUS_SLACK=1                            -- anywhere inside the cylinder (radius 8.5); the server allows Radius+5 for lag
local ENTRY_TRIES=4                                   -- retries per visit (a reply can be a lag rejection)
local LABEL_SHOW_DISTANCE,LABEL_RISE=95,12.5 -- circle sign: floats above the circle, clear of the 10.5-stud glowing zone; 95 so the outer-ring circles (72 studs out) read from spawn
local LABEL_WIDTH,LABEL_HEIGHT=260,84
local TOKEN_ICON,ROBUX_ICON,COSMETIC_ICON='rbxassetid://73345115390797','rbxassetid://112368980987150','rbxassetid://106304373894739'
local COLORS={Free=Color3.fromRGB(120,235,140),Setup=Color3.fromRGB(255,170,60),Open=Color3.fromRGB(170,120,255),Full=Color3.fromRGB(255,90,90),Starting=Color3.fromRGB(255,90,90)}
local circles,stores={},{}
local savedCamera,activeMode=false,false
local accumulator=0
local armed={}          -- [index]=false after an entry attempt or a leave while inside; re-armed on stepping out
local lastEntry={}      -- [index]=os.clock() of the last entry request
local tries={}          -- [index]=entry requests sent during this visit
local ghosts={}         -- floating ghost models -> base pivot
local pendingUntil=0    -- one walk-in request in flight at a time (cleared when the circle attrs arrive)
local function menuActive()
 return (state:GetAttribute('Mode')=='Menu'or player:GetAttribute('ReturnedToLobby')==true) and player:GetAttribute('MissionActive')~=true
end
local function alive()
 local c=player.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local root=c and c:FindFirstChild('HumanoidRootPart')
 if h and h.Health>0 and root and root:IsA('BasePart')then return root,h end
 return nil
end
local function interactActive()
 return menuActive()and player:GetAttribute('LobbyReady')==true and alive()~=nil
end
local function fire(action,arg)
 if bridge and bridge.Parent and menuActive()then bridge:Fire(action,arg)end
end
-- Wait independently: the camera and world still work while the menu creates its bridge.
task.spawn(function()
 local scripts=player:WaitForChild('PlayerScripts')
 local menu=scripts:WaitForChild('MainMenuClient')
 local candidate=menu:WaitForChild('LobbyMenuBridge')
 if candidate:IsA('BindableEvent')then bridge=candidate end
end)
-- Store signs are fixed-pixel billboards: on a phone 260 px is a third of the screen (owner 2026-10-24), so touch
-- screens draw them at SIGN_TOUCH_SCALE.
local SIGN_TOUCH_SCALE,SIGN_PHONE_SCALE=.68,.5 -- tablets / phones (owner 2026-10-24: still too big on phones at .68)
local function signScale()
 if not InputHints.IsMobile()then return 1 end
 local vp=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1024,768)
 return math.min(vp.X,vp.Y)<500 and SIGN_PHONE_SCALE or SIGN_TOUCH_SCALE -- a phone in landscape is under 500 px tall
end
local function billboard(anchor,name,icon,rise)
 local gui=Instance.new('BillboardGui');gui.Name=name;gui.Adornee=anchor
 local k=signScale()
 gui.Size=UDim2.fromOffset(LABEL_WIDTH*k,(icon and LABEL_HEIGHT+50 or LABEL_HEIGHT)*k);gui.StudsOffsetWorldSpace=Vector3.new(0,rise,0)
 gui.AlwaysOnTop=true;gui.MaxDistance=math.huge;-- shown/hidden by character distance in refreshWorld; MaxDistance would measure from the zoomed-out camera
 gui.LightInfluence=0;gui.Enabled=false;gui.Parent=anchor
 local top=0
 if icon then
  local image=Instance.new('ImageLabel');image.Name='Icon';image.BackgroundTransparency=1
  image.AnchorPoint=Vector2.new(.5,0);image.Position=UDim2.fromScale(.5,0);image.Size=UDim2.fromOffset(48*k,48*k);image.Image=icon;image.Parent=gui;top=50*k
 end
 local title=Instance.new('TextLabel');title.Name='Title';title.BackgroundTransparency=1
 title.AnchorPoint=Vector2.new(.5,0);title.Position=UDim2.new(.5,0,0,top);title.Size=UDim2.new(1,0,0,36*k);title.Font=Enum.Font.FredokaOne
 title.TextSize=math.floor(26*k+.5);title.TextColor3=Color3.fromRGB(244,236,210);title.TextStrokeColor3=Color3.fromRGB(14,8,24);title.TextStrokeTransparency=0
 title.TextXAlignment=Enum.TextXAlignment.Center;title.TextWrapped=true;title.Parent=gui
 local detail=title:Clone();detail.Name='Details';detail.Position=UDim2.new(.5,0,0,top+38*k);detail.Size=UDim2.new(1,0,0,40*k);detail.TextSize=math.floor(16*k+.5);detail.Visible=k>=SIGN_TOUCH_SCALE;-- phones: icon + name only; the small line would be unreadable
 detail.TextColor3=Color3.fromRGB(244,236,210);detail.Parent=gui
 return gui,title,detail
end
-- Circle sign: a real flat sign floating above the centre of the circle (client-only part under the camera) that turns to
-- face the camera every frame, so it reads as the circle's banner and never covers the players standing inside.
local signs={} -- [part]=pad
local function circleSign(pad)
 local part=Instance.new('Part');part.Name='LobbyCircleSign';part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
 part.CastShadow=false;part.Transparency=1;part.Size=Vector3.new(9,2.6,.05);part.CFrame=CFrame.new(pad.Position+Vector3.new(0,LABEL_RISE,0))
 local gui=Instance.new('SurfaceGui');gui.Name='LobbyCircleLabel';gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
 gui.PixelsPerStud=40;gui.LightInfluence=0;gui.Enabled=false;gui.Parent=part
 local title=Instance.new('TextLabel');title.Name='Title';title.BackgroundTransparency=1;title.Size=UDim2.fromScale(1,.55)
 title.Font=Enum.Font.FredokaOne;title.TextSize=46;title.TextColor3=Color3.fromRGB(244,236,210);title.TextStrokeColor3=Color3.fromRGB(14,8,24);title.TextStrokeTransparency=0
 title.TextXAlignment=Enum.TextXAlignment.Center;title.Parent=gui
 local badge=Instance.new('ImageLabel');badge.Name='HostRank';badge.BackgroundTransparency=1;badge.Size=UDim2.fromOffset(44,44);badge.Position=UDim2.fromOffset(0,6);badge.ScaleType=Enum.ScaleType.Fit;badge.Visible=false;badge.Parent=gui
 local detail=title:Clone();detail.Name='Details';detail.Position=UDim2.fromScale(0,.55);detail.Size=UDim2.fromScale(1,.4);detail.TextSize=26;detail.Parent=gui
 part.Parent=workspace.CurrentCamera
 signs[part]=pad
 return gui,title,detail,part
end
local function faceSigns()
 local cam=workspace.CurrentCamera;if not cam then return end
 local eye=cam.CFrame.Position
 for part,pad in signs do
  if part.LobbyCircleLabel.Enabled then
   local c=pad.Position+Vector3.new(0,LABEL_RISE,0)
   local look=Vector3.new(eye.X,c.Y,eye.Z)
   if (look-c).Magnitude>.1 then part.CFrame=CFrame.lookAt(c,look)end
  end
 end
end
local function prompt(anchor,name)
 local result=Instance.new('ProximityPrompt');result.Name=name;result.MaxActivationDistance=PROMPT_DISTANCE
 result.HoldDuration=0;result.ClickablePrompt=true;result.RequiresLineOfSight=false;result.KeyboardKeyCode=Enum.KeyCode.E;result.GamepadKeyCode=Enum.KeyCode.ButtonX
 result.Enabled=false;result.Parent=anchor;return result
end
local function addCircle(index,model)
 local pad=model:FindFirstChild('Pad');if not pad or not pad:IsA('BasePart')then return end
 local old=pad:FindFirstChild('LobbyCirclePrompt');if old then old:Destroy()end
 local old2=pad:FindFirstChild('LobbyCircleLabel');if old2 then old2:Destroy()end
 local gui,title,detail,sign=circleSign(pad)
 circles[index]={model=model,pad=pad,gui=gui,title=title,detail=detail,sign=sign}
 if armed[index]==nil then armed[index]=true end
end
local function addStore(id,model,icon)
 local anchor=model:FindFirstChild('PromptAnchor');if not anchor or not anchor:IsA('BasePart')then return end
 local gui,title,detail=billboard(anchor,'LobbyStoreLabel',icon,4)
 title.Text=id=='Tokens'and'TOKEN STORE'or id=='Robux'and'ROBUX STORE'or'COSMETICS';detail.Text=id=='Cosmetics'and'Colours, hats and outfits'or'Browse upgrades and cosmetics'
 local entry={model=model,anchor=anchor,gui=gui,prompt=prompt(anchor,'LobbyStorePrompt'),lastTrigger=0}
 entry.prompt.ActionText=id=='Cosmetics'and'Change look'or'Open store';entry.prompt.ObjectText=id=='Tokens'and'Token Store'or id=='Robux'and'Robux Store'or'Cosmetics'
 entry.connection=entry.prompt.Triggered:Connect(function()
  if not interactActive()or os.clock()-entry.lastTrigger<.5 then return end
  entry.lastTrigger=os.clock();fire('open',id=='Cosmetics'and'Character'or id)
 end)
 stores[id]=entry
end
local function disposeCircle(entry)signs[entry.sign]=nil;entry.sign:Destroy()end
local function disposeStore(entry)entry.connection:Disconnect();entry.prompt:Destroy();entry.gui:Destroy()end
-- Position of p relative to a circle's zone: inside box?, horizontal distance from the pad centre, local offset.
local function zoneOffset(entry,pos)
 local c=entry.pad.Position
 local d=Vector3.new(pos.X-c.X,0,pos.Z-c.Z)
 local inside=d.Magnitude<=ZONE_RADIUS and pos.Y<c.Y+ZONE_HEIGHT+2 and pos.Y>c.Y-4
 return inside,d.Magnitude,d
end
local function myCircle()
 local index=player:GetAttribute('LobbyCircle');return index,index and circles[index]
end
local function refreshWorld()
 local enabled=menuActive()
 local world=workspace:FindFirstChild('LobbyWorld');local folder=world and world:FindFirstChild('Circles')
 local root=alive()
 local mine=player:GetAttribute('LobbyCircle')
 for index=1,CIRCLE_COUNT do
  local model=folder and folder:FindFirstChild('Circle'..index);local entry=circles[index]
  if entry and (entry.model~=model or not entry.pad.Parent)then disposeCircle(entry);circles[index]=nil;entry=nil end
  if model and model:IsA('Model')and not entry then addCircle(index,model);entry=circles[index]end
  if entry then
   local status=model:GetAttribute('Status')or'Setup';local color=COLORS[status]or COLORS.Setup
   local owner=model:GetAttribute('OwnerName')or'Host';local count=model:GetAttribute('Count')or 0;local size=model:GetAttribute('Size')or 0
   local access=model:GetAttribute('Access')or'Public'
   entry.title.Text=status=='Free'and('START A RUN')or(string.upper(owner).."'S RUN")
   entry.title.TextColor3=color
   local ownerId=tonumber(model:GetAttribute('OwnerUserId'))
   local host=ownerId and Players:GetPlayerByUserId(ownerId)
   local badge=entry.gui:FindFirstChild('HostRank')
   local showRank=status~='Free' and host~=nil
   if badge and badge:IsA('ImageLabel') then
    badge.Visible=showRank
    badge.Image=host and RankCatalog.Get(host:GetAttribute('RR')).icon or ''
   end
   entry.title.Position=UDim2.fromOffset(showRank and 48 or 0,0)
   entry.title.Size=UDim2.new(1,showRank and -48 or 0,.55,0)
   entry.title.TextScaled=true

   entry.detail.Text=status=='Free'and'Walk in to start your own'
    or status=='Setup'and'Host is choosing settings'
    or status=='Starting'and'Starting...'
    or status=='Full'and(count..' / '..size..'  FULL')
    or(count..' / '..size..' players  |  '..(access=='Password'and'Password'or access=='Friends'and'Friends only'or'Walk in to join'))
   local near=root and (root.Position-entry.pad.Position).Magnitude<=LABEL_SHOW_DISTANCE
   entry.gui.Enabled=enabled and near==true and mine~=index
   local light=model:FindFirstChild('StatusLight',true)
   if light and(light:IsA('BasePart')or light:IsA('Light'))then light.Color=color end
   for _,name in {'LobbyPad_neon','LobbyZone_neon'}do local neon=model:FindFirstChild(name,true);if neon and neon:IsA('BasePart')then neon.Color=color end end
   local walls=model:FindFirstChild('LobbyZone',true);if walls and walls:IsA('BasePart')then walls.Color=color:Lerp(Color3.new(1,1,1),.35)end
  end
 end
 local models=world and world:FindFirstChild('Stores')
 for _,info in {{'Tokens','TokenStore',TOKEN_ICON},{'Robux','RobuxStore',ROBUX_ICON},{'Cosmetics','CosmeticStand',COSMETIC_ICON}}do
  local id,name,icon=info[1],info[2],info[3];local model=models and models:FindFirstChild(name);local entry=stores[id]
  if entry and(entry.model~=model or not entry.anchor.Parent)then disposeStore(entry);stores[id]=nil;entry=nil end
  if model and not entry then addStore(id,model,icon);entry=stores[id]end
  if entry then
   local near=root and (root.Position-entry.anchor.Position).Magnitude<=LABEL_SHOW_DISTANCE
   entry.gui.Enabled=enabled and near==true
   entry.prompt.Enabled=enabled and interactActive() and bridge~=nil
  end
 end
end
-- Walk-in entry: host a Free circle, join an Open one. Each zone fires once per visit; stepping out re-arms it.
local wasMine=nil
local function zoneStep()
 if not menuActive()then return end
 local root=alive();if not root then return end
 local mine=player:GetAttribute('LobbyCircle')
 if wasMine and not mine then armed[wasMine]=false end -- left/cancelled while standing inside: no instant re-entry
 if mine~=wasMine then pendingUntil=0 end
 wasMine=mine
 if os.clock()<pendingUntil then return end
 for index,entry in circles do
  local inside=zoneOffset(entry,root.Position)
  local off=root.Position-entry.pad.Position;local dist=Vector3.new(off.X,0,off.Z).Magnitude
  if not inside then armed[index]=true;tries[index]=0
  elseif armed[index] and not mine and not player:GetAttribute('LobbyPartyId') and interactActive() and bridge
   and dist<=(tonumber(entry.model:GetAttribute('Radius'))or 7.5)+ENTRY_RADIUS_SLACK and os.clock()-(lastEntry[index]or 0)>.6 then
   local status=entry.model:GetAttribute('Status')
   if status=='Free'or status=='Open'then
    tries[index]=(tries[index]or 0)+1;armed[index]=tries[index]<ENTRY_TRIES;lastEntry[index]=os.clock();pendingUntil=os.clock()+1
    fire(status=='Free'and'host'or'join',index)
    return -- one request in flight: overlapping box corners must not fire a second one this frame
   end
  end
 end
end
-- Lock: a circle's member/host stays inside its box. Far away (respawn, fall recovery) puts them back in the middle.
local function lockStep()
 if not menuActive()then return end
 local _,entry=myCircle();if not entry then return end
 local root,hum=alive();if not root then return end
 if hum.SeatPart or hum.Sit or root.Anchored then return end
 local inside,_,d=zoneOffset(entry,root.Position)
 local limit=ZONE_RADIUS-LOCK_MARGIN
 local c=entry.pad.Position
 if not inside or d.Magnitude>limit+2 then
  -- respawned, recovered from a fall or teleported away: back to the middle of your box
  root.CFrame=CFrame.new(c.X,c.Y+4,c.Z)*(root.CFrame-root.Position);root.AssemblyLinearVelocity=Vector3.zero;return
 end
 if d.Magnitude>limit then
  -- pull back onto the circle edge and drop the outward part of the velocity
  local dir=d.Unit;local pos=root.Position
  root.CFrame=root.CFrame+Vector3.new(c.X+dir.X*limit-pos.X,0,c.Z+dir.Z*limit-pos.Z)
  local v=root.AssemblyLinearVelocity;local out=v.X*dir.X+v.Z*dir.Z
  if out>0 then root.AssemblyLinearVelocity=v-Vector3.new(dir.X*out,0,dir.Z*out)end
 end
end
local function cameraMode(enabled)
 if enabled==activeMode then return end;activeMode=enabled
 if enabled then
  savedCamera={mode=player.CameraMode,min=player.CameraMinZoomDistance,max=player.CameraMaxZoomDistance,mouse=UIS.MouseBehavior,icon=UIS.MouseIconEnabled,camera=workspace.CurrentCamera,cameraType=workspace.CurrentCamera and workspace.CurrentCamera.CameraType,subject=workspace.CurrentCamera and workspace.CurrentCamera.CameraSubject}
  player.CameraMode=Enum.CameraMode.Classic;player.CameraMaxZoomDistance=MAX_ZOOM;player.CameraMinZoomDistance=MIN_ZOOM
 else
  if savedCamera then
   -- Missions are first person. The saved mode can be the spectator's Classic (left a run while dead), which kept
   -- the next mission in third person.
   player.CameraMinZoomDistance=savedCamera.min;player.CameraMaxZoomDistance=savedCamera.max;player.CameraMode=Enum.CameraMode.LockFirstPerson
   UIS.MouseBehavior=savedCamera.mouse;UIS.MouseIconEnabled=savedCamera.icon
   local camera=savedCamera.camera
   if player:GetAttribute('MissionActive')~=true and camera==workspace.CurrentCamera and camera and camera.CameraType==Enum.CameraType.Custom then
    if savedCamera.subject and savedCamera.subject.Parent then camera.CameraSubject=savedCamera.subject end
    if savedCamera.cameraType then camera.CameraType=savedCamera.cameraType end
   end
   savedCamera=false
  end
 end
 refreshWorld()
end
local function ghostStep()
 local world=workspace:FindFirstChild('LobbyWorld');local art=world and world:FindFirstChild('Art');local folder=art and art:FindFirstChild('Ghosts')
 if not folder then return end
 local t=os.clock()
 for i,g in folder:GetChildren()do
  if g:IsA('Model')then
   local base=ghosts[g];if not base then base=g:GetPivot();ghosts[g]=base end
   g:PivotTo(base*CFrame.new(0,math.sin(t*1.3+i)*1.2,0)*CFrame.Angles(0,math.sin(t*.4+i)*.5,0))
  end
 end
end
Run.PreRender:Connect(function(dt)
 local enabled=menuActive();cameraMode(enabled)
 if enabled then
  -- Only write on a change: per-frame camera writes reach the Roblox settings menu (CoreGui GameSettings re-entrancy error, 2026-10-25).
  if player.CameraMode~=Enum.CameraMode.Classic then player.CameraMode=Enum.CameraMode.Classic end
  if player.CameraMaxZoomDistance~=MAX_ZOOM then player.CameraMaxZoomDistance=MAX_ZOOM end;if player.CameraMinZoomDistance~=MIN_ZOOM then player.CameraMinZoomDistance=MIN_ZOOM end
  -- Free cursor, but leave the camera module alone while the right button drags the view (it locks the cursor then).
  if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)and UIS.MouseBehavior==Enum.MouseBehavior.LockCenter then UIS.MouseBehavior=Enum.MouseBehavior.Default end
  if not UIS.MouseIconEnabled then UIS.MouseIconEnabled=true end
  local camera=workspace.CurrentCamera;local _,hum=alive()
  -- InspectActive (InspectCamera, owner 2026-10-29): the Case Board / plaque inspect owns the camera until it glides back.
  if camera and hum and player:GetAttribute('InspectActive')~=true then if camera.CameraType~=Enum.CameraType.Custom then camera.CameraType=Enum.CameraType.Custom end;if camera.CameraSubject~=hum then camera.CameraSubject=hum end end
  ghostStep();faceSigns()
 end
 accumulator+=dt;if accumulator>=REFRESH_SECONDS then accumulator=0;refreshWorld()end
end)
Run.Heartbeat:Connect(function()zoneStep();lockStep()end)
-- Jump to leave: someone who JOINED another player's circle can jump to step out of the party (the host cannot;
-- the host cancels or leaves from the menu). Works for keyboard, touch and gamepad through JumpRequest.
local jumpLeaveAt=0
UIS.JumpRequest:Connect(function()
 if not interactActive()or os.clock()-jumpLeaveAt<1.5 then return end
 local _,entry=myCircle()
 if not entry or not player:GetAttribute('LobbyPartyId')then return end
 if entry.model:GetAttribute('OwnerUserId')==player.UserId then return end
 jumpLeaveAt=os.clock();fire('leave')
end)
-- Leaderboard stand: an interactive board (own SurfaceGui in PlayerGui so its arrows can be clicked/tapped), section
-- arrows + a "Next board" prompt for gamepads, the viewer's own row at the bottom, and their avatar on the left.
local lobbyEvent=RS:WaitForChild('LobbyEvent')
local Catalog=require(RS:WaitForChild('LobbyShopCatalog'))
local CATS=Catalog.Categories
local CustomTags=require(RS:WaitForChild('CustomTags'))
local boardSeq=7000000 -- own id range so MainMenuClient/VanShop request ids never collide
local boardWaiting={}  -- [request id]=category index
local boardCat,boardData,nextBoard=1,{},0
local boardGui,boardRowsUi,boardPrompt,boardBuilt
local CREAM,GOLD,MUTED,ORANGE=Color3.fromRGB(244,236,210),Color3.fromRGB(255,220,120),Color3.fromRGB(190,160,255),Color3.fromRGB(255,170,70)
local function fmt(cat,v)
 if type(v)~='number'then return '-'end
 if cat.time then local ms=math.floor(v);return ('%d:%02d.%02d'):format(ms//60000,(ms//1000)%60,(ms%1000)//10)end
 local digits=tostring(math.floor(v))
 local n=digits:reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','')
 if cat.percent then return n..'%' end
 return cat.money and('$'..n)or n
end
local function uiText(parent,name,x,y,w,h,size,color,align)
 local l=Instance.new('TextLabel');l.Name=name;l.BackgroundTransparency=1;l.Position=UDim2.fromScale(x,y);l.Size=UDim2.fromScale(w,h)
 l.Font=Enum.Font.FredokaOne;l.TextSize=size;l.TextColor3=color;l.TextStrokeTransparency=.4;l.TextXAlignment=align or Enum.TextXAlignment.Left;l.Text='';l.Parent=parent
 return l
end
local function requestBoard()
 boardSeq+=1;boardWaiting[boardSeq]=boardCat;nextBoard=os.clock()+60
 lobbyEvent:FireServer(boardSeq,'leaderboard',{category=CATS[boardCat].id})
end
local function drawBoard()
 if not boardRowsUi then return end
 local cat=CATS[boardCat];local d=boardData[cat.id]
 boardRowsUi.category.Text=cat.label..'  ('..boardCat..'/'..#CATS..')'
 for i=1,10 do
  local r=d and d.rows and d.rows[i]
  boardRowsUi.rows[i].Text=r and('#'..i..'  '..tostring(r.name))or(i==1 and(d==nil and'Loading...'or d.error and'Leaderboard unavailable right now'or'No survivors yet. Be the first!')or'')
  boardRowsUi.values[i].Text=r and fmt(cat,r.value)or''
  -- custom tag picture (e.g. the Ghoulfriend bow) right after the player's name
  local icon=boardRowsUi.rows[i]:FindFirstChild('TagIcon');local tag=r and CustomTags.Get(r.id)
  if icon then
   icon.Visible=tag~=nil and tag.icon~=nil;if icon.Visible then icon.Image=tag.icon end
   local label=boardRowsUi.rows[i];task.defer(function()icon.Position=UDim2.new(0,label.TextBounds.X+6,.5,0)end)
  end
 end
 local me=d and d.me
 boardRowsUi.me.Text='YOU  '..(me and me.rank and('#'..me.rank..'  ')or'')..player.DisplayName
 boardRowsUi.meValue.Text=me and(type(me.value)=='number'and me.value>0 and fmt(cat,me.value)or'no score yet')or''
end
local function stepBoard(dir)
 boardCat=(boardCat-1+dir)%#CATS+1;drawBoard()
 local d=boardData[CATS[boardCat].id]
 if not d or os.clock()-(d.time or 0)>60 then requestBoard()end
end
local function buildBoard(face,pixelsPerStud)
 if boardGui then boardGui:Destroy()end
 for _,g in face:GetChildren()do if g:IsA('SurfaceGui')then g.Enabled=false end end -- static placeholder from the installer
 local gui=Instance.new('SurfaceGui');gui.Name='LobbyBoardUI';gui.Adornee=face;gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
 gui.PixelsPerStud=pixelsPerStud or 40;gui.LightInfluence=0;gui.ResetOnSpawn=false;gui.Parent=player:WaitForChild('PlayerGui')
 uiText(gui,'Title',0,.01,1,.09,40,ORANGE,Enum.TextXAlignment.Center).Text='TOP SURVIVORS'
 local ui={rows={},values={}}
 ui.category=uiText(gui,'Category',.16,.105,.68,.075,22,MUTED,Enum.TextXAlignment.Center)
 for _,info in{{'Prev','<',.03,-1},{'Next','>',.85,1}}do
  local b=Instance.new('TextButton');b.Name=info[1];b.Text=info[2];b.Position=UDim2.fromScale(info[3],.1);b.Size=UDim2.fromScale(.12,.085)
  b.Font=Enum.Font.FredokaOne;b.TextSize=30;b.TextColor3=CREAM;b.BackgroundColor3=Color3.fromRGB(90,55,130);b.AutoButtonColor=true;b.Parent=gui
  Instance.new('UICorner',b).CornerRadius=UDim.new(.3,0)
  b.Activated:Connect(function()stepBoard(info[4])end)
 end
 for i=1,10 do
  local y=.2+(i-1)*.066
  ui.rows[i]=uiText(gui,'Row'..i,.04,y,.62,.062,21,i<=3 and GOLD or CREAM)
  ui.values[i]=uiText(gui,'Value'..i,.62,y,.34,.062,21,i<=3 and GOLD or CREAM,Enum.TextXAlignment.Right)
  local icon=Instance.new('ImageLabel');icon.Name='TagIcon';icon.BackgroundTransparency=1;icon.AnchorPoint=Vector2.new(0,.5);icon.Size=UDim2.fromOffset(24,24);icon.Visible=false;icon.Parent=ui.rows[i]
 end
 local line=Instance.new('Frame');line.BackgroundColor3=ORANGE;line.BorderSizePixel=0;line.Position=UDim2.fromScale(.04,.872);line.Size=UDim2.fromScale(.92,.006);line.Parent=gui
 ui.me=uiText(gui,'Me',.04,.888,.6,.09,24,ORANGE)
 ui.meValue=uiText(gui,'MeValue',.6,.888,.36,.09,24,ORANGE,Enum.TextXAlignment.Right)
 boardGui,boardRowsUi=gui,ui
 if boardPrompt then boardPrompt:Destroy()end
 boardPrompt=prompt(face,'LobbyBoardPrompt');boardPrompt.ActionText='Next board';boardPrompt.ObjectText='Leaderboard';boardPrompt.MaxActivationDistance=16
 boardPrompt.Triggered:Connect(function()stepBoard(1)end)
 drawBoard()
end
lobbyEvent.OnClientEvent:Connect(function(action,data)
 if action~='response'or type(data)~='table'or not boardWaiting[data.id]then return end
 local catIndex=boardWaiting[data.id];boardWaiting[data.id]=nil
 local value=data.ok and type(data.data)=='table'and data.data or nil
 boardData[CATS[catIndex].id]={rows=value and value.rows or {},me=value and value.me,error=not data.ok,time=os.clock()}
 if not data.ok then nextBoard=math.min(nextBoard,os.clock()+5)end
 if catIndex==boardCat then drawBoard()end
end)
-- Your avatar stands on the left of the board: a still copy of your current character, refreshed as it changes.
local avatarModel,avatarAt=nil,0
local function placeAvatar(board)
 local c=player.Character;local hum=c and c:FindFirstChildOfClass('Humanoid')
 if not c or not hum or hum.Health<=0 then return end
 local was=c.Archivable;c.Archivable=true;local copy=c:Clone();c.Archivable=was
 if not copy then return end
 for _,x in copy:GetDescendants()do
  if x:IsA('LuaSourceContainer')or x:IsA('Sound')or x:IsA('BillboardGui')or x:IsA('ProximityPrompt')or x:IsA('ForceField')then x:Destroy()
  elseif x:IsA('BasePart')then x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false end
 end
 local h=copy:FindFirstChildOfClass('Humanoid');if h then h.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None;h.PlatformStand=true end
 copy.Name='BoardAvatar'
 local _,size=copy:GetBoundingBox()
 copy:PivotTo(board:GetPivot()*CFrame.new(9.6,size.Y/2+.05,-1.2)*CFrame.Angles(0,math.rad(-15),0))
 if avatarModel then avatarModel:Destroy()end
 avatarModel=copy;copy.Parent=workspace
end
-- In a mission the same board is drawn on the van wall (RecoveryModels VanLeaderboard), without the avatar.
local function vanBoard()
 local camp=player:GetAttribute('MissionActive')==true and workspace:FindFirstChild('RecoveryCamp')
 return camp and camp:FindFirstChild('VanLeaderboard',true)
end
local function boardTick()
 local van=not menuActive()and vanBoard()or nil
 if van then
  if avatarModel then avatarModel:Destroy();avatarModel=nil end
  if boardBuilt~=van then boardBuilt=van;buildBoard(van,120)end
  boardGui.Enabled=true;boardPrompt.Enabled=alive()~=nil;boardPrompt.MaxActivationDistance=10
  if os.clock()>=nextBoard then requestBoard()end
  return
 end
 local world=workspace:FindFirstChild('LobbyWorld');local board=world and world:FindFirstChild('Leaderboard')
 local face=board and board:FindFirstChild('BoardFace',true)
 if not menuActive()or not face then
  if boardGui then boardGui.Enabled=false end;if boardPrompt then boardPrompt.Enabled=false end
  if avatarModel and not menuActive()then avatarModel:Destroy();avatarModel=nil end
  return
 end
 if boardBuilt~=face then boardBuilt=face;buildBoard(face)end
 boardGui.Enabled=true;boardPrompt.Enabled=interactActive()
 if os.clock()>=nextBoard then requestBoard()end
 if os.clock()-avatarAt>15 or not(avatarModel and avatarModel.Parent)then avatarAt=os.clock();placeAvatar(board)end
end
Run.Heartbeat:Connect(boardTick)
-- ===== Spook-o-Meter (WorldB 2026-10-27) =====
-- A 4-lane carnival courage meter (LobbyShowcaseServer builds LobbyWorld.Showcase.SpookOMeter). Stand on a lane pad and
-- a ghost puck in your rank colour shoots up its tube to your RR: one 1.15-stud stripe per rank tier, divisions inside
-- it. A ring marks the season peak (RRPeak). The lantern burns while this player's first clear of the UTC day still
-- earns the daily RR bonus (ProgressCore 'clear': RRDay/RRStreak). With 2+ lanes in use the title names the RR
-- bonuses the group gets by clearing together (RankRating.Gain: friends x1.1, carrying someone 2+ tiers lower x1.1).
-- Local only: other players' lanes come from their replicated rank attributes.
local MeterAudio=require(RS:WaitForChild('GameplayAudio'))
local METER_FLOOR,METER_STRIPE,METER_LOW,METER_HIGH=1.3,1.15,1.95,10.0
local METER_DEPTH=.1 -- tube axis z in FeatureBase space; LobbyShowcaseServer measures it (model attribute TubeZ)
local LANE_RADIUS,LANE_RISE,METER_SOUND_RANGE=1.5,1.4,40
local IDLE=Color3.fromRGB(150,150,160)
local meter={model=nil,base=nil,lanes={},guis={},ui=nil,lamp=nil,lampLight=nil,acc=0}
local meterFolder=Instance.new('Folder');meterFolder.Name='SpookOMeterLocal';meterFolder.Parent=workspace
local meterFriends={}
local function meterFriend(uid)
 if meterFriends[uid]==nil then
  meterFriends[uid]=false
  task.spawn(function()local ok,f=pcall(function()return player:IsFriendsWith(uid)end);meterFriends[uid]=ok and f==true end)
 end
 return meterFriends[uid]
end
local function meterHeight(rr)
 rr=math.max(0,tonumber(rr)or 0)
 local r=RankCatalog.Get(rr);local t=RankCatalog.Tiers[r.tier];local nt=RankCatalog.Tiers[r.tier+1]
 local frac=nt and (rr-t.min)/(nt.min-t.min) or math.min(1,(rr-t.min)/math.max(1,t.min))
 return math.clamp(METER_FLOOR+(r.tier-1+math.clamp(frac,0,.98))*METER_STRIPE,METER_LOW,METER_HIGH),r
end
local function meterClear()
 for _,l in meter.lanes do l.puck:Destroy();l.ring:Destroy()end;table.clear(meter.lanes)
 for _,g in meter.guis do g:Destroy()end;table.clear(meter.guis)
 if meter.lampLight then meter.lampLight:Destroy()end
 meter.model,meter.base,meter.ui,meter.lamp,meter.lampLight=nil,nil,nil,nil,nil
end
local function meterGui(face,name,canvas)
 local g=Instance.new('SurfaceGui');g.Name=name;g.Adornee=face;g.Face=Enum.NormalId.Front;g.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
 g.CanvasSize=canvas;g.LightInfluence=0;g.MaxDistance=60;g.ResetOnSpawn=false;g.Parent=player:WaitForChild('PlayerGui')
 table.insert(meter.guis,g);return g
end
local function meterSetup(m)
 meterClear()
 local baseP=m:FindFirstChild('FeatureBase');local template=m:FindFirstChild('Puck',true)
 if not baseP or not template or not template:IsA('BasePart')or not m:FindFirstChild('LanePad1')then return end
 meter.model,meter.base=m,baseP.CFrame;METER_DEPTH=tonumber(m:GetAttribute('TubeZ'))or .1
 local rot=meter.base:ToObjectSpace(template.CFrame).Rotation
 for i=1,4 do
  local pad=m:FindFirstChild('LanePad'..i)
  if pad then
   local x=pad:GetAttribute('LaneX')or 0
   local puck=template:Clone();puck.Name='Puck'..i;puck.Anchored=true;puck.CanCollide=false;puck.CanQuery=false;puck.CanTouch=false
   puck.Transparency=.55;puck.Color=IDLE;puck.CFrame=meter.base*CFrame.new(x,METER_LOW,METER_DEPTH)*rot;puck.Parent=meterFolder
   local glow=Instance.new('PointLight');glow.Range=6;glow.Brightness=0;glow.Shadows=false;glow.Parent=puck
   local ring=Instance.new('Part');ring.Name='PeakRing'..i;ring.Shape=Enum.PartType.Cylinder;ring.Size=Vector3.new(.08,1.06,1.06)
   ring.Material=Enum.Material.Neon;ring.Anchored=true;ring.CanCollide=false;ring.CanQuery=false;ring.CanTouch=false;ring.CastShadow=false
   ring.Transparency=1;ring.Parent=meterFolder
   meter.lanes[i]={pad=pad,x=x,rot=rot,puck=puck,glow=glow,ring=ring,occupant=nil,rr=nil,h=METER_LOW,from=METER_LOW,target=METER_LOW,t0=0,stripe=0,rang=true}
  end
 end
 local ui={}
 local titleFace,laneFace=m:FindFirstChild('TitleFace'),m:FindFirstChild('LaneFace')
 if titleFace then
  local g=meterGui(titleFace,'SpookOMeterTitle',Vector2.new(520,90))
  ui.title=uiText(g,'Title',0,0,1,.52,34,GOLD,Enum.TextXAlignment.Center);ui.title.Text='SPOOK-O-METER';ui.title.FontFace=Font.new('rbxasset://fonts/families/PressStart2P.json')
  ui.line=uiText(g,'Line',0,.52,1,.48,22,CREAM,Enum.TextXAlignment.Center)
 end
 if laneFace then
  local g=meterGui(laneFace,'SpookOMeterLanes',Vector2.new(840,70))
  ui.names,ui.ranks={},{}
  for i=1,4 do
   ui.names[i]=uiText(g,'Name'..i,(i-1)*.25,0,.25,.5,22,CREAM,Enum.TextXAlignment.Center)
   ui.ranks[i]=uiText(g,'Rank'..i,(i-1)*.25,.5,.25,.5,17,MUTED,Enum.TextXAlignment.Center)
  end
 end
 meter.ui=ui
 local lamp=m:FindFirstChild('Lamp',true)
 if lamp and lamp:IsA('BasePart')then
  meter.lamp=lamp
  local l=Instance.new('PointLight');l.Name='SpookLampLocal';l.Range=9;l.Brightness=0;l.Color=Color3.fromRGB(255,214,140);l.Shadows=false;l.Parent=lamp
  meter.lampLight=l
 end
end
-- Each player belongs to the nearest pad in range; each pad to the nearest such player.
local function meterOccupancy()
 local pick={}
 for _,q in Players:GetPlayers()do
  local c=q.Character;local root=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
  if root and h and h.Health>0 then
   local bestI,bd=nil,LANE_RADIUS
   for i,l in meter.lanes do
    local d=root.Position-l.pad.Position;local flat=Vector3.new(d.X,0,d.Z).Magnitude
    if flat<bd and math.abs(d.Y)<6 then bestI,bd=i,flat end
   end
   if bestI and(not pick[bestI]or bd<pick[bestI].d)then pick[bestI]={q=q,d=bd}end
  end
 end
 return pick
end
local function laneAim(l,q,launch)
 l.occupant=q;l.rr=q and q:GetAttribute('RR')or nil
 local h,r=meterHeight(l.rr or 0)
 l.from=launch and METER_LOW or l.h;l.target=q and h or METER_LOW;l.t0=os.clock();l.rang=q==nil
 l.stripe=math.floor((l.from-METER_FLOOR)/METER_STRIPE)
 if q then
  l.puck.Color=r.color;l.puck.Transparency=0;l.glow.Color=r.color;l.glow.Brightness=.7
  local peak=tonumber(q:GetAttribute('RRPeak'))or 0
  local ph,pr=meterHeight(peak)
  if peak>(l.rr or 0)and ph>h+.15 then
   l.ring.Color=pr.color;l.ring.Transparency=.3;l.ring.CFrame=meter.base*CFrame.new(l.x,ph,METER_DEPTH)*CFrame.Angles(0,0,math.pi/2)
  else l.ring.Transparency=1 end
 else l.puck.Color=IDLE;l.puck.Transparency=.55;l.glow.Brightness=0;l.ring.Transparency=1 end
end
local function meterDraw()
 local ui=meter.ui;if not ui then return end
 local today=math.floor(workspace:GetServerTimeNow()/86400)
 local day=tonumber(player:GetAttribute('RRDay'))or 0
 local ready=day~=today
 local streak=day==today-1 and (tonumber(player:GetAttribute('RRStreak'))or 0)+1 or 1
 local mult=streak>=(player:GetAttribute('RRStreakDays')or 3)and player:GetAttribute('RRStreakMult')or player:GetAttribute('RRDailyMult')
 local used,lo,hi,mine=0,math.huge,0,false
 for i,l in meter.lanes do
  local q=l.occupant
  if q then
   used+=1;local tier=RankCatalog.Get(q:GetAttribute('RR')or 0).tier;lo=math.min(lo,tier);hi=math.max(hi,tier);if q==player then mine=true end
  end
  if ui.names then
   ui.names[i].Text=q and q.DisplayName or 'STEP ON A PAD';ui.names[i].TextColor3=q and CREAM or MUTED
   local rank=q and RankCatalog.Get(q:GetAttribute('RR')or 0)
   local text=rank and rank.name or ''
   if q==player then local rr=q:GetAttribute('RR')or 0;local _,nextAt=RankCatalog.Progress(rr);text=nextAt and(text..'  -  '..math.max(0,nextAt-rr)..' RR to next rank')or(text..'  -  top rank!')end
   ui.ranks[i].Text=text;ui.ranks[i].TextColor3=rank and rank.color or MUTED
  end
 end
 if ui.line then
  local bonus={}
  if used>=2 and hi-lo>=2 then table.insert(bonus,'carry +10% RR')end
  if mine then for _,l in meter.lanes do if l.occupant and l.occupant~=player and meterFriend(l.occupant.UserId)then table.insert(bonus,'friends +10% RR');break end end end
  if used>=2 and #bonus>0 then ui.line.Text='TOGETHER: '..table.concat(bonus,', ');ui.line.TextColor3=ORANGE
  elseif ready then ui.line.Text='FIRST CLEAR TODAY: x'..tostring(mult or 1.5)..' RR'..(streak>=(player:GetAttribute('RRStreakDays')or 3)and'  ('..streak..'-day streak)'or'');ui.line.TextColor3=GOLD
  else ui.line.Text='Daily RR bonus used. Next at '..os.date('%H:%M',(today+1)*86400);ui.line.TextColor3=MUTED end
 end
 if meter.lamp then meter.lamp.Color=ready and Color3.new(1,1,1)or Color3.fromRGB(60,56,52)end
 if meter.lampLight then meter.lampLight.Brightness=ready and 1 or 0 end
end
Run.Heartbeat:Connect(function(dt)
 local world=workspace:FindFirstChild('LobbyWorld');local show=world and world:FindFirstChild('Showcase')
 local m=show and show:FindFirstChild('SpookOMeter')
 if m~=meter.model or (m and #meter.lanes==0)then if m then meterSetup(m)else meterClear()end end
 local on=meter.model~=nil and menuActive()
 for _,g in meter.guis do g.Enabled=on end
 if not on then return end
 meter.acc+=dt
 if meter.acc>=.1 then -- occupancy and labels at 10 Hz; the pucks move every frame
  meter.acc=0
  local pick=meterOccupancy()
  for i,l in meter.lanes do
   local q=pick[i]and pick[i].q or nil
   if q~=l.occupant then laneAim(l,q,q~=nil)
   elseif q and q:GetAttribute('RR')~=l.rr then laneAim(l,q,false)end -- RR changed while standing (rank-up arrives)
  end
  meterDraw()
 end
 local now=os.clock();local root=alive()
 for i,l in meter.lanes do
  local a=math.clamp((now-l.t0)/LANE_RISE,0,1);local e=1-(1-a)^3
  local h=l.from+(l.target-l.from)*e;l.h=h
  local bob=l.occupant and a>=1 and math.sin(now*2.2+i)*.06 or 0
  l.puck.CFrame=meter.base*CFrame.new(l.x,h+bob,METER_DEPTH)*l.rot
  local near=root~=nil and (root.Position-l.pad.Position).Magnitude<=METER_SOUND_RANGE
  local stripe=math.floor((h-METER_FLOOR)/METER_STRIPE)
  if l.occupant and l.target>l.from and stripe>l.stripe then l.stripe=stripe;if near then MeterAudio.Play('UiClick',l.puck.Position)end end
  if a>=1 and not l.rang then l.rang=true;if near then MeterAudio.Play('DinnerBell',l.puck.Position)end
   if l.occupant==player then -- my puck rang the bell: a grin and my rank pops up (local only)
    local r=RankCatalog.Get(player:GetAttribute('RR')or 0);local t=workspace:GetServerTimeNow()
    player:SetAttribute('FaceBeat','grin');player:SetAttribute('FaceBeatUntil',t+2.5);player:SetAttribute('ReactPop',string.upper(r.name)..'!');player:SetAttribute('ReactPopShake',0);player:SetAttribute('ReactPopAt',t)
   end
  end
 end
end)
-- ===== Crew Trophy (2026-10-26) =====
-- The plate engraves this viewer's crew record (ProgressService.CrewRecord through the lobby 'crewRecord' request):
-- the party's best level cleared together, or their 3 best crews when solo. The ring glows for a record set today.
local trophy={seq=8000000,waiting={},data=nil,next=0,model=nil,gui=nil,ui=nil,glow=nil}
local TROPHY_RANGE=60
local function crewRequest()
 trophy.seq+=1;trophy.waiting[trophy.seq]=true;trophy.next=os.clock()+20
 lobbyEvent:FireServer(trophy.seq,'crewRecord',{})
end
local function crewDraw()
 local ui,d=trophy.ui,trophy.data;if not ui then return end
 local lines={'','','',''};local today=false
 if not d or d.mode=='none'then
  ui.head.Text='CREW TROPHY';ui.big.Text='';lines[1]='Clear a level with a friend';lines[2]='to engrave your names here.'
 elseif d.mode=='party'then
  if (d.level or 0)<1 then ui.head.Text='NEW CREW';ui.big.Text='';lines[1]='No level cleared together yet.';lines[2]='Clear one to engrave your names!'
  else
   today=d.today==true
   ui.head.Text=today and 'NEW RECORD TODAY!' or 'OUR CREW RECORD';ui.big.Text='LEVEL '..d.level
   lines[1]=(d.names and d.names[1] or '?')..' & '..(d.names and d.names[2] or '?');lines[2]='Clear Level '..(d.level+1)..' together to beat it'
  end
 else
  ui.head.Text='MY BEST CREWS';ui.big.Text=''
  for i,r in d.rows or {}do lines[i]='Level '..r.level..'  with '..r.name..(r.today and '  (today!)' or '');if r.today then today=true end end
  lines[4]='Party up and beat them'
 end
 for i=1,4 do ui.lines[i].Text=lines[i]end
 ui.head.TextColor3=today and ORANGE or GOLD
 if trophy.glow then trophy.glow.LocalTransparencyModifier=0;trophy.glow.Transparency=today and 0 or .8 end
end
local function crewSetup(m)
 if trophy.gui then trophy.gui:Destroy()end;trophy.gui,trophy.ui,trophy.glow=nil,nil,nil;trophy.model=m
 local face=m and m:FindFirstChild('EngraveFace');if not face then return end
 local g=Instance.new('SurfaceGui');g.Name='CrewTrophyPlate';g.Adornee=face;g.Face=Enum.NormalId.Front;g.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
 g.CanvasSize=Vector2.new(520,340);g.LightInfluence=0;g.MaxDistance=45;g.ResetOnSpawn=false;g.Parent=player:WaitForChild('PlayerGui')
 local ink=Color3.fromRGB(60,40,16)
 local ui={lines={}}
 ui.head=uiText(g,'Head',.04,.03,.92,.16,30,GOLD,Enum.TextXAlignment.Center)
 ui.big=uiText(g,'Big',.04,.2,.92,.26,64,CREAM,Enum.TextXAlignment.Center)
 for i=1,4 do ui.lines[i]=uiText(g,'Line'..i,.04,.47+(i-1)*.13,.92,.12,24,i==4 and MUTED or CREAM,Enum.TextXAlignment.Center)end
 for _,l in g:GetDescendants()do if l:IsA('TextLabel')then l.TextStrokeColor3=ink;l.TextStrokeTransparency=.2 end end
 trophy.gui,trophy.ui=g,ui
 local glow=m:FindFirstChild('Glow',true);if glow and glow:IsA('BasePart')then trophy.glow=glow end
 crewDraw()
end
lobbyEvent.OnClientEvent:Connect(function(action,data)
 if action~='response'or type(data)~='table'or not trophy.waiting[data.id]then return end
 trophy.waiting[data.id]=nil
 if data.ok and type(data.data)=='table'then trophy.data=data.data else trophy.next=math.min(trophy.next,os.clock()+3)end -- busy or loading: retry soon
 crewDraw()
end)
player:GetAttributeChangedSignal('LobbyPartyId'):Connect(function()trophy.next=os.clock()+.6 end) -- joined/left: re-engrave shortly
Run.Heartbeat:Connect(function()
 local world=workspace:FindFirstChild('LobbyWorld');local show=world and world:FindFirstChild('Showcase')
 local m=show and show:FindFirstChild('CrewTrophy')
 if m~=trophy.model then crewSetup(m)end
 local on=m~=nil and menuActive()
 if trophy.gui then trophy.gui.Enabled=on end
 if not on then return end
 local root=alive()
 if root and os.clock()>=trophy.next and (root.Position-m:GetPivot().Position).Magnitude<=TROPHY_RANGE then crewRequest()end
end)
player.CharacterAppearanceLoaded:Connect(function()avatarAt=0 end)
player:GetAttributeChangedSignal('MissionActive'):Connect(function()cameraMode(menuActive());refreshWorld()end)
state:GetAttributeChangedSignal('Mode'):Connect(function()cameraMode(menuActive());refreshWorld()end)
cameraMode(menuActive());refreshWorld()
