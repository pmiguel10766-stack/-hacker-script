--[[ ============================================================
  FLIPPER ZERO VIRTUAL GUI  |  Luau (Delta Executor / Roblox)
  Tudo corre no CLIENTE: os efeitos só são vistos por ti.
  Controlos: botões tácteis, ou teclado (↑ ↓ Enter Backspace M).
============================================================ ]]

-- [1] SERVIÇOS E VARIÁVEIS GERAIS
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player   = Players.LocalPlayer
local GUI_NAME = "FlipperZeroVirtual"
local alive    = true
local connections = {}

local CFG    = { radius = 30, sound = true, doorTime = 5 }
local RADII  = { 20, 30, 50, 80 }
local ROWS   = 5 -- linhas visíveis no ecrã LCD

-- Palavras-chave para detetar objetos no Workspace
local DOOR_KEYS   = { "door", "porta", "gate", "portao", "barrier", "cancela", "barreira" }
local READER_KEYS = { "reader", "leitor", "keycard", "scanner", "badge" }
local TAG_KEYS    = { "card", "keycard", "badge", "tag", "cartao" }

-- [2] LIMPA INSTÂNCIAS ANTIGAS
local function getParent()
	local ok, ui = pcall(function() return gethui and gethui() end)
	if ok and ui then return ui end
	return game:GetService("CoreGui")
end
for _, p in ipairs({ player:WaitForChild("PlayerGui"), game:GetService("CoreGui") }) do
	local old = p:FindFirstChild(GUI_NAME)
	if old then old:Destroy() end
end

-- [3] HELPERS DE UI
local function make(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then o[k] = v end
	end
	if props.Parent then o.Parent = props.Parent end
	return o
end

local ORANGE = Color3.fromRGB(255, 136, 0)
local BLACK  = Color3.fromRGB(20, 20, 20)

local gui = make("ScreenGui", { Name = GUI_NAME, ResetOnSpawn = false, DisplayOrder = 999 })
if not pcall(function() gui.Parent = getParent() end) then
	gui.Parent = player.PlayerGui
end

local beep = make("Sound", { SoundId = "rbxasset://sounds/switch.mp3", Volume = 0.4, Parent = gui })
local function click()
	if CFG.sound then pcall(function() beep:Play() end) end
end

-- [4] CORPO DO FLIPPER
local main = make("Frame", {
	Size = UDim2.fromOffset(270, 430), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(236, 236, 236),
	Parent = gui,
})
make("UICorner", { CornerRadius = UDim.new(0, 28), Parent = main })
make("UIStroke", { Color = Color3.fromRGB(170, 170, 170), Thickness = 2, Parent = main })
local scale = make("UIScale", { Parent = main })
do -- ajusta o tamanho a ecrãs pequenos (telemóvel)
	local cam = workspace.CurrentCamera
	if cam then scale.Scale = math.clamp(cam.ViewportSize.Y / 600, 0.65, 1) end
end

-- Barra de arrastar + fechar
local header = make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Active = true, Parent = main })
make("TextLabel", {
	Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(16, 0), BackgroundTransparency = 1,
	Text = "FLIPPER ZERO", TextColor3 = Color3.fromRGB(120, 120, 120), Font = Enum.Font.Code,
	TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
})

-- Ecrã LCD
local bezel = make("Frame", { Size = UDim2.fromOffset(240, 158), Position = UDim2.fromOffset(15, 32), BackgroundColor3 = BLACK, Parent = main })
make("UICorner", { CornerRadius = UDim.new(0, 10), Parent = bezel })
local lcd = make("Frame", {
	Size = UDim2.fromOffset(232, 150), Position = UDim2.fromOffset(4, 4),
	BackgroundColor3 = ORANGE, ClipsDescendants = true, Parent = bezel,
})
make("UICorner", { CornerRadius = UDim.new(0, 6), Parent = lcd })

local function lcdLabel(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = BLACK
	props.Font = Enum.Font.Code
	props.TextXAlignment = Enum.TextXAlignment.Left
	props.TextYAlignment = Enum.TextYAlignment.Top
	props.Parent = lcd
	return make("TextLabel", props)
end

local titleLabel = lcdLabel({ Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(6, 2), TextSize = 13, Text = "Flipper" })
local battLabel  = lcdLabel({ Size = UDim2.fromOffset(60, 16), Position = UDim2.fromOffset(166, 2), TextSize = 12, Text = "100%[=]", TextXAlignment = Enum.TextXAlignment.Right })
make("Frame", { Size = UDim2.new(1, -8, 0, 1), Position = UDim2.fromOffset(4, 19), BackgroundColor3 = BLACK, BorderSizePixel = 0, Parent = lcd })
local listLabel  = lcdLabel({ Size = UDim2.fromOffset(222, 84), Position = UDim2.fromOffset(6, 22), TextSize = 13, Text = "" })
make("Frame", { Size = UDim2.new(1, -8, 0, 1), Position = UDim2.fromOffset(4, 108), BackgroundColor3 = BLACK, BorderSizePixel = 0, Parent = lcd })
local logLabel   = lcdLabel({ Size = UDim2.fromOffset(222, 38), Position = UDim2.fromOffset(6, 111), TextSize = 11, Text = "", TextWrapped = true })

-- [5] LOG ESTILO TERMINAL (efeito de escrita)
local logLines, logToken = {}, 0
local function log(msg)
	table.insert(logLines, "> " .. msg)
	while #logLines > 3 do table.remove(logLines, 1) end
	local prev = utf8.len(table.concat(logLines, "\n", 1, #logLines - 1)) or 0
	logLabel.Text = table.concat(logLines, "\n")
	local total = utf8.len(logLabel.Text) or 0
	logToken += 1
	local my = logToken
	logLabel.MaxVisibleGraphemes = prev
	task.spawn(function()
		for i = prev, total do
			if my ~= logToken or not alive then return end
			logLabel.MaxVisibleGraphemes = i
			task.wait(0.015)
		end
		logLabel.MaxVisibleGraphemes = -1
	end)
end

-- [6] FERRAMENTAS (SCAN, PORTAS, LUZES, RFID)
local function root()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- Partes dentro do raio (OverlapParams = rápido, sem lag)
local function nearbyParts(radius)
	local r = root()
	if not r then return {} end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { player.Character }
	op.MaxParts = 600
	return workspace:GetPartBoundsInRadius(r.Position, radius, op)
end

-- Verifica se o nome da parte (ou do pai) contém alguma palavra-chave
local function matches(part, keys)
	local names = { part.Name:lower() }
	if part.Parent and part.Parent ~= workspace then names[2] = part.Parent.Name:lower() end
	for _, n in ipairs(names) do
		for _, k in ipairs(keys) do
			if n:find(k, 1, true) then return true end
		end
	end
	return false
end

local function findTargets(keys, radius)
	local out = {}
	for _, p in ipairs(nearbyParts(radius)) do
		if matches(p, keys) then out[#out + 1] = p end
	end
	return out
end

-- Abre (atravessável + semitransparente) e restaura depois de doorTime
local active = {}
local function openPart(part)
	if active[part] then return end
	active[part] = true
	local oT, oC = part.Transparency, part.CanCollide
	part.CanCollide = false
	TweenService:Create(part, TweenInfo.new(0.3), { Transparency = math.max(oT, 0.7) }):Play()
	task.delay(CFG.doorTime, function()
		active[part] = nil
		if part.Parent then
			part.CanCollide = oC
			TweenService:Create(part, TweenInfo.new(0.3), { Transparency = oT }):Play()
		end
	end)
end

local function scanDoors()
	log("Sub-GHz 433.92MHz...")
	task.delay(0.4, function()
		log("Alvos: " .. #findTargets(DOOR_KEYS, CFG.radius))
	end)
end

local function openDoors(keys, label)
	local t = findTargets(keys, CFG.radius)
	if #t == 0 then log("Nenhum alvo no raio") return end
	for _, p in ipairs(t) do openPart(p) end
	log(label .. ": " .. #t .. " aberto(s)")
end

-- Luzes: alterna (value=nil) ou força ligado/desligado
local function setLights(radius, value)
	local n, seen = 0, {}
	for _, part in ipairs(nearbyParts(radius)) do
		for _, c in ipairs(part:GetChildren()) do
			if c:IsA("Light") and not seen[c] then
				seen[c] = true
				if value == nil then c.Enabled = not c.Enabled else c.Enabled = value end
				n += 1
			end
		end
	end
	log("IR TX: " .. n .. " luz(es)")
end

-- RFID
local saved = nil
local function fmtUid(n)
	n = n % 0x100000000
	return string.format("%02X:%02X:%02X:%02X",
		bit32.band(bit32.rshift(n, 24), 255), bit32.band(bit32.rshift(n, 16), 255),
		bit32.band(bit32.rshift(n, 8), 255), bit32.band(n, 255))
end
local function strHash(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 0x100000000 end
	return h
end

local function readTag()
	local r = root()
	if not r then log("Sem personagem") return end
	log("Lendo RFID 125kHz...")
	local best, bestD = nil, CFG.radius
	for _, pl in ipairs(Players:GetPlayers()) do
		local h = pl ~= player and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if h then
			local d = (h.Position - r.Position).Magnitude
			if d < bestD then bestD, best = d, { name = pl.Name, uid = fmtUid(pl.UserId) } end
		end
	end
	if not best then
		for _, p in ipairs(findTargets(TAG_KEYS, CFG.radius)) do
			local d = (p.Position - r.Position).Magnitude
			if d < bestD then bestD, best = d, { name = p.Name, uid = fmtUid(strHash(p:GetFullName())) } end
		end
	end
	task.delay(0.6, function()
		if not best then log("Nenhuma tag encontrada") return end
		saved = best
		log("Clonado: " .. best.name)
		log("UID " .. best.uid)
	end)
end

local function emulateTag()
	if not saved then log("Slot vazio") return end
	log("Emulando " .. saved.uid)
	task.delay(0.5, function()
		local keys = {}
		for _, k in ipairs(READER_KEYS) do keys[#keys + 1] = k end
		for _, k in ipairs(DOOR_KEYS) do keys[#keys + 1] = k end
		openDoors(keys, "Acesso OK")
	end)
end

-- [7] ECRÃS E MENUS
local gpio = { { "A7", false }, { "A6", false }, { "A4", false }, { "5V", false } }
local screens = {
	menu = { title = "Menu Principal", items = {
		{ label = "Sub-GHz",        go = "subghz" },
		{ label = "RFID / NFC",     go = "rfid" },
		{ label = "Infravermelho",  go = "ir" },
		{ label = "GPIO",           go = "gpio" },
		{ label = "Definicoes",     go = "settings" },
	} },
	subghz = { title = "Sub-GHz", items = {
		{ label = "Escanear portas", run = scanDoors },
		{ label = "Abrir portas",    run = function() openDoors(DOOR_KEYS, "Sinal enviado") end },
	} },
	rfid = { title = "RFID / NFC", items = {
		{ label = "Ler e clonar", run = readTag },
		{ label = "Emular",       run = emulateTag },
		{ label = function() return saved and ("Slot: " .. saved.uid) or "Slot: vazio" end,
		  run = function() saved = nil log("Slot limpo") end },
	} },
	ir = { title = "Infravermelho", items = {
		{ label = "Alternar luzes", run = function() setLights(CFG.radius, nil) end },
		{ label = "Acender todas",  run = function() setLights(100, true) end },
		{ label = "Apagar todas",   run = function() setLights(100, false) end },
	} },
	gpio = { title = "GPIO", items = {} },
	settings = { title = "Definicoes", items = {
		{ label = function() return "Som: " .. (CFG.sound and "ON" or "OFF") end,
		  run = function() CFG.sound = not CFG.sound end },
		{ label = function() return "Raio: " .. CFG.radius .. " studs" end,
		  run = function()
			local idx = table.find(RADII, CFG.radius) or 1
			CFG.radius = RADII[idx % #RADII + 1]
		  end },
		{ label = "Sobre", run = function() log("Flipper Virtual v1.0") end },
		{ label = "Fechar GUI", run = function() alive = false for _, c in ipairs(connections) do c:Disconnect() end gui:Destroy() end },
	} },
}
for i, pin in ipairs(gpio) do
	screens.gpio.items[i] = {
		label = function() return "Pin " .. pin[1] .. ": " .. (pin[2] and "HIGH" or "LOW") end,
		run = function() pin[2] = not pin[2] log("Pin " .. pin[1] .. " -> " .. (pin[2] and "HIGH" or "LOW")) end,
	}
end

-- Golfinho pixelizado (2 frames) + textos de estado
local DOLPHIN = {
	[=[
    _.--._
 .-'  o   `-.__
<   ______   __>
 `-.__..-'  `-']=],
	[=[
    _.--._
 .-'  -   `-.__
<   ______   __>
  `-.__..-'  `-']=],
}
local STATUS = { "Sub-GHz pronto", "Nivel 1 | XP 0/30", "Aperte OK" }
local frame, statusIdx = 1, 1

-- [8] NAVEGAÇÃO E RENDER
local state, sel, off, menuSel = "desktop", 1, 0, 1

local function render()
	if state == "desktop" then
		titleLabel.Text = "Flipper"
		listLabel.Text = DOLPHIN[frame] .. "\n" .. STATUS[statusIdx]
		return
	end
	local s = screens[state]
	titleLabel.Text = s.title
	local rows = {}
	for i = off + 1, math.min(#s.items, off + ROWS) do
		local it = s.items[i]
		local lbl = type(it.label) == "function" and it.label() or it.label
		rows[#rows + 1] = (i == sel and "> " or "  ") .. lbl
	end
	listLabel.Text = table.concat(rows, "\n")
end

local function openScreen(name, keepSel)
	state = name
	sel, off = keepSel or 1, 0
	if sel > ROWS then off = sel - ROWS end
	render()
end

local function move(d)
	if state == "desktop" then return end
	local n = #screens[state].items
	sel = (sel - 1 + d) % n + 1
	if sel <= off then off = sel - 1 end
	if sel > off + ROWS then off = sel - ROWS end
	render()
end

local function okPress()
	if state == "desktop" then openScreen("menu", menuSel) return end
	local it = screens[state].items[sel]
	if it.go then
		if state == "menu" then menuSel = sel end
		openScreen(it.go)
	elseif it.run then
		it.run()
		if alive then render() end
	end
end

local function backPress()
	if state == "desktop" then return end
	if state == "menu" then state = "desktop" render() else openScreen("menu", menuSel) end
end

local function menuPress() openScreen("menu", menuSel) end

-- [9] BOTÕES TÁCTEIS
local function button(parent, text, pos, size, bg, fg, cb)
	local b = make("TextButton", {
		Text = text, Position = pos, Size = size, BackgroundColor3 = bg, TextColor3 = fg,
		Font = Enum.Font.GothamBold, TextSize = 14, Parent = parent,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = b })
	b.Activated:Connect(function() click() cb() end)
	return b
end

local ring = make("Frame", { Size = UDim2.fromOffset(140, 140), Position = UDim2.fromOffset(15, 208), BackgroundColor3 = ORANGE, Parent = main })
make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
local clear = Color3.fromRGB(255, 255, 255)
local up = button(ring, "▲", UDim2.fromOffset(48, 6),  UDim2.fromOffset(44, 40), ORANGE, clear, function() move(-1) end)
local dn = button(ring, "▼", UDim2.fromOffset(48, 94), UDim2.fromOffset(44, 40), ORANGE, clear, function() move(1) end)
up.BackgroundTransparency, dn.BackgroundTransparency = 1, 1
button(ring, "OK", UDim2.fromOffset(42, 42), UDim2.fromOffset(56, 56), Color3.fromRGB(255, 175, 70), BLACK, okPress)

button(main, "MENU", UDim2.fromOffset(190, 222), UDim2.fromOffset(54, 54), ORANGE, BLACK, menuPress)
button(main, "BACK", UDim2.fromOffset(190, 300), UDim2.fromOffset(54, 54), ORANGE, BLACK, backPress)
make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 375), BackgroundTransparency = 1,
	Text = "FLIPPER", TextColor3 = ORANGE, Font = Enum.Font.Arcade, TextSize = 30, Parent = main,
})

-- Botão de fechar (X) no cabeçalho
local x = make("TextButton", {
	Text = "X", Size = UDim2.fromOffset(24, 20), Position = UDim2.new(1, -34, 0, 4), BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(120, 120, 120), Font = Enum.Font.GothamBold, TextSize = 14, Parent = header,
})
x.Activated:Connect(function()
	alive = false
	for _, c in ipairs(connections) do c:Disconnect() end
	gui:Destroy()
end)

-- [10] ARRASTAR O PAINEL (rato e toque)
local dragging, dragStart, startPos
header.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging, dragStart, startPos = true, i.Position, main.Position
		i.Changed:Connect(function()
			if i.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end
end)
table.insert(connections, UIS.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end))

-- [11] TECLADO (PC)
table.insert(connections, UIS.InputBegan:Connect(function(i, processed)
	if processed or not alive then return end
	local k = i.KeyCode
	if k == Enum.KeyCode.Up then move(-1)
	elseif k == Enum.KeyCode.Down then move(1)
	elseif k == Enum.KeyCode.Return then okPress()
	elseif k == Enum.KeyCode.Backspace then backPress()
	elseif k == Enum.KeyCode.M then menuPress() end
end))

-- [12] ANIMAÇÃO DO GOLFINHO (só no ecrã inicial)
task.spawn(function()
	local t = 0
	while alive do
		task.wait(0.5)
		if state == "desktop" then
			frame = frame % #DOLPHIN + 1
			t += 1
			if t % 4 == 0 then statusIdx = statusIdx % #STATUS + 1 end
			render()
		end
	end
end)

render()
log("Flipper Zero online")
