-- Puzzle side-objectives, item half (2026-10-27, WorldA; World_shared.md: WorldB adds its LullabyGramophone /
-- SlothToyChest `sections.X={...}` at the marker below). Required once by CursedBatchEffects (the item-effects owner).
-- MapGen.Furnisher places the props (CatShelf_1, Gramophone_1, ToyChest_1 + NappingSloth_1; attribute PuzzleSet).
-- Restock prunes props whose level gate is not met and spawns the loose pieces with FIXED ids and values; the tick
-- docks a carried piece that comes within reach of its prop and pays out. Payoffs are fixed, never random.
-- Ignoring a puzzle costs nothing: its pieces are ordinary cheap loot and no route depends on a prop.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local HttpService=game:GetService('HttpService')
local SS=game:GetService('ServerStorage')
local M={}
local TICK=.2
local DOCK_FLAT,DOCK_UP=4.5,7 -- a carried piece docks within this many studs of its prop's pivot (flat / height)
M.Gate={CatShelf=1,LullabyGramophone=math.huge,SlothToyChest=math.huge} -- first level each puzzle appears on. Gramophone (2) and toy chest (3) are OFF until their tests pass (lead 2026-10-27, pre-publish)
local ctx -- {map, give, say, noise, Audio, script} from CursedItemsServer
local detach,setParts
local level=1
local ticks=0 -- Heartbeat ticks (PuzzleTestApi state)
local sections={} -- [PuzzleSet] = {restock(), tick(clock), clue(), pickup(p,m), clear()}
local function clearSections() for _,s in pairs(sections) do if s.clear then s.clear() end end end
local function valueScale() return 1+.12*(level-1) end -- LootBudget.Plan's valueScale
local function mission(p) return p and p.Parent==Players and p:GetAttribute('MissionActive')==true end
local function tellAll(text) for _,p in ipairs(Players:GetPlayers()) do if mission(p) then ctx.say(p,text) end end end
-- Funny beats: a short grin (VoiceMouthClient GrinUntil) and a speech bubble over a prop (the Telephone's bubble).
local function grin(p,seconds) if p and p.Parent then p:SetAttribute('GrinUntil',math.max(p:GetAttribute('GrinUntil') or 0,workspace:GetServerTimeNow()+seconds)) end end
local function speech(pos,text) if ctx.speech then ctx.speech(pos,text) end end
local function sparkle(part,count)
 if not part then return end
 local fx=Instance.new('ParticleEmitter');fx.Texture='rbxasset://textures/particles/sparkles_main.dds';fx.Color=ColorSequence.new(Color3.fromRGB(255,214,120))
 fx.LightEmission=.6;fx.Size=NumberSequence.new(.5,.1);fx.Lifetime=NumberRange.new(.6,1.1);fx.Speed=NumberRange.new(4,8);fx.SpreadAngle=Vector2.new(80,80);fx.Rate=0;fx.Parent=part
 fx:Emit(count or 30);game:GetService('Debris'):AddItem(fx,2)
end
local function holder(m)
 local p=Players:GetPlayerByUserId(m:GetAttribute('HeldBy') or 0)
 local c=p and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if mission(p) and h and h.Health>0 and not m:GetAttribute('CargoStored') and not m:GetAttribute('Selling') then return p end
 return nil
end
local function near(m,prop)
 if not m.PrimaryPart or not prop or not prop.Parent then return false end
 local d=m.PrimaryPart.Position-prop:GetPivot().Position
 return Vector3.new(d.X,0,d.Z).Magnitude<DOCK_FLAT and math.abs(d.Y)<DOCK_UP
end
-- Take a carried piece out of its holder's hands and stand it, anchored and ungrabbable, with its bottom on `top`.
local function seat(p,m,top,rotation)
 detach(p,m,false,true);setParts(m,true,false)
 m:SetAttribute('Kind','puzzlePiece') -- not 'pickup': InteractServer will not start a grab on it, FieldMap stops showing it
 local cf,size=m:GetBoundingBox();local offset=m:GetPivot().Position-cf.Position
 m:PivotTo(rotation+(top+Vector3.new(0,size.Y/2,0)+offset))
end
-- Back to ordinary floor loot at `cf`, with an optional hop.
local function unseat(m,cf,pop)
 m:SetAttribute('Kind','pickup');m:PivotTo(cf);setParts(m,false,true)
 if m.PrimaryPart and pop then m.PrimaryPart.AssemblyLinearVelocity=pop end
end
local function prop(name) local m=ctx.map.Interactive:FindFirstChild(name);return m and m.PrimaryPart and m or nil end
-- Level gate not met (or no room for the pieces): the prop and its collider leave the map. Kept in ServerStorage
-- until the next restock so Studio tests can bring them back (PuzzleTestApi 'restock').
local function prunedFolder()
 local f=SS:FindFirstChild('PuzzlePruned');if not f then f=Instance.new('Folder');f.Name='PuzzlePruned';f.Parent=SS end;return f
end
local function prune(set)
 for _,folder in ipairs({ctx.map.Interactive,ctx.map.Collision}) do
  for _,x in ipairs(folder:GetChildren()) do if x:GetAttribute('PuzzleSet')==set then x:SetAttribute('PuzzleFrom',folder.Name);x.Parent=prunedFolder() end end
 end
end
-- Open rooms for loose pieces as {room, base, dist}, nearest first, lo..hi studs from `from` (other floor counts +40).
-- Never the start room, a hall, a stair, the foyer, `skipRoom` or a locked room.
local function roomsFrom(from,skipRoom,lo,hi)
 local graph=HttpService:JSONDecode(ctx.map.GeneratedGraph.Value);local locked={}
 for _,e in ipairs(graph.edges or {}) do if e.locked then locked[e.locked]=true end end
 local out={}
 for _,r in ipairs(graph.rooms) do
  if r.x1 and r.name~=skipRoom and r.name~=graph.start and not locked[r.name] and r.type~='Hall' and r.type~='Stair' and r.type~='Foyer' then
   local base=Vector3.new((r.x1+r.x2)/2,(r.level or 0)*16,(r.z1+r.z2)/2)
   local d=Vector3.new(base.X-from.X,0,base.Z-from.Z).Magnitude+math.abs(base.Y-from.Y)/16*40
   if d>=lo and d<=hi then out[#out+1]={room=r.name,base=base,dist=d} end
  end
 end
 table.sort(out,function(a,b) return a.dist<b.dist end)
 return out
end
local function spawnPiece(id,spot,value)
 local m=ctx.give(id,spot.base,value,'PuzzlePiece') -- CloseUpChoices giveItem: floor spot near base, register, Value
 if m then m:SetAttribute('Room',spot.room);m:SetAttribute('PuzzlePiece',true) end
 return m
end

-- CatShelf -------------------------------------------------------------------------------------------------
local CAT_VALUE,GOLD_VALUE,GOLD_VALUE_L1=8,30,18 -- per cat: loose (x valueScale), gilded L2+ (x valueScale), gilded L1
local CAT_FROM,CAT_TO=12,90 -- studs from the shelf to the cats' room centres
local GOLD=Color3.fromRGB(240,190,70)
local cat={shelf=nil,pieces={},home=0}
local function gild()
 local shelf=cat.shelf;if not shelf or not shelf.Parent then return end
 shelf:SetAttribute('Gilded',true)
 ctx.Audio.Play('StingChoir',shelf);ctx.noise(shelf:GetPivot().Position,30,'cat shelf chime',shelf)
 local eyes=shelf:FindFirstChild('CatShelf_neon');if eyes then eyes.Color=GOLD end
 local value=level==1 and GOLD_VALUE_L1 or math.floor(GOLD_VALUE*valueScale())
 local pivot=shelf:GetPivot()
 for i,m in ipairs(cat.pieces) do if m.Parent and m:GetAttribute('CatHome') then
  for _,part in ipairs(m:GetDescendants()) do
   if part:IsA('BasePart') and part.Transparency<1 then part.Color=GOLD;part.Material=Enum.Material.Metal;part.Reflectance=.15 end
  end
  local glow=Instance.new('Highlight');glow.Name='GildedGlow';glow.FillColor=GOLD;glow.FillTransparency=.55
  glow.OutlineColor=Color3.fromRGB(255,225,140);glow.DepthMode=Enum.HighlightDepthMode.Occluded;glow.Parent=m
  m:SetAttribute('Gilded',true);m:SetAttribute('DisplayName','Golden porcelain cat')
  m:SetAttribute('Value',value);m:SetAttribute('LootValue',value)
  local seatNo=m:GetAttribute('CatHome')
  task.delay(1.2+seatNo*.25,function()
   if not m.Parent or m:GetAttribute('Kind')~='puzzlePiece' then return end
   m:SetAttribute('CatHome',nil)
   unseat(m,pivot*CFrame.new((seatNo-2)*1.3,1.2,-2.2),pivot:VectorToWorldSpace(Vector3.new(0,10,-5))) -- front is -Z
   ctx.Audio.Play('ItemImpact',m)
  end)
 end end
 tellAll('The cats are home - and golden! Each one is worth $'..value..' now.')
 -- funny beat: a gold sparkle burst off the shelf, the cats purr, and everyone close by grins
 sparkle(shelf:FindFirstChild('CatShelf_neon') or shelf.PrimaryPart,40);speech(pivot.Position+Vector3.new(0,5,0),'PURRRRR!')
 for _,q in ipairs(Players:GetPlayers()) do
  local r=mission(q) and q.Character and q.Character:FindFirstChild('HumanoidRootPart')
  if r and (r.Position-pivot.Position).Magnitude<40 then grin(q,3) end
 end
end
local function catHome(p,m)
 local shelf=cat.shelf;cat.home+=1;local i=cat.home
 local cushion=shelf:FindFirstChild('Cushion'..i)
 local top=cushion and cushion.Position+Vector3.new(0,cushion.Size.Y/2-.05,0) or shelf:GetPivot()*Vector3.new((i-2)*1.45,1.8,0)
 seat(p,m,top,shelf:GetPivot().Rotation);m:SetAttribute('CatHome',i)
 shelf:SetAttribute('CatsHome',cat.home);ctx.Audio.Play('ClothHandle',m)
 ctx.say(p,'Porcelain cat home: '..cat.home..'/3')
 speech(top+Vector3.new(0,2.2,0),cat.home>=3 and 'MRRRP!!' or 'Mrrp!');grin(p,2) -- funny beat: the cat chirps, you grin
 if cat.home>=3 then task.delay(.8,gild) end
end
sections.CatShelf={
 restock=function()
  cat.shelf=prop('CatShelf_1');if not cat.shelf then return end
  cat.shelf:SetAttribute('CatsHome',0)
  local spots=roomsFrom(cat.shelf:GetPivot().Position,cat.shelf:GetAttribute('Room'),CAT_FROM,CAT_TO)
  local value=math.max(1,math.floor(CAT_VALUE*valueScale()))
  -- one cat per room, nearest rooms first; a small map with fewer than three rooms in reach doubles a room up
  if #spots>0 then for i=1,3 do local m=spawnPiece('PorcelainCat',spots[(i-1)%#spots+1],value);if m then table.insert(cat.pieces,m) end end end
  if #cat.pieces<3 then prune('CatShelf');cat.shelf=nil end -- no room for all three: no shelf, any cats are just loot
 end,
 tick=function()
  if not cat.shelf or not cat.shelf.Parent or cat.home>=3 then return end
  for _,m in ipairs(cat.pieces) do
   if m.Parent and m:GetAttribute('Kind')=='pickup' and not m:GetAttribute('Gilded') then
    local p=holder(m);if p and near(m,cat.shelf) then catHome(p,m) end
   end
  end
 end,
 clue=function()
  if not cat.shelf or not cat.shelf.Parent or cat.home>=3 then return nil end
  for _,m in ipairs(cat.pieces) do
   if m.Parent and m:GetAttribute('Kind')=='pickup' and not m:GetAttribute('HeldBy') and not m:GetAttribute('CargoStored') then return {room=m:GetAttribute('Room'),noun='A porcelain cat'} end
  end
  return nil
 end,
 pickup=function(p,m)
  if m:GetAttribute('ItemId')=='PorcelainCat' and not m:GetAttribute('Gilded') and cat.shelf and cat.shelf.Parent and cat.home<3 then
   ctx.say(p,'It misses its shelf. Carry it close to the cat shelf.')
  end
 end,
 clear=function() cat={shelf=nil,pieces={},home=0} end,
}

-- (LullabyGramophone section: World/LullabyGramophone/DESIGN.md) ------------------------------------------
-- (SlothToyChest section: World/SlothToyChest/DESIGN.md) ---------------------------------------------------
-- LullabyGramophone (WorldB 2026-10-27; World/LullabyGramophone) -----------------------------------------------
-- Level 2+: the lullaby record lies 25-60 studs away; carried next to the gramophone it docks on the platter and
-- plays: every monster dozes 15 s (CalmUntil), floating "z z z", everyone grins. Once per level. Fixed, never random.
local LULLABY_SECONDS,RECORD_VALUE,REC_FROM,REC_TO=15,10,25,60
local LILAC=Color3.fromRGB(200,170,255)
local lull={gram=nil,record=nil,done=false}
local function lullaby()
 local g=lull.gram;if not g or not g.Parent then return end
 lull.done=true
 local untilT=workspace:GetServerTimeNow()+LULLABY_SECONDS
 g:SetAttribute('LullabyUntil',untilT);g:SetAttribute('LullabyDone',true)
 ctx.Audio.Play('MusicBox',g);ctx.noise(g:GetPivot().Position,10,'lullaby',g)
 speech(g:GetPivot().Position+Vector3.new(0,6.5,0),'Hush now, little monsters...')
 local badge=g:FindFirstChild('LullabyGramophone_neon',true);if badge and badge:IsA('BasePart')then badge.Color=Color3.fromRGB(255,240,190)end
 local glow=Instance.new('PointLight');glow.Name='LullabyGlow';glow.Color=LILAC;glow.Brightness=.5;glow.Range=8;glow.Parent=g.PrimaryPart
 local platter=g:FindFirstChild('Platter',true);local arm=g:FindFirstChild('Arm',true);local record=lull.record
 local spinners={};for _,x in{platter,record and record.PrimaryPart}do if x and x:IsA('BasePart')then spinners[x]=x.CFrame end end
 local recordParts={};if record then for _,x in record:GetDescendants()do if x:IsA('BasePart')then recordParts[x]=x.CFrame end end end
 local axis=platter and platter.CFrame or g:GetPivot()
 if arm and arm:IsA('BasePart')then local hinge=arm.CFrame*CFrame.new(arm.Size.X/2,0,-arm.Size.Z/2);arm.CFrame=hinge*CFrame.Angles(math.rad(-7),0,0)*hinge:ToObjectSpace(arm.CFrame)end
 local o=os.clock()
 for _,mon in ipairs(workspace:FindFirstChild('RoamingCreatures')and workspace.RoamingCreatures:GetChildren()or{})do
  if mon:IsA('Model')then
   mon:SetAttribute('CalmUntil',math.max(mon:GetAttribute('CalmUntil')or 0,o+LULLABY_SECONDS));mon:SetAttribute('Dozing',true)
   local head=mon.PrimaryPart
   if head then
    local b=Instance.new('BillboardGui');b.Name='LullabyZzz';b.Size=UDim2.fromOffset(120,60);b.StudsOffsetWorldSpace=Vector3.new(0,mon:GetExtentsSize().Y/2+1.5,0);b.MaxDistance=90;b.Adornee=head;b.Parent=head
    local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.Text='z z z';t.TextColor3=LILAC;t.TextStrokeTransparency=.3;t.Parent=b
    game:GetService('Debris'):AddItem(b,LULLABY_SECONDS)
   end
  end
 end
 for _,p in ipairs(Players:GetPlayers())do if mission(p)then
  grin(p,3);p:SetAttribute('ReactPop','Lullaby! The monsters are dozing...');p:SetAttribute('ReactPopShake',0);p:SetAttribute('ReactPopAt',workspace:GetServerTimeNow())
 end end
 task.spawn(function()
  local a=0
  while os.clock()-o<LULLABY_SECONDS and g.Parent do
   task.wait(.1);a+=math.rad(20)
   local rot=axis*CFrame.Angles(0,a,0)*axis:Inverse()
   for x,cf in spinners do if x.Parent and x~=(record and record.PrimaryPart)then x.CFrame=rot*cf end end
   for x,cf in recordParts do if x.Parent and record and record:GetAttribute('Kind')=='puzzlePiece'then x.CFrame=rot*cf end end
  end
  for _,mon in ipairs(workspace:FindFirstChild('RoamingCreatures')and workspace.RoamingCreatures:GetChildren()or{})do mon:SetAttribute('Dozing',nil)end
  if glow.Parent then glow:Destroy()end
 end)
end
sections.LullabyGramophone={
 restock=function()
  lull={gram=prop('Gramophone_1'),record=nil,done=false}
  local g=lull.gram;if not g then return end
  g:SetAttribute('LullabyDone',nil);g:SetAttribute('LullabyUntil',nil)
  local spots=roomsFrom(g:GetPivot().Position,g:GetAttribute('Room'),REC_FROM,REC_TO)
  if #spots==0 then spots=roomsFrom(g:GetPivot().Position,g:GetAttribute('Room'),12,120)end
  local m=spots[1]and spawnPiece('LullabyRecord',spots[1],math.max(1,math.floor(RECORD_VALUE*valueScale())))
  if not m then prune('LullabyGramophone');lull.gram=nil;return end
  lull.record=m
 end,
 tick=function()
  local g,m=lull.gram,lull.record
  if not g or not g.Parent or lull.done or not m or not m.Parent or m:GetAttribute('Kind')~='pickup'then return end
  local p=holder(m)
  if p and near(m,g)then
   local platter=g:FindFirstChild('Platter',true)
   local top=platter and platter:IsA('BasePart')and platter.Position+Vector3.new(0,platter.Size.Y/2,0)or g:GetPivot()*Vector3.new(0,2.9,0)
   seat(p,m,top,g:GetPivot().Rotation);ctx.Audio.Play('ClothHandle',m);sparkle(m.PrimaryPart,24)
   lullaby()
  end
 end,
 clue=function()
  local m=lull.record
  if lull.done or not m or not m.Parent or m:GetAttribute('HeldBy')or m:GetAttribute('CargoStored')then return nil end
  return {room=m:GetAttribute('Room'),noun='The lullaby record'}
 end,
 pickup=function(p,m)
  if m==lull.record and not lull.done and lull.gram and lull.gram.Parent then ctx.say(p,'A lullaby record! Carry it to the gramophone.')end
 end,
 clear=function()lull={gram=nil,record=nil,done=false}end,
}

-- SlothToyChest (WorldB 2026-10-27; World/SlothToyChest) -------------------------------------------------------
-- Level 3+: the napping sloth hugs the toy chest's key. Walking (not crouched) within 9 studs wakes it: squeak, it hugs
-- tighter for 8 s, loud noise. A crouched player GRABs the key (Kind 'choice' claim); the key holder GRABs the chest:
-- three fixed toys spring out. Claims ride CloseUpChoiceEvent like the RingingWallPhone (no ChoiceId: CloseUpChoices
-- ignores them), so InteractServer/InteractController need nothing new.
local SLOTH_WAKE,SLOTH_TAKE,CHEST_REACH,SLOTH_STIR,TOY_VALUE=9,7,9,8,26
local TOYS={'WindUpCrabToy','SqueakyDuck','RebelliousToyDrum'}
local sl={chest=nil,sloth=nil,holder=nil,opened=false,last={},key=nil}
local claimConn
local function slothVerb()
 local s=sl.sloth;if not s or not s.Parent then return end
 if sl.holder then s:SetAttribute('ChoiceVerb','NAPPING SLOTH (no key)')
 else s:SetAttribute('ChoiceVerb','TAKE THE KEY (crouch!)')end
end
local function wake(p)
 local s=sl.sloth;if not s then return end
 local t=workspace:GetServerTimeNow();s:SetAttribute('SlothStirUntil',t+SLOTH_STIR)
 ctx.Audio.Play('MouseSqueak',s);task.delay(.25,function()if s.Parent then ctx.Audio.Play('MouseSqueak',s)end end)
 ctx.noise(s:GetPivot().Position,35,'sloth squeak',s)
 local body=s:FindFirstChild('Sloth',true)
 if body and body:IsA('BasePart')then local cf=body.CFrame;task.spawn(function()for i=1,6 do if not body.Parent then return end;body.CFrame=cf*CFrame.Angles(0,0,math.rad(i%2==0 and 6 or -6));task.wait(.08)end;if body.Parent then body.CFrame=cf end end)end
 if p then p:SetAttribute('FaceBeat','gasp');p:SetAttribute('FaceBeatUntil',t+1.2);p:SetAttribute('ReactPop','SQUEAK! Shhh!');p:SetAttribute('ReactPopShake',0);p:SetAttribute('ReactPopAt',t)end
 speech(s:GetPivot().Position+Vector3.new(0,3,0),'Mmmh... MINE.')
end
local function takeKey(p)
 local s=sl.sloth;if not s or sl.holder then return end
 local t=workspace:GetServerTimeNow()
 if t<(s:GetAttribute('SlothStirUntil')or 0)then ctx.say(p,'It is hugging the key tight... back off, then sneak in.');return end
 if p:GetAttribute('Crouching')~=true then wake(p);return end
 sl.holder=p;s:SetAttribute('HasKey',false);p:SetAttribute('ChestKey',sl.chest and sl.chest.Name or 'ToyChest_1')
 if sl.key then sl.key.Transparency=1 end
 ctx.Audio.Play('KeyJingle',s);grin(p,2.5);p:SetAttribute('ReactPop','Got the key!');p:SetAttribute('ReactPopShake',0);p:SetAttribute('ReactPopAt',t)
 slothVerb()
end
local function openChest(p)
 local c=sl.chest;if not c or sl.opened or sl.holder~=p then return end
 sl.opened=true;c:SetAttribute('ChestLocked',false);c:SetAttribute('ChoiceVerb','TOY CHEST (empty)');p:SetAttribute('ChestKey',nil);sl.holder=nil
 local lock=c:FindFirstChild('Padlock',true);if lock and lock:IsA('BasePart')then lock.Transparency=1 end
 ctx.Audio.Play('Unlock',c)
 local lid=c:FindFirstChild('Lid',true)
 if lid and lid:IsA('BasePart')then
  local pivot=c:GetPivot();local rel=pivot:ToObjectSpace(lid.CFrame)
  local hinge=pivot*CFrame.new(rel.X,rel.Y-lid.Size.Y/2,rel.Z+lid.Size.Z/2) -- back bottom edge of the lid (back = +Z)
  game:GetService('TweenService'):Create(lid,TweenInfo.new(.6,Enum.EasingStyle.Back),{CFrame=hinge*CFrame.Angles(math.rad(-95),0,0)*hinge:ToObjectSpace(lid.CFrame)}):Play()
 end
 task.delay(.5,function()
  if not c.Parent then return end
  ctx.Audio.Play('PresentOpen',c);ctx.Audio.Play('PartyHorn',c);sparkle(c.PrimaryPart,36)
  local value=math.max(1,math.floor(TOY_VALUE*valueScale()));local pivot=c:GetPivot();local made=0
  for i,id in ipairs(TOYS)do
   local base=(pivot*CFrame.new((i-2)*1.4,1,-2.6)).Position
   local m=ctx.give(id,base,value,'PuzzleGift')
   if m then made+=1;if m.PrimaryPart and not m.PrimaryPart.Anchored then m.PrimaryPart.AssemblyLinearVelocity=pivot:VectorToWorldSpace(Vector3.new((i-2)*3,14,-6))end end
  end
  c:SetAttribute('ToysMade',made)
  grin(p,3);p:SetAttribute('ReactPop','TOYS!');p:SetAttribute('ReactPopShake',0);p:SetAttribute('ReactPopAt',workspace:GetServerTimeNow())
 end)
end
local function slothClaims()
 if claimConn and claimConn.Connected then return end
 local ev=game:GetService('ReplicatedStorage'):FindFirstChild('CloseUpChoiceEvent');if not ev then return end
 claimConn=ev.OnServerEvent:Connect(function(p,action,m)
  if action~='claim'or typeof(m)~='Instance'or not m:IsA('Model')or not mission(p)then return end
  local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart');if not r then return end
  if m==sl.sloth and(m:GetPivot().Position-r.Position).Magnitude<=SLOTH_TAKE then takeKey(p)
  elseif m==sl.chest and(m:GetPivot().Position-r.Position).Magnitude<=CHEST_REACH then
   if sl.holder==p then openChest(p)elseif not sl.opened then ctx.say(p,'Locked. The napping sloth has the key.')end
  end
 end)
end
sections.SlothToyChest={
 restock=function()
  sl={chest=prop('ToyChest_1'),sloth=prop('NappingSloth_1'),holder=nil,opened=false,last={},key=nil}
  if not sl.chest or not sl.sloth then if sl.chest or sl.sloth then prune('SlothToyChest')end;sl.chest,sl.sloth=nil,nil;return end
  sl.key=sl.sloth:FindFirstChild('SlothKey',true)
  for _,m in{sl.chest,sl.sloth}do m:SetAttribute('Kind','choice');for _,x in m:GetDescendants()do if x:IsA('BasePart')then x.CanQuery=true end end end
  sl.chest:SetAttribute('ChoiceVerb','UNLOCK CHEST');sl.chest:SetAttribute('ChestLocked',true);sl.sloth:SetAttribute('HasKey',true)
  slothVerb();slothClaims()
 end,
 tick=function()
  local s=sl.sloth;if not s or not s.Parent then return end
  slothClaims()
  if sl.holder and(not mission(sl.holder)or sl.holder:GetAttribute('RoundDead')==true)then -- the key goes home
   sl.holder:SetAttribute('ChestKey',nil);sl.holder=nil;s:SetAttribute('HasKey',true);if sl.key then sl.key.Transparency=0 end;slothVerb()
  end
  if sl.holder or sl.opened then return end
  local t=workspace:GetServerTimeNow();if t<(s:GetAttribute('SlothStirUntil')or 0)then return end
  local at=s:GetPivot().Position
  for _,p in ipairs(Players:GetPlayers())do
   local r=mission(p)and p:GetAttribute('RoundDead')~=true and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
   if r then
    local last=sl.last[p];sl.last[p]=r.Position
    local moving=last and(r.Position-last).Magnitude>.6
    if moving and(r.Position-at).Magnitude<SLOTH_WAKE and p:GetAttribute('Crouching')~=true then wake(p);return end
   end
  end
 end,
 clue=function()
  if not sl.sloth or not sl.sloth.Parent or sl.holder or sl.opened then return nil end
  return {room=sl.sloth:GetAttribute('Room'),noun='A napping sloth with a key'}
 end,
 clear=function()
  for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('ChestKey')~=nil then p:SetAttribute('ChestKey',nil)end end
  sl={chest=nil,sloth=nil,holder=nil,opened=false,last={},key=nil}
 end,
}
M.SlothTest=function(action,p) -- PuzzleTestApi helpers (Studio): 'take' / 'open' as p
 if action=='take'then takeKey(p);return p:GetAttribute('ChestKey')
 elseif action=='open'then openChest(p);return sl.opened end
 return {chest=sl.chest and sl.chest.Name,sloth=sl.sloth and sl.sloth.Name,holder=sl.holder and sl.holder.Name,opened=sl.opened,lull=lull.gram and lull.gram.Name,record=lull.record and lull.record.Name,done=lull.done}
end
-- puzzle sections end

function M.Configure(drop,_,parts) detach=drop;setParts=parts end
function M.Init(c)
 ctx=c
 if Run:IsStudio() and c.script then
  -- Studio tests only: bring pruned props back and restock the puzzles as if this were `lvl`.
  local api=Instance.new('BindableFunction');api.Name='PuzzleTestApi';api.Parent=c.script
  api.OnInvoke=function(action,lvl,extra)
   if action=='worldb' and M.SlothTest then return M.SlothTest(lvl,extra) end -- WorldB puzzles (Studio tests): 'take' / 'open' / 'state'
   if action=='restock' then
    for _,x in ipairs(prunedFolder():GetChildren()) do local into=ctx.map:FindFirstChild(x:GetAttribute('PuzzleFrom') or '');if into then x.Parent=into end end
    M.Restock(lvl);return true
   end
   if action=='state' then -- what the CatShelf section sees (tests)
    local list={};for _,m in ipairs(cat.pieces) do local p=holder(m);list[#list+1]={held=m:GetAttribute('HeldBy'),holder=p and p.Name,near=near(m,cat.shelf),kind=m:GetAttribute('Kind'),alive=m.Parent~=nil} end
    return {shelf=cat.shelf and cat.shelf.Name,home=cat.home,pieces=list,ticks=ticks}
   end
   return false
  end
 end
end
function M.Restock(round)
 level=math.max(1,math.floor(tonumber(round) or 1))
 clearSections()
 prunedFolder():ClearAllChildren()
 for set,gate in pairs(M.Gate) do
  if level<gate then prune(set)
  elseif sections[set] then
   local ok,err=pcall(sections[set].restock)
   if not ok then warn('[PuzzleBatch] '..set..' skipped: '..tostring(err));prune(set) end
  end
 end
end
function M.Pickup(p,m)
 if not m:GetAttribute('PuzzlePiece') then return end
 for _,s in pairs(sections) do if s.pickup then s.pickup(p,m) end end
end
-- Telephone: the first unsolved puzzle's missing piece, as {room=<graph room name>, noun='A porcelain cat'}.
function M.Clue()
 for _,set in ipairs({'LullabyGramophone','SlothToyChest','CatShelf'}) do
  local s=sections[set];local c=s and s.clue and s.clue()
  if c and c.room then return c end
 end
 return nil
end
function M.ClearPlayer(_) end -- no player attributes: payouts are item values and monster CalmUntil
-- CursedBatchEffects.ClearLevel also runs on Phase changes (Deploying comes AFTER restock), so the puzzle state is only
-- reset at the start of each Restock; the props and pieces die with the map anyway.
function M.ClearLevel() end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK or not ctx then return end;elapsed=0
 local clock=os.clock();ticks+=1
 for set,s in pairs(sections) do if s.tick then local ok,err=pcall(s.tick,clock);if not ok then warn('[PuzzleBatch] '..set..' tick: '..tostring(err)) end end end
end)
return M
