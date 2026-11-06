-- Client half of CursedBatchEffects.ItemBatch7 (CursedA build 2026-10-27). Required once (task.spawn) by
-- CurseEffectsClient after ItemBatch6Client. Reads only replicated attributes; no remotes, no images.
--  * Companions: every player's follower (Companion attribute; templates ReplicatedStorage.CompanionKit): Dusty trundles
--    behind and carries its swallowed item as a spinning mini copy; the sock rides the left shoulder and warns (8 peeks
--    per level) when a monster is behind you: arrow + "PSST!" + a startled face.
--  * Treasures: crew outline on a worn / calling crown, idol dark-front grade + whisper.
--  * Map items: FoodCourtPager chip, through-wall marker, lime pulse, rumble and tug; HallPass chip.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local InputHints=require(RS:WaitForChild('InputHints'))
local player=Players.LocalPlayer
local Batch6Client -- set by M.Init (shared reaction player)
local camera=workspace.CurrentCamera

local DRAW_RADIUS=90        -- followers further than this from the camera are parked (not drawn, not updated)
local SLOW_RADIUS=40        -- beyond this they update at 10 Hz instead of every frame
local MAX_DRAWN=if InputHints.IsMobile()then 4 else 8 -- followers drawn at once, nearest first (3.4k-4.5k tris each)
local TELEPORT=22           -- further than this from its goal: pop next to the owner
local HIDDEN_POP=.8         -- floor follower out of the owner's sight this long: pop next to the owner
-- Peekaboo sock
local PEEKS=8               -- warnings per level, then the sock naps
local PEEK_RADIUS=26        -- a monster within this many studs of your head ...
local PEEK_CLOSE=12         -- ... in line of sight, or this close even through a wall
local PEEK_BEHIND=-.2       -- ... behind the view: flat dot(look, to monster) below this (about 100 degrees and more)
local PEEK_FLOOR=9          -- ... on roughly the same floor
local PEEK_REPEAT,PEEK_GAP=8,3 -- the same monster again after 8 s; any warning at most every 3 s
local PEEK_SHOW=1.6
-- Dusty
local DUSTY_SPEED=30        -- studs/s (sprint is 21.5; the 2x Speed pass outruns it and it pops along via TELEPORT)
local CARRY_FIT=.9          -- the carried item's mini copy fits in a 0.9-stud box on Dusty's back

local folder=Instance.new('Folder');folder.Name='CompanionFollowers';folder.Parent=workspace
local followers={}          -- 'userId:slot' -> state
local peekBank={}           -- userId -> {round=n, left=n}: dying does not refill the sock
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
local round=RS:WaitForChild('RecoveryRound',10) -- RecoveryRoundServer state: Round, Sold (nil in a place without it)

local function flat(v)
 local f=Vector3.new(v.X,0,v.Z);return if f.Magnitude>1e-3 then f.Unit else Vector3.new(0,0,-1)
end
local function refreshExclude()
 local list={folder}
 for _,p in ipairs(Players:GetPlayers())do if p.Character then table.insert(list,p.Character)end end
 local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
 if items then table.insert(list,items)end
 local creatures=workspace:FindFirstChild('RoamingCreatures');if creatures then table.insert(list,creatures)end
 params.FilterDescendantsInstances=list
end
-- Pull a goal back toward its anchor if a wall is in between (corridors, door frames, the van walls).
local function clampToRoom(from,to,pad)
 local dir=to-from;if dir.Magnitude<.05 then return to end
 local hit=workspace:Raycast(from,dir,params)
 return if hit then hit.Position-dir.Unit*math.min(pad,hit.Distance)else to
end
local function floorAt(pos,maxDrop)
 local hit=workspace:Raycast(pos+Vector3.new(0,2.5,0),Vector3.new(0,-(maxDrop+2.5),0),params)
 return hit and hit.Position.Y
end
local function ownerParts(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if not c or not h or h.Health<=0 then return nil end
 local root=c:FindFirstChild('HumanoidRootPart');local head=c:FindFirstChild('Head')
 if not root or not head then return nil end
 return c,root,head,h
end
local function styleFor(slot,id)
 return if id=='DustBunnyBot'then 'floor'else 'shoulder'
end
local function templateFor(slot,id)
 local kit=RS:FindFirstChild('CompanionKit')
 local t=kit and kit:FindFirstChild(id);return t and t:IsA('Model')and t or nil
end

-- HUD (owner of a sock only): a direction arrow + "PSST!" for 1.6 s, and the peeks left.
local gui=Instance.new('ScreenGui');gui.Name='CompanionHud';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=4
gui.Parent=player:WaitForChild('PlayerGui')
-- Drawn chevron pointing up at Rotation 0 (text arrows are missing from the game fonts, see TutorialGuide).
local arrow=Instance.new('Frame');arrow.Name='PeekArrow';arrow.AnchorPoint=Vector2.new(.5,.5);arrow.Size=UDim2.fromOffset(56,56)
arrow.BackgroundTransparency=1;arrow.Visible=false;arrow.Parent=gui
for _,side in ipairs({-1,1})do
 local bar=Instance.new('Frame');bar.AnchorPoint=Vector2.new(.5,.5);bar.Size=UDim2.fromOffset(36,10)
 bar.Position=UDim2.new(.5,side*11,.5,0);bar.Rotation=side*45;bar.BorderSizePixel=0
 bar.BackgroundColor3=Color3.fromRGB(196,170,255);bar.Parent=arrow
 Instance.new('UICorner',bar).CornerRadius=UDim.new(1,0)
 local edge=Instance.new('UIStroke');edge.Color=Color3.fromRGB(20,14,34);edge.Thickness=2;edge.Parent=bar
end
local psst=Instance.new('TextLabel');psst.Name='PeekText';psst.AnchorPoint=Vector2.new(.5,.5);psst.Size=UDim2.fromOffset(260,34)
psst.BackgroundTransparency=1;psst.Font=Enum.Font.FredokaOne;psst.TextScaled=true;psst.TextColor3=Color3.fromRGB(240,236,255)
psst.TextStrokeTransparency=.3;psst.Visible=false;psst.Parent=gui
local function showPeek(delta,left)
 local rel=camera.CFrame:VectorToObjectSpace(delta)
 local angle=math.atan2(rel.X,-rel.Z) -- 0 = straight ahead, +-pi = straight behind
 local view=camera.ViewportSize;local radius=math.min(view.X,view.Y)*(if InputHints.IsMobile()then .22 else .3)
 local centre=Vector2.new(view.X/2,view.Y/2)+Vector2.new(math.sin(angle),-math.cos(angle))*radius
 arrow.Position=UDim2.fromOffset(centre.X,centre.Y);arrow.Rotation=math.deg(angle);arrow.Visible=true
 psst.Position=UDim2.new(.5,0,.5,-radius-40)
 psst.Text=if left>0 then ('PSST! BEHIND YOU   (%d peeks left)'):format(left)else 'PSST! BEHIND YOU   (the sock is falling asleep)'
 psst.Visible=true
 Audio.Play('ClothHandle')
end
local hudUntil=0

local function hideReal(item,on)
 for _,x in ipairs(item:GetDescendants())do if x:IsA('BasePart')then x.LocalTransparencyModifier=on and 1 or 0 end end
end
local function dropCarry(s)
 if s.carryMini then s.carryMini:Destroy();s.carryMini=nil end
 if s.carryItem and s.carryItem.Parent then hideReal(s.carryItem,false)end
 s.carryItem=nil
end
local function miniOf(item)
 local ok,copy=pcall(function()return item:Clone()end)
 if not ok or not copy then return nil end
 for _,x in ipairs(copy:GetDescendants())do
  if x:IsA('BasePart')then
   if x.Name=='ItemGroundCollider'then x:Destroy()else x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.LocalTransparencyModifier=0 end
  elseif x:IsA('LuaSourceContainer')or x:IsA('Sound')or x:IsA('Light')or x:IsA('ParticleEmitter')or x:IsA('ProximityPrompt')or x:IsA('BillboardGui')then x:Destroy()end
 end
 local _,size=copy:GetBoundingBox();local longest=math.max(size.X,size.Y,size.Z)
 if longest>CARRY_FIT then copy:ScaleTo(copy:GetScale()*CARRY_FIT/longest)end
 copy.Name='DustyCarry';copy.Parent=folder
 return copy
end

local function build(owner,slot,id)
 local t=templateFor(slot,id);if not t then return nil end
 local m=t:Clone();m.Name=owner.Name..'_'..id
 local style=styleFor(slot,id)
 local wings={}
 for _,x in ipairs(m:GetDescendants())do
  if x:IsA('BasePart')then
   x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.Massless=true
   if style=='hover'and x.Material==Enum.Material.Neon then wings[x]=x.Size end
  elseif x:IsA('LuaSourceContainer')or x:IsA('Light')or x:IsA('Sound')then x:Destroy()end
 end
 m.Parent=folder
 local s={owner=owner,slot=slot,id=id,model=m,style=style,wings=wings,pos=nil,yaw=0,updatedAt=0,drawn=true,
  seen=setmetatable({},{__mode='k'}),lastPeek=-math.huge,peekUntil=0,peekDir=nil,hiddenSince=nil,
  idleSince=os.clock(),loopUntil=0,carryItem=nil,carryMini=nil,checkAt=0}
 if id=='PeekabooSock'then
  local r=round and round:GetAttribute('Round')or 0;local bank=peekBank[owner.UserId]
  if not bank or bank.round~=r then bank={round=r,left=PEEKS};peekBank[owner.UserId]=bank end
  s.bank=bank
 end
 return s
end
local function destroy(key)
 local s=followers[key];if not s then return end
 dropCarry(s);s.model:Destroy();followers[key]=nil
end
local function wanted()
 local list={}
 for _,p in ipairs(Players:GetPlayers())do
  if ownerParts(p)and not p:GetAttribute('RoundDead')and not p:GetAttribute('Hiding')and not p:GetAttribute('ClosetState')then
   local found=p:GetAttribute('Companion')
   if type(found)=='string'and found~=''and p:GetAttribute('MissionActive')==true then list[p.UserId..':Companion']={p,'Companion',found}end
  end
 end
 return list
end
local function sync()
 local want=wanted()
 for key,s in pairs(followers)do
  local w=want[key];if not w or w[1]~=s.owner or w[3]~=s.id then destroy(key)end
 end
 for key,w in pairs(want)do if not followers[key]then followers[key]=build(w[1],w[2],w[3])end end
 -- Draw only the nearest MAX_DRAWN within DRAW_RADIUS; park the rest (unparented, not updated).
 local camPos=camera.CFrame.Position;local order={}
 for key,s in pairs(followers)do
  local _,root=ownerParts(s.owner)
  s.distance=root and(root.Position-camPos).Magnitude or math.huge;table.insert(order,s)
 end
 table.sort(order,function(a,b)return a.distance<b.distance end)
 for i,s in ipairs(order)do
  local draw=i<=MAX_DRAWN and s.distance<=DRAW_RADIUS
  if draw~=s.drawn then s.drawn=draw;s.model.Parent=draw and folder or nil;if not draw then s.pos=nil end end
 end
end

local function peekCheck(s,root,head,now)
 local bank=s.bank;if not bank or bank.left<=0 or now-s.lastPeek<PEEK_GAP then return end
 local creatures=workspace:FindFirstChild('RoamingCreatures');if not creatures then return end
 local mine=s.owner==player
 local look=flat(if mine then camera.CFrame.LookVector else root.CFrame.LookVector)
 for _,enemy in ipairs(creatures:GetChildren())do
  local primary=enemy:IsA('Model')and enemy.PrimaryPart
  if primary and now-(s.seen[enemy]or -math.huge)>=PEEK_REPEAT then
   local delta=primary.Position-head.Position;local d=delta.Magnitude
   if d<PEEK_RADIUS and math.abs(delta.Y)<PEEK_FLOOR and look:Dot(flat(delta))<PEEK_BEHIND then
    local blocked=d>=PEEK_CLOSE and workspace:Raycast(head.Position,delta-delta.Unit*2.5,params)~=nil
    if not blocked then
     s.seen[enemy]=now;s.lastPeek=now;s.peekUntil=now+PEEK_SHOW;s.peekDir=flat(delta)
     bank.left-=1
     if mine then
      player:SetAttribute('CompanionPeeksLeft',bank.left) -- local only (never replicates): HUD + test probe
      showPeek(delta,bank.left);hudUntil=now+PEEK_SHOW
      -- Startled face on your own screen (local attribute) plus a short jolt.
      player:SetAttribute('FaceBeat','gasp');player:SetAttribute('FaceBeatUntil',workspace:GetServerTimeNow()+1.4)
      if Batch6Client and Batch6Client.Play then Batch6Client.Play('SockPeek') end
     end
     return
    end
   end
  end
 end
end

local function firstPerson(head)
 return (camera.CFrame.Position-head.Position).Magnitude<1.3
end
local function updateShoulder(s,root,head,now,dt)
 local napping=s.bank and s.bank.left<=0
 local goal=(head.CFrame*CFrame.new(-1.05,-.85,.15)).Position
 goal=clampToRoom(head.Position,goal,.25)
 local alpha=1-math.exp(-20*dt)
 s.pos=if s.pos then s.pos:Lerp(goal,alpha)else goal
 local look=flat(root.CFrame.LookVector);local lift=0;local roll=math.sin(now*2.2)*.08
 if s.peekUntil>now and s.peekDir then
  look=s.peekDir;lift=.45*math.abs(math.sin((s.peekUntil-now)*9))
 elseif napping then roll=1.25;lift=-.15 end
 local yaw=math.atan2(-look.X,-look.Z)
 s.model:PivotTo(CFrame.new(s.pos+Vector3.new(0,lift,0))*CFrame.Angles(0,yaw,0)*CFrame.Angles(0,0,roll))
 if s.owner==player then peekCheck(s,root,head,now)elseif now>=s.checkAt then s.checkAt=now+.2;peekCheck(s,root,head,now)end
end
local function updateHover(s,root,head,now,dt)
 local look=flat(root.CFrame.LookVector);local right=look:Cross(Vector3.yAxis)
 local moving=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude>.5
 if moving then s.idleSince=now end
 local chased=(s.owner:GetAttribute('ChasedUntil')or 0)>workspace:GetServerTimeNow()
 local goal;local flap=16;local scale=1
 if chased then          -- hides behind your head ("in your hood"), shivering
  goal=head.Position+Vector3.yAxis*.1-look*.75+Vector3.new(math.sin(now*40)*.04,0,0);flap=26;scale=.85
 elseif now<s.loopUntil then -- sale: a happy loop round your head
  local a=now*6;goal=head.Position+Vector3.yAxis*.6+(right*math.cos(a)+look*math.sin(a))*1.8;flap=24
 elseif now-s.idleSince>6 then -- idle: lands on top of your head, slow wings
  goal=head.Position+Vector3.yAxis*(head.Size.Y/2+.02);flap=3
 else
  goal=head.Position+right*1.5+Vector3.yAxis*(.6+math.sin(now*2.1)*.25)-look*.4+right*math.sin(now*1.3)*.35
 end
 goal=clampToRoom(head.Position,goal,.35)
 s.pos=if s.pos and(s.pos-goal).Magnitude<TELEPORT then s.pos:Lerp(goal,1-math.exp(-9*dt))else goal
 local yaw=math.atan2(-look.X,-look.Z)+math.sin(now*1.7)*.35
 s.model:PivotTo(CFrame.new(s.pos)*CFrame.Angles(0,yaw,0))
 local beat=.4+.6*math.abs(math.sin(now*flap))
 for part,base in pairs(s.wings)do part.Size=Vector3.new(base.X*beat*scale,base.Y*scale,base.Z)end
end
local function updateFloor(s,root,head,h,now,dt)
 local look=flat(root.CFrame.LookVector);local right=look:Cross(Vector3.yAxis)
 local feet=root.Position.Y-root.Size.Y/2-h.HipHeight
 local goal=clampToRoom(root.Position,root.Position-look*3.2+right*1.1,1)
 local y=floorAt(Vector3.new(goal.X,root.Position.Y,goal.Z),9)or feet
 goal=Vector3.new(goal.X,y,goal.Z)
 -- out of the owner's sight (other side of a door, a different stair flight) for a moment: pop beside them
 local seen=s.pos and workspace:Raycast(root.Position,(s.pos+Vector3.yAxis*.6)-root.Position,params)==nil
 if s.pos and not seen then s.hiddenSince=s.hiddenSince or now else s.hiddenSince=nil end
 if not s.pos or(s.pos-goal).Magnitude>TELEPORT or(s.hiddenSince and now-s.hiddenSince>HIDDEN_POP)then
  s.pos=goal;s.hiddenSince=nil
 else
  local flatStep=Vector3.new(goal.X-s.pos.X,0,goal.Z-s.pos.Z)
  local step=math.min(flatStep.Magnitude,DUSTY_SPEED*dt)
  local nextY=s.pos.Y+(goal.Y-s.pos.Y)*(1-math.exp(-18*dt)) -- stairs: Y follows the floor ray quickly
  local moved=if flatStep.Magnitude>1e-3 then flatStep.Unit*step else Vector3.zero
  s.pos=Vector3.new(s.pos.X+moved.X,nextY,s.pos.Z+moved.Z)
  if moved.Magnitude>.01 then s.yaw=math.atan2(-moved.X,-moved.Z)end
 end
 local wobble=math.sin(now*14)*.02
 local cf=CFrame.new(s.pos)*CFrame.Angles(0,s.yaw,0)*CFrame.Angles(wobble,0,0)
 s.model:PivotTo(cf)
 -- The carried item: find it at 4 Hz, hide the real (welded) one, ride a mini copy on Dusty's back.
 if now>=s.checkAt then
  s.checkAt=now+.25
  local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive');local found
  if items then for _,m in ipairs(items:GetChildren())do if m:GetAttribute('DustyCarriedBy')==s.owner.UserId then found=m;break end end end
  if found~=s.carryItem then dropCarry(s);if found then s.carryItem=found;s.carryMini=miniOf(found)end end
  if s.carryItem then hideReal(s.carryItem,true)end
 end
 if s.carryMini then
  local _,size=s.carryMini:GetBoundingBox()
  s.carryMini:PivotTo(cf*CFrame.new(0,.5+size.Y/2,.6)*CFrame.Angles(0,now*1.5,0))
 end
end

local syncAt,excludeAt=0,0
Run.RenderStepped:Connect(function(dt)
 local now=os.clock()
 if now>=excludeAt then excludeAt=now+1;refreshExclude()end
 if now>=syncAt then syncAt=now+.25;sync()end
 if now>=hudUntil then arrow.Visible=false;psst.Visible=false end
 for _,s in pairs(followers)do
  if not s.drawn then continue end
  local _,root,head,h=ownerParts(s.owner)
  if not root then continue end
  local slow=(s.distance or 0)>SLOW_RADIUS
  if slow and now-s.updatedAt<.1 then continue end
  local step=if slow then now-s.updatedAt else dt
  s.updatedAt=now
  local own=s.owner==player and s.style~='floor'and firstPerson(head)
  local parent=if own then nil else folder -- never in your own face in first person (the sock still peeks)
  if s.model.Parent~=parent then s.model.Parent=parent end
  if s.style=='floor'then updateFloor(s,root,head,h,now,math.min(step,.2))
  elseif s.style=='shoulder'then updateShoulder(s,root,head,now,math.min(step,.2))
  else updateHover(s,root,head,now,math.min(step,.2))end
 end
end)
Players.PlayerRemoving:Connect(function(p)
 for key,s in pairs(followers)do if s.owner==p then destroy(key)end end
 peekBank[p.UserId]=nil
end)

-- Treasures ---------------------------------------------------------------------------------------------
local function itemModels()
 local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
 return items and items:GetChildren()or {}
end
local darkGrade=Instance.new('ColorCorrectionEffect');darkGrade.Name='IdolDarkFront';darkGrade.Enabled=false;darkGrade.Parent=game:GetService('Lighting')
local lastWhisper=0
local function crownGlow(m,on)
 local h=m:FindFirstChild('CrownCrewOutline')
 if on and not h then
  h=Instance.new('Highlight');h.Name='CrownCrewOutline';h.FillTransparency=1;h.OutlineColor=Color3.fromRGB(245,186,34)
  h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.Adornee=m;h.Parent=m
 elseif not on and h then h:Destroy() end
end
local treasureAcc=0
Run.Heartbeat:Connect(function(dt)
 treasureAcc+=dt;if treasureAcc<.1 then return end;treasureAcc=0
 local now=workspace:GetServerTimeNow();local dark=0
 local myRoot=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 for _,m in ipairs(itemModels())do
  local id=m:GetAttribute('ItemId')
  if id=='MansionCrown' then
   local owner=m:GetAttribute('ItemWearOwner')
   crownGlow(m,(owner~=nil and owner~=player.UserId) or m:GetAttribute('CrownCalling')==true)
  elseif id=='GildedIdol' and m.PrimaryPart and m:GetAttribute('IdolLifted') and myRoot and (m.PrimaryPart.Position-myRoot.Position).Magnitude<45 then
   -- One room of light left between the dark and the idol: the screen sinks as the next step nears.
   local rooms=m:GetAttribute('IdolLightRooms')or 9;local wait=(m:GetAttribute('IdolNextStepAt')or now)-now
   if rooms<=1 then dark=math.max(dark,math.clamp(1-wait/9,.25,1)) end
   if rooms<=1 and wait<3 and now-lastWhisper>6 then lastWhisper=now;Audio.Play('ScareWhisper',m.PrimaryPart) end
  end
 end
 darkGrade.Enabled=dark>0;darkGrade.Brightness=-.12*dark;darkGrade.Contrast=.15*dark;darkGrade.Saturation=-.4*dark
end)

-- Map items ----------------------------------------------------------------------------------------------
local function leased(q,key) return workspace:GetServerTimeNow()<(q:GetAttribute(key)or 0) end
local function alive(q) local c=q.Character;local h=c and c:FindFirstChildOfClass('Humanoid');return h~=nil and h.Health>0 and q:GetAttribute('MissionActive')==true end
local HapticService=game:GetService('HapticService')

local TUG_SECONDS,TUG_SPEED=.35,7
local LIME=Color3.fromRGB(154,210,63)
local MINT=Color3.fromRGB(90,195,175)
local ORANGE=Color3.fromRGB(240,138,46)
local GREY=Color3.fromRGB(150,155,165)

local function rootOf(q) local c=q.Character;return c and c:FindFirstChild('HumanoidRootPart') end

-- HUD chip (top centre, under the round bar; same place on every device, nothing to press).
local mapGui=Instance.new('ScreenGui');mapGui.Name='MapItemsHud';mapGui.ResetOnSpawn=false;mapGui.IgnoreGuiInset=false;mapGui.DisplayOrder=4;mapGui.Parent=player:WaitForChild('PlayerGui')
local chip=Instance.new('TextLabel');chip.Name='Chip';chip.AnchorPoint=Vector2.new(.5,0);chip.Position=UDim2.new(.5,0,.4,0);chip.Size=UDim2.fromOffset(300,34) -- UI pass 2026-10-27: at y=64 it covered the quota HUD / LOOT chip on phones
chip.BackgroundColor3=Color3.fromRGB(28,29,34);chip.BackgroundTransparency=.2;chip.Font=Enum.Font.GothamBold;chip.TextScaled=true;chip.TextColor3=Color3.new(1,1,1);chip.Visible=false;chip.Parent=mapGui
Instance.new('UICorner',chip).CornerRadius=UDim.new(0,10)
local stroke=Instance.new('UIStroke');stroke.Thickness=2;stroke.Parent=chip
local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,10);pad.PaddingRight=UDim.new(0,10);pad.PaddingTop=UDim.new(0,4);pad.PaddingBottom=UDim.new(0,4);pad.Parent=chip
local edge=Instance.new('Frame');edge.Name='PagerPulse';edge.Size=UDim2.fromScale(1,1);edge.BackgroundTransparency=1;edge.Parent=mapGui
local edgeStroke=Instance.new('UIStroke');edgeStroke.Thickness=14;edgeStroke.Color=LIME;edgeStroke.Transparency=1;edgeStroke.Parent=edge
local function showChip(text,color) chip.Text=text;stroke.Color=color;chip.Visible=true end

-- Pager marker over the target room, only for the holder.
local marker=Instance.new('BillboardGui');marker.Name='PagerMarker';marker.AlwaysOnTop=true;marker.Size=UDim2.fromOffset(170,44);marker.LightInfluence=0;marker.MaxDistance=1e5;marker.Enabled=false
local markerText=Instance.new('TextLabel');markerText.Size=UDim2.fromScale(1,1);markerText.BackgroundTransparency=1;markerText.Font=Enum.Font.GothamBlack;markerText.TextScaled=true
markerText.TextColor3=LIME;markerText.TextStrokeTransparency=.3;markerText.Parent=marker
local markerAnchor=Instance.new('Part');markerAnchor.Name='PagerMarkerAnchor';markerAnchor.Anchored=true;markerAnchor.CanCollide=false;markerAnchor.CanQuery=false;markerAnchor.CanTouch=false;markerAnchor.Transparency=1;markerAnchor.Size=Vector3.one
marker.Adornee=markerAnchor;marker.Parent=mapGui

local tugUntil,lastBuzz,lastWhistle=0,nil,nil
player:GetAttributeChangedSignal('PagerBuzzAt'):Connect(function()
 if not leased(player,'PagerUntil') then return end
 tugUntil=os.clock()+TUG_SECONDS;lastBuzz=os.clock()
 pcall(function() HapticService:SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,.6) end)
 task.delay(.3,function() pcall(function() HapticService:SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,0) end) end)
end)
player:GetAttributeChangedSignal('HallPassWhistleAt'):Connect(function() lastWhistle=os.clock() end)

-- The pager tug: a short pull toward the Food Court on each buzz (same bounded velocity write as WetFloorClient).
Run.PreSimulation:Connect(function()
 if os.clock()>=tugUntil or not alive(player) or player:GetAttribute('Hiding') then return end
 local r=rootOf(player);local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid');local target=player:GetAttribute('PagerTargetPos')
 if not r or not h or r.Anchored or h.FloorMaterial==Enum.Material.Air or typeof(target)~='Vector3' then return end
 local d=Vector3.new(target.X-r.Position.X,0,target.Z-r.Position.Z);if d.Magnitude<2 then return end
 local v=r.AssemblyLinearVelocity;local pull=d.Unit*TUG_SPEED
 r.AssemblyLinearVelocity=Vector3.new(v.X+(pull.X-v.X)*.25,v.Y,v.Z+(pull.Z-v.Z)*.25)
end)

Run.Heartbeat:Connect(function()
 local now=os.clock();local live=alive(player);local r=rootOf(player)
 chip.Visible=false
 -- FoodCourtPager
 local paging=live and r and leased(player,'PagerUntil')
 if paging then
  local target=player:GetAttribute('PagerTargetPos');local name=string.upper(player:GetAttribute('PagerTargetName')or'FOOD COURT')
  if typeof(target)=='Vector3' then
   markerAnchor.Position=target+Vector3.new(0,4,0);if not markerAnchor.Parent then markerAnchor.Parent=workspace end
   local dist=math.floor((target-r.Position).Magnitude)
   local floorNote=(math.abs(target.Y-r.Position.Y)>8) and (target.Y>r.Position.Y and '  UPSTAIRS' or '  DOWNSTAIRS') or ''
   markerText.Text=name..'\n'..dist..' studs'..floorNote;marker.Enabled=true
   showChip(('ORDER READY: %s  %ds'):format(name,player:GetAttribute('PagerSecondsLeft')or 0),LIME)
  end
 else marker.Enabled=false end
 local pulse=lastBuzz and math.clamp(1-(now-lastBuzz)/.6,0,1) or 0
 edgeStroke.Transparency=1-pulse*.6
 chip.Rotation=pulse>0 and math.sin(now*60)*3*pulse or 0
 -- HallPass
 if live and leased(player,'HallPassUntil') then
  local state=player:GetAttribute('HallPassState');local left=player:GetAttribute('HallPassLeft')or 0
  if lastWhistle and now-lastWhistle<1 then showChip('NO RUNNING IN THE HALLS!',ORANGE)
  elseif state=='safe' then showChip(('HALL PASS %ds - keep walking'):format(left),MINT)
  elseif state=='room' then showChip(('HALL PASS %ds - works in hallways'):format(left),GREY)
  elseif state=='revoked' then showChip('PASS TAKEN - walk, don\'t run',ORANGE)
  else showChip('TARDY - pass used up',GREY) end
 end
end)

local M={}
function M.Init(batch6)Batch6Client=batch6 end
return M
