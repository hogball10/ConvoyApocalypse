--!strict
--[[
	Styled GUI helpers — dark apocalypse theme with rust/neon accents.
]]

local UIUtil = {}

UIUtil.Colors = {
	Bg = Color3.fromRGB(12, 14, 18),
	Panel = Color3.fromRGB(18, 20, 26),
	PanelAlt = Color3.fromRGB(24, 28, 36),
	Stroke = Color3.fromRGB(255, 140, 50),
	Accent = Color3.fromRGB(255, 140, 50),
	AccentDim = Color3.fromRGB(180, 90, 30),
	Danger = Color3.fromRGB(200, 55, 45),
	Success = Color3.fromRGB(60, 170, 90),
	Text = Color3.fromRGB(235, 235, 240),
	Muted = Color3.fromRGB(150, 155, 165),
	Scrap = Color3.fromRGB(255, 200, 80),
}

local function stroke(parent: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or UIUtil.Colors.Stroke
	s.Thickness = thickness or 1.5
	s.Transparency = 0.25
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function pad(parent: GuiObject, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

function UIUtil.ScreenGui(name: string, parent: Instance): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	return gui
end

function UIUtil.Frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = props.BackgroundColor3 or UIUtil.Colors.Panel
	f.BackgroundTransparency = props.BackgroundTransparency or 0.08
	f.BorderSizePixel = 0
	f.Size = props.Size or UDim2.fromOffset(100, 100)
	f.Position = props.Position or UDim2.fromScale(0, 0)
	f.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	f.Name = props.Name or "Frame"
	f.ClipsDescendants = props.ClipsDescendants == true
	if props.Parent then
		f.Parent = props.Parent
	end
	if props.Visible ~= nil then
		f.Visible = props.Visible
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, props.Corner or 10)
	corner.Parent = f
	if props.Stroke ~= false then
		stroke(f, props.StrokeColor or UIUtil.Colors.Stroke, props.StrokeThickness or 1.4)
	end
	if props.Pad then
		pad(f, props.Pad)
	end
	return f
end

function UIUtil.Text(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = props.BackgroundTransparency or 1
	if props.BackgroundColor3 then
		t.BackgroundColor3 = props.BackgroundColor3
		t.BackgroundTransparency = props.BackgroundTransparency or 0.3
	end
	t.Font = props.Font or Enum.Font.GothamMedium
	t.Text = props.Text or ""
	t.TextColor3 = props.TextColor3 or UIUtil.Colors.Text
	t.TextScaled = props.TextScaled ~= false
	t.Size = props.Size or UDim2.fromScale(1, 1)
	t.Position = props.Position or UDim2.fromScale(0, 0)
	t.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	t.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	t.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	t.Name = props.Name or "Text"
	t.BorderSizePixel = 0
	if props.Parent then
		t.Parent = props.Parent
	end
	if props.Corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, props.Corner)
		c.Parent = t
	end
	return t
end

function UIUtil.Button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = props.BackgroundColor3 or UIUtil.Colors.AccentDim
	b.BackgroundTransparency = props.BackgroundTransparency or 0
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.Text = props.Text or "Button"
	b.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	b.TextScaled = true
	b.Size = props.Size or UDim2.fromOffset(120, 36)
	b.Position = props.Position or UDim2.fromScale(0, 0)
	b.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	b.Name = props.Name or "Button"
	if props.Parent then
		b.Parent = props.Parent
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, props.Corner or 8)
	corner.Parent = b
	stroke(b, props.StrokeColor or Color3.fromRGB(255, 180, 100), 1.2)
	return b
end

function UIUtil.Scroll(props: { [string]: any }): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.ScrollBarImageColor3 = UIUtil.Colors.Accent
	s.CanvasSize = UDim2.fromOffset(0, 0)
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.Size = props.Size or UDim2.fromScale(1, 1)
	s.Position = props.Position or UDim2.fromScale(0, 0)
	s.Name = props.Name or "Scroll"
	if props.Parent then
		s.Parent = props.Parent
	end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s
	local p = Instance.new("UIPadding")
	p.PaddingRight = UDim.new(0, 6)
	p.Parent = s
	return s
end

return UIUtil
