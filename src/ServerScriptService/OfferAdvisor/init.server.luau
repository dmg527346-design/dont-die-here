-- Session-only contextual shop suggestions. Never grants or spends anything.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Http=game:GetService('HttpService')
local Progress=require(script.Parent.ProgressService)
local Catalog=require(RS:WaitForChild('LobbyShopCatalog'))
local Policy=require(script:WaitForChild('Policy'))
local event=RS:FindFirstChild('OfferPromptEvent')or Instance.new('RemoteEvent')
event.Name='OfferPromptEvent';event.Parent=RS
assert(event:IsA('RemoteEvent'),'OfferPromptEvent must be a RemoteEvent')
local TICK=2
local THREAT_DISTANCE=60
local DAMAGE_GRACE=15
local FRIEND_DISTANCE=28
local SOCIAL_SECONDS=20
local STUDIO_ROTATE_SECONDS=30
local sessions={}
local friendCache={}
local catalog={}
for _,offer in ipairs(Catalog.RobuxOffers)do catalog[offer.id]=offer end
local copy={
 free_revive={title='Want a second chance every level?',body='Second Chance gives you one free self revive every level. Take a look?',tag='SECOND CHANCE',accent='#A7CA7F'},
 revive_pack_3={title='Grab 3 backup revives',body='A pack of 3 self revive tokens for when a run goes wrong. View it?',tag='BACKUP PLAN',accent='#EDC568'},
 revive_token={title='Keep a backup revive',body='A saved self revive token can help when a run goes wrong. View it?',tag='BACKUP PLAN',accent='#EDC568'},
 jumpscare_all={title='A prank for your crew?',body='Save a group jumpscare charge for a surprise with friends. View it?',tag='FRIENDS & FRIGHTS',accent='#C5A4E5'},
 pass_hat_crown={title='Stand out with your crew',body='The crown cosmetic pass gives your character a royal look. View it?',tag='YOUR LOOK',accent='#EDC568'},
 pass_hat_halo={title='A little glow for your look',body='The halo cosmetic pass adds a bright finishing touch. View it?',tag='YOUR LOOK',accent='#A2D8E5'},
 vip={title='Make an entrance with friends',body='VIP adds a title and aura for your character. View the pass?',tag='VIP STYLE',accent='#C5A4E5'},
}
local function roundState()return RS:FindFirstChild('RecoveryRound')end
local function levelKey()
 local state=roundState()
 return tostring(state and state:GetAttribute('RunRevision')or 0)..':'..tostring(state and state:GetAttribute('Round')or 0)
end
local function publish(p,s)
 p:SetAttribute('OfferAdvisorDeathsRun',s.policy.deathsRun)
 p:SetAttribute('OfferAdvisorDeathsLevel',s.policy.deathsLevel)
 p:SetAttribute('OfferAdvisorShowsLevel',s.policy.shownLevel)
end
local function hide(p,s)
 local a=s.policy.active
 if a then s.policy.active=nil;if p.Parent then event:FireClient(p,'hide',{id=a.id})end end
end
local function reset(p,s)
 hide(p,s);s.policy=Policy.New(os.clock(),levelKey());s.nearFriendSeconds=0
 s.lastRound=0;s.lastRevision=nil;s.damageAt=-math.huge;s.nextPreview=0
 publish(p,s)
end
local function watchCharacter(p,s,c)
 if sessions[p]~=s or p.Character~=c then return end
 if s.deathConnection then s.deathConnection:Disconnect()end
 if s.healthConnection then s.healthConnection:Disconnect()end
 local h=c:FindFirstChildOfClass('Humanoid')or c:WaitForChild('Humanoid',10)
 if not h or sessions[p]~=s or p.Character~=c then return end
 local health=h.Health;local counted=false
 s.healthConnection=h.HealthChanged:Connect(function(value)
  if value<health then s.damageAt=os.clock()end;health=value
 end)
 s.deathConnection=h.Died:Connect(function()
  local state=roundState();local phase=state and state:GetAttribute('Phase')
  if counted or sessions[p]~=s or p:GetAttribute('MissionActive')~=true or phase=='Deploying'or phase=='Won'then return end
  counted=true;Policy.RecordDeath(s.policy);hide(p,s);publish(p,s)
 end)
end
local function joined(p)
 local s={policy=Policy.New(os.clock(),levelKey()),connections={},nearFriendSeconds=0,damageAt=-math.huge,nextPreview=0,lastRound=0}
 sessions[p]=s
 table.insert(s.connections,p.CharacterAdded:Connect(function(c)task.spawn(watchCharacter,p,s,c)end))
 table.insert(s.connections,p:GetAttributeChangedSignal('MissionActive'):Connect(function()
  if p:GetAttribute('MissionActive')==true then reset(p,s)else hide(p,s)end
 end))
 if p.Character then task.spawn(watchCharacter,p,s,p.Character)end
 publish(p,s)
end
local function friends(p,q)
 local low,high=math.min(p.UserId,q.UserId),math.max(p.UserId,q.UserId)
 local key=tostring(low)..':'..tostring(high)
 local cached=friendCache[key]
 if cached and os.clock()<cached.expires then return cached.value==true end
 if cached and cached.pending then return false end
 local record={value=false,pending=true,expires=0};friendCache[key]=record
 task.spawn(function()
  local ok,value=pcall(function()return p:IsFriendsWith(q.UserId)end)
  record.value=ok and value==true;record.pending=false;record.expires=os.clock()+120
 end)
 return false
end
local function isHolding(p)
 local count=p:GetAttribute('CursedHeldCount')
 if type(count)=='number'and count>0 then return true end
 local map=workspace:FindFirstChild('Mansion')
 local items=map and map:FindFirstChild('Interactive')
 if items then for _,m in ipairs(items:GetChildren())do
  if m:GetAttribute('HeldBy')==p.UserId then return true end
 end end
 return false
end
local function context(p,s,now)
 local state=roundState();local phase=state and state:GetAttribute('Phase')
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
 local mission=p:GetAttribute('MissionActive')==true
 local safe=r~=nil and h~=nil and h.Health>0 and p:GetAttribute('RoundDead')~=true
 if p:GetAttribute('MonsterJumpscareActive')or p:GetAttribute('Reviving')or p:GetAttribute('Hiding')or p:GetAttribute('PhysicalGrabActive')or isHolding(p)or now-s.damageAt<DAMAGE_GRACE then safe=false end
 if c and c:GetAttribute('RecoverySpawnReady')==false then safe=false end
 local monsters=workspace:FindFirstChild('RoamingCreatures')
 if monsters then for _,m in ipairs(monsters:GetChildren())do
  if m:IsA('Model')then
   local mr=m.PrimaryPart or m:FindFirstChild('HumanoidRootPart')
   if m:GetAttribute('AIState')=='Chase'or(r and mr and(mr.Position-r.Position).Magnitude<THREAT_DISTANCE)then safe=false;break end
  end
 end end
 -- A card already on screen only hides for real danger to this player (owner 2026-10-25: picking up an item or a
 -- chase somewhere else in the map hid it after a second): dead, jumpscared, grabbed, just hit, or a monster close by.
 local danger=not(r~=nil and h~=nil and h.Health>0 and p:GetAttribute('RoundDead')~=true)or p:GetAttribute('MonsterJumpscareActive')==true or p:GetAttribute('PhysicalGrabActive')==true or now-s.damageAt<DAMAGE_GRACE
 if not danger and monsters and r then for _,m in ipairs(monsters:GetChildren())do
  local mr=m:IsA('Model')and(m.PrimaryPart or m:FindFirstChild('HumanoidRootPart'))
  if mr and(mr.Position-r.Position).Magnitude<THREAT_DISTANCE then danger=true;break end
 end end
 local count,nearSocial=0,false
 for _,q in ipairs(Players:GetPlayers())do if q:GetAttribute('MissionActive')==true then
  count+=1
  if q~=p and r then local qc=q.Character;local qr=qc and qc:FindFirstChild('HumanoidRootPart');local qh=qc and qc:FindFirstChildOfClass('Humanoid')
   if qr and qh and qh.Health>0 and(qr.Position-r.Position).Magnitude<=FRIEND_DISTANCE and friends(p,q)and(qr.AssemblyLinearVelocity.Magnitude>1 or r.AssemblyLinearVelocity.Magnitude>1 or p:GetAttribute('PhysicalGrabActive')or q:GetAttribute('PhysicalGrabActive'))then nearSocial=true end
  end
 end end
 if nearSocial then s.nearFriendSeconds=math.min(SOCIAL_SECONDS+TICK,s.nearFriendSeconds+TICK)else s.nearFriendSeconds=math.max(0,s.nearFriendSeconds-TICK)end
 local owned={};local simulated=p:GetAttribute('AdminSimulateNoPasses')==true
 for id,offer in pairs(catalog)do if offer.kind=='Pass'then
  if simulated then owned[id]=false else owned[id]=p:GetAttribute('Pass_'..id)end
 end end
 local snapshot=Progress.Snapshot(p)
 local modal=p:GetAttribute('VanShopOpen')or p:GetAttribute('AppearanceOpen')or p:GetAttribute('MapOpen')or p:GetAttribute('AdminPassPanelOpen')
 return {mission=mission,phase=phase,safe=safe,danger=danger,modal=modal==true,ready=snapshot.ready==true,veteran=((snapshot.stats and snapshot.stats.RunsCompleted) or 0)>0,solo=count<=1,social=s.nearFriendSeconds>=SOCIAL_SECONDS,owned=owned,reviveTokens=snapshot.reviveTokens or 0,jumpscareCharges=snapshot.jumpscareCharges or 0,freeReviveAvailable=owned.free_revive==true and p:GetAttribute('FreeReviveUsed')~=true}
end
local function show(p,s,id,reason,now,permanent)
 local offer,words=catalog[id],copy[id]
 if not offer or not words then return false end
 local active=Policy.Show(s.policy,id,now,Http:GenerateGUID(false),permanent)
 local payload={id=active.id,offer=id,title=words.title,body=words.body,reason=reason,tag=words.tag,accent=words.accent,seconds=Policy.Lifetime,permanent=permanent==true}
 if type(offer.price)=='number'then payload.price=offer.price end
 event:FireClient(p,'show',payload);s.nextPreview=now+STUDIO_ROTATE_SECONDS;publish(p,s)
 return true
end
event.OnServerEvent:Connect(function(p,action,id,choice)
 if action~='answer'or type(id)~='string'or #id>80 or type(choice)~='string'or #choice>8 then return end
 local s=sessions[p];if not s then return end
 local now=os.clock()
 if s.lastAnswer and now-s.lastAnswer<.2 then return end;s.lastAnswer=now
 local accepted,offer=Policy.Answer(s.policy,id,choice,now)
 if not accepted then return end
 p:SetAttribute('OfferAdvisorLastAnswer',choice);p:SetAttribute('OfferAdvisorLastOffer',offer)
 s.nextPreview=now+10
 -- Yes only acknowledges interest. Shop opening and purchase remain existing client flows.
 event:FireClient(p,'hide',{id=id})
end)
Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(p)
 local s=sessions[p];sessions[p]=nil;if not s then return end
 for _,connection in ipairs(s.connections)do connection:Disconnect()end
 if s.deathConnection then s.deathConnection:Disconnect()end
 if s.healthConnection then s.healthConnection:Disconnect()end
 for key in pairs(friendCache)do if key:match('^'..p.UserId..':')or key:match(':'..p.UserId..'$')then friendCache[key]=nil end end
end)
for _,p in ipairs(Players:GetPlayers())do joined(p)end
task.spawn(function()
 while task.wait(TICK)do
  local now=os.clock()
  for p,s in pairs(sessions)do if p.Parent==Players then
   local state=roundState();local round=state and state:GetAttribute('Round')or 0;local revision=state and state:GetAttribute('RunRevision')or 0
   if s.lastRevision~=nil and revision~=s.lastRevision and round<=1 then reset(p,s)end
   s.lastRound=round;s.lastRevision=revision
   if Policy.SetLevel(s.policy,levelKey())then publish(p,s);event:FireClient(p,'hide')end
   local c=context(p,s,now)
   p:SetAttribute('OfferAdvisorContext',not c.safe and 'unsafe'or c.solo and 'solo'or c.social and 'social'or 'party')
   local permanent=Run:IsStudio()and script:GetAttribute('StudioPermanentPrompt')==true
   if s.policy.active and(not c.mission or c.danger or c.modal or not ({Searching=true,Returning=true,Selling=true})[c.phase])then hide(p,s)end
   if Policy.Expire(s.policy,now)then event:FireClient(p,'hide')end
   if Policy.CanShow(s.policy,c,now,permanent)and(not permanent or now>=s.nextPreview)then
    local id,reason=Policy.Select(s.policy,c)
    -- Explicit Studio demo may display a consumable even when test inventory is already stocked.
    if permanent and not id and not s.policy.declined.revive_pack_3 then id,reason='revive_pack_3','studio_preview'end
    if id then show(p,s,id,reason,now,permanent)end
   end
  end end
 end
end)
