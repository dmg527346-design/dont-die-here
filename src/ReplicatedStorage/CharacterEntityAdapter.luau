-- Presentation adapter: entities reuse the game's existing character animation owners.
local Adapter={}
function Adapter.Watch(add,remove)
    local folder=workspace:WaitForChild('CharacterEntities')
    local proxies={}
    local function watch(c)
        if not c:IsA('Model') or c:GetAttribute('CharacterEntity')~=true or proxies[c] then return end
        local proxy={Character=c,UserId=c:GetAttribute('CopiedUserId') or 0,Parent=folder,IsEntity=true}
        function proxy:GetAttribute(key) return c:GetAttribute(key) end
        proxies[c]=proxy
        c.Destroying:Once(function()proxy.Parent=nil;proxies[c]=nil;remove(proxy)end)
        task.spawn(add,proxy,c)
    end
    folder.ChildAdded:Connect(watch)
    for _,c in folder:GetChildren()do watch(c)end
end
return Adapter