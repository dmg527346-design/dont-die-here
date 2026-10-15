-- Quest Log screen (QUEST_LOG_PLAN section 9). Presentation only: the server (ReplicatedStorage.Quests) owns
-- progress, rolls, claims and grants. This script shows the state, asks to claim and plays the reveal.
-- Open it from anywhere on the client:  PlayerGui.QuestLog.Open:Fire('daily'|'weekly'|'achievements')
-- The van terminal prompt (QuestsRewardsPrompt) and the lobby QUESTS button both use that event.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Tween=game:GetService('TweenService')
local Run=game:GetService('RunService')
local GS=game:GetService('GuiService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local PPS=game:GetService('ProximityPromptService')
local SoundService=game:GetService('SoundService')
local Http=game:GetService('HttpService')
local p=Players.LocalPlayer
local UI=require(RS:WaitForChild('NeonUI'))
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local colors=UI.Color

-- Look ------------------------------------------------------------------------------------------
local MAX_W,MAX_H,MARGIN=900,520,12
local ORANGE,PURPLE=Color3.fromRGB(255,140,40),Color3.fromRGB(150,80,255)
local READY_GOLD=Color3.fromRGB(255,208,86)
local DONE_GREEN=Color3.fromRGB(52,222,104)
-- 3D quest icons (models/questcos/icons/<key>_512.png). Filled in after upload; empty = letter badge.
local ICONS={
 pickup='rbxassetid://84560132411318',selling='rbxassetid://93403394110277',locked_room='rbxassetid://102076404075662',hiding='rbxassetid://72746676117383',chase='rbxassetid://97997479722518',revive='rbxassetid://97437381948321',secrets='rbxassetid://121191513340922',no_death='rbxassetid://96152066675808',maps='rbxassetid://88665940601534',party='rbxassetid://93311567878566',boat='rbxassetid://137827771884096',achievements='rbxassetid://91859657031763',weekly_chest='rbxassetid://113977879393115',daily='rbxassetid://82192372407203',quests='rbxassetid://117099885163223',
}
local REWARD_ICON={tokens='rbxassetid://116174307880260',revives='rbxassetid://122888744965333'}
local TABS={
 {key='daily',label='TODAY',icon='daily'},
 {key='weekly',label='THIS WEEK',icon='weekly_chest'},
 {key='achievements',label='LIFETIME GOALS',icon='achievements'},
 {key='event',label='HALLOWEEN',icon='quests',event=true}, -- hidden unless state.event.enabled (EventConfig)
}
local TAB_SUB={
 daily='Finish a goal, then press CLAIM REWARD to collect it. New goals every day.',
 weekly='Finish a goal, then press CLAIM REWARD. Finish 4 to open the Weekly Chest.',
 achievements='Goals that never reset. Each has 5 stages; stage 5 gives a title.',
 event='Halloween event! Earn Candy Corn and spend it at the pumpkin cart.',
}

local ROMAN={'I','II','III','IV','V'}

-- Sounds: reuse the van reward set when it exists (VanRewardsClient makes it), so claims sound the same.
local function sfx(name,pitch)
 local folder=SoundService:FindFirstChild('VanRewardSounds');local base=folder and folder:FindFirstChild(name)
 if not base or not base:IsA('Sound')then return end
 local sd=base.IsPlaying and base:Clone()or base
 if sd~=base then sd.Parent=folder;sd.Ended:Once(function()sd:Destroy()end)end
 sd.PlaybackSpeed=pitch or 1;sd.TimePosition=0;sd:Play()
end

-- Remotes and state ------------------------------------------------------------------------------
local function remote(name)
 local f=RS:FindFirstChild('Quests');return f and f:FindFirstChild(name)
end
local MOCK=Run:IsStudio()and script:GetAttribute('Mock')==true and RS:FindFirstChild('Quests')==nil
local state,timeOffset=nil,0
local function eventOn()return state~=nil and type(state.event)=='table'and state.event.enabled==true end
local function serverNow()return os.time()+timeOffset end
local readyBefore={} -- quest keys that were ready in the last state (for the completion toast)
local onState -- forward: redraw hook

local function keyOf(tab,q)return tab..':'..tostring(q.id)end
local function collectReady(s)
 local out={}
 if type(s)~='table'then return out end
 for _,tab in {'daily','weekly'}do
  local t=s[tab];if type(t)=='table'and type(t.quests)=='table'then
   for _,q in t.quests do if q.ready and not q.claimed then out[keyOf(tab,q)]=q end end
  end
 end
 if type(s.achievements)=='table'then for _,a in s.achievements do if a.ready then out['ach:'..tostring(a.id)]=a end end end
 return out
end
local toast -- forward
local function setState(s,fromPush)
 if type(s)~='table'then return end
 -- A slow reply must never roll back a newer push: the server bumps rev on every quest write.
 if state and type(s.rev)=='number'and type(state.rev)=='number'and s.rev<state.rev then return end
 if type(s.serverTime)=='number'then timeOffset=s.serverTime-os.time()end
 local ready=collectReady(s)
 if fromPush and state then
  for k,q in ready do if not readyBefore[k]and q.text then toast(q.text)end end
 end
 readyBefore=ready;state=s
 p:SetAttribute('QuestReadyCount',tonumber(s.readyCount)or 0) -- lobby button badge + van terminal read this
 if onState then onState()end
end

local function mockState()
 local function q(id,text,hint,icon,pr,tg,tok,rev,claimed)
  return {id=id,text=text,hint=hint,icon=icon,progress=pr,target=tg,reward={tokens=tok,revives=rev},ready=pr>=tg and not claimed,claimed=claimed}
 end
 local day=86400
 return {serverTime=os.time(),rev=1,dailyEndsAt=(os.time()//day+1)*day,weeklyEndsAt=(os.time()//day+4)*day,readyCount=3,pinned='d_key_m',
  daily={rerolled=false,quests={
   q('d_pickup_s','Pick up 15 cursed items','Anything you can grab counts.','pickup',15,15,40,0,false),
   q('d_key_m','Unlock a locked room','Locked doors need a key from the same floor.','locked_room',0,1,60,0,false),
   q('d_clear_h','Clear 4 levels','Sell enough to meet the quota, then leave in the van.','maps',1,4,90,0,false)},
   bonus={done=1,target=3,ready=false,claimed=false,reward={tokens=50,revives=1}}},
  weekly={quests={
   q('w_sell','Sell $25,000 of loot','Team sells count for everyone in the van.','selling',25000,25000,150,0,false),
   q('w_hide','Hide in 20 wardrobes','Monsters cannot open them any more.','hiding',20,20,120,0,true),
   q('w_cruise','Clear 3 Cruise levels','The ship comes up in the map rotation.','boat',1,3,160,1,false),
   q('w_party','Clear 5 levels in a party','Two or more players in the run.','party',2,5,140,0,false),
   q('w_secret','Find 3 secrets','Look behind paintings and under beds.','secrets',0,3,150,0,false)},
   chest={done=1,target=4,ready=false,claimed=false,reward={tokens=300,revives=2}}},
  achievements={
   {id='collector',name='Collector',icon='pickup',count=262,tier=1,targets={50,250,1000,3000,10000},rewards={50,100,200,300,500},title='CURSED COLLECTOR',ready=true},
   {id='survivor',name='Survivor',icon='no_death',count=41,tier=1,targets={10,50,150,400,1000},rewards={50,100,200,300,500},title='SEASONED SURVIVOR',ready=false},
   {id='deepdiver',name='Deep Diver',icon='maps',count=8,tier=2,targets={3,5,8,12,20},rewards={50,120,220,350,600},title='ABYSS WALKER',ready=true},
   {id='locksmith',name='Locksmith',icon='locked_room',count=500,tier=5,targets={5,25,75,200,500},rewards={50,100,200,300,500},title='MASTER LOCKSMITH',ready=false},
  },
  mastery={done=1,target=10,ready=false,claimed=false,tag='[Haunted]'}}
end

local function fetch()
 if MOCK then setState(mockState());return true end
 local f=remote('GetState');if not f then return false end
 local ok,res=pcall(function()return f:InvokeServer()end)
 if ok and type(res)=='table'and res.ok then setState(res.state);return true end
 return false
end

-- GUI skeleton -----------------------------------------------------------------------------------
local pg=p:WaitForChild('PlayerGui')
local gui=Instance.new('ScreenGui');gui.Name='QuestLog';gui.DisplayOrder=136;gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Enabled=false;gui.Parent=pg
local openEvent=Instance.new('BindableEvent');openEvent.Name='Open';openEvent.Parent=gui
local backdrop=UI.backdrop(gui,.45)
local holder,plate=UI.plate(gui,'Panel',22)
holder.AnchorPoint=Vector2.new(.5,.5);holder.ZIndex=2
local close=UI.closeButton(holder,'Close',46);close.Position=UDim2.new(1,-6,0,6)

local header=Instance.new('Frame');header.Name='Header';header.BackgroundTransparency=1;header.Parent=plate
local title=UI.text(header,'Title','QUEST LOG',UI.Font.Display,30);UI.outline(title,2);UI.fit(title,18,32)
local titleGrad=Instance.new('UIGradient');titleGrad.Color=ColorSequence.new(ORANGE,PURPLE);titleGrad.Parent=title
local sub=UI.text(header,'Sub','',UI.Font.Body,15,colors.muted);UI.fit(sub,11,15)
local timer=UI.text(header,'Reset','',UI.Font.Bold,15,READY_GOLD);timer.TextXAlignment=Enum.TextXAlignment.Right;UI.fit(timer,11,16)

local tabBar=Instance.new('Frame');tabBar.Name='Tabs';tabBar.BackgroundTransparency=1;tabBar.Parent=plate
local tabList=Instance.new('UIListLayout');tabList.FillDirection=Enum.FillDirection.Horizontal;tabList.Padding=UDim.new(0,8);tabList.SortOrder=Enum.SortOrder.LayoutOrder;tabList.Parent=tabBar
local tabButtons={}

local body=Instance.new('ScrollingFrame');body.Name='Body';body.BackgroundTransparency=1;body.BorderSizePixel=0;body.ScrollBarThickness=6
body.ScrollBarImageColor3=PURPLE;body.AutomaticCanvasSize=Enum.AutomaticSize.Y;body.CanvasSize=UDim2.new();body.ScrollingDirection=Enum.ScrollingDirection.Y
body.Selectable=false;body.Parent=plate
local bodyList=Instance.new('UIListLayout');bodyList.Padding=UDim.new(0,8);bodyList.SortOrder=Enum.SortOrder.LayoutOrder;bodyList.Parent=body
local bodyPad=Instance.new('UIPadding');bodyPad.PaddingTop=UDim.new(0,6);bodyPad.PaddingBottom=UDim.new(0,8);bodyPad.PaddingLeft=UDim.new(0,6);bodyPad.PaddingRight=UDim.new(0,12);bodyPad.Parent=body

local footer=Instance.new('Frame');footer.Name='Footer';footer.BackgroundTransparency=1;footer.Parent=plate
local strip=Instance.new('Frame');strip.Name='Bonus';strip.BackgroundColor3=colors.card;strip.Parent=footer;UI.corner(strip,14)
local stripStroke=UI.stroke(strip,colors.greyDark,2,0)
local stripText=UI.text(strip,'Text','',UI.Font.Bold,16);UI.fit(stripText,11,17)
local stripPips=Instance.new('Frame');stripPips.Name='Pips';stripPips.BackgroundTransparency=1;stripPips.Parent=strip
local pipList=Instance.new('UIListLayout');pipList.FillDirection=Enum.FillDirection.Horizontal;pipList.Padding=UDim.new(0,4);pipList.VerticalAlignment=Enum.VerticalAlignment.Center;pipList.Parent=stripPips
local stripClaim=UI.button(strip,'Claim','CLAIM REWARD','use')
local claimAll=UI.button(footer,'ClaimAll','COLLECT ALL','buy')

local loading=UI.text(plate,'Loading','Loading quests...',UI.Font.Bold,18,colors.muted);loading.TextXAlignment=Enum.TextXAlignment.Center
loading.Size=UDim2.fromScale(1,1);loading.Visible=false;loading.ZIndex=5
local retry=UI.button(plate,'Retry','RETRY','muted');retry.AnchorPoint=Vector2.new(.5,.5);retry.Position=UDim2.new(.5,0,.5,44);retry.Size=UDim2.fromOffset(160,48);retry.Visible=false;retry.ZIndex=6

-- Layout ------------------------------------------------------------------------------------------
local compact=false
local function layout()
 local cam=workspace.CurrentCamera;local view=cam and cam.ViewportSize or Vector2.new(1280,720)
 local inset=gui.AbsoluteSize.Magnitude>0 and gui.AbsoluteSize or view
 compact=inset.Y<430 or inset.X<560
 local w=math.min(MAX_W,inset.X-MARGIN*2-(compact and 0 or 40))
 local h=math.min(MAX_H,inset.Y-MARGIN*2)
 holder.Size=UDim2.fromOffset(w,h);holder.Position=UDim2.fromScale(.5,.5)
 local side=compact and 12 or 20
 local headH=compact and 34 or 70
 close.Position=compact and UDim2.new(1,-30,0,30)or UDim2.new(1,-6,0,6);close.Size=UDim2.fromOffset(compact and 44 or 46,compact and 44 or 46)
 sub.Visible=not compact
 header.Position=UDim2.fromOffset(side,compact and 6 or 10);header.Size=UDim2.new(1,-side*2-40,0,headH)
 title.Position=UDim2.new();title.Size=UDim2.new(.6,0,0,compact and 28 or 38)
 sub.Position=UDim2.fromOffset(0,compact and 28 or 40);sub.Size=UDim2.new(.62,0,0,compact and 18 or 22)
 timer.AnchorPoint=Vector2.new(1,0);timer.Position=UDim2.new(1,compact and -20 or 0,0,compact and 4 or 12);timer.Size=UDim2.new(.38,0,0,22)
 local tabY=(compact and 6 or 10)+headH
 local tabH=compact and 44 or 46
 tabBar.Position=UDim2.fromOffset(side,tabY);tabBar.Size=UDim2.new(1,-side*2-(compact and 46 or 0),0,tabH)
 local shownTabs=0;for _,t in TABS do if not t.event or eventOn()then shownTabs+=1 end end
 for key,b in tabButtons do b.Visible=key~='event'or eventOn();b.Size=UDim2.new(1/math.max(1,shownTabs),-6,1,0)end
 local footH=compact and 58 or 64
 footer.AnchorPoint=Vector2.new(0,1);footer.Position=UDim2.new(0,side,1,-(compact and 8 or 12));footer.Size=UDim2.new(1,-side*2,0,footH)
 local bodyTop=tabY+tabH+8
 body.Position=UDim2.fromOffset(side-6,bodyTop);body.Size=UDim2.new(1,-side*2+12,1,-bodyTop-footH-(compact and 14 or 20))
 local allW=compact and 140 or 190
 claimAll.AnchorPoint=Vector2.new(1,.5);claimAll.Position=UDim2.fromScale(1,.5);claimAll.Size=UDim2.new(0,allW,1,-6)
 strip.Position=UDim2.new();strip.Size=UDim2.new(1,-allW-10,1,0)
 stripText.Position=UDim2.fromOffset(14,0);stripText.Size=UDim2.new(.52,-14,1,0)
 stripPips.AnchorPoint=Vector2.new(0,.5);stripPips.Position=UDim2.new(.54,0,.5,0);stripPips.Size=UDim2.new(.16,0,0,20)
 stripClaim.AnchorPoint=Vector2.new(1,.5);stripClaim.Position=UDim2.new(1,-6,.5,0);stripClaim.Size=UDim2.new(.26,-6,1,-12)
end

-- Small builders -----------------------------------------------------------------------------------
local function iconBadge(parent,key,size)
 local f=Instance.new('Frame');f.Name='Icon';f.Size=UDim2.fromOffset(size,size);f.BackgroundColor3=colors.cardLow;f.Parent=parent;UI.corner(f,math.floor(size*.24))
 local id=ICONS[key or '']
 if id and id~=''then
  local img=Instance.new('ImageLabel');img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.Image=id;img.ScaleType=Enum.ScaleType.Fit;img.Parent=f
 else
  local g=Instance.new('UIGradient');g.Rotation=45;g.Color=ColorSequence.new(PURPLE,ORANGE);g.Parent=f
  local t=UI.text(f,'Glyph',string.upper(string.sub(tostring(key or '?'),1,1)),UI.Font.Display,math.floor(size*.5));t.Size=UDim2.fromScale(1,1)
  t.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(t,2)
 end
 return f
end
local function rewardChips(parent,reward,height)
 local row=Instance.new('Frame');row.Name='Reward';row.BackgroundTransparency=1;row.AutomaticSize=Enum.AutomaticSize.X;row.Size=UDim2.fromOffset(0,height);row.Parent=parent
 local tag=UI.text(row,'Label','REWARD',UI.Font.Bold,math.floor(height*.42),READY_GOLD);tag.AutomaticSize=Enum.AutomaticSize.X;tag.Size=UDim2.fromOffset(0,height);tag.LayoutOrder=0
 local l=Instance.new('UIListLayout');l.FillDirection=Enum.FillDirection.Horizontal;l.Padding=UDim.new(0,6);l.VerticalAlignment=Enum.VerticalAlignment.Center;l.HorizontalAlignment=Enum.HorizontalAlignment.Right;l.Parent=row
 for i,key in {'tokens','revives'}do
  local n=type(reward)=='table'and tonumber(reward[key])or 0
  if n>0 then
   local chip=Instance.new('Frame');chip.Name=key;chip.LayoutOrder=i;chip.BackgroundColor3=colors.pill;chip.AutomaticSize=Enum.AutomaticSize.X;chip.Size=UDim2.fromOffset(0,height);chip.Parent=row
   UI.corner(chip,UDim.new(1,0))
   local cl=Instance.new('UIListLayout');cl.FillDirection=Enum.FillDirection.Horizontal;cl.Padding=UDim.new(0,4);cl.VerticalAlignment=Enum.VerticalAlignment.Center;cl.Parent=chip
   local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,4);pad.PaddingRight=UDim.new(0,10);pad.Parent=chip
   local img=Instance.new('ImageLabel');img.BackgroundTransparency=1;img.Size=UDim2.fromOffset(height-4,height-4);img.Image=REWARD_ICON[key];img.Parent=chip
   local t=UI.text(chip,'N',tostring(n),UI.Font.Display,math.floor(height*.62));t.AutomaticSize=Enum.AutomaticSize.X;t.Size=UDim2.fromOffset(0,height);t.LayoutOrder=2;UI.outline(t,1.5)
  end
 end
 return row
end
local function progressBar(parent,frac,complete)
 local bar=Instance.new('Frame');bar.Name='Bar';bar.BackgroundColor3=colors.cardLow;bar.Parent=parent;UI.corner(bar,UDim.new(1,0))
 local fill=Instance.new('Frame');fill.Name='Fill';fill.BackgroundColor3=Color3.new(1,1,1);fill.Size=UDim2.fromScale(math.clamp(frac,0,1),1);fill.Parent=bar
 UI.corner(fill,UDim.new(1,0))
 local g=Instance.new('UIGradient');g.Color=complete and ColorSequence.new(READY_GOLD,Color3.fromRGB(255,160,40))or ColorSequence.new(PURPLE,ORANGE);g.Parent=fill
 if frac<=0 then fill.Visible=false end
 return bar,fill
end
local function fmtNum(n)
 n=math.floor(tonumber(n)or 0)
 if n>=1e6 then return string.format('%.1fM',n/1e6)elseif n>=1e4 then return string.format('%dk',n//1000)end
 local s=tostring(n);local out=s:reverse():gsub('(%d%d%d)','%1,'):reverse();return(out:gsub('^,',''))
end
local function fmtTime(s)
 s=math.max(0,math.floor(s));local d,h,m=s//86400,(s%86400)//3600,(s%3600)//60
 if d>0 then return string.format('%dd %dh',d,h)elseif h>0 then return string.format('%dh %dm',h,m)end
 return string.format('%dm %ds',m,s%60)
end

-- Pulse on READY rims: one shared loop, only while open.
local pulsing={}
Run.RenderStepped:Connect(function()
 if not gui.Enabled then return end
 local a=(math.sin(os.clock()*4)+1)/2
 for s in pulsing do if s.Parent then s.Transparency=.05+a*.45 else pulsing[s]=nil end end
end)

-- Claim reveal ---------------------------------------------------------------------------------------
local busy=false
local function burst(over,reward)
 -- Rays + sparkle + floating amount over the card that was claimed. Visual only (the server already granted).
 sfx('coins');task.delay(.15,function()sfx('rare')end)
 local fx=Instance.new('Frame');fx.Name='Burst';fx.BackgroundTransparency=1;fx.ZIndex=30
 fx.AnchorPoint=Vector2.new(.5,.5);fx.Size=UDim2.fromOffset(40,40)
 local ap,as=over.AbsolutePosition-plate.AbsolutePosition,over.AbsoluteSize
 fx.Position=UDim2.fromOffset(ap.X+as.X/2,ap.Y+as.Y/2);fx.Parent=plate
 for i=1,10 do
  local ray=Instance.new('Frame');ray.BackgroundColor3=READY_GOLD;ray.BorderSizePixel=0;ray.AnchorPoint=Vector2.new(.5,1)
  ray.Position=UDim2.fromScale(.5,.5);ray.Size=UDim2.fromOffset(6,10);ray.Rotation=i*36;ray.ZIndex=30;ray.Parent=fx;UI.corner(ray,3)
  Tween:Create(ray,TweenInfo.new(.45,Enum.EasingStyle.Quart),{Size=UDim2.fromOffset(4,90),BackgroundTransparency=1}):Play()
 end
 local amount=type(reward)=='table'and tonumber(reward.tokens)or 0
 local revs=type(reward)=='table'and tonumber(reward.revives)or 0
 local words={}
 if amount>0 then table.insert(words,'+'..amount..' TOKENS')end
 if revs>0 then table.insert(words,'+'..revs..' REVIVE')end
 local candy=type(reward)=='table'and tonumber(reward.candyCorn)or 0
 if candy>0 then table.insert(words,'+'..candy..' CANDY CORN')end
 if type(reward)=='table'and type(reward.cosmeticIds)=='table'and #reward.cosmeticIds>0 then table.insert(words,'+ NEW COSMETIC')end
 if type(reward)=='table'and reward.tag then table.insert(words,tostring(reward.tag)..' TAG')end
 local label=UI.text(fx,'Amount',table.concat(words,'  '),UI.Font.Display,26,READY_GOLD)
 label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5);label.Size=UDim2.fromOffset(320,40);label.TextXAlignment=Enum.TextXAlignment.Center;label.ZIndex=31;UI.outline(label,2.5)
 Tween:Create(label,TweenInfo.new(1.1,Enum.EasingStyle.Quad),{Position=UDim2.new(.5,0,.5,-70),TextTransparency=1}):Play()
 task.delay(1.2,function()fx:Destroy()end)
end
local redraw -- forward
local function claim(tab,key,cardFrame)
 if busy then return end
 local f=remote('Claim')
 if not f and not MOCK then return end
 busy=true;p:SetAttribute('VanRewardHold',true)
 local ok,res
 if MOCK then
  ok,res=true,{ok=true,reward={tokens=60},state=state}
  task.wait(.25)
 else
  ok,res=pcall(function()return f:InvokeServer(tab,key)end)
 end
 if ok and type(res)=='table'and res.ok then
  if cardFrame and cardFrame.Parent then burst(cardFrame,res.reward)end
  if res.state then setState(res.state)end
 else
  sfx('cardReady',.7)
  if cardFrame and cardFrame.Parent then
   local note=UI.text(cardFrame,'Error',type(res)=='table'and res.reason or'Could not claim. Try again.',UI.Font.Bold,14,colors.red)
   note.Size=UDim2.new(1,-20,0,18);note.Position=UDim2.new(0,10,1,-20);note.ZIndex=12;task.delay(2.5,function()note:Destroy()end)
  end
  fetch()
 end
 task.delay(1.3,function()p:SetAttribute('VanRewardHold',nil)end)
 busy=false
end
local pendingAll={} -- ClaimAll request id per tab, kept until a definite answer
local function claimAllNow(tab)
 if busy then return end
 local f=remote('ClaimAll');if not f and not MOCK then return end
 busy=true;p:SetAttribute('VanRewardHold',true)
 local ok,res
 if MOCK then ok,res=true,{ok=true,reward={tokens=100},state=state}else
  -- One request id per press: an ambiguous retry of the same press must get the same frozen set back.
  -- Reuse the id until the server gives a definite answer, so a retry after a lost reply replays the same claim.
  pendingAll[tab]=pendingAll[tab]or Http:GenerateGUID(false)
  local requestId=pendingAll[tab]
  ok,res=pcall(function()return f:InvokeServer(tab,requestId)end)
 end
 if ok and type(res)=='table'and res.retry~=true then pendingAll[tab]=nil end
 if ok and type(res)=='table'and res.ok then
  -- Chain short bursts over every ready card, then one summed banner over the button.
  local cards={}
  for _,c in body:GetChildren()do if c:GetAttribute('Ready')then table.insert(cards,c)end end
  for i,c in cards do task.delay((i-1)*.22,function()if c.Parent then burst(c,nil)end end)end
  task.delay(#cards*.22,function()burst(claimAll,res.reward)end)
  if res.state then setState(res.state)end
 else
  sfx('cardReady',.7);fetch()
 end
 task.delay(1.6,function()p:SetAttribute('VanRewardHold',nil)end)
 busy=false
end
local function reroll(key)
 if busy then return end
 local f=remote('Reroll');if not f then return end
 busy=true
 local ok,res=pcall(function()return f:InvokeServer(key)end)
 if ok and type(res)=='table'and res.ok and res.state then setState(res.state)else fetch()end
 busy=false
end
local function pin(id)
 local f=remote('Pin');if not f then return end
 task.spawn(function()
  local ok,res=pcall(function()return f:InvokeServer(id)end)
  if ok and type(res)=='table'and res.ok and res.state then setState(res.state)end
 end)
end

-- Cards ------------------------------------------------------------------------------------------------
local current='daily'
local firstFocus=nil
local function card(order,height)
 local c=Instance.new('Frame');c.Name='Card'..order;c.LayoutOrder=order;c.BackgroundColor3=colors.card;c.Size=UDim2.new(1,0,0,height);c.Parent=body
 UI.corner(c,16)
 local g=Instance.new('UIGradient');g.Rotation=90;g.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(200,200,210));g.Parent=c
 return c
end
local function actionButton(parent,text,kind,width,height)
 local b=UI.button(parent,'Action',text,kind)
 b.AnchorPoint=Vector2.new(1,.5);b.Size=UDim2.fromOffset(width,height);b.Position=UDim2.new(1,-12,.5,0);b.ZIndex=4
 return b
end
local function questCard(tab,q,i,canReroll)
 local h=compact and 70 or 84
 local c=card(i,h)
 local rim=UI.stroke(c,colors.greyDark,2.5,0)
 local iconSize=h-20
 local icon=iconBadge(c,q.icon,iconSize);icon.Position=UDim2.fromOffset(10,10)
 local btnW,btnH=compact and 104 or 128,compact and 44 or 46
 local left=iconSize+22
 local name=UI.text(c,'Name',tostring(q.text or q.id),UI.Font.Bold,compact and 16 or 18);UI.fit(name,12,compact and 16 or 19)
 name.Position=UDim2.fromOffset(left,compact and 6 or 8);name.Size=UDim2.new(1,-left-btnW-170,0,compact and 22 or 24)
 if not compact and q.hint then
  local hint=UI.text(c,'Hint',tostring(q.hint),UI.Font.Body,13,colors.muted);UI.fit(hint,10,13)
  hint.Position=UDim2.fromOffset(left,32);hint.Size=UDim2.new(1,-left-btnW-120,0,16)
 end
 local target=math.max(1,tonumber(q.target)or 1);local progress=math.min(target,tonumber(q.progress)or 0)
 local bar=progressBar(c,progress/target,q.ready or q.claimed)
 bar.Position=UDim2.new(0,left,1,compact and -22 or -24);bar.Size=UDim2.new(1,-left-btnW-120,0,compact and 10 or 12)
 local count=UI.text(c,'Count','Done '..fmtNum(progress)..' of '..fmtNum(target),UI.Font.Bold,13,colors.muted)
 count.AnchorPoint=Vector2.new(0,.5);count.Position=UDim2.new(1,-btnW-110,1,compact and -17 or -18);count.Size=UDim2.fromOffset(90,18)
 local chips=rewardChips(c,q.reward,compact and 24 or 28);chips.AnchorPoint=Vector2.new(1,0);chips.Position=UDim2.new(1,-btnW-22,0,compact and 6 or 10)
 if q.claimed then
  c.BackgroundTransparency=.35;rim.Color=DONE_GREEN;rim.Transparency=.4
  local stamp=UI.text(c,'Stamp','COLLECTED ✓',UI.Font.Display,18,DONE_GREEN);stamp.AnchorPoint=Vector2.new(1,.5);stamp.Position=UDim2.new(1,-16,.5,0)
  stamp.Size=UDim2.fromOffset(btnW,30);stamp.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(stamp,2)
 elseif q.ready then
  c:SetAttribute('Ready',true);rim.Color=READY_GOLD;pulsing[rim]=true
  local b=actionButton(c,'CLAIM REWARD','use',btnW,btnH)
  b.Activated:Connect(function()claim(tab,q.claimKey or q.id,c)end)
  firstFocus=firstFocus or b
 elseif canReroll then
  local b=actionButton(c,'SWAP GOAL','muted',btnW,btnH)
  b:SetAttribute('RerollKey',q.claimKey or q.id)
  b.Activated:Connect(function()reroll(q.claimKey or q.id)end)
 else
  local pinned=state and state.pinned==q.id
  local b=actionButton(c,pinned and'TRACKING'or'TRACK','muted',btnW,btnH)
  if pinned then b.BackgroundColor3=PURPLE end
  b.Activated:Connect(function()pin(not pinned and q.id or nil)end)
 end
 return c
end
local function chainCard(a,i)
 local h=compact and 74 or 92
 local c=card(i,h)
 local rim=UI.stroke(c,colors.greyDark,2.5,0)
 local iconSize=h-20
 local icon=iconBadge(c,a.icon,iconSize);icon.Position=UDim2.fromOffset(10,10)
 local left=iconSize+22
 local btnW,btnH=compact and 104 or 128,compact and 44 or 46
 local tier=math.clamp(tonumber(a.tier)or 0,0,5)
 local targets=type(a.targets)=='table'and a.targets or{}
 local nextT=tonumber(targets[math.min(5,tier+1)])or 1
 local name=UI.text(c,'Name',string.upper(tostring(a.name or a.id)),UI.Font.Display,compact and 17 or 20)
 UI.outline(name,1.5);name.Position=UDim2.fromOffset(left,compact and 6 or 8);name.Size=UDim2.new(.45,0,0,compact and 22 or 26)
 -- Five tier pips: filled = claimed, gold = ready to claim.
 local pips=Instance.new('Frame');pips.Name='Tiers';pips.BackgroundTransparency=1;pips.Position=UDim2.new(.45,left,0,compact and 9 or 12);pips.Size=UDim2.fromOffset(130,18);pips.Parent=c
 local pl=Instance.new('UIListLayout');pl.FillDirection=Enum.FillDirection.Horizontal;pl.Padding=UDim.new(0,4);pl.Parent=pips
 for t=1,5 do
  local pip=Instance.new('TextLabel');pip.Size=UDim2.fromOffset(22,18);pip.Text=tostring(t);pip.FontFace=UI.Font.Bold;pip.TextSize=11;pip.Parent=pips;UI.corner(pip,5)
  pip.BackgroundColor3=t<=tier and PURPLE or(t==tier+1 and a.ready and READY_GOLD or colors.cardLow)
  pip.TextColor3=t<=tier and colors.text or(t==tier+1 and a.ready and colors.ink or colors.muted)
 end
 local done=tier>=5
 local count=math.floor(tonumber(a.count)or 0)
 local bar=progressBar(c,done and 1 or count/math.max(1,nextT),done or a.ready)
 bar.Position=UDim2.new(0,left,1,compact and -24 or -28);bar.Size=UDim2.new(1,-left-btnW-260,0,compact and 10 or 12)
 local cnt=UI.text(c,'Count',done and'ALL 5 STAGES DONE'or('Stage '..(tier+1)..' of 5 · Done '..fmtNum(count)..' of '..fmtNum(nextT)),UI.Font.Bold,13,colors.muted)
 cnt.AnchorPoint=Vector2.new(1,.5);cnt.Position=UDim2.new(1,-btnW-22,1,compact and -19 or -22);cnt.Size=UDim2.fromOffset(230,18);cnt.TextXAlignment=Enum.TextXAlignment.Right
 if not compact and a.title then
  local t=UI.text(c,'TitlePreview','Stage 5 prize: the '..tostring(a.title)..' title',UI.Font.Body,13,done and READY_GOLD or colors.muted);UI.fit(t,10,13)
  t.Position=UDim2.fromOffset(left,36);t.Size=UDim2.new(1,-left-btnW-30,0,16)
 end
 if a.ready and not done then
  c:SetAttribute('Ready',true);rim.Color=READY_GOLD;pulsing[rim]=true
  local rewards=type(a.rewards)=='table'and a.rewards or{}
  local chips=rewardChips(c,type(a.reward)=='table'and a.reward or{tokens=rewards[tier+1]},compact and 24 or 28);chips.AnchorPoint=Vector2.new(1,0);chips.Position=UDim2.new(1,-btnW-22,0,compact and 6 or 10)
  local b=actionButton(c,'CLAIM STAGE '..(tier+1),'use',btnW,btnH)
  b.Activated:Connect(function()claim('achievements',a.claimKey or a.id,c)end)
  firstFocus=firstFocus or b
 elseif done then
  rim.Color=PURPLE
  local stamp=UI.text(c,'Stamp','ALL DONE',UI.Font.Display,18,READY_GOLD);stamp.AnchorPoint=Vector2.new(1,.5);stamp.Position=UDim2.new(1,-16,.5,0)
  stamp.Size=UDim2.fromOffset(btnW,30);stamp.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(stamp,2)
 end
 return c
end
local function masteryCard(m)
 -- Haunted Mastery: the single hardest reward. Requirement shown in full before anyone starts.
 local h=compact and 80 or 96
 local c=card(0,h)
 local rim=UI.stroke(c,PURPLE,3,0)
 local g=c:FindFirstChildOfClass('UIGradient');if g then g.Color=ColorSequence.new(Color3.fromRGB(70,40,110),Color3.fromRGB(30,22,44))end
 c.BackgroundColor3=Color3.new(1,1,1)
 local tag=UI.text(c,'Tag',tostring(m.tag or'[Haunted]'),UI.Font.Display,compact and 24 or 30,Color3.fromRGB(210,255,220));UI.outline(tag,2.5)
 tag.Position=UDim2.fromOffset(16,compact and 6 or 8);tag.Size=UDim2.new(.5,0,0,compact and 30 or 36)
 local tg=Instance.new('UIGradient');tg.Color=ColorSequence.new(Color3.fromRGB(200,255,210),Color3.fromRGB(120,200,150));tg.Parent=tag
 local req=UI.text(c,'Req','Finish all 10 lifetime goals through stage 5 to earn this tag',UI.Font.Bold,14,colors.muted);UI.fit(req,10,14)
 req.Position=UDim2.fromOffset(16,compact and 36 or 46);req.Size=UDim2.new(1,-180,0,18)
 local done,target=math.floor(tonumber(m.done)or 0),math.max(1,tonumber(m.target)or 10)
 local bar=progressBar(c,done/target,m.ready or m.claimed);bar.Position=UDim2.new(0,16,1,compact and -18 or -22);bar.Size=UDim2.new(1,-180,0,10)
 local btnW,btnH=compact and 104 or 128,compact and 44 or 46
 if m.claimed then
  local s=UI.text(c,'Stamp','YOURS!',UI.Font.Display,20,READY_GOLD);s.AnchorPoint=Vector2.new(1,.5);s.Position=UDim2.new(1,-16,.5,0);s.Size=UDim2.fromOffset(btnW,30)
  s.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(s,2)
 elseif m.ready then
  c:SetAttribute('Ready',true);rim.Color=READY_GOLD;pulsing[rim]=true
  local b=actionButton(c,'CLAIM TAG','use',btnW,btnH);b.Activated:Connect(function()claim('mastery',m.claimKey or'mastery',c)end)
  firstFocus=firstFocus or b
 else
  local s=UI.text(c,'Count',done..' of '..target..' goals',UI.Font.Display,20,colors.text);s.AnchorPoint=Vector2.new(1,.5);s.Position=UDim2.new(1,-16,.5,0)
  s.Size=UDim2.fromOffset(btnW,30);s.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(s,2)
 end
end

-- Footer strip: daily bonus / weekly chest / nothing on achievements.
local stripConn
local function drawFooter()
 if stripConn then stripConn:Disconnect();stripConn=nil end
 for _,x in stripPips:GetChildren()do if x:IsA('GuiObject')then x:Destroy()end end
 local readyHere=0
 local list=state and state[current]
 if current~='achievements'and type(list)=='table'and type(list.quests)=='table'then
  for _,q in list.quests do if q.ready and not q.claimed then readyHere+=1 end end
 elseif current=='achievements'and state and type(state.achievements)=='table'then
  for _,a in state.achievements do if a.ready then readyHere+=1 end end
 elseif current=='event'and eventOn()and type(state.event.quests)=='table'then
  for _,q in state.event.quests do if q.ready and not q.claimed then readyHere+=1 end end
 end
 claimAll.Text=readyHere>0 and('COLLECT ALL ('..readyHere..')')or'COLLECT ALL'
 claimAll.Active=readyHere>1;claimAll.AutoButtonColor=false;claimAll.Visible=true
 claimAll.BackgroundColor3=readyHere>1 and colors.green or colors.grey
 local extra=current=='daily'and type(list)=='table'and list.bonus or current=='weekly'and type(list)=='table'and list.chest or nil
 strip.Visible=extra~=nil
 if not extra then return end
 local doneN,target=math.floor(tonumber(extra.done)or 0),math.max(1,tonumber(extra.target)or 3)
 local r=type(extra.reward)=='table'and extra.reward or{}
 local parts={}
 if (tonumber(r.tokens)or 0)>0 then table.insert(parts,r.tokens..' TOKENS')end
 if (tonumber(r.revives)or 0)>0 then table.insert(parts,r.revives..' REVIVE')end
 stripText.Text=(current=='daily'and'★ FINISH ALL 3 TODAY  ·  'or'★ FINISH 4 FOR THE WEEKLY CHEST  ·  ')..table.concat(parts,' + ')..(current=='weekly'and' + A COSMETIC'or'')
 for i=1,target do
  local pip=Instance.new('Frame');pip.Size=UDim2.fromOffset(16,16);pip.BackgroundColor3=i<=doneN and READY_GOLD or colors.cardLow;pip.Parent=stripPips;UI.corner(pip,4)
 end
 stripStroke.Color=extra.ready and READY_GOLD or colors.greyDark;pulsing[stripStroke]=extra.ready and true or nil
 if extra.claimed then stripClaim.Text='COLLECTED ✓';stripClaim.Active=false;stripClaim.BackgroundColor3=colors.grey
 elseif extra.ready then stripClaim.Text='CLAIM REWARD';stripClaim.Active=true;stripClaim.BackgroundColor3=colors.gold
 else stripClaim.Text='Done '..doneN..' of '..target;stripClaim.Active=false;stripClaim.BackgroundColor3=colors.grey end
 stripConn=stripClaim.Activated:Connect(function()
  if extra.ready and not extra.claimed then claim(current,extra.claimKey or(current=='daily'and'bonus'or'chest'),strip)end
 end)
end

local function tabReady(key)
 if not state then return 0 end
 local n=0
 if key=='event'then
  if eventOn()and type(state.event.quests)=='table'then for _,q in state.event.quests do if q.ready and not q.claimed then n+=1 end end end
  return n
 end
 if key=='achievements'then
  if type(state.achievements)=='table'then for _,a in state.achievements do if a.ready then n+=1 end end end
  if type(state.mastery)=='table'and state.mastery.ready then n+=1 end
 else
  local t=state[key]
  if type(t)=='table'then
   if type(t.quests)=='table'then for _,q in t.quests do if q.ready and not q.claimed then n+=1 end end end
   local extra=t.bonus or t.chest;if type(extra)=='table'and extra.ready and not extra.claimed then n+=1 end
  end
 end
 return n
end

redraw=function()
 for _,c in body:GetChildren()do if c:IsA('GuiObject')then c:Destroy()end end
 table.clear(pulsing);firstFocus=nil
 sub.Text=TAB_SUB[current]or''
 for key,b in tabButtons do
  local on=key==current
  b.BackgroundColor3=on and PURPLE or colors.pill
  local badge=b:FindFirstChild('Badge');local n=tabReady(key)
  if badge then badge.Visible=n>0;local t=badge:FindFirstChild('N');if t then t.Text=tostring(n)end end
 end
 loading.Visible=state==nil;retry.Visible=false
 if not state then return end
 if current=='event'and not eventOn()then current='daily'end
 if current=='event'then
  local ev=state.event
  local head=card(0,compact and 50 or 58);local hs=UI.stroke(head,ORANGE,3,0)
  local g=head:FindFirstChildOfClass('UIGradient');if g then g.Color=ColorSequence.new(Color3.fromRGB(90,40,10),Color3.fromRGB(40,16,40))end;head.BackgroundColor3=Color3.new(1,1,1)
  local candy=UI.text(head,'Candy','CANDY CORN  '..fmtNum(ev.candyCorn or 0),UI.Font.Display,compact and 20 or 24,Color3.fromRGB(255,200,90));UI.outline(candy,2)
  candy.Position=UDim2.fromOffset(16,0);candy.Size=UDim2.new(.6,0,1,0)
  local ends=UI.text(head,'Ends',ev.endsAt and('Ends in '..fmtTime(ev.endsAt-serverNow()))or'',UI.Font.Bold,14,colors.muted)
  ends.AnchorPoint=Vector2.new(1,0);ends.Position=UDim2.new(1,-16,0,0);ends.Size=UDim2.new(.38,0,1,0);ends.TextXAlignment=Enum.TextXAlignment.Right
  hs.Transparency=0
  if type(ev.quests)=='table'then for i,q in ev.quests do questCard('event',q,i,false)end end
  if type(ev.shop)=='table'then
   for i,item in ev.shop do
    local o=Shop and Shop.ById[item.id]
    local c=card(100+i,compact and 64 or 76);UI.stroke(c,PURPLE,2,0)
    local icon=Instance.new('ImageLabel');icon.BackgroundTransparency=1;icon.Size=UDim2.fromOffset(compact and 52 or 62,compact and 52 or 62);icon.Position=UDim2.fromOffset(8,6)
    icon.Image=o and(o.image or Shop.OfferImages[item.id])or'';icon.Parent=c
    local name=UI.text(c,'Name',o and o.name or tostring(item.id),UI.Font.Bold,compact and 16 or 18);name.Position=UDim2.fromOffset(compact and 70 or 80,0);name.Size=UDim2.new(.5,0,1,0)
    local owned=item.owned==true
    local b=actionButton(c,owned and'OWNED'or(tostring(item.price)..' CANDY'),owned and'muted'or'use',compact and 120 or 140,compact and 44 or 46)
    b.Active=not owned
    b.Activated:Connect(function()
     if owned or busy then return end
     local f=remote('EventBuy');if not f then return end
     busy=true
     local ok,res=pcall(function()return f:InvokeServer(item.id)end)
     if ok and type(res)=='table'and res.ok then burst(c,{cosmeticIds={item.id}});if res.state then setState(res.state)end else sfx('cardReady',.7);fetch()end
     busy=false
    end)
   end
  end
 elseif current=='achievements'then
  if type(state.mastery)=='table'then masteryCard(state.mastery)end
  if type(state.achievements)=='table'then for i,a in state.achievements do chainCard(a,i)end end
 else
  local t=state[current]
  if type(t)=='table'and type(t.quests)=='table'then
   local canReroll=current=='daily'and not t.rerolled
   for i,q in t.quests do questCard(current,q,i,canReroll and not q.ready and not q.claimed and(tonumber(q.progress)or 0)==0)end
  end
 end
 drawFooter()
 local cells={};for _,c in body:GetChildren()do if c:IsA('Frame')then
  -- popRows wants cells holding a 'Card' with a 'Pop' scale: wrap the visual in place.
  local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=c
  table.insert(cells,c)
 end end
 for _,c in cells do local pop=c:FindFirstChild('Pop');if pop then pop.Scale=.85;Tween:Create(pop,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,false,.03*c.LayoutOrder),{Scale=1}):Play()end end
end
onState=function()if gui.Enabled then redraw()end end

for i,tdef in TABS do
 local b=UI.button(tabBar,'Tab_'..tdef.key,tdef.label,'muted');b.LayoutOrder=i;b.Size=UDim2.new(1/#TABS,-6,1,0)
 local badge=Instance.new('Frame');badge.Name='Badge';badge.AnchorPoint=Vector2.new(.5,.5);badge.Position=UDim2.new(1,-6,0,4);badge.Size=UDim2.fromOffset(24,24)
 badge.BackgroundColor3=colors.red;badge.Visible=false;badge.ZIndex=6;badge.Parent=b;UI.corner(badge,UDim.new(1,0));UI.stroke(badge,colors.text,2,0)
 local n=UI.text(badge,'N','0',UI.Font.Display,14);n.Size=UDim2.fromScale(1,1);n.TextXAlignment=Enum.TextXAlignment.Center;n.ZIndex=7
 b.Activated:Connect(function()if current~=tdef.key then current=tdef.key;sfx('cardReady',1.3);redraw()end end)
 tabButtons[tdef.key]=b
end
claimAll.Activated:Connect(function()if claimAll.Active then claimAllNow(current)end end)
retry.Activated:Connect(function()retry.Visible=false;loading.Text='Loading quests...';task.spawn(function()if not fetch()then loading.Text='Quests are unavailable right now.';retry.Visible=true end end)end)

-- Open / close -----------------------------------------------------------------------------------------
local isOpen=false
local ACTION='QuestLogControls'
local function cycleTab(dir)
 local idx=1;for i,t in TABS do if t.key==current then idx=i end end
 for _=1,#TABS do idx=(idx-1+dir)%#TABS+1;if not TABS[idx].event or eventOn()then break end end
 current=TABS[idx].key;sfx('cardReady',1.3);redraw()
 UI.SelectWhenReady(function()return firstFocus or tabButtons[current]end)
end
local closeLog -- forward
local function onAction(_,inputState,input)
 if inputState~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
 local k=input.KeyCode
 if k==Enum.KeyCode.ButtonB or k==Enum.KeyCode.Escape then closeLog()
 elseif k==Enum.KeyCode.ButtonL1 then cycleTab(-1)
 elseif k==Enum.KeyCode.ButtonR1 then cycleTab(1)
 elseif k==Enum.KeyCode.ButtonY then if claimAll.Active then claimAllNow(current)end
 elseif k==Enum.KeyCode.ButtonX then
  local sel=GS.SelectedObject;local key=sel and sel:GetAttribute('RerollKey')
  if key then reroll(key)end
 end
 return Enum.ContextActionResult.Sink
end
local tick
local function openLog(tab)
 if tab and(tab=='daily'or tab=='weekly'or tab=='achievements'or tab=='event')then current=tab end
 if isOpen then redraw();return end
 isOpen=true;p:SetAttribute('QuestLogOpen',true)
 gui.Enabled=true;layout();UI.FocusAcquire('QuestLog',gui)
 UI.showBackdrop(backdrop,true);UI.slideIn(holder,UDim2.fromScale(.5,.5),.34);sfx('panelOpen')
 redraw()
 CAS:BindActionAtPriority(ACTION,onAction,false,Enum.ContextActionPriority.High.Value+50,
  Enum.KeyCode.ButtonB,Enum.KeyCode.Escape,Enum.KeyCode.ButtonL1,Enum.KeyCode.ButtonR1,Enum.KeyCode.ButtonY,Enum.KeyCode.ButtonX)
 UIS.MouseIconEnabled=true
 task.spawn(function()
  if not fetch()and not state then loading.Text='Quests are unavailable right now.';retry.Visible=true end
  UI.SelectWhenReady(function()return firstFocus or tabButtons[current]end)
 end)
 tick=task.spawn(function()
  while isOpen do
   if state then
    local ends=current=='weekly'and state.weeklyEndsAt or current=='daily'and state.dailyEndsAt or nil
    timer.Text=ends and('Resets in '..fmtTime(ends-serverNow()))or''
   end
   task.wait(1)
  end
 end)
end
closeLog=function()
 if not isOpen then return end
 isOpen=false;p:SetAttribute('QuestLogOpen',nil)
 CAS:UnbindAction(ACTION)
 if GS.SelectedObject and GS.SelectedObject:IsDescendantOf(gui)then GS.SelectedObject=nil end
 UI.showBackdrop(backdrop,false)
 local t=UI.slideOut(holder,.2)
 t.Completed:Once(function()if not isOpen then gui.Enabled=false end end)
 UI.FocusRelease('QuestLog')
end
close.Activated:Connect(closeLog)
backdrop.Activated:Connect(closeLog)
openEvent.Event:Connect(openLog)
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if isOpen then layout();redraw()end end)

-- The van terminal prompt opens the log (RecoveryModels builds QuestsRewardsPrompt like the other two).
PPS.PromptTriggered:Connect(function(prompt)
 if prompt.Name=='QuestsRewardsPrompt'or prompt.Name=='QuestBoardPrompt'then openLog('daily')end
 if prompt.Name=='EventStallPrompt'then openLog('event')end
end)
-- Studio test API (never in live servers): open/close/state without clicking.
if Run:IsStudio()then
 local api=Instance.new('BindableFunction');api.Name='QuestLogTestApi';api.Parent=gui
 api.OnInvoke=function(cmd,arg)
  if cmd=='open'then openLog(arg)elseif cmd=='close'then closeLog()elseif cmd=='state'then return state end
  return isOpen
 end
end

-- Completion toast (top centre, queued, never stacks) -----------------------------------------------------
local toastGui=Instance.new('ScreenGui');toastGui.Name='QuestToast';toastGui.DisplayOrder=137;toastGui.ResetOnSpawn=false
toastGui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;toastGui.Parent=pg
local queue,showing={},false
local function showNext()
 if showing or #queue==0 then return end
 showing=true
 local text=table.remove(queue,1)
 local holderT,plateT=UI.plate(toastGui,'Toast',16)
 holderT.AnchorPoint=Vector2.new(.5,0);holderT.Size=UDim2.fromOffset(compact and 300 or 380,64);holderT.Position=UDim2.new(.5,0,0,-80)
 local ic=iconBadge(plateT,'quests',44);ic.Position=UDim2.fromOffset(10,10)
 local a=UI.text(plateT,'Head','GOAL DONE!',UI.Font.Display,18,READY_GOLD);UI.outline(a,2);a.Position=UDim2.fromOffset(64,8);a.Size=UDim2.new(1,-74,0,22)
 local b=UI.text(plateT,'Body',text..'  ·  open QUESTS to claim your reward',UI.Font.Bold,14);UI.fit(b,10,14);b.Position=UDim2.fromOffset(64,32);b.Size=UDim2.new(1,-74,0,22)
 sfx('cardReady')
 Tween:Create(holderT,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,14)}):Play()
 task.delay(3,function()
  local t=Tween:Create(holderT,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-80)});t:Play()
  t.Completed:Wait();holderT:Destroy();showing=false;showNext()
 end)
end
toast=function(text)
 if #queue>=4 then return end
 table.insert(queue,tostring(text));showNext()
end

-- Van terminal face (RecoveryModels builds QuestsRewardsTerminal; edits here are local, so every player sees
-- their own progress on the same panel) ------------------------------------------------------------------
local faces={}
local function trackFace(x)if x.Name=='QuestsRewardsTerminal'and x:IsA('BasePart')then faces[x]=true end end
for _,x in workspace:GetDescendants()do trackFace(x)end
workspace.DescendantAdded:Connect(trackFace)
local function drawFaces()
 for t in faces do
  if not t:IsDescendantOf(workspace)then faces[t]=nil
  else
   local frame=t:FindFirstChild('RewardFace')and t.RewardFace:FindFirstChild('Frame')
   if frame then
    local ready=state and tonumber(state.readyCount)or 0
    local st=frame:FindFirstChild('Status')
    if st then
     local text=not state and'DAILY + WEEKLY QUESTS'or ready>0 and(ready..' READY TO CLAIM!')
      or('NEW QUESTS IN '..fmtTime((tonumber(state.dailyEndsAt)or serverNow())-serverNow()))
     if st.Text~=text then st.Text=text end
     st.TextTransparency=ready>0 and(math.sin(os.clock()*4)+1)*.18 or 0
    end
    local list=state and type(state.daily)=='table'and state.daily.quests
    for i=1,3 do
     local bar=frame:FindFirstChild('Bar'..i);local fill=bar and bar:FindFirstChild('Fill')
     if fill then
      local q=type(list)=='table'and list[i]
      local frac=q and math.clamp((tonumber(q.progress)or 0)/math.max(1,tonumber(q.target)or 1),0,1)or 0
      fill.Size=UDim2.fromScale(frac,1);fill.Visible=frac>0
      fill.BackgroundColor3=q and q.claimed and DONE_GREEN or Color3.new(1,1,1)
     end
    end
   end
  end
 end
end
task.spawn(function()while true do if next(faces)then drawFaces()end;task.wait(.1)end end)

-- Wiring to the server -------------------------------------------------------------------------------------
task.spawn(function()
 if MOCK then setState(mockState());return end
 local folder=RS:WaitForChild('Quests',60);if not folder then return end
 local changed=folder:WaitForChild('StateChanged',30)
 if changed and changed:IsA('RemoteEvent')then changed.OnClientEvent:Connect(function(s)setState(s,true)end)end
 for _=1,5 do if fetch()then break end;task.wait(3)end
end)
