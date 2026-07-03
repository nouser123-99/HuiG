-- ============================================================
--  HuiG — Optimized & Clean (Home, Visuals, Sounds, Misc, Settings)
-- ============================================================

-- ── shared upvalues ─────────────────────────────────────────
local Library, ThemeManager, SaveManager, Window
local Toggles, Options
local Players, RunService, MarketplaceService, TeleportService, StatsService
local player, playerGui, scriptStartTime
local uiConnections = {}
local huiNotify

-- BH shared state (needed by Visuals)
local isBlackHoleHole
local processedHoles   = {}
local bhPreloadedModels = {}
local bhActiveModels    = {}
local bhPreloadFolder

local function trackConnection(conn)
	table.insert(uiConnections, conn)
	return conn
end

-- ============================================================
--  CORE INIT
-- ============================================================
local function initCore()
	if _G.HuiG_SplashProgress then _G.HuiG_SplashProgress(15, "Connecting to repository...") end

	local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/"
	Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
	if _G.HuiG_SplashProgress then _G.HuiG_SplashProgress(45, "Loading Library...") end

	ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
	if _G.HuiG_SplashProgress then _G.HuiG_SplashProgress(65, "Loading Theme Manager...") end

	SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
	if _G.HuiG_SplashProgress then _G.HuiG_SplashProgress(80, "Loading Save Manager...") end

	Window = Library:CreateWindow({
    	Title        = "HuiG",
    	Footer       = "V2.6",
		Icon         = "crown",
   		NotifySide   = "Right",
    	CornerRadius = 20,
	})
	if _G.HuiG_SplashProgress then _G.HuiG_SplashProgress(95, "Building interface...") end

	-- ...rest of initCore stays exactly the same (topbar glow task.defer, service GetServices, etc.)

	task.defer(function()
		local TweenService = game:GetService("TweenService")

		local CONFIG = {
			SweepDuration    = 3.5,  -- much slower sweep, left to right
			PauseBetween     = 2,    -- wait after each sweep before repeating
			RestingDimness   = 0.5,  -- how grey/dim the text is at rest (0 = fully visible, 1 = invisible)
			BandWidth        = 0.55, -- wide, soft glow band so it doesn't look stepped
		}

		local screenGui = Library.ScreenGui
		if not screenGui then return end
		local mainFrame = screenGui:FindFirstChild("Main")
		if not mainFrame then return end

		for _, topBar in mainFrame:GetChildren() do
			if not (topBar:IsA("Frame") and topBar.Size.Y.Offset == 48) then continue end

			for _, holder in topBar:GetChildren() do
				if not (holder:IsA("Frame") and holder.BackgroundTransparency == 1) then continue end

				local layout = holder:FindFirstChildOfClass("UIListLayout")
				if layout then
					layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
				end

				local pad = holder:FindFirstChildOfClass("UIPadding")
				if not pad then
					pad = Instance.new("UIPadding")
					pad.Parent = holder
				end
				pad.PaddingLeft = UDim.new(0, 14)

				for _, child in holder:GetChildren() do
					if not (child:IsA("TextLabel") and child.TextSize == 20) then continue end
					if child:GetAttribute("HuiG_GlowActive") then continue end -- duplicate guard
					child:SetAttribute("HuiG_GlowActive", true)

					child.TextXAlignment = Enum.TextXAlignment.Left
					child.TextTransparency = 0 -- base label stays fully opaque; gradient controls dimming

					-- Gradient locked to the label's own color; transparency does the dimming/glow work
					local gradient = child:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
					gradient.Color = ColorSequence.new(child.TextColor3)

					local half = CONFIG.BandWidth / 2
					gradient.Transparency = NumberSequence.new{
						NumberSequenceKeypoint.new(0, CONFIG.RestingDimness),
						NumberSequenceKeypoint.new(math.clamp(0.5 - half, 0, 1), CONFIG.RestingDimness),
						NumberSequenceKeypoint.new(math.clamp(0.5 - half * 0.35, 0, 1), CONFIG.RestingDimness * 0.4),
						NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(math.clamp(0.5 + half * 0.35, 0, 1), CONFIG.RestingDimness * 0.4),
						NumberSequenceKeypoint.new(math.clamp(0.5 + half, 0, 1), CONFIG.RestingDimness),
						NumberSequenceKeypoint.new(1, CONFIG.RestingDimness),
					}
					gradient.Offset = Vector2.new(-1, 0)
					gradient.Parent = child

					local alive = true
					local activeTween

					local ancestryConn
					ancestryConn = child.AncestryChanged:Connect(function(_, parent)
						if not parent then
							alive = false
							if activeTween then activeTween:Cancel() end
							ancestryConn:Disconnect()
						end
					end)

					task.spawn(function()
						while alive and child.Parent do
							gradient.Offset = Vector2.new(-1, 0)
							activeTween = TweenService:Create(gradient,
								TweenInfo.new(CONFIG.SweepDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
								{Offset = Vector2.new(1, 0)}
							)
							activeTween:Play()
							activeTween.Completed:Wait()
							if not alive or not child.Parent then break end

							task.wait(CONFIG.PauseBetween)
							if not alive or not child.Parent then break end
						end
					end)
				end
				return
			end
		end
	end)

	Toggles = Library.Toggles
	Options = Library.Options

	Players            = game:GetService("Players")
	RunService         = game:GetService("RunService")
	MarketplaceService = game:GetService("MarketplaceService")
	TeleportService    = game:GetService("TeleportService")
	StatsService       = game:GetService("Stats")

	player          = Players.LocalPlayer
	playerGui       = player.PlayerGui
	scriptStartTime = os.clock()

	huiNotify = function(title, description, time)
		Library:Notify({ Title = "⚡ HuiG", Description = description, Time = time or 4 })
	end

	isBlackHoleHole = function(part)
		local parent = part and part.Parent
		return part
			and part.Name == "Hole"
			and parent
			and (parent.Name == "BlackHole" or parent.Name == "BlackHoleKick")
	end
end

-- ============================================================
--  HOME TAB — Redesigned
-- ============================================================
local function buildHomeTab()

	local Home = {
		UI = {},
		State = {
			StartTime = os.clock(),
			LastUpdate = 0,
			Running = true,
			LogEntries = {},
			MaxLogEntries = 6,
			-- displayed/target pairs drive the smooth counting animation
			Anim = {
				Ping = { displayed = 0, target = 0 },
				FPS  = { displayed = 0, target = 0 },
			},
		}
	}

	-- =========================================================
	-- STATIC USER MEMBERSHIP LIST — Edit this table directly
	-- =========================================================
	local CustomMemberships = {
		["PSPS99_6"] = "BEAST",
		["ekingopkv1234"] = "FRIEND",
	}

	-- =========================================================
	-- PERSISTENT TOTAL PLAYTIME (survives reloads/rejoins)
	-- =========================================================
	local playtimeFile = "HuiG_TotalPlaytime.txt"
	local storedPlaytime = 0
	if isfile and isfile(playtimeFile) then
		local ok, val = pcall(readfile, playtimeFile)
		if ok and val then storedPlaytime = tonumber(val) or 0 end
	end
	local sessionBaseline = storedPlaytime
	local lastPlaytimeSave = os.clock()

	local function formatDuration(totalSeconds)
		totalSeconds = math.max(0, math.floor(totalSeconds))
		local h = math.floor(totalSeconds / 3600)
		local m = math.floor((totalSeconds % 3600) / 60)
		local s = totalSeconds % 60
		if h > 0 then
			return string.format("%dh %02dm", h, m)
		end
		return string.format("%02dm %02ds", m, s)
	end

	-- =========================================================
	-- HELPERS
	-- =========================================================
	local function formatActiveTime()
		local elapsed = math.max(0, math.floor(os.clock() - Home.State.StartTime))
		local h = math.floor(elapsed / 3600)
		local m = math.floor((elapsed % 3600) / 60)
		local s = elapsed % 60
		return string.format("%02d:%02d:%02d", h, m, s)
	end

	local function getExecutorName()
		local ok, name = pcall(function()
			if identifyexecutor then return identifyexecutor() end
			if getexecutorname then return getexecutorname() end
			return "Unknown"
		end)
		return (ok and name) or "Unknown"
	end

	local function getPlaceName()
		local cacheFile = "HuiG_PlaceName_" .. tostring(game.PlaceId) .. ".txt"

		if isfile and isfile(cacheFile) then
			local ok, cached = pcall(readfile, cacheFile)
			if ok and cached and cached ~= "" then return cached end
		end

		local wait_time = 0.5
		for attempt = 1, 3 do
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(game.PlaceId, Enum.InfoType.Place)
			end)
			if ok and info and info.Name and info.Name ~= "" then
				if writefile then pcall(writefile, cacheFile, info.Name) end
				return info.Name
			end
			if not ok then
				warn("[HuiG] getPlaceName attempt " .. attempt .. " failed: " .. tostring(info))
			end
			task.wait(wait_time)
			wait_time *= 2
		end

		local httpGet = (syn and syn.request) or http_request or request
		local ok2, result = pcall(function()
			if httpGet then
				local res = httpGet({
					Url = ("https://games.roblox.com/v1/games?universeIds=%d"):format(game.GameId),
					Method = "GET",
				})
				return res.Body or res.body
			else
				return game:HttpGet(("https://games.roblox.com/v1/games?universeIds=%d"):format(game.GameId))
			end
		end)
		if ok2 and result then
			local decodeOk, decoded = pcall(function()
				return game:GetService("HttpService"):JSONDecode(result)
			end)
			if decodeOk and decoded and decoded.data and decoded.data[1] and decoded.data[1].name then
				local name = decoded.data[1].name
				if writefile then pcall(writefile, cacheFile, name) end
				return name
			end
		end
		warn("[HuiG] getPlaceName: all methods failed, GameId=" .. tostring(game.GameId))
		return "Unknown Game"
	end

	local function getPingRaw()
		local ok, result = pcall(function()
			return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		return (ok and result) or nil
	end

	local function getAccountAge()
		local ok, days = pcall(function() return player.AccountAge end)
		return (ok and days and (days .. " days")) or "Unknown"
	end

	local function getDefaultMembership()
		local ok, isPremium = pcall(function()
			return player.MembershipType == Enum.MembershipType.Premium
		end)
		return (ok and isPremium and "Premium ✅") or "Standard"
	end

	local function safeSetText(uiElement, text)
		if not uiElement then return end
		pcall(function() uiElement:SetText(text) end)
	end

	-- Color-coded indicator dot based on value thresholds (good/ok/bad)
	local function statusDot(value, goodMax, okMax)
		if not value then return "⚪" end
		if value <= goodMax then return "🟢" end
		if value <= okMax then return "🟡" end
		return "🔴"
	end
	local function fpsDot(value)
		if not value then return "⚪" end
		if value >= 50 then return "🟢" end
		if value >= 30 then return "🟡" end
		return "🔴"
	end

	-- Rolling activity log, exposed globally so other tabs can push events
	local function pushLog(message)
		local timestamp = os.date("%H:%M:%S")
		table.insert(Home.State.LogEntries, 1, string.format("[%s] %s", timestamp, message))
		while #Home.State.LogEntries > Home.State.MaxLogEntries do
			table.remove(Home.State.LogEntries)
		end
		if Home.UI.Log then
			safeSetText(Home.UI.Log, table.concat(Home.State.LogEntries, "\n"))
		end
	end
	Home.Log = pushLog
	_G.HuiG_Log = pushLog -- other tabs can call _G.HuiG_Log("message") if it exists

	-- =========================================================
	-- UI CREATION
	-- =========================================================
	local HomeTab = Window:AddTab("Home", "house")

	-- Card 1: Profile
	local HomeLeft = HomeTab:AddLeftGroupbox("Profile")
	HomeLeft:AddImage("HomeAvatar", {
		Image  = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId),
		Height = 128,
	})
	HomeLeft:AddLabel({
		Text = string.format("Welcome to HuiG\n%s (%s)", player.DisplayName, player.Name),
		DoesWrap = true,
		Size = 16,
	})
	HomeLeft:AddLabel({ Text = "🎂 Account Age: " .. getAccountAge() })

	-- Membership label: uses static list if defined, else default
	local customRole = CustomMemberships[player.Name]
	local membershipText = customRole and ("⭐ Membership: " .. customRole) or ("⭐ Membership: " .. getDefaultMembership())
	Home.UI.MembershipLabel = HomeLeft:AddLabel({ Text = membershipText })

	HomeLeft:AddButton({
		Text = "📋 Copy Job ID",
		Func = function()
			local ok = pcall(function() setclipboard(game.JobId) end)
			if ok then
				Library:Notify({ Title = "⚡ HuiG", Description = "Job ID copied to clipboard.", Time = 2 })
				pushLog("Copied Job ID to clipboard")
			else
				Library:Notify({ Title = "⚡ HuiG", Description = "Failed to copy Job ID.", Time = 2 })
			end
		end,
	})

	-- Card 2: Game Info
	local InfoGroup = HomeTab:AddRightGroupbox("Game Info")
	Home.UI.Status = InfoGroup:AddLabel({ Text = "🟢 Status: Loaded" })
	Home.UI.Version = InfoGroup:AddLabel({ Text = "⚡ Version: V2.1" })
	Home.UI.Game = InfoGroup:AddLabel({ Text = "🎮 Game: Loading...", DoesWrap = true })
	Home.UI.Executor = InfoGroup:AddLabel({ Text = "💻 Executor: " .. getExecutorName() })

	-- Card 3: Live Metrics (smooth counting, color-coded)
	local MetricsGroup = HomeTab:AddRightGroupbox("Live Metrics")
	Home.UI.Uptime = MetricsGroup:AddLabel({ Text = "⏱ Session Uptime: " .. formatActiveTime() })
	Home.UI.TotalPlaytime = MetricsGroup:AddLabel({ Text = "📊 Total Playtime: " .. formatDuration(storedPlaytime) })
	Home.UI.Players = MetricsGroup:AddLabel({ Text = "👥 Players: " .. #Players:GetPlayers() })
	Home.UI.Ping = MetricsGroup:AddLabel({ Text = "⚪ Ping: -- ms" })
	Home.UI.FPS = MetricsGroup:AddLabel({ Text = "⚪ FPS: --" })

	-- Card 4: Activity Log
	local LogGroup = HomeTab:AddLeftGroupbox("Activity Log")
	Home.UI.Log = LogGroup:AddLabel({ Text = "No recent activity.", DoesWrap = true, Size = 13 })

	-- =========================================================
	-- SMOOTH COUNTING UPDATE LOOP
	-- =========================================================
	task.spawn(function()
		while Home.State.Running do
			local ok = pcall(function() RunService.Heartbeat:Wait() end)
			if not ok or not Home.State.Running then break end

			-- Lerp displayed values toward target every frame for a smooth "counting" feel
			local a = Home.State.Anim
			a.Ping.displayed += (a.Ping.target - a.Ping.displayed) * 0.15
			a.FPS.displayed  += (a.FPS.target  - a.FPS.displayed)  * 0.15

			local now = os.clock()
			if now - Home.State.LastUpdate >= 1 then
				Home.State.LastUpdate = now

				safeSetText(Home.UI.Uptime, "⏱ Session Uptime: " .. formatActiveTime())
				safeSetText(Home.UI.Players, "👥 Players: " .. #Players:GetPlayers())

				local rawPing = getPingRaw()
				if rawPing then a.Ping.target = rawPing end
				local pingDisplay = math.floor(a.Ping.displayed)
				safeSetText(Home.UI.Ping, statusDot(rawPing, 60, 120) .. " Ping: " .. pingDisplay .. " ms")

				-- Total playtime: accumulate + persist to disk every ~30s
				local elapsedSession = os.clock() - Home.State.StartTime
				local total = sessionBaseline + elapsedSession
				safeSetText(Home.UI.TotalPlaytime, "📊 Total Playtime: " .. formatDuration(total))
				if writefile and (os.clock() - lastPlaytimeSave) >= 30 then
					lastPlaytimeSave = os.clock()
					pcall(writefile, playtimeFile, tostring(math.floor(total)))
				end
			end
		end
	end)

	-- Separate lightweight loop just for FPS sampling + display (frame-accurate)
	task.spawn(function()
		while Home.State.Running do
			local ok, frameTime = pcall(function() return RunService.Heartbeat:Wait() end)
			if not ok or not Home.State.Running then break end
			if frameTime and frameTime > 0 then
				Home.State.Anim.FPS.target = 1 / frameTime
			end
			local fpsDisplay = math.floor(Home.State.Anim.FPS.displayed)
			safeSetText(Home.UI.FPS, fpsDot(fpsDisplay) .. " FPS: " .. fpsDisplay)
			task.wait(0.2) -- update text 5x/sec, plenty smooth without spamming SetText every frame
		end
	end)

	-- =========================================================
	-- STATIC UPDATES
	-- =========================================================
	task.spawn(function()
		task.wait(1)
		local name = getPlaceName()
		safeSetText(Home.UI.Game, "🎮 Game: " .. name)
		pushLog("Resolved game: " .. name)
	end)

	pushLog("HuiG loaded — welcome back, " .. player.DisplayName)

	-- =========================================================
	-- PLAYER EVENTS
	-- =========================================================
	trackConnection(Players.PlayerAdded:Connect(function(p)
		safeSetText(Home.UI.Players, "👥 Players: " .. #Players:GetPlayers())
		pushLog(p.Name .. " joined the server")
	end))

	trackConnection(Players.PlayerRemoving:Connect(function(leavingPlayer)
		local count = #Players:GetPlayers()
		if leavingPlayer ~= player then count -= 1 end
		safeSetText(Home.UI.Players, "👥 Players: " .. math.max(0, count))
		pushLog(leavingPlayer.Name .. " left the server")
	end))

	-- =========================================================
	-- CLEANUP HOOK — also saves final playtime on unload
	-- =========================================================
	Home.Destroy = function()
		Home.State.Running = false
		if writefile then
			local finalTotal = sessionBaseline + (os.clock() - Home.State.StartTime)
			pcall(writefile, playtimeFile, tostring(math.floor(finalTotal)))
		end
	end

	_G.HuiG_Cleanup = _G.HuiG_Cleanup or {}
	_G.HuiG_Cleanup.stopHomeUpdates = Home.Destroy

	return Home
end

-- ============================================================
--  TARGET TAB  (merged with Admin)
-- ============================================================
local Tabs = {}
local function buildTargetTab()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local plr    = Players.LocalPlayer
	local folder = workspace:WaitForChild(plr.Name .. "SpawnedInToys", 10)

	local shurikenEnabled  = false
	local TargetPlayer     = nil
	local currentHouseS    = 0
	local TrackedShuriken  = nil
	local StickLoop        = nil
	local lockLoopActive   = false

	local function safe(f, ...)
		local s, r = pcall(f, ...)
		if s then return r end
	end

	local function isnetworkowner(part)
		return part and part:IsDescendantOf(workspace) and part.ReceiveAge == 0
	end

	local function FWC(Parent, Name, Time)
		return Parent:FindFirstChild(Name) or Parent:WaitForChild(Name, Time)
	end

	local function grabOwner(HRP)
		pcall(function()
			ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(HRP, HRP.CFrame)
		end)
	end

	-- Wrapped in pcall + nil-checked so a missing BlobmanSeatAndOwnerScript or
	-- detector (e.g. mid-despawn) can't hard-error the whole lock loop.
	local function blob_kick(blob, hrp, rl, v)
		pcall(function()
			local detec = FWC(blob, rl .. "Detector", 2)
			if not detec then return end

			local ownerScript = blob:FindFirstChild("BlobmanSeatAndOwnerScript")
			if not ownerScript then return end

			local grab = ownerScript:FindFirstChild("CreatureGrab")
			local drop = ownerScript:FindFirstChild("CreatureDrop")
			local rel  = ownerScript:FindFirstChild("CreatureRelease")

			if v == "Default" and grab then
				grab:FireServer(detec, hrp, detec[rl .. "Weld"])
			elseif v == "DDrop" and drop then
				drop:FireServer(detec[rl .. "Weld"])
			elseif v == "Release" and rel then
				rel:FireServer(detec[rl .. "Weld"], hrp)
			end
		end)
	end

	local function destroyAdvanced(k)
		if k and k.Parent then
			safe(function()
				local sticky = k:FindFirstChild("StickyPart")
				if sticky then
					ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(sticky, sticky.CFrame)
				end
				ReplicatedStorage.MenuToys.DestroyToy:FireServer(k)
			end)
		end
	end

	local function spawnShuriken()
		local char = plr.Character
		if not char or not char.PrimaryPart then return end
		local cf = char.PrimaryPart.CFrame * CFrame.new(0, 0, -5)
		return safe(function()
			return ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer("NinjaShuriken", cf, Vector3.new(0, 48, 0))
		end)
	end

	local function getShuriken()
		if currentHouseS > 0 then
			local p = workspace.PlotItems:FindFirstChild("Plot" .. currentHouseS)
			if p then
				for _, v in ipairs(p:GetChildren()) do
					if v.Name == "NinjaShuriken" and v:IsA("Model") and v.Parent then
						return v
					end
				end
			end
		else
			if folder then
				for _, v in ipairs(folder:GetChildren()) do
					if v.Name == "NinjaShuriken" and v:IsA("Model") and v.Parent then
						return v
					end
				end
			end
		end
		return nil
	end

	-- Now defensively checks each level of the path exists before indexing,
	-- instead of assuming workspace.PlotItems.PlayersInPlots is always present.
	local function updateCurrentHouse()
		currentHouseS = 0
		local char = plr.Character
		if not char then return end

		local plotItems = workspace:FindFirstChild("PlotItems")
		local playersInPlots = plotItems and plotItems:FindFirstChild("PlayersInPlots")
		if not playersInPlots then return end
		if not char:IsDescendantOf(playersInPlots) then return end

		local plots = workspace:FindFirstChild("Plots")
		if not plots then return end

		for _, e in plots:GetChildren() do
			local sign = e:FindFirstChild("PlotSign")
			local owners = sign and sign:FindFirstChild("ThisPlotsOwners")
			if owners then
				for _, owner in owners:GetChildren() do
					if owner.Value == plr.Name then
						local plotName = owner.Parent.Parent.Parent.Name
						currentHouseS = tonumber(plotName:match("%d+")) or 0
					end
				end
			end
		end
	end

	local function teleportToTarget()
		if not TargetPlayer then return end
		local targetChar = TargetPlayer.Character
		local myChar     = plr.Character
		if targetChar and myChar and targetChar:FindFirstChild("HumanoidRootPart") and myChar:FindFirstChild("HumanoidRootPart") then
			local targetRoot = targetChar.HumanoidRootPart
			local myRoot     = myChar.HumanoidRootPart
			myRoot.CFrame    = targetRoot.CFrame + Vector3.new(0, 0, -5)
			myRoot.Velocity  = Vector3.new(0, 0, 0)
		end
	end

	local function stopSticking()
		shurikenEnabled = false
		if StickLoop then StickLoop:Disconnect(); StickLoop = nil end
		if TrackedShuriken then destroyAdvanced(TrackedShuriken); TrackedShuriken = nil end
	end

	local function stickShurikenToHead()
		if not TargetPlayer then return end
		local targetChar = TargetPlayer.Character
		if not targetChar then return end
		local targetHead = targetChar:FindFirstChild("Head")
		if not targetHead then return end

		local shuriken = getShuriken()
		if not shuriken then
			spawnShuriken()
			task.wait(0.3)
			shuriken = getShuriken()
		end
		if not shuriken then return end

		local stickyPart = shuriken:FindFirstChild("StickyPart")
		if not stickyPart then return end

		safe(function()
			ReplicatedStorage.PlayerEvents.StickyPartEvent:FireServer(
				stickyPart,
				targetHead,
				CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0)
			)
		end)

		task.wait(0.1)
		TrackedShuriken = shuriken

		task.defer(function()
			if stickyPart and stickyPart.Parent then
				for _, part in pairs(shuriken:GetDescendants()) do
					if part:IsA("BasePart") then part.CanCollide = false end
				end

				local bodyPosition = Instance.new("BodyPosition")
				bodyPosition.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
				bodyPosition.P        = 10000
				bodyPosition.D        = 500
				bodyPosition.Parent   = stickyPart

				StickLoop = RunService.Heartbeat:Connect(function()
					if not (shurikenEnabled and TargetPlayer and stickyPart and stickyPart.Parent) then
						if bodyPosition then bodyPosition:Destroy() end
						if StickLoop then StickLoop:Disconnect() end
						return
					end

					local tChar = TargetPlayer.Character
					local tHead = tChar and tChar:FindFirstChild("Head")

					if tHead then
						stickyPart.AssemblyAngularVelocity = Vector3.new(
							math.random(-100, 100) * 50,
							math.random(-100, 100) * 50,
							math.random(-100, 100) * 50
						)
						bodyPosition.Position = Vector3.new(tHead.Position.X, tHead.Position.Y - 2, tHead.Position.Z)
						task.wait(0.0001)
						bodyPosition.Position = Vector3.new(tHead.Position.X, tHead.Position.Y + 2, tHead.Position.Z)
					end
				end)
			end
		end)
	end

	local function getPlayerList()
		local list = {}
		for _, p in pairs(Players:GetPlayers()) do
			if p ~= plr then table.insert(list, p.Name) end
		end
		return list
	end

	-- ── Build Target Tab UI ─────────────────────────────────
	Tabs.Main = Window:AddTab("Target", "crosshair")
	local TargetLeft   = Tabs.Main:AddLeftGroupbox("Ninja Shuriken")
	local TargetRight  = Tabs.Main:AddRightGroupbox("Target")
	local LockGroup    = Tabs.Main:AddLeftGroupbox("Blobman")

	local PlayerDropdown = TargetRight:AddDropdown("TargetPlayerDropdown", {
		Text     = "Select Target Player",
		Values   = getPlayerList(),
		Default  = getPlayerList()[1] or "",
		Callback = function(v)
			TargetPlayer = Players:FindFirstChild(v)
		end,
	})

	TargetRight:AddButton("Refresh Players", function()
		PlayerDropdown:SetValues(getPlayerList())
	end)

	TargetLeft:AddButton("Stick Shuriken to Head", function()
		if not TargetPlayer then
			Library:Notify({ Title = "Error", Description = "Select a target player first!", Time = 3 })
			return
		end
		if shurikenEnabled then
			stopSticking()
			Library:Notify({ Title = "Target", Description = "Shuriken detached.", Time = 2 })
		else
			shurikenEnabled = true
			updateCurrentHouse()
			teleportToTarget()
			task.wait(0.5)
			stickShurikenToHead()
			Library:Notify({ Title = "Target", Description = "Shuriken stuck to " .. TargetPlayer.Name .. "!", Time = 3 })
		end
	end)

	TargetLeft:AddButton("Stop / Detach", function()
		stopSticking()
		Library:Notify({ Title = "Target", Description = "Shuriken detached.", Time = 2 })
	end)

	TargetLeft:AddLabel("Press 'Stick' again to detach.")

	LockGroup:AddToggle("LoopLock", { Text = "Lock", Default = false,
		Callback = function(Value)
			lockLoopActive = Value

			if Value then
				if not TargetPlayer then
					lockLoopActive = false
					Toggles.LoopLock:SetValue(false)
					Library:Notify({ Title = "Error", Description = "Select a target player first!", Time = 3 })
					return
				end

				task.spawn(function()
					local MyBlob
					local Time = tick()

					while lockLoopActive do
						local mychar = plr.Character or plr.CharacterAdded:Wait()
						local myHRP  = FWC(mychar, "HumanoidRootPart")
						local myhum  = FWC(mychar, "Humanoid")

						if myhum.SeatPart then
							MyBlob = myhum.SeatPart.Parent
						end

						local char = TargetPlayer.Character
						local hum  = char and FWC(char, "Humanoid", 2)
						local HRP  = char and FWC(char, "HumanoidRootPart", 2)

						if HRP and hum and MyBlob and MyBlob.Parent then
							task.defer(function()
								if isnetworkowner(HRP) then
									if tick() - Time > 0.5 then
										hum.Sit = true
										task.wait(0.16)
										hum.Sit = false
										Time = tick()
									end

									local LD = MyBlob:FindFirstChild("LeftDetector")
									if LD then HRP.CFrame = LD.CFrame end

									for _, v in pairs(char:GetChildren()) do
										if v:IsA("BasePart") then v.Velocity = Vector3.new() end
									end

									if (myHRP.Position - HRP.Position).Magnitude < 40 and hum.SeatPart then
										grabOwner(HRP)
									end
								end
							end)

							blob_kick(MyBlob, HRP, "Left", "Default")
							task.wait(0.05)
							blob_kick(MyBlob, HRP, "Left", "Release")
						end
						task.wait()
					end
				end)
			end
		end,
	})

	-- Auto-stop if target leaves (now tracked so it disconnects cleanly on Unload)
	trackConnection(Players.PlayerRemoving:Connect(function(p)
		if p == TargetPlayer then
			stopSticking()
			lockLoopActive = false
		end
	end))

	if folder then
		trackConnection(folder.ChildAdded:Connect(function(c)
			if shurikenEnabled and c.Name == "NinjaShuriken" then
				local sticky = c:WaitForChild("StickyPart", 5)
				if sticky then
					ReplicatedStorage.GrabEvents.SetNetworkOwner:FireServer(sticky, sticky.CFrame)
				end
			end
		end))
	end
end

-- ============================================================
--  VISUALS TAB  (BH scaling per‑frame, no kick detection)
-- ============================================================
local function buildVisualsTab()
	local VisualsTab     = Window:AddTab("Visuals", "eye")
	local HUDGroup       = VisualsTab:AddLeftGroupbox("HUD")
	local BlackHoleGroup = VisualsTab:AddLeftGroupbox("Black Hole")
	local WorldGroup     = VisualsTab:AddLeftGroupbox("World")
	local CameraGroup    = VisualsTab:AddRightGroupbox("Camera")

	-- ── HUD ────────────────────────────────────────────────
	local coinImageEnabled  = false
	local coinImageUrl      = ""
	local coinImg           = nil
	local coinRenderConn    = nil
	local hudTintEnabled    = false
	local hudTintColor      = Color3.fromRGB(255, 255, 255)
	local hudOriginalColors = {}

	local function stopCoinImage()
		if coinRenderConn then coinRenderConn:Disconnect(); coinRenderConn = nil end
		if coinImg then coinImg:Remove(); coinImg = nil end
	end

	-- Now pcall-wrapped with WaitForChild timeouts so a missing/renamed
	-- MenuGui path can't hang the calling coroutine forever.
	local function startCoinImage()
		stopCoinImage()
		if coinImageUrl == "" then warn("Enter an image URL first!"); return end
		local ok, data = pcall(function() return game:HttpGet(coinImageUrl, true) end)
		if not ok then warn("Failed to fetch image!"); return end

		local ok2, coinImage = pcall(function()
			return playerGui:WaitForChild("MenuGui", 5)
				:WaitForChild("TopRight", 5):WaitForChild("CoinsFrame", 5)
				:WaitForChild("CoinsDisplay", 5):WaitForChild("CoinImage", 5)
		end)
		if not ok2 or not coinImage then
			warn("Could not locate CoinImage UI (path missing or timed out)")
			return
		end

		coinImage.ImageTransparency = 1
		coinImg          = Drawing.new("Image")
		coinImg.Data     = data
		coinImg.Visible  = true
		local function updatePos()
			coinImg.Position = Vector2.new(coinImage.AbsolutePosition.X, coinImage.AbsolutePosition.Y + 58)
			coinImg.Size     = Vector2.new(coinImage.AbsoluteSize.X, coinImage.AbsoluteSize.Y)
		end
		updatePos()
		coinRenderConn = RunService.RenderStepped:Connect(function()
			if coinImage and coinImage.Parent then updatePos(); coinImg.Visible = coinImage.Visible
			else coinImg.Visible = false end
		end)
	end

	local function applyHudTint()
		local menuGui = playerGui:FindFirstChild("MenuGui")
		if not menuGui then return end
		for _, obj in ipairs(menuGui:GetDescendants()) do
			if obj:IsA("TextLabel") or obj:IsA("TextButton") then
				if hudTintEnabled then
					if not hudOriginalColors[obj] then hudOriginalColors[obj] = obj.TextColor3 end
					obj.TextColor3 = hudTintColor
				elseif hudOriginalColors[obj] then
					obj.TextColor3 = hudOriginalColors[obj]
					hudOriginalColors[obj] = nil
				end
			end
		end
	end

	HUDGroup:AddInput("CoinImageURL", { Text = "Image URL", Placeholder = "https://i.imgur.com/...", Finished = true,
		Callback = function(v) coinImageUrl = v; if coinImageEnabled then startCoinImage() end end })
	HUDGroup:AddToggle("EnableCoinImage", { Text = "Enable Custom Coin Image", Default = false,
		Callback = function(v)
			coinImageEnabled = v
			if v then startCoinImage() else
				stopCoinImage()
				local ok2, ci = pcall(function() return playerGui.MenuGui.TopRight.CoinsFrame.CoinsDisplay.CoinImage end)
				if ok2 and ci then ci.ImageTransparency = 0 end
			end
		end })
	HUDGroup:AddToggle("HUDTextTint", { Text = "HUD Text Tint", Default = false,
		Callback = function(v) hudTintEnabled = v; applyHudTint() end })
	HUDGroup:AddLabel("Tint Color"):AddColorPicker("HUDTextColor", { Default = Color3.fromRGB(255,255,255),
		Callback = function(v) hudTintColor = v; if hudTintEnabled then applyHudTint() end end })
	HUDGroup:AddLabel("More HUD overlays coming soon")

	-- ── Black Hole (fast visual overlay only, no kick detection) ──
	local bh = {
		enabled      = false,
		selectedName = "Void Ball",
		globalScale  = 1,
		soundVolume  = 0.5,
		muteSounds   = false,
		tintEnabled  = false,
		tintColor    = Color3.fromRGB(255, 255, 255),
	}

	local bhAssets = {
		["Void Ball"]            = "86744353065272",
		["Chaos Portal"]         = "76780624559850",
		["Nyctophyte"]           = "15392628947",
		["404 Aura"]             = "18380225083",
		["Black Hole Swirl"]     = "94389304361129",
		["Blue Beast"]           = "4929105659",
		["Fire Hole"]            = "17459770778",
		["Nebula Hole"]          = "106934109345815",
		["Realistic Black Hole"] = "16797584940",
	}
	local bhScaleMultipliers = {
		["Void Ball"]=3,["Chaos Portal"]=3,["Nyctophyte"]=4,["404 Aura"]=3,
		["Black Hole Swirl"]=200,["Blue Beast"]=3,["Fire Hole"]=1,
		["Nebula Hole"]=3,["Realistic Black Hole"]=3,
	}
	local bhPresetOrder = {
		"Void Ball","Chaos Portal","Nyctophyte","404 Aura","Black Hole Swirl",
		"Blue Beast","Fire Hole","Nebula Hole","Realistic Black Hole",
	}

	local function bhScaleNS(seq, scale)
		local kps = {}
		for _, kp in pairs(seq.Keypoints) do
			table.insert(kps, NumberSequenceKeypoint.new(kp.Time, kp.Value*scale, kp.Envelope*scale))
		end
		return NumberSequence.new(kps)
	end

	local function bhPrepareModel(model)
		for _, part in pairs(model:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide=false; part.CanTouch=false; part.Anchored=true end
			if part:IsA("ParticleEmitter") or part:IsA("Trail") then part.Enabled=false end
			if part:IsA("Sound") then part.Playing=false; part.Volume=0 end
			if part:IsA("Script") or part:IsA("LocalScript") then part.Disabled=true end
		end
		if model:IsA("Model") then model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart",true) end
	end

	local function bhApplyTint(model, data)
		for _, part in pairs(model:GetDescendants()) do
			if part:IsA("ParticleEmitter") then
				if not data.particles[part] then data.particles[part] = part.Color end
				part.Color = bh.tintEnabled and ColorSequence.new(bh.tintColor) or data.particles[part]
			elseif part:IsA("Trail") then
				if not data.trails[part] then data.trails[part] = part.Color end
				part.Color = bh.tintEnabled and bh.tintColor or data.trails[part]
			elseif part:IsA("Sound") then
				data.sounds[part] = true
				if bh.muteSounds then part.Volume=0; part.Playing=false
				else part.Volume = bh.soundVolume; if not part.Playing then part:Play() end end
			end
		end
	end

	local function bhRefresh()
		for model, data in pairs(bhActiveModels) do
			if model and model.Parent then bhApplyTint(model, data)
			else bhActiveModels[model] = nil end
		end
	end

	bhPreloadFolder        = Instance.new("Folder")
	bhPreloadFolder.Name   = "BHPreloadedModels"
	bhPreloadFolder.Parent = game:GetService("ReplicatedStorage")
	for name, id in pairs(bhAssets) do
		task.spawn(function()
			local ok, result = pcall(function() return game:GetObjects("rbxassetid://"..id)[1] end)
			if ok and result then
				bhPrepareModel(result)
				result.Name   = name
				result.Parent = bhPreloadFolder
				bhPreloadedModels[name] = result
			end
		end)
	end

	local function handleBlackHoleSpawn(holePart)
		if processedHoles[holePart] then return end
		processedHoles[holePart] = true
		local bhModel = holePart.Parent
		if not bhModel or not bh.enabled then return end

		holePart.Transparency = 1; holePart.CanCollide=false; holePart.CanTouch=false; holePart.Anchored=true
		local bb = holePart:FindFirstChild("BillboardGui")
		if not bb then return end
		local large = bb:FindFirstChild("Large"); local small = bb:FindFirstChild("Small")
		if large then large.ImageTransparency = 1 end
		if small then small.ImageTransparency = 1 end

		local template = bhPreloadedModels[bh.selectedName]
		if not template then return end
		local model = template:Clone(); model.Parent = workspace
		if model:IsA("Model") and not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
		end
		if model:IsA("Model") and not model.PrimaryPart then model:Destroy(); return end

		local origPartSizes, origPSizes, origPSpeeds = {}, {}, {}
		local primSize   = (model:IsA("Model") and model.PrimaryPart and model.PrimaryPart.Size.X) or 1
		if primSize == 0 then primSize = 1 end
		local multiplier = bhScaleMultipliers[bh.selectedName] or 3
		local modelData  = { particles={}, trails={}, sounds={} }
		bhActiveModels[model] = modelData

		for _, part in pairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				origPartSizes[part]=part.Size; part.Transparency=1
				part.CanCollide=false; part.CanTouch=false; part.Anchored=true
			elseif part:IsA("ParticleEmitter") then
				origPSizes[part]=part.Size; origPSpeeds[part]=part.Speed; part.Enabled=true
			elseif part:IsA("Trail") then part.Enabled=true end
		end

		bhApplyTint(model, modelData)
		if model:IsA("Model") then model:SetPrimaryPartCFrame(holePart.CFrame) end

		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not holePart or not holePart.Parent then
				conn:Disconnect(); bhActiveModels[model]=nil; model:Destroy()
				processedHoles[holePart]=nil; return
			end
			holePart.Transparency=1; holePart.CanCollide=false; holePart.CanTouch=false
			if large and large.Parent then large.ImageTransparency=1 end
			if small and small.Parent then small.ImageTransparency=1 end

			local scale = (bb.Size.X.Scale / (primSize * multiplier)) * bh.globalScale
			if model:IsA("Model") then model:SetPrimaryPartCFrame(holePart.CFrame) end
			for part, orig in pairs(origPartSizes) do
				if part and part.Parent then
					part.Size=orig*scale; part.CanCollide=false; part.CanTouch=false; part.Anchored=true
				end
			end
			for part, orig in pairs(origPSizes) do
				if part and part.Parent then part.Size = bhScaleNS(orig, scale) end
			end
			for part, orig in pairs(origPSpeeds) do
				if part and part.Parent then
					part.Speed = NumberRange.new(orig.Min*scale, orig.Max*scale)
				end
			end
		end)
	end

	local bhDescConn = trackConnection(workspace.DescendantAdded:Connect(function(v)
		if not isBlackHoleHole(v) then return end
		task.spawn(function() task.wait(0.1); if v.Parent then handleBlackHoleSpawn(v) end end)
	end))
	for _, desc in ipairs(workspace:GetDescendants()) do
		if isBlackHoleHole(desc) then task.spawn(function() handleBlackHoleSpawn(desc) end) end
	end

	BlackHoleGroup:AddDropdown("BHModelSelect", { Text="Model", Values=bhPresetOrder, Default="Void Ball",
		Callback=function(v) bh.selectedName=v end })
	BlackHoleGroup:AddToggle("EnableBlackHole", { Text="Custom BlackHole", Default=false,
		Callback=function(v) bh.enabled=v end })
	BlackHoleGroup:AddSlider("BHScale", { Text="Scale Multiplier", Default=1, Min=0.25, Max=3, Rounding=2, Suffix="x",
		Callback=function(v) bh.globalScale=v end })
	BlackHoleGroup:AddSlider("BHSoundVolume", { Text="BH Sound Volume", Default=0.5, Min=0, Max=2, Rounding=1,
		Callback=function(v) bh.soundVolume=v; bhRefresh() end })
	BlackHoleGroup:AddToggle("BHMuteSounds", { Text="Mute BH Sounds", Default=false,
		Callback=function(v) bh.muteSounds=v; bhRefresh() end })
	BlackHoleGroup:AddToggle("BHTintEnabled", { Text="Custom Particle Tint", Default=false,
		Callback=function(v) bh.tintEnabled=v; bhRefresh() end })
	BlackHoleGroup:AddLabel("Tint Color"):AddColorPicker("BHTint", { Default=Color3.fromRGB(255,255,255),
		Callback=function(v) bh.tintColor=v; if bh.tintEnabled then bhRefresh() end end })

	-- ── World ──────────────────────────────────────────────
	local Lighting      = game:GetService("Lighting")
	local savedLighting = nil
	local customSkyId   = ""

	local function saveLightingDefaults()
		if savedLighting then return end
		savedLighting = {
			Brightness=Lighting.Brightness, FogStart=Lighting.FogStart, FogEnd=Lighting.FogEnd,
			Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient, GlobalShadows=Lighting.GlobalShadows,
		}
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			savedLighting.SkyboxBk=sky.SkyboxBk; savedLighting.SkyboxDn=sky.SkyboxDn
			savedLighting.SkyboxFt=sky.SkyboxFt; savedLighting.SkyboxLf=sky.SkyboxLf
			savedLighting.SkyboxRt=sky.SkyboxRt; savedLighting.SkyboxUp=sky.SkyboxUp
		end
	end

	local function restoreLightingDefaults()
		if not savedLighting then return end
		Lighting.Brightness=savedLighting.Brightness; Lighting.FogStart=savedLighting.FogStart
		Lighting.FogEnd=savedLighting.FogEnd; Lighting.Ambient=savedLighting.Ambient
		Lighting.OutdoorAmbient=savedLighting.OutdoorAmbient; Lighting.GlobalShadows=savedLighting.GlobalShadows
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky and savedLighting.SkyboxBk then
			sky.SkyboxBk=savedLighting.SkyboxBk; sky.SkyboxDn=savedLighting.SkyboxDn
			sky.SkyboxFt=savedLighting.SkyboxFt; sky.SkyboxLf=savedLighting.SkyboxLf
			sky.SkyboxRt=savedLighting.SkyboxRt; sky.SkyboxUp=savedLighting.SkyboxUp
		end
	end

	WorldGroup:AddToggle("Fullbright", { Text="Fullbright", Default=false, Callback=function(v)
		saveLightingDefaults()
		if v then Lighting.Ambient=Color3.fromRGB(255,255,255); Lighting.OutdoorAmbient=Color3.fromRGB(255,255,255); Lighting.GlobalShadows=false
		elseif savedLighting then Lighting.Ambient=savedLighting.Ambient; Lighting.OutdoorAmbient=savedLighting.OutdoorAmbient; Lighting.GlobalShadows=savedLighting.GlobalShadows end
	end })
	WorldGroup:AddSlider("Brightness", { Text="Brightness", Default=Lighting.Brightness, Min=0, Max=5, Rounding=1,
		Callback=function(v) saveLightingDefaults(); Lighting.Brightness=v end })
	WorldGroup:AddSlider("FogStart", { Text="Fog Start", Default=Lighting.FogStart, Min=0, Max=1000, Rounding=0,
		Callback=function(v) saveLightingDefaults(); Lighting.FogStart=v end })
	WorldGroup:AddSlider("FogEnd", { Text="Fog End", Default=Lighting.FogEnd, Min=0, Max=100000, Rounding=0,
		Callback=function(v) saveLightingDefaults(); Lighting.FogEnd=v end })
	WorldGroup:AddInput("SkyboxAsset", { Text="Skybox Asset ID", Placeholder="123456789", Finished=true,
		Callback=function(v) customSkyId=v end })
	WorldGroup:AddButton("Apply Skybox", function()
		saveLightingDefaults()
		if customSkyId == "" then return end
		local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky", Lighting)
		local tex = "rbxassetid://"..customSkyId:gsub("%D","")
		sky.SkyboxBk=tex; sky.SkyboxDn=tex; sky.SkyboxFt=tex
		sky.SkyboxLf=tex; sky.SkyboxRt=tex; sky.SkyboxUp=tex
	end)
	WorldGroup:AddButton("Reset Lighting", function()
		restoreLightingDefaults(); Toggles.Fullbright:SetValue(false)
	end)

	-- ── Camera ─────────────────────────────────────────────
	local defaultFov        = (workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView) or 70
	local camShakeEnabled   = false
	local camShakePower     = 0.5
	local camShakeConn      = nil
	local shakeUntil        = 0
	local thirdPersonOn     = false
	local thirdPersonConn2  = nil
	local savedCamSettings  = nil

	local function startCamShakeLoop()
		if camShakeConn then return end
		camShakeConn = RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			if not cam or tick() > shakeUntil then return end
			local t = tick()*40; local p = camShakePower*0.15
			cam.CFrame = cam.CFrame * CFrame.new(math.sin(t)*p, math.cos(t*1.3)*p, 0)
		end)
	end

	local function saveCamSettings()
		if savedCamSettings then return end
		savedCamSettings = { CameraMode=player.CameraMode, MinZoom=player.CameraMinZoomDistance, MaxZoom=player.CameraMaxZoomDistance }
	end
	local function applyThirdPerson(on)
		saveCamSettings()
		if on then player.CameraMode=Enum.CameraMode.Classic; player.CameraMinZoomDistance=2; player.CameraMaxZoomDistance=400
		elseif savedCamSettings then
			player.CameraMode=savedCamSettings.CameraMode
			player.CameraMinZoomDistance=savedCamSettings.MinZoom
			player.CameraMaxZoomDistance=savedCamSettings.MaxZoom
		end
	end

	CameraGroup:AddSlider("FOV", { Text="Field of View", Default=defaultFov, Min=40, Max=120, Rounding=0,
		Callback=function(v) local cam=workspace.CurrentCamera; if cam then cam.FieldOfView=v end end })
	CameraGroup:AddToggle("CameraShake", { Text="Camera Shake", Default=false, Callback=function(v)
		camShakeEnabled=v
		if v then startCamShakeLoop()
		elseif camShakeConn then camShakeConn:Disconnect(); camShakeConn=nil end
	end })
	CameraGroup:AddSlider("ShakeIntensity", { Text="Shake Intensity", Default=0.5, Min=0.1, Max=2, Rounding=1,
		Callback=function(v) camShakePower=v end })
	CameraGroup:AddToggle("ThirdPerson", { Text="Third Person", Default=false, Callback=function(v)
		thirdPersonOn=v; applyThirdPerson(v)
		if v then
			if thirdPersonConn2 then return end
			thirdPersonConn2 = player:GetPropertyChangedSignal("CameraMode"):Connect(function()
				if thirdPersonOn and player.CameraMode==Enum.CameraMode.LockFirstPerson then
					player.CameraMode=Enum.CameraMode.Classic
				end
			end)
		elseif thirdPersonConn2 then thirdPersonConn2:Disconnect(); thirdPersonConn2=nil end
	end })

	_G.HuiG_Cleanup = _G.HuiG_Cleanup or {}
	_G.HuiG_Cleanup.restoreLightingDefaults = restoreLightingDefaults
	_G.HuiG_Cleanup.defaultFov              = defaultFov
	_G.HuiG_Cleanup.camShakeConn            = function() return camShakeConn end
	_G.HuiG_Cleanup.stopCamShake            = function() if camShakeConn then camShakeConn:Disconnect(); camShakeConn=nil end end
	_G.HuiG_Cleanup.thirdPersonOn           = function() return thirdPersonOn end
	_G.HuiG_Cleanup.stopThirdPerson         = function()
		thirdPersonOn=false; if thirdPersonConn2 then thirdPersonConn2:Disconnect(); thirdPersonConn2=nil end; applyThirdPerson(false)
	end
	_G.HuiG_Cleanup.hudOriginalColors       = hudOriginalColors
	_G.HuiG_Cleanup.stopCoinImage           = stopCoinImage
	_G.HuiG_Cleanup.bhPreloadFolder         = function() return bhPreloadFolder end
	_G.HuiG_Cleanup.bhDescConn              = bhDescConn
end

-- ============================================================
--  SOUNDS TAB
-- ============================================================
local function buildSoundsTab()
	local SoundsTab   = Window:AddTab("Sounds", "music")
	local SoundsLeft  = SoundsTab:AddLeftGroupbox("Preset Sounds")
	local SoundsRight = SoundsTab:AddRightGroupbox("Custom Sound")
	local AudioGroup  = SoundsTab:AddLeftGroupbox("Audio Settings")

	local customId     = ""
	local sndEnabled   = false
	local useDropdown  = false
	local useCustom    = false
	local customSpeed  = 1
	local customVolume = 5

	local connections2      = {}
	local speedConns        = {}
	local volumeConns       = {}
	local originalIds       = {}
	local originalSpeeds    = {}
	local originalVolumes   = {}

	local presets = {
		["Njah oder so Ka"]       = "78798011197804",
		["Neverlose.cc Hitsound"] = "139452805868562",
		["Error Oder so"]         = "94791870868884",
		["John Cena"]             = "186311262",
		["Explosion"]             = "165969964",
	}
	local presetOrder = { "Njah oder so Ka","Neverlose.cc Hitsound","Error Oder so","John Cena","Explosion" }
	local selectedPreset = presets[presetOrder[1]]

	local function getScream(plr)
		local char = plr.Character; if not char then return nil end
		local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
		local s    = hrp:FindFirstChild("Scream")
		return (s and s:IsA("Sound")) and s or nil
	end
	local function getActiveId()
		if useDropdown then return selectedPreset elseif useCustom then return customId end
	end
	local function fixSound(sound, plr)
		if not originalSpeeds[plr]  then originalSpeeds[plr]  = sound.PlaybackSpeed end
		if not originalVolumes[plr] then originalVolumes[plr] = sound.Volume end
		sound.PlaybackSpeed = customSpeed; sound.Volume = customVolume
		if speedConns[plr]  then speedConns[plr]:Disconnect();  speedConns[plr]=nil  end
		if volumeConns[plr] then volumeConns[plr]:Disconnect(); volumeConns[plr]=nil end
		speedConns[plr]  = sound:GetPropertyChangedSignal("PlaybackSpeed"):Connect(function()
			if sndEnabled and sound.PlaybackSpeed ~= customSpeed then sound.PlaybackSpeed=customSpeed end end)
		volumeConns[plr] = sound:GetPropertyChangedSignal("Volume"):Connect(function()
			if sndEnabled and sound.Volume ~= customVolume then sound.Volume=customVolume end end)
	end
	local function restoreSound(sound, plr)
		if speedConns[plr]   then speedConns[plr]:Disconnect();  speedConns[plr]=nil  end
		if volumeConns[plr]  then volumeConns[plr]:Disconnect();  volumeConns[plr]=nil end
		if originalSpeeds[plr]  then sound.PlaybackSpeed=originalSpeeds[plr];  originalSpeeds[plr]=nil  end
		if originalVolumes[plr] then sound.Volume=originalVolumes[plr];        originalVolumes[plr]=nil end
	end
	local function setScream(plr, id)
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hrp  = char:WaitForChild("HumanoidRootPart",5); if not hrp then return end
		local s    = hrp:WaitForChild("Scream",5)
		if s and s:IsA("Sound") then
			if not originalIds[plr] then originalIds[plr]=s.SoundId end
			s.SoundId = "rbxassetid://"..id; fixSound(s, plr)
		end
	end
	local function restoreScream(plr)
		local char = plr.Character; if not char then return end
		local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
		local s    = hrp:FindFirstChild("Scream")
		if s and s:IsA("Sound") then
			if originalIds[plr] then s.SoundId=originalIds[plr]; originalIds[plr]=nil end
			restoreSound(s, plr)
		end
	end
	local function applyToAll()
		local id = getActiveId(); if not id or id=="" then warn("No sound ID!"); return end
		for _, plr in pairs(Players:GetPlayers()) do setScream(plr, id) end
	end
	local function restoreAll()
		for _, plr in pairs(Players:GetPlayers()) do restoreScream(plr) end
	end

	local function onAdded(plr)
		connections2[plr] = plr.CharacterAdded:Connect(function()
			originalIds[plr]=nil; originalSpeeds[plr]=nil; originalVolumes[plr]=nil
			if speedConns[plr]  then speedConns[plr]:Disconnect();  speedConns[plr]=nil  end
			if volumeConns[plr] then volumeConns[plr]:Disconnect(); volumeConns[plr]=nil end
			if sndEnabled then local id=getActiveId(); if id and id~="" then setScream(plr,id) end end
		end)
		if sndEnabled then local id=getActiveId(); if id and id~="" then setScream(plr,id) end end
	end
	local function onRemoving(plr)
		if connections2[plr] then connections2[plr]:Disconnect(); connections2[plr]=nil end
		if speedConns[plr]   then speedConns[plr]:Disconnect();   speedConns[plr]=nil   end
		if volumeConns[plr]  then volumeConns[plr]:Disconnect();  volumeConns[plr]=nil  end
		originalIds[plr]=nil; originalSpeeds[plr]=nil; originalVolumes[plr]=nil
	end
	for _, plr in pairs(Players:GetPlayers()) do onAdded(plr) end
	trackConnection(Players.PlayerAdded:Connect(onAdded))
	trackConnection(Players.PlayerRemoving:Connect(onRemoving))

	SoundsLeft:AddDropdown("SoundPreset", { Text="Sound Presets", Values=presetOrder, Default=presetOrder[1],
		Callback=function(v) selectedPreset=presets[v]; if sndEnabled and useDropdown then applyToAll() end end })
	SoundsLeft:AddToggle("EnablePresetSound", { Text="Enable Preset Sound", Default=false, Callback=function(v)
		useDropdown=v; if v then useCustom=false; Toggles.EnableCustomSound:SetValue(false) end
		sndEnabled=useDropdown or useCustom
		if sndEnabled then applyToAll() else restoreAll() end
	end })
	SoundsRight:AddInput("CustomScreamSound", { Text="Custom Scream Sound", Placeholder="Asset ID", Finished=true,
		Callback=function(v) customId=v end })
	SoundsRight:AddToggle("EnableCustomSound", { Text="Enable Custom Sound", Default=false, Callback=function(v)
		useCustom=v; if v then useDropdown=false; Toggles.EnablePresetSound:SetValue(false) end
		sndEnabled=useDropdown or useCustom
		if sndEnabled then if customId=="" then warn("Enter an asset ID first!"); return end; applyToAll()
		else restoreAll() end
	end })
	AudioGroup:AddSlider("SoundSpeed", { Text="Speed", Default=0, Min=-2, Max=2, Rounding=1, Suffix="x",
		Callback=function(v)
			customSpeed = v==0 and 1 or (v>0 and 1+v or 1/(1+math.abs(v)))
			if sndEnabled then for _, plr in pairs(Players:GetPlayers()) do
				local s=getScream(plr); if s then s.PlaybackSpeed=customSpeed end end end
		end })
	AudioGroup:AddSlider("SoundVolume", { Text="Volume", Default=5, Min=0, Max=10, Rounding=1, Suffix="vol",
		Callback=function(v)
			customVolume=v
			if sndEnabled then for _, plr in pairs(Players:GetPlayers()) do
				local s=getScream(plr); if s then s.Volume=customVolume end end end
		end })
	AudioGroup:AddLabel("More Sounds Settings coming soon")

	_G.HuiG_Cleanup = _G.HuiG_Cleanup or {}
	_G.HuiG_Cleanup.restoreAllSounds = restoreAll
	_G.HuiG_Cleanup.soundConnections = connections2
	_G.HuiG_Cleanup.speedConns       = speedConns
	_G.HuiG_Cleanup.volumeConns      = volumeConns
end

-- ============================================================
--  MISC TAB
-- ============================================================
local function buildMiscTab()
	local MiscTab   = Window:AddTab("Misc", "layers")
	local MiscLeft  = MiscTab:AddLeftGroupbox("Server")
	local MiscRight = MiscTab:AddRightGroupbox("Performance")

	local MiscFpsLabel = MiscRight:AddLabel({ Text="FPS : --", DoesWrap=false })
	local pingLabel    = MiscRight:AddLabel({ Text="Ping : --", DoesWrap=false })

	local fpsFrames  = 0
	local fpsLast    = tick()
	local pingLast   = 0

	trackConnection(RunService.Heartbeat:Connect(function()
		fpsFrames += 1
		local now = tick()
		if now - fpsLast >= 1 then
			MiscFpsLabel:SetText("FPS : " .. fpsFrames)
			fpsFrames = 0; fpsLast = now
		end
		if now - pingLast >= 1 then
			pingLast = now
			local ok, ping = pcall(function()
				return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
			if ok then pingLabel:SetText("Ping : " .. math.floor(ping) .. " ms") end
		end
	end))

	MiscRight:AddLabel({ Text="Performance stats update every second.", DoesWrap=true, Size=13 })

	MiscLeft:AddButton("Rejoin Server", function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
	end)
	MiscLeft:AddButton("Copy Game Link", function()
		if setclipboard then
			setclipboard(string.format("https://www.roblox.com/games/%d", game.PlaceId))
			Library:Notify({ Title="Copied", Description="Game link copied.", Time=3 })
		end
	end)
	MiscLeft:AddButton("Unload Script", function() Library:Unload() end)

	local ChangelogGroup = MiscTab:AddLeftGroupbox("📜 Changelog")
	ChangelogGroup:AddLabel({ Text = "V2.6", DoesWrap = false, Size = 16 })
	ChangelogGroup:AddLabel({ Text = "- Added HWID Auth", DoesWrap = true })
	ChangelogGroup:AddLabel({ Text = "- Removed Username Auth", DoesWrap = true })
	ChangelogGroup:AddLabel({ Text = "- Removed Local Effects", DoesWrap = true })
	ChangelogGroup:AddLabel({ Text = "- UI polish updates", DoesWrap = true })
end

-- ============================================================
--  SETTINGS TAB
-- ============================================================
local function buildSettingsTab()
	local SettingsTab = Window:AddTab("Settings", "settings")
	local MenuGroup   = SettingsTab:AddLeftGroupbox("Menu", "wrench")

	MenuGroup:AddToggle("KeybindMenuOpen", { Default=Library.KeybindFrame.Visible, Text="Open Keybind Menu",
		Callback=function(v) Library.KeybindFrame.Visible=v end })
	MenuGroup:AddToggle("ShowCustomCursor", { Text="Custom Cursor", Default=true,
		Callback=function(v) Library.ShowCustomCursor=v end })
	MenuGroup:AddDropdown("NotificationSide", { Values={"Left","Right"}, Default="Right", Text="Notification Side",
		Callback=function(v) Library:SetNotifySide(v) end })
	MenuGroup:AddDropdown("DPIDropdown", { Values={"50%","75%","100%","125%","150%","175%","200%"}, Default="100%", Text="DPI Scale",
		Callback=function(v) Library:SetDPIScale(tonumber(v:gsub("%%",""))) end })
	MenuGroup:AddSlider("UICornerSlider", { Text="Corner Radius", Default=20, Min=0, Max=20, Rounding=0,
		Callback=function(v) Window:SetCornerRadius(v) end })
	MenuGroup:AddDivider()
	MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default="RightShift", NoUI=true, Text="Menu keybind" })
	MenuGroup:AddButton("Unload", function() Library:Unload() end)

	Library.ToggleKeybind = Options.MenuKeybind

	ThemeManager:SetLibrary(Library)
	SaveManager:SetLibrary(Library)
	SaveManager:IgnoreThemeSettings()
	SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
	ThemeManager:SetFolder("HuiG")
	SaveManager:SetFolder("HuiG")
	SaveManager:BuildConfigSection(SettingsTab)
	ThemeManager:ApplyToTab(SettingsTab)

	Library:OnUnload(function()
		local c = _G.HuiG_Cleanup or {}
		if c.stopHomeUpdates   then c.stopHomeUpdates()  end
		if c.restoreAllSounds  then c.restoreAllSounds() end
		if c.stopCoinImage     then c.stopCoinImage()    end
		if c.stopWatermark then c.stopWatermark() end

		if c.hudOriginalColors then
			for obj, color in pairs(c.hudOriginalColors) do
				if obj and obj.Parent then obj.TextColor3=color end
			end
			table.clear(c.hudOriginalColors)
		end
		if c.soundConnections then
			for plr, conn in pairs(c.soundConnections) do if conn then conn:Disconnect() end end
		end
		if c.speedConns then
			for plr, conn in pairs(c.speedConns) do if conn then conn:Disconnect() end end
		end
		if c.volumeConns then
			for plr, conn in pairs(c.volumeConns) do if conn then conn:Disconnect() end end
		end
		if c.bhDescConn then c.bhDescConn:Disconnect() end
		for model in pairs(bhActiveModels) do
			if model and model.Parent then model:Destroy() end
		end
		table.clear(bhActiveModels)
		local folder = c.bhPreloadFolder and c.bhPreloadFolder()
		if folder and folder.Parent then folder:Destroy() end
		if c.restoreLightingDefaults then c.restoreLightingDefaults() end
		if c.stopCamShake            then c.stopCamShake()            end
		if c.stopThirdPerson and c.thirdPersonOn and c.thirdPersonOn() then c.stopThirdPerson() end

		local cam = workspace.CurrentCamera
		if cam and c.defaultFov then cam.FieldOfView = c.defaultFov end

		for _, conn in ipairs(uiConnections) do if conn then conn:Disconnect() end end
		table.clear(uiConnections)

		_G.HuiG_Cleanup = nil
		_G.HuiG_LastPos = nil
	end)

	SaveManager:LoadAutoloadConfig()
end

-- ============================================================
--  LOADING SPLASH — tracks real load progress
-- ============================================================
local function buildSplash()
	local splashPlayer = game:GetService("Players").LocalPlayer
	local splashGui = splashPlayer:WaitForChild("PlayerGui")

	local splash = Instance.new("ScreenGui")
	splash.Name = "HuiG_LoadingSplash"
	splash.ResetOnSpawn = false
	splash.IgnoreGuiInset = true
	splash.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	splash.DisplayOrder = 999999
	splash.Parent = splashGui

	-- Dim backdrop, fades in
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 1
	backdrop.Parent = splash

	-- Card
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0, 340, 0, 190)
	card.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.ZIndex = 2
	card.Parent = splash

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 18)
	cardCorner.Parent = card

	-- Subtle glow border with slow rotating gradient (monochrome)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 1.2
	cardStroke.Color = Color3.fromRGB(255, 255, 255)
	cardStroke.Transparency = 0.75
	cardStroke.Parent = card

	local strokeGradient = Instance.new("UIGradient")
	strokeGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	strokeGradient.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0.9),
	}
	strokeGradient.Parent = cardStroke

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = card

	local topPad = Instance.new("UIPadding")
	topPad.PaddingTop = UDim.new(0, 26)
	topPad.Parent = card

	-- Icon
	local iconLabel = Instance.new("TextLabel")
	iconLabel.LayoutOrder = 1
	iconLabel.Text = "⚡"
	iconLabel.TextSize = 40
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconLabel.Size = UDim2.new(1, 0, 0, 46)
	iconLabel.Parent = card

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.LayoutOrder = 2
	titleLabel.Text = "HuiG"
	titleLabel.TextSize = 32
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Size = UDim2.new(1, 0, 0, 38)
	titleLabel.Parent = card

	-- Stage text
	local stageLabel = Instance.new("TextLabel")
	stageLabel.LayoutOrder = 3
	stageLabel.Text = "Initializing..."
	stageLabel.TextSize = 14
	stageLabel.Font = Enum.Font.Gotham
	stageLabel.BackgroundTransparency = 1
	stageLabel.TextColor3 = Color3.fromRGB(160, 160, 165)
	stageLabel.Size = UDim2.new(1, 0, 0, 20)
	stageLabel.Parent = card

	-- Progress bar track
	local barTrack = Instance.new("Frame")
	barTrack.LayoutOrder = 4
	barTrack.Size = UDim2.new(0, 260, 0, 6)
	barTrack.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
	barTrack.BorderSizePixel = 0
	barTrack.Parent = card

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barTrack

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	barFill.BorderSizePixel = 0
	barFill.Parent = barTrack

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill

	-- Shimmer sweep across the fill
	local shimmerGradient = Instance.new("UIGradient")
	shimmerGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	shimmerGradient.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.45, 0),
		NumberSequenceKeypoint.new(0.55, 0),
		NumberSequenceKeypoint.new(1, 0.3),
	}
	shimmerGradient.Parent = barFill

	local percentLabel = Instance.new("TextLabel")
	percentLabel.LayoutOrder = 5
	percentLabel.Text = "0%"
	percentLabel.TextSize = 12
	percentLabel.Font = Enum.Font.Gotham
	percentLabel.BackgroundTransparency = 1
	percentLabel.TextColor3 = Color3.fromRGB(130, 130, 135)
	percentLabel.Size = UDim2.new(1, 0, 0, 16)
	percentLabel.Parent = card

	-- Entrance animation
	card.Size = UDim2.new(0, 340, 0, 190)
	local startScale = 0.85
	card:GetPropertyChangedSignal("Size") -- no-op, keeps signal warm
	local scaleFrame = Instance.new("UIScale")
	scaleFrame.Scale = startScale
	scaleFrame.Parent = card

	local TweenService = game:GetService("TweenService")
	TweenService:Create(backdrop, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(scaleFrame, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- Rotating border glow loop
	local alive = true
	task.spawn(function()
		while alive do
			strokeGradient.Rotation = (strokeGradient.Rotation + 40 * task.wait()) % 360
		end
	end)

	local function updateProgress(pct, text)
		pct = math.clamp(pct, 0, 100)
		if text then stageLabel.Text = text end
		percentLabel.Text = math.floor(pct) .. "%"
		TweenService:Create(barFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
			Size = UDim2.new(pct / 100, 0, 1, 0)
		}):Play()
	end

	local function closeSplash()
		alive = false
		local fadeOut = TweenService:Create(backdrop, TweenInfo.new(0.3, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 })
		local cardFade = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 })
		local cardScale = TweenService:Create(scaleFrame, TweenInfo.new(0.3, Enum.EasingStyle.Sine), { Scale = 1.05 })
		fadeOut:Play(); cardFade:Play(); cardScale:Play()
		fadeOut.Completed:Wait()
		splash:Destroy()
	end

	return updateProgress, closeSplash
end

-- ============================================================
--  WATERMARK
-- ============================================================
local function buildWatermark()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HuiG_Watermark"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 500
	gui.Parent = game:GetService("CoreGui")

	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(0, 230, 0, 30)
	pill.Position = _G.HuiG_LastPos or UDim2.new(1, -250, 0, 10)  -- right-aligned, below the top bar
	pill.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.8
	stroke.Parent = pill

	local strokeGradient = Instance.new("UIGradient")
	strokeGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	strokeGradient.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 0.9),
	}
	strokeGradient.Parent = stroke

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = pill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(230, 230, 235)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "⚡ HuiG | -- fps | -- ms"
	label.Parent = pill

	-- Rotating border glow
	local alive = true
	trackConnection(RunService.Heartbeat:Connect(function(dt)
		strokeGradient.Rotation = (strokeGradient.Rotation + 25 * dt) % 360
	end))

	-- Dragging
	local UserInputService = game:GetService("UserInputService")
	local dragging, dragStart, startPos = false, nil, nil

	trackConnection(pill.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = pill.Position
		end
	end))
	trackConnection(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			local newPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			pill.Position = newPos
			_G.HuiG_LastPos = newPos
		end
	end))
	trackConnection(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	-- Stat updates (lightweight, independent of Home tab)
	local fpsDisplayed, pingDisplayed = 0, 0
	task.spawn(function()
		while alive and gui.Parent do
			local ok, frameTime = pcall(function() return RunService.Heartbeat:Wait() end)
			if not ok then break end
			if frameTime and frameTime > 0 then
				fpsDisplayed += ((1 / frameTime) - fpsDisplayed) * 0.15
			end
			task.wait(0.2)

			local okPing, rawPing = pcall(function()
				return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
			if okPing then pingDisplayed += (rawPing - pingDisplayed) * 0.15 end

			local dot = "⚪"
			if fpsDisplayed >= 50 then dot = "🟢" elseif fpsDisplayed >= 30 then dot = "🟡" else dot = "🔴" end

			label.Text = string.format("⚡ HuiG | %s %d fps | %d ms", dot, math.floor(fpsDisplayed), math.floor(pingDisplayed))
		end
	end)

	_G.HuiG_Cleanup = _G.HuiG_Cleanup or {}
	_G.HuiG_Cleanup.stopWatermark = function()
		alive = false
		if gui and gui.Parent then gui:Destroy() end
	end

	return gui
end

-- ============================================================
--  ENTRY POINT
-- ============================================================
local splashUpdate, splashClose = buildSplash()
_G.HuiG_SplashProgress = splashUpdate

-- Authorization check
splashUpdate(5, "Checking authorization...")
task.wait(0.1) -- brief display

-- ============================================================
--  HWID AUTHENTICATION  (replace the old local table check)
-- ============================================================

-- 1. Function to get your executor's real HWID
local function getHWID()
    -- SYNAPSE / SCRIPT-WARE / KRNL users:
    if syn and syn.crypt and syn.crypt.custom and syn.crypt.custom.hash then
        return syn.crypt.custom.hash("HuiG-HWID-Salt")  -- unique salt
    end
    -- Alternative for other executors (less secure)
    if game:GetService("RbxAnalyticsService"):GetClientId() then
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end
    -- Fallback (User-based, not true HWID – only use if above fail)
    return "USER_" .. game.Players.LocalPlayer.UserId
end

local myHWID = getHWID()
splashUpdate(8, "Verifying HWID...")

-- 2. Your Google Apps Script URL
local apiUrl = "https://script.google.com/macros/s/AKfycby1HiApO8RUcLZajcSSuApmLrSdrtHvygQB--8OnQa47a1VG3Ee07He2HrRbptTJ7Jy/exec"

-- 3. Send request (syn.request or http_request)
local requestFunc = syn and syn.request or http_request or request
local function checkAuthorization()
    if not requestFunc then
        -- If no HTTP function, fallback to local list (optional)
        return false
    end
    local success, response = pcall(function()
        return requestFunc({
            Url = apiUrl .. "?hwid=" .. myHWID,
            Method = "GET",
        })
    end)
    if success and response and response.Body then
        return response.Body == "AUTHORIZED"
    end
    return false
end

-- 4. If not authorized, show the red screen and stop
if not checkAuthorization() then
    splashClose()
    _G.HuiG_SplashProgress = nil

    local unauthGui = Instance.new("ScreenGui")
    unauthGui.Name = "HuiG_Unauthorized"
    unauthGui.ResetOnSpawn = false
    unauthGui.IgnoreGuiInset = true
    unauthGui.DisplayOrder = 999999
    unauthGui.Parent = game:GetService("CoreGui")

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1,0,1,0)
    bg.BackgroundColor3 = Color3.fromRGB(20,20,20)
    bg.BackgroundTransparency = 0.5
    bg.BorderSizePixel = 0
    bg.Parent = unauthGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,0,1,0)
    label.BackgroundTransparency = 1
    label.Text = "⛔ UNAUTHORIZED HWID ⛔"
    label.TextColor3 = Color3.fromRGB(255,50,50)
    label.Font = Enum.Font.GothamBlack
    label.TextSize = 48
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3 = Color3.fromRGB(150,0,0)
    label.Parent = unauthGui

    local tweenService = game:GetService("TweenService")
    local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    tweenService:Create(label, tweenInfo, { TextSize = 52 }):Play()

    task.wait(5)
    unauthGui:Destroy()
    return  -- stops the whole script
end

splashUpdate(12, "HWID approved!")

-- If authorized, proceed normally
initCore()
splashUpdate(100, "Ready")
task.wait(0.35)
splashClose()
_G.HuiG_SplashProgress = nil

buildHomeTab()
buildTargetTab()
buildVisualsTab()
buildSoundsTab()
buildMiscTab()
buildSettingsTab()
buildWatermark()
