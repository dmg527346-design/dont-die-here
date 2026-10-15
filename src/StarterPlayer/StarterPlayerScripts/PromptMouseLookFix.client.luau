local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
-- Roblox's built-in prompt UI puts a clickable button on every visible ProximityPrompt. In first person the
-- locked cursor sits at screen centre, right on top of the prompt you are looking at, so that button swallowed
-- mouse movement and the camera stopped turning while an [E] prompt was up (WASD kept working).
-- In missions, mouse/keyboard and gamepad players use their key, so clicking is off;
-- touch keeps tap-to-use. The free-cursor lobby allows authored clickable prompts on every input. Local only.
local player=game:GetService('Players').LocalPlayer
local state=game:GetService('ReplicatedStorage'):WaitForChild('LobbyState')
local tracked=setmetatable({},{__mode='k'})
local function wantsClick()
 return state:GetAttribute('Mode')=='Menu' and player:GetAttribute('LobbyReady')==true and player:GetAttribute('MissionActive')~=true or player:GetAttribute('MissionActive')==true and player:GetAttribute('RoundDead')==true or InputHints.Get()=='touch'
end
local clickable=wantsClick()
local function apply(prompt)
 if tracked[prompt]==nil then tracked[prompt]=prompt.ClickablePrompt end -- the prompt's own setting
 prompt.ClickablePrompt=clickable and tracked[prompt]
end
local function consider(x)if x:IsA('ProximityPrompt')then apply(x)end end
for _,x in workspace:GetDescendants()do consider(x)end
workspace.DescendantAdded:Connect(consider)
local function refresh()
 local now=wantsClick()
 if now==clickable then return end
 clickable=now
 for prompt in tracked do if prompt.Parent then apply(prompt)end end
end
InputHints.Changed:Connect(refresh)
state:GetAttributeChangedSignal('Mode'):Connect(refresh)
player:GetAttributeChangedSignal('MissionActive'):Connect(refresh)
player:GetAttributeChangedSignal('LobbyReady'):Connect(refresh)



player:GetAttributeChangedSignal('RoundDead'):Connect(refresh)
