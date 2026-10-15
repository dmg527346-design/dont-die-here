local Players=game:GetService('Players')
local regions={body=true,feet=true,stalks=true,rings=true}
local records={}
local function bind(player)
 local record={connections={},parts={}}
 records[player]=record
 local function disconnectCharacter()
  for _,c in ipairs(record.connections)do c:Disconnect()end
  table.clear(record.connections);table.clear(record.parts)
 end
 local function characterAdded(character)
  disconnectCharacter()
  local scheduled=false
  local function apply()
   local value=character:GetAttribute('BodyColourHex')or player:GetAttribute('BodyColourHex')
   local color=if type(value)=='string'and value:match('^#%x%x%x%x%x%x$')then Color3.fromHex(value:sub(2))else nil
   for part in pairs(record.parts)do
    if part:IsDescendantOf(character)then
     local shade=part:GetAttribute('ColourShade')or 1
     local override=part:GetAttribute('ColourOverride')
     local target
     if typeof(override)=='Color3'then target=override
     elseif color then target=Color3.new(math.clamp(color.R*shade,0,1),math.clamp(color.G*shade,0,1),math.clamp(color.B*shade,0,1))
     else continue end
     if part.Color~=target then part.Color=target end
     local surface=part:FindFirstChild('UniformBodySurface');if surface and surface.Color~=target then surface.Color=target end
    end
   end
  end
  local function refresh()
   if scheduled then return end;scheduled=true
   task.defer(function()scheduled=false;if player.Character==character then apply()end end)
  end
  local function watch(part)
   if part:IsA('BasePart')and regions[part:GetAttribute('ColourRegion')]and not record.parts[part]then
    record.parts[part]=true
    table.insert(record.connections,part:GetPropertyChangedSignal('Color'):Connect(refresh))
    table.insert(record.connections,part:GetAttributeChangedSignal('ColourOverride'):Connect(refresh))
   end
  end
  for _,part in ipairs(character:GetDescendants())do watch(part)end
  table.insert(record.connections,character.DescendantAdded:Connect(function(part)watch(part);refresh()end))
  table.insert(record.connections,character:GetAttributeChangedSignal('BodyColourHex'):Connect(refresh))
  table.insert(record.connections,player:GetAttributeChangedSignal('BodyColourHex'):Connect(refresh))
  apply()
 end
 record.added=player.CharacterAdded:Connect(characterAdded)
 record.removing=player.CharacterRemoving:Connect(disconnectCharacter)
 if player.Character then characterAdded(player.Character)end
end
Players.PlayerAdded:Connect(bind)
Players.PlayerRemoving:Connect(function(player)local record=records[player];if record then record.added:Disconnect();record.removing:Disconnect();for _,c in ipairs(record.connections)do c:Disconnect()end;records[player]=nil end end)
for _,player in ipairs(Players:GetPlayers())do bind(player)end
