local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local GS=game:GetService('GuiService')
local Tween=game:GetService('TweenService')
local CAS=game:GetService('ContextActionService')
local PPS=game:GetService('ProximityPromptService')
local Market=game:GetService('MarketplaceService')
local Run=game:GetService('RunService')
local p=Players.LocalPlayer
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local Audio=require(RS:WaitForChild('GameplayAudio'))
local CameraGuard=require(RS:WaitForChild('CameraInputGuard'))
local UI=require(RS:WaitForChild('NeonUI'))
local event=RS:WaitForChild('LobbyEvent')
-- Layout (tune by screenshot): plate size limits, card height, header/footer bands.
local MAX_W,MAX_H,MARGIN,CARD_H,CARD_GAP=900,580,12,150,12
local HEADER_H,HEADER_H_COMPACT,FOOTER_H,SIDE=86,64,40,20
-- Motion: plate slides in from the right, then the card rows pop in one after another.
local SLIDE_IN,SLIDE_OUT,ROWS_START,ROW_STAGGER,POP_TIME=.36,.2,.2,.055,.26
local colors=UI.Color
local gui=Instance.new('ScreenGui');gui.Name='VanShop';gui.ResetOnSpawn=false;gui.DisplayOrder=130;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=p:WaitForChild('PlayerGui')
local backdrop=UI.backdrop(gui,.5)
local panel=UI.plate(gui,'Panel',24);panel.AnchorPoint=Vector2.new(.5,.5);panel.Position=UDim2.fromScale(.5,.5);panel.Visible=false
local function label(parent,name,value,pos,size,font,color,face)
 local t=UI.text(parent,name,value,face or UI.Font.Bold,font or 16,color);t.Position=pos;t.Size=size;t.TextWrapped=true;return t
end
local function button(parent,name,value,pos,size,fn,accent)
 local b=UI.button(parent,name,value,accent==true and 'buy' or accent=='use' and 'use' or 'muted');b.Position=pos;b.Size=size
 b.Activated:Connect(function()Audio.Play('UiClick');fn()end);return b
end
local headerIcon=Instance.new('Frame');headerIcon.Name='HeaderIcon';headerIcon.Position=UDim2.fromOffset(SIDE,18);headerIcon.Size=UDim2.fromOffset(50,50);headerIcon.BackgroundColor3=Color3.new(1,1,1);headerIcon.Parent=panel
UI.corner(headerIcon,UDim.new(1,0));UI.stroke(headerIcon,colors.ink,2.5,0)
local headerGradient=Instance.new('UIGradient');headerGradient.Rotation=90;headerGradient.Parent=headerIcon
local headerGlyph=UI.text(headerIcon,'Glyph','T',UI.Font.Display,24,colors.text);headerGlyph.Size=UDim2.fromScale(1,1);headerGlyph.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(headerGlyph,1.6)
local title=label(panel,'Title','TOKEN SHOP',UDim2.fromOffset(SIDE+62,16),UDim2.new(1,-300,0,34),30,colors.text,UI.Font.Title);title.TextWrapped=false;UI.fit(title,18,30)
local subtitle=label(panel,'Subtitle','',UDim2.fromOffset(SIDE+62,50),UDim2.new(1,-300,0,20),15,colors.muted,UI.Font.Body);UI.fit(subtitle,11,15)
local balance=label(panel,'Balance','',UDim2.new(1,-74,0,26),UDim2.fromOffset(0,36),16,colors.gold,UI.Font.Bold)
balance.AnchorPoint=Vector2.new(1,0);balance.AutomaticSize=Enum.AutomaticSize.X;balance.TextWrapped=false;balance.TextXAlignment=Enum.TextXAlignment.Center
balance.BackgroundTransparency=0;balance.BackgroundColor3=colors.pill;UI.corner(balance,UDim.new(1,0));UI.stroke(balance,Color3.fromRGB(70,70,86),1.5,0)
local balancePad=Instance.new('UIPadding');balancePad.PaddingLeft=UDim.new(0,16);balancePad.PaddingRight=UDim.new(0,16);balancePad.Parent=balance
local divider=Instance.new('Frame');divider.Name='Divider';divider.BorderSizePixel=0;divider.BackgroundColor3=Color3.fromRGB(255,255,255);divider.BackgroundTransparency=.9;divider.Position=UDim2.fromOffset(SIDE,HEADER_H-6);divider.Size=UDim2.new(1,-SIDE*2,0,1);divider.Parent=panel
local status=label(panel,'Status','',UDim2.new(0,SIDE,1,-FOOTER_H),UDim2.new(1,-SIDE*2,0,FOOTER_H-8),14,colors.muted,UI.Font.Body);UI.fit(status,10,14)
local list=Instance.new('ScrollingFrame');list.Name='Offers';list.BackgroundTransparency=1;list.BorderSizePixel=0;list.ScrollBarThickness=5;list.Selectable=false;list.ScrollBarImageColor3=Color3.fromRGB(150,150,170);list.AutomaticCanvasSize=Enum.AutomaticSize.Y;list.CanvasSize=UDim2.new();list.Position=UDim2.fromOffset(SIDE,HEADER_H+4);list.Size=UDim2.new(1,-SIDE*2+8,1,-(HEADER_H+4+FOOTER_H));list.Parent=panel
local grid=Instance.new('UIGridLayout');grid.CellPadding=UDim2.fromOffset(CARD_GAP,CARD_GAP);grid.SortOrder=Enum.SortOrder.LayoutOrder;grid.Parent=list
local pad=Instance.new('UIPadding');pad.PaddingTop=UDim.new(0,6);pad.PaddingBottom=UDim.new(0,10);pad.PaddingLeft=UDim.new(0,2);pad.PaddingRight=UDim.new(0,10);pad.Parent=list
local open=false;local activeTerminal;local section='Tokens';local progress={ready=false,owned={},equipped={},passes={},upgrades={}}
local sequence=600000000;local pending={};local prices={};local loadingPrice={};local previousFocus;local animationToken=0;local tweens={}
local entranceStart=-math.huge -- set on a real open; redraws inside the entrance window keep the same row timing
local ENTRANCE_WINDOW=ROWS_START+7*ROW_STAGGER+POP_TIME
local render,close,request
local focusTarget,focusUntil=nil,0 -- suggested offer to keep highlighted (anywhere mode)
local highlightFocus -- defined with the anywhere-mode helpers; render() re-applies it after every redraw
-- Products with saved charges are used from their card here (no HUD buttons or keybinds anywhere else).
local USES={
 grantJumpscare={attribute='JumpscareCharges',action='jumpscareAll',label='USE'},
 grantInstantWin={attribute='InstantWinCharges',action='instantWin',label='USE',confirm=true},
}
local WIN_CONFIRM_SECONDS=3 -- Instant Win spends a 200 R$ charge, so it needs a second click inside this window
local confirmUntil={}
local function useFor(offer)for field,use in USES do if offer[field]then return use end end end
local function monetize()return RS:FindFirstChild('MonetizeEvent')end
local function openGiftPicker()
 local shop=p.PlayerGui:FindFirstChild('MissionShop');local open=shop and shop:FindFirstChild('OpenGiftRevive')
 if open then close();open:Fire()else status.Text='Gift a Revive is unavailable right now.'end
end
local function platform()
 return InputHints.Get()
end
-- Phone tiles follow the device, not the last input: a touch screen keeps the compact 3-column grid
-- even when the input hint flips to mouse/keyboard. A gamepad still gets the big focusable cards.
local function phoneLayout()
 return platform()=='touch' or (UIS.TouchEnabled and platform()~='pad')
end
-- Anywhere mode: the Robux shop opened from a contextual suggestion, wherever the player is in a mission.
-- Only Robux purchases happen there; token purchases and USE charges stay at the van terminals.
local anywhere=false
-- Lobby mode: the 3D lobby opens this same shop from its menu icons and store kiosks (no van terminal there).
local lobbyMode=false
local function lobbyOk()
 local ch=p.Character;local h=ch and ch:FindFirstChildOfClass('Humanoid')
 local state=RS:FindFirstChild('LobbyState')
 -- ReturnedToLobby: left a run early while teammates still play (server Mode stays Mission).
 return state~=nil and(state:GetAttribute('Mode')=='Menu'or p:GetAttribute('ReturnedToLobby')==true)and p:GetAttribute('MissionActive')~=true and h~=nil and h.Health>0
end
local nearTerminal
local function canStay()
 -- Anywhere mode closes the moment the server marks the player unsafe (chase, damage, monster close).
 if anywhere then return p:GetAttribute('MissionActive')==true and p:GetAttribute('OfferAdvisorContext')~='unsafe' end
 if lobbyMode then return lobbyOk() end
 return nearTerminal()
end
function nearTerminal()
 local ch=p.Character;local root=ch and ch:FindFirstChild('HumanoidRootPart');local h=ch and ch:FindFirstChildOfClass('Humanoid')
 return p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead')and root and h and h.Health>0 and activeTerminal and activeTerminal.Parent and(root.Position-activeTerminal.Position).Magnitude<12
end
-- Only hand controller focus to a control that is really on screen (avoids 'invalid GuiObject' warnings).
local function selectable(o)
 if not(o and o:IsA('GuiObject')and o.Selectable and o:IsDescendantOf(game))then return false end
 local x=o
 while x and not x:IsA('LayerCollector')do if x:IsA('GuiObject')and not x.Visible then return false end;x=x.Parent end
 return x~=nil and x.Enabled
end
local function selectSafe(o)if o==nil or selectable(o)then GS.SelectedObject=o end end
local function cancelTweens()for _,t in tweens do t:Cancel()end;table.clear(tweens)end
local function animate(object,info,properties)local t=Tween:Create(object,info,properties);table.insert(tweens,t);t:Play();return t end
request=function(action,data,callback)
 sequence+=1;local id=sequence;pending[id]=callback or function()end
 event:FireServer(id,action,data or {})
 task.delay(25,function()if pending[id]then pending[id]=nil;if open then status.Text='Save service is taking longer than expected. Please refresh.'end end end)
end
local function layout()
 local camera=workspace.CurrentCamera;if not camera then return 1 end
 local v=gui.AbsoluteSize;local w=math.min(MAX_W,v.X-MARGIN*2);local h=math.min(MAX_H,v.Y-MARGIN*2)
 -- Phones: a smaller panel overall, with small tiles (see phoneTile).
 if phoneLayout()then w=math.min(w,math.floor(v.X*.84));h=math.min(h,v.Y-8)end
 panel.Size=UDim2.fromOffset(w,h)
 local compact=h<430 or w<560
 local header=compact and HEADER_H_COMPACT or HEADER_H
 headerIcon.Size=UDim2.fromOffset(compact and 38 or 50,compact and 38 or 50);headerIcon.Position=UDim2.fromOffset(SIDE,compact and 13 or 18)
 headerGlyph.TextSize=compact and 19 or 24
 local textX=SIDE+(compact and 48 or 62)
 local reserve=balance.AbsoluteSize.X+112
 title.Position=UDim2.fromOffset(textX,compact and 9 or 16);title.Size=UDim2.new(1,-(textX+reserve),0,compact and 28 or 34)
 subtitle.Visible=not compact or h>=360;subtitle.Position=UDim2.fromOffset(textX,compact and 36 or 50);subtitle.Size=UDim2.new(1,-(textX+reserve),0,compact and 16 or 20)
 balance.Position=UDim2.new(1,-66,0,compact and 15 or 26);balance.Size=UDim2.fromOffset(0,compact and 30 or 36);balance.TextSize=compact and 14 or 16
 divider.Position=UDim2.fromOffset(SIDE,header-6)
 list.Position=UDim2.fromOffset(SIDE,header+4);list.Size=UDim2.new(1,-SIDE*2+8,1,-(header+4+FOOTER_H))
 local phone=phoneLayout()
 local cols=phone and(w>=520 and 3 or 2)or w>=820 and 3 or w>=520 and 2 or 1
 grid.CellSize=UDim2.fromOffset(math.floor((w-SIDE*2-4-(cols-1)*(phone and 8 or CARD_GAP))/cols),phone and 88 or CARD_H)
 grid.CellPadding=UDim2.fromOffset(phone and 8 or CARD_GAP,phone and 8 or CARD_GAP)
 grid.FillDirectionMaxCells=cols
 return cols
end
local function loadPrice(offer)
 if prices[offer.id]or loadingPrice[offer.id]then return end
 loadingPrice[offer.id]=true
 task.spawn(function()
  local ok,info=pcall(function()return Market:GetProductInfoAsync(offer.assetId,offer.kind=='Pass'and Enum.InfoType.GamePass or Enum.InfoType.Product)end)
  prices[offer.id]={amount=ok and info.PriceInRobux or nil,available=ok and info.IsForSale==true}
  loadingPrice[offer.id]=nil;if open and section=='Robux'then render(offer.id)end -- only this card: every price used to rebuild the whole list
 end)
end
local function setHeader()
 local robux=section=='Robux'
 title.Text=robux and 'ROBUX SHOP'or 'TOKEN SHOP'
 subtitle.Text=robux and 'Passes, revives and boosts for your crew'or 'Spend tokens on upgrades and wearables'
 headerGlyph.Text=robux and 'R$'or 'T'
 headerGradient.Color=robux and ColorSequence.new(Color3.fromRGB(110,236,140),Color3.fromRGB(28,160,72))or ColorSequence.new(Color3.fromRGB(255,222,110),Color3.fromRGB(226,150,30))
end
-- render(onlyId) rebuilds one card (a purchase or a price load) instead of all ~70: a full rebuild hitched badly on
-- consoles after every purchase (2026-10-24). render(BALANCE_ONLY) just refreshes the balance line.
local BALANCE_ONLY='__balance__'
local lastPurchaseAt=0
render=function(onlyId)
 local cols=layout();local focus=GS.SelectedObject;local focusName=focus and focus:IsDescendantOf(list)and focus.Name
 if onlyId then local old=list:FindFirstChild('Offer_'..onlyId);if old then old:Destroy()end
 else for _,x in list:GetChildren()do if x:IsA('GuiObject')then x:Destroy()end end end
 balance.Text='TOKENS  '..(progress.tokens or p:GetAttribute('Tokens')or 0)..'   •   REVIVES  '..(progress.reviveTokens or 0)
 local robux=section=='Robux'
 -- Gameplay upgrades (Movement Speed, Stamina Capacity, Flashlight Strength) always lead the token list so they
 -- are not lost among the cosmetics; everything else follows in catalog order.
 local offers=robux and Shop.RobuxOffers or Shop.TokenOffers
 local order={}
 do
  local u,k=0,0
  for i,o in offers do if o.kind=='Upgrade'then u+=1;order[i]=u else k+=1;order[i]=100+k end end
 end
 local cells={}
 for index,offer in offers do
  if onlyId and offer.id~=onlyId then continue end
  local tier=progress.upgrades and progress.upgrades[offer.stat]or 0
  local upgrade=offer.kind=='Upgrade';local maxed=upgrade and tier>=#Shop.UpgradeCosts
  local owned=robux and progress.passes and progress.passes[offer.id]or not robux and progress.owned and progress.owned[offer.id]
  local cosmetic=offer.grants and Shop.ById[offer.grants]or not robux and offer.kind~='Upgrade'and offer
  local equipped=progress.equipped and(offer.id=='vip'and progress.equipped.Title=='title_vip'and progress.equipped.Aura=='aura_vip'or cosmetic and progress.equipped[cosmetic.kind]==cosmetic.id)
  local cost=upgrade and Shop.UpgradeCostFor(offer.stat,tier,p:GetAttribute('ShopTutorialStep'))or offer.price
  local accent=Color3.fromRGB(unpack(offer.color))
  local cell=Instance.new('Frame');cell.Name='Offer_'..offer.id;cell.LayoutOrder=order[index]or index;cell.BackgroundTransparency=1;cell.Parent=list;table.insert(cells,cell)
  local card=Instance.new('Frame');card.Name='Card';card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.5);card.Size=UDim2.fromScale(1,1);card.BackgroundColor3=Color3.new(1,1,1);card.BorderSizePixel=0;card.Parent=cell
  UI.corner(card,16);local rim=UI.stroke(card,accent,1.5,.45)
  local tint=Instance.new('UIGradient');tint.Rotation=125;tint.Color=ColorSequence.new(accent:Lerp(colors.cardLow,.55),colors.card);tint.Parent=card
  local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=card
  local badge=Instance.new('Frame');badge.Name='Badge';badge.Position=UDim2.fromOffset(12,12);badge.Size=UDim2.fromOffset(62,62);badge.BackgroundColor3=accent;badge.BackgroundTransparency=.78;badge.Parent=card
  UI.corner(badge,UDim.new(1,0));UI.stroke(badge,accent,2,.25)
  local symbol=UI.text(badge,'Symbol',upgrade and offer.stat:sub(1,3):upper()or offer.kind=='Product'and '+'or '★',UI.Font.Display,20,colors.text);symbol.Size=UDim2.fromScale(1,1);symbol.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(symbol,1.4)
  if offer.image then local art=Instance.new('ImageLabel');art.Name='Artwork';art.BackgroundTransparency=1;art.AnchorPoint=Vector2.new(.5,.5);art.Position=UDim2.fromScale(.5,.5);art.Size=UDim2.fromScale(1,1);art.Image=offer.image;art.ScaleType=Enum.ScaleType.Crop;art.Parent=badge;UI.corner(art,UDim.new(1,0));symbol.Visible=not art.IsLoaded;art:GetPropertyChangedSignal('IsLoaded'):Connect(function()symbol.Visible=not art.IsLoaded end)end
  local name=label(card,'Name',offer.name..(upgrade and(' • '..tier..'/4')or ''),UDim2.fromOffset(86,12),UDim2.new(1,-98,0,26),20,colors.text,UI.Font.Display);UI.fit(name,13,20);UI.outline(name,1.4)
  local desc=label(card,'Description',offer.description,UDim2.fromOffset(86,40),UDim2.new(1,-98,0,(robux and offer.kind=='Product'and useFor(offer)and(p:GetAttribute(useFor(offer).attribute)or 0)>0)and 28 or 44),13,colors.muted,UI.Font.Body);desc.TextYAlignment=Enum.TextYAlignment.Top;UI.fit(desc,10,13)
  if equipped then
   local tag=label(card,'EquippedTag','WORN',UDim2.new(0,12,0,78),UDim2.fromOffset(62,18),11,colors.ink,UI.Font.Title);tag.TextXAlignment=Enum.TextXAlignment.Center;tag.BackgroundTransparency=0;tag.BackgroundColor3=colors.green;UI.corner(tag,UDim.new(1,0))
  end
  if robux then loadPrice(offer)end
  local price=prices[offer.id]
  local priceText=owned and 'OWNED'or maxed and 'MAXED'or robux and(price and(price.amount and('R$ '..price.amount)or 'UNAVAILABLE')or 'LOADING…')or(cost..' TOKENS')
  local use=robux and offer.kind=='Product'and useFor(offer)
  local charges=use and not anywhere and not lobbyMode and(p:GetAttribute(use.attribute)or 0)or 0 -- charges are used in a game, from the van
  -- With a USE button too, the price moves up beside the description so it never gets squeezed out.
  local priceLabel=label(card,'Price',priceText,charges>0 and UDim2.new(0,86,1,-80)or UDim2.new(0,14,1,-48),charges>0 and UDim2.new(1,-98,0,24)or UDim2.new(1,-140,0,38),20,(owned or maxed)and colors.green or colors.gold,UI.Font.Display);priceLabel.TextYAlignment=Enum.TextYAlignment.Center;UI.fit(priceLabel,12,20);UI.outline(priceLabel,1.3)
  if charges>0 then
   local armed=use.confirm and os.clock()<(confirmUntil[offer.id]or 0)
   button(card,'Use_'..offer.id,armed and 'CONFIRM'or(use.label..' ('..charges..')'),UDim2.new(1,-232,1,-52),UDim2.fromOffset(104,42),function()
    if not open or not canStay()then close();return end
    if use.confirm and os.clock()>=(confirmUntil[offer.id]or 0)then
     confirmUntil[offer.id]=os.clock()+WIN_CONFIRM_SECONDS;status.Text='Click CONFIRM to use '..offer.name..' now.';render()
     task.delay(WIN_CONFIRM_SECONDS,function()if open then render()end end);return
    end
    confirmUntil[offer.id]=nil
    local ev=monetize();if not ev then status.Text='Purchases are unavailable right now.';return end
    status.Text='Using '..offer.name..'…';ev:FireServer(use.action)
   end,'use')
  end
  local text=owned and 'OWNED'or maxed and 'MAXED'or upgrade and 'UPGRADE'or robux and 'BUY'or 'UNLOCK'
  local buy=button(card,'Buy_'..offer.id,text,UDim2.new(1,-118,1,-52),UDim2.fromOffset(106,42),function()
   if not open or not canStay()then close();return end
   if not progress.ready then status.Text='Wait for your saved data to load.';return end
   if maxed then status.Text='This upgrade is already maxed.';return end
   if owned then status.Text='Already unlocked. Equip cosmetics from Appearance in the van.'
   elseif robux and offer.giftRevive then openGiftPicker()
   elseif robux then
    local live=prices[offer.id];if not live or not live.available then status.Text='This offer is currently unavailable.';return end
    local ok=pcall(function()if offer.kind=='Pass'then Market:PromptGamePassPurchase(p,offer.assetId)else Market:PromptProductPurchase(p,offer.assetId)end end)
    if not ok then status.Text='Roblox purchases are unavailable right now.'end
   else
    local function buy()status.Text='Saving purchase…';request('purchase',{offer=offer.id},function(data)progress=data.progress;status.Text=data.message;lastPurchaseAt=os.clock();render(offer.id)end)end
    -- Short on tokens (owner 2026-10-27): offer the smallest token pack that covers it; the purchase finishes when they arrive.
    local have=progress.tokens or p:GetAttribute('Tokens')or 0
    local pack,short
    if cost and have<cost then pack,short=require(game:GetService('ReplicatedStorage'):WaitForChild('TokenTopUp')).Offer(cost,have,buy)end
    if pack then status.Text=('You need %d more tokens. The %s pack covers it, and this finishes as soon as they arrive.'):format(short,pack.name)else buy()end
   end
  end,not owned and not maxed)
  if phoneLayout()then
   -- Phone tile: small art, name and price on the left, a small button bottom-right; the long description is hidden.
   badge.Position=UDim2.fromOffset(8,8);badge.Size=UDim2.fromOffset(34,34);symbol.TextSize=12
   name.Position=UDim2.fromOffset(48,8);name.Size=UDim2.new(1,-54,0,34);name.TextWrapped=true;UI.fit(name,9,14)
   desc.Visible=false
   local tag=card:FindFirstChild('EquippedTag');if tag then tag.Position=UDim2.fromOffset(8,46);tag.Size=UDim2.fromOffset(40,14);tag.TextSize=9 end
   priceLabel.Position=UDim2.new(0,8,1,-34);priceLabel.Size=UDim2.new(1,-84,0,28);UI.fit(priceLabel,9,14)
   buy.Position=UDim2.new(1,-74,1,-36);buy.Size=UDim2.fromOffset(66,30)
   local useButton=card:FindFirstChild('Use_'..offer.id);if useButton then useButton.Position=UDim2.new(1,-74,0,8);useButton.Size=UDim2.fromOffset(66,26);priceLabel.Size=UDim2.new(1,-84,0,28)end
  end
  local function hover(on)Tween:Create(rim,TweenInfo.new(.12),{Transparency=on and 0 or .45,Thickness=on and 2.5 or 1.5}):Play()end
  buy.MouseEnter:Connect(function()hover(true)end);buy.MouseLeave:Connect(function()hover(false)end)
  buy.SelectionGained:Connect(function()hover(true)end);buy.SelectionLost:Connect(function()hover(false)end)
 end
 local since=os.clock()-entranceStart
 if since<ENTRANCE_WINDOW then
  for _,t in UI.popRows(cells,cols,ROWS_START,ROW_STAGGER,POP_TIME,since)do table.insert(tweens,t)end
 end
 if focusName then local replacement=list:FindFirstChild(focusName,true);selectSafe(replacement and replacement:IsA('GuiButton')and replacement or nil)end
 if highlightFocus then highlightFocus()end
end
local closeButton=UI.closeButton(panel,'Close',50);closeButton.Position=UDim2.new(1,-30,0,30) -- inboard so phones' safe area never clips it
closeButton.Activated:Connect(function()Audio.Play('UiClick');close()end)
closeButton.Modal=true
close=function()
 if not open then return end;open=false;focusTarget=nil;entranceStart=-math.huge;p:SetAttribute('VanShopOpen',false);animationToken+=1;local token=animationToken
 cancelTweens();Audio.Play('UiClose');CameraGuard.Mute(.4)
 table.insert(tweens,UI.slideOut(panel,SLIDE_OUT));table.insert(tweens,UI.showBackdrop(backdrop,false))
 UI.FocusRelease('VanShop')
 if GS.SelectedObject and GS.SelectedObject:IsDescendantOf(panel)then GS.SelectedObject=nil;if selectable(previousFocus)then GS.SelectedObject=previousFocus end end
 task.delay(SLIDE_OUT+.02,function()if animationToken==token then panel.Visible=false end end)
end
-- The suggested offer stays highlighted for a while even when the list redraws (prices load right after opening).
local FOCUS_SECONDS=8
highlightFocus=function()
 if not focusTarget or os.clock()>focusUntil then return end
 local cell=list:FindFirstChild('Offer_'..focusTarget);local card=cell and cell:FindFirstChild('Card')
 local rim=card and card:FindFirstChildOfClass('UIStroke');if not rim then return end
 rim.Color=Color3.fromRGB(255,206,64);rim.Thickness=3.5;rim.Transparency=0
 if platform()=='pad'then local buy=card:FindFirstChild('Buy_'..focusTarget);if buy then selectSafe(buy)end end
end
local function focusOffer(id)
 -- Scroll the suggested offer into view, highlight its rim and give it controller focus.
 local cell=id and list:FindFirstChild('Offer_'..id);if not cell then return end
 focusTarget=id;focusUntil=os.clock()+FOCUS_SECONDS
 local top=cell.AbsolutePosition.Y-list.AbsolutePosition.Y+list.CanvasPosition.Y
 list.CanvasPosition=Vector2.new(0,math.max(0,top-12))
 highlightFocus()
end
local openPanel
local function show(terminal)
 anywhere=false;lobbyMode=false
 activeTerminal=terminal;if not nearTerminal()then return end
 section=terminal:GetAttribute('ShopSection')=='Robux'and 'Robux'or 'Tokens'
 setHeader()
 list.CanvasPosition=Vector2.zero
 request('vanShop',{},function(data)
  if not nearTerminal()then return end
  openPanel(data)
 end)
end
local anywhereRequest=0
local function showAnywhere(offerId)
 if p:GetAttribute('MissionActive')~=true or p:GetAttribute('AppearanceOpen')or p:GetAttribute('OfferAdvisorContext')=='unsafe'then return end
 anywhereRequest+=1;local ticket=anywhereRequest
 if open then close()end
 anywhere=true;lobbyMode=false;activeTerminal=nil;section='Robux'
 setHeader();subtitle.Text='Shop from anywhere: passes and revives apply instantly'
 list.CanvasPosition=Vector2.zero
 request('robuxShop',{},function(data)
  if ticket~=anywhereRequest or not anywhere or open or not canStay()then return end
  openPanel(data,offerId)
 end)
end
local function refreshControls()
   status.Text=anywhere and(platform()=='pad'and 'A buys   •   B closes'or platform()=='touch'and 'Tap BUY   •   Tap the red X to keep playing'or 'Click BUY   •   Esc or the red X closes')
    or platform()=='pad'and 'A selects   •   B closes   •   Saved upgrades apply now'or platform()=='touch'and (lobbyMode and 'Tap an offer   •   Tap the red X to close'or 'Tap an offer   •   Tap the red X to return to the van')or 'Click an offer   •   Esc or the red X closes   •   Saved upgrades apply now'
end
InputHints.Changed:Connect(function()if open then refreshControls()end end)
openPanel=function(data,focusId)
  progress=data.progress;open=true;animationToken+=1;previousFocus=GS.SelectedObject;p:SetAttribute('VanShopOpen',true);cancelTweens()
  UI.FocusAcquire('VanShop',gui)
  panel.Visible=true;entranceStart=os.clock();render()
  -- Always open at the top of the list (the canvas can keep an old offset while the cards are rebuilt).
  list.CanvasPosition=Vector2.zero;task.defer(function()if open then list.CanvasPosition=Vector2.zero end end)
  table.insert(tweens,UI.slideIn(panel,UDim2.fromScale(.5,.5),SLIDE_IN));table.insert(tweens,UI.showBackdrop(backdrop,true))
  refreshControls()
  Audio.Play('UiOpen')
  if platform()=='pad'then
   selectSafe(closeButton)
   -- Re-resolved every frame: prices load right after opening and rebuild the cards.
   UI.SelectWhenReady(function()
    if not open then return nil end
    local cells={};for _,cell in list:GetChildren()do if cell:IsA('Frame')then table.insert(cells,cell)end end
    table.sort(cells,function(a,b)return a.LayoutOrder<b.LayoutOrder end)
    for _,cell in cells do for _,child in cell:GetDescendants()do if child:IsA('GuiButton')then return child end end end
    return closeButton
   end)
  end
  if focusId then task.delay(SLIDE_IN*.8,function()if open then focusOffer(focusId)end end)end
end
PPS.PromptTriggered:Connect(function(prompt,who)if (prompt.Name=='VanTokenShopPrompt'or prompt.Name=='VanRobuxShopPrompt')and(not who or who==p)and InputHints.ConfirmTap()then show(prompt.Parent)end end) -- phones: a real tap, not a camera swipe
event.OnClientEvent:Connect(function(action,data)
 if action=='response'and pending[data.id]then local callback=pending[data.id];pending[data.id]=nil;if data.ok then callback(data.data)elseif open then status.Text=data.error;Audio.Play('UiError')end
 elseif action=='progress'then progress=data;if open then render(os.clock()-lastPurchaseAt<2 and BALANCE_ONLY or nil)end end -- the purchase reply already redrew its card
end)
CAS:BindActionAtPriority('VanShopClose',function(_,state)
 if not open then return Enum.ContextActionResult.Pass end
 if state==Enum.UserInputState.Begin then close()end
 return Enum.ContextActionResult.Sink
end,false,6000,Enum.KeyCode.Escape,Enum.KeyCode.ButtonB)
-- Charge counts change after a purchase or a use; MonetizeEvent replies show in the panel's status line.
for _,use in USES do p:GetAttributeChangedSignal(use.attribute):Connect(function()if open and section=='Robux'then render()end end)end
local function hookMonetize(ev)ev.OnClientEvent:Connect(function(action,ok,message)if open and message and(action=='jumpscareAll'or action=='instantWin')then status.Text=message end end)end
if monetize()then hookMonetize(monetize())else RS.ChildAdded:Connect(function(c)if c.Name=='MonetizeEvent'and c:IsA('RemoteEvent')then hookMonetize(c)end end)end
local timer=0
Run.Heartbeat:Connect(function(dt)timer+=dt;if timer>.25 then timer=0;if open and not canStay()then close()end end end)
p.CharacterRemoving:Connect(close)
p:GetAttributeChangedSignal('AppearanceOpen'):Connect(function()if p:GetAttribute('AppearanceOpen')then close()end end)
local function bindCamera()local c=workspace.CurrentCamera;if c then c:GetPropertyChangedSignal('ViewportSize'):Connect(function()if open then render()end end)end end
workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(bindCamera);bindCamera()
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if open then render()end end)
balance:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if open then layout()end end)
-- Contextual suggestions (OfferPromptClient) open the Robux shop wherever the player is.
local lobbyRequest=0
local function showLobby(which)
 if not lobbyOk()or p:GetAttribute('AppearanceOpen')then return end
 lobbyRequest+=1;local ticket=lobbyRequest
 if open then close()end
 anywhere=false;lobbyMode=true;activeTerminal=nil;section=which=='Robux'and 'Robux'or 'Tokens'
 setHeader()
 list.CanvasPosition=Vector2.zero
 request('vanShop',{},function(data)
  if ticket~=lobbyRequest or not lobbyMode or open or not lobbyOk()then return end
  openPanel(data)
 end)
end
local openLobby=Instance.new('BindableEvent');openLobby.Name='OpenLobbyShop';openLobby.Parent=gui
openLobby.Event:Connect(showLobby)
local openAnywhere=Instance.new('BindableEvent');openAnywhere.Name='OpenRobuxAnywhere';openAnywhere.Parent=gui
openAnywhere.Event:Connect(showAnywhere)
if Run:IsStudio()then local preview=Instance.new('BindableEvent');preview.Name='PreviewVanShop';preview.Parent=script;preview.Event:Connect(show)end
if Run:IsStudio()then
 -- Studio-only: tests close the shop through its real close path.
 local api=Instance.new('BindableFunction');api.Name='LobbyShopTestApi';api.Parent=script
 api.OnInvoke=function(action,terminal)
  if action=='close'then local was=open;if open then close()end;return was end
  if action=='openTerminal'and typeof(terminal)=='Instance'then show(terminal);return true end -- the prompt's own open path
  return false
 end
end
