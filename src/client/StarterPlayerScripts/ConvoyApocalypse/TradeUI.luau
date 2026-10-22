--!strict
--[[
	Visiting and trading. A PLAYERS panel lists everyone on the server: VISIT
	takes you to their garage, and once you share one, TRADE asks them to swap.
	The other side gets an accept / decline popup; accepting opens the trade
	window where both put parts and scrap on the table and confirm.
	Opens from the PLAYERS button or the T key in the garage.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))

local player = Players.LocalPlayer

local TIER_RANK = { Scrap = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Relic = 7 }

local TradeUI = {}
TradeUI._data = nil :: any
-- Everyone in the garage I am standing in, by userId.
TradeUI._together = {} :: { [number]: boolean }
-- The open trade as the server last described it, and my side of it.
TradeUI._trade = nil :: any
TradeUI._counts = {} :: { [string]: number }
TradeUI._scrap = 0

local playersPanel: Frame? = nil
local playersList: ScrollingFrame? = nil
local requestPopup: Frame? = nil
local requestLabel: TextLabel? = nil
local requestFrom = 0
local requestToken = 0
local tradeWindow: Frame? = nil
local tradeTitle: TextLabel? = nil
local myList: ScrollingFrame? = nil
local theirList: ScrollingFrame? = nil
local myScrapBox: TextBox? = nil
local myScrapHave: TextLabel? = nil
local theirScrap: TextLabel? = nil
local theirStatus: TextLabel? = nil
local confirmButton: TextButton? = nil

local refreshPlayers: () -> ()
local renderTrade: () -> ()

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function makeLabel(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, font: Enum.Font, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	label.Parent = parent
	return label
end

-- ── Players panel ──────────────────────────────────────────────────────────

refreshPlayers = function()
	local list = playersList
	if not list then
		return
	end
	clearChildren(list)
	local order = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			order += 1
			local together = TradeUI._together[other.UserId] == true
			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.BackgroundColor3 = UIUtil.Colors.PanelAlt
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, 46)
			row.Parent = list
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = row
			makeLabel(row, other.DisplayName, UDim2.new(1, -130, 0, 22), UDim2.fromOffset(10, 4), UIUtil.Colors.Text, Enum.Font.GothamBold, 15)
			makeLabel(
				row,
				if together then "In your garage" else "@" .. other.Name,
				UDim2.new(1, -130, 0, 16),
				UDim2.fromOffset(10, 26),
				if together then UIUtil.Colors.Success else UIUtil.Colors.Muted,
				Enum.Font.Gotham,
				11
			)
			local button = UIUtil.Button({
				Name = "Action",
				Text = if together then "TRADE" else "VISIT",
				Size = UDim2.fromOffset(100, 32),
				Position = UDim2.new(1, -110, 0.5, -16),
				Parent = row,
			})
			button.MouseButton1Click:Connect(function()
				if TradeUI._together[other.UserId] then
					Remotes.Event("TradeRequest"):FireServer(other.UserId)
				else
					Remotes.Event("JoinGarage"):FireServer(other.UserId)
					task.delay(0.8, function()
						TradeUI.RefreshTogether()
					end)
				end
			end)
		end
	end
	if order == 0 then
		makeLabel(list, "Nobody else is here yet.", UDim2.new(1, 0, 0, 30), UDim2.new(), UIUtil.Colors.Muted, Enum.Font.Gotham, 14)
	end
end

-- Who shares my garage right now, then redraw the list.
function TradeUI.RefreshTogether()
	task.spawn(function()
		local ok, occupants = pcall(function()
			return Remotes.Function("GetGarageOccupants"):InvokeServer()
		end)
		local together = {}
		if ok and typeof(occupants) == "table" then
			for _, entry in occupants do
				together[entry.userId] = true
			end
		end
		TradeUI._together = together
		refreshPlayers()
	end)
end

-- ── Request popup ──────────────────────────────────────────────────────────

local function hideRequest()
	requestToken += 1
	if requestPopup then
		requestPopup.Visible = false
	end
end

local function showRequest(fromUserId: number, fromName: string)
	if not requestPopup or not requestLabel then
		return
	end
	requestFrom = fromUserId
	requestLabel.Text = fromName .. " wants to trade"
	requestPopup.Visible = true
	requestToken += 1
	local token = requestToken
	task.delay(Constants.TRADE_REQUEST_TIMEOUT, function()
		if token == requestToken then
			hideRequest()
		end
	end)
end

-- ── Trade window ───────────────────────────────────────────────────────────

local function sendOffer()
	local parts = {}
	local ids = {}
	for partId in TradeUI._counts do
		table.insert(ids, partId)
	end
	table.sort(ids)
	for _, partId in ids do
		for _ = 1, TradeUI._counts[partId] do
			table.insert(parts, partId)
		end
	end
	Remotes.Event("TradeUpdate"):FireServer(parts, TradeUI._scrap)
end

local function offerOf(userId: number): any
	local trade = TradeUI._trade
	return trade and trade.offers and trade.offers[tostring(userId)]
end

local function countParts(list: any): { [string]: number }
	local counts = {}
	if typeof(list) == "table" then
		for _, partId in list do
			counts[partId] = (counts[partId] or 0) + 1
		end
	end
	return counts
end

-- Sorted (best tier first) part ids from a counts table.
local function sortedIds(counts: { [string]: number }): { string }
	local ids = {}
	for partId in counts do
		table.insert(ids, partId)
	end
	table.sort(ids, function(a, b)
		local pa, pb = PartsCatalog.Get(a), PartsCatalog.Get(b)
		local ra, rb = if pa then TIER_RANK[pa.tier] or 0 else 0, if pb then TIER_RANK[pb.tier] or 0 else 0
		if ra ~= rb then
			return ra > rb
		end
		return a < b
	end)
	return ids
end

renderTrade = function()
	local window, trade = tradeWindow, TradeUI._trade
	if not window or not trade or not myList or not theirList then
		if window then
			window.Visible = false
		end
		return
	end
	window.Visible = true
	local otherId = if trade.a == player.UserId then trade.b else trade.a
	local other = Players:GetPlayerByUserId(otherId)
	if tradeTitle then
		tradeTitle.Text = "TRADE WITH " .. string.upper(if other then other.DisplayName else "?")
	end
	local mine, theirs = offerOf(player.UserId), offerOf(otherId)

	-- My side: every part I have free, with - / + to put copies on the table.
	clearChildren(myList)
	local free = {}
	local data = TradeUI._data
	if data and typeof(data.ownedParts) == "table" then
		for partId in data.ownedParts do
			local copies = PartsCatalog.FreeCount(data, partId)
			if copies > 0 then
				free[partId] = copies
			end
		end
	end
	local order = 0
	for _, partId in sortedIds(free) do
		local part = PartsCatalog.Get(partId)
		if part then
			order += 1
			local have = free[partId]
			local offered = math.min(TradeUI._counts[partId] or 0, have)
			local color = Constants.TIER_COLORS[part.tier] or UIUtil.Colors.Text
			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.BackgroundColor3 = UIUtil.Colors.PanelAlt
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, 38)
			row.Parent = myList
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = row
			local stripe = Instance.new("Frame")
			stripe.BackgroundColor3 = color
			stripe.BorderSizePixel = 0
			stripe.Size = UDim2.new(0, 4, 1, -8)
			stripe.Position = UDim2.fromOffset(4, 4)
			stripe.Parent = row
			makeLabel(row, part.name, UDim2.new(1, -118, 0, 20), UDim2.fromOffset(14, 2), color, Enum.Font.GothamBold, 13)
			makeLabel(row, part.tier .. "  ·  have " .. tostring(have), UDim2.new(1, -118, 0, 14), UDim2.fromOffset(14, 21), UIUtil.Colors.Muted, Enum.Font.Gotham, 10)

			local minus = UIUtil.Button({ Name = "Minus", Text = "-", Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -96, 0.5, -13), Parent = row })
			local count = makeLabel(row, tostring(offered), UDim2.fromOffset(28, 26), UDim2.new(1, -66, 0.5, -13), UIUtil.Colors.Scrap, Enum.Font.GothamBold, 15)
			count.TextXAlignment = Enum.TextXAlignment.Center
			local plus = UIUtil.Button({ Name = "Plus", Text = "+", Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -34, 0.5, -13), Parent = row })
			minus.MouseButton1Click:Connect(function()
				local now = TradeUI._counts[partId] or 0
				if now > 0 then
					TradeUI._counts[partId] = if now > 1 then now - 1 else nil
					sendOffer()
					renderTrade()
				end
			end)
			plus.MouseButton1Click:Connect(function()
				local now = TradeUI._counts[partId] or 0
				if now < have then
					TradeUI._counts[partId] = now + 1
					sendOffer()
					renderTrade()
				end
			end)
		end
	end
	if order == 0 then
		makeLabel(myList, "You have no free parts to trade. Parts on your car stay put.", UDim2.new(1, 0, 0, 40), UDim2.new(), UIUtil.Colors.Muted, Enum.Font.Gotham, 12).TextWrapped = true
	end

	if myScrapHave then
		myScrapHave.Text = "of " .. tostring(if data then data.scrap or 0 else 0)
	end
	if myScrapBox and not myScrapBox:IsFocused() then
		myScrapBox.Text = tostring(TradeUI._scrap)
	end

	-- Their side: read-only.
	clearChildren(theirList)
	local theirCounts = countParts(if theirs then theirs.parts else nil)
	local theirOrder = 0
	for _, partId in sortedIds(theirCounts) do
		local part = PartsCatalog.Get(partId)
		if part then
			theirOrder += 1
			local color = Constants.TIER_COLORS[part.tier] or UIUtil.Colors.Text
			local row = Instance.new("Frame")
			row.LayoutOrder = theirOrder
			row.BackgroundColor3 = UIUtil.Colors.PanelAlt
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, 38)
			row.Parent = theirList
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = row
			local stripe = Instance.new("Frame")
			stripe.BackgroundColor3 = color
			stripe.BorderSizePixel = 0
			stripe.Size = UDim2.new(0, 4, 1, -8)
			stripe.Position = UDim2.fromOffset(4, 4)
			stripe.Parent = row
			makeLabel(row, part.name, UDim2.new(1, -60, 0, 20), UDim2.fromOffset(14, 2), color, Enum.Font.GothamBold, 13)
			makeLabel(row, part.tier, UDim2.new(1, -60, 0, 14), UDim2.fromOffset(14, 21), UIUtil.Colors.Muted, Enum.Font.Gotham, 10)
			local count = makeLabel(row, "x" .. tostring(theirCounts[partId]), UDim2.fromOffset(44, 26), UDim2.new(1, -48, 0.5, -13), UIUtil.Colors.Scrap, Enum.Font.GothamBold, 15)
			count.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
	if theirOrder == 0 then
		makeLabel(theirList, "Nothing offered yet.", UDim2.new(1, 0, 0, 30), UDim2.new(), UIUtil.Colors.Muted, Enum.Font.Gotham, 13)
	end
	if theirScrap then
		theirScrap.Text = "Scrap  " .. tostring(if theirs then theirs.scrap or 0 else 0)
	end

	local theyConfirmed = theirs ~= nil and theirs.confirmed == true
	local iConfirmed = mine ~= nil and mine.confirmed == true
	if theirStatus then
		theirStatus.Text = if theyConfirmed then "They have confirmed" else "Waiting for them to confirm"
		theirStatus.TextColor3 = if theyConfirmed then UIUtil.Colors.Success else UIUtil.Colors.Muted
	end
	if confirmButton then
		confirmButton.Text = if iConfirmed then "CONFIRMED  (waiting)" else "CONFIRM TRADE"
		confirmButton.BackgroundColor3 = if iConfirmed then UIUtil.Colors.PanelAlt else UIUtil.Colors.Success
	end
end

-- The server is the record of my offer; copy it back so the window never lies.
local function adoptTrade(trade: any)
	TradeUI._trade = trade
	local mine = offerOf(player.UserId)
	TradeUI._counts = countParts(if mine then mine.parts else nil)
	TradeUI._scrap = if mine then mine.scrap or 0 else 0
	renderTrade()
end

local function closeTrade()
	TradeUI._trade = nil
	TradeUI._counts = {}
	TradeUI._scrap = 0
	if tradeWindow then
		tradeWindow.Visible = false
	end
end

-- ── Building ───────────────────────────────────────────────────────────────

local function build()
	local gui = UIUtil.ScreenGui("Trade", player:WaitForChild("PlayerGui"))
	gui.DisplayOrder = 5

	local toggle = UIUtil.Button({
		Name = "Toggle",
		Text = "PLAYERS  (T)",
		Size = UDim2.fromOffset(150, 36),
		Position = UDim2.new(0, 728, 1, -52),
		Parent = gui,
	})

	-- Players panel
	local panel = UIUtil.Frame({
		Name = "PlayersPanel",
		Size = UDim2.fromOffset(380, 330),
		-- Above the lever picker (which sits just over the button row).
		Position = UDim2.new(0, 728, 1, -540),
		Visible = false,
		Parent = gui,
	})
	playersPanel = panel
	UIUtil.Text({
		Name = "Title",
		Text = "PLAYERS",
		Size = UDim2.new(1, -28, 0, 30),
		Position = UDim2.fromOffset(14, 8),
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Parent = panel,
	})
	UIUtil.Text({
		Name = "Hint",
		Text = "VISIT a garage, then TRADE once you are in the same one.",
		Size = UDim2.new(1, -28, 0, 16),
		Position = UDim2.fromOffset(14, 38),
		TextColor3 = UIUtil.Colors.Muted,
		Font = Enum.Font.Gotham,
		Parent = panel,
	})
	playersList = UIUtil.Scroll({
		Name = "List",
		Size = UDim2.new(1, -24, 1, -70),
		Position = UDim2.fromOffset(12, 60),
		Parent = panel,
	})

	local function setOpen(open: boolean)
		panel.Visible = open
		if open then
			-- Same screen space as the shop panels, so only one is open at a time.
			for _, name in { "Shop", "Passes" } do
				local other = player.PlayerGui:FindFirstChild(name)
				local otherPanel = if other then other:FindFirstChild("Panel") else nil
				if otherPanel and otherPanel:IsA("GuiObject") then
					otherPanel.Visible = false
				end
			end
			TradeUI.RefreshTogether()
			refreshPlayers()
		end
	end
	toggle.MouseButton1Click:Connect(function()
		setOpen(not panel.Visible)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.T then
			return
		end
		if gui.Enabled then
			setOpen(not panel.Visible)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			if panel.Visible then
				TradeUI.RefreshTogether()
			end
		end
	end)
	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshPlayers)
	end)

	-- Incoming request popup
	local popup = UIUtil.Frame({
		Name = "Request",
		Size = UDim2.fromOffset(360, 92),
		Position = UDim2.new(0.5, 0, 0, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = gui,
	})
	requestPopup = popup
	requestLabel = UIUtil.Text({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		Parent = popup,
	})
	local accept = UIUtil.Button({
		Name = "Accept",
		Text = "ACCEPT",
		Size = UDim2.new(0.5, -18, 0, 36),
		Position = UDim2.new(0, 12, 1, -46),
		BackgroundColor3 = UIUtil.Colors.Success,
		Parent = popup,
	})
	local decline = UIUtil.Button({
		Name = "Decline",
		Text = "DECLINE",
		Size = UDim2.new(0.5, -18, 0, 36),
		Position = UDim2.new(0.5, 6, 1, -46),
		BackgroundColor3 = UIUtil.Colors.Danger,
		Parent = popup,
	})
	accept.MouseButton1Click:Connect(function()
		Remotes.Event("TradeRespond"):FireServer(requestFrom, true)
		hideRequest()
	end)
	decline.MouseButton1Click:Connect(function()
		Remotes.Event("TradeRespond"):FireServer(requestFrom, false)
		hideRequest()
	end)

	-- Trade window
	local window = UIUtil.Frame({
		Name = "Window",
		Size = UDim2.fromOffset(660, 440),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	tradeWindow = window
	tradeTitle = UIUtil.Text({
		Name = "Title",
		Text = "TRADE",
		Size = UDim2.new(1, -28, 0, 30),
		Position = UDim2.fromOffset(14, 8),
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Parent = window,
	})

	local function column(name: string, x: number): Frame
		local frame = UIUtil.Frame({
			Name = name,
			Size = UDim2.fromOffset(310, 320),
			Position = UDim2.fromOffset(x, 48),
			BackgroundColor3 = UIUtil.Colors.Bg,
			Parent = window,
		})
		return frame
	end

	local mineColumn = column("Mine", 14)
	UIUtil.Text({
		Text = "YOUR OFFER",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 6),
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Text,
		Parent = mineColumn,
	})
	makeLabel(mineColumn, "Scrap", UDim2.fromOffset(50, 28), UDim2.fromOffset(10, 34), UIUtil.Colors.Scrap, Enum.Font.GothamBold, 14)
	local box = Instance.new("TextBox")
	box.Name = "ScrapBox"
	box.Size = UDim2.fromOffset(110, 28)
	box.Position = UDim2.fromOffset(62, 34)
	box.BackgroundColor3 = UIUtil.Colors.PanelAlt
	box.BorderSizePixel = 0
	box.Font = Enum.Font.GothamBold
	box.TextSize = 14
	box.TextColor3 = UIUtil.Colors.Scrap
	box.PlaceholderText = "0"
	box.ClearTextOnFocus = false
	box.Text = "0"
	box.Parent = mineColumn
	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = box
	myScrapBox = box
	myScrapHave = makeLabel(mineColumn, "of 0", UDim2.fromOffset(110, 28), UDim2.fromOffset(180, 34), UIUtil.Colors.Muted, Enum.Font.Gotham, 12)
	box.FocusLost:Connect(function()
		local typed = tonumber(box.Text) or 0
		local have = if TradeUI._data then TradeUI._data.scrap or 0 else 0
		TradeUI._scrap = math.clamp(math.floor(typed), 0, have)
		box.Text = tostring(TradeUI._scrap)
		sendOffer()
	end)
	myList = UIUtil.Scroll({
		Name = "List",
		Size = UDim2.new(1, -16, 1, -76),
		Position = UDim2.fromOffset(8, 68),
		Parent = mineColumn,
	})

	local theirColumn = column("Theirs", 336)
	UIUtil.Text({
		Text = "THEIR OFFER",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 6),
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Text,
		Parent = theirColumn,
	})
	theirScrap = makeLabel(theirColumn, "Scrap  0", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 34), UIUtil.Colors.Scrap, Enum.Font.GothamBold, 14)
	theirList = UIUtil.Scroll({
		Name = "List",
		Size = UDim2.new(1, -16, 1, -76),
		Position = UDim2.fromOffset(8, 68),
		Parent = theirColumn,
	})

	local status = makeLabel(window, "Waiting for them to confirm", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 376), UIUtil.Colors.Muted, Enum.Font.Gotham, 13)
	status.TextXAlignment = Enum.TextXAlignment.Center
	theirStatus = status

	local confirm = UIUtil.Button({
		Name = "Confirm",
		Text = "CONFIRM TRADE",
		Size = UDim2.fromOffset(240, 36),
		Position = UDim2.new(0.5, -250, 1, -46),
		BackgroundColor3 = UIUtil.Colors.Success,
		Parent = window,
	})
	confirmButton = confirm
	confirm.MouseButton1Click:Connect(function()
		Remotes.Event("TradeConfirm"):FireServer()
	end)
	local cancelButton = UIUtil.Button({
		Name = "Cancel",
		Text = "CANCEL",
		Size = UDim2.fromOffset(240, 36),
		Position = UDim2.new(0.5, 10, 1, -46),
		BackgroundColor3 = UIUtil.Colors.Danger,
		Parent = window,
	})
	cancelButton.MouseButton1Click:Connect(function()
		Remotes.Event("TradeCancel"):FireServer()
	end)
end

function TradeUI.Init()
	build()

	Remotes.Event("DataUpdated").OnClientEvent:Connect(function(data)
		TradeUI._data = data
		if TradeUI._trade then
			renderTrade()
		end
	end)
	task.spawn(function()
		local data = Remotes.Function("GetPlayerData"):InvokeServer()
		if data then
			TradeUI._data = data
		end
	end)

	-- Moving garages changes who is "together".
	Remotes.Event("EnterGarage").OnClientEvent:Connect(function()
		TradeUI._together = {}
		task.delay(0.8, TradeUI.RefreshTogether)
	end)

	Remotes.Event("TradeUpdate").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.request then
			showRequest(payload.request.fromUserId, payload.request.fromName)
		elseif payload.requestEnded then
			hideRequest()
		elseif payload.cancelled or payload.completed then
			closeTrade()
		elseif payload.offers then
			hideRequest()
			adoptTrade(payload)
		end
	end)
end

return TradeUI
