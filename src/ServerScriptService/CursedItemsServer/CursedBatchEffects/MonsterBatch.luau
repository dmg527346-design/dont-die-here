-- Monster items (Monsters build 2026-10-27, drafts ItemDrafts_20261026\Monsters): required exactly once by the running
-- CursedBatchEffects owner. Own 4 Hz Heartbeat; no per-player leases (only short reaction faces that expire on their own).
--   Watch Gnome: resting (not held), it stares any Collar Crawler in line of sight frozen (CreatureRoamServer reads the
--     GnomeWatchedUntil os.clock lease in its weeping-angel check). 25 s of freezing per gnome, then it falls asleep.
--   Tip Bell (dropped by the Bellhop after a carry, MonsterAbilities.carrierGrab): rings whenever it moves faster than a
--     walk, in hands (holder walk speed + 2) or in the cart (14 studs/s): MonsterEvidence loudness 55 naming the holder.
--   Cuckoo Clock (omen THE CUCKOO, placed by CursedItemsServer omenProp): every 60 s it calls every monster in earshot to
--     itself (MonsterEvidence loudness 90; a held clock names its carrier). Grabbing it winds it back to a full minute.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService.GameplayAudioServer)
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local M={}
local TICK=.25
local ITEM_IDS={WatchGnome=true,TipBell=true,CuckooClock=true}
local GNOME={Range=36,Stamina=25,EyeHeight=.6,ChestHeight=2.5,Hold=.5,WarnRange=60,CheerRange=45}
local BELL={Ring=.5,Loudness=55,Margin=2.5,CartSpeed=14,BaseWalk=12}
local CUCKOO={First=75,Every=60,Loudness=90,TickFrom=5,StartleRange=40}
local CUCKOO_CUE=(Sounds::any).CuckooCall and 'CuckooCall' or 'PartyHorn' -- a real cuckoo once the owner picks one (SOUNDS.md)
local LIVE_PHASES={Searching=true,Selling=true,Returning=true}
local SLEEPY_EYES=Color3.fromRGB(95,100,110)
local wallParams=RaycastParams.new();wallParams.FilterType=Enum.RaycastFilterType.Include
local bells=setmetatable({},{__mode='k'}) -- [model]={last=Vector3,at=number,next=number}

local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function interactive()
 local mansion=workspace:FindFirstChild('Mansion');return mansion and mansion:FindFirstChild('Interactive')
end
-- Reaction face + pop word (Monsters build): a short React* face on the selected-face channel, only when no held item
-- owns it, and a pop word on that player's screen (CurseEffectsClient). shake 0..1 = a small camera jolt.
local function react(p,face,secs,text,shake)
 local now=workspace:GetServerTimeNow();local cur=p:GetAttribute('DraftSelectedItem')
 local mine=type(cur)=='string'and cur:sub(1,5)=='React'
 if face and(mine or now>=(p:GetAttribute('DraftSelectedUntil')or 0))then
  if not(cur==face and now<(p:GetAttribute('DraftSelectedUntil')or 0))then p:SetAttribute('DraftSelectedItem',face);p:SetAttribute('DraftSelectedStart',now)end
  p:SetAttribute('DraftSelectedUntil',now+(secs or 1.5))
 end
 if text then p:SetAttribute('ReactPop',text);p:SetAttribute('ReactPopShake',shake or 0);p:SetAttribute('ReactPopAt',now)end
end
local function nearPlayers(pos,range)
 local list={}
 for _,q in Players:GetPlayers()do
  local c=living(q);local r=c and c:FindFirstChild('HumanoidRootPart')
  if r and(r.Position-pos).Magnitude<range then table.insert(list,q)end
 end
 return list
end

-- ===== Watch Gnome =====
local function crawlers()
 local list={};local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,enemy in ipairs(folder:GetChildren())do
  if enemy:IsA('Model')and enemy:GetAttribute('CreatureKind')=='Crawler'and enemy.PrimaryPart then table.insert(list,enemy)end
 end end
 return list
end
local function eyes(m)
 local e=m:FindFirstChild('WatchGnome_neon',true);if e and e:IsA('BasePart')then return e end
 for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')and part.Material==Enum.Material.Neon then return part end end
 return nil
end
local function setStaring(m,on)
 if(m:GetAttribute('GnomeStaring')==true)~=on then
  m:SetAttribute('GnomeStaring',on or nil)
  if on and m.PrimaryPart then -- the gnome locks on: a zap, and everyone nearby cheers it on
   Audio.Play('HypnoHit',m)
   for _,q in nearPlayers(m.PrimaryPart.Position,GNOME.CheerRange)do react(q,'ReactGrin',1.8,'GET HIM, GNOME!')end
  end
 end
end
local function sleep(m)
 m:SetAttribute('StareLeft',0);m:SetAttribute('GnomeAsleep',true);setStaring(m,false)
 local e=eyes(m);if e then e.Material=Enum.Material.SmoothPlastic;e.Color=SLEEPY_EYES end
 Audio.Play('HeliumHiss',m) -- a long sleepy sigh
 if m.PrimaryPart then for _,q in nearPlayers(m.PrimaryPart.Position,GNOME.CheerRange)do react(q,'ReactSob',1.6,'The gnome fell asleep...')end end
end
local function gnomeTick(m,list,clock,step)
 if m:GetAttribute('GnomeAsleep')then return end
 local root=m.PrimaryPart
 -- Only a gnome that sits still stares: held, carried off by a monster or mid-sale does nothing.
 if not root or m:GetAttribute('HeldBy')or m:GetAttribute('MonsterCarried')or m:GetAttribute('Selling')then setStaring(m,false);return end
 local left=m:GetAttribute('StareLeft');if type(left)~='number'then left=GNOME.Stamina end
 local mansion=workspace:FindFirstChild('Mansion');local walls=mansion and mansion:FindFirstChild('Collision')
 if walls then wallParams.FilterDescendantsInstances={walls}end
 local eye=root.Position+Vector3.new(0,GNOME.EyeHeight,0)
 local froze=false
 for _,enemy in ipairs(list)do
  local to=enemy.PrimaryPart.Position+Vector3.new(0,GNOME.ChestHeight,0)-eye
  if to.Magnitude<GNOME.Range and(not walls or not workspace:Raycast(eye,to,wallParams))then
   enemy:SetAttribute('GnomeWatchedUntil',math.max(enemy:GetAttribute('GnomeWatchedUntil')or 0,clock+GNOME.Hold));froze=true
  end
 end
 if froze then left=math.max(0,left-step);m:SetAttribute('StareLeft',left)end
 if left<=0 then sleep(m)else setStaring(m,froze)end
end

-- ===== Tip Bell =====
local function bellTick(m,clock)
 local root=m.PrimaryPart;if not root then return end
 local s=bells[m];if not s then s={};bells[m]=s end
 local pos=root.Position;local last,lastAt=s.last,s.at;s.last=pos;s.at=clock
 if not last or not lastAt or clock-lastAt<=0 or m:GetAttribute('Selling')then return end
 local speed=Vector3.new(pos.X-last.X,0,pos.Z-last.Z).Magnitude/(clock-lastAt)
 local holder=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 if holder and living(holder)then
  -- the holder's own speed (a fast mouse-wheel move of the held bell must not ring it)
  local r=holder.Character:FindFirstChild('HumanoidRootPart')
  if r then local v=r.AssemblyLinearVelocity;speed=Vector3.new(v.X,0,v.Z).Magnitude end
  local walk=(holder:GetAttribute('UpgradeWalkSpeed')or BELL.BaseWalk)*(tonumber(holder:GetAttribute('CursedSpeedMultiplier'))or 1)
  if speed<=walk+BELL.Margin then return end
 elseif m:GetAttribute('CargoStored')then
  holder=nil;if speed<=BELL.CartSpeed then return end
 else return end
 if clock<(s.next or 0)then return end
 s.next=clock+BELL.Ring
 Audio.Play('BellhopBell',m);m:SetAttribute('BellRangAt',workspace:GetServerTimeNow())
 if holder then react(holder,'ReactWince',.7,nil)end -- every ring: the runner winces
 local bus=SS:FindFirstChild('MonsterEvidence')
 if bus then bus:Fire(pos,BELL.Loudness,'tip bell',holder)end
end

-- ===== Cuckoo Clock =====
local function cuckooTick(m,now)
 local root=m.PrimaryPart;if not root or m:GetAttribute('Selling')then return end
 local at=m:GetAttribute('CuckooAt')
 if type(at)~='number'then at=now+CUCKOO.First;m:SetAttribute('CuckooAt',at)end
 local left=at-now
 if left>0 then
  local whole=math.ceil(left) -- tick-tock: one tick per whole second in the last five
  if whole<=CUCKOO.TickFrom and m:GetAttribute('CuckooTick')~=whole then m:SetAttribute('CuckooTick',whole);Audio.Play('ClockTick',m)end
  return
 end
 m:SetAttribute('CuckooAt',now+CUCKOO.Every);m:SetAttribute('CuckooTick',nil);m:SetAttribute('CuckooCalls',(m:GetAttribute('CuckooCalls')or 0)+1);m:SetAttribute('CuckooCalledAt',now)
 Audio.Play(CUCKOO_CUE,m);task.delay(.45,function()if m.Parent then Audio.Play(CUCKOO_CUE,m)end end) -- cuck-OO
 local holder=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 if holder and not living(holder)then holder=nil end
 -- everyone near it jumps out of their skin; the one holding it hardest
 for _,q in nearPlayers(root.Position,CUCKOO.StartleRange)do
  react(q,'ReactStartle',1.6,q==holder and 'CUCKOO!! (they all heard that)' or 'CUCKOO!',q==holder and .9 or .5)
 end
 local bus=SS:FindFirstChild('MonsterEvidence')
 if bus then bus:Fire(root.Position,CUCKOO.Loudness,'cuckoo clock',holder)end
end

function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId');if not ITEM_IDS[id]or not living(p)or not m.PrimaryPart then return end
 if id=='WatchGnome'then
  setStaring(m,false)
  if m:GetAttribute('GnomeAsleep')then react(p,'ReactSob',1.2,'Zzz... (it is asleep)');return end
  -- On grab: a whistle when a Crawler is within 60 studs (an early warning, no direction).
  for _,enemy in ipairs(crawlers())do
   if(enemy.PrimaryPart.Position-m.PrimaryPart.Position).Magnitude<GNOME.WarnRange then
    Audio.Play('Whistle',m);react(p,'ReactStartle',1.4,'PSST! A CRAWLER IS CLOSE!',.3);return
   end
  end
  react(p,'ReactGrin',1.2,'Set me down near a Crawler!')
 elseif id=='TipBell'then
  Audio.Play('BellhopBell',m) -- on grab: one soft ding so players learn the sound (no monster noise)
  local s=bells[m];if s then s.last=nil;s.next=os.clock()+BELL.Ring end
  react(p,'ReactGrin',1.4,"A TIP! Walk, don't run...")
 elseif id=='CuckooClock'then -- on grab: wind it back to a full minute
  m:SetAttribute('CuckooAt',workspace:GetServerTimeNow()+CUCKOO.Every);m:SetAttribute('CuckooTick',nil)
  Audio.Play('ClockTick',m);task.delay(.25,function()if m.Parent then Audio.Play('ClockTick',m)end end)
  react(p,'ReactGrin',1.2,'Wound up! 60 seconds')
 end
end
function M.ClearPlayer(_p)end -- nothing per player (reaction faces expire by themselves)
function M.ClearLevel()
 table.clear(bells)
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,enemy in ipairs(folder:GetChildren())do enemy:SetAttribute('GnomeWatchedUntil',nil)end end
end

local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK then return end
 local step=elapsed;elapsed=0
 local folder=interactive();if not folder then return end
 local clock=os.clock();local now=workspace:GetServerTimeNow()
 local rr=RS:FindFirstChild('RecoveryRound');local live=rr~=nil and LIVE_PHASES[rr:GetAttribute('Phase')or'']==true
 local list
 for _,m in ipairs(folder:GetChildren())do
  if m:IsA('Model')then
   local id=m:GetAttribute('ItemId')
   if id=='WatchGnome'then
    list=list or crawlers()
    if #list>0 or m:GetAttribute('GnomeStaring')then gnomeTick(m,list,clock,step)end
   elseif id=='TipBell'then bellTick(m,clock)
   elseif id=='CuckooClock'and live then cuckooTick(m,now)end
  end
 end
end)
return M
