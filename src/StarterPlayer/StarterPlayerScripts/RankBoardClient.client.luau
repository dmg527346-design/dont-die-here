-- Rank Rewards board (2026-10-22): the lobby's RankBoard (opposite the mastery board) shows every rank, what it
-- takes to get there and what it pays, for the player looking at it. Presentation only: the server pays the rewards
-- (ProgressCore rrGrant) and publishes RR and RRRewardStep as player attributes.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Tween=game:GetService('TweenService')
local Ranks=require(RS:WaitForChild('RankCatalog'))
local C=require(RS:WaitForChild('LobbyShopCatalog'))
local p=Players.LocalPlayer
local pg=p:WaitForChild('PlayerGui')

-- Van rank panel (owner 2026-10-29): your rank as its own 3D panel on the van wall, in the open space under the van
-- leaderboard (RecoveryModels VanLeaderboard). It copies the HUD rank card: RANK tab, rank badge, rank name, RR,
-- progress bar and 'N RR TO <next>'. Newcomer is a rank like any other. Built on this client (everyone sees their own).
task.spawn(function()
 local NAVY,EDGE,TAB=Color3.fromRGB(34,32,46),Color3.fromRGB(96,94,112),Color3.fromRGB(196,198,214)
 local built,panel,parts
 local nameLabel,rrLabel,fill,nextLabel,badge
 local function lbl(parent,txt,x,y,w,h,color,size,align)
  local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Text=txt;t.TextColor3=color;t.TextScaled=true;t.TextXAlignment=align or Enum.TextXAlignment.Left
  t.Position=UDim2.fromScale(x,y);t.Size=UDim2.fromScale(w,h);t.Parent=parent
  local k=Instance.new('UITextSizeConstraint');k.MaxTextSize=size;k.Parent=t
  return t
 end
 local function draw()
  if not nameLabel then return end
  local rr=tonumber(p:GetAttribute('RR'))or 0
  local r=Ranks.Get(rr);local lo,hi=Ranks.Progress(rr)
  badge.Image=r.icon or'';nameLabel.Text=string.upper(r.name);rrLabel.Text=math.floor(rr)..' RR'
  fill.BackgroundColor3=r.color;fill.Size=UDim2.fromScale(hi and math.clamp((rr-lo)/math.max(1,hi-lo),0,1)or 1,1)
  nextLabel.Text=hi and((hi-math.floor(rr))..' RR TO '..string.upper(Ranks.Get(hi).name))or'TOP RANK!'
 end
 local function build(board)
  if parts then parts:Destroy()end
  -- Under the board on the same wall: 5.6 x 2.3 studs, its top 0.35 below the board's bottom edge.
  local w,h=5.6,2.3
  local at=board.CFrame*CFrame.new(0,-board.Size.Y/2-.35-h/2,0)+board.CFrame.LookVector*.02
  parts=Instance.new('Model');parts.Name='VanRankPanel'
  local function part(name,size,cf,color,mat)
   local x=Instance.new('Part');x.Name=name;x.Size=size;x.CFrame=cf;x.Color=color;x.Material=mat;x.Anchored=true;x.CanCollide=false
   x.CanQuery=false;x.CanTouch=false;x.CastShadow=false;x.Parent=parts;return x
  end
  part('Rim',Vector3.new(w+.16,h+.16,board.Size.Z*.6),at*CFrame.new(0,0,.04),EDGE,Enum.Material.SmoothPlastic)
  panel=part('Panel',Vector3.new(w,h,board.Size.Z*.7),at,NAVY,Enum.Material.SmoothPlastic)
  parts.Parent=board.Parent
  local g=Instance.new('SurfaceGui');g.Name='RankCard';g.Face=Enum.NormalId.Front;g.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;g.CanvasSize=Vector2.new(560,230)
  g.LightInfluence=0;g.MaxDistance=50;g.Parent=panel
  -- the RANK tab across the top edge, like the HUD card
  local tab=Instance.new('Frame');tab.BackgroundColor3=TAB;tab.Position=UDim2.fromScale(.28,.02);tab.Size=UDim2.fromScale(.17,.16);tab.Parent=g
  Instance.new('UICorner',tab).CornerRadius=UDim.new(0,8)
  lbl(tab,'RANK',0,0,1,1,Color3.fromRGB(30,30,42),30,Enum.TextXAlignment.Center)
  -- round badge with the rank emblem
  local ring=Instance.new('Frame');ring.BackgroundColor3=Color3.fromRGB(22,20,30);ring.Position=UDim2.fromScale(.03,.18);ring.Size=UDim2.fromScale(.26,.63);ring.Parent=g
  local ar=Instance.new('UIAspectRatioConstraint');ar.AspectRatio=1;ar.Parent=ring
  Instance.new('UICorner',ring).CornerRadius=UDim.new(1,0)
  local rs=Instance.new('UIStroke');rs.Color=Color3.fromRGB(200,202,214);rs.Thickness=4;rs.Parent=ring
  badge=Instance.new('ImageLabel');badge.BackgroundTransparency=1;badge.AnchorPoint=Vector2.new(.5,.5);badge.Position=UDim2.fromScale(.5,.5);badge.Size=UDim2.fromScale(.78,.78);badge.Parent=ring
  nameLabel=lbl(g,'',.33,.24,.45,.17,Color3.fromRGB(226,226,236),38)
  rrLabel=lbl(g,'',.78,.24,.19,.17,Color3.fromRGB(120,230,220),34,Enum.TextXAlignment.Right)
  local bar=Instance.new('Frame');bar.BackgroundColor3=Color3.fromRGB(58,58,70);bar.Position=UDim2.fromScale(.33,.5);bar.Size=UDim2.fromScale(.64,.09);bar.Parent=g
  Instance.new('UICorner',bar).CornerRadius=UDim.new(1,0)
  fill=Instance.new('Frame');fill.Size=UDim2.fromScale(0,1);fill.Parent=bar
  Instance.new('UICorner',fill).CornerRadius=UDim.new(1,0)
  nextLabel=lbl(g,'',.33,.68,.64,.14,Color3.fromRGB(206,206,218),28)
  built=board;draw()
 end
 p:GetAttributeChangedSignal('RR'):Connect(draw)
 while true do
  local camp=workspace:FindFirstChild('RecoveryCamp');local board=camp and camp:FindFirstChild('VanLeaderboard',true)
  if board and board:IsA('BasePart')and(board~=built or not(parts and parts.Parent))then build(board)end
  task.wait(2)
 end
end)
local board=workspace:WaitForChild('LobbyWorld'):WaitForChild('RankBoard',30)
local face=board and board:WaitForChild('RankFace',30)
if not face then return end

local INK=Color3.fromRGB(5,5,8)
local GOLD=Color3.fromRGB(255,214,96)
local MUTED=Color3.fromRGB(150,145,170)
local DIM=Color3.fromRGB(70,66,88)
local function rgb(t)return Color3.fromRGB(t[1],t[2],t[3])end
local function text(parent,name,words,x,y,w,h,color,max,align)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=words;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true
 t.TextColor3=color or Color3.new(1,1,1);t.TextXAlignment=align or Enum.TextXAlignment.Center
 t.Position=UDim2.fromScale(x,y);t.Size=UDim2.fromScale(w,h);t.Parent=parent
 local k=Instance.new('UITextSizeConstraint');k.MaxTextSize=max or 200;k.Parent=t
 local o=Instance.new('UIStroke');o.Color=INK;o.Thickness=3;o.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;o.Parent=t
 return t
end
local function frame(parent,name,x,y,w,h,color,radius)
 local f=Instance.new('Frame');f.Name=name;f.BackgroundColor3=color;f.BorderSizePixel=0;f.Position=UDim2.fromScale(x,y);f.Size=UDim2.fromScale(w,h);f.Parent=parent
 if radius then local c=Instance.new('UICorner');c.CornerRadius=radius;c.Parent=f end
 return f
end
local function kindWord(kind)return kind=='Title'and'TITLE'or kind=='Aura'and'AURA'or kind=='Trail'and'TRAIL'or string.upper(tostring(kind))end

-- Build ------------------------------------------------------------------------------------------------
local gui=Instance.new('SurfaceGui');gui.Name='RankBoardUI';gui.Adornee=face;gui.Face=Enum.NormalId.Front
gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(1600,math.floor(1600*face.Size.Y/math.max(.1,face.Size.X)))
gui.LightInfluence=0;gui.Brightness=1.4;gui.ResetOnSpawn=false;gui.ZOffset=1;gui.Parent=pg
local bg=frame(gui,'Back',0,0,1,1,Color3.new(1,1,1),UDim.new(0,40))
local fill=Instance.new('UIGradient');fill.Rotation=90;fill.Color=ColorSequence.new(Color3.fromRGB(40,30,20),Color3.fromRGB(10,9,16));fill.Parent=bg
local rim=Instance.new('UIStroke');rim.Thickness=12;rim.Color=Color3.new(1,1,1);rim.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rim.Parent=bg
local rg=Instance.new('UIGradient');rg.Color=ColorSequence.new(GOLD,Color3.fromRGB(150,120,255));rg.Rotation=30;rg.Parent=rim
local title=text(bg,'Title','RANK REWARDS',.035,.025,.5,.115,Color3.new(1,1,1),180,Enum.TextXAlignment.Left)
local tg=Instance.new('UIGradient');tg.Rotation=90;tg.Color=ColorSequence.new(Color3.fromRGB(255,240,170),Color3.fromRGB(255,170,40));tg.Parent=title
text(bg,'Sub','WIN LEVELS TO EARN RR  ·  EVERY NEW RANK PAYS\nREWARDS ARE YOURS FOREVER',.037,.145,.52,.07,MUTED,34,Enum.TextXAlignment.Left)
text(bg,'YouLabel','YOUR RANK',.6,.03,.365,.04,MUTED,50,Enum.TextXAlignment.Right)
local youRank=text(bg,'YouRank','',.6,.068,.365,.075,Color3.new(1,1,1),120,Enum.TextXAlignment.Right)
local youNext=text(bg,'YouNext','',.6,.15,.365,.045,GOLD,60,Enum.TextXAlignment.Right)

-- The ladder: one card per rank above Newcomer, joined by a progress line behind them.
local tiers={};for i=2,#Ranks.Tiers do table.insert(tiers,i)end
local n=#tiers
local CARD_W,GAP,X0,Y0,CARD_H=.122,.0145,.03,.235,.6
local line=frame(bg,'Line',X0+CARD_W/2,Y0+.075,(n-1)*(CARD_W+GAP),.012,Color3.fromRGB(30,28,40),UDim.new(1,0))
local lineFill=frame(line,'Fill',0,0,0,1,GOLD,UDim.new(1,0))
local lfg=Instance.new('UIGradient');lfg.Color=ColorSequence.new(Color3.fromRGB(140,214,150),GOLD);lfg.Parent=lineFill
local cards={}
for k,ti in tiers do
 local t=Ranks.Tiers[ti];local tint=rgb(t.color)
 local x=X0+(k-1)*(CARD_W+GAP)
 local card=frame(bg,'Rank'..ti,x,Y0,CARD_W,CARD_H,Color3.new(1,1,1),UDim.new(0,26))
 local cg=Instance.new('UIGradient');cg.Rotation=90;cg.Color=ColorSequence.new(tint:Lerp(Color3.fromRGB(20,18,30),.72),Color3.fromRGB(12,11,18));cg.Parent=card
 local stroke=Instance.new('UIStroke');stroke.Thickness=6;stroke.Color=tint;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=card
 local halo=frame(card,'Halo',.12,.025,.76,.27,tint,UDim.new(1,0));halo.BackgroundTransparency=.75;halo.SizeConstraint=Enum.SizeConstraint.RelativeXX;halo.Size=UDim2.fromScale(.76,.76)
 local icon=Instance.new('ImageLabel');icon.Name='Emblem';icon.BackgroundTransparency=1;icon.Image=t.icon;icon.ScaleType=Enum.ScaleType.Fit
 icon.SizeConstraint=Enum.SizeConstraint.RelativeXX;icon.Position=UDim2.fromScale(.1,.015);icon.Size=UDim2.fromScale(.8,.8);icon.Parent=card
 text(card,'Name',string.upper(t.name),.05,.29,.9,.075,tint,70)
 text(card,'Need',t.min..' RR',.05,.365,.9,.045,MUTED,44)
 -- rewards, one line each
 local lines={'+'..(t.tokens or 0)..' TOKENS'}
 for _,id in {t.reward,t.reward2,t.reward3}do local c=id and C.ById[id];if c then table.insert(lines,string.upper(c.name)..'|'..kindWord(c.kind))end end
 local list=Instance.new('Frame');list.Name='Rewards';list.BackgroundTransparency=1;list.Position=UDim2.fromScale(.06,.435);list.Size=UDim2.fromScale(.88,.43);list.Parent=card
 local ll=Instance.new('UIListLayout');ll.Padding=UDim.new(.025,0);ll.Parent=list
 for i,words in lines do
  local chip=frame(list,'Reward'..i,0,0,1,.21,i==1 and Color3.fromRGB(60,50,20)or tint:Lerp(Color3.fromRGB(14,12,20),.6),UDim.new(0,14));chip.LayoutOrder=i
  local name,kind=string.match(words,'^(.-)|(.+)$')
  if name then
   text(chip,'Name',name,.05,.06,.9,.56,Color3.new(1,1,1),40)
   text(chip,'Kind',kind,.05,.6,.9,.34,tint:Lerp(Color3.new(1,1,1),.45),26)
  else
   text(chip,'Tokens',words,.05,.12,.9,.76,GOLD,40)
  end
 end
 local state=text(card,'State','',.05,.885,.9,.08,Color3.new(1,1,1),48)
 local lock=text(card,'Lock','🔒',.68,.02,.3,.12,Color3.new(1,1,1),60)
 cards[ti]={card=card,stroke=stroke,state=state,icon=icon,halo=halo,lock=lock,tint=tint,cg=cg}
end
local foot=frame(bg,'Footer',.03,.875,.94,.09,Color3.fromRGB(20,16,30),UDim.new(0,24))
local fs=Instance.new('UIStroke');fs.Thickness=5;fs.Color=GOLD;fs.Transparency=.35;fs.Parent=foot
text(foot,'Divisions','EVERY DIVISION STEP (I → II → III) PAYS +'..Ranks.DIVISION_TOKENS..' TOKENS',.025,.15,.62,.7,GOLD,64,Enum.TextXAlignment.Left)
local paidText=text(foot,'Paid','',.65,.15,.325,.7,Color3.new(1,1,1),56,Enum.TextXAlignment.Right)

-- Draw ---------------------------------------------------------------------------------------------------
local pulse
local function draw()
 local rr=tonumber(p:GetAttribute('RR'))
 if not rr then youRank.Text='LOADING…';return end
 local r=Ranks.Get(rr);local step=math.max(Ranks.Step(rr),tonumber(p:GetAttribute('RRRewardStep'))or 1)
 youRank.Text=string.upper(r.name)..'  ·  '..math.floor(rr)..' RR';youRank.TextColor3=r.color
 local nextTier=Ranks.Tiers[r.tier+1]
 youNext.Text=nextTier and((nextTier.min-math.floor(rr))..' RR TO '..string.upper(nextTier.name))or'TOP RANK REACHED'
 -- earned so far (tier tokens and division tokens of every step reached)
 local earned=0;for s=2,step do earned+=Ranks.StepReward(s).tokens end
 paidText.Text='YOU HAVE EARNED '..earned..' TOKENS FROM RANKS'
 local reachedCount=0
 if pulse then pulse:Cancel();pulse=nil end
 for k,ti in tiers do
  local c=cards[ti];local t=Ranks.Tiers[ti]
  local reached=step>=(ti-1)*3+1
  local isNext=not reached and(k==1 or step>=(tiers[k-1]-1)*3+1)
  if reached then reachedCount=k end
  c.lock.Visible=not reached
  c.icon.ImageTransparency=reached and 0 or isNext and .15 or .55
  c.halo.BackgroundTransparency=reached and .6 or .88
  c.stroke.Color=reached and GOLD or isNext and c.tint or DIM;c.stroke.Thickness=reached and 7 or isNext and 8 or 4;c.stroke.Transparency=0
  if reached then c.state.Text='UNLOCKED!';c.state.TextColor3=Color3.fromRGB(140,255,170)
  elseif isNext then c.state.Text=(t.min-math.floor(rr))..' RR TO GO';c.state.TextColor3=GOLD
   pulse=Tween:Create(c.stroke,TweenInfo.new(.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Transparency=.6});pulse:Play()
  else c.state.Text='LOCKED';c.state.TextColor3=MUTED end
 end
 -- progress line: full segments up to the reached card, plus the share of the way to the next one
 local frac=0
 if reachedCount>0 then frac=(reachedCount-1)/(n-1)end
 local nt=tiers[reachedCount+1]
 if nt and reachedCount>0 then
  local lo,hi=Ranks.Tiers[nt-1].min,Ranks.Tiers[nt].min
  frac+=math.clamp((rr-lo)/math.max(1,hi-lo),0,1)/(n-1)
 end
 lineFill.Size=UDim2.fromScale(math.clamp(frac,0,1),1)
end
draw()
p:GetAttributeChangedSignal('RR'):Connect(draw)
p:GetAttributeChangedSignal('RRRewardStep'):Connect(draw)
