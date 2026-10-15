-- Permanent bottom-right note (top-right on phones): Roblox Plus members earn +10% run tokens (granted server-side in ProgressCore.RunTokens).
-- The old like/favorite token bonus is gone: Roblox does not allow rewards for liking or favoriting (removed 2026-10-07).
local Players=game:GetService('Players');local UIS=game:GetService('UserInputService')
local p=Players.LocalPlayer
local MARGIN=12
local BOX_W,BOX_H=230,28
local TOUCH_LIFT_LARGE=412 -- above the touch button grid
local PHONE_TOP=6 -- phones: the very top-right corner (device safe area, above Roblox's top bar row)
local gui=Instance.new('ScreenGui');gui.Name='PlusBonusHud';gui.ResetOnSpawn=false;gui.DisplayOrder=5;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=p:WaitForChild('PlayerGui')
local box=Instance.new('Frame');box.AnchorPoint=Vector2.new(1,1);box.Size=UDim2.fromOffset(BOX_W,BOX_H);box.BackgroundColor3=Color3.fromRGB(14,22,22);box.BackgroundTransparency=.6;box.Parent=gui
Instance.new('UICorner',box).CornerRadius=UDim.new(0,10)
local plus=Instance.new('TextLabel');plus.Name='Plus';plus.BackgroundTransparency=1;plus.Position=UDim2.fromOffset(8,4);plus.Size=UDim2.new(1,-16,0,20)
plus.Font=Enum.Font.FredokaOne;plus.TextScaled=true;plus.TextXAlignment=Enum.TextXAlignment.Right;plus.TextColor3=Color3.fromRGB(244,236,210);plus.Parent=box
local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=16;c.MinTextSize=9;c.Parent=plus
local function refresh()
 local member=p.MembershipType==Enum.MembershipType.Premium
 plus.Text=member and 'ROBLOX PLUS: +10% TOKENS ✓'or 'ROBLOX PLUS: +10% TOKENS'
 local touch=UIS.TouchEnabled and not UIS.KeyboardEnabled
 local cam=workspace.CurrentCamera;local phone=cam and cam.ViewportSize.Y<500
 if UIS.TouchEnabled and phone then -- phones: out of the way of the touch buttons, pinned to the top-right corner
  gui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets
  box.AnchorPoint=Vector2.new(1,0);box.Position=UDim2.new(1,-MARGIN,0,PHONE_TOP)
 else
  gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
  box.AnchorPoint=Vector2.new(1,1);box.Position=UDim2.new(1,-MARGIN,1,-(touch and TOUCH_LIFT_LARGE or MARGIN))
 end
end
refresh();p:GetPropertyChangedSignal('MembershipType'):Connect(refresh)
UIS.LastInputTypeChanged:Connect(refresh)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(refresh)end
