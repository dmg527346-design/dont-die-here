-- Pure ranking policy. Personal progress is deliberately outside this module.
local Policy={}
local function validId(id)
    return type(id)=='number' and id==id and id>0 and id%1==0 and id<=9007199254740991
end
function Policy.new(explicit,creatorUserId,creatorResolved)
    local excluded={}
    for id,value in explicit do if value==true and validId(id)then excluded[id]=true end end
    if validId(creatorUserId)then excluded[creatorUserId]=true end
    local resolved=creatorResolved~=false
    local self={}
    function self.IsExcluded(id) return excluded[id]==true end
    function self.CanRank(id) return resolved and validId(id) and not excluded[id] end
    function self.CreatorReady() return resolved end
    function self.ResolveCreator(id)
        if validId(id)then excluded[id]=true end
        resolved=true
    end
    function self.ExcludedIds()
        local ids={};for id in excluded do table.insert(ids,id)end;table.sort(ids);return ids
    end
    function self.PageSize()
        local n=0;for _ in excluded do n+=1 end
        return math.min(100,10+n)
    end
    return self
end
return Policy