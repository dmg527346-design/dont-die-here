-- First-find items (CursedA 2026-10-27, draft 2026-10-26): FoamFinger, BobbleBuddy, WobbleJelly.
-- The level 1 start-room bonus item is one of these (CursedItemsServer picks it; catalog firstFind=true keeps them
-- out of the normal loot bag). Driven by ItemBatch6: Pickup(p,m), ClearPlayer(p), ClearLevel().
-- Grab: a held lease the clients draw (CurseEffectsClient jelly wobble, CharacterMotionClient bobble eyes, the
-- ItemBatch6Client glow/crowd/steps) + a face and a screen pop (Feedback). Stored in the cart: one celebration per
-- item (confetti fountain, cues, RecoveryRound.CartCheerAt for the HUD bar flash). No penalties of any kind.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local Feedback=require(script.Parent:WaitForChild('Feedback'))
local M={}
local TICK=.25
local LEASE=.5
local CHEER_SECONDS=1.6
local LEASES={FoamFinger='FoamFingerUntil',BobbleBuddy='BobbleUntil',WobbleJelly='JellyUntil'}
local HOLD_FACE={FoamFinger='grin',BobbleBuddy='grin',WobbleJelly='pucker'}
local GRAB_REACT={FoamFinger={'FoamCheer','grin',2.5},BobbleBuddy={'BobbleBoing','gasp',1.2},WobbleJelly={'JellySplat','gasp',1.2}}
-- First cue that exists in GameplaySoundCatalog wins.
local GRAB_CUES={FoamFinger={'FirstFindCheer','PartyHorn'},BobbleBuddy={'DraftSelected_SpringyWhisk','ClownHonk'},WobbleJelly={'JellyWobble','FrostingSquish'}}
local STORE_CUES={FoamFinger={'FirstFindCheer','PartyHorn'},BobbleBuddy={'DraftSelected_SpringyWhisk','PartyHorn'},WobbleJelly={'JellyWobble','PartyBlower'}}
M.KEYS={'FoamFingerUntil','BobbleUntil','JellyUntil','FirstFindGrabAt','FirstFindGrabItem'}
-- Confetti without red (content rule): blue, green, yellow, purple, orange.
local CONFETTI={Color3.fromRGB(60,170,240),Color3.fromRGB(120,220,90),Color3.fromRGB(250,210,60),Color3.fromRGB(170,110,245),Color3.fromRGB(255,160,40)}
local items={}

local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function lease(p,key,now)
 p:SetAttribute(key,math.max(p:GetAttribute(key)or 0,now+LEASE))
end
local function cue(list)
 for _,key in ipairs(list or {})do if Sounds[key]then return key end end
 return nil
end
local function burst(part,offset,count,rate,seconds)
 local a=Instance.new('Attachment');a.Name='FirstFindConfetti';a.Position=offset or Vector3.zero;a.Parent=part
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds'
 e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,CONFETTI[1]),ColorSequenceKeypoint.new(.25,CONFETTI[2]),ColorSequenceKeypoint.new(.5,CONFETTI[3]),ColorSequenceKeypoint.new(.75,CONFETTI[4]),ColorSequenceKeypoint.new(1,CONFETTI[5])})
 e.Size=NumberSequence.new(.32,.18);e.Lifetime=NumberRange.new(1.1,2);e.Speed=NumberRange.new(12,22);e.SpreadAngle=Vector2.new(35,35)
 e.EmissionDirection=Enum.NormalId.Top;e.Acceleration=Vector3.new(0,-20,0);e.Drag=1.4;e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-300,300)
 e.LightEmission=.4;e.Rate=rate or 0;e.Parent=a
 e:Emit(count or 60)
 if rate and rate>0 then task.delay(seconds or 1,function()if e.Parent then e.Enabled=false end end)end
 Debris:AddItem(a,(seconds or 0)+2.5)
end
local function cartFor(m)
 local name=m:GetAttribute('CargoCart');local parent=m.Parent
 local cart=name and parent and parent:FindFirstChild(name)
 return cart and cart:IsA('Model')and cart.PrimaryPart and cart or nil
end
local function celebrate(m,s)
 s.cheered=true;m:SetAttribute('FirstFindCheered',true)
 local now=workspace:GetServerTimeNow()
 local cart=cartFor(m)
 if cart then
  local offset=cart:GetAttribute('BasketOffset')
  burst(cart.PrimaryPart,typeof(offset)=='Vector3'and offset*cart:GetScale()or Vector3.new(0,2,0),120,45,CHEER_SECONDS)
  Audio.Play('QuotaMet',cart)
 elseif m.PrimaryPart then burst(m.PrimaryPart,nil,120,45,CHEER_SECONDS)end
 local key=cue(STORE_CUES[s.id]);if key then Audio.Play(key,m)end
 -- Everyone near the cart grins at the fountain.
 local pos=(cart and cart.PrimaryPart or m.PrimaryPart).Position
 for _,q in ipairs(Players:GetPlayers())do
  local c=living(q);local r=c and c:FindFirstChild('HumanoidRootPart')
  if r and(r.Position-pos).Magnitude<40 then Feedback.React(q,'CartCheer','grin',2.5)end
 end
 -- HUD owner (RecoveryRoundClient) flashes the quota bars gold when this changes. Only this module writes it.
 local state=RS:FindFirstChild('RecoveryRound')
 if state then state:SetAttribute('CartCheerAt',now);state:SetAttribute('CartCheerItem',s.id)end
end
local function track(m,id)
 local s=items[m];if s then return s end
 s={id=id};items[m]=s
 s.gone=m.Destroying:Connect(function()items[m]=nil end)
 return s
end
function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId');if not LEASES[id]then return end
 local c=living(p);if not c or not m.PrimaryPart then return end
 local s=track(m,id);local now=workspace:GetServerTimeNow()
 lease(p,LEASES[id],now)
 local r=GRAB_REACT[id];Feedback.React(p,r[1],r[2],r[3])
 -- Grab pop (once per item per level, so re-grabs stay quiet): confetti puff, the item's cue, and a stamp the
 -- clients use for the big first wobble / boing.
 if not s.popped then
  s.popped=true
  p:SetAttribute('FirstFindGrabAt',now);p:SetAttribute('FirstFindGrabItem',id)
  burst(m.PrimaryPart,nil,45)
  local key=cue(GRAB_CUES[id]);if key then Audio.Play(key,m)end
 end
end
function M.ClearPlayer(p)
 for _,key in ipairs(M.KEYS)do p:SetAttribute(key,nil)end
end
function M.ClearLevel()
 for _,s in pairs(items)do if s.gone then s.gone:Disconnect()end end
 table.clear(items)
 local state=RS:FindFirstChild('RecoveryRound')
 if state then state:SetAttribute('CartCheerAt',nil);state:SetAttribute('CartCheerItem',nil)end
end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK then return end;elapsed=0
 if not next(items)then return end
 local now=workspace:GetServerTimeNow()
 for m,s in pairs(items)do
  if not m.Parent then items[m]=nil;continue end
  if m:GetAttribute('CargoStored')then
   if not s.cheered then celebrate(m,s)end
  elseif not m:GetAttribute('Selling')then
   local owner=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
   if owner and living(owner)then lease(owner,LEASES[s.id],now);Feedback.Hold(owner,HOLD_FACE[s.id])end
  end
 end
end)
return M
