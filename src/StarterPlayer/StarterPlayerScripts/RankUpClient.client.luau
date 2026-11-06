-- Presentation only. Server owns RR, rank transitions and cosmetic rewards.
-- No VR override: DDHVR.Loader leaves this owner active; its UI uses the native VR panel.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Tween=game:GetService('TweenService')
local player=Players.LocalPlayer
local Catalog=require(RS:WaitForChild('RankCatalog'))
local Audio=require(RS:WaitForChild('GameplayAudio'))
-- Shown BEFORE the round recap (tokens + RR) and a little quicker: the recap waits on the RankUpShowing attribute,
-- and a recap that is already open is hidden while the banner plays, so the two never overlap.
local BANNER_W,BANNER_H,SHOW_SECONDS=420,134,1.8
local IN_SECONDS,OUT_SECONDS=.18,.18
local PANEL=Color3.fromRGB(16,14,24)
local queue={}
local showing=false
local function text(parent,name,words,y,size,color)
 local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1
 t.Position=UDim2.fromOffset(112,y);t.Size=UDim2.new(1,-126,0,size+6)
 t.Font=Enum.Font.FredokaOne;t.Text=words;t.TextColor3=color or Color3.new(1,1,1)
 t.TextScaled=true;t.TextXAlignment=Enum.TextXAlignment.Left
 local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=10;limit.MaxTextSize=size;limit.Parent=t
 t.Parent=parent;return t
end
local function nextBanner()
 if showing or #queue==0 then return end
 showing=true;player:SetAttribute('RankUpShowing',true)
 local info=table.remove(queue,1)
 local tier=Catalog.Tiers[math.clamp(tonumber(info.tier)or 1,1,#Catalog.Tiers)]
 local color=Color3.fromRGB(tier.color[1],tier.color[2],tier.color[3])
 local gui=Instance.new('ScreenGui');gui.Name='RankUpBanner';gui.ResetOnSpawn=false
 gui.DisplayOrder=970;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
 local card=Instance.new('CanvasGroup');card.Name='Banner';card.AnchorPoint=Vector2.new(.5,.5)
 card.Size=UDim2.fromOffset(BANNER_W,BANNER_H);card.Position=UDim2.fromScale(.5,.43)
 card.BackgroundColor3=PANEL;card.BorderSizePixel=0;card.GroupTransparency=1;card.Parent=gui
 local round=Instance.new('UICorner');round.CornerRadius=UDim.new(0,16);round.Parent=card
 local rim=Instance.new('UIStroke');rim.Color=color;rim.Thickness=2;rim.Parent=card
 local scale=Instance.new('UIScale');scale.Parent=card
 local function layout()
  local cam=workspace.CurrentCamera;local vp=cam and cam.ViewportSize or Vector2.new(1280,720)
  scale.Scale=math.min(1,(vp.X-32)/BANNER_W,(vp.Y-32)/BANNER_H)
 end
 layout()
 local cam=workspace.CurrentCamera
 local connection=cam and cam:GetPropertyChangedSignal('ViewportSize'):Connect(layout)
 local icon=Instance.new('ImageLabel');icon.Name='RankIcon';icon.BackgroundTransparency=1
 icon.Size=UDim2.fromOffset(90,90);icon.Position=UDim2.fromOffset(12,22)
 -- Only catalog assets already present in the place are used.
 icon.Image=tier.icon;icon.ScaleType=Enum.ScaleType.Fit;icon.Parent=card
 text(card,'Heading',info.newTier and'NEW RANK!'or'RANK UP',12,18)
 text(card,'Rank',tostring(info.rank or tier.name),40,29,color)
 -- What this rank-up paid (rank rewards, 2026-10-22): a row of reward chips under the rank name.
 local gained=type(info.gained)=='table'and info.gained or {}
 local chips={}
 if (tonumber(gained.tokens)or 0)>0 then table.insert(chips,'+'..math.floor(gained.tokens)..' TOKENS')end
 for _,it in type(gained.items)=='table'and gained.items or {}do
  if type(it)=='table'then table.insert(chips,string.upper(tostring(it.name))..(it.kind=='Title'and' TITLE'or it.kind=='Aura'and' AURA'or it.kind=='Trail'and' TRAIL'or''))end
 end
 if #chips==0 and type(info.reward)=='table'then table.insert(chips,'+ '..tostring(info.reward.name))end
 if info.newTier then
  card.Size=UDim2.fromOffset(BANNER_W,BANNER_H+(#chips>2 and 62 or 34))
  -- A slow spinning shine behind the emblem on a new rank.
  local rays=Instance.new('ImageLabel');rays.Name='Shine';rays.BackgroundTransparency=1;rays.Image='rbxassetid://136893400437569'
  rays.ImageColor3=color;rays.Size=UDim2.fromOffset(150,150);rays.AnchorPoint=Vector2.new(.5,.5);rays.Position=UDim2.fromOffset(57,67);rays.ZIndex=0;rays.Parent=card
  Tween:Create(rays,TweenInfo.new(6,Enum.EasingStyle.Linear,Enum.EasingDirection.In,-1),{Rotation=360}):Play()
  icon.ZIndex=2
 end
 local row=Instance.new('Frame');row.Name='Rewards';row.BackgroundTransparency=1;row.Position=UDim2.fromOffset(112,84);row.Size=UDim2.new(1,-124,1,-92);row.Parent=card
 local grid=Instance.new('UIGridLayout');grid.CellSize=UDim2.new(.5,-4,0,26);grid.CellPadding=UDim2.fromOffset(6,6);grid.SortOrder=Enum.SortOrder.LayoutOrder;grid.Parent=row
 if #chips==1 then grid.CellSize=UDim2.new(1,0,0,26)end
 for i,words in chips do
  local chip=Instance.new('TextLabel');chip.Name='Chip'..i;chip.LayoutOrder=i;chip.BackgroundColor3=color:Lerp(PANEL,.55);chip.BorderSizePixel=0
  chip.Font=Enum.Font.FredokaOne;chip.Text=words;chip.TextColor3=Color3.new(1,1,1);chip.TextScaled=true;chip.Parent=row
  local cc=Instance.new('UICorner');cc.CornerRadius=UDim.new(0,8);cc.Parent=chip
  local cs=Instance.new('UIStroke');cs.Color=color;cs.Thickness=1.5;cs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;cs.Parent=chip
  local cp=Instance.new('UIPadding');cp.PaddingLeft=UDim.new(0,6);cp.PaddingRight=UDim.new(0,6);cp.PaddingTop=UDim.new(0,4);cp.PaddingBottom=UDim.new(0,4);cp.Parent=chip
  local cl=Instance.new('UITextSizeConstraint');cl.MaxTextSize=16;cl.Parent=chip
 end
 gui.Parent=player:WaitForChild('PlayerGui')
 local recap=player.PlayerGui:FindFirstChild('RoundRecap')
 local hidRecap=recap and recap:IsA('ScreenGui') and recap.Enabled and recap or nil
 if hidRecap then hidRecap.Enabled=false end
 local function done()
  showing=false
  if hidRecap and hidRecap.Parent then hidRecap.Enabled=true end
  if #queue==0 then player:SetAttribute('RankUpShowing',nil)end
  nextBanner()
 end
 Audio.Play('QuotaMet')
 Tween:Create(card,TweenInfo.new(IN_SECONDS,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{GroupTransparency=0,Position=UDim2.fromScale(.5,.46)}):Play()
 if info.newTier then -- a new rank pops: bigger, then settles
  scale.Scale*=1.25;Tween:Create(scale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=scale.Scale/1.25}):Play()
 end
 task.delay((info.newTier and SHOW_SECONDS+1.6 or SHOW_SECONDS+.4)+IN_SECONDS,function()
  if not gui.Parent then if connection then connection:Disconnect()end;done();return end
  local tw=Tween:Create(card,TweenInfo.new(OUT_SECONDS),{GroupTransparency=1,Position=UDim2.fromScale(.5,.43)})
  tw:Play();tw.Completed:Wait()
  if connection then connection:Disconnect()end
  gui:Destroy();done()
 end)
end
local function pulseOther(info)
 local other=Players:GetPlayerByUserId(tonumber(info.userId)or 0)
 if not other then return end
 task.spawn(function()
  local deadline=os.clock()+3
  local badge
  repeat
   local character=other.Character
   local cosmetics=character and character:FindFirstChild('ProgressCosmetics')
   local tag=cosmetics and cosmetics:FindFirstChild('LobbyNameTag',true)
   local found=tag and tag:FindFirstChild('RankBadge',true)
   if found and found:IsA('GuiObject')then badge=found;break end
   task.wait(.1)
  until os.clock()>=deadline or not other.Parent
  if not badge then return end
  local prior=badge:FindFirstChild('RankPromotionGlow');if prior then prior:Destroy()end
  local tier=Catalog.Tiers[math.clamp(tonumber(info.tier)or 1,1,#Catalog.Tiers)]
  local glow=Instance.new('UIStroke');glow.Name='RankPromotionGlow';glow.Color=Color3.fromRGB(tier.color[1],tier.color[2],tier.color[3])
  glow.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;glow.Thickness=2;glow.Transparency=1;glow.Parent=badge
  local pulse=Tween:Create(glow,TweenInfo.new(.35,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,2,true),{Transparency=.1,Thickness=4})
  pulse:Play();pulse.Completed:Wait();glow:Destroy()
 end)
end
local event=RS:WaitForChild('RankEvent',math.huge)
if event:IsA('RemoteEvent')then
 event.OnClientEvent:Connect(function(kind,info)
  if kind~='rankUp' or type(info)~='table' then return end
  if tonumber(info.userId)==player.UserId then
   if #queue<8 then table.insert(queue,info);nextBanner()end
  else pulseOther(info)end
 end)
end
