-- Monster speech is authored dialogue only. Player microphones and chat are never captured or replayed.
local Players=game:GetService('Players')
local SS=game:GetService('ServerStorage')
local RS=game:GetService('ReplicatedStorage')
local Debris=game:GetService('Debris')
local rng=Random.new()
local lastMimic=setmetatable({},{__mode='k'})
local lines={
 Lure={'Over here.','This way.','Come closer.'},
 FakeSafety={'It is safe here.','I found the way out.','Follow the light.'},
 FakeDistress={'Please help me.','I cannot find the door.','Do not leave me here.'},
 Separation={'Where did everyone go?','I am right behind you.','Wait for me.'},
 Echo={'Is someone there?','I heard you.','You are not alone.'},
 Psychological={'You should not have come here.','I can hear your footsteps.','Do you remember the way back?'},
}
local approved={};for _,list in lines do for _,text in list do approved[text]=true end end
local function validMonster(m)
 local folder=workspace:FindFirstChild('RoamingCreatures')
 return typeof(m)=='Instance' and m:IsA('Model') and m.PrimaryPart~=nil and folder~=nil and m:IsDescendantOf(folder)
end
local function active(p)
 local h=p and p.Character and p.Character:FindFirstChildOfClass('Humanoid')
 return p~=nil and p.Parent==Players and p:GetAttribute('MissionActive')==true and p:GetAttribute('RoundDead')~=true and h~=nil and h.Health>0
end
local function speak(m,text,quality)
 if not validMonster(m) or not approved[text] then return false end
 local f=Instance.new('Folder');f.Name='MimickedPhrase';f.Parent=m.PrimaryPart
 local t=Instance.new('AudioTextToSpeech');t.Text=text;t.VoiceId='3';t.Volume=.55;t.Speed=rng:NextNumber(.90,.99);t.Pitch=type(quality)=='number'and quality>.9 and -1 or -2;t.Parent=f
 local e=Instance.new('AudioEmitter');e.AudioInteractionGroup='CursedAudio';e:SetDistanceAttenuation({[0]=1,[12]=.9,[55]=0});e.Parent=m.PrimaryPart
 local w=Instance.new('Wire');w.SourceInstance=t;w.TargetInstance=e;w.Parent=f
 Debris:AddItem(f,16);Debris:AddItem(e,16)
 task.spawn(function()
  local ok=pcall(function()
   local loaded=t:LoadAsync()
   if not m.Parent or not t.Parent then return end
   m:SetAttribute('MimicSpeechLoadStatus',tostring(loaded))
   if loaded==Enum.AssetFetchStatus.Success then t:Play() else m:SetAttribute('MimicSpeechUnavailable',true)end
  end)
  if not ok and m.Parent then m:SetAttribute('MimicSpeechUnavailable',true)end
 end)
 m:SetAttribute('LastMimicPhrase',text);m:SetAttribute('MimicSpeechSource','AuthoredDialogue');return true
end
-- Remove the obsolete transcript receiver; no player supplied speech enters the NPC graph.
local obsolete=RS:FindFirstChild('MimicPhraseEvent');if obsolete then obsolete:Destroy()end
local old=SS:FindFirstChild('MonsterMimicApi');if old then old:Destroy()end
local api=Instance.new('BindableFunction');api.Name='MonsterMimicApi'
api.OnInvoke=function(action,m,recipient,purpose,quality)
 if action=='heard'then return false end
 if action=='speech'then return speak(m,recipient,quality)end
 if action~='context'and action~='available'then return false end
 if not validMonster(m) or type(recipient)~='number' or recipient~=recipient then return false end
 if not active(Players:GetPlayerByUserId(recipient))then return false end
 local now=os.clock();if now-(lastMimic[m]or -math.huge)<24 then return false end
 if action=='available'then return true end
 local list=lines[type(purpose)=='string'and purpose or '']or lines.Lure
 lastMimic[m]=now;m:SetAttribute('MimicPurpose',purpose or 'Lure');m:SetAttribute('MimicSpeaker',nil);m:SetAttribute('MimicQuality',quality or .85)
 return speak(m,list[rng:NextInteger(1,#list)],quality)
end
api.Parent=SS
script:SetAttribute('Initialized',true)
