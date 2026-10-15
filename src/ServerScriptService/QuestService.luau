-- One server quest bridge. ProgressService is the persistence owner and binds its transaction here.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Http=game:GetService('HttpService')
local Catalog=require(RS:WaitForChild('QuestCatalog'))
local Engine=require(script.Parent:WaitForChild('QuestCore')).new(Catalog)
local EventConfig=require(RS:WaitForChild('EventConfig'))
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local Q={}
local bridge
local buffers,locks,pendingOps,nextRemote,nextPush,displayRevs,overrides,fixtures={},{},{},{},{},{},{},{}
local changed
local dirty={}
local pendingLegacy={}
local departFlushing,departTries,departNext={},{},{}
local mapKinds={claim='questClaim',claimAll='questClaimAll',reroll='questReroll',pin='questPin',eventPurchase='questEventPurchase',adminRewards='questAdminRewards'}
local allowedHooks={}
for _,defs in {Catalog.Daily,Catalog.Weekly,Catalog.Achievements,Catalog.Event and Catalog.Event.quests or {}} do for _,d in defs do allowedHooks[d.event]=true end end
for _,name in {'Death','CandyCornCollected','PumpkinCarved','HorsemanHeadFound','EventTreasureFound','EventSecretFound'}do allowedHooks[name]=true end
local function now(p)return overrides[p] or os.time()end
function Q.Now(p)return now(p)end
local function player(p)return typeof(p)=='Instance' and p:IsA('Player')end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)~=math.huge end
local function short(s,n)return type(s)=='string' and #s>0 and #s<=(n or 120) and not string.find(s,'%c')end
local function buf(p)
 local b=buffers[p];if not b then b={events={},pending=nil,seen={},seenOrder={}};buffers[p]=b end;return b
end
local function pool()
 local out={}
 for id in Shop.Purchasable do
  local item=Shop.ById[id]
  if item and table.find({'Hat','Ring','Shirt','Shoes','Eyes','Back','Trail','Torch'},item.kind) and not item.chestExclusive and item.releaseStage~='event' and not item.nonPurchasable then
   table.insert(out,{id=id,kind=item.kind,tokenPurchasable=true,premium=false,retired=false})
  end
 end
 table.sort(out,function(a,b)return a.id<b.id end);return out
end
local function selection(p)
 local size=1;local party=p and p:GetAttribute('LobbyPartyId')
 if party then for _,other in Players:GetPlayers()do if other~=p and other:GetAttribute('LobbyPartyId')==party then size+=1 end end end
 -- MissionRuntime keeps CruiseBoatServer disabled, so its weekly cannot be selected.
 return {partySize=size,mapKinds=Catalog.MapKinds,capabilities={maps=true,boat=false},cosmeticPool=pool()}
end
local function config()return {Halloween=table.clone(EventConfig.Halloween)}end
local function payload(p,kind)
 return {kind=kind,userId=p.UserId,now=now(p),selection=selection(p),cosmeticPool=pool(),eventConfig=config()}
end
local function ensure(p)
 if not bridge or not player(p) or not bridge.Load(p) then return false,'Your quest save is unavailable.' end
 local d=bridge.Profile(p)
 if not d then return false,'Your quest save is unavailable.' end
 local t=now(p);local day=math.floor(t/86400);local week=math.floor((t+259200)/604800)
 local q=d.Quests
 local retiredBoat=false
 if q and q.weekly then for _,row in q.weekly.entries do if row.id=='w_boat' or row.definition and row.definition.id=='w_boat'then retiredBoat=true;break end end end
 local h=EventConfig.Halloween;local active=h.Enabled==true and t>=h.StartsAt and t<h.EndsAt
 if retiredBoat or active and not(q and q.activeEvent==(h.Id or Catalog.Event.id) and q.events and q.events[q.activeEvent]) or not q or not q.daily or q.daily.period~=day or not q.weekly or q.weekly.period~=week then
  local ok,msg=bridge.Transaction(p,{kind='questInit',quest=payload(p,'init')})
  if not ok then return false,msg end
 end
 return true
end
local function freeze(p)
 local b=buf(p)
 if b.pending then return b.pending end
 if #b.events==0 then return nil end
 local d=bridge.Profile(p);local producer='quest:'..p.UserId
 local mark=d.Quests and d.Quests.producers and d.Quests.producers[producer]
 local events={};for i=1,math.min(128,#b.events)do events[i]=b.events[i]end
 for _=1,#events do table.remove(b.events,1)end
 b.pending={id=Http:GenerateGUID(false),producerId=producer,seq=(mark and mark.seq or 0)+1,createdAt=now(p),events=events}
 return b.pending
end
local function committed(p,batch)
 local b=buf(p);if b.pending==batch then b.pending=nil end
end
local function guard(p,callback,waitForLock)
 if locks[p] and waitForLock then
  local untilAt=os.clock()+20;while locks[p] and os.clock()<untilAt do task.wait(.05)end
 end
 if locks[p]then return {ok=false,reason='Quest progress is saving. Please retry.'}end
 locks[p]=true
 local ok,result=pcall(callback)
 locks[p]=nil
 if not ok then
  if player(p) and p.Parent then p:SetAttribute('QuestSaveStatus','Retry')end
  warn('Quest operation failed: '..tostring(result))
  return {ok=false,reason='Your quest could not save. Please retry.'}
 end
 return result
end
local function state(p,overlay)
 local d=bridge.Profile(p)
 if not d or not d.Quests then return nil end
 if overlay then
  local b=buf(p);local events={}
  if b.pending then for _,e in b.pending.events do table.insert(events,e)end end
  for _,e in b.events do if #events<128 then table.insert(events,e)end end
  if #events>0 then
   local op=payload(p,'progress');local producer='preview:'..p.UserId
   local mark=d.Quests.producers and d.Quests.producers[producer]
   op.batch={id='preview',producerId=producer,seq=(mark and mark.seq or 0)+1,createdAt=now(p),events=events}
   local preview=Engine.Apply(d,op);if preview then d=preview end
  end
 end
 local s=Engine.State(d,now(p),config())
 displayRevs[p]=math.max(displayRevs[p]or 0,s.rev)+1;s.savedRev=s.rev;s.rev=displayRevs[p]
 return s
end
local function push(p)
 dirty[p]=true
 if not changed or p.Parent~=Players then return end
 if os.clock()<(nextPush[p]or 0)then return end
 nextPush[p]=os.clock()+.5;dirty[p]=nil
 local s=state(p,true);if s then changed:FireClient(p,s);p:SetAttribute('QuestReadyCount',s.readyCount)end
end
function Q.GetState(p)
 if not player(p) or p.Parent~=Players then return {ok=false,reason='Player unavailable.'}end
 return guard(p,function()
  local ok,reason=ensure(p);if not ok then return {ok=false,reason=reason}end
  return {ok=true,state=state(p,true)}
 end,false)
end
function Q.IsAssisted(runId,round)
 local recovery=RS:FindFirstChild('RecoveryRound')
 return recovery~=nil and recovery:GetAttribute('QuestAssisted')==true and (not runId or recovery:GetAttribute('QuestRunId')==runId) and (not round or recovery:GetAttribute('Round')==round)
end
function Q.MarkAssisted(runId,round)
 local recovery=RS:FindFirstChild('RecoveryRound')
 if recovery and (not runId or recovery:GetAttribute('QuestRunId')==runId) and (not round or recovery:GetAttribute('Round')==round)then recovery:SetAttribute('QuestAssisted',true);recovery:SetAttribute('QuestAssistedRunId',recovery:GetAttribute('QuestRunId'))end
end
local personal={ItemPickup=true,GrabUse=true,DoorUnlocked=true,SecretFound=true,ClosetHide=true,ChaseEscaped=true,BoatDocked=true}
function Q.Record(p,hook,amount,ctx)
 if not bridge or not player(p) or p.Parent~=Players or not allowedHooks[hook] or not finite(amount) or amount<0 or amount%1~=0 or amount>1000000000 then return false end
 ctx=type(ctx)=='table' and table.clone(ctx) or {}
 local fixture=fixtures[p]==true and ctx.fixture==true
 if (p:GetAttribute('RewardTestMode')==true or p:GetAttribute('AdminSimulateNoPasses')==true or p:GetAttribute('QuestTestMode')==true) and not fixture then return false end
 if ctx.admin or ctx.adminSpawned or ctx.AdminProvenance or ctx.test or ctx.instantWin then return false end
 if hook=='LobbyToyGrab'then
  local ls=RS:FindFirstChild('LobbyState')
  if p:GetAttribute('MissionActive')==true or not(ls and ls:GetAttribute('Mode')=='Menu' or p:GetAttribute('ReturnedToLobby')==true)then return false end
 elseif not fixture then
  if p:GetAttribute('MissionActive')~=true then return false end
  if ctx.lobbyToy or ctx.gear or ctx.assisted or Q.IsAssisted(ctx.runId,ctx.round)then return false end
  if personal[hook]then local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if not h or h.Health<=0 then return false end end
 end
 if hook=='ChaseEscaped'then local h=EventConfig.Halloween;local t=now(p);ctx.eventEligible=h.Enabled==true and t>=h.StartsAt and t<h.EndsAt end
 local copied={};local fields=0
 for k,v in ctx do if k~='fixture' and short(k,40) and (type(v)=='boolean' or type(v)=='string' and #v<=120 or finite(v))then fields+=1;if fields>24 then return false end;copied[k]=v end end
 copied.fixture=nil
 local id=ctx.eventId
 if not short(id,120)then id=hook..':'..Http:GenerateGUID(false)end
 local b=buf(p)
 if b.seen[id] then return true end
 local saved=bridge.Profile(p);local receipts=saved and saved.Quests and saved.Quests.eventReceipts
 if receipts and receipts[id]then return true end -- qualified owner identity already committed (e.g. restored map loot)
 if #b.events>=4096 then p:SetAttribute('QuestSaveStatus','Progress paused: save pending');return false end
 b.seen[id]=true;table.insert(b.seenOrder,id)
 while #b.seenOrder>2048 do b.seen[table.remove(b.seenOrder,1)]=nil end
 table.insert(b.events,{hook=hook,eventId=id,amount=amount,at=now(p),ctx=copied})
 p:SetAttribute('QuestSaveStatus','Saving')
 if #b.events>=96 then task.spawn(Q.Flush,p)end
 task.defer(function()if bridge.Profile(p)and bridge.Profile(p).Quests then push(p)end end)
 return true
end
function Q.RecordParty(roster,hook,amount,ctx)
 local n=0
 for _,p in roster do if Q.Record(p,hook,amount,ctx)then n+=1 end end
 return n
end
local function flushInner(p,legacy)
 if legacy then pendingLegacy[p]=table.clone(legacy)end
 local ok,reason=ensure(p);if not ok then return {ok=false,reason=reason}end
 local pending=pendingOps[p]
 if pending then
  pending.op.now=now(p)
  local saved,result=bridge.Transaction(p,{kind=mapKinds[pending.op.kind],quest=pending.op})
  if not saved then
   if result~='Save service is unavailable. Please try again.' and result~='Save is busy. Please try again.'then pendingOps[p]=nil else return {ok=false,reason=result}end
  else
   if pending.op.batch then committed(p,pending.op.batch)end;pendingOps[p]=nil
  end
  end
 legacy=pendingLegacy[p]
 local last
 repeat
  local batch=freeze(p)
  local op=payload(p,batch and 'progress' or 'init');op.batch=batch
  local wrapped=legacy and table.clone(legacy) or {kind=batch and 'questProgress' or 'questInit'}
  wrapped.quest=op
  local saved,result=bridge.Transaction(p,wrapped)
  if not saved then return {ok=false,reason=result}end
  if batch then committed(p,batch)end
  last=result
  if legacy then pendingLegacy[p]=nil end
  legacy=nil
 until #buf(p).events==0 and not buf(p).pending
 p:SetAttribute('QuestSaveStatus','Saved');push(p)
 return {ok=true,state=state(p,false),reward=type(last)=='table' and last.reward or nil}
end
function Q.Flush(p)
 if not bridge or not player(p)then return false,'Unavailable.'end
 local result=guard(p,function()return flushInner(p)end,true)
 return result.ok,result.reason
end
function Q.Checkpoint(p,legacy)
 local result=guard(p,function()return flushInner(p,legacy)end,true)
 return result.ok,result.reason
end
function Q.FlushParty(roster)
 for _,p in roster do task.spawn(Q.Flush,p)end
end
local function canClaim(p)
 if p:GetAttribute('MissionActive')==true then return bridge.CanUseVanShop(p)end
 local ls=RS:FindFirstChild('LobbyState');return ls and ls:GetAttribute('Mode')=='Menu' or p:GetAttribute('ReturnedToLobby')==true
end
function Q.Mutate(p,kind,tab,key,requestId)
 if not player(p) or p.Parent~=Players or not mapKinds[kind]then return {ok=false,reason='Invalid quest request.'}end
 if kind~='pin' and not canClaim(p) and not fixtures[p]then return {ok=false,reason='Claim quests in the lobby or inside the van.'}end
 if kind=='claim' or kind=='claimAll'then if not table.find({'daily','weekly','achievements','mastery','event'},tab)then return {ok=false,reason='Invalid quest tab.'}end end
 if (kind=='claim' or kind=='reroll')and not short(key,220)then return {ok=false,reason='Invalid quest key.'}end
 if kind=='eventPurchase' and not short(key,120)then return {ok=false,reason='Invalid event reward.'}end
 if kind=='pin'and key~=nil and not short(key,120)then return {ok=false,reason='Invalid quest pin.'}end
 if requestId~=nil and not short(requestId,120)then return {ok=false,reason='Invalid request identity.'}end
 return guard(p,function()
  local ok,reason=ensure(p);if not ok then return {ok=false,reason=reason}end
  if kind=='claimAll' and requestId then
   local receipt=bridge.Profile(p).Quests.requests[requestId]
   if receipt then
    local prefix='claimAll|'..p.UserId..'|'..tab..'|'
    if string.sub(receipt.fingerprint,1,#prefix)~=prefix then return {ok=false,reason='Request identity was reused for another operation.'}end
    return {ok=true,reward=receipt.result.reward,state=state(p,true)}
   end
  end
  local signature=kind..':'..tostring(tab)..':'..tostring(key)
  local pending=pendingOps[p]
  if pending and pending.signature~=signature then return {ok=false,reason='Retry your pending quest action before another action.'}end
  if not pending then
   local op=payload(p,kind);op.tab=tab;op.requestId=requestId or Http:GenerateGUID(false);op.batch=freeze(p)
   if kind=='claim' or kind=='reroll'then op.claimKey=key
   elseif kind=='pin' or kind=='eventPurchase'then op.questId=key
   elseif kind=='claimAll'then
    op.keys={};local s=state(p,true)
    if tab=='achievements'then
     for _,row in s.achievements do
      if row.ready then for tier=row.tier+1,5 do if row.count>=row.targets[tier]then table.insert(op.keys,'achievements:'..row.id..':v'..bridge.Profile(p).Quests.achievements[row.id].version..':tier'..tier)end end end
     end
    elseif tab=='mastery'then if s.mastery.ready then table.insert(op.keys,s.mastery.claimKey)end
    elseif tab=='event'then
     for _,row in (s.event and s.event.quests)or{}do if row.ready then table.insert(op.keys,row.claimKey)end end
     if s.event and s.event.finale and s.event.finale.ready then table.insert(op.keys,s.event.finale.claimKey)end
    else
     for _,row in s[tab].quests do if row.ready then table.insert(op.keys,row.claimKey)end end
     local bonus=s[tab][tab=='daily'and'bonus'or'chest'];if bonus.ready then table.insert(op.keys,bonus.claimKey)end
    end
    if #op.keys==0 then return {ok=false,reason='No quest rewards are ready.'}end
   end
   local preview,validation=Engine.Apply(bridge.Profile(p),op)
   if not preview then return {ok=false,reason=validation,state=state(p,true)}end
   pending={signature=signature,op=op};pendingOps[p]=pending
  end
  pending.op.now=now(p)
  local saved,answer=bridge.Transaction(p,{kind=mapKinds[kind],quest=pending.op})
  if not saved then
   -- Only an uncertain save keeps its immutable operation. A validation rejection is definitive.
   if answer~='Save service is unavailable. Please try again.' and answer~='Save is busy. Please try again.'then
    pendingOps[p]=nil
   end
   return {ok=false,reason=answer,state=state(p,true)}
  end
  if pending.op.batch then committed(p,pending.op.batch)end
  pendingOps[p]=nil;p:SetAttribute('QuestSaveStatus','Saved');push(p)
  return {ok=true,reward=type(answer)=='table'and answer.reward or nil,state=state(p,false)}
 end,false)
end
-- Server-only owner reward grant. The client never supplies authority.
local function adminOwner(p)
 if not player(p) or p.Parent~=Players then return false end
 if p.UserId==315936607 then return true end
 if p.UserId~=-1 or not fixtures[p] or p:GetAttribute('QuestTestMode')~=true or not game:GetService('RunService'):IsStudio() then return false end
 local ok,args=pcall(function()return game:GetService('StudioTestService'):GetTestArgs()end)
 return ok and type(args)=='table' and args.kind=='QuestNativeTest' and args.questTest==true and args.forceName=='QuestNativeTest'
end
function Q.AdminCatalog(p)
 if not adminOwner(p)then return {}end
 local result=Q.GetState(p);if not result.ok then return {}end
 local rows=Engine.RewardOptions(bridge.Profile(p),now(p),config())
 for _,row in rows do row.label=row.label or row.name end
 return rows
end
function Q.AdminRewards(p,selector,requestId,bootstrap)
 if selector=='ALL'then selector='all'end
 if not adminOwner(p)then return {ok=false,reason='Owner access only.'}end
 if not short(selector,220) or requestId~=nil and not short(requestId,120) or bootstrap~=nil and type(bootstrap)~='boolean'then return {ok=false,reason='Invalid quest reward request.'}end
 return guard(p,function()
  local available,why=ensure(p);if not available then return {ok=false,reason=why}end
  if not fixtures[p] and (p:GetAttribute('RewardTestMode')==true or bridge.CanPersist and not bridge.CanPersist(p))then return {ok=false,reason='Restore your real save before granting quest rewards.'}end
  local flushed=flushInner(p);if not flushed.ok then return flushed end
  local op=payload(p,'adminRewards');op.questId=selector;op.adminOwner=315936607;op.bootstrap=bootstrap==true
  op.requestId=requestId or Http:GenerateGUID(false)
  local preview,validation=Engine.Apply(bridge.Profile(p),op)
  if not preview then return {ok=false,reason=validation,state=state(p,true)}end
  local pending={signature='adminRewards:'..selector,op=op};pendingOps[p]=pending
  local saved,answer=bridge.Transaction(p,{kind='questAdminRewards',quest=op})
  if not saved then
   if answer~='Save service is unavailable. Please try again.' and answer~='Save is busy. Please try again.'then pendingOps[p]=nil end
   return {ok=false,reason=answer,state=state(p,true)}
  end
  pendingOps[p]=nil;p:SetAttribute('QuestSaveStatus','Saved');push(p)
  return {ok=true,reward=type(answer)=='table'and answer.reward or nil,state=state(p,false)}
 end,false)
end
function Q.HasPending(p)local b=buffers[p];return pendingOps[p]~=nil or pendingLegacy[p]~=nil or b~=nil and (#b.events>0 or b.pending~=nil)end
function Q.Reset(p)pendingLegacy[p]=nil;dirty[p]=nil;buffers[p]=nil;pendingOps[p]=nil;displayRevs[p]=nil;nextPush[p]=nil end
function Q.SetFixture(p,enabled,timestamp)fixtures[p]=enabled and true or nil;overrides[p]=timestamp;Q.Reset(p)end
function Q.SetTime(p,timestamp)assert(fixtures[p] and finite(timestamp) and timestamp%1==0,'Invalid fixture clock');overrides[p]=timestamp;dirty[p]=true end
function Q.ClearContext(p,events)local op=payload(p,'progress');op.events=events;return op end
function Q.ProfileChanged(p)dirty[p]=true end
function Q.Profile(p)return bridge and bridge.Profile(p)end
function Q.Push(p)push(p)end
function Q.Bind(owner)
 assert(not bridge,'QuestService is already bound.');bridge=owner
 local function remote(name,class)
  local folder=RS:FindFirstChild('Quests');if not folder then folder=Instance.new('Folder');folder.Name='Quests';folder.Parent=RS end
  local item=folder:FindFirstChild(name);assert(not item or item.ClassName==class,'Wrong Quests remote class')
  if not item then item=Instance.new(class);item.Name=name;item.Parent=folder end;return item
 end
 changed=remote('StateChanged','RemoteEvent')
 local function rate(p,method)
  local n=nextRemote[p]or{};nextRemote[p]=n
  if os.clock()<(n[method]or 0)then return false end;n[method]=os.clock()+.5;return true
 end
 remote('GetState','RemoteFunction').OnServerInvoke=function(p)if not rate(p,'state')then return {ok=false,reason='Please wait.'}end;return Q.GetState(p)end
 remote('Claim','RemoteFunction').OnServerInvoke=function(p,tab,key)if not rate(p,'claim')then return {ok=false,reason='Please wait.'}end;return Q.Mutate(p,'claim',tab,key)end
 remote('ClaimAll','RemoteFunction').OnServerInvoke=function(p,tab,id)if not rate(p,'claimAll')then return {ok=false,reason='Please wait.'}end;return Q.Mutate(p,'claimAll',tab,nil,id)end
 remote('Reroll','RemoteFunction').OnServerInvoke=function(p,key)if not rate(p,'reroll')then return {ok=false,reason='Please wait.'}end;return Q.Mutate(p,'reroll',nil,key)end
 remote('Pin','RemoteFunction').OnServerInvoke=function(p,id)if not rate(p,'pin')then return {ok=false,reason='Please wait.'}end;return Q.Mutate(p,'pin',nil,id)end
 remote('EventBuy','RemoteFunction').OnServerInvoke=function(p,id)if not rate(p,'eventPurchase')then return {ok=false,reason='Please wait.'}end;return Q.Mutate(p,'eventPurchase','event',id)end
 remote('ShowHaunted','RemoteFunction').OnServerInvoke=function(p,show)
  if type(show)~='boolean'or not rate(p,'tag')then return {ok=false,reason='Invalid tag setting.'}end
  local ok,msg=bridge.Transaction(p,{kind='showHauntedTag',show=show});return {ok=ok,reason=not ok and msg or nil}
 end
 local adminApi=game:GetService('ServerStorage'):FindFirstChild('QuestAdminApi')or Instance.new('BindableFunction')
 adminApi.Name='QuestAdminApi';adminApi.Parent=game:GetService('ServerStorage')
 adminApi.OnInvoke=function(action,p,selector,id,bootstrap)
  if action=='catalog'then return Q.AdminCatalog(p)end
  if action=='grant'then return Q.AdminRewards(p,selector,id,bootstrap)end
  return {ok=false,reason='Unknown quest admin action.'}
 end
 local function joined(p)task.spawn(function()
  local result=Q.GetState(p)
  if result.ok then
   push(p)
   -- User requested all quest rewards. One durable owner-only grant, through the normal claim writer.
   if p.UserId==315936607 then
    for attempt=1,3 do
     local granted=Q.AdminRewards(p,'all','owner-quest-rewards-20261007',true)
     if granted.ok then p:SetAttribute('AdminQuestRewardsGranted',true);break end
     task.wait(attempt*2)
    end
   end
  end
 end)end
 Players.PlayerAdded:Connect(joined);for _,p in Players:GetPlayers()do joined(p)end
 Players.PlayerRemoving:Connect(function(p)
  local saved=Q.Flush(p)
  if saved then Q.Reset(p)end
  nextRemote[p]=nil;nextPush[p]=nil;displayRevs[p]=nil;fixtures[p]=nil;overrides[p]=nil
 end)
 game:BindToClose(function()
  local pending=0
  for p in buffers do pending+=1;task.spawn(function()Q.Flush(p);pending-=1 end)end
  local untilAt=os.clock()+25;while pending>0 and os.clock()<untilAt do task.wait(.1)end
 end)
 task.spawn(function()
  local ticks=0
  while true do task.wait(1);ticks+=1
   -- Departed players: retry their last quest save with backoff, one flush at a time, and give up after a few tries.
   -- Without a loaded profile nothing can be saved, so drop the buffer instead of re-reading the DataStore forever.
   if ticks%5==0 then for p in buffers do if p.Parent~=Players and not departFlushing[p] and os.clock()>=(departNext[p]or 0)then
    if not bridge.Profile(p)then Q.Reset(p);departTries[p]=nil;departNext[p]=nil
    else
     departFlushing[p]=true
     task.spawn(function()
      local saved=Q.Flush(p);departFlushing[p]=nil
      local tries=(departTries[p]or 0)+1
      if saved or tries>=6 then Q.Reset(p);departTries[p]=nil;departNext[p]=nil;if bridge.ReleaseDeparted then bridge.ReleaseDeparted(p)end
      else departTries[p]=tries;departNext[p]=os.clock()+math.min(120,10*2^tries)end
     end)
    end
   end end end
   for _,p in Players:GetPlayers()do
    local profile=bridge.Profile(p)
    if not locks[p] and profile and profile.Quests then
     local q=profile.Quests;local t=now(p)
     if q.daily.period~=math.floor(t/86400) or q.weekly.period~=math.floor((t+259200)/604800) then local result=Q.GetState(p);if result.ok then dirty[p]=true end end
     if dirty[p]then push(p)end
    end
   end
  end
 end)
end
return Q
