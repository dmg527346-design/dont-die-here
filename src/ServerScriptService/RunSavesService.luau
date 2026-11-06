-- One module owns run-slot DataStore writes, mission lease renewal and exit/shutdown flush.
-- ProgressService is independent and is never required or modified here.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local DSS=game:GetService('DataStoreService')
local Http=game:GetService('HttpService')
local Core=require(script.Parent:WaitForChild('RunSavesCore'))
-- Unpublished review copies never construct external stores; published games keep their existing path.
local LOCAL_REVIEW=Run:IsStudio()and game.PlaceId==0 and game.GameId==0
local STUDIO_MEMORY=LOCAL_REVIEW or game:GetService('RunService'):IsStudio()and workspace:GetAttribute('StudioDataStores')~=true -- Studio playtests keep saves in memory: stopping during a DataStore call hangs Studio. Workspace StudioDataStores=true tests real saves
local store
if not STUDIO_MEMORY then store=DSS:GetDataStore('RunSaves_v1'..(Run:IsStudio()and '_Studio'or ''))end
local M={}
local SERVER_ID=game.JobId~=''and game.JobId or Http:GenerateGUID(false)
local RESERVATION_SECONDS,LEASE_SECONDS,RENEW_SECONDS=300,180,45
local MAX_ID=9007199254740991
local selections,busy={},{}
local context,snapshotProvider,finishing,finished,starting,pendingTerminal
local captureTerminal,flushTerminal
local lastHealthDecision,healthDirty,healthScheduled
local healthCacheEpoch=0
local refreshHealthDecision
local departedHealth={}
local departedPlayers=setmetatable({},{__mode="k"})
local restoreReturningMember,applyRunHealth
local function now()return DateTime.now().UnixTimestamp end
-- Studio multi-client tests: test players have UserId<=0 (-1, -2, ...). They get a temporary save kept in server
-- memory only (seeded with one "Studio Test" slot), stored under a positive stand-in key so RunSavesCore stays unchanged.
-- Real players and live servers never take this path.
local STUDIO=Run:IsStudio()
local TEST_KEY_BASE=MAX_ID-100000
local memory={}
local function testId(id)return STUDIO and type(id)=='number'and id%1==0 and id<=0 and id>=-1000 end
local function storageKey(id)if testId(id)then return TEST_KEY_BASE-id end;return id end
local function ownerId(p)
 if not(typeof(p)=='Instance'and p:IsA('Player')and p.Parent==Players)then return nil end
 local id=p.UserId
 return(id>0 and id<=MAX_ID or testId(id))and id or nil
end
local function validId(id)return type(id)=='number'and id==id and id%1==0 and(id>0 and id<=MAX_ID or testId(id))end
local function testProfile(id)
 if memory[id]==nil then
  local key=storageKey(id)
  local seeded=Core.Apply(nil,{kind='create',ownerUserId=key,actorUserId=key,slotIndex=1,name='Studio Test',now=DateTime.now().UnixTimestamp})
  memory[id]=Http:JSONEncode(seeded)
 end
 return Http:JSONDecode(memory[id])
end
local function transact(id,op)
 if not validId(id)then return false,'Invalid run owner.'end
 local finish=os.clock()+15
 while busy[id]and os.clock()<finish do task.wait(.05)end
 if busy[id]then return false,'Run save is busy.'end
 busy[id]=true;local result,message,failure
 for attempt=1,3 do
  local key=storageKey(id)
  op.ownerUserId=key;op.now=now();if op.actorUserId==id then op.actorUserId=key end
  local ok,value
  if STUDIO_MEMORY or testId(id)then -- Same Core rules; unpublished review and synthetic tests are session-only
   ok=true;local nextValue,msg=Core.Apply(testProfile(id),op);message=msg
   if nextValue~=nil then memory[id]=Http:JSONEncode(nextValue)end;value=nextValue
  else
   ok,value=pcall(function()assert(store,'Persistence store is not available');return store:UpdateAsync(tostring(id),function(old)
    local nextValue,msg=Core.Apply(old,op);message=msg;return nextValue
   end,{id})end)
  end
  if ok then result=value;failure=nil;break end
  failure=value;if attempt<3 then task.wait(attempt)end
 end
 busy[id]=nil
 if result then return true,message,result end
 return false,failure and 'Run-save storage is unavailable. Please try again.'or message or 'Could not update run save.'
end
local function read(id)
 if not validId(id)then return nil,'Invalid run owner.'end
 if STUDIO_MEMORY or testId(id)then return Core.Reconcile(testProfile(id))end
 local options=Instance.new('DataStoreGetOptions');options.UseCache=false
 local ok,value=pcall(function()assert(store,'Persistence store is not available');return store:GetAsync(tostring(id),options)end)
 if not ok then return nil,'Run-save storage is unavailable. Please try again.'end
 return Core.Reconcile(value)
end
local function ticket(id,selection,launchToken)
 return {ownerUserId=id,slotIndex=selection.slotIndex,generation=selection.generation,token=selection.token,mode=selection.mode,launchToken=launchToken}
end
local function publish(p,d)
 if p and p.Parent==Players then p:SetAttribute('RunSaveSelected',d.selection and d.selection.slotIndex or nil)end
 return Core.Snapshot(d)
end
function M.List(p)
 local id=ownerId(p);if not id then return false,'Player unavailable.'end
 local d,err=read(id);if not d then return false,err end
 if d.selection then selections[p]=ticket(id,d.selection)else selections[p]=nil end
 return true,publish(p,d)
end
function M.Create(p,i,name)
 local id=ownerId(p);if not id then return false,'Player unavailable.'end
 -- Save names are always set by the server ("Run 3"): they are shown to the whole party, so no client text is stored.
 local ok,msg,d=transact(id,{kind='create',actorUserId=id,slotIndex=i,name=type(i)=='number'and i%1==0 and('Run '..i)or''})
 return ok,ok and publish(p,d)or msg
end
function M.Delete(p,i)
 local id=ownerId(p);if not id then return false,'Player unavailable.'end
 local ok,msg,d=transact(id,{kind='delete',actorUserId=id,slotIndex=i})
 if ok and selections[p]and selections[p].slotIndex==i then selections[p]=nil end
 return ok,ok and publish(p,d)or msg
end
function M.Select(p,i,mode)
 local id=ownerId(p);if not id then return false,'Player unavailable.'end
 local chosen=Http:GenerateGUID(false)
 local ok,msg,d=transact(id,{kind='select',actorUserId=id,slotIndex=i,mode=mode or 'load',token=chosen})
 if not ok then return false,msg end
 selections[p]=ticket(id,d.selection)
 return true,publish(p,d)
end
function M.ValidateChoice(p,save)
 if type(save)~='table'or(save.mode~='new'and save.mode~='load')then return false,'Choose NEW or LOAD and a save slot.'end
 local ok,value=M.Select(p,save.slot,save.mode)
 if not ok then return false,value end
 return true,M.GetSelection(p)
end
function M.GetSelection(p)
 local selected=selections[p]
 return selected and table.clone(selected)or nil
end
function M.PrepareLaunch(p,launchToken)
 local id=ownerId(p);local selected=selections[p]
 if not id or not selected or selected.ownerUserId~=id then return false,'Choose a run save before starting.'end
 local ok,msg,d=transact(id,{kind='reserve',actorUserId=id,slotIndex=selected.slotIndex,generation=selected.generation,token=selected.token,mode=selected.mode,launchToken=launchToken,serverId=SERVER_ID,expiresAt=now()+RESERVATION_SECONDS})
 if not ok then return false,msg end
 return true,ticket(id,d.selection,launchToken)
end
function M.CancelLaunch(value)
 if type(value)~='table'then return false,'Invalid launch ticket.'end
 return transact(value.ownerUserId,{kind='cancel',slotIndex=value.slotIndex,generation=value.generation,token=value.token,launchToken=value.launchToken})
end
local function missionOp(kind,snapshot,failId)
 if not context or finished then return false,'No active run-save session.'end
 return transact(context.ownerUserId,{kind=kind,slotIndex=context.slotIndex,generation=context.generation,token=context.token,serverId=SERVER_ID,expiresAt=now()+LEASE_SECONDS,snapshot=snapshot,failId=failId})
end
-- Cache synchronously before disconnect/Stop teardown strips mission state and character.
function M.BlockHealthCache()
 lastHealthDecision=nil;healthDirty=false;healthScheduled=false;healthCacheEpoch+=1
end
refreshHealthDecision=function()
 if not context or finished or finishing or pendingTerminal or not snapshotProvider then return nil end
 local owner
 for _,p in ipairs(context.members or {})do if p.UserId==context.ownerUserId then owner=p;break end end
 if not owner then owner=Players:GetPlayerByUserId(context.ownerUserId)end
 if not owner then return nil end
 local ok,value=pcall(snapshotProvider,owner)
 if ok and type(value)=='table'then
  if value.delete==true then lastHealthDecision={delete=true};healthDirty=false;return lastHealthDecision end
  local clean=Core.NormalizeSnapshot(value)
  if clean then lastHealthDecision=clean;return clean end
 end
 return nil
end
function M.MarkHealthChanged(p)
 if not context or finished or finishing or pendingTerminal then return end
 local member=false
 for _,candidate in ipairs(context.members or {})do if candidate==p then member=true;break end end
 if not member then return end
 local decision=refreshHealthDecision()
 if not decision or decision.delete==true then return end
 healthDirty=true
 if healthScheduled then return end
 healthScheduled=true
 local epoch=healthCacheEpoch
 -- Roblox allows one write per key every 6 s; health regen alone changes health constantly, so batch it.
 task.delay(20,function()
  if epoch~=healthCacheEpoch then return end
  healthScheduled=false
  if not healthDirty or finished or finishing or pendingTerminal then return end
  refreshHealthDecision()
  local latest=lastHealthDecision
  if not latest or latest.delete==true then healthDirty=false;return end
  healthDirty=false
  local ok=M.Checkpoint(latest)
  if not ok and not finished and not pendingTerminal and epoch==healthCacheEpoch then healthDirty=true end
 end)
end
-- Save progress now and keep playing (called at the start of every level).
function M.Checkpoint(snapshot)
 if pendingTerminal or finishing then return false,'Run save is being finalized.'end
 local clean,err=Core.NormalizeSnapshot(snapshot);if not clean then return false,err end
 lastHealthDecision=clean;healthDirty=false
 local ok,msg,d=missionOp('checkpoint',clean)
 if ok and d and d.slots[context.slotIndex]then context.slot=d.slots[context.slotIndex]end
 return ok,msg
end
-- A failed attempt: spend one chance and keep the run (deleted on the last chance). Returns ok, chances left.
function M.FailChance(failId)
 if pendingTerminal or finishing then return false,'Run save is being finalized.'end
 M.BlockHealthCache()
 local ok,msg,d=missionOp('fail',nil,failId)
 if not ok then return false,msg end
 local kept=d and d.slots[context.slotIndex]
 if kept then
  local reset=msg~='Already counted.'and(context.slot and context.slot.chances or 2)<=1 -- the last chance just turned it into a new save
  context.slot=kept;return true,kept.chances,reset
 end
 finished=true -- the slot is gone; nothing more to write this mission
 local p=Players:GetPlayerByUserId(context.ownerUserId);if p then p:SetAttribute('RunSaveStatus','ChanceUsed')end
 return true,0
end
-- Health travels in the existing run snapshot and lease, never through a second writer.
function M.CaptureMembers()
 local rows,seen={},{}
 if not context then return rows end
 for memberIndex,p in ipairs(context.members or {})do
  local id=p.UserId
  local current=Players:GetPlayerByUserId(id)
  if current and current~=p and current:GetAttribute('MissionActive')==true and restoreReturningMember then
   restoreReturningMember(current);p=context.members[memberIndex]
  end
  if validId(id)and not seen[id]and #rows<16 then
   local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
   local health=h and h.Health or p:GetAttribute('RecoverySessionHealth')
   table.insert(rows,departedHealth[id]and table.clone(departedHealth[id])or {userId=id,displayName=p.DisplayName,health=health,maxHealth=h and h.MaxHealth or 100})
   seen[id]=true
  end
 end
 -- Retain a saved teammate who is absent from this particular launch.
 for _,row in ipairs(context.slot and context.slot.members or {})do
  if row.userId and not seen[row.userId]and #rows<16 then table.insert(rows,table.clone(row));seen[row.userId]=true end
 end
 return rows
end
applyRunHealth=function(p,slot,mode)
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 local maximum=h and h.MaxHealth or 100
 local health=maximum
 if mode=='load'then
  for _,row in ipairs(slot.members or {})do if row.userId==p.UserId and type(row.health)=='number'and row.health>0 then health=math.clamp(row.health,0,maximum);break end end
 end
 p:SetAttribute('RecoverySessionHealth',health)
 if h and h.Health>0 then h.Health=health end
end
restoreReturningMember=function(p)
 -- Membership/admission belongs to the existing lobby/mission system, never to health.
 if not context or finished or pendingTerminal or p.Parent~=Players or p:GetAttribute('MissionActive')~=true then return false end
 local memberIndex
 for i,old in ipairs(context.members or {})do if old.UserId==p.UserId then
  if old==p then return false end
  memberIndex=i;break
 end end
 if not memberIndex then return false end
 local row=departedHealth[p.UserId]
 if not row then
  for _,saved in ipairs(lastHealthDecision and lastHealthDecision.members or context.slot and context.slot.members or {})do
   if saved.userId==p.UserId then row=saved;break end
  end
 end
 context.members[memberIndex]=p
 departedHealth[p.UserId]=nil
 applyRunHealth(p,{members=row and {row}or {}},'load')
 return true
end
local function watchReturningPlayer(p)
 p:GetAttributeChangedSignal('MissionActive'):Connect(function()restoreReturningMember(p)end)
 restoreReturningMember(p)
end
local function recordDepartingMember(p)
 if not context or finished or pendingTerminal or p.UserId==context.ownerUserId then return end
 local admitted=false
 for _,member in ipairs(context.members or {})do if member==p then admitted=true;break end end
 if not admitted then return end
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 departedHealth[p.UserId]={userId=p.UserId,displayName=p.DisplayName,health=h and h.Health or p:GetAttribute('RecoverySessionHealth'),maxHealth=h and h.MaxHealth or 100}
 local decision=refreshHealthDecision()
 if not decision and lastHealthDecision and lastHealthDecision.delete~=true then
  local patched=table.clone(lastHealthDecision);patched.members=M.CaptureMembers()
  decision=Core.NormalizeSnapshot(patched)
  if decision then lastHealthDecision=decision end
 end
 if decision and decision.delete~=true then M.Checkpoint(decision)end
end
function M.BeginMission(id,value,partyMembers)
 if starting or finishing or context and not finished then return false,'The previous run save is still being finalized. Please try again.'end
 -- A completed terminal transaction releases the lease; a later Studio launch may acquire a fresh context.
 -- Keep the existing round owner's snapshot callback, but discard all previous-run terminal/cache state.
 if context then
  context=nil;pendingTerminal=nil;finished=false
  M.BlockHealthCache();departedHealth={};departedPlayers=setmetatable({},{__mode='k'})
 end
 if type(value)~='table'or value.ownerUserId~=id or(value.mode~='new'and value.mode~='load')then return false,'Invalid mission run-save ticket.'end
 local boundOwner
 if type(partyMembers)=='table'then for _,member in ipairs(partyMembers)do if ownerId(member)==id then boundOwner=member;break end end end
 if not boundOwner then return false,'The party owner must be present in the mission.'end
 starting=true
 local ok,msg,d=transact(id,{kind='acquire',slotIndex=value.slotIndex,generation=value.generation,token=value.token,mode=value.mode,launchToken=value.launchToken,serverId=SERVER_ID,expiresAt=now()+LEASE_SECONDS})
 starting=false
 if not ok then return false,msg end
 context={ownerUserId=id,slotIndex=value.slotIndex,generation=value.generation,token=value.token,mode=value.mode,slot=d.slots[value.slotIndex],members=partyMembers or {}}
 finished=false
 M.BlockHealthCache()
 departedHealth={}
 for _,member in ipairs(context.members)do applyRunHealth(member,context.slot,context.mode)end
 if ownerId(boundOwner)~=id then
  captureTerminal(boundOwner,nil);flushTerminal()
  return false,'The party owner left before the run could start.'
 end
 return true,M.GetMissionContext()
end
function M.GetMissionContext()
 if not context then return nil end
 -- Return an independent canonical copy; consumers cannot mutate the private lease identity.
 local profile=Core.Reconcile({version=1,slots={[context.slotIndex]=context.slot}})
 return {ownerUserId=context.ownerUserId,slotIndex=context.slotIndex,mode=context.mode,slot=profile.slots[context.slotIndex]}
end
function M.RegisterSnapshot(callback)
 assert(type(callback)=='function','Run-save snapshot provider must be a function')
 assert(not snapshotProvider or snapshotProvider==callback,'Run-save snapshot provider already registered')
 snapshotProvider=callback
 refreshHealthDecision()
end
captureTerminal=function(p,decision)
 if pendingTerminal then return end
 -- A current genuine-death decision always beats an earlier living snapshot.
 if decision==nil then decision=lastHealthDecision end
 local kind=type(decision)=='table'and decision.delete==true and 'invalidate'or type(decision)=='table'and 'save'or 'release'
 local clean,err
 if kind=='save'then clean,err=Core.NormalizeSnapshot(decision)end
 pendingTerminal={owner=p,kind=kind,snapshot=clean,error=err,attempts=0,retryUntil=os.clock()+25}
end
flushTerminal=function()
 if not pendingTerminal or finished then return finished==true end
 if finishing then return false,'Run save is being finalized.'end
 finishing=true
 local pending=pendingTerminal;pending.attempts+=1
 local ok,msg
 if pending.error then ok,msg=false,pending.error else ok,msg=missionOp(pending.kind,pending.snapshot)end
 if ok then finished=true;M.BlockHealthCache()end
 finishing=false
 local p=pending.owner
 if p and p.Parent==Players then p:SetAttribute('RunSaveStatus',ok and(pending.kind=='invalidate'and 'ChanceUsed'or pending.kind=='save'and 'Saved'or 'Preserved')or tostring(msg))end
 if not ok and pending.attempts<3 and os.clock()<pending.retryUntil then task.delay(3,function()if not finished then flushTerminal()end end)end
 return ok,msg
end
function M.InvalidateMissionSlot(force)
 if not context or finished then return false,'No active run-save session.'end
 if pendingTerminal then
  if pendingTerminal.kind=='invalidate'then return flushTerminal()end
  return false,'Run already has a terminal decision.'
 end
 local p=Players:GetPlayerByUserId(context.ownerUserId)
 if not p or not snapshotProvider then return false,'Run owner snapshot is unavailable.'end
 -- Recovery is the authority for genuine death vs map-rebuild RoundDead placeholders.
 local ok,decision=pcall(snapshotProvider,p)
 -- force: the whole run failed (team wipe / timer), which always costs one chance.
 if force then decision={delete=true}
 elseif not ok or type(decision)~='table'or decision.delete~=true then return false,'Run owner has not ended dead.'end
 captureTerminal(p,decision) -- Freeze before the first storage yield or automatic respawn.
 return flushTerminal()
end
local function finishMission(p)
 if not context or finished or not p or p.UserId~=context.ownerUserId then return end
 if not pendingTerminal then
  local decision
  if snapshotProvider then local ok,value=pcall(snapshotProvider,p);if ok then decision=value end end
  captureTerminal(p,decision)
 end
 return flushTerminal()
end
Players.PlayerAdded:Connect(watchReturningPlayer)
for _,p in Players:GetPlayers()do watchReturningPlayer(p)end
-- A failed same-session deployment never spends a chance or checkpoints partial world state.
function M.AbortMissionStart()
 if not context or finished then return true end
 if not pendingTerminal then
  M.BlockHealthCache()
  pendingTerminal={owner=Players:GetPlayerByUserId(context.ownerUserId),kind='release',attempts=0,retryUntil=os.clock()+25}
 end
 return flushTerminal()
end
function M.DepartMission(p)
 if context and departedPlayers[p]==context then return true end
 if context then departedPlayers[p]=context end
 recordDepartingMember(p)
 if context and p.UserId==context.ownerUserId then finishMission(p)end
 selections[p]=nil
 return true
end
Players.PlayerRemoving:Connect(M.DepartMission)
game:BindToClose(function()
 if game:GetService('RunService'):IsStudio() then return end -- Studio stop: close-time saves can hang the server shutdown
 local deadline=os.clock()+25
 if not context or finished then return end
 if not pendingTerminal then local p=Players:GetPlayerByUserId(context.ownerUserId);if p then finishMission(p)end end
 while finishing and not finished and os.clock()<deadline do task.wait(.05)end
 -- The cached decision and owner reference survive PlayerRemoving and automatic respawn.
 if pendingTerminal and not finished and not finishing and os.clock()<deadline then flushTerminal()end
 while finishing and not finished and os.clock()<deadline do task.wait(.05)end
end)
task.spawn(function()
 while true do
  task.wait(RENEW_SECONDS)
  if context and not finished and not finishing and not pendingTerminal then missionOp('renew')end
 end
end)
return M

