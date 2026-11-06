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
-- Native device (owner 2026-10-25): phones and tablets always get the touch UI and consoles the controller UI, whatever
-- key or button is pressed on them; only a PC follows its last input (keyboard / controller; a touch screen counts as
-- keyboard there). A touch device with a mouse (a touchscreen laptop) is a PC.
local function nativeDevice()
 if GS:IsTenFootInterface()then return 'pad' end
 -- Studio's device emulator reports a mouse and keyboard on emulated phones, so in Studio any touch screen is mobile.
 if UIS.TouchEnabled and(not UIS.MouseEnabled or game:GetService('RunService'):IsStudio())then return 'touch' end
 return 'pc'
end
local NATIVE=nativeDevice()
function H.Native()return NATIVE end
function H.IsMobile()return NATIVE=='touch' end
local function pcMode(input)local m=classify(input);if m=='touch'then return 'kb' end;return m end
local mode=NATIVE~='pc'and NATIVE or pcMode(UIS:GetLastInputType())or defaultMode()
UIS.LastInputTypeChanged:Connect(function(input)
 if NATIVE~='pc'then return end -- phones, tablets and consoles never switch
 local nextMode=pcMode(input)
 if nextMode and nextMode~=mode then mode=nextMode;changed:Fire(mode)end
end)
-- Controller wording: the connected pad's own button names (Xbox RT / LB, PlayStation R2 / L1, ...).
local PAD_TOKENS={RT='ButtonR2',LT='ButtonL2',RB='ButtonR1',LB='ButtonL1'}
function H.Button(key)
 local ok,name=pcall(function()return UIS:GetStringForKeyCode(Enum.KeyCode[key])end)
 local label=ok and type(name)=='string'and name:gsub('^Button','')or ''
 if label==''then label=(key:gsub('^Button',''))end
 return label
end
-- Rewrites Xbox trigger/bumper names written in a hint (RT, LT, RB, LB) to the connected controller's names.
function H.PadText(text)
 return (text:gsub('%f[%w](%u[TB])%f[%W]',function(token)local key=PAD_TOKENS[token];return key and H.Button(key)or token end))
end
-- Real taps (owner 2026-10-25): on phones a finger swiping the camera across a van prompt opened the panel. Prompt
-- handlers call ConfirmTap(): it waits for the finger that fired the prompt to lift and says yes only for a short
-- tap that stayed put. Keyboard, controller and PC always pass.
local touches=setmetatable({},{__mode='k'})
UIS.TouchStarted:Connect(function(t)touches[t]={from=t.Position,at=os.clock()}end)
UIS.TouchMoved:Connect(function(t)local r=touches[t];if r and(t.Position-r.from).Magnitude>12 then r.moved=true end end)
UIS.TouchEnded:Connect(function(t)local r=touches[t];if r then r.ended=os.clock()end end)
function H.ConfirmTap()
 if NATIVE~='touch'then return true end
 local newest;for _,r in touches do if not newest or r.at>newest.at then newest=r end end
 if not newest or newest.ended and os.clock()-newest.ended>.25 then return true end -- not fired by a finger
 while not newest.ended and os.clock()-newest.at<.45 do task.wait()end
 return newest.ended~=nil and not newest.moved and newest.ended-newest.at<.45
end
-- PlayStation pads (owner 2026-10-25): show the real button art (cross / circle / square / triangle), not words.
function H.IsPlayStation()
 local ok,name=pcall(function()return UIS:GetStringForKeyCode(Enum.KeyCode.ButtonY)end)
 return ok and name=='ButtonTriangle'
end
-- Puts the connected PlayStation pad's own button image (UIS:GetImageForKeyCode) inside a key label and hides its
-- text; anywhere else (Xbox, keyboard, no image) the image goes and the text shows again. Returns true when drawn.
function H.Glyph(label,key)
 local img=label:FindFirstChild('PadGlyph')
 if label:GetAttribute('GlyphTextAlpha')==nil then label:SetAttribute('GlyphTextAlpha',label.TextTransparency)end
 local id=''
 if H.IsPlayStation()then local ok,got=pcall(function()return UIS:GetImageForKeyCode(Enum.KeyCode[key])end);if ok and type(got)=='string'then id=got end end
 if id==''then
  if img then img:Destroy()end;label.TextTransparency=label:GetAttribute('GlyphTextAlpha');return false
 end
 if not img then
  img=Instance.new('ImageLabel');img.Name='PadGlyph';img.BackgroundTransparency=1;img.AnchorPoint=Vector2.new(.5,.5)
  img.Position=UDim2.fromScale(.5,.5);img.Size=UDim2.fromScale(.8,.8);img.ScaleType=Enum.ScaleType.Fit;img.ZIndex=label.ZIndex+1;img.Parent=label
 end
 img.Image=id;label.TextTransparency=1
 return true
end
function H.Get()
 -- Poll the real input too so every listener sees the new mode regardless of signal callback order.
 if NATIVE~='pc'then return NATIVE end
 return pcMode(UIS:GetLastInputType())or mode
end
return H
