local M={}
function M.Build(kit,accessories)
 local source=game.ServerStorage.CursedBlenderTemplates
 local ids={'RainCloud','CoolSunglasses','FlyJar','CursedPerfume','BirthdayHat'}
 for _,id in ipairs(ids)do local old=kit:FindFirstChild(id);if old then old:Destroy()end;source.CursedItemKit[id]:Clone().Parent=kit end
 for _,id in ipairs({'CoolHat','AnnoyingFly','PartyBlower'})do local old=accessories:FindFirstChild(id);if old then old:Destroy()end;source.CursedAccessoryKit[id]:Clone().Parent=accessories end
 return ids
end
return M