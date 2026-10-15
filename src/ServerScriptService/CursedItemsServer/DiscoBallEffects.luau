-- Lifecycle is owned by the registered item and its server-authoritative HeldBy value.
local Players=game:GetService('Players')
local D={}
function D.Register(m)
 local root=m.PrimaryPart
 local a=Instance.new('Attachment');a.Name='DiscoAudioOrigin';a.Parent=root
 local music=Instance.new('Sound');music.Name='DiscoMusic';local cue=require(game.ReplicatedStorage.GameplaySoundCatalog).DiscoMusic;music.SoundId=cue.id;music.Volume=cue.volume;music.PlaybackSpeed=cue.speed;music.SoundGroup=game.SoundService:FindFirstChild('GameplayMusic');music.Looped=true
 music.RollOffMode=Enum.RollOffMode.InverseTapered;music.RollOffMinDistance=4;music.RollOffMaxDistance=32;music.Parent=a
 local function update()
  local owner=Players:GetPlayerByUserId(m:GetAttribute('HeldBy') or 0)
  local h=owner and owner.Character and owner.Character:FindFirstChildOfClass('Humanoid')
  local playing=m:IsDescendantOf(workspace) and owner~=nil and h~=nil and h.Health>0 and not m:GetAttribute('Selling')
  m:SetAttribute('DiscoPlaying',playing)
  if playing then if not music.IsPlaying then music:Play() end else music:Stop();music.TimePosition=0 end
 end
 local connections={}
 table.insert(connections,m:GetAttributeChangedSignal('HeldBy'):Connect(update))
 table.insert(connections,m:GetAttributeChangedSignal('Selling'):Connect(update))
 table.insert(connections,m.AncestryChanged:Connect(update))
 m.Destroying:Once(function() for _,c in connections do c:Disconnect() end end)
 update()
end
return D