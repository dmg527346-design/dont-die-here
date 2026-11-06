local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local GS=game:GetService('GuiService')
local CAS=game:GetService('ContextActionService')
local p=Players.LocalPlayer
local function authorized()return p:GetAttribute('AdminAuthorized')==true end
local function owner()return p:GetAttribute('AdminOwner')==true end
local event=RS:WaitForChild('AdminPassEvent')
local Audio=require(RS:WaitForChild('GameplayAudio'))
local PANEL_MAX_W,PANEL_MAX_H,MARGIN,ROW_H=740,530,12,48
local colors={panel=Color3.fromRGB(22,42,43),card=Color3.fromRGB(31,55,53),cream=Color3.fromRGB(244,236,210),green=Color3.fromRGB(167,202,127),ink=Color3.fromRGB(8,18,22)}
local gui=Instance.new('ScreenGui');gui.Name='AdminPassPanel';gui.ResetOnSpawn=false;gui.DisplayOrder=989;gui.Parent=p:WaitForChild('PlayerGui')
local function round(x)local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,12);c.Parent=x;local s=Instance.new('UIStroke');s.Color=colors.ink;s.Thickness=2;s.Parent=x end
local function label(parent,name,value)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=value;t.BackgroundTransparency=1;t.Font=Enum.Font.FredokaOne;t.TextColor3=colors.cream;t.TextSize=16;t.TextWrapped=true;t.Parent=parent;return t
end
local function button(parent,name,value,fn)
 local b=Instance.new('TextButton');b.Name=name;b.Text=value;b.Font=Enum.Font.FredokaOne;b.TextSize=15;b.TextWrapped=true;b.TextColor3=colors.cream;b.BackgroundColor3=colors.card;b.AutoButtonColor=true;b.Selectable=true;b.Parent=parent;round(b)
 b.Activated:Connect(function()if not authorized()then return end;Audio.Play('UiClick');fn()end);return b
end
local openButton,closeButton,refreshButton,panel,status,rosterList,passList
local sequence=0;local waiting;local chosen;local snapshot={players={},passes={}};local previousFocus
panel=Instance.new('Frame');panel.Name='Panel';panel.AnchorPoint=Vector2.new(.5,.5);panel.Position=UDim2.fromScale(.5,.5);panel.BackgroundColor3=colors.panel;panel.Visible=false;panel.Parent=gui;round(panel)
local heading=label(panel,'Title','OWNER • PASS ACCESS');heading.Position=UDim2.fromOffset(12,8);heading.Size=UDim2.new(1,-118,0,32);heading.TextXAlignment=Enum.TextXAlignment.Left
local controls=label(panel,'Controls','');controls.Position=UDim2.fromOffset(12,42);controls.Size=UDim2.new(1,-24,0,28)
status=label(panel,'Status','Choose a player, then a pass. Access saves for future games.');status.Position=UDim2.new(0,12,1,-56);status.Size=UDim2.new(1,-24,0,48)
local function list(name,x,w)
 local f=Instance.new('ScrollingFrame');f.Name=name;f.Position=UDim2.new(x,12,0,104);f.Size=UDim2.new(w,-18,1,-168);f.BackgroundColor3=colors.ink;f.BorderSizePixel=0;f.ScrollBarThickness=6;f.AutomaticCanvasSize=Enum.AutomaticSize.Y;f.CanvasSize=UDim2.new();f.Parent=panel;round(f)
 local layout=Instance.new('UIListLayout');layout.Padding=UDim.new(0,6);layout.Parent=f
 local pad=Instance.new('UIPadding');pad.PaddingTop=UDim.new(0,6);pad.PaddingBottom=UDim.new(0,6);pad.PaddingLeft=UDim.new(0,6);pad.PaddingRight=UDim.new(0,10);pad.Parent=f
 return f
end
rosterList=list('Players',0,.40);passList=list('Passes',.40,.60)
local render
local function request(action,userId,offerId)
 if waiting then return end
 sequence+=1;waiting=sequence;status.Text=action=='grant'and 'Saving access…'or 'Loading players…'
 event:FireServer(sequence,action,userId,offerId)
 local id=sequence;task.delay(35,function()if waiting==id then waiting=nil;status.Text='The request is taking longer than expected. Refresh to check access.'end end)
end
render=function()
 local focus=GS.SelectedObject;local focusName=focus and focus:IsDescendantOf(panel)and focus.Name
 for _,f in {rosterList,passList}do for _,x in f:GetChildren()do if x:IsA('GuiObject')then x:Destroy()end end end
 local target
 for _,row in snapshot.players do
  if row.id==chosen then target=row end
  local b=button(rosterList,'Player_'..row.id,row.displayName..'\n@'..row.name,function()chosen=row.id;render();status.Text='Grant access to @'..row.name end)
  b.Size=UDim2.new(1,0,0,ROW_H+8);b.BackgroundColor3=row.id==chosen and colors.green or colors.card
  b.TextColor3=row.id==chosen and colors.ink or colors.cream
 end
 if chosen and not target then chosen=nil end
 for _,offer in snapshot.passes do
  local has=target and target.passes[offer.id]==true
  local title=offer.name..(has and' • HAS ACCESS'or owner()and' • GRANT'or' • OWNER ONLY')
  local b=button(passList,'Grant_'..offer.id,title,function()
   if not owner()then status.Text='Only the owner can grant pass access.';return end
   if not chosen then status.Text='Select a player from the left first.';return end
   if has then status.Text='This player already has '..offer.name..' access.';return end
   request('grant',chosen,offer.id)
  end)
  b.Size=UDim2.new(1,0,0,ROW_H);b.TextColor3=has and colors.green or colors.cream
 end
 if focusName then local replacement=panel:FindFirstChild(focusName,true);GS.SelectedObject=replacement and replacement:IsA('GuiButton')and replacement or refreshButton end
end
local function platform()
 return InputHints.Get()
end
local function layout()
 local camera=workspace.CurrentCamera;if not camera then return end
 local v=gui.AbsoluteSize
 panel.Size=UDim2.fromOffset(math.min(PANEL_MAX_W,v.X-MARGIN*2),math.min(PANEL_MAX_H,math.max(180,v.Y-MARGIN*2)))
 local mode=platform()
 controls.Text=mode=='pad'and 'D-pad to choose • A to grant • B to close'
  or mode=='touch'and 'Tap a player, then tap a pass to grant access'
  or 'Click a player, then a pass • P opens/closes'
end
local function setOpen(value)
 if value and not owner()then return end -- owner only (2026-10-25)
 panel.Visible=value;closeButton.Modal=value;p:SetAttribute('AdminPassPanelOpen',value)
 if value then UIS.MouseBehavior=Enum.MouseBehavior.Default end
 if value then previousFocus=GS.SelectedObject;layout();request('list');if platform()=='pad'then GS.SelectedObject=refreshButton end
 else if GS.SelectedObject and GS.SelectedObject:IsDescendantOf(panel)then GS.SelectedObject=previousFocus and previousFocus.Parent and previousFocus or openButton end end
end
-- No on-screen button (owner 2026-10-25): this panel is the PASSES tab of the owner's P window (AdminPowersClient).
closeButton=button(panel,'Close','CLOSE',function()setOpen(false)end);closeButton.AnchorPoint=Vector2.new(1,0);closeButton.Position=UDim2.new(1,-12,0,8);closeButton.Size=UDim2.fromOffset(90,44)
refreshButton=button(panel,'Refresh','REFRESH',function()request('list')end);refreshButton.Position=UDim2.new(1,-110,0,54);refreshButton.Size=UDim2.fromOffset(98,44)
-- Keep refresh above the lists; the control hint leaves room for this button.
refreshButton.Position=UDim2.new(1,-214,0,8);heading.Size=UDim2.new(1,-230,0,32)
event.OnClientEvent:Connect(function(id,ok,result)
 if id~=waiting then return end;waiting=nil
 if not ok then status.Text=type(result)=='string'and result or 'Could not grant access.';return end
 if result.players then snapshot=result;render();status.Text='Choose a player, then a pass. Grants apply immediately.'
 else
  for _,row in snapshot.players do if row.id==result.targetId then row.passes[result.offerId]=true end end
  render();status.Text=result.message
 end
end)
local api=Instance.new('BindableFunction');api.Name='PassPanelApi';api.Parent=script
api.OnInvoke=function(action,at,size)
 if action=='isOpen'then return panel.Visible end
 if action=='close'then setOpen(false);return true end
 if action=='open'and owner()then
  setOpen(true)
  if typeof(at)=='Vector2'and typeof(size)=='Vector2'then -- sit exactly where the powers window was
   local o=gui.AbsolutePosition;panel.AnchorPoint=Vector2.zero;panel.Position=UDim2.fromOffset(at.X-o.X,at.Y-o.Y);panel.Size=UDim2.fromOffset(size.X,size.Y)
  end
  return true
 end
 return false
end
CAS:BindActionAtPriority('OwnerPassPanelBack',function(_,state)
 if not panel.Visible then return Enum.ContextActionResult.Pass end
 if state==Enum.UserInputState.Begin then setOpen(false)end
 return Enum.ContextActionResult.Sink
end,false,5000,Enum.KeyCode.ButtonB)
InputHints.Changed:Connect(layout)
workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()local c=workspace.CurrentCamera;if c then c:GetPropertyChangedSignal('ViewportSize'):Connect(layout)end;layout()end)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout)end
layout()

local tools=button(panel,'PlayerTools','POWERS',function() -- back to the powers tabs of the same window
 setOpen(false);p.PlayerScripts:WaitForChild('AdminPowersClient'):WaitForChild('OpenPowers'):Fire()
end)
tools.Size=UDim2.fromOffset(130,44);tools.Position=UDim2.new(0,12,0,48)
controls.Position=UDim2.fromOffset(150,50);controls.Size=UDim2.new(1,-162,0,24)
local function accessChanged()heading.Text='OWNER · PASS ACCESS';gui.Enabled=owner();if not owner()then setOpen(false)end end
p:GetAttributeChangedSignal('AdminAuthorized'):Connect(accessChanged);p:GetAttributeChangedSignal('AdminOwner'):Connect(accessChanged);accessChanged()
