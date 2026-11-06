-- HideyBox (CursedA 2026-10-27, stealth draft 2026-10-26): grab = the cardboard box drops over you. Stand still 1 s and
-- monsters ignore you (DisguiseUntil lease: the Mask's perception + catch contract in CreatureRoamServer) while the
-- box's 25 s hide budget lasts. Moving shuffles it (monster noise), a running teammate kicks it off you.
-- Driven by ItemBatch6 (Configure / IsWorn / ReleaseHold / Pickup / ClearPlayer / ClearLevel).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Feedback=require(script.Parent:WaitForChild('Feedback'))
local M={}
M.KEYS={}
local TICK,LEASE=.25,.5
local WORN_SCALE=3
local SETTLE,STILL_SPEED=1,1.2
local BUDGET=25
local WATCHED_RADIUS=12
local NERVOUS_RADIUS=10
local SHUFFLE_EVERY,SHUFFLE_LOUDNESS,SCRAPE_EVERY=.65,18,2.4
local KICK_RANGE,KICK_SPEED,KICK_LOUDNESS,KICK_FLING=3.6,10,40,24
local REWEAR_DELAY=1.5
local worn={} -- m -> {owner,character,stillSince,hidden,nextShuffle,nextScrape}
local boxes=setmetatable({},{__mode='k'}) -- m -> {budget,kickedAt}
local stamps={} -- p -> the DisguiseUntil value this module wrote
local detach,clearHold,setParts
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
-- DisguiseUntil is os.clock based (CreatureRoamServer perceive + catch, SkitterController, the Mask).
local function hide(p,clock)
 local stamp=math.max(p:GetAttribute('DisguiseUntil')or 0,clock+LEASE)
 p:SetAttribute('DisguiseUntil',stamp);stamps[p]=stamp
end
local function unhide(p)
 if stamps[p]and p:GetAttribute('DisguiseUntil')==stamps[p]then p:SetAttribute('DisguiseUntil',nil)end
 stamps[p]=nil
end
local function wornPose(c,m)
 local root=c:FindFirstChild('HumanoidRootPart');local h=c:FindFirstChildOfClass('Humanoid')
 if not root or not h then return nil end
 local floor=root.Position.Y-root.Size.Y/2-h.HipHeight
 local half=(m:GetAttribute('HideyHalfHeight')or .9)*WORN_SCALE
 return CFrame.new(root.Position.X,floor+half,root.Position.Z)*root.CFrame.Rotation*(m:GetAttribute('ModelPivotOffset')or CFrame.identity)
end
local function kickerNear(owner,pos)
 for _,q in ipairs(Players:GetPlayers())do if q~=owner then
  local c=living(q);local r=c and c:FindFirstChild('HumanoidRootPart')
  if r and not q:GetAttribute('Hiding')and not q:GetAttribute('ClosetState')then
   local v=r.AssemblyLinearVelocity
   if Vector3.new(r.Position.X-pos.X,0,r.Position.Z-pos.Z).Magnitude<KICK_RANGE and math.abs(r.Position.Y-pos.Y)<4
    and Vector3.new(v.X,0,v.Z).Magnitude>KICK_SPEED then return q,r end
  end
 end end
 return nil,nil
end
local function releaseWear(m,fling)
 local s=worn[m];if not s then return false end
 worn[m]=nil;unhide(s.owner)
 if not m.Parent then return true end
 m:SetAttribute('HideyWornBy',nil);m:SetAttribute('HideyHidden',nil)
 m:ScaleTo(1)
 if m:GetAttribute('HeldBy')==s.owner.UserId and detach then
  detach(s.owner,m,false,true) -- registry/inventory bookkeeping stays with CursedItemsServer
 else
  if clearHold then clearHold(m)end
  if setParts then setParts(m,false,true)end
 end
 local root=s.owner.Character and s.owner.Character:FindFirstChild('HumanoidRootPart')
 if root and m.PrimaryPart then
  m:PivotTo(root.CFrame*CFrame.new(0,0,-3))
  m.PrimaryPart.AssemblyLinearVelocity=fling or Vector3.new(0,-1,0)
 end
 return true
end
function M.Configure(drop,clear,parts)
 detach=drop;clearHold=clear;setParts=parts
end
function M.IsWorn(m)return worn[m]~=nil end
function M.WornBy(p)
 for m,s in pairs(worn)do if s.owner==p then return m end end
 return nil
end
function M.ReleaseHold(p,m)
 local s=worn[m];if not s or s.owner~=p then return false end
 if clearHold then clearHold(m)end
 return releaseWear(m)
end
function M.Pickup(p,m)
 if m:GetAttribute('ItemId')~='HideyBox'or worn[m]then return end
 local c=living(p);if not c or not m.PrimaryPart or not clearHold or not setParts or not detach then return end
 local box=boxes[m];if not box then box={budget=BUDGET,kickedAt=-math.huge};boxes[m]=box end
 if box.budget<=0 then notice(p,'The box is too squashed to hide in. It still sells.');Feedback.React(p,'BoxSquashed','frown',1.2);return end
 if os.clock()-box.kickedAt<REWEAR_DELAY then return end
 clearHold(m);m:SetAttribute('HeldBy',p.UserId)
 for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')then
  part.Anchored=true;part.Massless=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
 end end
 m:ScaleTo(WORN_SCALE)
 m:SetAttribute('HideyWornBy',p.UserId);m:SetAttribute('HideyHidden',false);m:SetAttribute('HideyBudget',box.budget)
 worn[m]={owner=p,character=c,stillSince=os.clock(),hidden=false,nextShuffle=0,nextScrape=0}
 local pose=wornPose(c,m);if pose then m:PivotTo(pose)end
 Audio.Play('ClothHandle',m)
 Feedback.React(p,'BoxIn','grin',1.5)
end
function M.ClearPlayer(p)
 for m,s in pairs(worn)do if s.owner==p then releaseWear(m)end end
 unhide(p)
end
function M.ClearLevel()
 for m in pairs(worn)do releaseWear(m)end
 table.clear(worn);table.clear(stamps)
 for m in pairs(boxes)do boxes[m]=nil end
end
Run.Heartbeat:Connect(function(dt)
 if not next(worn)then elapsed=0;return end
 for m,s in pairs(worn)do
  local c=living(s.owner)
  if not m.Parent or c~=s.character or m:GetAttribute('HeldBy')~=s.owner.UserId then releaseWear(m)
  else local pose=wornPose(c,m);if pose then m:PivotTo(pose)else releaseWear(m)end end
 end
 elapsed+=dt;if elapsed<TICK then return end
 local step=elapsed;elapsed=0
 local clock=os.clock()
 for m,s in pairs(worn)do
  local box=boxes[m];local root=s.character:FindFirstChild('HumanoidRootPart')
  if not box or not root then releaseWear(m);continue end
  local pos=root.Position
  local kicker,kickRoot=kickerNear(s.owner,pos)
  if kicker and kickRoot then
   box.kickedAt=clock
   local away=Vector3.new(pos.X-kickRoot.Position.X,0,pos.Z-kickRoot.Position.Z)
   away=if away.Magnitude>.1 then away.Unit else root.CFrame.LookVector
   Audio.Play('ItemImpact',m);evidence(pos,KICK_LOUDNESS,'box kicked',kicker)
   notice(s.owner,kicker.DisplayName..' kicked your box off!');notice(kicker,'You kicked a box. Someone was in it.')
   Feedback.React(s.owner,'BoxKicked','gasp',1.5);Feedback.React(kicker,'BoxKick','grin',1.5)
   m:SetAttribute('HideyKicks',(m:GetAttribute('HideyKicks')or 0)+1)
   releaseWear(m,away*KICK_FLING+Vector3.new(0,16,0))
   continue
  end
  local v=root.AssemblyLinearVelocity;local speed=Vector3.new(v.X,0,v.Z).Magnitude
  local nearest=nearestMonster(pos)
  if speed>STILL_SPEED then
   s.stillSince=clock
   if s.hidden then s.hidden=false;m:SetAttribute('HideyHidden',false);unhide(s.owner)end
   if clock>=s.nextShuffle then s.nextShuffle=clock+SHUFFLE_EVERY;evidence(pos,SHUFFLE_LOUDNESS,'box shuffle',s.owner)end
   if clock>=s.nextScrape then s.nextScrape=clock+SCRAPE_EVERY;Audio.Play('SandSlide',m)end
  elseif not s.hidden then
   if nearest<WATCHED_RADIUS then s.stillSince=clock
   elseif clock-s.stillSince>=SETTLE then s.hidden=true;m:SetAttribute('HideyHidden',true);Audio.ToPlayer(s.owner,'ClothHandle');Feedback.React(s.owner,'BoxHidden','grin',1.5)end
  end
  if s.hidden then
   box.budget=math.max(0,box.budget-step*(nearest<NERVOUS_RADIUS and 2 or 1))
   m:SetAttribute('HideyBudget',box.budget)
   if box.budget<=0 then
    m:SetAttribute('HideySquashed',true);m:SetAttribute('DisplayName','Squashed box')
    Audio.Play('ItemImpact',m);evidence(pos,KICK_LOUDNESS,'box collapsed',s.owner)
    notice(s.owner,'The box gave out. RUN!')
    Feedback.React(s.owner,'BoxCollapse','gasp',2)
    releaseWear(m)
   else hide(s.owner,clock)end
  end
 end
end)
return M
