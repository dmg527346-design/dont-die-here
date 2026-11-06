-- Card chrome for the rank card (MainMenuClient) and the mastery card (QuestLogClient). Owner 2026-10-25: the glass
-- plates looked generic ("like AI"), so this is built like the game's own lobby buttons (MainMenuClient
-- lobbyButtonFinish: small corners, thick ink outline, hard drop shadow, faint wear) with ideas from outside pixel-UI
-- kits (Kombai "Pixel Hollow", the pixel_ui package): one solid raised colour, a label set into the top border, a thin
-- inner accent line and deterministic grit. No image assets: everything is UI shapes.
local M={}
M.FACE=Color3.fromRGB(34,28,42) -- the one raised-panel colour
M.INK=Color3.fromRGB(12,9,16)
M.SHADOW=Color3.fromRGB(8,6,11)
M.SOCKET=Color3.fromRGB(14,11,19)
M.RADIUS,M.OUTLINE,M.DROP=5,3,5 -- the lobby buttons' corner, outline and drop
M.SOCKET_INSET=7 -- px from the card's edges to the socket
M.TAG_HEIGHT=15
local TAG_MIN_CARD_HEIGHT=60 -- px: smaller cards hide the border tag

local function corner(o,r)local c=Instance.new('UICorner');c.CornerRadius=r;c.Parent=o;return c end
local function stroke(o,color,thickness,transparency)
 local s=Instance.new('UIStroke');s.Color=color;s.Thickness=thickness;s.Transparency=transparency or 0;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=o;return s
end

-- Builds the chrome inside `card` (a Frame or TextButton the caller owns) and returns
-- {face, socket, tag, SetAccent(color), Layout(height, textX) -> socket size}.
function M.Build(card,tagText)
 -- hard drop shadow first, so the face draws over it
 local shadow=Instance.new('Frame');shadow.Name='Drop';shadow.BorderSizePixel=0;shadow.BackgroundColor3=M.SHADOW
 shadow.Position=UDim2.fromOffset(0,M.DROP);shadow.Size=UDim2.fromScale(1,1);shadow.ZIndex=0;shadow.Parent=card
 corner(shadow,UDim.new(0,M.RADIUS));stroke(shadow,M.INK,M.OUTLINE)
 local face=Instance.new('Frame');face.Name='Plate';face.BorderSizePixel=0;face.BackgroundColor3=M.FACE
 face.Size=UDim2.fromScale(1,1);face.ZIndex=0;face.Parent=card
 corner(face,UDim.new(0,M.RADIUS));stroke(face,M.INK,M.OUTLINE)
 -- thin inner accent line just inside the ink outline (the rank's colour / the monster's tint)
 local inner=Instance.new('Frame');inner.Name='Inner';inner.BackgroundTransparency=1;inner.AnchorPoint=Vector2.new(.5,.5)
 inner.Position=UDim2.fromScale(.5,.5);inner.Size=UDim2.new(1,-6,1,-6);inner.ZIndex=0;inner.Parent=face
 corner(inner,UDim.new(0,M.RADIUS-2))
 local accentLine=stroke(inner,Color3.new(1,1,1),1.5,.5)
 -- a few faint scratches on the right half, the same on every screen
 for i=1,4 do
  local w=Instance.new('Frame');w.Name='Wear';w.BorderSizePixel=0;w.BackgroundColor3=Color3.new(1,1,1);w.BackgroundTransparency=.92
  w.AnchorPoint=Vector2.new(.5,.5);w.Position=UDim2.fromScale(.48+.11*i,.22+.15*((i*7)%5));w.Size=UDim2.fromOffset(7+(i*5)%9,1)
  w.Rotation=-25-(i*13)%30;w.ZIndex=0;w.Parent=face
 end
 -- round socket: ink outside, accent ring inside, drawn over the badge / portrait so its edge stays clean
 local socket=Instance.new('Frame');socket.Name='Socket';socket.AnchorPoint=Vector2.new(.5,.5);socket.BackgroundColor3=M.SOCKET
 socket.BorderSizePixel=0;socket.ZIndex=1;socket.Parent=card
 corner(socket,UDim.new(.5,0));stroke(socket,M.INK,M.OUTLINE)
 local ring=Instance.new('Frame');ring.Name='Ring';ring.BackgroundTransparency=1;ring.AnchorPoint=Vector2.new(.5,.5)
 ring.Position=UDim2.fromScale(.5,.5);ring.Size=UDim2.new(1,-4,1,-4);ring.ZIndex=5;ring.Parent=socket
 corner(ring,UDim.new(.5,0))
 local ringStroke=stroke(ring,Color3.new(1,1,1),2,0)
 -- label set into the top border
 local tag=Instance.new('TextLabel');tag.Name='Tag';tag.AutomaticSize=Enum.AutomaticSize.X;tag.Size=UDim2.fromOffset(0,M.TAG_HEIGHT)
 tag.AnchorPoint=Vector2.new(0,.5);tag.BackgroundColor3=Color3.new(1,1,1);tag.BorderSizePixel=0;tag.Font=Enum.Font.Arcade;tag.TextSize=12
 tag.TextColor3=M.INK;tag.Text=tagText;tag.ZIndex=6;tag.Parent=card
 corner(tag,UDim.new(0,3));stroke(tag,M.INK,2)
 local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,6);pad.PaddingRight=UDim.new(0,6);pad.Parent=tag

 local style={face=face,socket=socket,tag=tag}
 function style.SetAccent(color)accentLine.Color=color;ringStroke.Color=color;tag.BackgroundColor3=color end
 function style.Layout(height,textX)
  local size=height-M.SOCKET_INSET*2
  socket.Size=UDim2.fromOffset(size,size);socket.Position=UDim2.fromOffset(M.SOCKET_INSET+size/2,height/2)
  tag.Position=UDim2.fromOffset(textX,0)
  tag.Visible=height>=TAG_MIN_CARD_HEIGHT -- the compact phone card has no room above its name line
  return size
 end
 return style
end
return M
