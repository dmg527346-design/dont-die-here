-- Cart items (CursedA 2026-10-27, draft 2026-10-26 "ItemBatchCart"): items whose curse acts while they sit IN the
-- recovery cart. HungryLunchbox: every 15 s it eats the cheapest item beside it and grows by 1.5x what it ate.
-- RecoveryRoundServer owns storing (CargoStored / CargoCart) and the cart value (sum of LootValue, every .1 s); this
-- module only rewrites the lunchbox's own Value/LootValue and destroys what it eats (updateCargo / the 4 Hz item tick
-- drop the eaten item's state by themselves). Driven by ItemBatch6.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local Feedback=require(script.Parent:WaitForChild('Feedback'))
local M={}
M.KEYS={}
local TICK=.25
local LUNCHBOX='HungryLunchbox'
local FIRST_BITE=8
local BITE_EVERY=15
local GROWTH=1.5
local VALUE_CAP=240
local STARVE_AFTER=20
local RATTLE_EVERY=5
local CHOMP_NOISE,RATTLE_NOISE,GRAB_NOISE=30,18,12
local WATCH_RADIUS=24 -- players this close to a chomp make a face at it
local items={}

local function chompCue()return Sounds.LunchboxChomp and 'LunchboxChomp' or 'NeonChatter' end
local function worth(m)return m:GetAttribute('LootValue')or m:GetAttribute('Value')or 0 end
local function evidence(pos,loud,label,source)
 local bus=SS:FindFirstChild('MonsterEvidence');if bus then bus:Fire(pos,loud,label,source)end
end
local function levelLive()
 local state=RS:FindFirstChild('RecoveryRound');local phase=state and state:GetAttribute('Phase')
 return phase=='Searching'or phase=='Returning'
end
local function stored(m)
 return m.Parent~=nil and m.PrimaryPart~=nil and m:GetAttribute('CargoStored')==true and not m:GetAttribute('Selling')
  and not m:GetAttribute('MonsterCarried')and not m:GetAttribute('HeldBy')
end
local function track(m)
 local s=items[m];if s then return s end
 s={chomps=m:GetAttribute('Chomps')or 0};items[m]=s
 m.Destroying:Connect(function()items[m]=nil end)
 return s
end
local function pickFood(m)
 local own=worth(m);local cartName=m:GetAttribute('CargoCart');local best,bestWorth,bestDist=nil,math.huge,math.huge
 for _,x in ipairs(m.Parent:GetChildren())do
  if x~=m and x:IsA('Model')and x.PrimaryPart and x:GetAttribute('ItemId')and x:GetAttribute('CargoStored')==true
   and x:GetAttribute('CargoCart')==cartName and not x:GetAttribute('Selling')and not x:GetAttribute('Gear')
   and not x:GetAttribute('HeldBy')and not x:GetAttribute('MonsterCarried')and not x:GetAttribute('ItemWearOwner')
   and not x:GetAttribute('Treasure')then
   local w=worth(x)
   if w>0 and w<=own then
    local d=(x.PrimaryPart.Position-m.PrimaryPart.Position).Magnitude
    if w<bestWorth or(w==bestWorth and d<bestDist)then best,bestWorth,bestDist=x,w,d end
   end
  end
 end
 return best
end
local function chomp(m,s,food)
 local eaten=worth(food);local gain=math.floor(eaten*GROWTH+.5)
 local before=worth(m);local after=math.min(VALUE_CAP,before+gain)
 local name=food:GetAttribute('DisplayName')or food.Name
 food:Destroy()
 m:SetAttribute('Value',after);m:SetAttribute('LootValue',after)
 s.chomps+=1;m:SetAttribute('Chomps',s.chomps)
 m:SetAttribute('DisplayName',('Hungry lunchbox (ate %d)'):format(s.chomps))
 m:SetAttribute('LunchboxAteName',name);m:SetAttribute('LunchboxNet',(after-before)-eaten)
 m:SetAttribute('LunchboxAteAt',workspace:GetServerTimeNow())
 Audio.Play(chompCue(),m.PrimaryPart)
 evidence(m.PrimaryPart.Position,CHOMP_NOISE,'lunchbox chomp',m)
 for _,q in ipairs(Players:GetPlayers())do
  local c=q.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
  if r and q:GetAttribute('MissionActive')==true and(r.Position-m.PrimaryPart.Position).Magnitude<WATCH_RADIUS then Feedback.React(q,'LunchChomp','gasp',1.4)end
 end
end
local function step(m,s,now)
 if not stored(m)or not levelLive()then s.storedAt=nil;s.hungrySince=nil;return end
 if not s.storedAt then s.storedAt=now;s.nextBite=now+FIRST_BITE;s.hungrySince=nil end
 if worth(m)>=VALUE_CAP then s.hungrySince=nil;m:SetAttribute('LunchboxFull',true);return end
 if now<s.nextBite then return end
 local food=pickFood(m)
 if food then chomp(m,s,food);s.nextBite=now+BITE_EVERY;s.hungrySince=nil;return end
 s.hungrySince=s.hungrySince or now
 if now-s.hungrySince>=STARVE_AFTER and now>=(s.nextRattle or 0)then
  s.nextRattle=now+RATTLE_EVERY
  Audio.Play('ItemRattle',m.PrimaryPart)
  evidence(m.PrimaryPart.Position,RATTLE_NOISE,'starving lunchbox',m)
  m:SetAttribute('LunchboxStarvingAt',workspace:GetServerTimeNow())
 end
end
function M.Pickup(p,m)
 if m:GetAttribute('ItemId')~=LUNCHBOX or not m.PrimaryPart then return end
 local s=track(m);s.storedAt=nil;s.hungrySince=nil
 -- On grab it snaps its lid at you: one chomp clack, a little noise, a startled face.
 Audio.Play(chompCue(),m.PrimaryPart)
 evidence(m.PrimaryPart.Position,GRAB_NOISE,'lunchbox snap',p)
 Feedback.React(p,'LunchSnap','gasp',1.3)
end
function M.ClearPlayer(_p)end
function M.ClearLevel()table.clear(items)end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK then return end;elapsed=0
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if not interactive then return end
 for _,m in ipairs(interactive:GetChildren())do if m:IsA('Model')and m:GetAttribute('ItemId')==LUNCHBOX then track(m)end end
 if not next(items)then return end
 local now=os.clock()
 for m,s in pairs(items)do if m.Parent==interactive then step(m,s,now)end end
end)
return M
