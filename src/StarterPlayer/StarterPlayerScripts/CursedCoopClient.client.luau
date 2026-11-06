-- Client visuals only; ItemBatch4 owns leases, attachment identity and removal.
-- No screen UI: vision is blocked by the real meshes. Everyone else sees the server-welded
-- meshes on the character. The wearer plays in LockFirstPerson with the camera at the Head bar
-- (below the eye stalks), so a local copy of the same mesh is posed in front of their camera.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local player=Players.LocalPlayer
-- Tuned by screenshot; keep values here.
local HAND_RISE=3 -- seconds for the hands to creep over the eyes
local HAND_CYCLE,HAND_CLOSED=4.7,3.9 -- fingers part for the last .8 s of each cycle
local HAND_PEEK_ANGLE=.7 -- finger spread (rad) before each finger's SpreadWeight
local HAND_PEEK_PART=.45 -- wearer's view: hands also slide this far apart while peeking
local HAND_RISE_UP,HAND_RISE_BACK=1.6,2.4 -- start offset above / behind the head (studs)
local HAND_VIEW_SQUEEZE=1.0 -- wearer's view only: each hand slides this far toward the nose
-- Point in each model's Root space that sits on the wearer's camera (Root axes = body axes, -Z front).
local VIEW_ANCHOR={
 GuessWhoHands=Vector3.new(0,-.258,-.445), -- eye midpoint
 CursedHair=Vector3.new(0,0,0), -- eye midpoint
 FacePlunger=Vector3.new(0,0,1.26), -- just behind the cup rim
}
-- Extra camera-space nudge per item (+Y up, -Z forward).
local VIEW_NUDGE={
 GuessWhoHands=Vector3.new(0,0,0),
 CursedHair=Vector3.new(0,.06,.04),
 FacePlunger=Vector3.new(0,-.36,-.6), -- cup rim ~.95 studs out and low: blocks the centre/lower view, edges stay visible
}
local apparition,apparitionSource,stingAt
local whispers={}
local views={} -- [source model]=view
local function stopWhisper()
 for m,sound in pairs(whispers)do pcall(function()sound:Stop();sound:Destroy()end);whispers[m]=nil end
end
local function destroyApparition()
 if apparition then apparition:Destroy()end;apparition=nil;apparitionSource=nil
end
local function dropView(src)
 local v=views[src];if not v then return end
 views[src]=nil;v.clone:Destroy()
 if src.Parent then for _,x in src:GetDescendants()do if x:IsA('BasePart')then x.LocalTransparencyModifier=0 end end end
end
local function clearViews()for src in pairs(views)do dropView(src)end end
local function makeView(src,id)
 local root=src.PrimaryPart;if not root then return end
 local arch=src.Archivable;src.Archivable=true
 local ok,clone=pcall(function()return src:Clone()end);src.Archivable=arch
 if not ok or not clone or not clone.PrimaryPart then return end
 local v={clone=clone,id=id,parts={},fingers={},src=src}
 local cr=clone.PrimaryPart
 local junk={}
 for _,x in clone:GetDescendants()do
  if x:IsA('Motor6D')and x.Name=='Knuckle'then
   local c0=x:GetAttribute('BaseC0');if typeof(c0)~='CFrame'then c0=x.C0 end
   table.insert(v.fingers,{finger=x.Part1,palm=x.Part0,c0=c0,c1=x.C1,w=x:GetAttribute('SpreadWeight')or 1})
  end
  if x:IsA('JointInstance')or x:IsA('WeldConstraint')or x:IsA('Constraint')or x:IsA('LuaSourceContainer')or x:IsA('Sound')or x:IsA('Attachment')then table.insert(junk,x)end
 end
 local isFinger={};for _,f in ipairs(v.fingers)do isFinger[f.finger]=true end
 local srcByName={};for _,x in src:GetDescendants()do if x:IsA('BasePart')then srcByName[x.Name]=x end end
 v.srcRoot=root
 for _,x in clone:GetDescendants()do if x:IsA('BasePart')then
  local n=x.Name
  local side=(n:sub(1,2)=='L_'or n:sub(1,4)=='Left')and 1 or((n:sub(1,2)=='R_'or n:sub(1,5)=='Right')and -1 or 0)
  if not isFinger[x]then table.insert(v.parts,{part=x,rel=cr.CFrame:ToObjectSpace(x.CFrame),side=side,src=srcByName[x.Name]})end
  x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.LocalTransparencyModifier=0
  if x.Name=='Root'or x.Name=='ItemGroundCollider'then x.Transparency=1 end
 end end
 for _,x in ipairs(junk)do x:Destroy()end
 clone.Name='CursedView_'..id;clone.Parent=workspace.CurrentCamera
 views[src]=v
 return v
end
local function poseView(v,cam,now)
 local cf=cam.CFrame*CFrame.new(VIEW_NUDGE[v.id])
 local angle=0
 if v.id=='GuessWhoHands'then
  local age=now-(player:GetAttribute('GuessWhoStart')or now)
  local away=1-math.clamp(age/HAND_RISE,0,1);away*=away
  cf*=CFrame.new(0,HAND_RISE_UP*away,HAND_RISE_BACK*away) -- camera +Z is behind the wearer
  local peek=age>=HAND_RISE and (age-HAND_RISE)%HAND_CYCLE>=HAND_CLOSED
  v.angle=(v.angle or 0)+((peek and HAND_PEEK_ANGLE or 0)-(v.angle or 0))*.18;angle=v.angle
 end
 local rootCF=cf*CFrame.new(-VIEW_ANCHOR[v.id])
 local squeeze=v.id=='GuessWhoHands'and HAND_VIEW_SQUEEZE-HAND_PEEK_PART*(angle/HAND_PEEK_ANGLE)or 0
 local placed={}
 for _,e in ipairs(v.parts)do
  -- Items copy the live (physics) pose of the real model; the hands use their authored rest.
  local rel=e.rel;if v.id~='GuessWhoHands'and e.src and e.src.Parent then rel=v.srcRoot.CFrame:ToObjectSpace(e.src.CFrame)end
  local p=rootCF*CFrame.new(e.side*squeeze,0,0)*rel;e.part.CFrame=p;placed[e.part]=p
 end
 for _,f in ipairs(v.fingers)do
  local palm=placed[f.palm];if palm then f.finger.CFrame=palm*f.c0*CFrame.Angles(angle*f.w,0,0)*f.c1:Inverse()end
 end
 for _,x in v.src:GetDescendants()do if x:IsA('BasePart')then x.LocalTransparencyModifier=1 end end
end
-- The hand mirror only reflects what is straight behind the holder, so the monster stands on that line.
-- The doorway the server chose is kept when it is already close to the line.
local REFLECT_KEEP_DOOR_DOT=math.cos(math.rad(12))
local REFLECT_MIN,REFLECT_MAX=6,14
local function reflectionSpot(c,cam,cf)
 local r=c and c:FindFirstChild('HumanoidRootPart');local folder=workspace:FindFirstChild('HeldItemVisuals')
 if not r or not cam or not folder then return cf end
 local glass
 for _,copy in folder:GetChildren()do local s=copy:FindFirstChild('MirrorSurface');if s and copy:GetAttribute('ItemId')=='FearMirror'then glass=s end end
 if not glass then return cf end
 local back=cam.CFrame.Position-glass.Position;back=Vector3.new(back.X,0,back.Z)
 if back.Magnitude<.01 then return cf end;back=back.Unit
 local toDoor=cf.Position-r.Position;toDoor=Vector3.new(toDoor.X,0,toDoor.Z)
 if toDoor.Magnitude>.01 and toDoor.Unit:Dot(back)>=REFLECT_KEEP_DOOR_DOT then return cf end
 local dist=math.clamp(toDoor.Magnitude,REFLECT_MIN,REFLECT_MAX)
 local map=workspace:FindFirstChild('Mansion');local collision=map and map:FindFirstChild('Collision')
 if collision then
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={collision}
  -- No room before a wall behind the player: keep the server's (wall-checked) spot instead.
  local hit=workspace:Raycast(r.Position,back*dist,params);if hit then dist=hit.Distance-1.5;if dist<2 then return cf end end
 end
 local pos=Vector3.new(r.Position.X,cf.Position.Y,r.Position.Z)+back*dist
 return CFrame.lookAt(pos,Vector3.new(r.Position.X,pos.Y,r.Position.Z))
end
local function monsterSource()
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,m in folder:GetChildren()do if m:IsA('Model') and m:FindFirstChildWhichIsA('BasePart',true)then return m end end end
end
local function createApparition(source)
 local arch=source.Archivable;source.Archivable=true
 local ok,clone=pcall(function()return source:Clone()end);source.Archivable=arch
 if not ok or not clone then return end
 for _,d in clone:GetDescendants()do
  if d:IsA('LuaSourceContainer')or d:IsA('Sound')or d:IsA('Humanoid')or d:IsA('Animator')or d:IsA('JointInstance')or d:IsA('Constraint')then d:Destroy()
  elseif d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true end
 end
 clone.Name='FearMirrorApparition';clone:SetAttribute('MirrorApparition',true);clone.Parent=workspace
 local _,size=clone:GetBoundingBox();local factor=math.min(1,7/math.max(size.X,size.Z,.01),9/math.max(size.Y,.01))
 if factor<1 then clone:ScaleTo(clone:GetScale()*factor)end
 apparition=clone;apparitionSource=source
end
-- Everyone's view of a wearer: hands creep up from behind, fingers part for a peek.
local function peerHands(p,now)
 local c=p.Character;local hands=c and c:FindFirstChild('CursedAttach_GuessWhoHands')
 if not hands then return end
 local age=now-(p:GetAttribute('GuessWhoStart')or now)
 local active=now<(p:GetAttribute('GuessWhoUntil')or 0)
 local peek=active and age>=HAND_RISE and (age-HAND_RISE)%HAND_CYCLE>=HAND_CLOSED
 local target=peek and HAND_PEEK_ANGLE or 0
 local root=hands.PrimaryPart;local weld=root and root:FindFirstChild('CursedVisualWeld')
 local rest=root and root:GetAttribute('CursedVisualRestC0')
 -- Head +Z is the face front, so -Z is behind. The offset is in Head space: left of the rest C0.
 local away=1-math.clamp(age/HAND_RISE,0,1);away*=away
 if weld and typeof(rest)=='CFrame'then weld.C0=CFrame.new(0,HAND_RISE_UP*away,-HAND_RISE_BACK*away)*rest end
 -- The character Animator resets Motor6D.Transform inside the rig every frame, so pose C0 locally.
 for _,d in hands:GetDescendants()do if d:IsA('Motor6D')and d.Name=='Knuckle'then
  local base=d:GetAttribute('BaseC0');if typeof(base)~='CFrame'then base=d.C0;d:SetAttribute('BaseC0',base)end
  local angle=d:GetAttribute('SpreadNow')or 0;angle+=(target*(d:GetAttribute('SpreadWeight')or 1)-angle)*.18
  d:SetAttribute('SpreadNow',angle);d.C0=base*CFrame.Angles(angle,0,0)
 end end
end
Run:BindToRenderStep('CursedCoopVisuals',Enum.RenderPriority.Camera.Value+8,function()
 local now=workspace:GetServerTimeNow()
 for _,p in Players:GetPlayers()do peerHands(p,now)end
 local c=player.Character
 local alive=c and c:FindFirstChildOfClass('Humanoid')and c:FindFirstChildOfClass('Humanoid').Health>0
 local cam=workspace.CurrentCamera
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 -- Wearer view models: hands visual plus attached plunger / hair.
 local want={}
 if alive and cam and cam.CameraType~=Enum.CameraType.Scriptable then
  local hands=c:FindFirstChild('CursedAttach_GuessWhoHands')
  if hands and now<(player:GetAttribute('GuessWhoUntil')or 0)then want[hands]='GuessWhoHands'end
  if interactive then for _,m in interactive:GetChildren()do
   local id=m:GetAttribute('ItemId')
   if VIEW_ANCHOR[id]and id~='GuessWhoHands'and m:GetAttribute('AttachedTo')==player.UserId then want[m]=id end
  end end
 end
 for src in pairs(views)do if not want[src]or not src.Parent then dropView(src)end end
 for src,id in pairs(want)do local v=views[src]or makeView(src,id);if v then poseView(v,cam,now)end end
 local fear=alive and now<(player:GetAttribute('MirrorFearUntil')or 0)
 local cf=player:GetAttribute('MirrorMonsterCF')
 if fear and typeof(cf)=='CFrame'then
  if not apparition then local source=monsterSource();if source then createApparition(source)end end
  if apparition then
   cf=reflectionSpot(c,cam,cf)
   apparition:PivotTo(cf);local box,size=apparition:GetBoundingBox();local lift=cf.Position.Y-(box.Position.Y-size.Y*.5)
   apparition:PivotTo(apparition:GetPivot()+Vector3.new(0,lift,0));apparition:SetAttribute('FearHolder',player.UserId)
  end
  local start=player:GetAttribute('MirrorFearStart')or now
  if stingAt~=start then stingAt=start;Audio.Play('MirrorSting',c:FindFirstChild('Head'))end
  if cam then cam.CFrame*=CFrame.Angles(math.sin(now*39)*.0015,math.sin(now*31)*.002,math.sin(now*27)*.002)end
 else destroyApparition();stingAt=nil end
 local present={}
 if interactive then for _,m in interactive:GetChildren()do if m:GetAttribute('AttachedTo')and m:GetAttribute('ItemId')=='ClingyTeddy'and m.PrimaryPart then
  present[m]=true
 end end end
 for m,sound in pairs(whispers)do if not present[m]then pcall(function()sound:Stop();sound:Destroy()end);whispers[m]=nil end end
end)
player.CharacterRemoving:Connect(function()destroyApparition();stopWhisper();clearViews()end)
-- Stuck co-op items: the wearer can call for help; teammates always see who is stuck and how far away they are.
-- ItemBatch4 sets Player.CursedAttach (item id) while an item is stuck; CursedItemsServer stamps Player.HelpCallAt on a call.
local CAS=game:GetService('ContextActionService')
local UIS=game:GetService('UserInputService')
local Catalog=require(RS:WaitForChild('CursedCatalog'))
local InputHints=require(RS:WaitForChild('InputHints'))
local cursedEvent=RS:WaitForChild('CursedEvent')
local HELP_LOUD,HELP_COOLDOWN=6,4 -- seconds a call stays loud for teammates; seconds between calls (server enforces the same)
local PULL_REACH=10 -- studs: ItemBatch4 REACH, a teammate must be this close to pull it off
local STUDS_PER_METRE=1/.28
local GOLD,RED,CREAM,INK=Color3.fromRGB(255,214,60),Color3.fromRGB(255,90,80),Color3.fromRGB(244,236,210),Color3.fromRGB(14,8,24)
local function itemName(id)local e=Catalog.Items[id];return e and e.name or 'cursed item'end
local function stuckId(p)local id=p:GetAttribute('CursedAttach');return type(id)=='string'and id~=''and id or nil end
local function aliveChar(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and c or nil
end
local function label(parent,name,text,size,color)
 local l=Instance.new('TextLabel');l.Name=name;l.BackgroundTransparency=1;l.Font=Enum.Font.FredokaOne;l.Text=text;l.TextColor3=color or CREAM
 l.TextStrokeColor3=INK;l.TextStrokeTransparency=.2;l.TextScaled=true;l.Parent=parent
 local cap=Instance.new('UITextSizeConstraint');cap.MaxTextSize=size;cap.MinTextSize=9;cap.Parent=l
 return l
end
local helpGui=Instance.new('ScreenGui');helpGui.Name='CoopHelpHud';helpGui.ResetOnSpawn=false;helpGui.DisplayOrder=40;helpGui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;helpGui.Parent=player:WaitForChild('PlayerGui')
-- Wearer: a card above the carry text with one big button.
local card=Instance.new('Frame');card.Name='StuckCard';card.AnchorPoint=Vector2.new(.5,1);card.Position=UDim2.new(.5,0,1,-150);card.Size=UDim2.fromOffset(340,112)
card.BackgroundColor3=Color3.fromRGB(26,16,30);card.BackgroundTransparency=.12;card.Visible=false;card.Parent=helpGui
Instance.new('UICorner',card).CornerRadius=UDim.new(0,14)
local cardStroke=Instance.new('UIStroke');cardStroke.Color=GOLD;cardStroke.Thickness=2;cardStroke.Parent=card
local cardTitle=label(card,'Title','',20,GOLD);cardTitle.Position=UDim2.fromOffset(12,8);cardTitle.Size=UDim2.new(1,-24,0,24)
local cardBody=label(card,'Body','A teammate has to pull it off. Call them over!',15);cardBody.Position=UDim2.fromOffset(12,34);cardBody.Size=UDim2.new(1,-24,0,18)
local callButton=Instance.new('TextButton');callButton.Name='CallForHelp';callButton.AnchorPoint=Vector2.new(.5,0);callButton.Position=UDim2.new(.5,0,0,60);callButton.Size=UDim2.new(1,-24,0,44)
callButton.BackgroundColor3=GOLD;callButton.AutoButtonColor=true;callButton.BorderSizePixel=0;callButton.Font=Enum.Font.FredokaOne;callButton.TextSize=22;callButton.TextColor3=INK;callButton.Text='CALL FOR HELP';callButton.Parent=card
Instance.new('UICorner',callButton).CornerRadius=UDim.new(0,12)
-- Teammates: a banner at the top while a call is fresh.
local banner=Instance.new('Frame');banner.Name='HelpBanner';banner.AnchorPoint=Vector2.new(.5,0);banner.Position=UDim2.new(.5,0,0,96);banner.Size=UDim2.fromOffset(420,62)
banner.BackgroundColor3=Color3.fromRGB(60,12,14);banner.BackgroundTransparency=.1;banner.Visible=false;banner.Parent=helpGui
Instance.new('UICorner',banner).CornerRadius=UDim.new(0,14)
local bannerStroke=Instance.new('UIStroke');bannerStroke.Color=RED;bannerStroke.Thickness=2;bannerStroke.Parent=banner
local bannerTitle=label(banner,'Title','',22,GOLD);bannerTitle.Position=UDim2.fromOffset(12,6);bannerTitle.Size=UDim2.new(1,-24,0,26)
local bannerBody=label(banner,'Body','',15);bannerBody.Position=UDim2.fromOffset(12,34);bannerBody.Size=UDim2.new(1,-24,0,20)
local lastCall=-math.huge
local function callForHelp()
 if not stuckId(player)or not aliveChar(player)then return end
 local now=os.clock();if now-lastCall<HELP_COOLDOWN then return end
 lastCall=now;cursedEvent:FireServer('help')
 Audio.Play('UiOpen')
end
callButton.Activated:Connect(callForHelp)
local bound=false
local function bindCall(on)
 if on==bound then return end;bound=on
 if on then CAS:BindActionAtPriority('CoopCallHelp',function(_,st)
  if UIS:GetFocusedTextBox()then return Enum.ContextActionResult.Pass end
  if st==Enum.UserInputState.Begin then callForHelp()end;return Enum.ContextActionResult.Sink
 end,false,2100,Enum.KeyCode.H,Enum.KeyCode.DPadLeft)
 else CAS:UnbindAction('CoopCallHelp')end
end
-- Markers over stuck teammates: name, item, distance; through walls so they can be found.
local markers={} -- [Player]={gui,title,detail}
local heardCall={} -- [Player]=HelpCallAt already announced
local function dropMarker(p)local m=markers[p];if m then m.gui:Destroy();markers[p]=nil end end
-- A screen label that follows the stuck player's head every frame (BillboardGuis made on the client did not draw
-- reliably here); when they are off screen or behind you it sits on the screen edge in their direction.
local function marker(p,head)
 local m=markers[p]
 if m and m.head==head then return m end
 dropMarker(p)
 local g=Instance.new('Frame');g.Name='HelpMarker_'..p.Name;g.AnchorPoint=Vector2.new(.5,1);g.BackgroundTransparency=1;g.Size=UDim2.fromOffset(220,74);g.Parent=helpGui
 local icon=label(g,'Icon','!',40,GOLD);icon.Position=UDim2.new(.5,-16,0,0);icon.Size=UDim2.fromOffset(32,34)
 local title=label(g,'Title','',18,GOLD);title.Position=UDim2.fromOffset(0,32);title.Size=UDim2.new(1,0,0,22)
 local detail=label(g,'Detail','',14);detail.Position=UDim2.fromOffset(0,54);detail.Size=UDim2.new(1,0,0,18)
 m={gui=g,icon=icon,title=title,detail=detail,head=head};markers[p]=m
 return m
end
local EDGE=70 -- pixels kept from the screen edge when the stuck player is off screen
Run.RenderStepped:Connect(function()
 local cam=workspace.CurrentCamera;if not cam then return end
 local vp=cam.ViewportSize;local inset=helpGui.AbsolutePosition
 for _,m in pairs(markers) do
  local head=m.head
  if head and head.Parent then
   local sp=cam:WorldToViewportPoint(head.Position+Vector3.new(0,6,0)) -- clear of the player's own title tags (they reach ~5 studs up)
   local x,y=sp.X,sp.Y
   if sp.Z<0 then x,y=vp.X-x,vp.Y-y end -- behind the camera: mirror so the edge arrow points the right way
   local off=sp.Z<0 or x<EDGE or x>vp.X-EDGE or y<EDGE or y>vp.Y-EDGE
   if off then
    local cx,cy=vp.X/2,vp.Y/2;local dx,dy=x-cx,y-cy
    if math.abs(dx)<1e-3 and math.abs(dy)<1e-3 then dy=1 end
    local s=math.min((cx-EDGE)/math.max(math.abs(dx),1e-3),(cy-EDGE)/math.max(math.abs(dy),1e-3))
    x,y=cx+dx*s,cy+dy*s
   end
   -- while the help banner shows, keep the label (anchored at its bottom) below it
   if banner.Visible then y=math.max(y,banner.AbsolutePosition.Y+banner.AbsoluteSize.Y+8+m.gui.AbsoluteSize.Y) end
   m.gui.Position=UDim2.fromOffset(x-inset.X,y-inset.Y)
  end
 end
end)
local helpTick=0
Run.Heartbeat:Connect(function(dt)
 helpTick+=dt;if helpTick<.1 then return end;helpTick=0
 local now=workspace:GetServerTimeNow();local clock=os.clock()
 local inMission=player:GetAttribute('MissionActive')==true
 -- Wearer card.
 local mine=inMission and aliveChar(player)and stuckId(player)
 card.Visible=mine~=nil and mine~=false
 bindCall(card.Visible)
 -- Sit above the first-game tutorial tip when it shows (it covers the bottom centre on small screens).
 if card.Visible then
  local tut=player.PlayerGui:FindFirstChild('FirstGameTutorial');local tip=tut and tut.Enabled and tut:FindFirstChild('Tip')
  if tip and tip:IsA('GuiObject') and tip.Visible and tip.AbsoluteSize.Y>0 then
   local y=tip.AbsolutePosition.Y-helpGui.AbsolutePosition.Y-10
   card.Position=UDim2.new(.5,0,0,math.max(card.AbsoluteSize.Y+8,y))
  else card.Position=UDim2.new(.5,0,1,-150) end
 end
 if card.Visible then
  cardTitle.Text=string.upper(itemName(mine))..' IS STUCK ON YOU!'
  local device=InputHints.Get()
  local key=device=='pad'and'  (D-PAD LEFT)'or device=='kb'and'  (H)'or''
  local wait=HELP_COOLDOWN-(clock-lastCall)
  callButton.Text=wait>0 and'HELP CALLED!'or'CALL FOR HELP'..key
  callButton.BackgroundColor3=wait>0 and Color3.fromRGB(150,140,110)or GOLD
  cardStroke.Transparency=.5+.5*math.sin(clock*5)
 end
 -- Teammates who are stuck.
 local myRoot=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 local loudest,loudAt=nil,-math.huge
 local selfTest=Run:IsStudio()and script:GetAttribute('HelpMarkSelf')==true -- Studio-only: show your own marker for solo tests
 for _,p in ipairs(Players:GetPlayers())do
  local id=inMission and(p~=player or selfTest)and stuckId(p)
  local c=id and aliveChar(p);local head=c and c:FindFirstChild('Head')
  if not head then dropMarker(p);heardCall[p]=nil;continue end
  local m=marker(p,head)
  local callAt=p:GetAttribute('HelpCallAt')or -math.huge
  local loud=now-callAt<HELP_LOUD
  local d=myRoot and(myRoot.Position-head.Position).Magnitude
  m.title.Text=p.DisplayName..(loud and' NEEDS HELP!'or' is stuck')
  m.detail.Text=d and d<=PULL_REACH and'GRAB IT TO PULL IT OFF'or(itemName(id)..(d and('  |  '..math.floor(d/STUDS_PER_METRE+.5)..'m')or''))
  local pulse=loud and(1+.18*math.abs(math.sin(clock*6)))or 1
  m.gui.Size=UDim2.fromOffset(220*pulse,74*pulse)
  m.icon.TextColor3=loud and RED or GOLD
  if loud and callAt>loudAt then loudest,loudAt=p,callAt end
  if loud and heardCall[p]~=callAt then heardCall[p]=callAt;Audio.Play('BellhopBell')end
 end
 for p in pairs(markers)do if p.Parent~=Players then dropMarker(p);heardCall[p]=nil end end
 banner.Visible=loudest~=nil
 if loudest then
  local id=stuckId(loudest)
  bannerTitle.Text=string.upper(loudest.DisplayName)..' NEEDS HELP!'
  bannerBody.Text='The '..string.lower(itemName(id))..' is stuck on them. Walk up and grab it to pull it off.'
 end
end)
