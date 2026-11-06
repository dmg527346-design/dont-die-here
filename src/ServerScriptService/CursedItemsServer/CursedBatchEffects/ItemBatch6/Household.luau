-- Household items (CursedA 2026-10-27, drafts 2026-10-26): HiccupBubbleBath, PopUpToaster.
-- Driven by ItemBatch6 (Pickup / ClearPlayer / ClearLevel). Clients render from the attributes set here
-- (CurseEffectsClient.ItemBatch6Client: bubble float, creature highlights, toast hop, screen pops).
local Players=game:GetService('Players')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Sounds=require(game:GetService('ReplicatedStorage'):WaitForChild('GameplaySoundCatalog'))
local Feedback=require(script.Parent:WaitForChild('Feedback'))
local M={}
local TICK=.25
M.KEYS={'BubbledUntil','BubbleBornAt','BubblePoppedBy','ToastPopAt'}

-- [HiccupBubbleBath]
local TAG_EVERY,TAG_RADIUS,TAG_SECONDS=3,45,3.6
local HICCUP_FIRST,HICCUP_EVERY=8,14
local SMALL_HIC_EVERY=4.5 -- little hiccups (hop + hic, no bubble) between the big ones
local BUBBLE_SECONDS,BUBBLE_GRACE,BUBBLE_POP_REACH,BUBBLE_SIZE=4,.8,5.5,7
local SOAP=Color3.fromRGB(190,232,255)
local baths={} -- model -> {nextTag,nextHiccup,nextSmall} (os.clock)
local bubbles={} -- player -> bubble Part
-- [PopUpToaster]
local TOAST_FIRST,TOAST_EVERY=3,7
local TOAST_POP_RADIUS=9
local TOAST_STARTLE_RADIUS=10
local TOAST_STUN,TOAST_FLEE,TOAST_STARTLE_COOLDOWN=1.2,3,10 -- os.clock seconds (CreatureRoamServer time)
local TOAST_LOUDNESS=36
local TOAST_COLOR=Color3.fromRGB(221,188,128)
local toasters={} -- model -> {nextPop}
local startled={} -- creature -> os.clock when it can be startled again

local function living(p)
 local c=p and p.Parent and p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if h and h.Health>0 and p:GetAttribute('MissionActive')==true then return c end
 return nil
end
local function creatures()
 local f=workspace:FindFirstChild('RoamingCreatures');return f and f:GetChildren()or {}
end
local function cue(a,b)return Sounds[a]and a or b end
local function sheltered(p)return p:GetAttribute('Hiding')==true or p:GetAttribute('ClosetState')~=nil or p:GetAttribute('ChoiceDeciding')==true end
local function evidence(pos,loudness,label,source)
 local bus=SS:FindFirstChild('MonsterEvidence');if bus then bus:Fire(pos,loudness,label,source)end
end

-- [HiccupBubbleBath] -------------------------------------------------------------------------------------------
local function foam(m,on)
 local root=m.PrimaryPart;if not root then return end
 local e=root:FindFirstChild('BathFoam')
 if not e and on then
  e=Instance.new('ParticleEmitter');e.Name='BathFoam';e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(SOAP,Color3.fromRGB(235,215,255))
  e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(1,.45)});e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,1)})
  e.Lifetime=NumberRange.new(1.2,2);e.Rate=6;e.Speed=NumberRange.new(1,2.5);e.SpreadAngle=Vector2.new(35,35);e.Acceleration=Vector3.new(0,1.5,0);e.LightEmission=.3;e.Parent=root
 end
 if e then e.Enabled=on end
end
local function splash(pos,count)
 local a=Instance.new('Attachment');a.WorldPosition=pos;a.Parent=workspace.Terrain
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(SOAP)
 e.Size=NumberSequence.new(.35,.1);e.Lifetime=NumberRange.new(.6,1.1);e.Speed=NumberRange.new(10,18);e.SpreadAngle=Vector2.new(180,180);e.Acceleration=Vector3.new(0,-20,0);e.Drag=2;e.Rate=0;e.Parent=a
 e:Emit(count or 40);Debris:AddItem(a,1.5)
end
-- A few soap bubbles out of the holder's mouth on every hiccup.
local function hicBubbles(c)
 local head=c:FindFirstChild('Head');if not head then return end
 local a=Instance.new('Attachment');a.Name='HiccupPuff';a.Position=Vector3.new(0,.3,-head.Size.Z*.5);a.Parent=head
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.Color=ColorSequence.new(SOAP,Color3.fromRGB(235,215,255))
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,.55)});e.Transparency=NumberSequence.new(.15,1)
 e.Lifetime=NumberRange.new(1,1.6);e.Speed=NumberRange.new(2,4);e.SpreadAngle=Vector2.new(30,30);e.EmissionDirection=Enum.NormalId.Front
 e.Acceleration=Vector3.new(0,2,0);e.Rate=0;e.Parent=a
 e:Emit(8);Debris:AddItem(a,2)
end
local function popBubble(p,by,quiet)
 local b=bubbles[p];bubbles[p]=nil
 p:SetAttribute('BubbledUntil',nil);p:SetAttribute('BubbleBornAt',nil)
 if not quiet then p:SetAttribute('BubblePoppedBy',by and by.UserId or 0)end
 if b and b.Parent then
  if not quiet then
   Audio.Play('BalloonPop',b);splash(b.Position)
   Feedback.React(p,'BubblePop','grin',1.5)
   if by then Feedback.React(by,'BubblePop','grin',1.5)end
  end
  b:Destroy()
 end
end
local function hiccup(p,c,m)
 local hr=c:FindFirstChild('HumanoidRootPart');if not hr or bubbles[p]then return end
 local now=workspace:GetServerTimeNow()
 p:SetAttribute('BubbleBornAt',now);p:SetAttribute('BubbledUntil',now+BUBBLE_SECONDS);p:SetAttribute('BubblePoppedBy',nil)
 local b=Instance.new('Part');b.Name='HiccupBubble';b.Shape=Enum.PartType.Ball;b.Size=Vector3.one*BUBBLE_SIZE
 b.Material=Enum.Material.Glass;b.Color=SOAP;b.Transparency=.6;b.Reflectance=.25
 b.CanCollide=false;b.CanQuery=false;b.CanTouch=false;b.Massless=true;b.CastShadow=false
 local w=Instance.new('Weld');w.Name='HiccupBubbleWeld';w.Part0=hr;w.Part1=b;w.C0=CFrame.new(0,.4,0);w.Parent=b
 b.Parent=c;bubbles[p]=b
 Audio.Play(cue('BubbleHiccup','JarPop'),hr);hicBubbles(c)
 Feedback.React(p,'Hiccup','gasp',BUBBLE_SECONDS)
 m:SetAttribute('Hiccups',(m:GetAttribute('Hiccups')or 0)+1)
end
local function smallHic(p,c,m)
 local hr=c:FindFirstChild('HumanoidRootPart');if not hr or bubbles[p]then return end
 Audio.Play(cue('BubbleHiccup','JarPop'),hr);hicBubbles(c)
 Feedback.React(p,'HicSmall','gasp',.7)
 m:SetAttribute('SmallHiccups',(m:GetAttribute('SmallHiccups')or 0)+1)
end

-- [PopUpToaster] -----------------------------------------------------------------------------------------------
local function toastSlices(root)
 local parent=workspace:FindFirstChild('Mansion')or workspace
 for i=-1,1,2 do
  local s=Instance.new('Part');s.Name='ToastSlice';s.Size=Vector3.new(.8,.7,.12);s.Color=TOAST_COLOR;s.Material=Enum.Material.SmoothPlastic
  s.CanQuery=false;s.CanTouch=false;s.Massless=true;s.CastShadow=false
  s.CFrame=CFrame.new(root.Position+Vector3.new(0,root.Size.Y*.5+.45,i*.2))*CFrame.Angles(0,math.random()*math.pi,0)
  s.Parent=parent
  s.AssemblyLinearVelocity=Vector3.new(math.random(-40,40)/10,26+math.random(0,6),i*3)
  s.AssemblyAngularVelocity=Vector3.new(math.random(-8,8),math.random(-4,4),math.random(-8,8))
  Debris:AddItem(s,4)
 end
end
local function toastPop(m,p,c)
 local root=m.PrimaryPart;local hr=c:FindFirstChild('HumanoidRootPart');if not root or not hr then return end
 local now=workspace:GetServerTimeNow();local clock=os.clock()
 Audio.Play(cue('ToasterDing','DinnerBell'),root);Audio.Play('JarPop',root);toastSlices(root)
 m:SetAttribute('ToastPops',(m:GetAttribute('ToastPops')or 0)+1)
 for _,q in ipairs(Players:GetPlayers())do
  local qc=living(q);local qr=qc and qc:FindFirstChild('HumanoidRootPart')
  if qr and not sheltered(q)and(q==p or(qr.Position-hr.Position).Magnitude<=TOAST_POP_RADIUS)then
   q:SetAttribute('ToastPopAt',now);Feedback.React(q,'ToastDing','gasp',1.6)
  end
 end
 for _,n in ipairs(creatures())do
  local pp=n.PrimaryPart
  if pp and clock>=(startled[n]or 0)and(pp.Position-root.Position).Magnitude<=TOAST_STARTLE_RADIUS then
   startled[n]=clock+TOAST_STARTLE_COOLDOWN
   n:SetAttribute('StunnedUntil',math.max(n:GetAttribute('StunnedUntil')or 0,clock+TOAST_STUN))
   n:SetAttribute('FleeUntil',math.max(n:GetAttribute('FleeUntil')or 0,clock+TOAST_STUN+TOAST_FLEE))
  end
 end
 evidence(root.Position,TOAST_LOUDNESS,'toaster ding',m)
end

function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId')
 if not living(p)then return end
 local clock=os.clock()
 -- Re-grabbing restarts the countdowns: neither the bubble nor the ding can be fired on demand.
 if id=='HiccupBubbleBath'then baths[m]={nextTag=clock,nextHiccup=clock+HICCUP_FIRST,nextSmall=clock+2};Feedback.React(p,'BathGrab','grin',1.2)
 elseif id=='PopUpToaster'then toasters[m]={nextPop=clock+TOAST_FIRST};Feedback.React(p,'ToastGrab','frown',1.2)
 end
end
function M.ClearPlayer(p)
 popBubble(p,nil,true)
 for _,k in ipairs(M.KEYS)do p:SetAttribute(k,nil)end
end
function M.ClearLevel()
 table.clear(baths);table.clear(bubbles);table.clear(toasters);table.clear(startled)
end
Players.PlayerRemoving:Connect(function(p)local b=bubbles[p];if b then b:Destroy()end;bubbles[p]=nil end)

local acc=0
Run.Heartbeat:Connect(function(dt)
 acc+=dt;if acc<TICK then return end;acc=0
 local now=workspace:GetServerTimeNow();local clock=os.clock()
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if interactive then
  for _,m in ipairs(interactive:GetChildren())do
   local id=m:GetAttribute('ItemId')
   if id=='HiccupBubbleBath'and m.PrimaryPart then
    local p=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0);local c=p and living(p)
    if c then
     local s=baths[m];if not s then s={nextTag=clock,nextHiccup=clock+HICCUP_FIRST,nextSmall=clock+2};baths[m]=s end
     foam(m,true)
     if clock>=s.nextTag then
      s.nextTag=clock+TAG_EVERY;local tagged=0
      for _,n in ipairs(creatures())do
       local pp=n.PrimaryPart
       if pp and(pp.Position-m.PrimaryPart.Position).Magnitude<=TAG_RADIUS then n:SetAttribute('BubbleTagUntil',now+TAG_SECONDS);tagged+=1 end
      end
      if tagged>0 then m:SetAttribute('BubbleTags',(m:GetAttribute('BubbleTags')or 0)+tagged)end
     end
     if clock>=s.nextHiccup then s.nextHiccup=clock+HICCUP_EVERY;s.nextSmall=clock+BUBBLE_SECONDS+SMALL_HIC_EVERY;hiccup(p,c,m)
     elseif clock>=s.nextSmall and s.nextHiccup-clock>2 then s.nextSmall=clock+SMALL_HIC_EVERY;smallHic(p,c,m)end
    else baths[m]=nil;foam(m,false)end
   elseif id=='PopUpToaster'then
    local p=Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0);local c=p and living(p)
    if c then
     local s=toasters[m];if not s then s={nextPop=clock+TOAST_FIRST};toasters[m]=s end
     if clock>=s.nextPop then s.nextPop=clock+TOAST_EVERY;toastPop(m,p,c)end
    else toasters[m]=nil end
   end
  end
 end
 for m in pairs(baths)do if not m.Parent then baths[m]=nil end end
 for m in pairs(toasters)do if not m.Parent then toasters[m]=nil end end
 for n in pairs(startled)do if not n.Parent then startled[n]=nil end end
 -- Bubbles: a teammate walking into one pops it (after a short grace); otherwise it pops itself.
 for p,b in pairs(bubbles)do
  local c=living(p);local hr=c and c:FindFirstChild('HumanoidRootPart')
  if not hr or not b.Parent or now>=(p:GetAttribute('BubbledUntil')or 0)then popBubble(p,nil,not hr)
  elseif now-(p:GetAttribute('BubbleBornAt')or now)>=BUBBLE_GRACE then
   for _,q in ipairs(Players:GetPlayers())do
    local qc=q~=p and living(q);local qr=qc and qc:FindFirstChild('HumanoidRootPart')
    if qr and(qr.Position-hr.Position).Magnitude<=BUBBLE_POP_REACH then popBubble(p,q);break end
   end
  end
 end
end)
return M
