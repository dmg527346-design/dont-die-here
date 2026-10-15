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
local missionEntry=script:GetAttribute('MissionEntry')==true
local runRestart=script:GetAttribute('RunRestart')==true
local Teleport=game:GetService('TeleportService')
local arriving=Teleport:GetArrivingTeleportGui()
if arriving then missionEntry=true end
-- Leaving a run teleports to a PUBLIC lobby with {lobbyReturn=...}: that arrival is not a private-server entry.
local arrivalData=Teleport:GetLocalPlayerTeleportData()
if type(arrivalData)=='table'and arrivalData.lobbyReturn then missionEntry=false end
local gui=Instance.new('ScreenGui');gui.Name='MansionLoading';gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=10000;gui.Parent=Players.LocalPlayer:WaitForChild('PlayerGui')
local frame=Instance.new('Frame');frame.Size=UDim2.fromScale(1,1);frame.BackgroundColor3=Color3.fromRGB(9,8,10);frame.BorderSizePixel=0;frame.Parent=gui
local label=Instance.new('TextLabel');label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5);label.Size=UDim2.fromScale(.8,.1);label.BackgroundTransparency=1;label.Font=Enum.Font.Garamond;label.TextSize=28;label.TextColor3=Color3.fromRGB(216,200,171);label.Name='LoadingMessage';label.Text=runRestart and 'Creating a new world...'or missionEntry and 'Joining your private server...'or 'Something is taking shape...';label.Parent=frame
if arriving then arriving:Destroy()end
if missionEntry then Teleport:SetTeleportGui(gui:Clone())end
game:GetService('ReplicatedFirst'):RemoveDefaultLoadingScreen()
local mansion=workspace:WaitForChild('Mansion',math.huge)
while mansion:GetAttribute('Ready')~=true do mansion:GetAttributeChangedSignal('Ready'):Wait() end
while not mansion:GetAttribute('ExpectedMapParts') do task.wait() end
while true do
 local expected=mansion:GetAttribute('ExpectedMapParts')
 local count=0;for _,p in ipairs(mansion:GetDescendants()) do if p:IsA('BasePart') and p:GetAttribute('GenerationPartId') then count+=1 end end
 if count>=expected then break end;task.wait(.1)
end
local content={};local seen={}
for _,p in ipairs(mansion:GetDescendants()) do if p:IsA('MeshPart') and not seen[p.MeshId] then seen[p.MeshId]=true;table.insert(content,p.MeshId) end end
local titles={Mansion='the mansion',Dungeon='the infested dungeon',Birthday='the birthday party',Mall='the abandoned mall',Cruise='the abandoned cruise ship',Hospital='the abandoned hospital',Hotel='the haunted hotel',School='the abandoned elementary school'}
label.Text='Entering '..(titles[mansion:GetAttribute('MapKind')] or 'the darkness')..'...'
local preloaded=false
task.spawn(function()
 local ok,err=pcall(function() game:GetService('ContentProvider'):PreloadAsync(content) end)
 if not ok then warn('[MansionLoading] mesh preload: '..tostring(err)) end
 preloaded=true
end)
-- An asset delivery request must not leave a complete, replicated map behind
-- a permanent black screen. Requests continue in the background after timeout.
local began=os.clock()
repeat task.wait(.05) until preloaded or os.clock()-began>=8
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
 while player:GetAttribute('LobbyReady')~=true and not(player:GetAttribute('MissionActive')==true and placed())and os.clock()-entryStarted<ENTRY_TIMEOUT*2 do task.wait(.05)end
end

local tw=TweenService:Create(frame,TweenInfo.new(.45),{BackgroundTransparency=1});TweenService:Create(label,TweenInfo.new(.35),{TextTransparency=1}):Play();tw:Play();tw.Completed:Wait();gui:Destroy()


