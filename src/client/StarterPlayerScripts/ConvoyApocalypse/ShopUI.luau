--!strict
--[[
	Boost shop. Scrap buys a few runs of a bonus (double scrap, bigger tank...).
	Opens from the SHOP button or the B key while in the garage.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))

local player = Players.LocalPlayer

local ShopUI = {}
ShopUI._data = nil :: any
ShopUI._panel = nil :: Frame?
ShopUI._scrapLabel = nil :: TextLabel?
ShopUI._rows = {} :: { [string]: { owned: TextLabel, buy: TextButton } }

local function refresh()
	local data = ShopUI._data
	local scrap = if data then data.scrap or 0 else 0
	if ShopUI._scrapLabel then
		ShopUI._scrapLabel.Text = "Scrap  " .. tostring(scrap)
	end
	for _, item in Constants.SHOP_ITEMS do
		local row = ShopUI._rows[item.id]
		if row then
			local left = if data and data.boosts then data.boosts[item.id] or 0 else 0
			row.owned.Text = if left > 0 then string.format("Active: %d run%s left", left, if left == 1 then "" else "s") else "Not active"
			row.owned.TextColor3 = if left > 0 then UIUtil.Colors.Success else UIUtil.Colors.Muted
			local maxed = left >= Constants.SHOP_MAX_RUNS
			row.buy.Text = if maxed then "FULL" else string.format("%d  (+%d runs)", item.price, item.runs)
			row.buy.BackgroundColor3 = if maxed or scrap < item.price then UIUtil.Colors.PanelAlt else UIUtil.Colors.AccentDim
		end
	end
end

local function build()
	local gui = UIUtil.ScreenGui("Shop", player:WaitForChild("PlayerGui"))

	local toggle = UIUtil.Button({
		Name = "Toggle",
		Text = "SHOP  (B)",
		Size = UDim2.fromOffset(150, 36),
		Position = UDim2.new(0, 412, 1, -52),
		Parent = gui,
	})

	local rowHeight = 74
	local panel = UIUtil.Frame({
		Name = "Panel",
		Size = UDim2.fromOffset(470, 96 + rowHeight * #Constants.SHOP_ITEMS),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	ShopUI._panel = panel

	UIUtil.Text({
		Name = "Title",
		Text = "BOOST SHOP",
		Size = UDim2.new(0.5, -16, 0, 32),
		Position = UDim2.fromOffset(14, 10),
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Parent = panel,
	})
	ShopUI._scrapLabel = UIUtil.Text({
		Name = "Scrap",
		Text = "Scrap  0",
		Size = UDim2.new(0.5, -16, 0, 28),
		Position = UDim2.new(0.5, 0, 0, 12),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UIUtil.Colors.Scrap,
		Font = Enum.Font.GothamBold,
		Parent = panel,
	})
	UIUtil.Text({
		Name = "Hint",
		Text = "Boosts last a number of runs. They stack with your parts.",
		Size = UDim2.new(1, -28, 0, 18),
		Position = UDim2.fromOffset(14, 46),
		TextColor3 = UIUtil.Colors.Muted,
		Font = Enum.Font.Gotham,
		Parent = panel,
	})

	for index, item in Constants.SHOP_ITEMS do
		local top = 74 + (index - 1) * rowHeight
		local row = Instance.new("Frame")
		row.Name = item.id
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
			Text = item.name,
			Size = UDim2.new(0.6, -10, 0, 24),
			Position = UDim2.fromOffset(10, 6),
			Font = Enum.Font.GothamBold,
			Parent = row,
		})
		UIUtil.Text({
			Name = "Desc",
			Text = item.desc,
			Size = UDim2.new(0.6, -10, 0, 16),
			Position = UDim2.fromOffset(10, 30),
			TextColor3 = UIUtil.Colors.Muted,
			Font = Enum.Font.Gotham,
			Parent = row,
		})
		local owned = UIUtil.Text({
			Name = "Owned",
			Text = "Not active",
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
			Remotes.Event("BuyBoost"):FireServer(item.id)
		end)
		ShopUI._rows[item.id] = { owned = owned, buy = buy }
	end

	-- The pass shop sits in the same spot, so only one is open at a time.
	local function setOpen(open: boolean)
		panel.Visible = open
		if open then
			for _, other in { { "Passes", "Panel" }, { "Trade", "PlayersPanel" } } do
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
		if processed or input.KeyCode ~= Enum.KeyCode.B then
			return
		end
		if gui.Enabled then
			setOpen(not panel.Visible)
		end
	end)
	refresh()
end

function ShopUI.Init()
	build()
	Remotes.Event("DataUpdated").OnClientEvent:Connect(function(data)
		ShopUI._data = data
		refresh()
	end)
	task.spawn(function()
		local data = Remotes.Function("GetPlayerData"):InvokeServer()
		if data then
			ShopUI._data = data
			refresh()
		end
	end)
end

return ShopUI
