-- Called by the existing movement owner. Camera-local, bounded and independent of hand/hold transforms.
local Players=game:GetService('Players')
local M={};local sprint,crouch,dread=0,0,0;local blur,grade,gui;local edges={}
local function create()
 local camera=workspace.CurrentCamera;if not camera then return end
 blur=Instance.new('BlurEffect');blur.Name='SprintSoftFocus';blur.Size=0;blur.Enabled=false;blur.Parent=camera
 grade=Instance.new('ColorCorrectionEffect');grade.Name='SprintPostProcessing';grade.Enabled=false;grade.Parent=camera
 gui=Instance.new('ScreenGui');gui.Name='MovementVignette';gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.ResetOnSpawn=false;gui.DisplayOrder=-5;gui.Parent=Players.LocalPlayer:WaitForChild('PlayerGui')
 local shapes={{0,0,1,.23,90},{0,.75,1,.25,-90},{0,0,.23,1,0},{.77,0,.23,1,180}}
 for i,s in shapes do
  local f=Instance.new('Frame');f.Name='SoftEdge'..i;f.BackgroundColor3=Color3.fromRGB(4,9,10);f.BackgroundTransparency=1;f.BorderSizePixel=0;f.Active=false;f.Position=UDim2.fromScale(s[1],s[2]);f.Size=UDim2.fromScale(s[3],s[4]);f.Parent=gui
  local g=Instance.new('UIGradient');g.Rotation=s[5];g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(.45,.65),NumberSequenceKeypoint.new(1,1)});g.Parent=f;edges[i]=f
 end
end
function M.Update(dt,isSprinting,isCrouching,enabled)
 if not blur or not blur.Parent then
  if blur then blur:Destroy()end;if grade then grade:Destroy()end;if gui then gui:Destroy()end;table.clear(edges);blur=nil;grade=nil;gui=nil;create()
 end;if not blur then return end
 local alpha=1-math.exp(-math.min(dt,.1)*8)
 sprint+=((enabled and isSprinting and 1 or 0)-sprint)*alpha;crouch+=((enabled and isCrouching and 1 or 0)-crouch)*alpha
 local camera=workspace.CurrentCamera;if camera then blur.Parent=camera;grade.Parent=camera end
 -- Running: soft focus, punchier grade and a light edge darkening. Crouching: a gentle vignette and a little less colour.
 blur.Size=sprint*3;blur.Enabled=sprint>.01
 grade.Contrast=sprint*.1;grade.Saturation=-sprint*.1-crouch*.12;grade.Brightness=sprint*.02;grade.Enabled=sprint>.01 or crouch>.01
 -- Dread (LevelAmbienceClient.DreadLayer sets DreadLevel 0..1 / DreadKickAt): the edges close in and pulse like a
 -- heartbeat as a monster gets near (about 1-2 beats a second), slam dark when one spots you, colour drains; with
 -- CameraMotion on, a fine smooth tremor during a chase. Nothing flashes.
 local p=Players.LocalPlayer;local t=os.clock()
 dread+=((p:GetAttribute('DreadLevel')or 0)-dread)*(1-math.exp(-math.min(dt,.1)*3))
 local kickAt=p:GetAttribute('DreadKickAt');local kick=kickAt and math.max(0,1-(t-kickAt)/.7)or 0
 local beat=math.max(0,math.sin(t*math.pi*2*(1+1.1*dread)))^4*dread
 grade.Saturation-=dread*.22;grade.Contrast+=dread*.06;grade.Enabled=grade.Enabled or dread>.01
 local edge=math.max(crouch*.55,sprint*.3,dread*.4+beat*.22,kick*.8)
 if enabled and camera and(dread>.3 or kick>0)then
  local amp=math.rad(.1+.3*math.clamp((dread-.3)/.7,0,1)+1.1*kick)
  camera.CFrame*=CFrame.Angles(math.noise(t*8,.31)*amp,math.noise(t*8,7.7)*amp,0)
 end
 gui.Enabled=edge>.01;for _,f in edges do f.BackgroundTransparency=1-edge end
end
return M
