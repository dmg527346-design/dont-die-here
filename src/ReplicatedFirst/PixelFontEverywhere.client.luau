-- Press Start 2P everywhere (user request 2026-10-21): every TextLabel / TextButton / TextBox this client shows
-- (PlayerGui menus, HUD, tutorial, loading screen, world BillboardGuis / SurfaceGuis), the chat window and bubbles,
-- and the interaction prompts. Roblox's default prompt UI cannot change font, so prompts switch to Custom style
-- on this client and are drawn below (key, object, action, hold bar; tap / click works like the default).
-- Built-in Roblox font family, nothing uploaded. Delete this one script to get the original fonts back.
local Players=game:GetService('Players')
local PromptService=game:GetService('ProximityPromptService')
local UIS=game:GetService('UserInputService')
local TextChat=game:GetService('TextChatService')
local Tween=game:GetService('TweenService')
local RS=game:GetService('ReplicatedStorage')
local PIXEL=Font.new('rbxasset://fonts/families/PressStart2P.json')
local player=Players.LocalPlayer

-- Text: set now, and again whenever a script sets .Font / .FontFace back.
local hooked=setmetatable({},{__mode='k'})
-- Kept in their own fonts (user request 2026-10-22): the main menu's page panel (Start a run, shop, settings pages).
local function excluded(o)
 local canvas=o:FindFirstAncestor('Canvas')
 return canvas~=nil and canvas.Parent~=nil and canvas.Parent.Name=='HorrorMainMenu'
end
-- Drop shadow, bottom right (user request 2026-10-22). Roblox text has no shadow, so each pixel label draws its text
-- twice inside itself: PixelShadow (black, shifted down-right) under PixelFace (the real look). The label's own text is
-- hidden, and every text property a script sets on the label (text, colour, fades, typewriter) is copied to both.
-- TextBoxes keep plain text (typing into a hidden label would be invisible).
local SYNC={'TextSize','TextScaled','TextWrapped','TextXAlignment','TextYAlignment','RichText','LineHeight','TextTruncate','FontFace'}
-- The shadow copy drops rich-text colours and strokes, so it is always plain black.
local function blackText(s)
 s=string.gsub(s,'%s+color%s*=%s*"[^"]*"','');s=string.gsub(s,"%s+color%s*=%s*'[^']*'",'')
 s=string.gsub(s,'<stroke[^>]*>','');return (string.gsub(s,'</stroke>',''))
end
local shadowed=setmetatable({},{__mode='k'})
local function shadow(o)
 if shadowed[o] or o:IsA('TextBox') then return end
 shadowed[o]=true
 local face=Instance.new('TextLabel');face.Name='PixelFace'
 local drop=Instance.new('TextLabel');drop.Name='PixelShadow'
 for _,t in {drop,face}do
  t.BackgroundTransparency=1;t.BorderSizePixel=0;t.Size=UDim2.fromScale(1,1);t.Active=false;t.AutoLocalize=false
  for _,c in o:GetChildren()do if c:IsA('UITextSizeConstraint')then c:Clone().Parent=t end end
 end
 drop.TextColor3=Color3.new(0,0,0);drop.TextStrokeTransparency=1
 drop.ZIndex=o.ZIndex;face.ZIndex=o.ZIndex+1
  -- The label's own glyphs are hidden with MaxVisibleGraphemes=0, so every script keeps full control of TextTransparency,
 -- colours and strokes (they are copied as-is; fades work). Writing TextTransparency ourselves left toasts stuck on screen:
 -- a fade to 1 that ended on our own 1 never fired a change. Scripts that type text out set PixelFace/PixelShadow directly.
 local function paint()
  local alpha=o.TextTransparency
  face.TextTransparency=alpha;face.TextStrokeTransparency=o.TextStrokeTransparency
  local c=o.TextColor3;local dark=c.R*.3+c.G*.59+c.B*.11<.35 -- dark text (keycaps on light keys): a black shadow only doubles it
  drop.TextTransparency=dark and 1 or alpha -- solid black, as opaque as the text itself
  face.TextColor3=o.TextColor3;face.TextStrokeColor3=o.TextStrokeColor3
 end
 local function offset()
  local px=math.clamp(math.floor(o.TextBounds.Y/24+.5),1,2) -- tight: 1 px, 2 px only on big text
  drop.Position=UDim2.fromOffset(px,px)
 end
 for _,k in SYNC do face[k]=o[k];drop[k]=o[k];o:GetPropertyChangedSignal(k):Connect(function()face[k]=o[k];drop[k]=o[k]end)end
 local function syncText()face.Text=o.Text;drop.Text=o.RichText and blackText(o.Text)or o.Text end
 syncText();o:GetPropertyChangedSignal('Text'):Connect(syncText);o:GetPropertyChangedSignal('RichText'):Connect(syncText)
 for _,k in {'TextTransparency','TextStrokeTransparency','TextColor3','TextStrokeColor3'}do o:GetPropertyChangedSignal(k):Connect(paint)end
 local function hideGlyphs()
  if o.MaxVisibleGraphemes~=0 then face.MaxVisibleGraphemes=o.MaxVisibleGraphemes;drop.MaxVisibleGraphemes=o.MaxVisibleGraphemes;o.MaxVisibleGraphemes=0 end
 end
 o:GetPropertyChangedSignal('MaxVisibleGraphemes'):Connect(hideGlyphs)
 o:GetPropertyChangedSignal('TextBounds'):Connect(offset)
 o:GetPropertyChangedSignal('ZIndex'):Connect(function()drop.ZIndex=o.ZIndex;face.ZIndex=o.ZIndex+1 end)
 face.MaxVisibleGraphemes=o.MaxVisibleGraphemes;drop.MaxVisibleGraphemes=o.MaxVisibleGraphemes
 -- Text outlines (UIStroke, Contextual) and text gradients belong to the glyphs: copy them onto the face and keep
 -- them in sync, otherwise the visible copy loses them (quota amount lost its outline, 2026-10-22).
 local copies={}
 local function mirror(c)
  if copies[c] then return end
  if not(c:IsA('UIGradient')or c:IsA('UIStroke')and c.ApplyStrokeMode==Enum.ApplyStrokeMode.Contextual)then return end
  local m=c:Clone();copies[c]=m;m.Parent=face
  c.Changed:Connect(function(prop)if prop~='Parent' and prop~='Name' then pcall(function()m[prop]=c[prop]end)end end)
  c.AncestryChanged:Connect(function()if c.Parent~=o then m:Destroy();copies[c]=nil end end)
 end
 for _,c in o:GetChildren()do mirror(c)end
 o.ChildAdded:Connect(mirror)
 paint();offset();hideGlyphs()
 drop.Parent=o;face.Parent=o
end
local function apply(o)
 if not(o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox'))then return end
 if o.Name=='PixelFace'or o.Name=='PixelShadow'then return end
 if excluded(o)then return end
 if o.FontFace.Family~=PIXEL.Family then o.FontFace=PIXEL end
 shadow(o)
 if hooked[o]then return end;hooked[o]=true
 o:GetPropertyChangedSignal('FontFace'):Connect(function()if o.FontFace.Family~=PIXEL.Family then o.FontFace=PIXEL end end)
end
local function watch(root)
 for _,o in root:GetDescendants()do apply(o)end
 root.DescendantAdded:Connect(apply)
end
task.spawn(function()watch(player:WaitForChild('PlayerGui'))end)
watch(workspace)

-- Chat window, input bar and bubbles.
local function chatFont()
 for _,name in {'ChatWindowConfiguration','ChatInputBarConfiguration','BubbleChatConfiguration','ChannelTabsConfiguration'}do
  local c=TextChat:FindFirstChild(name);if c then pcall(function()c.FontFace=PIXEL end)end
 end
end
chatFont();TextChat.ChildAdded:Connect(function()task.defer(chatFont)end)

-- Interaction prompts.
local hints;task.spawn(function()local m=RS:WaitForChild('InputHints',30);if m then local ok,v=pcall(require,m);if ok then hints=v end end end)
local function custom(o)if o:IsA('ProximityPrompt')then o.Style=Enum.ProximityPromptStyle.Custom end end
for _,o in workspace:GetDescendants()do custom(o)end
workspace.DescendantAdded:Connect(custom)

local PANEL=Color3.fromRGB(16,22,24);local INK=Color3.fromRGB(240,238,226);local MUTED=Color3.fromRGB(168,182,176);local BAR=Color3.fromRGB(167,227,138)
local PAD={ButtonA='A',ButtonB='B',ButtonX='X',ButtonY='Y',ButtonL1='LB',ButtonR1='RB',ButtonL2='LT',ButtonR2='RT',ButtonL3='LS',ButtonR3='RS',DPadUp='UP',DPadDown='DN',DPadLeft='LT',DPadRight='RT'}
local function keyText(prompt,inputType)
 if inputType==Enum.ProximityPromptInputType.Touch then return 'TAP'end
 if inputType==Enum.ProximityPromptInputType.Gamepad then
  local name=prompt.GamepadKeyCode.Name
  if hints and hints.Button then local ok,v=pcall(hints.Button,name);if ok and type(v)=='string'and #v>0 then return v=='Square'and'□'or v=='Circle'and'○'or v=='Triangle'and'△'or v=='Cross'and'✕'or v end end
  return PAD[name]or name
 end
 local s=UIS:GetStringForKeyCode(prompt.KeyboardKeyCode)
 return(s~=''and s or prompt.KeyboardKeyCode.Name):upper()
end
local function new(class,parent,props)local o=Instance.new(class);for k,v in props do o[k]=v end;o.Parent=parent;return o end

local open={}
PromptService.PromptShown:Connect(function(prompt,inputType)
 if prompt.Style~=Enum.ProximityPromptStyle.Custom then return end
 local gui=player:FindFirstChild('PlayerGui');if not gui then return end
 local hasObject=prompt.ObjectText~=''
 local width=math.clamp(84+10*math.max(#prompt.ActionText,#prompt.ObjectText),170,360)
 local board=new('BillboardGui',gui,{Name='PixelPrompt',Adornee=prompt.Parent,Size=UDim2.fromOffset(width,58),AlwaysOnTop=true,LightInfluence=0,ResetOnSpawn=false,
  SizeOffset=Vector2.new(prompt.UIOffset.X/width,prompt.UIOffset.Y/58),ClipsDescendants=false,Active=true})
 local panel=new('Frame',board,{BackgroundColor3=PANEL,BackgroundTransparency=.15,Size=UDim2.fromScale(1,1),BorderSizePixel=0})
 new('UICorner',panel,{CornerRadius=UDim.new(0,8)});new('UIStroke',panel,{Color=Color3.fromRGB(6,10,12),Thickness=2})
 local scale=new('UIScale',panel,{Scale=.7})
 local key=new('TextButton',panel,{Name='Key',AutoButtonColor=false,BackgroundColor3=INK,Position=UDim2.fromOffset(8,8),Size=UDim2.fromOffset(42,42),Text=keyText(prompt,inputType),TextColor3=PANEL,TextScaled=true,FontFace=PIXEL})
 new('UICorner',key,{CornerRadius=UDim.new(0,6)});new('UITextSizeConstraint',key,{MaxTextSize=16,MinTextSize=6});new('UIPadding',key,{PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4)})
 new('TextLabel',panel,{Name='Object',BackgroundTransparency=1,Position=UDim2.fromOffset(58,8),Size=UDim2.new(1,-64,0,14),Text=prompt.ObjectText,TextColor3=MUTED,TextSize=9,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,FontFace=PIXEL,Visible=hasObject})
 new('TextLabel',panel,{Name='Action',BackgroundTransparency=1,Position=UDim2.fromOffset(58,hasObject and 26 or 16),Size=UDim2.new(1,-64,0,18),Text=prompt.ActionText,TextColor3=INK,TextScaled=true,TextXAlignment=Enum.TextXAlignment.Left,FontFace=PIXEL})
 local track=new('Frame',panel,{BackgroundColor3=Color3.fromRGB(40,50,52),BorderSizePixel=0,Position=UDim2.new(0,58,1,-9),Size=UDim2.new(1,-66,0,3),Visible=prompt.HoldDuration>0})
 local fill=new('Frame',track,{BackgroundColor3=BAR,BorderSizePixel=0,Size=UDim2.fromScale(0,1)})
 Tween:Create(scale,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 local conns={}
 local holding
 table.insert(conns,prompt.PromptButtonHoldBegan:Connect(function()
  holding=Tween:Create(fill,TweenInfo.new(prompt.HoldDuration,Enum.EasingStyle.Linear),{Size=UDim2.fromScale(1,1)});holding:Play()
 end))
 table.insert(conns,prompt.PromptButtonHoldEnded:Connect(function()if holding then holding:Cancel()end;fill.Size=UDim2.fromScale(0,1)end))
 table.insert(conns,prompt.Triggered:Connect(function()fill.Size=UDim2.fromScale(0,1);scale.Scale=.92;Tween:Create(scale,TweenInfo.new(.15),{Scale=1}):Play()end))
 table.insert(conns,prompt:GetPropertyChangedSignal('ActionText'):Connect(function()panel.Action.Text=prompt.ActionText end))
 table.insert(conns,prompt:GetPropertyChangedSignal('ObjectText'):Connect(function()panel.Object.Text=prompt.ObjectText end))
 -- Tap / click on the prompt works like Roblox's own prompt.
 if inputType==Enum.ProximityPromptInputType.Touch or prompt.ClickablePrompt then
  local down=false
  local function press(input)if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then down=true;prompt:InputHoldBegin()end end
  local function release(input)if down and(input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1)then down=false;prompt:InputHoldEnd()end end
  table.insert(conns,key.InputBegan:Connect(press));table.insert(conns,key.InputEnded:Connect(release))
  local cover=new('TextButton',panel,{Name='Tap',BackgroundTransparency=1,Text='',Size=UDim2.fromScale(1,1),ZIndex=5})
  table.insert(conns,cover.InputBegan:Connect(press));table.insert(conns,cover.InputEnded:Connect(release))
 end
 open[prompt]={board=board,conns=conns}
end)
PromptService.PromptHidden:Connect(function(prompt)
 local o=open[prompt];if not o then return end;open[prompt]=nil
 for _,c in o.conns do c:Disconnect()end;o.board:Destroy()
end)
