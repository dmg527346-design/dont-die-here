-- Client half of item batch 3: camera curses for the holder (hourglass flip, spinning top),
-- the lemon squeeze blackout, and the helium puff every player can see. Server leases drive all of it.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local p=Players.LocalPlayer

local HOURGLASS_FLIP_SECONDS=8 -- time held to go fully upside down
local HOURGLASS_RECOVER_SECONDS=1.2
local SPIN_RATE=math.rad(55) -- degrees per second while holding the top
local HELIUM_PUFF=Vector3.new(1.4,1.12,1.4)
local HELIUM_GROW_SECONDS=6

local function leased(q,key) return workspace:GetServerTimeNow()<(q:GetAttribute(key)or 0) end
local function alive(q) local c=q.Character;local h=c and c:FindFirstChildOfClass('Humanoid');return h and h.Health>0 and q:GetAttribute('MissionActive')==true end

-- Camera roll is removed before the camera module reads the camera (so it never accumulates);
-- the spin is intentionally left in so the camera, and the character with it, keeps turning.
local roll,appliedRoll,rollCamera=0,0,nil
-- Stray cat curse (map attribute CatCurse): a hard shake when it starts, then short tremors until the level ends.
local CAT_BURST_ANGLE,CAT_BURST_SECONDS=math.rad(2.4),1.5
local CAT_TREMOR_ANGLE,CAT_TREMOR_SECONDS=math.rad(.8),.8
local CAT_TREMOR_GAP_MIN,CAT_TREMOR_GAP_MAX=6,13
local catOn,catBurstUntil,catTremorAt,catTremorUntil=false,0,0,0
-- Door slam (InteractServer, every 5th level): a hard jolt for everyone, stronger the closer you are, plus a deep
-- (the bang itself is a 3D sound on the door, InteractServer).
local SLAM_ANGLE,SLAM_SECONDS=math.rad(3.2),1.1
local slamAt,slamAmp=0,0
task.spawn(function()
 local thud=Instance.new('Sound');thud.Name='DoorSlamThud';thud.SoundId='rbxassetid://9126090621';thud.Volume=.9;thud.PlaybackSpeed=.8;thud.Parent=game:GetService('SoundService')
 local ev=game:GetService('ReplicatedStorage'):WaitForChild('DoorSlamEvent',30)
 if ev then ev.OnClientEvent:Connect(function(pos)
  local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
  local d=r and typeof(pos)=='Vector3'and(r.Position-pos).Magnitude or 60
  slamAt=os.clock();slamAmp=SLAM_ANGLE*math.clamp(1.2-d/120,.45,1)
 end)end
end)
local appliedShake=nil
Run:BindToRenderStep('CurseRollReset',Enum.RenderPriority.Camera.Value-2,function()
 if rollCamera and rollCamera==workspace.CurrentCamera and appliedRoll~=0 then rollCamera.CFrame*=CFrame.Angles(0,0,-appliedRoll)end
 if appliedShake and rollCamera==workspace.CurrentCamera then rollCamera.CFrame*=appliedShake:Inverse()end
 appliedRoll=0;appliedShake=nil;rollCamera=nil
end)
local function catShake(now)
 local map=workspace:FindFirstChild('Mansion')
 local on=map~=nil and map:GetAttribute('CatCurse')==true and alive(p)
 if on and not catOn then catBurstUntil=now+CAT_BURST_SECONDS;catTremorAt=now+math.random(CAT_TREMOR_GAP_MIN,CAT_TREMOR_GAP_MAX)end
 catOn=on;if not on then return 0 end
 if now>=catTremorAt then catTremorUntil=now+CAT_TREMOR_SECONDS;catTremorAt=now+math.random(CAT_TREMOR_GAP_MIN,CAT_TREMOR_GAP_MAX)end
 if now<catBurstUntil then return CAT_BURST_ANGLE*(catBurstUntil-now)/CAT_BURST_SECONDS end
 if now<catTremorUntil then return CAT_TREMOR_ANGLE*math.sin(math.pi*(catTremorUntil-now)/CAT_TREMOR_SECONDS)end
 return 0
end
Run:BindToRenderStep('CurseCamera',Enum.RenderPriority.Camera.Value+2,function(dt)
 local cam=workspace.CurrentCamera;if not cam then return end
 local live=alive(p)
 if live and leased(p,'SpinUntil')then
  cam.CFrame=CFrame.new(cam.CFrame.Position)*CFrame.Angles(0,SPIN_RATE*dt,0)*cam.CFrame.Rotation
 end
 if live and leased(p,'HourglassUntil')then roll=math.min(math.pi,roll+math.pi*dt/HOURGLASS_FLIP_SECONDS)
 else roll=math.max(0,roll-math.pi*dt/HOURGLASS_RECOVER_SECONDS)end
 if roll>0 then cam.CFrame*=CFrame.Angles(0,0,roll);appliedRoll=roll;rollCamera=cam end
 local now=os.clock();local amp=catShake(now)
 local se=now-slamAt;if se<SLAM_SECONDS then amp=math.max(amp,slamAmp*(1-se/SLAM_SECONDS)^1.5)end
 if amp>0 then
  appliedShake=CFrame.Angles(math.noise(now*19,1)*amp*2,math.noise(now*23,2)*amp*2,math.noise(now*17,3)*amp)
  cam.CFrame*=appliedShake;rollCamera=cam
 end
end)

-- Lemon: the holder's view blacks out in the same waves the eyes squeeze shut.
local gui=Instance.new('ScreenGui');gui.Name='LemonSqueeze';gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.ResetOnSpawn=false;gui.DisplayOrder=-5;gui.Parent=p:WaitForChild('PlayerGui')
local shade=Instance.new('Frame');shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new(0,0,0);shade.BackgroundTransparency=1;shade.BorderSizePixel=0;shade.Parent=gui

-- Helium: torsos swell like balloons while the tank is held. Each client keeps the true size to restore.
local baseSize={}
local puff={}
local jiggle={}
local JELLY_RATE,JELLY_SQUASH,JELLY_GRAB_BOOST=11,.16,2.2
Run.Heartbeat:Connect(function(dt)
 local closed=0
 if alive(p)and leased(p,'LemonUntil')then local wave=math.sin(os.clock()*2.4+p.UserId%5)*.5+.5;closed=math.clamp((wave-.3)/.35,0,1)end
 shade.BackgroundTransparency=1-closed*.92
 for _,q in ipairs(Players:GetPlayers())do
  local torso=q.Character and q.Character:FindFirstChild('UpperTorso')
  if torso then
   if not baseSize[torso]then baseSize[torso]=torso.Size;torso.Destroying:Connect(function()baseSize[torso]=nil;puff[torso]=nil;jiggle[torso]=nil end)end
   local target=(alive(q)and leased(q,'HeliumUntil'))and 1 or 0
   local t=puff[torso]or 0
   t=target>t and math.min(1,t+dt/HELIUM_GROW_SECONDS)or math.max(0,t-dt*1.5)
   -- Wobbly jelly (ItemBatch6 JellyUntil): squash and stretch on top of the helium puff, a big splat after the grab.
   local was=jiggle[torso]or 0
   local jt=(alive(q)and leased(q,'JellyUntil'))and math.min(1,was+dt*4)or math.max(0,was-dt*2.5)
   if t~=(puff[torso]or 0)or jt>0 or was>0 then
    puff[torso]=t;jiggle[torso]=jt
    local s=Vector3.new(1,1,1):Lerp(HELIUM_PUFF,t) -- (Vector3.new: selene misreads Vector3.one:Lerp)
    if jt>0 then
     local root=q.Character:FindFirstChild('HumanoidRootPart')
     local speed=root and Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude or 0
     local age=workspace:GetServerTimeNow()-(q:GetAttribute('FirstFindGrabAt')or 0)
     local boost=q:GetAttribute('FirstFindGrabItem')=='WobbleJelly'and age>=0 and age<2 and JELLY_GRAB_BOOST*math.exp(-age*2.5)or 0
     local w=math.sin(os.clock()*JELLY_RATE+q.UserId%7)*JELLY_SQUASH*jt*(1+math.min(speed/16,1)*.6+boost)
     s*=Vector3.new(1-w*.5,1+w,1-w*.5)
    end
    torso.Size=baseSize[torso]*s
   end
  end
 end
end)

-- Reaction pops (Monsters build 2026-10-27): MonsterBatch, MonsterAbilities and RecoveryRoundServer set ReactPop (text),
-- ReactPopShake (0..1) and ReactPopAt (server time) on a player. A short word pops near the top of that player's screen
-- (1.5 s, never over the middle of the view) with a small camera jolt (off when the player turned camera motion off).
do
 local Prefs=require(game:GetService('ReplicatedStorage'):WaitForChild('HorrorPreferences'))
 local popGui=Instance.new('ScreenGui');popGui.Name='ReactPop';popGui.ResetOnSpawn=false;popGui.DisplayOrder=6;popGui.Parent=p:WaitForChild('PlayerGui')
 local word=Instance.new('TextLabel');word.Name='Word';word.AnchorPoint=Vector2.new(.5,.5);word.Position=UDim2.fromScale(.5,.2);word.Size=UDim2.fromScale(.6,.075)
 word.BackgroundTransparency=1;word.Font=Enum.Font.FredokaOne;word.TextScaled=true;word.TextColor3=Color3.fromRGB(255,236,150)
 word.TextStrokeTransparency=0;word.TextStrokeColor3=Color3.fromRGB(24,14,40);word.Visible=false;word.Parent=popGui
 local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=20;limit.MaxTextSize=52;limit.Parent=word
 local pop=Instance.new('UIScale');pop.Parent=word
 local shownAt=-10
 p:GetAttributeChangedSignal('ReactPopAt'):Connect(function()
  local text=p:GetAttribute('ReactPop');if type(text)~='string'or text==''then return end
  shownAt=os.clock();word.Text=text;word.Visible=true;word.Rotation=math.random(-5,5)
  local shake=math.clamp(tonumber(p:GetAttribute('ReactPopShake'))or 0,0,1)
  local ok,motion=pcall(Prefs.Get,'CameraMotion')
  if shake>0 and(not ok or motion~=false)then slamAt=os.clock();slamAmp=math.rad(2.2)*shake end
 end)
 Run.RenderStepped:Connect(function()
  if not word.Visible then return end
  local age=os.clock()-shownAt
  if age>1.5 then word.Visible=false;return end
  pop.Scale=age<.12 and .3+age/.12*.9 or age<.22 and 1.2-(age-.12)/.1*.2 or 1
  word.TextTransparency=age>1.1 and(age-1.1)/.4 or 0;word.TextStrokeTransparency=word.TextTransparency
 end)
end
-- Item batches 6/7 (CursedA 2026-10-27): faces, screen washes and item renderers live in child ModuleScripts.
task.spawn(function()
 local ok6,b6=pcall(require,script:WaitForChild('ItemBatch6Client'))
 if not ok6 then warn('ItemBatch6Client: '..tostring(b6));b6=nil end
 local m7=script:FindFirstChild('ItemBatch7Client')
 if m7 then local ok7,b7=pcall(require,m7);if ok7 and b7 and b7.Init then b7.Init(b6)elseif not ok7 then warn('ItemBatch7Client: '..tostring(b7))end end
end)
