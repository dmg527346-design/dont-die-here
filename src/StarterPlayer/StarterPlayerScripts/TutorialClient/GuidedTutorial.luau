local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Hints=require(RS:WaitForChild('InputHints'))
local Flow=require(script.Parent:WaitForChild('TutorialFlow'))
local View=require(script.Parent:WaitForChild('TutorialGuide'))
local Catalog=require(RS:WaitForChild('CursedCatalog'))
local M={};local active=false;local started=false;local goalVan=false
function M.IsActive()return active end
-- The van is marked by TutorialClient's green wireframe, not a Highlight (that outlined the courtyard walls as a white box).
function M.GoalIsVan()return active and goalVan end
local function escape(s)return(tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;'))end
local function green(s)return '<font color="#A7E38A">'..escape(s)..'</font>'end
local function validItem(model)
 return model and model.Parent and model:IsA('Model')and model.PrimaryPart and model:GetAttribute('Kind')=='pickup'and model:GetAttribute('ItemId')and not model:GetAttribute('Gear')and not model:GetAttribute('AdminSpawned')and not model:GetAttribute('LobbyToy')and not model:GetAttribute('Selling')and not model:GetAttribute('MonsterCarried')and not model:GetAttribute('AttachedTo')and not model:GetAttribute('ItemWearOwner')
end
function M.Start()
 if started then return end;started=true
 -- Step changes settle before they show (2026-10-22): near a distance edge (7 studs to the basket, 11 to the cart) the
 -- decided step flipped every few frames, replaying the card's pop-in over and over. A new step must hold for
 -- STEP_SETTLE seconds first; the very first step and 'complete' show at once.
 local STEP_SETTLE=.45;local shownStep,pendingId,pendingSince=nil,nil,0
 local p=Players.LocalPlayer;local view;local session=Flow.New();local target;local mapWas;local cartWas;local cartPosition;local cartMoved=0;local pusherPosition;local pusherId;local lastCargoCount=0;local storedUntil=0;local runWas;local wasMission=false;local skipped=false;local persisted=false;local replay=false;local lightUsed=false;local lastFlash;local flashCharacter;local flashConnection
 -- Funnel: each step id is reported once per server (PlayerMetricsServer logs the 'Tutorial' funnel).
 local reported={}
 local function report(id)
  if reported[id]then return end;reported[id]=true
  local ev=RS:FindFirstChild('TutorialStepEvent');if ev then ev:FireServer(id)end
 end
 local function finish()
  if persisted then return end;persisted=true
  if not replay then RS:WaitForChild('LobbyEvent'):FireServer(900000000+math.random(1,99999),'tutorialDone',{})end
 end
 local function makeView()return View.New(Hints,function()report('skipped');skipped=true;active=false;finish();if view then view:Show(nil,{})end end)end
 local function button(name)
  local b=p.PlayerGui:FindFirstChild(name,true);return b and b:IsA('GuiButton')and b or nil
 end
 local crouchFeedback=p:GetAttributeChangedSignal('Crouching'):Connect(function()
  if active and view and view.currentStep and view.currentStep.action=='crouch'then view:Success('crouch',view.currentStep.id)end
 end)
 local PathfindingService=game:GetService('PathfindingService')
 local function choose(interactive,cart,root)
  local lockedRooms={};if interactive then for _,door in interactive:GetChildren()do if door:GetAttribute('Kind')=='door'and door:GetAttribute('Locked')and door:GetAttribute('Room')then lockedRooms[door:GetAttribute('Room')]=true end end end
  -- Locked-room areas by position too, so an untagged item behind a locked door is never the target.
  local lockedAreas={};local graphValue=interactive and interactive.Parent:FindFirstChild('GeneratedGraph')
  if next(lockedRooms)and graphValue then local ok,graph=pcall(function()return game:GetService('HttpService'):JSONDecode(graphValue.Value)end)
   if ok and graph and graph.rooms then for _,r in graph.rooms do if lockedRooms[r.name]and r.x1 then table.insert(lockedAreas,r)end end end end
  local function safe(m)
   if lockedRooms[m:GetAttribute('Room')]or m:GetAttribute('CargoStored')or m:GetAttribute('HeldBy')or m:GetAttribute('Locked')then return false end
   local q=m.PrimaryPart.Position
   for _,r in lockedAreas do if q.X>r.x1-1 and q.X<r.x2+1 and q.Z>r.z1-1 and q.Z<r.z2+1 and math.abs(q.Y-(r.level or 0)*16-3)<9 then return false end end
   return true
  end
  if validItem(target)and safe(target)then return target end
  target=nil;if not interactive or not cart or not cart.PrimaryPart then return nil end
  local from=root and root.Position or cart.PrimaryPart.Position
  local list={}
  for _,m in interactive:GetChildren()do if validItem(m)and safe(m)then
   -- The free start-room item always comes first; the rest are shortlisted by straight distance from the player.
   local q=m.PrimaryPart.Position
   local d=(q-from).Magnitude+math.abs(q.Y-from.Y)*4-(m:GetAttribute('BonusLoot')and 1000 or 0)
   table.insert(list,{m=m,d=d,key=tostring(m:GetAttribute('LootSpawnIdentity')or m:GetAttribute('ItemId'))})
  end end
  table.sort(list,function(a,b)if math.abs(a.d-b.d)>=.01 then return a.d<b.d end;return a.key<b.key end)
  if #list==0 then return nil end
  if list[1].m:GetAttribute('BonusLoot')then target=list[1].m;return target end
  -- Then the item with the shortest WALK, measured like the white line (owner 2026-10-22: the straight-line pick sent
  -- players on long detours around walls). Same agent and goal as TutorialGuide:Route; a failed path counts triple.
  local best=math.huge
  for i=1,math.min(6,#list)do
   local c=list[i]
   if not(validItem(c.m)and c.m.PrimaryPart)then continue end -- ComputeAsync yields: the item can stream out or be taken meanwhile
   local q=c.m.PrimaryPart.Position
   local away=Vector3.new(from.X-q.X,0,from.Z-q.Z);local goal=away.Magnitude>.1 and q+away.Unit*4 or q
   local length=c.d*3
   local path=PathfindingService:CreatePath({AgentRadius=cart:GetAttribute('HeldBy')==p.UserId and 2.4 or 1.8,AgentHeight=5,AgentCanJump=false,WaypointSpacing=3}) -- wider while pushing the cart, like the line
   if pcall(function()path:ComputeAsync(from,goal)end)and path.Status==Enum.PathStatus.Success then
    local w=path:GetWaypoints();length=0;for j=2,#w do length+=(w[j].Position-w[j-1].Position).Magnitude end
   end
   path:Destroy()
   if length<best-.01 and validItem(c.m)then best=length;target=c.m end
  end
  return target
 end
 task.spawn(function()
  while p.Parent do
   task.wait(.1)
   local state=RS:FindFirstChild('RecoveryRound');local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive');local cart=interactive and interactive:FindFirstChild('RecoveryCart')
   local character=p.Character;local root=character and character:FindFirstChild('HumanoidRootPart');local hum=character and character:FindFirstChildOfClass('Humanoid')
   local mission=p:GetAttribute('MissionActive')==true
   local preview=Run:IsStudio()and RS:GetAttribute('TutorialPreview')=='first'
   local round=state and state:GetAttribute('Round')or 1
   local runKey=state and state:GetAttribute('QuestRunId')or state
   if mission and(not wasMission or runKey~=runWas)then
    session=Flow.New();cartMoved=0;cartPosition=nil;target=nil;skipped=false;persisted=false;lightUsed=false;lastFlash=character and character:GetAttribute('FlashlightOn')
    replay=preview or p:GetAttribute('AdminOwner')==true and p:GetAttribute('TutorialDone')~=false
    active=(preview or p:GetAttribute('TutorialDone')==false or replay)and round<=1
   elseif not mission then active=false end
   wasMission=mission;runWas=runKey
   if character~=flashCharacter then
    if flashConnection then flashConnection:Disconnect();flashConnection=nil end
    flashCharacter=character;lastFlash=character and character:GetAttribute('FlashlightOn')
    if character then flashConnection=character:GetAttributeChangedSignal('FlashlightOn'):Connect(function()
     local value=character:GetAttribute('FlashlightOn')
     if active and lastFlash~=nil and value~=lastFlash then lightUsed=true;if view and view.currentStep and view.currentStep.action=='light'then view:Success('light',view.currentStep.id)end end;lastFlash=value
    end)end
   end
   if mapWas~=map or cartWas~=cart then target=nil;cartPosition=nil;mapWas=map;cartWas=cart end
   if cart and cart.PrimaryPart and cart:GetAttribute('HeldBy')~=nil then
    local id=cart:GetAttribute('HeldBy');local owner=Players:GetPlayerByUserId(id);local mover=owner and owner.Character and owner.Character:FindFirstChild('HumanoidRootPart')
    local pos=cart.PrimaryPart.Position
    if mover and cartPosition and pusherPosition and pusherId==id then
     local delta=mover.Position-pusherPosition;local walked=Vector3.new(delta.X,0,delta.Z).Magnitude
     if walked>.05 then cartMoved+=math.min((pos-cartPosition).Magnitude,walked*1.25,5)end
    end
    cartPosition=pos;pusherPosition=mover and mover.Position;pusherId=id
   else cartPosition=nil;pusherPosition=nil;pusherId=nil end
   if skipped or not active or p:GetAttribute('IntroPlaying')==true then if view then view:Destroy();view=nil end;continue end
   if not view then view=makeView()end
   local alive=root and hum and hum.Health>0 and p:GetAttribute('RoundDead')~=true
   local held;local cargoCount=0
   if interactive then for _,m in interactive:GetChildren()do if validItem(m)then
    if m:GetAttribute('HeldBy')==p.UserId then if not held or m:GetAttribute('ItemId')==p:GetAttribute('CursedActive')then held=m end end
    if m:GetAttribute('CargoStored')then cargoCount+=1 end
   end end end
   if cargoCount>lastCargoCount then storedUntil=os.clock()+2.5 end;lastCargoCount=cargoCount
   local item=choose(interactive,cart,alive and root or nil)
   -- choose() waits on pathfinding: meanwhile an item can stream out, be grabbed or be sold (live V1193:
   -- 'attempt to index nil with Position'). Re-check both before their positions are read below.
   if item and not validItem(item)then item=nil end;if held and not held.PrimaryPart then held=nil end
   local world=workspace:FindFirstChild('RecoveryCamp');local van=world and world:FindFirstChild('AnomalyRecoveryVan');local vanRoot=van and van.PrimaryPart
   local basket=cart and cart:FindFirstChild('BasketFloor');local cartRoot=cart and cart.PrimaryPart
   local basketPoint=cartRoot and cartRoot.Position
   local over=false
   if cartRoot and typeof(cart:GetAttribute('BasketOffset'))=='Vector3'and typeof(cart:GetAttribute('BasketSize'))=='Vector3'then
    local cf=cartRoot.CFrame*CFrame.new(cart:GetAttribute('BasketOffset')*cart:GetScale());local size=cart:GetAttribute('BasketSize')*cart:GetScale();basketPoint=cf.Position
    if held then local q=cf:PointToObjectSpace(held.PrimaryPart.Position);over=math.abs(q.X)<size.X/2+.5 and math.abs(q.Z)<size.Z/2+.5 and q.Y>-size.Y/2-.3 and q.Y<size.Y/2+3.2 end
   end
   local vanPoint=vanRoot and(vanRoot.CFrame*CFrame.new(0,1,-18)).Position
   local atVan=false;if vanRoot and cartRoot then local q=vanRoot.CFrame:PointToObjectSpace(cartRoot.Position);atVan=math.abs(q.X)<9 and q.Z>-24 and q.Z<12 end
   local teamSize=0;for _,q in Players:GetPlayers()do if q:GetAttribute('MissionActive')==true then teamSize+=1 end end
   local observation={teamSize=teamSize,justStored=os.clock()<storedUntil,active=mission,alive=alive==true or alive~=nil and alive~=false,cartReady=cartRoot~=nil,cartHeldBy=cart and cart:GetAttribute('HeldBy'),cartMine=cart and cart:GetAttribute('HeldBy')==p.UserId,cartMoved=cartMoved,cartValue=state and state:GetAttribute('CartValue')or 0,cargoCount=cargoCount,sold=state and state:GetAttribute('Sold')or 0,quota=state and state:GetAttribute('Quota')or math.huge,phase=state and state:GetAttribute('Phase'),round=round,lightUsed=lightUsed,crouching=p:GetAttribute('Crouching')==true,heldItem=held~=nil,itemOverBasket=over,cartDistance=root and basketPoint and(root.Position-basketPoint).Magnitude or math.huge,target=item~=nil,targetCartDistance=cartRoot and item and(cartRoot.Position-item.PrimaryPart.Position).Magnitude or math.huge,cartAtVan=atVan}
   local step=Flow.Decide(session,observation)
   if step and shownStep and step.id~=shownStep.id and step.id~='complete'then
    if pendingId~=step.id then pendingId=step.id;pendingSince=os.clock()end
    if os.clock()-pendingSince<STEP_SETTLE then step=shownStep else shownStep=step;pendingId=nil end
   else shownStep=step;pendingId=nil end
   if step then report(step.id)end
   if step and step.id=='complete'then finish();active=false;view:Destroy();view=nil;continue end
   local device=Hints.Get();local grab=device=='touch'and 'Tap GRAB'or device=='pad'and 'Hold '..Hints.Button('ButtonR2')or 'Hold left click'
   local release=device=='touch'and 'tap DROP'or device=='pad'and 'release '..Hints.Button('ButtonR2')or 'release left click'
   local keep=device=='touch'and 'Keep the cart grabbed'or device=='pad'and 'Keep holding '..Hints.Button('ButtonR2')or 'Keep holding left click'
   local itemName=held and(held:GetAttribute('DisplayName')or (Catalog.Items[held:GetAttribute('ItemId')]or{}).name)or item and(item:GetAttribute('DisplayName')or(Catalog.Items[item:GetAttribute('ItemId')]or{}).name)or 'the item'
   local touch=device=='touch'
   local texts={
    loading={'GETTING READY','Stay with your team.'},
    grabCart={'GRAB THE CART',touch and 'Walk to the cart and tap GRAB.'or grab..' on the cart.'},
    waitCart={'GRAB THE CART','A teammate has the cart. Grab it when they let go.'},
    regrabCart={'GRAB THE CART AGAIN',touch and 'Tap GRAB on the cart.'or grab..' on the cart.'},
    pushCart={'PUSH THE CART',touch and 'Keep GRAB on and walk along the line.'or keep..' and walk along the line.'},
    followCart={'FOLLOW YOUR TEAM','Follow the line to the item.'},
    stored={'STORED IN THE CART!','Nice! That item is safe in the cart.'},
    flashlight={'TRY YOUR FLASHLIGHT',touch and 'Tap the LIGHT button.'or device=='pad'and 'Press '..(Hints.Button('ButtonB')=='Circle'and 'Circle'or 'B')..'.'or 'Press F.'},
    crouch={'TRY CROUCHING',touch and 'Tap the CROUCH button.'or device=='pad'and 'Click the right stick.'or 'Press C or Ctrl. You can hide under tables.'},
    stand={'STAND UP',touch and 'Tap STAND.'or device=='pad'and 'Click the right stick again.'or 'Press C or Ctrl again.'},
    parkCart={'PARK THE CART',(touch and 'Tap DROP'or release:sub(1,1):upper()..release:sub(2))..' to park here.'},
    pickFirstItem={'PICK UP THE ITEM',(touch and 'Tap GRAB on 'or grab..' on ')..green(itemName)..'.'},
    findItems={'FIND MORE ITEMS','Find items and put them in the cart.'},
    bringItem={'BRING IT TO THE CART','Carry '..green(itemName)..' to the cart.'},
    aimBasket={'AIM AT THE BASKET','Look at the basket to move it over.'},
    releaseItem={'DROP IT IN',(touch and 'Tap DROP'or release:sub(1,1):upper()..release:sub(2))..' now.'},
    nextItem={'TAKE THE CART TO MORE LOOT','Follow the line to '..green(itemName)..'.'},
    helpCollect={'HELP COLLECT',(touch and 'Tap GRAB on 'or grab..' on ')..green(itemName)..'.'},
    findLoot={'LOOKING FOR LOOT','Stay with the cart.'},
    grabToSell={'TIME TO SELL',touch and 'Tap GRAB on the cart.'or grab..' on the cart.'},
    pushToVan={'PUSH IT TO THE VAN','Follow the line into the van.'},
    followToVan={'BACK TO THE VAN','Follow the line.'},
    releaseCart={'LET GO TO SELL',(touch and 'Tap DROP'or release:sub(1,1):upper()..release:sub(2))..'.'},
    waitForSale={'SELLING SOON','Wait for your teammate to let go.'},
    selling={'SELLING...','The van is buying your loot.'},
    extract={'EVERYONE INTO THE VAN','Quota met! Follow the line into the van.'},
   }
   local data=step and texts[step.id]
   goalVan=step~=nil and step.goal=='van'
   if step and data then
    local goalModel=step.goal=='cart'and cart or step.goal=='basket'and cart or step.goal=='item'and item or step.goal=='van'and van or nil
    local goalPart=step.goal=='basket'and basket or goalModel and goalModel.PrimaryPart
    local goal=step.goal=='basket'and basketPoint or step.goal=='van'and vanPoint or goalPart and goalPart.Position
    -- Navigation ends beside solid objects, never inside the cart or a tabletop.
    if step.goal=='cart'and cartRoot then goal=(cartRoot.CFrame*CFrame.new(0,0,-6)).Position
    elseif (step.goal=='item'or step.goal=='basket')and goal and root then
     local away=Vector3.new(root.Position.X-goal.X,0,root.Position.Z-goal.Z)
     if away.Magnitude>.1 then goal+=away.Unit*4 end
    end
    if goal and root and interactive and step.action~='light'and step.action~='crouch'then
     local doors={};for _,door in interactive:GetChildren()do if door:GetAttribute('Kind')=='door'and door:GetAttribute('Open')==false and not door:GetAttribute('Locked')then table.insert(doors,door)end end
     local direction=goal-root.Position
     if #doors>0 and direction.Magnitude>.1 then
      local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=doors
      local hit=workspace:Raycast(root.Position,direction.Unit*math.min(direction.Magnitude,9),params)
      if hit then
       local door=hit.Instance:FindFirstAncestorOfClass('Model')
       if door and door:GetAttribute('Kind')=='door'then
        step={id='openDoor',goal='door',action='use',shared=true};goalModel=door;goalPart=door.PrimaryPart
        if goalPart then local away=Vector3.new(root.Position.X-goalPart.Position.X,0,root.Position.Z-goalPart.Position.Z);goal=goalPart.Position+(away.Magnitude>.1 and away.Unit*3 or Vector3.zero)end
        data={'OPEN THE DOOR',device=='touch'and 'Tap OPEN.'or device=='pad'and 'Press '..Hints.Button('ButtonX')..'.'or 'Press E.'}
       end
      end
     end
    end
    local targetName=step.goal=='door'and 'OPEN THIS DOOR'or step.goal=='basket'and 'PUT IT IN THE BASKET'or step.goal=='cart'and 'YOUR CART'or step.goal=='van'and 'THE VAN'or itemName
    local spot=step.action=='use'and button('UseAction')or step.action=='light'and button('LightAction')or step.action=='crouch'and button('CrouchAction')or(step.action=='grab'or step.action=='release')and button('GrabDrop')or nil
    if step.action=='grab'and root and goalPart and(root.Position-goalPart.Position).Magnitude>8 then spot=nil end
    view:Show(step,{title=data[1],text=data[2],button=spot,targetPart=goalPart,targetModel=step.goal~='van'and goalModel or nil,targetName=targetName,from=root and root.Position,goal=goal,goalKey=goalModel,map=map,push=observation.cartMine})
   else view:Show(nil,{})end
  end
  crouchFeedback:Disconnect();if flashConnection then flashConnection:Disconnect()end;if view then view:Destroy()end
 end)
end
return M
