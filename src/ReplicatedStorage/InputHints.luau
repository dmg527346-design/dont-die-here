-- One client-side source for input wording. Hardware/emulator defaults never override real input.
local UIS=game:GetService('UserInputService')
local GS=game:GetService('GuiService')
local H={}
local changed=Instance.new('BindableEvent')
H.Changed=changed.Event
local function classify(input)
 if input==Enum.UserInputType.Touch then return 'touch' end
 if input.Name:find('Gamepad',1,true)then return 'pad' end
 if input==Enum.UserInputType.Keyboard or input.Name:find('Mouse',1,true)then return 'kb' end
end
local function defaultMode()
 if GS:IsTenFootInterface()or(UIS.GamepadEnabled and not UIS.KeyboardEnabled and not UIS.TouchEnabled)then return 'pad' end
 if UIS.TouchEnabled and not UIS.KeyboardEnabled then return 'touch' end
 return 'kb'
end
local mode=classify(UIS:GetLastInputType())or defaultMode()
UIS.LastInputTypeChanged:Connect(function(input)
 local nextMode=classify(input)
 if nextMode and nextMode~=mode then mode=nextMode;changed:Fire(mode)end
end)
function H.Get()
 -- Poll the real input too so every listener sees the new mode regardless of signal callback order.
 return classify(UIS:GetLastInputType())or mode
end
return H
