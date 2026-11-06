local Preferences=require(game.ReplicatedStorage:WaitForChild('HorrorPreferences'))
local missionPlayer=game:GetService('Players').LocalPlayer
while missionPlayer:GetAttribute('MissionActive')~=true do missionPlayer:GetAttributeChangedSignal('MissionActive'):Wait()end
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local CAS=game:GetService('ContextActionService')
local player=Players.LocalPlayer
local event=RS:WaitForChild('MonsterJumpscare')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local current
local function stop(token)
 if not current or token and current.token~=token then return end
 local s=current;current=nil
 if s.render then s.render:Disconnect() end
 if s.gui then s.gui:Destroy() end
 if s.sound then Audio.Stop(s.sound)end
 if s.hitSound then Audio.Stop(s.hitSound)end
 CAS:UnbindAction('MonsterScareMovement')
end
local function start(token,monster,stamp,duration,party)
 stop()
 local char=player.Character
 if not char then return end
 -- A group scare can arrive before the monster has streamed in on this device (phones stream less): it still
 -- plays, as the scare sound and a full-screen card, instead of silently doing nothing.
 local missing=not monster or not monster:IsA('Model')
 if missing and not party then return end
 if missing or not Preferences.Get('Jumpscares')then
  if missing and Preferences.Get('Jumpscares')then Audio.Play('MonsterJumpscare',nil,{duration=duration});Audio.Play('MonsterJumpscareHit',nil,{duration=duration})end
  local quiet=Instance.new('ScreenGui');quiet.Name='QuietCaught';quiet.IgnoreGuiInset=true;quiet.ScreenInsets=Enum.ScreenInsets.None;quiet.ResetOnSpawn=false;quiet.DisplayOrder=10000;quiet.Parent=player.PlayerGui
  local fade=Instance.new('Frame');fade.Size=UDim2.fromScale(1,1);fade.BackgroundColor3=Color3.fromRGB(9,18,22);fade.BorderSizePixel=0;fade.Parent=quiet
  local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Font=Enum.Font.FredokaOne;label.TextSize=28;label.TextColor3=Color3.fromRGB(244,236,210);label.Text=party and(party.nonlethal and'SKITTER HIT'or(party.sourceName..' scared everyone!'))or'YOU WERE CAUGHT';label.Parent=fade
  current={token=token,character=char,gui=quiet};task.delay(duration+1,function()stop(token)end);return
 end
 local gui=Instance.new('ScreenGui');gui.Name='MonsterJumpscare';gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.ResetOnSpawn=false;gui.DisplayOrder=10000;
 local viewport=Instance.new('ViewportFrame');viewport.Name='MonsterFace';viewport.Size=UDim2.fromScale(1,1);viewport.BackgroundColor3=Color3.fromRGB(3,0,5);viewport.BorderSizePixel=0
 viewport.Ambient=Color3.fromRGB(130,100,110);viewport.LightColor=Color3.fromRGB(255,205,210);viewport.LightDirection=Vector3.new(-.3,-.5,-1);viewport.Parent=gui
 local world=Instance.new('WorldModel');world.Parent=viewport
 local old=monster.Archivable;monster.Archivable=true;local clone=monster:Clone();monster.Archivable=old
 local kindName=monster:GetAttribute('CreatureKind')
 local authored=kindName=='Bellhop' or kindName=='Lantern' or kindName=='Neon' or kindName=='Skitter' or kindName=='Mittens' or kindName=='Dancer' or kindName=='Yoyo' -- Blender-built monsters keep their authored colours
 for _,x in clone:GetDescendants() do
  if x:IsA('LuaSourceContainer') or x:IsA('Sound') or x:IsA('ParticleEmitter') or x:IsA('Beam') or x:IsA('Trail') or x:IsA('JointInstance') or x:IsA('WeldConstraint') then x:Destroy()
  elseif x:IsA('BasePart') then x.Anchored=true;x.CanCollide=false;x.CanTouch=false;x.CanQuery=false;if not authored then x.Color=Color3.fromRGB(36,29,38) end end
 end
 clone.Parent=world;clone:PivotTo(CFrame.identity)
 local head=clone:FindFirstChild('Head') or clone:FindFirstChild('Torso')
 local left,right=clone:FindFirstChild('LeftEye'),clone:FindFirstChild('RightEye')
 local torso=clone:FindFirstChild('Torso')
 local eyePos=left and right and (left.Position+right.Position)/2 or head and head.Position or Vector3.zero
 local leftCup,rightCup=clone:FindFirstChild('LeftEyeCup'),clone:FindFirstChild('RightEyeCup')
 local cupPos=leftCup and rightCup and (leftCup.Position+rightCup.Position)/2
 local front=cupPos and eyePos-cupPos or left and -left.CFrame.ZVector or clone:GetPivot().LookVector
 -- Authored monsters swivel their stalk eyes, so face the camera from the body's real forward instead.
 if authored and clone.PrimaryPart then front=clone.PrimaryPart.CFrame.LookVector;viewport.Ambient=Color3.fromRGB(150,146,162) end
 front=Vector3.new(front.X,0,front.Z)
 if front.Magnitude<.001 then front=clone:GetPivot().LookVector else front=front.Unit end
 local focus=head and head.Position:Lerp(eyePos,authored and .38 or .48) or eyePos
 local eyes=left and right and (left.Position-right.Position).Magnitude or 1.5
 local distance=authored and math.max(2.6,eyes*1.75) or math.max(3.4,eyes*2.8)
 local camera=Instance.new('Camera');camera.FieldOfView=58;camera.Parent=viewport;viewport.CurrentCamera=camera;camera.CFrame=CFrame.lookAt(focus+front*distance*1.4,focus);gui.Parent=player:WaitForChild('PlayerGui')
 for _,eye in {left,right} do if eye then eye.Material=Enum.Material.Neon;eye.Color=Color3.fromRGB(238,218,220) end end
 local shade=Instance.new('Frame');shade.Name='DeathFade';shade.BackgroundColor3=Color3.new();shade.BorderSizePixel=0;shade.Size=UDim2.fromScale(1,1);shade.BackgroundTransparency=1;shade.ZIndex=2;shade.Parent=gui
 local sound=Audio.Play('MonsterJumpscare',nil,{duration=duration})
 local hitSound=Audio.Play('MonsterJumpscareHit',nil,{duration=duration})
 local s={token=token,character=char,gui=gui,sound=sound,hitSound=hitSound};current=s
 if party then gui:SetAttribute('SourceUserId',party.sourceUserId);gui:SetAttribute('SourceName',party.sourceName);gui:SetAttribute('PresentationOnly',true)
 else CAS:BindActionAtPriority('MonsterScareMovement',function()return Enum.ContextActionResult.Sink end,false,3000,unpack(Enum.PlayerActions:GetEnumItems()))end
 s.render=Run.RenderStepped:Connect(function()
  local age=workspace:GetServerTimeNow()-stamp
  if player.Character~=char or not char.Parent or age>duration+1 then stop(token);return end
  local rush=1-math.exp(-math.max(age,0)*15)
  local shake=Preferences.Get('CameraMotion') and math.exp(-math.max(age,0)*2)*.025 or 0
  local pos=focus+front*distance*(1.4-.4*rush)+Vector3.new(math.sin(age*59)*shake,math.cos(age*67)*shake,0)
  camera.CFrame=CFrame.lookAt(pos,focus)*CFrame.Angles(0,0,math.sin(age*35)*shake*.5)
  shade.BackgroundTransparency=party and 1 or 1-math.clamp((age-(duration-.2))/.2,0,1)
  if party and age>=duration then stop(token)end
 end)
end
event.OnClientEvent:Connect(function(action,token,monster,stamp,duration,tag)
 if action=='start'then start(token,monster,stamp,duration)
 elseif action=='hit'and not player:GetAttribute('MonsterJumpscareActive')then start(token,monster,stamp,duration,{nonlethal=true,sourceName='Skitter',sourceUserId=0})
 elseif action=='party'and not player:GetAttribute('MonsterJumpscareActive')then start(token,monster,stamp,duration,tag)
 elseif action=='end'then stop(token)end
end)
player.CharacterRemoving:Connect(function()stop()end)

