-- Token goal hint: every time the player's token balance goes up, a small card above the "+N TOKENS" toast
-- names the nearest gameplay upgrade (Movement Speed, Stamina Capacity, Flashlight Strength), shows tokens / cost
-- and what the upgrade does. Upgrade tiers come from ProgressService (UpgradeTier_<Stat> attributes).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local TweenService=game:GetService('TweenService')
local p=Players.LocalPlayer
local C=require(RS:WaitForChild('LobbyShopCatalog'))

local SHOW_FOR=5
local CLOSE_AT=.6 -- "you're getting close" once this share of the cost is saved
local ROMAN={'I','II','III','IV','V'}
local colors={ink=Color3.fromRGB(8,18,22),panel=Color3.fromRGB(22,42,43),bar=Color3.fromRGB(12,26,28),cream=Color3.fromRGB(244,236,210),muted=Color3.fromRGB(157,181,171),gold=Color3.fromRGB(243,217,136),green=Color3.fromRGB(167,202,127)}
local UPGRADES={
 {stat='Speed',name='Movement Speed',benefit=function(t)local s=C.UpgradeStats.Speed[t+1];return ('Walk %g, sprint %g'):format(C.BaseSpeed.Walk+s[1],C.BaseSpeed.Sprint+s[2])end},
 {stat='Stamina',name='Stamina Capacity',benefit=function(t)return ('%d stamina (now %d)'):format(C.UpgradeStats.Stamina[t+1],C.UpgradeStats.Stamina[t])end},
 {stat='Flashlight',name='Flashlight Strength',benefit=function()return 'A wider, longer flashlight beam'end},
}

-- The cheapest next upgrade tier still to buy; ties keep the order above.
local function nextGoal()
 local best
 for _,u in ipairs(UPGRADES)do
  local tier=p:GetAttribute('UpgradeTier_'..u.stat)
  if typeof(tier)~='number' then return nil end
  local cost=C.UpgradeCosts[tier+1]
  if cost and(not best or cost<best.cost)then best={u=u,tier=tier,cost=cost}end
 end
 return best
end

local function label(parent,name,value,y,h,size,color)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=value;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne
 t.Position=UDim2.new(0,14,0,y);t.Size=UDim2.new(1,-28,0,h);t.TextSize=size;t.TextColor3=color;t.TextScaled=true
 t.TextXAlignment=Enum.TextXAlignment.Center;t.Parent=parent
 local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=size;c.MinTextSize=10;c.Parent=t
 return t
end

local shown=0
local function show()
 local goal=nextGoal();if not goal then return end
 local tokens=p:GetAttribute('Tokens')or 0
 local title=goal.u.name..' '..(ROMAN[goal.tier+1]or tostring(goal.tier+1))
 local headline,footer
 if tokens>=goal.cost then
  headline='You can unlock '..title..'!';footer='Spend your tokens in the token shop.'
 elseif tokens/goal.cost>=CLOSE_AT then
  headline="You're getting close to "..title..'!';footer='Keep going to get '..title..'.'
 else
  headline='Next upgrade: '..title;footer='Keep going to get '..title..'.'
 end
 shown+=1;local mine=shown
 local old=p.PlayerGui:FindFirstChild('TokenGoalHint');if old then old:Destroy()end
 -- In a mission the full card was too much mid-run (owner, 2026-10-22): a small one-line pill out of the way instead,
 -- top-left on phones, above the health bar on PC; 3 s, slides in and fades. The lobby keeps the full card.
 if p:GetAttribute('MissionActive')==true then
  local touch=require(RS:WaitForChild('InputHints')).Get()=='touch'
  local gui=Instance.new('ScreenGui');gui.Name='TokenGoalHint';gui.ResetOnSpawn=false;gui.DisplayOrder=600;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=p.PlayerGui
  local pill=Instance.new('CanvasGroup');pill.Name='Pill';pill.BackgroundColor3=colors.panel;pill.BackgroundTransparency=.1;pill.BorderSizePixel=0;pill.GroupTransparency=1
  pill.Size=UDim2.fromOffset(touch and 220 or 250,34);pill.AnchorPoint=touch and Vector2.new(0,0)or Vector2.new(0,1)
  local home=touch and UDim2.new(0,12,0,106)or UDim2.new(0,16,1,-172) -- phones: left edge, under the MAP button (owner, 2026-10-22)
  pill.Position=home+UDim2.fromOffset(-30,0);pill.Parent=gui
  local pc=Instance.new('UICorner');pc.CornerRadius=UDim.new(0,10);pc.Parent=pill
  local ps=Instance.new('UIStroke');ps.Color=colors.ink;ps.Thickness=2;ps.Parent=pill
  local line=tokens>=goal.cost and('READY: '..title)or title
  local name=label(pill,'Goal',line,3,14,13,tokens>=goal.cost and colors.gold or colors.cream);name.TextXAlignment=Enum.TextXAlignment.Left;name.Position=UDim2.fromOffset(10,3);name.Size=UDim2.new(1,-90,0,14)
  local track=Instance.new('Frame');track.Position=UDim2.fromOffset(10,21);track.Size=UDim2.new(1,-20,0,7);track.BackgroundColor3=colors.bar;track.BorderSizePixel=0;track.Parent=pill
  local tc=Instance.new('UICorner');tc.CornerRadius=UDim.new(1,0);tc.Parent=track
  local fill=Instance.new('Frame');fill.Size=UDim2.fromScale(math.clamp(tokens/goal.cost,0,1),1);fill.BackgroundColor3=colors.green;fill.BorderSizePixel=0;fill.Parent=track
  local fc=Instance.new('UICorner');fc.CornerRadius=UDim.new(1,0);fc.Parent=fill
  local count=label(pill,'Count',('%d/%d'):format(math.min(tokens,goal.cost),goal.cost),3,14,12,colors.muted);count.TextXAlignment=Enum.TextXAlignment.Right;count.Position=UDim2.new(1,-82,0,3);count.Size=UDim2.fromOffset(72,14)
  -- Noticeable without being in the way: a bouncy pop-in, a chime, and a glowing outline (gold and pulsing when ready).
  local ready=tokens>=goal.cost
  ps.Color=ready and colors.gold or colors.green;ps.Thickness=ready and 3 or 2
  local pop=Instance.new('UIScale');pop.Scale=.6;pop.Parent=pill
  TweenService:Create(pill,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{GroupTransparency=0,Position=home}):Play()
  TweenService:Create(pop,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
  if ready then TweenService:Create(ps,TweenInfo.new(.55,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Transparency=.6}):Play()end
  pcall(function()require(RS:WaitForChild('GameplayAudio')).Play(ready and 'QuotaMet' or 'UiOpen')end)
  task.delay(4.5,function()
   if shown~=mine or not gui.Parent then return end
   TweenService:Create(pill,TweenInfo.new(.4),{GroupTransparency=1}):Play();task.delay(.45,function()if gui.Parent then gui:Destroy()end end)
  end)
  return
 end
 local gui=Instance.new('ScreenGui');gui.Name='TokenGoalHint';gui.ResetOnSpawn=false;gui.DisplayOrder=600
 gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=p.PlayerGui
 local card=Instance.new('Frame');card.Name='Card';card.AnchorPoint=Vector2.new(.5,1);card.Position=UDim2.new(.5,0,.72,-40)
 card.Size=UDim2.fromOffset(300,112);card.BackgroundColor3=colors.panel;card.BorderSizePixel=0;card.Parent=gui
 local sizeLimit=Instance.new('UISizeConstraint');sizeLimit.MaxSize=Vector2.new(280,112);sizeLimit.Parent=card
 card.Size=UDim2.new(.92,0,0,112)
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,14);corner.Parent=card
 local stroke=Instance.new('UIStroke');stroke.Color=colors.ink;stroke.Thickness=3;stroke.Parent=card
 label(card,'Headline',headline,8,24,18,colors.gold)
 label(card,'Benefit',goal.u.benefit(goal.tier+1),33,18,14,colors.muted)
 local track=Instance.new('Frame');track.Name='Progress';track.Position=UDim2.new(0,16,0,56);track.Size=UDim2.new(1,-32,0,20)
 track.BackgroundColor3=colors.bar;track.BorderSizePixel=0;track.Parent=card
 local tc=Instance.new('UICorner');tc.CornerRadius=UDim.new(0,10);tc.Parent=track
 local fill=Instance.new('Frame');fill.Name='Fill';fill.Size=UDim2.fromScale(0,1);fill.BackgroundColor3=colors.green;fill.BorderSizePixel=0;fill.Parent=track
 local fc=Instance.new('UICorner');fc.CornerRadius=UDim.new(0,10);fc.Parent=fill
 local count=label(track,'Count',('%d / %d tokens'):format(math.min(tokens,goal.cost),goal.cost),1,18,14,colors.cream)
 count.Position=UDim2.new(0,0,0,1);count.Size=UDim2.new(1,0,1,-2);count.ZIndex=2
 label(card,'Footer',footer,82,20,14,colors.cream)
 TweenService:Create(fill,TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromScale(math.clamp(tokens/goal.cost,0,1),1)}):Play()
 task.delay(SHOW_FOR,function()if shown==mine and gui.Parent then gui:Destroy()end end)
end

local last=p:GetAttribute('Tokens')
p:GetAttributeChangedSignal('Tokens'):Connect(function()
 local now=p:GetAttribute('Tokens')
 local gained=typeof(now)=='number' and typeof(last)=='number' and now>last
 last=now
 if not gained then return end -- first load and spending stay quiet
 task.spawn(function()
  -- A van gift being opened holds the token toast until COLLECT; this card waits with it.
  local held=os.clock();while p:GetAttribute('VanRewardHold')and os.clock()-held<30 do task.wait(.1)end
  show()
 end)
end)
