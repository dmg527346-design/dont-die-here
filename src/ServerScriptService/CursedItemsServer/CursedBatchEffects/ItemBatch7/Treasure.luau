-- Rare treasures (CursedA 2026-10-27, draft 2026-10-26): GildedIdol, MansionCrown. Driven by CursedBatchEffects.ItemBatch7.
-- Placement and value belong to CursedItemsServer.restock and LootBudget.Treasure (a fixed rule from the catalog's
-- `treasure` gate: one per level from level 3, deepest room; never random, never paid). This module owns only the curses
-- of the treasures listed in ITEM_IDS; another treasure (e.g. SongbirdMusicBox) only needs its catalog entry for placement
-- and keeps its own curse in its own batch.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local HttpService=game:GetService('HttpService')
local Audio=require(game:GetService('ServerScriptService').GameplayAudioServer)
local Feedback=require(script.Parent.Parent:WaitForChild('ItemBatch6'):WaitForChild('Feedback'))
local M={}
local TICK=.25
local LEASE=.5
-- Gilded idol: the dark eats its trail room by room.
local IDOL_FIRST_DARK=3 -- the treasure room goes dark 3 s after the first lift
local IDOL_STEP=9 -- then one more room of the idol's trail every 9 s
local IDOL_CAUGHT_PAUSE=12 -- after the dark reaches the idol's room it rests 12 s (then wakes again if still there)
local IDOL_WAKE_LURE=8 -- the woken monster walks to the idol for 8 s (CreatureRoamServer LurePosition/LureUntil, os.clock)
local IDOL_WAKE_LOUDNESS=60
-- Mansion crown: worn on grab; every monster that sees the wearer prefers them (CreatureRoamServer hooks read CrownedUntil).
local CROWN_OFFSET=CFrame.new(0,.95,0)
local CROWN_BARE_GRACE=6 -- off a head (and away from the van) for 6 s, it starts chiming for a head
local CROWN_CHIME_EVERY=3
local CROWN_CHIME_LOUDNESS=45
local VAN_QUIET_RADIUS=30
local ITEM_IDS={GildedIdol=true,MansionCrown=true}
local items,wear,leases,darkened={},{},{},{}
local fixtures -- lights and neon pieces of the current map, cached on the first idol lift of a level
local roomCache:{[string]:any}={}
local detach,clearHold,setParts

local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function lease(p,key,now)
 local stamp=math.max(p:GetAttribute(key)or 0,now+LEASE)
 p:SetAttribute(key,stamp);leases[p]=leases[p]or{};leases[p][key]=stamp
end
local function clearLeases(p)
 for key,stamp in pairs(leases[p]or{}) do if p:GetAttribute(key)==stamp then p:SetAttribute(key,nil) end end
 leases[p]=nil
end
local function mansion()return workspace:FindFirstChild('Mansion')end
local function rooms(map)
 local graph=map and map:FindFirstChild('GeneratedGraph')
 if not graph then return {} end
 if roomCache.source~=graph.Value then
  roomCache.source=graph.Value;roomCache.list={}
  local ok,data=pcall(HttpService.JSONDecode,HttpService,graph.Value)
  if ok and type(data)=='table' and data.rooms then for _,r in data.rooms do if r.x1 and r.x2 and r.z1 and r.z2 then table.insert(roomCache.list,r) end end end
 end
 return roomCache.list
end
local function roomAt(map,pos)
 for _,r in rooms(map) do
  local floor=(r.level or 0)*16
  if pos.X>=r.x1 and pos.X<=r.x2 and pos.Z>=r.z1 and pos.Z<=r.z2 and pos.Y>=floor-2 and pos.Y<floor+15 then return r end
 end
 return nil
end
local function roomCentre(r)return Vector3.new((r.x1+r.x2)/2,(r.level or 0)*16+10,(r.z1+r.z2)/2)end
local function nearVan(pos)
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
 return van~=nil and (van:GetPivot().Position-pos).Magnitude<VAN_QUIET_RADIUS
end
local function evidence(pos,loudness,kind)
 local bus=SS:FindFirstChild('MonsterEvidence');if bus then bus:Fire(pos,loudness,kind)end
end
local function lure(enemy,pos,clock,seconds)
 -- A fresh position each time: CreatureRoamServer only consumes a lure whose position changed (consumedLure).
 enemy:SetAttribute('LurePosition',pos+Vector3.new(math.random()*.2-.1,0,math.random()*.2-.1))
 enemy:SetAttribute('LureUntil',clock+seconds)
end

-- Gilded idol ----------------------------------------------------------------------------------------------------
local function collectFixtures(map)
 fixtures={}
 local interactive=map:FindFirstChild('Interactive')
 for _,x in map:GetDescendants() do
  if interactive and x:IsDescendantOf(interactive) then continue end
  local part=if x:IsA('Light') then x.Parent elseif x:IsA('BasePart') and x.Material==Enum.Material.Neon then x else nil
  if part and part:IsA('BasePart') then table.insert(fixtures,{x=x,part=part}) end
 end
end
local function darkenRoom(map,r)
 if not r or darkened[r.name] then return false end
 if not fixtures then collectFixtures(map) end
 local saved={};darkened[r.name]=saved
 local floor=(r.level or 0)*16
 for _,f in fixtures do
  local x,part=f.x,f.part
  if x.Parent and part.Parent then
   local p=part.Position
   if p.X>=r.x1-.5 and p.X<=r.x2+.5 and p.Z>=r.z1-.5 and p.Z<=r.z2+.5 and p.Y>=floor-1 and p.Y<floor+16 then
    if x:IsA('Light') then
     if x.Enabled then x.Enabled=false;table.insert(saved,{x,'Enabled',true}) end
    elseif x.Material==Enum.Material.Neon then
     table.insert(saved,{x,'Material',x.Material});table.insert(saved,{x,'Color',x.Color})
     x.Material=Enum.Material.SmoothPlastic;x.Color=x.Color:Lerp(Color3.new(0,0,0),.7)
    end
   end
  end
 end
 return true
end
local function restoreLights()
 for _,saved in pairs(darkened) do for _,entry in ipairs(saved) do local x,key,value=entry[1],entry[2],entry[3];if x.Parent then x[key]=value end end end
 table.clear(darkened)
end
local function wakeNearest(pos,clock)
 local creatures=workspace:FindFirstChild('RoamingCreatures')
 local best,distance
 if creatures then for _,enemy in ipairs(creatures:GetChildren()) do
  local primary=enemy:IsA('Model') and enemy.PrimaryPart;local h=enemy:FindFirstChildOfClass('Humanoid')
  if primary and (not h or h.Health>0) then local d=(primary.Position-pos).Magnitude;if not distance or d<distance then best,distance=enemy,d end end
 end end
 if best then lure(best,pos,clock,IDOL_WAKE_LURE) end
 evidence(pos,IDOL_WAKE_LOUDNESS,'IdolWake')
end
local function liftIdol(m,s,clock)
 if s.lifted then return end
 local map=mansion();local origin=map and roomAt(map,m.PrimaryPart.Position)
 s.lifted=true;s.trail={};s.roomByName={};s.dark=0;s.nextStep=clock+IDOL_FIRST_DARK
 if origin then s.trail[1]=origin.name;s.roomByName[origin.name]=origin end
 m:SetAttribute('IdolLifted',true);Audio.Play('StingChoir',m)
end
-- Everyone within reach of the idol flinches when the dark takes a room (holder first).
local function flinch(m,key,mood,seconds,radius)
 local pos=m.PrimaryPart and m.PrimaryPart.Position;if not pos then return end
 for _,q in ipairs(Players:GetPlayers()) do
  local c=living(q);local r=c and c:FindFirstChild('HumanoidRootPart')
  if r and (r.Position-pos).Magnitude<radius then Feedback.React(q,key,mood,seconds) end
 end
end
local function idolTick(m,s,clock)
 local map=mansion()
 if not s.lifted or not m.PrimaryPart or not map or m:GetAttribute('Selling') then return end
 local here=roomAt(map,m.PrimaryPart.Position)
 if here and s.trail[#s.trail]~=here.name then table.insert(s.trail,here.name);s.roomByName[here.name]=here end
 if #s.trail==0 then return end
 if clock>=s.nextStep then
  local current=#s.trail
  if s.dark==0 or s.dark<current-1 then
   -- The dark is still behind the idol: one more room of its trail goes out.
   s.dark+=1;local room=s.roomByName[s.trail[s.dark]]
   if darkenRoom(map,room) then Audio.Play('BulbCrack',roomCentre(room));flinch(m,'IdolDark','gasp',1.2,45) end
   s.nextStep=clock+IDOL_STEP
  else
   -- The dark has caught up: the idol's own room goes out and the nearest monster wakes and comes to look.
   s.dark=current;darkenRoom(map,s.roomByName[s.trail[current]])
   Audio.Play('BulbCrack',m);Audio.Play('MonsterNotice',m)
   wakeNearest(m.PrimaryPart.Position,clock);flinch(m,'IdolWake','gasp',2.2,45)
   m:SetAttribute('IdolWokeAt',workspace:GetServerTimeNow())
   s.nextStep=clock+IDOL_CAUGHT_PAUSE
  end
 end
 m:SetAttribute('IdolLightRooms',math.max(0,#s.trail-s.dark))
 m:SetAttribute('IdolNextStepAt',workspace:GetServerTimeNow()+math.max(0,s.nextStep-clock))
end

-- Mansion crown --------------------------------------------------------------------------------------------------
local function releaseWear(m)
 local s=wear[m];if not s then return false end
 wear[m]=nil
 local stamps=leases[s.owner];local stamp=stamps and stamps.CrownedUntil
 if stamp then
  if s.owner:GetAttribute('CrownedUntil')==stamp then s.owner:SetAttribute('CrownedUntil',nil) end
  stamps.CrownedUntil=nil
 end
 for _,key in ipairs({'ItemWearOwner','ItemWearRole','ItemWearOffset','ItemWearStart','ItemWearEnd'}) do m:SetAttribute(key,nil) end
 local item=items[m];if item then item.bareSince=os.clock() end
 if not m.Parent then return true end
 if m:GetAttribute('HeldBy')==s.owner.UserId and detach then
  -- Registry/inventory bookkeeping stays with CursedItemsServer.
  detach(s.owner,m,false,true)
 else
  if clearHold then clearHold(m) end
  if setParts then setParts(m,false,true) end
  local root=s.owner.Character and s.owner.Character:FindFirstChild('HumanoidRootPart')
  if root and m.PrimaryPart then m:PivotTo(root.CFrame*CFrame.new(0,0,-3));m.PrimaryPart.AssemblyLinearVelocity=Vector3.new(0,-1,0) end
 end
 return true
end
local function crownOn(p,m,c,now)
 local head=c:FindFirstChild('Head');if not head or not clearHold or not detach or not setParts then return end
 clearHold(m);m:SetAttribute('HeldBy',p.UserId)
 for _,part in ipairs(m:GetDescendants()) do if part:IsA('BasePart') then
  part.Anchored=true;part.Massless=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
 end end
 local offset=(m:GetAttribute('CrownWearOffset')or CROWN_OFFSET)*(m:GetAttribute('ModelPivotOffset')or CFrame.identity)
 m:SetAttribute('ItemWearOwner',p.UserId);m:SetAttribute('ItemWearRole','Crown');m:SetAttribute('ItemWearOffset',offset)
 m:SetAttribute('ItemWearStart',now);m:SetAttribute('ItemWearEnd',nil);m:SetAttribute('CrownCalling',nil)
 wear[m]={owner=p,character=c};m:PivotTo(head.CFrame*offset);lease(p,'CrownedUntil',now)
 local s=items[m];if s then s.bareSince=nil;s.lifted=true end
 Audio.Play('StingChoir',m)
 Feedback.React(p,'CrownOn','grin',3)
end
local function crownTick(m,s,clock)
 if not s.lifted or wear[m] or not m.PrimaryPart then return end
 local quiet=m:GetAttribute('Selling') or m:GetAttribute('HeldBy') or nearVan(m.PrimaryPart.Position)
 if quiet then s.bareSince=clock;if m:GetAttribute('CrownCalling') then m:SetAttribute('CrownCalling',nil) end;return end
 s.bareSince=s.bareSince or clock
 if clock-s.bareSince>=CROWN_BARE_GRACE and clock>=(s.nextChime or 0) then
  s.nextChime=clock+CROWN_CHIME_EVERY;m:SetAttribute('CrownCalling',true)
  Audio.Play('KeyJingle',m);evidence(m.PrimaryPart.Position,CROWN_CHIME_LOUDNESS,'CrownChime')
 end
end

-- Shared lifecycle -----------------------------------------------------------------------------------------------
local function track(m,id)
 local s=items[m];if s then return s end
 s={id=id,connections={}};items[m]=s
 table.insert(s.connections,m.Destroying:Connect(function()
  for _,connection in ipairs(s.connections) do connection:Disconnect() end
  -- A sold (or otherwise removed) idol gives the house its lights back.
  if s.id=='GildedIdol' and s.lifted then
   local sold=m:GetAttribute('Selling')==true or m:GetAttribute('Sold')==true
   restoreLights()
   local map=mansion();local camp=workspace:FindFirstChild('RecoveryCamp')
   if sold and camp then Audio.Play('StingChoir',camp:FindFirstChild('AnomalyRecoveryVan')) end
   if map then map:SetAttribute('IdolLightsBackAt',workspace:GetServerTimeNow()) end
  end
  items[m]=nil;wear[m]=nil
 end))
 return s
end
function M.Configure(drop,clear,parts)
 detach=drop;clearHold=clear;setParts=parts
end
function M.IsWorn(m)return wear[m]~=nil end
function M.ReleaseHold(p,m)
 local s=wear[m];if not s or s.owner~=p then return false end
 -- The outer detach already removes this item from inventory. Clear its hold
 -- before releaseWear so it cannot recurse into registry detach a second time.
 if clearHold then clearHold(m) end
 return releaseWear(m)
end
function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId');if not ITEM_IDS[id] then return end
 local c=living(p);if not c or not m.PrimaryPart then return end
 local s=track(m,id);local clock=os.clock();local now=workspace:GetServerTimeNow()
 if id=='GildedIdol' then
  if not s.lifted then Feedback.React(p,'IdolLift','grin',2.5) end
  liftIdol(m,s,clock)
 elseif id=='MansionCrown' and not wear[m] then crownOn(p,m,c,now)
 end
end
function M.ClearPlayer(p)
 clearLeases(p);p:SetAttribute('CrownedUntil',nil)
 for m,s in pairs(wear) do if s.owner==p then releaseWear(m) end end
end
function M.ClearLevel()
 for _,p in ipairs(Players:GetPlayers()) do M.ClearPlayer(p) end
 restoreLights()
 for _,s in pairs(items) do
  for _,connection in ipairs(s.connections) do connection:Disconnect() end
 end
 table.clear(items);table.clear(wear);table.clear(leases);fixtures=nil;table.clear(roomCache)
end
local function lobbyOnly()
 local state=RS:FindFirstChild('LobbyState')
 if not state or state:GetAttribute('Mode')~='Menu' then return false end
 for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('MissionActive')==true then return false end end
 return true
end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 if lobbyOnly()then return end
 for m,s in pairs(wear) do
  local c=living(s.owner)
  if not m.Parent or c~=s.character or m:GetAttribute('HeldBy')~=s.owner.UserId then releaseWear(m)
  else
   local head=c:FindFirstChild('Head');local offset=m:GetAttribute('ItemWearOffset')
   if not head or typeof(offset)~='CFrame' then releaseWear(m) else m:PivotTo(head.CFrame*offset) end
  end
 end
 elapsed+=dt;if elapsed<TICK then return end
elapsed=0
 local clock=os.clock();local now=workspace:GetServerTimeNow()
 for m,s in pairs(items) do if m.Parent then
  if s.id=='GildedIdol' then idolTick(m,s,clock)
  elseif s.id=='MansionCrown' then
   local w=wear[m];if w then lease(w.owner,'CrownedUntil',now);Feedback.Hold(w.owner,'grin') end
   crownTick(m,s,clock)
  end
 end end
end)
Players.PlayerRemoving:Connect(M.ClearPlayer)
return M
