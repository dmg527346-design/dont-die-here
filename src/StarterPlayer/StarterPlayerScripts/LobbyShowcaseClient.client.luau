-- Lobby showcase, client side (stands are built by ServerScriptService.LobbyShowcaseServer): spins the items, flies a
-- comet carrying each trail around its stand, draws every plaque (icon, name, what it does, live price, BUY) and
-- buys: Robux offers through Roblox's purchase prompt, token offers through the lobby's own purchase request.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Market=game:GetService('MarketplaceService')
local PromptService=game:GetService('ProximityPromptService')
local StarterGui=game:GetService('StarterGui')
local C=require(RS:WaitForChild('LobbyShopCatalog'))
local event=RS:WaitForChild('LobbyEvent')
local p=Players.LocalPlayer
local pg=p:WaitForChild('PlayerGui')
local folder=workspace:WaitForChild('LobbyWorld'):WaitForChild('Showcase')
while folder:GetAttribute('Ready')~=true do task.wait(.2)end

local GOLD=Color3.fromRGB(255,206,64)
local INK=Color3.fromRGB(22,18,30)
local function notice(text)
 pcall(function()StarterGui:SetCore('SendNotification',{Title='Shop',Text=text,Duration=4})end)
end
-- Token purchases use the lobby request channel; ids far above MainMenuClient's own counter, so replies never mix.
local sequence,pending=900000,{}
event.OnClientEvent:Connect(function(action,data)
 if action~='response'or type(data)~='table'then return end
 local cb=pending[data.id];if not cb then return end
 pending[data.id]=nil;cb(data.ok,data.ok and data.data or data.error)
end)
local function offerFor(id)return C.RobuxById[id]or C.ById[id]end
local owned={}
local refreshers={}
-- Earned cosmetics (rank auras and trails): what this player owns and wears, from the lobby's 'progress' request.
-- Equipping goes through the same server request as the Cosmetics menu ('appearanceEquip'), which checks ownership and
-- keeps one cosmetic per slot (equipping replaces whatever was in that slot).
local earned,wearing={},{}
local function request(action,data,cb)
 sequence+=1;local rid=sequence;pending[rid]=cb or function()end
 event:FireServer(rid,action,data or {})
 task.delay(12,function()pending[rid]=nil end)
end
local function redrawAll()for _,f in refreshers do f()end end
local museumHook -- Curio Cabinet: set by the block at the end of the stand setup
local function takeProgress(progress)
 if type(progress)~='table'then return end
 table.clear(earned)
 local o=progress.owned
 if type(o)=='table'then for k,v in o do if v==true and type(k)=='string'then earned[k]=true elseif type(v)=='string'then earned[v]=true end end end
 wearing=type(progress.equipped)=='table'and progress.equipped or {}
 if museumHook and type(progress.museum)=='table'then museumHook(progress.museum)end
 redrawAll()
end
local function syncProgress()request('progress',nil,function(ok,data)if ok and type(data)=='table'then takeProgress(data.progress)end end)end
local equipBusy=false
-- Cosmetics an offer puts on the character: a token cosmetic itself, a Robux pass's granted cosmetic, or both VIP pieces.
local SLOTS={Hat=true,Ring=true,Shirt=true,Shoes=true,Eyes=true,Back=true,Trail=true,Torch=true,Aura=true,Title=true}
local function wearTargets(offer)
 if offer.id=='vip'then local t,a=C.ById.title_vip,C.ById.aura_vip;return t and a and{t,a}or nil end
 if offer.grants then local c=C.ById[offer.grants];return c and{c}or nil end
 if SLOTS[offer.kind]then return{offer}end
 return nil
end
local function ownsAll(t)for _,c in t do if not earned[c.id]then return false end end;return true end
-- Equip shows only for what this player owns: the save must own every piece, and for a Robux pass Roblox must also
-- confirm the pass (or the server's Pass_<id> grant). The server refuses any equip it does not own regardless.
local function canEquip(offer,t)
 if not t or not ownsAll(t)then return false end
 if C.RobuxById[offer.id]and offer.kind=='Pass'then return owned[offer.id]==true or p:GetAttribute('Pass_'..offer.id)==true end
 return true
end
local function wearsAll(t)for _,c in t do if wearing[c.kind]~=c.id then return false end end;return true end
-- Equip or unequip through the Cosmetics menu's own server request: ownership is checked there and each slot holds one.
local function toggleEquip(offer)
 if equipBusy then return end
 local targets=wearTargets(offer)
 if not canEquip(offer,targets)then notice(offer.description or'Unlocked by playing.');return end
 local on=wearsAll(targets)
 local queue={}
 if on and offer.id=='vip'then queue={{offer='',slot='VIP'}}
 else for _,c in targets do table.insert(queue,{offer=on and''or c.id,slot=c.kind})end end
 equipBusy=true
 local function nextOne(i)
  local job=queue[i]
  if not job then equipBusy=false;notice(on and(offer.name..' taken off.')or('Equipped '..offer.name..'.'));return end
  request('appearanceEquip',job,function(ok,data)
   if ok and type(data)=='table'then takeProgress(data.progress);nextOne(i+1)
   else equipBusy=false;notice(tostring(data))end
  end)
 end
 nextOne(1)
end
local function buy(id)
 local offer=offerFor(id);if not offer then return end
 local wear=wearTargets(offer)
 if offer.nonPurchasable or canEquip(offer,wear)then toggleEquip(offer);return end
 if C.RobuxById[id]then
  if offer.giftRevive then notice('Gift a Revive is bought during a game: open the ROBUX panel in the van when a teammate dies.');return end
  if owned[id]then notice('You already own '..offer.name..'.');return end
  local ok=pcall(function()if offer.kind=='Pass'then Market:PromptGamePassPurchase(p,offer.assetId)else Market:PromptProductPurchase(p,offer.assetId)end end)
  if not ok then notice('Roblox purchases are unavailable right now.')end
 else
  sequence+=1;local rid=sequence
  pending[rid]=function(ok,result)
   if ok then owned[id]=true;if type(result)=='table'then takeProgress(result.progress)end;notice(type(result)=='table'and result.message or('Unlocked '..offer.name..'!'));if refreshers[id]then refreshers[id]()end
   else notice(tostring(result))end
  end
  event:FireServer(rid,'purchase',{offer=id})
  task.delay(12,function()pending[rid]=nil end)
 end
end
Market.PromptGamePassPurchaseFinished:Connect(function(who,passId,bought)
 if who~=p or not bought then return end
 for _,o in C.RobuxOffers do if o.kind=='Pass'and o.assetId==passId then owned[o.id]=true;if refreshers[o.id]then refreshers[o.id]()end end end
 task.delay(2,syncProgress);task.delay(6,syncProgress) -- the server grants the pass's cosmetic once it sees the pass
end)
PromptService.PromptTriggered:Connect(function(prompt)
 local id=prompt:GetAttribute('OfferId');if id and prompt:IsDescendantOf(folder)then buy(id)end
end)

-- Plaque: a SurfaceGui in PlayerGui (so its BUY button takes clicks and taps) on the lectern's face.
local function plaque(stand)
 local id=stand:GetAttribute('OfferId');local offer=offerFor(id);local face=stand:FindFirstChild('Plaque')
 if not offer or not face then return end
 local robux=C.RobuxById[id]~=nil
 local gui=Instance.new('SurfaceGui');gui.Name='ShowcasePlaque_'..id;gui.Adornee=face;gui.Face=Enum.NormalId.Front
 gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(560,350);gui.LightInfluence=0;gui.Brightness=1.25
 gui.MaxDistance=45;gui.ResetOnSpawn=false;gui.Parent=pg
 local bg=Instance.new('Frame');bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=INK;bg.Parent=gui
 local tint=Color3.fromRGB(unpack(offer.color or {255,255,255}))
 local grad=Instance.new('UIGradient');grad.Rotation=90;grad.Color=ColorSequence.new(tint:Lerp(INK,.7),INK);grad.Parent=bg
 local function label(text,x,y,w,h,size,color)
  local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Position=UDim2.fromOffset(x,y);t.Size=UDim2.fromOffset(w,h)
  t.Text=text;t.TextColor3=color;t.TextScaled=true;t.TextWrapped=true;t.TextXAlignment=Enum.TextXAlignment.Left;t.Font=Enum.Font.FredokaOne;t.Parent=bg
  local lim=Instance.new('UITextSizeConstraint');lim.MaxTextSize=size;lim.Parent=t
  local s=Instance.new('UIStroke');s.Thickness=2;s.Color=Color3.new(0,0,0);s.Parent=t
  return t
 end
 local icon=Instance.new('ImageLabel');icon.Position=UDim2.fromOffset(20,20);icon.Size=UDim2.fromOffset(130,130);icon.BackgroundColor3=Color3.fromRGB(34,30,42)
 icon.Image=offer.image or C.OfferImages[id]or'';icon.Parent=bg
 Instance.new('UICorner',icon).CornerRadius=UDim.new(0,16)
 local ir=Instance.new('UIStroke');ir.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;ir.Thickness=4;ir.Color=GOLD;ir.Parent=icon
 if icon.Image==''then icon.Visible=false end
 local tx=icon.Visible and 168 or 20;local tw=560-tx-20
 label(string.upper(offer.name),tx,22,tw,44,30,Color3.fromRGB(255,236,180))
 label(offer.description or'',tx,72,tw,82,19,Color3.fromRGB(214,210,226))
 local price=label('',20,172,520,48,34,Color3.fromRGB(120,255,170));price.TextXAlignment=Enum.TextXAlignment.Center
 local button=Instance.new('TextButton');button.Position=UDim2.fromOffset(20,236);button.Size=UDim2.fromOffset(520,94);button.BackgroundColor3=GOLD
 button.AutoButtonColor=true;button.Text='BUY';button.TextColor3=INK;button.TextScaled=true;button.Font=Enum.Font.FredokaOne;button.Parent=bg
 Instance.new('UICorner',button).CornerRadius=UDim.new(0,14)
 local bs=Instance.new('UIStroke');bs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;bs.Thickness=4;bs.Color=Color3.fromRGB(120,80,10);bs.Parent=button
 local bl=Instance.new('UITextSizeConstraint');bl.MaxTextSize=40;bl.Parent=button
 local bp=Instance.new('UIPadding');bp.PaddingTop=UDim.new(0,18);bp.PaddingBottom=UDim.new(0,18);bp.Parent=button
 button.Activated:Connect(function()buy(id)end)
 local robuxPrice=offer.price
 local prompt=face:FindFirstChild('BuyPrompt')
 local function draw()
  local isOwned=owned[id]==true
  local wear=wearTargets(offer)
  if canEquip(offer,wear)then -- owned cosmetic: equip / unequip right here, no menu
   local on=wearsAll(wear)
   price.Text=on and'WEARING IT'or(offer.nonPurchasable and'YOU EARNED THIS'or'YOU OWN THIS');price.TextColor3=Color3.fromRGB(120,255,170)
   button.Visible=true;button.AutoButtonColor=true;button.Text=on and'UNEQUIP'or'EQUIP'
   button.BackgroundColor3=on and Color3.fromRGB(110,104,124)or GOLD
   if prompt then prompt.Enabled=true;prompt.ActionText=on and'Unequip'or'Equip'end
   return
  end
  if offer.nonPurchasable then
   local rank=string.match(offer.description or'','^Rank reward: reach (%a+)')
   price.Text=rank and('REACH '..string.upper(rank)..' RANK')or'NOT SOLD: EARN IT';price.TextColor3=Color3.fromRGB(255,214,96);button.Visible=false
   if prompt then prompt.Enabled=false end
  elseif isOwned then
   price.Text='OWNED';button.Text='OWNED';button.BackgroundColor3=Color3.fromRGB(90,90,100);button.AutoButtonColor=false
  elseif robux then
   price.Text='R$ '..tostring(robuxPrice);button.Text=offer.giftRevive and'BUY IN A GAME'or'BUY'
  else
   price.Text=tostring(offer.price or'?')..' TOKENS';button.Text='UNLOCK'
  end
  if prompt and not offer.nonPurchasable then prompt.ActionText=isOwned and'Owned'or robux and('Buy  R$ '..tostring(robuxPrice))or('Unlock  '..tostring(offer.price)..' tokens')end
 end
 refreshers[id]=draw;draw()
 if robux then
  task.spawn(function()
   local ok,info=pcall(function()return Market:GetProductInfo(offer.assetId,offer.kind=='Pass'and Enum.InfoType.GamePass or Enum.InfoType.Product)end)
   if ok and info and info.PriceInRobux then robuxPrice=info.PriceInRobux end
   if offer.kind=='Pass'then
    local has,yes=pcall(function()return Market:UserOwnsGamePassAsync(p.UserId,offer.assetId)end)
    if has and yes then owned[id]=true end
   end
   draw()
  end)
 end
end

-- Moving pieces: spin the floating items. Stands stream in after join (StreamingEnabled), so each one is set
-- up when it arrives, once.
local spinners={}
local paused=false -- set by setMission below
local asleep={} -- stand -> the lights/particles/beams/trails it switched off while the camera is far away (see the end)
local function setup(stand)
 if not stand:IsA('Model')or not stand:GetAttribute('OfferId')or stand:GetAttribute('ShowcaseReady')then return end
 if not stand:WaitForChild('Plaque',10)or not stand:WaitForChild('ItemAnchor',10)then return end
 stand:SetAttribute('ShowcaseReady',true)
 plaque(stand)
 local item=stand:FindFirstChild('Item')
 if item then table.insert(spinners,{item=item,home=item:IsA('Model')and item:GetPivot()or item.CFrame})end
end
folder.ChildAdded:Connect(function(stand)task.spawn(setup,stand)end)
for _,stand in folder:GetChildren()do task.spawn(setup,stand)end
-- ===== Curio Cabinet (2026-10-26) =====
-- One wall, everyone's own collection: per player, a cubby shows either the item (sold at least once: Museum save) or
-- its dust sheet. Sold today/yesterday = NEW tag; the first sight this session lifts the sheet off (cloth + bell).
local Cursed=require(RS:WaitForChild('CursedCatalog'))
local Audio=require(RS:WaitForChild('GameplayAudio'))
local museum,museumReady,revealed={},false,{}
local cabinet,cabinetSlots,curioGui,curioUi=nil,0,nil,nil
local missingAt=0
local TITLES={{0,'Visitor'},{10,'Junior Curator'},{25,'Curator'},{50,'Head Curator'},{75,'Grand Curator'}}
local function today()return math.floor(workspace:GetServerTimeNow()/86400)end
local function setHidden(root,hidden)
 local v=hidden and 1 or 0
 for _,d in root:GetDescendants()do if d:IsA('BasePart')or d:IsA('Decal')or d:IsA('Texture')then d.LocalTransparencyModifier=v end end
end
local function liftSheet(sheet,delay)
 task.delay(delay,function()
  if not sheet.Parent then return end
  local home,t0=sheet.CFrame,os.clock()
  pcall(Audio.Play,'ClothHandle',sheet.Position)
  local conn;conn=Run.RenderStepped:Connect(function()
   local a=math.clamp((os.clock()-t0)/.7,0,1)
   if not sheet.Parent then conn:Disconnect();return end
   sheet.CFrame=home*CFrame.new(0,a*1.2,0)*CFrame.Angles(0,a*2,0);sheet.LocalTransparencyModifier=a
   if a>=1 then conn:Disconnect();sheet.CFrame=home end
  end)
 end)
end
local function newTag(slot,sheet,on)
 local tag=slot:FindFirstChild('CurioNew')
 if not on then if tag then tag:Destroy()end;return end
 if tag then return end
 tag=Instance.new('BillboardGui');tag.Name='CurioNew';tag.Adornee=sheet;tag.Size=UDim2.fromOffset(64,24);tag.StudsOffset=Vector3.new(0,.95,0)
 tag.MaxDistance=30;tag.LightInfluence=0;tag.AlwaysOnTop=false;tag.Parent=slot
 local l=Instance.new('TextLabel');l.BackgroundColor3=GOLD;l.Size=UDim2.fromScale(1,1);l.Font=Enum.Font.FredokaOne;l.TextScaled=true;l.Text='NEW';l.TextColor3=INK;l.Parent=tag
 Instance.new('UICorner',l).CornerRadius=UDim.new(0,8)
end
local function curioCard(cab)
 if curioGui then curioGui:Destroy();curioGui=nil end
 local face=cab:FindFirstChild('CurioCard');if not face then return end
 local gui=Instance.new('SurfaceGui');gui.Name='ShowcasePlaque_CurioCard';gui.Adornee=face;gui.Face=Enum.NormalId.Front
 gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(560,350);gui.LightInfluence=0;gui.Brightness=1.25
 gui.MaxDistance=45;gui.ResetOnSpawn=false;gui.Enabled=not paused;gui.Parent=pg
 local bg=Instance.new('Frame');bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=INK;bg.Parent=gui
 local function label(text,x,y,w,h,size,color,center)
  local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Position=UDim2.fromOffset(x,y);t.Size=UDim2.fromOffset(w,h)
  t.Text=text;t.TextColor3=color;t.TextScaled=true;t.TextWrapped=true;t.Font=Enum.Font.FredokaOne
  t.TextXAlignment=center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left;t.Parent=bg
  local lim=Instance.new('UITextSizeConstraint');lim.MaxTextSize=size;lim.Parent=t
  local s=Instance.new('UIStroke');s.Thickness=2;s.Color=Color3.new(0,0,0);s.Parent=t
  return t
 end
 local ui={}
 ui.title=label('MY CURSED CURIOS',20,14,380,40,30,Color3.fromRGB(255,236,180))
 ui.count=label('',400,14,140,40,30,GOLD);ui.count.TextXAlignment=Enum.TextXAlignment.Right
 local barBack=Instance.new('Frame');barBack.Position=UDim2.fromOffset(20,62);barBack.Size=UDim2.fromOffset(520,16);barBack.BackgroundColor3=Color3.fromRGB(50,44,62);barBack.Parent=bg
 Instance.new('UICorner',barBack).CornerRadius=UDim.new(1,0)
 ui.bar=Instance.new('Frame');ui.bar.Size=UDim2.fromScale(0,1);ui.bar.BackgroundColor3=GOLD;ui.bar.Parent=barBack
 Instance.new('UICorner',ui.bar).CornerRadius=UDim.new(1,0)
 ui.rank=label('',20,84,520,30,22,Color3.fromRGB(190,160,255))
 label('STILL MISSING',20,120,520,28,22,Color3.fromRGB(214,210,226))
 ui.lines={}
 for i=1,3 do ui.lines[i]=label('',20,150+(i-1)*58,520,54,19,Color3.fromRGB(244,236,210))end
 ui.foot=label('Sell an item in a run to put it on the shelf.',20,322,520,22,16,Color3.fromRGB(150,140,170),true)
 curioGui,curioUi=gui,ui
end
local function slotsOf(cab)
 local list={}
 -- Cubbies are the section models' children (no walk through all ~1,600 descendants every second).
 for _,section in cab:GetChildren()do for _,d in section:GetChildren()do if d:IsA('Model')and d:GetAttribute('CurioId')then table.insert(list,d)end end end
 table.sort(list,function(a,b)return (a:GetAttribute('CurioIndex')or 0)<(b:GetAttribute('CurioIndex')or 0)end)
 return list
end
local function drawCurios(cab,slots)
 if not curioUi then return end
 local have,missing=0,{}
 for _,slot in slots do local id=slot:GetAttribute('CurioId');if museum[id]~=nil then have+=1 else table.insert(missing,slot)end end
 local total=#slots;local pct=total>0 and have/total or 0
 curioUi.count.Text=have..' / '..total;curioUi.bar.Size=UDim2.fromScale(pct,1)
 local title='Visitor';for _,t in TITLES do if pct*100>=t[1]then title=t[2]end end;if total>0 and have==total then title='Master of Curios'end
 curioUi.rank.Text=string.upper(title)
 local start=#missing>0 and (missingAt%#missing) or 0
 for i=1,3 do
  local slot=missing[#missing>0 and ((start+i-1)%#missing)+1 or 0]
  local meta=slot and Cursed.Items[slot:GetAttribute('CurioId')]
  curioUi.lines[i].Text=(#missing>=i and meta)and(meta.name..'  -  '..(slot:GetAttribute('Rare')and'rare: a close-up choice'or meta.hint or'any level'))or(i==1 and #missing==0 and'Nothing! Every curio is home.'or'')
 end
end
local function refreshCabinet()
 local cab=folder:FindFirstChild('CurioCabinet')
 if not cab or not museumReady or cab:GetAttribute('Building')then return end -- still being filled (LobbyShowcaseServer)
 local slots=slotsOf(cab)
 if cab~=cabinet or #slots~=cabinetSlots then cabinet,cabinetSlots=cab,#slots;curioCard(cab)end -- built, or streamed back in
 local now=today();local delay,lifted=0,false
 for _,slot in slots do
  local id=slot:GetAttribute('CurioId');local day=museum[id];local sold=day~=nil
  local item,sheet=slot:FindFirstChild('Item'),slot:FindFirstChild('DustSheet')
  if item then setHidden(item,not sold)end
  if sheet then
   if sold and day>=now-1 and not revealed[id]then liftSheet(sheet,delay);delay+=.25;lifted=true
   else sheet.LocalTransparencyModifier=sold and 1 or 0 end -- a lifting sheet stays visible until its animation runs
   newTag(slot,sheet,sold and day>=now-1)
  end
  if sold then revealed[id]=true end
 end
 if lifted then task.delay(delay+.6,function()pcall(Audio.Play,'QuotaMet')end)end
 drawCurios(cab,slots)
end
museumHook=function(map)
 table.clear(museum)
 for id,day in map do if type(id)=='string'and type(day)=='number'then museum[id]=day end end
 museumReady=true;refreshCabinet()
end
folder.ChildAdded:Connect(function(c)if c.Name=='CurioCabinet'then task.defer(refreshCabinet)end end)
task.spawn(function()
 while true do
  task.wait(1)
  if not paused then
   local cab=folder:FindFirstChild('CurioCabinet')
   if cab and(cab~=cabinet or #slotsOf(cab)~=cabinetSlots)then refreshCabinet()end
   if os.clock()-missingAt>=6 and cabinet and cabinet.Parent then missingAt=os.clock()//1;drawCurios(cabinet,slotsOf(cabinet))end
  end
 end
end)
local t0=os.clock()
Run.RenderStepped:Connect(function()
 if paused then return end
 local t=os.clock()-t0
 for i=#spinners,1,-1 do
  local s=spinners[i]
  if not s.item.Parent then table.remove(spinners,i);continue end -- the stand streamed out; it is set up again when it comes back
  if asleep[s.item.Parent] then continue end
  local cf=s.home*CFrame.new(0,math.sin(t*1.6)*.18,0)*CFrame.Angles(0,t*.9,0)
  if s.item.Parent then if s.item:IsA('Model')then s.item:PivotTo(cf)else s.item.CFrame=cf end end
 end
end)
syncProgress()
for _,a in {'EquippedAura','EquippedTitle'}do p:GetAttributeChangedSignal(a):Connect(syncProgress)end
p.CharacterAdded:Connect(function()task.wait(1);syncProgress()end)
task.spawn(function()while true do task.wait(20);syncProgress()end end)
-- During a mission (Studio runs lobby and mission in one server) the stands are 1,200 studs away: switch their lights,
-- particles, trails, beams and plaques off and stop the spinner, and switch them back on in the lobby.
local saved={}
local function setMission(on)
 if on==paused then return end
 paused=on
 if on then
  table.clear(saved)
  for _,x in folder:GetDescendants()do
   if(x:IsA('Light')or x:IsA('ParticleEmitter')or x:IsA('Beam')or x:IsA('Trail'))and x.Enabled then saved[x]=true;x.Enabled=false end
  end
  for _,g in pg:GetChildren()do if g.Name:match('^ShowcasePlaque_')then g.Enabled=false end end
 else
  for x in saved do if x.Parent then x.Enabled=true end end
  table.clear(saved)
  for _,g in pg:GetChildren()do if g.Name:match('^ShowcasePlaque_')then g.Enabled=true end end
 end
end
p:GetAttributeChangedSignal('MissionActive'):Connect(function()setMission(p:GetAttribute('MissionActive')==true)end)
setMission(p:GetAttribute('MissionActive')==true)
-- Lobby frame cost (2026-10-25): the gallery holds ~110 lights, ~80 particle emitters and the running statues' beams.
-- A stand farther than FAR_STUDS from the camera switches its effects off and stops spinning until the camera comes back.
local FAR_STUDS=60 -- plaques already hide at 45 (SurfaceGui MaxDistance)
local function sleepStand(stand,on)
 if on==(asleep[stand]~=nil) then return end
 if on then
  local off={}
  for _,x in stand:GetDescendants()do if(x:IsA('Light')or x:IsA('ParticleEmitter')or x:IsA('Beam')or x:IsA('Trail'))and x.Enabled then off[x]=true;x.Enabled=false end end
  asleep[stand]=off
 else
  for x in asleep[stand]do if x.Parent then x.Enabled=true end end
  asleep[stand]=nil
 end
end
task.spawn(function()
 while true do
  task.wait(.25)
  local cam=workspace.CurrentCamera
  if not paused and cam then -- in a mission setMission owns the switches
   local at=cam.CFrame.Position
   for _,stand in folder:GetChildren()do
    if stand:IsA('Model')and stand:GetAttribute('OfferId')then sleepStand(stand,(stand:GetPivot().Position-at).Magnitude>FAR_STUDS)end
   end
  end
 end
end)

-- Crew Photo Booth, the crew's side (owner 2026-10-28 "make the photobooth work and look cool"). The server runs the
-- booth (LobbyShowcaseServer: BoothCountdown 3..1..0, BoothFlashAt). From inside you could not see any of it, so for
-- whoever stands in the booth: the view becomes the booth's lens on the back wall with a viewfinder and a big 3-2-1,
-- a white flash on the shutter, then a printed card of the crew slides up for a few seconds. Nothing is stored.
do
 local Tween=game:GetService('TweenService')
 local RankCatalog=require(RS:WaitForChild('RankCatalog'))
 local PIXEL=Font.new('rbxasset://fonts/families/FredokaOne.json')
 local booth,zone,gui,count,flash,card,hint
 local holding=false
 local function inBooth(q)
  local c=q.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
  if not(r and h and h.Health>0 and zone and zone.Parent)then return false end
  local o=zone.CFrame:PointToObjectSpace(r.Position)
  return math.abs(o.X)<=zone.Size.X/2 and math.abs(o.Y)<=zone.Size.Y/2+1 and math.abs(o.Z)<=zone.Size.Z/2
 end
 local function label(parent,name,text,size,pos,anchor)
  local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Size=size;t.Position=pos;t.AnchorPoint=anchor or Vector2.zero
  t.FontFace=PIXEL;t.TextScaled=true;t.Text=text;t.TextColor3=Color3.new(1,1,1);t.Parent=parent
  local s=Instance.new('UIStroke');s.Thickness=3;s.Color=Color3.fromRGB(30,16,48);s.Parent=t
  return t
 end
 local function makeGui()
  if gui and gui.Parent then return end
  gui=Instance.new('ScreenGui');gui.Name='PhotoBoothView';gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=400;gui.Enabled=false
  local view=Instance.new('Frame');view.Name='Viewfinder';view.BackgroundTransparency=1;view.Size=UDim2.fromScale(1,1);view.Parent=gui
  for _,a in{Vector2.new(0,0),Vector2.new(1,0),Vector2.new(0,1),Vector2.new(1,1)}do for _,wide in{true,false}do
   local f=Instance.new('Frame');f.Name='Corner';f.BorderSizePixel=0;f.BackgroundColor3=Color3.new(1,1,1);f.AnchorPoint=a
   f.Size=wide and UDim2.new(.1,0,0,5)or UDim2.new(0,5,.15,0);f.Position=UDim2.fromScale(a.X==0 and .05 or .95,a.Y==0 and .08 or .92);f.Parent=view
  end end
  local dot=Instance.new('Frame');dot.Name='RecDot';dot.Size=UDim2.fromOffset(14,14);dot.Position=UDim2.new(.05,14,.08,16);dot.BackgroundColor3=Color3.fromRGB(190,140,255);dot.Parent=view
  local dc=Instance.new('UICorner');dc.CornerRadius=UDim.new(1,0);dc.Parent=dot
  label(view,'Rec','REC',UDim2.fromOffset(70,22),UDim2.new(.05,34,.08,12))
  count=label(view,'Count','3',UDim2.fromScale(.3,.3),UDim2.fromScale(.5,.45),Vector2.new(.5,.5))
  hint=label(view,'Hint','SMILE... OR SCREAM',UDim2.fromScale(.5,.06),UDim2.fromScale(.5,.86),Vector2.new(.5,.5))
  flash=Instance.new('Frame');flash.Name='Flash';flash.Size=UDim2.fromScale(1,1);flash.BackgroundColor3=Color3.new(1,1,1);flash.BackgroundTransparency=1;flash.ZIndex=5;flash.Parent=gui
  gui.Parent=p:WaitForChild('PlayerGui')
 end
 local function printCard(crew)
  if card then card:Destroy()end
  card=Instance.new('Frame');card.Name='PhotoCard';card.AnchorPoint=Vector2.new(.5,0);card.Position=UDim2.fromScale(.5,1.05);card.Size=UDim2.fromOffset(300,360)
  card.BackgroundColor3=Color3.fromRGB(246,240,226);card.Rotation=-4;card.ZIndex=6;card.Parent=gui
  local fit=Instance.new('UIScale');fit.Scale=math.clamp(workspace.CurrentCamera.ViewportSize.Y/700,.6,1.3);fit.Parent=card
  local cc=Instance.new('UICorner');cc.CornerRadius=UDim.new(0,8);cc.Parent=card
  local shot=Instance.new('Frame');shot.Name='Shot';shot.Position=UDim2.fromOffset(18,18);shot.Size=UDim2.new(1,-36,0,250);shot.BackgroundColor3=Color3.new(1,1,1);shot.ZIndex=6;shot.Parent=card
  local grad=Instance.new('UIGradient');grad.Color=ColorSequence.new(Color3.fromRGB(70,40,110),Color3.fromRGB(18,12,30));grad.Rotation=90;grad.Parent=shot
  local n=math.min(#crew,4)
  local w=(264-12)/math.max(n,1)
  for i=1,n do
   local q=crew[i];local r=RankCatalog.Get(q:GetAttribute('RR')or 0)
   local side=math.min(w-10,80)
   local ghost=Instance.new('Frame');ghost.Name='Ghost'..i;ghost.AnchorPoint=Vector2.new(.5,1);ghost.Size=UDim2.fromOffset(side,side*1.15)
   ghost.Position=UDim2.new(0,6+w*(i-.5),1,-34);ghost.BackgroundColor3=r.color;ghost.ZIndex=7;ghost.Parent=shot
   local gc=Instance.new('UICorner');gc.CornerRadius=UDim.new(.5,0);gc.Parent=ghost
   for _,ex in{.28,.6}do local eye=Instance.new('Frame');eye.Size=UDim2.fromScale(.14,.2);eye.Position=UDim2.fromScale(ex,.3);eye.BackgroundColor3=Color3.fromRGB(20,16,28);eye.ZIndex=8;eye.Parent=ghost;local ec=Instance.new('UICorner');ec.CornerRadius=UDim.new(.5,0);ec.Parent=eye end
   local mouth=Instance.new('Frame');mouth.Size=UDim2.fromScale(.24,.16);mouth.Position=UDim2.fromScale(.38,.6);mouth.BackgroundColor3=Color3.fromRGB(20,16,28);mouth.ZIndex=8;mouth.Parent=ghost
   local mc=Instance.new('UICorner');mc.CornerRadius=UDim.new(.5,0);mc.Parent=mouth
   local nm=label(shot,'Name'..i,q.DisplayName,UDim2.fromOffset(w-4,20),UDim2.new(0,6+w*(i-.5),1,-6),Vector2.new(.5,1));nm.ZIndex=8
  end
  local cap=label(card,'Caption','SPOOK CREW OF '..#crew,UDim2.new(1,-36,0,30),UDim2.fromOffset(18,276));cap.TextColor3=Color3.fromRGB(70,40,110);cap.ZIndex=7
  cap:FindFirstChildOfClass('UIStroke').Enabled=false
  local foot=label(card,'Footer',"DON'T DIE HERE  "..os.date('%b %d'),UDim2.new(1,-36,0,22),UDim2.fromOffset(18,312));foot.TextColor3=Color3.fromRGB(120,100,140);foot.ZIndex=7
  foot:FindFirstChildOfClass('UIStroke').Enabled=false
  Tween:Create(card,TweenInfo.new(.7,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5),AnchorPoint=Vector2.new(.5,.5),Rotation=-3}):Play()
  local shown=card
  task.delay(4.5,function()
   if shown.Parent then
    Tween:Create(shown,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.fromScale(.5,1.6)}):Play()
    task.delay(.55,function()shown:Destroy();if gui and not holding and card==shown then gui.Enabled=false end end)
   end
  end)
 end
 local prevType,prevCF,prevFov
 local hidden={}
 local function hold(on)
  local cam=workspace.CurrentCamera
  if on and not holding then
   holding=true;prevType,prevCF,prevFov=cam.CameraType,cam.CFrame,cam.FieldOfView
   hidden={};for _,g in p.PlayerGui:GetDescendants()do if g:IsA('ScreenGui')and g~=gui and g.Enabled then hidden[g]=true;g.Enabled=false end end -- a clean frame (menus included)
   Run:BindToRenderStep('PhotoBoothLens',Enum.RenderPriority.Camera.Value+30,function()
    if not(zone and zone.Parent)then return end
    for g in hidden do if g.Enabled then g.Enabled=false end end -- other scripts switch their HUD back on
    cam.CameraType=Enum.CameraType.Scriptable;cam.FieldOfView=88 -- the booth is shallow: a wide lens fits the crew
    cam.CFrame=CFrame.lookAt((zone.CFrame*CFrame.new(0,2.0,-4.8)).Position,(zone.CFrame*CFrame.new(0,1.3,0)).Position) -- from the opening (zone -Z), where the crew face after walking in
   end)
  elseif not on and holding then
   holding=false;Run:UnbindFromRenderStep('PhotoBoothLens')
   for g in hidden do if g.Parent then g.Enabled=true end end;hidden={}
   if prevCF then cam.CFrame=prevCF end;cam.FieldOfView=prevFov or 70 -- back where the view was, so the zoom distance is kept
   cam.CameraType=(prevType==Enum.CameraType.Scriptable)and Enum.CameraType.Custom or(prevType or Enum.CameraType.Custom)
   local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if h then cam.CameraSubject=h end
  end
 end
 local function onCountdown()
  local n=booth and booth:GetAttribute('BoothCountdown')
  if n and n>0 then
   if n==3 and inBooth(p)then makeGui();gui.Enabled=true;gui.Viewfinder.Visible=true;flash.BackgroundTransparency=1;hint.Text='SMILE... OR SCREAM';hold(true)end
   if holding and count then count.Text=tostring(n);count.TextTransparency=0;count.Size=UDim2.fromScale(.42,.42);Tween:Create(count,TweenInfo.new(.35,Enum.EasingStyle.Back),{Size=UDim2.fromScale(.3,.3)}):Play()end
  elseif n==0 and holding then
   count.Text='';hint.Text='';flash.BackgroundTransparency=0;Tween:Create(flash,TweenInfo.new(.7),{BackgroundTransparency=1}):Play()
   local crew={};for _,q in Players:GetPlayers()do if inBooth(q)then table.insert(crew,q)end end
   if #crew==0 then crew={p}end
   task.delay(.9,function()hold(false);local v=gui:FindFirstChild('Viewfinder');if v then v.Visible=false end;printCard(crew)end) -- shot taken: the viewfinder goes, the print comes
  end
 end
 local hooked
 task.spawn(function()
  while true do
   local lw=workspace:FindFirstChild('LobbyWorld');local sc=lw and lw:FindFirstChild('Showcase');local b=sc and sc:FindFirstChild('CrewPhotoBooth')
   if b and b~=hooked then
    hooked=b;booth=b;zone=b:WaitForChild('BoothZone',10)
    b:GetAttributeChangedSignal('BoothCountdown'):Connect(function()if booth==b then onCountdown()end end)
   end
   -- walked out mid-countdown: give the view back
   if holding and not inBooth(p)and(booth==nil or(booth:GetAttribute('BoothCountdown')or 0)>0)then hold(false);if gui then gui.Enabled=false end end
   task.wait(.5)
  end
 end)
end


-- Showcase runners (owner 2026-10-29 'the spawn is really laggy'): the server no longer animates the 10 trail runners
-- (their 570 limb parts were replicated to every player all the time). This client plays the run cycle itself, only
-- for runners within RUNNER_RANGE of its camera, and stops it for the rest and during missions.
do
 local RUNNER_RANGE=110 -- the whole hall, but only runners actually on screen (below)
 local tracks={} -- Runner -> AnimationTrack
 task.spawn(function()
  while true do
   -- Owner 2026-10-29: never alive during a real run (mission with a real save), even dead or spectating: both the
   -- player's MissionActive and the server's MissionRunning must be off. During a run the runners' trail particles
   -- and beams are switched off on this screen too, so they cost nothing at all.
   local cam=workspace.CurrentCamera;local inLobby=p:GetAttribute('MissionActive')~=true and workspace:GetAttribute('MissionRunning')~=true
   for _,stand in folder:GetChildren()do
    local runner=stand:FindFirstChild('Runner');local id=runner and runner:GetAttribute('RunnerAnim')
    if id then
     local root=runner:FindFirstChild('HumanoidRootPart')
     local near=inLobby and cam~=nil and root~=nil and(root.Position-cam.CFrame.Position).Magnitude<RUNNER_RANGE
     if near then local _,onScreen=cam:WorldToViewportPoint(root.Position);near=onScreen end
     local track=tracks[runner]
     if near and not track then
      local hum=runner:FindFirstChildOfClass('Humanoid');local animator=hum and hum:FindFirstChildOfClass('Animator')
      if animator then
       local anim=Instance.new('Animation');anim.AnimationId=id
       local ok,t=pcall(animator.LoadAnimation,animator,anim)
       if ok and t then t.Looped=true;tracks[runner]=t;track=t end
      end
     end
     if track then
      if near and not track.IsPlaying then track:Play(.25,1,1.1)elseif not near and track.IsPlaying then track:Stop(.25)end
     end
    end
   end
   for _,stand in folder:GetChildren()do
    local runner=stand:FindFirstChild('Runner')
    if runner and runner:GetAttribute('RunnerAnim')and runner:GetAttribute('FxOff')~=(not inLobby)then
     runner:SetAttribute('FxOff',not inLobby) -- local attribute: this screen only
     for _,d in runner:GetDescendants()do if d:IsA('ParticleEmitter')or d:IsA('Beam')then d.Enabled=inLobby end end
    end
   end
   for runner in tracks do if not runner.Parent then tracks[runner]=nil end end
   task.wait(.5)
  end
 end)
end
