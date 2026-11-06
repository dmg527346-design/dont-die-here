-- Owner-only admin powers (god mode, speed, jump, items, monsters, rounds, cosmetics).
-- Client: StarterPlayerScripts.AdminPowersClient. Every request is checked against OWNER_USER_ID here;
-- the mission-side scripts expose BindableFunctions (CursedItemAdminApi, CreatureAdminApi,
-- RecoveryAdminApi) that only exist on a running mission server.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local OWNER_USER_ID=315936607
local Access=require(script.Parent:WaitForChild('AdminAccess'))
local SPEED_MIN,SPEED_MAX=4,200
local JUMP_MIN,JUMP_MAX=0,250
local DEFAULT_JUMP=game.StarterPlayer.CharacterJumpHeight
local event=RS:FindFirstChild('AdminPowersEvent') or Instance.new('RemoteEvent');event.Name='AdminPowersEvent';event.Parent=RS
-- Owner-only settings that must survive the lobby -> mission teleport (separate from player progress saves).
local LOCAL_REVIEW=game:GetService('RunService'):IsStudio()and game.PlaceId==0 and game.GameId==0
local STUDIO_MEMORY=LOCAL_REVIEW or game:GetService('RunService'):IsStudio()and workspace:GetAttribute('StudioDataStores')~=true -- Studio playtests keep saves in memory: stopping during a DataStore call hangs Studio. Workspace StudioDataStores=true tests real saves
local settingsStore
if not STUDIO_MEMORY then settingsStore=game:GetService('DataStoreService'):GetDataStore('DDH_AdminSettings_v1'..(game:GetService('RunService'):IsStudio() and '_Studio' or ''))end
local SETTINGS_KEY='owner_'..OWNER_USER_ID
local lastRequest={}

-- Quest provenance only: successful assisted play never earns quest progress.
local QuestService=require(script.Parent:WaitForChild('QuestService'))
local questAidActions={giveEffect=true,clearTarget=true,revivePlayer=true,heal=true,
 spawnItem=true,giveItem=true,clearEffects=true,throw=true,bringItems=true,itemTarget=true,
 spawnMonster=true,clearMonsters=true,bank=true,revives=true,round=true}
local function markQuestAid(p,action,value)
 local target=p
 if action=='giveEffect' or action=='clearTarget' or action=='revivePlayer' then
  target=type(value)=='number' and Players:GetPlayerByUserId(value) or nil
 end
 local global=action=='spawnMonster' or action=='clearMonsters' or action=='noMonsters' or action=='bank' or action=='round'
 local active=target and target:GetAttribute('MissionActive')==true
 if global and not active then for _,member in Players:GetPlayers()do if member:GetAttribute('MissionActive')==true then active=true;break end end end
 if not active then return end
 local aided=questAidActions[action] or action=='god'and value==true or action=='noMonsters'and value==true
  or action=='speed'and p:GetAttribute('AdminWalkSpeed')~=nil or action=='jump'and p:GetAttribute('AdminJumpHeight')~=nil
 if aided then QuestService.MarkAssisted()end
end
local godConnections={}
-- Owner test map rotation: each level after the first walks every size of one map type (smallest first), then the
-- next type in MapGen.Profiles.Kinds order. Only while the owner is in the mission; position is saved per owner.
local MapProfiles=require(script.Parent:WaitForChild('MapGen'):WaitForChild('Profiles'))
local rotationState -- {kind=string, seen={size,...}}
local rotation=Instance.new('BindableFunction');rotation.Name='TestMapRotation';rotation.Parent=SS
rotation.OnInvoke=function(currentKind,currentSize)
 if STUDIO_MEMORY then return nil end
 local owner=Players:GetPlayerByUserId(OWNER_USER_ID)
 -- Off unless switched on for testing (owner attribute AdminMapRotation=true), so live runs keep the normal map order.
 if not owner or owner:GetAttribute('MissionActive')~=true or owner:GetAttribute('AdminMapRotation')~=true then return nil end
 local kinds=MapProfiles.Kinds
 local function sizesOf(k)return MapProfiles.KindSizes[k]or MapProfiles.Sizes end
 local st=rotationState
 if type(st)~='table'or not table.find(kinds,st.kind)then st={kind=table.find(kinds,currentKind)and currentKind or kinds[1],seen={}} end
 st.seen=type(st.seen)=='table'and st.seen or{}
 if st.kind==currentKind and type(currentSize)=='string'and not table.find(st.seen,currentSize)then table.insert(st.seen,currentSize)end
 local size
 for _,s in ipairs(sizesOf(st.kind))do if not table.find(st.seen,s)then size=s;break end end
 if not size then
  local i=table.find(kinds,st.kind)or 0
  st={kind=kinds[i%#kinds+1],seen={}};size=sizesOf(st.kind)[1]
 end
 table.insert(st.seen,size);rotationState=st
 local snapshot={kind=st.kind,seen=table.clone(st.seen)}
 task.spawn(function()pcall(function()settingsStore:UpdateAsync(SETTINGS_KEY,function(old)old=type(old)=='table'and old or{};old.rotation=snapshot;return old end)end)end)
 owner:SetAttribute('TestMapNext',st.kind..' '..size)
 return st.kind,size
end

local function isOwner(p)return Access.IsOwner(p)end
local function character(p) local c=p.Character;return c,c and c:FindFirstChildOfClass('Humanoid'),c and c:FindFirstChild('HumanoidRootPart') end
local function api(name) return SS:FindFirstChild(name) end
local function missionOnly() return false,'Only available inside a running mission.' end

local function applyGod(p)
 local c,h=character(p)
 if godConnections[p] then godConnections[p]:Disconnect();godConnections[p]=nil end
 if not h then return end
 if p:GetAttribute('AdminGod') then
  h.Health=h.MaxHealth
  godConnections[p]=h:GetPropertyChangedSignal('Health'):Connect(function()
   if p:GetAttribute('AdminGod') and h.Health<h.MaxHealth and h.Health>0 then h.Health=h.MaxHealth end
  end)
  p:SetAttribute('RoundDead',false)
 end
end
local function stripCosmetics(p)
 local c=p.Character;if not c or not p:GetAttribute('AdminNoCosmetics') then return end
 for _,x in ipairs(c:GetChildren()) do if x.Name=='ProgressCosmetics' or x:IsA('Accessory') then x:Destroy() end end
 local level=workspace:FindFirstChild('CursedLevelCosmetics')
 if level then for _,x in ipairs(level:GetChildren()) do if x:GetAttribute('CosmeticOwner')==p.UserId then x:Destroy() end end end
end
local function applyMovement(p)
 local _,h=character(p);if not h then return end
 local jump=p:GetAttribute('AdminJumpHeight')
 h.UseJumpPower=false;h.JumpHeight=jump or DEFAULT_JUMP
end

local function floorAhead(r,distance)
 local origin=r.Position+r.CFrame.LookVector*distance+Vector3.new(0,3,0)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={r.Parent,workspace:FindFirstChild('RoamingCreatures')}
 local hit=workspace:Raycast(origin,Vector3.new(0,-40,0),params)
 return hit and hit.Position or (r.Position+r.CFrame.LookVector*distance-Vector3.new(0,3,0))
end

local handlers={}
function handlers.state(p)
 local items=api('CursedItemAdminApi');local creatures=api('CreatureAdminApi');local round=api('RecoveryAdminApi')
 return true,'Ready.',{
  mission=p:GetAttribute('MissionActive')==true,players=Access.Roster(),owner=isOwner(p),
  effects=items and items:Invoke('effects',p)or{},
  questRewards=isOwner(p)and QuestService.AdminCatalog(p)or{},
  items=items and items:Invoke('catalog',p) or {},
  monsters=creatures and creatures:Invoke('templates') or {},
  round=round and round:Invoke('status') or nil,
  god=p:GetAttribute('AdminGod')==true,noCosmetics=p:GetAttribute('AdminNoCosmetics')==true,
  speed=p:GetAttribute('AdminWalkSpeed'),jump=p:GetAttribute('AdminJumpHeight'),noPasses=p:GetAttribute('AdminSimulateNoPasses')==true,
  noMonsters=game.ServerScriptService.CreatureRoamServer:GetAttribute('AdminNoMonsters')==true,
 }
end
local function targetPlayer(id)
 if type(id)~='number'or id~=id or id%1~=0 or math.abs(id)>9007199254740991 then return nil end
 return Players:GetPlayerByUserId(id)
end
function handlers.giveEffect(p,userId,id)
 local target=targetPlayer(userId)
 if not target then return false,'Choose a player currently in this server.'end
 -- Public lobbies hold strangers: effects go only on yourself there. In a mission (a private party) teammates are fine.
 if target~=p and not(p:GetAttribute('MissionActive')==true and target:GetAttribute('MissionActive')==true)then return false,'In the lobby you can only give effects to yourself.'end
 if type(id)~='string'or #id>60 then return false,'Choose an effect.'end
 local a=api('CursedItemAdminApi');if not a then return false,'Item effects are not ready yet.'end
 return a:Invoke('giveEffect',target,id)
end
function handlers.clearTarget(p,userId)
 local target=targetPlayer(userId);if not target then return false,'Choose a player currently in this server.'end
 local a=api('CursedItemAdminApi');if not a then return false,'Item effects are not ready yet.'end;return a:Invoke('clearEffects',target)
end
function handlers.revivePlayer(p,userId)
 local target=targetPlayer(userId);if not target then return false,'Choose a player currently in this server.'end
 local a=api('RecoveryAdminApi');if not a then return false,'Reviving is only available in a mission.'end
 return a:Invoke('revive',target)
end
function handlers.questRewards(p,selector,requestId)
 if not isOwner(p)then return false,'Owner access only.'end
 local result=QuestService.AdminRewards(p,selector,requestId)
 if not result.ok then return false,result.reason end
 return true,'Quest rewards saved. Equip them in Character.',result
end
function handlers.adminGrant(p,userId,on)return Access.Set(p,userId,on)end
function handlers.god(p,on)
 p:SetAttribute('AdminGod',on==true or nil);applyGod(p)
 -- Remembered for the owner across teleports and sessions (god mode starts ON until switched off here).
 if isOwner(p)then task.spawn(function()pcall(function()settingsStore:UpdateAsync(SETTINGS_KEY,function(old)old=type(old)=='table'and old or{};old.god=on==true;return old end)end)end)end
 return true,on and 'God mode ON: monsters ignore you and you cannot die.' or 'God mode OFF.'
end
function handlers.heal(p)
 local _,h=character(p);if not h then return false,'No character.' end
 h.Health=h.MaxHealth;p:SetAttribute('RoundDead',false);return true,'Healed.'
end
function handlers.speed(p,value)
 value=tonumber(value)
 if not value or value<=0 then p:SetAttribute('AdminWalkSpeed',nil);return true,'Speed reset to normal.' end
 value=math.clamp(value,SPEED_MIN,SPEED_MAX);p:SetAttribute('AdminWalkSpeed',value);return true,'Walk speed '..value..' (sprint '..math.floor(value*1.6)..').'
end
function handlers.jump(p,value)
 value=tonumber(value)
 if not value or value<0 then p:SetAttribute('AdminJumpHeight',nil) else p:SetAttribute('AdminJumpHeight',math.clamp(value,JUMP_MIN,JUMP_MAX)) end
 applyMovement(p);return true,'Jump height '..(p:GetAttribute('AdminJumpHeight') or DEFAULT_JUMP)..'.'
end
-- Test as a player without passes: ProgressService filters pass benefits while AdminSimulateNoPasses is set.
function handlers.noPasses(p,on)
 on=on==true
 p:SetAttribute('AdminSimulateNoPasses',on or nil)
 local saved=pcall(function() settingsStore:UpdateAsync(SETTINGS_KEY,function(old) old=type(old)=='table' and old or {};old.simulateNoPasses=on;return old end) end)
 return true,(on and 'Game passes OFF for you: you play as a player without any passes.' or 'Game passes back ON.')..(saved and '' or ' (Could not save the setting; it applies to this server only.)')
end
function handlers.cosmetics(p,hide)
 p:SetAttribute('AdminNoCosmetics',hide==true or nil);stripCosmetics(p)
 return true,hide and 'Cosmetics removed.' or 'Cosmetics come back on your next respawn.'
end
-- Items
local function items(p,...) local a=api('CursedItemAdminApi');if not a then return missionOnly() end;return a:Invoke(...) end
function handlers.spawnItem(p,id) if type(id)~='string' then return false,'Pick an item.' end;return items(p,'spawn',p,id) end
function handlers.giveItem(p,id) if type(id)~='string' then return false,'Pick an item.' end;return items(p,'give',p,id) end
function handlers.clearEffects(p) return items(p,'clearEffects',p) end
function handlers.throw(p,power) return items(p,'throw',p,power) end
function handlers.bringItems(p) return items(p,'bring',p,80) end
function handlers.itemTarget(p,target,op)
 if typeof(target)~='Instance' then return false,'Aim at an item.' end
 if op~='delete' and op~='freeze' and op~='launch' and op~='grow' and op~='shrink' then return false,'Unknown item action.' end
 -- the client may send a part of the item; resolve the item model under Mansion.Interactive
 local interactive=workspace:FindFirstChild('Mansion') and workspace.Mansion:FindFirstChild('Interactive')
 while target and target.Parent~=interactive do target=target.Parent end
 if not target then return false,'Aim at a loose item.' end
 return items(p,'target',p,target,op)
end
-- Monsters
function handlers.spawnMonster(p,index)
 local a=api('CreatureAdminApi');if not a then return missionOnly() end
 local _,_,r=character(p);if not r then return false,'No character.' end
 local ok,result=a:Invoke('spawn',p,floorAhead(r,14),index)
 return ok,ok and ('Spawned '..tostring(result)..'.') or (result or 'Could not spawn here.')
end
function handlers.clearMonsters(p) local a=api('CreatureAdminApi');if not a then return missionOnly() end;a:Invoke('clear');return true,'All monsters removed (until the next level).' end
function handlers.noMonsters(p,on) local a=api('CreatureAdminApi');if not a then return missionOnly() end;a:Invoke('hold',nil,on==true);return true,on and 'Monster spawning paused.' or 'Monster spawning resumed.' end
-- Gear shop team bank (owner only, like every handler here).
function handlers.bank(p,amount)
 local g=api('GearShopApi');if not g then return missionOnly() end
 if type(amount)~='number'or amount~=amount or amount<=0 or amount>100000 then return false,'Invalid amount.' end
 return g:Invoke('addBank',math.floor(amount))
end
-- Van rewards test clock (ProgressService.RewardAdminApi): add playtime, re-open the daily gift, restore the real save.
function handlers.rewards(p,action,value)
 local r=SS:FindFirstChild('RewardAdminApi');if not r then return false,'Rewards are not ready yet.'end
 if action~='time'and action~='daily'and action~='restore'then return false,'Unknown rewards action.'end
 return r:Invoke(action,p,value)
end
-- Revive tokens (saved to the owner's progress through ProgressService)
function handlers.revives(p,amount)
 local r=SS:FindFirstChild('RewardAdminApi');if not r then return false,'Saves are not ready yet.'end
 return r:Invoke('revives',p,amount)
end
-- Rounds
function handlers.round(p,action,value)
 local a=api('RecoveryAdminApi');if not a then return missionOnly() end
 if action~='restart' and action~='next' and action~='end' and action~='addTime' and action~='quota' then return false,'Unknown round action.' end
 return a:Invoke(action,value)
end

event.OnServerEvent:Connect(function(p,id,action,a,b)
 if not Access.IsAdmin(p)then return end
 if type(id)~='number' or id~=id or id<1 or id>1e9 or type(action)~='string' or #action>20 or not handlers[action] then return end
 if action~='state'and action~='giveEffect'and action~='clearTarget'and action~='revivePlayer'and not isOwner(p)then event:FireClient(p,id,false,'Owner access only.');return end
 local now=os.clock();if now-(lastRequest[p] or 0)<.12 then event:FireClient(p,id,false,'Slow down.');return end;lastRequest[p]=now
 local ok,success,message,data=pcall(handlers[action],p,a,b)
 if not ok then warn('[AdminPowers] '..action..': '..tostring(success));event:FireClient(p,id,false,'That failed: '..tostring(success));return end
 if success==true then markQuestAid(p,action,a)end
 event:FireClient(p,id,success==true,message,data)
end)

local function onCharacter(p,c)
 local h=c:WaitForChild('Humanoid',10);if not h or p.Character~=c then return end
 applyGod(p);applyMovement(p)
 if p:GetAttribute('MissionActive')==true and (p:GetAttribute('AdminGod')==true or p:GetAttribute('AdminWalkSpeed')~=nil or p:GetAttribute('AdminJumpHeight')~=nil)then QuestService.MarkAssisted()end
 if p:GetAttribute('AdminNoCosmetics') then task.delay(1,stripCosmetics,p) end
 c.ChildAdded:Connect(function(x) if p:GetAttribute('AdminNoCosmetics') and (x.Name=='ProgressCosmetics' or x:IsA('Accessory')) then task.defer(function() if x.Parent then x:Destroy() end end) end end)
end
local function onPlayer(p)
 p:GetAttributeChangedSignal('AdminAuthorized'):Connect(function()
  if not Access.IsAdmin(p)then for _,key in {'AdminGod','AdminWalkSpeed','AdminJumpHeight','AdminNoCosmetics','AdminSimulateNoPasses'}do p:SetAttribute(key,nil)end;applyGod(p)end
 end)
 if isOwner(p)then task.spawn(function()
  local ok,saved=pcall(function() return settingsStore:GetAsync(SETTINGS_KEY) end)
  if ok and type(saved)=='table' and saved.simulateNoPasses==true and p.Parent then p:SetAttribute('AdminSimulateNoPasses',true) end
  -- Owner testing: god mode starts OFF (switch it on in POWERS; that choice is remembered); the map rotation
  -- resumes where it stopped when it is switched on (owner attribute AdminMapRotation=true).
  if ok and p.Parent then
   if type(saved)=='table'and saved.god==true then p:SetAttribute('AdminGod',true);applyGod(p)end
   if type(saved)=='table'and type(saved.rotation)=='table'then rotationState=saved.rotation end
  end
 end)end
 p.CharacterAdded:Connect(function(c)if Access.IsAdmin(p)then onCharacter(p,c)end end)
 if p.Character and Access.IsAdmin(p)then task.spawn(onCharacter,p,p.Character)end
end
Players.PlayerAdded:Connect(onPlayer)
for _,p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerRemoving:Connect(function(p)
 lastRequest[p]=nil
 if godConnections[p] then godConnections[p]:Disconnect();godConnections[p]=nil end
end)
