-- Shared look for the van shops and the appearance panel: black glass plate, slowly turning neon rim,
-- red X close button, slide-in plate and row-by-row card pops. Visual only; callers keep all behaviour.
-- ModalFocus hides the other HUD screens and proximity prompts while one of these panels is open.
local TS=game:GetService('TweenService')
local Run=game:GetService('RunService')
local Players=game:GetService('Players')
local PPS=game:GetService('ProximityPromptService')
local GS=game:GetService('GuiService')
local M={}
local BUILDER='rbxasset://fonts/families/BuilderSans.json'
M.Font={
 Title=Font.new(BUILDER,Enum.FontWeight.ExtraBold),
 Bold=Font.new(BUILDER,Enum.FontWeight.Bold),
 Body=Font.new(BUILDER,Enum.FontWeight.Medium),
 Display=Font.fromEnum(Enum.Font.FredokaOne),
}
M.Color={
 plate=Color3.fromRGB(12,12,16),plateTop=Color3.fromRGB(26,26,33),pill=Color3.fromRGB(30,30,38),
 card=Color3.fromRGB(24,24,31),cardLow=Color3.fromRGB(15,15,20),
 text=Color3.fromRGB(255,255,255),muted=Color3.fromRGB(176,178,192),ink=Color3.fromRGB(5,5,8),
 green=Color3.fromRGB(52,222,104),greenDark=Color3.fromRGB(20,150,64),
 red=Color3.fromRGB(232,36,72),redDark=Color3.fromRGB(170,16,46),
 gold=Color3.fromRGB(255,208,86),grey=Color3.fromRGB(70,72,84),greyDark=Color3.fromRGB(44,45,54),
}
-- Neon rim colours (violet -> blue -> green -> amber -> pink -> violet) so the turning gradient has no seam.
M.Rim=ColorSequence.new({
 ColorSequenceKeypoint.new(0,Color3.fromRGB(150,90,255)),ColorSequenceKeypoint.new(.22,Color3.fromRGB(60,170,255)),
 ColorSequenceKeypoint.new(.45,Color3.fromRGB(60,235,140)),ColorSequenceKeypoint.new(.68,Color3.fromRGB(255,196,70)),
 ColorSequenceKeypoint.new(.86,Color3.fromRGB(255,70,150)),ColorSequenceKeypoint.new(1,Color3.fromRGB(150,90,255)),
})
M.RIM_SPIN_DEG=36 -- degrees per second
function M.corner(o,r)local c=Instance.new('UICorner');c.CornerRadius=typeof(r)=='UDim'and r or UDim.new(0,r or 14);c.Parent=o;return c end
function M.stroke(o,color,thickness,transparency)
 local s=Instance.new('UIStroke');s.Color=color or M.Color.ink;s.Thickness=thickness or 2;s.Transparency=transparency or 0
 s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.LineJoinMode=Enum.LineJoinMode.Round;s.Parent=o;return s
end
-- Dark outline around text glyphs (the chunky game-shop look), not around the box.
function M.outline(t,thickness,transparency)
 local s=Instance.new('UIStroke');s.Name='TextOutline';s.Color=M.Color.ink;s.Thickness=thickness or 1.5;s.Transparency=transparency or .1
 s.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;s.LineJoinMode=Enum.LineJoinMode.Round;s.Parent=t;return s
end
function M.text(parent,name,value,face,size,color)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=value or '';t.BackgroundTransparency=1;t.FontFace=face or M.Font.Bold
 t.TextSize=size or 16;t.TextColor3=color or M.Color.text;t.TextXAlignment=Enum.TextXAlignment.Left;t.Parent=parent;return t
end
-- Scaled text that never clips: shrinks between min and max instead of overflowing its box.
function M.fit(t,min,max)
 t.TextScaled=true;t.TextWrapped=true
 local c=t:FindFirstChildOfClass('UITextSizeConstraint')or Instance.new('UITextSizeConstraint');c.MinTextSize=min;c.MaxTextSize=max;c.Parent=t;return t
end
local spinning={}
local spinConnection
local function spinStep(dt)
 local any=false
 for g,host in spinning do
  if not g.Parent then spinning[g]=nil
  elseif host.Visible then any=true;g.Rotation=(g.Rotation+dt*M.RIM_SPIN_DEG)%360 end
 end
 if not next(spinning)and spinConnection then spinConnection:Disconnect();spinConnection=nil end
end
local function spin(g,host)spinning[g]=host;if not spinConnection then spinConnection=Run.RenderStepped:Connect(spinStep)end end
-- Returns holder (position/size/animate this), plate (content parent).
function M.plate(parent,name,radius)
 radius=radius or 22
 local holder=Instance.new('Frame');holder.Name=name;holder.BackgroundTransparency=1;holder.Parent=parent
 local glow=Instance.new('Frame');glow.Name='RimGlow';glow.BackgroundTransparency=1;glow.Size=UDim2.fromScale(1,1);glow.ZIndex=0;glow.Parent=holder
 M.corner(glow,radius+2)
 local glowStroke=M.stroke(glow,Color3.new(1,1,1),9,.8);local glowGradient=Instance.new('UIGradient');glowGradient.Color=M.Rim;glowGradient.Parent=glowStroke
 local plate=Instance.new('Frame');plate.Name='Plate';plate.Size=UDim2.fromScale(1,1);plate.BackgroundColor3=Color3.new(1,1,1);plate.BorderSizePixel=0;plate.ZIndex=0;plate.Parent=holder
 M.corner(plate,radius)
 local fill=Instance.new('UIGradient');fill.Name='Fill';fill.Rotation=90
 fill.Color=ColorSequence.new(M.Color.plateTop,M.Color.plate);fill.Parent=plate
 local rim=M.stroke(plate,Color3.new(1,1,1),3,0);rim.Name='NeonRim'
 local rimGradient=Instance.new('UIGradient');rimGradient.Color=M.Rim;rimGradient.Parent=rim
 spin(rimGradient,holder);spin(glowGradient,holder)
 local pop=Instance.new('UIScale');pop.Name='PlatePop';pop.Parent=holder
 return holder,plate
end
-- Full-screen catcher: dims the world a little and swallows clicks so nothing behind the panel reacts.
function M.backdrop(gui,transparency)
 local b=Instance.new('TextButton');b.Name='Backdrop';b.Text='';b.AutoButtonColor=false;b.Selectable=false;b.BorderSizePixel=0
 b.BackgroundColor3=Color3.new(0,0,0);b.BackgroundTransparency=1;b.Position=UDim2.new(0,0,0,-80);b.Size=UDim2.new(1,0,1,80);b.Visible=false;b.ZIndex=0;b.Parent=gui
 b:SetAttribute('OpenTransparency',transparency or .45)
 return b
end
function M.showBackdrop(b,on)
 local target=on and b:GetAttribute('OpenTransparency')or 1
 if on then b.Visible=true end
 local t=TS:Create(b,TweenInfo.new(on and .22 or .16,Enum.EasingStyle.Quad),{BackgroundTransparency=target});t:Play()
 if not on then t.Completed:Connect(function(state)if state==Enum.PlaybackState.Completed then b.Visible=false end end)end
 return t
end
-- Controller focus: thick gold ring just outside the control, so it never looks like a 'chosen' white ring.
M.FOCUS_COLOR=Color3.fromRGB(255,206,64)
function M.selection(b,radius)
 local f=Instance.new('Frame');f.Name='FocusOutline';f.BackgroundTransparency=1;f.Size=UDim2.new(1,8,1,8);f.Position=UDim2.fromOffset(-4,-4)
 M.corner(f,typeof(radius)=='UDim'and radius or UDim.new(0,(radius or 12)+4));M.stroke(f,M.FOCUS_COLOR,3.5,0);b.SelectionImageObject=f
 b.Destroying:Connect(function()f:Destroy()end)
end
local function pressable(b)
 local s=Instance.new('UIScale');s.Name='Press';s.Parent=b
 local function to(v,t)TS:Create(s,TweenInfo.new(t or .12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=v}):Play()end
 b.MouseEnter:Connect(function()to(1.05)end);b.MouseLeave:Connect(function()to(1)end)
 b.SelectionGained:Connect(function()to(1.05)end);b.SelectionLost:Connect(function()to(1)end)
 b.MouseButton1Down:Connect(function()to(.94,.06)end);b.MouseButton1Up:Connect(function()to(1.05)end)
 return s
end
local SHADE=Color3.fromRGB(196,196,196) -- bottom of every chunky button face (and its label)
local BUTTON={
 buy={M.Color.green,M.Color.greenDark,M.Color.text},
 use={M.Color.gold,Color3.fromRGB(214,140,24),M.Color.text},
 muted={M.Color.grey,M.Color.greyDark,Color3.fromRGB(214,216,226)},
 danger={M.Color.red,M.Color.redDark,M.Color.text},
}
-- Chunky rounded button: bright top, darker bottom, dark rim, outlined white label (game-shop style).
function M.button(parent,name,value,kind)
 local style=BUTTON[kind or 'buy']or BUTTON.buy
 local b=Instance.new('TextButton');b.Name=name;b.Text=value;b.AutoButtonColor=false;b.Selectable=true;b.BorderSizePixel=0
 b.BackgroundColor3=style[1];b.FontFace=M.Font.Display;b.TextColor3=style[3];b.TextSize=19;b.Parent=parent
 -- A UIGradient also multiplies the label, so it only shades white -> light grey: the face darkens toward
 -- the bottom while the text stays near-white (a coloured gradient made the text vanish into the fill).
 local g=Instance.new('UIGradient');g.Rotation=90;g.Color=ColorSequence.new(Color3.new(1,1,1),SHADE);g.Parent=b
 M.corner(b,12);M.stroke(b,M.Color.ink,2,.05);M.outline(b,1.4,.15);M.selection(b,12);pressable(b)
 local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=11;limit.MaxTextSize=19;limit.Parent=b;b.TextScaled=true
 local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,6);pad.PaddingRight=UDim.new(0,6);pad.PaddingTop=UDim.new(0,6);pad.PaddingBottom=UDim.new(0,6);pad.Parent=b
 return b
end
-- Round red X with a white ring, sat on the plate corner where thumbs and cursors reach it.
function M.closeButton(parent,name,size)
 size=size or 48
 local b=Instance.new('TextButton');b.Name=name;b.Text='X';b.AnchorPoint=Vector2.new(.5,.5);b.Size=UDim2.fromOffset(size,size)
 b.AutoButtonColor=false;b.Selectable=true;b.BorderSizePixel=0;b.BackgroundColor3=Color3.fromRGB(240,44,80);b.ZIndex=20
 b.FontFace=M.Font.Title;b.TextSize=math.floor(size*.5);b.TextColor3=M.Color.text;b.Parent=parent
 local g=Instance.new('UIGradient');g.Rotation=90;g.Color=ColorSequence.new(Color3.new(1,1,1),SHADE);g.Parent=b
 M.corner(b,UDim.new(1,0));M.stroke(b,Color3.fromRGB(255,255,255),3,0);M.selection(b,size)
 local sel=b.SelectionImageObject;if sel then sel.Size=UDim2.new(1,8,1,8);sel.Position=UDim2.fromOffset(-4,-4)end
 pressable(b)
 return b
end
-- Plate glides in from beyond the right edge (fast, no long overshoot) and pops up to full size as it lands.
function M.slideIn(holder,target,duration)
 duration=duration or .34
 holder.Position=UDim2.new(target.X.Scale+1,target.X.Offset+40,target.Y.Scale,target.Y.Offset)
 local pop=holder:FindFirstChild('PlatePop')
 if pop then pop.Scale=.9;TS:Create(pop,TweenInfo.new(duration*1.15,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()end
 local t=TS:Create(holder,TweenInfo.new(duration,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=target});t:Play();return t
end
function M.slideOut(holder,duration)
 local p=holder.Position
 local t=TS:Create(holder,TweenInfo.new(duration or .2,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Position=UDim2.new(p.X.Scale+1,p.X.Offset+40,p.Y.Scale,p.Y.Offset)});t:Play();return t
end
-- Cards are cells holding a centred 'Card' frame with a 'Pop' UIScale; rows pop in order, quickly.
-- Returns the tweens so the caller can cancel them on close / reopen.
-- elapsed: seconds since the entrance began, so a redraw mid-entrance (prices loading) continues the
-- same row timing instead of snapping to full size or restarting.
function M.popRows(cells,columns,startDelay,stagger,duration,elapsed)
 local tweens={}
 duration=duration or .26;elapsed=elapsed or 0
 table.sort(cells,function(a,b)return a.LayoutOrder<b.LayoutOrder end)
 columns=math.max(1,columns or 1)
 for i,cell in cells do
  local card=cell:FindFirstChild('Card');local pop=card and card:FindFirstChild('Pop')
  if pop then
   local row=math.floor((i-1)/columns)
   local delay=(startDelay or 0)+math.min(row,7)*(stagger or .055)-elapsed
   if delay+duration>0 then
    local left=duration;local from=0
    if delay<0 then from=math.clamp(-delay/duration,0,1);left=duration+delay;delay=0 end
    pop.Scale=from;card.Position=UDim2.new(.5,0,.5,16*(1-from))
    local a=TS:Create(pop,TweenInfo.new(left,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,false,delay),{Scale=1})
    local b=TS:Create(card,TweenInfo.new(left*.9,Enum.EasingStyle.Quart,Enum.EasingDirection.Out,0,false,delay),{Position=UDim2.fromScale(.5,.5)})
    a:Play();b:Play();table.insert(tweens,a);table.insert(tweens,b)
   end
  end
 end
 return tweens
end
-- Modal focus ------------------------------------------------------------------------------
-- Screens that must stay visible over any panel (round results, jumpscares, loading, rewards).
M.KeepVisible={MonsterJumpscare=true,MonsterWinCutscene=true,RoundRecap=true,BadgeEarnedToast=true,RunTokenReward=true,MansionLoading=true,Freecam=true,TouchGui=true,
 ShopTutorial=true} -- the shop chapter points at the panel's own buttons (TutorialClient.ShopTutorial)
local owners={};local hidden={};local promptsWere
function M.FocusAcquire(owner,ownGui)
 local first=next(owners)==nil
 owners[owner]=ownGui
 if hidden[ownGui]then hidden[ownGui]:Disconnect();hidden[ownGui]=nil;ownGui.Enabled=true end
 if not first then return end
 local pg=Players.LocalPlayer:FindFirstChildOfClass('PlayerGui')
 if pg then for _,g in pg:GetChildren()do
  if g:IsA('ScreenGui')and g.Enabled and not M.KeepVisible[g.Name]and g.DisplayOrder<500 then
   local mine=false;for _,o in owners do if o==g then mine=true end end
   if not mine then
    g.Enabled=false
    -- Scripts that re-show their screen while the panel is open (tutorial steps, HUD refreshes) are kept
    -- hidden until the panel closes; the screen then comes back because its owner wanted it shown.
    local conn;conn=g:GetPropertyChangedSignal('Enabled'):Connect(function()
     if g.Enabled and hidden[g]==conn then g.Enabled=false end
    end)
    hidden[g]=conn
   end
  end
 end end
 local ok,was=pcall(function()return PPS.Enabled end)
 if ok then promptsWere=was;pcall(function()PPS.Enabled=false end)end
end
function M.FocusRelease(owner)
 if owners[owner]==nil then return end
 owners[owner]=nil
 if next(owners)then return end
 local restore={}
 for g,c in hidden do c:Disconnect();table.insert(restore,g)end
 table.clear(hidden)
 for _,g in restore do if g.Parent and not g.Enabled then g.Enabled=true end end
 if promptsWere~=nil then local was=promptsWere;promptsWere=nil;pcall(function()PPS.Enabled=was end)end
end
function M.IsFocused()return next(owners)~=nil end
-- Controller focus that sticks: panels slide in from off screen, and a selection made before the target is
-- visible and on screen is dropped, so a gamepad player had to press View to get focus. This keeps applying
-- the selection until it holds for a few frames, and backs off as soon as the player moves it themselves.
local selectToken=0
local function shown(o)
 local x=o
 while x and not x:IsA('LayerCollector')do if x:IsA('GuiObject')and not x.Visible then return false end;x=x.Parent end
 return x~=nil and x.Enabled
end
function M.SelectWhenReady(o,timeout)
 -- o: a GuiObject, or a function returning the current target (panels rebuild their cards right after
 -- opening, e.g. prices loading, so a fixed object can be destroyed before focus lands).
 selectToken+=1;local token=selectToken
 local resolve=type(o)=='function'and o or function()return o end
 task.spawn(function()
  local deadline=os.clock()+(timeout or 2);local applied,stable,last=false,0,nil
  while token==selectToken and os.clock()<deadline do
   local target=resolve()
   local current=GS.SelectedObject
   -- The player moved focus to something real: leave it alone.
   if applied and current and current~=target and current~=last and current.Parent and not(target and target:IsDescendantOf(current))then return end
   if target and target:IsA('GuiObject')and target.Parent then
    local cam=workspace.CurrentCamera;local view=cam and cam.ViewportSize or Vector2.new(1e4,1e4)
    local pos,size=target.AbsolutePosition,target.AbsoluteSize
    local onScreen=size.X>0 and size.Y>0 and pos.X>=-4 and pos.X+size.X<=view.X+4 and pos.Y+size.Y>=0 and pos.Y<=view.Y
    if target.Selectable and onScreen and shown(target)then
     if current~=target then GS.SelectedObject=target;applied=true;stable=0;last=target else stable+=1;if stable>=8 then return end end
    end
   end
   Run.RenderStepped:Wait()
  end
 end)
end
return M
