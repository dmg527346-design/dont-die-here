-- Round recap card for every mission participant (dead and spectating included).
-- Shows only server-recorded numbers (RecoveryRoundServer 'recap'); tokens are
-- celebrated only after ProgressService confirms the save ('tokens').
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local player=Players.LocalPlayer
local Audio=require(RS:WaitForChild('GameplayAudio'))
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local event=RS:WaitForChild('RoundRecap',math.huge) -- created after the server's map build; no yield warning
local state;repeat state=RS:FindFirstChild('RecoveryRound');if not state then task.wait(.25) end until state

-- Style (project palette) and layout
local PANEL=Color3.fromRGB(22,42,43);local CARD=Color3.fromRGB(31,55,53);local CREAM=Color3.fromRGB(244,236,210)
local GREEN=Color3.fromRGB(167,202,127);local RED=Color3.fromRGB(231,104,96);local GOLD=Color3.fromRGB(246,206,104);local INK=Color3.fromRGB(8,18,22)
local CARD_MAX_W,CARD_MIN_W,CARD_H=520,280,428 -- +24 for the run-save line
local SHOW_DELAY=.6
local CUTSCENE_WAIT=9
local COUNT_SECONDS=.9

local shown,tokens={}, {}
local current
local RankCatalog=require(RS:WaitForChild('RankCatalog'))
local rrPending,masteryMoved,questState
local RR_EXTRA_H,RR_PANEL_H=142,128
local RR_PANEL=Color3.fromRGB(16,14,24)
local BONUS_NAMES={daily='DAILY 1.5x',streak='STREAK',friends='FRIENDS',carry='CARRY'}
local drawRank

local function font(o,size,minSize)
 o.Font=Enum.Font.FredokaOne;o.TextScaled=true
 local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=size;c.MinTextSize=minSize or 9;c.Parent=o
end
local function label(parent,props,size)
 local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.TextColor3=CREAM;t.TextXAlignment=Enum.TextXAlignment.Left
 for k,v in props do t[k]=v end;font(t,size or 18);t.Parent=parent;return t
end
local function corner(o,r) local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,r or 14);c.Parent=o end
local function stroke(o,color,th) local s=Instance.new('UIStroke');s.Color=color or INK;s.Thickness=th or 2;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=o;return s end
local function clock(s) return ('%d:%02d'):format(s//60,s%60) end

-- Listen before mission remotes exist: quest updates can arrive during lobby play.
local function receiveQuests(s)
 if type(s)~='table' or type(s.masteries)~='table' then return end
 if questState and tonumber(s.rev) and tonumber(questState.rev) and s.rev<questState.rev then return end
 local before={}
 if questState and type(questState.masteries)=='table' then for _,m in questState.masteries do before[m.id]=m.count end end
 local preferred=type(s.masteryLast)=='table' and s.masteryLast.id
 for _,m in s.masteries do
  if before[m.id] and (tonumber(m.count)or 0)>(tonumber(before[m.id])or 0) then
   if not masteryMoved or m.id==preferred then masteryMoved=m end
  elseif masteryMoved and masteryMoved.id==m.id then masteryMoved=m end
 end
 questState=s
 if current and drawRank then drawRank(current) end
end
task.spawn(function()
 local folder=RS:WaitForChild('Quests',math.huge)
 local changed=folder:WaitForChild('StateChanged',math.huge)
 if changed:IsA('RemoteEvent') then changed.OnClientEvent:Connect(receiveQuests) end
 local get=folder:WaitForChild('GetState',math.huge)
 if get:IsA('RemoteFunction') then
  local ok,res=pcall(function()return get:InvokeServer()end)
  if ok and type(res)=='table' and res.ok then receiveQuests(res.state) end
 end
end)

drawRank=function(c)
 local payload=c.rr
 local box=c.ui.card:FindFirstChild('RankRating')
 if not payload then return end
 if box then box:Destroy() end
 local rr=math.max(0,tonumber(payload.rr)or 0)
 local before=math.max(0,tonumber(payload.before)or rr)
 local info=RankCatalog.Get(rr)
 local lo,hi=RankCatalog.Progress(rr)
 local color=info.color
 local delta=tonumber(payload.delta)or (rr-before)
 box=Instance.new('Frame');box.Name='RankRating';box.Position=UDim2.fromOffset(16,346)
 box.Size=UDim2.new(1,-32,0,RR_PANEL_H);box.BackgroundColor3=RR_PANEL;box.BorderSizePixel=0;box.Parent=c.ui.card
 corner(box,12);local rankRim=stroke(box,color,2);rankRim.Transparency=payload.pending and .45 or 0
 local rrText=payload.protected and 'RANK PROTECTED' or ('%+d RR'):format(delta)
 if payload.pending and not payload.protected then rrText..=' if nobody revives' end
 label(box,{Name='Delta',Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-24,0,32),Text=rrText,TextColor3=color,TextTransparency=payload.pending and .3 or 0},27)
 local chips=Instance.new('Frame');chips.Name='Bonuses';chips.BackgroundTransparency=1;chips.Position=UDim2.fromOffset(12,42);chips.Size=UDim2.new(1,-24,0,18);chips.Parent=box
 local layout=Instance.new('UIListLayout');layout.FillDirection=Enum.FillDirection.Horizontal;layout.Padding=UDim.new(0,5);layout.Parent=chips
 for _,key in type(payload.bonuses)=='table' and payload.bonuses or {} do
  if BONUS_NAMES[key] then
   local chip=label(chips,{Name=tostring(key),Size=UDim2.new(.24,-4,1,0),Text=BONUS_NAMES[key],TextXAlignment=Enum.TextXAlignment.Center,TextColor3=color},12)
   chip.BackgroundColor3=color;chip.BackgroundTransparency=.88;corner(chip,5)
  end
 end
 local nextAt=tonumber(payload.nextAt)or hi
 local nextRank=payload.nextRank or (hi and RankCatalog.Get(hi).name)
 label(box,{Name='NextRank',Position=UDim2.fromOffset(12,64),Size=UDim2.new(1,-24,0,18),Text=nextAt and (math.max(0,math.ceil(nextAt-rr))..' RR to '..tostring(nextRank)) or 'LEGEND - HIGHEST RANK',TextXAlignment=Enum.TextXAlignment.Right},14)
 local back=Instance.new('Frame');back.Name='Progress';back.Position=UDim2.fromOffset(12,86);back.Size=UDim2.new(1,-24,0,8);back.BorderSizePixel=0;back.BackgroundColor3=Color3.fromRGB(48,44,60);back.Parent=box;corner(back,4)
 local fill=Instance.new('Frame');fill.Name='Fill';fill.BorderSizePixel=0;fill.BackgroundColor3=Color3.new(1,1,1);fill.BackgroundTransparency=payload.pending and .35 or 0;fill.Parent=back;corner(fill,4)
 local span=hi and math.max(1,hi-lo)or 1
 local start=hi and math.clamp((before-lo)/span,0,1)or 1
 local finish=hi and math.clamp((rr-lo)/span,0,1)or 1
 fill.Size=UDim2.fromScale(start,1)
 TweenService:Create(fill,TweenInfo.new(.9,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromScale(finish,1)}):Play()
 local mastery=masteryMoved
 label(box,{Name='Mastery',Position=UDim2.fromOffset(12,102),Size=UDim2.new(1,-24,0,18),Text=mastery and (string.upper(tostring(mastery.name))..' '..tostring(mastery.count)..'/'..tostring(mastery.nextTarget)) or '',TextColor3=CREAM},14)
 local height=CARD_H+RR_EXTRA_H
 c.ui.card.Size=UDim2.new(c.ui.card.Size.X.Scale,c.ui.card.Size.X.Offset,0,height)
 local cam=workspace.CurrentCamera;local vp=cam and cam.ViewportSize or Vector2.new(1280,720)
 local reserve=(c.recap.outcome~='Won' and vp.Y<500)and 144 or 0
 c.ui.card:FindFirstChildOfClass('UIScale').Scale=math.min(1,(vp.Y-56-reserve)/height)*(vp.Y<500 and .85 or 1) -- phones: a bit smaller so it all fits
end
task.spawn(function()
 local remote=RS:WaitForChild('RankEvent',math.huge)
 if not remote:IsA('RemoteEvent')then return end
 remote.OnClientEvent:Connect(function(kind,payload)
  if kind~='rr' or type(payload)~='table' then return end
  rrPending={data=payload,at=os.clock()}
  if current then current.rr=payload;drawRank(current)end
 end)
end)

local function build(recap)
 local gui=Instance.new('ScreenGui');gui.Name='RoundRecap';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=960;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
 local cam=workspace.CurrentCamera;local vp=cam and cam.ViewportSize or Vector2.new(1280,720)
 local width=math.clamp(vp.X*.9,CARD_MIN_W,CARD_MAX_W)
 -- Short (phone) screens after a team wipe: the revive bar owns the bottom, so the card fits in the space above it.
 local reserve=(recap.outcome~='Won'and vp.Y<500)and 144 or 0
 local area=Instance.new('Frame');area.Name='CardArea';area.BackgroundTransparency=1;area.Size=UDim2.new(1,0,1,-reserve);area.Parent=gui
 local card=Instance.new('Frame');card.Name='Card';card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.5);card.Size=UDim2.fromOffset(width,CARD_H)
 card.BackgroundColor3=PANEL;card.BackgroundTransparency=.04;card.Parent=area;corner(card,16);stroke(card,INK,3)
 local scale=Instance.new('UIScale');scale.Scale=math.min(1,(vp.Y-56-reserve)/CARD_H)*(vp.Y<500 and .85 or 1);scale.Parent=card -- owner 2026-10-29: phones a bit smaller -- fit short phone screens (gems sit just above the card); the comment used to swallow Parent=card
 local won=recap.outcome=='Won'
 local accent=won and GREEN or RED
 local title=won and ('LEVEL '..recap.level..' CLEARED') or recap.reason=='TimeExpired' and 'OUT OF TIME' or 'THE HOUSE WON'
 local sub
 if won then sub=recap.survived and 'You made it to the van.' or 'Your team got you out. Nice save, crew.'
 elseif recap.reason=='TimeExpired' then sub='The doors sealed before the haul was in.'
 else sub='The house resets. You don\'t. Go again.' end
 -- Win gems: cleared / big haul (125% of quota) / nobody went down
 local gemsEarned={true,recap.sold>=recap.quota*1.25,(recap.deaths or 0)==0}
 if won then
  local names={'cleared','big haul','nobody went down'};local got={}
  for i,ok in gemsEarned do if ok then table.insert(got,names[i])end end
  local n=#got;sub=n..'/3  -  '..table.concat(got,', ')
 end
 local titleLabel=label(card,{Name='Title',Position=UDim2.fromOffset(20,14),Size=UDim2.new(1,-40,0,40),Text=title,TextColor3=accent,TextXAlignment=won and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left},34)
 local subLabel=label(card,{Name='Subtitle',Position=UDim2.fromOffset(20,54),Size=UDim2.new(1,-40,0,22),Text=sub,TextColor3=Color3.fromRGB(205,214,196),TextXAlignment=won and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left},18)
 local win
 if won then
  win={}
  -- gold title with a stamp-in scale
  local grad=Instance.new('UIGradient');grad.Rotation=90;grad.Color=ColorSequence.new(Color3.fromRGB(255,240,170),GOLD);grad.Parent=titleLabel;titleLabel.TextColor3=Color3.new(1,1,1)
  win.titleScale=Instance.new('UIScale');win.titleScale.Scale=2.4;win.titleScale.Parent=titleLabel;titleLabel.TextTransparency=1;subLabel.TextTransparency=1;win.sub=subLabel;win.title=titleLabel
  -- dim + slow light rays behind the card
  -- Owner 2026-10-29: the dark layer covers the WHOLE screen. It lives in its own ScreenGui that ignores the safe-area
  -- insets the card uses (on phones the old one stopped short of the edges and the notch), just behind the card.
  local dimGui=Instance.new('ScreenGui');dimGui.Name='RoundRecapDim';dimGui.ResetOnSpawn=false;dimGui.IgnoreGuiInset=true;dimGui.ScreenInsets=Enum.ScreenInsets.None
  dimGui.DisplayOrder=959;dimGui.Parent=game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')
  gui.Destroying:Connect(function()dimGui:Destroy()end)
  local dim=Instance.new('Frame');dim.Name='Dim';dim.Size=UDim2.fromScale(1,1);dim.BackgroundColor3=Color3.new(0,0,0);dim.BackgroundTransparency=1;dim.BorderSizePixel=0;dim.ZIndex=0;dim.Parent=dimGui;win.dim=dim
  local rays=Instance.new('Frame');rays.Name='Rays';rays.AnchorPoint=Vector2.new(.5,.5);rays.Position=UDim2.fromScale(.5,.5);rays.Size=UDim2.fromOffset(10,10);rays.BackgroundTransparency=1;rays.ZIndex=0;rays.Parent=gui;win.rays=rays
  for i=1,8 do
   local ray=Instance.new('Frame');ray.AnchorPoint=Vector2.new(.5,.5);ray.Position=UDim2.fromScale(.5,.5);ray.Size=UDim2.fromOffset(1400,26);ray.Rotation=i*22.5;ray.BackgroundColor3=GOLD;ray.BorderSizePixel=0;ray.BackgroundTransparency=1;ray.ZIndex=0;ray.Parent=rays
   local g=Instance.new('UIGradient');g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.55),NumberSequenceKeypoint.new(1,1)});g.Parent=ray
  end
  -- (this gui is ZIndexBehavior Global: the card and its text stay at 1, above the dim and rays at 0)
  -- three gems riding the top edge of the card
  win.gems={}
  for i=1,3 do
   local gem=Instance.new('Frame');gem.Name='Gem'..i;gem.AnchorPoint=Vector2.new(.5,.5);gem.Position=UDim2.new(.5,(i-2)*56,0,-4);gem.Size=UDim2.fromOffset(30,30);gem.Rotation=45
   gem.BackgroundColor3=Color3.fromRGB(40,52,50);gem.BorderSizePixel=0;gem.ZIndex=5;gem.Parent=card;corner(gem,6);local st=stroke(gem,INK,3)
   local sc=Instance.new('UIScale');sc.Scale=1;sc.Parent=gem
   win.gems[i]={frame=gem,scale=sc,earned=gemsEarned[i],lit=false}
  end
  -- leave room above the card for the gems on short screens
 end
 -- Haul vs quota with a bar
 local haul=Instance.new('Frame');haul.Name='Haul';haul.Position=UDim2.fromOffset(16,86);haul.Size=UDim2.new(1,-32,0,64);haul.BackgroundColor3=CARD;haul.Parent=card;corner(haul,12)
 local haulText=label(haul,{Name='Amount',Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-24,0,28),Text=''},24)
 local barBack=Instance.new('Frame');barBack.Position=UDim2.new(0,12,1,-20);barBack.Size=UDim2.new(1,-24,0,10);barBack.BackgroundColor3=INK;barBack.Parent=haul;corner(barBack,5)
 local bar=Instance.new('Frame');bar.Size=UDim2.fromScale(0,1);bar.BackgroundColor3=accent;bar.Parent=barBack;corner(bar,5)
 -- Stat rows
 local rows={
  {'Items sold',recap.items},
  {'Time',recap.seconds,clock},
  {'Team',recap.team,function(v) return v..(v==1 and ' player' or ' players')..' · '..recap.survivors..' standing' end},
 }
 if recap.deaths>0 or recap.revives>0 then table.insert(rows,{'Close calls',recap.deaths,function(v) return v..(v==1 and ' down' or ' downs')..' · '..recap.revives..(recap.revives==1 and ' revive' or ' revives') end}) end
 local counters={}
 for i,row in rows do
  local y=158+(i-1)*28
  label(card,{Name='Stat'..i,Position=UDim2.fromOffset(24,y),Size=UDim2.new(.45,-24,0,24),Text=row[1],TextColor3=Color3.fromRGB(176,190,170)},17)
  local value=label(card,{Name='Value'..i,Position=UDim2.new(.45,0,0,y),Size=UDim2.new(.55,-24,0,24),Text='',TextXAlignment=Enum.TextXAlignment.Right},18)
  table.insert(counters,{label=value,target=row[2],format=row[3],name=card:FindFirstChild('Stat'..i)})
 end
 -- Tokens
 local tokenBox=Instance.new('Frame');tokenBox.Name='Tokens';tokenBox.AnchorPoint=Vector2.new(.5,0);tokenBox.Position=UDim2.new(.5,0,0,276);tokenBox.Size=UDim2.new(1,-32,0,62)
 tokenBox.BackgroundColor3=CARD;tokenBox.Parent=card;corner(tokenBox,12);local tokenStroke=stroke(tokenBox,GOLD,2);tokenStroke.Transparency=.6
 local tokenText=label(tokenBox,{Name='Amount',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.42),Size=UDim2.new(1,-24,0,32),TextXAlignment=Enum.TextXAlignment.Center,TextColor3=GOLD,Text=''},28)
 local tokenNote=label(tokenBox,{Name='Note',AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-4),Size=UDim2.new(1,-24,0,16),TextXAlignment=Enum.TextXAlignment.Center,TextColor3=Color3.fromRGB(190,198,180),Text=''},14)
 -- Next goal and countdown
 local nextText
 local MAP_SHORT={Mansion='MANSION',Dungeon='DUNGEON',Hospital='HOSPITAL',Hotel='HOTEL',School='SCHOOL'} -- ForecastBobble teaser (WorldA)
 if won then nextText='NEXT: Level '..(recap.level+1)..(type(recap.nextMapKind)=='string'and(' · '..(MAP_SHORT[recap.nextMapKind]or recap.nextMapKind:upper())..(recap.nextMapNew and' (NEW)'or''))or'')..' · quota $'..recap.nextQuota
 else nextText='Best level: '..math.max(player:GetAttribute('HighestLevel') or 0,recap.level-1)..' · New run starts at level 1' end
 label(card,{Name='Next',Position=UDim2.new(0,20,1,-56),Size=UDim2.new(1,-40,0,22),Text=nextText,TextColor3=CREAM,TextXAlignment=Enum.TextXAlignment.Center},18)
 -- Run save: chances left after this round (the server lowers it on a failed run).
 local saveName=state:GetAttribute('RunSaveName')
 if saveName then
  local left=state:GetAttribute('RunSaveChances')or 2
  local deleted=state:GetAttribute('RunSaveDeleted')==true
  local fresh=state:GetAttribute('RunSaveNew')==true
  local line=fresh and('All 2 chances used  -  NEW SAVE "'..saveName..'" starts at level 1')or deleted and('SAVE "'..saveName..'" DELETED  -  all 2 chances used')
   or(won and('Save "'..saveName..'"  -  '..left..'/2 chances left')or('Save "'..saveName..'" kept  -  '..left..'/2 chances left'))
  label(card,{Name='RunSave',Position=UDim2.new(0,20,1,-82),Size=UDim2.new(1,-40,0,20),Text=line,TextColor3=fresh and GOLD or deleted and RED or(left<=1 and GOLD or GREEN),TextXAlignment=Enum.TextXAlignment.Center},16)
 end
 local countdown=label(card,{Name='Countdown',Position=UDim2.new(0,20,1,-30),Size=UDim2.new(1,-40,0,18),Text='',TextColor3=Color3.fromRGB(150,165,150),TextXAlignment=Enum.TextXAlignment.Center},14)
 gui.Parent=player:WaitForChild('PlayerGui')
 return {win=win,gui=gui,card=card,haulText=haulText,bar=bar,counters=counters,tokenBox=tokenBox,tokenText=tokenText,tokenNote=tokenNote,tokenStroke=tokenStroke,countdown=countdown}
end

local function close()
 if not current then return end
 local c=current;current=nil
 if c.render then c.render:Disconnect() end
 local t=TweenService:Create(c.ui.card,TweenInfo.new(.25),{Position=UDim2.fromScale(.5,.56)});t:Play()
 for _,o in c.ui.gui:GetDescendants() do if o:IsA('TextLabel') then TweenService:Create(o,TweenInfo.new(.25),{TextTransparency=1}):Play() elseif o:IsA('Frame') then TweenService:Create(o,TweenInfo.new(.25),{BackgroundTransparency=1}):Play() end end
 task.delay(.3,function() c.ui.gui:Destroy() end)
end

local function celebrate(c,confirm)
 if c.celebrated then return end
 c.celebrated=true
 c.tokenFrom=os.clock();c.tokenTarget=confirm.earned;c.tokenBalance=confirm.balance
 if confirm.earned>0 then
  Audio.Play('QuotaMet')
  c.ui.tokenStroke.Transparency=0
  local s=Instance.new('UIScale');s.Scale=1;s.Parent=c.ui.tokenBox
  TweenService:Create(s,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.12}):Play()
  task.delay(.2,function() TweenService:Create(s,TweenInfo.new(.35,Enum.EasingStyle.Quad),{Scale=1}):Play() end)
  -- A short spray of sparks from the token box.
  for i=1,14 do
   local spark=Instance.new('Frame');spark.Size=UDim2.fromOffset(6,6);spark.AnchorPoint=Vector2.new(.5,.5);spark.Position=UDim2.fromScale(.5,.5);spark.BackgroundColor3=i%2==0 and GOLD or CREAM;spark.Parent=c.ui.tokenBox;corner(spark,3)
   local a=math.rad(i*360/14);local r=90+math.random()*50
   local tw=TweenService:Create(spark,TweenInfo.new(.7,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(.5,math.cos(a)*r,.5,math.sin(a)*r*.5),BackgroundTransparency=1})
   tw:Play();task.delay(.75,function() spark:Destroy() end)
  end
 end
end

local function show(recap)
 close()
 local ui=build(recap)
 local c:any={recap=recap,ui=ui,started=os.clock()} -- celebrate() adds celebrated/tokenFrom/... later
 current=c
 if rrPending and os.clock()-rrPending.at<30 then c.rr=rrPending.data;drawRank(c)end
 ui.card.Position=UDim2.fromScale(.5,.56)
 TweenService:Create(ui.card,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5)}):Play()
 Audio.Play(recap.outcome=='Won' and 'RoundWin' or 'UiOpen')
 local win=ui.win
 if win then
  -- 1) dim in, 2) title stamps down with a flash, 3) confetti, 4) stats tick in one by one, 5) gems light up
  TweenService:Create(win.dim,TweenInfo.new(.5),{BackgroundTransparency=.45}):Play()
  for _,ray in win.rays:GetChildren()do TweenService:Create(ray,TweenInfo.new(.8),{BackgroundTransparency=.82}):Play()end
  task.delay(.15,function()
   if not ui.gui.Parent then return end
   win.title.TextTransparency=0
   TweenService:Create(win.titleScale,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
   local flash=Instance.new('Frame');flash.Size=UDim2.fromScale(1,1);flash.BackgroundColor3=Color3.new(1,1,1);flash.BackgroundTransparency=.55;flash.BorderSizePixel=0;flash.ZIndex=1;flash.Parent=ui.gui
   TweenService:Create(flash,TweenInfo.new(.5),{BackgroundTransparency=1}):Play();task.delay(.55,function()flash:Destroy()end)
   TweenService:Create(win.sub,TweenInfo.new(.4),{TextTransparency=0}):Play()
   local colors={GOLD,CREAM,GREEN,Color3.fromRGB(190,150,255)}
   local vp=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
   for i=1,46 do
    local bit=Instance.new('Frame');bit.Size=UDim2.fromOffset(math.random(6,11),math.random(10,16));bit.AnchorPoint=Vector2.new(.5,.5);bit.BorderSizePixel=0;bit.ZIndex=6
    bit.BackgroundColor3=colors[i%#colors+1];bit.Rotation=math.random(0,360);bit.Position=UDim2.new(.5,math.random(-60,60),.38,0);bit.Parent=ui.gui
    local tx=math.random(-math.floor(vp.X*.45),math.floor(vp.X*.45));local ty=math.random(math.floor(vp.Y*.25),math.floor(vp.Y*.6))
    local t=1.4+math.random()*1.1
    TweenService:Create(bit,TweenInfo.new(t,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(.5,tx,.38,ty),Rotation=bit.Rotation+math.random(-540,540),BackgroundTransparency=1}):Play()
    task.delay(t+.05,function()bit:Destroy()end)
   end
  end)
  for i,counter in ui.counters do
   counter.label.TextTransparency=1;if counter.name then counter.name.TextTransparency=1 end
   task.delay(.7+i*.22,function()
    if not ui.gui.Parent then return end
    TweenService:Create(counter.label,TweenInfo.new(.25),{TextTransparency=0}):Play();if counter.name then TweenService:Create(counter.name,TweenInfo.new(.25),{TextTransparency=0}):Play()end
    Audio.Play('UiClick')
   end)
  end
  local gemAt=.9+#ui.counters*.22+.35
  for i,gem in win.gems do
   task.delay(gemAt+(i-1)*.38,function()
    if not ui.gui.Parent or not gem.earned then return end
    gem.frame.BackgroundColor3=i==1 and GREEN or GOLD;gem.scale.Scale=1.6
    TweenService:Create(gem.scale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
    Audio.Play(i==3 and 'QuotaMet' or 'UiClick')
   end)
  end
 end
 local lastTick=0
 c.render=Run.RenderStepped:Connect(function(dt)
  if ui.win then ui.win.rays.Rotation+=dt*6 end
  local a=math.clamp((os.clock()-c.started-.25)/COUNT_SECONDS,0,1);local e=1-(1-a)^3
  ui.haulText.Text=('Recovered  $%d  /  $%d'):format(math.floor(recap.sold*e+.5),recap.quota)
  ui.bar.Size=UDim2.fromScale(math.clamp(recap.sold*e/math.max(1,recap.quota),0,1),1)
  for _,counter in ui.counters do local v=math.floor(counter.target*e+.5);counter.label.Text=counter.format and counter.format(v) or tostring(v) end
  if a<1 and os.clock()-lastTick>.09 then lastTick=os.clock();Audio.Play('UiClick') end
  -- Tokens: server-confirmed only.
  local confirm=tokens[recap.id]
  if recap.outcome=='Won' and recap.tokensExpected>0 then
   if confirm and a>=1 then
    celebrate(c,confirm)
    local t=math.clamp((os.clock()-c.tokenFrom)/COUNT_SECONDS,0,1);local te=1-(1-t)^3
    if confirm.duplicate then ui.tokenText.Text='TOKENS ALREADY SAVED';ui.tokenNote.Text='Balance '..confirm.balance
    else ui.tokenText.Text='+'..math.floor(confirm.earned*te+.5)..' TOKENS';ui.tokenNote.Text='Saved · balance '..math.floor(confirm.balance-confirm.earned+confirm.earned*te+.5) end
   else ui.tokenText.Text='+'..recap.tokensExpected..' TOKENS';ui.tokenText.TextTransparency=.55;ui.tokenNote.Text='Saving your reward...' end
   if confirm and a>=1 then ui.tokenText.TextTransparency=0 end
  elseif recap.outcome=='Won' then
   local left=recap.runLevels-(recap.level%recap.runLevels)
   ui.tokenText.Text='NO TOKENS YET';ui.tokenNote.Text='Clear '..left..' more '..(left==1 and 'level' or 'levels')..' to earn '..Shop.TokensPerRun
  else
   ui.tokenText.Text='NO TOKENS THIS TIME';ui.tokenText.TextColor3=Color3.fromRGB(190,190,180);ui.tokenNote.Text='Clear a level to earn '..Shop.TokensPerRun..' tokens'
  end
  local ends=state:GetAttribute('TransitionEnds')
  if ends then
   local s=math.max(0,math.ceil(ends-workspace:GetServerTimeNow()))
   local teaser='' -- ForecastBobble (WorldA): the coming omen / van sale on the countdown line
   if recap.outcome=='Won'then
    local OMEN_TITLES={Adrenaline='ADRENALINE RUSH',Untouchable='UNTOUCHABLE',Hush='THE HUSH',Visitor='THE VISITOR',OneKind='ONE OF A KIND',Valued='VALUED LOOT',SlayerSale='SLAYER SALE',DoubleTokens='DOUBLE TOKENS',DimBatteries='DIM BATTERIES',HeavyQuota='HEAVY QUOTA',Restless='RESTLESS'}
    local bad={DimBatteries=true,HeavyQuota=true,Restless=true}
    if type(recap.nextOmen)=='string'then teaser='Omen: '..(OMEN_TITLES[recap.nextOmen]or recap.nextOmen)..' · ';ui.countdown.TextColor3=bad[recap.nextOmen]and Color3.fromRGB(255,166,84)or Color3.fromRGB(110,226,140)
    elseif recap.level+1==2 then teaser='Van sale 25% off · ';ui.countdown.TextColor3=Color3.fromRGB(110,226,140)end
   end
   ui.countdown.Text=teaser..(recap.outcome=='Won'and'next level in 'or'New run in ')..s..'s'
  end
 end)
end

event.OnClientEvent:Connect(function(kind,payload)
 if type(payload)~='table' then return end
 if kind=='tokens' and type(payload.recapId)=='string' then
  tokens[payload.recapId]=payload
 elseif kind=='recap' and type(payload.id)=='string' and not shown[payload.id] then
  shown[payload.id]=true
  task.spawn(function()
   task.wait(SHOW_DELAY)
   -- After a team wipe, let the monster cutscene finish first.
   local waited=0
   if payload.reason=='TeamWipe' then
    -- The cutscene starts after this player's jumpscare; wait for it to begin, then end.
    while not player.PlayerGui:FindFirstChild('MonsterWinCutscene') and waited<5.5 do waited+=task.wait(.1) end
    waited=0
   end
   while player.PlayerGui:FindFirstChild('MonsterWinCutscene') and waited<CUTSCENE_WAIT do waited+=task.wait(.1) end
   -- A rank-up banner plays first (RankUpClient); the recap waits for it so the two never overlap.
   waited=0
   while player:GetAttribute('RankUpShowing') and waited<6 do waited+=task.wait(.1) end
   if state:GetAttribute('Phase')==(payload.outcome=='Won' and 'Won' or 'Failed') then show(payload) end
  end)
 end
end)
-- Small in-game tag: which save this run is on and how many chances it has left.
do
 local hud=Instance.new('ScreenGui');hud.Name='RunSaveTag';hud.ResetOnSpawn=false;hud.DisplayOrder=20;hud.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
 local tag=Instance.new('TextLabel');tag.Name='Tag';tag.AnchorPoint=Vector2.new(1,0);tag.Position=UDim2.new(1,-12,0,8);tag.Size=UDim2.fromOffset(230,22)
 tag.BackgroundColor3=INK;tag.BackgroundTransparency=.35;tag.TextColor3=CREAM;tag.TextXAlignment=Enum.TextXAlignment.Center;font(tag,15,8);corner(tag,8);tag.Parent=hud
 hud.Parent=player:WaitForChild('PlayerGui')
  -- Sits just below the quota bar (same right-hand position), following its real height on every screen,
  -- or below the mastery card (QuestLogClient MasteryHud) when that card is showing under the quota bar.
  game:GetService('RunService').Heartbeat:Connect(function()
   local quota=player.PlayerGui:FindFirstChild('RecoveryQuota');local panel=quota and quota:FindFirstChild('QuotaPanel')
   local y=8
   if panel and panel.AbsoluteSize.Y>0 then y=math.floor(panel.AbsolutePosition.Y-hud.AbsolutePosition.Y+panel.AbsoluteSize.Y+6)end
   local mh=player.PlayerGui:FindFirstChild('MasteryHud');local card=mh and mh.Enabled and mh:FindFirstChild('Card')
   if card and card.Visible and card.AbsoluteSize.Y>0 then y=math.max(y,math.floor(card.AbsolutePosition.Y-hud.AbsolutePosition.Y+card.AbsoluteSize.Y+6))end
   if tag.Position.Y.Offset~=y then tag.Position=UDim2.new(1,-12,0,y)end
  end)
 local function refresh()
  local name=state:GetAttribute('RunSaveName');local left=state:GetAttribute('RunSaveChances')or 2
  hud.Enabled=name~=nil and player:GetAttribute('MissionActive')==true
  if name then
   local deleted=state:GetAttribute('RunSaveDeleted')==true
   local fresh=state:GetAttribute('RunSaveNew')==true
   tag.Text=deleted and('SAVE DELETED')or fresh and('NEW SAVE: '..name..'  |  '..left..'/2 chances')or('SAVE: '..name..'  |  '..left..'/2 chances')
   tag.TextColor3=deleted and RED or fresh and GREEN or(left<=1 and GOLD or CREAM)
  end
 end
 for _,a in {'RunSaveName','RunSaveChances','RunSaveDeleted','RunSaveNew'}do state:GetAttributeChangedSignal(a):Connect(refresh)end
 player:GetAttributeChangedSignal('MissionActive'):Connect(refresh);refresh()
end
state:GetAttributeChangedSignal('Phase'):Connect(function()
 local phase=state:GetAttribute('Phase')
 if phase~='Won' and phase~='Failed' then close();rrPending=nil end
 if phase=='Deploying' then masteryMoved=nil end
end)

-- RoadTripStickers (WorldB 2026-10-27): on a clear the newest sticker (server-drawn with Fresh=true) slaps onto the van board.
state:GetAttributeChangedSignal('Phase'):Connect(function()
 if state:GetAttribute('Phase')~='Won'then return end
 task.delay(.4,function()
  local camp=workspace:FindFirstChild('RecoveryCamp');local board=camp and camp:FindFirstChild('RoadTripStickers',true)
  local gui=board and board:FindFirstChild('Stickers',true);if not gui then return end
  for _,f in gui:GetChildren()do
   if f:IsA('Frame')and f:GetAttribute('Fresh')and not f:FindFirstChild('SlapScale')then
    local s=Instance.new('UIScale');s.Name='SlapScale';s.Scale=2.2;s.Parent=f;f.BackgroundTransparency=1
    TweenService:Create(s,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
    TweenService:Create(f,TweenInfo.new(.25),{BackgroundTransparency=0}):Play()
    local face=gui.Parent;if face and face:IsA('BasePart')then Audio.Play('PresentOpen',face)end
   end
  end
 end)
end)
