-- Pure profile operations. All ownership, generation and lease checks also run in UpdateAsync.
local M={}
local MAX_SLOTS,MAX_COUNT,MAX_ID=3,1000000000000,9007199254740991
local function integer(v,min,max)return type(v)=='number'and v==v and v%1==0 and v>=min and v<=max end
local function text(v,max)return type(v)=='string'and #v<=max and utf8.len(v)~=nil end
local function index(v)return integer(v,1,MAX_SLOTS)end
local function members(values)
 local result={}
 if type(values)=='table'then for _,entry in ipairs(values)do
  if #result>=16 then break end
  if text(entry,64)then table.insert(result,{displayName=entry})
  elseif type(entry)=='table'and text(entry.displayName or entry.name,64)then
   local row={displayName=entry.displayName or entry.name}
   if integer(entry.userId,1,MAX_ID)then row.userId=entry.userId end
   -- Optional fields migrate legacy saves without inventing historical damage.
   if row.userId and type(entry.health)=='number'and entry.health==entry.health and math.abs(entry.health)<math.huge then
    local maximum=entry.maxHealth
    if type(maximum)~='number'or maximum~=maximum or math.abs(maximum)==math.huge then maximum=100 end
    row.maxHealth=math.clamp(maximum,1,10000)
    row.health=math.clamp(entry.health,0,row.maxHealth)
   end
   table.insert(result,row)
  end
 end end
 return result
end
-- Gear shop: unused gear as a short list of {id, charges}; ids are re-validated by GearShopServer on load.
local function gearList(values)
 local result={}
 if type(values)=='table'then for _,entry in ipairs(values)do
  if #result>=24 then break end
  if type(entry)=='table'and text(entry.id,32)and #entry.id>0 and integer(entry.charges or 0,0,99)then table.insert(result,{id=entry.id,charges=entry.charges or 0})end
 end end
 return result
end
-- Map types this save has played in the current cycle (no repeats until all are seen). Additive: older saves
-- without the field load with an empty list.
local function kindList(values)
 local result,seen={},{}
 if type(values)=='table'then for _,entry in ipairs(values)do
  if #result>=16 then break end
  if text(entry,32)and #entry>0 and not seen[entry]then seen[entry]=true;table.insert(result,entry)end
 end end
 return result
end
local function slot(value)
 if type(value)~='table'or not text(value.name,40)or #value.name==0 or not integer(value.round,1,1000000)or not integer(value.quota,0,MAX_COUNT)or not integer(value.sold,0,MAX_COUNT)then return nil end
 if not text(value.runId or '',160)or not text(value.mapKind or '',64)or not integer(value.createdAt,0,MAX_COUNT)or not integer(value.updatedAt,0,MAX_COUNT)then return nil end
 local seed=value.mapSeed
 if seed~=nil and seed~=false and not integer(seed,0,MAX_ID)then return nil end
 -- Chances: failed runs left before the slot is deleted (older saves without the field get the full 3).
 local chances=value.chances;if chances==nil then chances=3 end
 if not integer(chances,1,3)then return nil end
 return {chances=chances,name=value.name,round=value.round,quota=value.quota,sold=value.sold,runId=value.runId or '',mapKind=value.mapKind or '',mapSeed=seed or false,createdAt=value.createdAt,updatedAt=value.updatedAt,members=members(value.members),bank=integer(value.bank,0,MAX_COUNT)and value.bank or 0,gear=gearList(value.gear),mapsSeen=kindList(value.mapsSeen)}
end
function M.Reconcile(old)
 if old~=nil and type(old)~='table'then return nil,'Invalid run-save profile.'end
 if old and old.version~=nil and old.version~=1 then return nil,'Unsupported run-save version.'end
 local d={version=1,slots={false,false,false},generations={0,0,0},leases={},terminals={},selection=false,usedSlots={false,false,false}}
 if not old then return d end
 for i=1,MAX_SLOTS do
  local value=type(old.slots)=='table'and(old.slots[i]or old.slots[tostring(i)])
  if value then local clean=slot(value);if not clean then return nil,'Invalid saved slot '..i..'.'end;d.slots[i]=clean end
  local generation=type(old.generations)=='table'and(old.generations[i]or old.generations[tostring(i)])
  d.generations[i]=integer(generation,0,MAX_COUNT)and generation or (d.slots[i]and 1 or 0)
  d.usedSlots[i]=type(old.usedSlots)=='table'and(old.usedSlots[i]==true or old.usedSlots[tostring(i)]==true)or false
  local lease=type(old.leases)=='table'and(old.leases[tostring(i)]or old.leases[i])or nil
  if lease~=nil then
   if type(lease)~='table'or not text(lease.token,100)or #lease.token==0 or not text(lease.serverId,100)or not text(lease.launchToken,160)or not integer(lease.generation,0,MAX_COUNT)or not integer(lease.expiresAt,0,MAX_COUNT)or(lease.stage~='reserved'and lease.stage~='active')or(lease.mode~='new'and lease.mode~='load')then return nil,'Invalid run-save lease.'end
   d.leases[tostring(i)]={token=lease.token,serverId=lease.serverId,launchToken=lease.launchToken,generation=lease.generation,expiresAt=lease.expiresAt,stage=lease.stage,mode=lease.mode,lastFail=text(lease.lastFail,160)and lease.lastFail or nil}
  end
  local terminal=type(old.terminals)=='table'and(old.terminals[tostring(i)]or old.terminals[i])
  if terminal then
   if type(terminal)~='table'or not text(terminal.token,100)or not integer(terminal.generation,0,MAX_COUNT)or(terminal.kind~='save'and terminal.kind~='release'and terminal.kind~='invalidate')then return nil,'Invalid terminal run-save marker.'end
   d.terminals[tostring(i)]={token=terminal.token,generation=terminal.generation,kind=terminal.kind}
  end
 end
 local selected=old.selection
 if selected and type(selected)=='table'and index(selected.slotIndex)and integer(selected.generation,0,MAX_COUNT)and text(selected.token,100)and #selected.token>0 and(selected.mode=='new'or selected.mode=='load')then
  d.selection={slotIndex=selected.slotIndex,generation=selected.generation,token=selected.token,mode=selected.mode}
 end
 return d
end
local function leased(d,i,now)local lease=d.leases[tostring(i)];return lease and lease.expiresAt>now end
local function writer(d,op)
 local lease=d.leases[tostring(op.slotIndex)]
 return lease and lease.expiresAt>op.now and lease.stage=='active'and lease.serverId==op.serverId and lease.token==op.token and lease.generation==op.generation and d.generations[op.slotIndex]==op.generation and d.slots[op.slotIndex]
end
function M.Apply(old,op)
 local d,err=M.Reconcile(old);if not d then return nil,err end
 if type(op)~='table'or not index(op.slotIndex)or not integer(op.now,0,MAX_COUNT)or not integer(op.ownerUserId,1,MAX_ID)then return nil,'Invalid run-save operation.'end
 local i=op.slotIndex;local key=tostring(i)
 if op.kind=='create'or op.kind=='delete'or op.kind=='select'or op.kind=='reserve'then
  if op.actorUserId~=op.ownerUserId then return nil,'Only the owner can edit run saves.'end
 end
 if op.kind=='create'then
  if leased(d,i,op.now)then return nil,'This slot is in use.'end
  if d.slots[i]then return nil,'Choose an empty slot.'end
  if not text(op.name,40)or #op.name==0 or not op.name:find('%S')then return nil,'Use a save name of 1-40 characters.'end
  d.generations[i]+=1;d.usedSlots[i]=false;d.leases[key]=nil
  d.slots[i]={chances=3,name=op.name,round=1,quota=0,sold=0,runId='',mapKind='',mapSeed=false,createdAt=op.now,updatedAt=op.now,members={},mapsSeen={}}
 elseif op.kind=='delete'then
  if leased(d,i,op.now)then return nil,'This slot is in use.'end
  d.slots[i]=false;d.generations[i]+=1;d.usedSlots[i]=false;d.leases[key]=nil
  if d.selection and d.selection.slotIndex==i then d.selection=false end
 elseif op.kind=='select'then
  if not d.slots[i]then return nil,'Create this save first.'end
  if leased(d,i,op.now)then return nil,'This slot is in use.'end
  if op.mode~='new'and op.mode~='load'then return nil,'Choose NEW or LOAD.'end
  if op.mode=='new'and(d.usedSlots[i]or d.slots[i].round~=1 or d.slots[i].runId~='')then return nil,'This run already started. Choose LOAD.'end
  if not text(op.token,100)or #op.token==0 then return nil,'Invalid selection token.'end
  d.selection={slotIndex=i,generation=d.generations[i],token=op.token,mode=op.mode}
 elseif op.kind=='reserve'then
  local chosen=d.selection
  if not chosen or chosen.slotIndex~=i or chosen.token~=op.token or chosen.generation~=op.generation or chosen.mode~=op.mode or not d.slots[i]or d.generations[i]~=op.generation then return nil,'Save selection changed.'end
  if not text(op.launchToken,160)or #op.launchToken==0 or not text(op.serverId,100)or not integer(op.expiresAt,op.now+1,MAX_COUNT)then return nil,'Invalid launch reservation.'end
  for n=1,MAX_SLOTS do if leased(d,n,op.now)then
   local lease=d.leases[tostring(n)]
   if n~=i or lease.stage~='reserved'or lease.token~=op.token or lease.launchToken~=op.launchToken or lease.serverId~=op.serverId then return nil,'This owner already has a run in use.'end
  end end
  d.leases[key]={token=op.token,serverId=op.serverId,launchToken=op.launchToken,generation=op.generation,expiresAt=op.expiresAt,stage='reserved',mode=op.mode}
 elseif op.kind=='acquire'then
  local lease=d.leases[key]
  if not lease or lease.expiresAt<=op.now or lease.token~=op.token or lease.launchToken~=op.launchToken or lease.generation~=op.generation or lease.mode~=op.mode or d.generations[i]~=op.generation or not d.slots[i]then return nil,'Launch reservation expired or changed.'end
  if lease.stage=='active'and lease.serverId~=op.serverId then return nil,'Another mission owns this run.'end
  if not text(op.serverId,100)or #op.serverId==0 or not integer(op.expiresAt,op.now+1,MAX_COUNT)then return nil,'Invalid mission lease.'end
  lease.stage='active';lease.serverId=op.serverId;lease.expiresAt=op.expiresAt;d.usedSlots[i]=true
 elseif op.kind=='cancel'then
  local lease=d.leases[key]
  if lease and lease.stage=='reserved'and lease.token==op.token and lease.launchToken==op.launchToken and lease.generation==op.generation and d.generations[i]==op.generation then d.leases[key]=nil end
 elseif op.kind=='checkpoint'or op.kind=='fail'then
  -- Mid-mission writes: the lease stays active so the run keeps saving afterwards.
  if not writer(d,op)then return nil,'Mission lease expired or changed.'end
  if not integer(op.expiresAt,op.now+1,MAX_COUNT)then return nil,'Invalid lease renewal.'end
  local lease=d.leases[key]
  if op.kind=='checkpoint'then
   local input=op.snapshot
   if type(input)~='table'then return nil,'Invalid run snapshot.'end
   local oldSlot=d.slots[i]
   local clean=slot({chances=oldSlot.chances,name=oldSlot.name,createdAt=oldSlot.createdAt,updatedAt=op.now,round=input.round,quota=input.quota,sold=input.sold,runId=input.runId,mapKind=input.mapKind,mapSeed=input.mapSeed,members=input.members,bank=input.bank,gear=input.gear,mapsSeen=input.mapsSeen})
   if not clean then return nil,'Invalid run snapshot.'end
   d.slots[i]=clean;lease.expiresAt=op.expiresAt
  else
   -- One failed attempt at the saved level costs one chance; failId makes a retried write count once.
   if not text(op.failId,160)or #op.failId==0 then return nil,'Invalid failure id.'end
   if lease.lastFail==op.failId then return d,'Already counted.'end
   local left=(d.slots[i].chances or 3)-1
   if left>0 then d.slots[i].chances=left
   else
    -- Last chance gone: the slot becomes a brand-new save (same name, level 1, 3 chances) and this mission keeps writing to it.
    local old=d.slots[i]
    d.slots[i]={chances=3,name=old.name,round=1,quota=0,sold=0,runId='',mapKind='',mapSeed=false,createdAt=op.now,updatedAt=op.now,members={},mapsSeen={}}
   end
   lease.lastFail=op.failId;lease.expiresAt=op.expiresAt
  end
 elseif op.kind=='renew'or op.kind=='save'or op.kind=='release'or op.kind=='invalidate'then
  local prior=d.terminals[key]
  if op.kind~='renew'and prior and prior.token==op.token and prior.generation==op.generation and prior.kind==op.kind then return d,'Already finalized.'end
  if not writer(d,op)then return nil,'Mission lease expired or changed.'end
  if op.kind=='renew'then
   if not integer(op.expiresAt,op.now+1,MAX_COUNT)then return nil,'Invalid lease renewal.'end
   d.leases[key].expiresAt=op.expiresAt
  elseif op.kind=='save'then
   local input=op.snapshot
   if type(input)~='table'then return nil,'Invalid run snapshot.'end
   local oldSlot=d.slots[i]
   local clean=slot({chances=oldSlot.chances,name=oldSlot.name,createdAt=oldSlot.createdAt,updatedAt=op.now,round=input.round,quota=input.quota,sold=input.sold,runId=input.runId,mapKind=input.mapKind,mapSeed=input.mapSeed,members=input.members,bank=input.bank,gear=input.gear,mapsSeen=input.mapsSeen})
   if not clean then return nil,'Invalid run snapshot.'end
   d.slots[i]=clean;d.leases[key]=nil
  elseif op.kind=='release'then d.leases[key]=nil
  else
   -- A failed run uses one chance; the slot keeps its last good save until the chances run out.
   local left=(d.slots[i].chances or 3)-1
   if left>0 then d.slots[i].chances=left;d.leases[key]=nil
   else
    d.slots[i]=false;d.generations[i]+=1;d.usedSlots[i]=false;d.leases[key]=nil
    if d.selection and d.selection.slotIndex==i then d.selection=false end
   end
  end
  if op.kind~='renew'then d.terminals[key]={token=op.token,generation=op.generation,kind=op.kind}end
 else return nil,'Unknown run-save operation.'end
 return d,'Run save updated.'
end
function M.NormalizeSnapshot(value)
 if type(value)~='table'then return nil,'Invalid run snapshot.'end
 local clean=slot({name='Run',createdAt=0,updatedAt=0,round=value.round,quota=value.quota,sold=value.sold,runId=value.runId,mapKind=value.mapKind,mapSeed=value.mapSeed,members=value.members,bank=value.bank,gear=value.gear,mapsSeen=value.mapsSeen})
 return clean,not clean and 'Invalid run snapshot.'or nil
end
function M.Snapshot(old)
 local d,err=M.Reconcile(old);if not d then return nil,err end
 local rows={false,false,false}
 -- Names shown are always "Run N": older saves may hold a client-sent name that was never text-filtered.
 for i,value in ipairs(d.slots)do if value then rows[i]={index=i,chances=value.chances,name='Run '..i,round=value.round,quota=value.quota,sold=value.sold,updatedAt=value.updatedAt,members=members(value.members)}end end
 return {slots=rows,selected=d.selection and d.selection.slotIndex or false}
end
return M

