-- The Roblox player list (Tab, with its Server / Friends tabs) never shows in this game; Tab is the map key.
-- Roblox's list still toggles open on every Tab press even while it is switched off, so after each Tab press
-- (and once after loading) the setting is flipped on and straight back off, which closes it within a frame.
do
 local StarterGui=game:GetService('StarterGui')
 local UIS=game:GetService('UserInputService')
 local function hidePlayerList(flip)
  if flip then pcall(StarterGui.SetCoreGuiEnabled,StarterGui,Enum.CoreGuiType.PlayerList,true) end
  pcall(StarterGui.SetCoreGuiEnabled,StarterGui,Enum.CoreGuiType.PlayerList,false)
 end
 local function closeAfterTab(input)
  if input.KeyCode~=Enum.KeyCode.Tab then return end
  hidePlayerList(true);task.defer(hidePlayerList,true);task.delay(.1,hidePlayerList,true);task.delay(.3,hidePlayerList,true)
 end
 hidePlayerList(false)
 UIS.InputBegan:Connect(closeAfterTab);UIS.InputEnded:Connect(closeAfterTab)
 task.spawn(function()
  if not game:IsLoaded() then game.Loaded:Wait() end
  for _,delay in {1,4,10} do task.wait(delay);hidePlayerList(true) end
 end)
end
local Players=game:GetService('Players')
local TweenService=game:GetService('TweenService')
local loadingStarted=os.clock() -- LoadingSeconds attribute: how long this cover stayed up (tuning the menu opening)
local missionEntry=script:GetAttribute('MissionEntry')==true
local runRestart=script:GetAttribute('RunRestart')==true
local Teleport=game:GetService('TeleportService')
local arriving=Teleport:GetArrivingTeleportGui()
if arriving then missionEntry=true end
-- Leaving a run teleports to a PUBLIC lobby with {lobbyReturn=...}: that arrival is not a private-server entry.
local arrivalData=Teleport:GetLocalPlayerTeleportData()
if type(arrivalData)=='table'and arrivalData.lobbyReturn then missionEntry=false end
local gui=Instance.new('ScreenGui');gui.Name='MansionLoading';gui.IgnoreGuiInset=true;gui.ScreenInsets=Enum.ScreenInsets.None;gui.ResetOnSpawn=false;gui.DisplayOrder=10000;gui.Parent=Players.LocalPlayer:WaitForChild('PlayerGui')
local frame=Instance.new('Frame');frame.Size=UDim2.fromScale(1,1);frame.BackgroundColor3=Color3.fromRGB(9,8,10);frame.BorderSizePixel=0;frame.Parent=gui
local label=Instance.new('TextLabel');label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5);label.Size=UDim2.fromScale(.8,.1);label.BackgroundTransparency=1;label.Font=Enum.Font.Garamond;label.TextSize=28;label.TextColor3=Color3.fromRGB(216,200,171);label.Name='LoadingMessage';label.Text=runRestart and 'Creating a new world...'or missionEntry and 'Joining your private server...'or 'Something is taking shape...';label.Parent=frame
if arriving then arriving:Destroy()end
if missionEntry then Teleport:SetTeleportGui(gui:Clone())end
game:GetService('ReplicatedFirst'):RemoveDefaultLoadingScreen()
local initialState=game:GetService('ReplicatedStorage'):WaitForChild('LobbyState')
-- Mesh preload runs alongside the entry wait below; the cover waits for it at most PRELOAD_WAIT seconds from its start
-- (was a fixed 8 s before the entry wait even began). Requests continue in the background after the cover lifts.
local PRELOAD_WAIT=if runRestart then 1.5 else 4 -- next level: most meshes are cached from the last one (was 4, 2026-10-25)
local preloaded,preloadBegan=true,os.clock()
-- Only mission entry needs the generated mission map and its assets.
-- The PLAY cover inside a public lobby (MissionEntry clone) skips it: that lobby's map is parked and never streams in.
local function parkedLobbyMap()local m=workspace:FindFirstChild('Mansion');return m~=nil and m:GetAttribute('LobbyParked')==true end
-- An arrival on a lobby (Mode 'Menu') never waits for a map either; only the PLAY clone (MissionEntry attr) may.
if(missionEntry or initialState:GetAttribute('Mode')~='Menu')and not parkedLobbyMap()and not(script:GetAttribute('MissionEntry')~=true and initialState:GetAttribute('Mode')=='Menu')then
local mansion=workspace:WaitForChild('Mansion',math.huge)
while mansion:GetAttribute('Ready')~=true do mansion:GetAttributeChangedSignal('Ready'):Wait() end
while not mansion:GetAttribute('ExpectedMapParts') do task.wait() end
-- Map parts are counted as they replicate (one scan, then events) instead of walking every descendant ten times a
-- second: on a phone that walk over 20k+ instances competed with the very download it waited for (2026-10-25).
local count,content,seen=0,{},{}
local function arrived(p)
 if not p:IsA('BasePart') then return end
 if p:GetAttribute('GenerationPartId') then count+=1 end
 -- Preload the parts, not their id strings: a bare id preloads as an image ('Asset type does not match').
 if p:IsA('MeshPart') and not seen[p.MeshId] then seen[p.MeshId]=true;table.insert(content,p) end
end
local addedCon=mansion.DescendantAdded:Connect(arrived)
local removedCon=mansion.DescendantRemoving:Connect(function(p) if p:IsA('BasePart') and p:GetAttribute('GenerationPartId') then count-=1 end end)
for _,p in ipairs(mansion:GetDescendants()) do arrived(p) end
while count<(mansion:GetAttribute('ExpectedMapParts') or 0) and not parkedLobbyMap() do task.wait(.05) end
addedCon:Disconnect();removedCon:Disconnect()
local titles={Mansion='the mansion',Dungeon='the infested dungeon',Birthday='the birthday party',Mall='the abandoned mall',Cruise='the abandoned cruise ship',Hospital='the abandoned hospital',Hotel='the haunted hotel',School='the abandoned elementary school'}
label.Text='Entering '..(titles[mansion:GetAttribute('MapKind')] or 'the darkness')..'...'
preloaded=false;preloadBegan=os.clock()
task.spawn(function()
 local ok,err=pcall(function() game:GetService('ContentProvider'):PreloadAsync(content) end)
 if not ok then warn('[MansionLoading] mesh preload: '..tostring(err)) end
 preloaded=true
end)
end
local player=Players.LocalPlayer
-- The server itself decides: a lobby (LobbyState.Mode 'Menu') never waits for a mission, whatever teleport GUI came along.
local function lobbyServer()local st=game:GetService('ReplicatedStorage'):FindFirstChild('LobbyState');return st~=nil and st:GetAttribute('Mode')=='Menu'end
-- Only the arrival copy (ReplicatedFirst) checks this; the menu's launch copy (MissionEntry attr) must keep its wait on the lobby.
local arrivalCopy=script:GetAttribute('MissionEntry')~=true
if missionEntry and arrivalCopy and lobbyServer()then missionEntry=false end
-- In the van for real: spawn acknowledged (RecoverySpawnReady), the character within 12 studs of its placement, and
-- the round on a deployed level with a real quota. A restart in the same server keeps the old character's
-- RecoverySpawnReady=true and the previous run's Phase/Quota for a moment, which used to drop the cover early.
-- ENTRY_TIMEOUT is the hard limit so a missed signal can never leave a black screen forever.
local ENTRY_TIMEOUT=25
local entryStarted=os.clock()
local function placed()
 local c=player.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
 if not r or c:GetAttribute('RecoverySpawnReady')~=true then return false end
 local st=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 local phase=st and st:GetAttribute('Phase')
 if not(phase=='Deploying'or phase=='Searching'or phase=='Selling'or phase=='Returning')or(st:GetAttribute('Quota')or 0)<=0 then return false end
 local at=c:GetAttribute('RecoverySpawnCFrame')
 return typeof(at)~='CFrame'or(r.Position-at.Position).Magnitude<=12
end
if missionEntry then
 label.Text=runRestart and 'Resetting your run...'or 'Joining your private server...'
 while player:GetAttribute('MissionActive')~=true and not(arrivalCopy and lobbyServer()and player:GetAttribute('LobbyReady')==true)do
  local deadline=script:GetAttribute('Countdown')
  if deadline and workspace:GetServerTimeNow()<deadline then label.Text='Starting in '..math.max(1,math.ceil(deadline-workspace:GetServerTimeNow()))..'...'
  else label.Text='Joining your private server...'end
  task.wait(.05)
 end
 label.Text='Preparing safe entry...'
 while player:GetAttribute('MissionActive')==true and not placed()and os.clock()-entryStarted<ENTRY_TIMEOUT do task.wait(.05)end
else
 label.Text='Preparing safe entry...'
 if player:GetAttribute('LobbyReady')==true then label.Text='Opening main menu...'end
 while not(player:GetAttribute('LobbyReady')==true and player.Character and player.Character:GetAttribute('LobbySpawnReady')==true and player.Character:FindFirstChild('HumanoidRootPart')) and not(player:GetAttribute('MissionActive')==true and placed())and os.clock()-entryStarted<ENTRY_TIMEOUT*2 do task.wait(.05)end
end

while not preloaded and os.clock()-preloadBegan<PRELOAD_WAIT do task.wait(.05)end
pcall(function()Players.LocalPlayer:SetAttribute('LoadingSeconds',math.floor((os.clock()-loadingStarted)*100)/100)end)
local tw=TweenService:Create(frame,TweenInfo.new(.45),{BackgroundTransparency=1});TweenService:Create(label,TweenInfo.new(.35),{TextTransparency=1}):Play();tw:Play();tw.Completed:Wait();gui:Destroy()


