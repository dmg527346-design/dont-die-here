-- Only runtime owner of generation, readiness, graph publication and seed selection.
local Players=game:GetService('Players')
Players.CharacterAutoLoads=false
local SS=game:GetService('ServerStorage')
local RunService=game:GetService('RunService')
local R=require(script.Rules)
local P=require(script.Planner)
local V=require(script.Validator)
local B=require(script.Builder)
local G=require(script.GraphExport)
local Profiles=require(script.Profiles)
game:GetService('ReplicatedStorage'):SetAttribute('MapPool',table.concat(Profiles.Kinds,',')) -- map-only client scripts switch off on live servers when their map is not in the pool
local MapLighting=require(script.MapLighting)
local ZFightGuard=require(script.ZFightGuard)
MapLighting.Global()
local startup=os.clock()
local mansion=workspace:WaitForChild('Mansion',math.huge)
-- Live public lobby (not a reserved mission server): nobody enters this map, so it is not Persistent and is parked far from
-- LobbyWorld once built; joining phones no longer download ~8k map instances they never see. Studio: ForceLobbyPark attr tests it
-- (lobby-only tests: a Studio mission started on a parked map uses stale graph coordinates).
local publicLobby=if RunService:IsStudio() then script:GetAttribute('ForceLobbyPark')==true else not(game.PrivateServerId~='' and game.PrivateServerOwnerId==0)
local LOBBY_PARK=Vector3.new(-8000,0,0)
mansion.ModelStreamingMode=if publicLobby then Enum.ModelStreamingMode.Default else Enum.ModelStreamingMode.Persistent
mansion:SetAttribute('LobbyParked',publicLobby or nil) -- MansionLoading: the PLAY cover in a lobby must not wait for this map's parts
mansion:SetAttribute('RuntimeReady',false)
local recoveryPreview=workspace:FindFirstChild('RecoveryPreview');if recoveryPreview then recoveryPreview:Destroy() end
mansion:SetAttribute('Ready',false)
mansion:ClearAllChildren()
local spawn=workspace:FindFirstChildOfClass('SpawnLocation')
local loading={}
local function hold(player,char)
 local root=char:WaitForChild('HumanoidRootPart',12)
 if not root or mansion:GetAttribute('Ready') then return end
 -- Public lobby (menu): the player never enters this map, so their character is not frozen while it generates.
 local lobbyState=game:GetService('ReplicatedStorage'):FindFirstChild('LobbyState')
 if game.PrivateServerId=='' and lobbyState and lobbyState:GetAttribute('Mode')=='Menu' then return end
 loading[player]=root;root.Anchored=true
end
local function added(p)
 p.CharacterAdded:Connect(function(char) hold(p,char) end)
 if p.Character then task.spawn(hold,p,p.Character) end
end
Players.PlayerAdded:Connect(added);Players.PlayerRemoving:Connect(function(p) loading[p]=nil end)
for _,p in ipairs(Players:GetPlayers()) do added(p) end
local function release()
 for p,root in pairs(loading) do
  if p.Parent and root.Parent then if not game.ServerScriptService:FindFirstChild('RecoveryRoundServer') then root.CFrame=spawn.CFrame*CFrame.new(0,3,0);root.Anchored=false end end
 end
 table.clear(loading)
end
local attempts={};local stage;local accepted
local force=if RunService:IsStudio() then script:GetAttribute('ForceSeed') else nil
local initial=force or Random.new():NextInteger(1,2147480000)
local mapKind,sizeClass=Profiles.Select(initial,if RunService:IsStudio() then script:GetAttribute('ForceMapKind') else nil,if RunService:IsStudio() then script:GetAttribute('ForceSizeClass') else nil,true) -- the startup map is level 1's: Profiles.FirstLevelKinds
mansion:SetAttribute('MapKind',mapKind);mansion:SetAttribute('SizeClass',sizeClass)
local success,err=xpcall(function()
 local kit=SS:WaitForChild('MapKit',15);assert(kit,'MapKit missing')
 local good,why=V.Kit(kit);assert(good,table.concat(why,'; '))
 for attempt=1,R.MaxAttempts do
  local seed=initial+attempt-1;local count=math.max(1,#Players:GetPlayers())
  local t0=os.clock() -- startup timing attributes (PlanSeconds/BuiltCheckSeconds/PathSeconds/LightingSeconds)
  local plan=if force then P.Generate(seed,count,mapKind,sizeClass) else P.Best(seed,6,V.Plan,count,mapKind,sizeClass)
  mansion:SetAttribute('PlanSeconds',(mansion:GetAttribute('PlanSeconds') or 0)+os.clock()-t0)
  seed=plan.seed
  local valid,reasons=V.Plan(plan)
  if valid then
   local ok,result=pcall(B.Build,plan,kit,workspace)
   if ok then
    stage=result;stage.Name='MansionBuild'
    t0=os.clock();valid,reasons=V.Built(plan,stage);mansion:SetAttribute('BuiltCheckSeconds',(mansion:GetAttribute('BuiltCheckSeconds') or 0)+os.clock()-t0)
    if valid then t0=os.clock();valid,reasons=V.Paths(plan,stage);mansion:SetAttribute('PathSeconds',(mansion:GetAttribute('PathSeconds') or 0)+os.clock()-t0) end
    if valid then accepted=plan;break end
   else reasons={tostring(result)};valid=false end
  end
  table.insert(attempts,{seed=seed,reasons=reasons})
  warn('[MapGen] rejected seed '..seed..': '..table.concat(reasons,'; '))
  if stage then stage:Destroy();stage=nil end
  for _,m in ipairs(workspace:GetChildren()) do if m~=mansion and m:IsA('Model') and m:GetAttribute('Seed') and not m:GetAttribute('Ready') then m:Destroy() end end
  if force then break end
 end
 if accepted then
  mansion:ClearAllChildren()
  for _,child in ipairs(stage:GetChildren()) do child.Parent=mansion end
  for name,value in pairs(stage:GetAttributes()) do mansion:SetAttribute(name,value) end
  G.Publish(accepted,mansion);mansion:SetAttribute('PlanHash',P.Hash(accepted));mansion:SetAttribute('LegacyFallback',false);mansion:SetAttribute('TemplateFallback',false)
  if spawn then spawn.CFrame=CFrame.new(unpack(accepted.spawn))*CFrame.new(0,-2.5,0) end
  stage:Destroy();stage=nil
  print(('[MapGen] kind=%s size=%s seed=%d shape=%s rooms=%d hash=%s build=%.3fs'):format(mapKind,sizeClass,accepted.seed,accepted.shape,#accepted.rooms,P.Hash(accepted),mansion:GetAttribute('BuildSeconds')))
 else error('No valid generated map after '..#attempts..' attempts') end
end,debug.traceback)
if not success then
 if stage then stage:Destroy() end
 -- Remove any partially built models left by an exception inside Builder.
 for _,m in ipairs(workspace:GetChildren()) do if m~=mansion and m:IsA('Model') and m:GetAttribute('Seed') and not m:GetAttribute('Ready') then m:Destroy() end end
 warn('[MapGen] generation fallback: '..tostring(err))
 local reserves=SS:FindFirstChild('MapFallbacks')
 local reserve=reserves and reserves:FindFirstChild(mapKind..'_'..sizeClass)
 if reserve then
  local saved=reserve:Clone();mansion:ClearAllChildren()
  for _,child in ipairs(saved:GetChildren()) do child.Parent=mansion end
  for name,value in pairs(saved:GetAttributes()) do mansion:SetAttribute(name,value) end
  saved:Destroy();mansion:SetAttribute('TemplateFallback',true);mansion:SetAttribute('LegacyFallback',false)
  B.BindKeyFollowers(mansion)
  if spawn then spawn.CFrame=CFrame.new(mansion:GetAttribute('SpawnPosition'))*CFrame.new(0,-2.5,0) end
 else
 local legacy=assert(SS:FindFirstChild('LegacyMansion'),'LegacyMansion missing'):Clone()
 mansion:ClearAllChildren();for _,child in ipairs(legacy:GetChildren()) do child.Parent=mansion end;legacy:Destroy()
 local graph=require(SS.MapGenBackup.CreatureRoamServer.MansionRoomGraph)
 mansion:SetAttribute('RoomCount',#graph.rooms);mansion:SetAttribute('Shape','Legacy');mansion:SetAttribute('BuildSeconds',0);mansion:SetAttribute('FurnitureSkipped',0);mansion:SetAttribute('PlanHash','legacy')
 local value=Instance.new('StringValue');value.Name='GeneratedGraph';value.Value=game:GetService('HttpService'):JSONEncode(graph);value.Parent=mansion
 mansion:SetAttribute('LegacyFallback',true);mansion:SetAttribute('Seed',initial)
 if spawn then spawn.CFrame=CFrame.new(0,.55,106) end
 local legacyOK,legacyError=pcall(require(script.LegacyLocks),mansion)
 if not legacyOK then warn('[MapGen] legacy lock setup failed: '..tostring(legacyError)) end
 end
end
do local t0=os.clock()
MapLighting.Apply(mansion,game:GetService('HttpService'):JSONDecode(mansion.GeneratedGraph.Value),SS.MapKit)
mansion:SetAttribute('LightingSeconds',(mansion:GetAttribute('LightingSeconds') or 0)+os.clock()-t0) end
-- Dressing lays trim, stains and cards flush on other parts; pull visible coplanar faces apart (z-fighting).
-- Z-fight guard runs right after the map is marked Ready: it only nudges faces 0.02 studs (no parts added or removed),
-- so players load in while it works instead of waiting 3-5 s at every level start (2026-10-23).
local function zFightLater()
 local revision=mansion:GetAttribute('WorldRevision')
 task.spawn(function()
  if mansion:GetAttribute('WorldRevision')~=revision then return end
  local ok,err=pcall(ZFightGuard.Apply,mansion);if not ok then warn('[MapGen] z-fight guard failed: '..tostring(err))end
 end)
end
local failures=Instance.new('StringValue');failures.Name='GenerationFailures';failures.Value=game:GetService('HttpService'):JSONEncode(attempts);failures.Parent=mansion
if publicLobby then
 mansion:PivotTo(mansion:GetPivot()+LOBBY_PARK)
 -- World-space attributes written during the build move with it: InteractServer also runs on lobbies (lobby toys) and
 -- re-poses every door/drawer from ClosedPivot; keys keep an Approach CFrame. DrawerOffset and Footprint are relative.
 local at=mansion:GetAttribute('SpawnPosition');if typeof(at)=='Vector3' then mansion:SetAttribute('SpawnPosition',at+LOBBY_PARK)end
 for _,d in ipairs(mansion:GetDescendants())do for _,name in {'ClosedPivot','Approach'}do local cf=d:GetAttribute(name);if typeof(cf)=='CFrame' then d:SetAttribute(name,cf+LOBBY_PARK)end end end
 -- Characters first appear on the SpawnLocation (invisible, no collision): keep it on the lobby so streaming starts there.
 local world=workspace:FindFirstChild('LobbyWorld');local point=world and world:FindFirstChild('SpawnPoint')
 if spawn and point and point:IsA('BasePart') then spawn.CFrame=CFrame.new(point.Position+Vector3.new(0,3,0)) end
end
local partCount=0
for _,p in ipairs(mansion:GetDescendants()) do if p:IsA('BasePart') then partCount+=1;p:SetAttribute('GenerationPartId',partCount) end end
mansion:SetAttribute('ExpectedMapParts',partCount);mansion:SetAttribute('StartupSeconds',os.clock()-startup)
-- Keys and padlocks disappear during play. Late joiners must wait for the
-- current replicated map, rather than the original pre-pickup part count.
local countAdded,countRemoved
local function trackParts()
countAdded=mansion.DescendantAdded:Connect(function(p)
 if p:IsA('BasePart') and p:GetAttribute('GenerationPartId') then partCount+=1;mansion:SetAttribute('ExpectedMapParts',partCount) end
end)
countRemoved=mansion.DescendantRemoving:Connect(function(p)
 if p:IsA('BasePart') and p:GetAttribute('GenerationPartId') then partCount-=1;mansion:SetAttribute('ExpectedMapParts',partCount) end
end)
end
trackParts()
mansion:SetAttribute('Ready',true);mansion:SetAttribute('RuntimeReady',true);release();zFightLater()

-- Whole-run rebuild, requested by RecoveryRoundServer after a party wipe.
local regenerate=Instance.new('BindableFunction');regenerate.Name='RegenerateMissionMap';regenerate.Parent=script
-- Map type and size for a rebuild: wantKind/wantSize when given and allowed, else random, never the map just played.
local function pickKind(wantKind,wantSize,oldKind)
 local candidates={};for _,kind in ipairs(Profiles.Kinds)do if kind~=oldKind or(kind==wantKind and type(wantSize)=='string')then table.insert(candidates,kind)end end
 local random=Random.new();local kind=if type(wantKind)=='string'and table.find(candidates,wantKind)then wantKind else candidates[random:NextInteger(1,#candidates)];local sizes=Profiles.KindSizes[kind] or Profiles.Sizes
 return kind,Profiles.NormalizeSize(kind,if kind==wantKind and type(wantSize)=='string'and table.find(sizes,wantSize)then wantSize else sizes[random:NextInteger(1,#sizes)]) -- per-kind sizes (Cruise has no Compact)
end
-- The next level's plan is worked out during the level-clear recap (RecoveryRoundServer fires PrepareNextMap), so the
-- rebuild behind the loading cover starts at the build step; a plan whose type/size/party no longer fit is dropped (2026-10-25).
local prepared,preparing
local prepare=Instance.new('BindableEvent');prepare.Name='PrepareNextMap';prepare.Parent=script
prepare.Event:Connect(function(wantKind,wantSize)
 if preparing or mansion:GetAttribute('Rebuilding')then return end
 preparing=true;prepared=nil
 local ok,err=pcall(function()
  local kind,size=pickKind(wantKind,wantSize,mansion:GetAttribute('MapKind'))
  local count=math.max(1,#Players:GetPlayers());local seed=Random.new():NextInteger(1,2147470000)
  -- Short slices: the recap has ~6 s, and 0.1 s slices showed as ~110 ms hitches on the win screen (2026-10-25).
  P.YieldEvery=0.006;local plan=P.Best(seed,6,V.Plan,count,kind,size)
  if V.Plan(plan)then prepared={kind=kind,size=size,count=count,seed=seed,plan=plan}end
 end)
 P.YieldEvery=0.1
 if not ok then warn('[MapGen] next-map plan failed: '..tostring(err))end
 preparing=false
end)
regenerate.OnInvoke=function(wantKind,wantSize) -- wantKind: optional map type (RecoveryRoundServer's per-save bag); wantSize: optional size (owner test rotation)
 if mansion:GetAttribute('Rebuilding')then return false,'A rebuild is already running.'end
 countAdded:Disconnect();countRemoved:Disconnect()
 mansion:SetAttribute('Rebuilding',true);mansion:SetAttribute('Ready',false);mansion:SetAttribute('RuntimeReady',false)
 local oldPivot=mansion:GetPivot();local oldKind=mansion:GetAttribute('MapKind');local oldExpected=mansion:GetAttribute('ExpectedMapParts')
 mansion:SetAttribute('ExpectedMapParts',nil);mansion:PivotTo(oldPivot+Vector3.new(0,4096,0))
 local fresh,plan
 local ok,message=xpcall(function()
  local kind,size=pickKind(wantKind,wantSize,oldKind)
  local seed=Random.new():NextInteger(1,2147470000)
  local waitUntil=os.clock()+3;while preparing and os.clock()<waitUntil do task.wait()end
  local early=prepared;prepared=nil
  if early and not(early.kind==kind and(type(wantSize)~='string'or early.size==size)and early.count==math.max(1,#Players:GetPlayers()))then early=nil end
  if early then size=early.size;seed=early.seed end
  mansion:SetAttribute('PreparedPlanUsed',early~=nil)
  local buildLog={} -- one entry per attempt: why it failed and how long it took (BuildLog attribute)
  for attempt=1,R.MaxAttempts do
   local t0=os.clock()
   local candidate=if attempt==1 and early then early.plan else P.Best(seed+attempt-1,6,V.Plan,math.max(1,#Players:GetPlayers()),kind,size)
   local t1=os.clock();local why='plan'
   if V.Plan(candidate)then
    local built,result=pcall(B.Build,candidate,SS.MapKit,workspace)
    why=built and 'built' or 'build error'
    if built then
     local valid,errs=V.Built(candidate,result);if not valid then why='checks('..tostring(errs and errs[1])..' +'..(errs and #errs-1 or 0)..')' else valid=V.Paths(candidate,result);if not valid then why='paths' end end
     table.insert(buildLog,('%d:%s %.1f+%.1fs'):format(attempt,valid and 'ok' or why,t1-t0,os.clock()-t1))
     if valid then fresh=result;plan=candidate;break end
     result:Destroy()
    else table.insert(buildLog,('%d:%s %.1fs'):format(attempt,why,os.clock()-t0))end
   else table.insert(buildLog,('%d:plan %.1fs'):format(attempt,os.clock()-t0))end
  end
  mansion:SetAttribute('BuildLog',kind..' '..table.concat(buildLog,' '))
  if not fresh then fresh=assert(SS.MapFallbacks:FindFirstChild(kind..'_'..size),'New-map fallback missing'):Clone();fresh.Parent=workspace
  else G.Publish(plan,fresh)end
  local pivot=fresh:GetPivot()
  fresh:SetAttribute('PlanHash',plan and P.Hash(plan)or ('fallback:'..tostring(fresh:GetAttribute('Seed'))))
  fresh:SetAttribute('TemplateFallback',plan==nil);fresh:SetAttribute('LegacyFallback',false)
  mansion:SetAttribute('LootReady',false);mansion:SetAttribute('AvailableLootValue',0);mansion:SetAttribute('NextDangerPulse',nil)
  -- Keep client references to Mansion and its folders valid.
  for _,child in ipairs(mansion:GetChildren())do
   local replacement=fresh:FindFirstChild(child.Name)
   if child:IsA('Folder')and replacement and replacement:IsA('Folder')then
    child:ClearAllChildren();for _,object in ipairs(replacement:GetChildren())do object.Parent=child end;replacement:Destroy()
   elseif child:IsA('StringValue')and replacement and replacement:IsA('StringValue')then child.Value=replacement.Value;replacement:Destroy()
   else child:Destroy()end
  end
  for _,child in ipairs(fresh:GetChildren())do child.Parent=mansion end
  -- Synchronize rendering guards, including absent values, on the persistent root.
  for _,name in ipairs({'MallDressingVersion','SteadyLightingVersion','StoneFinishVersion','SculptedWalls','ManorReferenceVersion','MaterialFinishVersion','CruiseWorldVersion','HospitalDressingVersion','HotelDressingVersion','SchoolDressingVersion','RevampDressingVersion','AngledCorners','AngledCornerData'})do
   mansion:SetAttribute(name,fresh:GetAttribute(name))
  end
  for name,value in pairs(fresh:GetAttributes())do if name~='Ready'and name~='RuntimeReady'then mansion:SetAttribute(name,value)end end
  mansion.WorldPivot=pivot;fresh:Destroy();fresh=nil;MapLighting.Global(mansion:GetAttribute('MapKind'))
  local lightingOK,lightingError=pcall(function()
   local graph=game:GetService('HttpService'):JSONDecode(mansion.GeneratedGraph.Value)
   MapLighting.Apply(mansion,graph,SS.MapKit)
  end)
  if not lightingOK then warn('[MapGen] regenerated lighting/dressing failed: '..tostring(lightingError)) end
  partCount=0
  for _,object in ipairs(mansion:GetDescendants())do if object:IsA('BasePart')then partCount+=1;object:SetAttribute('GenerationPartId',partCount)end end
  mansion:SetAttribute('ExpectedMapParts',partCount);mansion:SetAttribute('WorldRevision',(mansion:GetAttribute('WorldRevision')or 0)+1)
  if spawn then spawn.CFrame=CFrame.new(mansion:GetAttribute('SpawnPosition'))*CFrame.new(0,-2.5,0)end
 end,debug.traceback)
 if not ok then if fresh then fresh:Destroy()end;mansion:PivotTo(oldPivot);mansion:SetAttribute('ExpectedMapParts',oldExpected)end
 trackParts()
 mansion:SetAttribute('Ready',true);mansion:SetAttribute('RuntimeReady',true);mansion:SetAttribute('Rebuilding',false)
 if ok then zFightLater()end
 return ok,ok and {kind=mansion:GetAttribute('MapKind'),seed=mansion:GetAttribute('Seed'),revision=mansion:GetAttribute('WorldRevision')}or message
end

