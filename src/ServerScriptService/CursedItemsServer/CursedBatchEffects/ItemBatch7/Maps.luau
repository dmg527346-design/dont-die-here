-- Map items (CursedA 2026-10-27, draft 2026-10-26): cursed items that only spawn on one map kind (CursedCatalog
-- map='Mall'|'School'; CursedItemsServer.eligibleItems honours `map`). Driven by CursedBatchEffects.ItemBatch7
-- (Pickup / ClearPlayer / ClearLevel), own 4 Hz Heartbeat. Uses the level's GeneratedGraph (rooms: name, type, purpose, level, x1..z2, neighbors) for the layout.
--   FoodCourtPager (Mall)    buzzes and tugs the holder to the Food Court; arriving there = value x1.75, 75 s held = cancelled.
--   HallPass       (School)  walking in a Hallway room = monsters ignore you (DisguiseUntil), 45 s per pass; running = whistle.
-- Client half: CurseEffectsClient.ItemBatch7Client (reads the player attributes below; no remotes of its own).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local HS=game:GetService('HttpService')
local Audio=require(game.ServerScriptService.GameplayAudioServer)
local Feedback=require(script.Parent.Parent:WaitForChild('ItemBatch6'):WaitForChild('Feedback'))
local M={}
local TICK=.25
local LEASE=.5
-- FoodCourtPager
local PAGER_BUZZ_EVERY=3      -- seconds between buzzes while held
local PAGER_HEAR_RADIUS=30    -- a buzz sends the nearest monster inside this radius to the holder
local PAGER_DEADLINE=75       -- held seconds before the order is cancelled (time on the floor or in the cart does not count)
local PAGER_BONUS=1.75        -- sale value multiplier once the pager reaches the Food Court
local PAGER_TARGETS={'Dining','Kitchen'} -- Mall Dining='Food Court', Kitchen='Food Court Kitchen' (MapGen.Profiles purpose)
-- HallPass
local PASS_SECONDS=45         -- protected hallway seconds per pass per level (stored on the model, so a teammate gets the rest)
local PASS_REVOKE=8           -- seconds the pass stops working after the holder is caught running
local PASS_RUN_GRACE=.5       -- seconds of running in a hall before the whistle
local PASS_LOCKER_RADIUS=24   -- locker banks this close bang when the whistle blows
local ITEM_IDS={FoodCourtPager=true,HallPass=true}
local items,leases,aux,disguise={},{},{},{}
local cache={raw=nil,graph=nil,byName={},lockers=nil}

local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function rootOf(p) local c=living(p);local r=c and c:FindFirstChild('HumanoidRootPart');return r and r:IsA('BasePart') and r or nil end
local function lease(p,key,now)
 local stamp=math.max(p:GetAttribute(key)or 0,now+LEASE)
 p:SetAttribute(key,stamp);leases[p]=leases[p]or{};leases[p][key]=stamp
end
-- Helper attributes that only mean something while their lease is live; recorded so ClearPlayer removes them.
local function setAux(p,key,value)
 if p:GetAttribute(key)~=value then p:SetAttribute(key,value) end
 aux[p]=aux[p]or{};aux[p][key]=true
end
-- DisguiseUntil (os.clock, read by CreatureRoamServer + SkitterController) already means "monsters do not see or catch".
-- Never shorten another owner's value (THE VEIL card, Mask); only extend it while the pass works.
local function hide(p,clock)
 local stamp=math.max(p:GetAttribute('DisguiseUntil')or 0,clock+LEASE)
 p:SetAttribute('DisguiseUntil',stamp);disguise[p]=stamp
end
local function clearPlayerAttrs(p)
 for key,stamp in pairs(leases[p]or{}) do if p:GetAttribute(key)==stamp then p:SetAttribute(key,nil) end end
 for key in pairs(aux[p]or{}) do p:SetAttribute(key,nil) end
 if disguise[p] and p:GetAttribute('DisguiseUntil')==disguise[p] then p:SetAttribute('DisguiseUntil',nil) end
 leases[p]=nil;aux[p]=nil;disguise[p]=nil
end
local function notice(p,text)
 local event=RS:FindFirstChild('CursedEvent') -- CursedItemsServer's notice channel (client shows it for 6 s)
 if event and p.Parent then event:FireClient(p,'notice',text) end
end
local function setValue(m,v)
 v=math.max(0,math.floor(v));m:SetAttribute('Value',v);m:SetAttribute('LootValue',v)
end
local function valueOf(m) return m:GetAttribute('Value')or m:GetAttribute('LootValue')or 0 end

-- Layout ------------------------------------------------------------------------------------------------------------
local function graph()
 local map=workspace:FindFirstChild('Mansion');local v=map and map:FindFirstChild('GeneratedGraph')
 if not v then return nil,cache.byName end
 if cache.raw~=v.Value then
  local ok,g=pcall(HS.JSONDecode,HS,v.Value)
  cache.raw=v.Value;cache.graph=ok and g or nil;cache.byName={};cache.lockers=nil
  if ok and g then for _,r in ipairs(g.rooms or {}) do cache.byName[r.name]=r end end
 end
 return cache.graph,cache.byName
end
local function floorH() local g=graph();return g and g.floorHeight or 16 end
local function roomAt(pos)
 local g=graph();if not g then return nil end
 local level=math.floor((pos.Y+2)/floorH());local other
 for _,r in ipairs(g.rooms or {}) do
  if r.x1 and pos.X>=r.x1 and pos.X<=r.x2 and pos.Z>=r.z1 and pos.Z<=r.z2 then
   if (r.level or 0)==level then return r end
   other=other or r
  end
 end
 return other
end
local function centre(r) return Vector3.new((r.x1+r.x2)/2,(r.level or 0)*floorH()+3,(r.z1+r.z2)/2) end
local function lockers()
 graph();if cache.lockers then return cache.lockers end
 local list={};local map=workspace:FindFirstChild('Mansion')
 if map then for _,d in ipairs(map:GetDescendants()) do if d.Name=='SchoolHallLockers' and d:IsA('Model') then table.insert(list,d) end end end
 cache.lockers=list;return list
end

-- Monsters ----------------------------------------------------------------------------------------------------------
local function monsters()
 local out={};local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,enemy in ipairs(folder:GetChildren()) do
  local primary=enemy:IsA('Model') and enemy.PrimaryPart;local h=enemy:FindFirstChildOfClass('Humanoid')
  if primary and (not h or h.Health>0) then table.insert(out,enemy) end
 end end
 return out
end
local function nearest(pos,range)
 local best,bestD=nil,range or math.huge
 for _,enemy in ipairs(monsters()) do local d=(enemy.PrimaryPart.Position-pos).Magnitude;if d<bestD then best,bestD=enemy,d end end
 return best,bestD
end
-- CreatureRoamServer consumes LurePosition/LureUntil with os.clock() and Brain:Hear(...,'Object').
local function lure(enemy,pos,seconds) enemy:SetAttribute('LurePosition',pos);enemy:SetAttribute('LureUntil',os.clock()+seconds) end

-- Item behaviour ----------------------------------------------------------------------------------------------------
local Items={}

Items.FoodCourtPager={
 pickup=function(m,s,p)
  if s.state==nil then
   local g,byName=graph();local target
   if g then
    for _,want in ipairs(PAGER_TARGETS) do
     for _,r in ipairs(g.rooms or {}) do if r.type==want and r.name~=g.start and r.x1 then target=r;break end end
     if target then break end
    end
    if not target and g.metrics and g.metrics.deepestRoom then target=byName[g.metrics.deepestRoom] end
   end
   if not target then s.state='quiet';return end
   s.target=target;s.targetPos=centre(target);s.left=PAGER_DEADLINE;s.nextBuzz=0;s.state='ringing'
   m:SetAttribute('PagerState','ringing');Feedback.React(p,'PagerStart','gasp',1.4)
   notice(p,('BZZT! Your order is ready at the %s. Bring the pager there!'):format(target.purpose or 'Food Court'))
  elseif s.state=='ringing' then
   notice(p,('The pager still wants the %s. %d s left.'):format(s.target.purpose or 'Food Court',math.ceil(s.left)))
  end
 end,
 tick=function(m,s,p,now,clock)
  if s.state~='ringing' then return end
  local r=rootOf(p);if not r then return end
  s.left-=TICK
  local here=roomAt(r.Position)
  if here and here.name==s.target.name then
   s.state='collected';m:SetAttribute('PagerState','collected');setValue(m,valueOf(m)*PAGER_BONUS)
   Audio.Play('DinnerBell',m);setAux(p,'PagerDoneAt',now);Feedback.React(p,'PagerCollected','grin',2.5)
   notice(p,('Order collected! The pager is worth $%d now.'):format(valueOf(m)));return
  end
  if s.left<=0 then
   s.state='cancelled';m:SetAttribute('PagerState','cancelled');setValue(m,valueOf(m)/2)
   Audio.Play('TelephoneRing',m);setAux(p,'PagerDoneAt',now);Feedback.React(p,'PagerCancelled','frown',2.5)
   local enemy=nearest(r.Position);if enemy then lure(enemy,r.Position,10) end
   notice(p,'ORDER CANCELLED! The pager screamed for help. Value halved.');return
  end
  lease(p,'PagerUntil',now)
  setAux(p,'PagerTargetPos',s.targetPos);setAux(p,'PagerTargetName',s.target.purpose or 'Food Court');setAux(p,'PagerSecondsLeft',math.ceil(s.left))
  if clock>=s.nextBuzz then
   s.nextBuzz=clock+PAGER_BUZZ_EVERY;Audio.Play('ItemRattle',m);setAux(p,'PagerBuzzAt',now);Feedback.Face(p,'gasp',.6)
   local enemy=nearest(r.Position,PAGER_HEAR_RADIUS);if enemy then lure(enemy,r.Position,6) end
  end
 end,
}

Items.HallPass={
 pickup=function(m,s,p)
  local left=m:GetAttribute('PassSecondsLeft')or PASS_SECONDS
  if left<=0 then notice(p,'This hall pass is used up. TARDY!');Feedback.React(p,'PassTardy','frown',1.5)
  else Feedback.React(p,'PassGrab','grin',1.5);notice(p,('Hall pass: WALK through hallways and monsters leave you alone (%d s left). No running!'):format(math.ceil(left))) end
 end,
 tick=function(m,s,p,now,clock)
  local r=rootOf(p);if not r then return end
  local left=m:GetAttribute('PassSecondsLeft')or PASS_SECONDS
  local here=roomAt(r.Position);local inHall=here~=nil and here.type=='Hall'
  local v=r.AssemblyLinearVelocity;local speed=Vector3.new(v.X,0,v.Z).Magnitude
  local walk=(p:GetAttribute('UpgradeWalkSpeed')or 13.5)*(p:GetAttribute('CursedSpeedMultiplier')or 1)
  s.runFor=(inHall and speed>walk*1.2+1) and (s.runFor or 0)+TICK or 0
  local state
  if left<=0 then state='tardy'
  elseif clock<(s.revokedUntil or 0) then state='revoked'
  elseif not inHall then state='room'
  elseif s.runFor>=PASS_RUN_GRACE then
   state='revoked';s.revokedUntil=clock+PASS_REVOKE;s.runFor=0
   Audio.Play('Whistle',r)
   local banged=0
   for _,bank in ipairs(lockers()) do
    if banged<3 and (bank:GetPivot().Position-r.Position).Magnitude<PASS_LOCKER_RADIUS then banged+=1;Audio.Play('MetalImpact',bank:GetPivot().Position) end
   end
   local enemy=nearest(r.Position,80);if enemy then lure(enemy,r.Position,8) end
   setAux(p,'HallPassWhistleAt',now);Feedback.React(p,'PassWhistle','gasp',1.6)
   notice(p,('NO RUNNING IN THE HALLS! Pass taken away for %d s.'):format(PASS_REVOKE))
  else
   state='safe';left=math.max(0,left-TICK);m:SetAttribute('PassSecondsLeft',left);hide(p,clock);Feedback.Hold(p,'grin')
   if left<=0 then
    state='tardy';Audio.Play('DinnerBell',r)
    local enemy=nearest(r.Position);if enemy then lure(enemy,r.Position,10) end
    notice(p,'RIIING! TARDY! The hall pass ran out.');Feedback.React(p,'PassTardy','frown',2)
   end
  end
  lease(p,'HallPassUntil',now);setAux(p,'HallPassState',state);setAux(p,'HallPassLeft',math.ceil(left))
 end,
}

-- Ownership (same shape as ItemBatch5) ----------------------------------------------------------------------------
local function currentHolder(m)
 local owner=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 return m:IsDescendantOf(workspace) and living(owner) and not m:GetAttribute('Selling') and not m:GetAttribute('CargoStored') and owner or nil
end
local function track(m,id)
 local s=items[m];if s then s.holder=currentHolder(m);return s end
 s={id=id,connections={}};items[m]=s
 table.insert(s.connections,m.Destroying:Connect(function()
  for _,connection in ipairs(s.connections) do connection:Disconnect() end
  items[m]=nil
 end))
 s.holder=currentHolder(m);return s
end
function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId');if not ITEM_IDS[id] then return end
 if not living(p) or not m.PrimaryPart then return end
 local s=track(m,id);s.holder=p
 Items[id].pickup(m,s,p)
 Items[id].tick(m,s,p,workspace:GetServerTimeNow(),os.clock()) -- leases go live on the grab frame, not 0.25 s later
end
function M.ClearPlayer(p)
 clearPlayerAttrs(p)
 for _,s in pairs(items) do if s.holder==p then s.holder=nil end end
end
function M.ClearLevel()
 for _,p in ipairs(Players:GetPlayers()) do M.ClearPlayer(p) end
 for _,s in pairs(items) do for _,connection in ipairs(s.connections) do connection:Disconnect() end end
 table.clear(items);table.clear(leases);table.clear(aux);table.clear(disguise)
 cache.raw=nil;cache.graph=nil;cache.byName={};cache.lockers=nil
end
local function lobbyOnly()
 local state=RS:FindFirstChild('LobbyState')
 if not state or state:GetAttribute('Mode')~='Menu' then return false end
 for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('MissionActive')==true then return false end end
 return true
end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK then return end;elapsed=0
 if lobbyOnly() or not next(items) then return end
 local now,clock=workspace:GetServerTimeNow(),os.clock()
 local held={}
 for m,s in pairs(items) do
  if m.Parent then
   local owner=currentHolder(m)
   if s.holder and s.holder~=owner then -- dropped, stored or sold: its helper attrs end with the lease
    for key in pairs(aux[s.holder]or{}) do if key~='PagerDoneAt' and key~='HallPassWhistleAt' then s.holder:SetAttribute(key,nil);aux[s.holder][key]=nil end end
   end
   s.holder=owner
   if owner then held[owner]=true;Items[s.id].tick(m,s,owner,now,clock) end
  end
 end
 for p in pairs(leases) do if not held[p] and not living(p) then M.ClearPlayer(p) end end
end)
Players.PlayerRemoving:Connect(function(p) M.ClearPlayer(p) end)
return M
