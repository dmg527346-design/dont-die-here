-- Only activate with an actual VRService flag, including headsets initialized after ReplicatedFirst starts.
local VR=game:GetService('VRService')
local connection
local activated=false
local function activate()
 if activated or not VR.VREnabled then return end
 activated=true
 if connection then connection:Disconnect() end
 require(script.Parent:WaitForChild('DDHVR'):WaitForChild('Loader')).Start()
end
connection=VR:GetPropertyChangedSignal('VREnabled'):Connect(activate)
activate()
