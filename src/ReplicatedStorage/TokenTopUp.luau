-- Token top-up (owner 2026-10-27): when a token purchase (upgrade or cosmetic) is short, offer the smallest Robux
-- token pack that covers the shortfall (the biggest pack if none does), then finish that purchase automatically once
-- the tokens arrive (within 3 minutes). Client only: the server still checks the balance on every purchase.
local Players=game:GetService('Players')
local Market=game:GetService('MarketplaceService')
local Shop=require(script.Parent:WaitForChild('LobbyShopCatalog'))
local M={}
local PENDING_SECONDS=180

local packs={}
for _,o in Shop.RobuxOffers do if o.kind=='Product'and(tonumber(o.grantTokens)or 0)>0 then table.insert(packs,o)end end
table.sort(packs,function(a,b)return a.grantTokens<b.grantTokens end)

function M.Packs()return packs end
-- The smallest pack that covers `short` tokens, else the biggest one.
function M.PackFor(short)
 for _,o in packs do if o.grantTokens>=short then return o end end
 return packs[#packs]
end

local pending -- {cost=n, retry=function, expires=clock, assetId=n}
local player=Players.LocalPlayer
local function tokens()return tonumber(player:GetAttribute('Tokens'))or 0 end
player:GetAttributeChangedSignal('Tokens'):Connect(function()
 local job=pending
 if job and os.clock()<job.expires and tokens()>=job.cost then pending=nil;task.spawn(job.retry)end
end)
Market.PromptProductPurchaseFinished:Connect(function(userId,assetId,bought)
 if userId==player.UserId and pending and pending.assetId==assetId and not bought then pending=nil end
end)

-- cost: tokens the purchase needs; have: the player's tokens as the UI knows them; retry: runs the purchase again.
-- Returns the offered pack, or nil when no top-up is needed or no pack exists.
function M.Offer(cost,have,retry)
 have=math.max(tonumber(have)or 0,tokens())
 local short=(tonumber(cost)or 0)-have
 if short<=0 or #packs==0 then return nil end
 local pack=M.PackFor(short)
 pending={cost=cost,retry=retry,expires=os.clock()+PENDING_SECONDS,assetId=pack.assetId}
 local ok=pcall(function()Market:PromptProductPurchase(player,pack.assetId)end)
 if not ok then pending=nil;return nil end
 return pack,short
end

return M
