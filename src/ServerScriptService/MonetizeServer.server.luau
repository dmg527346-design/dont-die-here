-- ServerScriptService.MonetizeServer (Script). ProgressService remains the sole receipt owner.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local SS=game:GetService('ServerStorage')
local Http=game:GetService('HttpService')
local Progress=require(script.Parent:WaitForChild('ProgressService'))
local event=RS:FindFirstChild('MonetizeEvent') or Instance.new('RemoteEvent')
assert(event:IsA('RemoteEvent'),'MonetizeEvent must be a RemoteEvent')
event.Name='MonetizeEvent';event.Parent=RS
local scare=RS:WaitForChild('MonsterJumpscare')
local gates,busy={},{}
local function living(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 return p.Parent==Players and p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true and h~=nil and h.Health>0
end
local function reply(p,action,ok,message)
 if p.Parent==Players then event:FireClient(p,action,ok,message)end
end
local function allow(p,key,gap)
 local now=os.clock();local t=gates[p]or {};gates[p]=t
 if now<(t[key]or 0)then return false end;t[key]=now+gap;return true
end
local function monster()
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if folder then for _,m in folder:GetChildren()do if m:IsA('Model')and m.PrimaryPart then return m end end end
end
event.OnServerEvent:Connect(function(p,action,value)
 if type(action)~='string'or p.Parent~=Players then return end
 if action=='giftReviveTarget'then
  if not allow(p,action,.5)then return end
  Progress.SetGiftReviveTarget(p,nil)
  if type(value)~='number'or value~=value or math.abs(value)==math.huge or value%1~=0 or value<=0 or value>9007199254740991 then return end
  local target=Players:GetPlayerByUserId(value);local api=SS:FindFirstChild('RecoveryApi')
  if not target or target==p or not api or not api:IsA('BindableFunction')then reply(p,action,false,'Choose a dead teammate in this mission.');return end
  local ok,identity=pcall(function()return api:Invoke('GiftReviveIdentity',p,target)end)
  if not ok or type(identity)~='table'then reply(p,action,false,'That teammate cannot be revived right now.');return end
  local accepted,message=Progress.SetGiftReviveTarget(p,value,identity)
  reply(p,action,accepted,message)
 elseif action=='setFlashlightColor'then
  if not allow(p,action,1)then return end
  if typeof(value)~='Color3'or p:GetAttribute('Pass_flashlight_colors')~=true then reply(p,action,false,'Flashlight Colors pass required.');return end
  for _,n in {value.R,value.G,value.B}do if n~=n or math.abs(n)==math.huge then return end end
  local ok,message=Progress.SetFlashlightColor(p,Color3.new(math.clamp(value.R,0,1),math.clamp(value.G,0,1),math.clamp(value.B,0,1)))
  reply(p,action,ok,message)
 elseif action=='jumpscareAll'then
  if busy[p]or not living(p)or p:GetAttribute('MonsterJumpscareActive')then return end
  if not allow(p,'scareRequest',1)then return end
  if not Progress.CanUseVanShop(p)then reply(p,action,false,'Use group jumpscares inside the van.');return end
  local limits=gates[p];if os.clock()<(limits.scareSpent or 0)then reply(p,action,false,'Wait before scaring everyone again.');return end
  local targets={};for _,q in Players:GetPlayers()do if q~=p and living(q)and not q:GetAttribute('MonsterJumpscareActive')then table.insert(targets,q)end end
  local model=monster()
  if #targets==0 or not model then reply(p,action,false,'No living teammates or monster available.');return end
  local roundState=RS:FindFirstChild('RecoveryRound');local roundId=roundState and roundState:GetAttribute('Round')
  local levelEnds=roundState and roundState:GetAttribute('LevelEnds');local character=p.Character
  local operation=Http:GenerateGUID(false)
  busy[p]=true
  local called,ok,message=pcall(Progress.ConsumeJumpscare,p,operation)
  busy[p]=nil
  if not called then
   local refunded,restored=pcall(Progress.RefundJumpscare,p,operation)
   if not refunded or not restored then task.spawn(function()for attempt=1,10 do task.wait(5);local retryOk,done=pcall(Progress.RefundJumpscare,p,operation);if retryOk and done then return end end end)end
   reply(p,action,false,'The saved charge could not be used; restoration is being checked.');return
  end
  if not ok then reply(p,action,false,message);return end
  local validTargets={}
  if living(p)and Progress.CanUseVanShop(p)and p.Character==character and not p:GetAttribute('MonsterJumpscareActive')and model.Parent and (not roundState or (roundState:GetAttribute('Round')==roundId and roundState:GetAttribute('LevelEnds')==levelEnds))then
   for _,q in targets do if living(q)and not q:GetAttribute('MonsterJumpscareActive')then table.insert(validTargets,q)end end
  end
  if #validTargets==0 then
   local refundOk,restored=pcall(Progress.RefundJumpscare,p,operation)
   if not refundOk or not restored then task.spawn(function()for attempt=1,10 do task.wait(5);local retryOk,done=pcall(Progress.RefundJumpscare,p,operation);if retryOk and done then return end end end)end
   reply(p,action,false,refundOk and restored and 'The mission changed; your charge was restored.'or 'The mission changed; charge restoration is being checked.');return
  end
  limits.scareSpent=os.clock()+20
  local token='party:'..Http:GenerateGUID(false);local stamp=workspace:GetServerTimeNow()
  -- Presentation only: never invoke MonsterJumpscare.Start, anchor, or change health.
  if model.Parent then for _,q in validTargets do if living(q)and not q:GetAttribute('MonsterJumpscareActive')then
   scare:FireClient(q,'party',token,model,stamp,1.3,{sourceUserId=p.UserId,sourceName=p.DisplayName,presentationOnly=true})
  end end end
  reply(p,action,true,'You scared everyone!')
 elseif action=='instantWin'then
  -- Spend one saved charge, clear the level for the whole team, and give the charge back if the win cannot happen.
  if busy[p]or p:GetAttribute('MissionActive')~=true then return end
  if not allow(p,'instantWin',2)then return end
  if not Progress.CanUseVanShop(p)then reply(p,action,false,'Use Instant Win inside the van.');return end
  local api=SS:FindFirstChild('RecoveryApi')
  if not api or not api:IsA('BindableFunction')then reply(p,action,false,'Instant Win is unavailable right now.');return end
  local checked,can,why=pcall(function()return api:Invoke('canInstantWin',p)end)
  if not checked or not can then reply(p,action,false,checked and why or 'Instant Win is unavailable right now.');return end
  local operation=Http:GenerateGUID(false)
  busy[p]=true
  local called,ok,message=pcall(Progress.ConsumeInstantWin,p,operation)
  if not called or not ok then busy[p]=nil;reply(p,action,false,called and message or 'Your Instant Win charge could not be used. Try again.');return end
  local won,result=pcall(function()if not Progress.CanUseVanShop(p)then return false end;return api:Invoke('instantWin',p)end)
  busy[p]=nil
  if not won or result~=true then
   local refunded,restored=pcall(Progress.RefundInstantWin,p,operation)
   if not refunded or not restored then task.spawn(function()for attempt=1,10 do task.wait(5);local retryOk,done=pcall(Progress.RefundInstantWin,p,operation);if retryOk and done then return end end end)end
   reply(p,action,false,'The level changed before the win went through; your charge was kept.');return
  end
  for _,q in Players:GetPlayers()do if q~=p and q:GetAttribute('MissionActive')==true then reply(q,'instantWinTeam',true,p.DisplayName..' used Instant Win! Level cleared.')end end
  reply(p,action,true,'Instant Win used. Level cleared!')
 end
end)
Players.PlayerRemoving:Connect(function(p)gates[p]=nil;busy[p]=nil end)

