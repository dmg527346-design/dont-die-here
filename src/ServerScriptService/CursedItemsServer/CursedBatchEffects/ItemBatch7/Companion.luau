-- Companions (CursedA 2026-10-27, draft 2026-10-26): found critters (PeekabooSock, DustBunnyBot) adopt the player who
-- grabs them for the rest of the level. CursedItemsServer's use() chain spends the grabbed item (the Cake pattern) when
-- CursedBatchEffects.AdoptCompanion returns true; the player then carries attribute Companion=<id> and
-- CurseEffectsClient.ItemBatch7Client draws the follower on every client (templates ReplicatedStorage.CompanionKit).
-- Shared owner for companions: a future companion (e.g. GlowMoth) joins KINDS here, never a second manager.
-- The sock is pure client presentation (it reads replicated monster positions). The server only owns Dusty's belly:
-- one dropped item welded to the owner (AttachedTo, so nobody can grab it and the cart cannot store it), spat into the
-- cart basket when the owner gets near it, or spat out on the floor when a monster comes close.
-- Driven by CursedBatchEffects.ItemBatch7 (Configure / Adopt / ClearPlayer / ClearLevel).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game:GetService('ServerScriptService'):WaitForChild('GameplayAudioServer'))
local C=require(RS:WaitForChild('CursedCatalog'))
local Feedback=require(script.Parent.Parent:WaitForChild('ItemBatch6'):WaitForChild('Feedback'))
local M={}
local KINDS={PeekabooSock=true,DustBunnyBot=true}
local TICK=.25
local EAT_RADIUS=9          -- an item the owner let go of (a release tosses it ~7 studs), resting this close to the owner's root
local EAT_DELAY,EAT_WINDOW=.6,3 -- seconds after the drop: the cart's own drop catch (1.5 s window) gets first go
local EAT_COOLDOWN=2        -- after a spit or a deposit
local CART_SKIP=12          -- owner this close to the cart basket: Dusty never eats (you are loading the cart yourself)
local DEPOSIT_RADIUS=9      -- owner this close to the cart basket: Dusty spits the item into it
local PANIC_RADIUS=12       -- a monster this close to the owner: Dusty panics and spits the item out
local WHIRR_EVERY,WHIRR_LOUDNESS=2,14 -- carrying hums: monster noise 14 (walking is 12, running 30)
local SPIT_LOUDNESS=30
local BELLY_OFFSET=CFrame.new(0,-1.6,2.4) -- behind and under the root; every client hides the real item and draws a mini copy on Dusty
local bonds={} -- p -> {kind=id, belly=Model?, weld=WeldConstraint?, eatReadyAt=clock, nextWhirr=clock}
local lastHeld=setmetatable({},{__mode='k'}) -- item Model -> {owner=p, at=os.clock()} the last tick a Dusty owner held it
local setParts -- CursedItemsServer.parts(m,anchored,collide), handed over by Configure
local elapsed=0

local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function notice(p,text)
 local event=RS:FindFirstChild('CursedEvent');if event and p.Parent then event:FireClient(p,'notice',text)end
end
local function evidence(pos,loudness,label,actor)
 local bus=SS:FindFirstChild('MonsterEvidence');if bus then bus:Fire(pos,loudness,label,actor)end
end
local function nearestMonster(pos)
 local best=math.huge;local creatures=workspace:FindFirstChild('RoamingCreatures')
 if creatures then for _,enemy in ipairs(creatures:GetChildren())do
  local primary=enemy:IsA('Model')and enemy.PrimaryPart
  if primary then best=math.min(best,(primary.Position-pos).Magnitude)end
 end end
 return best
end
local function interactive()
 local map=workspace:FindFirstChild('Mansion');return map and map:FindFirstChild('Interactive')
end
-- The cart basket in world space, exactly like RecoveryRoundServer.basketFrame (attributes are authored unscaled).
local function basket()
 local folder=interactive();local cart=folder and folder:FindFirstChild('RecoveryCart')
 local offset=cart and cart:GetAttribute('BasketOffset');local size=cart and cart:GetAttribute('BasketSize')
 if not cart or not cart.PrimaryPart or typeof(offset)~='Vector3'or typeof(size)~='Vector3'then return nil end
 local s=cart:GetScale()
 return cart.PrimaryPart.CFrame*CFrame.new(offset*s),size*s
end
local function itemName(m)
 local entry=C.Items[m:GetAttribute('ItemId')or''];return m:GetAttribute('DisplayName')or(entry and entry.name)or 'item'
end
-- Loose, sellable floor loot only: never gear, worn, stuck-on, monster-carried, selling or cart cargo.
local function edible(m)
 return m:IsA('Model')and m.PrimaryPart~=nil and m:GetAttribute('ItemId')~=nil and not KINDS[m:GetAttribute('ItemId')]
  and not m:GetAttribute('HeldBy')and not m:GetAttribute('CargoStored')and not m:GetAttribute('AttachedTo')
  and not m:GetAttribute('ItemWearOwner')and not m:GetAttribute('FaceOwner')and not m:GetAttribute('MonsterCarried')
  and not m:GetAttribute('Selling')and not m:GetAttribute('Gear')and not m:GetAttribute('Spent')and not m:GetAttribute('LobbyToy')
  and(m:GetAttribute('Value')or 0)>0
end
local function unweld(s)
 local m=s.belly;s.belly=nil
 if s.weld then s.weld:Destroy();s.weld=nil end
 if not m or not m.Parent then return nil end
 m:SetAttribute('AttachedTo',nil);m:SetAttribute('DustyCarriedBy',nil)
 if setParts then setParts(m,false,true)end -- ordinary loose loot again (server-owned, ground collider on)
 return m
end
local function swallow(p,s,m,root)
 if not setParts then return end
 lastHeld[m]=nil
 -- Owner bug 2026-10-27 (stuck in Freefall after Dusty ate a dropped cat gift): the belly item used to be WELDED to the
 -- owner's root, which put it (its ground collider, its client-driven Motor6Ds) inside the player's physics assembly.
 -- Now it is anchored, non-colliding and simply parked behind the owner every tick: same look (clients hide it and
 -- draw a mini copy on Dusty), no physics link to the character at all.
 setParts(m,true,false)
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')then x.CanCollide=false;x.CanQuery=false;x.CanTouch=false end end
 m:PivotTo(root.CFrame*BELLY_OFFSET)
 s.belly=m;s.weld=nil;s.root=root;s.nextWhirr=os.clock()+WHIRR_EVERY
 m:SetAttribute('AttachedTo',p.UserId);m:SetAttribute('DustyCarriedBy',p.UserId)
 Audio.Play('VacuumMotor',root)
 Feedback.React(p,'DustyGulp','grin',1.2)
 notice(p,'Dusty swallowed the '..itemName(m)..'. Walk to the cart and it spits it in.')
end
local function spit(p,s,reason)
 local m=unweld(s);if not m then return end
 s.eatReadyAt=os.clock()+EAT_COOLDOWN
 local c=p.Character;local root=c and c:FindFirstChild('HumanoidRootPart')
 if root and m.PrimaryPart then
  m:PivotTo(root.CFrame*CFrame.new(0,-.5,3))
  m.PrimaryPart.AssemblyLinearVelocity=-root.CFrame.LookVector*10+Vector3.new(0,8,0)
  if reason=='panic'then evidence(root.Position,SPIT_LOUDNESS,'dusty spat',p)end
 end
 Audio.Play('Spit',m)
 if reason=='panic'then Feedback.React(p,'DustyPanic','gasp',1.6);notice(p,'Dusty panicked and spat the '..itemName(m)..' out!')end
end
local function deposit(p,s,cf,size)
 local m=unweld(s);if not m or not m.PrimaryPart then return end
 s.eatReadyAt=os.clock()+EAT_COOLDOWN
 -- Straight into the middle of the basket: RecoveryRoundServer's cargo pass (storeCargo) stores anything resting inside it.
 m:PivotTo(cf*CFrame.new(0,-size.Y*.1,0))
 m.PrimaryPart.AssemblyLinearVelocity=Vector3.new(0,-2,0)
 Audio.Play('Spit',m)
 Feedback.React(p,'DustyDeliver','grin',2)
 m:SetAttribute('DustyDelivered',true)
 notice(p,'Dusty spat the '..itemName(m)..' into the cart!')
end

function M.Configure(_drop,_clear,parts)
 setParts=parts
end
-- Called from CursedItemsServer's grab chain. true = the item is spent (the caller detaches and destroys it).
function M.Adopt(p,m)
 local id=m:GetAttribute('ItemId')
 if not KINDS[id]then return false end
 local c=living(p);if not c then return false end
 if bonds[p]then notice(p,'You already have a companion. This one just wants to be sold.');return false end
 bonds[p]={kind=id,eatReadyAt=0,nextWhirr=0}
 p:SetAttribute('Companion',id)
 local root=c:FindFirstChild('HumanoidRootPart')
 if id=='PeekabooSock'then
  Audio.Play('ClothHandle',root)
  Feedback.React(p,'SockAdopt','grin',2.5)
  notice(p,'The sock ghost climbed onto your shoulder. It whispers when something is behind you.')
 else
  Audio.Play('VacuumMotor',root)
  Feedback.React(p,'DustyAdopt','grin',2.5)
  notice(p,'Dusty adopted you! Drop an item by your feet and Dusty carries it to the cart.')
 end
 return true
end
-- Death / character reset: Dusty spits out what it carries; the bond itself lasts the whole level.
function M.ClearPlayer(p)
 local s=bonds[p];if s and s.belly then spit(p,s,'dropped')end
end
function M.ClearLevel()
 for p,s in pairs(bonds)do
  if s.belly then spit(p,s,'dropped')end
  if p.Parent then p:SetAttribute('Companion',nil)end
 end
 table.clear(bonds);table.clear(lastHeld)
end
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK then return end
 elapsed=0
 if not next(bonds)then return end
 local folder=interactive();if not folder then return end
 local clock=os.clock()
 local owners={}
 for p,s in pairs(bonds)do if s.kind=='DustBunnyBot'then owners[p.UserId]=p end end
 if not next(owners)then return end
 for _,m in ipairs(folder:GetChildren())do
  local holder=owners[m:GetAttribute('HeldBy')or 0]
  if holder then lastHeld[m]={owner=holder,at=clock}end
 end
 local cf,size=basket()
 for p,s in pairs(bonds)do
  if s.kind~='DustBunnyBot'then continue end
  local c=living(p);local root=c and c:FindFirstChild('HumanoidRootPart')
  if not root then continue end
  local pos=root.Position
  local toCart=if cf then (cf.Position-pos).Magnitude else math.huge
  if s.belly then
   if s.belly.Parent and s.root==root then s.belly:PivotTo(root.CFrame*BELLY_OFFSET)end -- the parked (anchored) belly item rides along
   if not s.belly.Parent or s.root~=root then spit(p,s,'lost') -- gone, or the owner respawned
   elseif nearestMonster(pos)<PANIC_RADIUS then spit(p,s,'panic')
   elseif toCart<DEPOSIT_RADIUS then deposit(p,s,cf,size)
   elseif clock>=s.nextWhirr then s.nextWhirr=clock+WHIRR_EVERY;evidence(pos,WHIRR_LOUDNESS,'dusty whirr',p)end
  elseif clock>=s.eatReadyAt and toCart>=CART_SKIP and nearestMonster(pos)>=PANIC_RADIUS then
   for m,seen in pairs(lastHeld)do
    local age=clock-seen.at
    if seen.owner==p and m.Parent==folder and age>=EAT_DELAY and age<=EAT_WINDOW and edible(m)
     and(m.PrimaryPart.Position-pos).Magnitude<EAT_RADIUS then
     swallow(p,s,m,root);break
    end
   end
  end
 end
 for m,seen in pairs(lastHeld)do if clock-seen.at>EAT_WINDOW then lastHeld[m]=nil end end
end)
Players.PlayerRemoving:Connect(function(p)
 M.ClearPlayer(p);bonds[p]=nil
end)
return M
