-- Retention metrics -> Creator Dashboard > Analytics > Custom events. Read-only observer: it only
-- watches existing attributes (MissionActive, RoundDead, RecoveryRound.Round/Phase) and never changes gameplay.
-- Lobby and missions are separate servers: the funnel session (MetricsSession/MetricsFirst/MetricsStart) travels in
-- teleport data (LobbyServer launch/joinParty, RecoveryRoundServer leave), so one sitting stays one funnel session.
local Players=game:GetService('Players');local Analytics=game:GetService('AnalyticsService')
local RS=game:GetService('ReplicatedStorage');local Run=game:GetService('RunService');local Http=game:GetService('HttpService')
local F1,F2,F3=Enum.AnalyticsCustomFieldKeys.CustomField01.Name,Enum.AnalyticsCustomFieldKeys.CustomField02.Name,Enum.AnalyticsCustomFieldKeys.CustomField03.Name
local LAST_EVENT_WINDOW=60 -- a quit within this many seconds is blamed on the last event
local TELEPORT_WINDOW=90 -- leaving within this many seconds of a metrics-tagged teleport is a server hop, not a quit
local state=RS:FindFirstChild('RecoveryRound') -- missing on lobby servers; resolved lazily below
local S={}
local watchItems -- set with the item watchers below
local function studioTrace(line) -- Studio only: the last analytics calls, for playtest checks (live servers send them instead)
 local ss=game:GetService('ServerStorage');ss:SetAttribute('AnalyticsTrace',string.sub((ss:GetAttribute('AnalyticsTrace')or'')..line..';',-2000))
end
local function log(p,name,value,fields)
 if Run:IsStudio()then studioTrace('ev:'..name..':'..tostring(fields and fields[Enum.AnalyticsCustomFieldKeys.CustomField01.Name]or''));return end -- keep test sessions out of live numbers
 pcall(function()Analytics:LogCustomEvent(p,name,value,fields)end)
end
local function levelBucket(r)return r<=0 and 'Lobby'or r>=10 and 'Level 10+'or 'Level '..r end
local function roundBucket()return levelBucket(state and state:GetAttribute('Round')or 0)end
local function phase()return tostring(state and state:GetAttribute('Phase')or 'None')end
-- Phases where a death or revive is a real one. RecoveryRoundServer.rebuildWorld sets RoundDead=true on everyone as a
-- deployment flag between levels (phase Won/Failed), which used to log thousands of fake deaths and revives.
local LIVE={Searching=true,Returning=true,Selling=true}
local function aliveNow(p)return p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true end
local function bucketSeconds(s)return s<30 and '<30s'or s<120 and '30s-2m'or s<300 and '2-5m'or s<900 and '5-15m'or '15m+'end
local function event(s,name)s.lastEvent=name;s.lastEventAt=os.clock()end
local function settleAlive(s,p)
 if s.aliveSince then s.aliveTotal+=os.clock()-s.aliveSince;s.aliveSince=nil end
 if aliveNow(p)then s.aliveSince=os.clock()end
end
local function deathCause(p)
 local killer=p:GetAttribute('LastMonsterKill')
 if killer and os.clock()-(p:GetAttribute('LastMonsterKillAt')or -100)<10 then return 'Monster: '..tostring(killer)end
 if p:GetAttribute('MonsterJumpscareActive')then return 'Monster'end
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
 if r and r.Position.Y<-20 then return 'Fell'end
 return 'Other'
end
local function mapKind()local map=workspace:FindFirstChild('Mansion');return tostring(map and map:GetAttribute('MapKind')or'Unknown')end
-- Funnels (rebuilt 2026-10-26; the old Onboarding steps, FirstSession, SessionLength, Levels, Tutorial and ShopTutorial
-- funnels are no longer sent). Creator Dashboard > Analytics > Funnels shows five:
--  Onboarding    (built-in, once per player ever): a brand-new player's path from joining to the first upgrade.
--  1 Tutorial    (one per sitting): the monster intro, every guided tutorial card, then the shop chapter.
--  2 Level Loop  (one per player per level): cart, items, 5 items, quota, sale, clear.
--  3 Play Time   (one per sitting, lobby and missions together): how long people stay.
--  4 Run Depth   (one per run): how far a run gets, level 1 to clearing level 10.
local ONBOARDING={'Joined','Saw the monster intro','Mission started','Grabbed the cart','Picked up an item','First item in the cart',
 '5 items in the cart','First sale','Cleared level 1','Reached level 2','Reached level 3','Bought an upgrade'}
local function funnel(p,s,index)
 if s.funnel[index]then return end;s.funnel[index]=true
 if Run:IsStudio()then studioTrace('onb:'..index);return end
 pcall(function()Analytics:LogOnboardingFunnelStepEvent(p,index,ONBOARDING[index])end)
end
-- Tutorial: client ids (TutorialFlow cards, MonsterIntroClient, ShopTutorial) -> step labels in play order.
local TUTORIAL_STEPS={
 {'introStart','Monster intro started'},{'introDone','Monster intro finished'},
 {'grabCart','Card: grab the cart'},{'pushCart','Card: push the cart'},{'parkCart','Card: park the cart'},
 {'pickFirstItem','Card: pick up the item'},{'bringItem','Carrying the first item'},{'aimBasket','Card: aim at the basket'},
 {'releaseItem','Card: drop it in'},{'findItems','First item stored'},{'grabToSell','Cart full: grab it'},
 {'pushToVan','Pushing the cart to the van'},{'selling','Selling'},{'crouch','Card: crouch'},{'stand','Card: stand up'},
 {'extract','Card: back to the van'},{'complete','Tutorial complete'},
 {'shop1','Shop: chapter started'},{'shopBoostWalk','Shop: walking to team upgrades'},{'shopBoostBuy','Shop: at the cereal boxes'},
 {'shop4','Shop: bought a team upgrade'},{'shopTokensOpen','Shop: at the token screen'},{'shopSpeedBuy','Shop: token shop open'},
 {'shop7','Shop: bought Movement Speed'}}
local TUTORIAL,TUTORIAL_INDEX={},{};for i,v in TUTORIAL_STEPS do TUTORIAL[i]=v[2];TUTORIAL_INDEX[v[1]]=i end
local LOOP={'Level started','Grabbed the cart','Picked up an item','1 item in the cart','3 items in the cart','5 items in the cart','Quota reached','Sold at the van','Level cleared'}
local PLAY={'Joined','1 minute','3 minutes','5 minutes','10 minutes','15 minutes','20 minutes','30 minutes','45 minutes','60 minutes'}
local PLAY_AT={0,60,180,300,600,900,1200,1800,2700,3600}
local DEPTH={};for i=1,10 do DEPTH[i]='Level '..i end;DEPTH[11]='Cleared level 10'
local FEATURES={QuestLogOpen='Quest log',VanRewardsOpen='Rewards',VanShopOpen='Van shop'}
local tutorialEvent=RS:FindFirstChild('TutorialStepEvent')or Instance.new('RemoteEvent');tutorialEvent.Name='TutorialStepEvent';tutorialEvent.Parent=RS
local function step(p,s,name,list,index,session)
 local key=name..index..(session or'');if s.steps[key]then return end;s.steps[key]=true
 if Run:IsStudio()then studioTrace('step:'..name..':'..index);return end
 pcall(function()Analytics:LogFunnelStepEvent(p,name,session or s.session,index,list[index])end)
end
local function tutorialStep(p,s,id)local i=TUTORIAL_INDEX[id];if i then s.tutorialLast=id;step(p,s,'1 Tutorial',TUTORIAL,i)end end
local function runKey()local run=state and state:GetAttribute('QuestRunId');return type(run)=='string'and string.sub((string.gsub(run,'[^%w]','')),1,8)or nil end -- short key: funnel session ids are capped at 50 characters
local function loopStep(p,s,index)
 local run=runKey();local round=state and state:GetAttribute('Round')or 0
 if run and round>0 and p:GetAttribute('MissionActive')==true then step(p,s,'2 Level Loop',LOOP,index,run..'-L'..round..'-'..p.UserId)end
end
-- LevelResult: one per player per level, value = seconds in the level; F1 level, F2 outcome, F3 map kind.
local function levelResult(p,s,outcome)
 local open=s.level;if not open then return end;s.level=nil
  log(p,'LevelResult',math.floor(os.clock()-open.at),{[F1]=levelBucket(open.round),[F2]=outcome,[F3]=open.kind})
end
-- Progression path 'Run': one Start per level a player is in, then Complete (quota met) or Fail. Leaving mid-level logs nothing.
local function progression(p,s,status)
 local round=state and state:GetAttribute('Round')or 0
 if round<=0 or p:GetAttribute('MissionActive')~=true then return end
 if status=='Start'then if s.progressLevel==round then return end;s.progressLevel=round
 elseif s.progressLevel~=round then return else s.progressLevel=nil end
 s.deadReal=false -- a level boundary ends any death: the rebuild's RoundDead=false afterwards is not a revive
 local fields={[F1]=mapKind(),[F2]=#Players:GetPlayers()..' players'}
 if status=='Start'then
  if s.level and s.level.round~=round then levelResult(p,s,'Skipped')end
  s.level={round=round,at=os.clock(),kind=fields[F1]}
  local run=runKey()
  if run then step(p,s,'4 Run Depth',DEPTH,math.min(round,10),run..'-'..p.UserId)end
  loopStep(p,s,1)
 elseif status=='Complete'then
  levelResult(p,s,'Cleared')
  loopStep(p,s,9)
  local run=runKey()
  if round>=10 and run then step(p,s,'4 Run Depth',DEPTH,11,run..'-'..p.UserId)end
 else levelResult(p,s,state and state:GetAttribute('FailureReason')=='TimeExpired'and 'Failed: time'or 'Failed: wipe')end
 if Run:IsStudio()then studioTrace('prog:'..status..':'..round..':'..fields[F1]);return end
 pcall(function()
  if status=='Start'then Analytics:LogProgressionStartEvent(p,'Run',round,'Level '..round,fields)
  elseif status=='Complete'then Analytics:LogProgressionCompleteEvent(p,'Run',round,'Level '..round,fields)
  else Analytics:LogProgressionFailEvent(p,'Run',round,'Level '..round,fields)end
 end)
end
-- The session a teleport carried in, if any ({s=id,f=first,t=start os.time}).
local function carried(p)
 local ok,join=pcall(function()return p:GetJoinData()end)
 local data=ok and type(join)=='table'and join.TeleportData
 local all=type(data)=='table'and data.metrics
 local m=type(all)=='table'and all[tostring(p.UserId)]
 if type(m)=='table'and type(m.s)=='string'and #m.s<=64 and type(m.t)=='number'and os.time()-m.t<6*3600 then return m end
end
local function track(p)
 local carry=carried(p)
 local s={joined=os.clock(),deaths=0,retries=0,revives=0,aliveTotal=0,lastEvent='Joined',lastEventAt=os.clock(),diedSinceStart=false,funnel={},steps={},shopOpen=false,
  session=carry and carry.s or Http:GenerateGUID(false),start=carry and carry.t or os.time(),first=carry and carry.f==true or nil,carried=carry~=nil}
 S[p]=s
 p:SetAttribute('MetricsSession',s.session);p:SetAttribute('MetricsStart',s.start)
 funnel(p,s,1)
 if not s.carried then step(p,s,'3 Play Time',PLAY,1)end
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()if p:GetAttribute('MissionActive')==true then progression(p,s,'Start')end end)
 -- Shop chapter steps 1, 4 and 7 come from the saved chapter step (server truth); a save already at 3 logs nothing.
 p:GetAttributeChangedSignal('ShopTutorialStep'):Connect(function()
  local v=p:GetAttribute('ShopTutorialStep')
  if v==1 then tutorialStep(p,s,'shop1')
  elseif v==2 then tutorialStep(p,s,'shop4');funnel(p,s,12)
  elseif v==3 and s.shopOpen and(p:GetAttribute('UpgradeTier_Speed')or 0)>=1 then tutorialStep(p,s,'shop7');funnel(p,s,12)end
  s.shopOpen=v==1 or v==2
 end)
 p:GetAttributeChangedSignal('UpgradeTier_Speed'):Connect(function()if(p:GetAttribute('UpgradeTier_Speed')or 0)>0 then funnel(p,s,12)end end)
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()
  if p:GetAttribute('MissionActive')==true then
   s.lifeStart=os.clock()
   if s.diedSinceStart then s.retries+=1;event(s,'RetryAfterDeath');log(p,'RetryAfterDeath',s.retries,{[F1]=roundBucket()})
   else event(s,'MissionStart')end
   s.diedSinceStart=false
  else event(s,'MissionEnded')end
  settleAlive(s,p)
 end)
 -- Dead-air breakers (CursedItemsServer.DeadAirBreakers): logged, and the Quit cause shows 'DeadAir:<name>' instead of 'Nothing recent'.
 p:GetAttributeChangedSignal('DeadAirLast'):Connect(function()
  local v=p:GetAttribute('DeadAirLast');if type(v)~='string'then return end
  local name=string.match(v,'^(%a+)')or 'Unknown'
  event(s,'DeadAir:'..name);log(p,'DeadAirBreaker',1,{[F1]=roundBucket(),[F2]=name})
 end)
 p:GetAttributeChangedSignal('RoundDead'):Connect(function()
  if p:GetAttribute('MissionActive')~=true then settleAlive(s,p);return end
  if p:GetAttribute('RoundDead')==true then
   if LIVE[phase()]then
    s.deaths+=1;s.diedSinceStart=true;s.deadReal=true
    local life=s.lifeStart and os.clock()-s.lifeStart or 0
    local cause=deathCause(p)
    event(s,'Death:'..cause)
    log(p,'TimeAliveBeforeDeath',math.floor(life),{[F1]=roundBucket(),[F2]=cause,[F3]=phase()})
   end
  elseif s.deadReal then
   s.deadReal=false;s.lifeStart=os.clock()
   if LIVE[phase()]then s.revives+=1;event(s,'Revived');log(p,'Revive',1,{[F1]=roundBucket()})end
  end
  settleAlive(s,p)
 end)
end
local function onPhase()
 local ph=phase()
 if ph=='Failed'or ph=='Won'then for p,s in S do if p:GetAttribute('MissionActive')then event(s,'Round'..ph);progression(p,s,ph=='Won'and'Complete'or'Fail')end end end
 -- A failed level restarts or retries at the same Round, so Searching also opens the level (Start dedupes per level).
 if ph=='Searching'then for p,s in S do progression(p,s,'Start')end end
end
local function onRound()for p,s in S do progression(p,s,'Start')end end
local function bindState(obj)if obj.Name=='RecoveryRound'then state=obj;obj:GetAttributeChangedSignal('Phase'):Connect(onPhase);obj:GetAttributeChangedSignal('Round'):Connect(onRound);task.defer(onRound)end end -- catch up (bug hunt 2026-10-27): RecoveryRound can arrive with Round already set, after MissionActive, so level 1's Start was lost
if state then bindState(state)else RS.ChildAdded:Connect(function(c)if not state then bindState(c)end end)end
tutorialEvent.OnServerEvent:Connect(function(p,id)
 local s=S[p];if not s or type(id)~='string'or #id>32 then return end
 s.tutorialReports=(s.tutorialReports or 0)+1;if s.tutorialReports>80 then return end
 local feature=FEATURES[string.match(id,'^open:(%w+)$')or'']
 if feature then -- side menus (set client-side, so the client reports the first open per server)
  s.opened=s.opened or{};if not s.opened[feature]then s.opened[feature]=true;log(p,'FeatureOpened',1,{[F1]=feature,[F2]=roundBucket()})end
  return
 end
 if id=='skipped'then
  if not s.tutorialSkipped then s.tutorialSkipped=true;log(p,'TutorialSkipped',1,{[F1]=tostring(s.tutorialLast or 'none')})end
  return
 end
 if id=='shopSkipped'then
  if not s.shopSkipped then s.shopSkipped=true;log(p,'ShopTutorialSkipped',1,{[F1]=tostring(s.shopLast or 'none')})end
  return
 end
 if id=='introStart'then funnel(p,s,2)end
 -- 'nextItem' only brings the cart to the FIRST item (2026-10-25), so it is the push step.
 if id=='nextItem'then id='pushCart'end
 if string.sub(id,1,4)=='shop'then s.shopLast=id end
 tutorialStep(p,s,id)
end)
-- Items and the cart (CursedItemsServer sets HeldBy / CargoStored): per-player custom events plus funnel steps.
-- ItemPickedUp / ItemStored: F1 level, F2 item name (first pickup of each item only). CartGrabbed / CartDropped: F1 level.
local watched=nil
local function itemName(m)return(string.gsub(tostring(m:GetAttribute('DisplayName')or m:GetAttribute('ItemId')or m.Name),'[^%w %-]',''))end -- custom fields refuse quotes, commas and the like
local function watchModel(m)
 if m.Name=='RecoveryCart'then
  local holder
  m:GetAttributeChangedSignal('HeldBy'):Connect(function()
   local id=m:GetAttribute('HeldBy')
   local was=holder and Players:GetPlayerByUserId(holder)
   if was and S[was]and id~=holder then log(was,'CartDropped',1,{[F1]=roundBucket()})end
   local p=id and Players:GetPlayerByUserId(id)
   if p and S[p]and id~=holder then log(p,'CartGrabbed',1,{[F1]=roundBucket()});funnel(p,S[p],4);loopStep(p,S[p],2)end
   holder=id
  end)
  return
 end
 if not m:GetAttribute('ItemId')then return end
 local last
 m:GetAttributeChangedSignal('HeldBy'):Connect(function()
  local id=m:GetAttribute('HeldBy');local p=id and Players:GetPlayerByUserId(id)
  if p and S[p]then
   last=p
   if not m:GetAttribute('MetricsPicked')then m:SetAttribute('MetricsPicked',true);log(p,'ItemPickedUp',1,{[F1]=roundBucket(),[F2]=itemName(m)})end
   funnel(p,S[p],5);loopStep(p,S[p],3)
  end
 end)
 m:GetAttributeChangedSignal('CargoStored'):Connect(function()
  if m:GetAttribute('CargoStored')and last and S[last]then log(last,'ItemStored',1,{[F1]=roundBucket(),[F2]=itemName(m)})end
 end)
end
watchItems=function(items)
 if items==watched then return end;watched=items
 if not items then return end
 for _,m in items:GetChildren()do watchModel(m)end
 items.ChildAdded:Connect(watchModel)
end
Players.PlayerAdded:Connect(track)
for _,p in Players:GetPlayers()do track(p)end
task.spawn(function()
 while true do
  task.wait(1)
  local map=workspace:FindFirstChild('Mansion');local items=map and map:FindFirstChild('Interactive')
  local cart=items and items:FindFirstChild('RecoveryCart')
  watchItems(items)
  local stored=0;if items then for _,m in items:GetChildren()do if m:GetAttribute('CargoStored')then stored+=1 end end end
  for p,s in S do
   local played=os.time()-s.start
   for i=2,#PLAY do if played>=PLAY_AT[i]then step(p,s,'3 Play Time',PLAY,i)end end
   if p:GetAttribute('MissionActive')==true then
    funnel(p,s,3)
    if cart and cart:GetAttribute('HeldBy')==p.UserId then funnel(p,s,4);loopStep(p,s,2)end
    if state then
     local sold,value,quota=state:GetAttribute('Sold')or 0,state:GetAttribute('CartValue')or 0,state:GetAttribute('Quota')or math.huge
     if stored>=1 or sold>0 then funnel(p,s,6);loopStep(p,s,4)end
     if stored>=3 then loopStep(p,s,5)end
     if stored>=5 then funnel(p,s,7);loopStep(p,s,6)end
     if sold+value>=quota then loopStep(p,s,7)end
     if sold>0 then funnel(p,s,8);loopStep(p,s,8)end
     local round=state:GetAttribute('Round')or 0
     if state:GetAttribute('Phase')=='Won'and round==1 or round>=2 then funnel(p,s,9)end
     if round>=2 then funnel(p,s,10)end;if round>=3 then funnel(p,s,11)end
    end
   end
  end
 end
end)
Players.PlayerRemoving:Connect(function(p)
 local s=S[p];S[p]=nil;if not s then return end
 settleAlive(s,p);if s.aliveSince then s.aliveTotal+=os.clock()-s.aliveSince end
 local dead=p:GetAttribute('RoundDead')==true
 -- A lobby->mission launch, party hop or mission->lobby return is a server change, not a quit.
 local hop=p:GetAttribute('LeavingRun')==true or os.clock()-(p:GetAttribute('MetricsTeleportAt')or -1e9)<TELEPORT_WINDOW
 levelResult(p,s,p:GetAttribute('LeavingRun')==true and 'Left to lobby'or dead and 'Quit while dead'or 'Quit while alive')
 if hop then return end
 local session=os.clock()-s.joined
 local where=p:GetAttribute('MissionActive')~=true and 'Lobby/Menu'or dead and 'Dead/Spectating'or 'Alive in mission'
 local cause=os.clock()-s.lastEventAt<=LAST_EVENT_WINDOW and s.lastEvent or 'Nothing recent'
 local fields={[F1]=where,[F2]=roundBucket(),[F3]=cause}
 log(p,'Quit',math.floor(session),fields)
 log(p,'DeathsBeforeQuit',s.deaths,{[F1]=where,[F2]=bucketSeconds(session)})
 log(p,'TimeAliveBeforeQuit',math.floor(s.aliveTotal),{[F1]=where,[F2]=roundBucket()})
 log(p,'RetriesAfterDeath',s.retries,{[F1]=s.deaths>0 and 'Died at least once'or 'Never died'})
end)
