local M={}
function M.IsProtected(p)
 -- AdminGod: owner-only god mode set by AdminPowersServer (never caught, seen or heard).
 -- ChoiceDeciding: the close-up yes/no card is up (CloseUpChoices claim); no monster may catch or hurt them (owner 2026-10-25).
 return p:GetAttribute('AdminGod')==true or p:GetAttribute('Hiding')==true or p:GetAttribute('ClosetState')~=nil or p:GetAttribute('ChoiceDeciding')==true
  or workspace:GetServerTimeNow()<(p:GetAttribute('ClosetProtectedUntil')or 0)
  -- BalloonSafeUntil: a friend balloon is eating the monster next to them (CloseUpChoices.ExtraChoices).
  or workspace:GetServerTimeNow()<(p:GetAttribute('BalloonSafeUntil')or 0)
  -- BubbledUntil: sealed in a hiccup bubble (CursedBatchEffects.ItemBatch6); they can't move, monsters can't reach them.
  or workspace:GetServerTimeNow()<(p:GetAttribute('BubbledUntil')or 0)
end
-- 'Untouchable' omen (owner 2026-10-26): only the FIRST time a monster reaches a player in the level. That contact starts a
-- short shield (UntouchableUntil) so the whole attack misses and they can run; after it they are on their own.
local SHIELD_SECONDS=3
function M.OmenShield(p)
 local s=game:GetService('ReplicatedStorage'):FindFirstChild('RecoveryRound')
 if not s or s:GetAttribute('Omen')~='Untouchable'then return false end
 local now=workspace:GetServerTimeNow()
 if p:GetAttribute('UntouchableRound')~=s:GetAttribute('Round')then p:SetAttribute('UntouchableRound',s:GetAttribute('Round'));p:SetAttribute('UntouchableUntil',now+SHIELD_SECONDS)end
 return now<(p:GetAttribute('UntouchableUntil')or 0)
end
return M