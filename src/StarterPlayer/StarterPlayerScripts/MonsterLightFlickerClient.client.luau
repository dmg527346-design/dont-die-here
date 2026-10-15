-- A monster close to you makes the lights around you flicker and flash red (your screen only).
-- The closer the monster, the harder the flicker. Every touched light is restored when it leaves.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local player=Players.LocalPlayer
local DANGER_RADIUS=40 -- monster distance where the effect starts
local FULL_RADIUS=12 -- monster distance for the strongest effect
local LIGHT_RADIUS=32 -- lights this close to you react
local RED=Color3.fromRGB(255,30,25)
local lights,base={},{} -- base[light]={brightness,color,enabled,nextFlip,on}
local cachedMap
local function rebuild(map)
 table.clear(lights);cachedMap=map
 for _,d in ipairs(map:GetDescendants())do if d:IsA('Light')then table.insert(lights,d)end end
end
local dirty=true
local function watch(map)
 map.DescendantAdded:Connect(function(d)if d:IsA('Light')then dirty=true end end)
 map.DescendantRemoving:Connect(function(d)if d:IsA('Light')then dirty=true end end)
end
local function restore(l)
 local b=base[l];if not b then return end
 base[l]=nil
 if l.Parent then l.Brightness=b.brightness;l.Color=b.color;l.Enabled=b.enabled end
end
local acc=0
Run.RenderStepped:Connect(function(dt)
 acc+=dt;if acc<1/30 then return end;dt=acc;acc=0
 local map=workspace:FindFirstChild('Mansion')
 if map~=cachedMap then for l in pairs(base)do restore(l)end;if map then watch(map)end;dirty=true;cachedMap=map end
 if map and dirty then rebuild(map);dirty=false end
 local c=player.Character;local r=c and c:FindFirstChild('HumanoidRootPart')
 -- Strength from the nearest monster.
 local strength=0
 local folder=workspace:FindFirstChild('RoamingCreatures')
 if r and folder and player:GetAttribute('MissionActive')==true then
  for _,m in ipairs(folder:GetChildren())do
   local part=m:IsA('Model')and(m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart',true))
   if part then
    local d=(part.Position-r.Position).Magnitude
    if d<DANGER_RADIUS then strength=math.max(strength,1-math.clamp((d-FULL_RADIUS)/(DANGER_RADIUS-FULL_RADIUS),0,1))end
   end
  end
 end
 local now=os.clock()
 local active={}
 if strength>0 and r then
  for _,l in ipairs(lights)do
   local part=l.Parent
   if part and part:IsA('BasePart')and(part.Position-r.Position).Magnitude<LIGHT_RADIUS then
    active[l]=true
    local b=base[l]
    if not b then b={brightness=l.Brightness,color=l.Color,enabled=l.Enabled,nextFlip=now,on=true};base[l]=b end
    -- Random on/off blinks; closer monster = more time dark and faster blinking.
    if now>=b.nextFlip then
     b.on=not b.on or math.random()>strength*.75
     b.nextFlip=now+(b.on and(.08+math.random()*(.6-.45*strength))or(.04+math.random()*.12*strength))
    end
    local pulse=.5+.5*math.sin(now*(6+strength*10)+(part.Position.X+part.Position.Z)*.3)
    l.Color=b.color:Lerp(RED,math.clamp(.35+.55*strength*pulse+.1,0,1))
    l.Brightness=b.on and b.brightness*(.7+.5*math.random()*strength)or b.brightness*.04
    l.Enabled=b.enabled
   end
  end
 end
 for l in pairs(base)do if not active[l]then restore(l)end end
end)
player.CharacterRemoving:Connect(function()for l in pairs(base)do restore(l)end end)
