-- Anti-cheat boundary helpers; kept within this system's existing owner.
-- Server boundary protection. Reject requests; never ban, kick or correct movement.
local Players=game:GetService('Players')
local AntiCheat={}
local buckets={}
local counters={}
local function record(channel,reason)
 local key=channel..':'..reason
 counters[key]=math.min((counters[key] or 0)+1,1000000000)
end
function AntiCheat.Finite(n)
 return type(n)=='number' and n==n and math.abs(n)<math.huge
end
function AntiCheat.Allow(player,channel,rate,burst)
 if typeof(player)~='Instance' or not player:IsA('Player') or player.Parent~=Players then return false end
 local now=os.clock()
 local user=buckets[player]
 if not user then user={};buckets[player]=user end
 local bucket=user[channel]
 if not bucket then bucket={tokens=burst,last=now};user[channel]=bucket end
 bucket.tokens=math.min(burst,bucket.tokens+math.max(0,now-bucket.last)*rate)
 bucket.last=now
 if bucket.tokens<1 then record(channel,'rate');return false end
 bucket.tokens-=1
 return true
end
function AntiCheat.Payload(value)
 -- Lobby requests are small records. Bound work, nesting, strings and numbers.
 local remaining=64
 local bytes=0
 local seen={}
 local function valid(v,depth)
  remaining-=1
  if remaining<0 then return false end
  local t=typeof(v)
  if t=='nil' or t=='boolean' then return true end
  if t=='number' then return AntiCheat.Finite(v) end
  if t=='string' then
   bytes+=#v
   return #v<=1024 and bytes<=4096 and utf8.len(v)~=nil
  end
  if t~='table' or depth>=3 or seen[v] then return false end
  seen[v]=true
  for key,item in pairs(v) do
   if (type(key)~='string' and type(key)~='number') or not valid(key,depth+1) or not valid(item,depth+1) then return false end
  end
  seen[v]=nil
  return true
 end
 return valid(value,0)
end
function AntiCheat.Stats()
 return table.clone(counters)
end
Players.PlayerRemoving:Connect(function(player)buckets[player]=nil end)

local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Http=game:GetService('HttpService')
local TextService=game:GetService('TextService')
local Teleport=game:GetService('TeleportService')
local Memory=game:GetService('MemoryStoreService')
local Messages=game:GetService('MessagingService')
local Core=require(script.Parent.LobbyPartyCore)
local Runtime=require(script.Parent.MissionRuntime)
local Access=require(script.Parent.MissionAccess)
local Progress=require(script.Parent.ProgressService)
local Quest=require(script.Parent.QuestService)
local RunSaves=require(script.Parent.RunSavesService)
local studio=Run:IsStudio()
local private=game.PrivateServerId~='' and game.PrivateServerOwnerId==0
local event=RS:WaitForChild('LobbyEvent')
local state=RS:WaitForChild('LobbyState')
Players.CharacterAutoLoads=false
state:SetAttribute('Mode',private and 'Mission' or 'Menu')
state:SetAttribute('LobbyCapacity',Access.LobbyCapacity)
state:SetAttribute('LobbyPopulation',0)
state:SetAttribute('PrivatePartyOnly',true)
local records=Memory:GetSortedMap('HorrorParties_v1')
local sessions=Memory:GetSortedMap('HorrorMissionSessions_v1')
local prefStore=game:GetService('DataStoreService'):GetDataStore('HorrorPreferences_v1')
local localRecords,owned,preferences,revisions,friends,limits,busy={},{},{},{},{},{},{}
local launchContexts={}
local lobbyTransfers={}
local job=studio and 'studio' or game.JobId
-- Server-owned local circle reservations; attributes are presentation only.
local CIRCLE_COUNT,SETUP_SECONDS=20,180
local circleSlots,claims={},{}
local function circleModel(index)
 local world=workspace:FindFirstChild('LobbyWorld');local circles=world and world:FindFirstChild('Circles')
 local model=circles and circles:FindFirstChild('Circle'..index)
 return model and model:IsA('Model') and model or nil
end
local function circleIndex(value)
 return AntiCheat.Finite(value) and value%1==0 and value>=1 and value<=CIRCLE_COUNT
end
local function publishCircle(index)
 local model=circleModel(index);if not model then return end
 local slot=circleSlots[index];local record=slot and slot.record
 local status=not slot and 'Free' or not record and 'Setup' or record.status~='Waiting' and 'Starting' or #record.members>=record.size and 'Full' or 'Open'
 model:SetAttribute('Status',status);model:SetAttribute('PartyId',record and record.id or nil)
 model:SetAttribute('OwnerUserId',slot and slot.owner.UserId or nil);model:SetAttribute('OwnerName',slot and slot.owner.DisplayName or nil)
 model:SetAttribute('Size',record and record.size or 0);model:SetAttribute('Count',record and #record.members or 0)
 model:SetAttribute('Access',record and (record.password~='' and 'Password' or record.friendsOnly and 'Friends' or 'Public') or 'Public')
end
local function releaseClaim(p)
 local claim=claims[p];if not claim then return end
 claims[p]=nil;p:SetAttribute('LobbyCircle',nil)
 if circleSlots[claim.index]==claim then circleSlots[claim.index]=nil;publishCircle(claim.index)end
end
local function clearPartyCircle(record)
 if not record or record.job~=job or not record.circle then return end
 local slot=circleSlots[record.circle]
 if slot and slot.record and slot.record.id==record.id then releaseClaim(slot.owner)end
end
local function updatePartyCircle(record)
 if record.job~=job or not record.circle then return end
 local slot=circleSlots[record.circle]
 if slot and slot.owner.UserId==record.owner and slot.record and slot.record.id==record.id then slot.record=record;publishCircle(record.circle)end
end
local function nearCircle(p,index)
 local model=circleModel(index);local pad=model and model:FindFirstChild('Pad');local radius=model and model:GetAttribute('Radius')
 local char=p.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
 if not pad or not pad:IsA('BasePart') or not AntiCheat.Finite(radius) or radius<=0 or not root or not root:IsA('BasePart') or not hum or hum.Health<=0 then return false end
 -- Horizontal distance with room for movement lag (lobby walk/sprint is fast); the client only asks from inside the ring.
 local d=root.Position-pad.Position
 return Vector3.new(d.X,0,d.Z).Magnitude<=radius+5 and math.abs(d.Y)<=14
end
local function claimCircle(p,index)
 if not circleIndex(index) or not circleModel(index)then return false,'Choose an available circle.'end
 if p:GetAttribute('LobbyPartyId')then return false,'Leave your current party first.'end
 local existing=circleSlots[index]
 if existing then
  if existing.owner==p then return true,{circle=index,status='Setup'}end
  return false,'That circle is occupied.'
 end
 releaseClaim(p)
 local claim:any={index=index,owner=p,expires=os.clock()+SETUP_SECONDS}
 circleSlots[index]=claim;claims[p]=claim;p:SetAttribute('LobbyCircle',index);publishCircle(index)
 task.delay(SETUP_SECONDS,function()if claims[p]==claim and not claim.record then releaseClaim(p);if p.Parent then event:FireClient(p,'notice','Circle setup expired. Choose a circle again.')end end end)
 return true,{circle=index,status='Setup'}
end
task.spawn(function()while task.wait(2)do for index=1,CIRCLE_COUNT do publishCircle(index)end end end)
local function user(p)return {id=p.UserId,name=p.Name,display=p.DisplayName}end
local function setPrefs(p,data)
 preferences[p]=Core.Preferences(data)
 for key,value in pairs(preferences[p])do p:SetAttribute('Setting'..key,value)end
end
local savedRevisions={} -- last preference revision written; unchanged prefs are never re-saved
local function savePrefs(p,override)
 if studio then return end
 local data=override or preferences[p];if not data then return end
 local revision=revisions[p]or 0
 if revision==0 or savedRevisions[p]==revision then return end
 local stamp=DateTime.now().UnixTimestampMillis
 local ok=pcall(function()prefStore:UpdateAsync('player_'..p.UserId,function(old)
  if type(old)=='table' and (old.updated or 0)>stamp then return nil end
  return {version=1,settings=data,updated=stamp}
 end)end)
 if ok then savedRevisions[p]=revision end
 if p.Parent then p:SetAttribute('PreferenceSaveStatus',ok and 'Saved' or 'Session only')end
end
local function get(id)
 if studio then return localRecords[id] end
 local record=records:GetAsync(id);return record
end
local function write(record)
 if studio then localRecords[record.id]=record;return end
 records:SetAsync(record.id,record,120,os.time())
end
local function update(id,transform)
 if studio then local next=transform(localRecords[id]);if next then localRecords[id]=next end;return next end
 return records:UpdateAsync(id,function(record)
  local next=transform(record);return next,next and os.time() or nil
 end,120)
end
local function remove(id)
 if studio then localRecords[id]=nil else records:RemoveAsync(id)end
end
local function friendList(p)
 local cached=friends[p]
 if cached and os.clock()-cached.time<60 then return cached.list end
 local list={}
 local pages=Players:GetFriendsAsync(p.UserId)
 repeat
  for _,friend in pages:GetCurrentPage()do
   table.insert(list,{id=friend.Id,username=friend.Username or friend.UserName or friend.Name,display=friend.DisplayName or friend.Username or friend.Name,online=friend.IsOnline==true})
  end
  if pages.IsFinished or #list>=1000 then break end
  pages:AdvanceToNextPageAsync()
 until false
 friends[p]={time=os.clock(),list=list};return list
end
local function isFriend(p,id)
 if p.UserId==id then return true end
 for _,friend in friendList(p)do if friend.id==id then return true end end
 return false
end
local function snapshot(p)
 local id=p:GetAttribute('LobbyPartyId')
 local record=id and get(id)
 return {party=Core.Snapshot(record),preferences=preferences[p] or Core.Preferences(),progress=Progress.Snapshot(p),studio=studio,mode=state:GetAttribute('Mode')}
end
local function push(record)
 updatePartyCircle(record)
 for _,member in record.members do local p=Players:GetPlayerByUserId(member.id)
  if p then event:FireClient(p,'state',{party=Core.Snapshot(record),preferences=preferences[p],studio=studio,mode=state:GetAttribute('Mode')})end
 end
end
local function leave(p)
 local id=p:GetAttribute('LobbyPartyId');if not id then releaseClaim(p);p:SetAttribute('LobbyCircle',nil);return end
 local record=get(id)
 p:SetAttribute('LobbyPartyId',nil);p:SetAttribute('LobbyCircle',nil)
 if not record then releaseClaim(p);return end
 if record.owner==p.UserId then
  clearPartyCircle(record)
  remove(id);owned[id]=nil
  for _,member in record.members do local other=Players:GetPlayerByUserId(member.id);if other then other:SetAttribute('LobbyPartyId',nil);other:SetAttribute('LobbyCircle',nil);event:FireClient(other,'state',snapshot(other));event:FireClient(other,'notice','The host closed the party.')end end
 else
  record=update(id,function(current)if not current then return nil end;Core.Remove(current,p.UserId);if current.status~='Waiting' then current.status='Waiting';current.countdown=nil;current.cancelled=true end;return current end)
  if record then push(record)end
 end
end
local function restoreLaunch(record,message)
 record.status='Waiting';record.countdown=nil;record.session=nil;record.cancelled=nil
 write(record);push(record)
 for _,member in record.members do local p=Players:GetPlayerByUserId(member.id);if p then event:FireClient(p,'notice',message)end end
end
local function start(p,record)
 if record.owner~=p.UserId then return false,'Only the party owner can start.'end
 if record.status~='Waiting' then return false,'Your party is already starting.'end
 if #record.members~=record.size then return false,'Wait until all '..record.size..' players have joined.'end
 local partyPlayers={}
 for _,member in record.members do local other=Players:GetPlayerByUserId(member.id)
  if not other or other:GetAttribute('LobbyPartyId')~=record.id then return false,'A party member is still joining this lobby.'end
  table.insert(partyPlayers,other)
 end
 if studio and #partyPlayers~=#Players:GetPlayers() then return false,'For Studio preview, put everyone in this test server in the same party.'end
 record=update(record.id,function(current)
  if not current or current.owner~=p.UserId or current.status~='Waiting' or #current.members~=current.size then return nil end
  current.status='Preparing';return current
 end)
 if not record then return false,'Party changed. Please try again.'end
 push(record)
 local chosen,choiceError=RunSaves.ValidateChoice(p,record.runSaveChoice)
 if not chosen then restoreLaunch(record,choiceError);return false,choiceError end
 for _,member in partyPlayers do local saved,reason=Quest.Flush(member);if not saved then restoreLaunch(record,reason or 'Quest progress is still saving.');return false,reason or 'Quest progress is still saving.'end end
 local launchToken=Http:GenerateGUID(false)
 local reserved,saveTicket=RunSaves.PrepareLaunch(p,launchToken)
 if not reserved then restoreLaunch(record,saveTicket);return false,saveTicket end
 local code,privateId,sessionId
 if not studio then
  local ok,err=pcall(function()
   code,privateId=Teleport:ReserveServerAsync(game.PlaceId);sessionId=Http:GenerateGUID(false)
   local allowed,prefs,colors={},{},{}
   for _,other in partyPlayers do
    allowed[tostring(other.UserId)]=true;prefs[tostring(other.UserId)]=preferences[other]
    colors[tostring(other.UserId)]={body=other:GetAttribute('BodyColourHex'),eyes=other:GetAttribute('EyeColourHex')}
   end
   sessions:SetAsync(sessionId,{version=2,token=launchToken,privateId=privateId,allowed=allowed,preferences=prefs,colors=colors,owner=p.UserId,runSave=saveTicket,count=#partyPlayers,sourcePlaceId=game.PlaceId,sourceGameId=game.GameId,expires=os.time()+Access.ArrivalSeconds,admitted={},destinationJob=''},300)
  end)
  if not ok then RunSaves.CancelLaunch(saveTicket);restoreLaunch(record,'Could not prepare the private server. Please try again.');return false,'Private server service is temporarily unavailable.'end
 end
 record=update(record.id,function(current)
  if not current or current.status~='Preparing' or #current.members~=current.size then return nil end
  current.status='Starting';current.countdown=workspace:GetServerTimeNow()+3;current.session=sessionId;return current
 end)
 if not record then RunSaves.CancelLaunch(saveTicket);if sessionId then pcall(function()sessions:RemoveAsync(sessionId)end)end;return false,'Launch cancelled because the party changed.'end
 push(record)
 local deadline=record.countdown
 task.spawn(function()
  while workspace:GetServerTimeNow()<deadline do task.wait(.1)end
  local current=get(record.id)
  if not current or current.status~='Starting' or current.countdown~=deadline then RunSaves.CancelLaunch(saveTicket);if sessionId then pcall(function()sessions:RemoveAsync(sessionId)end)end;return end
  for _,other in partyPlayers do if not other.Parent or other:GetAttribute('LobbyPartyId')~=record.id then RunSaves.CancelLaunch(saveTicket);if sessionId then pcall(function()sessions:RemoveAsync(sessionId)end)end;restoreLaunch(current,'Launch cancelled because someone left.');return end end
  if studio then
   for _,member in partyPlayers do member:SetAttribute('MissionAuthorized',true)end
   local started,startError=Runtime.Start(partyPlayers,saveTicket,p.UserId)
   if not started then
    RunSaves.CancelLaunch(saveTicket)
    for _,member in partyPlayers do member:SetAttribute('MissionAuthorized',false)end
    restoreLaunch(current,startError or 'Could not open the selected save.');return
   end
   state:SetAttribute('Mode','Mission');state:SetAttribute('StudioPreview',true)
   clearPartyCircle(record)
   for _,member in partyPlayers do member:SetAttribute('LobbyCircle',nil)end
   remove(record.id);owned[record.id]=nil
   event:FireAllClients('launch',{studio=true})
  else
   current.status='Teleporting';write(current);push(current)
   local options=Instance.new('TeleportOptions');options.ReservedServerAccessCode=code
   options:SetTeleportData({missionSession=sessionId,missionToken=launchToken})
   for _,member in partyPlayers do launchContexts[member]={options=options,attempts=0,record=current}end
   local ok=pcall(function()Teleport:TeleportAsync(game.PlaceId,partyPlayers,options)end)
   if not ok then RunSaves.CancelLaunch(saveTicket);for _,member in partyPlayers do launchContexts[member]=nil end;restoreLaunch(current,'Teleport failed. Your party is still here; try again.')end
  end
 end)
 return true,'Starting in 3 seconds.'
end
local function handle(p,action,data)
 data=type(data)=='table' and data or {}
 if action=='sync' then return true,snapshot(p)end
 if action=='preferences' then
  setPrefs(p,data);revisions[p]=(revisions[p] or 0)+1;local revision=revisions[p]
  p:SetAttribute('PreferenceSaveStatus',studio and 'Studio session' or 'Saving')
  task.delay(2,function()if p.Parent and revisions[p]==revision then savePrefs(p)end end)
  return true,{preferences=preferences[p]}
 end
 if action=='vanAppearance'then return Progress.VanShopInfo(p)end
 if action=='vanShop'then return Progress.VanShopInfo(p)end
 if action=='robuxShop'then return Progress.RobuxShopInfo(p)end
 if action=='progress'then Progress.Load(p);return true,{progress=Progress.Snapshot(p)}end
 if action=='setShowHauntedTag'then return Progress.SetShowHauntedTag(p,type(data)=='boolean'and data or data.show)end
 if action=='leaderboard'then return Progress.BoardFor(p,data.category)end
 if action=='purchase'then return Progress.Purchase(p,data.offer)end
 if action=='appearanceEquip'then return Progress.Equip(p,data.offer,data.slot)end
 if action=='equip'then return false,'Equip cosmetics from Appearance.'end
 if action=='tutorialDone'then return Progress.CompleteTutorial(p)end
 if p:GetAttribute('MissionActive') then return false,'You are already in a mission.'end
 if action=='circle.claim' then return claimCircle(p,data.circle)
 elseif action=='circle.release' then
  if p:GetAttribute('LobbyPartyId')then return false,'Leave your party to release its circle.'end
  releaseClaim(p);return true,{}
 elseif action=='runSaves.list'then return RunSaves.List(p)
 elseif action=='runSaves.create'or action=='runSaves.delete'or action=='runSaves.select'then
  if p:GetAttribute('LobbyPartyId')then return false,'Choose your save before creating a party.'end
  if action=='runSaves.create'then return RunSaves.Create(p,data.index,data.name)
  elseif action=='runSaves.delete'then return RunSaves.Delete(p,data.index)
  else return RunSaves.Select(p,data.index)end
 elseif action=='friends' then
  local query=type(data.query)=='string' and data.query:sub(1,50) or ''
  local out={};for _,friend in friendList(p)do if Core.MatchFriend(friend,query)then table.insert(out,friend);if #out>=30 then break end end end
  return true,{friends=out}
 elseif action=='browse' then
  local list={}
  if studio then for _,record in pairs(localRecords)do table.insert(list,{value=record})end
  else list=records:GetRangeAsync(Enum.SortDirection.Descending,50)end
  local out={}
  for _,entry in list do local record=entry.value
   if type(record)=='table' and record.status=='Waiting' and #record.members<record.size and (not record.friendsOnly or isFriend(p,record.owner))then table.insert(out,Core.Snapshot(record))end
  end
  return true,{parties=out}
 elseif action=='create' then
  if p:GetAttribute('LobbyPartyId') then return false,'Leave your current party first.'end
  local claim=claims[p]
  if not circleIndex(data.circle) or not claim or claim.index~=data.circle or circleSlots[data.circle]~=claim or claim.record or os.clock()>=claim.expires then return false,'Claim a circle before setting up your party.'end
  -- Party passwords go through Roblox's text filter: anything it would censor is refused, and so is every
  -- password while the filter cannot be reached (fail closed). Passwords are never shown, only compared.
  local password=data.password or ''
  if type(password)=='string' and password~='' and #password<=40 then
   local checked,filtered=pcall(function()return TextService:FilterStringAsync(password,p.UserId,Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()end)
   if not checked then return false,'Could not check that password right now. Try again.'end
   if filtered~=password then return false,'That password is not allowed. Choose a different one.'end
  end
  local record,err=Core.New(user(p),data.size,data.friendsOnly,password,Http:GenerateGUID(false),job,data.circle)
  if not record then return false,err end
  local valid,saveError=RunSaves.ValidateChoice(p,data.save)
  if not valid then return false,saveError end
  if not p.Parent or claims[p]~=claim or circleSlots[data.circle]~=claim or os.clock()>=claim.expires then return false,'Your circle reservation expired. Choose a circle again.'end
  record.runSaveChoice={slot=data.save.slot,mode=data.save.mode}
  write(record)
  if not p.Parent or claims[p]~=claim or circleSlots[data.circle]~=claim or os.clock()>=claim.expires then remove(record.id);return false,'Your circle reservation ended.'end
  claim.record=record;owned[record.id]=true;p:SetAttribute('LobbyPartyId',record.id);push(record)
  return true,{party=Core.Snapshot(record)}
 elseif action=='leave' then leave(p);return true,snapshot(p)
 elseif action=='join' or action=='circle.join' then
  if action=='circle.join' then
   if not circleIndex(data.circle)then return false,'Choose an available circle.'end
   local slot=circleSlots[data.circle]
   if not slot or not slot.record then return false,'The host is still setting up this circle.'end
   if not nearCircle(p,data.circle)then return false,'Walk into the circle to join.'end
   data.id=slot.record.id
  end
  if p:GetAttribute('LobbyPartyId') then return false,'Leave your current party first.'end
  if type(data.id)~='string' or #data.id>80 or type(data.password or '')~='string' or #(data.password or '')>40 then return false,'Invalid party request.'end
  local record=get(data.id);if not record then return false,'That party has closed.'end
  if record.job==job and record.circle and not nearCircle(p,record.circle)then return false,'Walk into the circle to join.'end
  local friend=not record.friendsOnly or isFriend(p,record.owner)
  local rejected
  record=update(data.id,function(current)
   if not current then rejected='That party has closed.';return nil end
   if not p.Parent or p:GetAttribute('MissionActive') or p:GetAttribute('LobbyPartyId') then rejected='You are no longer available to join.';return nil end
   if current.job==job and current.circle and not nearCircle(p,current.circle)then rejected='Walk into the circle to join.';return nil end
   local ok,err=Core.Admit(current,user(p),friend,data.password or '')
   if not ok then rejected=err;return nil end
   if current.job~=job and not studio then for _,member in current.members do if member.id==p.UserId then member.arrivingUntil=os.time()+45 end end end
   return current
  end)
  if not record then return false,rejected or 'Could not join that party.'end
  if not p.Parent or p:GetAttribute('MissionActive') or p:GetAttribute('LobbyPartyId') or record.job==job and record.circle and not nearCircle(p,record.circle) then
   local corrected=update(record.id,function(current)if current then Core.Remove(current,p.UserId);return current end end)
   if corrected then push(corrected)end
   return false,'You are no longer available at that circle.'
  end
  if record.job~=job and not studio then
   local saved,reason=Quest.Flush(p);if not saved then update(record.id,function(current)if current then Core.Remove(current,p.UserId);return current end end);return false,reason end
   local options=Instance.new('TeleportOptions');options.ServerInstanceId=record.job;options:SetTeleportData({joinParty=record.id})
   lobbyTransfers[p]=record.id
   local ok=pcall(function()Teleport:TeleportAsync(game.PlaceId,{p},options)end)
   if not ok then lobbyTransfers[p]=nil;update(record.id,function(current)if current then Core.Remove(current,p.UserId);return current end end);return false,'Could not reach your friendÃ¢â‚¬â„¢s lobby. Try again.'end
   return true,{transferring=true}
  end
  releaseClaim(p);p:SetAttribute('LobbyPartyId',record.id);p:SetAttribute('LobbyCircle',record.job==job and record.circle or nil);push(record);return true,{party=Core.Snapshot(record)}
 end
 local id=p:GetAttribute('LobbyPartyId');local record=id and get(id)
 if not record then return false,'Create or join a party first.'end
 if action=='start' then return start(p,record)
 elseif action=='invite' then
  if record.owner~=p.UserId or record.status~='Waiting' then return false,'Only the host can invite while waiting.'end
  if type(data.userId)~='number' or data.userId%1~=0 or not isFriend(p,data.userId)then return false,'Choose someone from your friends list.'end
  local invite={userId=data.userId,party=Core.Snapshot(record),expires=os.time()+60}
  local target=Players:GetPlayerByUserId(data.userId)
  if target then event:FireClient(target,'invite',invite)
  elseif not studio then Messages:PublishAsync('HorrorPartyInvites_v1',invite)end
  return true,'Invitation sent to your friend if they are in the game.'
 elseif action=='kick' then
  if record.owner~=p.UserId or record.status~='Waiting' or type(data.userId)~='number' or data.userId==p.UserId then return false,'Only the host can remove another member.'end
  if not AntiCheat.Finite(data.userId) or data.userId%1~=0 or data.userId<=0 then return false,'Invalid member.'end
  local isMember=false;for _,member in record.members do if member.id==data.userId then isMember=true;break end end
  if not isMember then return false,'That player is not in your party.'end
  local removed=false
  record=update(id,function(current)
   if not current or current.owner~=p.UserId or current.status~='Waiting' then return nil end
   removed=false
   for _,member in current.members do if member.id==data.userId then removed=true;break end end
   if not removed then return nil end
   Core.Remove(current,data.userId);return current
  end)
  if not record or not removed then return false,'The party changed. Please try again.'end
  local target=Players:GetPlayerByUserId(data.userId);if target and target:GetAttribute('LobbyPartyId')==id then target:SetAttribute('LobbyPartyId',nil);target:SetAttribute('LobbyCircle',nil);event:FireClient(target,'state',snapshot(target))end
  if record then push(record)end;return true,{party=Core.Snapshot(record)}
 end
 return false,'Unknown menu action.'
end
event.OnServerEvent:Connect(function(p,requestId,action,data)
 if type(requestId)~='number' or requestId~=requestId or requestId%1~=0 or requestId<0 or requestId>1e9 or type(action)~='string' or #action>20 then return end
 if not AntiCheat.Payload(data) then
  event:FireClient(p,'response',{id=requestId,ok=false,error='Invalid request.'});return
 end
 local now=os.clock();local rate=limits[p] or {time=now,count=0};limits[p]=rate
 if now-rate.time>1 then rate.time=now;rate.count=0 end
 rate.count+=1
 if rate.count>12 or busy[p] then event:FireClient(p,'response',{id=requestId,ok=false,error='Please wait a moment.'});return end
 busy[p]=true
 task.spawn(function()
  local ok,success,result=pcall(handle,p,action,data)
  busy[p]=nil
  if not p.Parent then return end
  event:FireClient(p,'response',{id=requestId,ok=ok and success==true,data=ok and success and result or nil,error=not ok and 'Menu service is temporarily unavailable. Try again.' or not success and result or nil})
 end)
end)
Teleport.TeleportInitFailed:Connect(function(p,result,message,placeId,options)
 if placeId~=game.PlaceId or not p.Parent then return end
 local context=launchContexts[p]
 if context and context.attempts<3 then
  context.attempts+=1;event:FireClient(p,'notice','Reconnecting to your partyÃ¢â‚¬â„¢s private mission...')
  task.delay(2,function()if p.Parent and launchContexts[p]==context then local saved=Quest.Flush(p);local ok=saved and pcall(function()Teleport:TeleportAsync(game.PlaceId,{p},context.options)end);if not ok then launchContexts[p]=nil;event:FireClient(p,'notice','Could not connect. Rejoin your friends from the main menu.')end end end)
 elseif context then
  launchContexts[p]=nil;p:SetAttribute('LobbyPartyId',nil);event:FireClient(p,'state',snapshot(p));event:FireClient(p,'notice','Could not connect after three attempts. Please rejoin from the main menu.')
 else
  local pending=lobbyTransfers[p];lobbyTransfers[p]=nil
  if pending then pcall(function()update(pending,function(current)if current then Core.Remove(current,p.UserId);return current end end)end)end
  event:FireClient(p,'notice','Teleport interrupted. Please try again.')
 end
end)
local missionSession
local missionClosed=false
local missionAborted=false
local arrivalTimerStarted=false
local admittedPlayers={}
local function startAdmittedParty(session)
 if missionClosed or missionAborted then return end
 local roster={}
 for id in pairs(session.allowed)do
  local player=admittedPlayers[id]
  if not player or not player.Parent then return end
  table.insert(roster,player)
 end
 if #roster~=session.count then return end
 missionClosed=true
 state:SetAttribute('MissionSealed',true)
 state:SetAttribute('MissionPartySize',#roster)
 for _,player in roster do
  setPrefs(player,session.preferences and session.preferences[tostring(player.UserId)])
  local colors=session.colors and session.colors[tostring(player.UserId)]
  local transfer=game.ServerStorage:FindFirstChild('CharacterColourTransfer')
  if transfer and colors then transfer:Invoke(player,colors.body,colors.eyes)end
 end
 local started,startError=Runtime.Start(roster,session.runSave,session.owner)
 if not started then missionAborted=true;for _,player in roster do player:Kick(startError or 'Could not open the selected run save.')end;return end
 for _,player in roster do event:FireClient(player,'launch',{private=true})end
end
local LOBBY_WALK_SPEED=24
local lobbyLoading,respawnAt={},{}
local function lobbyActive(p)
 return p.Parent==Players and p:GetAttribute('LobbyReady')==true and p:GetAttribute('MissionActive')~=true and (not private or p:GetAttribute('ReturnedToLobby')==true)
end
local function lobbySpawn(p,char)
 while lobbyActive(p) and p.Character==char do
  local world=workspace:FindFirstChild('LobbyWorld');local map=workspace:FindFirstChild('Mansion')
  if world and world:GetAttribute('Ready')==true and (not map or map:GetAttribute('Ready')==true) then break end
  task.wait(.1)
 end
 if not lobbyActive(p) or p.Character~=char then return false end
 local world=workspace:FindFirstChild('LobbyWorld');local spawnPart=world and world:FindFirstChild('SpawnPoint')
 local root=char:WaitForChild('HumanoidRootPart',12);local hum=char:WaitForChild('Humanoid',12)
 if not spawnPart or not spawnPart:IsA('BasePart') or not root or not root:IsA('BasePart') or not hum or not hum:IsA('Humanoid') or hum.Health<=0 or not lobbyActive(p) or p.Character~=char then return false end
 p:SetAttribute('LobbyBaseWalkSpeed',LOBBY_WALK_SPEED);hum.WalkSpeed=LOBBY_WALK_SPEED
 local radius=spawnPart:GetAttribute('SpawnRadius') or world:GetAttribute('SpawnRadius');radius=AntiCheat.Finite(radius) and math.clamp(radius,0,100) or 0
 local angle=math.random()*math.pi*2;local spread=math.sqrt(math.random())*radius
 local cf,size=spawnPart.CFrame,spawnPart.Size
 local top=(math.abs(cf.RightVector.Y)*size.X+math.abs(cf.UpVector.Y)*size.Y+math.abs(cf.LookVector.Y)*size.Z)/2
 char:PivotTo(CFrame.new(spawnPart.Position+Vector3.new(math.cos(angle)*spread,top+hum.HipHeight+root.Size.Y/2+.25,math.sin(angle)*spread)))
 root.Anchored=false
 for _,part in char:GetDescendants()do if part:IsA('BasePart')then part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end end
 return true
end
local function loadLobbyCharacter(p)
 if not lobbyActive(p) or lobbyLoading[p] then return end
 lobbyLoading[p]=true
 task.spawn(function()
  while lobbyActive(p) do
   local world=workspace:FindFirstChild('LobbyWorld');local map=workspace:FindFirstChild('Mansion')
   if world and world:GetAttribute('Ready')==true and (not map or map:GetAttribute('Ready')==true) then break end
   task.wait(.1)
  end
  if lobbyActive(p) then
   local ok=pcall(function()p:LoadCharacterAsync()end)
   if not ok and p.Parent then event:FireClient(p,'notice','Your lobby character could not load. Please rejoin.')end
  end
  lobbyLoading[p]=nil
 end)
end
-- A failed spectator teleport returns only that player through the normal lobby spawn owner.
local returnApi=Instance.new('BindableFunction');returnApi.Name='ReturnToLobby';returnApi.Parent=script
returnApi.OnInvoke=function(p)
 if typeof(p)~='Instance' or not p:IsA('Player') or p.Parent~=Players or p:GetAttribute('MissionActive')~=true or p:GetAttribute('RoundDead')~=true or p:GetAttribute('Reviving')then return false,'Spectator return is unavailable.'end
 local saved,reason=Quest.Flush(p);if not saved then return false,reason end
 RunSaves.DepartMission(p) -- identical departure checkpoint, while genuine death is still visible
 local items=game.ServerStorage:FindFirstChild('CursedItemApi');if items and items:IsA('BindableFunction')then items:Invoke('reset',p)end
 releaseClaim(p);p:SetAttribute('LobbyPartyId',nil);p:SetAttribute('LobbyCircle',nil)
 p:SetAttribute('ReturnedToLobby',true);p:SetAttribute('MissionActive',false);p:SetAttribute('MissionAuthorized',false)
 p:SetAttribute('RoundDead',nil);p:SetAttribute('Reviving',nil);p:SetAttribute('LeavingRun',nil);p:SetAttribute('LobbyReady',true)
 local remaining=0;for _,other in Players:GetPlayers()do if other:GetAttribute('MissionActive')==true then remaining+=1 end end
 if remaining==0 then state:SetAttribute('Mode','Menu');workspace:SetAttribute('MissionRunning',false)end
 loadLobbyCharacter(p)
 event:FireClient(p,'returnedToLobby',snapshot(p))
 return true,remaining
end
local function lobbyCharacterAdded(p,char)
 task.spawn(function()
  if not lobbyActive(p) or not lobbySpawn(p,char) then return end
  local hum=char:FindFirstChildOfClass('Humanoid');if not hum then return end
  hum.Died:Connect(function()respawnAt[p]=os.clock()+2;task.delay(2,function()if lobbyActive(p) and p.Character==char then loadLobbyCharacter(p)end end)end)
 end)
end
task.spawn(function()
 while task.wait(1)do
  for _,p in Players:GetPlayers()do
   if lobbyActive(p) then
    local char=p.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local hum=char and char:FindFirstChildOfClass('Humanoid')
    if root and root:IsA('BasePart') and hum and hum.Health>0 then
     if root.Position.Y < -50 then task.spawn(lobbySpawn,p,char)
     else local map=workspace:FindFirstChild('Mansion');if not map or map:GetAttribute('Ready')==true then root.Anchored=false end end
    elseif not char or hum and hum.Health<=0 and os.clock()>=(respawnAt[p] or 0) then loadLobbyCharacter(p)end
   end
  end
 end
end)
local function joined(p)
 p.CharacterAdded:Connect(function(char)lobbyCharacterAdded(p,char)end)
 setPrefs(p,Core.DefaultPreferences);p:SetAttribute('MissionActive',false);p:SetAttribute('MissionAuthorized',false)
 if private then
  p:SetAttribute('LobbyReady',false)
  if p.Character then p.Character:Destroy()end
  if missionClosed or missionAborted then p:Kick('This private mission is sealed to its original party.');return end
  task.spawn(function()
   local join=p:GetJoinData();local data=join.TeleportData
   local id=type(data)=='table'and data.missionSession
   local token=type(data)=='table'and data.missionToken
   if type(id)~='string'or #id>80 or type(token)~='string'or #token>80 or missionSession and missionSession~=id then p:Kick('Join your party through the main menu.');return end
   local context={reserved=true,closed=missionClosed or missionAborted,token=token,userId=p.UserId,privateId=game.PrivateServerId,job=game.JobId,sourcePlaceId=join.SourcePlaceId,sourceGameId=join.SourceGameId,now=os.time()}
   local rejected
   local ok,session=pcall(function()
    return sessions:UpdateAsync(id,function(current)
     context.closed=missionClosed or missionAborted
     context.now=os.time()
     if missionSession and missionSession~=id then rejected='Wrong party session.';return nil end
     local claimed,reason=Access.Claim(current,context)
     if not claimed then rejected=reason;return nil end
     return claimed
    end,300)
   end)
   if not ok or type(session)~='table'or rejected or not session.admitted or session.admitted[tostring(p.UserId)]~=game.JobId or not p.Parent or missionClosed or missionAborted then
    if p.Parent then p:Kick(rejected or 'Could not verify your private party admission.')end
    return
   end
   missionSession=id
   admittedPlayers[tostring(p.UserId)]=p
   p:SetAttribute('MissionAuthorized',true)
   if not arrivalTimerStarted then
    arrivalTimerStarted=true
    task.delay(45,function()
     if missionClosed or missionAborted then return end
     missionAborted=true;state:SetAttribute('MissionSealed',true)
     for _,member in Players:GetPlayers()do member:Kick('The whole party did not arrive. Rejoin the main lobby and start again.')end
    end)
   end
   startAdmittedParty(session)
  end)

 else
  local count=0;for _,other in Players:GetPlayers()do if other~=p and other:GetAttribute('LobbyReady')and not other:GetAttribute('MissionActive')then count+=1 end end
  if count>=Access.LobbyCapacity then p:Kick('This lobby is full. Please join another lobby.');return end
  p:SetAttribute('LobbyReady',true)
  state:SetAttribute('LobbyPopulation',count+1)
  if p.Character then lobbyCharacterAdded(p,p.Character)else loadLobbyCharacter(p)end
  task.spawn(function()
   if not studio then
    local ok,data=pcall(function()return prefStore:GetAsync('player_'..p.UserId)end)
    if ok and type(data)=='table' and (revisions[p] or 0)==0 then setPrefs(p,data.settings)end
   end
   local join=p:GetJoinData();local data=join.TeleportData
   if type(data)=='table' and type(data.joinParty)=='string' and #data.joinParty<=80 then
    local record=get(data.joinParty)
    if record and record.job==job and record.status=='Waiting'then
     for _,member in record.members do if member.id==p.UserId then p:SetAttribute('LobbyPartyId',record.id);p:SetAttribute('LobbyCircle',record.circle);record=update(record.id,function(current)if current then for _,member in current.members do if member.id==p.UserId then member.arrivingUntil=nil end end;return current end end)or record;push(record);break end end
    end
   end
   if p.Parent then event:FireClient(p,'state',snapshot(p))end
  end)
 end
end
Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(p)
 admittedPlayers[tostring(p.UserId)]=nil
 if not private then
  local count=0;for _,other in Players:GetPlayers()do if other~=p and other:GetAttribute('LobbyReady')and not other:GetAttribute('MissionActive')then count+=1 end end
  state:SetAttribute('LobbyPopulation',count)
 end
 if not p:GetAttribute('MissionActive') and not launchContexts[p]then pcall(leave,p)else releaseClaim(p)end
 launchContexts[p]=nil;lobbyTransfers[p]=nil
 task.spawn(function()savePrefs(p,preferences[p]);savedRevisions[p]=nil;revisions[p]=nil end);friends[p]=nil;limits[p]=nil;busy[p]=nil
 preferences[p]=nil;lobbyLoading[p]=nil;respawnAt[p]=nil
end)
for _,p in Players:GetPlayers()do joined(p)end
if not studio then pcall(function()Messages:SubscribeAsync('HorrorPartyInvites_v1',function(message)
 local data=message.Data
 if type(data)=='table' and type(data.userId)=='number' and type(data.expires)=='number' and data.expires>os.time()then
  local p=Players:GetPlayerByUserId(data.userId);if p and not p:GetAttribute('MissionActive')then event:FireClient(p,'invite',data)end
 end
end)end)end
task.spawn(function()
 while task.wait(15)do
  for id in pairs(owned)do
   pcall(function()
    local record=update(id,function(current)
     if not current then return nil end
     local live=Players:GetPlayerByUserId(current.owner)
     if not live then return nil end
     if current.status=='Waiting'then for i=#current.members,1,-1 do local member=current.members[i];if member.arrivingUntil and member.arrivingUntil<os.time() and not Players:GetPlayerByUserId(member.id)then table.remove(current.members,i)end end end
     current.updated=os.time();return current
    end)
    if record then push(record)else
     owned[id]=nil
     for _,slot in pairs(circleSlots)do if slot.record and slot.record.id==id then releaseClaim(slot.owner)end end
    end
   end)
  end
 end
end)
game:BindToClose(function()
 for id in pairs(owned)do pcall(remove,id)end
 local pending=0
 for _,p in Players:GetPlayers()do pending+=1;task.spawn(function()savePrefs(p);pending-=1 end)end
 local deadline=os.clock()+20;while pending>0 and os.clock()<deadline do task.wait(.1)end
end)

