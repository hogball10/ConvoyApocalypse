--!strict
--[[
	The menu column on the right of the garage: daily reward, quests and
	achievements, leaderboards, cosmetics, prestige and the party list. One shared
	panel shows whichever tab was clicked; a "!" marks a tab with something to claim.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))
local SoundFX = require(script.Parent:WaitForChild("SoundFX"))

local player = Players.LocalPlayer

local MenuUI = {}
MenuUI._data = nil :: any
MenuUI._panel = nil :: Frame?
MenuUI._content = nil :: Frame?
MenuUI._tab = nil :: string?
MenuUI._buttons = {} :: { [string]: TextButton }
MenuUI._boards = nil :: any
MenuUI._runs = {} :: { any }
MenuUI._armedPrestige = false

local TABS = {
	{ id = "Daily", label = "DAILY" },
	{ id = "Quests", label = "QUESTS" },
	{ id = "Boards", label = "BOARDS" },
	{ id = "Style", label = "STYLE" },
	{ id = "Prestige", label = "PRESTIGE" },
	{ id = "Party", label = "PARTY" },
}

local function act(action: string, a: any?, b: any?)
	if string.sub(action, 1, 5) == "Claim" or action == "BuyCosmetic" or action == "Prestige" then
		SoundFX.Play("coin")
	end
	Remotes.Event("ProgressAction"):FireServer(action, a, b)
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function fmt(n: number): string
	local text = tostring(math.floor(n))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function statValue(data: any, stat: string): number
	if stat == "kills" then
		return data.totalKills or 0
	elseif stat == "runs" then
		return data.totalRuns or 0
	elseif stat == "distance" then
		return data.highScore or 0
	elseif stat == "level" then
		return data.level or 1
	elseif stat == "bosses" then
		return data.stats and data.stats.bossKills or 0
	elseif stat == "pickups" then
		return data.stats and data.stats.pickups or 0
	elseif stat == "prestige" then
		return data.prestige or 0
	end
	return 0
end

-- Is there something to claim under this tab?
local function hasReward(tab: string): boolean
	local data = MenuUI._data
	if not data then
		return false
	end
	if tab == "Daily" then
		return data.daily ~= nil and data.serverDay ~= nil and data.daily.lastDay < data.serverDay
	elseif tab == "Quests" then
		for _, entry in (data.quests and data.quests.list) or {} do
			local quest = Constants.QuestById(entry.id)
			if quest and not entry.claimed and entry.progress >= quest.target then
				return true
			end
		end
		for _, achievement in Constants.ACHIEVEMENTS do
			if not (data.achievements or {})[achievement.id] and statValue(data, achievement.stat) >= achievement.target then
				return true
			end
		end
	elseif tab == "Prestige" then
		return (data.level or 1) >= Constants.PRESTIGE_LEVEL and (data.prestige or 0) < Constants.PRESTIGE_MAX
	end
	return false
end

local function refreshBadges()
	for _, tab in TABS do
		local button = MenuUI._buttons[tab.id]
		if button then
			local flagged = hasReward(tab.id)
			button.Text = if flagged then tab.label .. "  !" else tab.label
			button.BackgroundColor3 = if flagged then UIUtil.Colors.Success elseif MenuUI._tab == tab.id then UIUtil.Colors.Accent else UIUtil.Colors.AccentDim
		end
	end
end

-- A titled row inside a list.
local function listRow(parent: Instance, order: number, height: number): Frame
	local row = Instance.new("Frame")
	row.BackgroundColor3 = UIUtil.Colors.PanelAlt
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -6, 0, height)
	row.LayoutOrder = order
	row.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row
	return row
end

local function bar(parent: Instance, fraction: number, color: Color3, position: UDim2, size: UDim2)
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	back.BorderSizePixel = 0
	back.Position = position
	back.Size = size
	back.Parent = parent
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 5)
	backCorner.Parent = back
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill
end

local function heading(parent: Instance, text: string, order: number)
	local label = UIUtil.Text({
		Name = "Heading",
		Text = text,
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Size = UDim2.new(1, -6, 0, 24),
		Parent = parent,
	})
	label.LayoutOrder = order
end

-- ── Daily ──────────────────────────────────────────────────────────────────

local function renderDaily(content: Instance)
	local data = MenuUI._data
	local lastDay = data.daily and data.daily.lastDay or 0
	local streak = data.daily and data.daily.streak or 0
	local today = data.serverDay or 0
	local claimable = lastDay < today
	-- The streak breaks if yesterday was missed.
	local shown = if lastDay >= today - 1 then streak else 0
	local nextDay = if claimable then shown + 1 else shown

	UIUtil.Text({
		Text = "Log in every day to keep your streak going. Day 7 pays big!",
		TextColor3 = UIUtil.Colors.Muted,
		Font = Enum.Font.Gotham,
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(6, 0),
		Parent = content,
	})

	local count = #Constants.DAILY_REWARDS
	local tileW = 0.14
	for index, reward in Constants.DAILY_REWARDS do
		local tile = Instance.new("Frame")
		tile.BackgroundColor3 = UIUtil.Colors.PanelAlt
		tile.BorderSizePixel = 0
		tile.Size = UDim2.new(tileW, -6, 0, 120)
		tile.Position = UDim2.new((index - 1) * (1 / count), 3, 0, 40)
		tile.Parent = content
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = tile
		local cycleDay = ((nextDay - 1) % count) + 1
		local doneUpTo = if claimable then cycleDay - 1 elseif shown > 0 then ((shown - 1) % count) + 1 else 0
		local done = index <= doneUpTo
		local current = claimable and index == cycleDay
		if current then
			local stroke = Instance.new("UIStroke")
			stroke.Color = UIUtil.Colors.Accent
			stroke.Thickness = 2
			stroke.Parent = tile
		end
		UIUtil.Text({
			Text = "DAY " .. index,
			Font = Enum.Font.GothamBold,
			TextColor3 = if current then UIUtil.Colors.Accent else UIUtil.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -8, 0, 22),
			Position = UDim2.fromOffset(4, 6),
			Parent = tile,
		})
		UIUtil.Text({
			Text = fmt(reward.scrap),
			Font = Enum.Font.GothamBlack,
			TextColor3 = UIUtil.Colors.Scrap,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -8, 0, 32),
			Position = UDim2.fromOffset(4, 34),
			Parent = tile,
		})
		UIUtil.Text({
			Text = "scrap + " .. reward.xp .. " XP",
			Font = Enum.Font.Gotham,
			TextColor3 = UIUtil.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -8, 0, 16),
			Position = UDim2.fromOffset(4, 70),
			Parent = tile,
		})
		if done then
			UIUtil.Text({
				Text = "CLAIMED",
				Font = Enum.Font.GothamBold,
				TextColor3 = UIUtil.Colors.Success,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -8, 0, 16),
				Position = UDim2.fromOffset(4, 94),
				Parent = tile,
			})
		end
	end

	local button = UIUtil.Button({
		Text = if claimable then "CLAIM TODAY'S REWARD" else "CLAIMED. COME BACK TOMORROW",
		Size = UDim2.new(0.6, 0, 0, 46),
		Position = UDim2.new(0.2, 0, 0, 190),
		BackgroundColor3 = if claimable then UIUtil.Colors.Success else UIUtil.Colors.PanelAlt,
		Parent = content,
	})
	button.MouseButton1Click:Connect(function()
		if claimable then
			act("ClaimDaily")
		end
	end)
	UIUtil.Text({
		Text = string.format("Current streak: %d day%s", shown, if shown == 1 then "" else "s"),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 250),
		Parent = content,
	})
end

-- ── Quests and achievements ───────────────────────────────────────────────

local function renderGoal(parent: Instance, order: number, text: string, progress: number, target: number, scrap: number, xp: number, claimed: boolean, onClaim: () -> ())
	local row = listRow(parent, order, 62)
	UIUtil.Text({
		Text = text,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(0.62, -10, 0, 22),
		Position = UDim2.fromOffset(10, 6),
		Parent = row,
	})
	UIUtil.Text({
		Text = string.format("%s / %s   ·   +%s scrap, +%d XP", fmt(math.min(progress, target)), fmt(target), fmt(scrap), xp),
		Font = Enum.Font.Gotham,
		TextColor3 = UIUtil.Colors.Muted,
		Size = UDim2.new(0.62, -10, 0, 16),
		Position = UDim2.fromOffset(10, 30),
		Parent = row,
	})
	bar(row, progress / target, UIUtil.Colors.Accent, UDim2.fromOffset(10, 50), UDim2.new(0.62, -10, 0, 6))
	local ready = progress >= target and not claimed
	local button = UIUtil.Button({
		Text = if claimed then "DONE" elseif ready then "CLAIM" else "IN PROGRESS",
		Size = UDim2.new(0.34, -10, 0, 38),
		Position = UDim2.new(0.66, 0, 0.5, -19),
		BackgroundColor3 = if ready then UIUtil.Colors.Success else UIUtil.Colors.PanelAlt,
		Parent = row,
	})
	button.MouseButton1Click:Connect(function()
		if ready then
			onClaim()
		end
	end)
end

local function renderQuests(content: Instance)
	local data = MenuUI._data
	local scroll = UIUtil.Scroll({ Size = UDim2.fromScale(1, 1), Parent = content })
	heading(scroll, "DAILY QUESTS  (reset each day)", 0)
	local order = 1
	for _, entry in (data.quests and data.quests.list) or {} do
		local quest = Constants.QuestById(entry.id)
		if quest then
			renderGoal(scroll, order, quest.text, entry.progress, quest.target, quest.scrap, quest.xp, entry.claimed, function()
				act("ClaimQuest", quest.id)
			end)
			order += 1
		end
	end
	if order == 1 then
		UIUtil.Text({ Text = "Quests will appear in a moment...", TextColor3 = UIUtil.Colors.Muted, Size = UDim2.new(1, 0, 0, 24), Parent = scroll }).LayoutOrder = 1
		order += 1
	end
	heading(scroll, "ACHIEVEMENTS", order)
	order += 1
	local claimed = data.achievements or {}
	for _, achievement in Constants.ACHIEVEMENTS do
		renderGoal(scroll, order, achievement.text, statValue(data, achievement.stat), achievement.target, achievement.scrap, achievement.xp, claimed[achievement.id] == true, function()
			act("ClaimAchievement", achievement.id)
		end)
		order += 1
	end
end

-- ── Leaderboards ───────────────────────────────────────────────────────────

local function boardColumn(content: Instance, title: string, entries: { any }, xScale: number, suffix: string)
	local column = Instance.new("Frame")
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(0.5, -6, 1, 0)
	column.Position = UDim2.new(xScale, 3, 0, 0)
	column.Parent = content
	UIUtil.Text({
		Text = title,
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = column,
	})
	local scroll = UIUtil.Scroll({ Size = UDim2.new(1, 0, 1, -30), Position = UDim2.fromOffset(0, 30), Parent = column })
	for index, entry in entries do
		local row = listRow(scroll, index, 28)
		local mine = entry.userId == player.UserId
		UIUtil.Text({
			Text = string.format("%d.  %s", index, entry.name),
			Font = if mine then Enum.Font.GothamBold else Enum.Font.Gotham,
			TextColor3 = if mine then UIUtil.Colors.Accent else UIUtil.Colors.Text,
			Size = UDim2.new(0.6, -8, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			Parent = row,
		})
		UIUtil.Text({
			Text = fmt(entry.value) .. suffix,
			Font = Enum.Font.GothamBold,
			TextColor3 = UIUtil.Colors.Scrap,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.4, -8, 1, 0),
			Position = UDim2.new(0.6, 0, 0, 0),
			Parent = row,
		})
	end
	if #entries == 0 then
		UIUtil.Text({ Text = "No scores yet", TextColor3 = UIUtil.Colors.Muted, Size = UDim2.new(1, 0, 0, 24), Parent = scroll })
	end
end

local function renderBoards(content: Instance)
	local boards = MenuUI._boards
	if not boards then
		UIUtil.Text({ Text = "Loading leaderboards...", TextColor3 = UIUtil.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Center, Parent = content })
		return
	end
	if boards.available == false then
		UIUtil.Text({
			Text = "Leaderboards are only available in the published game.",
			TextColor3 = UIUtil.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 30),
			Parent = content,
		})
		return
	end
	boardColumn(content, "FURTHEST RUN", boards.distance, 0, " m")
	boardColumn(content, "MOST KILLS IN A RUN", boards.kills, 0.5, "")
end

local function loadBoards()
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.Function("GetLeaderboards"):InvokeServer()
		end)
		MenuUI._boards = if ok then result else { available = false, distance = {}, kills = {} }
		if MenuUI._tab == "Boards" then
			MenuUI.Render()
		end
	end)
end

-- ── Style (cosmetics) ──────────────────────────────────────────────────────

local SLOT_TITLES = { paint = "PAINT", trail = "TRAILS", flag = "FLAGS" }

local function renderStyle(content: Instance)
	local data = MenuUI._data
	local cosmetics = data.cosmetics or { owned = {}, paint = "", trail = "", flag = "" }
	local scroll = UIUtil.Scroll({ Size = UDim2.fromScale(1, 1), Parent = content })
	local order = 0
	for _, slot in Constants.COSMETIC_SLOTS do
		heading(scroll, SLOT_TITLES[slot] .. (if slot == "paint" then "  (tints your plain blocks)" else ""), order)
		order += 1
		-- "None" first, so a slot can always be cleared.
		local items = { { id = "", name = "None", price = 0, color = Color3.fromRGB(60, 62, 70) } }
		for _, item in Constants.COSMETICS do
			if item.slot == slot then
				table.insert(items, item)
			end
		end
		for _, item in items do
			local row = listRow(scroll, order, 44)
			order += 1
			local swatch = Instance.new("Frame")
			swatch.BackgroundColor3 = item.color
			swatch.BorderSizePixel = 0
			swatch.Size = UDim2.fromOffset(28, 28)
			swatch.Position = UDim2.fromOffset(10, 8)
			swatch.Parent = row
			local swatchCorner = Instance.new("UICorner")
			swatchCorner.CornerRadius = UDim.new(0, 6)
			swatchCorner.Parent = swatch
			if (item :: any).rainbow then
				local gradient = Instance.new("UIGradient")
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 235, 70)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 90, 255)),
				})
				gradient.Parent = swatch
			end
			UIUtil.Text({
				Text = item.name,
				Font = Enum.Font.GothamBold,
				Size = UDim2.new(0.5, -50, 0, 22),
				Position = UDim2.fromOffset(46, 11),
				Parent = row,
			})
			local owned = item.id == "" or cosmetics.owned[item.id] == true
			local equipped = (cosmetics :: any)[slot] == item.id
			local label = if equipped then "EQUIPPED" elseif owned then "EQUIP" else fmt(item.price) .. " scrap"
			local button = UIUtil.Button({
				Text = label,
				Size = UDim2.new(0.34, -8, 0, 32),
				Position = UDim2.new(0.66, 0, 0.5, -16),
				BackgroundColor3 = if equipped then UIUtil.Colors.Success elseif owned then UIUtil.Colors.AccentDim else UIUtil.Colors.PanelAlt,
				Parent = row,
			})
			button.MouseButton1Click:Connect(function()
				if equipped then
					return
				end
				if owned then
					act("EquipCosmetic", slot, item.id)
				else
					act("BuyCosmetic", item.id)
				end
			end)
		end
	end
end

-- ── Prestige ───────────────────────────────────────────────────────────────

local function renderPrestige(content: Instance)
	local data = MenuUI._data
	local prestige = data.prestige or 0
	local level = data.level or 1
	local bonus = math.round(Constants.PRESTIGE_BONUS * 100 * prestige)
	local nextBonus = math.round(Constants.PRESTIGE_BONUS * 100 * (prestige + 1))
	local ready = level >= Constants.PRESTIGE_LEVEL and prestige < Constants.PRESTIGE_MAX

	UIUtil.Text({
		Text = "PRESTIGE " .. prestige,
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = content,
	})
	UIUtil.Text({
		Text = string.format("Permanent bonus now: +%d%% scrap and XP", bonus),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 50),
		Parent = content,
	})
	UIUtil.Text({
		Text = string.format("Prestiging resets your level, XP and scrap (back to %d) and raises the bonus to +%d%%. Parts, cars and cosmetics are kept.", Constants.STARTING_SCRAP, nextBonus),
		Font = Enum.Font.Gotham,
		TextColor3 = UIUtil.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0.86, 0, 0, 50),
		Position = UDim2.new(0.07, 0, 0, 86),
		Parent = content,
	})
	UIUtil.Text({
		Text = string.format("Level %d / %d required", math.min(level, Constants.PRESTIGE_LEVEL), Constants.PRESTIGE_LEVEL),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 150),
		Parent = content,
	})
	bar(content, level / Constants.PRESTIGE_LEVEL, UIUtil.Colors.Accent, UDim2.new(0.2, 0, 0, 178), UDim2.new(0.6, 0, 0, 10))
	local button = UIUtil.Button({
		Text = if prestige >= Constants.PRESTIGE_MAX then "MAX PRESTIGE" elseif not ready then "LOCKED" elseif MenuUI._armedPrestige then "TAP AGAIN TO CONFIRM" else "PRESTIGE",
		Size = UDim2.new(0.5, 0, 0, 50),
		Position = UDim2.new(0.25, 0, 0, 210),
		BackgroundColor3 = if ready then UIUtil.Colors.Danger else UIUtil.Colors.PanelAlt,
		Parent = content,
	})
	button.MouseButton1Click:Connect(function()
		if not ready then
			return
		end
		if MenuUI._armedPrestige then
			MenuUI._armedPrestige = false
			act("Prestige")
			return
		end
		MenuUI._armedPrestige = true
		MenuUI.Render()
		task.delay(4, function()
			if MenuUI._armedPrestige then
				MenuUI._armedPrestige = false
				if MenuUI._tab == "Prestige" then
					MenuUI.Render()
				end
			end
		end)
	end)
end

-- ── Party ──────────────────────────────────────────────────────────────────

local function renderParty(content: Instance)
	local invite = UIUtil.Button({
		Text = "INVITE FRIENDS TO PLAY",
		Size = UDim2.new(0.5, 0, 0, 44),
		Position = UDim2.new(0.25, 0, 0, 0),
		BackgroundColor3 = UIUtil.Colors.Success,
		Parent = content,
	})
	invite.MouseButton1Click:Connect(function()
		local ok, canInvite = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and canInvite then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end
	end)
	UIUtil.Text({
		Text = "RUNS YOU CAN JOIN",
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 56),
		Parent = content,
	})
	local scroll = UIUtil.Scroll({ Size = UDim2.new(1, 0, 1, -90), Position = UDim2.fromOffset(0, 86), Parent = content })
	local shown = 0
	for _, run in MenuUI._runs do
		if run.hostUserId ~= player.UserId then
			shown += 1
			local row = listRow(scroll, shown, 46)
			UIUtil.Text({
				Text = string.format("%s's convoy", run.name),
				Font = Enum.Font.GothamBold,
				Size = UDim2.new(0.6, -10, 0, 22),
				Position = UDim2.fromOffset(10, 4),
				Parent = row,
			})
			UIUtil.Text({
				Text = string.format("%d driver%s  ·  %s m", run.players, if run.players == 1 then "" else "s", fmt(run.distance)),
				Font = Enum.Font.Gotham,
				TextColor3 = UIUtil.Colors.Muted,
				Size = UDim2.new(0.6, -10, 0, 16),
				Position = UDim2.fromOffset(10, 26),
				Parent = row,
			})
			local join = UIUtil.Button({
				Text = "JOIN RUN",
				Size = UDim2.new(0.34, -8, 0, 32),
				Position = UDim2.new(0.66, 0, 0.5, -16),
				Parent = row,
			})
			join.MouseButton1Click:Connect(function()
				Remotes.Event("JoinRun"):FireServer(run.hostUserId)
			end)
		end
	end
	if shown == 0 then
		UIUtil.Text({
			Text = "Nobody is on a run right now. Start one and friends can join from here.",
			Font = Enum.Font.Gotham,
			TextColor3 = UIUtil.Colors.Muted,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = scroll,
		})
	end
	UIUtil.Text({
		Text = "Tip: park next to a wrecked teammate for 3 seconds to revive them.",
		Font = Enum.Font.Gotham,
		TextColor3 = UIUtil.Colors.Muted,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -22),
		Parent = content,
	})
end

local function loadRuns()
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.Function("GetOpenRuns"):InvokeServer()
		end)
		if ok and typeof(result) == "table" then
			MenuUI._runs = result
			if MenuUI._tab == "Party" then
				MenuUI.Render()
			end
		end
	end)
end

-- ── Panel ──────────────────────────────────────────────────────────────────

local RENDERERS: { [string]: (Instance) -> () } = {
	Daily = renderDaily,
	Quests = renderQuests,
	Boards = renderBoards,
	Style = renderStyle,
	Prestige = renderPrestige,
	Party = renderParty,
}

function MenuUI.Render()
	local content = MenuUI._content
	local panel = MenuUI._panel
	refreshBadges()
	if not content or not panel or not MenuUI._tab or not MenuUI._data then
		return
	end
	clear(content)
	local title = panel:FindFirstChild("Title") :: TextLabel?
	if title then
		for _, tab in TABS do
			if tab.id == MenuUI._tab then
				title.Text = tab.label
			end
		end
	end
	local render = RENDERERS[MenuUI._tab]
	if render then
		render(content)
	end
end

function MenuUI.Open(tab: string?)
	local panel = MenuUI._panel
	if not panel then
		return
	end
	if tab == nil or (MenuUI._tab == tab and panel.Visible) then
		panel.Visible = false
		MenuUI._tab = nil
		refreshBadges()
		return
	end
	-- The other panels use the same spot in the middle of the screen.
	for _, other in { { "Passes", "Panel" }, { "Trade", "PlayersPanel" } } do
		local gui = player.PlayerGui:FindFirstChild(other[1])
		local otherPanel = if gui then gui:FindFirstChild(other[2]) else nil
		if otherPanel and otherPanel:IsA("GuiObject") then
			otherPanel.Visible = false
		end
	end
	MenuUI._tab = tab
	MenuUI._armedPrestige = false
	panel.Visible = true
	if tab == "Boards" then
		loadBoards()
	elseif tab == "Party" then
		loadRuns()
	end
	MenuUI.Render()
end

local function build()
	local gui = UIUtil.ScreenGui("Menu", player:WaitForChild("PlayerGui"))

	for index, tab in TABS do
		local button = UIUtil.Button({
			Name = tab.id,
			Text = tab.label,
			Size = UDim2.fromOffset(132, 34),
			Position = UDim2.new(1, -14, 0.5, (index - 1) * 40 - 120),
			AnchorPoint = Vector2.new(1, 0),
			Parent = gui,
		})
		MenuUI._buttons[tab.id] = button
		button.MouseButton1Click:Connect(function()
			MenuUI.Open(tab.id)
		end)
	end

	local panel = UIUtil.Frame({
		Name = "Panel",
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(660, 400),
		Position = UDim2.new(0.5, -70, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	MenuUI._panel = panel
	UIUtil.Text({
		Name = "Title",
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Size = UDim2.new(1, -70, 0, 32),
		Position = UDim2.fromOffset(16, 10),
		Parent = panel,
	})
	local close = UIUtil.Button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(34, 30),
		Position = UDim2.new(1, -46, 0, 10),
		BackgroundColor3 = UIUtil.Colors.Danger,
		Parent = panel,
	})
	close.MouseButton1Click:Connect(function()
		MenuUI.Open(nil)
	end)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -32, 1, -62)
	content.Position = UDim2.fromOffset(16, 50)
	content.Parent = panel
	MenuUI._content = content
end

function MenuUI.Init()
	build()
	local function onData(data: any)
		MenuUI._data = data
		MenuUI.Render()
	end
	Remotes.Event("DataUpdated").OnClientEvent:Connect(onData)
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.Function("GetPlayerData"):InvokeServer()
		end)
		if ok and data then
			onData(data)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			if MenuUI._tab == "Party" and MenuUI._panel and MenuUI._panel.Visible then
				loadRuns()
			end
		end
	end)
end

return MenuUI
