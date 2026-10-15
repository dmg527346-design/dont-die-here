local Players=game:GetService('Players')
local Audio=require(script.Parent:WaitForChild('GameplayAudioServer'))
local map=workspace:WaitForChild('Mansion',math.huge)
while not map:GetAttribute('RuntimeReady') do map:GetAttributeChangedSignal('RuntimeReady'):Wait()end
local interactive=map:WaitForChild('Interactive')
local watched=setmetatable({},{__mode='k'})
local function watch(model)
 if watched[model] or not model:IsA('Model') then return end
 watched[model]=true
 local held=model:GetAttribute('HeldBy')
 model:GetAttributeChangedSignal('HeldBy'):Connect(function()
  local now=model:GetAttribute('HeldBy');if now==held then return end
  local old=held;held=now
  if model:GetAttribute('Selling') then return end
  local cart=model:GetAttribute('Kind')=='cart'
  if now then Audio.Play(cart and 'CartGrab' or 'ItemPickup',model)
  elseif old then Audio.Play(cart and 'CartRelease' or 'ItemRelease',model)end
 end)
 local cargo=model:GetAttribute('CargoStored')
 model:GetAttributeChangedSignal('CargoStored'):Connect(function()
  local now=model:GetAttribute('CargoStored');if now and not cargo then Audio.Play('CargoStore',model)end;cargo=now
 end)
 local locked=model:GetAttribute('Locked')
 model:GetAttributeChangedSignal('Locked'):Connect(function()
  local now=model:GetAttribute('Locked');if locked and not now then Audio.Play('Unlock',model)end;locked=now
 end)
 local lit=model:GetAttribute('SecretLight')
 model:GetAttributeChangedSignal('SecretLight'):Connect(function()
  local now=model:GetAttribute('SecretLight');if lit~=nil and now~=lit then Audio.Play('FlashlightClick',model)end;lit=now
 end)
 local quiet=model:GetAttribute('Quiet')
 model:GetAttributeChangedSignal('Quiet'):Connect(function()
  local now=model:GetAttribute('Quiet');if now~=quiet then Audio.Play('ClothHandle',model)end;quiet=now
 end)
end
interactive.ChildAdded:Connect(watch)
for _,model in interactive:GetChildren()do watch(model)end
local function playerAdded(player)
 local keys=player:GetAttribute('Keys') or 0
 player:GetAttributeChangedSignal('Keys'):Connect(function()
  local now=player:GetAttribute('Keys') or 0;if now>keys then Audio.ToPlayer(player,'KeyJingle')end;keys=now
 end)
 local hiding=player:GetAttribute('Hiding')
 player:GetAttributeChangedSignal('Hiding'):Connect(function()
  local now=player:GetAttribute('Hiding');if now~=hiding then Audio.ToPlayer(player,'ClothHandle')end;hiding=now
 end)
end
Players.PlayerAdded:Connect(playerAdded)
for _,player in Players:GetPlayers()do playerAdded(player)end
local round=game.ReplicatedStorage:WaitForChild('RecoveryRound',math.huge)
local phase=round:GetAttribute('Phase');local sold=round:GetAttribute('Sold') or 0;local saleStartedSold=sold
round:GetAttributeChangedSignal('Sold'):Connect(function()
 local now=round:GetAttribute('Sold') or 0;if now>sold then Audio.Play('SaleComplete')end;sold=now
end)
round:GetAttributeChangedSignal('Phase'):Connect(function()
 local now=round:GetAttribute('Phase');if now==phase then return end
 local previous=phase;phase=now
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan')
 if now=='Selling' then saleStartedSold=sold;Audio.Play('SaleStart',van)
 elseif previous=='Selling' and now=='Searching' and sold<=saleStartedSold then Audio.Play('SaleCancelled')
 elseif now=='Returning' then Audio.Play('QuotaMet')
 elseif now=='Won' then Audio.Play('RoundWin')
 elseif now=='Failed' then Audio.Play('TeamWipe')
 elseif now=='Searching' and previous~='Selling' then Audio.Play('RoundStart')end
end)
local extraction
round:GetAttributeChangedSignal('ExtractionSeconds'):Connect(function()
 local seconds=round:GetAttribute('ExtractionSeconds');local whole=seconds and math.ceil(seconds)
 if whole and whole~=extraction and whole<=3 and whole>0 then Audio.Play('ClockTick')end;extraction=whole
end)
