--[[
    PMiguelX_AdminPanel.lua  (versão completa e atualizada)
    Painel privado de testes · Delta Executor · Roblox
    Uso exclusivo em ambiente de desenvolvimento e testes de física.
]]

-- ============================================================
-- SERVIÇOS E CONSTANTES
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LightingSvc = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local MarketplaceService = game:GetService("MarketplaceService")
local StatsService = game:GetService("Stats")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")

local LocalPlayer = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local GUI_NAME = "PMX_AdminPanel"
local CONFIG_FILE = "PMiguelX_Config.json"
local ENV_KEY = "PMX_AdminPanel_Unload"
local DEFAULT_GRAVITY = 196.2

local DEFAULTS = {
	WalkSpeed = 16,
	JumpPower = 50,
	Gravity = DEFAULT_GRAVITY,
	FlySpeed = 60,
	AccentIndex = 1,
	AntiAFK = false,
	GodMode = false,
}

local ACCENTS = {
	{ name = "Ciano", color = Color3.fromRGB(0, 205, 255) },
	{ name = "Azul", color = Color3.fromRGB(40, 120, 255) },
	{ name = "Prata", color = Color3.fromRGB(176, 186, 200) },
	{ name = "Verde", color = Color3.fromRGB(0, 210, 130) },
	{ name = "Roxo", color = Color3.fromRGB(150, 95, 255) },
	{ name = "Laranja", color = Color3.fromRGB(255, 140, 25) },
}

local C = {
	bg = Color3.fromRGB(10, 12, 18),
	panel = Color3.fromRGB(16, 19, 28),
	item = Color3.fromRGB(25, 29, 41),
	text = Color3.fromRGB(226, 232, 240),
	muted = Color3.fromRGB(125, 135, 152),
	silver = Color3.fromRGB(196, 204, 216),
	danger = Color3.fromRGB(176, 46, 58),
	dark = Color3.fromRGB(8, 10, 14),
}

local LOGO_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 230, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 228, 238)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 130, 210)),
})

-- ============================================================
-- ESTADO GLOBAL
-- ============================================================
local L = {} -- medidas responsivas (preenchidas em buildGui)

local Config = {}
for k, v in pairs(DEFAULTS) do
	Config[k] = v
end

local Connections = {}
local Themed = {}
local Refreshers = {}
local Tabs = {}
local Waypoints = {}

local State = {
	unloaded = false,
	uiVisible = false,
	flying = false,
	flyUp = false,
	flyDown = false,
	noclip = false,
	fullbright = false,
	nightVision = false,
	antiAFK = false,
	godMode = false,
	freecam = false,
	telemetry = false,
	telemetryTimer = 0,
	savedCFrame = nil,
	currentTab = "Player",
	gui = nil,
	mainWindow = nil,
	statusLabel = nil,
	telemetryLabel = nil,
	statsLabel = nil,
	loadMessage = "Pronto.",
}

-- ============================================================
-- UTILITÁRIOS
-- ============================================================
local function track(conn)
	table.insert(Connections, conn)
	return conn
end

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[PMX] " .. tostring(err))
	end
	return ok
end

local function new(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function stroke(parent, color, thickness)
	return new("UIStroke", {
		Color = color or C.silver,
		Thickness = thickness or 1,
		Transparency = 0.35,
	}, parent)
end

local function logoGradient(parent)
	return new("UIGradient", { Color = LOGO_GRADIENT, Rotation = 90 }, parent)
end

local function accent()
	local entry = ACCENTS[Config.AccentIndex] or ACCENTS[1]
	return entry.color
end

local function themed(obj, prop)
	table.insert(Themed, { obj = obj, prop = prop })
	obj[prop] = accent()
	return obj
end

local function notify(msg)
	if State.statusLabel then
		State.statusLabel.Text = tostring(msg)
	end
end

local function getHumanoid()
	local char = LocalPlayer.Character
	if not char then
		return nil, nil
	end
	return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function label(parent, text, size, pos, textSize, font, color, xAlign)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Size = size,
		Position = pos or UDim2.new(0, 0, 0, 0),
		Font = font or Enum.Font.GothamMedium,
		TextSize = textSize or L.font,
		TextColor3 = color or C.text,
		TextXAlignment = xAlign or Enum.TextXAlignment.Left,
		Text = text,
	}, parent)
end

local function button(parent, text, onClick, color, textColor)
	local b = new("TextButton", {
		Size = UDim2.new(1, -6, 0, L.rowH),
		BackgroundColor3 = color or C.item,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = L.font,
		TextColor3 = textColor or C.text,
		Text = text,
	}, parent)
	corner(b, 8)
	if onClick then
		b.MouseButton1Click:Connect(function()
			safe(onClick)
		end)
	end
	return b
end

local function sectionLabel(parent, text)
	return label(
		parent,
		string.upper(text),
		UDim2.new(1, -6, 0, L.rowH - 12),
		nil,
		L.font - 3,
		Enum.Font.GothamBlack,
		C.muted
	)
end

local function makeToggle(parent, text, initial, onChange)
	local state = initial and true or false
	local b = button(parent, text, nil)
	local function paint()
		b.BackgroundColor3 = state and accent() or C.item
		b.Text = text .. "    " .. (state and "● ON" or "○ OFF")
	end
	paint()
	table.insert(Refreshers, paint)
	b.MouseButton1Click:Connect(function()
		state = not state
		paint()
		if onChange then
			safe(onChange, state)
		end
	end)
	return {
		Set = function(v)
			state = v and true or false
			paint()
		end,
		Get = function()
			return state
		end,
	}
end

local function makeNumberInput(parent, text, key, minV, maxV, onApply)
	local row = new("Frame", {
		Size = UDim2.new(1, -6, 0, L.rowH),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
	}, parent)
	corner(row, 8)

	label(row, text, UDim2.new(0.56, 0, 1, 0), UDim2.new(0, 12, 0, 0))

	local boxH = L.rowH - 14
	local box = new("TextBox", {
		Size = UDim2.new(0.34, 0, 0, boxH),
		Position = UDim2.new(0.62, 0, 0.5, -math.floor(boxH / 2)),
		BackgroundColor3 = C.bg,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		TextSize = L.font,
		TextColor3 = C.text,
		ClearTextOnFocus = false,
		Text = tostring(Config[key]),
	}, row)
	corner(box, 6)

	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n then
			n = math.clamp(n, minV, maxV)
			Config[key] = n
			if onApply then
				safe(onApply, n)
			end
		end
		box.Text = tostring(Config[key])
	end)

	table.insert(Refreshers, function()
		box.Text = tostring(Config[key])
	end)
	return box
end

local function newPage(key, parent)
	local page = new("ScrollingFrame", {
		Name = key,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.silver,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Visible = false,
	}, parent)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, page)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	}, page)
	return page
end

local function makeDraggable(handle, target, onTap)
	local dragging = false
	local moved = false
	local startInput, startPos

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			startInput = Vector2.new(input.Position.X, input.Position.Y)
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved and onTap then
						safe(onTap)
					end
				end
			end)
		end
	end)

	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local current = Vector2.new(input.Position.X, input.Position.Y)
			local d = current - startInput
			if d.Magnitude > 8 then
				moved = true
			end
			if moved then
				target.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y
				)
			end
		end
	end))
end

local function isTablet()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(800, 600)
	return math.min(vp.X, vp.Y) >= 600, vp
end

local function getGuiParent()
	local ok, hui = pcall(function()
		return gethui and gethui()
	end)
	if ok and typeof(hui) == "Instance" then
		return hui
	end
	local okCore, core = pcall(function()
		return CoreGui
	end)
	if okCore and core then
		return core
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function destroyOldInstances()
	local containers = {}
	local okCore, core = pcall(function()
		return CoreGui
	end)
	if okCore and core then
		table.insert(containers, core)
	end
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if pg then
		table.insert(containers, pg)
	end
	local okH, hui = pcall(function()
		return gethui and gethui()
	end)
	if okH and typeof(hui) == "Instance" then
		table.insert(containers, hui)
	end
	for _, c in ipairs(containers) do
		local old = c:FindFirstChild(GUI_NAME)
		if old then
			old:Destroy()
		end
	end
end

local function detectExecutor()
	local name = "Desconhecido"
	local ok, result = pcall(function()
		if identifyexecutor then
			return (identifyexecutor())
		end
	end)
	if ok and result then
		name = tostring(result)
	end
	return name
end

local function applyAccent()
	for _, t in ipairs(Themed) do
		safe(function()
			t.obj[t.prop] = accent()
		end)
	end
	for _, fn in ipairs(Refreshers) do
		safe(fn)
	end
end

-- ============================================================
-- WORKSPACE (DELTA): CONFIGURAÇÃO JSON
-- ============================================================
local function saveConfig()
	if type(writefile) ~= "function" then
		return false, "Workspace indisponível neste executor."
	end
	local okJson, json = pcall(HttpService.JSONEncode, HttpService, Config)
	if not okJson then
		return false, "Erro ao codificar a configuração."
	end
	local okWrite, err = pcall(writefile, CONFIG_FILE, json)
	if okWrite then
		return true, "Configuração salva no Workspace."
	end
	return false, "Falha ao salvar: " .. tostring(err)
end

local function loadConfig()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then
		return false, "Workspace indisponível neste executor."
	end
	local okExists, exists = pcall(isfile, CONFIG_FILE)
	if not okExists then
		return false, "Falha ao verificar o ficheiro."
	end
	if not exists then
		saveConfig()
		return true, "Ficheiro de configuração criado."
	end
	local okRead, content = pcall(readfile, CONFIG_FILE)
	if not okRead or type(content) ~= "string" then
		return false, "Falha ao ler a configuração."
	end
	local okJson, data = pcall(HttpService.JSONDecode, HttpService, content)
	if not okJson or type(data) ~= "table" then
		return false, "Configuração corrompida, usando padrões."
	end
	for k, default in pairs(DEFAULTS) do
		if type(data[k]) == type(default) then
			Config[k] = data[k]
		end
	end
	return true, "Configuração carregada do Workspace."
end

local function resetConfig()
	for k, v in pairs(DEFAULTS) do
		Config[k] = v
	end
	return saveConfig()
end

-- ============================================================
-- FÍSICA E LOCALPLAYER
-- ============================================================
local function applyStats()
	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = Config.WalkSpeed
		hum.UseJumpPower = true
		hum.JumpPower = Config.JumpPower
	end
	workspace.Gravity = Config.Gravity
end

local flyConn
local function setFly(on)
	State.flying = on
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	local hum, root = getHumanoid()
	if not on then
		if hum then
			hum.PlatformStand = false
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		return
	end
	flyConn = track(RunService.Heartbeat:Connect(function()
		local h, r = getHumanoid()
		if not h or not r or not State.flying then
			return
		end
		h.PlatformStand = true
		local move = h.MoveDirection * Config.FlySpeed
		local vertical = 0
		if State.flyUp or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			vertical = 1
		elseif State.flyDown or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			vertical = -1
		end
		r.AssemblyLinearVelocity = Vector3.new(move.X, vertical * Config.FlySpeed, move.Z)
	end))
end

local noclipConn
local function setNoclip(on)
	State.noclip = on
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if on then
		noclipConn = track(RunService.Stepped:Connect(function()
			local char = LocalPlayer.Character
			if not char then
				return
			end
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
				end
			end
		end))
	else
		local char = LocalPlayer.Character
		if char then
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
					p.CanCollide = true
				end
			end
		end
	end
end

local godModeConn
local function setGodMode(on)
	State.godMode = on
	Config.GodMode = on
	if godModeConn then
		godModeConn:Disconnect()
		godModeConn = nil
	end
	if on then
		godModeConn = track(RunService.Heartbeat:Connect(function()
			local hum = getHumanoid()
			if hum and hum.Health < hum.MaxHealth then
				hum.Health = hum.MaxHealth
			end
		end))
		notify("God Mode ativo.")
	else
		notify("God Mode desativado.")
	end
end

-- ============================================================
-- FREECAM (CÂMERA LIVRE PROFISSIONAL & BLINDADA)
-- ============================================================
local freecamConn = nil
local freecamInputConn = nil
local freecamTouchConn = nil
local freecamPos = Vector3.new(0, 10, 0)
local freecamRot = Vector2.new(0, 0)
local isPanning = false
local panTouchId = nil
local lastTouchPos = Vector2.new(0, 0)

local function setFreecam(on)
	State.freecam = on
	local cam = workspace.CurrentCamera

	if freecamConn then freecamConn:Disconnect(); freecamConn = nil end
	if freecamInputConn then freecamInputConn:Disconnect(); freecamInputConn = nil end
	if freecamTouchConn then freecamTouchConn:Disconnect(); freecamTouchConn = nil end
	safe(ContextActionService.UnbindAction, ContextActionService, "PMX_FreecamBlock")

	local hum, root = getHumanoid()

	if on then
		if not cam then return end
		
		-- 1. Congelar personagem e desativar comandos de movimento por toque/teclado
		if hum then
			hum.PlatformStand = true
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true
		end

		-- Bloquear inputs de movimento do jogo para evitar que ande contra paredes
		ContextActionService:BindActionAtPriority(
			"PMX_FreecamBlock",
			function() return Enum.ContextActionResult.Sink end,
			false,
			Enum.ContextActionResultPriority.High.Value,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
			Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
			Enum.KeyCode.Space, Enum.KeyCode.Thumbstick1
		)

		-- 2. Inicializar posição exata da câmara livre
		cam.CameraType = Enum.CameraType.Scriptable
		freecamPos = cam.CFrame.Position
		local look = cam.CFrame.LookVector
		freecamRot = Vector2.new(math.atan2(-look.X, -look.Z), math.asin(look.Y))

		-- 3. Controlo de rotação por toque (Mobile / Tablet Friendly) & Mouse
		freecamTouchConn = track(UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch and not panTouchId then
				-- Se o toque não começou em cima de uma janela/botão da GUI, ativa o pan livre
				local pos = input.Position
				if State.mainWindow and State.mainWindow.Visible then
					local absPos = State.mainWindow.AbsolutePosition
					local absSize = State.mainWindow.AbsoluteSize
					if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
						return -- Permite interagir com o painel normalmente
					end
				end
				panTouchId = input
				lastTouchPos = Vector2.new(pos.X, pos.Y)
				isPanning = true
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				isPanning = true
			end
		end))

		track(UserInputService.InputEnded:Connect(function(input)
			if input == panTouchId or input.UserInputType == Enum.UserInputType.MouseButton2 then
				isPanning = false
				panTouchId = nil
			end
		end))

		freecamInputConn = track(UserInputService.InputChanged:Connect(function(input)
			if isPanning and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = Vector2.zero
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					delta = Vector2.new(input.Delta.X, input.Delta.Y)
				elseif input.UserInputType == Enum.UserInputType.Touch and input == panTouchId then
					local currentPos = Vector2.new(input.Position.X, input.Position.Y)
					delta = currentPos - lastTouchPos
					lastTouchPos = currentPos
				end

				local sensitivity = 0.005
				freecamRot = Vector2.new(
					freecamRot.X - delta.X * sensitivity,
					math.clamp(freecamRot.Y - delta.Y * sensitivity, -math.pi / 2 + 0.01, math.pi / 2 - 0.01)
				)
			end
		end))

		-- 4. Loop de atualização da câmara livre e movimento suave (W, A, S, D, Espaço, Shift)
		freecamConn = track(RunService.RenderStepped:Connect(function(dt)
			if not State.freecam or not cam then return end

			local speed = 65
			local moveDir = Vector3.zero
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then moveDir += Vector3.new(0, 0, -1) end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then moveDir += Vector3.new(0, 0, 1) end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then moveDir += Vector3.new(-1, 0, 0) end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then moveDir += Vector3.new(1, 0, 0) end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0, 1, 0) end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir += Vector3.new(0, -1, 0) end

			local rotation = CFrame.Angles(0, freecamRot.X, 0) * CFrame.Angles(freecamRot.Y, 0, 0)
			local forward = rotation.LookVector
			local right = rotation.RightVector
			local up = Vector3.new(0, 1, 0)

			local velocity = (right * moveDir.X + up * moveDir.Y + forward * -moveDir.Z) * speed
			freecamPos += velocity * dt

			cam.CFrame = CFrame.new(freecamPos) * rotation
		end))

		notify("Freecam ativo.")
	else
		-- Desativar câmara livre e restaurar estado perfeito do avatar
		safe(ContextActionService.UnbindAction, ContextActionService, "PMX_FreecamBlock")
		isPanning = false
		panTouchId = nil

		if root then
			root.Anchored = false
		end
		if hum then
			hum.PlatformStand = false
		end

		if cam then
			cam.CameraType = Enum.CameraType.Custom
			if root then
				cam.CameraSubject = hum
				-- Reposicionar câmara suavemente olhando para o avatar de frente/costas para evitar rotação brusca
				cam.CFrame = CFrame.new(root.Position + Vector3.new(0, 3, 8), root.Position)
			end
		end

		notify("Freecam desativado.")
	end
end

-- ============================================================
-- ILUMINAÇÃO: FULLBRIGHT E VISÃO NOTURNA
-- ============================================================
local lightOriginal
local nightCC

local function setFullbright(on)
	State.fullbright = on
	if on then
		if not lightOriginal then
			lightOriginal = {
				Brightness = LightingSvc.Brightness,
				ClockTime = LightingSvc.ClockTime,
				Ambient = LightingSvc.Ambient,
				OutdoorAmbient = LightingSvc.OutdoorAmbient,
				GlobalShadows = LightingSvc.GlobalShadows,
				FogEnd = LightingSvc.FogEnd,
			}
		end
		LightingSvc.Brightness = 3
		LightingSvc.ClockTime = 14
		LightingSvc.Ambient = Color3.new(1, 1, 1)
		LightingSvc.OutdoorAmbient = Color3.new(1, 1, 1)
		LightingSvc.GlobalShadows = false
		LightingSvc.FogEnd = 100000
	elseif lightOriginal then
		for k, v in pairs(lightOriginal) do
			LightingSvc[k] = v
		end
		lightOriginal = nil
	end
end

local function setNightVision(on)
	State.nightVision = on
	if on then
		if not nightCC or not nightCC.Parent then
			nightCC = new("ColorCorrectionEffect", {
				Name = "PMX_NightVision",
				TintColor = Color3.fromRGB(160, 255, 180),
				Brightness = 0.12,
				Contrast = 0.25,
				Saturation = -0.35,
			}, LightingSvc)
		end
	elseif nightCC then
		nightCC:Destroy()
		nightCC = nil
	end
end

-- ============================================================
-- ANTI-AFK
-- ============================================================
local function antiAFKPulse()
	safe(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
end

local function setAntiAFK(on)
	State.antiAFK = on
	Config.AntiAFK = on
	if on then
		antiAFKPulse()
		notify("Anti-AFK ativo.")
	else
		notify("Anti-AFK desativado.")
	end
end

-- ============================================================
-- CLEAR LAG / DEBRIS
-- ============================================================
local function clearLag()
	local count = 0
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and not obj:IsDescendantOf(LocalPlayer.Character or workspace) then
			local anchored = obj.Anchored
			if not anchored and obj.Parent and not obj.Parent:FindFirstChildOfClass("Humanoid") then
				obj:Destroy()
				count += 1
			end
		elseif obj:IsA("ParticleEmitter") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
			obj:Destroy()
			count += 1
		end
	end
	notify("Limpeza concluída: " .. tostring(count) .. " itens removidos.")
end

-- ============================================================
-- STOP ALL SCRIPTS (EMERGENCY)
-- ============================================================
local function stopAllScripts()
	safe(setFly, false)
	safe(setNoclip, false)
	safe(setFullbright, false)
	safe(setNightVision, false)
	safe(setGodMode, false)
	safe(setFreecam, false)
	State.antiAFK = false
	State.telemetry = false
	
	for _, conn in ipairs(Connections) do
		safe(function()
			conn:Disconnect()
		end)
	end
	table.clear(Connections)

	safe(function()
		workspace.Gravity = DEFAULT_GRAVITY
	end)

	local hum, root = getHumanoid()
	if root then
		root.Anchored = false
	end
	if hum then
		safe(function()
			hum.PlatformStand = false
			hum.WalkSpeed = DEFAULTS.WalkSpeed
			hum.JumpPower = DEFAULTS.JumpPower
		end)
	end
	notify("Todos os scripts e loops foram parados.")
end

-- ============================================================
-- UI: VISIBILIDADE E ABAS
-- ============================================================
local function setUIVisible(v)
	State.uiVisible = v
	if State.mainWindow then
		State.mainWindow.Visible = v
	end
end

local function toggleUI()
	setUIVisible(not State.uiVisible)
end

local function selectTab(key)
	State.currentTab = key
	for _, t in ipairs(Tabs) do
		local active = t.key == key
		t.page.Visible = active
		t.button.BackgroundColor3 = active and accent() or C.item
		t.button.TextColor3 = active and C.dark or C.text
	end
end

-- ============================================================
-- DESCARGA (UNLOAD)
-- ============================================================
local function unloadPanel()
	if State.unloaded then
		return
	end
	State.unloaded = true

	stopAllScripts()
	safe(saveConfig)

	if State.gui then
		State.gui:Destroy()
		State.gui = nil
	end

	ENV[ENV_KEY] = nil
end

-- ============================================================
-- CONSTRUÇÃO DA GUI
-- ============================================================
local function buildGui(executorName)
	local tablet, vp = isTablet()

	L.tablet = tablet
	L.font = tablet and 15 or 13
	L.rowH = tablet and 44 or 38
	L.titleH = tablet and 48 or 40
	L.footerH = tablet and 28 or 24
	L.sideW = tablet and 160 or 0
	L.tabH = tablet and 0 or 42
	L.width = tablet and math.min(640, vp.X - 40) or math.min(vp.X - 16, 360)
	L.height = tablet and math.min(460, vp.Y - 60) or math.min(vp.Y - 90, 500)
	L.width = math.max(L.width, 260)
	L.height = math.max(L.height, 260)

	local gui = new("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, getGuiParent())
	State.gui = gui

	-- ---------- JANELA DE CARREGAMENTO ----------
	local loader = new("Frame", {
		Name = "Loader",
		Size = UDim2.fromOffset(260, 250),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.bg,
		BorderSizePixel = 0,
	}, gui)
	corner(loader, 14)
	themed(stroke(loader, C.silver, 1.5), "Color")

	local logo = label(loader, "PMX", UDim2.new(1, 0, 0, 56), UDim2.new(0, 0, 0, 14), 44, Enum.Font.GothamBlack, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
	logoGradient(logo)
	stroke(logo, Color3.fromRGB(0, 205, 255), 1)

	label(loader, "TEST SUITE · DEV", UDim2.new(1, 0, 0, 14), UDim2.new(0, 0, 0, 68), 10, Enum.Font.GothamBold, C.muted, Enum.TextXAlignment.Center)

	local avatar = new("ImageLabel", {
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.new(0.5, -36, 0, 88),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
	}, loader)
	corner(avatar, 36)
	themed(stroke(avatar, C.silver, 1.5), "Color")

	task.spawn(function()
		safe(function()
			local content = Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			if content and avatar.Parent then
				avatar.Image = content
			end
		end)
	end)

	label(loader, LocalPlayer.Name, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 166), 14, Enum.Font.GothamBold, C.text, Enum.TextXAlignment.Center)

	local isDelta = string.find(string.lower(executorName), "delta", 1, true) ~= nil
	local execLabel = label(
		loader,
		"Executor: " .. executorName .. (isDelta and "  ✓" or ""),
		UDim2.new(1, 0, 0, 14),
		UDim2.new(0, 0, 0, 186),
		11,
		Enum.Font.GothamMedium,
		isDelta and C.silver or C.muted,
		Enum.TextXAlignment.Center
	)
	if isDelta then
		table.insert(Refreshers, function()
			execLabel.TextColor3 = accent()
		end)
		execLabel.TextColor3 = accent()
	end

	local barBg = new("Frame", {
		Size = UDim2.new(0, 190, 0, 5),
		Position = UDim2.new(0.5, -95, 0, 214),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
	}, loader)
	corner(barBg, 3)

	local barFill = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BorderSizePixel = 0,
	}, barBg)
	corner(barFill, 3)
	themed(barFill, "BackgroundColor3")

	-- ---------- JANELA PRINCIPAL ----------
	local main = new("Frame", {
		Name = "Main",
		Size = UDim2.fromOffset(L.width, L.height),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.bg,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	corner(main, 12)
	themed(stroke(main, C.silver, 1), "Color")
	State.mainWindow = main

	-- Barra de título
	local titleBar = new("Frame", {
		Size = UDim2.new(1, 0, 0, L.titleH),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, main)
	corner(titleBar, 12)

	local titleLogo = label(titleBar, "PMX", UDim2.new(0, 60, 1, 0), UDim2.new(0, 12, 0, 0), L.tablet and 18 or 16, Enum.Font.GothamBlack, Color3.new(1, 1, 1))
	logoGradient(titleLogo)
	label(titleBar, "Painel de Testes", UDim2.new(1, -150, 1, 0), UDim2.new(0, 70, 0, 0), L.font - 1, Enum.Font.GothamMedium, C.muted)

	local closeBtn = new("TextButton", {
		Size = UDim2.fromOffset(L.titleH - 12, L.titleH - 12),
		Position = UDim2.new(1, -(L.titleH - 6), 0, 6),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = L.font,
		TextColor3 = C.text,
		Text = "✕",
		AutoButtonColor = true,
	}, titleBar)
	corner(closeBtn, 8)
	closeBtn.MouseButton1Click:Connect(function()
		safe(setUIVisible, false)
	end)

	makeDraggable(titleBar, main)

	-- Contentor de abas
	local tabBar = new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, main)

	if tablet then
		tabBar.Position = UDim2.new(0, 0, 0, L.titleH)
		tabBar.Size = UDim2.new(0, L.sideW, 1, -(L.titleH + L.footerH))
	else
		tabBar.Position = UDim2.new(0, 0, 0, L.titleH)
		tabBar.Size = UDim2.new(1, 0, 0, L.tabH)
	end

	new("UIListLayout", {
		Padding = UDim.new(0, tablet and 6 or 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = tablet and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
	}, tabBar)
	new("UIPadding", {
		PaddingTop = UDim.new(0, tablet and 8 or 4),
		PaddingLeft = UDim.new(0, tablet and 6 or 4),
		PaddingRight = UDim.new(0, tablet and 6 or 4),
	}, tabBar)

	-- Área de conteúdo
	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
	}, main)
	if tablet then
		content.Position = UDim2.new(0, L.sideW, 0, L.titleH)
		content.Size = UDim2.new(1, -L.sideW, 1, -(L.titleH + L.footerH))
	else
		content.Position = UDim2.new(0, 0, 0, L.titleH + L.tabH)
		content.Size = UDim2.new(1, 0, 1, -(L.titleH + L.tabH + L.footerH))
	end

	-- Rodapé com estado
	local footer = new("Frame", {
		Position = UDim2.new(0, 0, 1, -L.footerH),
		Size = UDim2.new(1, 0, 0, L.footerH),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, main)
	corner(footer, 12)
	State.statusLabel = label(footer, "Pronto.", UDim2.new(1, -16, 1, 0), UDim2.new(0, 12, 0, 0), 11, Enum.Font.GothamMedium, C.muted)

	-- Páginas
	local pagePlayer = newPage("Player", content)
	local pageVehicles = newPage("Veiculos", content)
	local pageScriptBlox = newPage("ScriptBlox", content)
	local pageEmotes = newPage("Emotes", content)
	local pageTools = newPage("Ferramentas", content)
	local pageSettings = newPage("Settings", content)

	local tabDefs = {
		{ key = "Player", label = tablet and "Player & Física" or "Player", page = pagePlayer },
		{ key = "Veiculos", label = tablet and "Veículos" or "Veíc.", page = pageVehicles },
		{ key = "ScriptBlox", label = tablet and "ScriptBlox" or "S.Blox", page = pageScriptBlox },
		{ key = "Emotes", label = tablet and "Animações" or "Emotes", page = pageEmotes },
		{ key = "Ferramentas", label = tablet and "Utilitários" or "Utils", page = pageTools },
		{ key = "Settings", label = "Settings", page = pageSettings },
	}

	for _, def in ipairs(tabDefs) do
		local b = new("TextButton", {
			Size = tablet and UDim2.new(1, 0, 0, L.rowH) or UDim2.new(0.166, -3, 1, -8),
			BackgroundColor3 = C.item,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Enum.Font.GothamBold,
			TextSize = L.font - 2,
			TextColor3 = C.text,
			Text = def.label,
		}, tabBar)
		corner(b, 8)
		b.MouseButton1Click:Connect(function()
			selectTab(def.key)
		end)
		table.insert(Tabs, { key = def.key, button = b, page = def.page })
	end

	-- ---------- ABA: PLAYER & FÍSICA ----------
	sectionLabel(pagePlayer, "Mobilidade")
	makeToggle(pagePlayer, "Fly", false, function(v)
		setFly(v)
		notify(v and "Fly ativo." or "Fly desativado.")
	end)

	local flyRow = new("Frame", {
		Size = UDim2.new(1, -6, 0, L.rowH),
		BackgroundTransparency = 1,
	}, pagePlayer)

	local upBtn = new("TextButton", {
		Size = UDim2.new(0.5, -3, 1, 0),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = L.font,
		TextColor3 = C.text,
		Text = "▲ Subir",
	}, flyRow)
	corner(upBtn, 8)
	upBtn.MouseButton1Down:Connect(function() State.flyUp = true end)
	upBtn.MouseButton1Up:Connect(function() State.flyUp = false end)

	local downBtn = new("TextButton", {
		Size = UDim2.new(0.5, -3, 1, 0),
		Position = UDim2.new(0.5, 3, 0, 0),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = L.font,
		TextColor3 = C.text,
		Text = "▼ Descer",
	}, flyRow)
	corner(downBtn, 8)
	downBtn.MouseButton1Down:Connect(function() State.flyDown = true end)
	downBtn.MouseButton1Up:Connect(function() State.flyDown = false end)

	makeNumberInput(pagePlayer, "Velocidade do Fly", "FlySpeed", 10, 300, nil)
	makeNumberInput(pagePlayer, "WalkSpeed", "WalkSpeed", 0, 500, applyStats)
	makeNumberInput(pagePlayer, "JumpPower", "JumpPower", 0, 500, applyStats)
	makeToggle(pagePlayer, "Noclip", false, function(v)
		setNoclip(v)
		notify(v and "Noclip ativo." or "Noclip desativado.")
	end)
	makeToggle(pagePlayer, "God Mode", false, function(v)
		setGodMode(v)
	end)

	sectionLabel(pagePlayer, "Física do Mapa")
	makeNumberInput(pagePlayer, "Gravidade", "Gravity", 0, 1000, applyStats)
	button(pagePlayer, "Restaurar Padrões de Física", function()
		for _, k in ipairs({ "WalkSpeed", "JumpPower", "Gravity", "FlySpeed" }) do
			Config[k] = DEFAULTS[k]
		end
		applyStats()
		applyAccent()
		safe(saveConfig)
		notify("Físicas restauradas.")
	end)

	-- ---------- ABA: VEÍCULOS (GITHUB LINKS) ----------
	sectionLabel(pageVehicles, "Spawns (Repositório GitHub)")
	
	button(pageVehicles, "Carros", function()
		safe(function()
			local url = "https://raw.githubusercontent.com/pmiguel10766-stack/-hacker-script/refs/heads/main/Carros.lua"
			loadstring(game:HttpGet(url))()
			notify("Script de Carros executado.")
		end)
	end)

	button(pageVehicles, "Submarino", function()
		safe(function()
			local url = "https://raw.githubusercontent.com/pmiguel10766-stack/-hacker-script/refs/heads/main/Submarino.lua"
			loadstring(game:HttpGet(url))()
			notify("Script de Submarino executado.")
		end)
	end)

	button(pageVehicles, "Avião", function()
		safe(function()
			local url = "https://raw.githubusercontent.com/pmiguel10766-stack/-hacker-script/refs/heads/main/Avi%C3%A3o.lua"
			loadstring(game:HttpGet(url))()
			notify("Script de Avião executado.")
		end)
	end)

	local vehicleHint = label(pageVehicles, "Carrega num dos botões para injetar e executar o respetivo script diretamente do teu repositório GitHub.", UDim2.new(1, -6, 0, 44), nil, L.font - 2, Enum.Font.GothamMedium, C.muted)
	vehicleHint.TextWrapped = true
	vehicleHint.TextYAlignment = Enum.TextYAlignment.Top

	-- ---------- ABA: SCRIPTBLOX (BUSCA POR JOGO) ----------
	sectionLabel(pageScriptBlox, "Informações do Jogo Atual")
	
	local gameName = "Carregando..."
	local gameId = game.PlaceId
	local okName, info = pcall(function()
		return MarketplaceService:GetProductInfo(gameId)
	end)
	if okName and info and info.Name then
		gameName = info.Name
	end

	local infoBox = new("Frame", {
		Size = UDim2.new(1, -6, 0, L.rowH * 2 + 6),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
	}, pageScriptBlox)
	corner(infoBox, 8)

	label(infoBox, "Jogo: " .. gameName, UDim2.new(1, -20, 0, L.rowH), UDim2.new(0, 10, 0, 4), L.font, Enum.Font.GothamBold, C.text)
	label(infoBox, "PlaceID: " .. tostring(gameId), UDim2.new(1, -20, 0, L.rowH), UDim2.new(0, 10, 0, L.rowH + 4), L.font - 1, Enum.Font.Code, C.silver)

	sectionLabel(pageScriptBlox, "Pesquisa Rápida ScriptBlox")
	
	local searchRow = new("Frame", {
		Size = UDim2.new(1, -6, 0, L.rowH),
		BackgroundTransparency = 1,
	}, pageScriptBlox)

	local searchBox = new("TextBox", {
		Size = UDim2.new(0.7, -3, 1, 0),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = L.font - 1,
		TextColor3 = C.text,
		PlaceholderText = "Nome do jogo ou script...",
		ClearTextOnFocus = false,
		Text = gameName ~= "Carregando..." and gameName or "",
	}, searchRow)
	corner(searchBox, 8)

	local searchBtn = new("TextButton", {
		Size = UDim2.new(0.3, -3, 1, 0),
		Position = UDim2.new(0.7, 3, 0, 0),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = L.font - 1,
		TextColor3 = C.text,
		Text = "Buscar",
		AutoButtonColor = true,
	}, searchRow)
	corner(searchBtn, 8)

	themed(searchBtn, "BackgroundColor3")
	table.insert(Refreshers, function()
		searchBtn.BackgroundColor3 = accent()
	end)

	local resultsContainer = new("ScrollingFrame", {
		Size = UDim2.new(1, -6, 0, 160),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	}, pageScriptBlox)
	corner(resultsContainer, 8)

	new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, resultsContainer)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, resultsContainer)

	local function populateResults(queryText)
		for _, child in ipairs(resultsContainer:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local query = string.lower(queryText or "")
		local url = "https://scriptblox.com/api/script/search?q=" .. HttpService:UrlEncode(query ~= "" and query or gameName)
		
		task.spawn(function()
			local ok, res = pcall(function()
				return game:HttpGet(url)
			end)
			if ok and res then
				local okDec, data = pcall(function()
					return HttpService:JSONDecode(res)
				end)
				if okDec and data and data.result and data.result.scripts then
					local scripts = data.result.scripts
					if #scripts == 0 then
						label(resultsContainer, "Nenhum script encontrado.", UDim2.new(1, 0, 0, 30), nil, L.font - 1, Enum.Font.GothamMedium, C.muted, Enum.TextXAlignment.Center)
						return
					end
					for _, scr in ipairs(scripts) do
						local itemBtn = new("TextButton", {
							Size = UDim2.new(1, 0, 0, 36),
							BackgroundColor3 = C.bg,
							BorderSizePixel = 0,
							Font = Enum.Font.GothamBold,
							TextSize = L.font - 2,
							TextColor3 = C.text,
							Text = "  " .. tostring(scr.title or "Sem título") .. " (" .. (scr.game and scr.game.name or "Geral") .. ")",
							TextXAlignment = Enum.TextXAlignment.Left,
							AutoButtonColor = true,
						}, resultsContainer)
						corner(itemBtn, 6)
						itemBtn.MouseButton1Click:Connect(function()
							if scr.script then
								local okLoad, errLoad = pcall(function()
									loadstring(scr.script)()
								end)
								if okLoad then
									notify("Script injetado com sucesso!")
								else
									notify("Erro ao injetar script.")
									warn("[PMX] ScriptBlox Error: " .. tostring(errLoad))
								end
							else
								notify("Código do script indisponível.")
							end
						end)
					end
					return
				end
			end
			label(resultsContainer, "Falha ao buscar scripts.", UDim2.new(1, 0, 0, 30), nil, L.font - 1, Enum.Font.GothamMedium, C.muted, Enum.TextXAlignment.Center)
		end)
	end

	searchBtn.MouseButton1Click:Connect(function()
		populateResults(searchBox.Text)
	end)

	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			populateResults(searchBox.Text)
		end
	end)

	task.spawn(function()
		task.wait(0.5)
		populateResults(gameName)
	end)

	-- ---------- ABA: ANIMAÇÕES & EMOTES ----------
	sectionLabel(pageEmotes, "Emotes Universais")
	button(pageEmotes, "Carregar Universal Emote Script", function()
		safe(function()
			local url = "https://scriptblox.com/raw/Universal-Script-7yd7-I-Emote-Script-48024"
			loadstring(game:HttpGet(url))()
			notify("Script de Emotes injetado com sucesso!")
		end)
	end)

	local emotesHint = label(pageEmotes, "Este botão executa o script universal de emotes do ScriptBlox para realizares animações e danças em qualquer jogo.", UDim2.new(1, -6, 0, 50), nil, L.font - 2, Enum.Font.GothamMedium, C.muted)
	emotesHint.TextWrapped = true
	emotesHint.TextYAlignment = Enum.TextYAlignment.Top

	-- ---------- ABA: FERRAMENTAS & UTILITÁRIOS ----------
	sectionLabel(pageTools, "Visual, Câmera & Performance")
	makeToggle(pageTools, "Fullbright", false, function(v)
		setFullbright(v)
		notify(v and "Fullbright ativo." or "Fullbright desativado.")
	end)
	makeToggle(pageTools, "Visão Noturna", false, function(v)
		setNightVision(v)
		notify(v and "Visão noturna ativa." or "Visão noturna desativada.")
	end)
	makeToggle(pageTools, "Câmera Livre (Freecam)", false, function(v)
		setFreecam(v)
	end)
	button(pageTools, "Clear Lag / Debris (Otimizar)", function()
		clearLag()
	end)
	button(pageTools, "Abrir Consola de Desenvolvedor", function()
		safe(function()
			StarterGui:SetCore("DevConsoleVisible", true)
			notify("Consola aberta.")
		end)
	end)
	button(pageTools, "Parar Todos os Scripts (Stop All)", function()
		stopAllScripts()
	end, C.danger)

	sectionLabel(pageTools, "Utilitários")
	makeToggle(pageTools, "Anti-AFK", Config.AntiAFK, setAntiAFK)
	makeToggle(pageTools, "Telemetria", false, function(v)
		State.telemetry = v
		if State.telemetryLabel then
			State.telemetryLabel.Visible = v
		end
	end)

	local telemetryLabel = label(pageTools, "", UDim2.new(1, -6, 0, 60), nil, L.font - 2, Enum.Font.Code, C.silver)
	telemetryLabel.TextWrapped = true
	telemetryLabel.TextYAlignment = Enum.TextYAlignment.Top
	telemetryLabel.Visible = false
	State.telemetryLabel = telemetryLabel

	sectionLabel(pageTools, "Sistema de Waypoints")
	button(pageTools, "Salvar Waypoint Atual", function()
		local _, root = getHumanoid()
		if root then
			local wpName = "Ponto " .. (#Waypoints + 1)
			table.insert(Waypoints, { name = wpName, cf = root.CFrame })
			notify("Waypoint salvo: " .. wpName)
		else
			notify("Sem personagem.")
		end
	end)

	local wpScroll = new("ScrollingFrame", {
		Size = UDim2.new(1, -6, 0, 110),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	}, pageTools)
	corner(wpScroll, 8)

	new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, wpScroll)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, wpScroll)

	local function refreshWaypoints()
		for _, child in ipairs(wpScroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		if #Waypoints == 0 then
			label(wpScroll, "Nenhum waypoint guardado.", UDim2.new(1, 0, 0, 30), nil, L.font - 1, Enum.Font.GothamMedium, C.muted, Enum.TextXAlignment.Center)
			return
		end

		for i, wp in ipairs(Waypoints) do
			local wpBtn = new("TextButton", {
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundColor3 = C.bg,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamMedium,
				TextSize = L.font - 2,
				TextColor3 = C.text,
				Text = "  Ir para: " .. wp.name,
				TextXAlignment = Enum.TextXAlignment.Left,
				AutoButtonColor = true,
			}, wpScroll)
			corner(wpBtn, 6)
			wpBtn.MouseButton1Click:Connect(function()
				local _, root = getHumanoid()
				if root then
					root.CFrame = wp.cf
					notify("Teleportado para " .. wp.name)
				else
					notify("Sem personagem.")
				end
			end)
		end
	end

	button(pageTools, "Atualizar Lista de Waypoints", refreshWaypoints)
	task.spawn(refreshWaypoints)

	sectionLabel(pageTools, "Teleporte para Jogadores")
	local tpScroll = new("ScrollingFrame", {
		Size = UDim2.new(1, -6, 0, 130),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	}, pageTools)
	corner(tpScroll, 8)

	new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tpScroll)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, tpScroll)

	local function refreshPlayerList()
		for _, child in ipairs(tpScroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then
				local pBtn = new("TextButton", {
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundColor3 = C.bg,
					BorderSizePixel = 0,
					Font = Enum.Font.GothamMedium,
					TextSize = L.font - 2,
					TextColor3 = C.text,
					Text = "  Tp para: " .. p.Name,
					TextXAlignment = Enum.TextXAlignment.Left,
					AutoButtonColor = true,
				}, tpScroll)
				corner(pBtn, 6)
				pBtn.MouseButton1Click:Connect(function()
					local _, root = getHumanoid()
					local targetChar = p.Character
					local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
					if root and targetRoot then
						root.CFrame = targetRoot.CFrame + Vector3.new(0, 3, 0)
						notify("Teleportado para " .. p.Name)
					else
						notify("Não foi possível encontrar o jogador.")
					end
				end)
			end
		end
	end

	button(pageTools, "Atualizar Lista de Jogadores", refreshPlayerList)
	task.spawn(refreshPlayerList)

	sectionLabel(pageTools, "Posição")
	button(pageTools, "Salvar Posição", function()
		local _, root = getHumanoid()
		if root then
			State.savedCFrame = root.CFrame
			notify("Posição salva.")
		else
			notify("Sem personagem.")
		end
	end)
	button(pageTools, "Voltar à Posição Salva", function()
		local char = LocalPlayer.Character
		if char and State.savedCFrame then
			char:PivotTo(State.savedCFrame)
			notify("Retornado à posição salva.")
		else
			notify("Nenhuma posição salva.")
		end
	end)
	button(pageTools, "Explosão Visual (sem força)", function()
		local _, root = getHumanoid()
		if not root then
			return notify("Sem personagem.")
		end
		new("Explosion", {
			Position = root.Position + Vector3.new(0, 0, -8),
			BlastRadius = 8,
			BlastPressure = 0,
			DestroyJointRadiusPercent = 0,
		}, workspace)
		notify("Explosão visual criada.")
	end)
	button(pageTools, "Resetar Personagem", function()
		local char = LocalPlayer.Character
		if char then
			char:BreakJoints()
		end
	end, C.danger)

	-- ---------- ABA: SETTINGS ----------
	sectionLabel(pageSettings, "Painel de Informações do Jogador")
	
	local statsBox = new("Frame", {
		Size = UDim2.new(1, -6, 0, L.rowH * 2 + 6),
		BackgroundColor3 = C.item,
		BorderSizePixel = 0,
	}, pageSettings)
	corner(statsBox, 8)

	local statsLabel = label(statsBox, "FPS: -- | Ping: -- ms\nMemória: -- MB", UDim2.new(1, -20, 1, 0), UDim2.new(0, 10, 0, 0), L.font - 1, Enum.Font.Code, C.silver, Enum.TextXAlignment.Left)
	statsLabel.TextYAlignment = Enum.TextYAlignment.Center
	State.statsLabel = statsLabel

	sectionLabel(pageSettings, "Tema")
	label(pageSettings, "Cor de destaque (Accent Color)", UDim2.new(1, -6, 0, L.rowH - 10), nil, L.font, Enum.Font.GothamMedium, C.text)

	local swatchRow = new("Frame", {
		Size = UDim2.new(1, -6, 0, L.rowH),
		BackgroundTransparency = 1,
	}, pageSettings)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, swatchRow)

	for i, acc in ipairs(ACCENTS) do
		local sw = new("TextButton", {
			Size = UDim2.new(1 / #ACCENTS, -4, 1, 0),
			BackgroundColor3 = acc.color,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = true,
		}, swatchRow)
		corner(sw, 8)
		sw.MouseButton1Click:Connect(function()
			Config.AccentIndex = i
			applyAccent()
			selectTab(State.currentTab)
			safe(saveConfig)
			notify("Cor: " .. acc.name)
		end)
	end

	sectionLabel(pageSettings, "Workspace (Delta)")
	local cfgRow = new("Frame", {
		Size = UDim2.new(1, -6, 0, L.rowH),
		BackgroundTransparency = 1,
	}, pageSettings)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, cfgRow)

	local function cfgButton(text, action)
		local b = new("TextButton", {
			Size = UDim2.new(1 / 3, -4, 1, 0),
			BackgroundColor3 = C.item,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			TextSize = L.font - 2,
			TextColor3 = C.text,
			Text = text,
			AutoButtonColor = true,
		}, cfgRow)
		corner(b, 8)
		b.MouseButton1Click:Connect(function()
			safe(function()
				local ok, msg = action()
				notify(msg or (ok and "OK" or "Falha"))
				applyAccent()
				applyStats()
			end)
		end)
	end

	cfgButton("Save", saveConfig)
	cfgButton("Load", loadConfig)
	cfgButton("Reset", function()
		local ok, msg = resetConfig()
		return ok, "Padrões restaurados. " .. tostring(msg)
	end)

	sectionLabel(pageSettings, "Interface")
	label(pageSettings, "Atalho: RightControl mostra/oculta o painel.", UDim2.new(1, -6, 0, L.rowH - 10), nil, L.font - 2, Enum.Font.GothamMedium, C.muted)
	button(pageSettings, "Mostrar / Ocultar Painel", toggleUI)
	button(pageSettings, "Unload GUI (Emergência)", unloadPanel, C.danger)

	-- ---------- BOTÃO FLUTUANTE PMX ----------
	local toggleBtn = new("TextButton", {
		Name = "PMX_ToggleButton",
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(0, 10, 0.5, -28),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, gui)
	corner(toggleBtn, 28)
	themed(stroke(toggleBtn, C.silver, 1.5), "Color")

	local toggleLogo = label(toggleBtn, "PMX", UDim2.new(1, 0, 1, 0), nil, 15, Enum.Font.GothamBlack, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
	toggleLogo.TextYAlignment = Enum.TextYAlignment.Center
	logoGradient(toggleLogo)

	makeDraggable(toggleBtn, toggleBtn, toggleUI)

	-- ---------- ANIMAÇÃO DE CARREGAMENTO ----------
	selectTab("Player")

	task.spawn(function()
		local tween = TweenService:Create(barFill, TweenInfo.new(1.8, Enum.EasingStyle.Quad), {
			Size = UDim2.new(1, 0, 1, 0),
		})
		tween:Play()
		task.wait(2)
		if State.unloaded then
			return
		end
		loader.Visible = false
		setUIVisible(true)
		notify(State.loadMessage)
	end)

	return gui
end

-- ============================================================
-- INICIALIZAÇÃO E LOOP DE STATS
-- ============================================================
track(UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightControl then
		toggleUI()
	end
end))

track(LocalPlayer.Idled:Connect(function()
	if State.antiAFK then
		antiAFKPulse()
	end
end))

local lastTick = tick()
local frameCount = 0
local currentFps = 60

track(RunService.RenderStepped:Connect(function()
	frameCount += 1
	local now = tick()
	if now - lastTick >= 1 then
		currentFps = math.floor(frameCount / (now - lastTick) + 0.5)
		frameCount = 0
		lastTick = now

		if State.statsLabel and State.statsLabel.Parent then
			local ping = 0
			safe(function()
				ping = math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5)
			end)
			local mem = 0
			safe(function()
				mem = math.floor(StatsService:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Internal) + 0.5)
			end)
			State.statsLabel.Text = string.format("FPS: %d  |  Ping: %d ms\nMemória Interna: %d MB", currentFps, ping, mem)
		end
	end
end))

track(LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	safe(applyStats)
	if State.fullbright then
		safe(setFullbright, true)
	end
	if State.noclip then
		safe(setNoclip, true)
	end
	if State.flying then
		safe(setFly, true)
	end
	if State.godMode then
		safe(setGodMode, true)
	end
end))

task.spawn(function()
	safe(function()
		if type(ENV[ENV_KEY]) == "function" then
			ENV[ENV_KEY]()
		end
	end)
	safe(destroyOldInstances)

	local okCfg, cfgMsg = loadConfig()
	local executorName = detectExecutor()

	local okBuild, errBuild = pcall(buildGui, executorName)
	if not okBuild then
		warn("[PMX] Falha ao construir a GUI: " .. tostring(errBuild))
		return
	end

	State.loadMessage = okCfg and cfgMsg or ("Aviso: " .. tostring(cfgMsg))

	if Config.AntiAFK then
		setAntiAFK(true)
	end
	if Config.GodMode then
		setGodMode(true)
	end
	safe(applyStats)
	applyAccent()

	ENV[ENV_KEY] = unloadPanel
end)
