
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService.GameplayAudioServer)
local Batch3=require(script:WaitForChild('ItemBatch3'))
local Batch4=require(script:WaitForChild('ItemBatch4'))
local Batch5=require(script:WaitForChild('ItemBatch5'))
local Batch8=require(script:WaitForChild('ItemBatch8')) -- CursedB 2026-10-27
local Batch9=require(script:WaitForChild('ItemBatch9'))
local Batch6=require(script:WaitForChild('ItemBatch6')) -- CursedA 2026-10-27
local Batch7=require(script:WaitForChild('ItemBatch7')) -- CursedA 2026-10-27
local Puzzle=require(script:WaitForChild('PuzzleBatch')) -- World/CatShelf puzzle frame (WorldA)
local MonsterBatch=require(script:WaitForChild('MonsterBatch')) -- Monsters build 2026-10-27: Watch Gnome, Tip Bell, Cuckoo Clock
local DraftEffects=require(script:WaitForChild('ItemDraftEffects'))
local Halloween=require(script:WaitForChild('HalloweenBatch')) -- World/BrewCauldron (WorldA): event-gated cauldron
local M={}
local wear={}
local perfumed={}
local nextWhistle={}
local eyeFire={}
local beeFx,frostFx={},{}
local crunchNext={}
local applyMakeup
local detach,clearHold,parts,restoreHold
local folder=Instance.new('Folder');folder.Name='CursedLevelCosmetics';folder.Parent=workspace
local roundState
local function lobbyActive(p)
 local state=RS:FindFirstChild('LobbyState')
 return p and p.Parent and p:GetAttribute('MissionActive')~=true and p:GetAttribute('LobbyReady')==true and state and state:GetAttribute('Mode')=='Menu'
end
local function itemModels()
 local list={}
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 local current=RS:FindFirstChild('LobbyState')
 if (not current or current:GetAttribute('Mode')~='Menu') and interactive then for _,m in ipairs(interactive:GetChildren())do table.insert(list,m)end end
 local state=RS:FindFirstChild('LobbyState');local world=workspace:FindFirstChild('LobbyWorld');local toys=world and world:FindFirstChild('Toys');local runtime=toys and toys:FindFirstChild('RuntimeToys')
 if state and state:GetAttribute('Mode')=='Menu' and runtime then for _,m in ipairs(runtime:GetChildren())do if m:GetAttribute('LobbyToy')==true then table.insert(list,m)end end end
 return list
end
local function living(p)
 local c=p and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return p and p.Parent and (p:GetAttribute('MissionActive')==true or lobbyActive(p)) and h and h.Health>0
end
local function cosmetic(p,template,role,offset,endAt)
 local m=SS.CursedAccessoryKit[template]:Clone();m.Name=role..'_'..p.UserId
 m:SetAttribute('CosmeticOwner',p.UserId);m:SetAttribute('CosmeticRole',role);m:SetAttribute('CosmeticOffset',offset)
 m:SetAttribute('CosmeticBorn',workspace:GetServerTimeNow());m:SetAttribute('CosmeticEnd',endAt)
 for _,x in ipairs(m:GetDescendants())do
  if x:IsA('JointInstance')or x:IsA('Constraint')then x:Destroy()
  elseif x:IsA('BasePart')then x.Anchored=true;x.Massless=true;x.CanCollide=false;x.CanTouch=false;x.CanQuery=false;x.CastShadow=false end
 end
 local h=p.Character and p.Character:FindFirstChild('Head');if h then m:PivotTo(h.CFrame*offset)end
 m.Parent=folder
 return m
end
local function startWear(p,m,role,offset,duration)
 if wear[m]then return end
 clearHold(m);m:SetAttribute('HeldBy',p.UserId)
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')then x.Anchored=true;x.Massless=true;x.CanCollide=false;x.CanTouch=false;x.CanQuery=false end end
 offset*=m:GetAttribute('ModelPivotOffset')or CFrame.identity
 local now=workspace:GetServerTimeNow()
 m:SetAttribute('ItemWearOwner',p.UserId);m:SetAttribute('ItemWearRole',role);m:SetAttribute('ItemWearOffset',offset);m:SetAttribute('ItemWearStart',now);m:SetAttribute('ItemWearEnd',now+duration)
 wear[m]={owner=p,ends=now+duration,role=role}
 local head=p.Character and p.Character:FindFirstChild('Head');if head then m:PivotTo(head.CFrame*offset)end
end
function M.Configure(drop,clear,setParts,restore)detach=drop;clearHold=clear;parts=setParts;restoreHold=restore;Batch4.Configure(drop,clear,setParts);Batch5.Configure(drop,clear,setParts);Batch8.Configure(drop,clear,setParts);Batch9.Configure(drop,clear,setParts);Batch6.Configure(drop,clear,setParts);Batch7.Configure(drop,clear,setParts);Puzzle.Configure(drop,clear,setParts);Halloween.Configure(drop,clear,setParts)end
M.HalloweenInit=Halloween.Init;M.HalloweenPlace=Halloween.PlaceCauldron -- CursedItemsServer (World/BrewCauldron)
M.PuzzleInit=Puzzle.Init;M.PuzzleRestock=Puzzle.Restock;M.PuzzleClue=Puzzle.Clue -- CursedItemsServer (World/CatShelf etc.)
function M.CanSpawn(id)return Batch4.CanSpawn(id)end
-- Halloween event loot gate (CursedItemsServer.eligibleItems): ItemBatch8 owns the rule (CursedB 2026-10-27).
function M.HalloweenLive()return Batch8.HalloweenLive()end
function M.CanRemove(p,m)return Batch4.CanRemove(p,m)end
function M.RemoveAttached(p,m)return Batch4.RemoveAttached(p,m)end
function M.AdoptCompanion(p,m)return Batch7.AdoptCompanion(p,m)end
function M.HalloweenLive()return Halloween.Live()end
function M.IsWorn(m)return wear[m]~=nil or Batch5.IsWorn(m)or Batch6.IsWorn(m)or Batch7.IsWorn(m)end
function M.ReleaseHold(p,m)
 DraftEffects.Release(p,m)
 if Batch5.ReleaseHold(p,m)then return true end
 if Batch6.ReleaseHold(p,m)then return true end
 if Batch7.ReleaseHold(p,m)then return true end
 if not wear[m] or wear[m].owner~=p then return false end
 clearHold(m)
 -- Setting the party hat down takes it off now (Heartbeat ends the wear next frame), blower included.
 if wear[m].role=='BirthdayHat' then wear[m].ends=0 end
 return true
end
local function endWear(m,s)
 wear[m]=nil
 if s.role=='BirthdayHat' and s.owner then
  for _,c in ipairs(folder:GetChildren())do if c:GetAttribute('CosmeticRole')=='PartyBlower' and c:GetAttribute('CosmeticOwner')==s.owner.UserId then c:Destroy()end end
  s.owner:SetAttribute('PartyBlowerUntil',nil);s.owner:SetAttribute('PartyBlowerStart',nil)
 end
 if not m.Parent then return end
 m:SetAttribute('ItemWearOwner',nil);m:SetAttribute('ItemWearRole',nil);m:SetAttribute('ItemWearOffset',nil);m:SetAttribute('ItemWearEnd',nil)
 if s.role=='Cloud' then
  m:SetAttribute('Dehydrated',true);m:SetAttribute('DisplayName','Dehydrated cloud')
  for _,x in ipairs(m:GetChildren())do if x:IsA('BasePart')and x.Name:find('CloudLobe')then x.Size=x:GetAttribute('WetSize')*Vector3.new(1,.55,1);x.Color=Color3.fromRGB(185,164,135)end end
 end
 -- Completing an automatic use returns to the original grab, without replaying Pickup.
 if m:GetAttribute('HeldBy')==s.owner.UserId and living(s.owner) and s.owner:GetAttribute('PhysicalGrabActive')==true and restoreHold and restoreHold(m,s.owner)then return end
 if m:GetAttribute('HeldBy')==s.owner.UserId then detach(s.owner,m,false,true)else parts(m,false,true)end
 if m.PrimaryPart then
  m.PrimaryPart.CanQuery=true;m.PrimaryPart.Massless=false
  local root=s.owner.Character and s.owner.Character:FindFirstChild('HumanoidRootPart')
  if root then m:PivotTo(root.CFrame*CFrame.new(-2,1,-1.5))end
  m.PrimaryPart.AssemblyLinearVelocity=Vector3.new(0,-1,0)
 end
end
function M.Pickup(p,m)
 DraftEffects.Pickup(p,m)
 Batch3.Pickup(p,m)
 Batch4.Pickup(p,m)
 Batch5.Pickup(p,m);Batch8.Pickup(p,m);Batch9.Pickup(p,m)
 Batch6.Pickup(p,m)
 Batch7.Pickup(p,m)
 Puzzle.Pickup(p,m)
 Halloween.Pickup(p,m)
 MonsterBatch.Pickup(p,m)
 local id=m:GetAttribute('ItemId');local now=workspace:GetServerTimeNow()
 if id=='RainCloud'and not m:GetAttribute('Dehydrated')then
  startWear(p,m,'Cloud',CFrame.new(0,3.65,0),5)
  p:SetAttribute('CryingUntil',now+5)
 elseif id=='CoolSunglasses'then
  -- Glasses share the moustache face-pull lifecycle in CursedItemsServer.
  for _,x in ipairs(folder:GetChildren())do if x:GetAttribute('CosmeticOwner')==p.UserId and x:GetAttribute('CosmeticRole')=='CoolHat'then x:Destroy()end end
  cosmetic(p,'CoolHat','CoolHat',CFrame.new(0,2.76,0),nil)
  Audio.Play('CoolEquip',m)
 elseif id=='FlyJar'and not m:GetAttribute('FlyEscaped')then
  m:SetAttribute('FlyEscaped',true);m:SetAttribute('JarOpenedAt',now)
  local lid=m:FindFirstChild('JarLid')
  -- Keep the assembly welded to the jar; hiding only the cap left its trim floating.
  local hidden={}
  if lid then hidden[lid]=true;for _,part in ipairs(lid:GetConnectedParts(true))do if part~=m.PrimaryPart and (part.Name:lower():match('^jarlid')or part.Name:lower():match('^jarcap'))then hidden[part]=true end end end
  for _,part in ipairs(m:GetDescendants())do if part:IsA('BasePart')and (hidden[part]or part.Name:lower():match('^jarlid')or part.Name:lower():match('^jarcap'))then part.Transparency=1;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false end end
  for _,x in ipairs(m:GetDescendants())do if x:IsA('PointLight')and x.Name=='FlyGlow'then x.Enabled=false end end
  local fly=cosmetic(p,'AnnoyingFly','Fly',CFrame.new(0,1,2),now+20)
  fly:SetAttribute('FlySeed',math.random(1,9999))
  Audio.Play('JarPop',m)
 elseif id=='CursedPerfume'and not m:GetAttribute('PerfumeEmpty')then
  m:SetAttribute('PerfumeEmpty',true);m:SetAttribute('PerfumeSprayStart',now)
  local liquid=m:FindFirstChild('PerfumeLiquid');if liquid then liquid:SetAttribute('FullSize',liquid.Size);liquid:SetAttribute('LiquidRest',m.PrimaryPart.CFrame:ToObjectSpace(liquid.CFrame));liquid.Transparency=1 end
  local nozzle=m:FindFirstChild('Nozzle');if nozzle then nozzle:SetAttribute('NozzleRest',m.PrimaryPart.CFrame:ToObjectSpace(nozzle.CFrame))end
  p:SetAttribute('PerfumeSprayStart',now);p:SetAttribute('PerfumeSprayUntil',now+1.8)
  startWear(p,m,'PerfumeSpray',CFrame.new(.85,.2,1.3)*CFrame.Angles(.25,-2.44,0),1.8)
  perfumed[p]={begins=now+1.65};p:SetAttribute('PerfumeAuraStart',now+1.65)
  p:SetAttribute('PerfumedLevel',roundState and roundState:GetAttribute('Round')or 1)
 elseif id=='BirthdayHat'and not m:GetAttribute('HatWorn')then
  -- worn once (5 s) on the first grab; after it comes off it is an ordinary holdable item
  m:SetAttribute('HatWorn',true)
  startWear(p,m,'BirthdayHat',CFrame.new(0,3.18,0),5)
  cosmetic(p,'PartyBlower','PartyBlower',CFrame.new(0,.03,.88),now+5)
  p:SetAttribute('PartyBlowerUntil',now+5);p:SetAttribute('PartyBlowerStart',now)
  Audio.Play('PartyEquip',m)
 elseif id=='BeehiveJar'then
  -- One swollen eye from the first sting; it stays until ClearPlayer/ClearLevel.
  if not p:GetAttribute('BeeSwollen')then p:SetAttribute('BeeSwollen',math.random()<.5 and'Left'or'Right')end
 elseif id=='MakeupKit'then
  p:SetAttribute('MadeUp',true);applyMakeup(p)
 elseif id=='ChewingGum'then
  -- One stick per pickup (the pack keeps its sale value): chew 3 s, blow a bubble, pop at 5.5 s.
  for i=1,5 do
   local stick=m:FindFirstChild('GumStick'..i)
   if stick and stick.Transparency<1 then
    stick.Transparency=1;p:SetAttribute('GumChewStart',now)
    task.delay(5.5,function()local head=p.Parent and p:GetAttribute('GumChewStart')==now and p.Character and p.Character:FindFirstChild('Head');if head then Audio.Play('JarPop',head)end end)
    break
   end
  end
 elseif id=='CoffeeMug'and not m:GetAttribute('CoffeeEmpty')then
  -- Drink it all in one go; the stain lasts until the level ends.
  m:SetAttribute('CoffeeEmpty',true)
  startWear(p,m,'CoffeeSip',CFrame.new(0,-.45,1.15)*CFrame.Angles(-.9,0,0),1.6)
  local lobbyCoffee=m:GetAttribute('LobbyToy')==true;local character=p.Character
   task.delay(1.2,function()
    if lobbyCoffee and (not m.Parent or not lobbyActive(p) or p.Character~=character)then return end
    local l=m:FindFirstChild('CoffeeLiquid');if l then l.Transparency=1 end;if p.Parent then p:SetAttribute('TeethStained',true)end
   end)
 elseif id=='JawbreakerBag'then
  for i=1,5 do local c=m:FindFirstChild('Jawbreaker'..i);if c and c.Transparency<1 then c.Transparency=1;break end end
 end
end
local function douseEyes(p)
 for _,x in ipairs(eyeFire[p]or{})do x:Destroy()end;eyeFire[p]=nil
end
-- Red pepper flames sit on the front of each eyeball and follow it through the eye rig's welds.
local function igniteEyes(p)
 local head=p.Character and p.Character:FindFirstChild('Head');local fx={}
 if not head then return fx end
 for _,side in ipairs({'Left','Right'})do
  local eye=head:FindFirstChild(side..'Eyeball')
  if eye then
   local a=Instance.new('Attachment');a.Name='PepperEyeFire'
   a.Position=eye.CFrame:VectorToObjectSpace(head.CFrame.LookVector)*eye.Size.Z*.45;a.Parent=eye
   local e=Instance.new('ParticleEmitter');e.Name='PepperFlame';e.Texture='rbxasset://textures/particles/fire_main.dds'
   e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,240,120)),ColorSequenceKeypoint.new(.45,Color3.fromRGB(255,120,20)),ColorSequenceKeypoint.new(1,Color3.fromRGB(200,30,10))})
   e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.42),NumberSequenceKeypoint.new(1,0)})
   e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})
   e.LightEmission=1;e.Lifetime=NumberRange.new(.25,.45);e.Rate=45;e.Speed=NumberRange.new(1.5,2.5)
   e.SpreadAngle=Vector2.new(18,18);e.Acceleration=Vector3.new(0,6,0);e.RotSpeed=NumberRange.new(-90,90);e.ZOffset=.6
   e.Parent=a
   local l=Instance.new('PointLight');l.Name='PepperGlow';l.Color=Color3.fromRGB(255,120,30);l.Brightness=1.6;l.Range=5;l.Parent=a
   table.insert(fx,a)
  end
 end
 return fx
end
-- Front of an eyeball from its pupil (server pupils rest at the front of the eye).
local function eyeFront(head,side)
 local eye=head:FindFirstChild(side..'Eyeball');if not eye then return nil end
 local pupil=head:FindFirstChild(side..'Pupil');local f=pupil and pupil.Position-eye.Position
 return eye,(f and f.Magnitude>.01)and f.Unit or head.CFrame.LookVector
end
local function emitter(parent,props)
 local e=Instance.new('ParticleEmitter');for k,v in pairs(props)do e[k]=v end;e.Parent=parent;return e
end
local function addBees(p)
 local head=p.Character and p.Character:FindFirstChild('Head');if not head then return nil end
 local a=Instance.new('Attachment');a.Name='BeeSwarm';a.Position=Vector3.new(0,.7,0)
 emitter(a,{Name='Bees',Texture='rbxasset://textures/particles/sparkles_main.dds',Shape=Enum.ParticleEmitterShape.Sphere,
  Color=ColorSequence.new(Color3.fromRGB(255,200,25)),Size=NumberSequence.new(.16),Lifetime=NumberRange.new(.7,1.3),Rate=28,
  Speed=NumberRange.new(3,5),SpreadAngle=Vector2.new(180,180),Drag=4,RotSpeed=NumberRange.new(-300,300),LightEmission=.1})
 emitter(a,{Name='BeeStripes',Texture='rbxasset://textures/particles/sparkles_main.dds',Shape=Enum.ParticleEmitterShape.Sphere,
  Color=ColorSequence.new(Color3.fromRGB(25,20,15)),Size=NumberSequence.new(.1),Lifetime=NumberRange.new(.7,1.3),Rate=14,
  Speed=NumberRange.new(3,5),SpreadAngle=Vector2.new(180,180),Drag=4})
 a.Parent=head;return a
end
local function addFrost(p)
 local head=p.Character and p.Character:FindFirstChild('Head');if not head then return nil end
 local f=Instance.new('Folder');f.Name='PopsicleFrost'
 for _,side in ipairs({'Left','Right'})do
  local eye,front=eyeFront(head,side)
  if eye then
   local a=Instance.new('Attachment');a.Name='PopsicleFrost';a.Position=eye.CFrame:VectorToObjectSpace(front)*eye.Size.Z*.45;a.Parent=eye
   emitter(a,{Name='Frost',Texture='rbxasset://textures/particles/sparkles_main.dds',Color=ColorSequence.new(Color3.fromRGB(200,235,255)),
    Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(1,0)}),Lifetime=NumberRange.new(.6,1),Rate=10,
    Speed=NumberRange.new(.3,.8),SpreadAngle=Vector2.new(60,60),Acceleration=Vector3.new(0,-1.5,0),LightEmission=.6})
   local link=Instance.new('ObjectValue');link.Value=a;link.Parent=f
  end
 end
 f.Parent=head;return f
end
local function dropFx(store,p)
 local fx=store[p];store[p]=nil
 if fx then if fx:IsA('Folder')then for _,l in ipairs(fx:GetChildren())do if l.Value then l.Value:Destroy()end end end;fx:Destroy()end
end
-- Makeup: red lips and long lashes welded to the eyeballs. Idempotent, so the tick re-applies it after a respawn.
function applyMakeup(p)
 local head=p.Character and p.Character:FindFirstChild('Head');if not head or head:FindFirstChild('MakeupLashes')then return end
 local lips=head:FindFirstChild('ConnectedLips')
 -- CharacterAppearanceServer repaints colour regions on any change; ColourOverride is the hook it honours.
 if lips then if lips:GetAttribute('MakeupOrigColor')==nil then lips:SetAttribute('MakeupOrigColor',lips.Color)end;lips:SetAttribute('ColourOverride',Color3.fromRGB(205,0,25));lips.Color=Color3.fromRGB(205,0,25)end
 local folder=Instance.new('Folder');folder.Name='MakeupLashes'
 for _,side in ipairs({'Left','Right'})do
  local eye,front=eyeFront(head,side)
  if eye then
   local up=head.CFrame.UpVector;local right=front:Cross(up).Unit;local r=eye.Size.Y/2
   for i=-2,2 do
    local base=eye.Position+front*r*.62+up*r*.72+right*i*r*.24
    local tip=base+up*.34+front*.12+right*i*.07
    local lash=Instance.new('Part');lash.Name='MakeupLash';lash.Color=Color3.fromRGB(12,8,12);lash.Material=Enum.Material.SmoothPlastic
    lash.Size=Vector3.new(.035,(tip-base).Magnitude,.035);lash.CFrame=CFrame.lookAt((base+tip)/2,tip)*CFrame.Angles(math.pi/2,0,0)
    lash.CanCollide=false;lash.CanTouch=false;lash.CanQuery=false;lash.Massless=true;lash.CastShadow=false
    local w=Instance.new('WeldConstraint');w.Part0=eye;w.Part1=lash;w.Parent=lash;lash.Parent=folder
   end
  end
 end
 folder.Parent=head
end
-- Coffee stain: teeth are a CharacterAppearanceServer colour region, so tint through ColourOverride.
local STAIN=Color3.fromRGB(200,165,70)
local function teeth(p)
 local head=p.Character and p.Character:FindFirstChild('Head');local list={}
 if head then for _,row in ipairs({'Upper','Lower'})do for i=1,7 do local t=head:FindFirstChild(row..'Tooth'..i);if t then table.insert(list,t)end end end end
 return list
end
local function applyStain(p)
 for _,t in ipairs(teeth(p))do if t:GetAttribute('ColourOverride')~=STAIN then t:SetAttribute('ColourOverride',STAIN);t.Color=STAIN end end
end
local function removeStain(p)
 for _,t in ipairs(teeth(p))do if t:GetAttribute('ColourOverride')then t:SetAttribute('ColourOverride',nil);t.Color=Color3.new(1,1,1)end end
end
local function removeMakeup(p)
 local head=p.Character and p.Character:FindFirstChild('Head');if not head then return end
 local lashes=head:FindFirstChild('MakeupLashes');if lashes then lashes:Destroy()end
 local lips=head:FindFirstChild('ConnectedLips');local orig=lips and lips:GetAttribute('MakeupOrigColor')
 if lips then lips:SetAttribute('ColourOverride',nil)end
 if orig then lips:SetAttribute('MakeupOrigColor',nil);lips.Color=orig end
end
function M.ClearPlayer(p)
 DraftEffects.ClearPlayer(p)
 Batch3.ClearPlayer(p)
 Batch4.ClearPlayer(p)
 Batch5.ClearPlayer(p);Batch8.ClearPlayer(p);Batch9.ClearPlayer(p)
 Batch6.ClearPlayer(p)
 Batch7.ClearPlayer(p)
 Puzzle.ClearPlayer(p)
 Halloween.ClearPlayer(p)
 MonsterBatch.ClearPlayer(p)
 perfumed[p]=nil;nextWhistle[p]=nil;douseEyes(p);dropFx(beeFx,p);dropFx(frostFx,p);removeMakeup(p);removeStain(p);crunchNext[p]=nil
 for m,s in pairs(wear)do if s.owner==p then endWear(m,s)end end
 for _,m in ipairs(folder:GetChildren())do if m:GetAttribute('CosmeticOwner')==p.UserId then m:Destroy()end end
 for _,key in ipairs({'GumChewStart','TeethStained','BrokenTeeth','DollUntil','SnailUntil','CrunchUntil','MadeUp','BeeSwollen','HotSauceUntil','FrozenUntil','BeesUntil','PepperSquint','CryingUntil','PerfumedLevel','PerfumeAuraStart','PerfumeSprayStart','PerfumeSprayUntil','WhistleUntil','PartyBlowerUntil','PartyBlowerStart'})do p:SetAttribute(key,nil)end
end
function M.ClearLevel()
 DraftEffects.ClearLevel()
 Batch4.ClearLevel()
 Batch5.ClearLevel();Batch8.ClearLevel();Batch9.ClearLevel()
 Batch6.ClearLevel()
 Batch7.ClearLevel()
 Puzzle.ClearLevel()
 Halloween.ClearLevel()
 MonsterBatch.ClearLevel()
 for m,s in pairs(wear)do endWear(m,s)end
 for _,p in ipairs(Players:GetPlayers())do M.ClearPlayer(p)end
 folder:ClearAllChildren()
end

function M.CanWhistle(p,q,now)
 local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
 local qr=q.Character and q.Character:FindFirstChild('HumanoidRootPart')
 if q==p or not living(p)or not living(q)or not root or not qr or q:GetAttribute('Hiding')or q:GetAttribute('ClosetState')or q:GetAttribute('MonsterJumpscareActive')or now<=(nextWhistle[q]or 0)or(qr.Position-root.Position).Magnitude>=11 then return false end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
 local map=workspace:FindFirstChild('Mansion');local collision=map and map:FindFirstChild('Collision')
 if not collision then return false end
 params.FilterDescendantsInstances={collision};params.RespectCanCollide=true
 return workspace:Raycast(root.Position+Vector3.new(0,1,0),qr.Position-root.Position,params)==nil
end

local acc=0
Run.Heartbeat:Connect(function(dt)
 local now=workspace:GetServerTimeNow()
 DraftEffects.Frame(dt,now)
 for m,s in pairs(wear)do
  if not m.Parent then wear[m]=nil
  elseif now>=s.ends or not living(s.owner)then endWear(m,s)
  else
   local head=s.owner.Character:FindFirstChild('Head')
   if head then
    local offset=m:GetAttribute('ItemWearOffset')
    if s.role=='Cloud'then offset*=CFrame.new(0,math.sin(now*2)*.1,0)
    elseif s.role=='PerfumeSpray'then
     local age=now-(m:GetAttribute('ItemWearStart')or now);offset*=CFrame.Angles(0,0,math.sin(age*math.pi*4)*.12)
    end
    m:PivotTo(head.CFrame*offset)
   end
  end
 end
 acc+=dt;if acc<.25 then return end;acc=0
 DraftEffects.Tick(now)
 Halloween.Tick(now)
 -- Crying onion: sob only while it is in hand; the short lease lapses within half a second of letting go.
 local interactive=itemModels()
 if interactive then
  for _,m in ipairs(interactive)do
   if m:GetAttribute('ItemId')=='CryingOnion'then
    local p=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
    if living(p)then p:SetAttribute('CryingUntil',math.max(p:GetAttribute('CryingUntil')or 0,now+.5))end
   end
  end
 end
 -- Red pepper: eyes burn only while held; the squint stays until ClearLevel/ClearPlayer.
 local burning={}
 if interactive then
  for _,m in ipairs(interactive)do
   if m:GetAttribute('ItemId')=='RedPepper'then
    local p=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
    if living(p)then burning[p]=true end
   end
  end
 end
 for p in pairs(burning)do
  p:SetAttribute('PepperSquint',true)
  local fx=eyeFire[p]
  if not fx or not fx[1]or not fx[1].Parent then douseEyes(p);eyeFire[p]=igniteEyes(p)end
 end
 for p in pairs(eyeFire)do if not burning[p]then douseEyes(p)end end
 -- Held leases: hot sauce (mouth fire while speaking, client), popsicle (frost) and beehive jar (bee swarm).
 local leases={HotSauce='HotSauceUntil',Popsicle='FrozenUntil',BeehiveJar='BeesUntil',VentriloquistDoll='DollUntil',SnailShell='SnailUntil',JawbreakerBag='CrunchUntil'}
 local swarm,frozen,crunching={},{},{}
 if interactive then
  for _,m in ipairs(interactive)do
   local key=leases[m:GetAttribute('ItemId')or'']
   local p=key and Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
   if p and living(p)then
    p:SetAttribute(key,math.max(p:GetAttribute(key)or 0,now+.5))
    if key=='BeesUntil'then swarm[p]=true elseif key=='FrozenUntil'then frozen[p]=true elseif key=='CrunchUntil'then crunching[p]=true end
   end
  end
 end
 for p in pairs(swarm)do local fx=beeFx[p];if not fx or not fx.Parent then dropFx(beeFx,p);beeFx[p]=addBees(p)end end
 for p in pairs(beeFx)do if not swarm[p]then dropFx(beeFx,p)end end
 for p in pairs(frozen)do local fx=frostFx[p];if not fx or not fx.Parent then dropFx(frostFx,p);frostFx[p]=addFrost(p)end end
 for p in pairs(frostFx)do if not frozen[p]then dropFx(frostFx,p)end end
 for _,p in ipairs(Players:GetPlayers())do
  if p:GetAttribute('MadeUp')and living(p)then applyMakeup(p)end
  if p:GetAttribute('TeethStained')and living(p)then applyStain(p)end
 end
 -- Jawbreaker: every crunch while held cracks one more tooth (client hides them) for the rest of the level.
 for p in pairs(crunching)do
  if now>=(crunchNext[p]or 0)then
   crunchNext[p]=now+1.6
   p:SetAttribute('BrokenTeeth',math.min(14,(p:GetAttribute('BrokenTeeth')or 0)+1))
   local head=p.Character and p.Character:FindFirstChild('Head');if head then Audio.Play('GlassImpact',head)end
  end
 end
 for p in pairs(crunchNext)do if not crunching[p]then crunchNext[p]=nil end end
 for _,m in ipairs(folder:GetChildren())do
  local p=Players:GetPlayerByUserId(m:GetAttribute('CosmeticOwner')or 0)
  if not living(p)or(m:GetAttribute('CosmeticEnd')and now>=m:GetAttribute('CosmeticEnd'))then m:Destroy()
  elseif m:GetAttribute('CosmeticRole')~='Fly'then local head=p.Character:FindFirstChild('Head');if head then m:PivotTo(head.CFrame*m:GetAttribute('CosmeticOffset'))end end
 end
 for p,s in pairs(perfumed)do
  if not living(p)then M.ClearPlayer(p)
  elseif now>=s.begins then
   for _,q in ipairs(Players:GetPlayers())do
    if M.CanWhistle(p,q,now)then
     nextWhistle[q]=now+math.random(7,11);q:SetAttribute('WhistleUntil',now+1.5);Audio.Play('PerfumeWhistle',q.Character.Head)
    end
   end
  end
 end
end)
task.spawn(function()
 roundState=RS:WaitForChild('RecoveryRound',math.huge)
 roundState:GetAttributeChangedSignal('Round'):Connect(M.ClearLevel)
 roundState:GetAttributeChangedSignal('Phase'):Connect(function()
  local phase=roundState:GetAttribute('Phase');if phase=='Won'or phase=='Failed'or phase=='Deploying'then M.ClearLevel()end
 end)
end)
Players.PlayerRemoving:Connect(M.ClearPlayer)
return M


