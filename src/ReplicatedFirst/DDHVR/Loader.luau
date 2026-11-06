-- Invoked only by Bootstrap after VRService.VREnabled. No original stored source or Enabled property changes.
local M={}
local started=false
function M.Start()
 if started then return end
 started=true
 local player=game:GetService('Players').LocalPlayer
 local scripts=player:WaitForChild('PlayerScripts')
 local controllers=script.Parent:WaitForChild('Controllers')
 local names={}
 for _,module in controllers:GetChildren() do names[module.Name]=module end
 local enabled={}
 -- ReplicatedFirst installs this before normal StarterPlayerScripts start.
 local function pause(original)
  if original:IsA('LocalScript') and names[original.Name] then
   if enabled[original]==nil then enabled[original]=original.Enabled end
   if enabled[original] then original.Enabled=false end
  end
 end
 scripts.ChildAdded:Connect(pause)
 for _,original in scripts:GetChildren() do pause(original) end
 -- VR can become ready after PlayerScripts. Remove only UI owned by the controllers being replaced.
 local owned={InteractGui=true,GameplayReticle=true,PanelLookHint=true,SprintGui=true,LobbySprintHud=true,
  CrouchGui=true,CursedHud=true,CoopHelpHud=true,FieldMapScreen=true,FieldMapGui=true,LobbyBoardUI=true,
  RecoveryQuota=true,RecoverySpectator=true,MonsterJumpscare=true,QuietCaught=true,
  MonsterWinCutscene=true,LemonSqueeze=true,FlashlightGui=true,CruiseBoatHud=true,MovementVignette=true,
  QuestLog=true,QuestToast=true,MasteryHud=true,MasteryBoardUI=true,VanShop=true}
 for _,gui in player:WaitForChild('PlayerGui'):GetChildren() do if owned[gui.Name] then gui:Destroy() end end
 local camera=workspace.CurrentCamera
 if camera then
  for _,object in camera:GetChildren() do
   if object.Name=='FakeHands' or object.Name=='FieldMapView' or object.Name=='LobbyCircleSign' then object:Destroy() end
  end
 end
 local light=workspace:FindFirstChild('LocalFlashlight');if light then light:Destroy() end
 local lobby=workspace:FindFirstChild('LobbyWorld')
 if lobby then
  for _,object in lobby:GetDescendants() do
   if object:IsA('BillboardGui') and object.Name=='LobbyStoreLabel' then object:Destroy() end
  end
 end
 local support=require(script.Parent:WaitForChild('Support'))
 support.Start()
 -- All templates are ready before any replacement is allowed to run.
 local ready={}
 for name,module in names do
  local original=scripts:WaitForChild(name,30)
  if not original or not original:IsA('LocalScript') then error('VR controller missing: '..name) end
  if enabled[original]==nil then pause(original) end
  -- Preserve deliberately parked features, including the disabled cruise-boat controller.
  if enabled[original] then
   local run=require(module)
   local instance=original:Clone()
   if name=='VanShopClient' then
    for _,child in instance:GetChildren() do
     if child:IsA('BindableEvent') or child:IsA('BindableFunction') then child:Destroy() end
    end
   end
   instance.Name=name..'VR'
   instance.Enabled=false
   instance:SetAttribute('DDHVRVersion',1)
   instance.Parent=scripts
   table.insert(ready,{run=run,instance=instance,name=name})
  end
 end
 for _,entry in ready do
  task.spawn(function()
   local ok,reason=xpcall(entry.run,debug.traceback,entry.instance,support)
   if not ok then warn('DDH VR '..entry.name..': '..tostring(reason)) end
  end)
 end
 require(script.Parent:WaitForChild('UI')).Start()
 player:SetAttribute('DDHVRClientReady',true)
end
return M
