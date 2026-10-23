--!strict
--[[
	In-run HUD — cinematic distance / vitals / convoy panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RunHUD = {}
RunHUD._gui = nil :: ScreenGui?
RunHUD._onRunEnded = nil :: ((any) -> ())?
RunHUD._scrap = 0

local function makeBar(parent: Frame, name: string, yScale: number, color: Color3): Frame
	local back = Instance.new("Frame")
	back.Name = name .. "Back"
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Size = UDim2.new(1, -24, 0, 20)
	back.Position = UDim2.new(0, 12, yScale, 0)
	back.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Parent = back
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 6)
	fc.Parent = fill
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = name
	label.Parent = back
	return back
end

function RunHUD.Build()
	if RunHUD._gui then
		RunHUD._gui:Destroy()
	end
	local gui = UIUtil.ScreenGui("ConvoyRunHud", playerGui)
	gui.Enabled = false
	RunHUD._gui = gui

	local top = UIUtil.Frame({
		Name = "Top",
		Size = UDim2.new(0, 420, 0, 168),
		Position = UDim2.new(0.5, 0, 0, 18),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(10, 12, 16),
		BackgroundTransparency = 0.12,
		Parent = gui,
	})

	UIUtil.Text({
		Name = "Distance",
		Text = "0 m",
		Font = Enum.Font.GothamBlack,
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.new(0, 12, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIUtil.Colors.Accent,
		Parent = top,
	})
	UIUtil.Text({
		Name = "Biome",
		Text = "Wasteland Highways",
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.new(0, 12, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIUtil.Colors.Muted,
		Font = Enum.Font.Gotham,
		Parent = top,
	})

	makeBar(top, "Health", 0, Color3.fromRGB(210, 55, 55)).Position = UDim2.new(0, 12, 0, 78)
	makeBar(top, "Fuel", 0, Color3.fromRGB(240, 170, 45)).Position = UDim2.new(0, 12, 0, 104)
	UIUtil.Text({
		Name = "ScrapBalance",
		Text = "Scrap  " .. tostring(RunHUD._scrap),
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.new(0, 12, 0, 134),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIUtil.Colors.Scrap,
		Parent = top,
	})

	local convoy = UIUtil.Frame({
		Name = "Convoy",
		Size = UDim2.new(0, 240, 0, 160),
		Position = UDim2.new(1, -20, 0, 18),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(10, 12, 16),
		Parent = gui,
	})
	UIUtil.Text({
		Text = "CONVOY",
		Font = Enum.Font.GothamBlack,
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.new(0, 10, 0, 8),
		TextColor3 = UIUtil.Colors.Accent,
		Parent = convoy,
	})
	UIUtil.Text({
		Name = "ConvoyList",
		Text = "",
		Size = UDim2.new(1, -16, 1, -40),
		Position = UDim2.new(0, 10, 0, 36),
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		Parent = convoy,
	})

	-- Banner for the timed event in play (horde, kill rush, ...).
	local banner = UIUtil.Text({
		Name = "EventBanner",
		Text = "",
		Font = Enum.Font.GothamBlack,
		Size = UDim2.fromOffset(520, 34),
		Position = UDim2.new(0.5, 0, 0, 196),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Color3.fromRGB(255, 220, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(10, 12, 16),
		BackgroundTransparency = 0.25,
		Corner = 8,
		Parent = gui,
	})
	banner.Visible = false

	-- Ends your run early; tap twice so a stray click does not throw one away.
	local endRun = UIUtil.Button({
		Name = "EndRunButton",
		Text = "END RUN",
		Size = UDim2.new(0, 240, 0, 40),
		Position = UDim2.new(1, -20, 0, 186),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(150, 45, 45),
		Parent = gui,
	})
	local armed = false
	endRun.MouseButton1Click:Connect(function()
		if armed then
			armed = false
			endRun.Text = "ENDING..."
			Remotes.Event("LeaveRun"):FireServer()
			return
		end
		armed = true
		endRun.Text = "TAP AGAIN TO END"
		task.delay(3, function()
			if armed then
				armed = false
				endRun.Text = "END RUN"
			end
		end)
	end)

	local endPanel = UIUtil.Frame({
		Name = "EndPanel",
		Size = UDim2.new(0, 420, 0, 310),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		BackgroundColor3 = Color3.fromRGB(12, 10, 12),
		Parent = gui,
	})
	UIUtil.Text({
		Name = "EndTitle",
		Text = "RUN OVER",
		Font = Enum.Font.GothamBlack,
		Size = UDim2.new(1, -24, 0, 42),
		Position = UDim2.new(0, 12, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIUtil.Colors.Danger,
		Parent = endPanel,
	})
	UIUtil.Text({
		Name = "EndDetail",
		Text = "",
		Size = UDim2.new(1, -24, 0, 160),
		Position = UDim2.new(0, 12, 0, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIUtil.Colors.Text,
		Parent = endPanel,
	})
	local backBtn = UIUtil.Button({
		Text = "BACK TO GARAGE",
		Size = UDim2.new(0.7, 0, 0, 42),
		Position = UDim2.new(0.15, 0, 1, -58),
		BackgroundColor3 = UIUtil.Colors.AccentDim,
		Parent = endPanel,
	})
	backBtn.MouseButton1Click:Connect(function()
		endPanel.Visible = false
		gui.Enabled = false
		if RunHUD._onRunEnded then
			RunHUD._onRunEnded({})
		end
	end)
end

function RunHUD.Update(state: any)
	local gui = RunHUD._gui
	if not gui then
		return
	end

	local banner = gui:FindFirstChild("EventBanner") :: TextLabel?
	if banner then
		local event = state.event
		if event and not (state.ended or state.active == false) then
			banner.Visible = true
			if event.goal and event.goal > 0 then
				banner.Text = string.format("%s  %d/%d  (%ds)", event.name, event.progress or 0, event.goal, math.ceil(event.timeLeft or 0))
			else
				banner.Text = string.format("%s: %s", event.name, event.text or "")
			end
		else
			banner.Visible = false
		end
	end

	local endRunButton = gui:FindFirstChild("EndRunButton") :: TextButton?
	if endRunButton then
		local running = not (state.ended or state.active == false)
		endRunButton.Visible = running
		if running and endRunButton.Text == "ENDING..." then
			-- The server has not ended the run (others are still driving).
			endRunButton.Text = "END RUN"
		end
	end

	if state.ended or state.active == false then
		gui.Enabled = true
		local endPanel = gui:FindFirstChild("EndPanel") :: Frame
		endPanel.Visible = true
		local detail = endPanel:FindFirstChild("EndDetail") :: TextLabel
		local title = endPanel:FindFirstChild("EndTitle") :: TextLabel
		title.Text = if state.newRecord then "NEW RECORD!" else "RUN OVER"
		title.TextColor3 = if state.newRecord then UIUtil.Colors.Scrap else UIUtil.Colors.Danger
		local lines = {
			string.format("Distance: %.0f m  (+%d scrap)", state.distance or 0, state.distanceScrap or 0),
			string.format("Kills: %d  (+%d scrap)", state.kills or 0, state.killScrap or 0),
		}
		if (state.bossKills or 0) > 0 then
			table.insert(lines, string.format("Juggernauts: %d  (+%d scrap)", state.bossKills, state.bossScrap or 0))
		end
		table.insert(lines, string.format("Pickups: %d", state.pickups or 0))
		if state.boosts and #state.boosts > 0 then
			table.insert(lines, "Boosts used: " .. table.concat(state.boosts, ", "))
		end
		table.insert(lines, string.format("Total scrap: %d    XP: +%d", state.scrapEarned or 0, state.xpEarned or 0))
		table.insert(lines, string.format("Scrap on hand: %d", RunHUD._scrap))
		if (state.levelsGained or 0) > 0 then
			table.insert(lines, string.format("LEVEL UP! Now level %d", state.level or 1))
		end
		detail.Text = table.concat(lines, "\n")
		return
	end

	gui.Enabled = true
	local endPanel = gui:FindFirstChild("EndPanel") :: Frame?
	if endPanel then
		endPanel.Visible = false
	end

	local top = gui:FindFirstChild("Top") :: Frame
	local distance = top:FindFirstChild("Distance") :: TextLabel
	local biome = top:FindFirstChild("Biome") :: TextLabel
	distance.Text = string.format("%.0f m", state.distance or 0)

	local my = state.vehicles and state.vehicles[tostring(player.UserId)]
	if my then
		local healthBack = top:FindFirstChild("HealthBack") :: Frame
		local fuelBack = top:FindFirstChild("FuelBack") :: Frame
		local hFill = healthBack:FindFirstChild("Fill") :: Frame
		local fFill = fuelBack:FindFirstChild("Fill") :: Frame
		local hLabel = healthBack:FindFirstChild("Label") :: TextLabel
		local fLabel = fuelBack:FindFirstChild("Label") :: TextLabel
		local hp = (my.health or 0) / math.max(1, my.maxHealth or 1)
		local fp = (my.fuel or 0) / math.max(1, my.maxFuel or 1)
		hFill.Size = UDim2.new(math.clamp(hp, 0, 1), 0, 1, 0)
		fFill.Size = UDim2.new(math.clamp(fp, 0, 1), 0, 1, 0)
		hLabel.Text = string.format("HP  %d / %d", math.floor(my.health or 0), math.floor(my.maxHealth or 0))
		if (my.maxShield or 0) > 0 then
			hLabel.Text ..= string.format("   +%d shield", math.floor(my.shield or 0))
		end
		fLabel.Text = string.format("FUEL  %d / %d", math.floor(my.fuel or 0), math.floor(my.maxFuel or 0))
	end

	local distScrap = math.floor((state.distance or 0) / Constants.SCRAP_PER_METERS)
	biome.Text = string.format("%s   ·   ~%d scrap from distance", tostring(state.biome or ""), distScrap)

	local convoyList = gui:FindFirstChild("ConvoyList", true) :: TextLabel
	if convoyList and state.vehicles then
		local lines = {}
		for _, info in state.vehicles do
			table.insert(
				lines,
				string.format(
					"%s%s   Kills %d",
					info.name or "?",
					if info.alive then "" else "  ✖",
					info.kills or 0
				)
			)
		end
		convoyList.Text = table.concat(lines, "\n")
	end
end

local function setScrap(scrap: number)
	RunHUD._scrap = scrap
	local gui = RunHUD._gui
	local label = if gui then gui:FindFirstChild("ScrapBalance", true) else nil
	if label and label:IsA("TextLabel") then
		label.Text = "Scrap  " .. tostring(scrap)
	end
end

function RunHUD.Init(onRunEnded: (any) -> ())
	RunHUD._onRunEnded = onRunEnded
	RunHUD.Build()
	Remotes.Event("DataUpdated").OnClientEvent:Connect(function(data)
		setScrap(data.scrap or 0)
	end)
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.Function("GetPlayerData"):InvokeServer()
		end)
		if ok and data then
			setScrap(data.scrap or 0)
		end
	end)
	Remotes.Event("RunState").OnClientEvent:Connect(function(state)
		RunHUD.Update(state)
	end)
end

function RunHUD.Hide()
	if RunHUD._gui then
		RunHUD._gui.Enabled = false
	end
end

return RunHUD
