local C = require(game.ReplicatedStorage.LobbyShopCatalog)
local GS = game:GetService('GuiService')
local TS = game:GetService('TweenService')
local M = {}
-- Keyed by the parent's path so the main menu's full re-render keeps the chosen filter.
local filters = {}
local ORDER = {'Hat','Ring','Shirt','Shoes','Eyes','Back','Trail','Torch','Title','Aura'}
local LABEL = {All='ALL',Hat='HAT',Ring='RING',Shirt='INK',Shoes='KICKS',Eyes='EYES',Back='BACK',Trail='TRAIL',Torch='TORCH',Title='TITLE',Aura='AURA',Sets='SETS'}
local RANK = {}; for i,k in ipairs(ORDER) do RANK[k]=i end
local PANEL=Color3.fromRGB(22,42,43)
local CARD=Color3.fromRGB(31,55,53)
local CREAM=Color3.fromRGB(244,236,210)
local GREEN=Color3.fromRGB(167,202,127)
local INK=Color3.fromRGB(12,23,24)
local HOVER=Color3.fromRGB(42,70,64)
-- Optional 'neon' theme (van appearance panel): same cards and callbacks, black-glass colours.
local THEMES={
 default={PANEL=PANEL,CARD=CARD,CREAM=CREAM,GREEN=GREEN,INK=INK,HOVER=HOVER},
 neon={PANEL=Color3.fromRGB(34,34,44),CARD=Color3.fromRGB(24,24,31),CREAM=Color3.fromRGB(255,255,255),GREEN=Color3.fromRGB(52,222,104),INK=Color3.fromRGB(5,5,8),HOVER=Color3.fromRGB(40,40,52)},
}
local HEADER=24; local FILTER_Y=28; local FILTER_H=44; local LIST_Y=80
local GAP=8; local CARD_H=74; local GRID_THRESHOLD=300; local INSET=4
local function corner(o,r)
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,r);c.Parent=o
end
local function stroke(o,color,width)
 local s=Instance.new('UIStroke');s.Color=color;s.Thickness=width;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=o;return s
end
local function label(parent,name,text,pos,size,color,max)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=text;t.BackgroundTransparency=1;t.Position=pos;t.Size=size
 t.Font=Enum.Font.FredokaOne;t.TextColor3=color;t.TextScaled=true;t.TextWrapped=true;t.Parent=parent
 local c=Instance.new('UITextSizeConstraint');c.MinTextSize=9;c.MaxTextSize=max;c.Parent=t;return t
end
local function selection(b)
 local f=Instance.new('Frame');f.Name='FocusOutline';f.BackgroundTransparency=1;f.Size=UDim2.fromScale(1,1)
 -- Controller focus: gold ring just outside the card (same as the van panels).
 f.Size=UDim2.new(1,8,1,8);f.Position=UDim2.fromOffset(-4,-4)
 corner(f,16);stroke(f,Color3.fromRGB(255,206,64),3.5);b.SelectionImageObject=f
 -- SelectionImageObject must remain unparented so it is not drawn on unfocused cards.
 b.Destroying:Connect(function()f:Destroy()end)
end
function M.Draw(parent,progress,equip,options)
 progress=progress or {}
 options=options or {}
 local T=THEMES[options.theme or 'default']or THEMES.default
 local PANEL,CARD,CREAM,GREEN,INK,HOVER=T.PANEL,T.CARD,T.CREAM,T.GREEN,T.INK,T.HOVER
 local old=parent:FindFirstChild('OwnedCosmetics');local selected=GS.SelectedObject
 local focus=old and selected and selected:IsDescendantOf(old) and selected.Name
 if old then old:Destroy()end
 local root=Instance.new('Frame');root.Name='OwnedCosmetics';root.BackgroundTransparency=1;root.Size=UDim2.fromScale(1,1);root.Parent=parent
 label(root,'Heading',options.heading or 'OWNED COSMETICS',UDim2.fromOffset(0,0),UDim2.new(1,0,0,HEADER),options.headingColor or GREEN,16).TextXAlignment=Enum.TextXAlignment.Left
 local items={};local kinds={}
 for id,owned in pairs(progress.owned or {}) do
  local o=C.ById[id];if owned and o and RANK[o.kind] then table.insert(items,o);kinds[o.kind]=true end
 end
 table.sort(items,function(a,b)if a.kind~=b.kind then return RANK[a.kind]<RANK[b.kind]end;return a.name<b.name end)
 local key=parent:GetFullName()
 local active=filters[key] or 'All';if active~='All' and active~='Sets' and not kinds[active]then active='All'end;filters[key]=active
 local chips=Instance.new('ScrollingFrame');chips.Name='Filters';chips.BackgroundTransparency=1;chips.BorderSizePixel=0
 chips.Position=UDim2.fromOffset(0,FILTER_Y);chips.Size=UDim2.new(1,0,0,FILTER_H);chips.CanvasSize=UDim2.new();chips.AutomaticCanvasSize=Enum.AutomaticSize.X
 chips.ScrollingDirection=Enum.ScrollingDirection.X;chips.ScrollBarThickness=2;chips.Parent=root
 local flow=Instance.new('UIListLayout');flow.FillDirection=Enum.FillDirection.Horizontal;flow.Padding=UDim.new(0,6);flow.SortOrder=Enum.SortOrder.LayoutOrder;flow.Parent=chips
 local choices={'All'};for _,k in ipairs(ORDER)do if kinds[k]then table.insert(choices,k)end end
 if C.RewardCosmetics then table.insert(choices,'Sets')end
 for i,k in ipairs(choices)do
  local b=Instance.new('TextButton');b.Name='Filter_'..k;b.Text='';b.AutoButtonColor=false;b.Selectable=true;b.LayoutOrder=i
  b.Size=UDim2.fromOffset(k=='Title' and 64 or 58,FILTER_H);b.BackgroundColor3=k==active and GREEN or PANEL;b.Parent=chips;corner(b,12);stroke(b,INK,1);selection(b)
  label(b,'Label',LABEL[k],UDim2.fromOffset(3,3),UDim2.new(1,-6,1,-6),k==active and INK or CREAM,12)
  b.Activated:Connect(function()filters[key]=k;M.Draw(parent,progress,equip,{theme=options.theme,heading=options.heading,headingColor=options.headingColor,pop=false})end)
 end
-- [Haunted] (Haunted Mastery tag): owners can show or hide it over their head; hiding never removes it.
 if (progress.owned or {}).Tag_Haunted then
  local lp=game:GetService('Players').LocalPlayer
  local shown=lp:GetAttribute('ShowHauntedTag')~=false
  local t=Instance.new('TextButton');t.Name='HauntedToggle';t.Text='';t.AutoButtonColor=false;t.Selectable=true;t.LayoutOrder=#choices+1
  t.Size=UDim2.fromOffset(150,FILTER_H);t.BackgroundColor3=shown and Color3.fromRGB(60,110,80) or PANEL;t.Parent=chips;corner(t,12);stroke(t,INK,1);selection(t)
  label(t,'Label',shown and '[Haunted]: SHOWN' or '[Haunted]: HIDDEN',UDim2.fromOffset(4,3),UDim2.new(1,-8,1,-6),Color3.fromRGB(200,255,215),12)
  t.Activated:Connect(function()
   local f=game.ReplicatedStorage:FindFirstChild('Quests');f=f and f:FindFirstChild('ShowHaunted')
   if not f then return end
   task.spawn(function()
    pcall(function()f:InvokeServer(not shown)end)
    if root.Parent then M.Draw(parent,progress,equip,{theme=options.theme,heading=options.heading,headingColor=options.headingColor,pop=false})end
   end)
  end)
 end
 local list=Instance.new('ScrollingFrame');list.Name='List';list.BackgroundTransparency=1;list.BorderSizePixel=0
 list.Position=UDim2.fromOffset(0,LIST_Y);list.Size=UDim2.new(1,0,1,-LIST_Y);list.AutomaticCanvasSize=Enum.AutomaticSize.Y
 list.CanvasSize=UDim2.new();list.ScrollBarThickness=4;list.ScrollBarImageColor3=GREEN;list.Parent=root
 local padding=Instance.new('UIPadding');padding.PaddingLeft=UDim.new(0,INSET);padding.PaddingRight=UDim.new(0,INSET);padding.PaddingTop=UDim.new(0,INSET);padding.PaddingBottom=UDim.new(0,INSET);padding.Parent=list
 local grid=Instance.new('UIGridLayout');grid.CellPadding=UDim2.fromOffset(GAP,GAP);grid.SortOrder=Enum.SortOrder.LayoutOrder;grid.Parent=list
 local function resize()
  local columns=parent.AbsoluteSize.X>=GRID_THRESHOLD and 2 or 1
  grid.FillDirectionMaxCells=columns;grid.CellSize=UDim2.new(1/columns,-(INSET*2+4+GAP*(columns-1))/columns,0,CARD_H)
 end
 resize();local connection=parent:GetPropertyChangedSignal('AbsoluteSize'):Connect(resize)
 root.Destroying:Connect(function()connection:Disconnect()end)
 local shown=0;local first
 for _,o in ipairs(items)do if active~='Sets' and(active=='All' or o.kind==active)then
  shown=shown+1;local equipped=progress.equipped and progress.equipped[o.kind]==o.id
  local b=Instance.new('TextButton');b.Name='Equip_'..o.id;b.Text='';b.LayoutOrder=shown;b.AutoButtonColor=false;b.Selectable=true
  b.BackgroundColor3=CARD;b.Size=UDim2.fromOffset(140,CARD_H);b.Parent=list;corner(b,12);stroke(b,equipped and GREEN or INK,equipped and 2 or 1);selection(b);first=first or b
  local tile=Instance.new('Frame');tile.Name='IconTile';tile.Position=UDim2.fromOffset(8,9);tile.Size=UDim2.fromOffset(56,56)
  local rgb=o.color or {167,202,127};tile.BackgroundColor3=Color3.fromRGB(rgb[1],rgb[2],rgb[3]);tile.BackgroundTransparency=.65;tile.Parent=b;corner(tile,10)
  local icon=Instance.new('ImageLabel');icon.Name='Icon';icon.BackgroundTransparency=1;icon.Size=UDim2.new(1,-4,1,-4);icon.Position=UDim2.fromOffset(2,2)
  icon.Image=o.image or C.OfferImages[o.id] or ((o.id=='title_vip' or o.id=='aura_vip') and C.OfferImages.vip) or '';icon.ScaleType=Enum.ScaleType.Fit;icon.Parent=tile;corner(icon,8)
  label(b,'Name',o.name,UDim2.fromOffset(72,6),UDim2.new(1,-80,0,22),CREAM,15).TextXAlignment=Enum.TextXAlignment.Left
  label(b,'Slot',LABEL[o.kind],UDim2.fromOffset(72,28),UDim2.new(1,-80,0,12),GREEN,10).TextXAlignment=Enum.TextXAlignment.Left
  local pill=Instance.new('Frame');pill.Name='StatePill';pill.Position=UDim2.fromOffset(72,44);pill.Size=UDim2.new(1,-80,0,22);pill.BackgroundColor3=equipped and GREEN or PANEL;pill.Parent=b;corner(pill,9)
  label(pill,'State',equipped and 'EQUIPPED' or 'EQUIP',UDim2.fromOffset(3,2),UDim2.new(1,-6,1,-4),equipped and INK or CREAM,12)
  local scale=Instance.new('UIScale');scale.Parent=b
  local function feedback(on)
   TS:Create(b,TweenInfo.new(.12),{BackgroundColor3=on and HOVER or CARD}):Play()
  end
  if options.pop then
   -- Entrance only: cards pop in row by row, quickly (the caller passes pop on a real open).
   local row=math.floor((shown-1)/math.max(1,grid.FillDirectionMaxCells))
   scale.Scale=0
   TS:Create(scale,TweenInfo.new(.24,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,false,(options.popDelay or .12)+math.min(row,7)*.05),{Scale=1}):Play()
  end
  b.MouseEnter:Connect(function()feedback(true)end);b.MouseLeave:Connect(function()feedback(false)end)
  b.SelectionGained:Connect(function()feedback(true)end);b.SelectionLost:Connect(function()feedback(false)end)
  b.Activated:Connect(function()
   scale.Scale=.97;TS:Create(scale,TweenInfo.new(.12),{Scale=1}):Play()
   -- Use the latest supplied snapshot; never modify authoritative progress here.
   local isEquipped=progress.equipped and progress.equipped[o.kind]==o.id
   equip(isEquipped and '' or o.id,o.kind)
  end)
 end end
 if active=='Sets' then
  -- One row per map set: the four pieces (dim until owned), x/4, where each piece comes from, and the set aura.
  local sets={};local order={}
  for id,o in pairs(C.ById)do if o.set and o.releaseStage~='event' then
   if not sets[o.set]then sets[o.set]={};table.insert(order,o.set)end
   sets[o.set][o.kind]=o
  end end
  table.sort(order)
  grid.FillDirectionMaxCells=1;grid.CellSize=UDim2.new(1,-(INSET*2+4),0,CARD_H+22)
  local HOW={Hat='Weekly map quest',Ring='Token shop',Shirt='Token shop',Shoes='Token shop'}
  for i,setId in ipairs(order)do
   local s=sets[setId];local have=0
   local row=Instance.new('Frame');row.Name='Set_'..setId;row.LayoutOrder=i;row.BackgroundColor3=CARD;row.Parent=list;corner(row,12);stroke(row,INK,1)
   local aura=s.Aura;local auraOwned=aura and(progress.owned or {})[aura.id]
   local title=label(row,'Name',(aura and aura.name:gsub(' Aura','') or setId):upper()..' SET',UDim2.fromOffset(10,4),UDim2.new(.6,0,0,22),CREAM,16)
   title.TextXAlignment=Enum.TextXAlignment.Left
   for j,kind in ipairs({'Hat','Ring','Shirt','Shoes'})do
    local o=s[kind];local owned=o and(progress.owned or {})[o.id]
    if owned then have+=1 end
    local tile=Instance.new('ImageLabel');tile.Name='Piece_'..kind;tile.Position=UDim2.fromOffset(10+(j-1)*64,28);tile.Size=UDim2.fromOffset(56,56)
    tile.BackgroundColor3=PANEL;tile.Image=o and(C.OfferImages[o.id]or'')or'';tile.ImageTransparency=owned and 0 or .65;tile.Parent=row;corner(tile,10)
    if owned then stroke(tile,GREEN,2)end
    local how=label(tile,'How',owned and 'OWNED' or HOW[kind],UDim2.new(0,0,1,-14),UDim2.new(1,0,0,14),owned and GREEN or CREAM,9)
    how.BackgroundTransparency=.3;how.BackgroundColor3=INK
   end
   label(row,'Count',have..' / 4',UDim2.new(1,-120,0,30),UDim2.fromOffset(110,24),have==4 and GREEN or CREAM,18)
   label(row,'Aura',auraOwned and 'SET AURA UNLOCKED' or 'All 4: set aura',UDim2.new(1,-150,0,58),UDim2.fromOffset(140,20),auraOwned and GREEN or CREAM,11)
   shown+=1
  end
 end
 if shown==0 then
  local text=progress.ready and 'No cosmetics yet — unlock some in Store' or 'Loading cosmetics…'
  label(root,'Empty',text,UDim2.fromOffset(8,LIST_Y+12),UDim2.new(1,-16,0,64),CREAM,16)
 end
 if focus then
  GS.SelectedObject=list:FindFirstChild(focus) or chips:FindFirstChild(focus) or first or chips:FindFirstChild('Filter_All')
 end
 return root
end
return M
