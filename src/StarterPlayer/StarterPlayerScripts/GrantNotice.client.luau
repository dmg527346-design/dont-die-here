-- Grant notice: a card in the middle of the screen when the server grants something the player did not buy just now
-- (ProgressService sets the GrantNotice attribute, e.g. the 2026-10-17 free Jumpscare Everyone charge).
local Players=game:GetService('Players')
local GuiService=game:GetService('GuiService')
local RS=game:GetService('ReplicatedStorage')
local InputHints=require(RS:WaitForChild('InputHints'))
local p=Players.LocalPlayer

local NOTICES={
 jumpscare={title='FREE JUMPSCARE!',body="We fixed Jumpscare Everyone. Thanks for buying it: here is 1 free charge, banked in your ROBUX menu.",hint='Use it in a game from the ROBUX panel in the van. It needs a teammate.'},
}
local colors={ink=Color3.fromRGB(8,18,22),panel=Color3.fromRGB(22,42,43),cream=Color3.fromRGB(244,236,210),muted=Color3.fromRGB(157,181,171),red=Color3.fromRGB(235,90,90),green=Color3.fromRGB(167,202,127)}

local function text(parent,name,value,y,h,size,color)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=value;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextWrapped=true
 t.Position=UDim2.new(0,18,0,y);t.Size=UDim2.new(1,-36,0,h);t.TextSize=size;t.TextColor3=color;t.TextScaled=true;t.Parent=parent
 local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=size;c.MinTextSize=10;c.Parent=t
 return t
end

local showing=false
-- Owner appreciation award: a gold card that pops in over slowly turning light rays, one row per reward.
local Tween=game:GetService('TweenService')
local Run=game:GetService('RunService')
local gold,goldDeep=Color3.fromRGB(255,206,84),Color3.fromRGB(120,82,20)
local AWARD_ROWS={{'FLASHLIGHT COLORS','Free game pass: any beam colour'},{'3 REVIVE TOKENS','Get back up when a run goes wrong'},{'500 TOKENS','For cosmetics and upgrades'}}
-- Each award winner gets their own colour (gold for anyone else, e.g. the owner's preview).
local AWARD_COLORS={
 [3184980922]=Color3.fromRGB(255,86,86),   -- red
 [1768534720]=Color3.fromRGB(190,120,255), -- purple
 [10083716019]=Color3.fromRGB(110,230,120),-- green
 [7552093693]=Color3.fromRGB(120,205,255), -- light blue
}
local function showAward(kind)
 if showing then return end
 showing=true
 if not p.Character then p.CharacterAdded:Wait()end
 -- Studio only: ReplicatedStorage attribute OwnerAwardPreviewUser = a winner's UserId previews that winner's card
 local who={id=p.UserId,display=p.DisplayName,name=p.Name}
 local previewId=Run:IsStudio()and RS:GetAttribute('OwnerAwardPreviewUser')
 if type(previewId)=='number'and previewId>0 then
  who.id=previewId
  local okName,name=pcall(function()return Players:GetNameFromUserIdAsync(previewId)end)
  who.name=okName and name or tostring(previewId);who.display=who.name
 end
 local gold=AWARD_COLORS[who.id]or gold
 local goldDeep=gold:Lerp(Color3.new(),.55)
 task.wait(3)
 local gui=Instance.new('ScreenGui');gui.Name='GrantNotice';gui.ResetOnSpawn=false;gui.DisplayOrder=900;gui.IgnoreGuiInset=true;gui.Parent=p:WaitForChild('PlayerGui')
 local shade=Instance.new('Frame');shade.Name='Shade';shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new();shade.BackgroundTransparency=1;shade.BorderSizePixel=0;shade.Parent=gui
 Tween:Create(shade,TweenInfo.new(.4),{BackgroundTransparency=.4}):Play()
 local holder=Instance.new('Frame');holder.Name='Holder';holder.AnchorPoint=Vector2.new(.5,.5);holder.Position=UDim2.new(.5,0,.5,30);holder.Size=UDim2.fromOffset(460,396);holder.BackgroundTransparency=1;holder.Parent=gui
 local limit=Instance.new('UISizeConstraint');limit.MaxSize=Vector2.new(460,396);limit.Parent=holder
 local scale=Instance.new('UIScale');scale.Scale=.4;scale.Parent=holder
 -- light rays behind the card
 local rays=Instance.new('Frame');rays.Name='Rays';rays.AnchorPoint=Vector2.new(.5,.5);rays.Position=UDim2.fromScale(.5,.5);rays.Size=UDim2.fromOffset(620,620);rays.BackgroundTransparency=1;rays.ZIndex=0;rays.Parent=holder
 for i=0,7 do
  local r=Instance.new('Frame');r.AnchorPoint=Vector2.new(.5,.5);r.Position=UDim2.fromScale(.5,.5);r.Size=UDim2.new(0,46,1,0);r.Rotation=i*22.5;r.BorderSizePixel=0;r.BackgroundColor3=gold;r.BackgroundTransparency=.45;r.ZIndex=0;r.Parent=rays
  local g=Instance.new('UIGradient');g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.2),NumberSequenceKeypoint.new(1,1)});g.Rotation=90;g.Parent=r
 end
 local spin=Run.RenderStepped:Connect(function(dt)rays.Rotation=(rays.Rotation+dt*12)%360 end)
 local card=Instance.new('Frame');card.Name='Card';card.Size=UDim2.fromScale(1,1);card.BackgroundColor3=colors.panel;card.BorderSizePixel=0;card.ZIndex=2;card.Parent=holder
 Instance.new('UICorner',card).CornerRadius=UDim.new(0,18)
 local stroke=Instance.new('UIStroke');stroke.Color=gold;stroke.Thickness=4;stroke.Parent=card
 local sheen=Instance.new('UIGradient');sheen.Color=ColorSequence.new(gold,goldDeep);sheen.Rotation=45;sheen.Parent=stroke
 -- the player's avatar headshot in a gold ring, sitting on the card's top edge
 local avatar=Instance.new('ImageLabel');avatar.Name='Avatar';avatar.AnchorPoint=Vector2.new(.5,.5);avatar.Position=UDim2.new(.5,0,0,4);avatar.Size=UDim2.fromOffset(96,96)
 avatar.BackgroundColor3=colors.ink;avatar.BorderSizePixel=0;avatar.ZIndex=5;avatar.Parent=card
 Instance.new('UICorner',avatar).CornerRadius=UDim.new(1,0)
 local ring=Instance.new('UIStroke');ring.Color=gold;ring.Thickness=4;ring.Parent=avatar
 task.spawn(function()
  local ok,image=pcall(function()return Players:GetUserThumbnailAsync(who.id,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size150x150)end)
  if ok and avatar.Parent then avatar.Image=image end
 end)
 local function label(name,value,y,h,size,color)
  local t=text(card,name,value,y,h,size,color);t.ZIndex=3;return t
 end
 label('Crown','\u{2605}  OWNER APPRECIATION AWARD  \u{2605}',60,22,15,gold)
 label('Title','TOP 4 COLLECTOR',84,40,34,colors.cream)
 label('GrantedTo','GRANTED TO '..who.display:upper()..(who.display~=who.name and ' (@'..who.name..')' or ''),126,20,17,gold)
 label('Body',"Thank you for playing Don't Die Here! Here is a gift from the owner:",148,36,14,colors.muted)
 for i,row in AWARD_ROWS do
  local f=Instance.new('Frame');f.Name='Reward'..i;f.Position=UDim2.new(0,18,0,190+(i-1)*44);f.Size=UDim2.new(1,-36,0,38);f.BackgroundColor3=colors.ink;f.BackgroundTransparency=.25;f.BorderSizePixel=0;f.ZIndex=3;f.Parent=card
  Instance.new('UICorner',f).CornerRadius=UDim.new(0,10)
  local s=Instance.new('UIStroke');s.Color=gold;s.Transparency=.6;s.Parent=f
  local a=text(f,'Name',row[1],2,18,17,gold);a.Position=UDim2.new(0,12,0,2);a.Size=UDim2.new(1,-24,0,18);a.TextXAlignment=Enum.TextXAlignment.Left;a.ZIndex=4
  local b=text(f,'Detail',row[2],20,16,12,colors.cream);b.Position=UDim2.new(0,12,0,20);b.Size=UDim2.new(1,-24,0,15);b.TextXAlignment=Enum.TextXAlignment.Left;b.ZIndex=4
  f.BackgroundTransparency=1;a.TextTransparency=1;b.TextTransparency=1
  task.delay(.5+i*.25,function()
   Tween:Create(f,TweenInfo.new(.3),{BackgroundTransparency=.25}):Play()
   Tween:Create(a,TweenInfo.new(.3),{TextTransparency=0}):Play();Tween:Create(b,TweenInfo.new(.3),{TextTransparency=0}):Play()
  end)
 end
 local ok=Instance.new('TextButton');ok.Name='OK';ok.AnchorPoint=Vector2.new(.5,1);ok.Position=UDim2.new(.5,0,1,-10);ok.Size=UDim2.fromOffset(220,64)
 ok.BackgroundColor3=gold;ok.Text='THANK YOU!';ok.Font=Enum.Font.FredokaOne;ok.TextSize=22;ok.TextColor3=colors.ink;ok.AutoButtonColor=true;ok.ZIndex=4;ok.Parent=card
 Instance.new('UICorner',ok).CornerRadius=UDim.new(0,12)
 -- fit the 460x396 card (plus the avatar above it) on any screen: phones in landscape are often under 400 px tall
 local function fit()
  local v=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
  return math.min(1,(v.Y-80)/440,(v.X-24)/460)
 end
 Tween:Create(scale,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=fit()}):Play()
 local function sfx(id,volume)local s=Instance.new('Sound');s.SoundId='rbxassetid://'..id;s.Volume=volume;s.Parent=game:GetService('SoundService');s:Play();s.Ended:Connect(function()s:Destroy()end);task.delay(10,function()if s.Parent then s:Destroy()end end)end
 sfx(1846266827,.6);task.delay(.5,sfx,9119447936,.5) -- short fanfare, then the sparkle bell tree as the rewards slide in
 local fitConn=workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(function()scale.Scale=fit()end)
 gui.Destroying:Connect(function()fitConn:Disconnect()end)
 local done=false
 local function close()
  if done then return end;done=true
  if GuiService.SelectedObject==ok then GuiService.SelectedObject=nil end
  spin:Disconnect();gui:Destroy();showing=false
  if p:GetAttribute('GrantNotice')==kind then p:SetAttribute('GrantNotice',nil)end
 end
 ok.Activated:Connect(function()sfx(9116725218,.8);close()end)
 ok.Selectable=true;ok.SelectionOrder=0
 local function focus()if InputHints.Get()=='pad'and not done then GuiService.SelectedObject=ok end end
 focus();local focusConn=InputHints.Changed:Connect(focus)
 local selConn=GuiService:GetPropertyChangedSignal('SelectedObject'):Connect(function()if not done and InputHints.Get()=='pad'and GuiService.SelectedObject==nil then task.defer(focus)end end)
 ok.Destroying:Connect(function()focusConn:Disconnect();selConn:Disconnect()end)
 task.delay(45,close)
end
local function show(kind)
 if kind=='ownerAward'then return showAward(kind)end
 local n=NOTICES[kind];if not n or showing then return end
 showing=true
 -- Let the loading screen and the first menu settle so the card is the thing they see.
 if not p.Character then p.CharacterAdded:Wait()end
 task.wait(3)
 local gui=Instance.new('ScreenGui');gui.Name='GrantNotice';gui.ResetOnSpawn=false;gui.DisplayOrder=900;gui.IgnoreGuiInset=true;gui.Parent=p:WaitForChild('PlayerGui')
 local shade=Instance.new('Frame');shade.Name='Shade';shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new();shade.BackgroundTransparency=.45;shade.BorderSizePixel=0;shade.Parent=gui
 local card=Instance.new('Frame');card.Name='Card';card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.5);card.Size=UDim2.new(.9,0,0,210)
 card.BackgroundColor3=colors.panel;card.BorderSizePixel=0;card.Parent=gui
 local limit=Instance.new('UISizeConstraint');limit.MaxSize=Vector2.new(420,210);limit.Parent=card
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,16);corner.Parent=card
 local stroke=Instance.new('UIStroke');stroke.Color=colors.red;stroke.Thickness=3;stroke.Parent=card
 text(card,'Title',n.title,14,36,32,colors.red)
 text(card,'Body',n.body,56,52,18,colors.cream)
 text(card,'Hint',n.hint,110,34,15,colors.muted)
 local ok=Instance.new('TextButton');ok.Name='OK';ok.AnchorPoint=Vector2.new(.5,1);ok.Position=UDim2.new(.5,0,1,-14);ok.Size=UDim2.fromOffset(150,44)
 ok.BackgroundColor3=colors.green;ok.Text='GOT IT';ok.Font=Enum.Font.FredokaOne;ok.TextSize=22;ok.TextColor3=colors.ink;ok.AutoButtonColor=true;ok.Parent=card
 local okCorner=Instance.new('UICorner');okCorner.CornerRadius=UDim.new(0,12);okCorner.Parent=ok
 local done=false
 local function close()
  if done then return end;done=true
  if GuiService.SelectedObject==ok then GuiService.SelectedObject=nil end
  gui:Destroy();showing=false
  if p:GetAttribute('GrantNotice')==kind then p:SetAttribute('GrantNotice',nil)end -- local only; the save already holds the grant
 end
 ok.Activated:Connect(close)
 if InputHints.Get()=='pad'then GuiService.SelectedObject=ok end
 task.delay(30,close)
end

local function check()local kind=p:GetAttribute('GrantNotice');if kind then task.spawn(show,kind)end end
p:GetAttributeChangedSignal('GrantNotice'):Connect(check)
check()
