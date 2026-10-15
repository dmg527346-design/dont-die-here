-- Server-only authority. Replicated attributes are UI signals, never authorization inputs.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local Store=game:GetService('DataStoreService'):GetDataStore('DDH_AdminAccess_v1'..(Run:IsStudio()and '_Studio'or''))
local OWNER_ID=315936607
local nativeTest=false
if Run:IsStudio()then local ok,args=pcall(function()return game:GetService('StudioTestService'):GetTestArgs()end);nativeTest=ok and type(args)=='table'and args.kind=='AdminPanelNative'end
local M={};local grants,ready,versions,saving={},{},{},{}
local changed=Instance.new('BindableEvent');M.Changed=changed.Event
local function connected(p)return typeof(p)=='Instance'and p:IsA('Player')and p.Parent==Players end
function M.IsOwner(p)return connected(p)and(p.UserId==OWNER_ID or nativeTest and p.UserId==-1)end
function M.IsAdmin(p)return connected(p)and(M.IsOwner(p)or grants[p]==true)end
function M.Ready(p)return ready[p]==true end
local function publish(p)
 if not connected(p)then return end
 p:SetAttribute('AdminOwner',M.IsOwner(p));p:SetAttribute('AdminAuthorized',M.IsAdmin(p));p:SetAttribute('AdminAccessReady',ready[p]==true)
 changed:Fire(p,M.IsAdmin(p))
end
function M.Load(p)
 if not connected(p)then return false,'Player left.'end
 versions[p]=(versions[p]or 0)+1;local version=versions[p]
 if M.IsOwner(p)then ready[p]=true;publish(p);return true end
 local options=Instance.new('DataStoreGetOptions');options.UseCache=false
 local ok,row=pcall(function()return Store:GetAsync('user_'..p.UserId,options)end)
 if not connected(p)or versions[p]~=version then return false,'Player changed.'end
 grants[p]=ok and type(row)=='table'and row.granted==true or false;ready[p]=true;publish(p)
 return ok,ok and 'Access loaded.'or'Access unavailable; no admin privileges were enabled.'
end
function M.Set(actor,userId,on)
 if not M.IsOwner(actor)then return false,'Only the owner can grant or revoke admin.'end
 if type(userId)~='number'or userId~=userId or userId%1~=0 or math.abs(userId)>9007199254740991 or(userId<=0 and not nativeTest)or type(on)~='boolean'then return false,'Invalid player or access choice.'end
 local target=Players:GetPlayerByUserId(userId)
 if not connected(target)then return false,'Choose a player currently in this server.'end
 if M.IsOwner(target)then return false,'The owner cannot be revoked or delegated.'end
 if not M.Ready(target)then return false,'That player’s access is still loading.'end
 if saving[userId]then return false,'Admin access is already being saved for this player.'end
 saving[userId]=true
 local ok=pcall(function()
  Store:UpdateAsync('user_'..userId,function(old)
   local revision=type(old)=='table'and tonumber(old.revision)or 0
   return {version=1,granted=on,by=OWNER_ID,at=DateTime.now().UnixTimestamp,revision=(revision or 0)+1}
  end)
 end)
 saving[userId]=nil
 if not ok then return false,'Could not save admin access. No access was changed; try again.'end
 if connected(target)then versions[target]=(versions[target]or 0)+1;grants[target]=on;ready[target]=true;publish(target)end
 return true,(on and 'Admin granted to @'or'Admin revoked from @')..target.Name..'. Saved for future servers.'
end
function M.Roster()
 local rows={}
 for _,p in Players:GetPlayers()do rows[#rows+1]={id=p.UserId,name=p.Name,displayName=p.DisplayName,admin=M.IsAdmin(p),owner=M.IsOwner(p),ready=M.Ready(p),dead=p:GetAttribute('RoundDead')==true,mission=p:GetAttribute('MissionActive')==true}end
 table.sort(rows,function(a,b)return a.name:lower()<b.name:lower()end);return rows
end
Players.PlayerAdded:Connect(function(p)task.spawn(M.Load,p)end)
Players.PlayerRemoving:Connect(function(p)grants[p]=nil;ready[p]=nil;versions[p]=nil end)
for _,p in Players:GetPlayers()do task.spawn(M.Load,p)end
return M
