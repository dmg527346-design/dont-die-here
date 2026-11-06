-- PocketFogger (CursedA 2026-10-27, stealth draft 2026-10-26): grab = a 20-stud fog cloud for 18 s (2 puffs per machine).
-- Inside the cloud monsters only sense what is right next to them (CreatureRoamServer perceive reads FogCoverUntil /
-- FogBlindUntil), but teammates inside are whited out too and a cart in the fog drops off the field map and its beacon
-- (FogLostUntil, FieldMapClient.nearestCart). Driven by ItemBatch6.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Feedback=require(script.Parent:WaitForChild('Feedback'))
local M={}
M.KEYS={}
local TICK,LEASE=.25,.5
local RADIUS,GROW,SECONDS,FADE=20,1.5,18,4
local HEIGHT=12
local CHARGES,COOLDOWN=2,12
local PUFF_LOUDNESS=35
local FOG=Color3.fromRGB(220,232,238)
local clouds={} -- part -> {born,ends} (os.clock)
local machines=setmetatable({},{__mode='k'}) -- m -> {left,readyAt}
local stamps={} -- p -> FogCoverUntil stamp this module wrote
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
local function cloudFolder()
 local f=workspace:FindFirstChild('FogClouds')
 if not f then f=Instance.new('Folder');f.Name='FogClouds';f.Parent=workspace end
 return f
end
local function cover(p,clock)
 local stamp=math.max(p:GetAttribute('FogCoverUntil')or 0,clock+LEASE)
 p:SetAttribute('FogCoverUntil',stamp);stamps[p]=stamp
end
local function uncover(p)
 if stamps[p]and p:GetAttribute('FogCoverUntil')==stamps[p]then p:SetAttribute('FogCoverUntil',nil)end
 stamps[p]=nil
end
local function spawnCloud(pos)
 local part=Instance.new('Part');part.Name='FogCloud';part.Shape=Enum.PartType.Ball;part.Size=Vector3.one*2
 part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false;part.Transparency=1
 part.Position=pos
 local now=workspace:GetServerTimeNow()
 part:SetAttribute('FogRadius',RADIUS*.3);part:SetAttribute('FogBorn',now);part:SetAttribute('FogUntil',now+SECONDS)
 local e=Instance.new('ParticleEmitter');e.Name='Fog'
 e.Texture='rbxasset://textures/particles/smoke_main.dds' -- built-in engine cloud texture: nothing to upload
 e.Color=ColorSequence.new(FOG);e.LightInfluence=1;e.LightEmission=0
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,5),NumberSequenceKeypoint.new(1,11)})
 e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.25,.45),NumberSequenceKeypoint.new(.75,.55),NumberSequenceKeypoint.new(1,1)})
 e.Lifetime=NumberRange.new(3,5);e.Rate=12;e.Speed=NumberRange.new(.4,1.6);e.SpreadAngle=Vector2.new(180,180)
 e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-15,15)
 e.Shape=Enum.ParticleEmitterShape.Sphere;e.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume
 e.Parent=part
 part.Parent=cloudFolder()
 local clock=os.clock();clouds[part]={born=clock,ends=clock+SECONDS}
 return part
end
local function inside(list,pos)
 for _,c in ipairs(list)do
  if Vector3.new(pos.X-c.pos.X,0,pos.Z-c.pos.Z).Magnitude<c.r and math.abs(pos.Y-c.pos.Y)<HEIGHT then return true end
 end
 return false
end
function M.Pickup(p,m)
 if m:GetAttribute('ItemId')~='PocketFogger'then return end
 local c=living(p);local root=c and c:FindFirstChild('HumanoidRootPart')
 if not root or not m.PrimaryPart then return end
 local s=machines[m];if not s then s={left=CHARGES,readyAt=0};machines[m]=s end
 local clock=os.clock();if clock<s.readyAt then return end
 if s.left<=0 then s.readyAt=clock+2;Audio.Play('PerfumeSpray',m);notice(p,'Out of fog juice. It just wheezes.');Feedback.React(p,'FogWheeze','frown',1.5);return end
 s.left-=1;s.readyAt=clock+COOLDOWN;m:SetAttribute('FogCharges',s.left)
 spawnCloud(root.Position)
 Audio.Play('HeliumHiss',m);evidence(root.Position,PUFF_LOUDNESS,'fog machine',p)
 Feedback.React(p,'FogPuff','pucker',2)
 notice(p,if s.left>0 then 'PSHHH! Fog. One puff left.' else 'PSHHH! That was the last puff.')
end
function M.ClearPlayer(p)uncover(p)end
function M.ClearLevel()
 for part in pairs(clouds)do if part.Parent then part:Destroy()end end
 table.clear(clouds)
 for _,p in ipairs(Players:GetPlayers())do uncover(p)end
 for m in pairs(machines)do machines[m]=nil end
 local f=workspace:FindFirstChild('FogClouds');if f then f:ClearAllChildren()end
end
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK then return end;elapsed=0
 if next(clouds)==nil then return end
 local clock=os.clock();local live={}
 for part,c in pairs(clouds)do
  if not part.Parent then clouds[part]=nil
  elseif clock>=c.ends then
   clouds[part]=nil;part:SetAttribute('FogRadius',0)
   local e=part:FindFirstChild('Fog');if e then e.Enabled=false end
   Debris:AddItem(part,FADE)
  else
   local grow=math.clamp((clock-c.born)/GROW,.3,1);local r=RADIUS*grow
   part.Size=Vector3.one*r*2;part:SetAttribute('FogRadius',r)
   local e=part:FindFirstChild('Fog');if e then e.Rate=30*grow*grow end
   table.insert(live,{pos=part.Position,r=r})
  end
 end
 if #live==0 then return end
 for _,p in ipairs(Players:GetPlayers())do
  local c=living(p);local root=c and c:FindFirstChild('HumanoidRootPart')
  if root and inside(live,root.Position)then cover(p,clock)end
 end
 local creatures=workspace:FindFirstChild('RoamingCreatures')
 if creatures then for _,enemy in ipairs(creatures:GetChildren())do
  local primary=enemy:IsA('Model')and enemy.PrimaryPart
  if primary and inside(live,primary.Position)then enemy:SetAttribute('FogBlindUntil',clock+LEASE)end
 end end
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if interactive then
  local serverNow=workspace:GetServerTimeNow()
  for _,cart in ipairs(interactive:GetChildren())do
   if cart:GetAttribute('Kind')=='cart'and cart.PrimaryPart and inside(live,cart.PrimaryPart.Position)then cart:SetAttribute('FogLostUntil',serverNow+LEASE)end
  end
 end
end)
return M
