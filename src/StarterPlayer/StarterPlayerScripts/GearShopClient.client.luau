-- Short gear shop / weapon messages from GearShopServer (bottom centre, above the hotbar).
local Players=game:GetService('Players');local RS=game:GetService('ReplicatedStorage');local TweenService=game:GetService('TweenService')
local p=Players.LocalPlayer
local SHOW_SECONDS=3
local BOTTOM=150
local gui=Instance.new('ScreenGui');gui.Name='GearShopToast';gui.ResetOnSpawn=false;gui.DisplayOrder=42;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=p:WaitForChild('PlayerGui')
local label=Instance.new('TextLabel');label.AnchorPoint=Vector2.new(.5,1);label.Position=UDim2.new(.5,0,1,-BOTTOM);label.Size=UDim2.new(.9,0,0,26)
label.BackgroundTransparency=1;label.Font=Enum.Font.FredokaOne;label.TextScaled=true;label.TextColor3=Color3.fromRGB(255,226,150);label.TextTransparency=1;label.Text='';label.Parent=gui
local cap=Instance.new('UITextSizeConstraint');cap.MaxTextSize=20;cap.MinTextSize=11;cap.Parent=label
local stroke=Instance.new('UIStroke');stroke.Thickness=2;stroke.Transparency=1;stroke.Parent=label
local serial=0
RS:WaitForChild('GearShopEvent').OnClientEvent:Connect(function(kind,text)
 if kind~='toast'or type(text)~='string'then return end
 serial+=1;local mine=serial
 label.Text=text;label.TextTransparency=0;stroke.Transparency=.3
 task.delay(SHOW_SECONDS,function()if serial==mine then TweenService:Create(label,TweenInfo.new(.4),{TextTransparency=1}):Play();TweenService:Create(stroke,TweenInfo.new(.4),{Transparency=1}):Play()end end)
end)
