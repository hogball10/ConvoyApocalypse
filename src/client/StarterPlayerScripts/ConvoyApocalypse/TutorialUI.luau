--!strict
--[[
	A short guided tour for new players: a few tip cards in the garage, shown once
	(the profile remembers it) and skippable. Hidden during runs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))

local player = Players.LocalPlayer

local TutorialUI = {}
TutorialUI._shown = false

local STEPS = {
	{
		title = "Welcome to Convoy Apocalypse!",
		body = "Build a car, drive down the road, shoot zombies and earn scrap. Spend scrap on better parts and go further every run.",
	},
	{
		title = "1. Get parts",
		body = "Walk up to a lever in your garage to roll a random part, then pay scrap to keep what it lands on. Rarer parts cost more.",
	},
	{
		title = "2. Build your car",
		body = "Open INVENTORY (I), click a part, then click the green pad to place it. Every car needs an engine, wheels, a fuel tank and a seat. More fuel tanks mean more range.",
	},
	{
		title = "3. Start a run",
		body = "Hold the orange pad to start. Friends can hop in from the PARTY menu, and a teammate parked next to your wreck for 3 seconds will revive you.",
	},
	{
		title = "4. Driving",
		body = "W / S to speed up or slow down, A / D to steer. Your guns fire on their own. Grab fuel, scrap and repair orbs, hit boost pads and jump ramps. Watch for hordes and kill rushes!",
	},
	{
		title = "5. Running dry",
		body = "No fuel? You stall but keep shooting. The run ends when your car is destroyed, or press END RUN any time to bank your scrap.",
	},
	{
		title = "6. Free rewards",
		body = "Check DAILY and QUESTS on the right every day for free scrap and XP. Reach level 15 to PRESTIGE for a permanent bonus. Have fun!",
	},
}

local function build()
	local gui = UIUtil.ScreenGui("Tutorial", player:WaitForChild("PlayerGui"))
	gui.DisplayOrder = 20

	local card = UIUtil.Frame({
		Name = "Card",
		Size = UDim2.fromOffset(560, 190),
		Position = UDim2.new(0.5, 0, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
	})
	local title = UIUtil.Text({
		Name = "Title",
		Font = Enum.Font.GothamBlack,
		TextColor3 = UIUtil.Colors.Accent,
		Size = UDim2.new(1, -28, 0, 30),
		Position = UDim2.fromOffset(14, 10),
		Parent = card,
	})
	local body = UIUtil.Text({
		Name = "Body",
		Font = Enum.Font.Gotham,
		Size = UDim2.new(1, -28, 0, 80),
		Position = UDim2.fromOffset(14, 46),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local step = UIUtil.Text({
		Name = "Step",
		Font = Enum.Font.Gotham,
		TextColor3 = UIUtil.Colors.Muted,
		Size = UDim2.fromOffset(120, 18),
		Position = UDim2.new(0, 14, 1, -34),
		Parent = card,
	})
	local skip = UIUtil.Button({
		Name = "Skip",
		Text = "SKIP",
		Size = UDim2.fromOffset(90, 32),
		Position = UDim2.new(1, -214, 1, -42),
		BackgroundColor3 = UIUtil.Colors.PanelAlt,
		Parent = card,
	})
	local nextButton = UIUtil.Button({
		Name = "Next",
		Text = "NEXT",
		Size = UDim2.fromOffset(100, 32),
		Position = UDim2.new(1, -114, 1, -42),
		BackgroundColor3 = UIUtil.Colors.Success,
		Parent = card,
	})

	local index = 1
	local function show()
		local current = STEPS[index]
		title.Text = current.title
		body.Text = current.body
		step.Text = string.format("%d / %d", index, #STEPS)
		nextButton.Text = if index == #STEPS then "DONE" else "NEXT"
	end
	local function finish()
		gui:Destroy()
		Remotes.Event("ProgressAction"):FireServer("TutorialDone")
	end
	nextButton.MouseButton1Click:Connect(function()
		if index >= #STEPS then
			finish()
		else
			index += 1
			show()
		end
	end)
	skip.MouseButton1Click:Connect(finish)
	show()
end

function TutorialUI.Init()
	local function check(data: any)
		if TutorialUI._shown or not data or data.tutorialDone ~= false then
			return
		end
		TutorialUI._shown = true
		build()
	end
	Remotes.Event("DataUpdated").OnClientEvent:Connect(check)
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.Function("GetPlayerData"):InvokeServer()
		end)
		if ok then
			check(data)
		end
	end)
end

return TutorialUI
