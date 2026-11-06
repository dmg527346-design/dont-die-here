-- Permanent bottom-right note (top-right on phones): Roblox Plus members earn +10% run tokens (granted server-side in ProgressCore.RunTokens).
-- The old like/favorite token bonus is gone: Roblox does not allow rewards for liking or favoriting (removed 2026-10-07).
local Players=game:GetService('Players');local UIS=game:GetService('UserInputService')
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local p=Players.LocalPlayer
local MARGIN=12
local BOX_W,BOX_H=230,28
local TOUCH_LIFT_LARGE=520 -- owner 2026-10-26: raised (was 412) so the Plus pill and the omen pill above it sit higher on tablets
-- -- above the touch button grid
local PHONE_TOP=6 -- phones: the very top-right corner (device safe area, above Roblox's top bar row)
local gui=Instance.new('ScreenGui');gui.Name='PlusBonusHud';gui.ResetOnSpawn=false;gui.DisplayOrder=5;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=p:WaitForChild('PlayerGui')
local box=Instance.new('Frame');box.AnchorPoint=Vector2.new(1,1);box.Size=UDim2.fromOffset(BOX_W,BOX_H);box.BackgroundColor3=Color3.fromRGB(14,22,22);box.BackgroundTransparency=.6;box.Parent=gui
Instance.new('UICorner',box).CornerRadius=UDim.new(0,10)
local plus=Instance.new('TextLabel');plus.Name='Plus';plus.BackgroundTransparency=1;plus.Position=UDim2.fromOffset(8,4);plus.Size=UDim2.new(1,-16,0,20)
plus.Font=Enum.Font.FredokaOne;plus.TextScaled=true;plus.TextXAlignment=Enum.TextXAlignment.Right;plus.TextColor3=Color3.fromRGB(244,236,210);plus.Parent=box
local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=16;c.MinTextSize=9;c.Parent=plus
-- Lobby rank card (MainMenuClient QuickPlay.RankCard) reaching into the bottom-right corner: sit just above it.
local function cardLift()
 local qp=p.PlayerGui:FindFirstChild('QuickPlay');local card=qp and qp.Enabled and qp:FindFirstChild('RankCard',true)
 if not(card and card.Visible)then return 0 end
 if card.AbsolutePosition.X+card.AbsoluteSize.X<gui.AbsoluteSize.X-MARGIN-BOX_W then return 0 end
 if card.AbsolutePosition.Y<gui.AbsoluteSize.Y*.5 then return 0 end -- computer / console: the card is up in the top-right corner
 return gui.AbsolutePosition.Y+gui.AbsoluteSize.Y-card.AbsolutePosition.Y+8
end
local function refresh()
 local member=p.MembershipType==Enum.MembershipType.Premium
 plus.Text=member and 'ROBLOX PLUS: +10% TOKENS ✓'or 'ROBLOX PLUS: +10% TOKENS'
 local touch=InputHints.IsMobile()
 local cam=workspace.CurrentCamera;local phone=cam and cam.ViewportSize.Y<500
 if InputHints.IsMobile()and phone then -- phones: out of the way of the touch buttons, pinned to the top-right corner
  gui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets
  box.AnchorPoint=Vector2.new(1,0);box.Position=UDim2.new(1,-MARGIN,0,PHONE_TOP+(p:GetAttribute('OmenChipTop')and 36 or 0)) -- OmenClient's level omen pill takes the top row
 else
  gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
  box.AnchorPoint=Vector2.new(1,1);box.Position=UDim2.new(1,-MARGIN,1,-(touch and TOUCH_LIFT_LARGE or math.max(MARGIN,cardLift())))
 end
end
refresh();p:GetPropertyChangedSignal('MembershipType'):Connect(refresh);p:GetAttributeChangedSignal('OmenChipTop'):Connect(refresh)
UIS.LastInputTypeChanged:Connect(refresh)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(refresh)end
task.spawn(function()
 local qp=p.PlayerGui:WaitForChild('QuickPlay',60);if not qp then return end
 qp:GetPropertyChangedSignal('Enabled'):Connect(refresh)
 local row=qp:WaitForChild('Row',60);local card=row and(row:WaitForChild('RankCard',10)or qp:FindFirstChild('RankCard',true));if not card then return end
 card:GetPropertyChangedSignal('AbsolutePosition'):Connect(refresh);card:GetPropertyChangedSignal('Visible'):Connect(refresh);refresh()
end)
