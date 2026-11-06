-- Cinematic inspect camera (owner 2026-10-29), shared by the lobby Case Board (StoryClient) and the plaque / Curio card
-- inspect (LobbyInspectClient): glide the camera into first person in front of something, hold it there, glide back.
-- While active: Scriptable camera, the local character hidden on this screen, movement controls paused.
-- Begin / MoveTo / End yield until their glide finishes (call them from a task). Only one session at a time.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local M={}
local p=Players.LocalPlayer
local session -- {saved=CFrame, cameraType, fov, token, owner}
-- Movement pause: this game has no PlayerModule, so the character's root is anchored on this screen only (the
-- player owns it, so it simply stands still) and let go again afterwards.
local frozen
local function freeze(on)
 if on then
  local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
  if r and r:IsA('BasePart')and not r.Anchored then r.AssemblyLinearVelocity=Vector3.zero;r.Anchored=true;frozen=r end
 elseif frozen then
  if frozen.Parent then frozen.Anchored=false end;frozen=nil
 end
end
local function ease(t)return t<.5 and 4*t*t*t or 1-(-2*t+2)^3/2 end
local function hideCharacter(hidden)
 local c=p.Character;if not c then return end
 for _,d in c:GetDescendants()do if d:IsA('BasePart')or d:IsA('Decal')then d.LocalTransparencyModifier=hidden and 1 or 0 end end
end
local function glide(goal,seconds,token)
 local cam=workspace.CurrentCamera;local from=session and session.hold or cam.CFrame;local t=0
 while t<1 do
  t=math.min(1,t+Run.RenderStepped:Wait()/math.max(seconds,.01))
  if not session or session.token~=token then return false end
  session.hold=from:Lerp(goal,ease(t));cam.CFrame=session.hold
 end
 return true
end
-- While a session lives, every frame puts the camera back where the glide left it (other scripts, the camera module
-- and Studio tools all write the camera), keeps the HUD it hid hidden and the character out of view.
local HOLD_STEP='InspectCameraHold'
-- Screens that stay up while inspecting (the inspect UI itself).
local KEEP={StoryCaseFiles=true,StoryNoteReader=true,LobbyInspectBack=true}
-- Your own overhead name / rank tags (BillboardGuis on or adorned to your character, wherever they live) would float
-- right in front of the first-person camera: they are switched off while inspecting. Rescanned twice a second.
local PromptService=game:GetService('ProximityPromptService')
local function ownTag(g)
 local c=p.Character;if not c or not g:IsA('BillboardGui')then return false end
 return g:IsDescendantOf(c)or(g.Adornee~=nil and g.Adornee:IsDescendantOf(c))
end
local function hideTags(s)
 local roots={p.Character,p:FindFirstChild('PlayerGui'),workspace:FindFirstChild('CharacterEntities')}
 for _,root in roots do if root then for _,g in root:GetDescendants()do
  if g:IsA('BillboardGui')and g.Enabled and ownTag(g)then g.Enabled=false;if not table.find(s.tags,g)then table.insert(s.tags,g)end end
 end end end
end
local function holdStep()
 local s=session;local cam=workspace.CurrentCamera;if not s or not cam then return end
 if PromptService.Enabled then PromptService.Enabled=false end -- no interaction prompts over the inspect view
 for _,g in s.tags do if g.Enabled then g.Enabled=false end end
 if os.clock()>=(s.tagScan or 0)then s.tagScan=os.clock()+.5;hideTags(s)end
 if cam.CameraType~=Enum.CameraType.Scriptable then cam.CameraType=Enum.CameraType.Scriptable end
 if s.hold then cam.CFrame=s.hold end
 if cam.FieldOfView~=70 then cam.FieldOfView=70 end
 -- HUD that turns itself back on (or appears) mid-inspect is put away too and comes back with the rest.
 for _,g in p.PlayerGui:GetChildren()do
  if g:IsA('ScreenGui')and g.Enabled and not KEEP[g.Name]then g.Enabled=false;if not table.find(s.hud,g)then table.insert(s.hud,g)end end
 end
 hideCharacter(true)
end
local function restore(s)
 pcall(function()Run:UnbindFromRenderStep(HOLD_STEP)end)
 p:SetAttribute('InspectActive',nil)
 hideCharacter(false)
 for _,g in s.hud do if g.Parent then g.Enabled=true end end
 for _,g in s.tags do if g.Parent then g.Enabled=true end end
 PromptService.Enabled=true
 freeze(false)
end

function M.Active()return session~=nil end
function M.Owner()return session and session.owner end
-- Start (or retarget) a session: glide to `goal`. `owner` is a name so a caller can tell its session from another's.
function M.Begin(goal,seconds,owner)
 if session then return M.MoveTo(goal,seconds)end
 local cam=workspace.CurrentCamera
 session={saved=cam.CFrame,cameraType=cam.CameraType,fov=cam.FieldOfView,token=0,owner=owner,hud={},tags={}}
 PromptService.Enabled=false;hideTags(session)
 cam.CameraType=Enum.CameraType.Scriptable;cam.FieldOfView=70
 p:SetAttribute('InspectActive',true) -- LobbyWorldClient stops forcing its Custom camera while this is set
 hideCharacter(true)
 -- The rest of the HUD steps aside so only the panel and the inspect screens show.
 for _,g in p:WaitForChild('PlayerGui'):GetChildren()do
  if g:IsA('ScreenGui')and g.Enabled and not KEEP[g.Name]then g.Enabled=false;table.insert(session.hud,g)end
 end
 freeze(true)
 session.hold=cam.CFrame
 Run:BindToRenderStep(HOLD_STEP,Enum.RenderPriority.Camera.Value+10,holdStep)
 return M.MoveTo(goal,seconds)
end
function M.MoveTo(goal,seconds)
 if not session then return false end
 session.token+=1
 return glide(goal,seconds or .7,session.token)
end
-- Glide back to where the player was looking and give the camera and controls back.
function M.End(seconds)
 local s=session;if not s then return end
 s.token+=1;local token=s.token
 local ok=glide(s.saved,seconds or .5,token)
 if session~=s or(not ok and session and session.token~=token)then return end
 local cam=workspace.CurrentCamera;cam.CameraType=s.cameraType;cam.FieldOfView=s.fov
 session=nil
 restore(s)
end
-- Drop the session at once (respawn, mission start): no glide.
function M.Cancel()
 local s=session;if not s then return end
 session=nil
 local cam=workspace.CurrentCamera;cam.CameraType=s.cameraType;cam.FieldOfView=s.fov
 restore(s)
end
-- A camera frame that fills the view with a flat panel: `cf` = the panel's CFrame (its Front face is the readable
-- side), `size` = its width / height in studs, `fill` = how much of the screen it may take (0..1).
function M.FrameFor(cf,size,fill)
 local cam=workspace.CurrentCamera;local v=cam and cam.ViewportSize or Vector2.new(1280,720)
 local tanV=math.tan(math.rad(70)/2);local aspect=v.X/math.max(1,v.Y)
 fill=fill or .82
 local d=math.max((size.X/2)/(tanV*aspect*fill),(size.Y/2)/(tanV*fill))
 local front=cf.LookVector
 return CFrame.lookAt(cf.Position+front*d,cf.Position,cf.UpVector)
end
return M
