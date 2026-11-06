-- VR-only version of the existing owner. Original source remains untouched.
return function(script, VRSupport)
-- Client half of item batch 3: camera curses for the holder (hourglass flip, spinning top),
-- the lemon squeeze blackout, and the helium puff every player can see. Server leases drive all of it.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local p=Players.LocalPlayer

local HOURGLASS_FLIP_SECONDS=8 -- time held to go fully upside down
local HOURGLASS_RECOVER_SECONDS=1.2
local SPIN_RATE=0 -- degrees per second while holding the top
local HELIUM_PUFF=Vector3.new(1.4,1.12,1.4)
local HELIUM_GROW_SECONDS=6

local function leased(q,key) return workspace:GetServerTimeNow()<(q:GetAttribute(key)or 0) end
local function alive(q) local c=q.Character;local h=c and c:FindFirstChildOfClass('Humanoid');return h and h.Health>0 and q:GetAttribute('MissionActive')==true end

-- Camera roll is removed before the camera module reads the camera (so it never accumulates);
-- the spin is intentionally left in so the camera, and the character with it, keeps turning.
local roll,appliedRoll,rollCamera=0,0,nil
Run:BindToRenderStep('CurseRollReset',Enum.RenderPriority.Camera.Value-2,function()
 if rollCamera and rollCamera==workspace.CurrentCamera and appliedRoll~=0 then rollCamera.CFrame*=CFrame.Angles(0,0,-appliedRoll)end
 appliedRoll=0;rollCamera=nil
end)
Run:BindToRenderStep('CurseCamera',Enum.RenderPriority.Camera.Value+2,function(dt)
 local cam=workspace.CurrentCamera;if not cam then return end
 local live=alive(p)
 if live and leased(p,'SpinUntil')then
  cam.CFrame=CFrame.new(cam.CFrame.Position)*CFrame.Angles(0,SPIN_RATE*dt,0)*cam.CFrame.Rotation
 end
 if live and leased(p,'HourglassUntil')then roll=0
 else roll=math.max(0,roll-math.pi*dt/HOURGLASS_RECOVER_SECONDS)end
 if roll>0 then cam.CFrame*=CFrame.Angles(0,0,roll);appliedRoll=roll;rollCamera=cam end
end)

-- Lemon: the holder's view blacks out in the same waves the eyes squeeze shut.
local gui=Instance.new('ScreenGui');gui.Name='LemonSqueeze';gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=-5;gui.Parent=p:WaitForChild('PlayerGui')
local shade=Instance.new('Frame');shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new(0,0,0);shade.BackgroundTransparency=1;shade.BorderSizePixel=0;shade.Parent=gui

-- Helium: torsos swell like balloons while the tank is held. Each client keeps the true size to restore.
local baseSize={}
local puff={}
Run.Heartbeat:Connect(function(dt)
 local closed=0
 if alive(p)and leased(p,'LemonUntil')then local wave=math.sin(os.clock()*2.4+p.UserId%5)*.5+.5;closed=math.clamp((wave-.3)/.35,0,1)end
 shade.BackgroundTransparency=1-closed*.25
 for _,q in ipairs(Players:GetPlayers())do
  local torso=q.Character and q.Character:FindFirstChild('UpperTorso')
  if torso then
   if not baseSize[torso]then baseSize[torso]=torso.Size;torso.Destroying:Connect(function()baseSize[torso]=nil;puff[torso]=nil end)end
   local target=(alive(q)and leased(q,'HeliumUntil'))and 1 or 0
   local t=puff[torso]or 0
   t=target>t and math.min(1,t+dt/HELIUM_GROW_SECONDS)or math.max(0,t-dt*1.5)
   if t~=(puff[torso]or 0)then
    puff[torso]=t
    local s=(Vector3.one):Lerp(HELIUM_PUFF,t)
    torso.Size=baseSize[torso]*s
   end
  end
 end
end)

end
