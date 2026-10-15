local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
-- Exact body and eye RGB controls; lip, mouth interior and pupil colours are fixed.
-- Van appearance panel: docked on the right like a character creator, black glass + neon rim (NeonUI),
-- big turnable preview on the left, red X and DONE both close. Behaviour and remotes are unchanged.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local GuiService=game:GetService('GuiService')
local RunService=game:GetService('RunService')
local CAS=game:GetService('ContextActionService')
local TweenService=game:GetService('TweenService')
local player=Players.LocalPlayer
local Appearance=require(RS:WaitForChild('AppearanceWidgets'))
local CameraGuard=require(RS:WaitForChild('CameraInputGuard'))
local UI=require(RS:WaitForChild('NeonUI'))
local paintPreview
local lobby=RS:WaitForChild('LobbyEvent')
local progress={ready=false,owned={},equipped={}}
local requestSequence=800000000;local responses={}
local drawOwned
local function request(action,data,callback)
 requestSequence+=1;local id=requestSequence;responses[id]=callback;lobby:FireServer(id,action,data)
 task.delay(25,function()responses[id]=nil end)
end
local event=RS:WaitForChild('CharacterCustomColour')
local values={body={145,168,102},eyes={238,233,217},light={255,236,196}}
local pending={body=0,eyes=0,light=0}
local REGIONS={'body','eyes','light'} -- light = flashlight beam (Flashlight Colors pass)
-- Quick colour presets (two rows of seven). Picking one is the same as typing that RGB value.
local PRESETS={
 body={{145,168,102},{110,140,80},{78,108,58},{190,204,120},{236,214,180},{206,160,120},{150,105,75},{96,66,46},{58,58,68},{205,205,214},{120,170,214},{180,130,214},{232,120,142},{242,190,90}},
 eyes={{238,233,217},{255,255,255},{255,240,200},{255,220,120},{255,170,80},{255,90,90},{200,40,60},{160,255,160},{90,220,120},{140,220,255},{80,140,255},{200,150,255},{255,140,220},{60,60,64}},
 light={{255,236,196},{255,255,255},{255,250,222},{255,214,140},{255,170,80},{255,80,80},{255,60,160},{200,90,255},{110,110,255},{80,180,255},{80,255,230},{90,255,120},{200,255,90},{255,240,90}},
}
local HEADINGS={body='Body Colour',eyes='Eye Colour',light='Flashlight Colour'}
-- Layout (tune by screenshot). Panel docks right; the preview stage fills the space to its left.
local EDGE,BANNER_H,BANNER_TOP,PANEL_TOP_GAP=16,52,8,12
local PANEL_MIN_W,PANEL_MAX_W,PANEL_SHARE,TWO_COLUMN_W,COLOUR_COL_W=340,640,.5,600,300
local SWATCH_COLS,SWATCH_GAP,SWATCH_MAX,SLIDER_H,STAGE_MIN_W=7,6,40,38,220
local SLIDE_IN,SLIDE_OUT,ROWS_START,ROW_STAGGER=.36,.2,.18,.06
local C=UI.Color
local gui=Instance.new('ScreenGui')
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Name='CharacterColourGui';gui.ResetOnSpawn=false;gui.DisplayOrder=130;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=player:WaitForChild('PlayerGui')
-- Phones: lay the whole panel out at a larger virtual size, then scale it down (smaller text, cards and buttons).
local PHONE_UI_SCALE=.65
local root=Instance.new('Frame');root.Name='Root';root.BackgroundTransparency=1;root.Size=UDim2.fromScale(1,1);root.ZIndex=1;root.Parent=gui
local rootScale=Instance.new('UIScale');rootScale.Parent=root
local function phoneScale()local v=gui.AbsoluteSize;return(game:GetService('UserInputService').TouchEnabled and v.Y<500)and PHONE_UI_SCALE or 1 end
local backdrop=UI.backdrop(gui,.6)
local function label(class,name,parent,size,face)
    local x=Instance.new(class);x.Name=name;x.BackgroundTransparency=1
    x.TextColor3=C.text;x.FontFace=face or UI.Font.Bold;x.TextSize=size or 14;x.Parent=parent
    return x
end
-- Title banner across the top centre.
local banner=UI.plate(gui,'TitleBanner',16);banner.AnchorPoint=Vector2.new(.5,0);banner.Visible=false
local bannerText=label('TextLabel','Text',banner,30,UI.Font.Title);bannerText.Size=UDim2.new(1,-24,1,-8);bannerText.Position=UDim2.fromOffset(12,4);bannerText.Text='Customize your Character';UI.fit(bannerText,16,30)
-- Preview stage on the left: transparent viewport so the character stands over the dimmed world.
local stage=Instance.new('Frame');stage.Name='PreviewStage';stage.BackgroundTransparency=1;stage.Visible=false;stage.Parent=gui
local floorGlow=Instance.new('Frame');floorGlow.Name='FloorGlow';floorGlow.AnchorPoint=Vector2.new(.5,.5);floorGlow.BackgroundColor3=Color3.fromRGB(150,120,255);floorGlow.BorderSizePixel=0;floorGlow.Parent=stage
UI.corner(floorGlow,UDim.new(1,0))
local glowFade=Instance.new('UIGradient');glowFade.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.55),NumberSequenceKeypoint.new(1,1)});glowFade.Parent=floorGlow
-- Main panel.
local panel,plate=UI.plate(gui,'Picker',22);panel.AnchorPoint=Vector2.new(1,0);panel.Visible=false
-- Controller focus never leaves the panel (no jumping out to HUD buttons at the edges).
panel.SelectionGroup=true
panel.SelectionBehaviorUp=Enum.SelectionBehavior.Stop;panel.SelectionBehaviorDown=Enum.SelectionBehavior.Stop
panel.SelectionBehaviorLeft=Enum.SelectionBehavior.Stop;panel.SelectionBehaviorRight=Enum.SelectionBehavior.Stop
local open=UI.closeButton(panel,'CloseAppearance',50);open.Position=UDim2.new(1,-30,0,30);open.Visible=false
local title=label('TextLabel','Title',panel,24,UI.Font.Title)
title.Text='Appearance';title.TextXAlignment=Enum.TextXAlignment.Left
local status=label('TextLabel','SaveStatus',panel,13,UI.Font.Body)
status.TextColor3=C.muted;status.TextXAlignment=Enum.TextXAlignment.Left;UI.fit(status,10,13)
local padHints=label('TextLabel','PadHints',panel,13,UI.Font.Bold)
padHints.TextColor3=C.gold;padHints.TextXAlignment=Enum.TextXAlignment.Right;padHints.Visible=false
padHints.Text='LB / RB  jump section     B  close';UI.fit(padHints,10,13)
local scroll=Instance.new('ScrollingFrame');scroll.Name='ColourControls';scroll.BackgroundTransparency=1
scroll.BorderSizePixel=0;scroll.CanvasSize=UDim2.new();scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.ScrollBarThickness=4;scroll.ScrollBarImageColor3=Color3.fromRGB(150,150,170);scroll.Parent=panel
local scrollList=Instance.new('UIListLayout');scrollList.Padding=UDim.new(0,10);scrollList.SortOrder=Enum.SortOrder.LayoutOrder;scrollList.Parent=scroll
local scrollPad=Instance.new('UIPadding');scrollPad.PaddingRight=UDim.new(0,10);scrollPad.PaddingBottom=UDim.new(0,8);scrollPad.Parent=scroll
local ownedFrame=Instance.new('Frame');ownedFrame.Name='AppearanceInventory';ownedFrame.BackgroundTransparency=1;ownedFrame.Parent=panel
local done=UI.button(panel,'DoneAppearance','DONE','buy')
-- Single-column panels (phones, narrow windows): Colours / Cosmetics tabs, each with the full body height,
-- instead of squeezing both lists into one column where the cosmetics list could not fit.
local TAB_H=36
local tabs=Instance.new('Frame');tabs.Name='SectionTabs';tabs.BackgroundTransparency=1;tabs.Visible=false;tabs.Parent=panel
local tabLayout=Instance.new('UIListLayout');tabLayout.FillDirection=Enum.FillDirection.Horizontal;tabLayout.Padding=UDim.new(0,8);tabLayout.SortOrder=Enum.SortOrder.LayoutOrder;tabLayout.Parent=tabs
local activeTab='Colours';local tabButtons={}
local function applyTab()
 local tabbed=tabs.Visible
 scroll.Visible=not tabbed or activeTab=='Colours'
 ownedFrame.Visible=not tabbed or activeTab=='Cosmetics'
 for name,b in tabButtons do b.BackgroundColor3=name==activeTab and UI.Color.green or UI.Color.grey end
end
for i,name in {'Colours','Cosmetics'}do
 local b=UI.button(tabs,'Tab_'..name,name:upper(),'muted');b.LayoutOrder=i;b.Size=UDim2.new(.5,-4,1,0);tabButtons[name]=b
 b.Activated:Connect(function()activeTab=name;applyTab()end)
end
-- Live, rotatable copy of the player's own character.
local TURN_MOUSE,TURN_TOUCH,TURN_STICK,STICK_DEADZONE=.012,.014,3.2,.18
local preview=Instance.new('ViewportFrame');preview.Name='CharacterPreview';preview.BackgroundTransparency=1;preview.BorderSizePixel=0;preview.Ambient=Color3.fromRGB(175,175,185);preview.LightColor=Color3.fromRGB(255,248,235);preview.LightDirection=Vector3.new(-.4,-1,.6);preview.Parent=stage
local previewWorld=Instance.new('WorldModel');previewWorld.Parent=preview
local previewCamera=Instance.new('Camera');previewCamera.FieldOfView=30;previewCamera.Parent=preview;preview.CurrentCamera=previewCamera
local previewHint=label('TextLabel','TurnHint',stage,14,UI.Font.Bold)
previewHint.AnchorPoint=Vector2.new(.5,1);previewHint.TextColor3=C.text;previewHint.BackgroundTransparency=.25;previewHint.BackgroundColor3=C.plate;previewHint.AutomaticSize=Enum.AutomaticSize.X
UI.corner(previewHint,UDim.new(1,0));local hintPad=Instance.new('UIPadding');hintPad.PaddingLeft=UDim.new(0,14);hintPad.PaddingRight=UDim.new(0,14);hintPad.Parent=previewHint
local controls={};local focusables={};local chosen=1;local blocks={}
local isOpen=false;local animationToken=0;local motion={}
local previewMode=false -- Studio-only PreviewAppearance hook: skip the in-van auto-close
local function parseHex(text)
    local h=text:gsub('#',''):upper()
    if #h~=6 or not h:match('^[0-9A-F]+$') then return nil end
    return {tonumber(h:sub(1,2),16),tonumber(h:sub(3,4),16),tonumber(h:sub(5,6),16)}
end
local function asHex(v) return string.format('#%02X%02X%02X',v[1],v[2],v[3]) end
local function sendSoon(region)
    pending[region]+=1
    local revision=pending[region]
    task.delay(.12,function()
        if pending[region]~=revision then return end
        local c=values[region]
        if region=='light'then
         if player:GetAttribute('Pass_flashlight_colors')~=true then return end
         local ev=RS:FindFirstChild('MonetizeEvent');if ev then ev:FireServer('setFlashlightColor',Color3.fromRGB(c[1],c[2],c[3]))end
         return
        end
        event:FireServer(region,c[1],c[2],c[3])
    end)
end
local function refresh()
    for _,region in REGIONS do
        local c=values[region];local ui=controls[region]
        ui.swatch.BackgroundColor3=Color3.fromRGB(c[1],c[2],c[3])
        if UIS:GetFocusedTextBox()~=ui.hex then ui.hex.Text=asHex(c) end
        for channel=1,3 do
            local row=ui.rows[channel]
            if UIS:GetFocusedTextBox()~=row.number then row.number.Text=tostring(c[channel]) end
            row.fill.Size=UDim2.new(c[channel]/255,0,1,0)
        end
        for _,chip in ui.presets do
            local on=chip.rgb[1]==c[1]and chip.rgb[2]==c[2]and chip.rgb[3]==c[3]
            chip.ring.Transparency=on and 0 or 1
        end
    end
    status.Text=player:GetAttribute('ColourSaveStatus') or 'Loading'
    if paintPreview then paintPreview() end
    local selected=GuiService.SelectedObject
    for _,row in focusables do row.marker.Visible=isOpen and selected==row.row end
end
local function change(region,channel,number)
    local nextValue=math.clamp(math.floor(number+.5),0,255)
    if values[region][channel]==nextValue then return end
    values[region][channel]=nextValue;refresh();sendSoon(region)
end
local function textBox(name,parent,size)
    local box=label('TextBox',name,parent,size,UI.Font.Bold);box.ClearTextOnFocus=false
    box.BackgroundTransparency=0;box.BackgroundColor3=C.pill;UI.corner(box,9);UI.stroke(box,Color3.fromRGB(70,70,86),1.2,0)
    return box
end
for index,region in REGIONS do
    local block=Instance.new('Frame');block.Name=region=='body' and 'Body' or region=='eyes' and 'Eyes' or 'Flashlight'
    block.BackgroundTransparency=1;block.LayoutOrder=index;block.Size=UDim2.new(1,0,0,240);block.Parent=scroll
    local inner=Instance.new('Frame');inner.Name='Section';inner.AnchorPoint=Vector2.new(.5,.5);inner.Position=UDim2.fromScale(.5,.5);inner.Size=UDim2.fromScale(1,1);inner.BackgroundColor3=C.card;inner.BackgroundTransparency=.15;inner.Parent=block
    UI.corner(inner,14);UI.stroke(inner,Color3.fromRGB(255,255,255),1,.88)
    local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=inner
    local heading=label('TextLabel','Heading',inner,20,UI.Font.Title)
    heading.Position=UDim2.fromOffset(12,8);heading.Text=HEADINGS[region];heading.TextXAlignment=Enum.TextXAlignment.Left;UI.fit(heading,13,20)
    local lockNote
    if region=='light'then
     -- Own line under the heading so the pass hint never clips or collides with the colour chip.
     lockNote=label('TextLabel','PassNote',inner,13,UI.Font.Bold);lockNote.TextColor3=C.gold;lockNote.TextXAlignment=Enum.TextXAlignment.Left
     lockNote.Text='Needs the Flashlight Colors pass (Robux Shop in the van)';UI.fit(lockNote,10,13)
     local function lock()lockNote.Visible=player:GetAttribute('Pass_flashlight_colors')~=true;if blocks[region]and blocks[region].relayout then blocks[region].relayout()end end
     player:GetAttributeChangedSignal('Pass_flashlight_colors'):Connect(lock);task.defer(lock)
    end
    local swatch=Instance.new('Frame');swatch.Name='Preview';swatch.BorderSizePixel=0;swatch.AnchorPoint=Vector2.new(1,0)
    swatch.Size=UDim2.fromOffset(30,30);swatch.Parent=inner
    UI.corner(swatch,UDim.new(1,0));UI.stroke(swatch,Color3.fromRGB(255,255,255),2,0)
    local hexBox=textBox('Hex',inner,14);hexBox.Selectable=false;hexBox.AnchorPoint=Vector2.new(1,0);hexBox.Size=UDim2.fromOffset(92,30);hexBox.PlaceholderText='#RRGGBB'
    controls[region]={swatch=swatch,hex=hexBox,rows={},presets={}}
    hexBox.FocusLost:Connect(function()
        local parsed=parseHex(hexBox.Text)
        if parsed then values[region]=parsed;sendSoon(region) end
        refresh()
    end)
    local grid=Instance.new('Frame');grid.Name='Presets';grid.BackgroundTransparency=1;grid.Parent=inner
    for i,rgb in PRESETS[region]do
        local chip=Instance.new('TextButton');chip.Name='Preset'..i;chip.Text='';chip.AutoButtonColor=false;chip.Selectable=true
        chip.BackgroundColor3=Color3.fromRGB(rgb[1],rgb[2],rgb[3]);chip.BorderSizePixel=0;chip.Parent=grid;UI.corner(chip,8)
        UI.stroke(chip,C.ink,1.2,.2);UI.selection(chip,10)
        local ring=Instance.new('Frame');ring.Name='Chosen';ring.BackgroundTransparency=1;ring.Size=UDim2.new(1,6,1,6);ring.Position=UDim2.fromOffset(-3,-3);ring.Parent=chip;UI.corner(ring,10)
        local ringStroke=UI.stroke(ring,Color3.fromRGB(255,255,255),2.5,0)
        local grow=Instance.new('UIScale');grow.Parent=chip
        chip.MouseEnter:Connect(function()TweenService:Create(grow,TweenInfo.new(.1),{Scale=1.1}):Play()end)
        chip.SelectionGained:Connect(function()TweenService:Create(grow,TweenInfo.new(.1),{Scale=1.12}):Play()end)
        chip.SelectionLost:Connect(function()TweenService:Create(grow,TweenInfo.new(.1),{Scale=1}):Play()end)
        chip.MouseLeave:Connect(function()TweenService:Create(grow,TweenInfo.new(.1),{Scale=1}):Play()end)
        chip.Activated:Connect(function()values[region]={rgb[1],rgb[2],rgb[3]};refresh();sendSoon(region)end)
        table.insert(controls[region].presets,{chip=chip,rgb=rgb,ring=ringStroke})
    end
    local rowFrames={}
    for channel,name in {'R','G','B'} do
        local row=Instance.new('Frame');row.Name=name..'Channel'
        row.BackgroundTransparency=1;row.Selectable=true;row.Parent=inner;UI.selection(row,12)
        row.BackgroundColor3=Color3.new(1,1,1);UI.corner(row,12)
        -- Controller: the selected slider row lights up so it is obvious which value the D-pad changes.
        row.SelectionGained:Connect(function()TweenService:Create(row,TweenInfo.new(.1),{BackgroundTransparency=.88}):Play()end)
        row.SelectionLost:Connect(function()TweenService:Create(row,TweenInfo.new(.1),{BackgroundTransparency=1}):Play()end)
        local marker=Instance.new('Frame');marker.Name='GamepadFocus'
        marker.BorderSizePixel=0;marker.BackgroundColor3=Color3.fromRGB(255,255,255)
        marker.Position=UDim2.fromOffset(0,6);marker.Size=UDim2.new(0,3,1,-12)
        marker.Visible=false;marker.Parent=row;UI.corner(marker,2)
        local channelLabel=label('TextLabel','Channel',row,15,UI.Font.Title)
        channelLabel.Position=UDim2.fromOffset(8,0);channelLabel.Size=UDim2.new(0,16,1,0)
        channelLabel.Text=name
        local track=Instance.new('TextButton');track.Name='Track';track.Text='';track.AutoButtonColor=false
        track.BorderSizePixel=0;track.BackgroundColor3=Color3.fromRGB(58,58,70)
        track.AnchorPoint=Vector2.new(0,.5);track.Position=UDim2.new(0,30,.5,0);track.Parent=row;UI.corner(track,UDim.new(1,0))
        local fill=Instance.new('Frame');fill.Name='Fill';fill.BorderSizePixel=0
        fill.BackgroundColor3=channel==1 and Color3.fromRGB(240,84,96) or channel==2 and Color3.fromRGB(70,214,120) or Color3.fromRGB(84,150,246)
        fill.Size=UDim2.fromScale(0,1);fill.Parent=track;UI.corner(fill,UDim.new(1,0))
        local number=textBox('Value',row,14);number.AnchorPoint=Vector2.new(1,.5)
        local minus=UI.button(row,'Minus','−','muted');minus.AnchorPoint=Vector2.new(1,.5)
        local plus=UI.button(row,'Plus','+','muted');plus.AnchorPoint=Vector2.new(1,.5)
        -- One controller stop per slider: the row. Its +/-, value box and track stay mouse/touch controls.
        minus.Selectable=false;plus.Selectable=false;number.Selectable=false;track.Selectable=false
        local function fromPointer(x)
            change(region,channel,(x-track.AbsolutePosition.X)/track.AbsoluteSize.X*255)
        end
        track.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                fromPointer(input.Position.X)
            end
        end)
        minus.Activated:Connect(function() change(region,channel,values[region][channel]-8) end)
        plus.Activated:Connect(function() change(region,channel,values[region][channel]+8) end)
        number.FocusLost:Connect(function()
            local n=tonumber(number.Text)
            if n and n==n then change(region,channel,n) end
            refresh()
        end)
        controls[region].rows[channel]={number=number,fill=fill,marker=marker}
        table.insert(focusables,{region=region,channel=channel,marker=marker,row=row})
        table.insert(rowFrames,{row=row,track=track,number=number,minus=minus,plus=plus})
    end
    -- Positions everything inside the section for the current width; returns the section height.
    local function relayout()
        local w=block.AbsoluteSize.X;if w<=0 then return end
        local pad=12;local inner_w=w-pad*2
        swatch.Position=UDim2.new(1,-pad,0,8);hexBox.Position=UDim2.new(1,-(pad+40),0,8)
        heading.Size=UDim2.new(1,-(pad+150),0,30)
        local y=44
        if lockNote and lockNote.Visible then lockNote.Position=UDim2.fromOffset(pad,y-4);lockNote.Size=UDim2.new(1,-pad*2,0,18);y+=20 end
        local size=math.min(SWATCH_MAX,math.floor((inner_w-(SWATCH_COLS-1)*SWATCH_GAP)/SWATCH_COLS))
        local rows=math.ceil(#PRESETS[region]/SWATCH_COLS)
        grid.Position=UDim2.fromOffset(pad,y);grid.Size=UDim2.new(1,-pad*2,0,rows*size+(rows-1)*SWATCH_GAP)
        for i,chip in controls[region].presets do
            local c=(i-1)%SWATCH_COLS;local r=math.floor((i-1)/SWATCH_COLS)
            chip.chip.Position=UDim2.fromOffset(c*(size+SWATCH_GAP),r*(size+SWATCH_GAP));chip.chip.Size=UDim2.fromOffset(size,size)
        end
        y+=rows*size+(rows-1)*SWATCH_GAP+10
        for i,parts in rowFrames do
            parts.row.Position=UDim2.fromOffset(pad-8,y+(i-1)*SLIDER_H);parts.row.Size=UDim2.new(1,-(pad*2-8),0,SLIDER_H)
            parts.plus.Position=UDim2.new(1,0,.5,0);parts.plus.Size=UDim2.fromOffset(34,30)
            parts.minus.Position=UDim2.new(1,-40,.5,0);parts.minus.Size=UDim2.fromOffset(34,30)
            parts.number.Position=UDim2.new(1,-80,.5,0);parts.number.Size=UDim2.fromOffset(44,30)
            parts.track.Size=UDim2.new(1,-(30+134),0,14)
        end
        y+=3*SLIDER_H+8
        block.Size=UDim2.new(1,0,0,y)
        return y
    end
    blocks[region]={block=block,inner=inner,pop=pop,relayout=relayout}
end
local help=label('TextLabel','GamepadHelp',scroll,13,UI.Font.Body)
help.LayoutOrder=99;help.Size=UDim2.new(1,0,0,40);help.TextWrapped=true;help.TextColor3=C.muted;UI.fit(help,10,13)
help.Text='PAD: ↑↓ channel   ←→ ±16   A/X ±1';help.TextXAlignment=Enum.TextXAlignment.Left
local function received(region,attribute)
    local c=parseHex(player:GetAttribute(attribute) or '')
    if c then values[region]=c;refresh() end
end
player:GetAttributeChangedSignal('BodyColourHex'):Connect(function() received('body','BodyColourHex') end)
player:GetAttributeChangedSignal('EyeColourHex'):Connect(function() received('eyes','EyeColourHex') end)
player:GetAttributeChangedSignal('ColourSaveStatus'):Connect(refresh)
local function receivedLight()
    local c=player:GetAttribute('FlashlightColor')
    if typeof(c)=='Color3'then values.light={math.round(c.R*255),math.round(c.G*255),math.round(c.B*255)};refresh()end
end
player:GetAttributeChangedSignal('FlashlightColor'):Connect(receivedLight);task.defer(receivedLight)
local lobbyOpen=false -- opened from the 3D lobby (menu icon or cosmetics stand) instead of the van
local function inLobby()
 local state=RS:FindFirstChild('LobbyState');local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
 return state~=nil and(state:GetAttribute('Mode')=='Menu'or player:GetAttribute('ReturnedToLobby')==true)and player:GetAttribute('MissionActive')~=true and h~=nil and h.Health>0
end
local function inVan()
 if lobbyOpen then return inLobby() end
 local camp=workspace:FindFirstChild('RecoveryCamp');local van=camp and camp:FindFirstChild('AnomalyRecoveryVan');local floor=van and van:FindFirstChild('Floor');local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if player:GetAttribute('MissionActive')~=true or player:GetAttribute('RoundDead')or not root or not floor then return false end
 local q=floor.CFrame:PointToObjectSpace(root.Position);return math.abs(q.X)<11 and q.Y>0 and q.Y<12 and q.Z>-24.5 and q.Z<16
end
local panelTarget=UDim2.new(1,-EDGE,0,0)
local function layout()
 local uiScale=phoneScale();rootScale.Scale=uiScale;root.Size=UDim2.fromScale(1/uiScale,1/uiScale)
 for _,c in gui:GetChildren()do if c~=root and c:IsA('GuiObject')and c.Name~='Backdrop'then c.Parent=root end end
 local v=gui.AbsoluteSize/uiScale
 local compact=v.Y<430
 local phone=uiScale<1 -- phones drop the title banner so the lists get the height
 local bannerH=phone and 0 or compact and 40 or BANNER_H
 local bannerW=math.min(compact and 360 or 520,v.X-2*EDGE-120)
 banner.Size=UDim2.fromOffset(bannerW,bannerH);banner.Position=UDim2.new(.5,0,0,BANNER_TOP)
 banner.Visible=not phone and banner.Visible
 local top=phone and EDGE or BANNER_TOP+bannerH+(compact and 6 or PANEL_TOP_GAP)
 local stacked=v.X<640 -- narrow screens: preview moves inside the panel
 local pw=stacked and v.X-2*EDGE or math.clamp(math.floor(v.X*PANEL_SHARE),PANEL_MIN_W,math.min(PANEL_MAX_W,v.X-STAGE_MIN_W-3*EDGE))
 local ph=v.Y-top-EDGE
 panelTarget=UDim2.new(1,-EDGE,0,top)
 panel.Size=UDim2.fromOffset(pw,ph)
 if isOpen and not motion.sliding then panel.Position=panelTarget end
 local pad=16
 title.Position=UDim2.fromOffset(pad,compact and 10 or 14);title.Size=UDim2.new(1,-(pad+80),0,compact and 24 or 28);title.TextSize=compact and 20 or 24
 status.Position=UDim2.fromOffset(pad,compact and 34 or 44);status.Size=UDim2.new(.4,-pad,0,18)
 padHints.Position=UDim2.new(.4,0,0,compact and 34 or 44);padHints.Size=UDim2.new(.6,-(pad+64),0,18)
 local contentTop=compact and 58 or 70
 local doneH=compact and 38 or 46
 done.Size=UDim2.new(1,-pad*2,0,doneH);done.Position=UDim2.new(0,pad,1,-(doneH+pad*.75))
 local contentH=ph-contentTop-doneH-pad*1.5
 local innerW=pw-pad*2
 -- Stage: free space left of the panel, or a strip at the top of a stacked panel.
 stage.Parent=stacked and panel or root
 local stageH=0
 if stacked then
  stageH=math.floor(contentH*.32)
  stage.AnchorPoint=Vector2.zero;stage.Position=UDim2.fromOffset(pad,contentTop);stage.Size=UDim2.fromOffset(innerW,stageH)
 else
  local stageW=v.X-pw-3*EDGE
  stage.AnchorPoint=Vector2.zero;stage.Position=UDim2.fromOffset(EDGE,top);stage.Size=UDim2.fromOffset(stageW,ph)
 end
 preview.Size=UDim2.new(1,0,1,-30);preview.Position=UDim2.new()
 floorGlow.Position=UDim2.new(.5,0,1,-46);floorGlow.Size=UDim2.new(.36,0,0,22);floorGlow.BackgroundTransparency=.35
 previewHint.Position=UDim2.new(.5,0,1,0);previewHint.Size=UDim2.fromOffset(0,26)
 local bodyTop=contentTop+(stacked and stageH+8 or 0)
 local bodyH=contentH-(stacked and stageH+8 or 0)
 local two=not stacked and pw>=TWO_COLUMN_W
 tabs.Visible=not two
 if two then
  local colW=math.min(COLOUR_COL_W+40,math.floor(innerW*.55))
  scroll.Position=UDim2.fromOffset(pad,bodyTop);scroll.Size=UDim2.fromOffset(colW,bodyH)
  ownedFrame.Position=UDim2.fromOffset(pad+colW+14,bodyTop);ownedFrame.Size=UDim2.fromOffset(innerW-colW-14,bodyH)
 else
  tabs.Position=UDim2.fromOffset(pad,bodyTop);tabs.Size=UDim2.fromOffset(innerW,TAB_H)
  local listTop=bodyTop+TAB_H+8;local listH=bodyH-TAB_H-8
  scroll.Position=UDim2.fromOffset(pad,listTop);scroll.Size=UDim2.fromOffset(innerW,listH)
  ownedFrame.Position=UDim2.fromOffset(pad,listTop);ownedFrame.Size=UDim2.fromOffset(innerW,listH)
 end
 applyTab()
 for _,region in REGIONS do blocks[region].relayout()end
 open.Size=UDim2.fromOffset(compact and 44 or 50,compact and 44 or 50);open.Position=UDim2.new(1,-30,0,30);open.ZIndex=20
 local device=InputHints.Get();local pad_=device=='pad';local touch=device=='touch'
 previewHint.Text=pad_ and 'Right stick: turn'or touch and 'Drag to turn'or 'Drag or hold right click: turn'
 padHints.Visible=pad_ and true or false
 help.Text=pad_ and 'D-pad: move · A: pick a colour or cosmetic\nOn a slider: ←/→ adjust (hold for fast) · A +1 · X −1 · LB/RB: jump section · B: close'or touch and 'Tap a colour or drag the sliders.\nTap a cosmetic to equip; tap DONE or the red X to leave.'or 'Click a colour, drag sliders or enter RGB / hex.\nClick a cosmetic to equip; Esc, DONE or the red X closes.'
end
local popOwned=false
drawOwned=function()
 local pop=popOwned;popOwned=false
 Appearance.Draw(ownedFrame,progress,function(id,slot)
  request('appearanceEquip',{offer=id,slot=slot},function(ok,data)
   if ok then progress=data.progress;drawOwned();status.Text=data.message else status.Text=tostring(data)end
  end)
 end,{theme='neon',heading='COSMETICS',headingColor=C.text,pop=pop,popDelay=ROWS_START+.12})
end
local rebuildPreview
local selectStart,usingPad -- controller helpers, defined with the controller bindings below
local function cancelMotion()for _,t in motion do if typeof(t)=='Instance'then t:Cancel()end end;table.clear(motion)end
local function play(object,info,props)local t=TweenService:Create(object,info,props);table.insert(motion,t);t:Play();return t end
local function setOpen(value)
 local wasOpen=isOpen
 if wasOpen==value then
  if value then refresh();layout()end
  return
 end
 isOpen=value;open.Modal=value;player:SetAttribute('AppearanceOpen',value)
 if not value then lobbyOpen=false end
 animationToken+=1;local token=animationToken
 cancelMotion()
 if wasOpen and not value then CameraGuard.Mute(.4)end
 if value then
  UI.FocusAcquire('Appearance',gui);activeTab='Colours'
  panel.Visible=true;banner.Visible=true;stage.Visible=true;open.Visible=true
  layout()
  rebuildPreview()
  UIS.MouseBehavior=Enum.MouseBehavior.Default;popOwned=true;drawOwned()
  if usingPad()then task.defer(selectStart)end
  -- Plate slides in from the right; banner drops in; colour sections pop one after another.
  motion.sliding=true
  local slide=UI.slideIn(panel,panelTarget,SLIDE_IN);table.insert(motion,slide)
  slide.Completed:Connect(function()if animationToken==token then motion.sliding=nil;panel.Position=panelTarget end end)
  banner.Position=UDim2.new(.5,0,0,-80);play(banner,TweenInfo.new(.32,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,BANNER_TOP)})
  preview.ImageTransparency=1;play(preview,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,0,false,.1),{ImageTransparency=0})
  for i,region in REGIONS do
   local b=blocks[region];b.pop.Scale=0
   play(b.pop,TweenInfo.new(.26,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,false,ROWS_START+(i-1)*ROW_STAGGER),{Scale=1})
  end
  table.insert(motion,UI.showBackdrop(backdrop,true))
 else
  UI.FocusRelease('Appearance');previewMode=false
  table.insert(motion,UI.slideOut(panel,SLIDE_OUT))
  play(banner,TweenInfo.new(SLIDE_OUT,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-80)})
  play(preview,TweenInfo.new(SLIDE_OUT),{ImageTransparency=1})
  table.insert(motion,UI.showBackdrop(backdrop,false))
  task.delay(SLIDE_OUT+.02,function()if animationToken==token then panel.Visible=false;banner.Visible=false;stage.Visible=false;open.Visible=false end end)
 end
 if not value and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui)then GuiService.SelectedObject=nil end
 refresh();layout()
end
local function toggle()
 if isOpen then setOpen(false);return end
 if not inVan()then return end
 request('vanAppearance',{},function(ok,data)
  if not ok or not inVan()then return end;progress=data.progress;setOpen(true)
 end)
end
lobby.OnClientEvent:Connect(function(action,data)
 if action=='response'and responses[data.id]then local callback=responses[data.id];responses[data.id]=nil;callback(data.ok,data.ok and data.data or data.error)
 elseif action=='progress'then progress=data;if isOpen then drawOwned()end end
end)
local openLobby=Instance.new('BindableEvent');openLobby.Name='OpenLobbyAppearance';openLobby.Parent=gui
openLobby.Event:Connect(function()
 if isOpen or not inLobby()then return end
 lobbyOpen=true
 request('vanAppearance',{},function(ok,data)
  if not ok or not lobbyOpen or not inLobby()then lobbyOpen=false;return end;progress=data.progress;setOpen(true)
 end)
end)
game:GetService('ProximityPromptService').PromptTriggered:Connect(function(prompt,who)if prompt.Name=='VanAppearancePrompt'and(not who or who==player)and not isOpen then toggle()end end)
open.Activated:Connect(function()if isOpen then setOpen(false)end end)
done.Activated:Connect(function()if isOpen then setOpen(false)end end)
player:GetAttributeChangedSignal('VanShopOpen'):Connect(function()if player:GetAttribute('VanShopOpen')and isOpen then setOpen(false)end end)
-- Controller ------------------------------------------------------------------------------------------
-- D-pad moves between every control (native selection); A picks. On a slider row ←/→ change the value
-- (hold to repeat), A/X fine-tune ±1. LB/RB jump Body → Eyes → Flashlight → Cosmetics → DONE. B closes.
local PAD_STEP,PAD_REPEAT_DELAY,PAD_REPEAT_EVERY,PAD_FINE=4,.3,.04,1
local rowLookup={};for _,f in focusables do rowLookup[f.row]=f end
local function sectionTargets()
 local list={}
 for _,region in REGIONS do local chips=controls[region].presets;if chips[1]then table.insert(list,{tab='Colours',region=region,object=chips[1].chip})end end
 local owned=ownedFrame:FindFirstChild('OwnedCosmetics')
 local cards=owned and owned:FindFirstChild('List')
 local first
 if cards then for _,b in cards:GetChildren()do if b:IsA('GuiButton')and(not first or b.LayoutOrder<first.LayoutOrder)then first=b end end end
 if not first and owned then local filters=owned:FindFirstChild('Filters');first=filters and filters:FindFirstChild('Filter_All')end
 if first then table.insert(list,{tab='Cosmetics',object=first})end
 table.insert(list,{object=done})
 return list
end
local function sectionOf(object,list)
 if not object then return 0 end
 for i,target in list do
  if target.region and object:IsDescendantOf(blocks[target.region].block)then return i end
  if target.tab=='Cosmetics'and object:IsDescendantOf(ownedFrame)then return i end
  if target.object==object then return i end
 end
 return 0
end
local function focus(target)
 if target.tab and tabs.Visible and activeTab~=target.tab then activeTab=target.tab;applyTab()end
 GuiService.SelectedObject=target.object;UI.SelectWhenReady(target.object)
end
selectStart=function()
 if not isOpen then return end
 -- Start on the preset that matches the current body colour, else the first one.
 local c=values.body;local pick=controls.body.presets[1]
 for _,chip in controls.body.presets do if chip.rgb[1]==c[1]and chip.rgb[2]==c[2]and chip.rgb[3]==c[3]then pick=chip end end
 focus({tab='Colours',object=pick.chip})
end
usingPad=function()
 return InputHints.Get()=='pad'
end
CAS:BindActionAtPriority('AppearanceSections',function(_,state,input)
 if not isOpen then return Enum.ContextActionResult.Pass end
 if state==Enum.UserInputState.Begin then
  if input.KeyCode==Enum.KeyCode.ButtonB then setOpen(false)
  else
   local list=sectionTargets()
   local at=sectionOf(GuiService.SelectedObject,list)
   local step=input.KeyCode==Enum.KeyCode.ButtonR1 and 1 or -1
   local nextIndex=at==0 and 1 or (at-1+step)%#list+1
   focus(list[nextIndex])
  end
 end
 return Enum.ContextActionResult.Sink
end,false,6500,Enum.KeyCode.ButtonB,Enum.KeyCode.ButtonR1,Enum.KeyCode.ButtonL1)
local holdToken=0
CAS:BindActionAtPriority('CharacterColourNavigation',function(_,state,input)
 local row=isOpen and rowLookup[GuiService.SelectedObject]
 if not row then return Enum.ContextActionResult.Pass end -- everywhere else the D-pad and A behave natively
 local key=input.KeyCode
 if state==Enum.UserInputState.Begin then
  if key==Enum.KeyCode.ButtonA or key==Enum.KeyCode.ButtonX then
   change(row.region,row.channel,values[row.region][row.channel]+(key==Enum.KeyCode.ButtonA and PAD_FINE or -PAD_FINE))
  else
   local dir=key==Enum.KeyCode.DPadRight and 1 or -1
   holdToken+=1;local token=holdToken
   change(row.region,row.channel,values[row.region][row.channel]+dir*PAD_STEP)
   task.delay(PAD_REPEAT_DELAY,function()
    while holdToken==token and isOpen and rowLookup[GuiService.SelectedObject]==row do
     change(row.region,row.channel,values[row.region][row.channel]+dir*PAD_STEP)
     task.wait(PAD_REPEAT_EVERY)
    end
   end)
  end
 elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then
  holdToken+=1
 end
 return Enum.ContextActionResult.Sink
end,false,3000,Enum.KeyCode.ButtonA,Enum.KeyCode.ButtonX,Enum.KeyCode.DPadLeft,Enum.KeyCode.DPadRight)
-- Keep whatever the controller selects scrolled into view, and show the slider marker.
local function reveal(object)
 local frame=object and object:FindFirstAncestorWhichIsA('ScrollingFrame')
 if not frame or not object:IsDescendantOf(panel)then return end
 local top=object.AbsolutePosition.Y-frame.AbsolutePosition.Y+frame.CanvasPosition.Y
 local view=frame.AbsoluteSize.Y;local y=frame.CanvasPosition.Y
 local section=object:FindFirstAncestor('Section')
 if section and object.Parent and object.Parent.Name=='Presets'then top=math.min(top,section.AbsolutePosition.Y-frame.AbsolutePosition.Y+frame.CanvasPosition.Y)end
 if top<y+8 then y=top-12 elseif top+object.AbsoluteSize.Y>y+view-8 then y=top+object.AbsoluteSize.Y-view+24 end
 frame.CanvasPosition=Vector2.new(frame.CanvasPosition.X,math.max(0,y))
end
GuiService:GetPropertyChangedSignal('SelectedObject'):Connect(function()
 if not isOpen then return end
 holdToken+=1
 reveal(GuiService.SelectedObject);refresh()
end)
InputHints.Changed:Connect(function()
 if isOpen and usingPad()and not(GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel))then selectStart()end
end)
UIS.InputBegan:Connect(function(input,processed)
    if processed or UIS:GetFocusedTextBox() then return end
    if input.KeyCode==Enum.KeyCode.Escape and isOpen then setOpen(false)end
end)
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(layout)
InputHints.Changed:Connect(layout)
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout)
local headParts={}
local function characterAdded(character)
    table.clear(headParts)
    local head=character:WaitForChild('Head',10)
    if not head then return end
    table.insert(headParts,head)
    for _,v in head:GetDescendants() do if v:IsA('BasePart') then table.insert(headParts,v) end end
end
player.CharacterAdded:Connect(characterAdded)
if player.Character then task.spawn(characterAdded,player.Character) end
RunService:BindToRenderStep('CharacterHeadVisibility',Enum.RenderPriority.Camera.Value+4,function()
    local camera=workspace.CurrentCamera
    if not camera then return end
    -- First person = the camera is at your own head (works for the game's scripted camera too, so no eye/lid bits show).
    local myHead=headParts[1];local firstPerson=myHead~=nil and myHead.Parent~=nil and(camera.CFrame.Position-myHead.Position).Magnitude<2.5
    for _,part in headParts do part.LocalTransparencyModifier=firstPerson and 1 or 0 end
    -- Your own worn hat sits on the camera in first person (a durag's tails filled the screen): hide it too.
    local worn=player.Character and player.Character:FindFirstChild('ProgressCosmetics')
    local hat=worn and worn:FindFirstChild('CosmeticHat')
    if hat then for _,part in hat:GetDescendants()do if part:IsA('BasePart')then part.LocalTransparencyModifier=firstPerson and 1 or 0 end end end
    if isOpen and not previewMode and not inVan()then setOpen(false)end
    if isOpen then UIS.MouseBehavior=Enum.MouseBehavior.Default end
end)
-- Character preview: a scriptless, anchored clone of the live character, repainted from the picker values
-- so slider changes show instantly; re-cloned when cosmetics or the character change.
local previewModel;local previewYaw=0;local previewBase=CFrame.new()
local livePairs={} -- {livePart, previewPart}: the preview mirrors the real character's pose every frame
local BODY_REGIONS={body=true,feet=true,stalks=true,rings=true}
paintPreview=function()
 if not previewModel then return end
 for _,x in previewModel:GetDescendants()do if x:IsA('BasePart')then
  local region=x:GetAttribute('ColourRegion');local v=region=='white'and values.eyes or BODY_REGIONS[region]and values.body
  if v then
   local shade=x:GetAttribute('ColourShade')or 1
   local c=Color3.new(math.clamp(v[1]/255*shade,0,1),math.clamp(v[2]/255*shade,0,1),math.clamp(v[3]/255*shade,0,1))
   x.Color=c;local surface=x:FindFirstChild('UniformBodySurface');if surface then pcall(function()surface.Color=c end)end
  end
 end end
end
local function poseCamera()
 if not previewModel then return end
 previewModel:PivotTo(previewBase*CFrame.Angles(0,previewYaw,0))
end
rebuildPreview=function()
 local character=player.Character
 if previewModel then previewModel:Destroy();previewModel=nil end
 if not character or not character:FindFirstChild('HumanoidRootPart')then return end
 local archivable=character.Archivable;character.Archivable=true
 local ok,copy=pcall(function()return character:Clone()end)
 character.Archivable=archivable
 if not ok or not copy then return end
 -- Clone keeps descendant order, so live and copy lists line up part for part.
 table.clear(livePairs)
 -- Match parts by name path (plus index among same-named siblings), so non-archivable extras can't shift the pairing.
 local function key(x,top)
  local parts={}
  while x and x~=top do
   local n=0;for _,sib in x.Parent:GetChildren()do if sib.Name==x.Name then n+=1 end;if sib==x then break end end
   table.insert(parts,1,x.Name..'#'..n);x=x.Parent
  end
  return table.concat(parts,'/')
 end
 do
  local copies={};for _,x in copy:GetDescendants()do if x:IsA('BasePart')then copies[key(x,copy)]=x end end
  for _,x in character:GetDescendants()do if x:IsA('BasePart')then local twin=copies[key(x,character)];if twin then table.insert(livePairs,{x,twin})end end end
 end
 for _,x in copy:GetDescendants()do
  if x:IsA('LuaSourceContainer')or x:IsA('Sound')or x:IsA('Constraint')and not x:IsA('WeldConstraint')or x:IsA('BodyMover')or x:IsA('ProximityPrompt')or x:IsA('BillboardGui')then x:Destroy()
  elseif x:IsA('BasePart')then x.Anchored=true;x.CanCollide=false;x.CanQuery=false;x.CanTouch=false;x.LocalTransparencyModifier=0
  elseif x:IsA('Humanoid')then x.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
 end
 copy.PrimaryPart=copy:FindFirstChild('HumanoidRootPart');if not copy.PrimaryPart then copy:Destroy();return end
 copy.PrimaryPart.Transparency=1
 copy:PivotTo(CFrame.new());copy.Parent=previewWorld;previewModel=copy
 -- Frame the whole body from the front (root faces -Z), keeping the pivot at the root so it spins in place.
 local box,size=copy:GetBoundingBox()
 local height=math.max(size.Y,size.X*.9,1)
 local distance=height/2/math.tan(math.rad(previewCamera.FieldOfView/2))*(phoneScale()<1 and 1.45 or 1.12) -- phones: character set further back
 local centre=Vector3.new(0,box.Position.Y,0)
 previewBase=CFrame.new()
 previewCamera.CFrame=CFrame.lookAt(centre+Vector3.new(0,height*.06,-distance),centre)
 paintPreview();poseCamera()
end
-- Literally live: every frame, each preview part takes its live part's pose relative to the root (blinks, mouth,
-- arm sway, worn items moving), turned by the preview yaw. Colours still come from paintPreview so sliders stay instant.
-- Runs at the end of each frame (after CharacterMotionClient's blink/gaze/lid updates and joint solving),
-- so every preview part takes its pose and size from the same moment and the eyes never tear.
game:GetService('RunService').Heartbeat:Connect(function()
 if not isOpen or not previewModel or not previewModel.Parent then return end
 local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
 if not root then return end
 local inv=root.CFrame:Inverse();local base=previewBase*CFrame.Angles(0,previewYaw,0)
 for _,pair in livePairs do
  local live,copy=pair[1],pair[2]
  if live.Parent and copy.Parent then
   copy.CFrame=base*(inv*live.CFrame)
   -- Blinks squash the eyeball, pupil and lid by resizing them; mirror sizes too or the eyes look broken.
   if copy.Size~=live.Size then copy.Size=live.Size end
   if copy~=previewModel.PrimaryPart then copy.Transparency=live.Transparency end
   if not(live:GetAttribute('ColourRegion'))then copy.Color=live.Color end
  end
 end
end)
local previewDirty=false
local function markDirty(x)
 -- Footstep/voice audio attachments come and go constantly; only visible changes need a re-clone.
 if x and not(x:IsA('BasePart')or x:IsA('Model')or x:IsA('Accessory')or x:IsA('Decal')or x:IsA('SurfaceAppearance')or x:IsA('Clothing')or x:IsA('SpecialMesh'))then return end
 if previewDirty then return end;previewDirty=true
 task.delay(.05,function()previewDirty=false;if isOpen then rebuildPreview()end end)
end
local characterWatch={}
local function watchCharacter(character)
 for _,c in characterWatch do c:Disconnect()end;table.clear(characterWatch)
 table.insert(characterWatch,character.DescendantAdded:Connect(markDirty))
 table.insert(characterWatch,character.DescendantRemoving:Connect(markDirty))
 markDirty()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character)end
-- Turning: hold right mouse anywhere, drag on the preview (mouse or touch), or the right stick.
local mouseTurning=false;local dragInput;local lastMouseX
-- Input moves a target; the preview eases toward it once per frame (raw mouse events arrive unevenly).
local targetYaw=previewYaw
local TURN_SMOOTHING=16
preview.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragInput=input;lastMouseX=input.Position.X end
end)
UIS.InputBegan:Connect(function(input)
 if isOpen and input.UserInputType==Enum.UserInputType.MouseButton2 then mouseTurning=true;lastMouseX=UIS:GetMouseLocation().X end
end)
UIS.InputChanged:Connect(function(input)
 if not isOpen then return end
 if input.UserInputType==Enum.UserInputType.MouseMovement and(mouseTurning or dragInput and dragInput.UserInputType==Enum.UserInputType.MouseButton1)then
  -- With a free cursor MouseMovement.Delta can be zero; use actual pointer displacement.
  local x=input.Position.X
  local dx=lastMouseX and x-lastMouseX or 0;lastMouseX=x
  targetYaw+=dx*TURN_MOUSE
 elseif input.UserInputType==Enum.UserInputType.Touch and dragInput==input then
  targetYaw+=input.Delta.X*TURN_TOUCH
 end
end)
UIS.InputEnded:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton2 then mouseTurning=false end
 if dragInput and(input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 and dragInput.UserInputType==Enum.UserInputType.MouseButton1)then dragInput=nil end
end)
RunService.RenderStepped:Connect(function(dt)
 if not isOpen then mouseTurning=false;dragInput=nil;lastMouseX=nil;return end
 -- Keep world-camera rotation muted while the panel is up so turning the preview never turns the player.
 CameraGuard.Mute(.4)
 for _,state in UIS:GetGamepadState(Enum.UserInputType.Gamepad1)do
  if state.KeyCode==Enum.KeyCode.Thumbstick2 and math.abs(state.Position.X)>STICK_DEADZONE then
   targetYaw+=state.Position.X*TURN_STICK*dt
  end
 end
 if math.abs(targetYaw-previewYaw)>.0005 then
  previewYaw+=(targetYaw-previewYaw)*(1-math.exp(-dt*TURN_SMOOTHING));poseCamera()
 end
end)
received('body','BodyColourHex');received('eyes','EyeColourHex')
refresh();layout()
if RunService:IsStudio()then local previewEvent=Instance.new('BindableEvent');previewEvent.Name='PreviewAppearance';previewEvent.Parent=script;previewEvent.Event:Connect(function()previewMode=true;progress.ready=true;setOpen(true)end)end
if RunService:IsStudio()then
 -- Studio-only: tests close the appearance screen through its real close path.
 local api=Instance.new('BindableFunction');api.Name='LobbyAppearanceTestApi';api.Parent=script
 api.OnInvoke=function(action)if action=='close'then local was=isOpen;if isOpen then setOpen(false)end;return was end;return false end
end
