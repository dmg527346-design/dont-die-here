-- Consoles (owner 2026-10-25): the whole UI 30% bigger on a TV, so it reads like the computer UI does up close.
-- Each top-level piece of every ScreenGui gets a UIScale. A UIScale grows a piece about its AnchorPoint, so centred
-- things stay centred and corner things stay in their corner; the scale is capped so nothing leaves the screen.
-- Pieces that already own a UIScale (their script sizes them, e.g. the rank card, PLAY row, HP / stamina bars) are left alone.
local GuiService=game:GetService('GuiService')
if not GuiService:IsTenFootInterface()then return end
local Players=game:GetService('Players')
local TV=1.3
local NAME='ConsoleTvScale'
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')

local SKIP={MenuGrid=true,NavQuests=true,NavQuestsDrop=true} -- the lobby grid and Quests bar size themselves on consoles (MainMenuClient TV_SCALE)
local function ownScale(o)
 if SKIP[o.Name] then return true end
 for _,c in o:GetChildren()do if c:IsA('UIScale')and c.Name~=NAME then return true end end
 return false
end
-- A see-through frame that covers (nearly) the whole screen is only a holder: scale what is inside it instead.
local function isHolder(o)
 return o:IsA('Frame')and o.BackgroundTransparency>=.99 and o.Size.X.Scale>=.9 and o.Size.Y.Scale>=.9
end
local function fit(o,ui)
 local cam=workspace.CurrentCamera;if not cam then return end
 local cur=ui.Scale>0 and ui.Scale or 1
 local size=o.AbsoluteSize/cur;if size.X<=0 or size.Y<=0 then return end
 local gui=o:FindFirstAncestorWhichIsA('LayerCollector')
 local origin=gui and gui:IsA('ScreenGui')and gui.AbsolutePosition or Vector2.zero
 local view=gui and gui:IsA('ScreenGui')and gui.AbsoluteSize or cam.ViewportSize
 -- the anchor point stays put while the box grows around it
 local a=o.AnchorPoint;local pos=o.AbsolutePosition-origin
 local pivot=pos+o.AbsoluteSize*a
 local s=TV
 for _,axis in {'X','Y'}do
  local p,len,an,v=pivot[axis],size[axis],a[axis],view[axis]
  if len*an>0 then s=math.min(s,p/(len*an))end
  if len*(1-an)>0 then s=math.min(s,(v-p)/(len*(1-an)))end
 end
 ui.Scale=math.clamp(s,1,TV)
end
local function apply(o)
 if not o:IsA('GuiObject')or ownScale(o)then return end
 if isHolder(o)then
  for _,c in o:GetChildren()do apply(c)end
  o.ChildAdded:Connect(function(c)task.defer(apply,c)end)
  return
 end
 if o:FindFirstChild(NAME)then return end
 local ui=Instance.new('UIScale');ui.Name=NAME;ui.Parent=o
 local busy=false
 local function refit()if busy then return end;busy=true;task.defer(function()busy=false;if ui.Parent then fit(o,ui)end end)end
 o:GetPropertyChangedSignal('AbsoluteSize'):Connect(refit)
 o:GetPropertyChangedSignal('AbsolutePosition'):Connect(refit)
 refit()
 -- a script that later gives the piece its own UIScale owns its size again
 o.ChildAdded:Connect(function(c)if c:IsA('UIScale')and c.Name~=NAME then ui:Destroy()end end)
end
local function watch(gui)
 if not gui:IsA('ScreenGui')or gui:GetAttribute('NoTvScale')then return end
 for _,c in gui:GetChildren()do apply(c)end
 gui.ChildAdded:Connect(function(c)task.defer(apply,c)end)
end
for _,g in pg:GetChildren()do watch(g)end
pg.ChildAdded:Connect(watch)
