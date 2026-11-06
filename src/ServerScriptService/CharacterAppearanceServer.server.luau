-- Two independent, exact RGB choices. Version 1 palette saves are migrated in place.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local DSS=game:GetService('DataStoreService')
local RunService=game:GetService('RunService')
local schemes=require(RS:WaitForChild('CharacterSchemes'))
local event=RS:WaitForChild('CharacterCustomColour')
local LOCAL_REVIEW=RunService:IsStudio()and game.PlaceId==0 and game.GameId==0
local STUDIO_MEMORY=LOCAL_REVIEW or game:GetService('RunService'):IsStudio()and workspace:GetAttribute('StudioDataStores')~=true -- Studio playtests keep saves in memory: stopping during a DataStore call hangs Studio. Workspace StudioDataStores=true tests real saves
local store
if not STUDIO_MEMORY then store=DSS:GetDataStore(RunService:IsStudio() and 'HorrorCharacterScheme_v1_Studio' or 'HorrorCharacterScheme_v1')end
local SAVE_INTERVAL=45
local RATE_LIMIT=.08
local states={}
local closing=false
local fixed=schemes[1]
local EYE_DEFAULT=Color3.fromRGB(238,233,217)
local THROAT_FIXED=Color3.fromRGB(50,32,43)
local THROAT_CAVITY_FIXED=Color3.fromRGB(32,17,28)
local THROAT_DEEP_FIXED=Color3.fromRGB(13,8,17)
local TEETH_FIXED=Color3.fromRGB(239,232,212)
local PUPIL_FIXED=Color3.fromRGB(17,17,22)
local function fromColor(c) return {math.round(c.R*255),math.round(c.G*255),math.round(c.B*255)} end
local function validByte(v) return type(v)=='number' and v==v and v%1==0 and v>=0 and v<=255 end
local function validRGB(c) return type(c)=='table' and validByte(c[1]) and validByte(c[2]) and validByte(c[3]) end
local function copy(c) return {c[1],c[2],c[3]} end
local function hex(c) return string.format('#%02X%02X%02X',c[1],c[2],c[3]) end
local function asColor(c) return Color3.fromRGB(c[1],c[2],c[3]) end
local function clean(old)
    if type(old)=='table' and old.version==2 and validRGB(old.body) and validRGB(old.eyes) then
        return copy(old.body),copy(old.eyes)
    end
    local i=type(old)=='table' and old.version==1 and old.index or 1
    if type(i)~='number' or i%1~=0 or i<1 or i>#schemes then i=1 end
    return fromColor(schemes[i].body),fromColor(EYE_DEFAULT)
end
local function apply(player,character)
    local state=states[player]
    if not state then return end
    player:SetAttribute('BodyColourHex',hex(state.body))
    player:SetAttribute('EyeColourHex',hex(state.eyes))
    if not character then return end
    local body=asColor(state.body)
    local eyes=asColor(state.eyes)
    local bc=character:FindFirstChildOfClass('BodyColors')
    if bc then
        bc.HeadColor3=fixed.lips
        bc.TorsoColor3=body
        bc.LeftArmColor3=body;bc.RightArmColor3=body
        bc.LeftLegColor3=body;bc.RightLegColor3=body
    end
    for _,part in character:GetDescendants() do
        if part:IsA('BasePart') then
            local region=part:GetAttribute('ColourRegion')
            local color
            if region=='white' then color=eyes
            elseif region=='body' or region=='feet' or region=='stalks' or region=='rings' then color=body
            elseif region=='lips' then color=fixed.lips
            elseif region=='mouth' then color=THROAT_FIXED
            elseif region=='throat' then color=THROAT_CAVITY_FIXED
            elseif region=='throat_deep' then color=THROAT_DEEP_FIXED
            elseif region=='teeth' then color=TEETH_FIXED
            elseif region=='pupil' then color=PUPIL_FIXED end
            -- Temporary item effects (e.g. MakeupKit lipstick) set ColourOverride; it wins until they clear it.
            local override=part:GetAttribute('ColourOverride')
            if typeof(override)=='Color3' then
                if part.Color~=override then part.Color=override end
            elseif color then
                local shade=part:GetAttribute('ColourShade') or 1
                part.Color=Color3.new(math.clamp(color.R*shade,0,1),math.clamp(color.G*shade,0,1),math.clamp(color.B*shade,0,1))
                local surface=part:FindFirstChild('UniformBodySurface');if surface then surface.Color=part.Color end
            end
        end
    end
    character:SetAttribute('BodyColourHex',hex(state.body))
    character:SetAttribute('EyeColourHex',hex(state.eyes))
    character:SetAttribute('ColourScheme',0)
end

-- Avatar appearance loading can recolor R15 limbs after CharacterAdded.
-- Keep the custom palette authoritative without a polling loop.
local function watchCharacter(player,character)
    local state=states[player]
    if not state then return end
    for _,connection in ipairs(state.characterConnections or {}) do connection:Disconnect() end
    state.characterConnections={}
    local watched={}
    local scheduled=false
    local function refresh()
        if scheduled then return end
        scheduled=true
        task.defer(function()
            scheduled=false
            if states[player]==state and player.Character==character then apply(player,character) end
        end)
    end
    local function watch(object)
        if watched[object] then return end
        if object:IsA('BasePart') and object:GetAttribute('ColourRegion') then
            watched[object]=true
            table.insert(state.characterConnections,object:GetPropertyChangedSignal('Color'):Connect(refresh))
        elseif object:IsA('BodyColors') then
            watched[object]=true
            table.insert(state.characterConnections,object.Changed:Connect(refresh))
        end
    end
    for _,object in ipairs(character:GetDescendants()) do watch(object) end
    table.insert(state.characterConnections,character.DescendantAdded:Connect(function(object) watch(object);refresh() end))
    apply(player,character)
end

local transfer=Instance.new('BindableFunction');transfer.Name='CharacterColourTransfer';transfer.Parent=game.ServerStorage
transfer.OnInvoke=function(player,bodyHex,eyeHex)
 local state=states[player];if not state then return false end
 local function parse(value)
  if type(value)~='string' or not value:match('^#%x%x%x%x%x%x$')then return nil end
  return {tonumber(value:sub(2,3),16),tonumber(value:sub(4,5),16),tonumber(value:sub(6,7),16)}
 end
 local body,eyes=parse(bodyHex),parse(eyeHex);if not body or not eyes then return false end
 state.body=body;state.eyes=eyes;state.revision+=1;state.changedAt=math.max(DateTime.now().UnixTimestampMillis,state.changedAt+1);apply(player,player.Character);return true
end
-- Lock-free saves: a write happens only when a colour changed, and every write carries the time of that change, so
-- an older write (another server, a retry) can never overwrite a newer choice. Loading is a plain read and never waits.
-- session/lease stay '' and 0 so servers still on the previous lease-based code keep loading these records.
local function save(player,state)
    if STUDIO_MEMORY then
        state.savedRevision=state.revision
        if player.Parent then player:SetAttribute('ColourSaveStatus','Studio session only')end
        return
    end
    if not state.loaded then return end
    while state.saving do task.wait(.1) end
    local revision=state.revision
    if revision==state.savedRevision then return end
    state.saving=true
    local body,eyes,stamp=copy(state.body),copy(state.eyes),state.changedAt
    local saved=false
    for attempt=1,3 do
        local superseded=false
        local ok=pcall(function()
            assert(store,'Persistence store is not available');return store:UpdateAsync('player_'..player.UserId,function(old)
                superseded=false
                if type(old)=='table' and type(old.version)=='number' and old.version>2 then superseded=true;return nil end
                if type(old)=='table' and type(old.updated)=='number' and old.updated>stamp then superseded=true;return nil end
                return {version=2,body=body,eyes=eyes,session='',lease=0,updated=stamp}
            end)
        end)
        if ok then saved=true;break end
        if superseded then saved=true;break end
        if attempt<3 then task.wait(attempt) end
    end
    if saved and state.savedRevision<revision then state.savedRevision=revision end
    state.saving=false
    if player.Parent then player:SetAttribute('ColourSaveStatus',saved and (state.revision==state.savedRevision and 'Saved' or 'Saving…') or 'Save unavailable') end
end
local function join(player)
    if states[player] then return end
    local state={body=fromColor(fixed.body),eyes=fromColor(EYE_DEFAULT),revision=0,savedRevision=0,changedAt=0,
        lastRequest=-math.huge,loaded=false,saving=false}
    states[player]=state
    player:SetAttribute('ColourSaveStatus','Loading')
    state.connection=player.CharacterAdded:Connect(function(character) watchCharacter(player,character) end)
    state.appearanceConnection=player.CharacterAppearanceLoaded:Connect(function(character)
        if player.Character==character then apply(player,character) end
    end)
    if player.Character then watchCharacter(player,player.Character) end
    if STUDIO_MEMORY then state.loaded=true;player:SetAttribute('ColourSaveStatus','Studio session only');apply(player,player.Character);return end
    task.spawn(function()
        local attempt,heldSince=0,nil
        while states[player]==state and not closing do
            attempt+=1
            local ok,old=pcall(function() assert(store,'Persistence store is not available');return store:GetAsync('player_'..player.UserId) end)
            if ok then
                -- A server on the previous code may still be flushing this player's last change on teleport; give it a moment.
                local held=type(old)=='table' and type(old.session)=='string' and old.session~='' and (tonumber(old.lease) or 0)>os.time()
                heldSince=heldSince or (held and os.clock()) or nil
                if not held or os.clock()-heldSince>=8 then
                    if type(old)=='table' and type(old.version)=='number' and old.version>2 then
                        player:SetAttribute('ColourSaveStatus','Session only — saving unavailable');return
                    end
                    local body,eyes=clean(old)
                    state.loaded=true
                    if state.revision==0 then state.body=body;state.eyes=eyes
                    else state.changedAt=math.max(state.changedAt,(type(old)=='table' and tonumber(old.updated) or 0)+1) end
                    player:SetAttribute('ColourSaveStatus',state.revision==state.savedRevision and 'Saved' or 'Saving…')
                    apply(player,player.Character)
                    if state.revision~=state.savedRevision then task.spawn(save,player,state) end
                    return
                end
                task.wait(1)
            else
                if attempt==3 and player.Parent then player:SetAttribute('ColourSaveStatus','Session only — saving unavailable') end
                task.wait(math.min(2^attempt,30))
            end
        end
    end)
end
event.OnServerEvent:Connect(function(player,region,r,g,b)
    local state=states[player]
    if closing or not state or (region~='body' and region~='eyes') or not validByte(r) or not validByte(g) or not validByte(b) then return end
    local now=os.clock()
    if now-state.lastRequest<RATE_LIMIT then return end
    state.lastRequest=now
    local nextColor={r,g,b}
    if hex(state[region])==hex(nextColor) then return end
    state[region]=nextColor;state.revision+=1;state.changedAt=math.max(DateTime.now().UnixTimestampMillis,state.changedAt+1)
    apply(player,player.Character)
    player:SetAttribute('ColourSaveStatus',state.loaded and 'Saving…' or 'Session only — saving unavailable')
    local revision=state.revision
    task.delay(3,function()
        if states[player]==state and state.loaded and state.revision==revision and not closing then save(player,state) end
    end)
end)
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player)
    local state=states[player]
    if not state then return end
    state.connection:Disconnect()
    state.appearanceConnection:Disconnect()
    for _,connection in ipairs(state.characterConnections or {}) do connection:Disconnect() end
    states[player]=nil
    save(player,state)
end)
for _,player in Players:GetPlayers() do join(player) end
task.spawn(function()
    while not closing do
        task.wait(SAVE_INTERVAL)
        if closing then break end
        -- Retries only: a change whose save failed. Nothing is written for players whose colours are already saved.
        for player,state in states do
            if state.loaded and not state.saving and state.revision~=state.savedRevision then task.spawn(save,player,state) end
        end
    end
end)
game:BindToClose(function()
 if game:GetService('RunService'):IsStudio() then return end -- Studio stop: close-time saves can hang the server shutdown
    closing=true
    local pending=0
    for player,state in states do
        pending+=1
        task.spawn(function() save(player,state);pending-=1 end)
    end
    local deadline=os.clock()+25
    while pending>0 and os.clock()<deadline do task.wait(.1) end
end)

