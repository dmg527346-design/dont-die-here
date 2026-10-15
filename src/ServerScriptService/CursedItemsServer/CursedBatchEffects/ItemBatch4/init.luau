-- Batch 4: server-owned leases, replicated attachments and co-op rescue.
-- CursedBatchEffects calls Configure, Pickup and ClearPlayer. Never require from a test command.
local Players=game:GetService('Players')
local SS=game:GetService('ServerStorage')
local Run=game:GetService('RunService')
local Audio=require(game.ServerScriptService:WaitForChild('GameplayAudioServer'))
local M={}
local LEASES={GuessWhoHands='GuessWhoUntil',FearMirror='MirrorFearUntil'}
local KEYS={'GuessWhoStart','GuessWhoUntil','MirrorFearStart','MirrorFearUntil','MirrorMonsterCF','CursedAttach'}
local COOP={FacePlunger=true,ClingyTeddy=true,CursedHair=true,MannequinHand=true,ClawPlushie=true}
local MALL_COOP={MannequinHand=true,ClawPlushie=true}
local departing,pending={},{}
local cleanupEpoch=setmetatable({},{__mode='k'})
local attached,visuals={},{}
local detach,clearHold,setParts
local LEASE=.5
local REACH=10
local function living(p)
 local c=p and not departing[p] and p.Parent==Players and p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 return c and h and h.Health>0 and p:GetAttribute('MissionActive')==true and c or nil
end
local function missionCount(exclude)
 local n=0;for _,p in ipairs(Players:GetPlayers())do if p~=exclude and living(p)then n+=1 end end
 return n
end
-- Players in the mission (alive or dead): the 2+ player rule is about the party, not who is alive.
local function partyCount(exclude)
 local n=0;for _,p in ipairs(Players:GetPlayers())do if p~=exclude and not departing[p] and p.Parent==Players and p:GetAttribute('MissionActive')==true then n+=1 end end
 return n
end
function M.Configure(drop,clear,parts)detach=drop;clearHold=clear;setParts=parts end
local function studioSoloOverride()
 return Run:IsStudio()and script.Parent.Parent:GetAttribute('CoopSoloTest')==true
end
function M.CanSpawn(id,exclude)
 return not COOP[id]or partyCount(exclude)>=2 or studioSoloOverride() -- Studio-only CoopSoloTest lets a solo tester spawn co-op items
end
local function detachVisual(p,id)
 local t=visuals[p];local m=t and t[id]
 if m then m:Destroy();t[id]=nil end
 local c=p.Character;local orphan=c and c:FindFirstChild('CursedAttach_'..id);if orphan then orphan:Destroy()end
end
local function attachVisual(p,id)
 local c=living(p);if not c then return end
 visuals[p]=visuals[p]or{};local old=visuals[p][id]
 if old and old.Parent==c then return old end
 detachVisual(p,id)
 local kit=SS:FindFirstChild('CursedAttachKit');local template=kit and kit:FindFirstChild(id)
 if not template or not template:IsA('Model')or not template.PrimaryPart then return end
 local bone=c:FindFirstChild(template:GetAttribute('AttachBone')or 'Head')
 if not bone or not bone:IsA('BasePart')then return end
 local offset=template:GetAttribute('AttachOffset')or CFrame.identity
 local m=template:Clone();m.Name='CursedAttach_'..id
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')then x.Anchored=false;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.Massless=true;x.CastShadow=false end end
 m:PivotTo(bone.CFrame*offset)
 local w=Instance.new('Weld');w.Name='CursedVisualWeld';w.Part0=bone;w.Part1=m.PrimaryPart
 w.C0=bone.CFrame:ToObjectSpace(m.PrimaryPart.CFrame);w.Parent=m.PrimaryPart
 m.PrimaryPart:SetAttribute('CursedVisualRestC0',w.C0)
 m:SetAttribute('CursedOwner',p.UserId);m.Parent=c;visuals[p][id]=m
 return m
end
local function release(m,spent)
 local s=attached[m];if not s then return false end
 attached[m]=nil
 local w=m.PrimaryPart and m.PrimaryPart:FindFirstChild('CursedItemAttachWeld');if w then w:Destroy()end
 m:SetAttribute('AttachedTo',nil);if spent then m:SetAttribute('CurseSpent',true)end
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')and x:FindFirstChildWhichIsA('BallSocketConstraint')then pcall(function()x:SetNetworkOwnershipAuto()end)end end
 if s.owner:GetAttribute('CursedAttach')==s.id then s.owner:SetAttribute('CursedAttach','')end
 if m.Parent and m.PrimaryPart then
  if clearHold then clearHold(m)else m:SetAttribute('HeldBy',nil)end
  if setParts then setParts(m,false,true)else
   for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')then x.Anchored=false;x.CanQuery=x==m.PrimaryPart;x.CanCollide=x==m.PrimaryPart;x.CanTouch=false end end
  end
  local c=s.owner.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
  if r then m:PivotTo(r.CFrame*CFrame.new(1,-1,-2))end
  m.PrimaryPart.AssemblyLinearVelocity=Vector3.new(0,-1,0)
 end
 return true,s
end
function M.CanRemove(p,m)
 local s=attached[m]
 if s==nil or living(p)==nil or living(s.owner)==nil or s.owner.Character~=s.character or m.Parent==nil or m:GetAttribute('AttachedTo')~=s.owner.UserId then return false end
 -- Normally a teammate must pull it off; with every teammate dead the wearer can grab it off themselves.
 return s.owner~=p or missionCount(p)==0
end
local function finishRescue(m)
 local ok,s=release(m,true);if not ok then return false end
 if s.id=='FacePlunger'then
  Audio.Play('PlungerPop',m)
  local evidence=SS:FindFirstChild('MonsterEvidence');if evidence then evidence:Fire(m.PrimaryPart.Position,45,'face plunger pop',m)end
 elseif s.id=='CursedHair'then Audio.Play('HairRustle',m)end
 return true
end
function M.RemoveAttached(p,m)
 if not M.CanRemove(p,m)then return false end
 local expected=attached[m]
 local r=p.Character:FindFirstChild('HumanoidRootPart');local head=p.Character:FindFirstChild('Head')or r
 if not r or not m.PrimaryPart or (r.Position-m.PrimaryPart.Position).Magnitude>REACH then return false end
 local map=workspace:FindFirstChild('Mansion');local collision=map and map:FindFirstChild('Collision')
 if not collision then return false end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={collision};params.RespectCanCollide=true
 if workspace:Raycast(head.Position,m.PrimaryPart.Position-head.Position,params)then return false end
 -- Revalidate after reach/visibility work: death, leave or a concurrent rescue may have changed the state.
 if attached[m]~=expected or not M.CanRemove(p,m)then return false end
 return finishRescue(m)
end
local function attachItem(p,m,id,forcePopulation)
 local c=living(p)
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if not interactive or m.Parent~=interactive then return false end
 if not c or not m.PrimaryPart or m:GetAttribute('CurseSpent')or(not forcePopulation and not M.CanSpawn(id))or(p:GetAttribute('CursedAttach')or '')~='' or attached[m]or pending[m]then return false end
 local defaultBone=id=='MannequinHand'and 'RightHand'or(id=='ClingyTeddy'and 'UpperTorso'or 'Head')
 local bone=c:FindFirstChild(m:GetAttribute('AttachBone')or defaultBone)
 if not bone or not bone:IsA('BasePart')or not detach or not clearHold or not setParts then return false end
 -- Remove inventory first, then weld the existing registered loot; no clone or lost sale value.
 local epoch=cleanupEpoch[p]or 0
 pending[m]=true
 local ok,err=pcall(function()detach(p,m,false,true);clearHold(m)end)
 pending[m]=nil
 if not ok then warn('[ItemBatch4] attachment detach failed: '..tostring(err));return false end
 if (cleanupEpoch[p]or 0)~=epoch or living(p)~=c or m.Parent~=interactive or not m.PrimaryPart or bone.Parent~=c or attached[m]or m:GetAttribute('CurseSpent')or(p:GetAttribute('CursedAttach')or '')~=''then return false end
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')then x.Anchored=false;x.CanCollide=false;x.CanTouch=false;x.CanQuery=false;x.Massless=true end end
 local fallback=id=='MannequinHand'and CFrame.new(0,-.05,0)or(id=='ClawPlushie'and CFrame.new(0,2.8,0)or(id=='ClingyTeddy'and CFrame.new(0,0,1.05)or CFrame.new(0,1,.6)))
 m:PivotTo(bone.CFrame*(m:GetAttribute('AttachOffset')or fallback))
 local w=Instance.new('Weld');w.Name='CursedItemAttachWeld';w.Part0=bone;w.Part1=m.PrimaryPart;w.C0=bone.CFrame:ToObjectSpace(m.PrimaryPart.CFrame);w.Parent=m.PrimaryPart
 -- The item stays in Mansion.Interactive so the established GRAB path can target it.
 local state={owner=p,id=id,character=c,at=os.clock()}
 attached[m]=state
 m.PrimaryPart.CanQuery=true;m:SetAttribute('AttachedTo',p.UserId)
 if attached[m]~=state then return false end
 p:SetAttribute('CursedAttach',id)
 if attached[m]~=state then return false end
 -- Physics hair: the wearer's client simulates the swinging strand segments so head shakes respond instantly.
 for _,x in ipairs(m:GetDescendants())do if x:IsA('BasePart')and x:FindFirstChildWhichIsA('BallSocketConstraint')then pcall(function()x:SetNetworkOwner(p)end)end end
 if living(p)~=c then release(m,true);return false end
 return attached[m]==state
end
local function mirrorCF(p)
 if typeof(p)~='Instance'or not p:IsA('Player')then return nil end
 local c=living(p);if not c or not c:IsA('Model')then return nil end
 local r=c:FindFirstChild('HumanoidRootPart')
 if not r or not r:IsA('BasePart')then return nil end
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 local collision=map and map:FindFirstChild('Collision')
 local look=r.CFrame.LookVector;local flatLook=Vector3.new(look.X,0,look.Z)
 flatLook=flatLook.Magnitude>.001 and flatLook.Unit or Vector3.new(0,0,-1)
 local behind;local best=math.huge
 if interactive then for _,door in ipairs(interactive:GetChildren())do
  if door:IsA('Model')and door:GetAttribute('Kind')=='door'and door.PrimaryPart then
   local slab=door:FindFirstChild('Door')or door:FindFirstChild('Slab')
   local cf,size;if slab and slab:IsA('BasePart')then cf,size=slab.CFrame,slab.Size else cf,size=door:GetBoundingBox()end
   local pos=Vector3.new(cf.Position.X,cf.Position.Y-size.Y*.5,cf.Position.Z)
   local delta=pos-r.Position;local flat=Vector3.new(delta.X,0,delta.Z);local d=flat.Magnitude
   if math.abs(pos.Y-(r.Position.Y-3))<6 and d>.001 and d<=45 and flatLook:Dot(flat.Unit)<-.2 and d<best then
    behind=pos;best=d
   end
  end
 end end
 local pos=behind
 if not pos then
  local clearance=8
  local params
  if collision then
   params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={collision};params.RespectCanCollide=true
   local wall=workspace:Raycast(r.Position,-flatLook*8,params)
   if wall then clearance=math.clamp(wall.Distance-1.5,0,8)end
  end
  local flatPos=r.Position-flatLook*clearance
  local floorY=r.Position.Y-3
  if params then
   local floor=workspace:Raycast(Vector3.new(flatPos.X,r.Position.Y+4,flatPos.Z),Vector3.new(0,-32,0),params)
   if floor and floor.Normal.Y>.5 then floorY=floor.Position.Y end
  end
  pos=Vector3.new(flatPos.X,floorY,flatPos.Z)
 end
 local target=Vector3.new(r.Position.X,pos.Y,r.Position.Z)
 -- With zero rear clearance, choose orientation toward the player without moving in front.
 if(target-pos).Magnitude<.001 then target=pos+flatLook end
 return CFrame.lookAt(pos,target)
end
function M.Pickup(p,m)
 local id=m:GetAttribute('ItemId');local now=workspace:GetServerTimeNow()
 if COOP[id]then attachItem(p,m,id)
 elseif id=='GuessWhoHands'then p:SetAttribute('GuessWhoStart',now);p:SetAttribute('GuessWhoUntil',now+LEASE);attachVisual(p,id)
 elseif id=='FearMirror'then p:SetAttribute('MirrorFearStart',now);p:SetAttribute('MirrorFearUntil',now+LEASE);p:SetAttribute('MirrorMonsterCF',mirrorCF(p))end
end
function M.ClearPlayer(p)
 cleanupEpoch[p]=(cleanupEpoch[p]or 0)+1
 for m,s in pairs(attached)do if s.owner==p then release(m,true)end end
 if visuals[p]then for id in pairs(visuals[p])do detachVisual(p,id)end;visuals[p]=nil end
 for _,key in ipairs(KEYS)do p:SetAttribute(key,nil)end
end
function M.ClearLevel()
 for _,p in ipairs(Players:GetPlayers())do M.ClearPlayer(p)end
 for m in pairs(attached)do release(m,true)end
end
local function soloSafety(exclude,ignoreOverride)
 if not ignoreOverride and studioSoloOverride()then return end
 -- Keep the surviving wearer's registered item grabbable; CanRemove uses the current living roster.
 -- Dead/disconnected owners are cleaned by ClearPlayer and the Heartbeat lifecycle below.
end
-- Studio server-only test surface. No RemoteEvent, and never created in a live server.
if Run:IsStudio()then
 local hook=Instance.new('BindableFunction');hook.Name='CoopCurseTest'
 hook.OnInvoke=function(action,p,m)
  if not Run:IsStudio()then return false end
  if action=='canSpawn'then return M.CanSpawn(p)
  elseif action=='canRemove'then return M.CanRemove(p,m)
  elseif action=='remove'then return M.RemoveAttached(p,m)
  elseif action=='normalAttach'then M.Pickup(p,m);return attached[m]~=nil
  elseif action=='attach'then
   if typeof(p)~='Instance'or not p:IsA('Player')or typeof(m)~='Instance'or not m:IsA('Model')then return false end
   local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
   local id=m:GetAttribute('ItemId')
   if not COOP[id]or not interactive or m.Parent~=interactive then return false end
   return attachItem(p,m,id,true)
  elseif action=='rescue'then
   m=p
   -- Only this private Studio hook may omit a rescuer. Normal RemoveAttached is unchanged.
   if typeof(m)~='Instance'or not m:IsA('Model')or not attached[m]then return false end
   return finishRescue(m)
  elseif action=='soloCheck'then soloSafety(nil,true);return true
  elseif action=='state'then
   if typeof(p)~='Instance'or not p:IsA('Player')then return false end
   local list,ids={},{};for item,state in pairs(attached)do
    if state.owner==p then table.insert(ids,state.id);table.insert(list,{id=state.id,model=item,attributes=item:GetAttributes(),welded=item.PrimaryPart and item.PrimaryPart:FindFirstChild('CursedItemAttachWeld')~=nil or false})end
   end
   return {attributes=p:GetAttributes(),attachedItemIds=ids,attached=list,population=missionCount(nil),override=studioSoloOverride()}
  end
  return false
 end
 hook.Parent=SS
 -- Run privileged test bodies in a normal Studio server task, never the MCP execution context.
 local owner=script.Parent.Parent
 local Http=game:GetService('HttpService')
 local runnerActive=false
 local RUNNERS={playtest='StudioPlaytestRunner',sale='StudioSaleRunner'}
 local function runRequested()
  if not Run:IsStudio()or runnerActive then return end
  local action=owner:GetAttribute('CoopTestRun');local childName=RUNNERS[action]
  if not childName then return end
  runnerActive=true;owner:SetAttribute('CoopTestStatus','running');owner:SetAttribute('CoopTestReport',nil)
  task.spawn(function()
   local ok,result=xpcall(function()
    local child=script:FindFirstChild(childName)
    if not child or not child:IsA('ModuleScript')then error('Missing Studio runner '..childName)end
    local runner=require(child)
    if type(runner)~='function'then error('Studio runner must return a function: '..childName)end
    return runner()
   end,debug.traceback)
   local report
   if ok then
    local encoded,value=pcall(function()
     if type(result)=='string'then
      local decoded=Http:JSONDecode(result)
      if type(decoded)~='table'then error('Runner JSON must contain a report object')end
      return result
     elseif type(result)=='table'then return Http:JSONEncode(result)
     else error('Runner returned no JSON report')end
    end)
    if encoded then report=value else ok=false;result=value end
   end
   if not ok then report=Http:JSONEncode({completed=false,error=tostring(result):sub(1,4096),runner=action})end
   if #report>60000 then report=Http:JSONEncode({completed=false,error='Runner report exceeds 60000-byte report budget',runner=action})end
   owner:SetAttribute('CoopTestReport',report)
   owner:SetAttribute('CoopTestStatus','done')
   owner:SetAttribute('CoopTestRun',nil)
   runnerActive=false
  end)
 end
 -- Studio test spawn: CursedItemsServer attribute StudioSpawnTestItems (comma list) puts those items as real
 -- registered loot in a row in front of each player once per round, after the van placement settles.
 local spawnedRound={}
 local function spawnTestItems(p)
  local list=owner:GetAttribute('StudioSpawnTestItems');if type(list)~='string'or list==''then return end
  local c=p.Character;if not c then return end
  local t=os.clock();repeat task.wait(.25)until not c.Parent or(c:GetAttribute('RecoverySpawnReady')==true and owner:FindFirstChild('PreviewCursedBatch'))or os.clock()-t>40
  local r=c.Parent and c:FindFirstChild('HumanoidRootPart');local preview=owner:FindFirstChild('PreviewCursedBatch')
  if not r or not preview or not living(p)then return end
  local state=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound');local round=state and state:GetAttribute('Round')or 0
  if spawnedRound[p]==round then return end;spawnedRound[p]=round
  task.wait(1)
  local ids={};for id in list:gmatch('[^,%s]+')do table.insert(ids,id)end
  for i,id in ipairs(ids)do
   -- A row on the player's right, away from the cart parked on their left (the cart auto-sells at the van).
   local pos=r.Position+r.CFrame.RightVector*4+r.CFrame.LookVector*((i-(#ids+1)/2)*2.4)+Vector3.new(0,1,0)
   local ok,err=pcall(function()return preview:Invoke(id,pos)end);if not ok then warn('[StudioSpawnTestItems] '..id..': '..tostring(err))end
  end
 end
 local function watchPlayer(p)
  p.CharacterAdded:Connect(function()task.spawn(spawnTestItems,p)end)
  if p.Character then task.spawn(spawnTestItems,p)end
 end
 for _,p in ipairs(Players:GetPlayers())do watchPlayer(p)end;Players.PlayerAdded:Connect(watchPlayer)
 Players.PlayerRemoving:Connect(function(p)spawnedRound[p]=nil end)
 owner:GetAttributeChangedSignal('CoopTestRun'):Connect(runRequested)
 task.defer(runRequested)
end
local acc=0
local function lobbyOnly()
 local state=game:GetService('ReplicatedStorage'):FindFirstChild('LobbyState')
 if not state or state:GetAttribute('Mode')~='Menu' then return false end
 for _,p in ipairs(Players:GetPlayers())do if p:GetAttribute('MissionActive')==true then return false end end
 return true
end
Run.Heartbeat:Connect(function(dt)
 if lobbyOnly()then return end
 acc+=dt;if acc<.25 then return end;acc=0
 local now=workspace:GetServerTimeNow();soloSafety()
 for m,s in pairs(attached)do
  -- Studio solo testing only: with nobody to pull it off, the curse pops off by itself after 15 s.
  if m.Parent and studioSoloOverride()and partyCount()<2 and os.clock()-(s.at or os.clock())>15 then finishRescue(m)
  elseif not m.Parent or not living(s.owner)or s.owner.Character~=s.character then release(m,true)

  end
 end
 local map=workspace:FindFirstChild('Mansion');local interactive=map and map:FindFirstChild('Interactive')
 if interactive then for _,m in ipairs(interactive:GetChildren())do
  local id=m:GetAttribute('ItemId');local key=LEASES[id];local p=key and Players:GetPlayerByUserId(m:GetAttribute('HeldBy')or 0)
  if p and living(p)then
   p:SetAttribute(key,now+LEASE)
   if id=='GuessWhoHands'then
    if not p:GetAttribute('GuessWhoStart')then p:SetAttribute('GuessWhoStart',now)end;attachVisual(p,id)
   elseif id=='FearMirror'then
    if not p:GetAttribute('MirrorFearStart')then p:SetAttribute('MirrorFearStart',now)end
    p:SetAttribute('MirrorMonsterCF',mirrorCF(p))
   end
  end
 end end
 for _,p in ipairs(Players:GetPlayers())do
  if not living(p)or now>=(p:GetAttribute('GuessWhoUntil')or 0)then detachVisual(p,'GuessWhoHands');p:SetAttribute('GuessWhoStart',nil);p:SetAttribute('GuessWhoUntil',nil)end
  if not living(p)or now>=(p:GetAttribute('MirrorFearUntil')or 0)then p:SetAttribute('MirrorFearStart',nil);p:SetAttribute('MirrorFearUntil',nil);p:SetAttribute('MirrorMonsterCF',nil)end
 end
end)
Players.PlayerRemoving:Connect(function(p)departing[p]=true;M.ClearPlayer(p);soloSafety(p)end)
return M



