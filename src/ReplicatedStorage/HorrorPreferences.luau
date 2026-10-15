local P=game:GetService('Players')
local defaults={MasterVolume=.65,EffectsVolume=.7,MenuMusicVolume=.25,Jumpscares=true,FlashingLights=true,CameraMotion=true,SpitEffects=true,VoiceEffects=true}
-- Only the volume sliders are player-adjustable. These effects are always on; older saved OFF values are ignored.
local fixed={Jumpscares=true,FlashingLights=true,CameraMotion=true,SpitEffects=true,VoiceEffects=true}
local M={}
function M.Get(key)
 if fixed[key]~=nil then return fixed[key]end
 local p=P.LocalPlayer;if not p then return defaults[key]end
 local v=p:GetAttribute('LocalSetting'..key)
 if v==nil then v=p:GetAttribute('Setting'..key)end
 if v==nil then v=defaults[key]end
 return v
end
return M
