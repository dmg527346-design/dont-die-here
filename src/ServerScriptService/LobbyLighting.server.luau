-- Halloween night look for the 3D lobby (LobbyState.Mode == 'Menu'). Missions keep MapGen.MapLighting as the owner:
-- on Mode -> Mission this restores the place's own fog/sky/post values and re-runs MapLighting.Global for the map kind.
local Lighting=game:GetService('Lighting')
local RS=game:GetService('ReplicatedStorage')
local SSS=game:GetService('ServerScriptService')
local state=RS:WaitForChild('LobbyState',30)
if not state then return end

-- Values MapLighting.Global never touches: captured once from the place so a mission gets them back unchanged.
local PROPS={'FogStart','FogEnd','FogColor','ColorShift_Top','ColorShift_Bottom','GeographicLatitude','ShadowSoftness'}
local saved={}
for _,k in PROPS do saved[k]=Lighting[k] end
local function effect(name) local e=Lighting:FindFirstChild(name);return e end
local savedFx={}
for _,n in {'SunRays','Bloom','DepthOfField'} do local e=effect(n);if e then savedFx[n]={e=e,enabled=e.Enabled,intensity=e:IsA('BloomEffect')and e.Intensity or nil,threshold=e:IsA('BloomEffect')and e.Threshold or nil} end end
local air=Lighting:FindFirstChildOfClass('Atmosphere')
local savedAir=air and {Density=air.Density,Offset=air.Offset,Color=air.Color,Decay=air.Decay,Glare=air.Glare,Haze=air.Haze}
local sky=Lighting:FindFirstChildOfClass('Sky')
local savedSky=sky and {CelestialBodiesShown=sky.CelestialBodiesShown,StarCount=sky.StarCount,MoonAngularSize=sky.MoonAngularSize}
-- Lobby-only colour grade; created here, switched off for missions.
local LOBBY_CLOCK=23.2 -- must differ from MapLighting's ClockTime 0 so its night reset is noticed below
local grade=Lighting:FindFirstChild('LobbyGrade') or Instance.new('ColorCorrectionEffect')
grade.Name='LobbyGrade';grade.Enabled=false;grade.Parent=Lighting

local applying=false
local function lobbyLook()
	if state:GetAttribute('Mode')~='Menu' then return end -- a deferred call must not undo a mission's lighting
	applying=true
	-- moonlit purple night: readable, orange lamp/jack-o'-lantern glow, green cauldrons, neon circles pop through bloom
	Lighting.ClockTime=LOBBY_CLOCK;Lighting.GeographicLatitude=20
	Lighting.Brightness=1.1
	Lighting.Ambient=Color3.fromRGB(58,42,92);Lighting.OutdoorAmbient=Color3.fromRGB(70,56,118)
	Lighting.ExposureCompensation=0
	Lighting.EnvironmentDiffuseScale=0.6;Lighting.EnvironmentSpecularScale=0.6
	Lighting.GlobalShadows=true;Lighting.ShadowSoftness=0.4
	Lighting.FogStart=0;Lighting.FogEnd=100000;Lighting.FogColor=Color3.fromRGB(40,24,60)
	Lighting.ColorShift_Top=Color3.fromRGB(150,140,255);Lighting.ColorShift_Bottom=Color3.fromRGB(40,10,60)
	local mall=Lighting:FindFirstChild('MallGrade');if mall then mall.Enabled=false end
	grade.Enabled=true;grade.TintColor=Color3.fromRGB(225,215,255);grade.Saturation=0.1;grade.Contrast=0.12;grade.Brightness=0
	if air then air.Density=0.34;air.Offset=0.1;air.Color=Color3.fromRGB(70,44,104);air.Decay=Color3.fromRGB(255,120,50);air.Glare=0.4;air.Haze=1.6 end
	if sky then sky.CelestialBodiesShown=true;sky.StarCount=3000;sky.MoonAngularSize=18 end
	local dof=effect('DepthOfField');if dof then dof.Enabled=false end
	local bloom=effect('Bloom');if bloom and bloom:IsA('BloomEffect') then bloom.Enabled=true;bloom.Intensity=0.4;bloom.Threshold=1.4 end
	local rays=effect('SunRays');if rays then rays.Enabled=false end
	task.defer(function()applying=false end)
end
local function missionLook()
	grade.Enabled=false
	for _,k in PROPS do Lighting[k]=saved[k] end
	for _,f in savedFx do f.e.Enabled=f.enabled;if f.intensity then f.e.Intensity=f.intensity end;if f.threshold then f.e.Threshold=f.threshold end end
	if air and savedAir then for k,v in savedAir do air[k]=v end end
	if sky and savedSky then for k,v in savedSky do sky[k]=v end end
	local mapGen=SSS:FindFirstChild('MapGen');local ml=mapGen and mapGen:FindFirstChild('MapLighting')
	local mansion=workspace:FindFirstChild('Mansion')
	if ml then local ok,why=pcall(function()require(ml).Global(mansion and mansion:GetAttribute('MapKind'))end);if not ok then warn('[LobbyLighting] '..tostring(why)) end end
end
local function inMenu() return state:GetAttribute('Mode')=='Menu' end
local wasMenu=nil
local function refresh()
	local menu=inMenu()
	if menu then lobbyLook() elseif wasMenu then missionLook() end
	wasMenu=menu
end
state:GetAttributeChangedSignal('Mode'):Connect(refresh)
-- MapGen sets the mission night when it (re)builds the map; in the lobby put the Halloween look back right after it.
Lighting:GetPropertyChangedSignal('ClockTime'):Connect(function()
	if not applying and inMenu() and Lighting.ClockTime~=LOBBY_CLOCK then task.defer(lobbyLook) end
end)
refresh()
