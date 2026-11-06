local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
-- Contextual Robux-shop suggestions, shown as a small card right under the quota panel.
-- The server (OfferAdvisor) decides WHEN and WHAT; this script only shows the card and reports the answer.
-- Yes opens the Robux shop on screen wherever the player is (VanShop "anywhere" mode).
-- Keyboard 1 = yes, 2 = no; controller D-pad up = yes, down = no, B = close; touch taps the buttons or the X.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local GS=game:GetService('GuiService')
local CAS=game:GetService('ContextActionService')
local TS=game:GetService('TweenService')
local Run=game:GetService('RunService')
local p=Players.LocalPlayer
local UI=require(RS:WaitForChild('NeonUI'))
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local Market=game:GetService('MarketplaceService')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local event=RS:WaitForChild('OfferPromptEvent')
-- Layout (tune by screenshot): sits just under the 82px quota panel, centred.
-- Slim bar (2026-10-04): about a quarter of the old 560x104 card so it never dominates a phone screen.
local CARD_W,CARD_H,CARD_TOP,EDGE=300,56,90,12
local CLOSE_SIZE,BUTTON_RIGHT=18,28 -- X sits inside the top-right corner; buttons keep clear of it
local BADGE,BUTTON_W,YES_H,NO_H=40,62,22,20
local SLIDE_TIME,FADE_TIME=.32,.22
local C=UI.Color
local gui=Instance.new('ScreenGui');gui.Name='OfferPrompt';gui.ResetOnSpawn=false;gui.DisplayOrder=40
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=p:WaitForChild('PlayerGui')
local holder=Instance.new('CanvasGroup');holder.Name='Card';holder.AnchorPoint=Vector2.new(.5,0);holder.Position=UDim2.new(.5,0,0,CARD_TOP)
holder.Size=UDim2.fromOffset(CARD_W,CARD_H);holder.BackgroundTransparency=1;holder.Visible=false;holder.Parent=gui
local scale=Instance.new('UIScale');scale.Parent=holder
-- Card body: black glass like the shop, with a colour wash from the offer's accent so it reads at a glance.
local card=Instance.new('Frame');card.Name='Body';card.Size=UDim2.fromScale(1,1);card.BackgroundColor3=Color3.new(1,1,1);card.BorderSizePixel=0;card.Parent=holder
UI.corner(card,16)
local wash=Instance.new('UIGradient');wash.Rotation=0;wash.Parent=card
local rim=UI.stroke(card,Color3.new(1,1,1),2.5,0)
local rimGradient=Instance.new('UIGradient');rimGradient.Parent=rim
local strip=Instance.new('Frame');strip.Name='AccentStrip';strip.Size=UDim2.new(0,6,1,-24);strip.Position=UDim2.fromOffset(10,12);strip.BorderSizePixel=0;strip.Parent=card
UI.corner(strip,UDim.new(1,0))
local badge=Instance.new('Frame');badge.Name='Badge';badge.Position=UDim2.fromOffset(24,16);badge.Size=UDim2.fromOffset(70,70);badge.BackgroundTransparency=.75;badge.Parent=card
UI.corner(badge,UDim.new(1,0));local badgeRim=UI.stroke(badge,Color3.new(1,1,1),2,.2)
local art=Instance.new('ImageLabel');art.Name='Art';art.BackgroundTransparency=1;art.Size=UDim2.fromScale(1,1);art.ScaleType=Enum.ScaleType.Crop;art.Parent=badge
UI.corner(art,UDim.new(1,0))
local glyph=UI.text(badge,'Glyph','R$',UI.Font.Display,22,C.text);glyph.Size=UDim2.fromScale(1,1);glyph.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(glyph,1.5)
local tag=UI.text(card,'Tag','',UI.Font.Title,11,C.ink);tag.Position=UDim2.fromOffset(106,12);tag.Size=UDim2.fromOffset(0,18);tag.AutomaticSize=Enum.AutomaticSize.X
tag.BackgroundTransparency=0;tag.TextXAlignment=Enum.TextXAlignment.Center;UI.corner(tag,UDim.new(1,0))
local tagPad=Instance.new('UIPadding');tagPad.PaddingLeft=UDim.new(0,9);tagPad.PaddingRight=UDim.new(0,9);tagPad.Parent=tag
local price=UI.text(card,'Price','',UI.Font.Display,15,C.gold);price.Position=UDim2.fromOffset(106,12);price.Size=UDim2.fromOffset(80,18);UI.outline(price,1.2)
local title=UI.text(card,'Title','',UI.Font.Display,19,C.text);title.Position=UDim2.fromOffset(106,32);title.Size=UDim2.new(1,-250,0,24);UI.fit(title,13,19);UI.outline(title,1.3)
local body=UI.text(card,'Body','',UI.Font.Body,13,Color3.fromRGB(214,216,228));body.Position=UDim2.fromOffset(106,56);body.Size=UDim2.new(1,-250,0,38)
body.TextYAlignment=Enum.TextYAlignment.Top;UI.fit(body,10,13)
local yes=UI.button(card,'Yes','YES','buy');yes.AnchorPoint=Vector2.new(1,0);yes.Position=UDim2.new(1,-18,0,22);yes.Size=UDim2.fromOffset(112,34)
local no=UI.button(card,'No','NO','muted');no.AnchorPoint=Vector2.new(1,0);no.Position=UDim2.new(1,-18,0,62);no.Size=UDim2.fromOffset(112,30)
-- Controller hints: D-pad pictures (up lit cyan = yes, down lit orange = no) shown inside the buttons on a pad.
local PAD_ICONS={yes='rbxassetid://89032056383783',no='rbxassetid://137804651602951'}
local PAD_ICON_SIZE,PAD_TEXT_INSET=18,20 -- icon px; left padding that makes room for it
local function padIcon(button,image)
 local icon=Instance.new('ImageLabel');icon.Name='PadIcon';icon.BackgroundTransparency=1;icon.Image=image;icon.ScaleType=Enum.ScaleType.Fit
 -- The button's left padding shifts its children, so the icon is pulled back to the left edge.
 icon.AnchorPoint=Vector2.new(0,.5);icon.Position=UDim2.new(0,-(PAD_TEXT_INSET-4),.5,0);icon.Size=UDim2.fromOffset(PAD_ICON_SIZE,PAD_ICON_SIZE);icon.ZIndex=button.ZIndex+1;icon.Visible=false;icon.Parent=button
 return icon
end
local yesIcon=padIcon(yes,PAD_ICONS.yes)
local noIcon=padIcon(no,PAD_ICONS.no)
local close=UI.closeButton(holder,'Close',CLOSE_SIZE);close.Position=UDim2.new(1,-(CLOSE_SIZE/2+5),0,CLOSE_SIZE/2+5);close.ZIndex=30
-- Time left: a thin bar along the bottom in the accent colour.
local timerTrack=Instance.new('Frame');timerTrack.Name='Timer';timerTrack.AnchorPoint=Vector2.new(0,1);timerTrack.Position=UDim2.new(0,24,1,-6);timerTrack.Size=UDim2.new(1,-48,0,3)
timerTrack.BackgroundColor3=Color3.new(1,1,1);timerTrack.BackgroundTransparency=.85;timerTrack.BorderSizePixel=0;timerTrack.Parent=card;UI.corner(timerTrack,UDim.new(1,0))
local timerFill=Instance.new('Frame');timerFill.Size=UDim2.fromScale(1,1);timerFill.BorderSizePixel=0;timerFill.Parent=timerTrack;UI.corner(timerFill,UDim.new(1,0))

local BUSY_ATTRIBUTES={'VanShopOpen','AppearanceOpen','MapOpen','AdminPassPanelOpen'}
local function busy()for _,a in BUSY_ATTRIBUTES do if p:GetAttribute(a)then return true end end;return false end
local current -- payload being shown
local lastAnswerAt=0 -- debounce shared by the key paths (CAS and the backpack-proof fallback)
local showToken=0
local motion={}
local function stopMotion()for _,t in motion do t:Cancel()end;table.clear(motion)end
local function play(o,info,props)local t=TS:Create(o,info,props);table.insert(motion,t);t:Play();return t end
local function hex(s,fallback)
 if typeof(s)=='Color3'then return s end
 local h=type(s)=='string'and s:gsub('#','')or''
 if #h==6 then local ok,c=pcall(Color3.fromHex,h);if ok then return c end end
 return fallback
end
local function device()
 return InputHints.Get()
end
local function labels()
 local d=device()
 local pad=d=='pad'
 yesIcon.Visible=pad;noIcon.Visible=pad
 -- On a pad the D-pad picture sits at the left of the button, so the word moves right to make room.
 for _,b in {yes,no}do local padding=b:FindFirstChildOfClass('UIPadding');if padding then padding.PaddingLeft=UDim.new(0,pad and PAD_TEXT_INSET or 6)end end
 yes.Text=d=='kb'and'YES [1]'or'YES'
 no.Text=d=='kb'and'NO [2]'or'NO'
end
local function layout()
 local v=gui.AbsoluteSize
 local w=math.min(CARD_W,v.X-EDGE*2)
 holder.Size=UDim2.fromOffset(w,CARD_H)
 -- Sits right under the quota panel (its real bottom edge, which scales on phones), centred.
 local quota=p.PlayerGui:FindFirstChild('RecoveryQuota');local panel=quota and quota:FindFirstChild('QuotaPanel')
 local top=CARD_TOP
 if panel and panel.AbsoluteSize.Y>0 then
  local panelTop=panel.AbsolutePosition.Y-gui.AbsolutePosition.Y
  if device()=='touch'or(UIS.TouchEnabled and v.Y<500)then
   -- Phones: straight above the quota bar (it may reach up into the top inset; that is intended).
   top=math.floor(panelTop-CARD_H-6)
   -- No room above it (the quota sits at the very top on phones): go just under it instead of off screen.
   if top<2 then top=math.floor(panelTop+panel.AbsoluteSize.Y+6)end
  else
   top=math.floor(panelTop+panel.AbsoluteSize.Y+6)
  end
 end
 holder:SetAttribute('Top',top)
 if not current or not next(motion)then holder.Position=UDim2.new(.5,0,0,top)end
 strip.Size=UDim2.new(0,4,1,-16);strip.Position=UDim2.fromOffset(6,8)
 badge.Size=UDim2.fromOffset(BADGE,BADGE);badge.Position=UDim2.fromOffset(14,(CARD_H-BADGE)/2)
 local textX=14+BADGE+8;local right=BUTTON_W+BUTTON_RIGHT+4
 tag.Visible=false;body.Visible=false
 title.Position=UDim2.fromOffset(textX,7);title.Size=UDim2.new(1,-(textX+right),0,20);UI.fit(title,10,15)
 price.Position=UDim2.fromOffset(textX,29);price.Size=UDim2.new(1,-(textX+right),0,16);price.TextSize=13
 yes.Size=UDim2.fromOffset(BUTTON_W,YES_H);no.Size=UDim2.fromOffset(BUTTON_W,NO_H)
 yes.Position=UDim2.new(1,-BUTTON_RIGHT,0,5);no.Position=UDim2.new(1,-BUTTON_RIGHT,0,5+YES_H+3)
 for _,bt in {yes,no}do local lim=bt:FindFirstChildOfClass('UITextSizeConstraint');if lim then lim.MaxTextSize=12;lim.MinTextSize=8 end;local pd=bt:FindFirstChildOfClass('UIPadding');if pd then pd.PaddingTop=UDim.new(0,2);pd.PaddingBottom=UDim.new(0,2)end end
 timerTrack.Position=UDim2.new(0,14,1,-3);timerTrack.Size=UDim2.new(1,-28,0,2)
 labels()
end
local hide
-- Phones: make room at the top by sliding the quota bar down while a card is up (restored on hide).
local QUOTA_SHIFT=CARD_H+6
local function shiftQuota(on)
 local quota=p.PlayerGui:FindFirstChild('RecoveryQuota');local panel=quota and quota:FindFirstChild('QuotaPanel')
 if not panel then return end
 local y=0 -- quota no longer moves; kept so earlier shifts always reset
 if panel.Position.Y.Offset~=y then TS:Create(panel,TweenInfo.new(.25,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,y)}):Play()end
end
local function unbind()CAS:UnbindAction('OfferPromptAnswer')end
local function answer(choice)
 if not current then return end
 local payload=current
 event:FireServer('answer',payload.id,choice)
 Audio.Play(choice=='yes'and'UiClick'or'UiClose')
 hide()
 if choice=='yes'then
  -- Open the Robux shop right here, scrolled to the suggested offer.
  local shop=p.PlayerGui:FindFirstChild('VanShop');local open=shop and shop:FindFirstChild('OpenRobuxAnywhere')
  if open then open:Fire(payload.offer)end
 end
end
local function bind()
 CAS:BindActionAtPriority('OfferPromptAnswer',function(_,state,input)
  if not current or state~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
  -- Never steal keys while another panel or a text box owns input.
  if busy()or UIS:GetFocusedTextBox()then return Enum.ContextActionResult.Pass end
  local k=input.KeyCode
  lastAnswerAt=os.clock()
  if k==Enum.KeyCode.One or k==Enum.KeyCode.KeypadOne or k==Enum.KeyCode.DPadUp then answer('yes')
  elseif k==Enum.KeyCode.Two or k==Enum.KeyCode.KeypadTwo or k==Enum.KeyCode.DPadDown then answer('no')
  else answer('close')end
  return Enum.ContextActionResult.Sink
 end,false,5500,Enum.KeyCode.One,Enum.KeyCode.KeypadOne,Enum.KeyCode.Two,Enum.KeyCode.KeypadTwo,Enum.KeyCode.DPadUp,Enum.KeyCode.DPadDown,Enum.KeyCode.ButtonB)
end
hide=function(silent)
 showToken+=1;local token=showToken
 current=nil;unbind();stopMotion();shiftQuota(false)
 if silent then holder.Visible=false;return end
 local top=holder:GetAttribute('Top')or CARD_TOP
 play(holder,TweenInfo.new(FADE_TIME,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{GroupTransparency=1,Position=UDim2.new(.5,0,0,top-14)})
 task.delay(FADE_TIME+.02,function()if showToken==token then holder.Visible=false end end)
end
local function show(payload)
 if type(payload)~='table'or type(payload.id)~='string'then return end
 local offer=Shop.RobuxById[payload.offer or '']
 local accent=hex(payload.accent,Color3.fromRGB(255,120,170))
 current=payload;showToken+=1;local token=showToken;stopMotion()
 -- Content
 tag.Text=string.upper(payload.tag or'SUGGESTED FOR YOU');tag.BackgroundColor3=accent
 title.Text=payload.title or(offer and offer.name)or'Robux shop'
 body.Text=payload.body or(offer and offer.description)or''
 -- Price is this player's live Roblox price (regional pricing), never a stored catalog number; blank until it loads.
 price.Text=''
 if offer and offer.assetId then
  task.spawn(function()
   local ok,info=pcall(function()return Market:GetProductInfoAsync(offer.assetId,offer.kind=='Pass'and Enum.InfoType.GamePass or Enum.InfoType.Product)end)
   if ok and type(info)=='table'and type(info.PriceInRobux)=='number'and token==showToken then price.Text='R$ '..info.PriceInRobux end
  end)
 end
 art.Image=offer and offer.image or'';glyph.Visible=art.Image==''
 badge.BackgroundColor3=accent;badgeRim.Color=accent;strip.BackgroundColor3=accent;timerFill.BackgroundColor3=accent
 wash.Color=ColorSequence.new(accent:Lerp(Color3.fromRGB(10,10,14),.62),Color3.fromRGB(14,14,19))
 wash.Transparency=NumberSequence.new(0)
 rimGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,accent),ColorSequenceKeypoint.new(.5,accent:Lerp(Color3.new(1,1,1),.35)),ColorSequenceKeypoint.new(1,accent)})
 layout()
 -- Entrance: drop in under the quota with a small pop; never covers the middle of the screen.
 local top=holder:GetAttribute('Top')or CARD_TOP
 holder.Visible=true;holder.GroupTransparency=1;holder.Position=UDim2.new(.5,0,0,top-18);scale.Scale=.94
 play(holder,TweenInfo.new(SLIDE_TIME,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{GroupTransparency=0,Position=UDim2.new(.5,0,0,top)})
 play(scale,TweenInfo.new(SLIDE_TIME*1.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
 bind()
 -- Arrived while a shop/appearance panel is open: wait hidden until it closes (no sound, no key capture).
 if busy()then holder.Visible=false;unbind()else Audio.Play('UiOpen');shiftQuota(true)end
 -- Countdown (permanent Studio test prompts never time out).
 local seconds=math.clamp((tonumber(payload.seconds)or 12)-1,3,30)
 timerTrack.Visible=not payload.permanent
 timerFill.Size=UDim2.fromScale(1,1)
 if not payload.permanent then
  play(timerFill,TweenInfo.new(seconds,Enum.EasingStyle.Linear),{Size=UDim2.fromScale(0,1)})
  task.delay(seconds,function()if showToken==token and current==payload then answer('timeout')end end)
 end
 -- Gentle attention pulse on the rim, a few times only.
 task.spawn(function()
  for i=1,3 do
   if showToken~=token then return end
   TS:Create(rim,TweenInfo.new(.45,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,1,true),{Thickness=4}):Play()
   task.wait(1.1)
  end
 end)
end
-- Roblox's built-in backpack can grab 1/2 before ContextActionService sees them, so also listen directly.
local KEY_YES={[Enum.KeyCode.One]=true,[Enum.KeyCode.KeypadOne]=true}
local KEY_NO={[Enum.KeyCode.Two]=true,[Enum.KeyCode.KeypadTwo]=true}
UIS.InputBegan:Connect(function(input)
 if not current or not holder.Visible or UIS:GetFocusedTextBox()then return end
 if busy()then return end
 -- Players carrying backpack tools use 1/2 to equip them: leave those keys alone for them.
 if p.Backpack and p.Backpack:FindFirstChildWhichIsA('Tool')or p.Character and p.Character:FindFirstChildWhichIsA('Tool')then return end
 if os.clock()-lastAnswerAt<.2 then return end
 if KEY_YES[input.KeyCode]then lastAnswerAt=os.clock();answer('yes')elseif KEY_NO[input.KeyCode]then lastAnswerAt=os.clock();answer('no')end
end)
yes.Activated:Connect(function()answer('yes')end)
no.Activated:Connect(function()answer('no')end)
close.Activated:Connect(function()answer('close')end)
event.OnClientEvent:Connect(function(action,payload)
 if action=='show'then show(payload)
 elseif action=='hide'then if current and(not payload or payload.id==current.id)then hide()end end
end)
-- Panels own the screen: the card steps aside while a shop or the appearance panel is open, and comes back after.
local function panelsChanged()
 local blocked=busy()
 if current then holder.Visible=not blocked;shiftQuota(not blocked);if blocked then unbind()else bind()end end
end
p:GetAttributeChangedSignal('VanShopOpen'):Connect(panelsChanged)
p:GetAttributeChangedSignal('AppearanceOpen'):Connect(panelsChanged)
p:GetAttributeChangedSignal('MapOpen'):Connect(panelsChanged)
p:GetAttributeChangedSignal('AdminPassPanelOpen'):Connect(panelsChanged)
-- A run ending (or the player leaving the mission) clears any card.
p:GetAttributeChangedSignal('MissionActive'):Connect(function()if p:GetAttribute('MissionActive')~=true and current then hide(true)end end)
InputHints.Changed:Connect(layout)
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(layout)
layout()
if Run:IsStudio()then
 local preview=Instance.new('BindableEvent');preview.Name='PreviewOfferPrompt';preview.Parent=script
 preview.Event:Connect(function(payload)show(payload)end)
end
