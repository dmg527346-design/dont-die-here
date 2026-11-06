-- Owner-only POWERS panel (P). The server (ServerScriptService.AdminPowersServer) re-checks the owner on every request.
-- Fly and noclip run here because the client owns its character's physics. Hotkeys: P panel (F7 is reserved by Roblox), X fly, T throw held item.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local GS=game:GetService('GuiService')
local CAS=game:GetService('ContextActionService')
local Run=game:GetService('RunService')
local p=Players.LocalPlayer
local function authorized()return p:GetAttribute('AdminAuthorized')==true end
local function owner()return p:GetAttribute('AdminOwner')==true end
local event=RS:WaitForChild('AdminPowersEvent')
local Audio=require(RS:WaitForChild('GameplayAudio'))

-- Layout and tuning constants (tuned by screenshot; report old -> new when nudging).
local PANEL_MAX_W,PANEL_MAX_H,MARGIN,ROW_H,GAP=760,560,12,44,6
local HEADER_BOTTOM=58 -- clears the 44px Close button at y=8, with 6px spacing
local OPEN_BUTTON_X,OPEN_BUTTON_W,OPEN_BUTTON_H=116,110,44
local SPEED_STEP,JUMP_STEP,FLY_STEP,THROW_STEP=8,10,20,50
local FLY_DEFAULT,FLY_MAX,THROW_DEFAULT,THROW_MAX=60,300,180,600
local colors={panel=Color3.fromRGB(22,42,43),card=Color3.fromRGB(31,55,53),cream=Color3.fromRGB(244,236,210),green=Color3.fromRGB(167,202,127),red=Color3.fromRGB(214,110,98),ink=Color3.fromRGB(8,18,22)}

local gui=Instance.new('ScreenGui');gui.Name='AdminPowersPanel';gui.ResetOnSpawn=false;gui.DisplayOrder=990;gui.IgnoreGuiInset=false;gui.Parent=p:WaitForChild('PlayerGui')
local function round(x) local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,12);c.Parent=x;local s=Instance.new('UIStroke');s.Color=colors.ink;s.Thickness=2;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=x end
local function label(parent,name,text,size)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=text;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextColor3=colors.cream;t.TextSize=size or 16;t.TextWrapped=true;t.Parent=parent;return t
end
local testCallbacks=setmetatable({},{__mode="k"})
local function button(parent,name,text,fn)
 local b=Instance.new('TextButton');b.Name=name;b.Text=text;b.Font=Enum.Font.FredokaOne;b.TextSize=15;b.TextWrapped=true;b.TextColor3=colors.cream;b.BackgroundColor3=colors.card;b.AutoButtonColor=true;b.Selectable=true;b.Parent=parent;round(b)
 testCallbacks[b]=fn;b:SetAttribute('OwnerOnly',true)
 b.Activated:Connect(function()if not authorized()or b:GetAttribute('OwnerOnly')==true and not owner()then return end;Audio.Play('UiClick');fn(b)end);return b
end

local state={noPasses=false,god=false,fly=false,noclip=false,noCosmetics=false,noMonsters=false,speed=nil,jump=nil,flySpeed=FLY_DEFAULT,throw=THROW_DEFAULT,items={},monsters={},players={},effects={},questRewards={},mission=false,round=nil}
local panel,status,pages,tabs,openButton,refreshUi,refreshState,setOpen
local sequence,pending=0,{}

local function request(action,a,b,done)
 sequence+=1;pending[sequence]=done or true;event:FireServer(sequence,action,a,b)
end
event.OnClientEvent:Connect(function(id,ok,message,data)
 local done=pending[id];pending[id]=nil
 if status and message then status.Text=message;status.TextColor3=ok and colors.green or colors.red end
 if type(done)=='function' then done(ok,data) end
end)

-- Fly / noclip ---------------------------------------------------------------
local flyParts={}
local function stopFly()
 for _,x in flyParts do x:Destroy() end;table.clear(flyParts)
 local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if h then h.PlatformStand=false end
end
local function startFly()
 stopFly()
 local c=p.Character;local r=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid');if not r or not h then return end
 local a=Instance.new('Attachment');a.Name='AdminFlyAttachment';a.Parent=r
 local v=Instance.new('LinearVelocity');v.Name='AdminFlyVelocity';v.Attachment0=a;v.MaxForce=math.huge;v.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector;v.RelativeTo=Enum.ActuatorRelativeTo.World;v.VectorVelocity=Vector3.zero;v.Parent=r
 local o=Instance.new('AlignOrientation');o.Name='AdminFlyOrientation';o.Mode=Enum.OrientationAlignmentMode.OneAttachment;o.Attachment0=a;o.MaxTorque=math.huge;o.Responsiveness=40;o.Parent=r
 flyParts={a,v,o};h.PlatformStand=true
end
local function vertical()
 local up=(UIS:IsKeyDown(Enum.KeyCode.Space) or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1,Enum.KeyCode.ButtonR1)) and 1 or 0
 local down=(UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1,Enum.KeyCode.ButtonL1)) and 1 or 0
 return up-down
end
Run.RenderStepped:Connect(function()
 local c=p.Character;if not c then return end
 if state.fly and owner()then
  local r=c:FindFirstChild('HumanoidRootPart');local h=c:FindFirstChildOfClass('Humanoid');local cam=workspace.CurrentCamera
  if not r or not h or h.Health<=0 then return end
  if #flyParts==0 or not flyParts[2].Parent then startFly() end
  local look=cam.CFrame.LookVector;local flat=Vector3.new(look.X,0,look.Z);if flat.Magnitude<.01 then flat=r.CFrame.LookVector end;flat=flat.Unit
  local right=flat:Cross(Vector3.yAxis)
  local move=h.MoveDirection -- world-space, already camera-relative
  local forward=move:Dot(flat);local side=move:Dot(right)
  local dir=look*forward+right*side+Vector3.yAxis*vertical()
  flyParts[2].VectorVelocity=dir.Magnitude>.01 and dir.Unit*state.flySpeed or Vector3.zero
  flyParts[3].CFrame=CFrame.lookAt(Vector3.zero,flat)
  h.PlatformStand=true
 end
 if state.noclip and owner()then for _,x in c:GetDescendants() do if x:IsA('BasePart') and x.CanCollide then x.CanCollide=false end end end
end)
p.CharacterAdded:Connect(function() table.clear(flyParts);if state.fly then task.delay(.5,startFly) end end)

-- Item under the crosshair (camera-centre ray, ignoring our own character).
local function aimedItem()
 local cam=workspace.CurrentCamera;local ray=cam:ViewportPointToRay(cam.ViewportSize.X/2,cam.ViewportSize.Y/2)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={p.Character}
 local interactive=workspace:FindFirstChild('Mansion') and workspace.Mansion:FindFirstChild('Interactive')
 local hit=workspace:Raycast(ray.Origin,ray.Direction*80,params)
 if hit and interactive and hit.Instance:IsDescendantOf(interactive) then return hit.Instance end
end

-- Panel ---------------------------------------------------------------------
panel=Instance.new('Frame');panel.Name='Panel';panel.AnchorPoint=Vector2.new(.5,.5);panel.Position=UDim2.fromScale(.5,.5);panel.BackgroundColor3=colors.panel;panel.Visible=false;panel.Parent=gui;round(panel)
local heading=label(panel,'Title','OWNER • POWERS',20);heading.Position=UDim2.fromOffset(12,8);heading.Size=UDim2.new(1,-120,0,32);heading.TextXAlignment=Enum.TextXAlignment.Left
status=label(panel,'Status','P opens/closes • X fly • T throw held item');status.Position=UDim2.new(0,12,1,-44);status.Size=UDim2.new(1,-24,0,36)
local tabBar=Instance.new('Frame');tabBar.Name='Tabs';tabBar.BackgroundTransparency=1;tabBar.Position=UDim2.fromOffset(12,HEADER_BOTTOM);tabBar.Size=UDim2.new(1,-24,0,ROW_H);tabBar.Parent=panel
local tabLayout=Instance.new('UIListLayout');tabLayout.FillDirection=Enum.FillDirection.Horizontal;tabLayout.SortOrder=Enum.SortOrder.LayoutOrder;tabLayout.Padding=UDim.new(0,GAP);tabLayout.Parent=tabBar
local body=Instance.new('Frame');body.Name='Body';body.BackgroundTransparency=1;body.Position=UDim2.fromOffset(12,HEADER_BOTTOM+ROW_H+GAP);body.Size=UDim2.new(1,-24,1,-(HEADER_BOTTOM+ROW_H+GAP+52));body.Parent=panel
pages,tabs={},{}
local currentPage='Player'
local function page(name)
 local f=Instance.new('ScrollingFrame');f.Name=name;f.Size=UDim2.fromScale(1,1);f.BackgroundColor3=colors.ink;f.BorderSizePixel=0;f.ScrollBarThickness=6;f.AutomaticCanvasSize=Enum.AutomaticSize.Y;f.CanvasSize=UDim2.new();f.Visible=false;f.Parent=body;round(f)
 local grid=Instance.new('UIGridLayout');grid.CellSize=UDim2.new(.5,-GAP,0,ROW_H);grid.CellPadding=UDim2.fromOffset(GAP,GAP);grid.SortOrder=Enum.SortOrder.LayoutOrder;grid.Parent=f
 local pad=Instance.new('UIPadding');pad.PaddingTop=UDim.new(0,GAP);pad.PaddingBottom=UDim.new(0,GAP);pad.PaddingLeft=UDim.new(0,GAP);pad.PaddingRight=UDim.new(0,GAP+6);pad.Parent=f
 pages[name]=f
 local t=button(tabBar,'Tab_'..name,name:upper(),function() currentPage=name;refreshUi() end);t:SetAttribute('OwnerOnly',false);t.Size=UDim2.new(1/8,-GAP,1,0);t.LayoutOrder=#tabBar:GetChildren();tabs[name]=t
 return f
end
local order=0
local function add(f,name,text,fn) order+=1;local b=button(f,name,text,fn);b.LayoutOrder=order;return b end
local function info(f,name,text) order+=1;local t=label(f,name,text,15);t.LayoutOrder=order;t.TextColor3=colors.green;return t end

-- PLAYER
local playerPage=page('Player')
local godButton=add(playerPage,'God','',function() request('god',not state.god,nil,function(ok) if ok then state.god=not state.god;refreshUi() end end) end)
local flyButton=add(playerPage,'Fly','',function() state.fly=not state.fly;if state.fly then startFly() else stopFly() end;refreshUi() end)
local flySlower=add(playerPage,'FlySlower','FLY SPEED −',function() state.flySpeed=math.max(FLY_STEP,state.flySpeed-FLY_STEP);refreshUi() end)
local flyFaster=add(playerPage,'FlyFaster','FLY SPEED +',function() state.flySpeed=math.min(FLY_MAX,state.flySpeed+FLY_STEP);refreshUi() end)
local noclipButton=add(playerPage,'Noclip','',function()
 state.noclip=not state.noclip
 -- R15 collides with its torso and head; restoring those is enough for the Humanoid to stand normally again.
 if not state.noclip and p.Character then for _,x in p.Character:GetChildren() do if x:IsA('BasePart') and (x.Name:find('Torso') or x.Name=='Head') then x.CanCollide=true end end end
 refreshUi()
end)
local healButton=add(playerPage,'Heal','HEAL',function() request('heal') end)
local function setSpeed(v) request('speed',v,nil,function(ok) if ok then state.speed=v and v>0 and math.clamp(v,4,200) or nil;refreshUi() end end) end
local speedDown=add(playerPage,'SpeedDown','SPEED −',function() setSpeed(math.max(4,(state.speed or 12)-SPEED_STEP)) end)
local speedUp=add(playerPage,'SpeedUp','SPEED +',function() setSpeed((state.speed or 12)+SPEED_STEP) end)
local speedReset=add(playerPage,'SpeedReset','SPEED NORMAL',function() setSpeed(0) end)
local function setJump(v) request('jump',v,nil,function(ok) if ok then state.jump=v and v>=0 and math.clamp(v,0,250) or nil;refreshUi() end end) end
local jumpDown=add(playerPage,'JumpDown','JUMP −',function() setJump(math.max(0,(state.jump or game.StarterPlayer.CharacterJumpHeight)-JUMP_STEP)) end)
local jumpUp=add(playerPage,'JumpUp','JUMP +',function() setJump((state.jump or game.StarterPlayer.CharacterJumpHeight)+JUMP_STEP) end)
local jumpReset=add(playerPage,'JumpReset','JUMP NORMAL',function() setJump(-1) end)
local cosmeticsButton=add(playerPage,'Cosmetics','',function() request('cosmetics',not state.noCosmetics,nil,function(ok) if ok then state.noCosmetics=not state.noCosmetics;refreshUi() end end) end)
add(playerPage,'ClearEffects','CLEAR MY ITEM EFFECTS',function() request('clearEffects') end)
local passesButton=add(playerPage,'NoPasses','',function() request('noPasses',not state.noPasses,nil,function(ok) if ok then state.noPasses=not state.noPasses;refreshUi() end end) end)
local movementInfo=info(playerPage,'MovementInfo','')

-- ITEMS
local itemPage=page('Items')
add(itemPage,'ThrowHeld','THROW HELD ITEM (T)',function() request('throw',state.throw) end)
local throwPower=add(itemPage,'ThrowPower','',function() state.throw=state.throw>=THROW_MAX and THROW_STEP or state.throw+THROW_STEP;refreshUi() end)
add(itemPage,'Bring','BRING NEARBY ITEMS',function() request('bringItems') end)
info(itemPage,'AimHint','Aim tools act on the item in your crosshair:')
for _,op in {'delete','freeze','launch','grow','shrink'} do
 add(itemPage,'Aim_'..op,'AIM: '..op:upper(),function() local target=aimedItem();if not target then status.Text='Close the panel, look at an item, then press again (or use the item list below).';status.TextColor3=colors.red;return end;request('itemTarget',target,op) end)
end
info(itemPage,'ItemHint','SPAWN drops it in front of you • EFFECT puts it in your hands')
local itemRows={}

-- MONSTERS
local monsterPage=page('Monsters')
local noMonstersButton=add(monsterPage,'NoMonsters','',function() request('noMonsters',not state.noMonsters,nil,function(ok) if ok then state.noMonsters=not state.noMonsters;refreshUi() end end) end)
add(monsterPage,'ClearMonsters','REMOVE ALL MONSTERS',function() request('clearMonsters') end)
local monsterRows={}

-- ROUND
local roundPage=page('Round')
local roundInfo=info(roundPage,'RoundInfo','')
add(roundPage,'RefreshRound','REFRESH STATUS',function() refreshState() end)
add(roundPage,'Restart','RESTART FROM LEVEL 1',function() request('round','restart') end)
add(roundPage,'Next','START NEXT LEVEL',function() request('round','next') end)
add(roundPage,'End','STOP / FAIL THIS LEVEL',function() request('round','end') end)
add(roundPage,'Quota','MARK QUOTA MET',function() request('round','quota') end)
add(roundPage,'AddTime','TIMER +60s',function() request('round','addTime',60) end)
add(roundPage,'RemoveTime','TIMER −60s',function() request('round','addTime',-60) end)
 add(roundPage,'Bank500','TEAM BANK +$500',function() request('bank',500) end)
 add(roundPage,'Bank2500','TEAM BANK +$2,500',function() request('bank',2500) end)
 add(roundPage,'Revive1','REVIVE TOKENS +1',function() request('revives',1) end)
 add(roundPage,'Revive5','REVIVE TOKENS +5',function() request('revives',5) end)
 add(roundPage,'Revive10','REVIVE TOKENS +10',function() request('revives',10) end)

-- REWARDS: simulate van reward time for testing (test mode: nothing saves until RESTORE)
local rewardPage=page('Rewards')
info(rewardPage,'RewardInfo','Test the van DAILY / TIMED panels. While testing, your progress does not save until RESTORE.')
add(rewardPage,'RewardPlus5','PLAYTIME +5 MIN',function() request('rewards','time',300) end)
add(rewardPage,'RewardPlus30','PLAYTIME +30 MIN',function() request('rewards','time',1800) end)
add(rewardPage,'RewardPlus60','PLAYTIME +1 HOUR',function() request('rewards','time',3600) end)
add(rewardPage,'RewardMax','PLAYTIME TO 6 HOURS (ALL READY)',function() request('rewards','time',21600) end)
add(rewardPage,'RewardDaily','MAKE DAILY GIFT CLAIMABLE',function() request('rewards','daily') end)
add(rewardPage,'RewardRestore','RESTORE MY REAL SAVE',function() request('rewards','restore') end)

-- Target tools use the real server item/revive owners; delegated admins cannot use owner tools.
local targetPage=page('Targets');local chosenTarget;local effectRows={}
local targetName=info(targetPage,'TargetName','Choose a player')
add(targetPage,'RefreshTargets','REFRESH PLAYERS / EFFECTS',function()refreshState()end):SetAttribute('OwnerOnly',false)
local function cycleTarget(direction)
 local list=state.players or {};if #list==0 then return end
 local index=1;for i,row in list do if row.id==chosenTarget then index=i;break end end
 chosenTarget=list[(index-1+direction)%#list+1].id;refreshUi()
end
add(targetPage,'TargetPrevious','< PREVIOUS PLAYER',function()cycleTarget(-1)end):SetAttribute('OwnerOnly',false)
add(targetPage,'TargetNext','NEXT PLAYER >',function()cycleTarget(1)end):SetAttribute('OwnerOnly',false)
add(targetPage,'ReviveTarget','REVIVE PLAYER (NO TOKENS)',function()if chosenTarget then request('revivePlayer',chosenTarget)end end):SetAttribute('OwnerOnly',false)
add(targetPage,'ClearTarget','CLEAR PLAYER ITEM EFFECTS',function()if chosenTarget then request('clearTarget',chosenTarget)end end):SetAttribute('OwnerOnly',false)
add(targetPage,'GrantAdmin','GRANT ADMIN (OWNER ONLY)',function()if chosenTarget then request('adminGrant',chosenTarget,true,function()task.delay(.2,refreshState)end)end end)
add(targetPage,'RevokeAdmin','REVOKE ADMIN (OWNER ONLY)',function()if chosenTarget then request('adminGrant',chosenTarget,false,function()task.delay(.2,refreshState)end)end end)
local effectHint=info(targetPage,'EffectHint','Pick a player, then an effect. Uses real cursed items.');effectHint.TextScaled=true
local hintLimit=Instance.new('UITextSizeConstraint');hintLimit.MinTextSize=10;hintLimit.MaxTextSize=15;hintLimit.Parent=effectHint
-- QUESTS (owner only, your own account): grant quest rewards through the real claim path (saved receipts).
local questPage=page('Quests');local questRows={}
local questPending={} -- selector -> requestId, kept until the server answers so a retry replays the same grant
local function questGrant(selector)
 questPending[selector]=questPending[selector]or game:GetService('HttpService'):GenerateGUID(false)
 request('questRewards',selector,questPending[selector],function(ok)questPending[selector]=nil;if ok then task.delay(.3,refreshState)end end)
end
info(questPage,'QuestInfo','Gives YOU quest rewards through the normal claim (saved). Halloween is not included.')
add(questPage,'QuestAll','CLAIM ALL ACTIVE QUEST REWARDS',function()questGrant('ALL')end)
local closeButton=button(panel,'Close','CLOSE',function() setOpen(false) end);closeButton.AnchorPoint=Vector2.new(1,0);closeButton.Position=UDim2.new(1,-12,0,8);closeButton.Size=UDim2.fromOffset(90,44);closeButton:SetAttribute('OwnerOnly',false)

local function onOff(v) return v and ' • ON' or ' • OFF' end
refreshUi=function()
 gui.Enabled=authorized();heading.Text=owner()and'OWNER · POWERS'or'ADMIN · PLAYER TOOLS'
 for _,b in gui:GetDescendants()do if b:IsA('GuiButton')then local enabled=authorized()and(b:GetAttribute('OwnerOnly')~=true or owner());b.Active=enabled;b.Selectable=enabled;b.AutoButtonColor=enabled;b.TextTransparency=enabled and 0 or .45 end end
 local chosen;for _,row in state.players or {}do if row.id==chosenTarget then chosen=row;break end end
 targetName.Text=chosen and('@'..chosen.name..(chosen.dead and' · DEAD'or' · ALIVE')..(chosen.admin and' · ADMIN'or''))or'Choose a player'
 for name,f in pages do f.Visible=name==currentPage;tabs[name].BackgroundColor3=name==currentPage and colors.green or colors.card;tabs[name].TextColor3=name==currentPage and colors.ink or colors.cream end
 godButton.Text='GOD MODE'..onOff(state.god);godButton.TextColor3=state.god and colors.green or colors.cream
 flyButton.Text='FLY (X)'..onOff(state.fly);flyButton.TextColor3=state.fly and colors.green or colors.cream
 noclipButton.Text='NOCLIP'..onOff(state.noclip);noclipButton.TextColor3=state.noclip and colors.green or colors.cream
 passesButton.Text=state.noPasses and 'MY GAME PASSES • OFF (testing)' or 'MY GAME PASSES • ON';passesButton.TextColor3=state.noPasses and colors.red or colors.cream
 cosmeticsButton.Text=state.noCosmetics and 'COSMETICS • REMOVED' or 'REMOVE ALL COSMETICS';cosmeticsButton.TextColor3=state.noCosmetics and colors.green or colors.cream
 movementInfo.Text='Speed '..(state.speed or 'normal')..' • Jump '..(state.jump or 'normal')..' • Fly '..state.flySpeed..'\nFly: Space/R1 up, Ctrl/L1 down'
 throwPower.Text='THROW POWER '..state.throw
 noMonstersButton.Text='PAUSE MONSTER SPAWNS'..onOff(state.noMonsters);noMonstersButton.TextColor3=state.noMonsters and colors.green or colors.cream
 local r=state.round
 roundInfo.Text=not state.mission and 'Not in a mission: item, monster and round tools work once a mission starts.' or r and ('Level '..r.round..' • '..r.phase..' • $'..r.sold..' / $'..r.quota..(type(r.levelEnds)=='number' and (' • '..math.max(0,math.floor(r.levelEnds-workspace:GetServerTimeNow()))..'s left') or '')) or 'Round status unavailable.'
end
local function rebuildLists()
 for _,b in effectRows do b:Destroy()end;table.clear(effectRows)
 local found=false;for _,row in state.players or{}do if row.id==chosenTarget then found=true end end
 if not found then chosenTarget=state.players and state.players[1]and state.players[1].id end
 for _,effect in state.effects or{}do
  local b=add(targetPage,'Effect_'..effect.id,'EFFECT: '..effect.name,function()if chosenTarget then request('giveEffect',chosenTarget,effect.id)else status.Text='Choose a player first.'end end)
  b:SetAttribute('OwnerOnly',false);effectRows[#effectRows+1]=b
 end
 for _,x in itemRows do x:Destroy() end;table.clear(itemRows)
 for _,item in state.items do
  table.insert(itemRows,add(itemPage,'Spawn_'..item.id,'SPAWN '..item.name,function() request('spawnItem',item.id) end))
  table.insert(itemRows,add(itemPage,'Give_'..item.id,'EFFECT '..item.name,function() request('giveItem',item.id) end))
 end
 for _,x in questRows do x:Destroy() end;table.clear(questRows)
 for _,row in state.questRewards or{}do
  if type(row)=='table'and row.id then table.insert(questRows,add(questPage,'Quest_'..tostring(row.id),tostring(row.label or row.id),function()questGrant(row.id)end))end
 end
 for _,x in monsterRows do x:Destroy() end;table.clear(monsterRows)
 for i,name in state.monsters do table.insert(monsterRows,add(monsterPage,'Monster_'..i,'SPAWN '..tostring(name):upper(),function() request('spawnMonster',i) end)) end
end
function refreshState()
 request('state',nil,nil,function(ok,data)
  if not ok or type(data)~='table' then return end
  state.mission=data.mission;state.round=data.round;state.god=data.god;state.noCosmetics=data.noCosmetics;state.noMonsters=data.noMonsters;state.noPasses=data.noPasses;state.speed=data.speed;state.jump=data.jump
  state.items=data.items or{};state.questRewards=data.questRewards or{};state.monsters=data.monsters or{};state.players=data.players or{};state.effects=data.effects or{}
  rebuildLists();refreshUi()
 end)
end

local function layout()
 local cam=workspace.CurrentCamera;if not cam then return end
 local v=gui.AbsoluteSize
 panel.Size=UDim2.fromOffset(math.min(PANEL_MAX_W,v.X-MARGIN*2),math.min(PANEL_MAX_H,math.max(120,v.Y-MARGIN*2)))
end
local previousFocus
function setOpen(value)
 if value and not owner()then return end -- owner only (2026-10-25): nobody else gets this window
 if value and not owner()then currentPage='Targets'end
 panel.Visible=value;if openButton then openButton.Visible=not value and not p:GetAttribute('InLobbyCircle')end;closeButton.Modal=value;p:SetAttribute('AdminPowersPanelOpen',value)
 if value then previousFocus=GS.SelectedObject;UIS.MouseBehavior=Enum.MouseBehavior.Default;layout();refreshState();refreshUi()
  if UIS:GetLastInputType().Name:find('Gamepad') then GS.SelectedObject=tabs[currentPage] end
 elseif GS.SelectedObject and GS.SelectedObject:IsDescendantOf(panel) then GS.SelectedObject=previousFocus and previousFocus.Parent and previousFocus or nil end
end
-- One window, no on-screen button (owner 2026-10-25): P opens it on the owner's screen only. PASSES is the admin pass
-- panel (AdminPassClient), shown in this window's place; its POWERS tab comes back here.
local function passApi()local s=p.PlayerScripts:FindFirstChild('AdminPassClient');return s and s:FindFirstChild('PassPanelApi')end
local passesTab=button(tabBar,'Tab_Passes','PASSES',function()
 local api=passApi();if not api then return end
 local at,size=panel.AbsolutePosition,panel.AbsoluteSize;setOpen(false);api:Invoke('open',at,size)
end);passesTab:SetAttribute('OwnerOnly',true);passesTab.Size=UDim2.new(1/8,-GAP,1,0);passesTab.LayoutOrder=99
local openPowers=Instance.new('BindableEvent');openPowers.Name='OpenPowers';openPowers.Parent=script
openPowers.Event:Connect(function()if owner()then setOpen(true)end end)


CAS:BindAction('OwnerPowersPanel',function(_,s)
 if not owner()or UIS:GetFocusedTextBox()then return Enum.ContextActionResult.Pass end
 if s==Enum.UserInputState.Begin then
  -- P closes whichever tab is up, or opens the window
  local api=passApi()
  if api and api:Invoke('isOpen')then api:Invoke('close')else setOpen(not panel.Visible)end
 end
 return Enum.ContextActionResult.Sink
end,false,Enum.KeyCode.P)
CAS:BindAction('OwnerPowersFly',function(_,s) if not owner()then return Enum.ContextActionResult.Pass end;if s==Enum.UserInputState.Begin and not UIS:GetFocusedTextBox()then state.fly=not state.fly;if state.fly then startFly() else stopFly() end;refreshUi() end;return Enum.ContextActionResult.Pass end,false,Enum.KeyCode.X)
CAS:BindAction('OwnerPowersThrow',function(_,s) if not owner()then return Enum.ContextActionResult.Pass end;if s==Enum.UserInputState.Begin and not UIS:GetFocusedTextBox()then request('throw',state.throw) end;return Enum.ContextActionResult.Pass end,false,Enum.KeyCode.T)
CAS:BindActionAtPriority('OwnerPowersBack',function(_,s) if not panel.Visible then return Enum.ContextActionResult.Pass end;if s==Enum.UserInputState.Begin then setOpen(false) end;return Enum.ContextActionResult.Sink end,false,5001,Enum.KeyCode.ButtonB)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout) end
layout();refreshUi()

local function accessChanged()
 if not owner()then setOpen(false);local clipped=state.noclip;state.fly=false;stopFly();state.noclip=false
  if clipped and p.Character then for _,part in p.Character:GetChildren()do if part:IsA('BasePart')and(part.Name:find('Torso')or part.Name=='Head')then part.CanCollide=true end end end
 end
 refreshUi()
end
p:GetAttributeChangedSignal('AdminAuthorized'):Connect(accessChanged)
p:GetAttributeChangedSignal('AdminOwner'):Connect(accessChanged);accessChanged()
local bridge=Instance.new('BindableEvent');bridge.Name='OpenTargets';bridge.Parent=script
bridge.Event:Connect(function()if owner()then currentPage='Targets';setOpen(true)end end)
Players.PlayerAdded:Connect(function()if panel.Visible then refreshState()end end)
Players.PlayerRemoving:Connect(function()if panel.Visible then task.defer(refreshState)end end)

if Run:IsStudio()then
 local api=Instance.new('BindableFunction');api.Name='AdminPanelTestApi';api.Parent=script
 api.OnInvoke=function(action,value)
  if action=='open'then currentPage='Targets';setOpen(true);return panel.Visible end
  if action~='activate'or typeof(value)~='Instance'or not value:IsA('GuiButton')or not value:IsDescendantOf(panel)or not value.Active or not authorized()or value:GetAttribute('OwnerOnly')==true and not owner()then return false end
  local parent=value;while parent and parent~=gui do if parent:IsA('GuiObject')and not parent.Visible then return false end;parent=parent.Parent end
  local fn=testCallbacks[value];if not fn then return false end;task.spawn(fn,value);return true
 end
end
