local C=require(game.ReplicatedStorage.LobbyShopCatalog)
local R=require(game.ReplicatedStorage.RewardsConfig)
local QuestCatalog=require(game.ReplicatedStorage.QuestCatalog)
local QuestEngine=require(script.Parent.QuestCore).new(QuestCatalog)
local M={}
-- Every equip slot; new slots default to '' so existing saves stay valid.
local SLOTS={'Title','Aura','Hat','Ring','Shirt','Shoes','Eyes','Back','Trail','Torch'}
local isSlot={};for _,s in SLOTS do isSlot[s]=true end
local function number(v)if type(v)~='number'or v~=v or v==math.huge or v==-math.huge then return 0 end;return math.clamp(math.floor(v),0,1000000000000)end
-- Run reward: base 25, doubled by the pass, then +10% each (rounded up) for Roblox Plus and for favoriting.
function M.RunTokens(op)
 local base=C.TokensPerRun*(op.doubleTokens and 2 or 1)
 local pct=op.plusBonus and .1 or 0 -- Roblox Plus perk only; no like/favorite reward
 if pct>0 then base+=math.ceil(base*pct)end
 return base
end
local reconcileKnown
reconcileKnown=function(old)
 if type(old)=='table'and type(old.version)=='number'and old.version>1 then return nil,'Save version is newer than this server.'end
 local d={version=1,Tokens=0,HighestLevel=0,FastestClearMs=0,TotalRetrieved=0,BestHaul=0,LevelsCleared=0,RunsCompleted=0,Owned={},Equipped={Title='',Aura='',Hat='',Ring='',Shirt='',Shoes='',Eyes='',Back='',Trail='',Torch=''},Settings={ShowHauntedTag=true},Receipts={},Upgrades={Speed=0,Stamina=0,Flashlight=0},ReviveTokens=0,PurchaseReceipts={},ReviveUses={},JumpscareCharges=0,JumpscareUses={},InstantWinCharges=0,InstantWinUses={},GiftClaims={},FlashlightColor=false,TutorialDone=false,AdminPasses={},CompGrants={},FavoriteBonus=false}
 if type(old)~='table'then return d end
 d.Settings.ShowHauntedTag=not (type(old.Settings)=='table' and old.Settings.ShowHauntedTag==false)
 d.TutorialDone=old.TutorialDone==true
 d.FavoriteBonus=old.FavoriteBonus==true
 if type(old.CompGrants)=='table'then for key,value in old.CompGrants do if type(key)=='string'and #key<=64 and value==true then d.CompGrants[key]=true end end end
 if type(old.AdminPasses)=='table'then for id,value in old.AdminPasses do
  local offer=C.RobuxById[id]
  if value==true and offer and offer.kind=='Pass'then d.AdminPasses[id]=true end
 end end
 for _,k in {'Tokens','HighestLevel','FastestClearMs','TotalRetrieved','BestHaul','LevelsCleared','RunsCompleted'}do d[k]=number(old[k])end
 d.ReviveTokens=number(old.ReviveTokens)
 d.JumpscareCharges=number(old.JumpscareCharges)
 d.InstantWinCharges=number(old.InstantWinCharges)
 if type(old.InstantWinUses)=='table'then for id,status in old.InstantWinUses do
  if type(id)=='string'and #id>0 and #id<=160 and(status=='consumed'or status=='refunded')then d.InstantWinUses[id]=status end
 end end
 if type(old.FlashlightColor)=='table'then
  local valid=true;local color={}
  for i,key in {'r','g','b'}do local v=old.FlashlightColor[key];if v==nil then v=old.FlashlightColor[i]end;if type(v)~='number'or v~=v or math.abs(v)==math.huge then valid=false;break end;color[key]=math.clamp(math.floor(v+.5),0,255)end
  if valid then d.FlashlightColor=color end
 end
 if type(old.GiftClaims)=='table'then for id,claim in old.GiftClaims do
  if type(id)=='string'and #id>0 and #id<=160 and type(claim)=='string'and #claim>0 and #claim<=100 then d.GiftClaims[id]=claim end
 end end
 if type(old.JumpscareUses)=='table'then for id,status in old.JumpscareUses do
  if type(id)=='string'and #id>0 and #id<=160 and(status=='consumed'or status=='refunded')then d.JumpscareUses[id]=status end
 end end
 if type(old.Upgrades)=='table'then for stat in d.Upgrades do d.Upgrades[stat]=math.clamp(number(old.Upgrades[stat]),0,#C.UpgradeCosts)end end
 for _,key in {'PurchaseReceipts','ReviveUses'}do if type(old[key])=='table'then for id,v in old[key]do if type(id)=='string'and #id<=160 and(v==true or v=='consumed'or v=='refunded'or v=='used')then d[key][id]=v end end end end
 if type(old.Owned)=='table'then for id,value in old.Owned do if type(id)=='string' and #id>0 and #id<=120 and not string.find(id,'%c') and value==true then d.Owned[id]=true end end end
 if type(old.Equipped)=='table'then for _,kind in SLOTS do local id=old.Equipped[kind];if C.ById[id]and C.ById[id].kind==kind and d.Owned[id]then d.Equipped[kind]=id end end end
 if type(old.Receipts)=='table'then for _,id in old.Receipts do if type(id)=='string'and #id<=160 then table.insert(d.Receipts,id);if #d.Receipts>=150 then break end end end end
 return d
end
local function applyKnown(old,op)
 local d,err=M.Reconcile(old);if not d then return nil,err end
 if op.kind=='clear'then
  if table.find(d.Receipts,op.id)then return d,'Already credited.'end
  table.insert(d.Receipts,op.id);if #d.Receipts>150 then table.remove(d.Receipts,1)end
  d.HighestLevel=math.max(d.HighestLevel,number(op.level));d.LevelsCleared+=1
  d.TotalRetrieved+=number(op.money);d.BestHaul=math.max(d.BestHaul,number(op.money))
  local ms=number(op.ms);if op.level==1 and ms>0 and(d.FastestClearMs==0 or ms<d.FastestClearMs)then d.FastestClearMs=ms end
  if op.completed then d.RunsCompleted+=1;d.Tokens+=M.RunTokens(op) end
  if op.questClear then
   local qc=op.questClear;local producer='clear:'..tostring(qc.userId)
   local seq=d.Quests and d.Quests.producers and d.Quests.producers[producer] and d.Quests.producers[producer].seq or 0
   local qop={kind='progress',userId=qc.userId,now=qc.now,selection=qc.selection,cosmeticPool=qc.cosmeticPool,eventConfig=qc.eventConfig,
    batch={id=op.id,createdAt=qc.now,producerId=producer,seq=seq+1,events=qc.events}}
   local qd,qr=QuestEngine.Apply(d,qop);if not qd then return nil,qr end;d=qd
  elseif op.quest then local qd,qr=QuestEngine.Apply(d,op.quest);if not qd then return nil,qr end;d=qd end
  return d,op.completed and ('Run cleared! +'..(M.RunTokens(op))..' tokens.')or 'Level recorded.'
 elseif op.kind=='purchase'then
  local offer=C.ById[op.offer];if not offer then return nil,'That offer does not exist.'end
  if offer.kind=='Upgrade'then
   local tier=d.Upgrades[offer.stat];local cost=C.UpgradeCosts[tier+1]
   if not cost then return nil,'This upgrade is already maxed.'end
   if d.Tokens<cost then return nil,'Not enough tokens.'end
   d.Tokens-=cost;d.Upgrades[offer.stat]=tier+1;return d,offer.name..' upgraded to tier '..(tier+1)..'.'
  end
  if not C.Purchasable[offer.id]then return nil,'This offer is no longer sold for tokens.'end
  if not offer.price then return nil,'This cosmetic requires its Roblox pass.'end
  if d.Owned[offer.id]then return nil,'You already own this offer.'end
  if d.Tokens<offer.price then return nil,'Not enough tokens. Complete runs to earn more.'end
  d.Tokens-=offer.price;d.Owned[offer.id]=true;return d,'Unlocked '..offer.name..'. Equip it in Appearance.'
 elseif op.kind=='equip'then
  if op.offer==''and op.slot=='VIP'then
   if d.Equipped.Title=='title_vip'then d.Equipped.Title=''end
   if d.Equipped.Aura=='aura_vip'then d.Equipped.Aura=''end
   return d,'VIP cosmetics removed.'
  end
  if op.offer==''and isSlot[op.slot]then d.Equipped[op.slot]='';return d,'Cosmetic removed.'end
  local offer=C.ById[op.offer];if not offer or not d.Owned[op.offer]then return nil,'Unlock this cosmetic first.'end
  -- Each appearance slot is selected independently.
  if not isSlot[offer.kind]then return nil,'This offer is not a cosmetic.'end
  d.Equipped[offer.kind]=offer.id;return d,'Equipped '..offer.name..'.'
 elseif op.kind=='favorite'then
  return d,'This bonus is no longer available.' -- like/favorite rewards removed (Roblox rules)
 elseif op.kind=='compensate'then
  -- One-time support grant keyed by campaign; the flag commits with the tokens.
  if type(op.key)~='string'or #op.key==0 or #op.key>64 or type(op.amount)~='number'or op.amount<1 or op.amount>10 then return nil,'Invalid compensation.'end
  if d.CompGrants[op.key]then return d,'Already compensated.'end
  d.CompGrants[op.key]=true;d.ReviveTokens+=math.floor(op.amount)
  return d,'Compensation revive tokens added.'
 elseif op.kind=='vanDaily'then
  if type(op.day)~='number'or op.day~=op.day or op.day%1~=0 or op.day<0 or op.day>100000000 then return nil,'Invalid reward day.'end
  if type(op.roll)~='number'or op.roll~=op.roll or op.roll%1~=0 or op.roll<1 or op.roll>10000 then return nil,'Invalid reward roll.'end
  local v=R.ProfileRewards(d)
  if v.lastDailyDay==op.day then return d,'Daily reward already claimed.'end
  if v.lastDailyDay>op.day then return nil,'Daily reward clock moved backwards.'end
  local streak=R.EffectiveStreak(d,op.day)
  local reward=R.Daily(streak,op.roll)
  v.lastDailyDay=op.day;v.streak=streak;v.lastDailyReward=reward
  d.VanRewards=v
  d.Tokens+=reward.tokens;d.ReviveTokens+=reward.revives;d.InstantWinCharges+=reward.instantWin
  return d,'Daily reward claimed.'
 elseif op.kind=='vanSessionOpen'then
  if type(op.sessionId)~='string'or #op.sessionId==0 or #op.sessionId>100 or type(op.owner)~='string'or #op.owner==0 or #op.owner>100 then return nil,'Invalid reward session owner.'end
  if type(op.now)~='number'or op.now~=op.now or op.now%1~=0 or op.now<1 or op.now>100000000000 then return nil,'Invalid session time.'end
  local v=R.ProfileRewards(d)
  local session=v.timedSession
  if type(op.openedAt)~='number'or op.openedAt~=op.openedAt or op.openedAt%1~=0 or op.openedAt<1 or op.openedAt>100000000000000 then return nil,'Invalid owner opening time.'end
  if session and session.owner==op.owner then return d,'Reward session already opened.'end
  if session and (op.openedAt<session.ownerOpenedAt or (op.openedAt==session.ownerOpenedAt and op.owner<=session.owner))then return nil,'Reward session ownership changed.'end
  if session and op.now<session.lastSeen then return nil,'Reward session clock moved backwards.'end
  if not session or op.now-session.lastSeen>900 then
   session={id=op.sessionId,startedAt=op.now,playedSeconds=0,claimed={},lastSeen=op.now,owner=op.owner,ownerOpenedAt=op.openedAt}
  else
   session.owner=op.owner;session.ownerOpenedAt=op.openedAt;session.lastSeen=op.now
  end
  v.timedSession=session;d.VanRewards=v
  return d,'Reward session opened.'
 elseif op.kind=='vanSessionCheckpoint'then
  local v=R.ProfileRewards(d);local session=v.timedSession
  if not session or session.owner~=op.owner then return nil,'Reward session ownership changed.'end
  if type(op.now)~='number'or op.now~=op.now or op.now%1~=0 or op.now<session.lastSeen or op.now>100000000000 then return nil,'Invalid session time.'end
  if type(op.playedSeconds)~='number'or op.playedSeconds~=op.playedSeconds or math.abs(op.playedSeconds)==math.huge or op.playedSeconds<0 then return nil,'Invalid session progress.'end
  session.playedSeconds=math.max(session.playedSeconds,math.min(math.floor(op.playedSeconds),R.MaxSeconds));session.lastSeen=op.now
  d.VanRewards=v;return d,'Reward session saved.'
 elseif op.kind=='vanTimed'then
  if type(op.sessionId)~='string'or #op.sessionId==0 or #op.sessionId>100 then return nil,'Invalid reward session.'end
  if type(op.sessionStartedAt)~='number'or op.sessionStartedAt~=op.sessionStartedAt or op.sessionStartedAt%1~=0 or op.sessionStartedAt<1 or op.sessionStartedAt>100000000000 then return nil,'Invalid session start.'end
  local reward,at=R.Timed(op.slotId)
  if not reward then return nil,'Unknown timed reward.'end
  if type(op.elapsedSeconds)~='number'or op.elapsedSeconds~=op.elapsedSeconds or math.abs(op.elapsedSeconds)==math.huge or op.elapsedSeconds<at then return nil,'Timed reward is not ready.'end
  local v=R.ProfileRewards(d)
  local active=v.timedSession
  if not active or active.owner~=op.owner or active.id~=op.sessionId or active.startedAt~=op.sessionStartedAt then return nil,'Reward session ownership changed.'end
  if type(op.now)~='number'or op.now~=op.now or op.now%1~=0 or op.now<active.lastSeen or op.now>100000000000 then return nil,'Invalid session time.'end
  active.playedSeconds=math.max(active.playedSeconds,math.min(math.floor(op.elapsedSeconds),R.MaxSeconds));active.lastSeen=op.now
  if active.claimed[op.slotId]then return d,'Timed reward already claimed.'end
  if op.sessionStartedAt<=v.timedFloor then return nil,'Reward session expired.'end
  local session=v.timedSessions[op.sessionId]
  if session and session.startedAt~=op.sessionStartedAt then return nil,'Reward session mismatch.'end
  if session and session.claimed[op.slotId]then return d,'Timed reward already claimed.'end
  if not session then
   session={startedAt=op.sessionStartedAt,claimed={}}
   v.timedSessions[op.sessionId]=session
   local sessions={}
   for id,item in v.timedSessions do table.insert(sessions,{id=id,startedAt=item.startedAt})end
   if #sessions>32 then
    table.sort(sessions,function(a,b)return a.startedAt<b.startedAt or (a.startedAt==b.startedAt and a.id<b.id)end)
    v.timedFloor=math.max(v.timedFloor,sessions[#sessions-32].startedAt)
    for id,item in v.timedSessions do if item.startedAt<=v.timedFloor then v.timedSessions[id]=nil end end
    if op.sessionStartedAt<=v.timedFloor then return nil,'Reward session expired.'end
   end
  end
  session.claimed[op.slotId]=true;active.claimed[op.slotId]=true;d.VanRewards=v
  d.Tokens+=reward.tokens;d.ReviveTokens+=reward.revives;d.InstantWinCharges+=reward.instantWin
  return d,'Timed reward claimed.'
 elseif op.kind=='receipt'then
  if type(op.id)~='string'or #op.id==0 or #op.id>160 then return nil,'Invalid receipt.'end
  if d.PurchaseReceipts[op.id]then return d,'Already granted.'end
  local offer=C.Products[op.productId]
  if not offer or offer.kind~='Product'then return nil,'Unknown product.'end
  local tokens=number(offer.grantTokens);local charges=number(offer.grantJumpscare);local wins=number(offer.grantInstantWin)
  local revives=offer.grantRevives and number(offer.grantRevives) or ((offer.giftRevive==true or offer.id=='revive_token') and 1 or 0)
  if tokens==0 and charges==0 and wins==0 and revives==0 then return nil,'Unsupported product grant.'end
  -- Receipt and every reward commit in the same UpdateAsync profile operation.
  d.PurchaseReceipts[op.id]=true;d.Tokens+=tokens;d.JumpscareCharges+=charges;d.InstantWinCharges+=wins;d.ReviveTokens+=revives
  if offer.giftRevive==true then d.GiftClaims[op.id]='pending'end
  return d,revives>1 and (revives..' revive tokens added.') or revives==1 and 'Revive token added.' or wins>0 and 'Instant Win charge added.' or tokens>0 and 'Tokens added.' or 'Jumpscare charge added.'
 elseif op.kind=='claimGift'then
  if type(op.id)~='string'or not d.PurchaseReceipts[op.id]or type(op.claim)~='string'or #op.claim==0 or #op.claim>100 then return nil,'Invalid gift claim.'end
  -- Store the winner's identity, then compare the committed result outside UpdateAsync.
  -- This reserves the attempt, not the token. A crash here leaves the purchased token saved.
  if d.GiftClaims[op.id]=='pending'then d.GiftClaims[op.id]=op.claim end
  return d,'Gift claim checked.'
 elseif op.kind=='consumeJumpscare'then
  if type(op.id)~='string'or #op.id==0 or #op.id>160 then return nil,'Invalid jumpscare operation.'end
  if d.JumpscareUses[op.id]then return nil,'Jumpscare already handled.'end
  if d.JumpscareCharges<1 then return nil,'No jumpscare charges remaining.'end
  d.JumpscareCharges-=1;d.JumpscareUses[op.id]='consumed';return d,'Jumpscare charge used.'
 elseif op.kind=='refundJumpscare'then
  if d.JumpscareUses[op.id]=='consumed'then d.JumpscareCharges+=1;d.JumpscareUses[op.id]='refunded'end
  return d,'Jumpscare charge restored.'
 elseif op.kind=='consumeInstantWin'then
  if type(op.id)~='string'or #op.id==0 or #op.id>160 then return nil,'Invalid Instant Win operation.'end
  if d.InstantWinUses[op.id]then return nil,'Instant Win already handled.'end
  if d.InstantWinCharges<1 then return nil,'No Instant Win charges remaining.'end
  d.InstantWinCharges-=1;d.InstantWinUses[op.id]='consumed';return d,'Instant Win charge used.'
 elseif op.kind=='refundInstantWin'then
  if d.InstantWinUses[op.id]=='consumed'then d.InstantWinCharges+=1;d.InstantWinUses[op.id]='refunded'end
  return d,'Instant Win charge restored.'
 elseif op.kind=='flashlightColor'then
  if type(op.color)~='table'then return nil,'Invalid flashlight color.'end
  local color={}
  for _,key in {'r','g','b'}do local v=op.color[key];if type(v)~='number'or v~=v or math.abs(v)==math.huge then return nil,'Invalid flashlight color.'end;color[key]=math.clamp(math.floor(v+.5),0,255)end
  d.FlashlightColor=color;return d,'Flashlight color saved.'
 elseif op.kind=='consumeRevive'then
  if d.ReviveUses[op.id]then return nil,'Revive already handled.'end
  if d.ReviveTokens<1 then return nil,'No revive tokens remaining.'end
  d.ReviveTokens-=1;d.ReviveUses[op.id]='consumed';return d,'Revive token used.'
 elseif op.kind=='confirmRevive'then
  if d.ReviveUses[op.id]=='consumed'then d.ReviveUses[op.id]='used'end
  return d,'Revive confirmed.'
 elseif op.kind=='recoverRevives'then
  for id,status in d.ReviveUses do if status=='consumed'then d.ReviveTokens+=1;d.ReviveUses[id]='refunded'end end
  return d,'Interrupted revives restored.'
 elseif op.kind=='refundRevive'then
  if d.ReviveUses[op.id]=='consumed'then d.ReviveTokens+=1;d.ReviveUses[op.id]='refunded'end
  return d,'Revive token restored.'
 elseif op.kind=='grant'then
  -- Robux passes unlock cosmetics; Appearance alone chooses equipment.
  local names={}
  for _,id in op.ids or {}do
   local offer=C.ById[id]
   if offer and isSlot[offer.kind]and not d.Owned[id]then
    d.Owned[id]=true;table.insert(names,offer.name)
    
   end
  end
  return d,#names>0 and('Unlocked '..table.concat(names,', ')..'.')or 'Already unlocked.'
 elseif op.kind=='adminPass'then
  local offer=C.RobuxById[op.offer]
  if not offer or offer.kind~='Pass'then return nil,'Unknown game pass.'end
  d.AdminPasses[offer.id]=true
  local ids=offer.id=='vip'and {'title_vip','aura_vip'}or offer.grants and {offer.grants}or {}
  for _,id in ids do local cosmetic=C.ById[id]
   if cosmetic and not d.Owned[id]then
    d.Owned[id]=true
    
   end
  end
  return d,offer.name..' access granted.'
 elseif op.kind=='tutorial'then
  d.TutorialDone=true;return d,'Tutorial complete.'
 elseif op.kind=='vip'then
  d.Owned.title_vip=true;d.Owned.aura_vip=true
  
  return d,'Haunted VIP unlocked.'
 end
 return nil,'Unknown progress operation.'
end
local function setAuras(d)
 for _,set in QuestCatalog.MapSets do
  if d.Owned['hat_'..set] and d.Owned['ring_'..set] and d.Owned['tat_'..set] and d.Owned['shoe_'..set] then d.Owned['aura_set_'..set]=true end
 end
end
function M.Apply(old,op)
 if type(op)~='table' then return nil,'Invalid progress operation.' end
 local mapping={questInit='init',questProgress='progress',questClaim='claim',questClaimAll='claimAll',questReroll='reroll',questPin='pin',questEventPurchase='eventPurchase',questAdminRewards='adminRewards'}
 local d,result
 if mapping[op.kind] then
  local reconciled,err=M.Reconcile(old);if not reconciled then return nil,err end
  local qop={};for key,value in op.quest or op do qop[key]=value end;qop.kind=mapping[op.kind]
  d,result=QuestEngine.Apply(reconciled,qop)
 elseif op.kind=='showHauntedTag' then
  d,result=M.Reconcile(old);if not d then return nil,result end
  if type(op.show)~='boolean' then return nil,'Invalid tag setting.' end
  if not d.Owned.Tag_Haunted then return nil,'Unlock Haunted Mastery first.' end
  d.Settings.ShowHauntedTag=op.show;result='Tag visibility saved.'
 else
  d,result=applyKnown(old,op)
  if d and op.quest and op.kind~='clear' then
   local qd,qr=QuestEngine.Apply(d,op.quest)
   if not qd then return nil,qr end
   d=qd
  end
 end
 if d then setAuras(d) end
 return d,result
end
M.QuestEngine=QuestEngine
M.Slots=SLOTS
-- Forward compatibility: keep top-level fields this version doesn't know about (written by newer
-- servers during a rolling update) instead of silently dropping them on the next write.
function M.Reconcile(old)
 local d,err=reconcileKnown(old)
 if d and type(old)=='table'then for key,value in old do if type(key)=='string'and d[key]==nil then d[key]=value end end end
 if d and d.Quests~=nil then local q,qe=QuestEngine.Reconcile(d.Quests);if not q then return nil,qe end;d.Quests=q end
 return d,err
end
return M

