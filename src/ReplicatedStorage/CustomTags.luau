-- Custom overhead tags for specific players, keyed by UserId (stays correct if they rename).
-- ProgressService draws the tag above the head (above the VIP title and any hat); the leaderboards show `icon`
-- next to the player's name.
local M = {}

local REDS = { "#FF6B6B", "#B0101E" } -- light / dark red, alternating per letter
local GHOUL = { "#B05CFF", "#FF8A1F" } -- purple / orange, alternating per letter

M.ByUserId = {
	[315936607] = { text = "[Haunted Owner]", colors = REDS, emoji = "🎃" }, -- game owner
	[2565716611] = { text = "[Ghoulfriend]", colors = GHOUL, icon = "rbxassetid://77350338735536" }, -- DRAGONAMANDA15
	[506102195] = { text = "[1 dolla cuh]", colors = REDS, emoji = "💲" }, -- Memescooly_2
	[4750690736] = { text = "[1 dolla cuh]", colors = REDS, emoji = "💲" }, -- Endeavor308
}

function M.Get(userId)
	return M.ByUserId[userId]
end

-- Rich text with each letter in the next colour of the tag's palette (spaces skipped), emoji appended uncoloured.
function M.RichText(tag)
	local out, i = {}, 0
	for _, code in utf8.codes(tag.text) do
		local ch = utf8.char(code)
		if ch == " " then
			table.insert(out, " ")
		else
			i += 1
			if ch == "<" then ch = "&lt;" elseif ch == ">" then ch = "&gt;" elseif ch == "&" then ch = "&amp;" end
			table.insert(out, ('<font color="%s">%s</font>'):format(tag.colors[(i - 1) % #tag.colors + 1], ch))
		end
	end
	local s = table.concat(out)
	if tag.emoji then s ..= " " .. tag.emoji end
	return s
end

return M
