-- Omens (owner 2026-10-26): from level 3 every level has one effect (RecoveryRoundServer sets RecoveryRound.Omen).
-- At level start a big card announces it, holds, then shrinks into a small chip under the quota panel for the rest
-- of the level. Also draws the green VALUED tag over Valued loot (this client only). The card owns its UIScale, so
-- ConsoleUiScale leaves it alone; the TV factor is applied here.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local TweenService=game:GetService('TweenService')
local GuiService=game:GetService('GuiService')
local player=Players.LocalPlayer
local state=RS:WaitForChild('RecoveryRound',math.huge) -- mission servers only; the lobby never has one

local GOOD,BAD=Color3.fromRGB(110,226,140),Color3.fromRGB(255,166,84)
local TEXT,MUTED,INK=Color3.fromRGB(244,236,210),Color3.fromRGB(170,164,190),Color3.fromRGB(14,12,22)
local OMENS={
 Adrenaline={title='ADRENALINE RUSH',text='When a monster chases you, you get a burst of speed.',good=true},
 Untouchable={title='UNTOUCHABLE',text='The FIRST time a monster gets you, it cannot hurt you. Only once! After that you are on your own, so play smart.',good=true},
 Hush={title='THE HUSH',text='Monsters see and hear you 20% less.',good=true},
 Visitor={title='THE VISITOR',text='Someone left the team a gift.',good=true},
 OneKind={title='ONE OF A KIND',text='Every monster on this level is the same kind.',good=true},
 Valued={title='VALUED LOOT',text='Some loot is worth much more. Look for the green VALUED tag.',good=true},
 SlayerSale={title='SLAYER SALE',text='The Monster Slayer is 35% off in the van.',good=true},
 DoubleTokens={title='DOUBLE TOKENS',text='Clear this level for double tokens.',good=true},
 DimBatteries={title='DIM BATTERIES',text='Your flashlight beam is 25% shorter.',good=false},
 HeavyQuota={title='HEAVY QUOTA',text='The quota is 15% higher this level.',good=false},
 Restless={title='RESTLESS',text='Monsters hear you from further away.',good=false},
 -- Monsters build 2026-10-27 (omen pool 2)
 LowGravity={title='MOON NIGHT',text='Gravity is low tonight. Jumps go higher and float, falls are slow. But every big landing goes THUD, and monsters hear it.',good=true},
 Shrunk={title='TEENY TINY',text='The whole crew is half size! Walk under desks and tables to hide, and monsters see you less far. But your little legs are slow, and nobody can crouch.',good=false},
 RushHour={title='RUSH HOUR',text='The cart wants to GO! Pushing it you move much faster, and a cart you let go of keeps rolling. But a fast cart squeaks and honks, and monsters hear it.',good=true},
 Cuckoo={title='THE CUCKOO',text='A cuckoo clock is hidden on this level. Every minute it calls the monsters to it. Grab it to wind it back, or sell it to shut it up.',good=false},
}

local gui=Instance.new('ScreenGui');gui.Name='OmenGui';gui.ResetOnSpawn=false;gui.DisplayOrder=18;gui.IgnoreGuiInset=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets -- same space as RecoveryQuota, so the chip can sit under it
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=player:WaitForChild('PlayerGui')

local function label(parent,name,size,color,order)
 local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextSize=size;t.TextColor3=color
 t.TextWrapped=true;t.AutomaticSize=Enum.AutomaticSize.Y;t.Size=UDim2.new(1,0,0,0);t.LayoutOrder=order;t.Text='';t.Parent=parent
 return t
end
-- The announcement card: centred in the upper third, width capped to the screen.
local card=Instance.new('Frame');card.Name='OmenCard';card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.32)
card.Size=UDim2.fromOffset(480,0);card.AutomaticSize=Enum.AutomaticSize.Y;card.BackgroundColor3=INK;card.BackgroundTransparency=.12
card.BorderSizePixel=0;card.Visible=false;card.Parent=gui
Instance.new('UICorner',card).CornerRadius=UDim.new(0,16)
local stroke=Instance.new('UIStroke');stroke.Thickness=3;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=card
local pad=Instance.new('UIPadding');pad.PaddingTop=UDim.new(0,14);pad.PaddingBottom=UDim.new(0,16);pad.PaddingLeft=UDim.new(0,18);pad.PaddingRight=UDim.new(0,18);pad.Parent=card
local list=Instance.new('UIListLayout');list.SortOrder=Enum.SortOrder.LayoutOrder;list.Padding=UDim.new(0,4);list.HorizontalAlignment=Enum.HorizontalAlignment.Center;list.Parent=card
local cardScale=Instance.new('UIScale');cardScale.Parent=card
local header=label(card,'Header',15,MUTED,1)
local title=label(card,'Title',38,GOOD,2);local titleStroke=Instance.new('UIStroke');titleStroke.Thickness=2;titleStroke.Transparency=.35;titleStroke.Parent=title
local body=label(card,'Body',19,TEXT,3)
local detail=label(card,'Detail',17,GOOD,4)
-- The omen's dashboard prop (RecoveryRoundServer puts it on the van console, tag OmenDashProp) sways at the top of the
-- card (Monsters build 2026-10-27; omens without a prop show no viewport).
local CS=game:GetService('CollectionService')
local view=Instance.new('ViewportFrame');view.Name='OmenProp';view.Size=UDim2.fromOffset(92,92);view.BackgroundTransparency=1
view.LayoutOrder=0;view.Visible=false;view.Ambient=Color3.fromRGB(150,150,170);view.LightColor=Color3.fromRGB(255,246,226)
view.LightDirection=Vector3.new(-1,-1.4,1);view.Parent=card
local viewCam=Instance.new('Camera');viewCam.FieldOfView=32;viewCam.Parent=view;view.CurrentCamera=viewCam
local propCopy
local function showProp(id)
 if propCopy then propCopy:Destroy();propCopy=nil end
 local src;for _,m in CS:GetTagged('OmenDashProp')do if m:GetAttribute('Omen')==id then src=m;break end end
 view.Visible=src~=nil;if not src then return end
 propCopy=src:Clone();CS:RemoveTag(propCopy,'OmenDashProp') -- untagged, or parenting the copy re-fires the added signal below (endless clone loop)
 propCopy:PivotTo(CFrame.identity);propCopy.Parent=view
 local box,size=propCopy:GetBoundingBox();local reach=size.Magnitude/2/math.tan(math.rad(viewCam.FieldOfView/2))
 viewCam.CFrame=CFrame.lookAt(box.Position+Vector3.new(.35,.3,-1).Unit*reach,box.Position) -- from the front (-Z), a little above
end
-- The omen is set before the van is rebuilt, so the prop can arrive after the card: show it then.
CS:GetInstanceAddedSignal('OmenDashProp'):Connect(function(m)
 if not m:IsDescendantOf(workspace)then return end
 if card.Visible and m:GetAttribute('Omen')==state:GetAttribute('Omen')then showProp(m:GetAttribute('Omen'))end
end)
game:GetService('RunService').RenderStepped:Connect(function()
 if propCopy and card.Visible then propCopy:PivotTo(CFrame.Angles(0,math.sin(os.clock()*1.4)*.6,0))end -- gentle sway, front stays readable
end)
-- The chip: a small reminder under the quota panel (82 px tall, top centre).
local chip=Instance.new('TextLabel');chip.Name='OmenChip';chip.AnchorPoint=Vector2.new(.5,0);chip.Position=UDim2.new(.5,0,0,90)
chip.Size=UDim2.fromOffset(0,28);chip.AutomaticSize=Enum.AutomaticSize.X;chip.BackgroundColor3=INK;chip.BackgroundTransparency=.2;chip.BorderSizePixel=0
chip.Font=Enum.Font.FredokaOne;chip.TextSize=15;chip.TextColor3=TEXT;chip.Visible=false;chip.Parent=gui
Instance.new('UICorner',chip).CornerRadius=UDim.new(1,0)
local chipPad=Instance.new('UIPadding');chipPad.PaddingLeft=UDim.new(0,14);chipPad.PaddingRight=UDim.new(0,14);chipPad.Parent=chip
local chipStroke=Instance.new('UIStroke');chipStroke.Thickness=2;chipStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;chipStroke.Parent=chip
local chipScale=Instance.new('UIScale');chipScale.Parent=chip

local function screenScale()
 local cam=workspace.CurrentCamera;local v=cam and cam.ViewportSize or Vector2.new(1280,720)
 local s=math.clamp(math.min(v.X/900,v.Y/560),.62,1.15)
 if GuiService:IsTenFootInterface()then s*=1.3 end
 return s,v
end
local function fit()
 local s,v=screenScale()
 card.Size=UDim2.fromOffset(math.min(480,(v.X*.9)/s),0);if chip.Parent==gui then chipScale.Scale=math.min(s,1.2)end
end
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(fit);fit()

local shown -- "<round>:<omen>" already announced
local token=0
local function chipText(def)return 'OMEN: '..def.title end
-- Where the chip sits. Computer and console: inside the quota panel (RecoveryRoundClient), just under it. Phones and
-- tablets: right above the Roblox Plus pill (PlusBonusHud), right-aligned (owner 2026-10-26); on phones that pill is
-- pinned to the top, so OmenChipTop asks PlusBonusHud to drop it one row. It only sits in those panels, never owns them.
local InputHints=require(RS:WaitForChild('InputHints'))
task.spawn(function()
 while true do
  local plusLabel=InputHints.IsMobile()and player.PlayerGui:FindFirstChild('PlusBonusHud')and player.PlayerGui.PlusBonusHud:FindFirstChild('Plus',true)
  local plusBox=plusLabel and plusLabel.Parent
  local q=player.PlayerGui:FindFirstChild('QuotaPanel',true)
  if plusBox and plusBox:IsA('GuiObject')then
   if chip.Parent~=plusBox then chip.Parent=plusBox;chip.AnchorPoint=Vector2.new(1,1);chip.Position=UDim2.new(1,0,0,-6);chipScale.Scale=1;chip.ZIndex=5 end
  elseif q and q:IsA('GuiObject')then
   if chip.Parent~=q then chip.Parent=q;chip.AnchorPoint=Vector2.new(.5,0);chip.Position=UDim2.new(.5,0,1,6);chipScale.Scale=1;chip.ZIndex=5 end
  elseif chip.Parent~=gui then chip.Parent=gui;chip.AnchorPoint=Vector2.new(.5,0);chip.Position=UDim2.new(.5,0,0,90)end
  local top=plusBox~=nil and chip.Parent==plusBox and chip.Visible
  if(player:GetAttribute('OmenChipTop')==true)~=top then player:SetAttribute('OmenChipTop',top or nil)end
  task.wait(.25)
 end
end)
local function refresh()
 local id=state:GetAttribute('Omen');local def=id and OMENS[id]
 local active=player:GetAttribute('MissionActive')==true and def~=nil
 if not active then card.Visible=false;chip.Visible=false;return end
 local color=def.good and GOOD or BAD
 chip.Text=chipText(def);chipStroke.Color=color;chip.TextColor3=color
 local key=tostring(state:GetAttribute('Round'))..':'..id
 local extra=id=='Visitor'and state:GetAttribute('OmenDetail')and('The Visitor left '..state:GetAttribute('OmenDetail')..'.')
  or id=='OneKind'and state:GetAttribute('OmenMonster')and('Tonight it is the '..state:GetAttribute('OmenMonster')..'.')or nil
 detail.Text=extra or '';detail.Visible=extra~=nil;detail.TextColor3=color
 if shown==key then if not card.Visible then chip.Visible=true end;return end
 shown=key;token+=1;local mine=token
 header.Text=('LEVEL %d OMEN  ·  %s'):format(state:GetAttribute('Round')or 0,def.good and 'A GOOD ONE'or'A BAD ONE')
 title.Text=def.title;title.TextColor3=color;stroke.Color=color;body.Text=def.text;showProp(id)
 chip.Visible=false;card.Visible=true;card.BackgroundTransparency=1
 local s=screenScale();cardScale.Scale=s*.6
 TweenService:Create(cardScale,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=s}):Play()
 TweenService:Create(card,TweenInfo.new(.25),{BackgroundTransparency=.12}):Play()
 task.delay(6.5,function()
  if token~=mine then return end
  local t=TweenService:Create(cardScale,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=0});t:Play();t.Completed:Wait()
  if token~=mine then return end
  card.Visible=false;chip.Visible=state:GetAttribute('Omen')==id and player:GetAttribute('MissionActive')==true
 end)
end
-- Untouchable spent: say so right away, so nobody thinks they are still safe.
player:GetAttributeChangedSignal('UntouchableUntil'):Connect(function()
 if not player:GetAttribute('UntouchableUntil')then return end
 token+=1;local mine=token
 header.Text='UNTOUCHABLE';title.Text='SHIELD USED UP';title.TextColor3=BAD;stroke.Color=BAD
 body.Text='RUN! That was your one free hit. Next time it hurts. Play smart!';detail.Visible=false;view.Visible=false
 card.Visible=true;local s=screenScale();cardScale.Scale=s*.6
 TweenService:Create(cardScale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=s}):Play()
 task.delay(4,function()if token==mine then card.Visible=false end end)
 chip.Text='OMEN: UNTOUCHABLE (USED)';chip.TextColor3=BAD;chipStroke.Color=BAD
end)
for _,a in {'Omen','OmenDetail','OmenMonster','Round'}do state:GetAttributeChangedSignal(a):Connect(refresh)end
player:GetAttributeChangedSignal('MissionActive'):Connect(refresh)
task.defer(refresh)
-- THE CUCKOO (Monsters build 2026-10-27): the chip counts down to the next call (the clock's CuckooAt is server time);
-- SILENCED once it is sold.
task.spawn(function()
 while true do
  task.wait(.5)
  if state:GetAttribute('Omen')=='Cuckoo'and chip.Visible then
   local mansion=workspace:FindFirstChild('Mansion');local f=mansion and mansion:FindFirstChild('Interactive');local at
   if f then for _,m in ipairs(f:GetChildren())do if m:GetAttribute('ItemId')=='CuckooClock'then at=m:GetAttribute('CuckooAt');break end end end
   if type(at)=='number'then
    local left=math.max(0,math.ceil(at-workspace:GetServerTimeNow()))
    chip.Text=('OMEN: THE CUCKOO  %d:%02d'):format(left//60,left%60)
   else chip.Text='OMEN: THE CUCKOO (SILENCED)'end
  end
 end
end)

-- VALUED tags: a green line above each Valued loot item, drawn only on this client.
local tags={}
local function tag(m)
 if tags[m]or not m:IsA('Model')or m:GetAttribute('Valued')~=true or not m.PrimaryPart then return end
 local bb=Instance.new('BillboardGui');bb.Name='ValuedTag';bb.Adornee=m.PrimaryPart;bb.Size=UDim2.fromOffset(110,26);bb.StudsOffsetWorldSpace=Vector3.new(0,1.6,0)
 bb.AlwaysOnTop=false;bb.MaxDistance=45;bb.LightInfluence=0;bb.Parent=gui
 local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.Text='VALUED'
 t.TextColor3=GOOD;t.Parent=bb;local st=Instance.new('UIStroke');st.Thickness=2;st.Color=Color3.fromRGB(10,30,16);st.Parent=t
 tags[m]=bb
 m.AncestryChanged:Connect(function()if not m:IsDescendantOf(workspace)and tags[m]then tags[m]:Destroy();tags[m]=nil end end)
end
task.spawn(function()
 while true do
  -- held or sold loot loses the tag; dropped loot gets it back
  for m,bb in tags do if m:GetAttribute('HeldBy')or m:GetAttribute('Valued')~=true then bb:Destroy();tags[m]=nil end end
  local mansion=workspace:FindFirstChild('Mansion');local f=mansion and mansion:FindFirstChild('Interactive')
  if f then for _,m in f:GetChildren()do if not m:GetAttribute('HeldBy')then tag(m)end end end
  task.wait(1)
 end
end)


-- ForecastBobble (WorldA; van dashboard ghost): a sign over its head. Searching: this level. Returning: static, "tuning in".
-- Won: the next level's map + omen (RecoveryRoundServer winLevel sets NextMapKind/NextOmen) with a springy head bob.
-- The van is rebuilt every level, so the bobble is looked up again whenever it is missing.
do
 local Run=game:GetService('RunService')
 local Audio=require(RS:WaitForChild('GameplayAudio'))
 local MAP_NAMES={Mansion='THE MANSION',Dungeon='THE DUNGEON',Hospital='THE HOSPITAL',Hotel='THE HOTEL',School='THE SCHOOL'}
 local REVEAL_DELAY,WOBBLE_SECONDS=2.2,2.4
 local bobble,head,neon,baseHead,baseNeon,sign,line1,line2,line3
 local revealAt,lastTick=nil,0
 local function mapName(k)return type(k)=='string'and(MAP_NAMES[k]or k:upper())or'???'end
 local function find()
  local camp=workspace:FindFirstChild('RecoveryCamp');local b=camp and camp:FindFirstChild('ForecastBobble',true)
  if b and b==bobble and head and head.Parent then return true end
  if sign then sign:Destroy();sign=nil end
  bobble=b;head=b and b:FindFirstChild('Head');neon=b and b:FindFirstChild('Head_neon')
  if not head or not head:IsA('BasePart') then head=nil;return false end
  baseHead=head.CFrame;baseNeon=neon and neon:IsA('BasePart') and neon.CFrame or nil
  sign=Instance.new('BillboardGui');sign.Name='ForecastSign';sign.Adornee=head;sign.Size=UDim2.fromScale(2.4,.9) -- owner 2026-10-27: was 6.4x2.4 studs, far too big over the van TV
  sign.StudsOffsetWorldSpace=Vector3.new(0,1,0);sign.MaxDistance=16;sign.LightInfluence=0;sign.ResetOnSpawn=false
  local bg=Instance.new('Frame');bg.Name='Back';bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=INK;bg.BackgroundTransparency=.15;bg.Parent=sign
  Instance.new('UICorner',bg).CornerRadius=UDim.new(.08,0)
  local rim=Instance.new('UIStroke');rim.Thickness=1;rim.Color=Color3.fromRGB(66,201,240);rim.Parent=bg
  local function row(name,y,h,color)
   local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Position=UDim2.fromScale(.05,y);t.Size=UDim2.fromScale(.9,h)
   t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=color;t.Text='';t.Parent=bg
   local s=Instance.new('UIStroke');s.Thickness=1.5;s.Transparency=.3;s.Parent=t;return t
  end
  line1=row('Line1',.06,.24,MUTED);line2=row('Line2',.33,.36,TEXT);line3=row('Line3',.72,.22,GOOD)
  sign.Parent=player:WaitForChild('PlayerGui')
  return true
 end
 local function omenLine(id,level)
  local def=type(id)=='string'and OMENS[id]
  if def then return 'OMEN: '..def.title,def.good and GOOD or BAD end
  if level==2 then return 'VAN SALE: GEAR + BOOSTS 25% OFF',GOOD end
  if level<3 then return 'OMENS START AT LEVEL 3',MUTED end
  return 'CLEAR SKIES',MUTED
 end
 local function draw()
  if not find() then return end
  local phase=state:GetAttribute('Phase');local round=state:GetAttribute('Round')or 0
  if phase=='Won'and state:GetAttribute('NextMapKind')and revealAt and os.clock()>=revealAt then
   local level=state:GetAttribute('NextLevel')or round+1
   line1.Text='FORECAST \u{00B7} LEVEL '..level
   line2.Text='NEXT STOP: '..mapName(state:GetAttribute('NextMapKind'))..(state:GetAttribute('NextMapNew')and'  NEW!'or'')
   local text,color=omenLine(state:GetAttribute('NextOmen'),level);line3.Text=text;line3.TextColor3=color
  elseif phase=='Returning'or phase=='Won'then
   line1.Text='FORECAST';line2.Text='TUNING IN...';line3.Text='GET EVERYONE TO THE VAN';line3.TextColor3=MUTED
  else
   line1.Text='NOW \u{00B7} LEVEL '..round;line2.Text=mapName(state:GetAttribute('MapKind'))
   local text,color=omenLine(state:GetAttribute('Omen'),round);if round>=3 and text=='CLEAR SKIES'then text='NO OMEN'end
   line3.Text=text;line3.TextColor3=color
  end
 end
 state:GetAttributeChangedSignal('Phase'):Connect(function()
  if state:GetAttribute('Phase')=='Won'then
   local at=os.clock()+REVEAL_DELAY;revealAt=at
   task.delay(REVEAL_DELAY,function()
    if revealAt~=at or state:GetAttribute('Phase')~='Won'or not find()then return end
    draw()
    Audio.Play('UiOpen',head)
    local def=OMENS[state:GetAttribute('NextOmen')or'']
    if def and not def.good then task.delay(.35,function()if head and head.Parent then Audio.Play('StingKnock',head)end end)end
   end)
  else revealAt=nil end
  draw()
 end)
 for _,k in {'Round','MapKind','Omen','NextMapKind','NextOmen'}do state:GetAttributeChangedSignal(k):Connect(draw)end
 local nextFind=0
 Run.RenderStepped:Connect(function()
  if not head or not head.Parent then -- van rebuilt: look for the new bobble at most once a second
   if os.clock()<nextFind then return end;nextFind=os.clock()+1
   if not find()then return end;draw()
  end
  local cam=workspace.CurrentCamera;if not cam or(cam.CFrame.Position-baseHead.Position).Magnitude>90 then return end
  local phase=state:GetAttribute('Phase');local now=os.clock()
  -- damped spring after the reveal, then a slow nod while the clear holds; still otherwise
  local a=0
  if revealAt and now>=revealAt then local t=now-revealAt;a=t<WOBBLE_SECONDS and math.exp(-t*1.6)*math.sin(t*14)or math.sin(now*3)*.12 end
  if phase=='Returning'then a=math.sin(now*9)*.04 end -- jittery "static"
  local neck=baseHead*CFrame.new(0,-head.Size.Y/2,0) -- the head swings on its spring, under the head mesh
  local tilt=CFrame.Angles(a*.35,0,a*.2)
  head.CFrame=neck*tilt*neck:Inverse()*baseHead
  if neon and baseNeon then neon.CFrame=neck*tilt*neck:Inverse()*baseNeon;neon.Transparency=(revealAt and now>=revealAt and now-revealAt<WOBBLE_SECONDS and math.floor(now*2.5)%2==0)and .6 or 0 end -- blink under 3 Hz
  if phase=='Returning'and line2 then
   line2.TextTransparency=math.floor(now*2.5)%3==0 and .5 or 0 -- static flicker (under 3 Hz)
   if now-lastTick>1 and(cam.CFrame.Position-baseHead.Position).Magnitude<25 then lastTick=now;Audio.Play('ClockTick',head)end
  elseif line2 then line2.TextTransparency=0 end
 end)
 draw()
end
