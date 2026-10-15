-- Gear shop: the team bank (every dollar sold this run) buys gear from the van's right-wall crates.
-- Owns: bank, gear inventory across level rebuilds and run saves, gear effects (GearUseApi).
-- Monster effects go through CreatureRoamServer's CreatureWeaponApi; item spawning through CursedItemsServer's SpawnGearItem.
local Players=game:GetService('Players');local RS=game:GetService('ReplicatedStorage');local SS=game:GetService('ServerStorage')
local Debris=game:GetService('Debris');local TweenService=game:GetService('TweenService')
local Targeting=require(script:WaitForChild('MonsterShotTargeting'))
local Audio=require(game:GetService('ServerScriptService'):WaitForChild('GameplayAudioServer'))

local SHOP={ -- crate order: nearest the spawn first (lowest van-local Z)
 {id='Grenade',name='Grenade',price=150,charges=1},
 {id='ProxMine',name='Proximity Grenade',price=200,charges=1},
 {id='HypnoGun',name='Hypno Gun',price=500,charges=3},
 {id='SlayerGun',name='Monster Slayer',price=1250,charges=3},
 {id='SkitterTrap',name='Skitter Trap',price=150,charges=1},
 {id='MedKit',name='MedKit',price=150,charges=1},
 {id='BigMedKit',name='Big MedKit',price=250,charges=1},
}
local BY_ID={};for _,e in SHOP do BY_ID[e.id]=e end
local BLAST_RADIUS=16      -- grenade / proximity blast reach (studs)
local FLEE_SECONDS=12      -- how long a blasted monster ignores players while fleeing
local HYPNO_SECONDS=35
local MINE_TRIGGER=3       -- horizontal studs: a monster must step onto the mine
local GUN_RANGE=160
local ORB_VALUE=75        -- sell value of the orb a slain monster drops
local MONSTER_HP=100       -- gear damage a monster can take
local GRENADE_DAMAGE=34    -- 3 grenades kill
local MINE_DAMAGE=50       -- 2 proximity grenades kill
local LOCKER_OFFSET=CFrame.new(9,.3,-7) -- van-local storage tray: right of spawn, left of the shop crates
local LOCKER_SIZE=Vector3.new(2.6,.12,5)
local SHOWCASE_SCALE=1.25 -- shop display models (the grey crates are hidden)
local BANK_SIGN_OFFSET=Vector3.new(-2.6,1.9,0) -- van-local: out from the shop wall toward the aisle, just above the items
local SLAYER_SHOT_SOUND=111381796854533 -- 'Collateral Ruin Hit 1': heavy impact, distinct from the hypno gun's zap

local bank=0;local lastSold=0;local lastRound=0;local loadedContext=false
local records={} -- live gear model -> {id, charges}
local pending={} -- gear waiting to be (re)spawned in the van locker: {id, charges}
local state

local event=RS:FindFirstChild('GearShopEvent')or Instance.new('RemoteEvent');event.Name='GearShopEvent';event.Parent=RS
local function toast(p,text)if p and p.Parent then event:FireClient(p,'toast',text)end end
local function toastAll(text)event:FireAllClients('toast',text)end
local function publishBank()if state then state:SetAttribute('Bank',bank)end end

local function van()return workspace:FindFirstChild('AnomalyRecoveryVan',true)end
local function vanCF()local v=van();return v and v:GetPivot()end
local function missionMap()return workspace:FindFirstChild('Mansion')end
local function phase()return state and state:GetAttribute('Phase')end
local function alive(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
 return p:GetAttribute('MissionActive')==true and not p:GetAttribute('RoundDead')and h and h.Health>0 and r,r
end

-- Run save: RecoveryRoundServer's captureRunSave asks for this.
local api=SS:FindFirstChild('GearShopApi')or Instance.new('BindableFunction');api.Name='GearShopApi';api.Parent=SS
api.OnInvoke=function(action,...)
 if action=='snapshot'then
  local gear={}
  for m,rec in records do if m.Parent and #gear<24 then table.insert(gear,{id=rec.id,charges=m:GetAttribute('Charges')or rec.charges})end end
  for _,rec in pending do if #gear<24 then table.insert(gear,{id=rec.id,charges=rec.charges})end end
  return {bank=bank,gear=gear}
 elseif action=='addBank'then
  local amount=...
  bank+=amount;publishBank();toastAll(('The owner added $%d to the team bank. Team bank: $%d'):format(amount,bank))
  return true,('Team bank +$%d (now $%d).'):format(amount,bank)
 end
end

local function track(m,id,charges)
 records[m]={id=id,charges=charges}
 m.AncestryChanged:Connect(function()
  if m.Parent then return end
  local rec=records[m];records[m]=nil
  -- Not consumed (map rebuilt / cleared): bring it back in the van locker next level.
  if rec and not rec.consumed then table.insert(pending,{id=rec.id,charges=m:GetAttribute('Charges')or rec.charges})end
 end)
end
local function spawnGear(id,cf,charges)
 local spawner=SS:FindFirstChild('SpawnGearItem');if not spawner then return nil end
 local ok,m=pcall(function()return spawner:Invoke(id,cf,charges)end)
 if ok and m then track(m,id,charges);return m end
end
local function consume(p,m)
 local rec=records[m];if rec then rec.consumed=true end
 local items=SS:FindFirstChild('CursedItemApi');if items and p then pcall(function()items:Invoke('release',p)end)end
 if m.Parent then m:Destroy()end
end

-- Van locker (storage tray) and shop crates are dressed whenever a new van appears.
local function lockerCF()local cf=vanCF();return cf and cf*LOCKER_OFFSET end
local function dressVan(v)
 if v:FindFirstChild('GearLocker')then return end
 local cf=v:GetPivot()
 local tray=Instance.new('Part');tray.Name='GearLocker';tray.Anchored=true;tray.CanCollide=true;tray.Size=LOCKER_SIZE
 tray.CFrame=cf*LOCKER_OFFSET;tray.Color=Color3.fromRGB(38,44,42);tray.Material=Enum.Material.DiamondPlate;tray.Parent=v
 for _,side in {-1,1}do
  local rim=Instance.new('Part');rim.Name='GearLockerRim';rim.Anchored=true;rim.CanCollide=false;rim.Size=Vector3.new(.12,.3,LOCKER_SIZE.Z)
  rim.CFrame=tray.CFrame*CFrame.new(side*LOCKER_SIZE.X/2,.15,0);rim.Color=Color3.fromRGB(70,80,74);rim.Material=Enum.Material.Metal;rim.Parent=v
 end
 local sign=Instance.new('BillboardGui');sign.Name='GearLockerSign';sign.Size=UDim2.fromOffset(160,26);sign.StudsOffset=Vector3.new(0,1.6,0);sign.MaxDistance=30;sign.LightInfluence=0;sign.Parent=tray
 local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=Color3.fromRGB(244,236,210);t.Text='GEAR LOCKER';t.Parent=sign
 local st=Instance.new('UIStroke');st.Thickness=1.5;st.Transparency=.3;st.Parent=t
 -- Shop: the 4 crates on the spawn's right wall (+X), nearest first.
 local crates={}
 for _,d in v:GetDescendants()do if d:IsA('BasePart')and d.Name=='EquipmentCrate'and cf:PointToObjectSpace(d.Position).X>0 then table.insert(crates,d)end end
 table.sort(crates,function(a,b)return cf:PointToObjectSpace(a.Position).Z<cf:PointToObjectSpace(b.Position).Z end)
 -- A fifth interaction on its own shelf below the four existing gear displays.
 local upperShelf
 for _,d in v:GetDescendants()do if d:IsA('BasePart')and d.Name=='StorageShelf'and cf:PointToObjectSpace(d.Position).X>0 then upperShelf=d end end
 if upperShelf and #crates>=4 then
  local q=cf:PointToObjectSpace(upperShelf.Position)
  local shelf=Instance.new('Part');shelf.Name='SkitterTrapShelf';shelf.Size=Vector3.new(upperShelf.Size.X,.12,4.8);shelf.CFrame=cf*CFrame.new(q.X-.8,q.Y-2.14,q.Z-.5)
  shelf.Anchored=true;shelf.CanCollide=false;shelf.CanQuery=false;shelf.Transparency=1;shelf.Color=upperShelf.Color;shelf.Material=upperShelf.Material;shelf.Parent=v
  local crate=Instance.new('Part');crate.Name='SkitterTrapShopCrate';crate.Size=Vector3.new(2,.8,3);crate.CFrame=shelf.CFrame*CFrame.new(0,.48,0);crate.Anchored=true;crate.Transparency=1;crate.CanCollide=false;crate.CanTouch=false;crate.Parent=v
  table.insert(crates,crate)
 end
 -- Medical displays share the trap's bench height and flank it on the cushions.
 if upperShelf and #crates==5 then
  local q=cf:PointToObjectSpace(upperShelf.Position)
  for _,dz in {-4.5,3.5}do
   local crate=Instance.new('Part');crate.Name='MedicalGearShopCrate';crate.Size=Vector3.new(2,.8,3)
   crate.CFrame=cf*CFrame.new(q.X-.8,q.Y-2.14+.48,q.Z+dz)
   crate.Anchored=true;crate.Transparency=1;crate.CanCollide=false;crate.CanTouch=false;crate.Parent=v;crates[#crates+1]=crate
  end
 end
 for i,crate in crates do
  local entry=SHOP[i];if not entry then break end
  if entry.id=='SkitterTrap' and game.ServerScriptService.CreatureRoamServer:GetAttribute('SkitterEnabled')~=true then crate:Destroy();continue end -- no Skitter, no trap for sale
  if entry.id=='MedKit' or entry.id=='BigMedKit' then crate:Destroy();continue end -- med kits removed (user, 2026-10-06)
  crate:SetAttribute('GearShopId',entry.id);crate.Transparency=1;crate.CanCollide=false
  local template=SS.CursedItemKit:FindFirstChild(entry.id)
  if template then
   local show=template:Clone();show.Name='GearShowcase_'..entry.id
   for k in show:GetAttributes()do show:SetAttribute(k,nil)end
   for _,d in show:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false end end
   show:ScaleTo(entry.id=='MedKit'and .85 or entry.id=='BigMedKit'and .7 or(entry.id=='SkitterTrap'and .9 or SHOWCASE_SCALE))
   -- Sits on the shelf where the crate was.
   local base=crate.CFrame*CFrame.new(0,-crate.Size.Y/2,0)
   show:PivotTo(CFrame.new(base.Position+Vector3.new(0,show.PrimaryPart.Size.Y/2,0))*cf.Rotation) -- side-on: the aisle sees each item's profile
   if entry.id=='MedKit'or entry.id=='BigMedKit'then
    show:PivotTo(CFrame.new(base.Position)*cf.Rotation*CFrame.Angles(0,math.pi/2,0))
    local box,size=show:GetBoundingBox();show:PivotTo(show:GetPivot()+Vector3.new(0,base.Position.Y+.025-(box.Position.Y-size.Y/2),0))
   end
   show.Parent=v
  end
  local prompt=Instance.new('ProximityPrompt');prompt.Name='GearShopPrompt';prompt.ObjectText=entry.name;prompt.ActionText='Buy $'..entry.price
  prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=.35;prompt.MaxActivationDistance=7
  prompt.RequiresLineOfSight=false;prompt.ClickablePrompt=true;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton;prompt.Parent=crate
  local label=Instance.new('BillboardGui');label.Name='GearShopLabel';label.Size=UDim2.fromOffset(150,40);label.StudsOffset=Vector3.new(0,(entry.id=='SkitterTrap'or entry.id=='MedKit'or entry.id=='BigMedKit')and .65 or 1.5,0);if entry.id=='MedKit'or entry.id=='BigMedKit'then label.StudsOffset=Vector3.zero;label.StudsOffsetWorldSpace=cf:VectorToWorldSpace(Vector3.new(-1.25,0,0))+Vector3.new(0,.75,0)end;label.MaxDistance=24;label.LightInfluence=0;label.Parent=crate
  local n=Instance.new('TextLabel');n.Size=UDim2.fromScale(1,.55);n.BackgroundTransparency=1;n.Font=Enum.Font.FredokaOne;n.TextScaled=true;n.TextColor3=Color3.fromRGB(244,236,210);n.Text=entry.name:upper();n.Parent=label
  local pr=n:Clone();pr.Position=UDim2.fromScale(0,.55);pr.Size=UDim2.fromScale(1,.45);pr.TextColor3=Color3.fromRGB(167,202,127);pr.Text='$'..entry.price..(entry.charges>1 and(' - '..entry.charges..' shots')or'');pr.Parent=label
  for _,x in {n,pr}do local s2=Instance.new('UIStroke');s2.Thickness=1.5;s2.Transparency=.3;s2.Parent=x end
  prompt.Triggered:Connect(function(p)
   local ok,r=alive(p);if not ok then return end
   if (r.Position-crate.Position).Magnitude>9 then return end
   if bank<entry.price then toast(p,('Not enough in the team bank ($%d / $%d).'):format(bank,entry.price));return end
   bank-=entry.price;publishBank()
   local out=crate.CFrame*CFrame.new(-1.6,-.2,0) -- pops out on the aisle side of the crate
   if not spawnGear(entry.id,CFrame.new(out.Position),entry.charges)then bank+=entry.price;publishBank();toast(p,'The shop is restocking. Try again in a moment.');return end
   toastAll(('%s bought a %s. Team bank: $%d'):format(p.DisplayName,entry.name,bank))
  end)
 end
 -- Line the display items up along the shelf: evenly spaced by their real lengths, resting on the top,
 -- none past either end. Each crate (buy prompt, label, spawn point) moves with its item.
 local shelf
 for _,d in v:GetDescendants()do if d:IsA('BasePart')and d.Name=='StorageShelf'and cf:PointToObjectSpace(d.Position).X>0 then shelf=d end end
 if shelf then
  local q=cf:PointToObjectSpace(shelf.Position);local length=shelf.Size.Z;local top=q.Y+shelf.Size.Y/2
  local rows={}
  for i,crate in crates do
   local show=SHOP[i] and v:FindFirstChild('GearShowcase_'..SHOP[i].id)
   if show and i<=4 then
    local box,size=show:GetBoundingBox();local extent=cf:VectorToObjectSpace(box:VectorToWorldSpace(size))
    table.insert(rows,{crate=crate,show=show,center=cf:PointToObjectSpace(box.Position),z=math.abs(extent.Z),y=math.abs(extent.Y)})
   end
  end
  local used=0;for _,row in rows do used+=row.z end
  local gap=math.max(0,(length-used)/(#rows+1));local z=q.Z-length/2+gap
  for _,row in rows do
   local target=Vector3.new(q.X,top+row.y/2,z+row.z/2)
   row.show:PivotTo(row.show:GetPivot()+cf:VectorToWorldSpace(target-row.center))
   local c=cf:PointToObjectSpace(row.crate.Position)
   row.crate.CFrame=row.crate.CFrame+cf:VectorToWorldSpace(Vector3.new(0,0,target.Z-c.Z))
   z+=row.z+gap
  end
 end
 -- Bank display above the shop.
 if crates[1]then
  local mid=crates[math.min(#crates,2)]
  local bb=Instance.new('BillboardGui');bb.Name='GearBankSign';bb.Size=UDim2.fromOffset(190,28);bb.StudsOffsetWorldSpace=cf:VectorToWorldSpace(BANK_SIGN_OFFSET);bb.MaxDistance=30;bb.LightInfluence=0;bb.Parent=mid
  local t2=Instance.new('TextLabel');t2.Size=UDim2.fromScale(1,1);t2.BackgroundTransparency=1;t2.Font=Enum.Font.FredokaOne;t2.TextScaled=true;t2.TextColor3=Color3.fromRGB(255,214,110);t2.Parent=bb
  local s3=Instance.new('UIStroke');s3.Thickness=1.5;s3.Transparency=.3;s3.Parent=t2
  local function show()t2.Text='TEAM BANK  $'..bank end;show()
  task.spawn(function()while bb.Parent do show();task.wait(.5)end end)
 end
end

-- Pending gear (level rebuild / loaded save) lands in the locker once the new level is running.
local function flushPending()
 if #pending==0 then return end
 local cf=lockerCF();local spawner=SS:FindFirstChild('SpawnGearItem');local map=missionMap()
 if not cf or not spawner or not map or not map:GetAttribute('RuntimeReady')or phase()~='Searching'then return end
 local list=pending;pending={}
 for i,rec in list do
  if BY_ID[rec.id]then
   local slot=cf*CFrame.new(((i-1)%2-.5)*1.1,.6,-1.8+math.floor((i-1)/2)*1.2%4.8)
   if not spawnGear(rec.id,CFrame.new(slot.Position),rec.charges)then table.insert(pending,rec)end
  end
 end
end

-- Bank: every dollar sold this run. Sold resets to 0 each level, so only increases count.
local function bindState(obj)
 state=obj;lastSold=obj:GetAttribute('Sold')or 0;publishBank()
 obj:GetAttributeChangedSignal('Sold'):Connect(function()
  local s=obj:GetAttribute('Sold')or 0
  if s>lastSold then bank+=s-lastSold;publishBank()end
  lastSold=s
 end)
 obj:GetAttributeChangedSignal('Round'):Connect(function()
  local r=obj:GetAttribute('Round')or 0
  if r<=0 then return end
  if not loadedContext then
   loadedContext=true
   local ok,RunSaves=pcall(require,game.ServerScriptService:WaitForChild('RunSavesService',5))
   local ctx=ok and RunSaves and RunSaves.GetMissionContext and RunSaves.GetMissionContext()
   if ctx and ctx.mode=='load'and type(ctx.slot)=='table'then
    bank=tonumber(ctx.slot.bank)or 0
    for _,g in ipairs(ctx.slot.gear or {})do if BY_ID[g.id]then table.insert(pending,{id=g.id,charges=math.clamp(tonumber(g.charges)or BY_ID[g.id].charges,1,BY_ID[g.id].charges)})end end
   end
  elseif r<lastRound then
   -- Team wipe restart: the run starts over, so do the bank and gear.
   bank=0;table.clear(pending);for m,rec in records do rec.consumed=true;if m.Parent then m:Destroy()end end
  end
  lastRound=r;lastSold=obj:GetAttribute('Sold')or 0;publishBank()
 end)
end
local existing=RS:FindFirstChild('RecoveryRound');if existing then bindState(existing)end
RS.ChildAdded:Connect(function(c)if c.Name=='RecoveryRound'then bindState(c)end end)

task.spawn(function()
 while true do
  task.wait(1)
  local v=van();if v then dressVan(v)end
  flushPending()
 end
end)

---------------------------------------------------------------- effects
local function monsters()local w=SS:FindFirstChild('CreatureWeaponApi');if not w then return {}end;local ok,list=pcall(function()return w:Invoke('list')end);return ok and list or {}end
local function weapon(action,model,a,b)local w=SS:FindFirstChild('CreatureWeaponApi');if not w then return false end;local ok,result=pcall(function()return w:Invoke(action,model,a,b)end);return ok and result==true end
local function monsterRoot(model)return model.PrimaryPart or model:FindFirstChild('HumanoidRootPart')or model:FindFirstChildWhichIsA('BasePart',true)end
local function playersCentroid()
 local sum,n=Vector3.zero,0
 for _,p in Players:GetPlayers()do local ok,r=alive(p);if ok then sum+=r.Position;n+=1 end end
 return n>0 and sum/n or nil
end
local function sound(id,parent,volume)
 local s=Instance.new('Sound');s.SoundId='rbxassetid://'..id;s.Volume=volume or 1;s.RollOffMaxDistance=140;s.Parent=parent;s:Play();Debris:AddItem(s,6)
end
local killMonster -- defined below (shared with the slayer)
-- Explosions are visual only (no pressure, no joint breaking): they never hurt players. Monsters take gear damage.
local function explode(pos,damage)
 local e=Instance.new('Explosion');e.Position=pos;e.BlastPressure=0;e.BlastRadius=BLAST_RADIUS;e.DestroyJointRadiusPercent=0;e.ExplosionType=Enum.ExplosionType.NoCraters;e.Parent=workspace
 local avoid=playersCentroid()
 for _,m in monsters()do local r=monsterRoot(m);if r and (r.Position-pos).Magnitude<=BLAST_RADIUS then
  local hp=(m:GetAttribute('GearHealth')or MONSTER_HP)-(damage or 0);m:SetAttribute('GearHealth',hp)
  if hp<=0 then killMonster(m,r.Position)else weapon('blast',m,avoid,FLEE_SECONDS)end
 end end
end
local function beam(from,to,color,width)
 width=width or .12
 local d=(to-from);if d.Magnitude<.01 then return end;local p=Instance.new('Part');p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Material=Enum.Material.Neon;p.Color=color
 p.Size=Vector3.new(width,width,d.Magnitude);p.CFrame=CFrame.lookAt(from+d/2,to);p.Parent=workspace
 TweenService:Create(p,TweenInfo.new(.3),{Transparency=1,Size=Vector3.new(.02,.02,d.Magnitude)}):Play();Debris:AddItem(p,.4)
end
local function aimOf(p,r)
 local aim=p:GetAttribute('GearAim');local head=p.Character and p.Character:FindFirstChild('Head')
 local origin=(head or r).Position
 if Targeting.ValidAim(aim,origin)then return aim.Position,aim.LookVector.Unit end
 return origin,r.CFrame.LookVector
end
local SLAYER_HIT_RADIUS,SLAYER_BEAM_WIDTH=5,.45 -- studs; the other guns use 2.5 and a .12 beam
local function shoot(p,r,m,color,hitRadius,beamWidth)
 local origin,dir=aimOf(p,r)
 local models=monsters()
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
 local ignore={m};local cam=workspace:FindFirstChild('Camera');if cam then table.insert(ignore,cam)end
 for _,q in Players:GetPlayers()do if q.Character then table.insert(ignore,q.Character)end end
 for _,model in ipairs(models)do table.insert(ignore,model)end
 params.FilterDescendantsInstances=ignore
 local head=p.Character and p.Character:FindFirstChild('Head')
 local anchor=(head or r).Position
 -- A camera may be near the character but on the other side of a wall.
 local offset=origin-anchor
 if offset.Magnitude>.01 and workspace:Raycast(anchor,offset,params)then origin=anchor end
 local hit=workspace:Raycast(origin,dir*GUN_RANGE,params)
 local range=hit and math.min(GUN_RANGE,(hit.Position-origin).Magnitude)or GUN_RANGE
 local muzzle=m.PrimaryPart and m.PrimaryPart.Position or anchor
 local function clear(from,to)
  local delta=to-from
  if delta.Magnitude<.01 then return true end
  local obstruction=workspace:Raycast(from,delta,params)
  return not obstruction
 end
 local target,at=Targeting.Select(models,origin,dir,range,hitRadius or 2.5,function(point)
  return clear(origin,point)and clear(anchor,point)and clear(muzzle,point)
 end)
 local to=at or(hit and hit.Position or origin+dir*GUN_RANGE)
 beam(muzzle,to,color,beamWidth)
 return target,to,muzzle
end
local function spendCharge(p,m,entry)
 local left=(m:GetAttribute('Charges')or entry.charges)-1;m:SetAttribute('Charges',left)
 if records[m]then records[m].charges=left end
 if left<=0 then toast(p,entry.name..' is out of shots.');consume(p,m)else toast(p,entry.name..': '..left..' shot'..(left==1 and''or's')..' left')end
end

local function armMine(pos)
 local template=SS.CursedItemKit:FindFirstChild('ProxMine');if not template then return end
 local mine=template:Clone();mine.Name='ArmedProxMine'
 for _,d in mine:GetDescendants()do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false end end
 for k in mine:GetAttributes()do mine:SetAttribute(k,nil)end
 mine:PivotTo(CFrame.new(pos+Vector3.new(0,mine.PrimaryPart.Size.Y/2,0)))
 mine.Parent=missionMap()or workspace
 local led=mine:FindFirstChild('ProxMine__Led')
 sound(9113438364,mine.PrimaryPart,.5)
 task.spawn(function()
  task.wait(1.5) -- arming time
  local blink=0
  while mine.Parent do
   blink+=1;if led then led.Transparency=blink%4<2 and 0 or .8 end
   for _,m in monsters()do local mr=monsterRoot(m)
    if mr then local d=mr.Position-pos
     if Vector3.new(d.X,0,d.Z).Magnitude<=MINE_TRIGGER and math.abs(d.Y)<9 then mine:Destroy();explode(pos,MINE_DAMAGE);return end
    end
   end
   task.wait(.15)
  end
 end)
end

local function armSkitterTrap(pos)
 local map=missionMap();local template=SS.CursedItemKit:FindFirstChild('SkitterTrap')
 if not map or not template or not template.PrimaryPart then return nil end
 local trap=template:Clone();trap.Name='ArmedSkitterTrap'
 for k in trap:GetAttributes()do trap:SetAttribute(k,nil)end
 local pivot=trap:GetPivot();local bottom=math.huge
 for _,part in trap:GetDescendants()do if part:IsA('BasePart')then
  if part.Transparency<.95 then bottom=math.min(bottom,pivot:PointToObjectSpace(part.Position).Y-part.Size.Y*.5)end
  part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
 end end
 if bottom==math.huge then bottom=0 end
 trap:PivotTo(CFrame.new(pos+Vector3.new(0,.035-bottom,0)));trap:SetAttribute('Armed',false);trap:SetAttribute('TargetKind','Skitter');trap:SetAttribute('TrapPosition',pos)
 trap.Parent=map
 sound(9113438364,trap.PrimaryPart,.5)
 task.spawn(function()
  task.wait(.8)
  if not trap.Parent or missionMap()~=map then return end
  trap:SetAttribute('Armed',true)
  while trap.Parent and missionMap()==map do
   if phase()=='Deploying'or phase()=='Won'or phase()=='Failed'then trap:Destroy();return end
   local api=SS:FindFirstChild('CreatureWeaponApi')
   if api then
    local ok,list=pcall(function()return api:Invoke('skitters')end)
    if ok and type(list)=='table'then for _,monster in list do
     if monster:GetAttribute('CreatureKind')=='Skitter'and monster:GetAttribute('Grounded')==true then
      -- Creature owner revalidates registered identity, floor support, proximity and LOS atomically.
      if weapon('skitterTrap',monster,pos)then
       trap:SetAttribute('Armed',false);sound(9113438364,trap.PrimaryPart,.65)
       toastAll('The Skitter Trap caught the Skitter!');trap:Destroy();return
      end
     end
    end end
   end
   task.wait(.1)
  end
  if trap.Parent then trap:Destroy()end
 end)
 return trap
end

killMonster=function(target,dropAt)
 if not weapon('kill',target)then return false end;toastAll('A monster was destroyed! It dropped a $'..ORB_VALUE..' orb.')
 -- Reward: a sellable orb drops where the monster died (snapped to the floor below).
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 local folder=workspace:FindFirstChild('RoamingCreatures');params.FilterDescendantsInstances=folder and {folder} or {}
 local floor=workspace:Raycast(dropAt+Vector3.new(0,2,0),Vector3.new(0,-30,0),params)
 local spawner=SS:FindFirstChild('SpawnGearItem')
 if spawner then pcall(function()spawner:Invoke('MonsterOrb',CFrame.new((floor and floor.Position or dropAt)+Vector3.new(0,.8,0)))end)end
end
local use=SS:FindFirstChild('GearUseApi')or Instance.new('BindableFunction');use.Name='GearUseApi';use.Parent=SS
use.OnInvoke=function(p,m)
 local ok,r=alive(p);if not ok or not m or not m.Parent then return end
 local id=m:GetAttribute('ItemId');local entry=BY_ID[id];if not entry then return end
 if id=='MedKit'or id=='BigMedKit'then
  if m:GetAttribute('HeldBy')~=p.UserId or m:GetAttribute('MedKitUsed')then return false end
  local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if not h or h.Health<=0 then return false end
  m:SetAttribute('MedKitUsed',true)
  local before=h.Health;h.Health=math.min(h.MaxHealth,h.Health+(id=='BigMedKit'and 100 or 50))
  consume(p,m);toast(p,('Healed %d health.'):format(math.floor(h.Health-before+.5)));return true
 elseif id=='Grenade'then
  local origin,dir=aimOf(p,r)
  local start=(m.PrimaryPart and m.PrimaryPart.Position)or origin
  consume(p,m)
  local ball=Instance.new('Part');ball.Shape=Enum.PartType.Ball;ball.Size=Vector3.one*.6;ball.Color=Color3.fromRGB(78,92,52);ball.Anchored=true;ball.CanCollide=false;ball.CanQuery=false;ball.Position=start;ball.Parent=workspace
  local vel=dir*48+Vector3.new(0,14,0);local pos=start
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;local ig={ball};for _,q in Players:GetPlayers()do if q.Character then table.insert(ig,q.Character)end end;params.FilterDescendantsInstances=ig
  local landed=false
  for _=1,120 do
   local dt=1/30;local nextPos=pos+vel*dt;vel+=Vector3.new(0,-workspace.Gravity*.6,0)*dt
   local hit=workspace:Raycast(pos,nextPos-pos,params)
   if hit then pos=hit.Position+hit.Normal*.3;ball.Position=pos;landed=true;break end
   pos=nextPos;ball.Position=pos;task.wait(dt)
  end
  sound(9113438364,ball,.6)
  task.wait(landed and 1.2 or 0)
  ball:Destroy();explode(pos,GRENADE_DAMAGE)
 elseif id=='ProxMine'then
  local look=Vector3.new(r.CFrame.LookVector.X,0,r.CFrame.LookVector.Z);look=look.Magnitude>.01 and look.Unit or Vector3.new(0,0,-1)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;local ig={m};for _,q in Players:GetPlayers()do if q.Character then table.insert(ig,q.Character)end end;params.FilterDescendantsInstances=ig
  local hit=workspace:Raycast(r.Position+look*2.5+Vector3.new(0,1,0),Vector3.new(0,-12,0),params)
  if not hit then toast(p,'Find solid floor to set the proximity grenade.');return end
  consume(p,m);armMine(hit.Position);toast(p,'Proximity grenade armed. It goes off when a monster steps on it.')
 elseif id=='SkitterTrap'then
  if m:GetAttribute('TrapDeploying')then return end
  if m:GetAttribute('HeldBy')~=p.UserId then return end
  m:SetAttribute('TrapDeploying',true)
  local look=Vector3.new(r.CFrame.LookVector.X,0,r.CFrame.LookVector.Z);look=look.Magnitude>.01 and look.Unit or Vector3.new(0,0,-1)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true;local ig={m}
  local creatures=workspace:FindFirstChild('RoamingCreatures');if creatures then ig[#ig+1]=creatures end
  for _,q in Players:GetPlayers()do if q.Character then ig[#ig+1]=q.Character end end;params.FilterDescendantsInstances=ig
  local hit=workspace:Raycast(r.Position+look*3.5+Vector3.new(0,1,0),Vector3.new(0,-8,0),params)
  local map=missionMap();local room
  if hit and map and hit.Normal.Y>.9 then
   for _,v in game.HttpService:JSONDecode(map.GeneratedGraph.Value).rooms do if hit.Position.X>v.x1+1 and hit.Position.X<v.x2-1 and hit.Position.Z>v.z1+1 and hit.Position.Z<v.z2-1 and math.abs(hit.Position.Y-v.level*16)<.25 then room=v;break end end
  end
  if room then
   local head=p.Character:FindFirstChild('Head')or r
   if workspace:Raycast(head.Position,hit.Position+Vector3.new(0,.15,0)-head.Position,params)then room=nil end
   local template=SS.CursedItemKit:FindFirstChild('SkitterTrap')
   if not template then room=nil else
    local _,size=template:GetBoundingBox();local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude;overlap.FilterDescendantsInstances={m};overlap.RespectCanCollide=false
    for _,part in workspace:GetPartBoundsInBox(CFrame.new(hit.Position+Vector3.new(0,size.Y*.5+.08,0)),Vector3.new(size.X+.1,size.Y,size.Z+.1),overlap)do
     if part.CanCollide or part:IsDescendantOf(p.Character)then room=nil;break end
    end
   end
  end
  local trap=room and armSkitterTrap(hit.Position)
  if not trap then m:SetAttribute('TrapDeploying',nil);toast(p,'Find a clear floor inside the map to set the Skitter Trap.');return end
  consume(p,m);toast(p,'Skitter Trap armed. Only a grounded Skitter can trigger it.')
 elseif id=='HypnoGun'then
  -- Misses are free, so shots are rate-limited per player.
  local nowT=os.clock();if nowT<(p:GetAttribute('HypnoReadyAt')or 0)then return end;p:SetAttribute('HypnoReadyAt',nowT+1.2)
  -- Wide, glowing spiral shot with the same generous aim assist as the Monster Slayer.
  local target,_,muzzle=shoot(p,r,m,Color3.fromRGB(255,60,190),5,.4)
  -- Shooter gets one immediate 2D cue; nearby players get the positional muzzle cue.
  Audio.ToPlayer(p,'HypnoShotLocal')
  for _,listener in Players:GetPlayers()do if listener~=p then RS.GameplaySoundEvent:FireClient(listener,'HypnoShot',muzzle)end end
  if target and weapon('hypnotize',target,HYPNO_SECONDS)then
   target:SetAttribute('FleeUntil',os.clock()+4) -- staggers away from whoever is near first, then wanders dazed
   local mr=monsterRoot(target)
   if mr then
    Audio.Play('HypnoHit',mr)
    local fx=Instance.new('Folder');fx.Name='HypnoFX';fx.Parent=mr
    -- Swirling sparkles + a pulsing pink glow everyone can see.
    local att=Instance.new('Attachment');att.Name='HypnoSwirl';att.Position=Vector3.new(0,3,0);att.Parent=mr
    local pe=Instance.new('ParticleEmitter');pe.Texture='rbxasset://textures/particles/sparkles_main.dds';pe.Color=ColorSequence.new(Color3.fromRGB(255,60,190),Color3.fromRGB(120,255,230))
    pe.Rate=60;pe.Lifetime=NumberRange.new(.8,1.4);pe.Speed=NumberRange.new(2,4);pe.RotSpeed=NumberRange.new(180,360);pe.SpreadAngle=Vector2.new(180,180);pe.Size=NumberSequence.new(1,0);pe.LightEmission=1;pe.Parent=att
    local glow=Instance.new('PointLight');glow.Color=Color3.fromRGB(255,80,200);glow.Brightness=3;glow.Range=16;glow.Parent=att
    -- Spinning hypno rings over its head.
    local rings={}
    for i=1,2 do
     local ring=Instance.new('Part');ring.Name='HypnoRing';ring.Shape=Enum.PartType.Cylinder;ring.Size=Vector3.new(.12,3.4-i*.9,3.4-i*.9);ring.Material=Enum.Material.Neon
     ring.Color=i==1 and Color3.fromRGB(255,60,190)or Color3.fromRGB(120,255,230);ring.Transparency=.35;ring.CanCollide=false;ring.CanQuery=false;ring.CanTouch=false;ring.Massless=true;ring.Anchored=true;ring:SetAttribute('GearIgnoreHit',true);ring.Parent=fx
     table.insert(rings,ring)
    end
    -- Floating countdown everyone can read.
    local bb=Instance.new('BillboardGui');bb.Name='HypnoTag';bb.Size=UDim2.fromOffset(180,44);bb.StudsOffsetWorldSpace=Vector3.new(0,6.5,0);bb.AlwaysOnTop=true;bb.MaxDistance=120;bb.Parent=mr
    local tl=Instance.new('TextLabel');tl.Size=UDim2.fromScale(1,1);tl.BackgroundTransparency=1;tl.Font=Enum.Font.FredokaOne;tl.TextScaled=true;tl.TextColor3=Color3.fromRGB(255,120,220);tl.TextStrokeTransparency=0;tl.Parent=bb
    local untilT=os.clock()+HYPNO_SECONDS
    task.spawn(function()
     local spin=0
     while mr.Parent and target.Parent and os.clock()<untilT do
      spin+=.12
      local top=mr.CFrame*CFrame.new(0,4.6,0)
      for i,ring in rings do ring.CFrame=CFrame.new(top.Position+Vector3.new(0,(i-1)*.5,0))*CFrame.Angles(0,spin*(i==1 and 1 or -1.6),math.rad(90)) end
      tl.Text='HYPNOTIZED  '..math.ceil(untilT-os.clock())
      glow.Brightness=2.2+math.sin(spin*3)
      task.wait(.03)
     end
     fx:Destroy();att:Destroy();bb:Destroy()
    end)
   end
   toast(p,'Hypnotized! It wanders off dazed for '..HYPNO_SECONDS..' seconds.')
   spendCharge(p,m,entry)
  else
   -- A miss keeps the shot: the gun only spends a charge when it actually hypnotizes something.
   toast(p,'Missed! No shot used. Aim at a monster.')
  end
 elseif id=='SlayerGun'then
  sound(SLAYER_SHOT_SOUND,r,.6)
  local target,at=shoot(p,r,m,Color3.fromRGB(255,40,30),SLAYER_HIT_RADIUS,SLAYER_BEAM_WIDTH)
  if target then
   local e=Instance.new('Explosion');e.Position=at;e.BlastPressure=0;e.BlastRadius=6;e.DestroyJointRadiusPercent=0;e.ExplosionType=Enum.ExplosionType.NoCraters;e.Parent=workspace
   local mr=monsterRoot(target);killMonster(target,mr and mr.Position or at)
  end
  spendCharge(p,m,entry)
 end
end


