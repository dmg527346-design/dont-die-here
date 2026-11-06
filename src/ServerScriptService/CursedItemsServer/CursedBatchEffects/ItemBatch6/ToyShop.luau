-- Toy-shop items (CursedA 2026-10-27, draft 2026-10-26): HomesickYoyo. Driven by ItemBatch6.
-- ItemBatch6Client moves the holder along the string (YoyoZipTo/YoyoZipUntil) and shakes cameras
-- (YoyoBonkUntil dizzy wobble, YoyoCaughtUntil jolt).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local Feedback=require(script.Parent:WaitForChild('Feedback'))
local M={}
local TICK=.25
M.KEYS={'YoyoZipTo','YoyoZipUntil','YoyoBonkUntil','YoyoCaughtUntil'}
local ZIP_RANGE=45
local ZIP_MIN=6
local ZIP_SECONDS=1.2
local SLEEP_SECONDS=20
local BONK_SECONDS=2.5
local STRING_COLOR=Color3.fromRGB(245,236,215)
local YOYO_PURPLE=Color3.fromRGB(138,92,245)
local sleepers={}
local zipRay=RaycastParams.new();zipRay.FilterType=Enum.RaycastFilterType.Exclude;zipRay.IgnoreWater=true

local function living(p)
 local c=p and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function notice(p,text)
 local e=RS:FindFirstChild('CursedEvent');if e and p.Parent then e:FireClient(p,'notice',text)end
end
local function hidden(q)return q:GetAttribute('Hiding')or q:GetAttribute('ClosetState')end
local function pickBuddy(p,root)
 local filter={}
 for _,q in ipairs(Players:GetPlayers())do if q.Character then table.insert(filter,q.Character)end end
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if interactive then table.insert(filter,interactive)end
 zipRay.FilterDescendantsInstances=filter -- walls, doors and monsters still block the string
 local best,bestD=nil,ZIP_RANGE
 for _,q in ipairs(Players:GetPlayers())do
  local qc=q~=p and living(q);local qr=qc and qc:FindFirstChild('HumanoidRootPart')
  if qr and not hidden(q)then
   local d=(qr.Position-root.Position).Magnitude
   if d>=ZIP_MIN and d<bestD and not workspace:Raycast(root.Position,qr.Position-root.Position,zipRay)then best,bestD=q,d end
  end
 end
 return best
end
local function zipString(m,qr)
 local a0=Instance.new('Attachment');a0.Name='YoyoStringStart';a0.Parent=m.PrimaryPart
 local a1=Instance.new('Attachment');a1.Name='YoyoStringEnd';a1.Parent=qr
 local b=Instance.new('Beam');b.Name='YoyoString';b.Attachment0=a0;b.Attachment1=a1;b.Color=ColorSequence.new(STRING_COLOR)
 b.Width0=.1;b.Width1=.1;b.FaceCamera=true;b.LightEmission=.4;b.Segments=6;b.Parent=a0
 local bead=Instance.new('Part');bead.Name='YoyoLatch';bead.Shape=Enum.PartType.Ball;bead.Size=Vector3.one*.8;bead.Color=YOYO_PURPLE
 bead.Material=Enum.Material.Neon;bead.CanCollide=false;bead.CanQuery=false;bead.CanTouch=false;bead.Massless=true;bead.CastShadow=false
 bead.CFrame=qr.CFrame*CFrame.new(0,.4,-1.1)
 local w=Instance.new('WeldConstraint');w.Part0=qr;w.Part1=bead;w.Parent=bead;bead.Parent=qr.Parent
 for _,x in ipairs({a0,a1,bead})do Debris:AddItem(x,ZIP_SECONDS+.3)end
end
local function bonkStars(c)
 local head=c:FindFirstChild('Head');if not head then return end
 local a=Instance.new('Attachment');a.Name='YoyoBonkStars';a.Position=Vector3.new(0,head.Size.Y*.7,0);a.Parent=head
 local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds'
 e.Color=ColorSequence.new(Color3.fromRGB(250,210,60),Color3.fromRGB(180,140,255));e.Size=NumberSequence.new(.35,.1)
 e.Lifetime=NumberRange.new(.6,.9);e.Rate=14;e.Speed=NumberRange.new(1.5,2.5);e.SpreadAngle=Vector2.new(10,180)
 e.RotSpeed=NumberRange.new(-200,200);e.LightEmission=.6;e.Parent=a
 Debris:AddItem(a,BONK_SECONDS)
end
local function clearSleep(m)
 sleepers[m]=nil
 local g=m.PrimaryPart and m.PrimaryPart:FindFirstChild('YoyoSleep');if g then g:Destroy()end
end
local function sleep(m,now)
 m:SetAttribute('YoyoSleepUntil',now+SLEEP_SECONDS)
 clearSleep(m)
 local g=Instance.new('BillboardGui');g.Name='YoyoSleep';g.Size=UDim2.fromScale(2.2,1.1);g.StudsOffset=Vector3.new(0,1.6,0)
 g.MaxDistance=40;g.LightInfluence=0;g.ResetOnSpawn=false
 local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,1);t.TextScaled=true;t.Font=Enum.Font.FredokaOne
 t.Text='z Z z';t.TextColor3=Color3.fromRGB(205,185,255);t.TextStrokeTransparency=.3;t.Parent=g
 g.Parent=m.PrimaryPart;sleepers[m]=true
end
local function yoyo(p,m,c)
 local root=c:FindFirstChild('HumanoidRootPart');if not root or not m.PrimaryPart then return end
 local now=workspace:GetServerTimeNow()
 if now<(m:GetAttribute('YoyoSleepUntil')or 0)then Feedback.React(p,'YoyoSleepy','frown',1.2);return end
 local q=pickBuddy(p,root)
 if q then
  local qr=q.Character.HumanoidRootPart
  p:SetAttribute('YoyoZipTo',q.UserId);p:SetAttribute('YoyoZipUntil',now+ZIP_SECONDS)
  q:SetAttribute('YoyoCaughtUntil',now+ZIP_SECONDS+.4)
  zipString(m,qr);Audio.Play('MonsterWhoosh',m.PrimaryPart)
  Feedback.React(p,'YoyoZip','gasp',1.6);Feedback.React(q,'YoyoCaught','gasp',1.6)
  notice(q,'THWIP! '..p.DisplayName.." yo-yo'd over to you.")
  m:SetAttribute('YoyoZips',(m:GetAttribute('YoyoZips')or 0)+1)
 else
  p:SetAttribute('YoyoBonkUntil',now+BONK_SECONDS);bonkStars(c);Audio.Play('PlungerPop',m.PrimaryPart)
  Feedback.React(p,'YoyoBonk','frown',BONK_SECONDS)
  notice(p,'Nobody to go home to. It went around the world and bonked you.')
 end
 sleep(m,now)
end

function M.Pickup(p,m)
 if m:GetAttribute('ItemId')~='HomesickYoyo'then return end
 local c=living(p);if c then yoyo(p,m,c)end
end
function M.ClearPlayer(p)
 for _,key in ipairs(M.KEYS)do p:SetAttribute(key,nil)end
end
function M.ClearLevel()
 for m in pairs(sleepers)do if m.Parent then clearSleep(m)end end
 table.clear(sleepers)
end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<TICK then return end;elapsed=0
 if not next(sleepers)then return end
 local now=workspace:GetServerTimeNow()
 for m in pairs(sleepers)do
  if not m.Parent then sleepers[m]=nil elseif now>=(m:GetAttribute('YoyoSleepUntil')or 0)then clearSleep(m)end
 end
end)
return M
