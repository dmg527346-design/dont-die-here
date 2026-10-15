local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
-- Mission purchase UI. Products are bought and used from the van's ROBUX panel (VanShopClient); there are no HUD buttons or keybinds.
-- This script owns the Gift a Revive teammate picker (opened through the OpenGiftRevive BindableEvent) and shows MonetizeEvent replies.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local Marketplace=game:GetService('MarketplaceService')
local Run=game:GetService('RunService')
local GS=game:GetService('GuiService')
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local p=Players.LocalPlayer
local function padUser()return InputHints.Get()=='pad'end
local function offer(field)for _,o in ipairs(Shop.RobuxOffers)do if o[field]then return o end end end
local giftOffer=offer('giftRevive')
local function event()return RS:FindFirstChild('MonetizeEvent')end

local gui=Instance.new('ScreenGui');gui.Name='MissionShop';gui.ResetOnSpawn=false;gui.DisplayOrder=140;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=p:WaitForChild('PlayerGui')
local openGift=Instance.new('BindableEvent');openGift.Name='OpenGiftRevive';openGift.Parent=gui
local toast=Instance.new('TextLabel');toast.Name='Toast';toast.AnchorPoint=Vector2.new(.5,0);toast.Position=UDim2.new(.5,0,0,70);toast.Size=UDim2.fromOffset(420,32);toast.BackgroundTransparency=.3;toast.BackgroundColor3=Color3.fromRGB(20,16,24);toast.TextColor3=Color3.new(1,1,1);toast.Font=Enum.Font.GothamBold;toast.TextScaled=true;toast.Visible=false;toast.Parent=gui
Instance.new('UICorner',toast)
local toastId=0
local function say(msg)toastId+=1;local id=toastId;toast.Text=msg;toast.Visible=true;task.delay(3,function()if toastId==id then toast.Visible=false end end)end

-- Gift a Revive: a NeonUI panel listing every teammate; downed ones get a REVIVE button (reserve on the server, then buy).
local UI=require(RS:WaitForChild('NeonUI'))
local menu=UI.plate(gui,'GiftReviveMenu',22);menu.AnchorPoint=Vector2.new(.5,.5);menu.Position=UDim2.fromScale(.5,.5);menu.Size=UDim2.fromOffset(380,340);menu.Visible=false
local plate=menu:FindFirstChild('Plate')
local title=UI.text(plate,'Title','GIFT A REVIVE',UI.Font.Title,26);title.Position=UDim2.fromOffset(20,14);title.Size=UDim2.new(1,-90,0,32);UI.fit(title,16,26)
local sub=UI.text(plate,'Subtitle','Revive a teammate, or keep the token.',UI.Font.Body,14,UI.Color.muted);sub.Position=UDim2.fromOffset(20,46);sub.Size=UDim2.new(1,-90,0,18);UI.fit(sub,10,14)
local list=Instance.new('ScrollingFrame');list.Name='Teammates';list.Position=UDim2.fromOffset(16,74);list.Size=UDim2.new(1,-32,1,-90);list.BackgroundTransparency=1;list.BorderSizePixel=0;list.ScrollBarThickness=5;list.AutomaticCanvasSize=Enum.AutomaticSize.Y;list.CanvasSize=UDim2.new();list.Parent=plate
local layout=Instance.new('UIListLayout');layout.Padding=UDim.new(0,8);layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Parent=list
local empty=UI.text(plate,'Empty','',UI.Font.Bold,16,UI.Color.muted);empty.Position=UDim2.new(0,24,.5,-10);empty.Size=UDim2.new(1,-48,0,60);empty.TextXAlignment=Enum.TextXAlignment.Center;empty.TextWrapped=true;empty.Visible=false
local close=UI.closeButton(plate,'Close',44);close.Position=UDim2.new(1,-28,0,28)
local function teammates()
 local t={};for _,q in ipairs(Players:GetPlayers())do if q~=p and q:GetAttribute('MissionActive')==true then table.insert(t,q)end end
 table.sort(t,function(x,y)local dx,dy=x:GetAttribute('RoundDead')==true,y:GetAttribute('RoundDead')==true;if dx~=dy then return dx end;return x.DisplayName<y.DisplayName end)
 return t
end
local pendingTarget
local function closeMenu()
 if not menu.Visible then return end
 menu.Visible=false;UI.FocusRelease('GiftRevive')
 if GS.SelectedObject and GS.SelectedObject:IsDescendantOf(menu)then GS.SelectedObject=nil end
end
close.Activated:Connect(closeMenu)
UIS.InputBegan:Connect(function(input)
 if menu.Visible and(input.KeyCode==Enum.KeyCode.ButtonB or input.KeyCode==Enum.KeyCode.Escape)then closeMenu()end
end)
local function render()
 for _,c in ipairs(list:GetChildren())do if c:IsA('GuiObject')then c:Destroy()end end
 local mates=teammates();local anyDead=false
 for i,q in ipairs(mates)do
  local dead=q:GetAttribute('RoundDead')==true;anyDead=anyDead or dead
  local row=Instance.new('Frame');row.Name='Row_'..q.UserId;row.LayoutOrder=i;row.Size=UDim2.new(1,-8,0,52);row.BackgroundColor3=UI.Color.card;row.Parent=list;UI.corner(row,12);UI.stroke(row,dead and Color3.fromRGB(211,179,246)or UI.Color.grey,1.5,dead and 0 or .5)
  local face=Instance.new('ImageLabel');face.BackgroundColor3=UI.Color.ink;face.Position=UDim2.fromOffset(8,6);face.Size=UDim2.fromOffset(40,40);face.Image='rbxthumb://type=AvatarHeadShot&id='..q.UserId..'&w=150&h=150';face.Parent=row;UI.corner(face,UDim.new(1,0))
  local name=UI.text(row,'Name',q.DisplayName,UI.Font.Bold,16);name.Position=UDim2.fromOffset(56,6);name.Size=UDim2.new(1,-190,0,22);UI.fit(name,11,16)
  local st=UI.text(row,'State',dead and 'DOWN' or 'ALIVE',UI.Font.Title,12,dead and Color3.fromRGB(255,120,140)or UI.Color.green);st.Position=UDim2.fromOffset(56,28);st.Size=UDim2.new(1,-190,0,16)
  if dead then
   local b=UI.button(row,'Revive_'..q.UserId,'REVIVE','buy');b.AnchorPoint=Vector2.new(1,.5);b.Position=UDim2.new(1,-8,.5,0);b.Size=UDim2.fromOffset(124,38)
   b.Activated:Connect(function()
    local ev=event();if not ev or not giftOffer then say('Gift a Revive is unavailable right now.');return end
    pendingTarget=q.UserId;ev:FireServer('giftReviveTarget',q.UserId);closeMenu();say('Preparing purchase for '..q.DisplayName..'...')
   end)
  end
 end
 empty.Visible=not anyDead
 empty.Text=#mates==0 and 'No teammates in this game yet.' or 'Nobody is down right now. Come back here when a teammate needs you.'
 return anyDead
end
local function openMenu()
 render();menu.Visible=true;UI.FocusAcquire('GiftRevive',gui)
 local pop=menu:FindFirstChild('PlatePop');if pop then pop.Scale=.85;game:GetService('TweenService'):Create(pop,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()end
 if padUser()then UI.SelectWhenReady(list:FindFirstChildWhichIsA('TextButton',true)or close)end
end
-- Refresh live while open (teammates going down or being revived).
for _,q in ipairs(Players:GetPlayers())do q:GetAttributeChangedSignal('RoundDead'):Connect(function()if menu.Visible then render()end end)end
Players.PlayerAdded:Connect(function(q)q:GetAttributeChangedSignal('RoundDead'):Connect(function()if menu.Visible then render()end end)end)
Players.PlayerRemoving:Connect(function()if menu.Visible then task.defer(render)end end)
openGift.Event:Connect(openMenu)
-- The GIFT A REVIVE panel in the van opens the same teammate picker.
game:GetService('ProximityPromptService').PromptTriggered:Connect(function(prompt,who)
 if prompt.Name=='VanGiftRevivePrompt'and(not who or who==p)and not menu.Visible then openMenu()end
end)
-- Server replies (action, ok, message). The purchase prompt opens only after the target is reserved.
local function hook(ev)
 ev.OnClientEvent:Connect(function(action,ok,message)
  if action=='giftReviveTarget'then
   if ok and pendingTarget and giftOffer then pcall(function()Marketplace:PromptProductPurchase(p,giftOffer.assetId)end)
   else say(message or 'That teammate cannot be revived right now.')end
   pendingTarget=nil
  elseif message then say(message)end
 end)
end
if event()then hook(event())else RS.ChildAdded:Connect(function(c)if c.Name=='MonetizeEvent'and c:IsA('RemoteEvent')then hook(c)end end)end
Run.Heartbeat:Connect(function()
 local small=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y<500
 menu.Size=small and UDim2.fromOffset(330,280)or UDim2.fromOffset(380,340)
 if menu.Visible and p:GetAttribute('MissionActive')~=true then closeMenu()end
end)
