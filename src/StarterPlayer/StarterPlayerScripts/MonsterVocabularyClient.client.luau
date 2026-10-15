-- Disabled 2026-10-07 (voice chat policy): the game no longer transcribes players' microphones.
-- Monsters never hear or repeat what players say. Kept as an inert script so nothing that looks for it breaks.
local player=game:GetService('Players').LocalPlayer
player:SetAttribute('MimicVocabularyAvailable',false)
