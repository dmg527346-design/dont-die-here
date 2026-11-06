-- Pure reducer: no Roblox services, clock, randomness, writes or listeners.
-- Usage: local Engine = require(QuestCore).new(require(QuestCatalog))
-- Init(profile,userId,now,selection?) -> clonedProfile,result; State(profile,now) -> display snapshot.
-- Apply(profile,op) -> clonedProfile,result OR nil,reason. Caller commits this entire profile
-- through the existing ProgressCore transaction. Never commit result separately from balances.
-- op.kind: progress/claim/claimAll/reroll/pin; userId and now are server-owned.
-- Mutators except progress require requestId. claim uses claimKey; claimAll uses frozen keys.
-- Optional batch on any mutator is applied atomically before eligibility is checked.
-- batch={id,createdAt,producerId,seq,events={{hook,eventId,at,amount,ctx}}}.
-- IDs/timestamps/sequence, selection capabilities and cosmeticPool MUST be server constructed.
-- CosmeticPool entries: {id,kind,tokenPurchasable=true,premium=false,retired=false}.
-- Durable producer high-water marks never evict: at 64 producers fail closed, requiring a
-- stable per-player producer identity and monotonic durable sequence. Service must not use JobId.
-- Historical marks remain; the new producer budget is not consumed each server session.
-- Event receipts retain 2,048 identities. Pruning raises an event-time rejection floor;
-- expired events fail closed, so an evicted event cannot be repackaged into a new batch.
-- The server must qualify saved-run item/clear GUIDs before batching; this reducer's bounded
-- recent event ledger is not a replacement for the run owner's permanent receipt rules.
-- Archives settle earned rewards at rollover and accept late events for retained periods.
-- They are capped at Catalog.MaxArchivedPeriods; older events/claims fail closed.
local Module = {}

local function finite(v)
 return type(v)=='number' and v==v and math.abs(v)~=math.huge
end
local function integer(v,min,max)
 return finite(v) and v%1==0 and v>=min and v<=max
end
local function identifier(v,max)
 return type(v)=='string' and #v>0 and #v<=(max or 120) and not string.find(v,'%c')
end
local function copy(value,stack,budget,depth)
 depth=depth or 0;budget=budget or {n=0};stack=stack or {}
 budget.n+=1
 assert(depth<=24 and budget.n<=60000,'Profile exceeds bounded clone budget.')
 local t=type(value)
 if t=='number' then assert(finite(value),'Profile contains a non-finite number.');return value end
 if t=='nil' or t=='string' or t=='boolean' then return value end
 assert(t=='table' and not stack[value],'Profile contains unsupported or cyclic data.')
 stack[value]=true;local out={}
 for key,item in value do
  assert(type(key)=='string' or integer(key,1,1000000000),'Profile contains invalid table keys.')
  out[key]=copy(item,stack,budget,depth+1)
 end
 stack[value]=nil;return out
end
local function clone(value)
 local ok,result=pcall(copy,value)
 if not ok then return nil,tostring(result) end
 return result
end
local function sumReward(a,b)
 a.tokens+=(b.tokens or 0);a.revives+=(b.revives or 0);a.candyCorn=(a.candyCorn or 0)+(b.candyCorn or 0)
 for _,id in b.cosmeticIds or {} do table.insert(a.cosmeticIds,id) end
 for _,id in b.tagIds or {} do table.insert(a.tagIds,id);if id=='Tag_Haunted' then a.tag='[Haunted]' end end
 return a
end
local function emptyReward()
 return {tokens=0,revives=0,candyCorn=0,cosmeticIds={},tagIds={}}
end
local function reward(def)
 local r=def or {};local out=emptyReward()
 out.tokens=integer(r.tokens or 0,0,1000000) and (r.tokens or 0) or 0
 out.revives=integer(r.revives or 0,0,100) and (r.revives or 0) or 0
 out.candyCorn=integer(r.candyCorn or 0,0,1000000) and (r.candyCorn or 0) or 0
 for _,id in r.cosmeticIds or {} do assert(identifier(id),'Invalid reward cosmetic.');table.insert(out.cosmeticIds,id) end
 for _,id in r.tagIds or {} do assert(identifier(id),'Invalid reward tag.');table.insert(out.tagIds,id) end
 return out
end
local function hash(text)
 local n=17
 for i=1,#text do n=(n*131+string.byte(text,i))%2147483647 end
 return n
end
local function sortedKeys(t)
 local keys={};for key in t do table.insert(keys,key) end;table.sort(keys);return keys
end
local function length(t)
 local n=0;for _ in t do n+=1 end;return n
end
local function canonical(v)
 local t=type(v)
 if t=='nil' then return 'z' end
 if t=='number' then return 'n'..tostring(v)..';' end
 if t=='boolean' then return v and 'b1' or 'b0' end
 if t=='string' then return 's'..#v..':'..v end
 local keys={};for key in v do table.insert(keys,key) end
 table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b) end)
 local pieces={'{'}
 for _,key in keys do table.insert(pieces,canonical(key));table.insert(pieces,canonical(v[key])) end
 table.insert(pieces,'}');return table.concat(pieces)
end
local function batchFingerprint(batch)
 local encoded=canonical(batch)
 return #encoded..':'..hash(encoded)..':'..hash(string.reverse(encoded))
end

function Module.new(Catalog)
 assert(type(Catalog)=='table' and type(Catalog.Daily)=='table' and type(Catalog.Weekly)=='table','Invalid quest catalog.')
 local E={};local DAY=Catalog.ResetSeconds or 86400;local WEEK=Catalog.WeekSeconds or 604800
 local OFFSET=Catalog.MondayOffsetSeconds or 259200
 local MAX_ARCHIVE=math.clamp(Catalog.MaxArchivedPeriods or 32,1,32)
 local MAX_DISTINCT=math.clamp(Catalog.MaxDistinct or 64,1,128)
 local VERSION=Catalog.Version or 1
 local byId,achById,eligibleItems,eligibleMaps={},{},{},{}
 for _,id in Catalog.ScholarEligibleIds or {} do eligibleItems[id]=true end
 for _,id in Catalog.MapKinds or {} do eligibleMaps[id]=true end
 for _,list in {Catalog.Daily,Catalog.Weekly} do for _,def in list do
  assert(identifier(def.id) and not byId[def.id],'Duplicate quest id.')
  byId[def.id]=def
  if def.alternative then byId[def.alternative.id]=def.alternative end
 end end
 for _,def in Catalog.Achievements or {} do
  assert(identifier(def.id) and #def.targets==5 and #def.rewards==5,'Achievements require five tiers.')
  achById[def.id]=def
 end
 local masteryDefs={}
 for _,def in Catalog.Masteries or {} do
  assert(identifier(def.id) and type(def.targets)=='table' and #def.targets>=1 and #def.targets<=20 and identifier(def.event,60),'Invalid mastery.')
  table.insert(masteryDefs,def)
 end
 local BOOST=math.clamp(Catalog.MasteryDailyBoost or 0,0,100)
 local function periods(now)
  return math.floor(now/DAY),math.floor((now+OFFSET)/WEEK)
 end
 local function validateTime(now)
  return integer(now,0,100000000000)
 end
 local function validUser(userId)
  return integer(userId,-1000000,9007199254740991)
 end
 local function feasible(def,selection)
  local filters=def.filters or {};local size=selection.partySize or 1
  if (filters.minPartySize or 1)>size then return false end
  if filters.maxPartySize and size>filters.maxPartySize then return false end
  if def.capability and not (selection.capabilities or {})[def.capability] then return false end
  if filters.mapKind then
   local maps=selection.mapKinds or {}
   if not maps[filters.mapKind] and not table.find(maps,filters.mapKind) then return false end
  end
  return true
 end
 local function candidates(list,selection,difficulty)
  local out={};local seen={}
  for _,original in list do
   local def=original
   if not feasible(def,selection) and def.alternative then def=def.alternative end
   if (not difficulty or original.difficulty==difficulty) and feasible(def,selection) and not seen[def.id] then
    seen[def.id]=true;table.insert(out,def)
   end
  end
  table.sort(out,function(a,b)return a.id<b.id end);return out
 end
 local function pick(pool,seed)
  assert(#pool>0,'Catalog lacks feasible quest candidates.')
  return pool[seed%#pool+1]
 end
 local function definitionKey(tab,period,id,generation)
  return tab..':'..tostring(period)..':'..id..':v'..VERSION..':g'..generation
 end
 local function freezeDefinition(def)
  local frozen=copy(def)
  if frozen.mode=='distinct' then
   frozen.maxDistinct=MAX_DISTINCT
   if (frozen.metric=='mapKind' or frozen.metric=='map') and not frozen.eligibleIds then frozen.eligibleIds=copy(Catalog.MapKinds or {}) end
  end
  return frozen
 end
 local function entry(def,tab,period,generation)
  return {id=def.id,claimKey=definitionKey(tab,period,def.id,generation or 0),generation=generation or 0,
   progress=0,distinct={},claimed=false,settled=false,settledReward=nil,definition=freezeDefinition(def)}
 end
 local function makePeriod(tab,period,q)
  local out={period=period,version=VERSION,entries={},rerolled=false,bonusClaimed=false,chestClaimed=false,
   bonusDefinition=copy(tab=='daily' and Catalog.DailyBonus or Catalog.WeeklyChest)}
  if tab=='daily' then
   -- Dailies remain solo-feasible even when rolled while temporarily in a party.
   local soloSelection=copy(q.selection);soloSelection.partySize=1
   for _,difficulty in {'easy','medium','hard'} do
    local pool=candidates(Catalog.Daily,soloSelection,difficulty)
    local def=pick(pool,hash(q.userId..':'..period..':'..difficulty..':'..VERSION))
    table.insert(out.entries,entry(def,tab,period,0))
   end
  else
   local all=candidates(Catalog.Weekly,q.selection);local solo={}
   for _,def in all do
    if not (def.filters or {}).minPartySize or def.filters.minPartySize<=1 then table.insert(solo,def) end
   end
   assert(#solo>=4 and #all>=5,'Catalog needs at least four feasible solo weekly quests and five total.')
   local chosen={}
   local function take(pool,index)
    local available={};for _,def in pool do if not chosen[def.id] then table.insert(available,def) end end
    if #available==0 then return false end
    local def=pick(available,hash(q.userId..':'..period..':weekly:'..index..':'..VERSION))
    chosen[def.id]=true;table.insert(out.entries,entry(def,tab,period,0));return true
   end
   for i=1,4 do take(solo,i) end
   take(all,5)
  end
  return out
 end
 local function grant(profile,r)
  profile.Tokens=(profile.Tokens or 0)+r.tokens
  profile.ReviveTokens=(profile.ReviveTokens or 0)+r.revives
  assert(integer(profile.Tokens,0,9007199254740991) and integer(profile.ReviveTokens,0,9007199254740991),'Reward balance overflow.')
  profile.Owned=profile.Owned or {};profile.Settings=profile.Settings or {}
  for _,id in r.cosmeticIds do profile.Owned[id]=true end
  for _,id in r.tagIds do
   profile.Owned[id]=true
   if id=='Tag_Haunted' then profile.Settings.ShowHauntedTag=true end
  end
 end
 local function itemReward(q,item)
  local r=reward(item.definition.reward)
  if item.definition.firstReward and not q.firstClaims[item.id] then sumReward(r,reward(item.definition.firstReward));q.firstClaims[item.id]=true end
  return r
 end
 local function chestReward(profile,op,key,definition)
  definition=definition or Catalog.WeeklyChest
  local r=reward(definition.reward);local pool=op.cosmeticPool
  key=tostring(op.userId)..':'..key
  assert(type(pool)=='table','Weekly chest requires the trusted current token cosmetic pool.')
  local ids,seen={},{}
  if type(pool)=='table' then
   assert(#pool<=256,'Cosmetic pool is too large.')
   for _,item in pool do
    assert(type(item)=='table' and identifier(item.id) and type(item.kind)=='string','Invalid cosmetic pool entry.')
    assert(item.tokenPurchasable==true and item.premium~=true and item.retired~=true,'Cosmetic pool includes an ineligible offer.')
    assert(table.find({'Hat','Ring','Shirt','Shoes','Title','Aura','Eyes','Back','Trail','Torch'},item.kind),'Cosmetic pool contains a non-cosmetic.')
    if not seen[item.id] and not (profile.Owned or {})[item.id] then seen[item.id]=true;table.insert(ids,item.id) end
   end
  end
  table.sort(ids)
  local exclusive={}
  for _,id in definition.exclusiveIds or {} do if not (profile.Owned or {})[id] then table.insert(exclusive,id) end end
  table.sort(exclusive)
  if #exclusive>0 and hash(key..':exclusive')%100<(definition.exclusiveChance or 0) then table.insert(r.cosmeticIds,exclusive[hash(key..':choice')%#exclusive+1])
  elseif #ids>0 then table.insert(r.cosmeticIds,ids[hash(key)%#ids+1])
  else r.tokens+=(definition.fallbackTokens or 150) end
  return r
 end
 local function completeCount(period)
  local n=0
  for _,item in period.entries do local def=item.definition;if def and item.progress>=def.target then n+=1 end end
  return n
 end
 local function settle(profile,tab,period,op,total)
  total._settledKeys=total._settledKeys or {}
  for _,item in period.entries do
   local def=item.definition
   if def and item.progress>=def.target and not item.claimed then
    local r=itemReward(profile.Quests,item);grant(profile,r);sumReward(total,r)
    item.claimed=true;item.settled=true;item.settledReward=r
    total._settledKeys[item.claimKey]=true
   end
  end
  local count=completeCount(period)
  local bonus=period.bonusDefinition
  if tab=='daily' and count>=bonus.target and not period.bonusClaimed then
   local r=reward(bonus.reward);grant(profile,r);sumReward(total,r)
   period.bonusClaimed=true;period.bonusSettledReward=r
   total._settledKeys[tab..':'..period.period..':'..bonus.id..':v'..period.version..':g0']=true
  elseif tab=='weekly' and count>=bonus.target and not period.chestClaimed then
   local key=tab..':'..period.period..':'..bonus.id..':v'..period.version..':g0'
   local r=chestReward(profile,op,key,bonus);grant(profile,r);sumReward(total,r)
   period.chestClaimed=true;period.chestSettledReward=r
   total._settledKeys[key]=true
  end
 end
 local function newQuest(profile,userId,now,selection)
  selection=selection or {}
  local q={v=1,catalogVersion=VERSION,userId=userId,selection={partySize=selection.partySize or 1,mapKinds=copy(selection.mapKinds or {}),capabilities=copy(selection.capabilities or {})},
   daily=nil,weekly=nil,archives={daily={},weekly={}},archiveFloors={daily=-math.huge,weekly=-math.huge},
   achievements={},seen={items={},maps={}},producers={},batches={},batchOrder={},eventReceipts={},eventFloor=-1,requests={},requestOrder={},rev=0,lastNow=now,masteryClaimed=false,firstClaims={},
   masteryDefinition=copy(Catalog.Mastery)}
  -- Floors use serializable integers, never infinities.
  q.archiveFloors={daily=-1000000000,weekly=-1000000000}
  for _,def in Catalog.Achievements or {} do
   local count=0
   if def.id=='survivor' then count=profile.LevelsCleared or 0
   elseif def.id=='deep_diver' or def.id=='deep' then count=profile.HighestLevel or 0
   elseif def.id=='tycoon' then count=profile.TotalRetrieved or 0 end
   if not integer(count,0,100000000000) then count=0 end
   q.achievements[def.id]={count=count,tier=0,distinct={},definition=freezeDefinition(def),version=VERSION}
  end
  q.masteryDefinition.chainIds=sortedKeys(q.achievements)
  local day,week=periods(now);q.daily=makePeriod('daily',day,q);q.weekly=makePeriod('weekly',week,q)
  return q
 end
 -- Collection membership is additive; saved progress, targets, rewards and claims remain owned by the frozen definition.
 local function migrateScholar(q)
  local scholar=q.achievements and q.achievements.curse_scholar
  local def=scholar and scholar.definition
  if type(def)~='table' then return end
  -- Preserve the existing retired-Balloon migration without discarding historical picks.
  if type(def.targets)=='table' and def.targets[5]==77 then
   def.targets[5]=76
   local at=type(def.eligibleIds)=='table' and table.find(def.eligibleIds,'Balloon');if at then table.remove(def.eligibleIds,at)end
  end
  local collectionVersion=Catalog.ScholarCollectionVersion or 1
  if type(def.eligibleIds)~='table' or (def.collectionVersion or 1)>=collectionVersion then return end
  local present={};for _,id in def.eligibleIds do present[id]=true end
  for _,id in Catalog.ScholarEligibleIds or {} do
   if not present[id] then table.insert(def.eligibleIds,id);present[id]=true end
  end
  def.maxDistinct=math.max(def.maxDistinct or MAX_DISTINCT,math.min(#def.eligibleIds,MAX_DISTINCT))
  def.collectionVersion=collectionVersion
 end
 -- The map pool shrank to five types (owner 2026-10-27): a saved Explore Different Maps ladder keeps its progress and
 -- claims; any tier target above the catalog's is lowered to it so every tier stays reachable.
 local function migrateTraveler(q)
  local traveler=q.achievements and q.achievements.world_traveler
  local def=traveler and traveler.definition
  local current=achById.world_traveler
  if type(def)~='table' or type(def.targets)~='table' or not current then return end
  for i,target in current.targets do if type(def.targets[i])=='number' and def.targets[i]>target then def.targets[i]=target end end
 end
 local function setup(profile,userId,now,selection,op,total)
  assert(validUser(userId) and validateTime(now),'Invalid server user/time.')
  assert(integer(profile.Tokens or 0,0,9007199254740991) and integer(profile.ReviveTokens or 0,0,9007199254740991),'Invalid profile balances.')
  local q=profile.Quests
  if q==nil then q=newQuest(profile,userId,now,selection);profile.Quests=q end
  assert(type(q)=='table' and q.v==1 and q.userId==userId,'Unsupported quest profile or user mismatch.')
  assert(integer(q.rev or 0,0,9007199254740991),'Invalid quest revision.')
  assert(now>=(q.lastNow or 0),'Quest clock moved backwards.')
  q.archives=q.archives or {daily={},weekly={}};q.archiveFloors=q.archiveFloors or {daily=-1000000000,weekly=-1000000000}
  q.firstClaims=q.firstClaims or {}
  q.requests=q.requests or {};q.requestOrder=q.requestOrder or {};q.batches=q.batches or {};q.batchOrder=q.batchOrder or {};q.producers=q.producers or {}
  q.eventReceipts=q.eventReceipts or {};q.eventFloor=q.eventFloor or -1
  q.seen=q.seen or {items={},maps={}};q.achievements=q.achievements or {};q.selection=q.selection or {partySize=1,mapKinds={},capabilities={}}
  migrateScholar(q);migrateTraveler(q)
  q.masteries=q.masteries or {};q.masteryBoost=q.masteryBoost or {day=-1,used=0}
  for _,def in masteryDefs do if type(q.masteries[def.id])~='table' then q.masteries[def.id]={count=0,level=0} end end
  local day,week=periods(now)
  if selection and (q.daily.period~=day or q.weekly.period~=week) then
   q.selection={partySize=selection.partySize or 1,mapKinds=copy(selection.mapKinds or {}),capabilities=copy(selection.capabilities or {})}
  end
  for _,pair in {{'daily',day},{'weekly',week}} do
   local tab,current=pair[1],pair[2];local period=q[tab]
   if not period or period.period~=current then
    if period then
     assert(period.period<current,'Quest period moved backwards.')
     settle(profile,tab,period,op,total)
     q.archives[tab][tostring(period.period)]=period
    end
    q[tab]=makePeriod(tab,current,q)
    local keys=sortedKeys(q.archives[tab]);table.sort(keys,function(a,b)return tonumber(a)<tonumber(b) end)
    while #keys>MAX_ARCHIVE do
     local key=table.remove(keys,1);q.archiveFloors[tab]=math.max(q.archiveFloors[tab],assert(tonumber(key)));q.archives[tab][key]=nil
    end
   end
  end
  local used={};for _,item in q.weekly.entries do if item.id~='w_boat' then used[item.id]=true end end
  for index,item in q.weekly.entries do
   if item.id=='w_boat' then
    local selectionNow=copy(q.selection);selectionNow.partySize=1
    local pool=candidates(Catalog.Weekly,selectionNow);local replacements={}
    for _,def in pool do if not used[def.id] then table.insert(replacements,def) end end
    local def=pick(replacements,hash(q.userId..':'..q.weekly.period..':retired_boat'))
    local replacement=entry(def,'weekly',q.weekly.period,1)
    replacement.claimKey='weekly:'..q.weekly.period..':'..def.id..':v'..q.weekly.version..':g1'
    if item.claimed or item.progress>=item.definition.target then
     -- Retiring a completed goal keeps its earned reward and chest contribution.
     replacement.progress=replacement.definition.target
     replacement.claimed=item.claimed==true;replacement.settled=item.settled==true
     replacement.settledReward=item.settledReward and copy(item.settledReward) or nil
     replacement.definition.reward=copy(item.definition.reward)
     replacement.definition.firstReward=nil
    end
    q.weekly.entries[index]=replacement;used[def.id]=true
    if q.pinned=='w_boat' then q.pinned=nil end
   end
  end
  for _,tab in {'daily','weekly'} do
   for _,item in q[tab].entries do
    local receipt=(q.adminQuestEntries or {})[tab..':'..item.id]
    if receipt and receipt.claimed and receipt.period==q[tab].period then item.progress=item.definition.target;item.claimed=true end
   end
  end
  q.lastNow=now;return q
 end
 local function eventEnabled(config,now)
  local h=config and config.Halloween
  return type(h)=='table' and h.Enabled==true and integer(h.StartsAt,0,100000000000) and integer(h.EndsAt,1,100000000000) and now>=h.StartsAt and now<h.EndsAt
 end
 local function setupEvent(q,op)
  if not eventEnabled(op.eventConfig,op.now) then return end
  local h=op.eventConfig.Halloween;local id=h.Id or Catalog.Event.id
  assert(identifier(id),'Invalid event identity.')
  q.events=q.events or {}
  if not q.events[id] then
   local entries={};for _,def in Catalog.Event.quests do local d=copy(def);d.metric='count';d.mode='count';table.insert(entries,{id=d.id,claimKey='event:'..id..':'..d.id,definition=d,progress=0,distinct={},claimed=false}) end
   q.events[id]={id=id,startsAt=h.StartsAt,endsAt=h.EndsAt,entries=entries,candyCorn=0,receipts={},finaleClaimed=false,shop=copy(Catalog.Event.shop),finale=copy(Catalog.Event.finale)}
  end
  q.activeEvent=id
 end
 local function eventFilters(def,ctx)
  local f=def.filters or {}
  if f.eventOnly and ctx.eventEligible~=true then return false end
  if f.minPartySize and (ctx.partySize or 1)<f.minPartySize then return false end
  if f.maxPartySize and (ctx.partySize or 1)>f.maxPartySize then return false end
  if f.mapKind and ctx.mapKind~=f.mapKind then return false end
  if f.noDeath and ctx.noDeath~=true then return false end
  if f.noPartyDeath and ctx.noPartyDeath~=true then return false end
  if f.minTimeLeft and (ctx.timeLeft or -1)<f.minTimeLeft then return false end
  return true
 end
 local function advance(item,def,event)
  if def.event~=event.hook or not eventFilters(def,event.ctx) then return end
  local metric=def.metric or 'count';local value=event.amount
  if metric=='value' then value=event.ctx.value or event.amount
  elseif metric=='level' then value=event.ctx.level or event.amount
  elseif metric=='itemId' then value=event.ctx.itemId
  elseif metric=='mapKind' or metric=='map' then value=event.ctx.mapKind end
  local limit=def.target or def.targets[#def.targets]
  if def.mode=='distinct' then
   if not identifier(value,120) then return end
   if def.eligibleIds and not table.find(def.eligibleIds,value) then return end
   if not item.distinct[value] and length(item.distinct)<(def.maxDistinct or MAX_DISTINCT) then item.distinct[value]=true end
   item.progress=math.min(limit,length(item.distinct))
  elseif def.mode=='max' then
   assert(integer(value,0,1000000000),'Invalid event metric.')
   item.progress=math.min(limit,math.max(item.progress or 0,value))
  else
   assert(integer(value,0,1000000000),'Invalid event metric.')
   item.progress=math.min(limit,(item.progress or 0)+value)
  end
 end
 local function findPeriod(q,tab,period)
  if q[tab].period==period then return q[tab] end
  assert(period<q[tab].period and period>q.archiveFloors[tab],'Event period is expired or future.')
  local archived=q.archives[tab][tostring(period)]
  if not archived then archived=makePeriod(tab,period,q);q.archives[tab][tostring(period)]=archived end
  assert(length(q.archives[tab])<=MAX_ARCHIVE,'Archived period budget exceeded.')
  return archived
 end
 -- Masteries: points from qualifying events (doubled while today's boost lasts); every level reached grants on the spot.
 local function advanceMasteries(profile,q,event,total)
  if not q.masteries or event.amount<=0 then return end
  for _,def in masteryDefs do
   local rec=q.masteries[def.id];local max=#def.targets
   if rec and def.event==event.hook and rec.level<max and (def.creatureKind==nil or event.ctx.creatureKind==def.creatureKind)
    and (def.kind~='collection' or eligibleItems[event.ctx.itemId or '']) then
    local points=event.amount;local day=math.floor(event.at/DAY);local boost=q.masteryBoost
    if day>boost.day then boost.day=day;boost.used=0 end
    if day==boost.day and boost.used<BOOST then local extra=math.min(points,BOOST-boost.used);boost.used+=extra;points+=extra end
    rec.count=math.min(def.targets[max],rec.count+points)
    while rec.level<max and rec.count>=def.targets[rec.level+1] do
     rec.level+=1
     local r=reward(Catalog.MasteryLevelReward);if rec.level==max then sumReward(r,reward(Catalog.MasteryCompleteReward)) end
     grant(profile,r);sumReward(total,r);q.masteryLast={id=def.id,level=rec.level,at=event.at}
    end
   end
  end
  local grand=Catalog.GrandMastery
  if grand and #masteryDefs>0 and not q.grandMastery then
   for _,def in masteryDefs do local rec=q.masteries[def.id];if not rec or rec.level<#def.targets then return end end
   local r=reward(grand.reward);grant(profile,r);sumReward(total,r);q.grandMastery=true
  end
 end
 local function applyBatch(profile,q,batch,op,total)
  if batch==nil then return end
  assert(type(batch)=='table' and identifier(batch.id,120) and identifier(batch.producerId,100),'Invalid progress batch identity.')
  assert(validateTime(batch.createdAt) and batch.createdAt<=op.now and integer(batch.seq,1,9007199254740991),'Invalid progress batch timestamp/sequence.')
  assert(type(batch.events)=='table' and #batch.events<=128,'Invalid progress batch size.')
  if q.batches[batch.id] then
   local old=q.batches[batch.id]
   assert(old.producerId==batch.producerId and old.seq==batch.seq and old.createdAt==batch.createdAt and old.fingerprint==batchFingerprint(batch),'Batch identity was reused.')
   return
  end
  local producer=q.producers[batch.producerId]
  if producer then assert(batch.seq>producer.seq,'Progress batch is stale or replayed.')
  else assert(length(q.producers)<64,'Quest producer budget exhausted; ownership rollover is required.') end
  local eventIds={};local digest=batchFingerprint(batch)
  for _,event in batch.events do
   assert(type(event)=='table' and identifier(event.hook,60) and identifier(event.eventId,120),'Invalid quest event.')
   assert(validateTime(event.at) and event.at<=batch.createdAt and op.now-event.at<=DAY*32,'Invalid or expired event time.')
   assert(integer(event.amount,0,1000000000),'Invalid quest event amount.')
   assert(type(event.ctx or {})=='table','Invalid event context.')
   assert(length(event.ctx or {})<=24,'Event context exceeds field budget.')
   for key,value in event.ctx or {} do
    assert(identifier(key,40),'Invalid event context key.')
    assert(type(value)=='boolean' or finite(value) or (type(value)=='string' and #value<=120),'Invalid event context value.')
   end
   local eventDigest=batchFingerprint(event)
   local oldEvent=q.eventReceipts[event.eventId]
   if oldEvent then assert(oldEvent.at==event.at and oldEvent.fingerprint==eventDigest,'Event identity was reused.')
   else assert(event.at>q.eventFloor,'Event receipt expired; saved-run qualification is required.') end
   event.ctx=event.ctx or {}
   -- Admin, test and instant-win exclusions are supplied by trusted hooks, never client payloads.
   if not eventIds[event.eventId] and not oldEvent and not event.ctx.admin and not event.ctx.instantWin and not event.ctx.test then
    eventIds[event.eventId]=true
    q.eventReceipts[event.eventId]={at=event.at,fingerprint=eventDigest}
    local day,week=periods(event.at)
    for _,pair in {{'daily',day},{'weekly',week}} do
     local tab,period=pair[1],pair[2];local record=findPeriod(q,tab,period)
     for _,item in record.entries do
      if not item.claimed then local def=item.definition;if def then advance(item,def,event) end end
     end
     if record~=q[tab] then settle(profile,tab,record,op,total) end
    end
    for _,item in q.achievements do
     local def=item.definition
     item.progress=item.count;advance(item,def,event);item.count=item.progress;item.progress=nil
    end
    advanceMasteries(profile,q,event,total)
    if eventEnabled(op.eventConfig,event.at) and eventEnabled(op.eventConfig,op.now) then
     local ev=q.events and q.events[q.activeEvent]
     if ev then
      if event.hook=='CandyCornCollected' and event.ctx.eventEligible==true then ev.candyCorn=math.min(1000000000,ev.candyCorn+event.amount) end
      for _,item in ev.entries do if not item.claimed then advance(item,item.definition,event) end end
     end
    end
    local scholar=q.achievements.curse_scholar
    if event.hook=='ItemPickup' and event.ctx.itemId and scholar and table.find(scholar.definition.eligibleIds or {},event.ctx.itemId) then q.seen.items[event.ctx.itemId]=true end
    local traveler=q.achievements.world_traveler
    if event.hook=='LevelCleared' and event.ctx.mapKind and traveler and table.find(traveler.definition.eligibleIds or {},event.ctx.mapKind) then q.seen.maps[event.ctx.mapKind]=true end
   end
  end
  q.producers[batch.producerId]={seq=batch.seq,createdAt=batch.createdAt}
  q.batches[batch.id]={producerId=batch.producerId,seq=batch.seq,createdAt=batch.createdAt,fingerprint=digest}
  table.insert(q.batchOrder,batch.id)
  while #q.batchOrder>(Catalog.MaxAppliedBatches or 128) do q.batches[table.remove(q.batchOrder,1)]=nil end
  local eventKeys=sortedKeys(q.eventReceipts)
  if #eventKeys>2048 then
   table.sort(eventKeys,function(a,b)
    local aa,bb=q.eventReceipts[a].at,q.eventReceipts[b].at
    return aa<bb or (aa==bb and a<b)
   end)
   for i=1,#eventKeys-2048 do
    local id=eventKeys[i];q.eventFloor=math.max(q.eventFloor,q.eventReceipts[id].at);q.eventReceipts[id]=nil
   end
  end
 end
 local function achievementKey(id,tier,version)
  return 'achievements:'..id..':v'..(version or VERSION)..':tier'..tier
 end
 local function masteryKey(q)
  return 'mastery:'..(q.masteryDefinition.id or 'mastery')..':v'..q.catalogVersion
 end
 local function resolve(q,key)
  assert(identifier(key,220),'Invalid claim key.')
  for _,tab in {'daily','weekly'} do
   local periodsList={q[tab]};for _,period in q.archives[tab] do table.insert(periodsList,period) end
   for _,period in periodsList do
    for _,item in period.entries do if item.claimKey==key then return {tab=tab,period=period,item=item,def=item.definition} end end
    local def=period.bonusDefinition
    if key==tab..':'..period.period..':'..def.id..':v'..period.version..':g0' then return {tab=tab,period=period,bonus=true,def=def} end
   end
  end
  for _,item in q.adminQuestEntries or {} do if item.claimKey==key then return {tab=item.tab,item=item,def=item.definition,adminEntry=true} end end
  for _,item in q.adminMapEntries or {} do if item.claimKey==key then return {tab='adminMap',item=item,def=item.definition} end end
  for id,item in q.achievements do
   local def=item.definition
   for tier=1,5 do if key==achievementKey(id,tier,item.version) then return {tab='achievements',def=def,tier=tier,item=item} end end
  end
  local ev=q.events and q.events[q.activeEvent]
  if ev then for _,item in ev.entries do if item.claimKey==key then return {tab='event',item=item,def=item.definition,event=ev} end end
   if key=='event:'..ev.id..':finale' then return {tab='event',bonus=true,event=ev} end
  end
  if key==masteryKey(q) then return {tab='mastery'} end
  error('Claim identity is unknown, changed or expired.')
 end
 local function claimOne(profile,q,key,op)
  local found=resolve(q,key);local r
  if found.tab=='adminMap' or found.adminEntry then assert(op.kind=='adminRewards' and op.adminOwner==315936607,'Owner-only reward identity.')end
  if found.tab=='event' then
   assert(eventEnabled(op.eventConfig,op.now),'Halloween event is inactive.')
   if found.bonus then assert(not found.event.finaleClaimed and completeCount(found.event)>=found.event.finale.target,'Event finale is unavailable.');r=reward(found.event.finale.reward);found.event.finaleClaimed=true
   else assert(not found.item.claimed and found.item.progress>=found.def.target,'Event quest is unavailable.');r=reward(found.def.reward);found.item.claimed=true end
   found.event.candyCorn+=r.candyCorn
  elseif found.tab=='mastery' then
   assert(not q.masteryClaimed,'Mastery was already claimed.')
   local n=0;for _,id in q.masteryDefinition.chainIds do if q.achievements[id] and q.achievements[id].tier==5 then n+=1 end end
   assert(n==10 and n>=(q.masteryDefinition.target or 10),'Claim all ten tier-V achievements first.')
   r=reward(q.masteryDefinition.reward);table.insert(r.tagIds,'Tag_Haunted');r.tag='[Haunted]';q.masteryClaimed=true
  elseif found.tab=='achievements' then
   local item=found.item;assert(found.tier==item.tier+1,'Achievement tier is already claimed or out of order.')
   assert(item.count>=found.def.targets[found.tier],'Achievement is not complete.')
   r=reward(found.def.rewards[found.tier]);item.tier=found.tier
   if found.tier==5 and identifier(found.def.titleId) then table.insert(r.cosmeticIds,found.def.titleId) end
  elseif found.bonus then
   assert(completeCount(found.period)>=found.def.target,'Quest bonus is not complete.')
   if found.tab=='daily' then
    if found.period.bonusClaimed and found.period.bonusSettledReward then return copy(found.period.bonusSettledReward),true end
    assert(not found.period.bonusClaimed,'Daily bonus was already claimed.')
    r=reward(found.def.reward);found.period.bonusClaimed=true
   else
    if found.period.chestClaimed and found.period.chestSettledReward then return copy(found.period.chestSettledReward),true end
    assert(not found.period.chestClaimed,'Weekly chest was already claimed.')
    r=chestReward(profile,op,key,found.def);found.period.chestClaimed=true
   end
  else
   assert(found.def and found.item.progress>=found.def.target,'Quest is not complete.')
   if found.item.claimed and found.item.settled and found.item.settledReward then return copy(found.item.settledReward),true end
   assert(not found.item.claimed,'Quest was already claimed.')
   r=itemReward(q,found.item);found.item.claimed=true
  end
  grant(profile,r);return r
 end
 local function adminRewards(profile,q,op,total)
  assert(op.adminOwner==315936607,'Only the owner can grant quest rewards.')
  local selector=op.questId;assert(identifier(selector,220),'Invalid reward selection.')
  local claimedKeys={}
  local function take(key)
   local found=resolve(q,key)
   assert(found.tab~='event','Event rewards cannot be granted while preparing the event.')
   local claimed=found.tab=='mastery' and q.masteryClaimed or found.item and found.item.claimed
   if found.tab=='achievements' then claimed=found.item.tier>=found.tier end
   if found.bonus then claimed=found.tab=='daily' and found.period.bonusClaimed or found.tab=='weekly' and found.period.chestClaimed end
   if claimed then return end
   if found.item and found.tab~='achievements' then found.item.progress=found.def.target end
   if found.bonus then for _,item in found.period.entries do item.progress=item.definition.target end end
   local r=claimOne(profile,q,key,op);sumReward(total,r);table.insert(claimedKeys,key)
  end
  local function achievement(id,targetTier)
   local item=q.achievements[id];assert(item and integer(targetTier,1,5),'Unknown achievement reward.')
   item.count=math.max(item.count,item.definition.targets[targetTier])
   if item.definition.mode=='distinct' then
    for _,eligible in item.definition.eligibleIds or {} do item.distinct[eligible]=true end
    item.count=math.max(item.count,length(item.distinct))
   end
   for tier=item.tier+1,targetTier do take(achievementKey(id,tier,item.version)) end
  end
  local function mapReward(id)
   local def=byId[id];assert(def and def.firstReward,'Unknown map reward.')
   q.adminMapEntries=q.adminMapEntries or {}
   if not q.adminMapEntries[id] then
    local frozen=copy(def);frozen.reward={tokens=0,revives=0}
    local item=entry(frozen,'adminMap',0,0);item.claimKey='adminMap:'..id
    q.adminMapEntries[id]=item
   end
   take(q.adminMapEntries[id].claimKey)
  end
  local function baseReward(tab,id)
   local def=byId[id];assert(def and def.reward and not def.targets,'Unknown rotating quest reward.')
   local belongs=false;for _,candidate in Catalog[tab=='daily' and 'Daily' or 'Weekly'] do if candidate.id==id then belongs=true end end
   assert(belongs,'Quest belongs to another reward tab.')
   q.adminQuestEntries=q.adminQuestEntries or {}
   local identity=tab..':'..id
   local saved=q.adminQuestEntries[identity]
   if saved and saved.claimed then return end
   local current
   for _,item in q[tab].entries do if item.id==id or def.alternative and item.id==def.alternative.id then current=item end end
   local frozen=copy(def);frozen.alternative=nil
   local item=entry(frozen,tab,q[tab].period,0);item.claimKey='adminQuest:'..identity;item.tab=tab;item.period=q[tab].period
   q.adminQuestEntries[identity]=item
   if current then
    if not current.claimed then take(current.claimKey)end
    item.progress=item.definition.target;item.claimed=true
   else take(item.claimKey)end
  end
  if selector=='all' then
   for _,tab in {'daily','weekly'} do
    for _,item in q[tab].entries do take(item.claimKey) end
    local bonus=q[tab].bonusDefinition
    take(tab..':'..q[tab].period..':'..bonus.id..':v'..q[tab].version..':g0')
   end
   for _,tab in {'daily','weekly'} do for _,def in Catalog[tab=='daily' and 'Daily' or 'Weekly'] do baseReward(tab,def.id)end end
   for _,id in sortedKeys(q.achievements) do achievement(id,5) end
   for _,def in Catalog.Weekly do if def.firstReward then mapReward(def.id) end end
   take(masteryKey(q))
  elseif selector=='mastery' then
   for _,id in sortedKeys(q.achievements) do achievement(id,5) end;take(masteryKey(q))
  elseif selector=='chest' then
   local def=q.weekly.bonusDefinition;take('weekly:'..q.weekly.period..':'..def.id..':v'..q.weekly.version..':g0')
  elseif string.match(selector,'^daily:d_') and not string.find(selector,':v',1,true) then baseReward('daily',string.sub(selector,7))
  elseif string.match(selector,'^weekly:w_') and not string.find(selector,':v',1,true) then baseReward('weekly',string.sub(selector,8))
  elseif string.sub(selector,1,4)=='map:' then mapReward(string.sub(selector,5))
  elseif string.sub(selector,1,12)=='achievement:' then
   local id,tier=string.match(selector,'^achievement:([%w_]+):(%d)$');assert(id and tier,'Invalid achievement reward.');achievement(id,assert(tonumber(tier)))
  else take(selector) end
  return claimedKeys
 end
 local function fingerprint(op)
  local keys=op.keys or {};local pieces={op.kind,tostring(op.userId),tostring(op.tab or ''),tostring(op.claimKey or ''),tostring(op.questId or ''),tostring(op.adminOwner or ''),tostring(op.bootstrap or false),tostring(op.batch and batchFingerprint(op.batch) or '')}
  for _,key in keys do assert(identifier(key,220),'Invalid frozen claim key.');table.insert(pieces,key) end
  return table.concat(pieces,'|')
 end
 -- Hints are presentation copy: show current wording without changing frozen rewards/targets.
 local function displayCopy(def,field)
  local current=byId[def.id] or achById[def.id]
  if not current then for _,row in Catalog.Event and Catalog.Event.quests or {} do if row.id==def.id then current=row;break end end end
  return current and current[field] or def[field]
 end
 local function snapshotEntry(item,q)
  local def=item.definition
  local shown=reward(def.reward)
  if def.firstReward and q and not (q.firstClaims or {})[item.id] then sumReward(shown,reward(def.firstReward)) end
  return {id=item.id,claimKey=item.claimKey,text=displayCopy(def,'text'),hint=displayCopy(def,'hint'),icon=def.icon,progress=item.progress,
   target=def.target,reward=shown,claimed=item.claimed==true,ready=not item.claimed and item.progress>=def.target}
 end
 function E.State(profile,now,eventConfig)
  assert(validateTime(now),'Invalid state time.')
  local q=profile.Quests;assert(type(q)=='table' and q.v==1,'Quests are not initialized.')
  local out={serverTime=now,rev=q.rev,userId=q.userId,daily={resetAt=0},weekly={resetAt=0},achievements={},mastery={},pinned=q.pinned,readyCount=0,
   collection={items=copy(q.seen.items),maps=copy(q.seen.maps)}}
  for _,tab in {'daily','weekly'} do
   local period=q[tab];local view={period=period.period,entries={},rerolled=period.rerolled,resetAt=tab=='daily' and (period.period+1)*DAY or (period.period+1)*WEEK-OFFSET}
   for _,item in period.entries do
    local row=snapshotEntry(item,q);table.insert(view.entries,row);if row.ready then out.readyCount+=1 end
   end
   local def=period.bonusDefinition
   local claimed
   if tab=='daily' then claimed=period.bonusClaimed else claimed=period.chestClaimed end
   local bonus={id=def.id,hint=(tab=='daily' and Catalog.DailyBonus or Catalog.WeeklyChest).hint,claimKey=tab..':'..period.period..':'..def.id..':v'..period.version..':g0',progress=completeCount(period),target=def.target,
    reward=reward(def.reward),claimed=claimed==true,ready=not claimed and completeCount(period)>=def.target}
   bonus.done=bonus.progress
   view.quests=view.entries
   view[tab=='daily' and 'bonus' or 'chest']=bonus;if bonus.ready then out.readyCount+=1 end
   out[tab]=view
  end
  out.dailyEndsAt=out.daily.resetAt;out.weeklyEndsAt=out.weekly.resetAt
  local mastered=0
  for _,id in sortedKeys(q.achievements) do
   local item=q.achievements[id];local def=item.definition;local tier=item.tier+1;local nextTier=math.min(5,tier)
   local r=reward(def.rewards[nextTier]);if tier==5 and def.titleId then table.insert(r.cosmeticIds,def.titleId) end
   local row={id=def.id,name=displayCopy(def,'name'),text=displayCopy(def,'text'),hint=displayCopy(def,'hint'),icon=def.icon,count=item.count,progress=item.count,tier=item.tier,nextTier=nextTier,
    target=def.targets[nextTier],claimKey=tier<=5 and achievementKey(def.id,tier,item.version) or nil,reward=r,ready=tier<=5 and item.count>=def.targets[tier],claimed=item.tier==5,titleId=def.titleId,
    targets=copy(def.targets),rewards=copy(def.rewards),title=def.title}
   table.insert(out.achievements,row);if row.ready then out.readyCount+=1 end
  end
  for _,id in q.masteryDefinition.chainIds do if q.achievements[id] and q.achievements[id].tier==5 then mastered+=1 end end
  out.mastery={id=q.masteryDefinition.id,claimKey=masteryKey(q),progress=mastered,target=10,claimed=q.masteryClaimed==true,
   ready=not q.masteryClaimed and mastered>=10,done=mastered,hint=Catalog.Mastery.hint,tag='[Haunted]',reward={tokens=0,revives=0,cosmeticIds={},tagIds={'Tag_Haunted'},tag='[Haunted]'}}
  if out.mastery.ready then out.readyCount+=1 end
  out.masteries={}
  local today=math.floor(now/DAY);local boost=q.masteryBoost or {day=-1,used=0};local mastered=0
  out.masteryBoost={limit=BOOST,left=boost.day==today and math.max(0,BOOST-boost.used) or BOOST,resetAt=(today+1)*DAY}
  for _,def in masteryDefs do
   local rec=(q.masteries or {})[def.id] or {count=0,level=0};local max=#def.targets
   if rec.level>=max then mastered+=1 end
   table.insert(out.masteries,{id=def.id,name=def.name,kind=def.kind,creatureKind=def.creatureKind,unit=def.unit,hint=def.hint,color=copy(def.color),
    count=rec.count,level=rec.level,maxLevel=max,floor=rec.level>0 and def.targets[rec.level] or 0,nextTarget=def.targets[math.min(max,rec.level+1)],
    targets=copy(def.targets),complete=rec.level>=max,levelReward=reward(Catalog.MasteryLevelReward),completeReward=reward(Catalog.MasteryCompleteReward)})
  end
  out.masteryLast=q.masteryLast and copy(q.masteryLast) or nil
  local grand=Catalog.GrandMastery
  out.grandMastery=grand and {name=grand.name,hint=grand.hint,done=mastered,target=#masteryDefs,claimed=q.grandMastery==true,reward=reward(grand.reward)} or nil
  out.event={enabled=false}
  if eventEnabled(eventConfig,now) then
   local ev=q.events and q.events[q.activeEvent]
   if ev then
    out.event={enabled=true,id=ev.id,endsAt=ev.endsAt,candyCorn=ev.candyCorn,quests={},shop=copy(ev.shop)}
    for _,row in out.event.shop do row.price=row.cost;row.owned=profile.Owned and profile.Owned[row.id]==true or false end
    for _,item in ev.entries do local row=snapshotEntry(item,q);table.insert(out.event.quests,row);if row.ready then out.readyCount+=1 end end
    local done=completeCount(ev);out.event.finale={claimKey='event:'..ev.id..':finale',done=done,target=ev.finale.target,claimed=ev.finaleClaimed,ready=not ev.finaleClaimed and done>=ev.finale.target,reward=reward(ev.finale.reward)}
    if out.event.finale.ready then out.readyCount+=1 end
   end
  end
  return out
 end
 function E.Init(profile,userId,now,selection)
  local nextProfile,err=clone(profile);if not nextProfile then return nil,err end
  local ok,result=pcall(function()
   local total=emptyReward();local oldRev=nextProfile.Quests and nextProfile.Quests.rev or 0
   local oldDay=nextProfile.Quests and nextProfile.Quests.daily and nextProfile.Quests.daily.period
   local day=periods(now)
   local q=setup(nextProfile,userId,now,selection,selection or {},total)
   if oldDay~=day then q.rev=oldRev+1 end
   total._settledKeys=nil
   return {ok=true,reward=total,state=E.State(nextProfile,now)}
  end)
  if not ok then return nil,tostring(result) end
  return nextProfile,result
 end
 function E.Apply(profile,op)
  if type(op)~='table' then return nil,'Invalid quest operation.' end
  local operation,copyError=clone(op);if not operation then return nil,copyError end;op=operation
  local nextProfile,err=clone(profile);if not nextProfile then return nil,err end
  local ok,result=pcall(function()
   assert(table.find({'progress','claim','claimAll','reroll','pin','init','eventPurchase','adminRewards'},op.kind),'Unknown quest operation.')
   assert(validUser(op.userId) and validateTime(op.now),'Invalid server user/time.')
   local previous=nextProfile.Quests
   if previous then assert(previous.userId==op.userId,'Quest operation user mismatch.') end
   if op.kind=='adminRewards' then
    assert(op.adminOwner==315936607,'Only the owner can grant quest rewards.')
    if op.bootstrap==true and previous and previous.adminBootstrapGranted then return {ok=true,duplicate=true,reward=emptyReward(),state=E.State(nextProfile,op.now,op.eventConfig)}end
   end
   if op.kind=='progress' and previous and type(op.batch)=='table' and previous.batches and previous.batches[op.batch.id] then
    local receipt=previous.batches[op.batch.id]
    assert(receipt.fingerprint==batchFingerprint(op.batch),'Batch identity was reused.')
    return {ok=true,duplicate=true,reward=emptyReward(),state=E.State(nextProfile,op.now,op.eventConfig)}
   end
   local fp
   if op.kind~='progress' and op.kind~='init' then
    assert(identifier(op.requestId,120),'A durable request id is required.');fp=fingerprint(op)
    local receipt=previous and previous.requests and previous.requests[op.requestId]
    if receipt then
     assert(receipt.fingerprint==fp,'Request identity was reused for another operation.')
     local replay=copy(receipt.result);replay.duplicate=true;replay.state=E.State(nextProfile,op.now,op.eventConfig);return replay
    end
   end
   local total=emptyReward();local q=setup(nextProfile,op.userId,op.now,op.selection,op,total)
   setupEvent(q,op)
   applyBatch(nextProfile,q,op.batch,op,total)
   local duplicate=false
   local function applyClaim(key)
    local r,settled=claimOne(nextProfile,q,key,op)
    if not settled or not (total._settledKeys or {})[key] then sumReward(total,r) end
    if settled and not (total._settledKeys or {})[key] then duplicate=true end
   end
   if op.kind=='adminRewards' then
    total.claimedKeys=adminRewards(nextProfile,q,op,total)
    if op.bootstrap==true then assert(op.questId=='all','Bootstrap must grant all quest rewards.');q.adminBootstrapGranted=true end
   elseif op.kind=='eventPurchase' then
    assert(eventEnabled(op.eventConfig,op.now),'Halloween event is inactive.')
    local ev=q.events and q.events[q.activeEvent];assert(ev,'Event is unavailable.')
    local offer;for _,item in ev.shop do if item.id==op.questId then offer=item end end
    assert(offer and not (nextProfile.Owned or {})[offer.id],'Event offer is unavailable.')
    assert(ev.candyCorn>=offer.cost,'Not enough Candy Corn.');ev.candyCorn-=offer.cost
    grant(nextProfile,{tokens=0,revives=0,cosmeticIds={offer.id},tagIds={}});table.insert(total.cosmeticIds,offer.id)
   elseif op.kind=='progress' then assert(op.batch~=nil,'Progress requires a batch.')
   elseif op.kind=='claim' then
    if op.tab then assert(resolve(q,op.claimKey).tab==op.tab,'Claim key belongs to another tab.') end
    applyClaim(op.claimKey)
   elseif op.kind=='claimAll' then
    assert(type(op.keys)=='table' and #op.keys>0 and #op.keys<=64,'Claim All requires bounded frozen keys.')
    local seen={}
    for _,key in op.keys do
     assert(not seen[key],'Duplicate claim key.');seen[key]=true
     if op.tab then assert(resolve(q,key).tab==op.tab,'Claim All keys include another tab.') end
     applyClaim(key)
    end
   elseif op.kind=='reroll' then
    local found=resolve(q,op.claimKey)
    assert(found.tab=='daily' and not found.bonus and found.period==q.daily,'Only a current daily quest can reroll.')
    assert(q.daily.version==VERSION,'Quest catalog changed; reroll resumes after the next reset.')
    assert(not q.daily.rerolled and not found.item.claimed and found.item.progress<found.def.target,'Daily reroll is unavailable for this quest.')
    local difficulty=found.def.difficulty
    if not difficulty then
     for _,def in Catalog.Daily do if def.alternative and def.alternative.id==found.def.id then difficulty=def.difficulty;break end end
    end
    local soloSelection=copy(q.selection);soloSelection.partySize=1
    local pool=candidates(Catalog.Daily,soloSelection,difficulty);local remaining={}
    for _,def in pool do if def.id~=found.def.id then table.insert(remaining,def) end end
    assert(#remaining>0,'There is no feasible reroll alternative.')
    local def=pick(remaining,hash(q.userId..':'..q.daily.period..':'..found.def.id..':reroll:'..VERSION))
    for i,item in q.daily.entries do if item==found.item then q.daily.entries[i]=entry(def,'daily',q.daily.period,1);local previousGrant=(q.adminQuestEntries or {})['daily:'..def.id];if previousGrant and previousGrant.claimed and previousGrant.period==q.daily.period then q.daily.entries[i].progress=def.target;q.daily.entries[i].claimed=true end;break end end
    q.daily.rerolled=true
   elseif op.kind=='pin' then
    if op.questId==nil or op.questId=='' then q.pinned=nil
    else
     assert(identifier(op.questId),'Invalid pin identity.');local valid=false
     for _,tab in {'daily','weekly'} do for _,item in q[tab].entries do if item.id==op.questId and not item.claimed then valid=true end end end
     if achById[op.questId] and q.achievements[op.questId].tier<5 then valid=true end
     assert(valid,'Pin is not a current unclaimed quest.');q.pinned=op.questId
    end
   end
   q.rev+=1
   total._settledKeys=nil
   local answer={ok=true,duplicate=duplicate,reward=total,state=E.State(nextProfile,op.now,op.eventConfig)}
   if op.kind~='progress' and op.kind~='init' then
    q.requests[op.requestId]={fingerprint=fp,result={ok=true,reward=copy(total)},at=op.now}
    table.insert(q.requestOrder,op.requestId)
    while #q.requestOrder>(Catalog.MaxClaimReceipts or 256) do q.requests[table.remove(q.requestOrder,1)]=nil end
   end
   return answer
  end)
  if not ok then return nil,tostring(result) end
  return nextProfile,result
 end
 function E.RewardOptions(profile)
  local q=profile.Quests;assert(q and q.v==1,'Quests unavailable.')
  local out={{id='all',name='All quest rewards'},{id='mastery',name='Haunted Mastery and required achievements'},{id='chest',name='Current weekly chest'}}
  for _,tab in {'daily','weekly'} do
   for _,item in q[tab].entries do table.insert(out,{id=item.claimKey,name=item.definition.text,tab=tab,claimed=item.claimed})end
   local bonus=q[tab].bonusDefinition
   if tab=='daily' then table.insert(out,{id='daily:'..q.daily.period..':'..bonus.id..':v'..q.daily.version..':g0',name='Current daily bonus',tab=tab,claimed=q.daily.bonusClaimed})end
  end
  for _,tab in {'daily','weekly'} do for _,def in Catalog[tab=='daily' and 'Daily' or 'Weekly'] do table.insert(out,{id=tab..':'..def.id,name=def.text,tab=tab,claimed=(q.adminQuestEntries or {})[tab..':'..def.id] and q.adminQuestEntries[tab..':'..def.id].claimed or false})end end
  for _,def in Catalog.Weekly do if def.firstReward then table.insert(out,{id='map:'..def.id,name=def.text..' hat',claimed=q.firstClaims[def.id]==true})end end
  for _,id in sortedKeys(q.achievements) do local item=q.achievements[id];for tier=1,5 do table.insert(out,{id='achievement:'..id..':'..tier,name=item.definition.name..' tier '..tier,claimed=item.tier>=tier})end end
  return out
 end
 function E.Reconcile(value)
  local q,err=clone(value);if not q then return nil,err end
  if type(q)~='table' or q.v~=1 then return nil,'Unsupported quest save version; preserved without writing.' end
  local ok,reason=pcall(function()
   assert(integer(q.rev or 0,0,9007199254740991),'Invalid quest revision.')
   assert(type(q.daily)=='table' and type(q.weekly)=='table' and type(q.achievements)=='table','Invalid quest periods.')
   assert(length(q.achievements)<=32 and length(q.producers or {})<=64,'Quest ledger exceeds its budget.')
   assert(length(q.requests or {})<=256 and length(q.batches or {})<=256 and length(q.eventReceipts or {})<=2048,'Quest receipt budget exceeded.')
   for _,tab in {'daily','weekly'} do
    assert(type(q[tab].entries)=='table' and #q[tab].entries<=(tab=='daily' and 3 or 5),'Invalid quest entry budget.')
    assert(length((q.archives or {})[tab] or {})<=MAX_ARCHIVE,'Archive budget exceeded.')
   end
   assert(length(q.adminQuestEntries or {})<=64,'Admin quest receipt budget exceeded.')
   assert(length(q.adminMapEntries or {})<=8,'Admin map receipt budget exceeded.')
   assert(length(q.masteries or {})<=32,'Mastery budget exceeded.')
   assert(length(q.events or {})<=8 and length(q.firstClaims or {})<=64,'Quest event/first receipt budget exceeded.')
   for _,ev in q.events or {} do assert(type(ev.entries)=='table' and #ev.entries<=6 and integer(ev.candyCorn,0,1000000000),'Invalid event state.') end
   migrateScholar(q);migrateTraveler(q)
  end)
  if not ok then return nil,tostring(reason) end
  return q
 end
 return E
end
return Module
