-- Local presentation/input for the server-owned 3D lobby. MainMenuClient owns panels.
-- Circles: a translucent zone box around each pad. Walking into a Free zone hosts, into an Open zone joins (no button).
-- While the player belongs to a circle (LobbyCircle attr) they are kept inside its box until they cancel or leave.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local state=RS:WaitForChild('LobbyState')
local bridge
local MIN_ZOOM,MAX_ZOOM=7,26
local CIRCLE_COUNT,PROMPT_DISTANCE,REFRESH_SECONDS=20,12,.2
local ZONE_RADIUS,ZONE_HEIGHT,LOCK_MARGIN=8,10.5,.8    -- LobbyZone is a cylinder: radius 8, 10 studs tall
local ENTRY_RADIUS_SLACK=1                            -- anywhere inside the cylinder (radius 8.5); the server allows Radius+5 for lag
local ENTRY_TRIES=4                                   -- retries per visit (a reply can be a lag rejection)
local LABEL_SHOW_DISTANCE,LABEL_RISE=36,3.5 -- circle sign: centre of the circle, inside the cylinder
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
local function billboard(anchor,name,icon,rise)
 local gui=Instance.new('BillboardGui');gui.Name=name;gui.Adornee=anchor
 gui.Size=UDim2.fromOffset(LABEL_WIDTH,icon and LABEL_HEIGHT+50 or LABEL_HEIGHT);gui.StudsOffsetWorldSpace=Vector3.new(0,rise,0)
 gui.AlwaysOnTop=true;gui.MaxDistance=math.huge;-- shown/hidden by character distance in refreshWorld; MaxDistance would measure from the zoomed-out camera
 gui.LightInfluence=0;gui.Enabled=false;gui.Parent=anchor
 local top=0
 if icon then
  local image=Instance.new('ImageLabel');image.Name='Icon';image.BackgroundTransparency=1
  image.AnchorPoint=Vector2.new(.5,0);image.Position=UDim2.fromScale(.5,0);image.Size=UDim2.fromOffset(48,48);image.Image=icon;image.Parent=gui;top=50
 end
 local title=Instance.new('TextLabel');title.Name='Title';title.BackgroundTransparency=1
 title.AnchorPoint=Vector2.new(.5,0);title.Position=UDim2.new(.5,0,0,top);title.Size=UDim2.new(1,0,0,36);title.Font=Enum.Font.FredokaOne
 title.TextSize=26;title.TextColor3=Color3.fromRGB(244,236,210);title.TextStrokeColor3=Color3.fromRGB(14,8,24);title.TextStrokeTransparency=0
 title.TextXAlignment=Enum.TextXAlignment.Center;title.TextWrapped=true;title.Parent=gui
 local detail=title:Clone();detail.Name='Details';detail.Position=UDim2.new(.5,0,0,top+38);detail.Size=UDim2.new(1,0,0,40);detail.TextSize=16;detail.TextColor3=Color3.fromRGB(244,236,210);detail.Parent=gui
 return gui,title,detail
end
-- Circle sign: a real flat sign at the exact centre of the circle (client-only part under the camera) that turns to
-- face the camera every frame, so it always reads as sitting in the middle of the ring.
local signs={} -- [part]=pad
local function circleSign(pad)
 local part=Instance.new('Part');part.Name='LobbyCircleSign';part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
 part.CastShadow=false;part.Transparency=1;part.Size=Vector3.new(9,2.6,.05);part.CFrame=CFrame.new(pad.Position+Vector3.new(0,LABEL_RISE,0))
 local gui=Instance.new('SurfaceGui');gui.Name='LobbyCircleLabel';gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
 gui.PixelsPerStud=40;gui.LightInfluence=0;gui.Enabled=false;gui.Parent=part
 local title=Instance.new('TextLabel');title.Name='Title';title.BackgroundTransparency=1;title.Size=UDim2.fromScale(1,.55)
 title.Font=Enum.Font.FredokaOne;title.TextSize=46;title.TextColor3=Color3.fromRGB(244,236,210);title.TextStrokeColor3=Color3.fromRGB(14,8,24);title.TextStrokeTransparency=0
 title.TextXAlignment=Enum.TextXAlignment.Center;title.Parent=gui
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
   entry.title.Text=status=='Free'and('HOST A RUN')or(string.upper(owner).."'S RUN")
   entry.title.TextColor3=color
   entry.detail.Text=status=='Free'and'Walk in to host'
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
   player.CameraMinZoomDistance=savedCamera.min;player.CameraMaxZoomDistance=savedCamera.max;player.CameraMode=savedCamera.mode
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
  player.CameraMode=Enum.CameraMode.Classic;player.CameraMaxZoomDistance=MAX_ZOOM;player.CameraMinZoomDistance=MIN_ZOOM
  -- Free cursor, but leave the camera module alone while the right button drags the view (it locks the cursor then).
  if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)and UIS.MouseBehavior==Enum.MouseBehavior.LockCenter then UIS.MouseBehavior=Enum.MouseBehavior.Default end
  UIS.MouseIconEnabled=true
  local camera=workspace.CurrentCamera;local _,hum=alive()
  if camera and hum then if camera.CameraType~=Enum.CameraType.Custom then camera.CameraType=Enum.CameraType.Custom end;if camera.CameraSubject~=hum then camera.CameraSubject=hum end end
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
 boardRowsUi.meValue.Text=me and(type(me.value)=='number'and me.value>0 and fmt(cat,me.value)or'not ranked yet')or''
end
local function stepBoard(dir)
 boardCat=(boardCat-1+dir)%#CATS+1;drawBoard()
 local d=boardData[CATS[boardCat].id]
 if not d or os.clock()-(d.time or 0)>60 then requestBoard()end
end
local function buildBoard(face)
 if boardGui then boardGui:Destroy()end
 for _,g in face:GetChildren()do if g:IsA('SurfaceGui')then g.Enabled=false end end -- static placeholder from the installer
 local gui=Instance.new('SurfaceGui');gui.Name='LobbyBoardUI';gui.Adornee=face;gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
 gui.PixelsPerStud=40;gui.LightInfluence=0;gui.ResetOnSpawn=false;gui.Parent=player:WaitForChild('PlayerGui')
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
local function boardTick()
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
player.CharacterAppearanceLoaded:Connect(function()avatarAt=0 end)
player:GetAttributeChangedSignal('MissionActive'):Connect(function()cameraMode(menuActive());refreshWorld()end)
state:GetAttributeChangedSignal('Mode'):Connect(function()cameraMode(menuActive());refreshWorld()end)
cameraMode(menuActive());refreshWorld()
