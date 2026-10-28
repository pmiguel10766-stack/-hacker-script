--[[
╔══════════════════════════════════════════════════════════════╗
║  RADAR TÁTICO 3D  •  v1.0  •  Compatível com Delta Executor ║
║  - Radar 3D Small (portátil) e Medium (estação detalhada)    ║
║  - Consola de monitor 3D com tela neon (SurfaceGui)          ║
║  - Painel flutuante arrastável (mobile e PC)                 ║
║  - Modos: 1 Jogadores | 2 Tudo | 3 Mapa vetorial             ║
╚══════════════════════════════════════════════════════════════╝
]]

---------------------------------------------------------------
-- 0) SERVIÇOS
---------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local StarterGui       = game:GetService("StarterGui")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

---------------------------------------------------------------
-- 1) EVITA DUPLICAR: se já estiver rodando, remove a versão antiga
---------------------------------------------------------------
local GENV = (getgenv and getgenv()) or _G
if GENV.RadarTatico3D and GENV.RadarTatico3D.Destroy then
	pcall(GENV.RadarTatico3D.Destroy)
end

---------------------------------------------------------------
-- 2) CONFIGURAÇÕES (edite à vontade)
---------------------------------------------------------------
local CONFIG = {
	RANGE         = 300,   -- alcance do radar em studs
	SCAN_RATE     = 0.25,  -- segundos entre atualizações dos jogadores/veículos
	ENV_RATE      = 1.0,   -- segundos entre varreduras do ambiente (partes)
	MAX_PARTS     = 120,   -- máximo de partes do ambiente desenhadas
	MIN_PART_SIZE = 6,     -- ignora partes menores que isso (studs)
	SPIN = { Small = 120, Medium = 60 }, -- velocidade da antena (graus/segundo)
}

-- Paleta de cores
local NEON       = Color3.fromRGB(0, 255, 170)
local COL = {
	dark     = Color3.fromRGB(35, 38, 42),
	gray     = Color3.fromRGB(110, 115, 120),
	light    = Color3.fromRGB(200, 205, 210),
	olive    = Color3.fromRGB(78, 92, 62),
	concrete = Color3.fromRGB(140, 140, 135),
	white    = Color3.fromRGB(235, 238, 240),
	yellow   = Color3.fromRGB(255, 205, 40),
	red      = Color3.fromRGB(255, 50, 50),
}
local COL_PLAYER = Color3.fromRGB(60, 255, 90)
local COL_SELF   = Color3.fromRGB(255, 255, 255)
local COL_VEHICLE= Color3.fromRGB(255, 215, 40)
local COL_ENV    = Color3.fromRGB(0, 190, 230)
local COL_BTN_ON = Color3.fromRGB(0, 140, 100)
local COL_BTN_OFF= Color3.fromRGB(35, 50, 60)

local MODE_NAMES = { "JOGADORES", "TUDO", "MAPA" }
local COMPASS    = { "N", "NE", "L", "SE", "S", "SO", "O", "NO" }

---------------------------------------------------------------
-- 3) ESTADO GLOBAL DO SCRIPT
---------------------------------------------------------------
local State = {
	connections  = {},   -- conexões para desligar ao fechar
	folder       = nil,  -- pasta no Workspace com os modelos 3D
	rotor        = nil,  -- modelo que gira (antena)
	rotorBase    = nil,  -- CFrame do eixo de rotação
	origin       = nil,  -- posição (Vector3) do radar no mundo
	size         = nil,  -- "Small" ou "Medium"
	angle        = 0,    -- ângulo atual da antena (graus)
	spin         = 0,    -- velocidade de giro
	mode         = 1,    -- modo do monitor (1, 2 ou 3)
	beaconTween  = nil,
	gui          = nil,
	visor        = nil,  -- display do painel na tela
	surface      = nil,  -- display do monitor 3D
	modeButtons  = {},
	sizeButtons  = {},
	env          = {},   -- partes do ambiente em cache
	vehicleSeats = {},   -- VehicleSeats conhecidos
}

---------------------------------------------------------------
-- 4) FUNÇÕES UTILITÁRIAS
---------------------------------------------------------------
-- Guarda conexões para limpar depois
local function track(conn)
	table.insert(State.connections, conn)
	return conn
end

-- Cria uma instância já com propriedades e pai
local function create(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

-- Notificação no canto da tela (protegida com pcall)
local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Radar 3D", Text = text, Duration = 3 })
	end)
end

-- Número inteiro em texto
local function fmt(n) return tostring(math.floor(n + 0.5)) end

-- Direção cardeal (N, NE, L...) a partir do deslocamento no plano XZ
local function compass(dx, dz)
	local ang = math.deg(math.atan2(dx, -dz)) % 360
	local idx = math.floor((ang + 22.5) / 45) % 8 + 1
	return COMPASS[idx]
end

-- Escolhe onde colocar a GUI (gethui é o mais seguro no Delta)
local function getGuiParent()
	local ok, ui = pcall(function() return gethui and gethui() end)
	if ok and ui then return ui end
	local ok2, core = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and core then
		local test = Instance.new("Folder")
		local canParent = pcall(function() test.Parent = core end)
		test:Destroy()
		if canParent then return core end
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

-- Cria uma Part ancorada (tudo no radar é ancorado)
local function newPart(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	if extra then
		for k, v in pairs(extra) do p[k] = v end
	end
	p.Parent = parent
	return p
end

-- Cilindro VERTICAL (o cilindro do Roblox tem eixo no X, giramos 90° em Z)
local function cylinder(parent, name, cf, height, diameter, color, material, extra)
	extra = extra or {}
	extra.Shape = Enum.PartType.Cylinder
	return newPart(parent, name, Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.rad(90)), color, material, extra)
end

-- Cilindro com eixo no Z (usado nas parabólicas, que "olham" para -Z)
local function cylinderZ(parent, name, cf, length, diameter, color, material, extra)
	extra = extra or {}
	extra.Shape = Enum.PartType.Cylinder
	return newPart(parent, name, Vector3.new(length, diameter, diameter),
		cf * CFrame.Angles(0, math.rad(90), 0), color, material, extra)
end

---------------------------------------------------------------
-- 5) DISPLAY (usado no monitor 3D e no visor do painel)
--    Contém: título, mapa com anéis + varredura + blips, e lista de texto
---------------------------------------------------------------
local function buildDisplay(parent, w, h)
	local u = h / 190                                   -- fator de escala
	local function px(n) return math.max(1, math.floor(n * u + 0.5)) end
	local d = { u = u }

	-- Fundo
	local root = create("Frame", {
		Name = "Display", Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Color3.fromRGB(3, 14, 12),
		BorderSizePixel = 0, ClipsDescendants = true,
	}, parent)
	create("UICorner", { CornerRadius = UDim.new(0, px(6)) }, root)
	create("UIStroke", { Color = NEON, Thickness = math.max(1, u), Transparency = 0.2 }, root)
	d.root = root

	-- Título
	local header = create("TextLabel", {
		Size = UDim2.new(1, -px(12), 0, px(20)), Position = UDim2.fromOffset(px(6), px(3)),
		BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = px(13),
		TextColor3 = NEON, TextXAlignment = Enum.TextXAlignment.Left, Text = "RADAR",
	}, root)

	-- Mapa (quadrado)
	local s = h - px(30)
	d.mapPx = s
	local map = create("Frame", {
		Size = UDim2.fromOffset(s, s), Position = UDim2.fromOffset(px(6), px(26)),
		BackgroundColor3 = Color3.fromRGB(2, 10, 8), BorderSizePixel = 0,
		ClipsDescendants = true,
	}, root)
	create("UIStroke", { Color = Color3.fromRGB(0, 120, 90), Thickness = 1 }, map)

	-- Anéis de distância
	for _, f in ipairs({ 1, 0.66, 0.33 }) do
		local ring = create("Frame", {
			Size = UDim2.fromScale(f, f), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
		}, map)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		create("UIStroke", { Color = Color3.fromRGB(0, 120, 90), Thickness = 1, Transparency = 0.3 }, ring)
	end
	-- Linhas em cruz
	create("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(0, 110, 85), BackgroundTransparency = 0.5, BorderSizePixel = 0 }, map)
	create("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(0, 110, 85), BackgroundTransparency = 0.5, BorderSizePixel = 0 }, map)
	-- Letra N (norte = topo)
	create("TextLabel", { Size = UDim2.fromOffset(px(14), px(12)), Position = UDim2.new(0.5, -px(7), 0, 1),
		BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = px(11), Text = "N",
		TextColor3 = NEON, ZIndex = 4 }, map)

	-- Varredura: container quadrado que gira em torno do centro do mapa
	local sweep = create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2,
	}, map)
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, math.max(2, px(2)), 0.5, 0), BackgroundColor3 = NEON,
		BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 2,
	}, sweep)

	-- Camada dos blips + centro
	local layer = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, map)
	local center = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(px(4), px(4)), BackgroundColor3 = COL.red, BorderSizePixel = 0, ZIndex = 4 }, map)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, center)

	-- Lista de texto
	local list = create("TextLabel", {
		Position = UDim2.fromOffset(s + px(12), px(26)),
		Size = UDim2.fromOffset(w - s - px(18), s), BackgroundTransparency = 1,
		Font = Enum.Font.Code, TextSize = px(11), TextColor3 = Color3.fromRGB(120, 255, 190),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, ClipsDescendants = true, Text = "",
	}, root)
	d.maxLines = math.max(3, math.floor(s / (px(11) + 2)))

	-- Pool de blips (reaproveita Frames para não criar/destruir toda hora)
	local pool, corners, used = {}, {}, 0
	local function nextBlip()
		used = used + 1
		if used > 320 then return nil end
		local b = pool[used]
		if not b then
			b = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 }, layer)
			corners[used] = create("UICorner", {}, b)
			pool[used] = b
		end
		return b, corners[used]
	end

	-- API pública do display
	function d:SetHeader(t) header.Text = t end
	function d:SetList(lines)
		local n = math.min(#lines, d.maxLines)
		list.Text = (n > 0) and table.concat(lines, "\n", 1, n) or ""
	end
	function d:SetSweep(angle) sweep.Rotation = angle end
	function d:Begin() used = 0 end
	function d:Dot(nx, ny, sizePx, color, square)
		if nx < -0.05 or nx > 1.05 or ny < -0.05 or ny > 1.05 then return end
		local b, c = nextBlip(); if not b then return end
		local sz = math.max(2, math.floor(sizePx * u + 0.5))
		b.Visible = true; b.Rotation = 0
		b.Size = UDim2.fromOffset(sz, sz)
		b.Position = UDim2.fromScale(nx, ny)
		b.BackgroundColor3 = color; b.BackgroundTransparency = 0
		c.CornerRadius = square and UDim.new(0, 0) or UDim.new(1, 0)
	end
	function d:Rect(nx, ny, fw, fh, rot, color)
		if nx < -0.2 or nx > 1.2 or ny < -0.2 or ny > 1.2 then return end
		local b, c = nextBlip(); if not b then return end
		b.Visible = true; b.Rotation = rot
		b.Size = UDim2.fromOffset(math.max(2, fw * s), math.max(2, fh * s))
		b.Position = UDim2.fromScale(nx, ny)
		b.BackgroundColor3 = color; b.BackgroundTransparency = 0.55
		c.CornerRadius = UDim.new(0, 0)
	end
	function d:End()
		for i = used + 1, #pool do pool[i].Visible = false end
	end
	return d
end

---------------------------------------------------------------
-- 6) VARREDURA DE DADOS (jogadores, veículos, ambiente)
---------------------------------------------------------------
local refresh, updateEnv  -- declaradas antes pois uma usa a outra

-- Monitora VehicleSeats do mapa (inicial + dinâmico)
task.spawn(function()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("VehicleSeat") then State.vehicleSeats[inst] = true end
	end
end)
track(Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("VehicleSeat") then State.vehicleSeats[inst] = true end
end))
track(Workspace.DescendantRemoving:Connect(function(inst)
	if State.vehicleSeats[inst] then State.vehicleSeats[inst] = nil end
end))

-- Jogadores dentro do alcance (ordenados por distância)
local function collectPlayers(origin, range)
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			local off = hrp.Position - origin
			if off.Magnitude <= range then
				table.insert(list, { name = plr.Name, dx = off.X, dz = off.Z,
					dist = off.Magnitude, self = (plr == LocalPlayer) })
			end
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end

-- Veículos (VehicleSeat) dentro do alcance
local function collectVehicles(origin, range)
	local list = {}
	for seat in pairs(State.vehicleSeats) do
		if seat.Parent then
			local off = seat.Position - origin
			if off.Magnitude <= range then
				table.insert(list, { name = seat.Parent.Name, dx = off.X, dz = off.Z, dist = off.Magnitude })
			end
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end

-- Partes do ambiente (estruturas grandes) dentro do alcance
updateEnv = function()
	State.env = {}
	if not State.origin then return end
	local R = CONFIG.RANGE
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	if State.folder then table.insert(ex, State.folder) end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(ex, plr.Character) end
	end
	params.FilterDescendantsInstances = ex
	params.MaxParts = 400

	local ok, parts = pcall(function()
		return Workspace:GetPartBoundsInRadius(State.origin, R, params)
	end)
	if not ok then return end

	local out = {}
	for _, part in ipairs(parts) do
		local s = part.Size
		local big  = math.max(s.X, s.Y, s.Z)
		local flat = math.max(s.X, s.Z)
		-- ignora partes pequenas, invisíveis e gigantes (ex: baseplate)
		if big >= CONFIG.MIN_PART_SIZE and flat <= R and part.Transparency < 0.95 then
			local off = part.Position - State.origin
			local look = part.CFrame.LookVector
			table.insert(out, {
				name = part.Name, dx = off.X, dz = off.Z, dist = off.Magnitude,
				sx = s.X, sz = s.Z,
				rot = math.deg(math.atan2(look.X, -look.Z)), -- rotação vista de cima
			})
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	for i = 1, math.min(#out, CONFIG.MAX_PARTS) do State.env[i] = out[i] end
end

---------------------------------------------------------------
-- 7) RENDERIZAÇÃO (envia os dados para o monitor 3D e para o visor)
---------------------------------------------------------------
refresh = function()
	local displays = {}
	if State.visor then table.insert(displays, State.visor) end
	if State.surface then table.insert(displays, State.surface) end
	if #displays == 0 then return end

	-- Sem radar ativo: mostra aviso
	if not State.origin then
		for _, d in ipairs(displays) do
			d:Begin(); d:End()
			d:SetHeader("RADAR OFFLINE")
			d:SetList({ "Nenhum radar", "ativo.", "", "Escolha Small", "ou Medium." })
		end
		return
	end

	local R, origin, mode = CONFIG.RANGE, State.origin, State.mode
	local plist = collectPlayers(origin, R)
	local vlist = (mode >= 2) and collectVehicles(origin, R) or {}
	local envs  = (mode >= 2) and State.env or {}

	local lines, cmds = {}, {}
	-- converte deslocamento em coordenada normalizada do mapa (norte = topo)
	local function norm(dx, dz) return 0.5 + dx / (2 * R), 0.5 + dz / (2 * R) end

	-- Camada 1: ambiente (desenhado primeiro, fica por baixo)
	if mode == 2 then
		for _, e in ipairs(envs) do
			local x, y = norm(e.dx, e.dz)
			table.insert(cmds, { t = "dot", x = x, y = y, s = 3, col = COL_ENV, sq = true })
		end
	elseif mode == 3 then
		for _, e in ipairs(envs) do
			local x, y = norm(e.dx, e.dz)
			table.insert(cmds, { t = "rect", x = x, y = y, w = e.sx / (2 * R), h = e.sz / (2 * R),
				rot = e.rot, col = COL_ENV })
		end
	end
	-- Camada 2: veículos
	for _, v in ipairs(vlist) do
		local x, y = norm(v.dx, v.dz)
		table.insert(cmds, { t = "dot", x = x, y = y, s = 7, col = COL_VEHICLE, sq = true })
	end
	-- Camada 3: jogadores
	for _, p in ipairs(plist) do
		local x, y = norm(p.dx, p.dz)
		table.insert(cmds, { t = "dot", x = x, y = y, s = p.self and 5 or 6,
			col = p.self and COL_SELF or COL_PLAYER })
	end

	-- Texto da lista conforme o modo
	if mode == 1 then
		table.insert(lines, "Jogadores: " .. #plist)
		for _, p in ipairs(plist) do
			table.insert(lines, (p.self and "*" or "") .. string.sub(p.name, 1, 9)
				.. " " .. fmt(p.dist) .. "m " .. compass(p.dx, p.dz))
		end
	elseif mode == 2 then
		table.insert(lines, "J:" .. #plist .. " V:" .. #vlist .. " E:" .. #envs)
		for _, p in ipairs(plist) do
			table.insert(lines, (p.self and "*" or "") .. string.sub(p.name, 1, 9)
				.. " " .. fmt(p.dist) .. "m " .. compass(p.dx, p.dz))
		end
		for _, v in ipairs(vlist) do
			table.insert(lines, "[V]" .. string.sub(v.name, 1, 8) .. " " .. fmt(v.dist) .. "m")
		end
		for i = 1, math.min(#envs, 4) do
			table.insert(lines, "[E]" .. string.sub(envs[i].name, 1, 8) .. " " .. fmt(envs[i].dist) .. "m")
		end
	else
		lines = {
			"MAPA TÁTICO", "Alcance: " .. fmt(R) .. "m", "N = topo",
			"Radar: " .. fmt(origin.X) .. "," .. fmt(origin.Z), "",
			"Verde: jogador", "Amarelo: veículo", "Ciano: estrutura",
		}
	end

	-- Envia para cada display
	local header = "RADAR " .. string.upper(State.size or "") .. " | " .. MODE_NAMES[mode]
	for _, d in ipairs(displays) do
		d:Begin()
		for _, c in ipairs(cmds) do
			if c.t == "dot" then d:Dot(c.x, c.y, c.s, c.col, c.sq)
			else d:Rect(c.x, c.y, c.w, c.h, c.rot, c.col) end
		end
		d:End()
		d:SetHeader(header)
		d:SetList(lines)
	end
end

---------------------------------------------------------------
-- 8) CONSTRUÇÃO DOS MODELOS 3D
---------------------------------------------------------------
-- Cria o modelo "Rotor": tudo que gira com a antena. O eixo é uma peça invisível.
local function makeRotor(parent, rotorBase)
	local rotor = Instance.new("Model")
	rotor.Name = "Rotor"
	local pivot = newPart(rotor, "Eixo", Vector3.new(0.4, 0.4, 0.4), rotorBase,
		COL.dark, Enum.Material.Metal, { Transparency = 1 })
	rotor.PrimaryPart = pivot
	rotor.Parent = parent
	return rotor, rotorBase
end

-- RADAR SMALL: portátil, com parabólica
local function buildSmall(model, cf)
	-- Base circular + sapatas
	cylinder(model, "Base", cf * CFrame.new(0, 0.2, 0), 0.4, 5.4, COL.dark, Enum.Material.DiamondPlate, { CanCollide = true })
	for i = 1, 4 do
		local a = math.rad(45 + (i - 1) * 90)
		newPart(model, "Sapata", Vector3.new(0.8, 0.3, 0.8),
			cf * CFrame.new(math.cos(a) * 2.1, 0.55, math.sin(a) * 2.1), COL.gray, Enum.Material.Metal)
	end
	-- Caixa eletrônica + faixa de status neon
	newPart(model, "Caixa", Vector3.new(2.6, 1.4, 2.6), cf * CFrame.new(0, 1.1, 0), COL.olive, Enum.Material.Metal)
	newPart(model, "Status", Vector3.new(1.6, 0.15, 0.1), cf * CFrame.new(0, 1.1, -1.31), NEON, Enum.Material.Neon)
	-- Mastro
	cylinder(model, "Mastro", cf * CFrame.new(0, 3.3, 0), 3, 0.6, COL.gray, Enum.Material.Metal)
	-- Farol vermelho piscante
	local beacon = newPart(model, "Farol", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0.9, 1.95, 0.9),
		COL.red, Enum.Material.Neon, { Shape = Enum.PartType.Ball })

	-- Parte giratória
	local rotorBase = cf * CFrame.new(0, 4.9, 0)
	local rotor = makeRotor(model, rotorBase)
	cylinder(rotor, "Prato", rotorBase * CFrame.new(0, 0.2, 0), 0.4, 1.6, COL.dark)
	newPart(rotor, "Suporte", Vector3.new(0.4, 1.6, 0.4), rotorBase * CFrame.new(0, 1.2, 0.2), COL.gray)
	-- Parabólica inclinada 15° para cima, "olhando" para -Z
	local dishCF = rotorBase * CFrame.new(0, 2.2, -0.6) * CFrame.Angles(math.rad(15), 0, 0)
	cylinderZ(rotor, "Aro", dishCF * CFrame.new(0, 0, 0.12), 0.1, 4.4, NEON, Enum.Material.Neon)
	cylinderZ(rotor, "Parabolica", dishCF, 0.3, 4.2, COL.white, Enum.Material.SmoothPlastic)
	cylinderZ(rotor, "Interior", dishCF * CFrame.new(0, 0, -0.17), 0.1, 3.6, COL.gray, Enum.Material.Metal)
	cylinderZ(rotor, "Haste", dishCF * CFrame.new(0, 0, -1.0), 2.0, 0.12, COL.gray)
	newPart(rotor, "Corneta", Vector3.new(0.4, 0.4, 0.4), dishCF * CFrame.new(0, 0, -2.0),
		NEON, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	return rotor, rotorBase, beacon
end

-- RADAR MEDIUM: torre, cabine, radome e antena de barra
local function buildMedium(model, cf)
	-- Plataforma de concreto + faixas amarelas de segurança
	newPart(model, "Plataforma", Vector3.new(15, 0.8, 15), cf * CFrame.new(0, 0.4, 0),
		COL.concrete, Enum.Material.Concrete, { CanCollide = true })
	for _, s in ipairs({ { 0, 7, 14.6, 0.4 }, { 0, -7, 14.6, 0.4 }, { 7, 0, 0.4, 14.6 }, { -7, 0, 0.4, 14.6 } }) do
		newPart(model, "Faixa", Vector3.new(s[3], 0.06, s[4]), cf * CFrame.new(s[1], 0.82, s[2]),
			COL.yellow, Enum.Material.Neon)
	end
	-- Torre: 4 pilares + travessas
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			newPart(model, "Pilar", Vector3.new(0.6, 7, 0.6), cf * CFrame.new(sx * 2, 4.3, sz * 2), COL.gray)
		end
	end
	for _, y in ipairs({ 2.5, 5.5 }) do
		for _, s in ipairs({ -2, 2 }) do
			newPart(model, "Travessa", Vector3.new(4, 0.3, 0.3), cf * CFrame.new(0, y, s), COL.gray)
			newPart(model, "Travessa", Vector3.new(0.3, 0.3, 4), cf * CFrame.new(s, y, 0), COL.gray)
		end
	end
	newPart(model, "Deck", Vector3.new(5.2, 0.5, 5.2), cf * CFrame.new(0, 8.05, 0),
		COL.dark, Enum.Material.DiamondPlate, { CanCollide = true })
	-- Cabine de equipamentos + luz da porta + radome (cúpula) + gerador
	newPart(model, "Cabine", Vector3.new(5, 3.2, 4), cf * CFrame.new(-5, 2.4, 0),
		COL.olive, Enum.Material.Metal, { CanCollide = true })
	newPart(model, "PortaLuz", Vector3.new(0.1, 2, 1), cf * CFrame.new(-2.45, 2.0, 0), NEON, Enum.Material.Neon)
	newPart(model, "Radome", Vector3.new(3, 3, 3), cf * CFrame.new(-5, 5.3, 0),
		COL.white, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Transparency = 0.25 })
	newPart(model, "Gerador", Vector3.new(2.5, 1.6, 1.8), cf * CFrame.new(4.5, 1.6, -4.5), COL.gray, Enum.Material.Metal)
	-- Mastro com farol vermelho
	cylinder(model, "MastroFarol", cf * CFrame.new(2, 8.9, 2), 1.2, 0.2, COL.gray)
	local beacon = newPart(model, "Farol", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(2, 9.7, 2),
		COL.red, Enum.Material.Neon, { Shape = Enum.PartType.Ball })

	-- Parte giratória: antena de barra larga
	local rotorBase = cf * CFrame.new(0, 8.3, 0)
	local rotor = makeRotor(model, rotorBase)
	cylinder(rotor, "Prato", rotorBase * CFrame.new(0, 0.3, 0), 0.6, 2.4, COL.dark)
	cylinder(rotor, "Pedestal", rotorBase * CFrame.new(0, 1.4, 0), 1.6, 0.9, COL.gray)
	newPart(rotor, "Antena", Vector3.new(12, 4.6, 0.5), rotorBase * CFrame.new(0, 4.5, 0),
		COL.light, Enum.Material.SmoothPlastic)
	for i = 0, 5 do -- ripas neon da antena
		newPart(rotor, "Ripa", Vector3.new(11.6, 0.12, 0.15), rotorBase * CFrame.new(0, 2.6 + i * 0.8, -0.3),
			NEON, Enum.Material.Neon)
	end
	for _, sx in ipairs({ -3, 3 }) do -- reforços traseiros
		newPart(rotor, "Reforco", Vector3.new(0.5, 4.6, 1.2), rotorBase * CFrame.new(sx, 4.5, 0.85), COL.gray)
	end
	newPart(rotor, "CornetaBase", Vector3.new(1.2, 0.6, 1.6), rotorBase * CFrame.new(0, 7.1, -0.6), COL.dark)
	newPart(rotor, "Corneta", Vector3.new(0.5, 0.5, 0.5), rotorBase * CFrame.new(0, 6.9, -1.6),
		NEON, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	return rotor, rotorBase, beacon
end

-- CONSOLA DO MONITOR 3D (com tela neon + SurfaceGui + botões clicáveis)
local function buildConsole(parent, cf, onModeClick)
	local m = Instance.new("Model")
	m.Name = "MonitorConsole3D"

	newPart(m, "Base", Vector3.new(3.6, 1, 2.4), cf * CFrame.new(0, 0.5, 0), COL.dark, Enum.Material.Metal, { CanCollide = true })
	newPart(m, "Haste", Vector3.new(1.4, 1.4, 1), cf * CFrame.new(0, 1.7, 0), COL.gray)
	newPart(m, "Carcaca", Vector3.new(6.6, 4.4, 1.2), cf * CFrame.new(0, 4.5, 0), COL.dark)
	local panel = newPart(m, "PainelBotoes", Vector3.new(6.6, 0.5, 2), cf * CFrame.new(0, 2.0, -1.0), COL.gray)

	-- Tela luminosa neon
	local screen = newPart(m, "Tela", Vector3.new(5.8, 3.3, 0.1), cf * CFrame.new(0, 4.6, -0.65),
		Color3.fromRGB(10, 45, 38), Enum.Material.Neon)
	create("PointLight", { Color = NEON, Range = 14, Brightness = 1.2 }, screen)
	-- Moldura neon da tela
	newPart(m, "MoldTopo",  Vector3.new(6.0, 0.12, 0.12), cf * CFrame.new(0, 6.32, -0.66), NEON, Enum.Material.Neon)
	newPart(m, "MoldBase",  Vector3.new(6.0, 0.12, 0.12), cf * CFrame.new(0, 2.88, -0.66), NEON, Enum.Material.Neon)
	newPart(m, "MoldEsq",   Vector3.new(0.12, 3.5, 0.12), cf * CFrame.new(2.96, 4.6, -0.66), NEON, Enum.Material.Neon)
	newPart(m, "MoldDir",   Vector3.new(0.12, 3.5, 0.12), cf * CFrame.new(-2.96, 4.6, -0.66), NEON, Enum.Material.Neon)

	-- SurfaceGui na face frontal da tela
	local sg = create("SurfaceGui", {
		Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(504, 288), LightInfluence = 0, Brightness = 1.4,
	}, screen)

	-- 3 botões físicos (x invertido porque a consola está virada 180°)
	local cols  = { Color3.fromRGB(60, 255, 90), COL.yellow, Color3.fromRGB(0, 220, 255) }
	local xs    = { 2, 0, -2 }
	local names = { "1 JOGADORES", "2 TUDO", "3 MAPA" }
	for i = 1, 3 do
		local b = newPart(m, "Botao" .. i, Vector3.new(1.4, 0.25, 1.0),
			cf * CFrame.new(xs[i], 2.38, -1.1), cols[i], Enum.Material.Neon)
		local cd = create("ClickDetector", { MaxActivationDistance = 25 }, b)
		cd.MouseClick:Connect(function() onModeClick(i) end)
	end
	-- Legenda dos botões na face frontal do painel
	local psg = create("SurfaceGui", {
		Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(660, 50), LightInfluence = 0,
	}, panel)
	local fx = { 0.197, 0.5, 0.803 }
	for i = 1, 3 do
		create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(fx[i], 0.5),
			Size = UDim2.fromScale(0.3, 0.9), BackgroundTransparency = 1, Font = Enum.Font.Code,
			TextSize = 22, TextColor3 = cols[i], Text = names[i],
		}, psg)
	end
	m.Parent = parent
	return m, sg
end

---------------------------------------------------------------
-- 9) CRIAR / REMOVER O MUNDO 3D
---------------------------------------------------------------
local function updateSizeButtons()
	for name, btn in pairs(State.sizeButtons) do
		btn.BackgroundColor3 = (State.size == name) and COL_BTN_ON or COL_BTN_OFF
	end
end

local function destroyWorld()
	if State.beaconTween then
		pcall(function() State.beaconTween:Cancel() end)
		State.beaconTween = nil
	end
	if State.folder then State.folder:Destroy() end
	State.folder, State.rotor, State.rotorBase = nil, nil, nil
	State.origin, State.size, State.surface = nil, nil, nil
	State.env = {}
	State.angle = 0
	updateSizeButtons()
	refresh()
end

local function setMode(m)
	State.mode = m
	for i, btn in ipairs(State.modeButtons) do
		btn.BackgroundColor3 = (i == m) and COL_BTN_ON or COL_BTN_OFF
	end
	if m >= 2 then updateEnv() end
	refresh()
end

local function spawnRadar(size)
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then notify("Personagem não encontrado."); return end

	destroyWorld() -- remove radar anterior (se houver)

	-- Posição: à frente do jogador, no chão (raycast para baixo)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = (flat.Magnitude < 0.01) and Vector3.new(0, 0, -1) or flat.Unit
	local target = hrp.Position + flat * ((size == "Medium") and 22 or 14)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(target + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), rp)
	local ground = hit and hit.Position or (target - Vector3.new(0, 3, 0))
	local yaw = math.atan2(-flat.X, -flat.Z) -- radar "olha" na mesma direção do jogador
	local cf = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)

	-- Pasta que guarda tudo
	local folder = Instance.new("Folder")
	folder.Name = "RadarTatico3D_Mundo"
	local model = Instance.new("Model")
	model.Name = "Radar3D_" .. size
	model.Parent = folder

	local rotor, rotorBase, beacon
	if size == "Medium" then
		rotor, rotorBase, beacon = buildMedium(model, cf)
	else
		rotor, rotorBase, beacon = buildSmall(model, cf)
	end

	-- Consola ao lado do radar, virada para o jogador
	local xOff = (size == "Medium") and 13 or 7
	local consoleCF = cf * CFrame.new(xOff, 0, 6) * CFrame.Angles(0, math.pi, 0)
	local _, sg = buildConsole(folder, consoleCF, setMode)

	folder.Parent = Workspace

	-- Atualiza o estado
	State.folder, State.rotor, State.rotorBase = folder, rotor, rotorBase
	State.origin = cf.Position
	State.size = size
	State.spin = CONFIG.SPIN[size]
	State.angle = 0
	State.surface = buildDisplay(sg, 504, 288)

	-- Farol piscando com TweenService
	State.beaconTween = TweenService:Create(beacon,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.9 })
	State.beaconTween:Play()

	updateSizeButtons()
	setMode(State.mode)
	notify("Radar " .. size .. " criado!")
end

---------------------------------------------------------------
-- 10) FECHAR TUDO
---------------------------------------------------------------
local function destroyAll()
	destroyWorld()
	for _, c in ipairs(State.connections) do pcall(function() c:Disconnect() end) end
	State.connections = {}
	if State.gui then State.gui:Destroy() end
	GENV.RadarTatico3D = nil
end
GENV.RadarTatico3D = { Destroy = destroyAll }

---------------------------------------------------------------
-- 11) INTERFACE (painel flutuante arrastável)
---------------------------------------------------------------
local function makeButton(parent, text, size, onClick)
	local b = create("TextButton", {
		Size = size, BackgroundColor3 = COL_BTN_OFF, Text = text, TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = true, BorderSizePixel = 0,
	}, parent)
	create("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	track(b.Activated:Connect(onClick)) -- Activated funciona em toque e mouse
	return b
end

local function sectionLabel(parent, text)
	return create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 11, TextColor3 = NEON, TextXAlignment = Enum.TextXAlignment.Left, Text = text,
	}, parent)
end

local function row(parent)
	local r = create("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, parent)
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder }, r)
	return r
end

local function buildGui()
	local gui = create("ScreenGui", { Name = "RadarTatico3D_GUI", ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50 }, nil)
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
	gui.Parent = getGuiParent()
	State.gui = gui

	-- Janela principal (altura automática)
	local main = create("Frame", {
		Name = "Painel", Size = UDim2.fromOffset(280, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 12, 0.2, 0), BackgroundColor3 = Color3.fromRGB(10, 18, 22),
		BorderSizePixel = 0,
	}, gui)
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, main)
	create("UIStroke", { Color = NEON, Thickness = 1.5, Transparency = 0.2 }, main)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, main)

	-- Barra de título (arrastável)
	local top = create("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Color3.fromRGB(0, 70, 55),
		BorderSizePixel = 0, LayoutOrder = 0 }, main)
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, top)
	create("TextLabel", { Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left, Text = "RADAR TÁTICO 3D" }, top)

	-- Corpo do painel
	local body = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 1 }, main)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, body)
	create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6) }, body)

	-- Botões minimizar / fechar
	local minBtn = create("TextButton", { Size = UDim2.fromOffset(24, 20), Position = UDim2.new(1, -54, 0, 3),
		BackgroundColor3 = COL_BTN_OFF, Text = "–", TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold, TextSize = 14, BorderSizePixel = 0 }, top)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, minBtn)
	local closeBtn = create("TextButton", { Size = UDim2.fromOffset(24, 20), Position = UDim2.new(1, -28, 0, 3),
		BackgroundColor3 = Color3.fromRGB(160, 40, 40), Text = "X", TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold, TextSize = 12, BorderSizePixel = 0 }, top)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, closeBtn)
	track(minBtn.Activated:Connect(function()
		body.Visible = not body.Visible
		minBtn.Text = body.Visible and "–" or "+"
	end))
	track(closeBtn.Activated:Connect(destroyAll))

	-- Arrastar (mouse e toque)
	local dragging, dragStart, startPos
	track(top.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, main.Position
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					conn:Disconnect()
				end
			end)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))

	-- Seleção do modelo 3D
	local l1 = sectionLabel(body, "MODELO 3D"); l1.LayoutOrder = 1
	local r1 = row(body); r1.LayoutOrder = 2
	State.sizeButtons.Small  = makeButton(r1, "Radar 3D Small",  UDim2.new(0.5, -3, 1, 0), function() spawnRadar("Small") end)
	State.sizeButtons.Medium = makeButton(r1, "Radar 3D Medium", UDim2.new(0.5, -3, 1, 0), function() spawnRadar("Medium") end)

	-- Modos do monitor
	local l2 = sectionLabel(body, "MODO DO MONITOR"); l2.LayoutOrder = 3
	local r2 = row(body); r2.LayoutOrder = 4
	local labels = { "1 · Jogadores", "2 · Tudo", "3 · Mapa" }
	for i = 1, 3 do
		State.modeButtons[i] = makeButton(r2, labels[i], UDim2.new(1 / 3, -4, 1, 0), function() setMode(i) end)
	end

	-- Visor (mesmos dados do monitor 3D)
	local holder = create("Frame", { Size = UDim2.new(1, 0, 0, 178), BackgroundTransparency = 1, LayoutOrder = 5 }, body)
	State.visor = buildDisplay(holder, 268, 178)

	-- Remover tudo
	local rm = makeButton(body, "Remover Radar e Monitor", UDim2.new(1, 0, 0, 28), destroyWorld)
	rm.LayoutOrder = 6
	rm.BackgroundColor3 = Color3.fromRGB(110, 40, 40)
end

buildGui()
setMode(1)

---------------------------------------------------------------
-- 12) LOOP PRINCIPAL (rotação 360° + varreduras periódicas)
---------------------------------------------------------------
local scanAcc, envAcc = 0, 0
track(RunService.Heartbeat:Connect(function(dt)
	-- Rotação contínua da antena (em torno do eixo Y)
	if State.rotor and State.rotor.Parent then
		State.angle = (State.angle + State.spin * dt) % 360
		State.rotor:PivotTo(State.rotorBase * CFrame.Angles(0, -math.rad(State.angle), 0))
		-- Sincroniza a linha de varredura dos mapas com a antena
		if State.visor then State.visor:SetSweep(State.angle) end
		if State.surface then State.surface:SetSweep(State.angle) end
	end

	-- Atualização dos dados em intervalos (não a cada frame, para poupar FPS)
	scanAcc = scanAcc + dt
	envAcc  = envAcc + dt
	if State.origin and State.mode >= 2 and envAcc >= CONFIG.ENV_RATE then
		envAcc = 0
		updateEnv()
	end
	if scanAcc >= CONFIG.SCAN_RATE then
		scanAcc = 0
		refresh()
	end
end))

notify("Carregado! Escolha Radar Small ou Medium.")
