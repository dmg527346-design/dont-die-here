-- Mall items: required exactly once by the running CursedBatchEffects owner.
-- Co-op MannequinHand/ClawPlushie remain exclusively owned by ItemBatch4.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local SoundService=game:GetService('SoundService')
local M={}
local TICK=.25
local LEASE=.5
local ORANGE=Color3.fromRGB(255,128,20)
local SAFE_TINT=Color3.fromRGB(90,195,175)
local DANGER_TINT=Color3.fromRGB(245,35,35)
local MOOD_RADIUS=40
local CALM_RADIUS=30
local GIFT_DRAIN_PER_SECOND=2
local GIFT_MIN_VALUE=0
local MUZAK_RAMP_SECONDS=30
local MUZAK_MAX_VOLUME=1.2
local BODY_REGIONS={body=true,feet=true,stalks=true,rings=true}
local ITEM_IDS={SelfTanner=true,MoodRing=true,WetFloorSign=true,GiftCard=true,MascotHead=true,MuzakRadio=true}
local tanned,tints,items,wear,leases={},{},{},{},{}
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
local function repaint(c)
 if not c or not c.Parent then return end
 -- Existing CharacterAppearanceServer uses descendant changes to repaint its
 -- colour regions; this restores current appearance settings after overrides.
 local nudge=Instance.new('Folder');nudge.Name='MallTintRepaint';nudge.Parent=c
 task.defer(function()nudge:Destroy()end)
end
local function clearTint(p)
 local saved=tints[p];tints[p]=nil
 if not saved then return end
 for part,s in pairs(saved.parts) do if part.Parent and part:GetAttribute('ColourOverride')==s.applied then
  local previous=s.override
  -- Batch3 clears Vampired before this owner during level cleanup. Do not
  -- resurrect its saved pale override after that curse has already ended.
  if s.vampire and not p:GetAttribute('Vampired') then previous=nil end
  part:SetAttribute('ColourOverride',previous);part.Color=s.color
  local surface=part:FindFirstChild('UniformBodySurface')
  if surface and surface.Color==s.applied and s.surfaceColor then surface.Color=s.surfaceColor end
 end end
 repaint(saved.character)
end
local function tint(p,c,color)
 local saved=tints[p]
 if saved and saved.character~=c then clearTint(p);saved=nil end
 if not saved then saved={character=c,parts={}};tints[p]=saved end
 for _,part in ipairs(c:GetDescendants()) do
  if part:IsA('BasePart') and BODY_REGIONS[part:GetAttribute('ColourRegion')] then
   local s=saved.parts[part]
   if not s then
    local surface=part:FindFirstChild('UniformBodySurface')
    s={override=part:GetAttribute('ColourOverride'),color=part.Color,surfaceColor=surface and surface.Color,
     vampire=p:GetAttribute('Vampired')==true};saved.parts[part]=s
   end
   s.applied=color
   if part:GetAttribute('ColourOverride')~=color then part:SetAttribute('ColourOverride',color) end
   if part.Color~=color then part.Color=color end
   local surface=part:FindFirstChild('UniformBodySurface');if surface and surface.Color~=color then surface.Color=color end
  end
 end
end
local function stopRadio(m,s)
 if s.music and s.music.Parent then s.music:Stop();s.music.TimePosition=0 end
 s.radioStart=nil
 if m.Parent then m:SetAttribute('MusicPlaying',false) end
end
local function drainGift(m,s,now)
 if not s.giftTick then return end
 local elapsed=math.max(0,now-s.giftTick);s.giftTick=now
 if not m.Parent then return end
 local value=m:GetAttribute('Value')
 if type(value)~='number' then value=m:GetAttribute('LootValue') end
 if type(value)~='number' then return end
 s.drainFraction=(s.drainFraction or 0)+elapsed*GIFT_DRAIN_PER_SECOND
 local whole=math.floor(s.drainFraction);s.drainFraction-=whole
 if whole>0 then
  local remaining=math.max(math.min(value,GIFT_MIN_VALUE),value-whole)
  m:SetAttribute('Value',remaining);m:SetAttribute('LootValue',remaining)
 end
end
local function currentHolder(m)
 local owner=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 return m:IsDescendantOf(workspace) and living(owner) and not m:GetAttribute('Selling') and not m:GetAttribute('CargoStored') and owner or nil
end
local function refreshHolder(m,s)
 local owner=currentHolder(m);local now=os.clock()
 if owner==s.holder then return end
 if s.id=='GiftCard' then drainGift(m,s,now);s.giftTick=owner and now or nil end
 if s.id=='MuzakRadio' then stopRadio(m,s);if owner then s.radioStart=now end end
 s.holder=owner
end
local function track(m,id)
 local s=items[m];if s then refreshHolder(m,s);return s end
 s={id=id,connections={}};items[m]=s
 for _,name in ipairs({'HeldBy','Selling','CargoStored'}) do
  table.insert(s.connections,m:GetAttributeChangedSignal(name):Connect(function()refreshHolder(m,s)end))
 end
 table.insert(s.connections,m.Destroying:Connect(function()
  stopRadio(m,s);for _,connection in ipairs(s.connections) do connection:Disconnect() end
  items[m]=nil;wear[m]=nil
 end))
 refreshHolder(m,s);return s
end
local function releaseWear(m)
 local s=wear[m];if not s then return false end
 wear[m]=nil
 local another=false
 for _,other in pairs(wear) do if other.owner==s.owner then another=true;break end end
 local stamps=leases[s.owner];local stamp=stamps and stamps.MascotMuffleUntil
 if not another and stamp then
  if s.owner:GetAttribute('MascotMuffleUntil')==stamp then s.owner:SetAttribute('MascotMuffleUntil',nil) end
  stamps.MascotMuffleUntil=nil
 end
 for _,key in ipairs({'ItemWearOwner','ItemWearRole','ItemWearOffset','ItemWearStart','ItemWearEnd'}) do m:SetAttribute(key,nil) end
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
function M.Configure(drop,clear,parts)
 detach=drop;clearHold=clear;setParts=parts
end
function M.IsWorn(m)return wear[m]~=nil end
function M.ReleaseHold(p,m)
 local item=items[m]
 if item and item.id=='GiftCard' and item.holder==p then drainGift(m,item,os.clock());item.giftTick=nil end
 local s=wear[m];if not s or s.owner~=p then return false end
 -- The outer detach already removes this item from inventory. Clear its hold
 -- before releaseWear so it cannot recurse into registry detach a second time.
 if clearHold then clearHold(m) end
 return releaseWear(m)
end
function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId');if not ITEM_IDS[id] then return end
 local c=living(p);if not c or not m.PrimaryPart then return end
 local s=track(m,id);local now=workspace:GetServerTimeNow()
 if id=='SelfTanner' then
  tanned[p]=true;p:SetAttribute('SelfTanned',true);tint(p,c,ORANGE)
 elseif id=='MoodRing' then lease(p,'MoodRingUntil',now)
 elseif id=='WetFloorSign' then lease(p,'WetFloorUntil',now)
 elseif id=='MascotHead' and not wear[m] then
  local head=c:FindFirstChild('Head');if not head or not clearHold or not detach or not setParts then return end
  clearHold(m);m:SetAttribute('HeldBy',p.UserId)
  for _,part in ipairs(m:GetDescendants()) do if part:IsA('BasePart') then
   part.Anchored=true;part.Massless=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
  end end
  local offset=(m:GetAttribute('MascotWearOffset')or CFrame.new(0,.7,0))*(m:GetAttribute('ModelPivotOffset')or CFrame.identity)
  m:SetAttribute('ItemWearOwner',p.UserId);m:SetAttribute('ItemWearRole','MascotHead');m:SetAttribute('ItemWearOffset',offset)
  m:SetAttribute('ItemWearStart',now);m:SetAttribute('ItemWearEnd',nil)
  wear[m]={owner=p,character=c};m:PivotTo(head.CFrame*offset);lease(p,'MascotMuffleUntil',now)
 elseif id=='GiftCard' then s.giftTick=os.clock()
 end
end
function M.ClearPlayer(p)
 tanned[p]=nil;p:SetAttribute('SelfTanned',nil);clearTint(p);clearLeases(p)
 for m,s in pairs(wear) do if s.owner==p then releaseWear(m) end end
 for m,s in pairs(items) do if s.holder==p then
  if s.id=='GiftCard' then drainGift(m,s,os.clock());s.giftTick=nil end
  if s.id=='MuzakRadio' then stopRadio(m,s) end
  s.holder=nil
 end end
end
function M.ClearLevel()
 for _,p in ipairs(Players:GetPlayers()) do M.ClearPlayer(p) end
 for m,s in pairs(items) do
  stopRadio(m,s);for _,connection in ipairs(s.connections) do connection:Disconnect() end
  if s.origin and s.origin.Parent then s.origin:Destroy() end
 end
 table.clear(items);table.clear(wear);table.clear(tanned);table.clear(tints);table.clear(leases)
end
local function moodColor(c,creatures)
 local root=c:FindFirstChild('HumanoidRootPart');if not root then return SAFE_TINT end
 local nearest=MOOD_RADIUS
 if creatures then for _,enemy in ipairs(creatures:GetChildren()) do
  local primary=enemy:IsA('Model') and enemy.PrimaryPart
  local h=enemy:FindFirstChildOfClass('Humanoid')
  if primary and (not h or h.Health>0) then nearest=math.min(nearest,(primary.Position-root.Position).Magnitude) end
 end end
 return SAFE_TINT:Lerp(DANGER_TINT,math.clamp(1-nearest/MOOD_RADIUS,0,1)^.5) -- reacts early, full red when a creature is on you
end
local function radio(m,s,creatures,clock)
 if not m.PrimaryPart then return end
 if not s.holder then stopRadio(m,s);return end
 if not s.music or not s.music.Parent then
  local cue=require(RS:WaitForChild('GameplaySoundCatalog')).DiscoMusic
  local origin=Instance.new('Attachment');origin.Name='MuzakAudioOrigin';origin.Parent=m.PrimaryPart
  local song=Instance.new('Sound');song.Name='MuzakRadioSong';song.SoundId=cue.id; song.Looped=true
  song.PlaybackSpeed=cue.speed or 1;song.SoundGroup=SoundService:FindFirstChild('GameplayMusic')
  song.RollOffMode=Enum.RollOffMode.InverseTapered;song.RollOffMinDistance=4;song.RollOffMaxDistance=55;song.Parent=origin
  s.origin=origin;s.music=song;s.baseVolume=cue.volume or .12
 end
 s.radioStart=s.radioStart or clock
 s.music.Volume=s.baseVolume+(MUZAK_MAX_VOLUME-s.baseVolume)*math.clamp((clock-s.radioStart)/MUZAK_RAMP_SECONDS,0,1)
 if not s.music.IsPlaying then s.music:Play() end
 m:SetAttribute('MusicPlaying',true)
 if creatures then for _,enemy in ipairs(creatures:GetChildren()) do
  local primary=enemy:IsA('Model') and enemy.PrimaryPart
  if primary and (primary.Position-m.PrimaryPart.Position).Magnitude<CALM_RADIUS then
   enemy:SetAttribute('CalmUntil',math.max(enemy:GetAttribute('CalmUntil')or 0,clock+.6))
  end
 end end
end
local elapsed=0
local function lobbyOnly()
 local state=RS:FindFirstChild('LobbyState')
 if not state or state:GetAttribute('Mode')~='Menu' then return false end
 for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('MissionActive')==true then return false end end
 return true
end
Run.Heartbeat:Connect(function(dt)
 if lobbyOnly()then return end
 local now=workspace:GetServerTimeNow()
 for m,s in pairs(wear) do
  local c=living(s.owner)
  if not m.Parent or c~=s.character or m:GetAttribute('HeldBy')~=s.owner.UserId then releaseWear(m)
  else
   local head=c:FindFirstChild('Head')
   local offset=m:GetAttribute('ItemWearOffset')
   if not head or typeof(offset)~='CFrame' then releaseWear(m)
   else m:PivotTo(head.CFrame*offset) end
  end
 end
 elapsed+=dt;if elapsed<TICK then return end;elapsed=0
 local clock=os.clock();local mood={};local creatures=workspace:FindFirstChild('RoamingCreatures')
 for m,s in pairs(items) do if m.Parent then
  refreshHolder(m,s);if s.id=='MoodRing' and not s.holder then local stone=m:FindFirstChild('Stone');if stone and stone.Material==Enum.Material.Neon then stone.Material=Enum.Material.SmoothPlastic;stone.Color=Color3.new(1,1,1) end end
  local p=s.holder
  if p then
   if s.id=='MoodRing' then mood[p]=true;lease(p,'MoodRingUntil',now);local stone,holderChar=m:FindFirstChild('Stone'),living(p);if stone and holderChar then stone.Material=Enum.Material.Neon;stone.Color=moodColor(holderChar,creatures) end
   elseif s.id=='WetFloorSign' then lease(p,'WetFloorUntil',now)
   elseif s.id=='MascotHead' and wear[m] then lease(p,'MascotMuffleUntil',now)
   elseif s.id=='GiftCard' then drainGift(m,s,clock) end
  end
  if s.id=='MuzakRadio' then radio(m,s,creatures,clock) end
 end end
 for _,p in ipairs(Players:GetPlayers()) do
  local c=living(p)
  if c and (mood[p] or tanned[p]) then tint(p,c,if mood[p] then moodColor(c,creatures) else ORANGE)
  elseif tints[p] then clearTint(p) end
  if not c then M.ClearPlayer(p) end
 end
end)
Players.PlayerRemoving:Connect(M.ClearPlayer)
return M
