local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local Preferences=require(game.ReplicatedStorage:WaitForChild('HorrorPreferences'))
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local CAS=game:GetService('ContextActionService')
local UIS=game:GetService('UserInputService')
local Debris=game:GetService('Debris')
local GameplayAudio=require(RS:WaitForChild('GameplayAudio'))
local SoundCatalog=GameplayAudio.Catalog
local p=Players.LocalPlayer
local playback=Instance.new('Folder');playback.Name='CursedPlayback';playback.Parent=game:GetService('SoundService')
local output=Instance.new('AudioDeviceOutput');output.Name='CursedOutput';output.Player=p;output.Parent=playback
local voiceMix=Instance.new('AudioFader');voiceMix.Name='CursedPreferenceMix';voiceMix.Parent=playback
local mixWire=Instance.new('Wire');mixWire.SourceInstance=voiceMix;mixWire.TargetInstance=output;mixWire.Parent=playback
local function updateVoiceMix()voiceMix.Volume=Preferences.Get('VoiceEffects') and Preferences.Get('MasterVolume')*Preferences.Get('EffectsVolume') or 0 end
updateVoiceMix();p.AttributeChanged:Connect(function(key)if key:find('Setting',1,true)then updateVoiceMix()end end)
local listener,listenerWire
local function listen()
 if listener then listener:Destroy() end;if listenerWire then listenerWire:Destroy() end
 if not workspace.CurrentCamera then return end
 listener=Instance.new('AudioListener');listener.Name='CursedListener';listener.AudioInteractionGroup='CursedAudio';listener.Parent=workspace.CurrentCamera
 listenerWire=Instance.new('Wire');listenerWire.SourceInstance=listener;listenerWire.TargetInstance=voiceMix;listenerWire.Parent=playback
end
workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(listen);listen()
local e=RS:WaitForChild('CursedEvent')
local C=require(RS:WaitForChild('CursedCatalog'))
local map=workspace:WaitForChild('Mansion',math.huge);while map:GetAttribute('Ready')~=true or map:GetAttribute('RuntimeReady')~=true do map:GetAttributeChangedSignal('RuntimeReady'):Wait() end
local function itemModels()
 local list={}
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 local current=RS:FindFirstChild('LobbyState')
 if (not current or current:GetAttribute('Mode')~='Menu') and interactive then for _,m in ipairs(interactive:GetChildren())do table.insert(list,m)end end
 local state=RS:FindFirstChild('LobbyState');local world=workspace:FindFirstChild('LobbyWorld');local toys=world and world:FindFirstChild('Toys');local runtime=toys and toys:FindFirstChild('RuntimeToys')
 if state and state:GetAttribute('Mode')=='Menu' and runtime then for _,m in ipairs(runtime:GetChildren())do if m:GetAttribute('LobbyToy')==true then table.insert(list,m)end end end
 return list
end
local held={};local noticeUntil=0;local notice='';local valuables=0
local shoeTugUntil=0;local shoeTugTarget
local gui=Instance.new('ScreenGui');gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Name='CursedHud';gui.ResetOnSpawn=false;gui.Parent=p:WaitForChild('PlayerGui')
local label=Instance.new('TextLabel');label.Name='CarryStatus';label.AnchorPoint=Vector2.new(.5,1);label.Position=UDim2.new(.5,0,1,-74);label.Size=UDim2.new(.85,0,0,64);label.BackgroundTransparency=1;label.TextColor3=Color3.fromRGB(244,226,192);label.TextStrokeTransparency=1;label.TextSize=16;label.Font=Enum.Font.Gotham;label.TextWrapped=true;label.Parent=gui
local shade=Instance.new('Frame');shade.Name='TeddyArms';shade.Size=UDim2.new(1,0,.35,0);shade.BackgroundColor3=Color3.fromRGB(32,20,12);shade.BackgroundTransparency=1;shade.BorderSizePixel=0;shade.Parent=gui
local actions={Drop={action='drop',title='DROP',key=Enum.KeyCode.G,pad=Enum.KeyCode.DPadDown},Swap={action='swap',title='SWAP',key=Enum.KeyCode.Q,pad=Enum.KeyCode.DPadRight},Bank={action='bank',title='BANK',key=Enum.KeyCode.Z,pad=Enum.KeyCode.ButtonL2}}
for name,a in pairs(actions) do
 CAS:BindAction('Cursed'..name,function(_,state)if #held==0 or UIS:GetFocusedTextBox() or game:GetService('Players').LocalPlayer:GetAttribute('MapOpen') then return Enum.ContextActionResult.Pass end;if state==Enum.UserInputState.Begin then e:FireServer(a.action) end;return Enum.ContextActionResult.Sink end,false,a.key,a.pad)
 -- Item actions have no separate touch-button panel.
end
local function temporaryPart(name,pos,size,color,life)
 local x=Instance.new('Part');x.Name=name;x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.Size=size;x.Color=color;x.Material=Enum.Material.SmoothPlastic;x.CFrame=CFrame.new(pos);x.Parent=workspace;Debris:AddItem(x,life);return x
end
local function audio(pos,text)
 -- A bounded, shared TTS effect is used for calls. Noise remains server-authoritative.
 local a=temporaryPart('CursedAudio',pos,Vector3.one,Color3.new(),12);a.Transparency=1
 if not Preferences.Get('VoiceEffects')then a:Destroy();return end
 local t=Instance.new('AudioTextToSpeech');t.Text=text:sub(1,180);t.VoiceId='3';t.Volume=.25;t.Parent=a
 local emitter=Instance.new('AudioEmitter');emitter.AudioInteractionGroup='CursedAudio';emitter:SetDistanceAttenuation({[0]=1,[10]=.7,[40]=0});emitter.Parent=a
 local wire=Instance.new('Wire');wire.SourceInstance=t;wire.TargetInstance=emitter;wire.Parent=a
 task.spawn(function()pcall(function()t:LoadAsync();t:Play()end)end)
end
local alarmSounds=setmetatable({},{__mode='k'})
e.OnClientEvent:Connect(function(action,a,b,c)
 if action=='inventory' then if #held>0 and #a==#held and a[1] and held[1].model~=a[1].model then GameplayAudio.Play('ClothHandle')end;held=a;valuables=b or 0
 elseif action=='notice' then notice=a;noticeUntil=os.clock()+6;if a:find('hands are full') or a:find('will not let go') or a:find('Need ') then GameplayAudio.Play('UiError')end
 elseif action=='apparition' then GameplayAudio.Play('MonsterSearch',a);local x=temporaryPart('FalseFigure',a+Vector3.new(0,2,0),Vector3.new(1.7,4.5,.6),Color3.fromRGB(15,12,18),1.3);x.Transparency=.25
 elseif action=='frosting' then local x=temporaryPart('FrostingTrail',a-Vector3.new(0,2.9,0),Vector3.new(.7,.035,.9),Color3.fromRGB(203,123,151),18);x.Transparency=.2
 elseif action=='present' and b and c==p then notice='Something crawled out of the present.';noticeUntil=os.clock()+6
 elseif action=='speech' then audio(a,b)
 elseif action=='clockSmashed'or action=='clockQuiet'then
  if alarmSounds[a]then GameplayAudio.Stop(alarmSounds[a]);alarmSounds[a]=nil end
  if action=='clockSmashed'then GameplayAudio.Play('ItemImpact',a and a.PrimaryPart)end
 elseif action=='noise' then
  local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart');if r and (r.Position-a).Magnitude<60 then
   noticeUntil=math.max(noticeUntil,os.clock()+1.6);notice='['..b..']'
   local cue=SoundCatalog.NoiseCue(b,c);if cue then
    if b=='alarm ringing'and c and not c:GetAttribute('ClockBroken')then
     if alarmSounds[c]then GameplayAudio.Stop(alarmSounds[c])end
     alarmSounds[c]=GameplayAudio.Play(cue,c.PrimaryPart)
    elseif b~='alarm ringing'then GameplayAudio.Play(cue,a)end
   end
  end
 elseif action=='dance' then local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if h then h:Move(Vector3.new(math.sin(os.clock()*5),0,math.cos(os.clock()*5)));notice='The shoes are dancing. Interact to resist!';noticeUntil=os.clock()+1 end
 elseif action=='shoeTug' then shoeTugTarget=a;shoeTugUntil=os.clock()+.65;notice='The vacuum grabbed your shoe!';noticeUntil=os.clock()+3
 end
end)
e:FireServer('sync')
local function carryView(camera)
 local state=RS:FindFirstChild('LobbyState');local head=p.Character and p.Character:FindFirstChild('Head')
 if p:GetAttribute('MissionActive')~=true and p:GetAttribute('LobbyReady')==true and state and state:GetAttribute('Mode')=='Menu' and head then
  local direction=camera.CFrame.LookVector
  if InputHints.Get()=='kb' then local mouse=UIS:GetMouseLocation();local ray=camera:ScreenPointToRay(mouse.X,mouse.Y);local target=ray.Origin+ray.Direction*100;direction=(target-head.Position).Unit end
  return CFrame.lookAt(head.Position,head.Position+direction)
 end
 return camera.CFrame
end
local elapsed=0
Run.RenderStepped:Connect(function(dt)
 local camera=workspace.CurrentCamera;if not camera then return end;elapsed+=dt;if elapsed>1/60 and #held>0 then elapsed=0;e:FireServer('aim',carryView(camera)) end
 local active=held[1];local text=''
 if active and active.model.Parent then
  text=active.name..'  ['..#held..' items]'..(active.model:GetAttribute('LobbyToy')==true and '' or '  Loot '..valuables)
  local id=active.id;local m=active.model
  if id=='Compass' or id=='Portrait' then local target=m:GetAttribute('PointerTarget');if target then local localDir=camera.CFrame:VectorToObjectSpace(target-camera.CFrame.Position);text..='   '..(math.abs(localDir.X)<5 and 'AHEAD' or localDir.X>0 and 'RIGHT' or 'LEFT')..(m:GetAttribute('NeedleShake') and ' - needle shaking' or '') end
  elseif id=='Clock' then text..=(m:GetAttribute('ClockBroken')and '   SMASHED - SILENT' or '   A fall from height smashes and silences it')
  elseif id=='Cake' then text..='   Intact '..math.floor(100-(m:GetAttribute('CurseMeter') or 0))..'%'
  elseif id=='Jawbone' and m:GetAttribute('SecretNear') then text..='   SECRET NEARBY' end

 end
 if os.clock()<noticeUntil then text=notice..'\n'..text end;label.Text=text
 local obscure=p:GetAttribute('TeddyObscure') or 0;shade.BackgroundTransparency=1-obscure*.7
 local reveal=false;for _,item in ipairs(held) do if (item.id=='Flashlight' or item.id=='Candles' or item.id=='Lantern') and item.model:GetAttribute('SecretLight') then reveal=true end end
 local bridge=map:FindFirstChild('HiddenBridge');if bridge then for _,tile in ipairs(bridge:GetChildren()) do tile.Transparency=reveal and .3 or 1 end end
 local secrets=map:FindFirstChild('CursedSecrets');if secrets then for _,secret in ipairs(secrets:GetChildren()) do
  -- only on your own floor (floors are 16 studs apart): a secret right above you is not 'near'
  local me=p.Character and p.Character:FindFirstChild('HumanoidRootPart');local sameFloor=me and math.floor(me.Position.Y/16)==math.floor((secret.Position.Y+1)/16)
  local show=reveal and sameFloor and (secret.Position-camera.CFrame.Position).Magnitude<35;secret.LocalTransparencyModifier=show and 0 or 1
  local sign=secret:FindFirstChild('SecretLabel');if not sign then sign=Instance.new('BillboardGui');sign.Name='SecretLabel';sign.Size=UDim2.fromOffset(220,36);sign.AlwaysOnTop=true;sign.Parent=secret;local l=Instance.new('TextLabel');l.Size=UDim2.fromScale(1,1);l.BackgroundTransparency=1;l.TextColor3=Color3.fromRGB(165,222,193);l.Font=Enum.Font.GothamBold;l.TextSize=14;l.Text=secret:GetAttribute('SecretText');l.Parent=sign end;sign.Enabled=show and not secret:GetAttribute('Claimed')
 end end
end)

local visuals={}
local disguises={}
local disguiseVisibility={}
local linked={}
local tracks={};local trackTick=0

local footstepVolumes=setmetatable({},{__mode='k'})
local function visual(name,size,color)
 local x=temporaryPart(name,Vector3.zero,size,color,1000000);return x
end
local hornParams=RaycastParams.new();hornParams.FilterType=Enum.RaycastFilterType.Exclude;hornParams.RespectCanCollide=true
Run.RenderStepped:Connect(function(dt)
 local now=os.clock();local camera=workspace.CurrentCamera;if not camera then return end
 local revealing=false;for _,item in ipairs(held) do if item.id=='Flashlight' and item.model:GetAttribute('SecretLight') then revealing=true end end
 local creatures=workspace:FindFirstChild('RoamingCreatures');if p:GetAttribute('MissionActive')==true and creatures and now-trackTick>.8 then trackTick=now;local stamped=0;for _,monster in ipairs(creatures:GetChildren()) do if monster.PrimaryPart then local pos=monster.PrimaryPart.Position;if (pos-camera.CFrame.Position).Magnitude>70 or stamped>=6 then continue end;stamped+=1;local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={map.Collision};local hit=workspace:Raycast(pos+Vector3.new(0,3,0),Vector3.new(0,-12,0),params);if hit then local mark=temporaryPart('HiddenMonsterFootprint',hit.Position+Vector3.new(0,.025,0),Vector3.new(.35,.035,.8),Color3.fromRGB(125,174,145),24);mark.Transparency=1;table.insert(tracks,mark) end end end end
 for i=#tracks,1,-1 do local mark=tracks[i];if not mark.Parent then table.remove(tracks,i) else mark.Transparency=revealing and .3 or 1 end end
 local char=p.Character;local h=char and char:FindFirstChildOfClass('Humanoid')
 local r=char and char:FindFirstChild('HumanoidRootPart')
 if r and h and not r.Anchored and now<shoeTugUntil and shoeTugTarget then local d=shoeTugTarget-r.Position;d=Vector3.new(d.X,0,d.Z);if d.Magnitude>.5 then h:Move(d.Unit,false);local v=r.AssemblyLinearVelocity;local pull=d.Unit*8;r.AssemblyLinearVelocity=Vector3.new(pull.X,v.Y,pull.Z) end end
 if h and (p:GetAttribute('DancingUntil') or 0)>workspace:GetServerTimeNow() then h:Move(Vector3.new(math.sin(now*5),0,math.cos(now*5)),false) end
 if char then for _,x in ipairs(char:GetDescendants()) do if x:IsA('Sound') and x.Name=='Running' then if footstepVolumes[x]==nil then footstepVolumes[x]=x.Volume end;x.Volume=p:GetAttribute('QuietSteps') and footstepVolumes[x]*.08 or footstepVolumes[x] end end end
 for _,q in ipairs(Players:GetPlayers()) do
  if q~=p and q.Character then
   local active=q:GetAttribute('BorrowedFaceActive');local ghost=disguises[q]
   if active and not ghost then
    local creatures=workspace:FindFirstChild('RoamingCreatures');local template=creatures and creatures:GetChildren()[1]
    if template then ghost=template:Clone();for _,x in ipairs(ghost:GetDescendants()) do if x:IsA('LuaSourceContainer') or x:IsA('Sound') or x:IsA('Humanoid') then x:Destroy() elseif x:IsA('BasePart') then x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false end end;ghost.Name='BorrowedMonsterFace';ghost.Parent=workspace;disguises[q]=ghost end
   end
   local hidden=active and ghost~=nil or false;local previous=disguiseVisibility[q]
   if not previous or previous.char~=q.Character or previous.hidden~=hidden then for _,x in ipairs(q.Character:GetDescendants()) do if x:IsA('BasePart') then x.LocalTransparencyModifier=hidden and 1 or 0 end end;disguiseVisibility[q]={char=q.Character,hidden=hidden} end
   local r=q.Character:FindFirstChild('HumanoidRootPart');if ghost and r then ghost:PivotTo(r.CFrame) end
   if not active and ghost then ghost:Destroy();disguises[q]=nil end
   local isPartner=p:GetAttribute('BraceletPartner')==q.UserId
   if isPartner and not linked[q] then local hi=Instance.new('Highlight');hi.Name='BraceletSense';hi.Adornee=q.Character;hi.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;hi.FillColor=Color3.fromRGB(189,129,221);hi.FillTransparency=.8;hi.OutlineTransparency=.15;hi.Parent=gui;linked[q]=hi end
   if linked[q] then linked[q].Adornee=q.Character;linked[q].Enabled=isPartner end
  end
 end
 for q,ghost in pairs(disguises) do if not q.Parent or not q.Character then ghost:Destroy();disguises[q]=nil;disguiseVisibility[q]=nil end end
 for q,hi in pairs(linked) do if not q.Parent then hi:Destroy();linked[q]=nil end end
 for _,m in ipairs(itemModels()) do
  local id=m:GetAttribute('ItemId');local r=m:IsA('Model') and m.PrimaryPart
  if r and id then
   local target=m:GetAttribute('PointerTarget')
   for _,motor in ipairs(r:GetChildren()) do if motor:IsA('Motor6D') and motor.Name:sub(1,12)=='CurseMotion_' then
    if id=='Compass' and target then local d=r.CFrame:VectorToObjectSpace(target-r.Position);motor.Transform=CFrame.Angles(0,math.atan2(-d.X,-d.Z)+(m:GetAttribute('NeedleShake') and math.sin(now*35)*.3 or 0),0)
    elseif id=='Portrait' and target then local d=r.CFrame:VectorToObjectSpace(target-r.Position);motor.Transform=CFrame.new(math.clamp(d.X*.006,-.075,.075),math.clamp(d.Y*.006,-.04,.04),0)
    elseif id=='Teddy' then local owner=Players:GetPlayerByUserId(m:GetAttribute('HeldBy') or 0);local amount=owner and owner:GetAttribute('TeddyObscure') or 0;motor.Transform=CFrame.new(0,amount*.9,-amount*.35)*CFrame.Angles(0,0,(motor.Name:find('__4') and -1 or 1)*amount*1.2) end
   end end
   if id=='Horn' then
    local length=m:GetAttribute('HornLength') or 0;local x=visuals[m]
    -- The unrolled paper only shows while someone holds the horn (the curse's noise keeps going on the floor), and it
    -- stops at the first wall or prop instead of running through the room.
    if not m:GetAttribute('HeldBy') then length=0 end
    if length>0 then
     hornParams.FilterDescendantsInstances={m,x,Players.LocalPlayer.Character}
     local hit=workspace:Raycast(r.Position+r.CFrame.LookVector*.5,r.CFrame.LookVector*length,hornParams) -- the paper runs along the horn's front (local -Z)
     if hit then length=math.max(0,hit.Distance-.1)end
    end
    if length>.05 then if not x then x=visual('UnrolledPartyHorn',Vector3.new(.35,.18,length),Color3.fromRGB(209,139,178));visuals[m]=x end;x.Size=Vector3.new(.35,.18,length);x.CFrame=r.CFrame*CFrame.new(0,0,-length/2-.5)
    elseif x then x:Destroy();visuals[m]=nil end
   end
  end
 end
 for m,x in pairs(visuals) do if not m.Parent then x:Destroy();visuals[m]=nil end end
end)



-- Carry uses the real replicated spring assembly; no hand-locked visual copy.

-- Nearby loot receives an occluded outline and a small readable value label.
local lootHints={};local hintTimer=0
Run.RenderStepped:Connect(function(dt)
 hintTimer+=dt;if hintTimer<.2 then return end;hintTimer=0
 local cam=workspace.CurrentCamera;if not cam then return end
 for _,m in ipairs(itemModels()) do if m:IsA('Model') and m.PrimaryPart and m:GetAttribute('ItemId') then
  local hint=lootHints[m]
  if not hint then
   local h=Instance.new('Highlight');h.Name='LootOutline';h.Adornee=m;h.DepthMode=Enum.HighlightDepthMode.Occluded;h.FillTransparency=.96;h.OutlineTransparency=.25;h.FillColor=Color3.fromRGB(222,193,124);h.OutlineColor=h.FillColor;h.Parent=m
   local g=Instance.new('BillboardGui');g.Name='LootValueHint';g.Adornee=m.PrimaryPart;g.Size=UDim2.fromOffset(190,40);g.StudsOffsetWorldSpace=Vector3.new(0,m.PrimaryPart.Size.Y/2+.6,0);g.AlwaysOnTop=false;g.MaxDistance=25;g.Parent=m
   local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.GothamMedium;t.TextSize=13;t.TextColor3=Color3.fromRGB(236,217,176);t.TextStrokeTransparency=.8;t.Parent=g
   hint={highlight=h,label=g,text=t};lootHints[m]=hint
  end
  local distance=(cam.CFrame.Position-m.PrimaryPart.Position).Magnitude;local visible=(not m:GetAttribute('HeldBy') or m:GetAttribute('ItemId')=='GiftCard') and not m:GetAttribute('FaceOwner') and distance<25
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={m,p.Character,cam};local ray=workspace:Raycast(cam.CFrame.Position,m.PrimaryPart.Position-cam.CFrame.Position,params)
  if ray and ray.Distance+.8<distance then local model=ray.Instance:FindFirstAncestorOfClass('Model');visible=visible and m:GetAttribute('CargoStored')==true and model~=nil and (model:GetAttribute('Kind')=='cart' or model:GetAttribute('Kind')=='boat') end
  hint.highlight.Enabled=visible and not m:GetAttribute('CargoStored');hint.label.Enabled=visible and distance<16
  hint.text.Text=(m:GetAttribute('DisplayName') or 'Loot')..((m:GetAttribute('Gear') or m:GetAttribute('LobbyToy')==true) and '' or '\n$'..(m:GetAttribute('Value') or 0)) -- bought gear is a tool, not loot: no price
 end end
 for m,hint in pairs(lootHints) do if not m.Parent then if hint.highlight.Parent then hint.highlight:Destroy() end;if hint.label.Parent then hint.label:Destroy() end;lootHints[m]=nil end end
end)
local function sendCarryMode()
 e:FireServer('carryMode',InputHints.Get()=='touch')
end
InputHints.Changed:Connect(sendCarryMode);sendCarryMode()

local function layoutCarry()
 local cam=workspace.CurrentCamera;if not cam then return end
 local small=cam.ViewportSize.Y<500
 label.Position=UDim2.new(.5,0,1,small and -36 or -52);label.Size=UDim2.new(.52,0,0,small and 40 or 52);label.TextSize=small and 12 or 14
end
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layoutCarry);layoutCarry()

local mobileActions={}
for index,entry in ipairs({}) do
 local button=Instance.new('TextButton');button.Name=entry.name;button.AnchorPoint=Vector2.new(1,1);button.BackgroundColor3=Color3.fromRGB(20,24,25);button.BackgroundTransparency=.2;button.Font=Enum.Font.GothamMedium;button.TextSize=12;button.TextColor3=Color3.fromRGB(235,231,218);button.Text=entry.text;button.Visible=false;button.Parent=gui
 Instance.new('UICorner',button).CornerRadius=UDim.new(0,16)
 button.Activated:Connect(function() e:FireServer(entry.action) end)
 mobileActions[index]=button
end
Run.RenderStepped:Connect(function()
 local cam=workspace.CurrentCamera;if not cam then return end
 local small=cam.ViewportSize.Y<500;local touch=InputHints.Get()=='touch'
 for index,button in ipairs(mobileActions) do
  button.Visible=touch and #held>0
  button.Size=UDim2.fromOffset(small and 54 or 64,small and 54 or 64)
  button.Position=UDim2.new(1,-(index==1 and (small and 84 or 96) or (small and 146 or 170)),1,small and -104 or -154)
 end
end)

local function disableRagdoll(character)
 local h=character:WaitForChild('Humanoid',10);if not h then return end
 for _,state in ipairs({Enum.HumanoidStateType.Ragdoll,Enum.HumanoidStateType.FallingDown,Enum.HumanoidStateType.Physics}) do h:SetStateEnabled(state,false) end
end
p.CharacterAdded:Connect(disableRagdoll);if p.Character then disableRagdoll(p.Character) end

-- Keyboard/mouse only: scroll up pushes the held item further away, scroll down pulls it closer.
local HOLD_DEFAULT,HOLD_MIN,HOLD_MAX,HOLD_STEP=6,3.1,10,.5 -- 1.25x the original 4.8 / 2.5 / 8
local holdDistance=HOLD_DEFAULT
local holdEvent=RS:WaitForChild('CursedEvent')
local holdSendAt,holdSent=0,HOLD_DEFAULT
UIS.InputChanged:Connect(function(input,processed)
 if processed or input.UserInputType~=Enum.UserInputType.MouseWheel then return end
 if (p:GetAttribute('CursedHeldCount')or 0)<=0 or p:GetAttribute('TouchCarry')then return end
 holdDistance=math.clamp(holdDistance+(input.Position.Z>0 and HOLD_STEP or -HOLD_STEP),HOLD_MIN,HOLD_MAX)
end)
p:GetAttributeChangedSignal('CursedHeldCount'):Connect(function()
 if (p:GetAttribute('CursedHeldCount')or 0)<=0 then holdDistance=HOLD_DEFAULT end
end)
Run.Heartbeat:Connect(function()
 -- The server rate-limits actions, so send at most ~6 updates a second and only on change.
 if holdDistance~=holdSent and os.clock()-holdSendAt>.17 then holdSendAt=os.clock();holdSent=holdDistance;holdEvent:FireServer('holdDistance',holdDistance)end
end)

-- Hold visual (client only). The server owns each held item's real body: its
-- position, collisions and impacts. On this screen alone the real item is hidden
-- and a local copy is drawn with its own spring, so dragging and swinging run at
-- full frame rate with no ping. Pose rules match CursedItemsServer.
local HoldPose=require(RS:WaitForChild('HoldPose'))
local VISUAL_FREQUENCY=17 -- spring stiffness (rad/s); higher is snappier
local VISUAL_DAMPING=.7 -- under 1 leaves a little swing
local VISUAL_TURN=16 -- how fast the copy turns to the held orientation
local SWING_TILT=.04 -- radians of tilt per stud/s of lag
local SWING_MAX=.45
local SNAP_DISTANCE=15
local holdRay=RaycastParams.new();holdRay.FilterType=Enum.RaycastFilterType.Include;holdRay.RespectCanCollide=true
local doors,doorsAt={},0
local visuals={}
local visualFolder=Instance.new('Folder');visualFolder.Name='HeldItemVisuals';visualFolder.Parent=workspace
local function hideReal(m,hidden)
 for _,d in m:GetDescendants() do if d:IsA('BasePart') then d.LocalTransparencyModifier=hidden and 1 or 0 end end
end
local function makeVisual(m)
 local copy=m:Clone()
 local realParts,copyParts={}, {}
 for _,d in m:GetDescendants() do if d:IsA('BasePart') then table.insert(realParts,d) end end
 for _,d in copy:GetDescendants() do if d:IsA('BasePart') then table.insert(copyParts,d) end end
 local pairs_={}
 for i,real in realParts do
  local c=copyParts[i]
  if c and c.Name==real.Name and real.Name~='ItemGroundCollider' then table.insert(pairs_,{real=real,copy=c})
  elseif c then c:Destroy() end
 end
 for _,d in copy:GetDescendants() do
  if d:IsA('LuaSourceContainer') or d:IsA('Constraint') or d:IsA('JointInstance') or d.Name:sub(1,5)=='Hold_' or d.Name=='LootValueHint' or d.Name=='LootOutline' or (d:IsA('Light') and d.Name=='CameraFlash') then d:Destroy() -- Keep labels and the temporary flash on the real item.
  elseif d:IsA('BasePart') then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.LocalTransparencyModifier=0 end
 end
 copy.Name='HeldVisual_'..m.Name;copy.Parent=visualFolder
 local root=m.PrimaryPart
 return {copy=copy,pairs=pairs_,pos=root.Position,vel=Vector3.zero,rot=root.CFrame.Rotation}
end
local function dropVisual(m)
 local v=visuals[m];visuals[m]=nil
 if v then v.copy:Destroy() end
 if m.Parent then hideReal(m,false) end
end
Run:BindToRenderStep('CursedHoldVisual',Enum.RenderPriority.Camera.Value+5,function(dt)
 dt=math.min(dt,1/30)
 local camera=workspace.CurrentCamera;local character=p.Character;local r=character and character:FindFirstChild('HumanoidRootPart')
 local mine={}
 if camera and r then for i,entry in ipairs(held) do
  local m=entry.model
  if m and m.Parent and m.PrimaryPart and m:GetAttribute('HeldBy')==p.UserId and not m:GetAttribute('FaceOwner') and not m:GetAttribute('ItemWearOwner') then mine[m]=i end
 end end
 for m in visuals do if not mine[m] then dropVisual(m) end end
 if not next(mine) then return end
 local now=os.clock()
 if now>=doorsAt then
  doorsAt=now+1;table.clear(doors)
  if p:GetAttribute('MissionActive')==true then for _,d in map.Interactive:GetChildren() do if d:GetAttribute('Kind')=='door' then table.insert(doors,d) end end end
 end
 local blockers={p:GetAttribute('MissionActive')==true and map.Collision or workspace:FindFirstChild('LobbyWorld')};local camp=workspace:FindFirstChild('RecoveryCamp');if camp then table.insert(blockers,camp) end
 for _,d in doors do table.insert(blockers,d) end
 holdRay.FilterDescendantsInstances=blockers
 local cam=carryView(camera);local touch=p:GetAttribute('TouchCarry')
 local w,z=VISUAL_FREQUENCY,VISUAL_DAMPING
 for m,i in mine do
  local v=visuals[m];if not v then v=makeVisual(m);visuals[m]=v end
  hideReal(m,true)
  local pose=touch and HoldPose.Item(cam,HoldPose.LeftGrip(cam),m) or cam*CFrame.new(0,-.35,-holdDistance)
  if m:GetAttribute('ItemId')=='Mirror' and not touch then pose=cam*CFrame.new(0,.55,-holdDistance)*CFrame.Angles(0,math.pi,0) end
  -- Hand mirror: glass toward the holder, close enough that the reflection shows what is behind them.
  if m:GetAttribute('ItemId')=='FearMirror' and not touch then pose=cam*CFrame.new(0,-.45,-2.6)*CFrame.Angles(0,math.pi,0) end
  local goal=i==1 and pose.Position or r.Position-r.CFrame.RightVector*1.4+Vector3.new(0,-.3,0)
  if m:GetAttribute('ItemId')=='Balloon' then pose=CFrame.new(r.Position+Vector3.new(0,4.5,0))*r.CFrame.Rotation;goal=pose.Position end
  local hit=workspace:Raycast(r.Position+Vector3.new(0,1,0),goal-r.Position-Vector3.new(0,1,0),holdRay)
  if hit then goal=hit.Position-hit.Normal*.1+hit.Normal*math.max(.65,m.PrimaryPart.Size.Magnitude*.25) end
  -- Damped spring toward the hold point; snap if far (respawn, teleport).
  if (goal-v.pos).Magnitude>SNAP_DISTANCE then v.pos=goal;v.vel=Vector3.zero end
  v.vel+=((goal-v.pos)*w*w-v.vel*2*z*w)*dt
  v.pos+=v.vel*dt
  v.rot=v.rot:Lerp(pose.Rotation,1-math.exp(-VISUAL_TURN*dt))
  -- Swing: the item tilts against its lag, relative to the view.
  local lag=cam:VectorToObjectSpace(v.vel)
  local swing=CFrame.fromAxisAngle(cam.RightVector,math.clamp(-lag.Y*SWING_TILT,-SWING_MAX,SWING_MAX))*CFrame.fromAxisAngle(cam.LookVector,math.clamp(lag.X*SWING_TILT,-SWING_MAX,SWING_MAX))
  local rootCF=CFrame.new(v.pos)*swing*v.rot
  -- Every visible part follows its offset on the real item, so animations still show.
  local realRoot=m.PrimaryPart.CFrame
  for _,pair in v.pairs do
   if pair.real.Parent then pair.copy.CFrame=rootCF*realRoot:ToObjectSpace(pair.real.CFrame);pair.copy.Transparency=pair.real.Transparency end
  end
 end
end)



