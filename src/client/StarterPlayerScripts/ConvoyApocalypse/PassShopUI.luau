--!strict
--[[
	Gamepass shop. Permanent Robux perks (2x scrap, 2x fuel...) listed in
	Constants.GAMEPASSES. Opens from the PASSES button or the P key in the garage.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))

local player = Players.LocalPlayer

local PassShopUI = {}
PassShopUI._data = nil :: any
PassShopUI._panel = nil :: Frame?
PassShopUI._rows = {} :: { [string]: { buy: TextButton, status: TextLabel } }
-- Robux price per pass id, filled in from Roblox so the button never lies.
PassShopUI._prices = {} :: { [string]: string }

local function priceText(pass: Constants.GamePass): string
	if pass.passId <= 0 then
		return if RunService:IsStudio() then "TEST (Studio)" else "COMING SOON"
	end
	local price = PassShopUI._prices[pass.id]
	return if price then price else "BUY"
end

local function refresh()
	local passes = if PassShopUI._data and PassShopUI._data.passes then PassShopUI._data.passes else {}
	for _, pass in Constants.GAMEPASSES do
		local row = PassShopUI._rows[pass.id]
		if row then
			local owned = passes[pass.id] == true
			row.status.Text = if owned then "Owned" else "Not owned"
			row.status.TextColor3 = if owned then UIUtil.Colors.Success else UIUtil.Colors.Muted
			row.buy.Text = if owned then "OWNED" else priceText(pass)
			row.buy.BackgroundColor3 = if owned then UIUtil.Colors.PanelAlt else UIUtil.Colors.AccentDim
		end
	end
end

local function loadPrices()
	for _, pass in Constants.GAMEPASSES do
		if pass.passId > 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(pass.passId, Enum.InfoType.GamePass)
				end)
				if ok and info then
					local robux = info.PriceInRobux
					PassShopUI._prices[pass.id] = if robux then "R$ " .. tostring(robux) else "OFF SALE"
					refresh()
				end
			end)
		end
	end
end

local function build()
	local gui = UIUtil.ScreenGui("Passes", player:WaitForChild("PlayerGui"))

	local toggle = UIUtil.Button({
		Name = "Toggle",
		Text = "PASSES  (P)",
		Size = UDim2.fromOffset(150, 36),
		Position = UDim2.new(0, 570, 1, -52),
		Parent = gui,
	})

	local rowHeight = 74
	local panel = UIUtil.Frame({
		Name = "Panel",
		Size = UDim2.fromOffset(470, 78 + rowHeight * #Constants.GAMEPASSES),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	PassShopUI._panel = panel

	UIUtil.Text({
		Name = "Title",
		Text = "GAMEPASSES",
		Size = UDim2.new(1, -28, 0, 32),
		Position = UDim2.fromOffset(14, 10),
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Parent = panel,
	})
	UIUtil.Text({
		Name = "Hint",
		Text = "Permanent perks. They stack with your parts.",
		Size = UDim2.new(1, -28, 0, 18),
		Position = UDim2.fromOffset(14, 44),
		TextColor3 = UIUtil.Colors.Muted,
		Font = Enum.Font.Gotham,
		Parent = panel,
	})

	for index, pass in Constants.GAMEPASSES do
		local top = 68 + (index - 1) * rowHeight
		local row = Instance.new("Frame")
		row.Name = pass.id
		row.BackgroundColor3 = UIUtil.Colors.PanelAlt
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -28, 0, rowHeight - 8)
		row.Position = UDim2.fromOffset(14, top)
		row.Parent = panel
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row

		UIUtil.Text({
			Name = "Name",
			Text = pass.name,
			Size = UDim2.new(0.6, -10, 0, 24),
			Position = UDim2.fromOffset(10, 6),
			Font = Enum.Font.GothamBold,
			Parent = row,
		})
		UIUtil.Text({
			Name = "Desc",
			Text = pass.desc,
			Size = UDim2.new(0.6, -10, 0, 16),
			Position = UDim2.fromOffset(10, 30),
			TextColor3 = UIUtil.Colors.Muted,
			Font = Enum.Font.Gotham,
			Parent = row,
		})
		local status = UIUtil.Text({
			Name = "Status",
			Text = "Not owned",
			Size = UDim2.new(0.6, -10, 0, 14),
			Position = UDim2.fromOffset(10, 48),
			TextColor3 = UIUtil.Colors.Muted,
			Font = Enum.Font.Gotham,
			Parent = row,
		})
		local buy = UIUtil.Button({
			Name = "Buy",
			Text = "",
			Size = UDim2.new(0.4, -18, 0, 40),
			Position = UDim2.new(0.6, 8, 0.5, -20),
			Parent = row,
		})
		buy.MouseButton1Click:Connect(function()
			Remotes.Event("BuyGamepass"):FireServer(pass.id)
		end)
		PassShopUI._rows[pass.id] = { buy = buy, status = status }
	end

	-- The boost shop sits in the same spot, so only one is open at a time.
	local function setOpen(open: boolean)
		panel.Visible = open
		if open then
			for _, other in { { "Shop", "Panel" }, { "Trade", "PlayersPanel" } } do
				local otherGui = player.PlayerGui:FindFirstChild(other[1])
				local otherPanel = if otherGui then otherGui:FindFirstChild(other[2]) else nil
				if otherPanel and otherPanel:IsA("GuiObject") then
					otherPanel.Visible = false
				end
			end
		end
	end
	toggle.MouseButton1Click:Connect(function()
		setOpen(not panel.Visible)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.P then
			return
		end
		if gui.Enabled then
			setOpen(not panel.Visible)
		end
	end)
	refresh()
end

function PassShopUI.Init()
	build()
	loadPrices()
	Remotes.Event("DataUpdated").OnClientEvent:Connect(function(data)
		PassShopUI._data = data
		refresh()
	end)
	task.spawn(function()
		local data = Remotes.Function("GetPlayerData"):InvokeServer()
		if data then
			PassShopUI._data = data
			refresh()
		end
	end)
end

return PassShopUI
