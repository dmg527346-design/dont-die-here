-- Phones and tablets (owner 2026-10-25): HIGH QUALITY is on by default. If the game lags persistently (under 20 fps
-- for 10 seconds in a row) this switches to a lighter look (no light or sun shadows, no bloom / sun rays / depth of
-- field, half the particles; terrain grass can't be set from a script), saves HIGH QUALITY: OFF (MainMenuClient sends it) and shows a small
-- notice in the middle of the screen. Settings > HIGH QUALITY puts the full look back; after a manual ON this session
-- it never switches again until the next join. PCs and consoles are never touched. Local only.
local Players=game:GetService('Players')
local Lighting=game:GetService('Lighting')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local RS=game:GetService('ReplicatedStorage')
local InputHints=require(RS:WaitForChild('InputHints'))
if not InputHints.IsMobile()then return end
local Prefs=require(RS:WaitForChild('HorrorPreferences'))
local Card=require(RS:WaitForChild('HudCardStyle'))
local p=Players.LocalPlayer
local LAG_FPS,LAG_SECONDS,GRACE=20,10,15 -- under LAG_FPS for LAG_SECONDS straight; nothing counts in the first GRACE s
local saved=setmetatable({},{__mode='k'}) -- instance -> {property=original value}
local low,conns=false,{}
local autoSwitching,manualOn=false,false
local function set(x,prop,value)
 local s=saved[x];if not s then s={};saved[x]=s end
 if s[prop]==nil then s[prop]=x[prop]end
 x[prop]=value
end
local function lighten(x)
 if x:IsA('Light')then if x.Shadows then set(x,'Shadows',false)end
 elseif x:IsA('ParticleEmitter')then if not(saved[x]and saved[x].Rate)then set(x,'Rate',x.Rate*.5)end
 elseif x:IsA('BloomEffect')or x:IsA('SunRaysEffect')or x:IsA('DepthOfFieldEffect')then if x.Enabled then set(x,'Enabled',false)end
 end
end
local function restore()
 for x,s in saved do if x.Parent or x==Lighting then for prop,value in s do pcall(function()x[prop]=value end)end end end
 table.clear(saved)
end
local function apply()
 local want=Prefs.Get('MobileHighQuality')==false
 if want==low then return end
 low=want;p:SetAttribute('LowQualityMode',low)
 for _,c in conns do c:Disconnect()end;table.clear(conns)
 if not low then restore();return end
 pcall(set,Lighting,'GlobalShadows',false)
 for _,x in Lighting:GetDescendants()do lighten(x)end
 table.insert(conns,Lighting.DescendantAdded:Connect(lighten))
 table.insert(conns,workspace.DescendantAdded:Connect(lighten))
 for i,x in workspace:GetDescendants()do
  if not low then return end
  lighten(x);if i%2000==0 then task.wait()end
 end
end
local function notice()
 local gui=Instance.new('ScreenGui');gui.Name='LowQualityNotice';gui.ResetOnSpawn=false;gui.DisplayOrder=60;gui.IgnoreGuiInset=true
 local card=Instance.new('Frame');card.Name='Card';card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.5)
 card.Size=UDim2.new(.8,0,0,74);card.BackgroundColor3=Card.FACE;card.BackgroundTransparency=.08;card.Parent=gui
 local limit=Instance.new('UISizeConstraint');limit.MaxSize=Vector2.new(340,74);limit.Parent=card
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,Card.RADIUS);c.Parent=card
 local s=Instance.new('UIStroke');s.Color=Card.INK;s.Thickness=Card.OUTLINE;s.Parent=card
 local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.new(1,-20,1,-12);t.Position=UDim2.fromOffset(10,6)
 t.Font=Enum.Font.GothamBold;t.TextScaled=true;t.TextWrapped=true;t.TextColor3=Color3.fromRGB(235,230,240)
 t.Text='Your game is lagging, so it switched to low quality.\nWant it back? Open Settings in the main lobby.';t.Parent=card
 local size=Instance.new('UITextSizeConstraint');size.MaxTextSize=16;size.Parent=t
 gui.Parent=p:WaitForChild('PlayerGui')
 task.delay(6,function()
  local info=TweenInfo.new(.6)
  TweenService:Create(card,info,{BackgroundTransparency=1}):Play();TweenService:Create(s,info,{Transparency=1}):Play()
  TweenService:Create(t,info,{TextTransparency=1}):Play();task.wait(.7);gui:Destroy()
 end)
end
local function goLow()
 autoSwitching=true;p:SetAttribute('LocalSettingMobileHighQuality',false);autoSwitching=false
 apply();notice()
end
p:GetAttributeChangedSignal('LocalSettingMobileHighQuality'):Connect(function()
 if not autoSwitching and p:GetAttribute('LocalSettingMobileHighQuality')==true then manualOn=true end
 apply()
end)
p:GetAttributeChangedSignal('SettingMobileHighQuality'):Connect(apply)
apply()
-- Lag watch: count frames each second; LAG_SECONDS bad seconds in a row switch to low quality.
local started,frames,bad,window=os.clock(),0,0,os.clock()
RunService.RenderStepped:Connect(function()
 frames+=1
 local now=os.clock();local dt=now-window
 if dt<1 then return end
 local fps=frames/dt;frames,window=0,now
 if low or manualOn or now-started<GRACE then bad=0;return end
 if fps<LAG_FPS then bad+=1 else bad=0 end
 if bad>=LAG_SECONDS then bad=0;goLow()end
end)
