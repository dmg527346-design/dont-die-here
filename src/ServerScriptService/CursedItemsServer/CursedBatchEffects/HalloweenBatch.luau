-- Halloween event items: required exactly once by the running CursedBatchEffects owner (like ItemBatch5).
-- Gated by ReplicatedStorage.EventConfig.Halloween (Enabled and StartsAt <= os.time() < EndsAt), the same rule as
-- CursedItemsServer.eventLive and HalloweenEventWorld. Studio tests force it with ReplicatedStorage attribute
-- StudioHalloween=true (ignored outside Studio). Event off = nothing spawns and leftover items sleep.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService.GameplayAudioServer)
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local Catalog=require(RS:WaitForChild('CursedCatalog'))
local EventConfig=require(RS:WaitForChild('EventConfig'))
local M={}
local detach,clearHold,setParts

-- BrewCauldron: drop an item in, 10 s loud brew, the item pops out glazed for a fixed +50% (capped)
local BREW_SECONDS=10
local BREW_NOISE_EVERY,BREW_NOISE_RADIUS=2,40
local GLAZE_SHARE,GLAZE_CAP=.5,30 -- cap is the level-1 value, scaled like LootBudget
local BREW_IDLE=Color3.fromRGB(143,225,75)   -- slime green
local BREW_ACTIVE=Color3.fromRGB(255,154,46) -- pumpkin orange
local BREW_COLD=Color3.fromRGB(60,62,70)
local brew=nil -- {model, cauldron, ends, noiseAt, query={[BasePart]=bool}}
local ctx -- {map, furniture, searchStart, missionRunning, script, speech} from CursedItemsServer (HalloweenInit)
local AngledCorners=require(game:GetService('ServerScriptService').MapGen:WaitForChild('AngledCorners'))

function M.Live()
 if Run:IsStudio() and RS:GetAttribute('StudioHalloween')==true then return true end
 local h=EventConfig.Halloween;local t=os.time()
 return type(h)=='table' and h.Enabled==true and type(h.StartsAt)=='number' and type(h.EndsAt)=='number' and h.EndsAt>h.StartsAt and t>=h.StartsAt and t<h.EndsAt
end
local function loose(m) -- lying in the level: not held, not in the cart, not being sold
 return m.Parent~=nil and m:IsDescendantOf(workspace) and m:GetAttribute('HeldBy')==nil and not m:GetAttribute('Selling') and not m:GetAttribute('CargoStored')
end
local function evidence(pos,radius,label,source)
 local e=SS:FindFirstChild('MonsterEvidence');if e then e:Fire(pos,radius,label,source)end
end
local function cue(key,fallback)return Sounds[key]~=nil and key or fallback end
local function valueScale()
 local state=RS:FindFirstChild('RecoveryRound');local round=state and tonumber(state:GetAttribute('Round'))or 1
 return 1+.12*(math.max(1,round)-1) -- same curve as LootBudget.Plan
end
local function addValue(m,amount)
 local v=m:GetAttribute('LootValue');if type(v)~='number' then v=m:GetAttribute('Value') end
 v=(type(v)=='number' and v or 0)+amount
 m:SetAttribute('Value',v);m:SetAttribute('LootValue',v) -- sale and cart read LootValue or Value
end

local function cauldronModel()
 local map=workspace:FindFirstChild('Mansion');local holder=map and map:FindFirstChild('HalloweenCauldron')
 return holder and holder:FindFirstChild('BrewCauldron')
end
local function brewable(m)
 if not m:IsA('Model') then return false end
 local id=m:GetAttribute('ItemId');local meta=type(id)=='string' and Catalog.Items[id] or nil
 return meta~=nil and not meta.gear and m.PrimaryPart~=nil and loose(m) and not m:GetAttribute('Glazed')
  and not m:GetAttribute('Brewing') and not m:GetAttribute('ItemWearOwner') and not m:GetAttribute('LobbyToy')
end
local function setQuery(m,s,on)
 for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart') then
  if on then if s.query[part]~=nil then part.CanQuery=s.query[part] end
  else s.query[part]=part.CanQuery;part.CanQuery=false end
 end end
end
local function finishBrew(glaze)
 local s=brew;brew=nil;if not s then return end
 local c,m=s.cauldron,s.model
 local liquid=c.Parent and c:FindFirstChild('Brew',true)
 if c.Parent then c:SetAttribute('Brewing',false);c:SetAttribute('BrewEndsAt',nil) end
 if m.Parent then
  m:SetAttribute('Brewing',nil);setQuery(m,s,true)
  if glaze and m.PrimaryPart then
   local value=m:GetAttribute('LootValue')or m:GetAttribute('Value')or 0
   addValue(m,math.min(math.floor(value*GLAZE_SHARE),math.floor(GLAZE_CAP*valueScale())))
   m:SetAttribute('Glazed',true)
   local light=Instance.new('PointLight');light.Name='GlazeGlow';light.Color=BREW_ACTIVE;light.Range=4;light.Brightness=.5;light.Shadows=false;light.Parent=m.PrimaryPart
   if liquid then m:PivotTo(CFrame.new(liquid.Position+Vector3.new(0,1.6,0))*m:GetPivot().Rotation) end
   if setParts then setParts(m,false,true) end -- unanchor so it flies out and lands; the item owner re-anchors it at rest
   local look=c:GetPivot().LookVector
   m.PrimaryPart.AssemblyLinearVelocity=Vector3.new(look.X*7,16,look.Z*7)
   Audio.Play('BalloonPop',m)
   -- funny beat: the pot burps BLORP!, a puff of orange steam, and everyone close by grins (VoiceMouthClient FaceBeat 'grin')
   if ctx and ctx.speech then ctx.speech(m.PrimaryPart.Position+Vector3.new(0,2,0),'BLORP!') end
   if liquid then
    local fx=Instance.new('ParticleEmitter');fx.Texture='rbxasset://textures/particles/smoke_main.dds';fx.Color=ColorSequence.new(BREW_ACTIVE,Color3.fromRGB(255,214,150))
    fx.Size=NumberSequence.new(.8,2.4);fx.Transparency=NumberSequence.new(.4,1);fx.Lifetime=NumberRange.new(.6,1.1);fx.Speed=NumberRange.new(4,7);fx.SpreadAngle=Vector2.new(35,35);fx.Rate=0;fx.Parent=liquid
    fx:Emit(24);game:GetService('Debris'):AddItem(fx,2)
   end
   local t=workspace:GetServerTimeNow()
   for _,q in ipairs(Players:GetPlayers()) do
    local r=q.Character and q.Character:FindFirstChild('HumanoidRootPart')
    if r and q:GetAttribute('MissionActive')==true and (r.Position-c:GetPivot().Position).Magnitude<30 then q:SetAttribute('FaceBeat','grin');q:SetAttribute('FaceBeatUntil',math.max(q:GetAttribute('FaceBeatUntil') or 0,t+2.5)) end
   end
  end
 end
 if c.Parent then
  local left=math.max(0,(c:GetAttribute('BrewsLeft')or 0)-(glaze and 1 or 0));c:SetAttribute('BrewsLeft',left)
  if liquid then liquid.Color=left>0 and BREW_IDLE or BREW_COLD end
  if left==0 then
   local fire=c:FindFirstChild('Fire',true);if fire and fire:IsA('BasePart') then fire.Transparency=1 end
   local root=c.PrimaryPart;local glow=root and root:FindFirstChild('CauldronGlow');if glow then glow.Enabled=false end
  end
 end
end
local function cauldron(now,live)
 local c=cauldronModel()
 if brew and (not live or brew.cauldron~=c) then finishBrew(false) end
 if not c or not live then return end
 local liquid=c:FindFirstChild('Brew',true);if not liquid or not liquid:IsA('BasePart') then return end
 if brew then
  if not brew.model.Parent or not loose(brew.model) then finishBrew(false);return end -- grabbed, carted or gone: no bonus
  if now>=brew.noiseAt then
   brew.noiseAt=now+BREW_NOISE_EVERY
   evidence(liquid.Position,BREW_NOISE_RADIUS,'cauldron bubbling',c);Audio.Play(cue('CauldronBubble','HeliumHiss'),c)
  end
  if now>=brew.ends then finishBrew(true) end
  return
 end
 if (c:GetAttribute('BrewsLeft')or 0)<=0 then return end
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive');if not interactive then return end
 local mouth=liquid.Position;local radius=liquid.Size.X*.45
 for _,m in ipairs(interactive:GetChildren())do
  if brewable(m) then
   local pos=m.PrimaryPart.Position
   if Vector3.new(pos.X-mouth.X,0,pos.Z-mouth.Z).Magnitude<radius and pos.Y>mouth.Y-1 and pos.Y<mouth.Y+3 then
    brew={model=m,cauldron=c,ends=now+BREW_SECONDS,noiseAt=now,query={}}
    if setParts then setParts(m,true,false) end
    setQuery(brew.model,brew,false);m:SetAttribute('Brewing',true)
    m:PivotTo(CFrame.new(mouth+Vector3.new(0,.15,0))*m:GetPivot().Rotation) -- half sunk in the brew
    c:SetAttribute('Brewing',true);c:SetAttribute('BrewEndsAt',now+BREW_SECONDS);liquid.Color=BREW_ACTIVE
    Audio.Play(cue('CauldronSplash','ItemImpact'),c)
    return
   end
  end
 end
end

local CAULDRON_MIN_LEVEL=2
function M.PlaceCauldron(force)
 local map,furniture,searchStart,missionRunning=ctx.map,ctx.furniture,ctx.searchStart,ctx.missionRunning
 local old=map:FindFirstChild('HalloweenCauldron');if old then old:Destroy()end
 local state=RS:FindFirstChild('RecoveryRound');local round=state and state:GetAttribute('Round')
 if not M.Live() or not missionRunning() or type(round)~='number' or (round<CAULDRON_MIN_LEVEL and not force) then return nil end
 local kit=SS:FindFirstChild('EventKit');local template=kit and kit:FindFirstChild('BrewCauldron')
 if not template or not template:IsA('Model') then warn('[Halloween] Missing EventKit.BrewCauldron');return nil end
 local collision=map:FindFirstChild('Collision');if not collision then return nil end
 local sources={}
 for _,m in map.Interactive:GetChildren()do if m:IsA('Model')and m.PrimaryPart and m:GetAttribute('LootSpawnIdentity')and not m:GetAttribute('AdminSpawned')then table.insert(sources,m)end end
 if #sources==0 then return nil end
 -- middle distance from the van: not on the doorstep, not in the last room
 table.sort(sources,function(a,b)
  local da,db=(a:GetPivot().Position-searchStart).Magnitude,(b:GetPivot().Position-searchStart).Magnitude
  if math.abs(da-db)>.01 then return da<db end;return a:GetAttribute('LootSpawnIdentity')<b:GetAttribute('LootSpawnIdentity')
 end)
 local box,size=template:GetBoundingBox();local pivot=template:GetPivot();local bottom=box.Position.Y-size.Y/2
 local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include;ray.FilterDescendantsInstances={collision};ray.RespectCanCollide=true
 local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances={collision,furniture,map.Interactive}
 local start=math.ceil(#sources/2)
 for i=0,#sources-1 do
  local origin=sources[(start+i-1)%#sources+1]:GetPivot().Position
  for turn=0,7 do
   local a=turn*math.pi/4;local probe=origin+Vector3.new(math.cos(a)*4.5,3,math.sin(a)*4.5)
   local hit=workspace:Raycast(probe,Vector3.new(0,-12,0),ray)
   if hit and hit.Normal.Y>.9 and not AngledCorners.Blocked(map,hit.Position,math.max(size.X,size.Z)/2+.6) then
    local clear=workspace:GetPartBoundsInBox(CFrame.new(hit.Position+Vector3.new(0,size.Y/2+.25,0)),Vector3.new(size.X+1.5,size.Y,size.Z+1.5),overlap)
    if #clear==0 then
     local m=template:Clone();m.Name='BrewCauldron'
     for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.Anchored=true;x.CanTouch=false;x.CanQuery=false;x.CanCollide=x.Name~='Fire' end end
     m:SetAttribute('BrewsLeft',3);m:SetAttribute('Brewing',false)
     local root=m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')
     if root then local light=Instance.new('PointLight');light.Name='CauldronGlow';light.Color=Color3.fromRGB(143,225,75);light.Range=8;light.Brightness=.7;light.Shadows=false;light.Parent=root end -- dim and local (lead 2026-10-27: fewer map lights)
     local holder=Instance.new('Folder');holder.Name='HalloweenCauldron';holder.Parent=map
     m:PivotTo(CFrame.new(hit.Position+Vector3.new(0,pivot.Position.Y-bottom+.03,0))*pivot.Rotation);m.Parent=holder
     return m
    end
   end
  end
 end
 return nil
end
function M.Init(c)
 ctx=c
 if Run:IsStudio() and c.script and not c.script:FindFirstChild('PreviewHalloweenCauldron') then -- editor-only test entry: places one now, ignoring the level gate
  local f=Instance.new('BindableFunction');f.Name='PreviewHalloweenCauldron';f.Parent=c.script
  f.OnInvoke=function()return M.PlaceCauldron(true)end
 end
end
function M.Configure(drop,clear,parts)detach=drop;clearHold=clear;setParts=parts end
function M.Pickup(_p,_m) end -- (item sections add their grab hooks here)
function M.ClearPlayer(_p) end
function M.ClearLevel()
 finishBrew(false) -- the cauldron itself is replaced by PlaceCauldron (every refresh) and dies with the map
end
function M.Tick(now)
 cauldron(now,M.Live())
end
return M
