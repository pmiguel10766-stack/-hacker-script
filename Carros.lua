--[[
    ╔══════════════════════════════════════════════════════════╗
    ║   FIAT UNO SERVICE HUB  •  v2.0                          ║
    ║   Script client-side em Luau (Delta Executor / PC / Mobile)
    ╚══════════════════════════════════════════════════════════╝

    NOVIDADES v2.0
      • ProximityPrompt no carro: aproxime-se e prima E (ou toque) para ENTRAR / SAIR
      • O carro agora CONDUZ: aceleração, travagem, marcha-atrás, direção, colisões
        simples com paredes e seguimento do terreno (subidas/descidas)
      • HUD de RPM (conta-rotações, velocidade, marcha) enquanto conduz
      • Botão 2 (RPM Máximo): parado = simulação visual de rotação;
        a conduzir = define o LIMITE de RPM (limita a velocidade máxima)

    CONTROLOS
      PC:     W/↑ acelerar | S/↓ travar e marcha-atrás | A/D ou ←/→ direção
              Espaço = travão de mão | E (prompt) ou botão "Sair" = sair do carro
      Mobile: botões ◀ ▶ (direção), ▲ (acelerar), ▼ (travar/ré) no ecrã

    NOTAS
      • O carro é criado do lado do cliente: só você o vê.
      • PC: tecla RightShift mostra/oculta o painel.
      • Executar de novo substitui o painel e o carro anteriores.
]]

----------------------------------------------------------------
-- 1) SERVIÇOS
----------------------------------------------------------------
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
	task.wait()
	LocalPlayer = Players.LocalPlayer
end

----------------------------------------------------------------
-- 2) CONFIGURAÇÃO E TEMA
----------------------------------------------------------------
local CONFIG = {
	GuiName        = "FiatUnoServiceHub",
	ModelName      = "FiatUnoServico",
	SpawnDistance  = 16,    -- distância (studs) à frente do jogador
	MaxRPM         = 999,
	Width          = 330,
	Height         = 436,
	ButtonHeight   = 68,

	-- Condução
	TopSpeedMin    = 30,    -- velocidade máx. com limite de RPM mínimo (studs/s)
	TopSpeedRange  = 110,   -- acrescento ao limite máximo de RPM
	ReverseSpeed   = 22,
	WheelBase      = 7.8,
	SeatOffset     = CFrame.new(-1.2, 4.3, 0.4), -- posição do condutor (lado esquerdo)
	ExitOffset     = CFrame.new(-5.8, 3.2, 0.4), -- onde o jogador aparece ao sair

	-- Paleta usada pelo botão "Editor de Cor"
	Palette = {
		{ Name = "Branco",        Color = Color3.fromRGB(245, 245, 245) },
		{ Name = "Vermelho",      Color = Color3.fromRGB(200, 30, 40)   },
		{ Name = "Azul Elétrico", Color = Color3.fromRGB(52, 152, 219)  },
		{ Name = "Preto",         Color = Color3.fromRGB(28, 28, 32)    },
		{ Name = "Prata",         Color = Color3.fromRGB(170, 175, 182) },
		{ Name = "Amarelo",       Color = Color3.fromRGB(241, 196, 15)  },
		{ Name = "Verde",         Color = Color3.fromRGB(39, 174, 96)   },
		{ Name = "Laranja",       Color = Color3.fromRGB(230, 126, 34)  },
		{ Name = "Roxo",          Color = Color3.fromRGB(142, 68, 173)  },
		{ Name = "Rosa",          Color = Color3.fromRGB(233, 30, 140)  },
	},
}

local THEME = {
	Background = Color3.fromRGB(18, 18, 24),
	TopBar     = Color3.fromRGB(26, 26, 36),
	Panel      = Color3.fromRGB(30, 30, 42),
	Stroke     = Color3.fromRGB(50, 50, 68),
	Text       = Color3.fromRGB(245, 245, 250),
	Muted      = Color3.fromRGB(140, 146, 168),
	White      = Color3.new(1, 1, 1),
	Green      = Color3.fromHex("2ECC71"),
	Orange     = Color3.fromHex("F39C12"),
	Blue       = Color3.fromHex("3498DB"),
	Red        = Color3.fromHex("E74C3C"),
}

----------------------------------------------------------------
-- 3) LIMPEZA DE EXECUÇÕES ANTERIORES
----------------------------------------------------------------
local env = (getgenv and getgenv()) or _G
if env.FiatUnoHubCleanup then
	pcall(env.FiatUnoHubCleanup)
end

-- Remove carros órfãos de execuções anteriores (marcados por atributo)
for _, obj in ipairs(Workspace:GetChildren()) do
	if obj:IsA("Model") and obj:GetAttribute("FiatUnoHub") then
		pcall(function() obj:Destroy() end)
	end
end

----------------------------------------------------------------
-- 4) FUNÇÕES AUXILIARES
----------------------------------------------------------------
local connections = {}

local function connect(signal, callback)
	local c = signal:Connect(callback)
	table.insert(connections, c)
	return c
end

-- Cria uma instância com propriedades e filhos numa só chamada
local function create(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then inst.Parent = parent end
	return inst
end

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

----------------------------------------------------------------
-- 5) ESTADO GLOBAL
----------------------------------------------------------------
local State = {
	Car       = nil,   -- Model atual
	Prompt    = nil,   -- ProximityPrompt do carro
	RootCF    = nil,   -- CFrame de repouso (posição + rotação em Y)
	Wheels    = {},    -- partes que giram
	Body      = {},    -- partes da carroçaria (mudam de cor)
	Accent    = {},    -- partes de acento (versão mais escura da cor)
	LocalCF   = {},    -- offset de cada parte relativo à raiz
	RPM       = 0,     -- RPM do slider (simulação parado)
	ColorIdx  = 1,
	Busy      = false, -- bloqueia ações durante animações
	SimConn   = nil,
	Spin      = 0,
	Clock     = 0,
	Settled   = true,

	-- Condução
	Driving   = false,
	Char      = nil,   -- { hrp, hum, anchored, hidden }
	RayParams = nil,
	Pos       = Vector3.zero,
	Yaw       = 0,
	Pitch     = 0,
	Speed     = 0,     -- studs/s (negativo = marcha-atrás)
	Steer     = 0,     -- ângulo das rodas (rad)
	Fall      = 0,
	Limit     = CONFIG.MaxRPM, -- limite de RPM (a conduzir)
	LiveRPM   = 0,
	Gear      = "N",
}

-- Entradas dos botões de toque
local Touch = { Gas = false, Brake = false, Left = false, Right = false }

local exitCar -- declarada aqui, definida mais abaixo

----------------------------------------------------------------
-- 6) CONSTRUÇÃO DO MODELO 3D (Fiat Uno de serviço)
--    Frente do carro = -Z | Origem = centro, ao nível do chão
----------------------------------------------------------------
local function buildCar(rootCF)
	local model = Instance.new("Model")
	model.Name = CONFIG.ModelName
	model:SetAttribute("FiatUnoHub", true)

	local data = { Model = model, Wheels = {}, Body = {}, Accent = {}, LocalCF = {}, Prompt = nil }

	-- Adiciona uma peça ao modelo
	local function add(name, size, offset, color, kind, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.CFrame = rootCF * offset
		p.Parent = model
		data.LocalCF[p] = offset
		if kind == "body" then
			table.insert(data.Body, p)
		elseif kind == "accent" then
			table.insert(data.Accent, p)
		elseif kind == "wheel" then
			table.insert(data.Wheels, p)
		end
		return p
	end

	local CYL = Enum.PartType.Cylinder
	local WHITE  = CONFIG.Palette[1].Color
	local BLACK  = Color3.fromRGB(20, 20, 22)
	local GLASS  = Color3.fromRGB(150, 200, 230)
	local SILVER = Color3.fromRGB(200, 205, 212)
	local ACCENT = WHITE:Lerp(Color3.new(0, 0, 0), 0.35)
	local V3, CF = Vector3.new, CFrame.new

	-- Peça-raiz invisível (pivô do modelo)
	local root = add("Raiz", V3(1, 1, 1), CF(), BLACK)
	root.Transparency = 1
	model.PrimaryPart = root

	-- ProximityPrompt: entrar / sair do carro
	data.Prompt = create("ProximityPrompt", {
		Name = "PromptCarro",
		ActionText = "Entrar",
		ObjectText = "Fiat Uno de Serviço",
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		HoldDuration = 0.25,
		MaxActivationDistance = 14,
		RequiresLineOfSight = false,
		Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
		Enabled = false, -- ativado quando o carro assenta no chão
		Parent = root,
	})

	-- ── Carroçaria ────────────────────────────────────────────
	add("Carroceria", V3(6, 1.5, 12.4), CF(0, 2.05, 0), WHITE, "body").CanCollide = true
	add("Capo",       V3(5.9, 0.35, 3.6), CF(0, 2.97, -4.3), WHITE, "body")
	add("Traseira",   V3(5.9, 0.35, 2.1), CF(0, 2.97, 5.15), WHITE, "body")
	add("Teto",       V3(5.6, 0.25, 6.4), CF(0, 4.875, 0.9), WHITE, "body")

	-- Cabine envidraçada + para-brisas inclinado
	local cabin = add("VidrosLaterais", V3(5.4, 1.6, 6.4), CF(0, 3.95, 0.9), GLASS)
	cabin.Transparency = 0.45
	local windshield = add("ParaBrisas", V3(5.3, 1.7, 0.1),
		CF(0, 3.95, -2.45) * CFrame.Angles(math.rad(20), 0, 0), GLASS)
	windshield.Transparency = 0.4

	-- Colunas A, B e C
	for _, s in ipairs({ -1, 1 }) do
		add("ColunaA", V3(0.3, 1.75, 0.3), CF(s * 2.75, 3.95, -2.45) * CFrame.Angles(math.rad(20), 0, 0), WHITE, "body")
		add("ColunaB", V3(0.3, 1.6, 0.35), CF(s * 2.75, 3.95, 0.9), WHITE, "body")
		add("ColunaC", V3(0.3, 1.6, 0.35), CF(s * 2.75, 3.95, 3.95), WHITE, "body")
	end

	-- ── Frente: faixa preta, grelha, faróis ───────────────────
	add("FrenteNegra", V3(5.9, 0.9, 0.25), CF(0, 2.4, -6.3), BLACK)
	add("GrelhaFundo", V3(3.4, 0.55, 0.1), CF(0, 2.45, -6.45), Color3.fromRGB(40, 40, 44))
	for i = -1, 1 do
		add("GrelhaRipa", V3(3.2, 0.06, 0.06), CF(0, 2.45 + i * 0.15, -6.52), SILVER, nil, Enum.Material.Metal)
	end
	add("Emblema", V3(0.35, 0.35, 0.1), CF(0, 2.45, -6.58), SILVER, nil, Enum.Material.Metal, Enum.PartType.Ball)
	for _, s in ipairs({ -1, 1 }) do
		add("Farol",  V3(1.2, 0.55, 0.2), CF(s * 2.3, 2.5, -6.42), Color3.fromRGB(240, 240, 215), nil, Enum.Material.Neon)
		add("Lanterna", V3(0.9, 0.8, 0.2), CF(s * 2.4, 2.5, 6.3), Color3.fromRGB(200, 30, 30), nil, Enum.Material.Neon)
	end

	-- ── Para-choques pretos e matrículas ──────────────────────
	add("ParachoquesFrente",  V3(6.2, 0.9, 0.7), CF(0, 1.65, -6.35), BLACK)
	add("ParachoquesTras",    V3(6.2, 0.9, 0.7), CF(0, 1.65, 6.35), BLACK)
	add("MatriculaFrente", V3(1.9, 0.5, 0.06), CF(0, 1.7, -6.72), Color3.fromRGB(235, 235, 225))
	add("MatriculaTras",   V3(1.9, 0.5, 0.06), CF(0, 1.7, 6.72), Color3.fromRGB(235, 235, 225))

	-- ── Faixa preta lateral, logótipo (círculo vermelho), espelhos
	for _, s in ipairs({ -1, 1 }) do
		add("FaixaLateral", V3(0.06, 0.35, 12), CF(s * 3.03, 1.7, 0), BLACK)
		add("LogoPorta", V3(0.05, 0.95, 0.95), CF(s * 3.04, 2.35, -0.6), Color3.fromRGB(220, 20, 30), nil, nil, CYL)
		add("Espelho", V3(0.45, 0.3, 0.25), CF(s * 3.05, 3.85, -2.1), BLACK)
	end

	-- ── Interior ──────────────────────────────────────────────
	local SEAT = Color3.fromRGB(60, 60, 66)
	add("Painel", V3(5.2, 0.5, 0.6), CF(0, 3.35, -1.9), Color3.fromRGB(35, 35, 40))
	for _, s in ipairs({ -1, 1 }) do
		add("Banco", V3(1.7, 0.5, 1.5), CF(s * 1.2, 3.4, 0.2), SEAT)
		add("EncostoBanco", V3(1.7, 1.3, 0.3), CF(s * 1.2, 3.9, 0.95), SEAT)
	end
	add("BancoTras", V3(5, 0.5, 1.4), CF(0, 3.4, 2.9), SEAT)
	add("EncostoTras", V3(5, 1.2, 0.3), CF(0, 3.85, 3.65), SEAT)

	-- ── Rodas (pneu + jante + raios para ver a rotação) ───────
	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -3.9, 3.9 }) do
			add("Pneu", V3(0.9, 2.3, 2.3), CF(s * 2.75, 1.15, z), Color3.fromRGB(22, 22, 24), "wheel", nil, CYL)
			add("Jante", V3(0.08, 1.6, 1.6), CF(s * 3.2, 1.15, z), Color3.fromRGB(160, 165, 172), "wheel", Enum.Material.Metal, CYL)
			for _, angle in ipairs({ 0, 60, 120 }) do
				add("Raio", V3(0.06, 1.5, 0.2),
					CF(s * 3.25, 1.15, z) * CFrame.Angles(math.rad(angle), 0, 0),
					Color3.fromRGB(55, 55, 60), "wheel")
			end
			add("Cubo", V3(0.1, 0.45, 0.45), CF(s * 3.28, 1.15, z), SILVER, "wheel", Enum.Material.Metal, CYL)
		end
	end

	-- ── Suporte de teto + escada (detalhe emblemático) ────────
	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1.2, 3.0 }) do
			add("PernaSuporte", V3(0.18, 0.45, 0.18), CF(s * 2.4, 5.225, z), ACCENT, "accent")
		end
		add("TrilhoSuporte", V3(0.18, 0.16, 6.0), CF(s * 2.4, 5.5, 0.9), ACCENT, "accent")
	end
	for _, z in ipairs({ -1.2, 3.0 }) do
		add("BarraTransversal", V3(5.2, 0.16, 0.18), CF(0, 5.65, z), ACCENT, "accent")
	end

	local ORANGE = Color3.fromRGB(214, 110, 50)
	for _, s in ipairs({ -1, 1 }) do
		add("LongaronaEscada", V3(0.28, 0.25, 10), CF(s * 1.9, 5.85, -0.3), ORANGE)
	end
	for i = 0, 11 do
		add("DegrauEscada", V3(3.55, 0.14, 0.14), CF(0, 5.85, -5.0 + i * 0.85), SILVER, nil, Enum.Material.Metal)
	end

	return data
end

----------------------------------------------------------------
-- 7) INTERFACE GRÁFICA
----------------------------------------------------------------
-- Lista de destinos possíveis para a GUI (ordem de preferência)
local function getContainers()
	local list = {}
	pcall(function()
		if gethui then table.insert(list, gethui()) end
	end)
	pcall(function()
		table.insert(list, game:GetService("CoreGui"))
	end)
	pcall(function()
		table.insert(list, LocalPlayer:WaitForChild("PlayerGui", 5))
	end)
	return list
end

-- Remove GUIs antigas com o mesmo nome
for _, container in ipairs(getContainers()) do
	pcall(function()
		local old = container:FindFirstChild(CONFIG.GuiName)
		if old then old:Destroy() end
	end)
end

local gui = create("ScreenGui", {
	Name = CONFIG.GuiName,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
})

-- Escala responsiva (telemóvel / ecrãs pequenos)
local function computeScale()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min(vp.Y / 500, vp.X / 380), 0.55, 1)
end
local baseScale = computeScale()

-- Contentor principal (arrastável) + sombra
local holder = create("Frame", {
	Name = "Holder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(CONFIG.Width, CONFIG.Height),
	BackgroundTransparency = 1,
	Parent = gui,
})
local uiScale = create("UIScale", { Scale = 0, Parent = holder })

create("ImageLabel", {
	Name = "Sombra",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 6),
	Size = UDim2.new(1, 60, 1, 60),
	BackgroundTransparency = 1,
	Image = "rbxassetid://6014261993",
	ImageColor3 = Color3.new(0, 0, 0),
	ImageTransparency = 0.45,
	ScaleType = Enum.ScaleType.Slice,
	SliceCenter = Rect.new(49, 49, 450, 450),
	ZIndex = 0,
	Parent = holder,
})

local main = create("Frame", {
	Name = "Main",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	Parent = holder,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 16) }),
	create("UIStroke", { Color = THEME.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
})

-- ── Barra de topo ─────────────────────────────────────────────
local topBar = create("Frame", {
	Name = "TopBar",
	Size = UDim2.new(1, 0, 0, 58),
	BackgroundColor3 = THEME.TopBar,
	BorderSizePixel = 0,
	Parent = main,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 16) }),
})
-- Preenchimento para endireitar os cantos inferiores da barra
create("Frame", {
	Name = "Preenchimento",
	Position = UDim2.new(0, 0, 1, -16),
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = THEME.TopBar,
	BorderSizePixel = 0,
	Parent = topBar,
})
create("Frame", {
	Name = "Divisor",
	Position = UDim2.new(0, 0, 0, 58),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = THEME.Stroke,
	BorderSizePixel = 0,
	Parent = main,
})

local badge = create("Frame", {
	Name = "Icone",
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = topBar,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 10) }),
	create("UIGradient", {
		Color = ColorSequence.new(THEME.Green, THEME.Blue),
		Rotation = 45,
	}),
})
create("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Text = "🚗",
	TextSize = 22,
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.White,
	Parent = badge,
})
create("TextLabel", {
	Name = "Titulo",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(62, 9),
	Size = UDim2.new(1, -90, 0, 20),
	Text = "FIAT UNO SERVICE HUB",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = topBar,
})
create("TextLabel", {
	Name = "Subtitulo",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(62, 29),
	Size = UDim2.new(1, -90, 0, 16),
	Text = "Painel de controlo • v2.0",
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = THEME.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = topBar,
})
create("Frame", {
	Name = "Online",
	Position = UDim2.new(1, -24, 0, 25),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = THEME.Green,
	BorderSizePixel = 0,
	Parent = topBar,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

-- ── Contentor dos botões ──────────────────────────────────────
local content = create("Frame", {
	Name = "Conteudo",
	Position = UDim2.fromOffset(14, 72),
	Size = UDim2.new(1, -28, 0, CONFIG.ButtonHeight * 4 + 30),
	BackgroundTransparency = 1,
	Parent = main,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- Efeito de clarão ao clicar
local function flash(btn)
	local f = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.White,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = btn,
	}, { create("UICorner", { CornerRadius = UDim.new(0, 12) }) })
	tween(f, 0.4, { BackgroundTransparency = 1 }).Completed:Connect(function()
		f:Destroy()
	end)
end

-- Abanão (feedback de erro)
local function shake(btn)
	task.spawn(function()
		for _, r in ipairs({ -3, 3, -2, 2, 0 }) do
			tween(btn, 0.05, { Rotation = r })
			task.wait(0.05)
		end
	end)
end

-- Efeitos de hover / toque
local function attachEffects(btn, baseColor, noScale)
	local scale = btn:FindFirstChildOfClass("UIScale")
	local hover = false
	local function setHover(on)
		hover = on
		tween(btn, 0.15, { BackgroundColor3 = on and baseColor:Lerp(THEME.White, 0.14) or baseColor })
		if scale and not noScale then
			tween(scale, 0.15, { Scale = on and 1.03 or 1 })
		end
	end
	connect(btn.MouseEnter, function() setHover(true) end)
	connect(btn.MouseLeave, function() setHover(false) end)
	if not noScale then
		connect(btn.MouseButton1Down, function()
			tween(scale, 0.08, { Scale = 0.96 })
		end)
		connect(btn.MouseButton1Up, function()
			tween(scale, 0.12, { Scale = hover and 1.03 or 1 })
		end)
	end
end

-- Fábrica de botões estilizados
local function createButton(def)
	local btn = create("TextButton", {
		Name = def.name,
		LayoutOrder = def.order,
		Size = UDim2.new(1, 0, 0, CONFIG.ButtonHeight),
		BackgroundColor3 = def.color,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Parent = content,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 12) }),
		create("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200)),
			Rotation = 90,
		}),
		create("UIStroke", {
			Color = THEME.White,
			Transparency = 0.82,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("UIScale", { Scale = 1 }),
	})

	local iconBox = create("Frame", {
		Name = "IconBox",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Parent = btn,
	}, { create("UICorner", { CornerRadius = UDim.new(0, 10) }) })
	create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = def.icon,
		TextSize = 22,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.White,
		Parent = iconBox,
	})

	local pad = 74 + (def.rightPad or 0)
	local titleY = def.hasBar and 9 or 13
	create("TextLabel", {
		Name = "Titulo",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(62, titleY),
		Size = UDim2.new(1, -pad, 0, 22),
		Text = def.title,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = THEME.White,
		TextStrokeTransparency = 0.85,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = btn,
	})
	local sub = create("TextLabel", {
		Name = "Subtitulo",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(62, titleY + 22),
		Size = UDim2.new(1, -pad, 0, 16),
		Text = def.sub or "",
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = THEME.White,
		TextTransparency = 0.12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = btn,
	})

	attachEffects(btn, def.color, def.noScale)
	return btn, sub
end

-- Os 4 botões
local createBtn, createSub = createButton({
	name = "BtnCriar", order = 1, color = THEME.Green, icon = "🚗",
	title = "1. Criar Carro", sub = "Gera o Fiat Uno à sua frente",
})
local rpmBtn, rpmSub = createButton({
	name = "BtnRPM", order = 2, color = THEME.Orange, icon = "🏁",
	title = "2. RPM Máximo: 0 - 999", sub = "", hasBar = true, noScale = true,
})
local colorBtn, colorSub = createButton({
	name = "BtnCor", order = 3, color = THEME.Blue, icon = "🎨",
	title = "3. Editor de Cor", sub = "", rightPad = 34,
})
local deleteBtn, deleteSub = createButton({
	name = "BtnExcluir", order = 4, color = THEME.Red, icon = "🗑",
	title = "4. Excluir Carro", sub = "Remove o modelo do mundo",
})

-- Barra de progresso do RPM (dentro do botão 2)
local rpmTrack = create("Frame", {
	Name = "Trilho",
	Position = UDim2.fromOffset(62, 54),
	Size = UDim2.new(1, -74, 0, 6),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	Parent = rpmBtn,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
local rpmFill = create("Frame", {
	Name = "Preenchimento",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = rpmTrack,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

-- Amostra de cor (dentro do botão 3)
local swatch = create("Frame", {
	Name = "Amostra",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = CONFIG.Palette[1].Color,
	BorderSizePixel = 0,
	Parent = colorBtn,
}, {
	create("UICorner", { CornerRadius = UDim.new(1, 0) }),
	create("UIStroke", { Color = THEME.White, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
})

-- ── Barra de estado ───────────────────────────────────────────
local statusBar = create("Frame", {
	Name = "Estado",
	Position = UDim2.fromOffset(14, 72 + CONFIG.ButtonHeight * 4 + 30 + 12),
	Size = UDim2.new(1, -28, 0, 34),
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	Parent = main,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 10) }),
	create("UIStroke", { Color = THEME.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
})
local statusDot = create("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = THEME.Green,
	BorderSizePixel = 0,
	Parent = statusBar,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
local statusLabel = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(30, 0),
	Size = UDim2.new(1, -40, 1, 0),
	Text = "Pronto. Crie o carro para começar.",
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = statusBar,
})

local notifyId = 0
local function notify(text, color)
	notifyId = notifyId + 1
	local id = notifyId
	color = color or THEME.Green
	statusLabel.Text = text
	statusDot.BackgroundColor3 = color
	task.delay(3.5, function()
		if id == notifyId then
			statusLabel.Text = "Pronto."
			statusDot.BackgroundColor3 = THEME.Green
		end
	end)
end

-- ── HUD de condução (conta-rotações + controlos de toque) ─────
local hud = create("Frame", {
	Name = "Hud",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})

local TACH_H = 118
local tach = create("Frame", {
	Name = "ContaRotacoes",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(280, TACH_H),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Parent = hud,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 16) }),
	create("UIStroke", { Color = THEME.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	create("UIScale", { Scale = baseScale }),
})
create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.fromOffset(60, 14),
	Text = "RPM",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = THEME.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = tach,
})
local hudRpm = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 22),
	Size = UDim2.fromOffset(130, 46),
	Text = "0",
	Font = Enum.Font.GothamBold,
	TextSize = 40,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = tach,
})
local hudSpeed = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0.5, 0, 0, 22),
	Size = UDim2.new(0.5, -16, 0, 30),
	Text = "0 km/h",
	Font = Enum.Font.GothamBold,
	TextSize = 24,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = tach,
})
local hudGear = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0.5, 0, 0, 54),
	Size = UDim2.new(0.5, -16, 0, 16),
	Text = "Marcha: N",
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = THEME.Muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = tach,
})
local hudTrack = create("Frame", {
	Position = UDim2.fromOffset(16, 78),
	Size = UDim2.new(1, -32, 0, 10),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Parent = tach,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
local hudFill = create("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Green,
	BorderSizePixel = 0,
	Parent = hudTrack,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 96),
	Size = UDim2.new(1, -32, 0, 14),
	Text = "W/S acelerar/travar · A/D direção · Espaço travão de mão",
	Font = Enum.Font.Gotham,
	TextSize = 10,
	TextColor3 = THEME.Muted,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = tach,
})

-- Botão "Sair"
local exitBtn = create("TextButton", {
	Name = "BtnSair",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -(24 + TACH_H * baseScale + 10)),
	Size = UDim2.fromOffset(130, 36),
	BackgroundColor3 = THEME.Red,
	AutoButtonColor = true,
	Text = "⏏  Sair do carro",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = hud,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 10) }),
	create("UIScale", { Scale = baseScale }),
})

-- Controlos de toque (só em dispositivos com ecrã tátil)
local touchLeft = create("Frame", {
	Name = "ToqueEsquerda",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -20),
	Size = UDim2.fromOffset(172, 78),
	BackgroundTransparency = 1,
	Visible = UserInputService.TouchEnabled,
	Parent = hud,
}, { create("UIScale", { Scale = baseScale }) })
local touchRight = create("Frame", {
	Name = "ToqueDireita",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.fromOffset(78, 172),
	BackgroundTransparency = 1,
	Visible = UserInputService.TouchEnabled,
	Parent = hud,
}, { create("UIScale", { Scale = baseScale }) })

local function makePad(parent, text, pos, color, flag)
	local b = create("TextButton", {
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 30,
		TextColor3 = THEME.White,
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Position = pos,
		Size = UDim2.fromOffset(78, 78),
		Parent = parent,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 18) }),
		create("UIStroke", { Color = THEME.White, Transparency = 0.7, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local active
	connect(b.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			active = input
			Touch[flag] = true
			b.BackgroundTransparency = 0
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if active and (input == active
			or (input.UserInputType == Enum.UserInputType.MouseButton1
				and active.UserInputType == Enum.UserInputType.MouseButton1)) then
			active = nil
			Touch[flag] = false
			b.BackgroundTransparency = 0.25
		end
	end)
end
makePad(touchLeft,  "◀", UDim2.fromOffset(0, 0),  THEME.Blue,  "Left")
makePad(touchLeft,  "▶", UDim2.fromOffset(94, 0), THEME.Blue,  "Right")
makePad(touchRight, "▲", UDim2.fromOffset(0, 0),  THEME.Green, "Gas")
makePad(touchRight, "▼", UDim2.fromOffset(0, 94), THEME.Red,   "Brake")

-- ── Arrastar o painel pela barra de topo ──────────────────────
do
	local dragging, dragStart, startPos = false, nil, nil

	connect(topBar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = holder.Position
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			holder.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X / baseScale,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y / baseScale
			)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- Tecla RightShift mostra/oculta (PC)
connect(UserInputService.InputBegan, function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.RightShift then
		gui.Enabled = not gui.Enabled
	end
end)

----------------------------------------------------------------
-- 8) ATUALIZAÇÃO DA UI (RPM / COR / HUD)
----------------------------------------------------------------
local function updateRpmUI(animated)
	local shown = State.Driving and State.Limit or State.RPM
	local alpha = shown / CONFIG.MaxRPM
	if State.Driving then
		rpmSub.Text = string.format("Limite: %d  ·  Atual: %d RPM", State.Limit, math.floor(State.LiveRPM + 0.5))
	else
		rpmSub.Text = string.format("Atual: %d RPM  ·  arraste ↔", State.RPM)
	end
	if animated then
		tween(rpmFill, 0.2, { Size = UDim2.fromScale(alpha, 1) })
	else
		rpmFill.Size = UDim2.fromScale(alpha, 1)
	end
end

local function updateColorUI(index, animated)
	local entry = CONFIG.Palette[index]
	colorSub.Text = "Cor atual: " .. entry.Name
	if animated then
		tween(swatch, 0.3, { BackgroundColor3 = entry.Color })
	else
		swatch.BackgroundColor3 = entry.Color
	end
end

local function updateHud()
	local a = math.clamp(State.LiveRPM / CONFIG.MaxRPM, 0, 1)
	hudRpm.Text = tostring(math.floor(State.LiveRPM + 0.5))
	hudSpeed.Text = string.format("%d km/h", math.floor(math.abs(State.Speed) + 0.5))
	hudGear.Text = "Marcha: " .. State.Gear
	hudFill.Size = UDim2.fromScale(a, 1)
	if a < 0.6 then
		hudFill.BackgroundColor3 = THEME.Green:Lerp(THEME.Orange, a / 0.6)
	else
		hudFill.BackgroundColor3 = THEME.Orange:Lerp(THEME.Red, (a - 0.6) / 0.4)
	end
	updateRpmUI(false)
end

updateRpmUI(false)
updateColorUI(1, false)

----------------------------------------------------------------
-- 9) LÓGICA DO CARRO
----------------------------------------------------------------
-- Lê as entradas (teclado + botões de toque)
local function readInput()
	local throttle, steer, hand = 0, 0, false
	if not UserInputService:GetFocusedTextBox() then
		local down = function(k) return UserInputService:IsKeyDown(k) end
		if down(Enum.KeyCode.W) or down(Enum.KeyCode.Up) then throttle += 1 end
		if down(Enum.KeyCode.S) or down(Enum.KeyCode.Down) then throttle -= 1 end
		if down(Enum.KeyCode.A) or down(Enum.KeyCode.Left) then steer += 1 end
		if down(Enum.KeyCode.D) or down(Enum.KeyCode.Right) then steer -= 1 end
		hand = down(Enum.KeyCode.Space)
	end
	if Touch.Gas then throttle += 1 end
	if Touch.Brake then throttle -= 1 end
	if Touch.Left then steer += 1 end
	if Touch.Right then steer -= 1 end
	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1), hand
end

-- Altura do chão num ponto (nil se não houver chão)
local function groundAt(point)
	local r = Workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), State.RayParams)
	return r and r.Position.Y or nil
end

-- Um passo de física simplificada do carro
local function stepDrive(dt)
	local throttle, steerIn, hand = readInput()
	local limitA = math.clamp(State.Limit / CONFIG.MaxRPM, 0.2, 1)
	local maxSpeed = CONFIG.TopSpeedMin + CONFIG.TopSpeedRange * limitA
	local v = State.Speed

	-- Aceleração / travagem
	if throttle > 0 then
		if v < -0.5 then
			v += 80 * dt
		else
			local k = math.clamp(v / maxSpeed, 0, 1)
			v += (46 * (1 - k ^ 1.6) + 4) * dt
		end
	elseif throttle < 0 then
		if v > 0.5 then
			v -= 85 * dt
		else
			v -= 28 * (1 - math.clamp(-v / CONFIG.ReverseSpeed, 0, 1)) * dt
		end
	else
		local drag = 16 * dt
		if v > 0 then v = math.max(0, v - drag) else v = math.min(0, v + drag) end
	end
	if hand then
		local brake = 70 * dt
		if v > 0 then v = math.max(0, v - brake) else v = math.min(0, v + brake) end
	end
	v = math.clamp(v, -CONFIG.ReverseSpeed, maxSpeed)

	-- Direção (modelo de bicicleta)
	local maxSteer = 0.6 - 0.35 * math.clamp(math.abs(v) / maxSpeed, 0, 1)
	State.Steer += (steerIn * maxSteer - State.Steer) * math.min(1, dt * 8)
	State.Yaw += v * math.tan(State.Steer) / CONFIG.WheelBase * dt

	-- Movimento + colisão frontal/traseira simples
	local base = CFrame.new(State.Pos) * CFrame.Angles(0, State.Yaw, 0)
	local look = base.LookVector
	local step = v * dt
	if step ~= 0 then
		local dir = look * (step > 0 and 1 or -1)
		local hit = Workspace:Raycast(State.Pos + Vector3.new(0, 3.5, 0), dir * (math.abs(step) + 6.6), State.RayParams)
		if hit and hit.Normal.Y < 0.6 then
			v = -v * 0.25
			if math.abs(v) < 2 then v = 0 end
			step = 0
		end
	end
	State.Pos += look * step
	State.Speed = v

	-- Seguir o terreno (altura + inclinação)
	local f = groundAt(State.Pos + look * 5)
	local r = groundAt(State.Pos - look * 5)
	if f or r then
		f = f or r
		r = r or f
		local targetY = (f + r) / 2
		local targetPitch = math.clamp(math.atan2(f - r, 10), -0.6, 0.6)
		State.Pos = Vector3.new(State.Pos.X, State.Pos.Y + (targetY - State.Pos.Y) * math.min(1, dt * 14), State.Pos.Z)
		State.Pitch += (targetPitch - State.Pitch) * math.min(1, dt * 10)
		State.Fall = 0
	else
		State.Fall += 90 * dt
		State.Pos -= Vector3.new(0, State.Fall * dt, 0)
	end
	State.RootCF = CFrame.new(State.Pos) * CFrame.Angles(0, State.Yaw, 0)

	-- RPM e marcha (automática, 5 velocidades)
	local s = math.abs(v)
	local band = maxSpeed / 5
	local g = math.min(5, math.floor(s / band) + 1)
	local frac = math.clamp((s - (g - 1) * band) / band, 0, 1)
	local a
	if s < 1 then
		a = (throttle ~= 0) and 0.55 or 0.12
	else
		a = 0.3 + 0.65 * frac + ((throttle > 0) and 0.05 or 0)
	end
	a = math.clamp(a, 0.1, 1)
	State.LiveRPM += (a * State.Limit - State.LiveRPM) * math.min(1, dt * 7)
	if v < -0.5 then
		State.Gear = "R"
	elseif s < 0.5 and throttle == 0 then
		State.Gear = "N"
	else
		State.Gear = tostring(g)
	end
end

-- Simulação: condução (ou rotação visual parado) + seguimento do jogador
local function startSimulation()
	if State.SimConn then return end
	State.SimConn = RunService.Heartbeat:Connect(function(dt)
		local car = State.Car
		if not car or not car.Parent or State.Busy or not State.RootCF then return end
		dt = math.min(dt, 0.1)

		local driving = State.Driving
		if driving then stepDrive(dt) end

		local alpha = driving and (State.LiveRPM / CONFIG.MaxRPM) or (State.RPM / CONFIG.MaxRPM)
		if not driving then
			if alpha <= 0 then
				if State.Settled then return end -- já está em repouso
				State.Settled = true
			else
				State.Settled = false
			end
		end

		State.Clock += dt
		if driving then
			State.Spin = (State.Spin + State.Speed / 1.15 * dt) % (math.pi * 2)
		else
			State.Spin = (State.Spin + dt * alpha * 40) % (math.pi * 2)
		end

		local vib  = driving and alpha * 0.5 or alpha
		local bob  = math.sin(State.Clock * (26 + vib * 40)) * 0.04 * vib
		local sway = math.sin(State.Clock * (19 + vib * 30)) * math.rad(0.6) * vib
		local pose = State.RootCF
			* CFrame.Angles(State.Pitch, 0, 0)
			* CFrame.new(0, bob, 0)
			* CFrame.Angles(0, 0, sway)

		car:PivotTo(pose)
		for _, wheel in ipairs(State.Wheels) do
			local offset = State.LocalCF[wheel]
			if wheel.Parent and offset then
				local cf = pose
				if offset.Z < 0 and State.Steer ~= 0 then
					-- rodas dianteiras viram com a direção
					local px = offset.X < 0 and -2.75 or 2.75
					local pivot = Vector3.new(px, 1.15, offset.Z)
					cf = pose * CFrame.new(pivot) * CFrame.Angles(0, State.Steer, 0) * CFrame.new(-pivot)
				end
				wheel.CFrame = cf * offset * CFrame.Angles(-State.Spin, 0, 0)
			end
		end

		-- Mantém o jogador no banco do condutor
		if State.Driving then
			local c = State.Char
			if not c or not c.hrp.Parent or c.hum.Health <= 0 then
				exitCar()
			else
				c.hrp.CFrame = pose * CONFIG.SeatOffset
				updateHud()
			end
		end
	end)
end

-- Sair do carro (definição da função declarada acima)
exitCar = function()
	if not State.Driving then return end
	State.Driving = false
	State.Speed, State.Steer, State.LiveRPM, State.Fall = 0, 0, 0, 0
	State.Gear = "N"
	for k in pairs(Touch) do Touch[k] = false end

	local c = State.Char
	State.Char = nil
	if c then
		pcall(function()
			for inst, tr in pairs(c.hidden) do
				if inst.Parent then inst.Transparency = tr end
			end
			if c.hrp.Parent then
				c.hrp.Anchored = c.anchored
				if State.RootCF then
					c.hrp.CFrame = State.RootCF * CONFIG.ExitOffset
				end
				c.hrp.AssemblyLinearVelocity = Vector3.zero
			end
		end)
	end

	if State.Prompt then State.Prompt.ActionText = "Entrar" end
	hud.Visible = false
	holder.Visible = true
	State.Settled = false
	updateRpmUI(false)
	notify("🚪 Saiu do carro.", THEME.Blue)
end

-- Entrar no carro
local function enterCar()
	if State.Driving or State.Busy or not State.Car then return end
	local character = LocalPlayer.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		notify("⚠ Personagem não encontrado.", THEME.Red)
		return
	end

	-- Esconde o personagem (só localmente) para não atravessar o teto
	local hidden = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			hidden[d] = d.Transparency
			d.Transparency = 1
		end
	end
	State.Char = { hrp = hrp, hum = hum, anchored = hrp.Anchored, hidden = hidden }
	hrp.Anchored = true

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { State.Car, character }
	params.RespectCanCollide = true
	State.RayParams = params

	State.Driving = true
	State.Speed, State.Steer, State.Fall, State.LiveRPM = 0, 0, 0, 0
	State.Pos = State.RootCF.Position
	State.Yaw = select(2, State.RootCF:ToEulerAnglesYXZ())

	if State.Prompt then State.Prompt.ActionText = "Sair" end
	hud.Visible = true
	if UserInputService.TouchEnabled then holder.Visible = false end
	updateHud()
	notify("🚗 Ao volante! W/A/S/D para conduzir.", THEME.Green)
end

-- Remove o carro imediatamente e repõe o estado
local function destroyCarImmediate()
	if State.Driving then pcall(exitCar) end
	if State.SimConn then
		State.SimConn:Disconnect()
		State.SimConn = nil
	end
	if State.Car then
		pcall(function() State.Car:Destroy() end)
	end
	State.Car, State.Prompt, State.RootCF = nil, nil, nil
	State.Wheels, State.Body, State.Accent, State.LocalCF = {}, {}, {}, {}
	State.RPM, State.ColorIdx, State.Spin, State.Clock, State.Settled = 0, 1, 0, 0, true
	State.Speed, State.Steer, State.Pitch, State.Limit, State.LiveRPM = 0, 0, 0, CONFIG.MaxRPM, 0
	updateRpmUI(true)
	updateColorUI(1, true)
end

-- Verifica se existe carro; caso contrário avisa o jogador
local function requireCar(btn, message)
	if State.Car and not State.Car.Parent then
		destroyCarImmediate() -- o carro foi removido por outro meio
	end
	if State.Busy then
		notify("⏳ Aguarde a ação atual terminar...", THEME.Orange)
		return false
	end
	if not State.Car then
		notify(message or "⚠ Crie o carro primeiro (Botão 1).", THEME.Orange)
		shake(btn)
		return false
	end
	return true
end

-- Aplica uma cor da paleta à carroçaria (transição suave)
local function applyColor(index)
	local entry = CONFIG.Palette[index]
	local accent = entry.Color:Lerp(Color3.new(0, 0, 0), 0.35)
	for _, p in ipairs(State.Body) do
		if p.Parent then tween(p, 0.5, { Color = entry.Color }) end
	end
	for _, p in ipairs(State.Accent) do
		if p.Parent then tween(p, 0.5, { Color = accent }) end
	end
	updateColorUI(index, true)
end

-- Cria o carro à frente do jogador
local function spawnCar()
	if State.Busy then
		notify("⏳ Aguarde a ação atual terminar...", THEME.Orange)
		return
	end
	local character = LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		notify("⚠ Personagem não encontrado.", THEME.Red)
		shake(createBtn)
		return
	end

	State.Busy = true
	destroyCarImmediate() -- substitui carro existente

	local ok, err = pcall(function()
		-- Posição à frente do jogador + deteção do chão
		local ahead = hrp.Position + hrp.CFrame.LookVector * CONFIG.SpawnDistance
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = Workspace:Raycast(
			Vector3.new(ahead.X, hrp.Position.Y + 5, ahead.Z),
			Vector3.new(0, -60, 0),
			params
		)
		local groundY = hit and hit.Position.Y or (hrp.Position.Y - 3)
		local pos = Vector3.new(ahead.X, groundY, ahead.Z)

		-- Frente do carro aponta para a direita do jogador (vê-se a lateral)
		local rootCF = CFrame.lookAt(pos, pos + hrp.CFrame.RightVector)
		local startCF = rootCF * CFrame.new(0, 14, 0)

		local data = buildCar(startCF)
		State.Car, State.Wheels, State.Body = data.Model, data.Wheels, data.Body
		State.Accent, State.LocalCF = data.Accent, data.LocalCF
		State.RootCF = rootCF
		State.Pos = rootCF.Position
		State.Yaw = select(2, rootCF:ToEulerAnglesYXZ())
		State.Pitch = 0
		State.Prompt = data.Prompt
		data.Model.Parent = Workspace

		-- ProximityPrompt: entrar / sair
		data.Prompt.Triggered:Connect(function(plr)
			if plr ~= LocalPlayer or State.Busy then return end
			if State.Driving then
				exitCar()
			else
				enterCar()
			end
		end)

		-- Animação de queda com ressalto
		local cfv = Instance.new("CFrameValue")
		cfv.Value = startCF
		local conn = cfv:GetPropertyChangedSignal("Value"):Connect(function()
			if data.Model.Parent then data.Model:PivotTo(cfv.Value) end
		end)
		local tw = TweenService:Create(
			cfv,
			TweenInfo.new(0.9, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ Value = rootCF }
		)
		tw:Play()
		tw.Completed:Wait()
		conn:Disconnect()
		cfv:Destroy()
		if data.Model.Parent then
			data.Model:PivotTo(rootCF)
			data.Prompt.Enabled = true -- só agora é possível entrar
		end
	end)

	State.Busy = false

	if not ok then
		warn("[FiatUnoHub] Erro ao criar o carro: " .. tostring(err))
		destroyCarImmediate()
		notify("✖ Erro ao criar o carro.", THEME.Red)
		return
	end

	State.Settled = false
	startSimulation()
	notify("✔ Carro criado! Aproxime-se e prima E para entrar.", THEME.Green)
end

-- Exclui o carro com fade-out
local function removeCar()
	if not requireCar(deleteBtn, "⚠ Não há carro para excluir.") then return end
	if State.Driving then exitCar() end
	State.Busy = true
	local car = State.Car
	pcall(function()
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") then
				tween(d, 0.35, { Transparency = 1 })
			end
		end
	end)
	task.wait(0.4)
	destroyCarImmediate()
	State.Busy = false
	notify("🗑 Carro excluído do workspace.", THEME.Red)
end

----------------------------------------------------------------
-- 10) LIGAÇÃO DOS BOTÕES
----------------------------------------------------------------
-- Botão 1: criar
connect(createBtn.Activated, function()
	flash(createBtn)
	spawnCar()
end)

-- Botão 2: RPM (toque/arraste na barra, 0 - 999)
--   parado   -> simulação visual de rotação
--   a conduzir -> limite de RPM (mín. 200)
do
	local dragging = false

	local function setRpmFromX(x)
		local a = math.clamp((x - rpmTrack.AbsolutePosition.X) / math.max(rpmTrack.AbsoluteSize.X, 1), 0, 1)
		if a < 0.03 then a = 0 elseif a > 0.97 then a = 1 end
		local value = math.floor(a * CONFIG.MaxRPM + 0.5)
		if State.Driving then
			State.Limit = math.max(200, value)
		else
			State.RPM = value
		end
		updateRpmUI(false)
	end

	connect(rpmBtn.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if not requireCar(rpmBtn) then return end
			dragging = true
			setRpmFromX(input.Position.X)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setRpmFromX(input.Position.X)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if State.Driving then
				notify(string.format("⚙ Limite de RPM: %d", State.Limit), THEME.Orange)
			else
				notify(string.format("⚙ RPM definido: %d", State.RPM), THEME.Orange)
			end
		end
	end)
end

-- Botão 3: cor (cicla pela paleta)
connect(colorBtn.Activated, function()
	if not requireCar(colorBtn) then return end
	flash(colorBtn)
	State.ColorIdx = State.ColorIdx % #CONFIG.Palette + 1
	applyColor(State.ColorIdx)
	notify("🎨 Cor: " .. CONFIG.Palette[State.ColorIdx].Name, THEME.Blue)
end)

-- Botão 4: excluir
connect(deleteBtn.Activated, function()
	flash(deleteBtn)
	removeCar()
end)

-- Botão "Sair" do HUD
connect(exitBtn.Activated, function()
	exitCar()
end)

----------------------------------------------------------------
-- 11) MONTAGEM FINAL E LIMPEZA
----------------------------------------------------------------
local mounted = false
for _, container in ipairs(getContainers()) do
	local ok = pcall(function() gui.Parent = container end)
	if ok and gui.Parent == container then
		mounted = true
		break
	end
end
if not mounted then
	warn("[FiatUnoHub] Não foi possível montar a interface.")
	return
end

-- Animação de entrada do painel
tween(uiScale, 0.5, { Scale = baseScale }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Função de limpeza (chamada se o script for executado novamente)
env.FiatUnoHubCleanup = function()
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	connections = {}
	pcall(destroyCarImmediate)
	pcall(function() gui:Destroy() end)
end
