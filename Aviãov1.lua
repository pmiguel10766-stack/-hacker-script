--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║  Aviao_Monomotor_Flight.lua                                      ║
    ║  Monomotor de asa alta (estilo Cessna) • Roblox / Delta Executor ║
    ║  Repo: pmiguel10766-stack/-script-de-hacker                      ║
    ╚══════════════════════════════════════════════════════════════════╝

    CONTROLOS MOBILE
      • Manche (esquerda): arrastar  → baixo = nariz para cima, lados = inclinar
      • Potência (direita): arrastar o slider / botões MAX e IDLE
      • Leme: botões ◀ LEME / LEME ▶ (também direcionam em solo)
      • Botões: TREM DE ATERRAGEM, FARÓIS & LUZES, CÂMERA, SAIR

    CONTROLOS PC (opcional)
      • W/S = picar/cabrar   A/D = inclinar   Q/E = leme
      • Shift/Ctrl = potência   Z = máx   X = idle
      • G = trem   L = luzes   C = câmara
]]

-- ════════════════════════════════════════════════════════════════════
-- 1) SERVIÇOS E CONSTANTES
-- ════════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local GUI_NAME = "AviaoMonomotorFlightGui"
local MODEL_NAME = "AviaoMonomotorFlightModel"
local ENV = (getgenv and getgenv()) or _G

-- Parâmetros de voo (unidades em studs; 1 stud ≈ 0.28 m)
local CFG = {
	MAX_SPEED = 200,          -- velocidade máxima com potência total
	STALL = 42,               -- abaixo disto a sustentação desaparece
	ROTATE = 55,              -- velocidade mínima para levantar o nariz
	PITCH_DRAG = 110,         -- perda de velocidade ao subir / ganho ao picar
	ACCEL = 0.11,             -- resposta do motor
	TURN = 1.15,              -- taxa de curva em função da inclinação
	MAX_PITCH_UP = math.rad(32),
	MAX_PITCH_DN = math.rad(28),
	MAX_ROLL = math.rad(55),
	GEAR_H = 5.2,             -- altura do centro ao chão (trem estendido)
	BELLY_H = 3.7,            -- altura do centro ao chão (trem recolhido)
	GEAR_TIME = 2.2,          -- segundos para recolher / estender
	RPM_IDLE = 700,
	RPM_MAX = 2700,
	SPAWN_DIST = 45,          -- distância a que o avião nasce à frente
}

-- Paleta (tema escuro + neon)
local C = {
	WHITE = Color3.fromRGB(238, 238, 236),
	RED = Color3.fromRGB(176, 28, 38),
	DARK = Color3.fromRGB(28, 30, 36),
	GLASS = Color3.fromRGB(140, 195, 230),
	METAL = Color3.fromRGB(150, 155, 165),
	GREY = Color3.fromRGB(70, 74, 82),
	OFF = Color3.fromRGB(60, 62, 70),
	CYAN = Color3.fromRGB(0, 226, 255),
	GREEN = Color3.fromRGB(70, 255, 150),
	AMBER = Color3.fromRGB(255, 190, 60),
	DANGER = Color3.fromRGB(255, 70, 90),
	PANEL = Color3.fromRGB(12, 16, 30),
	TEXT = Color3.fromRGB(235, 242, 255),
	SUB = Color3.fromRGB(140, 155, 185),
}

-- ════════════════════════════════════════════════════════════════════
-- 2) GARBAGE COLLECTION: remove execuções anteriores
-- ════════════════════════════════════════════════════════════════════
local function safeDestroy(inst)
	pcall(function() inst:Destroy() end)
end

local function purgePrevious()
	if type(ENV.__AviaoMonomotorCleanup) == "function" then
		pcall(ENV.__AviaoMonomotorCleanup)
	end
	ENV.__AviaoMonomotorCleanup = nil

	local containers = {}
	pcall(function()
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		if pg then containers[#containers + 1] = pg end
	end)
	pcall(function()
		if gethui then containers[#containers + 1] = gethui() end
	end)
	pcall(function()
		containers[#containers + 1] = game:GetService("CoreGui")
	end)
	for _, container in ipairs(containers) do
		pcall(function()
			for _, child in ipairs(container:GetChildren()) do
				if child.Name == GUI_NAME then safeDestroy(child) end
			end
		end)
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == MODEL_NAME then safeDestroy(child) end
	end
end

-- ════════════════════════════════════════════════════════════════════
-- 3) PROGRAMA PRINCIPAL
-- ════════════════════════════════════════════════════════════════════
local function main()
	purgePrevious()

	local char = LP.Character or LP.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	assert(hum and hrp, "Personagem indisponível")
	hrp.Anchored = false
	local camera = Workspace.CurrentCamera

	local alive = true
	local conns = {}
	local function track(c) conns[#conns + 1] = c return c end

	local model, gui, controls
	local shutdown

	local pos = Vector3.zero
	local yaw, pitch, roll, speed = 0, 0, 0, 0
	local groundY, baseY = 0, 0
	local onGround = true

	shutdown = function()
		if not alive then return end
		alive = false
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		table.clear(conns)
		if model then safeDestroy(model) end
		if gui then safeDestroy(gui) end
		pcall(function()
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = hum
			camera.FieldOfView = 70
		end)
		pcall(function() if controls then controls:Enable() end end)
		pcall(function()
			if hrp and hrp.Parent then
				hrp.Anchored = false
				local right = CFrame.Angles(0, yaw, 0).RightVector
				local y = onGround and (groundY + 4) or pos.Y
				char:PivotTo(CFrame.new(pos.X + right.X * 9, y, pos.Z + right.Z * 9) * CFrame.Angles(0, yaw, 0))
				hum.Sit = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
		if ENV.__AviaoMonomotorCleanup == shutdown then ENV.__AviaoMonomotorCleanup = nil end
	end
	ENV.__AviaoMonomotorCleanup = shutdown

	-- ════════════════════════════════════════════════════════════════
	-- 4) MODELAGEM PROCEDURAL 3D
	-- ════════════════════════════════════════════════════════════════
	model = Instance.new("Model")
	model.Name = MODEL_NAME

	local registry = {}

	local function newGroup(base) return { base = base, cur = base } end

	local function mk(name, size, rel, color, mat, shape, transp, grp)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.Transparency = transp or 0
		p.Parent = model
		local entry = { part = p, rel = rel, grp = grp }
		if grp then entry.prel = grp.base:Inverse() * rel end
		registry[#registry + 1] = entry
		return p
	end

	local function cyl(name, len, dia, p, color, mat, grp, transp)
		return mk(name, Vector3.new(len, dia, dia),
			CFrame.new(p) * CFrame.Angles(0, math.rad(90), 0),
			color, mat, Enum.PartType.Cylinder, transp, grp)
	end

	local function beam(name, a, b, t, color, mat, grp)
		return mk(name, Vector3.new(t, t, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b), color, mat, nil, 0, grp)
	end

	local function ellipsoid(name, size, rel, color, grp)
		local p = mk(name, size, rel, color, nil, nil, 0, grp)
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
		return p
	end

	local root = mk("Raiz", Vector3.new(1, 1, 1), CFrame.identity, C.WHITE, nil, nil, 1)
	model.PrimaryPart = root

	-- Fuselagem
	cyl("Capo", 5.9, 4.2, Vector3.new(0, -0.7, -12.0), C.WHITE)
	cyl("FaixaCapo", 0.5, 4.3, Vector3.new(0, -0.7, -9.3), C.RED)
	mk("Cabine", Vector3.new(4.6, 2.4, 8), CFrame.new(0, -0.7, -5.0), C.WHITE)
	cyl("CabineInferior", 8, 4.0, Vector3.new(0, -1.6, -5.0), C.WHITE)
	cyl("Fuselagem1", 6, 4.2, Vector3.new(0, -0.9, 2.0), C.WHITE)
	cyl("Fuselagem2", 6, 3.2, Vector3.new(0, -0.3, 8.0), C.WHITE)
	cyl("Fuselagem3", 4, 2.4, Vector3.new(0, 0.3, 13.0), C.WHITE)
	cyl("Fuselagem4", 4, 1.5, Vector3.new(0, 0.7, 17.0), C.WHITE)

	for _, s in ipairs({ -1, 1 }) do
		mk("FaixaCabine", Vector3.new(0.12, 0.55, 8.0), CFrame.new(s * 2.31, -0.3, -5.0), C.RED)
		mk("FaixaTras1", Vector3.new(0.1, 0.5, 6.0), CFrame.new(s * 2.05, -0.5, 2.0), C.RED)
		mk("FaixaTras2", Vector3.new(0.1, 0.45, 6.0), CFrame.new(s * 1.55, -0.2, 8.0), C.RED)
		mk("EntradaAr", Vector3.new(1.0, 0.8, 0.15), CFrame.new(s * 1.05, -1.2, -14.93), C.DARK)
	end

	mk("ParaBrisa", Vector3.new(4.2, 3.0, 0.15),
		CFrame.new(0, 2.0, -8.6) * CFrame.Angles(math.rad(32), 0, 0),
		C.GLASS, Enum.Material.Glass, nil, 0.55)
	mk("VidroTras", Vector3.new(3.9, 2.9, 0.15), CFrame.new(0, 1.95, -1.55), C.GLASS, Enum.Material.Glass, nil, 0.55)
	mk("Teto", Vector3.new(4.4, 0.35, 6.2), CFrame.new(0, 3.55, -4.9), C.WHITE)
	for _, s in ipairs({ -1, 1 }) do
		mk("VidroLateral", Vector3.new(0.15, 2.9, 6.4), CFrame.new(s * 2.3, 1.95, -4.9), C.GLASS, Enum.Material.Glass, nil, 0.55)
		for _, zp in ipairs({ -8.0, -1.7 }) do
			mk("Montante", Vector3.new(0.3, 2.9, 0.3), CFrame.new(s * 2.3, 1.95, zp), C.WHITE)
		end
	end

	for _, sx in ipairs({ -1.1, 1.1 }) do
		mk("Assento", Vector3.new(1.7, 0.5, 1.8), CFrame.new(sx, -0.1, -5.0), C.DARK)
		mk("Encosto", Vector3.new(1.7, 2.0, 0.4), CFrame.new(sx, 1.0, -4.0), C.DARK)
	end
	mk("BancoTras", Vector3.new(3.8, 0.5, 1.8), CFrame.new(0, -0.1, -2.5), C.DARK)
	mk("EncostoTras", Vector3.new(3.8, 1.8, 0.4), CFrame.new(0, 0.9, -1.7), C.DARK)
	mk("Painel", Vector3.new(4.2, 0.9, 1.0), CFrame.new(0, 0.95, -8.3), C.DARK)
	mk("TelaPainel1", Vector3.new(1.0, 0.4, 0.05), CFrame.new(-0.9, 1.45, -7.78), C.CYAN, Enum.Material.Neon)
	mk("TelaPainel2", Vector3.new(1.0, 0.4, 0.05), CFrame.new(0.9, 1.45, -7.78), C.GREEN, Enum.Material.Neon)
	mk("ColunaManche", Vector3.new(0.18, 0.18, 1.0), CFrame.new(-1.1, 0.9, -7.3), C.GREY)
	mk("Manche", Vector3.new(0.9, 0.14, 0.14), CFrame.new(-1.1, 1.0, -6.8), C.DARK)

	mk("Asa", Vector3.new(38, 0.6, 4.2), CFrame.new(0, 3.95, -5.3), C.WHITE)
	mk("FaixaAsa", Vector3.new(38, 0.62, 0.5), CFrame.new(0, 3.95, -7.0), C.RED)
	local aileronGrp = {}
	for _, s in ipairs({ -1, 1 }) do
		cyl("PontaAsa", 4.2, 0.6, Vector3.new(s * 19, 3.95, -5.3), C.WHITE)
		mk("Flap", Vector3.new(7, 0.5, 1.5), CFrame.new(s * 6.6, 3.95, -2.45), C.WHITE)
		local g = newGroup(CFrame.new(s * 14.2, 3.95, -3.2))
		aileronGrp[s] = g
		mk("Aileron", Vector3.new(8, 0.45, 1.5), CFrame.new(s * 14.2, 3.95, -2.45), C.WHITE, nil, nil, 0, g)
		beam("Escora1", Vector3.new(s * 2.3, -1.5, -6.4), Vector3.new(s * 9.6, 3.65, -5.3), 0.38, C.WHITE, Enum.Material.Metal)
		beam("Escora2", Vector3.new(s * 2.3, -1.5, -4.2), Vector3.new(s * 9.6, 3.65, -5.3), 0.38, C.WHITE, Enum.Material.Metal)
	end

	mk("Deriva", Vector3.new(0.45, 5.6, 4.0), CFrame.new(0, 3.8, 14.6), C.WHITE)
	mk("DerivaTopo", Vector3.new(0.45, 1.0, 2.6), CFrame.new(0, 7.1, 15.3), C.RED)
	mk("Estabilizador", Vector3.new(13, 0.4, 4.0), CFrame.new(0, 1.0, 15.0), C.WHITE)
	local elevGrp = newGroup(CFrame.new(0, 1.0, 17.0))
	mk("Profundor", Vector3.new(13, 0.3, 1.8), CFrame.new(0, 1.0, 17.9), C.WHITE, nil, nil, 0, elevGrp)
	local rudGrp = newGroup(CFrame.new(0, 4.2, 16.6))
	mk("Leme", Vector3.new(0.35, 6.0, 1.8), CFrame.new(0, 4.2, 17.5), C.WHITE, nil, nil, 0, rudGrp)

	local propGrp = newGroup(CFrame.new(0, -0.7, -15.6))
	ellipsoid("Spinner", Vector3.new(2.0, 2.0, 2.8), CFrame.new(0, -0.7, -15.7), C.RED)
	local blades = {}
	for _, s in ipairs({ -1, 1 }) do
		blades[#blades + 1] = mk("Pa", Vector3.new(0.55, 3.4, 0.16), CFrame.new(0, -0.7 + s * 2.5, -15.0), C.DARK, nil, nil, 0, propGrp)
		blades[#blades + 1] = mk("PontaPa", Vector3.new(0.56, 0.8, 0.17), CFrame.new(0, -0.7 + s * 3.9, -15.0), C.AMBER, nil, nil, 0, propGrp)
	end
	local propDisc = cyl("DiscoHelice", 0.1, 8.6, Vector3.new(0, -0.7, -15.0), Color3.fromRGB(200, 205, 215), nil, propGrp, 1)

	local gearN = newGroup(CFrame.new(0, -2.6, -11.0))
	beam("PernaFrente", Vector3.new(0, -2.6, -11.0), Vector3.new(0, -4.0, -11.3), 0.45, C.METAL, Enum.Material.Metal, gearN)
	mk("RodaFrente", Vector3.new(0.8, 2.4, 2.4), CFrame.new(0, -4.0, -11.3), C.DARK, nil, Enum.PartType.Cylinder, 0, gearN)
	mk("CuboFrente", Vector3.new(0.9, 1.0, 1.0), CFrame.new(0, -4.0, -11.3), C.METAL, Enum.Material.Metal, Enum.PartType.Cylinder, 0, gearN)
	local gearM = {}
	for _, s in ipairs({ -1, 1 }) do
		local g = newGroup(CFrame.new(s * 2.1, -2.0, -3.2))
		gearM[s] = g
		beam("PernaPrincipal", Vector3.new(s * 2.1, -2.0, -3.2), Vector3.new(s * 3.7, -4.0, -3.2), 0.5, C.METAL, Enum.Material.Metal, g)
		mk("RodaPrincipal", Vector3.new(0.9, 2.4, 2.4), CFrame.new(s * 3.7, -4.0, -3.2), C.DARK, nil, Enum.PartType.Cylinder, 0, g)
		mk("CuboPrincipal", Vector3.new(1.0, 1.0, 1.0), CFrame.new(s * 3.7, -4.0, -3.2), C.METAL, Enum.Material.Metal, Enum.PartType.Cylinder, 0, g)
		mk("CarenagemRoda", Vector3.new(0.2, 1.9, 3.2), CFrame.new(s * 4.3, -3.9, -3.2), C.WHITE, nil, nil, 0, g)
	end

	local landing = mk("FarolDianteiro", Vector3.new(0.9, 0.9, 0.25), CFrame.new(0, -1.7, -14.97), C.OFF)
	local landSpot = Instance.new("SpotLight")
	landSpot.Face = Enum.NormalId.Front
	landSpot.Range = 60
	landSpot.Angle = 65
	landSpot.Brightness = 6
	landSpot.Color = Color3.fromRGB(255, 244, 220)
	landSpot.Enabled = false
	landSpot.Parent = landing

	local function ball(name, d, p, parent)
		return mk(name, Vector3.new(d, d, d), CFrame.new(p), C.OFF, nil, Enum.PartType.Ball)
	end
	local navL = ball("NavEsquerda", 0.9, Vector3.new(-19.2, 3.95, -5.3))
	local navR = ball("NavDireita", 0.9, Vector3.new(19.2, 3.95, -5.3))
	local navT = ball("NavCauda", 0.7, Vector3.new(0, 0.8, 19.1))
	local strobeL = ball("StrobeEsq", 0.6, Vector3.new(-19.1, 3.95, -3.4))
	local strobeR = ball("StrobeDir", 0.6, Vector3.new(19.1, 3.95, -3.4))
	local navLights = {
		{ part = navL, color = Color3.fromRGB(255, 40, 40) },
		{ part = navR, color = Color3.fromRGB(40, 255, 90) },
		{ part = navT, color = Color3.fromRGB(255, 255, 255) },
	}
	for _, n in ipairs(navLights) do
		local pl = Instance.new("PointLight")
		pl.Range = 14
		pl.Brightness = 1.5
		pl.Color = n.color
		pl.Enabled = false
		pl.Parent = n.part
		n.light = pl
	end
	local function setGlow(part, on, color)
		part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		part.Color = on and color or C.OFF
	end

	local trails = {}
	for _, tip in ipairs({ navL, navR }) do
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, 0.4, 0), Vector3.new(0, -0.4, 0)
		a0.Parent, a1.Parent = tip, tip
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.9
		tr.MinLength = 0.1
		tr.LightEmission = 0.4
		tr.Color = ColorSequence.new(Color3.new(1, 1, 1))
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		tr.Enabled = false
		tr.Parent = tip
		trails[#trails + 1] = tr
	end

	local emitters = {}
	for _, s in ipairs({ -1, 1 }) do
		local pipe = mk("Escape", Vector3.new(0.5, 0.5, 1.4), CFrame.new(s * 1.3, -2.5, -10.5), C.GREY, Enum.Material.Metal)
		local pe = Instance.new("ParticleEmitter")
		pe.EmissionDirection = Enum.NormalId.Back
		pe.Color = ColorSequence.new(Color3.fromRGB(190, 190, 195))
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.8) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(0.5, 1.0)
		pe.Speed = NumberRange.new(6, 12)
		pe.SpreadAngle = Vector2.new(12, 12)
		pe.Acceleration = Vector3.new(0, 2, 0)
		pe.Rotation = NumberRange.new(0, 360)
		pe.Rate = 0
		pe.Parent = pipe
		emitters[#emitters + 1] = pe
	end

	local pilotRel = CFrame.new(-1.1, 1.4, -5.0)

	-- Som do motor (em loop, preso à raiz do avião)
	local engineSound = Instance.new("Sound")
	engineSound.Name = "SomMotor"
	engineSound.SoundId = "rbxassetid://4690306390"
	engineSound.Looped = true
	engineSound.Volume = 0.4
	engineSound.RollOffMinDistance = 60
	engineSound.RollOffMaxDistance = 400
	engineSound.Parent = root
	engineSound:Play()

	local function applyPose(rootCF)
		for i = 1, #registry do
			local e = registry[i]
			if e.grp then
				e.part.CFrame = rootCF * e.grp.cur * e.prel
			else
				e.part.CFrame = rootCF * e.rel
			end
		end
	end

	-- ════════════════════════════════════════════════════════════════
	-- 5) POSICIONAMENTO INICIAL
	-- ════════════════════════════════════════════════════════════════
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model, char }
	rayParams.IgnoreWater = true

	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = (flat.Magnitude < 0.01) and Vector3.new(0, 0, -1) or flat.Unit
	local spawnXZ = hrp.Position + flat * CFG.SPAWN_DIST
	local gres = Workspace:Raycast(spawnXZ + Vector3.new(0, 60, 0), Vector3.new(0, -500, 0), rayParams)
	groundY = gres and gres.Position.Y or (hrp.Position.Y - 3)
	baseY = groundY
	pos = Vector3.new(spawnXZ.X, groundY + CFG.GEAR_H, spawnXZ.Z)
	yaw = math.atan2(-flat.X, -flat.Z)

	model.Parent = Workspace

	local throttleTarget, throttle, rpm = 0, 0, CFG.RPM_IDLE
	local gearTarget, gearAlpha = 1, 1
	local lightsOn = false
	local camMode = 1
	local propAng = 0
	local stick = Vector2.zero
	local rudderBtn = 0
	local stalling = false
	local collideCD = 0

	local function rootCFrame()
		return CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, roll)
	end
	applyPose(rootCFrame())

	hrp.Anchored = true
	hum.Sit = true
	char:PivotTo(rootCFrame() * pilotRel)

	pcall(function()
		local pm = require(LP:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 3))
		controls = pm:GetControls()
		controls:Disable()
	end)

	-- ════════════════════════════════════════════════════════════════
	-- 6) INTERFACE (HUD MOBILE • DARK / GLASSMORPHISM)
	-- ════════════════════════════════════════════════════════════════
	local UI = math.clamp(camera.ViewportSize.Y / 400, 0.8, 1.35)
	local function S(n) return math.floor(n * UI + 0.5) end

	gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100
	local okParent = pcall(function()
		gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not okParent or not gui.Parent then
		gui.Parent = LP:WaitForChild("PlayerGui")
	end

	local function corner(p, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = r
		c.Parent = p
		return c
	end
	local function stroke(p, col, th, tr)
		local s = Instance.new("UIStroke")
		s.Color = col
		s.Thickness = th
		s.Transparency = tr or 0
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = p
		return s
	end
	local function glass(p)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(36, 46, 80), Color3.fromRGB(10, 12, 24))
		g.Parent = p
	end
	local function newFrame(parent, name, size, p, anchor, color, transp)
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = size
		f.Position = p or UDim2.new()
		f.AnchorPoint = anchor or Vector2.zero
		f.BackgroundColor3 = color or C.PANEL
		f.BackgroundTransparency = transp or 0
		f.BorderSizePixel = 0
		f.Parent = parent
		return f
	end
	local function newLabel(parent, text, size, p, anchor, font, tsize, color, xalign)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = text
		l.Size = size
		l.Position = p or UDim2.new()
		l.AnchorPoint = anchor or Vector2.zero
		l.Font = font or Enum.Font.GothamMedium
		l.TextSize = tsize
		l.TextColor3 = color or C.TEXT
		l.TextXAlignment = xalign or Enum.TextXAlignment.Center
		l.Parent = parent
		return l
	end

	local btnStroke = {}

	local function newButton(parent, text, size, p, anchor, accent, tsize)
		local b = Instance.new("TextButton")
		b.AutoButtonColor = false
		b.Text = text
		b.Size = size
		b.Position = p
		b.AnchorPoint = anchor
		b.Font = Enum.Font.GothamBold
		b.TextSize = tsize or S(13)
		b.TextColor3 = C.TEXT
		b.BackgroundColor3 = C.PANEL
		b.BackgroundTransparency = 0.3
		b.BorderSizePixel = 0
		b.Parent = parent
		corner(b, UDim.new(0, S(12)))
		btnStroke[b] = stroke(b, accent, 1.5, 0.25)
		glass(b)
		return b
	end

	local toast = newLabel(gui, "", UDim2.new(0, S(360), 0, S(26)), UDim2.new(0.5, 0, 0.3, 0),
		Vector2.new(0.5, 0.5), Enum.Font.GothamBold, S(14), C.TEXT)
	toast.TextTransparency = 1
	toast.TextStrokeTransparency = 1
	local toastId = 0
	local function notify(text, color)
		toastId += 1
		local id = toastId
		toast.Text = text
		toast.TextColor3 = color or C.TEXT
		toast.TextTransparency = 0
		toast.TextStrokeTransparency = 0.6
		task.delay(1.8, function()
			if toastId == id and toast.Parent then
				TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	local panel = newFrame(gui, "Telemetria", UDim2.fromOffset(S(390), S(66)), UDim2.new(0.5, 0, 0, S(8)),
		Vector2.new(0.5, 0), C.PANEL, 0.25)
	corner(panel, UDim.new(0, S(14)))
	stroke(panel, C.CYAN, 1.5, 0.3)
	glass(panel)

	local function makeCell(i, title, vsize)
		local cell = newFrame(panel, "Cel" .. i, UDim2.new(0.25, 0, 1, 0), UDim2.new((i - 1) * 0.25, 0, 0, 0), nil, C.PANEL, 1)
		newLabel(cell, title, UDim2.new(1, 0, 0, S(16)), UDim2.new(0, 0, 0, S(6)), nil, Enum.Font.Gotham, S(10), C.SUB)
		return newLabel(cell, "0", UDim2.new(1, 0, 0, S(30)), UDim2.new(0, 0, 0, S(22)), nil, Enum.Font.GothamBold, vsize or S(22), C.CYAN)
	end
	local rpmValue = makeCell(1, "RPM")
	local spdValue = makeCell(2, "VELOCIDADE km/h")
	local altValue = makeCell(3, "ALTITUDE m")
	local gearValue = makeCell(4, "TREM", S(14))
	for i = 1, 3 do
		newFrame(panel, "Div", UDim2.new(0, 1, 0.6, 0), UDim2.new(i * 0.25, 0, 0.2, 0), nil, Color3.new(1, 1, 1), 0.85)
	end
	local rpmBarBg = newFrame(panel, "RpmBg", UDim2.new(0.17, 0, 0, S(4)), UDim2.new(0.04, 0, 1, -S(8)), nil, Color3.fromRGB(40, 48, 70), 0)
	corner(rpmBarBg, UDim.new(1, 0))
	local rpmBar = newFrame(rpmBarBg, "RpmFill", UDim2.new(0, 0, 1, 0), nil, nil, C.GREEN, 0)
	corner(rpmBar, UDim.new(1, 0))

	local statusPill = newFrame(gui, "Estado", UDim2.fromOffset(S(130), S(22)), UDim2.new(0.5, 0, 0, S(80)),
		Vector2.new(0.5, 0), C.PANEL, 0.3)
	corner(statusPill, UDim.new(1, 0))
	local statusStroke = stroke(statusPill, C.AMBER, 1.2, 0.2)
	local statusText = newLabel(statusPill, "● EM SOLO", UDim2.fromScale(1, 1), nil, nil, Enum.Font.GothamBold, S(11), C.AMBER)

	newLabel(gui, "PC: W/S A/D Q/E • Shift/Ctrl • G L C", UDim2.fromOffset(S(260), S(14)),
		UDim2.new(1, -S(10), 0, S(8)), Vector2.new(1, 0), Enum.Font.Gotham, S(10), C.SUB, Enum.TextXAlignment.Right)

	local exitBtn = newButton(gui, "✖ SAIR", UDim2.fromOffset(S(78), S(32)), UDim2.new(0, S(12), 0, S(10)),
		Vector2.zero, C.DANGER, S(12))

	local function makeDrag(obj, onStart, onMove, onEnd)
		local active
		track(obj.InputBegan:Connect(function(input)
			if active then return end
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				active = input
				onStart(Vector2.new(input.Position.X, input.Position.Y))
			end
		end))
		track(UIS.InputChanged:Connect(function(input)
			if not active then return end
			local same = (input == active)
				or (active.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
			if same then onMove(Vector2.new(input.Position.X, input.Position.Y)) end
		end))
		track(UIS.InputEnded:Connect(function(input)
			if not active then return end
			if input == active or (active.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
				active = nil
				onEnd()
			end
		end))
	end

	local joyBase = newFrame(gui, "Manche", UDim2.fromOffset(S(150), S(150)), UDim2.new(0, S(24), 1, -S(24)),
		Vector2.new(0, 1), C.PANEL, 0.4)
	corner(joyBase, UDim.new(0.5, 0))
	stroke(joyBase, C.CYAN, 1.5, 0.3)
	glass(joyBase)
	newFrame(joyBase, "LinhaH", UDim2.new(0.8, 0, 0, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.CYAN, 0.8)
	newFrame(joyBase, "LinhaV", UDim2.new(0, 1, 0.8, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.CYAN, 0.8)
	newLabel(joyBase, "MANCHE", UDim2.new(1, 0, 0, S(12)), UDim2.new(0, 0, 0, S(4)), nil, Enum.Font.Gotham, S(9), C.SUB)
	local knob = newFrame(joyBase, "Knob", UDim2.fromOffset(S(62), S(62)), UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5), C.CYAN, 0.2)
	corner(knob, UDim.new(0.5, 0))
	stroke(knob, Color3.new(1, 1, 1), 1.5, 0.4)

	local stickStart = Vector2.zero
	local STICK_R = S(60)
	makeDrag(joyBase,
		function(p) stickStart = p end,
		function(p)
			local d = p - stickStart
			if d.Magnitude > STICK_R then d = d.Unit * STICK_R end
			stick = d / STICK_R
			knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
		end,
		function()
			stick = Vector2.zero
			knob.Position = UDim2.fromScale(0.5, 0.5)
		end)

	local thrX = -S(22)
	newLabel(gui, "POTÊNCIA", UDim2.fromOffset(S(70), S(12)),
		UDim2.new(1, thrX + S(8), 1, -S(24 + 30 + 6 + 150 + 6 + 30 + 4)), Vector2.new(1, 1), Enum.Font.Gotham, S(9), C.SUB)
	local maxBtn = newButton(gui, "MAX", UDim2.fromOffset(S(54), S(30)),
		UDim2.new(1, thrX, 1, -S(24 + 30 + 6 + 150 + 6)), Vector2.new(1, 1), C.GREEN, S(11))
	local idleBtn = newButton(gui, "IDLE", UDim2.fromOffset(S(54), S(30)),
		UDim2.new(1, thrX, 1, -S(24)), Vector2.new(1, 1), C.AMBER, S(11))
	local track0 = newFrame(gui, "TrilhoPotencia", UDim2.fromOffset(S(54), S(150)),
		UDim2.new(1, thrX, 1, -S(24 + 30 + 6)), Vector2.new(1, 1), C.PANEL, 0.35)
	corner(track0, UDim.new(0, S(14)))
	stroke(track0, C.CYAN, 1.5, 0.3)
	glass(track0)
	local thrFill = newFrame(track0, "Preench", UDim2.new(1, 0, 0, 0), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1), C.CYAN, 0.35)
	corner(thrFill, UDim.new(0, S(14)))
	local thrHandle = newFrame(track0, "Pega", UDim2.new(1, S(8), 0, S(10)), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 0.5), Color3.new(1, 1, 1), 0.05)
	corner(thrHandle, UDim.new(0, S(5)))
	local thrPct = newLabel(track0, "0%", UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.4), nil, Enum.Font.GothamBold, S(12), C.TEXT)
	thrPct.ZIndex = 5

	local function setThrottle(v) throttleTarget = math.clamp(v, 0, 1) end
	local thrStartY, thrStartVal = 0, 0
	makeDrag(track0,
		function(p) thrStartY = p.Y thrStartVal = throttleTarget end,
		function(p) setThrottle(thrStartVal + (thrStartY - p.Y) / S(130)) end,
		function() end)
	track(maxBtn.Activated:Connect(function() setThrottle(1) end))
	track(idleBtn.Activated:Connect(function() setThrottle(0) end))

	local colX = -S(22 + 54 + 12)
	local gearBtn = newButton(gui, "🛞 TREM DE ATERRAGEM", UDim2.fromOffset(S(176), S(44)),
		UDim2.new(1, colX, 1, -S(24 + 36 + 8 + 44 + 8)), Vector2.new(1, 1), C.GREEN, S(12))
	local lightBtn = newButton(gui, "💡 FARÓIS & LUZES", UDim2.fromOffset(S(176), S(44)),
		UDim2.new(1, colX, 1, -S(24 + 36 + 8)), Vector2.new(1, 1), C.AMBER, S(12))
	local camBtn = newButton(gui, "🎥 CÂMERA", UDim2.fromOffset(S(176), S(36)),
		UDim2.new(1, colX, 1, -S(24)), Vector2.new(1, 1), C.CYAN, S(12))

	local pedalL = newButton(gui, "◀ LEME", UDim2.fromOffset(S(96), S(44)),
		UDim2.new(0.5, -S(6), 1, -S(24)), Vector2.new(1, 1), C.CYAN, S(12))
	local pedalR = newButton(gui, "LEME ▶", UDim2.fromOffset(S(96), S(44)),
		UDim2.new(0.5, S(6), 1, -S(24)), Vector2.new(0, 1), C.CYAN, S(12))
	local leftHeld, rightHeld = false, false
	local function updRudder() rudderBtn = (rightHeld and 1 or 0) - (leftHeld and 1 or 0) end
	makeDrag(pedalL, function() leftHeld = true updRudder() end, function() end, function() leftHeld = false updRudder() end)
	makeDrag(pedalR, function() rightHeld = true updRudder() end, function() end, function() rightHeld = false updRudder() end)

	local function refreshButtons()
		local gc = (gearTarget == 1) and C.GREEN or C.AMBER
		btnStroke[gearBtn].Color = gc
		gearBtn.BackgroundColor3 = gc:Lerp(C.PANEL, 0.82)
		btnStroke[lightBtn].Color = lightsOn and C.AMBER or C.SUB
		lightBtn.BackgroundColor3 = lightsOn and C.AMBER:Lerp(C.PANEL, 0.75) or C.PANEL
	end

	local function toggleGear()
		if gearTarget == 1 then
			if onGround then
				notify("Impossível recolher o trem em solo", C.DANGER)
				return
			end
			gearTarget = 0
			notify("Trem de aterragem: RECOLHENDO", C.AMBER)
		else
			gearTarget = 1
			notify("Trem de aterragem: ESTENDENDO", C.GREEN)
		end
		refreshButtons()
	end
	local function toggleLights()
		lightsOn = not lightsOn
		notify(lightsOn and "Faróis e luzes LIGADOS" or "Faróis e luzes DESLIGADOS", lightsOn and C.AMBER or C.SUB)
		refreshButtons()
	end
	local function toggleCam()
		camMode = (camMode == 1) and 2 or 1
		notify(camMode == 1 and "Câmera: EXTERNA" or "Câmera: COCKPIT", C.CYAN)
	end
	track(gearBtn.Activated:Connect(toggleGear))
	track(lightBtn.Activated:Connect(toggleLights))
	track(camBtn.Activated:Connect(toggleCam))
	track(exitBtn.Activated:Connect(function() shutdown() end))
	refreshButtons()

	track(UIS.InputBegan:Connect(function(input, gpe)
		if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local k = input.KeyCode
		if k == Enum.KeyCode.G then toggleGear()
		elseif k == Enum.KeyCode.L then toggleLights()
		elseif k == Enum.KeyCode.C then toggleCam()
		elseif k == Enum.KeyCode.Z then setThrottle(1)
		elseif k == Enum.KeyCode.X then setThrottle(0) end
	end))

	track(hum.Died:Connect(function() shutdown() end))
	track(char.AncestryChanged:Connect(function(_, parent) if not parent then shutdown() end end))

	-- ════════════════════════════════════════════════════════════════
	-- 7) LOOP DE FÍSICA, ANIMAÇÃO E HUD
	-- ════════════════════════════════════════════════════════════════
	local function deadzone(v)
		local a = math.abs(v)
		if a < 0.1 then return 0 end
		return math.sign(v) * (a - 0.1) / 0.9
	end

	local hudAcc = 0
	local errCount = 0

	local function step(dt)
		dt = math.min(dt, 0.08)
		local now = os.clock()

		local kx = (UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
		local ky = (UIS:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
		local kr = (UIS:IsKeyDown(Enum.KeyCode.E) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.Q) and 1 or 0)
		local ix = math.clamp(deadzone(stick.X) + kx, -1, 1)
		local iy = math.clamp(deadzone(stick.Y) + ky, -1, 1)
		local rud = math.clamp(rudderBtn + kr, -1, 1)
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then setThrottle(throttleTarget + dt * 0.45) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then setThrottle(throttleTarget - dt * 0.45) end

		throttle += math.clamp(throttleTarget - throttle, -dt * 0.9, dt * 0.9)
		local rpmTarget = CFG.RPM_IDLE + throttle * (CFG.RPM_MAX - CFG.RPM_IDLE)
		rpm += (rpmTarget - rpm) * math.min(1, dt * 3)
		local rpmN = math.clamp((rpm - CFG.RPM_IDLE) / (CFG.RPM_MAX - CFG.RPM_IDLE), 0, 1)

		-- Tom e volume do motor acompanham o RPM
		engineSound.PlaybackSpeed = 0.6 + rpmN * 1.0
		engineSound.Volume = 0.35 + rpmN * 0.65

		gearAlpha += math.clamp(gearTarget - gearAlpha, -dt / CFG.GEAR_TIME, dt / CFG.GEAR_TIME)
		local gearH = CFG.BELLY_H + (CFG.GEAR_H - CFG.BELLY_H) * gearAlpha

		local liftF = math.clamp((speed - 23) / (CFG.STALL - 23), 0, 1)
		local ctrlAuth = math.clamp((speed - 25) / 35, 0, 1)
		stalling = (not onGround) and speed < CFG.STALL

		local pTarget = (iy > 0 and iy * CFG.MAX_PITCH_UP or iy * CFG.MAX_PITCH_DN) * ctrlAuth
		if stalling then
			pTarget = math.max(pTarget - (1 - liftF) * math.rad(25), -math.rad(35))
		end
		if onGround then
			pTarget = (speed < CFG.ROTATE) and 0 or math.max(pTarget, 0)
		end
		pitch += (pTarget - pitch) * math.min(1, dt * 2.6)

		local rTarget = onGround and 0 or (-ix * CFG.MAX_ROLL * (0.35 + 0.65 * liftF))
		roll += (rTarget - roll) * math.min(1, dt * 3)
		local turn
		if onGround then
			turn = -(ix * 0.55 + rud * 0.9) * math.clamp(speed / 25, 0, 1)
		else
			turn = math.sin(roll) * CFG.TURN - rud * 0.45
		end
		yaw += turn * dt

		local target = math.max(throttle * CFG.MAX_SPEED - math.sin(pitch) * CFG.PITCH_DRAG, 0)
		speed += (target - speed) * math.min(1, dt * CFG.ACCEL * 1.0)
		if onGround then
			local brake = (throttle < 0.04) and 14 or 3
			speed = math.max(0, speed - brake * dt - speed * 0.03 * dt)
			if gearAlpha < 0.6 then
				speed = math.max(0, speed - speed * 0.9 * dt - 6 * dt)
			end
		end
		speed = math.clamp(speed, 0, CFG.MAX_SPEED * 1.35)

		local orient = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local fwd = orient.LookVector
		local vel = fwd * speed
		if not onGround then
			vel += Vector3.new(0, -(1 - liftF) * 70, 0)
		end

		-- Colisão nas asas: só ativa com RPM alto e atitude (pitch) alta
		local function wingCollisionActive()
			return rpmN > 0.7 and math.abs(pitch) > math.rad(12)
		end

		-- Colisão frontal + asas (asas só quando a condição acima se cumpre)
		if (not onGround) and speed > 5 and now > collideCD then
			local fwdDir = fwd * (speed * dt + 9)
			local offsets = { Vector3.zero }
			if wingCollisionActive() then
				local right = orient.RightVector * 19 -- meia envergadura
				offsets = { Vector3.zero, right, -right }
			end
			for _, off in ipairs(offsets) do
				local origin = pos + off
				local hit = Workspace:Raycast(origin, fwdDir, rayParams)
				if hit then
					collideCD = now + 1.5
					speed *= 0.25
					pos += hit.Normal * 2
					vel = Vector3.zero
					notify("⚠ COLISÃO", C.DANGER)
					break
				end
			end
		end

		pos += vel * dt
		pos = Vector3.new(pos.X, math.min(pos.Y, 4500), pos.Z)

		local res = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -1500, 0), rayParams)
		if res then groundY = res.Position.Y end
		local agl = pos.Y - groundY
		if agl < gearH then
			pos = Vector3.new(pos.X, groundY + gearH, pos.Z)
			agl = gearH
		end
		local wasOnGround = onGround
		onGround = agl <= gearH + 0.35
		if onGround and not wasOnGround then
			notify(gearAlpha < 0.6 and "Aterragem de barriga!" or "Tocou o solo", gearAlpha < 0.6 and C.DANGER or C.GREEN)
		end

		aileronGrp[-1].cur = aileronGrp[-1].base * CFrame.Angles(ix * 0.4, 0, 0)
		aileronGrp[1].cur = aileronGrp[1].base * CFrame.Angles(-ix * 0.4, 0, 0)
		elevGrp.cur = elevGrp.base * CFrame.Angles(-iy * 0.4, 0, 0)
		rudGrp.cur = rudGrp.base * CFrame.Angles(0, rud * 0.45, 0)

		local ret = 1 - gearAlpha
		gearN.cur = gearN.base * CFrame.Angles(-1.9 * ret, 0, 0)
		gearM[1].cur = gearM[1].base * CFrame.Angles(0, 0, -2.3 * ret)
		gearM[-1].cur = gearM[-1].base * CFrame.Angles(0, 0, 2.3 * ret)

		propAng += (6 + rpmN * 34) * dt
		propGrp.cur = propGrp.base * CFrame.Angles(0, 0, propAng)
		local bt = rpmN * 0.75
		for _, b in ipairs(blades) do b.Transparency = bt end
		propDisc.Transparency = 1 - rpmN * 0.2

		local rootCF = rootCFrame()
		applyPose(rootCF)
		char:PivotTo(rootCF * pilotRel)

		local t = os.clock()
		landSpot.Enabled = lightsOn
		setGlow(landing, lightsOn, Color3.fromRGB(255, 244, 220))
		for _, n in ipairs(navLights) do
			n.light.Enabled = lightsOn
			setGlow(n.part, lightsOn, n.color)
		end
		local ph = t % 1.3
		local strobeOn = lightsOn and (ph < 0.08 or (ph > 0.2 and ph < 0.28))
		setGlow(strobeL, strobeOn, Color3.new(1, 1, 1))
		setGlow(strobeR, strobeOn, Color3.new(1, 1, 1))

		for _, pe in ipairs(emitters) do
			pe.Rate = (throttle > 0.03) and (6 + throttle * 40) or 0
			pe.Speed = NumberRange.new(4 + throttle * 8, 8 + throttle * 12)
		end
		local trailOn = (not onGround) and speed > 85
		for _, tr in ipairs(trails) do tr.Enabled = trailOn end

		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local goal, alpha
		if camMode == 1 then
			local cp = rootCF.Position - rootCF.LookVector * 36 + Vector3.new(0, 10, 0)
			cp = Vector3.new(cp.X, math.max(cp.Y, groundY + 3), cp.Z)
			goal = CFrame.lookAt(cp, rootCF.Position + rootCF.LookVector * 25 + Vector3.new(0, 3, 0))
			alpha = 1 - math.exp(-dt * 5)
			camera.FieldOfView = 70
		else
			goal = rootCF * CFrame.new(-1.1, 2.6, -5.6)
			alpha = 1
			camera.FieldOfView = 80
		end
		camera.CFrame = camera.CFrame:Lerp(goal, alpha)

		hudAcc += dt
		if hudAcc >= 0.066 then
			hudAcc = 0
			rpmValue.Text = string.format("%d", math.floor(rpm / 10) * 10)
			rpmBar.Size = UDim2.new(math.clamp(rpm / CFG.RPM_MAX, 0, 1), 0, 1, 0)
			rpmBar.BackgroundColor3 = (rpm < 2200) and C.GREEN or ((rpm < 2500) and C.AMBER or C.DANGER)
			spdValue.Text = tostring(math.floor(speed * 1.008))
			spdValue.TextColor3 = stalling and C.DANGER or C.CYAN
			altValue.Text = tostring(math.max(0, math.floor((pos.Y - baseY - CFG.GEAR_H) * 0.28)))

			if gearAlpha >= 0.995 then
				gearValue.Text, gearValue.TextColor3 = "BAIXADO", C.GREEN
			elseif gearAlpha <= 0.005 then
				gearValue.Text, gearValue.TextColor3 = "RECOLHIDO", C.AMBER
			else
				gearValue.Text = (gearTarget == 1) and "ESTENDENDO" or "RECOLHENDO"
				gearValue.TextColor3 = C.CYAN
			end

			if stalling then
				local blink = (math.floor(t * 4) % 2 == 0)
				statusText.Text = "⚠ STALL"
				statusText.TextColor3 = blink and C.DANGER or C.TEXT
				statusStroke.Color = C.DANGER
			elseif onGround then
				statusText.Text = "● EM SOLO"
				statusText.TextColor3, statusStroke.Color = C.AMBER, C.AMBER
			else
				statusText.Text = "● EM VOO"
				statusText.TextColor3, statusStroke.Color = C.GREEN, C.GREEN
			end

			thrFill.Size = UDim2.new(1, 0, throttleTarget, 0)
			thrHandle.Position = UDim2.new(0.5, 0, 1 - throttleTarget, 0)
			thrPct.Text = string.format("%d%%", math.floor(throttleTarget * 100 + 0.5))
		end
	end

	track(RunService.RenderStepped:Connect(function(dt)
		if not alive then return end
		local ok, err = pcall(step, dt)
		if not ok then
			errCount += 1
			if errCount == 1 then warn("[Aviao_Monomotor_Flight] Erro no loop: " .. tostring(err)) end
			if errCount > 40 then shutdown() end
		end
	end))

	notify("Monomotor pronto — aumente a potência e descole!", C.CYAN)
end

-- ════════════════════════════════════════════════════════════════════
-- 8) ARRANQUE SEGURO (task.spawn + pcall)
-- ════════════════════════════════════════════════════════════════════
task.spawn(function()
	local ok, err = pcall(main)
	if not ok then
		warn("[Aviao_Monomotor_Flight] Falha ao iniciar: " .. tostring(err))
		pcall(purgePrevious)
	end
end)
