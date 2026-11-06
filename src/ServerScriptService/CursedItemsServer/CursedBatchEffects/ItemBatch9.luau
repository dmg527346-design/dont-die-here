-- Batch 9 (CursedB build 2026-10-27): RunawayToiletPaper, SnowGlobe, SongbirdMusicBox, TrailEraser, XRayLightBox,
-- CartMagnet, PullbackRacer. Required exactly once by CursedBatchEffects (Configure, Pickup, ClearPlayer, ClearLevel).
-- Own Heartbeat (4 Hz, the racer at 10 Hz). Faces: the shared Player.FaceBeat/FaceBeatUntil contract
-- (VoiceMouthClient, CharacterMotionClient). Screens: StarterPlayerScripts.CursedBatchBClient.
-- Monster hooks reused from CreatureRoamServer: CalmUntil / StunnedUntil / HypnoUntil / LurePosition+LureUntil (os.clock);
-- ErasedUserId / ErasedUntil (os.clock) is read by CreatureRoamServer perceive (TrailEraser).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local HS=game:GetService('HttpService')
local SoundService=game:GetService('SoundService')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Sounds=require(RS:WaitForChild('GameplaySoundCatalog'))
local M={}
local TICK,LEASE=.25,.5
local ITEMS={} -- [ItemId]={pickup=fn(p,m,now),tick=fn(now,models,clock),clearPlayer=fn(p),clearLevel=fn(),debug=fn()}
local KEYS={'FaceBeat','FaceBeatUntil'}
local detach,clearHold,setParts
local leases={}
local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function rootOf(p)local c=living(p);local r=c and c:FindFirstChild('HumanoidRootPart');return r and r:IsA('BasePart')and r or nil end
local function holderOf(m)
 local p=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
 return m.Parent and m:IsDescendantOf(workspace)and living(p)and not m:GetAttribute('Selling')and not m:GetAttribute('CargoStored')and p or nil
end
local function setValue(m,v)v=math.max(0,math.floor(v+.5));m:SetAttribute('Value',v);m:SetAttribute('LootValue',v)end
local function cue(key,fallback)return Sounds[key]and key or fallback end
local function evidence(pos,radius,label,source)
 local e=SS:FindFirstChild('MonsterEvidence');if e and e:IsA('BindableEvent')then e:Fire(pos,math.clamp(radius/1.4,1,100),label,source)end
end
local function lease(p,key,now)
 local stamp=math.max(p:GetAttribute(key)or 0,now+LEASE);p:SetAttribute(key,stamp);leases[p]=leases[p]or{};leases[p][key]=stamp
end
local function clearLeases(p)
 for key,stamp in pairs(leases[p]or{})do if p:GetAttribute(key)==stamp then p:SetAttribute(key,nil)end end;leases[p]=nil
end
-- Faces use the game's shared FaceBeat/FaceBeatUntil contract (ItemBatch6.Feedback; VoiceMouthClient draws the mouth,
-- CharacterMotionClient the eyes). kind -> mood; the same mood only extends, another mood takes over, except that a
-- short (<= .5 s) 4 Hz hold refresh never cuts a different, still-running face short (like Feedback.Hold).
local MOOD={Grin='grin',Pout='pucker',Sad='frown',Squint='squint',Laugh='laugh'}
local function face(p,kind,seconds,now)
 local mood=MOOD[kind];local t=now+seconds
 if p:GetAttribute('FaceBeat')~=mood then
  if seconds<=.5 and(p:GetAttribute('FaceBeatUntil')or 0)>now+.05 then return end
  p:SetAttribute('FaceBeat',mood);p:SetAttribute('FaceBeatUntil',t)
 elseif(p:GetAttribute('FaceBeatUntil')or 0)<t then p:SetAttribute('FaceBeatUntil',t)end
end
local function notice(p,text)
 local e=RS:FindFirstChild('CursedEvent');if e and p.Parent then e:FireClient(p,'notice',text)end
end
local function flatSpeed(r)local v=r.AssemblyLinearVelocity;return Vector3.new(v.X,0,v.Z).Magnitude end
local function monsters()
 local out={};local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,enemy in ipairs(folder:GetChildren())do
  local primary=enemy:IsA('Model')and enemy.PrimaryPart;local h=enemy:FindFirstChildOfClass('Humanoid')
  if primary and(not h or h.Health>0)then table.insert(out,enemy)end
 end end
 return out
end
-- CreatureRoamServer only consumes a lure whose position changed, so jitter it a hair each time.
local function lure(enemy,pos,seconds)
 enemy:SetAttribute('LurePosition',pos+Vector3.new(math.random()*.2-.1,0,math.random()*.2-.1));enemy:SetAttribute('LureUntil',os.clock()+seconds)
end
local function nearVan(pos,radius)
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
 return van~=nil and(van:GetPivot().Position-pos).Magnitude<radius
end
-- Level layout from the replicated GeneratedGraph (rooms: name, level, x1..z2, neighbors).
local graphCache={raw=nil,graph=nil}
local function graph()
 local map=workspace:FindFirstChild('Mansion');local v=map and map:FindFirstChild('GeneratedGraph')
 if not v then return nil end
 if graphCache.raw~=v.Value then local ok,g=pcall(HS.JSONDecode,HS,v.Value);graphCache.raw=v.Value;graphCache.graph=ok and g or nil end
 return graphCache.graph
end
local function roomAt(pos)
 local g=graph();if not g then return nil end
 local fh=g.floorHeight or 16;local level=math.floor((pos.Y+2)/fh);local other
 for _,r in ipairs(g.rooms or{})do
  if r.x1 and pos.X>=r.x1 and pos.X<=r.x2 and pos.Z>=r.z1 and pos.Z<=r.z2 then
   if(r.level or 0)==level then return r end
   other=other or r
  end
 end
 return other
end
local function hearts(part,count)
 if not part or not part.Parent then return end
 local a=Instance.new('Attachment');a.Name='Batch9Hearts';a.Parent=part
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(Color3.fromRGB(255,140,205))
 e.LightEmission=.5;e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,0)});e.Lifetime=NumberRange.new(.6,1)
 e.Speed=NumberRange.new(2,5);e.SpreadAngle=Vector2.new(60,60);e.Acceleration=Vector3.new(0,3,0);e.Rate=0;e.Parent=a
 e:Emit(count);Debris:AddItem(a,1.5)
end

-- RunawayToiletPaper ---------------------------------------------------------------------------------------
-- While held it unrolls a paper strip trail along the holder's path; every stud costs sale value (down to 50 %).
-- Teammates who cross the trail get paper stuck to their shoe for 12 s; a monster that crosses it is tangled 2 s.
local PAPER={LENGTH=225,STEP=2.5,GAP=8,CLIMB=3,MIN_SHARE=.5,MAX_STRIPS=400,SHOE=12,SHOE_REACH=1.4,TANGLE_REACH=3,TANGLE_STUN=2,TANGLE_COOLDOWN=8}
local PAPER_WHITE=Color3.fromRGB(246,246,240)
local rolls={} -- model -> {last=Vector3?}
local strips={} -- {part=Part,a=Vector3,b=Vector3}, oldest first
local shoes={} -- player -> streamer Part
local tangled={} -- creature model -> os.clock when it can be tangled again
local floorRay=RaycastParams.new();floorRay.FilterType=Enum.RaycastFilterType.Exclude;floorRay.RespectCanCollide=true
local function trailFolder()
 local map=workspace:FindFirstChild('Mansion');if not map then return nil end
 local f=map:FindFirstChild('PaperTrails')
 if not f then f=Instance.new('Folder');f.Name='PaperTrails';f.Parent=map end
 return f
end
local function removeStrip(i)local s=table.remove(strips,i);if s and s.part.Parent then s.part:Destroy()end end
local function layStrip(a,b,folder)
 local len=(b-a).Magnitude
 local x=Instance.new('Part');x.Name='PaperStrip';x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.CastShadow=false
 x.Material=Enum.Material.SmoothPlastic;x.Color=PAPER_WHITE;x.Size=Vector3.new(.9,.04,len+.2)
 x.CFrame=CFrame.lookAt((a+b)/2,b);x.Parent=folder
 table.insert(strips,{part=x,a=a,b=b})
 while #strips>PAPER.MAX_STRIPS do removeStrip(1)end
end
local function paperValue(m)
 local full=m:GetAttribute('PaperFullValue');if not full then return end
 local left=m:GetAttribute('PaperLeft')or 0
 setValue(m,math.ceil(full*(PAPER.MIN_SHARE+(1-PAPER.MIN_SHARE)*left/PAPER.LENGTH)))
end
local function unroll(m,c,interactive)
 local left=m:GetAttribute('PaperLeft')or 0;if left<=0 then return end
 local root=c:FindFirstChild('HumanoidRootPart');local folder=trailFolder();if not root or not folder then return end
 local s=rolls[m];if not s then s={};rolls[m]=s end
 floorRay.FilterDescendantsInstances={c,interactive,folder,workspace:FindFirstChild('RoamingCreatures')}
 local hit=workspace:Raycast(root.Position,Vector3.new(0,-6,0),floorRay)
 if not hit then return end -- airborne: the strand resumes where they land
 local here=hit.Position+Vector3.new(0,.03+(#strips%5)*.006,0) -- a hair apart, so crossings never z-fight
 local last=s.last
 if not last then s.last=here;return end
 local flat=Vector3.new(here.X-last.X,0,here.Z-last.Z).Magnitude
 if flat>PAPER.GAP or math.abs(here.Y-last.Y)>PAPER.CLIMB then s.last=here;return end
 if flat<PAPER.STEP then return end
 layStrip(last,here,folder);s.last=here
 left=math.max(0,left-math.min(left,flat));m:SetAttribute('PaperLeft',left);paperValue(m)
 if left<=0 then m:SetAttribute('PaperEmpty',true)end
end
local function nearStrip(pos,reach,above)
 for i,s in ipairs(strips)do
  local a,b=s.a,s.b;local dy=pos.Y-(a.Y+b.Y)/2
  if dy>=-1 and dy<=above then
   local ab=Vector3.new(b.X-a.X,0,b.Z-a.Z);local ap=Vector3.new(pos.X-a.X,0,pos.Z-a.Z)
   local t=math.clamp(ap:Dot(ab)/math.max(ab:Dot(ab),1e-3),0,1)
   if(ap-ab*t).Magnitude<=reach then return i end
  end
 end
 return nil
end
local function shoe(q,c,on)
 local x=shoes[q]
 if not on then if x then x:Destroy();shoes[q]=nil end;return end
 if x and x.Parent==c then return end
 if x then x:Destroy()end
 local foot=c:FindFirstChild('RightFoot')or c:FindFirstChild('HumanoidRootPart');if not foot then return end
 x=Instance.new('Part');x.Name='ShoePaper';x.Size=Vector3.new(.55,.03,2.6);x.Color=PAPER_WHITE;x.Material=Enum.Material.SmoothPlastic
 x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.Massless=true;x.CastShadow=false
 local w=Instance.new('Weld');w.Name='ShoePaperWeld';w.Part0=foot;w.Part1=x;w.C0=CFrame.new(0,-foot.Size.Y*.4,foot.Size.Z*.5+1.25)*CFrame.Angles(math.rad(-6),0,0);w.Parent=x
 x.Parent=c;shoes[q]=x
end
local function scraps(pos)
 local a=Instance.new('Attachment');a.WorldPosition=pos;a.Parent=workspace.Terrain
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(PAPER_WHITE)
 e.Size=NumberSequence.new(.22,.12);e.Lifetime=NumberRange.new(.8,1.4);e.Speed=NumberRange.new(6,12);e.SpreadAngle=Vector2.new(60,60);e.Acceleration=Vector3.new(0,-14,0);e.Drag=2;e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-200,200);e.Rate=0;e.Parent=a
 e:Emit(28);Debris:AddItem(a,2)
end
ITEMS.RunawayToiletPaper={
 pickup=function(p,m,now)
  if m:GetAttribute('PaperLeft')==nil then
   m:SetAttribute('PaperLeft',PAPER.LENGTH);m:SetAttribute('PaperFullValue',m:GetAttribute('Value')or 0)
   Audio.Play('ToiletFlush',m);face(p,'Grin',1.5,now)
  end
  rolls[m]={} -- a fresh strand starts under the new holder
 end,
 tick=function(now,list,clock)
  local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
  local rollHolders={}
  for _,m in ipairs(list)do
   local p=holderOf(m);local c=p and living(p)
   if c then rollHolders[p]=true;unroll(m,c,interactive)else rolls[m]=nil end
  end
  for m in pairs(rolls)do if not m.Parent then rolls[m]=nil end end
  if #strips>0 then
   for _,q in ipairs(Players:GetPlayers())do
    local qr=rootOf(q)
    if qr and not rollHolders[q]and nearStrip(qr.Position,PAPER.SHOE_REACH,5)then
     if now>=(q:GetAttribute('PaperShoeUntil')or 0)then Audio.Play('ClothHandle',qr);face(q,'Sad',1.5,now);q:SetAttribute('PaperStuckAt',now)end
     q:SetAttribute('PaperShoeUntil',now+PAPER.SHOE)
    end
   end
   for _,n in ipairs(monsters())do
    local pp=n.PrimaryPart
    if clock>=(tangled[n]or 0)then
     local i=nearStrip(pp.Position,PAPER.TANGLE_REACH,14)
     if i then
      tangled[n]=clock+PAPER.TANGLE_COOLDOWN
      n:SetAttribute('StunnedUntil',math.max(n:GetAttribute('StunnedUntil')or 0,clock+PAPER.TANGLE_STUN))
      Audio.Play('PresentOpen',pp);scraps(strips[i].part.Position)
      for k=math.min(#strips,i+1),math.max(1,i-1),-1 do removeStrip(k)end
     end
    end
   end
  end
  for n in pairs(tangled)do if not n.Parent then tangled[n]=nil end end
  for _,q in ipairs(Players:GetPlayers())do
   local qc=living(q);shoe(q,qc,qc~=nil and now<(q:GetAttribute('PaperShoeUntil')or 0))
  end
 end,
 clearPlayer=function(p)shoe(p,nil,false)end,
 clearLevel=function()
  for _,s in ipairs(strips)do if s.part.Parent then s.part:Destroy()end end
  local map=workspace:FindFirstChild('Mansion');local f=map and map:FindFirstChild('PaperTrails');if f then f:Destroy()end
  for q in pairs(shoes)do shoe(q,nil,false)end
  table.clear(rolls);table.clear(strips);table.clear(shoes);table.clear(tangled)
 end,
 debug=function()return{strips=#strips}end,
}
table.insert(KEYS,'PaperShoeUntil');table.insert(KEYS,'PaperStuckAt')

-- SnowGlobe ------------------------------------------------------------------------------------------------
-- Grab: you are inside the globe (a 7-stud dome welded to you, snow falling). Running shakes it into a blizzard
-- (the holder's screen whites out). Every 8-14 s a giant eye peers in (server-timed SnowEyeAt; the face goes "O").
-- The dome is SmoothPlastic, not Glass: see-through Glass on moving/held parts smears (CursedItems note 2026-10-24).
local GLOBE={SIZE=7,TRANSPARENCY=.8,CALM=8,BLIZZARD=18,SNOW_CALM=8,SNOW_BLIZZARD=90,EYE_FIRST=4,EYE_MIN=8,EYE_MAX=14,EYE_SECONDS=3.2}
local GLASS=Color3.fromRGB(205,235,255)
local domes={} -- [player]={character=Model,dome=Part,base=Part,trim=Part,snow=ParticleEmitter,parts={},eyeAt=t}
local function dropDome(p)
 local s=domes[p];domes[p]=nil
 if s then for _,x in ipairs(s.parts)do if x.Parent then x:Destroy()end end end
end
local function buildDome(p,c,now)
 local s=domes[p]
 if s and s.character==c and s.dome.Parent then return s end
 dropDome(p)
 local root=c:FindFirstChild('HumanoidRootPart');local hum=c:FindFirstChildOfClass('Humanoid')
 if not root or not hum then return nil end
 local feet=-(hum.HipHeight+root.Size.Y/2)
 local function shell(name,shape,size,color,material,transparency,offset)
  local x=Instance.new('Part');x.Name=name;x.Shape=shape;x.Size=size;x.Color=color;x.Material=material;x.Transparency=transparency;x.Reflectance=name=='SnowGlobeDome'and .15 or 0
  x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.Massless=true;x.CastShadow=false
  x.CFrame=root.CFrame*offset
  local w=Instance.new('Weld');w.Name='SnowGlobeWeld';w.Part0=root;w.Part1=x;w.C0=offset;w.Parent=x
  x.Parent=c;return x
 end
 local flat=CFrame.Angles(0,0,math.rad(90)) -- a cylinder's axis is X: turn it to stand up
 local dome=shell('SnowGlobeDome',Enum.PartType.Ball,Vector3.one*GLOBE.SIZE,GLASS,Enum.Material.SmoothPlastic,GLOBE.TRANSPARENCY,CFrame.new(0,feet+GLOBE.SIZE*.5-.6,0))
 local base=shell('SnowGlobeBase',Enum.PartType.Cylinder,Vector3.new(.7,GLOBE.SIZE*.92,GLOBE.SIZE*.92),Color3.fromRGB(44,65,145),Enum.Material.SmoothPlastic,0,CFrame.new(0,feet-.3,0)*flat)
 local trim=shell('SnowGlobeTrim',Enum.PartType.Cylinder,Vector3.new(.16,GLOBE.SIZE*.95,GLOBE.SIZE*.95),Color3.fromRGB(201,151,63),Enum.Material.Metal,0,CFrame.new(0,feet+.08,0)*flat)
 local snow=Instance.new('ParticleEmitter');snow.Name='SnowGlobeSnow';snow.Texture='rbxasset://textures/particles/sparkles_main.dds'
 snow.Color=ColorSequence.new(Color3.new(1,1,1));snow.LightEmission=.3;snow.Size=NumberSequence.new(.14,.08)
 snow.Lifetime=NumberRange.new(2,3.2);snow.Speed=NumberRange.new(.3,1.2);snow.SpreadAngle=Vector2.new(180,180)
 snow.Acceleration=Vector3.new(0,-1.6,0);snow.Drag=1;snow.Rate=GLOBE.SNOW_CALM
 snow.Shape=Enum.ParticleEmitterShape.Sphere;snow.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume;snow.Parent=dome
 s={character=c,dome=dome,base=base,trim=trim,snow=snow,parts={dome,base,trim},eyeAt=now+GLOBE.EYE_FIRST}
 domes[p]=s;return s
end
ITEMS.SnowGlobe={
 pickup=function(p,m,now)
  local c=living(p);if not c then return end
  lease(p,'SnowGlobeUntil',now)
  local s=buildDome(p,c,now);if s then s.snow:Emit(60)end
  Audio.Play('GlassImpact',m);face(p,'Grin',1.5,now)
  notice(p,"You're inside the snow globe now. Don't shake it.")
 end,
 tick=function(now,list)
  local holding={}
  for _,m in ipairs(list)do local p=holderOf(m);if p then holding[p]=true end end
  for p in pairs(holding)do
   local c=living(p);lease(p,'SnowGlobeUntil',now)
   local s=c and buildDome(p,c,now)
   if s then
    local hide=p:GetAttribute('Hiding')or p:GetAttribute('ClosetState')
    local r=c:FindFirstChild('HumanoidRootPart')
    local shake=r and math.clamp((flatSpeed(r)-GLOBE.CALM)/(GLOBE.BLIZZARD-GLOBE.CALM),0,1)or 0
    s.dome.Transparency=hide and 1 or GLOBE.TRANSPARENCY;s.base.Transparency=hide and 1 or 0;s.trim.Transparency=hide and 1 or 0
    s.snow.Enabled=not hide;s.snow.Rate=GLOBE.SNOW_CALM+(GLOBE.SNOW_BLIZZARD-GLOBE.SNOW_CALM)*shake*shake
    s.snow.Speed=NumberRange.new(.3+shake*4,1.2+shake*8)
    if shake>.6 then face(p,'Squint',.5,now)end
    if now>=s.eyeAt and not hide then
     s.eyeAt=now+math.random(GLOBE.EYE_MIN,GLOBE.EYE_MAX)
     p:SetAttribute('SnowEyeAt',now);p:SetAttribute('SnowEyeSide',math.random(1,3))
     task.delay(.6,function()if p.Parent and p:GetAttribute('SnowEyeAt')==now then face(p,'Pout',1.8,workspace:GetServerTimeNow())end end)
    end
   end
  end
  for p in pairs(domes)do if not holding[p]then dropDome(p)end end
 end,
 clearPlayer=function(p)dropDome(p)end,
 clearLevel=function()for p in pairs(domes)do dropDome(p)end;table.clear(domes)end,
 debug=function()local n=0;for _ in pairs(domes)do n+=1 end;return{domes=n}end,
}
for _,key in ipairs({'SnowGlobeUntil','SnowEyeAt','SnowEyeSide'})do table.insert(KEYS,key)end

-- SongbirdMusicBox (treasure) ------------------------------------------------------------------------------
-- Every grab winds it (full 25 s; the same hands again within 20 s only add 6 s). It plays while wound (the tune
-- drags in its last 6 s), runs down at half speed in the cart, and when it runs down it shrieks every 5 s and
-- lures every monster within 140 studs (quiet near the van). The holder grins while it sings.
local BOX={FULL=25,SAME=6,SAME_WINDOW=20,CART_RATE=.5,SLOW_FROM=6,SHRIEK_EVERY=5,SHRIEK_RADIUS=140,SHRIEK_LOUD=100,VAN_QUIET=30,HEAR=30}
local boxes={} -- [Model]={endsAt=clock,winder=Player,windAt=clock,started=bool,shrieking=bool,nextShriek=clock,song=Sound}
local function boxSong(m,s)
 if s.song and s.song.Parent then return s.song end
 local c=Sounds.MusicBox
 local song=Instance.new('Sound');song.Name='SongbirdTune';song.SoundId=c.id;song.Looped=true;song.Volume=.45
 song.PlaybackSpeed=c.speed or 1;song.SoundGroup=SoundService:FindFirstChild('GameplaySFX')or SoundService:FindFirstChild('GameplayMusic')
 song.RollOffMode=Enum.RollOffMode.InverseTapered;song.RollOffMinDistance=4;song.RollOffMaxDistance=60;song.Parent=m.PrimaryPart
 s.song=song;return song
end
local function stopSong(s)if s.song and s.song.Parent then s.song:Stop()end end
ITEMS.SongbirdMusicBox={
 pickup=function(p,m,now)
  local s=boxes[m];if not s then s={};boxes[m]=s;m.Destroying:Connect(function()stopSong(s);boxes[m]=nil end)end
  local clock=os.clock()
  local remaining=math.max(0,(s.endsAt or clock)-clock)
  local same=s.winder==p and clock-(s.windAt or-100)<BOX.SAME_WINDOW
  remaining=if same then math.min(BOX.FULL,remaining+BOX.SAME)else BOX.FULL
  s.endsAt=clock+remaining;s.winder=p;s.windAt=clock;s.started=true;s.shrieking=false
  m:SetAttribute('WindEndsAt',now+remaining);m:SetAttribute('WindFull',BOX.FULL);m:SetAttribute('WoundBy',p.UserId);m:SetAttribute('Shrieking',nil)
  Audio.Play('Unlock',m);face(p,'Grin',2,now)
  if same then notice(p,'The key is stiff. Let a friend wind it.')end
 end,
 tick=function(now,_list,clock,step)
  for m,s in pairs(boxes)do
   if not m.Parent or not m.PrimaryPart then stopSong(s);boxes[m]=nil;continue end
   if not s.started then continue end
   if m:GetAttribute('Selling')then stopSong(s);continue end
   if m:GetAttribute('CargoStored')then s.endsAt+=step*(1-BOX.CART_RATE);m:SetAttribute('WindEndsAt',now+math.max(0,s.endsAt-clock))end
   local remaining=s.endsAt-clock;local song=boxSong(m,s)
   if remaining>0 then
    song.PlaybackSpeed=if remaining<BOX.SLOW_FROM then .55+.45*remaining/BOX.SLOW_FROM else 1
    if not song.IsPlaying then song:Play()end
    local p=holderOf(m);if p then face(p,'Grin',.5,now)end
   else
    if song.IsPlaying then song:Stop()end
    if not s.shrieking then s.shrieking=true;s.nextShriek=clock;m:SetAttribute('Shrieking',true)end
    local pos=m.PrimaryPart.Position
    if clock>=s.nextShriek and not nearVan(pos,BOX.VAN_QUIET)then
     s.nextShriek=clock+BOX.SHRIEK_EVERY
     Audio.Play(cue('MusicBoxShriek','DollCry'),m);Audio.Play('StingChoir',m);m:SetAttribute('ShriekAt',now)
     evidence(pos,BOX.SHRIEK_LOUD*1.4,'music box shriek',m)
     for _,enemy in ipairs(monsters())do if(enemy.PrimaryPart.Position-pos).Magnitude<BOX.SHRIEK_RADIUS then lure(enemy,pos,BOX.SHRIEK_EVERY+1)end end
     for _,q in ipairs(Players:GetPlayers())do local r=rootOf(q);if r and(r.Position-pos).Magnitude<BOX.HEAR then face(q,'Pout',1.2,now)end end
    end
   end
  end
 end,
 clearPlayer=function(_p)end,
 clearLevel=function()for _,s in pairs(boxes)do stopSong(s)end;table.clear(boxes)end,
 debug=function()local list={};for m,s in pairs(boxes)do table.insert(list,{model=m:GetFullName(),left=(s.endsAt or 0)-os.clock(),shrieking=s.shrieking})end;return list end,
}

-- TrailEraser ----------------------------------------------------------------------------------------------
-- Grab while chased: every chasing monster within 70 studs is dazed 2.5 s (HypnoUntil), forgets you
-- (ErasedUserId/ErasedUntil) and wakes heading for the crumbs 30 studs past it. Cost: your field map is rubbed out
-- for 30 s (MapErasedUntil), the eraser shrinks and loses 25 % of its value per rub; 3 rubs, 15 s apart.
local ERASE={RUBS=3,COOLDOWN=15,RADIUS=70,DAZE=2.5,FORGET_EXTRA=.2,CRUMBS=30,LURE=6,MAP=30,SHRINK=.2,CUT=.25}
local CHASING={Chase=true,Search=true,Stalk=true,Investigate=true,Suspicious=true,Ambush=true}
local CRUMB=Color3.fromRGB(250,206,222)
local erasers=setmetatable({},{__mode='k'})
local function crumbs(part)
 local a=Instance.new('Attachment');a.Name='EraserCrumbs';a.Position=Vector3.new(0,2.5,0);a.Parent=part
 local e=Instance.new('ParticleEmitter');e.Color=ColorSequence.new(CRUMB);e.LightInfluence=1
 e.Size=NumberSequence.new(.28,.1);e.Lifetime=NumberRange.new(.6,1);e.Rate=26;e.Speed=NumberRange.new(2,4)
 e.SpreadAngle=Vector2.new(60,60);e.Acceleration=Vector3.new(0,-20,0);e.Rotation=NumberRange.new(0,360);e.Parent=a
 Debris:AddItem(a,ERASE.DAZE)
end
ITEMS.TrailEraser={
 pickup=function(p,m,now)
  local root=rootOf(p);if not root then return end
  local s=erasers[m]
  if not s then s={left=ERASE.RUBS,readyAt=0,value=m:GetAttribute('Value')or m:GetAttribute('LootValue')};erasers[m]=s end
  local clock=os.clock();if clock<s.readyAt then return end
  if s.left<=0 then notice(p,'It is just a pink nub now. Sell it.');return end
  s.readyAt=clock+1
  local pos=root.Position;local hit={}
  if now<(p:GetAttribute('ChasedUntil')or 0)then
   for _,enemy in ipairs(monsters())do
    if CHASING[enemy:GetAttribute('AIState')]and(enemy.PrimaryPart.Position-pos).Magnitude<ERASE.RADIUS then table.insert(hit,enemy)end
   end
  end
  if #hit==0 then Audio.Play('FrostingSquish',m);notice(p,'Nothing is chasing you. Save the rubs.');return end
  for _,enemy in ipairs(hit)do
   local at=enemy.PrimaryPart.Position
   local away=Vector3.new(at.X-pos.X,0,at.Z-pos.Z)
   away=if away.Magnitude>.1 then away.Unit else-root.CFrame.LookVector
   enemy:SetAttribute('HypnoUntil',math.max(enemy:GetAttribute('HypnoUntil')or 0,clock+ERASE.DAZE))
   enemy:SetAttribute('ErasedUserId',p.UserId);enemy:SetAttribute('ErasedUntil',clock+ERASE.DAZE+ERASE.FORGET_EXTRA)
   enemy:SetAttribute('LurePosition',at+away*ERASE.CRUMBS);enemy:SetAttribute('LureUntil',clock+ERASE.LURE)
   crumbs(enemy.PrimaryPart)
  end
  s.left-=1;s.readyAt=clock+ERASE.COOLDOWN
  local used=ERASE.RUBS-s.left
  m:SetAttribute('EraserRubs',s.left)
  pcall(function()m:ScaleTo(1-ERASE.SHRINK*used)end)
  if type(s.value)=='number'then setValue(m,math.max(1,s.value*(1-ERASE.CUT*used)))end
  p:SetAttribute('MapErasedUntil',now+ERASE.MAP);p:SetAttribute('EraserRubAt',now)
  face(p,'Grin',2.2,now)
  Audio.Play('FrostingSquish',m);Audio.Play('HypnoHit',hit[1])
  notice(p,('Rubbed out! %d monster%s forgot you. Your map got rubbed out too.'):format(#hit,#hit==1 and''or's'))
 end,
 tick=function()end,
 clearPlayer=function(_p)end,
 clearLevel=function()for m in pairs(erasers)do erasers[m]=nil end end,
}
table.insert(KEYS,'MapErasedUntil');table.insert(KEYS,'EraserRubAt')

-- XRayLightBox (Hospital) ----------------------------------------------------------------------------------
-- While held: XRayUntil lease (the holder's client sees monsters in this room + the rooms next door through walls).
-- Every 7 s (first on the grab) the flash goes off: XRayFlashAt, and every monster in that reveal set is lured to
-- the holder for 6 s. The holder makes an "O" face on every flash.
local XRAY={EVERY=7,LURE=6}
local xrays={} -- [Model]={nextFlash=clock}
ITEMS.XRayLightBox={
 pickup=function(p,m,now)
  local s=xrays[m]or{};xrays[m]=s;s.nextFlash=0
  Audio.Play('FlashlightClick',m) -- no face here: the first flash (same grab) gives the surprised pucker
  notice(p,'X-ray on: you see monsters in this room and the rooms next to it. The flash shows them you, too.')
 end,
 tick=function(now,list,clock)
  for m in pairs(xrays)do if not m.Parent then xrays[m]=nil end end
  for _,m in ipairs(list)do
   local p=holderOf(m);local s=xrays[m];local r=p and rootOf(p)
   if r and s then
    lease(p,'XRayUntil',now)
    if clock>=(s.nextFlash or 0)then
     s.nextFlash=clock+XRAY.EVERY
     Audio.Play('CameraShutter',m);p:SetAttribute('XRayFlashAt',now);face(p,'Pout',1.2,now)
     local here=roomAt(r.Position);local set={}
     if here then set[here.name]=true;for _,n in ipairs(here.neighbors or{})do set[n]=true end end
     for _,enemy in ipairs(monsters())do
      local at=roomAt(enemy.PrimaryPart.Position)
      if at and set[at.name]then lure(enemy,r.Position,XRAY.LURE)end
     end
    end
   end
  end
 end,
 clearPlayer=function(p)p:SetAttribute('XRayFlashAt',nil)end,
 clearLevel=function()table.clear(xrays)end,
}
table.insert(KEYS,'XRayUntil');table.insert(KEYS,'XRayFlashAt')

-- CartMagnet -----------------------------------------------------------------------------------------------
-- While held, the unattended cart (nobody pushing, 6..36 studs away) rolls toward the holder at up to 11 studs/s,
-- rattling loudly; inside 6 studs it bonks the holder (MagnetNudgeAt) and rests 3 s.
local MAG={RANGE=36,STOP=6,SPEED=11,RATTLE=2,NOISE=32,REST=3}
local magnets={} -- [Model]={rollSince=clock?,rattleAt=clock,restUntil=clock}
local function cartModel()
 local map=workspace:FindFirstChild('Mansion');local i=map and map:FindFirstChild('Interactive')
 local cart=i and i:FindFirstChild('RecoveryCart')
 return cart and cart.PrimaryPart and cart or nil
end
local function stopPull(cart)
 if not cart or not cart.PrimaryPart then return end
 for _,name in ipairs({'CartMagnetPull','CartMagnetHearts'})do local x=cart.PrimaryPart:FindFirstChild(name);if x then x:Destroy()end end
end
local function pull(cart,dir,speed)
 local root=cart.PrimaryPart
 local lv=root:FindFirstChild('CartMagnetPull')
 if not lv then
  local a=root:FindFirstChild('CartMagnetPullAt')or Instance.new('Attachment');a.Name='CartMagnetPullAt';a.Parent=root
  lv=Instance.new('LinearVelocity');lv.Name='CartMagnetPull';lv.Attachment0=a;lv.RelativeTo=Enum.ActuatorRelativeTo.World
  lv.VelocityConstraintMode=Enum.VelocityConstraintMode.Plane;lv.PrimaryTangentAxis=Vector3.xAxis;lv.SecondaryTangentAxis=Vector3.zAxis
  lv.MaxForce=math.max(4000,root.AssemblyMass*120);lv.Parent=root
  local e=Instance.new('ParticleEmitter');e.Name='CartMagnetHearts';e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(Color3.fromRGB(255,140,205))
  e.LightEmission=.5;e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.4),NumberSequenceKeypoint.new(1,0)});e.Lifetime=NumberRange.new(.6,1)
  e.Speed=NumberRange.new(2,4);e.SpreadAngle=Vector2.new(40,40);e.Acceleration=Vector3.new(0,4,0);e.Rate=10;e.Parent=root
 end
 lv.PlaneVelocity=Vector2.new(dir.X,dir.Z)*speed
end
ITEMS.CartMagnet={
 pickup=function(p,m,now)
  local s=magnets[m]or{rattleAt=0,restUntil=0};magnets[m]=s
  Audio.Play('MetalImpact',m);hearts(m.PrimaryPart,14);face(p,'Pout',1.5,now)
  notice(p,"The cart has a crush on you. It's coming.")
 end,
 tick=function(now,list,clock)
  local cart=cartModel();local pulled=false
  for m in pairs(magnets)do if not m.Parent then magnets[m]=nil end end
  for _,m in ipairs(list)do
   local p=holderOf(m);local s=magnets[m];local r=p and rootOf(p)
   if not(p and s and r and cart)or pulled then continue end
   local free=cart:GetAttribute('HeldBy')==nil and not cart:GetAttribute('Selling')and cart:GetAttribute('ClientDriven')==nil
   local cp=cart.PrimaryPart.Position
   local flat=Vector3.new(r.Position.X-cp.X,0,r.Position.Z-cp.Z);local d=flat.Magnitude
   if not free or clock<s.restUntil or d>MAG.RANGE then s.rollSince=nil;continue end
   if d<=MAG.STOP then
    if s.rollSince and clock-s.rollSince>=1 then
     Audio.Play('MetalImpact',cart.PrimaryPart);hearts(cart.PrimaryPart,18);p:SetAttribute('MagnetNudgeAt',now);face(p,'Grin',1.5,now)
     s.restUntil=clock+MAG.REST
    end
    s.rollSince=nil;continue
   end
   s.rollSince=s.rollSince or clock;pulled=true
   pull(cart,flat.Unit,math.min(MAG.SPEED,d*1.2));face(p,'Pout',.5,now)
   if clock>=s.rattleAt then s.rattleAt=clock+MAG.RATTLE;Audio.Play('CartRoll',cart.PrimaryPart);evidence(cp,MAG.NOISE,'cart rattling',cart)end
  end
  if cart and not pulled then stopPull(cart)end
 end,
 clearPlayer=function(_p)end,
 clearLevel=function()table.clear(magnets);stopPull(cartModel())end,
}
table.insert(KEYS,'MagnetNudgeAt')

-- PullbackRacer --------------------------------------------------------------------------------------------
-- Standing still winds it (RacerWind 0..1 over 2 s, ratchet clicks); moving again with wind >= .3 grants a zoom:
-- RacerZoomUntil/Speed/Dir (the holder's client drives the velocity), then RacerDizzyUntil. Checked at 10 Hz.
local RACE={WIND_TIME=2,MIN=.3,STILL=1.5,MOVE=3,SPEED=30,BASE=.45,EXTRA=.8,DIZZY=1.2,CLICK=.4,NOISE=30}
local racers={} -- [Model]={wind=0..1,clickAt=clock}
local function racerTick(now,clock,dt)
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 for m in pairs(racers)do if not m.Parent then racers[m]=nil end end
 if not interactive then return end
 for m,s in pairs(racers)do
  local p=holderOf(m);local r=p and rootOf(p)
  if not r then if(s.wind or 0)>0 then s.wind=0;m:SetAttribute('RacerWind',0)end;continue end
  lease(p,'RacerUntil',now)
  local zooming=now<(p:GetAttribute('RacerZoomUntil')or 0)
  if zooming then continue end
  local v=flatSpeed(r)
  if v<RACE.STILL then
   if s.wind<1 then
    s.wind=math.min(1,s.wind+dt/RACE.WIND_TIME);m:SetAttribute('RacerWind',math.floor(s.wind*100+.5)/100)
    if clock>=(s.clickAt or 0)then s.clickAt=clock+RACE.CLICK;Audio.Play('ClockTick',m)end
   end
  elseif v>RACE.MOVE and s.wind>=RACE.MIN then
   local vel=r.AssemblyLinearVelocity;local dir=Vector3.new(vel.X,0,vel.Z).Unit
   local length=RACE.BASE+RACE.EXTRA*s.wind
   p:SetAttribute('RacerZoomDir',dir);p:SetAttribute('RacerZoomSpeed',RACE.SPEED);p:SetAttribute('RacerZoomStart',now)
   p:SetAttribute('RacerZoomUntil',now+length);p:SetAttribute('RacerDizzyUntil',now+length+RACE.DIZZY)
   face(p,'Pout',length,now);task.delay(length,function()if p.Parent then face(p,'Squint',RACE.DIZZY,workspace:GetServerTimeNow())end end)
   Audio.Play(cue('RacerZoom','HeliumHiss'),m);evidence(r.Position,RACE.NOISE,'toy racer zoom',m)
   s.wind=0;m:SetAttribute('RacerWind',0)
  elseif v>RACE.MOVE and s.wind>0 then s.wind=0;m:SetAttribute('RacerWind',0)
  end
 end
end
ITEMS.PullbackRacer={
 pickup=function(p,m,now)
  local s=racers[m]or{wind=0};racers[m]=s;s.wind=0;m:SetAttribute('RacerWind',0)
  Audio.Play(cue('RacerZoom','HeliumHiss'),m);face(p,'Grin',1.2,now)
  if not m:GetAttribute('RacerTold')then m:SetAttribute('RacerTold',true);notice(p,'Stand still to wind it. Then go!')end
 end,
 tick=function()end,
 clearPlayer=function(_p)end,
 clearLevel=function()table.clear(racers)end,
 debug=function()local list={};for m,s in pairs(racers)do table.insert(list,{model=m:GetFullName(),wind=s.wind})end;return list end,
}
for _,key in ipairs({'RacerUntil','RacerZoomDir','RacerZoomSpeed','RacerZoomStart','RacerZoomUntil','RacerDizzyUntil'})do table.insert(KEYS,key)end

-- Shared lifecycle -----------------------------------------------------------------------------------------
function M.Configure(drop,clear,parts)detach=drop;clearHold=clear;setParts=parts end
function M.Pickup(p,m)
 local item=ITEMS[m:GetAttribute('ItemId')];if not item or not living(p)or not m.PrimaryPart then return end
 local ok,err=pcall(item.pickup,p,m,workspace:GetServerTimeNow())
 if not ok then warn('[ItemBatch9] pickup '..tostring(m:GetAttribute('ItemId'))..': '..tostring(err))end
end
function M.ClearPlayer(p)
 for _,item in pairs(ITEMS)do item.clearPlayer(p)end
 clearLeases(p)
 for _,key in ipairs(KEYS)do p:SetAttribute(key,nil)end
end
function M.ClearLevel()
 for _,item in pairs(ITEMS)do item.clearLevel()end
 for _,p in ipairs(Players:GetPlayers())do M.ClearPlayer(p)end
end
local function lobbyOnly()
 local state=RS:FindFirstChild('LobbyState')
 if not state or state:GetAttribute('Mode')~='Menu'then return false end
 for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('MissionActive')==true then return false end end
 return true
end
local elapsed,fast=0,0
Run.Heartbeat:Connect(function(dt)
 if lobbyOnly()then return end
 fast+=dt
 if fast>=.1 then local ok,err=pcall(racerTick,workspace:GetServerTimeNow(),os.clock(),fast);if not ok then warn('[ItemBatch9] PullbackRacer: '..tostring(err))end;fast=0 end
 elapsed+=dt;if elapsed<TICK then return end
 local step=elapsed;elapsed=0
 local now=workspace:GetServerTimeNow();local clock=os.clock()
 local byId={}
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if interactive then for _,m in ipairs(interactive:GetChildren())do
  local id=m:GetAttribute('ItemId');if id and ITEMS[id]and m.PrimaryPart then byId[id]=byId[id]or{};table.insert(byId[id],m)end
 end end
 for id,item in pairs(ITEMS)do local ok,err=pcall(item.tick,now,byId[id]or{},clock,step);if not ok then warn('[ItemBatch9] '..id..': '..tostring(err))end end
end)
if Run:IsStudio()then
 local old=SS:FindFirstChild('Batch9Test');if old then old:Destroy()end
 local probe=Instance.new('BindableFunction');probe.Name='Batch9Test'
 probe.OnInvoke=function(action)local item=ITEMS[action];return item and item.debug and item.debug()or false end
 probe.Parent=SS
end
Players.PlayerRemoving:Connect(M.ClearPlayer)
return M
