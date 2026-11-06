local SS=game:GetService('SoundService')
local Pref=require(game.ReplicatedStorage:WaitForChild('HorrorPreferences'))
local p=game.Players.LocalPlayer
local groups={}
for _,entry in {{'GameplaySFX',2.4},{'GameplayUI',2.25},{'GameplayMusic',.6}}do
 local group=SS:FindFirstChild(entry[1]) or Instance.new('SoundGroup')
 group.Name=entry[1];group.Parent=SS;groups[group]=entry[2]
end
local function update()
 local level=Pref.Get('MasterVolume')*Pref.Get('EffectsVolume')
 for group,base in groups do group.Volume=base*level end
end
local function added(x)
 if x:IsA('Sound') and x.Name~='MainMenuMusic' and x.SoundGroup==nil then x.SoundGroup=SS.GameplaySFX end
end
for _,x in game:GetDescendants()do added(x)end
game.DescendantAdded:Connect(added)
p.AttributeChanged:Connect(function(key)if key:find('Setting',1,true)then update()end end)
update()
