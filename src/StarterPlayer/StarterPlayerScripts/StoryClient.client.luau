-- Story (owner 2026-10-29): the note reader in levels, the Case Board in the lobby and the Case Files screen.
-- Data: ReplicatedStorage.StoryLore. Notes are placed and saved by the server (InteractServer.WorldHappenings ->
-- ProgressService.NoteStory -> save field StoryNotes); StoryEvent 'note' opens a note the moment it is read.
-- Found notes come from the lobby 'progress' request (storyNotes) plus every note read this session.
-- Every screen is built for phones, tablets, consoles and PC: sizes follow the viewport, buttons stay 44 px or more,
-- the gamepad selects tabs and B / Escape closes.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local GuiService=game:GetService('GuiService')
local CAS=game:GetService('ContextActionService')
local PromptService=game:GetService('ProximityPromptService')
local TweenService=game:GetService('TweenService')
local Story=require(RS:WaitForChild('StoryLore'))
local InputHints=require(RS:WaitForChild('InputHints'))
local p=Players.LocalPlayer
local pg=p:WaitForChild('PlayerGui')

local INK=Color3.fromRGB(16,20,22)
local PANEL=Color3.fromRGB(24,30,30)
local LINE=Color3.fromRGB(70,92,84)
local GREEN=Color3.fromRGB(176,255,206)
local PALE=Color3.fromRGB(214,232,220)
local DIM=Color3.fromRGB(128,150,140)
local PAPER=Color3.fromRGB(232,226,204)
local GOLD=Color3.fromRGB(255,214,110)

local found={} -- [note id]=true
local listeners={}
local function changed()for _,f in listeners do task.spawn(f)end end
local function foundCount()local n=0;for _,note in Story.Notes do if found[note.id]then n+=1 end end;return n end
local function unlocked(subject)return Story.SubjectUnlocked(found,subject.id)end
local function noteLevel(note)return note.index end -- level N (and N+12, N+24...) carries note N

-- Lobby progress request (the same channel LobbyShowcaseClient uses; ids far from its own counter).
local lobbyEvent=RS:WaitForChild('LobbyEvent',30)
local sequence,pending=960000,{}
if lobbyEvent then
 lobbyEvent.OnClientEvent:Connect(function(action,data)
  if action~='response'or type(data)~='table'then return end
  local cb=pending[data.id];if not cb then return end
  pending[data.id]=nil;cb(data.ok,data.ok and data.data or nil)
 end)
end
local function syncFound()
 if not lobbyEvent then return end
 sequence+=1;local rid=sequence
 pending[rid]=function(ok,data)
  local notes=ok and type(data)=='table'and type(data.progress)=='table'and data.progress.storyNotes
  if type(notes)=='table'then for id in notes do if type(id)=='string'then found[id]=true end end;changed()end
 end
 lobbyEvent:FireServer(rid,'progress',{})
 task.delay(12,function()pending[rid]=nil end)
end

local function viewport()local cam=workspace.CurrentCamera;return cam and cam.ViewportSize or Vector2.new(1280,720)end
local function compact()local v=viewport();return v.X<900 or v.Y<560 end
local function corner(o,r)local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,r or 10);c.Parent=o;return c end
local function stroke(o,color,t)local s=Instance.new('UIStroke');s.Color=color or LINE;s.Thickness=t or 2;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=o;return s end
local function pad(o,n)local u=Instance.new('UIPadding');for _,k in{'PaddingLeft','PaddingRight','PaddingTop','PaddingBottom'}do u[k]=UDim.new(0,n)end;u.Parent=o;return u end
local function label(parent,text,size,color,props)
 local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Text=text;t.TextSize=size;t.TextColor3=color or PALE
 t.TextWrapped=true;t.TextXAlignment=Enum.TextXAlignment.Left;t.TextYAlignment=Enum.TextYAlignment.Top
 t.AutomaticSize=Enum.AutomaticSize.Y;t.Size=UDim2.new(1,0,0,0);t.LineHeight=1.35
 for k,v in props or {}do t[k]=v end
 t.Parent=parent;return t
end
local function button(parent,text,size,props)
 local b=Instance.new('TextButton');b.AutoButtonColor=true;b.BackgroundColor3=PANEL;b.Text=text;b.TextSize=size;b.TextColor3=PALE
 b.TextWrapped=true;corner(b,8);stroke(b,LINE,2)
 for k,v in props or {}do b[k]=v end
 b.Parent=parent;return b
end

-- ===== Note reader (levels and lobby) =====
local reader
local function closeReader()if reader then reader:Destroy();reader=nil;CAS:UnbindAction('StoryCloseNote')end end
local closeFiles -- set below
local function showNote(note,fresh)
 closeReader()
 local small=compact();local v=viewport()
 local gui=Instance.new('ScreenGui');gui.Name='StoryNoteReader';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=210;gui.Parent=pg;reader=gui
 local shade=Instance.new('TextButton');shade.Text='';shade.AutoButtonColor=false;shade.BackgroundColor3=Color3.new(0,0,0);shade.BackgroundTransparency=.45;shade.Size=UDim2.fromScale(1,1);shade.Parent=gui
 local w=math.min(small and v.X-32 or 620,v.X-32);local paper=Instance.new('Frame');paper.Name='Paper'
 paper.AnchorPoint=Vector2.new(.5,.5);paper.Position=UDim2.fromScale(.5,.5);paper.Size=UDim2.fromOffset(w,math.min(v.Y-40,small and 340 or 470))
 paper.BackgroundColor3=PAPER;paper.Rotation=small and 0 or -1.2;paper.Parent=gui;corner(paper,6);stroke(paper,Color3.fromRGB(150,140,112),3)
 local scroll=Instance.new('ScrollingFrame');scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.Size=UDim2.new(1,0,1,-(small and 60 or 70))
 scroll.CanvasSize=UDim2.new();scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.ScrollBarThickness=6;scroll.ScrollBarImageColor3=Color3.fromRGB(110,100,80);scroll.Parent=paper
 pad(scroll,small and 14 or 24)
 local list=Instance.new('UIListLayout');list.Padding=UDim.new(0,small and 8 or 12);list.SortOrder=Enum.SortOrder.LayoutOrder;list.Parent=scroll
 local ink=Color3.fromRGB(38,40,46)
 label(scroll,fresh and'YOU FOUND A NOTE!  '..foundCount()..' OF '..#Story.Notes or'NOTE '..note.index..' OF '..#Story.Notes,small and 10 or 12,Color3.fromRGB(70,110,86),{LayoutOrder=1})
 label(scroll,note.title,small and 16 or 22,ink,{LayoutOrder=2})
 label(scroll,note.from,small and 10 or 12,Color3.fromRGB(96,92,80),{LayoutOrder=3})
 label(scroll,note.text,small and 12 or 15,ink,{LayoutOrder=4,LineHeight=1.5})
 local s=note.subject and Story.SubjectById[note.subject]
 if s then label(scroll,'NEW MONSTER FILE: '..s.name..'. Read it on the board in the lobby.',small and 10 or 12,Color3.fromRGB(46,110,74),{LayoutOrder=5})
 else label(scroll,'You can read it again on the board in the lobby.',small and 10 or 12,Color3.fromRGB(96,92,80),{LayoutOrder=5})end
 local ok=button(paper,'CLOSE',small and 13 or 15,{Name='Close',AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-10),Size=UDim2.fromOffset(170,small and 44 or 48),BackgroundColor3=Color3.fromRGB(40,52,48)})
 ok.Activated:Connect(closeReader);shade.Activated:Connect(closeReader)
 if GuiService:IsTenFootInterface()or InputHints.Get()=='pad'then GuiService.SelectedObject=ok end
 CAS:BindActionAtPriority('StoryCloseNote',function(_,state)if state==Enum.UserInputState.Begin then closeReader()end;return Enum.ContextActionResult.Sink end,false,3100,Enum.KeyCode.ButtonB,Enum.KeyCode.Escape)
 -- The page is as tall as its text (never past the screen), and drops in with a little settle.
 task.defer(function()
  if reader~=gui then return end
  local h=math.min(v.Y-40,list.AbsoluteContentSize.Y+(small and 28 or 48)+(small and 60 or 70))
  paper.Size=UDim2.fromOffset(w,h);paper.Position=UDim2.new(.5,0,.5,-24)
  TweenService:Create(paper,TweenInfo.new(.22,Enum.EasingStyle.Back),{Position=UDim2.fromScale(.5,.5)}):Play()
 end)
end

-- Notes this player already has: hidden on their own screen (and not aimable), still there for teammates.
local function hideIfFound(m)
 if not m:IsA('Model')or m:GetAttribute('Happening')~='StoryNote'then return end
 local have=found[m:GetAttribute('NoteId')or'']==true
 for _,d in m:GetDescendants()do
  if d:IsA('BasePart')then d.LocalTransparencyModifier=have and 1 or 0;d.CanQuery=not have
  elseif d:IsA('Light')or d:IsA('SurfaceGui')then d.Enabled=not have end
 end
end
local function sweepNotes()
 local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
 if items then for _,m in items:GetChildren()do hideIfFound(m)end end
end
task.spawn(function()
 local map=workspace:WaitForChild('Mansion',math.huge)
 local items=map:WaitForChild('Interactive',math.huge)
 items.ChildAdded:Connect(function(m)task.wait(.2);hideIfFound(m)end)
 sweepNotes()
end)
table.insert(listeners,sweepNotes)

-- 'NAME FOUND A NOTE!' for the rest of the crew: a small line at the top for 4 s.
local function sharedToast(name)
 local gui=Instance.new('ScreenGui');gui.Name='StoryNoteToast';gui.ResetOnSpawn=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.DisplayOrder=150;gui.Parent=pg
 local box=Instance.new('Frame');box.AnchorPoint=Vector2.new(.5,0);box.Position=UDim2.new(.5,0,0,90);box.Size=UDim2.fromOffset(math.min(viewport().X-32,560),58)
 box.BackgroundColor3=PAPER;box.Parent=gui;corner(box,8);stroke(box,Color3.fromRGB(150,140,112),2)
 label(box,string.upper(name)..' FOUND A NOTE! IT IS IN YOUR FILES TOO.',compact()and 11 or 14,Color3.fromRGB(38,40,46),{Size=UDim2.fromScale(1,1),AutomaticSize=Enum.AutomaticSize.None,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})
 task.delay(4,function()gui:Destroy()end)
end
task.spawn(function() -- WorldHappenings makes StoryEvent when the first level starts
 local storyEvent=RS:WaitForChild('StoryEvent',math.huge)
 storyEvent.OnClientEvent:Connect(function(action,id,by)
  local note=Story.NoteById[id];if not note then return end
  if action=='noteShared'then -- a teammate read it: it is yours too, no page pops up
   local fresh=not found[id];found[id]=true;changed()
   if fresh then sharedToast(tostring(by or'A teammate'))end
   return
  end
  if action~='note'then return end
  local fresh=not found[id];found[id]=true
  showNote(note,fresh);changed()
 end)
end)

-- ===== Lobby Case Board =====
-- Built on this client (a static, per-player board): free floor on the west side of the hall, facing the spawn.
-- Each photo is its own thin card part on the cork, so the inspect scene can lift it off the wall.
-- Card layout is in board studs: x to the viewer's right, y up from the floor (viewer right = the board's local -X).
-- Owner 2026-10-29: on the west wall to the right of the Rank Rewards display (as seen from the spawn), 1.5x size and
-- mounted above the cosmetic stands so nothing blocks it from anywhere in the hall. Wall face x 1126, centre z 11.
local BOARD_AT=CFrame.lookAt(Vector3.new(1126.7,0,11),Vector3.new(1127.7,0,11))
local SCALE=1.5
local BOARD_W,BOARD_H,BOARD_Y=20*SCALE,11.5*SCALE,21.5
local HELD_CARD=Vector3.new(3.4,3.09,.05) -- the size of a card in your hands
local CARD=Vector3.new(3.4*SCALE,3.09*SCALE,.05) -- on the wall
local CARD_SPOTS={} -- centres, x right / y up (laid out for a 20 x 11.5 board centred at height 7.4, then scaled)
for i,s in {{-7.3,9.95},{-2.45,9.85},{2.45,10.0},{7.3,9.9},{-4.85,6.3},{0,6.2},{4.85,6.35}}do CARD_SPOTS[i]={s[1]*SCALE,BOARD_Y+(s[2]-7.4)*SCALE}end
-- Owner 2026-10-29: the board's button stands where the west door was (door removed), on its own display pedestal.
local PEDESTAL_AT=CFrame.lookAt(Vector3.new(1130.2,0,8),Vector3.new(1131.2,0,8))
local CARD_TILT={-3,2,-2,3,2,-3,1.5}
local board -- {model, cork, cards={[id]={part,gui,cf}}}
local function boardCF(x,y,z)return BOARD_AT*CFrame.new(-x,y,z or 0)end

-- A card's face: a SurfaceGui in PlayerGui (so taps and clicks reach it). kind 'photo' = CCTV still + caption,
-- kind 'note' = a paper page with the note's text. Returns the gui and a function to refresh the caption.
local function cardFace(part,kind,thing,clickable)
 local gui=Instance.new('SurfaceGui');gui.Name='StoryCard_'..part.Name;gui.Adornee=part;gui.Face=Enum.NormalId.Front
 gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(520,472);gui.LightInfluence=0;gui.MaxDistance=140;gui.ResetOnSpawn=false;gui.Parent=pg
 local root=Instance.new(clickable and'TextButton'or'Frame');root.Name='Face';root.BackgroundColor3=PAPER;root.Size=UDim2.fromScale(1,1);root.Parent=gui
 if clickable then root.Text='';root.AutoButtonColor=false end
 local caption
 if kind=='photo'then
  local img=Instance.new('ImageLabel');img.Name='Photo';img.BackgroundColor3=Color3.new(0,0,0);img.Position=UDim2.fromOffset(18,18);img.Size=UDim2.fromOffset(484,272)
  img.Image=thing.image;img.ScaleType=Enum.ScaleType.Crop;img.Parent=root
  if thing.image==''then label(img,'NO SIGNAL',40,DIM,{Size=UDim2.fromScale(1,1),AutomaticSize=Enum.AutomaticSize.None,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})end
  caption=label(root,'',34,Color3.fromRGB(30,32,38),{Position=UDim2.fromOffset(22,306),Size=UDim2.new(1,-44,0,150),AutomaticSize=Enum.AutomaticSize.None})
 else
  label(root,thing.title,34,Color3.fromRGB(30,32,38),{Position=UDim2.fromOffset(24,22),Size=UDim2.new(1,-48,0,0)})
  label(root,thing.from,16,Color3.fromRGB(96,92,80),{Position=UDim2.fromOffset(24,96),Size=UDim2.new(1,-48,0,0)})
  label(root,thing.text,17,Color3.fromRGB(38,40,46),{Position=UDim2.fromOffset(24,140),Size=UDim2.new(1,-48,1,-160),AutomaticSize=Enum.AutomaticSize.None,LineHeight=1.45})
 end
 local pin=Instance.new('Frame');pin.AnchorPoint=Vector2.new(.5,.5);pin.Position=UDim2.new(.5,0,0,10);pin.Size=UDim2.fromOffset(30,30);pin.BackgroundColor3=Color3.fromRGB(230,200,90);pin.Parent=root;corner(pin,15)
 return gui,root,caption
end

-- ===== Inspect scene: first-person camera at the board, the card lifted into view =====
local scene -- {saved camera, held card, token}
local Inspect=require(RS:WaitForChild('InspectCamera')) -- the glide in / first person / glide back camera
local function ease(t)return t<.5 and 4*t*t*t or 1-(-2*t+2)^3/2 end
local function heldPose(cam)
 -- About 60 % of the screen height: phones hold it above the file sheet, wide screens left of the text column.
 -- The menu is on the left and the text on the right (wide) or below (phones): the card sits in between.
 if compact()then return cam*CFrame.new(.55,.75,-4.6)end
 return cam*CFrame.new(-.35,-.05,-3.9)
end
-- Lifts `part` from `fromCF` into the held pose with a small arc and a flip of the wrist; it then sways while held.
local function flyCard(part,fromCF,toHeld,seconds,token)
 local t=0
 while t<1 do
  t=math.min(1,t+Run.RenderStepped:Wait()/seconds)
  if not scene or scene.token~=token or not part.Parent then return false end
  local cam=workspace.CurrentCamera.CFrame
  local hold=heldPose(cam);local holdCF=CFrame.lookAt(hold.Position,cam.Position)*CFrame.Angles(0,0,math.rad(-4))
  local a,b=fromCF,holdCF;if not toHeld then a,b=holdCF,fromCF end
  local e=ease(t)
  local cf=a:Lerp(b,e)+Vector3.new(0,math.sin(e*math.pi)*.35,0)
  part.CFrame=cf*CFrame.Angles(math.sin(e*math.pi)*.35,math.sin(e*math.pi)*-.25,0)
  part.Size=CARD:Lerp(HELD_CARD,toHeld and e or 1-e) -- wall size shrinks to hand size on the way
 end
 return true
end
local swayConn
local function startSway(part)
 if swayConn then swayConn:Disconnect()end
 local t0=os.clock()
 swayConn=Run.RenderStepped:Connect(function()
  if not part.Parent then swayConn:Disconnect();swayConn=nil;return end
  local cam=workspace.CurrentCamera.CFrame;local t=os.clock()-t0
  local hold=heldPose(cam)*CFrame.new(math.sin(t*1.3)*.03,math.sin(t*2.1)*.035,0)
  part.CFrame=CFrame.lookAt(hold.Position,cam.Position)*CFrame.Angles(math.sin(t*1.7)*.04,math.sin(t*1.1)*.05,math.rad(-4)+math.sin(t*.9)*.03)
 end)
end
local function stopSway()if swayConn then swayConn:Disconnect();swayConn=nil end end
-- The camera spot in front of a board card (or the board centre), a little below and looking slightly up.
local function lookAtCard(id)
 local spot=board and board.cards[id];local centre=boardCF(0,BOARD_Y).Position
 -- A card: lean in toward it, but keep part of the board behind it (corner cards would show the hall).
 local target=spot and spot.cf.Position:Lerp(centre,.45)or centre
 local look=BOARD_AT.LookVector
 local far=spot==nil -- no card: the whole board
 local eye=target+look*(far and(compact()and 22 or 18)or(compact()and 10 or 8.5))+Vector3.new(0,far and -2 or -.5,0)
 -- Wide screens hold the card left of centre, so the camera steps to the viewer's left (board +X) and the wall card
 -- sits right of the held one.
 if not compact()then eye+=BOARD_AT.RightVector*(far and 1.5 or .8)end
 return CFrame.lookAt(eye,target)
end
local function hideWallCard(id,hidden)
 local spot=board and board.cards[id];if not spot then return end
 spot.part.LocalTransparencyModifier=hidden and 1 or 0;spot.gui.Enabled=not hidden
end
-- Hold something: a subject's photo (subject) or a note page (note). The old held card goes back first.
local function holdThing(kind,thing)
 if not scene then return end
 scene.token+=1;local token=scene.token
 task.spawn(function()
  local old=scene.held
  if old then
   stopSway()
   if old.wallId then flyCard(old.part,board.cards[old.wallId].cf,false,.35,token);hideWallCard(old.wallId,false)end
   old.part:Destroy();old.gui:Destroy();scene.held=nil
   if scene.token~=token then return end
  end
  local wallId=kind=='photo'and thing.id or nil
  Inspect.MoveTo(lookAtCard(wallId),.55)
  if not scene or scene.token~=token then return end
  local part=Instance.new('Part');part.Name='HeldStoryCard';part.Size=HELD_CARD;part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false
  part.Color=PAPER;part.Material=Enum.Material.SmoothPlastic
  local from=wallId and board.cards[wallId].cf or(workspace.CurrentCamera.CFrame*CFrame.new(0,-2.4,-2.5))
  part.CFrame=from;part.Parent=workspace.CurrentCamera
  local gui,_,caption=cardFace(part,kind,thing,false)
  if caption then caption.Text=('MONSTER %d\n%s'):format(thing.index,unlocked(thing)and thing.name or'???')end
  scene.held={part=part,gui=gui,wallId=wallId}
  if wallId then hideWallCard(wallId,true)end
  if flyCard(part,from,true,.55,token)then startSway(part)end
 end)
end
local function endScene()
 local s=scene;if not s then return end
 s.token+=1;local token=s.token
 stopSway()
 task.spawn(function()
  local held=s.held
  if held then
   if held.wallId and board then flyCard(held.part,board.cards[held.wallId].cf,false,.35,token);hideWallCard(held.wallId,false)end
   held.part:Destroy();held.gui:Destroy()
  end
  if scene==s then scene=nil end
  Inspect.End(.5)
 end)
end
local function beginScene()
 if scene then return end
 scene={token=0}
 task.spawn(Inspect.Begin,lookAtCard(nil),.7,'story')
end

-- ===== Case Files screen =====
-- In the lobby next to the board it is the inspect scene: tabs on top, the file text on the right (wide) or at the
-- bottom (phones), the photo or note held in view. Anywhere else it is a plain full-screen file.
local files
local currentShow -- the open screen's tab switcher (Studio test hook)
local tabs={}
local function bindClose(on)
 if on then CAS:BindActionAtPriority('StoryCloseFiles',function(_,state)if state==Enum.UserInputState.Begin then if reader then closeReader()elseif closeFiles then closeFiles()end end;return Enum.ContextActionResult.Sink end,false,3000,Enum.KeyCode.ButtonB,Enum.KeyCode.Escape,Enum.KeyCode.E,Enum.KeyCode.ButtonX)
 else CAS:UnbindAction('StoryCloseFiles')end
end
closeFiles=function()
 if files then files:Destroy();files=nil;table.clear(tabs);bindClose(false)end
 endScene()
end
local function nearBoard()
 local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
 return board~=nil and board.model.Parent~=nil and r~=nil and(r.Position-BOARD_AT.Position).Magnitude<60 and p:GetAttribute('MissionActive')~=true
end
local function openFiles(startId)
 if files then closeFiles();task.wait(.05)end
 closeReader()
 local cinematic=nearBoard()
 local small=compact();local v=viewport()
 -- CoreUISafeInsets: nothing of ours sits under Roblox's own top-left buttons (owner 2026-10-29: never touch those).
 local gui=Instance.new('ScreenGui');gui.Name='StoryCaseFiles';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
 gui.DisplayOrder=200;gui.Parent=pg;files=gui
 local panel=Instance.new('Frame');panel.Name='Panel';panel.BackgroundTransparency=1;panel.Size=UDim2.fromScale(1,1);panel.Parent=gui
 if not cinematic then
  local shade=Instance.new('Frame');shade.BackgroundColor3=Color3.new(0,0,0);shade.BackgroundTransparency=.35;shade.Size=UDim2.fromScale(1,1);shade.ZIndex=0;shade.Parent=panel
 end
 -- Left menu (owner 2026-10-29: a menu down the left side, made for consoles first): every tab and CLOSE stacked, all
 -- on screen at once. Short screens (phones) use two columns. The gamepad moves up / down the list and wraps.
 local TAB_COUNT=#Story.Subjects+2
 local items=TAB_COUNT+1 -- + CLOSE
 local gap=small and 4 or 6
 local availH=panel.AbsoluteSize.Y>0 and panel.AbsoluteSize.Y or v.Y-40
 local cols=(availH-2*gap)/items-gap<38 and 2 or 1
 local rows=math.ceil(items/cols)
 local cellH=math.clamp(math.floor((availH-(rows+1)*gap)/rows),34,54)
 local menuW=cols==2 and math.min(300,math.floor(v.X*.36))or(small and 190 or 250)
 local menu=Instance.new('Frame');menu.Name='Menu';menu.BackgroundColor3=INK;menu.BackgroundTransparency=.12;menu.Position=UDim2.fromOffset(gap,gap)
 menu.Size=UDim2.new(0,menuW,0,math.min(availH-2*gap,rows*(cellH+gap)+3*gap));menu.SelectionGroup=true;menu.SelectionBehaviorUp=Enum.SelectionBehavior.Stop;menu.SelectionBehaviorDown=Enum.SelectionBehavior.Stop
 menu.Active=true;menu.Parent=panel;corner(menu,12);stroke(menu,LINE,2) -- Active: a click on the menu's empty space is not 'outside'
 local strip=Instance.new('Frame');strip.Name='Tabs';strip.BackgroundTransparency=1;strip.Position=UDim2.fromOffset(gap,gap);strip.Size=UDim2.new(1,-2*gap,1,-2*gap);strip.Parent=menu
 local grid=Instance.new('UIGridLayout');grid.CellSize=UDim2.new(1/cols,-gap,0,cellH);grid.CellPadding=UDim2.fromOffset(gap,gap);grid.SortOrder=Enum.SortOrder.LayoutOrder
 grid.FillDirectionMaxCells=cols;grid.Parent=strip
 local close=button(strip,'CLOSE',small and 11 or 14,{Name='Close',LayoutOrder=99,BackgroundColor3=Color3.fromRGB(80,42,48),TextScaled=true})
 local closeFit=Instance.new('UITextSizeConstraint');closeFit.MaxTextSize=small and 11 or 15;closeFit.Parent=close
 close.Activated:Connect(closeFiles)
 -- Detail: right of the menu. Wide + board: a column on the right (the held card sits between); phones + board: the
 -- lower half (the held card above it); away from the board: the whole space beside the menu.
 local detail=Instance.new('ScrollingFrame');detail.Name='Detail';detail.BackgroundColor3=INK;detail.BackgroundTransparency=.12;detail.BorderSizePixel=0
 detail.ScrollBarThickness=6;detail.ScrollBarImageColor3=LINE;detail.CanvasSize=UDim2.new();detail.AutomaticCanvasSize=Enum.AutomaticSize.Y;detail.Active=true;detail.Parent=panel;corner(detail,12);stroke(detail,LINE,2)
 local leftX=menuW+2*gap
 if cinematic and not small then detail.AnchorPoint=Vector2.new(1,0);detail.Position=UDim2.new(1,-gap,0,gap);detail.Size=UDim2.new(.36,0,1,-2*gap)
 elseif cinematic then detail.AnchorPoint=Vector2.new(0,1);detail.Position=UDim2.new(0,leftX,1,-gap);detail.Size=UDim2.new(1,-leftX-gap,.5,0)
 else detail.Position=UDim2.fromOffset(leftX,gap);detail.Size=UDim2.new(1,-leftX-gap,1,-2*gap)end
 local body12,body15,title=small and 10 or 13,small and 11 or 15,small and 14 or 20
 local function clearDetail()for _,c in detail:GetChildren()do if not c:IsA('UICorner')and not c:IsA('UIStroke')then c:Destroy()end end;pad(detail,small and 10 or 18)
  local l=Instance.new('UIListLayout');l.Padding=UDim.new(0,small and 8 or 12);l.SortOrder=Enum.SortOrder.LayoutOrder;l.Parent=detail;detail.CanvasPosition=Vector2.zero end
 local function photo(subject,order)
  -- Only off the board (the scene holds the real photo up instead).
  local holder=Instance.new('Frame');holder.BackgroundColor3=Color3.new(0,0,0);holder.Size=UDim2.new(1,0,0,0);holder.LayoutOrder=order;holder.Parent=detail;corner(holder,8)
  local ar=Instance.new('UIAspectRatioConstraint');ar.AspectRatio=16/9;ar.Parent=holder
  if subject.image~=''then local img=Instance.new('ImageLabel');img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.Image=subject.image;img.ScaleType=Enum.ScaleType.Crop;img.Parent=holder;corner(img,8)
  else label(holder,'NO SIGNAL',small and 14 or 20,DIM,{Size=UDim2.fromScale(1,1),AutomaticSize=Enum.AutomaticSize.None,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})end
 end
 local show
 local function tab(id,text,order)
  local b=button(strip,text,small and 9 or 11,{Name='Tab_'..id,LayoutOrder=order,TextScaled=true,TextXAlignment=Enum.TextXAlignment.Left})
  local fit=Instance.new('UITextSizeConstraint');fit.MaxTextSize=small and 11 or 14;fit.MinTextSize=6;fit.Parent=b
  local inner=Instance.new('UIPadding');inner.PaddingLeft=UDim.new(0,10);inner.PaddingRight=UDim.new(0,6);inner.Parent=b
  b.Activated:Connect(function()show(id)end);tabs[id]=b;return b
 end
 local function readNoteHere(note)
  if cinematic then holdThing('note',note)else showNote(note,false)end
 end
 show=function(id)
  for k,b in tabs do b.BackgroundColor3=k==id and Color3.fromRGB(44,70,58)or PANEL end
  clearDetail()
  if id=='Land'then
   label(detail,Story.Land.title,title,GREEN,{LayoutOrder=1})
   label(detail,Story.Land.text,body15,PALE,{LayoutOrder=2,LineHeight=1.5})
   label(detail,Story.Land.crew,body12,DIM,{LayoutOrder=3,LineHeight=1.5})
   label(detail,'A glowing note is hidden in every level. Find them all!',body12,GOLD,{LayoutOrder=4})
   if cinematic then holdThing('note',Story.Notes[1])end
  elseif id=='Notes'then
   label(detail,'YOUR NOTES: '..foundCount()..' OF '..#Story.Notes,title,GREEN,{LayoutOrder=1})
   local first
   for i,note in Story.Notes do
    if found[note.id]then
     local b=button(detail,note.index..'. '..note.title,body12,{LayoutOrder=1+i,Size=UDim2.new(1,0,0,small and 44 or 48),TextXAlignment=Enum.TextXAlignment.Left})
     pad(b,10);b.Activated:Connect(function()readNoteHere(note)end);first=first or note
    else
     label(detail,note.index..'. ???  (hidden in level '..noteLevel(note)..')',body12,DIM,{LayoutOrder=1+i})
    end
   end
   if cinematic and first then holdThing('note',first)end
  else
   local s=Story.SubjectById[id];if not s then return end
   local open=unlocked(s)
   if cinematic then holdThing('photo',s)else photo(s,1)end
   label(detail,('MONSTER %d: %s'):format(s.index,open and s.name or'???'),title,open and GREEN or DIM,{LayoutOrder=2})
   if open then
    label(detail,'WHO IT WAS: '..s.owner,body12,GOLD,{LayoutOrder=3})
    label(detail,'IN THE GAME: '..s.monster,body12,DIM,{LayoutOrder=4})
    label(detail,s.text,body15,PALE,{LayoutOrder=5,LineHeight=1.5})
    label(detail,'HOW TO STAY SAFE: '..s.tip,body12,GREEN,{LayoutOrder=6})
   else
    local where;for _,note in Story.Notes do if note.subject==s.id then where=note end end
    label(detail,'Find the note about this monster'..(where and(' in level '..noteLevel(where))or'')..' to learn who it was.',body15,PALE,{LayoutOrder=3,LineHeight=1.5})
   end
  end
 end
 currentShow=show
 tab('Land','THE TOWN',1)
 for i,s in Story.Subjects do tab(s.id,unlocked(s)and s.name or('MONSTER %d'):format(i),1+i)end
 tab('Notes','NOTES '..foundCount()..'/'..#Story.Notes,20)
 tabs.Land.NextSelectionUp=close;close.NextSelectionDown=tabs.Land -- the gamepad wraps top <-> bottom
 if cinematic then beginScene()end
 show(startId or'Land')
 bindClose(true)
 if GuiService:IsTenFootInterface()or InputHints.Get()=='pad'then GuiService.SelectedObject=tabs[startId or'Land']end
end

local function buildBoard()
 local world=workspace:WaitForChild('LobbyWorld',math.huge)
 local old=world:FindFirstChild('StoryCaseBoard');if old then old:Destroy()end
 local m=Instance.new('Model');m.Name='StoryCaseBoard'
 local function part(name,size,cf,color,mat)
  local x=Instance.new('Part');x.Name=name;x.Size=size;x.CFrame=cf;x.Color=color;x.Material=mat or Enum.Material.Wood;x.Anchored=true
  x.CanCollide=true;x.CastShadow=false;x.TopSurface=Enum.SurfaceType.Smooth;x.BottomSurface=Enum.SurfaceType.Smooth;x.Parent=m;return x
 end
 local W,H,Y=BOARD_W,BOARD_H,BOARD_Y
 local wood=Color3.fromRGB(58,42,32)
 local cork=part('Cork',Vector3.new(W,H,.4),boardCF(0,Y),Color3.fromRGB(122,92,62),Enum.Material.Fabric)
 part('FrameTop',Vector3.new(W+1,.6,.7),boardCF(0,Y+H/2+.3),wood);part('FrameBottom',Vector3.new(W+1,.6,.7),boardCF(0,Y-H/2-.3),wood)
 part('FrameL',Vector3.new(.6,H+1.2,.7),boardCF(-W/2-.2,Y),wood);part('FrameR',Vector3.new(.6,H+1.2,.7),boardCF(W/2+.2,Y),wood)
 local lamp=part('Lamp',Vector3.new(W*.8,.3,.6),boardCF(0,Y+H/2+.9,-.8),Color3.fromRGB(40,40,40),Enum.Material.Metal)
 local light=Instance.new('SpotLight');light.Face=Enum.NormalId.Bottom;light.Angle=120;light.Range=26;light.Brightness=2.4;light.Color=Color3.fromRGB(220,255,230);light.Parent=lamp
 -- The display pedestal under the board, where the west door was: dark wood and gold, an old CCTV television on top
 -- flicking through the monster photos. Its screen is the button (tap / click), and it holds the prompt (E / X).
 local GOLD_TRIM,DARK=Color3.fromRGB(196,156,72),Color3.fromRGB(40,30,26)
 local function pcf(x,y,z)return PEDESTAL_AT*CFrame.new(x,y,z)end
 local upright=CFrame.Angles(0,0,math.rad(90)) -- a Cylinder part's axis is X: stand it up
 part('PedestalBase',Vector3.new(.5,4.6,4.6),pcf(0,.25,0)*upright,DARK)
 part('PedestalRing',Vector3.new(.14,4.85,4.85),pcf(0,.52,0)*upright,GOLD_TRIM,Enum.Material.Metal).CanCollide=false
 part('PedestalStep',Vector3.new(.4,3.7,3.7),pcf(0,.75,0)*upright,wood)
 for _,n in{'PedestalBase','PedestalRing','PedestalStep'}do m[n].Shape=Enum.PartType.Cylinder end
 part('PedestalColumn',Vector3.new(1.6,3.2,1.6),pcf(0,2.55,0),wood)
 part('PedestalBandLow',Vector3.new(1.78,.16,1.78),pcf(0,1.12,0),GOLD_TRIM,Enum.Material.Metal).CanCollide=false
 part('PedestalBandHigh',Vector3.new(1.78,.16,1.78),pcf(0,3.98,0),GOLD_TRIM,Enum.Material.Metal).CanCollide=false
 part('PedestalTop',Vector3.new(3.1,.35,2.7),pcf(0,4.33,0),DARK)
 part('PedestalTopTrim',Vector3.new(3.22,.1,2.82),pcf(0,4.18,0),GOLD_TRIM,Enum.Material.Metal).CanCollide=false
 local tilt=pcf(0,5.62,.1)*CFrame.Angles(math.rad(-8),0,0) -- the set leans back a little toward the viewer
 local tv=part('TV',Vector3.new(2.7,2.2,2.1),tilt,Color3.fromRGB(52,54,58),Enum.Material.SmoothPlastic);tv.CanCollide=false
 part('TVBezel',Vector3.new(2.4,1.85,.08),tilt*CFrame.new(0,0,-1.07),Color3.fromRGB(24,24,28),Enum.Material.SmoothPlastic).CanCollide=false
 local screen=part('TVScreen',Vector3.new(2.05,1.5,.05),tilt*CFrame.new(-.05,.04,-1.12),Color3.new(0,0,0),Enum.Material.SmoothPlastic);screen.CanCollide=false
 part('TVKnob',Vector3.new(.22,.22,.12),tilt*CFrame.new(1.05,-.55,-1.1),Color3.fromRGB(180,180,170),Enum.Material.Metal).CanCollide=false
 for i,a in{-25,25}do
  local ant=part('TVAntenna'..i,Vector3.new(.07,1.7,.07),tilt*CFrame.new(0,1.1,0)*CFrame.Angles(0,0,math.rad(a))*CFrame.new(0,.85,0),Color3.fromRGB(190,190,195),Enum.Material.Metal);ant.CanCollide=false
 end
 local glow=Instance.new('PointLight');glow.Color=Color3.fromRGB(170,255,200);glow.Brightness=1.4;glow.Range=11;glow.Parent=screen
 -- The screen: a SurfaceGui in PlayerGui (taps and clicks reach it) cycling the photos with a short static blink.
 local tvGui=pg:FindFirstChild('StoryPedestalScreen');if tvGui then tvGui:Destroy()end
 tvGui=Instance.new('SurfaceGui');tvGui.Name='StoryPedestalScreen';tvGui.Adornee=screen;tvGui.Face=Enum.NormalId.Front;tvGui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
 tvGui.CanvasSize=Vector2.new(410,300);tvGui.LightInfluence=0;tvGui.MaxDistance=90;tvGui.ResetOnSpawn=false;tvGui.Parent=pg
 local tvButton=Instance.new('ImageButton');tvButton.Name='Screen';tvButton.Size=UDim2.fromScale(1,1);tvButton.BackgroundColor3=Color3.new(0,0,0);tvButton.ScaleType=Enum.ScaleType.Crop
 tvButton.AutoButtonColor=false;tvButton.Parent=tvGui
 local tvLabel=label(tvButton,'TAP TO READ',26,GREEN,{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-8),Size=UDim2.new(1,-20,0,0),TextXAlignment=Enum.TextXAlignment.Center})
 tvLabel.Text=InputHints.Get()=='touch'and'TAP TO READ'or InputHints.Get()=='pad'and'PRESS X TO READ'or'CLICK TO READ'
 tvButton.Activated:Connect(function()openFiles()end)
 task.spawn(function()
  local i=0
  while tvGui.Parent do
   i=i%#Story.Subjects+1;tvButton.ImageTransparency=1;task.wait(.12)
   tvButton.Image=Story.Subjects[i].image;tvButton.ImageTransparency=0;task.wait(2.6)
  end
 end)
 -- A small brass sign on the column.
 local plate=part('PedestalPlate',Vector3.new(1.3,.55,.05),pcf(0,3.05,-.83),GOLD_TRIM,Enum.Material.Metal);plate.CanCollide=false
 local plateGui=Instance.new('SurfaceGui');plateGui.Name='Sign';plateGui.Face=Enum.NormalId.Front;plateGui.CanvasSize=Vector2.new(260,110);plateGui.LightInfluence=.3;plateGui.Parent=plate
 label(plateGui,'MONSTER FILES',30,Color3.fromRGB(40,30,20),{Size=UDim2.fromScale(1,1),AutomaticSize=Enum.AutomaticSize.None,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center,TextScaled=true})
 local prompt=Instance.new('ProximityPrompt');prompt.Name='CaseFilesPrompt';prompt.ActionText='Read the files';prompt.ObjectText='Monster files'
 prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=0;prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=false;prompt.Parent=screen
 -- Yarn between the photos (pale yellow, never red).
 local a0=nil
 for i,spot in CARD_SPOTS do
  local att=Instance.new('Attachment');att.Name='Yarn'..i;att.WorldPosition=boardCF(spot[1],spot[2]+CARD.Y/2-.1,-.25).Position;att.Parent=cork
  if a0 then local beam=Instance.new('Beam');beam.Attachment0=a0;beam.Attachment1=att;beam.Width0=.06;beam.Width1=.06;beam.FaceCamera=true;beam.CurveSize0=-.6;beam.CurveSize1=.6
   beam.Color=ColorSequence.new(Color3.fromRGB(236,220,150));beam.LightInfluence=1;beam.Parent=cork end
  a0=att
 end
 board={model=m,cork=cork,cards={}}
 for i,s in Story.Subjects do
  local spot=CARD_SPOTS[i]
  local cf=boardCF(spot[1],spot[2],-.24)*CFrame.Angles(0,0,math.rad(CARD_TILT[i]))
  local card=part('Card_'..s.id,CARD,cf,PAPER,Enum.Material.SmoothPlastic);card.CanCollide=false
  local gui,face,caption=cardFace(card,'photo',s,true)
  face.Activated:Connect(function()openFiles(s.id)end)
  board.cards[s.id]={part=card,gui=gui,cf=cf,caption=caption,photo=face:FindFirstChild('Photo')}
 end
 m.PrimaryPart=cork;m.Parent=world
 -- Title and status: one SurfaceGui on the cork, drawn around the cards (canvas 100 px per stud).
 local gui=pg:FindFirstChild('StoryCaseBoardGui');if gui then gui:Destroy()end
 gui=Instance.new('SurfaceGui');gui.Name='StoryCaseBoardGui';gui.Adornee=cork;gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
 gui.CanvasSize=Vector2.new(2000,1150);gui.LightInfluence=0;gui.MaxDistance=140;gui.ResetOnSpawn=false;gui.Parent=pg
 -- The cork itself is a button (owner 2026-10-29): clicking / tapping the brown board (not a photo, not READ THE FILES)
 -- while the files are open closes them and gives the normal view back.
 local root=Instance.new('TextButton');root.Name='Cork';root.Text='';root.AutoButtonColor=false;root.BackgroundTransparency=1;root.Size=UDim2.fromScale(1,1);root.Parent=gui
 root.Activated:Connect(function()if files then closeFiles()end end)
 local titleBg=Instance.new('Frame');titleBg.BackgroundColor3=PAPER;titleBg.Position=UDim2.fromOffset(600,14);titleBg.Size=UDim2.fromOffset(800,96);titleBg.Rotation=-1;titleBg.Parent=root;corner(titleBg,6)
 label(titleBg,'WHO ARE THEY?',58,Color3.fromRGB(30,32,38),{Size=UDim2.fromScale(1,1),AutomaticSize=Enum.AutomaticSize.None,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})
 local status=label(root,'',30,PAPER,{Position=UDim2.fromOffset(40,1070),Size=UDim2.fromOffset(1300,60),AutomaticSize=Enum.AutomaticSize.None})
 local open=Instance.new('TextButton');open.Name='OpenFiles';open.Text='READ THE FILES';open.TextSize=38;open.TextColor3=INK;open.BackgroundColor3=GREEN
 open.Position=UDim2.fromOffset(1480,1040);open.Size=UDim2.fromOffset(480,96);open.Parent=root;corner(open,12)
 open.Activated:Connect(function()openFiles()end)
 local function redraw()
  for _,s in Story.Subjects do
   local c=board.cards[s.id];local known=unlocked(s)
   if c.caption then c.caption.Text=('MONSTER %d\n%s'):format(s.index,known and s.name or'???')end
   if c.photo then c.photo.ImageTransparency=known and 0 or .35 end
  end
  status.Text=('NOTES FOUND: %d OF %d.  A NOTE IS HIDDEN IN EVERY LEVEL!'):format(foundCount(),#Story.Notes)
 end
 table.insert(listeners,redraw);redraw()
end
PromptService.PromptTriggered:Connect(function(prompt)
 if prompt.Name=='CaseFilesPrompt'and prompt:IsDescendantOf(workspace)then openFiles()end
end)
task.spawn(buildBoard)
-- Studio tests (rbxdev scenarios): open a file / close the screen without a click.
if Run:IsStudio()then
 local hook=Instance.new('BindableFunction');hook.Name='StoryTest';hook.Parent=script
 hook.OnInvoke=function(action,id)
  if action=='open'then task.spawn(openFiles,id);return true
  elseif action=='tab'then if currentShow and files then task.spawn(currentShow,id);return true end;return false
  elseif action=='close'then closeFiles();return true end
  return false
 end
end
syncFound()
-- Back in the lobby after a run: fetch the save again (notes read in the run are already in `found`).
p:GetAttributeChangedSignal('MissionActive'):Connect(function()
 if p:GetAttribute('MissionActive')~=true then task.delay(2,syncFound)else closeFiles()end
end)
p.CharacterAdded:Connect(function()if scene then closeFiles();Inspect.Cancel()end end)
-- Leaving the files (owner 2026-10-29): a click or tap that lands on nothing of the files screen (the world, the held
-- card, the dark hall) closes them; so does ending up away from the board (walked off, teleported) while they are open.
local UIS=game:GetService('UserInputService')
UIS.InputBegan:Connect(function(input,processed)
 if processed or not files then return end
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then closeFiles()end
end)
Run.Heartbeat:Connect(function()
 if not files or not scene then return end
 local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
 if not r or(r.Position-BOARD_AT.Position).Magnitude>70 then closeFiles()end
end)
