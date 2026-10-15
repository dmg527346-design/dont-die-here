-- Changes only existing proximity voice output paths; raw speech analyzers and mimic inputs stay intact.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local wires={};local routes={}
local function track(x)if x:IsA('Wire')then wires[x]=true end end
for _,x in game:GetDescendants()do track(x)end
game.DescendantAdded:Connect(track)
game.DescendantRemoving:Connect(function(x)wires[x]=nil end)
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<.1 then return end;elapsed=0
 for w in wires do
  if not w.Parent then wires[w]=nil;continue end
  if not routes[w] then
   local input=w.SourceInstance;local target=w.TargetInstance
   if input and input:IsA('AudioDeviceInput') and target and target:IsA('AudioEmitter') then
    local player=input.Player
    if player then
     local effect=Instance.new('AudioPitchShifter');effect.Name='MagicOrbVoicePitch';effect.Pitch=1;effect.Bypass=true;effect.Parent=input
     local feed=Instance.new('Wire');feed.Name='MagicOrbVoiceInput';feed.SourceInstance=input;feed.TargetInstance=effect;feed.Parent=effect
     -- Kazoo buzz sits after the pitch stage: input -> pitch -> buzz -> emitter.
     local buzz=Instance.new('AudioDistortion');buzz.Name='KazooBuzz';buzz.Level=.9;buzz.Bypass=true;buzz.Parent=input
     local link=Instance.new('Wire');link.Name='KazooBuzzInput';link.SourceInstance=effect;link.TargetInstance=buzz;link.Parent=buzz
     local muffle=Instance.new('AudioEqualizer');muffle.Name='MascotVoiceMuffle';muffle.LowGain=0;muffle.MidGain=-6;muffle.HighGain=-24;muffle.Bypass=true;muffle.Parent=input
     local muffleFeed=Instance.new('Wire');muffleFeed.Name='MascotVoiceInput';muffleFeed.SourceInstance=buzz;muffleFeed.TargetInstance=muffle;muffleFeed.Parent=muffle
     routes[w]={input=input,player=player,effect=effect,buzz=buzz,muffle=muffle,target=target};w.SourceInstance=muffle
    end
   end
  end
 end
 for w,r in routes do
  if not w.Parent or not r.input.Parent or not r.player.Parent or not r.target.Parent then
   if w.Parent and(w.SourceInstance==r.effect or w.SourceInstance==r.buzz or w.SourceInstance==r.muffle)then w.SourceInstance=r.input.Parent and r.input or nil end
   r.effect:Destroy();if r.buzz then r.buzz:Destroy()end;if r.muffle then r.muffle:Destroy()end;routes[w]=nil;continue
  end
  local c=r.player.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
  local alive=h and h.Health>0 and r.player:GetAttribute('MissionActive')==true
  local now=workspace:GetServerTimeNow()
  local orb=alive and r.player:GetAttribute('MagicOrbHeld')==true
  local helium=alive and now<(r.player:GetAttribute('HeliumUntil')or 0)
  local kazoo=alive and now<(r.player:GetAttribute('KazooUntil')or 0)
  -- Helium squeaks (high), the magic orb growls (low), the kazoo buzzes slightly high.
  local pitch=helium and 1.75 or orb and .72 or kazoo and 1.12 or 1
  r.effect.Pitch=pitch;r.effect.Bypass=pitch==1
  r.buzz.Bypass=not kazoo
  r.muffle.Bypass=not(alive and now<(r.player:GetAttribute('MascotMuffleUntil')or 0))
 end
end)

