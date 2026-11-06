-- Shop chapter (owner 2026-10-25): after the first tutorial, the same guide (card, typing, white line, outline) walks
-- the player through spending money for the first time: one team boost from the van bench with the team bank, then
-- Movement Speed in the van's token shop with the 50 tokens the tutorial paid. Gold accent and an UPGRADES tag so it
-- reads as a new chapter, not more of the first one.
-- The server owns every step (save field ShopTutorialStep, published as a player attribute): 1 buy a team boost,
-- 2 buy Movement Speed, 3 done. GearShopServer and ProgressCore charge the tutorial prices and move the step on;
-- this script only shows the way. It speaks only near the van, so nobody is dragged back out of a level.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local GuiService=game:GetService('GuiService')
local RunService=game:GetService('RunService')
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local M={}

local GOLD=Color3.fromRGB(255,198,92)
local VAN_RADIUS=48 -- studs from the van centre: the chapter only shows around the van
local NEAR=7 -- studs: close enough to use a prompt
local INFO_SECONDS,DONE_SECONDS=2.5,3 -- was 8 / 7, then 4.5 / 4 (owner 2026-10-25: get the shop part over with quickly)
local FIRST_LEVEL=2 -- the chapter waits until this level
local EXTRA_LINE=16 -- px added to the card for a third line of text
local SKIP_ROOM=40 -- px of the card's right side left to the SKIP button on phones
local SHORT_TO_ID={SPEED='Speed',STAMINA='Stamina',RECOVERY='Recovery',FLASHLIGHT='Flashlight',['CROUCH SPEED']='Crouch'}

local started=false
function M.Start(View,Hints,Guided)
 if started then return end;started=true
 local p=Players.LocalPlayer
 local view,skipped,lastStep=nil,false,p:GetAttribute('ShopTutorialStep')
 local infoUntil,doneUntil=0,0
 local selectedFor -- the buy button the gamepad selection was moved to (once)

 local function close()if view then view:Destroy();view=nil end end
 -- Funnel: each card is reported once per server (PlayerMetricsServer logs the 'ShopTutorial' funnel).
 local reported={}
 local function report(id)
  if reported[id]then return end;reported[id]=true
  local ev=RS:FindFirstChild('TutorialStepEvent');if ev then ev:FireServer(id)end
 end
 local function skip()
  skipped=true;close();report('shopSkipped')
  local ev=RS:FindFirstChild('LobbyEvent');if ev then ev:FireServer(900000000+math.random(1,99999),'shopTutorialSkip',{})end
 end
 local function ensureView()
  if not view then view=View.New(Hints,skip);view.gui.Name='ShopTutorial';view.route.Name='ShopTutorialRoute'end
  return view
 end
 local function van()return workspace:FindFirstChild('AnomalyRecoveryVan',true)end
 local function rootPart()local c=p.Character;return c and c:FindFirstChild('HumanoidRootPart')end
 local function alive()
  local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
  return h and h.Health>0 and p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true
 end
 -- A floor point in the aisle in front of a screen or box (inside the wall there is no path).
 local function floorUnder(part,root)local q=part.Position+part.CFrame.LookVector*2.5;return Vector3.new(q.X,root.Position.Y-2.5,q.Z)end
 -- Boost bench slots that are still for sale, the SPEED one first.
 local function boostSlots(v)
  local list={}
  for i=1,3 do
   local a=v:FindFirstChild('BoostSlot'..i);local prompt=a and a:FindFirstChild('BoostPrompt');local sign=a and a:FindFirstChild('BoostLabel')
   if prompt and prompt.Enabled and sign then
    local lines={};for _,t in sign:GetChildren()do if t:IsA('TextLabel')then table.insert(lines,t)end end
    table.sort(lines,function(x,y)return x.Position.Y.Scale<y.Position.Y.Scale end)
    local short=lines[1]and lines[1].Text or '';local id=SHORT_TO_ID[short]
    local price=lines[3]and tonumber((lines[3].Text:gsub('[^%d]','')))
    if id then table.insert(list,{anchor=a,prompt=prompt,id=id,short=short,priceLabel=lines[3],price=price})end
   end
  end
  table.sort(list,function(x,y)return(x.id=='Speed'and 0 or 1)<(y.id=='Speed'and 0 or 1)end)
  return list
 end
 local function keyWord(device,hold)
  if device=='pad'then return(hold and 'Hold ' or 'Press ')..Hints.Button('ButtonX')end
  if device=='touch'then return hold and 'Hold the button' or 'Tap the button'end
  return hold and 'Hold E' or 'Press E'
 end

 local acc=0
 RunService.Heartbeat:Connect(function(dt)
  acc+=dt;if acc<.1 then return end;acc=0
  local step=p:GetAttribute('ShopTutorialStep')
  -- Server step changes: a bought boost explains where the money comes from; a bought upgrade closes the chapter.
  if step~=lastStep then
   if lastStep==1 and step==2 then infoUntil=os.clock()+INFO_SECONDS end
   if lastStep==2 and step==3 then doneUntil=os.clock()+DONE_SECONDS end
   lastStep=step
  end
  local root=rootPart();local v=van()
  -- Waits for the first tutorial to end (in Studio, ReplicatedStorage.ShopTutorialTest lets a test run it alongside).
  local waiting=Guided.IsActive()and not(RunService:IsStudio()and RS:GetAttribute('ShopTutorialTest')==true)
  -- Owner 2026-10-25: the chapter starts once the player has reached level 2 (the first level's money is in the bank).
  local round=RS:FindFirstChild('RecoveryRound');local level=round and round:GetAttribute('Round')or 1
  local busy=skipped or waiting or level<FIRST_LEVEL or not alive()or not root or not v
  local nearVan=not busy and((root.Position-v:GetPivot().Position).Magnitude<=VAN_RADIUS or p:GetAttribute('VanShopOpen')==true)
  local talking=os.clock()<infoUntil or os.clock()<doneUntil
  if busy or not nearVan or not(step==1 or step==2 or talking)then
   if view and not talking then view:Show(nil,{})end
   if busy and view then view:Show(nil,{})end
   return
  end
  local device=Hints.Get();local vw=ensureView()
  local data={map=nil,from=root.Position}
  local s

  if os.clock()<doneUntil then
   s={id='shopDone',action='done'};data.title="YOU'RE FASTER NOW";data.text='Movement Speed is yours for good. Finish runs to earn more tokens.'
  elseif os.clock()<infoUntil then
   s={id='shopMoney',action='done'};data.title='WHOLE TEAM UPGRADED!'
   data.text=device=='touch'and 'Money comes from finishing levels. It stays every round, so keep upgrading!'
    or 'That money comes from finishing levels. It stays every round, so you can keep upgrading.'
  elseif step==1 then
   local slots=boostSlots(v);local slot=slots[1]
   local round=RS:FindFirstChild('RecoveryRound');local bank=round and round:GetAttribute('Bank')or 0
   local mine=slot and math.min(slot.price or Shop.TutorialBoostPrice,Shop.TutorialBoostPrice)
   if not slot or bank<mine then vw:Show(nil,{});return end -- nothing on the bench or not enough yet: stay quiet
   -- This player's price on every open box (the server charges the same; the signs are shared, so this is local).
   for _,o in slots do
    local own=math.min(o.price or Shop.TutorialBoostPrice,Shop.TutorialBoostPrice)
    if o.priceLabel.Text~='$'..own then o.priceLabel.Text='$'..own end
    if o.prompt.ActionText~='Buy $'..own then o.prompt.ActionText='Buy $'..own end
   end
   local display=v:FindFirstChild('BoostDisplay_'..slot.id,true)
   data.targetPart=slot.anchor;data.targetName='TEAM UPGRADE';data.targetModel=display
   if(root.Position-slot.anchor.Position).Magnitude>NEAR then
    s={id='shopBoostWalk',action='move'};data.title='TEAM UPGRADES'
    data.text=('Your team has $%d. Walk to the cereal boxes in the van.'):format(bank)
    data.goal=floorUnder(slot.anchor,root);data.goalKey='boost'..slot.id
   else
    s={id='shopBoostBuy',action='use'};data.title='BUY A TEAM UPGRADE'
    data.text=('%s to buy %s. It helps the whole team. Yours costs $%d.'):format(keyWord(device,true),slot.short,mine)
   end
  elseif step==2 then
   local shopGui=p.PlayerGui:FindFirstChild('VanShop')
   local open=p:GetAttribute('VanShopOpen')==true and shopGui
   local buy=open and shopGui:FindFirstChild('Buy_upgrade_speed',true)
   if buy and buy:IsA('GuiButton')and buy.Visible and buy.AbsoluteSize.X>0 then
    s={id='shopSpeedBuy',action='done'};data.title='MOVEMENT SPEED'
    data.text='Buy it with your 50 tokens. You keep it forever.'
    vw:Show(s,data);vw:Chapter('UPGRADES 2/2',GOLD);report(s.id)
    if device=='touch'then vw.text.Size=vw.text.Size-UDim2.fromOffset(SKIP_ROOM,0)end
    vw:Spotlight(buy,true,true);vw.tap.Visible=false -- the dim and the pulsing ring are enough; the label sat on the card's text
    if device=='pad'and selectedFor~=buy then selectedFor=buy;GuiService.SelectedObject=buy end
    return
   end
   local terminal=v:FindFirstChild('VanTokenTerminal',true)
   if open then
    s={id='shopTokensTab',action='done'};data.title='TOKEN SHOP';data.text='Open the TOKENS shop to find Movement Speed.'
   elseif terminal then
    data.targetPart=terminal;data.targetName='TOKEN SHOP';data.targetModel=terminal
    -- Owner 2026-10-25: no +50 TOKENS card; after the team upgrade a plain walk card points to the token screen.
    if(root.Position-terminal.Position).Magnitude<=NEAR then
     s={id='shopTokensOpen',action='use'};data.title='TOKEN SHOP';data.text=keyWord(device,false)..' to open the token shop.'
    else
     s={id='shopTokensGo',action='move'};data.title='TOKEN SHOP';data.text='Now walk to the TOKEN SHOP screen in the van.'
     data.goal=floorUnder(terminal,root);data.goalKey='tokens'
    end
   end
  end
  if not s then vw:Show(nil,{});return end
  vw:Show(s,data);report(s.id)
  -- Longer lines (the money explanation) get one more line of card, so the pixel text never spills out.
  if #data.text>(device=='touch'and 56 or 78)then
   vw.card.Size=vw.card.Size+UDim2.fromOffset(0,EXTRA_LINE);vw.text.Size=vw.text.Size+UDim2.fromOffset(0,EXTRA_LINE)
  end
  if device=='touch'then vw.text.Size=vw.text.Size-UDim2.fromOffset(SKIP_ROOM,0)end -- phones: keep the words clear of SKIP
  vw:Chapter(step==1 and not(os.clock()<infoUntil)and 'UPGRADES 1/2'or 'UPGRADES 2/2',GOLD)
 end)
end
return M
