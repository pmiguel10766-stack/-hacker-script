--[[
    SUBMARINO.LUA — Submersível Panorâmico de Exploração
    Luau / Roblox (LocalScript ou executor: Delta, mobile e PC)

    COMO USAR (loadstring):
    loadstring(game:HttpGet("https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main/Submarino.lua"))()

    CONTROLOS PC:
      W/S = avançar/recuar     A/D = virar
      Espaço = SUBIR (esvazia lastro)    Shift/Ctrl = DESCER (enche lastro)
      Q/E = nariz para cima/baixo        L = holofotes     X = entrar/sair
    MOBILE: botões no ecrã (esquerda = movimento, direita = lastro/nariz/luz).

    NOTA: corre do lado do cliente, por isso só tu vês o submarino.
]]

----------------------------------------------------------------------
-- 1. SERVIÇOS
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local Workspace        = game:GetService("Workspace")

local Jogador = Players.LocalPlayer
local Terreno = Workspace.Terrain

----------------------------------------------------------------------
-- 2. LIMPEZA DE EXECUÇÕES ANTERIORES (evita submarinos duplicados)
----------------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G
if ENV.__SubmarinoPanoramico then
    pcall(ENV.__SubmarinoPanoramico.Destruir)
    ENV.__SubmarinoPanoramico = nil
end

----------------------------------------------------------------------
-- 3. CONFIGURAÇÃO (ajusta à vontade)
----------------------------------------------------------------------
local CFG = {
    -- Visual
    COR_CASCO   = Color3.fromRGB(255, 170, 0),   -- amarelo vibrante
    COR_DETALHE = Color3.fromRGB(18, 18, 22),    -- preto das grelhas
    COR_METAL   = Color3.fromRGB(135, 140, 148),
    COR_VIDRO   = Color3.fromRGB(200, 230, 255),

    -- Água: "AUTO" lê a água do Terrain | "VIRTUAL" usa NIVEL_AGUA (Y fixo)
    MODO_AGUA  = "AUTO",
    NIVEL_AGUA = 0,
    STUD_METRO = 0.28,          -- 1 stud ≈ 0.28 m

    -- Movimento
    VEL_MAX       = 38,                 -- studs/s
    ACELERACAO    = 1.6,                -- suavização da velocidade
    VEL_VERTICAL  = 22,                 -- studs/s no máximo do lastro
    VEL_GUINADA   = 1.1,                -- rad/s
    VEL_NARIZ     = math.rad(55),       -- graus/s
    NARIZ_MAX     = math.rad(35),
    NIVELAR       = 1.8,                -- auto-nivelamento do nariz
    LASTRO_VEL    = 0.9,                -- fração/s ao carregar no botão
    LASTRO_RETORNO = 1.2,               -- volta ao neutro (0 = lastro manual)

    -- Recursos
    O2_DURACAO     = 900,   -- segundos de oxigénio (parado, à superfície = infinito)
    O2_RECARGA     = 8,     -- %/s à superfície
    BAT_DURACAO    = 1200,  -- segundos de bateria
    BAT_RECARGA    = 1.5,   -- %/s à superfície (painéis solares); 0 = desliga
    LIMITE_SUPERFICIE = 2.8, -- studs de profundidade considerados "superfície"

    -- Escuridão com a profundidade
    ESCURIDAO  = true,
    PROF_ESCURA = 120,      -- metros em que fica o mais escuro

    -- Entrada no submarino
    DIST_EMBARQUE  = 40,
    ALTURA_PILOTO  = 2.3,   -- ajusta se o boneco ficar alto/baixo no assento
}

----------------------------------------------------------------------
-- 4. ESTADO
----------------------------------------------------------------------
local S = {
    piloto = false,
    lastro = 0.5,            -- 0 = tanques vazios (sobe) | 1 = cheios (desce)
    vel = 0, yaw = 0, pitch = 0,
    luzes = false,
    oxigenio = 100, bateria = 100,
    emergencia = false,
    emAgua = false, superficieY = nil,
    ultimaAgua = -math.huge, ultimaSup = -math.huge,
    profundidade = 0,        -- em studs
    avisoTxt = "", avisoAte = 0,
}

local ent = {                -- teclas/botões premidos
    frente = false, tras = false, esq = false, dir = false,
    subir = false, descer = false, narizCima = false, narizBaixo = false,
}

local conexoes = {}
local function conectar(sinal, fn)
    local c = sinal:Connect(fn)
    table.insert(conexoes, c)
    return c
end

-- Declarações antecipadas (usadas por várias funções abaixo)
local hud, Modelo, Raiz, Refs, BV, BG, Efeito
local weldPiloto, humPiloto
local atualizarBotaoEmbarque

local function avisar(txt, seg)
    S.avisoTxt = txt
    S.avisoAte = os.clock() + (seg or 2.5)
end

----------------------------------------------------------------------
-- 5. DETECÇÃO DE ÁGUA (Terrain) — leituras leves e espaçadas
----------------------------------------------------------------------
-- Há água na voxel (4x4x4 studs) desta posição?
local function lerAgua(pos)
    local ok, res = pcall(function()
        local c = Terreno:WorldToCell(pos)
        local centro = Terreno:CellCenterToWorld(c.X, c.Y, c.Z)
        local reg = Region3.new(centro - Vector3.new(2, 2, 2), centro + Vector3.new(2, 2, 2))
        local mats, occ = Terreno:ReadVoxels(reg, 4)
        return mats[1][1][1] == Enum.Material.Water and occ[1][1][1] > 0.05
    end)
    return ok and res == true
end

-- Procura a superfície da água numa coluna acima da posição (1 leitura só)
local function acharSuperficie(pos)
    local ok, res = pcall(function()
        local reg = Region3.new(
            Vector3.new(pos.X - 2, pos.Y - 4, pos.Z - 2),
            Vector3.new(pos.X + 2, pos.Y + 1024, pos.Z + 2)
        ):ExpandToGrid(4)
        local mats, occ = Terreno:ReadVoxels(reg, 4)
        local base = reg.CFrame.Position - reg.Size / 2
        local nx, ny, nz = #mats, #mats[1], #mats[1][1]
        for iy = ny, 1, -1 do
            for ix = 1, nx do
                for iz = 1, nz do
                    if mats[ix][iy][iz] == Enum.Material.Water then
                        return base.Y + (iy - 1) * 4 + occ[ix][iy][iz] * 4
                    end
                end
            end
        end
        return nil
    end)
    if ok then return res end
    return nil
end

local function detectarAgua(pos)
    if CFG.MODO_AGUA == "VIRTUAL" then
        S.superficieY = CFG.NIVEL_AGUA
        S.emAgua = pos.Y < CFG.NIVEL_AGUA
        return
    end
    local agora = os.clock()
    if lerAgua(pos) then
        S.ultimaAgua = agora
        if not S.superficieY or (agora - S.ultimaSup) > 0.6 then
            S.superficieY = acharSuperficie(pos) or S.superficieY
            S.ultimaSup = agora
        end
        S.emAgua = true
    else
        -- pequena tolerância para não "cair" ao tocar na superfície
        S.emAgua = S.superficieY ~= nil
            and (agora - S.ultimaAgua) < 1
            and pos.Y < S.superficieY + 1
    end
end

----------------------------------------------------------------------
-- 6. CONSTRUÇÃO PROCEDURAL DO SUBMARINO
----------------------------------------------------------------------
local giraZ = CFrame.Angles(0, math.rad(90), 0)  -- cilindro deitado ao longo de Z
local giraY = CFrame.Angles(0, 0, math.rad(90))  -- cilindro em pé (eixo Y)
local CIL, ESF = Enum.PartType.Cylinder, Enum.PartType.Ball
local PLAST, METAL = Enum.Material.SmoothPlastic, Enum.Material.Metal

-- Cria uma peça leve, sem colisão (por defeito) e soldada à peça "pai"
local function criar(modelo, pai, nome, tam, cf, cor, mat, forma, transp, colide)
    local p = Instance.new("Part")
    p.Name = nome
    p.Size = tam
    p.Color = cor
    p.Material = mat or PLAST
    if forma then p.Shape = forma end
    p.Transparency = transp or 0
    p.CanCollide = (colide == true)
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Massless = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CFrame = pai.CFrame * cf
    p.Parent = modelo
    local w = Instance.new("Weld")
    w.Part0, w.Part1, w.C0 = pai, p, cf
    w.Parent = p
    return p, w
end

local function construirSubmarino(cfSpawn)
    local A, N, M = CFG.COR_CASCO, CFG.COR_DETALHE, CFG.COR_METAL
    local CINZA = Color3.fromRGB(70, 74, 82)

    local modelo = Instance.new("Model")
    modelo.Name = "SubmarinoPanoramico"

    -- Peça-raiz invisível (é nela que a física actua)
    local raiz = Instance.new("Part")
    raiz.Name = "Raiz"
    raiz.Size = Vector3.new(4, 2, 6)
    raiz.Transparency = 1
    raiz.CanCollide, raiz.CanTouch, raiz.CanQuery = false, false, false
    raiz.CFrame = cfSpawn
    raiz.Parent = modelo
    modelo.PrimaryPart = raiz

    local refs = { spots = {}, lampadas = {}, helices = {} }

    -- 6.1 Casco duplo (dois flutuadores amarelos) + detalhes
    for _, lado in ipairs({ -1, 1 }) do
        local x = lado * 4.4
        criar(modelo, raiz, "Flutuador", Vector3.new(12, 3.8, 3.8),
            CFrame.new(x, -0.6, 0) * giraZ, A, PLAST, CIL, 0, true)
        criar(modelo, raiz, "CapaFrente", Vector3.new(3.8, 3.8, 3.8),
            CFrame.new(x, -0.6, -6), A, PLAST, ESF, 0, true)
        criar(modelo, raiz, "CapaTras", Vector3.new(3.8, 3.8, 3.8),
            CFrame.new(x, -0.6, 6), A, PLAST, ESF, 0, true)

        -- grelhas pretas no topo
        for i = 0, 5 do
            criar(modelo, raiz, "Grelha", Vector3.new(1.6, 0.12, 0.22),
                CFrame.new(x, 1.24, -3 + i * 1.2), N)
        end

        -- propulsor traseiro: carenagem + hélice (as hélices giram)
        criar(modelo, raiz, "Carenagem", Vector3.new(1.2, 2, 2),
            CFrame.new(x, -0.6, 8.5) * giraZ, N, METAL, CIL)
        local hub, w = criar(modelo, raiz, "HubHelice", Vector3.new(0.5, 0.5, 0.5),
            CFrame.new(x, -0.6, 9.35), M, METAL)
        criar(modelo, hub, "PaA", Vector3.new(1.7, 0.2, 0.08), CFrame.new(), M, METAL)
        criar(modelo, hub, "PaB", Vector3.new(0.2, 1.7, 0.08), CFrame.new(), M, METAL)
        table.insert(refs.helices, { weld = w, base = w.C0 })

        -- propulsor lateral
        criar(modelo, raiz, "PropLateral", Vector3.new(1.2, 1.3, 1.3),
            CFrame.new(lado * 6.75, -0.6, 3.5), N, METAL, CIL)

        -- holofote (peça neon + SpotLight apontado para a frente)
        local lamp = criar(modelo, raiz, "Holofote", Vector3.new(1.2, 0.8, 0.5),
            CFrame.new(x, -0.3, -7.6), Color3.fromRGB(70, 72, 78), PLAST)
        local luz = Instance.new("SpotLight")
        luz.Face = Enum.NormalId.Front
        luz.Range = 60
        luz.Brightness = 6
        luz.Angle = 75
        luz.Color = Color3.fromRGB(235, 245, 255)
        luz.Shadows = false
        luz.Enabled = false
        luz.Parent = lamp
        table.insert(refs.spots, luz)
        table.insert(refs.lampadas, lamp)
    end

    -- 6.2 Convés central e quilha
    criar(modelo, raiz, "Conves", Vector3.new(6.2, 1.6, 11), CFrame.new(0, -0.5, 0.5), A, PLAST, nil, 0, true)
    criar(modelo, raiz, "Quilha", Vector3.new(2.4, 0.5, 10), CFrame.new(0, -1.6, 0.5), M, METAL)

    -- 6.3 Cúpula de vidro esférica + anel + escotilha
    criar(modelo, raiz, "AnelCupula", Vector3.new(0.5, 6.4, 6.4),
        CFrame.new(0, 0.55, 0.5) * giraY, N, METAL, CIL)
    local vidro = criar(modelo, raiz, "Cupula", Vector3.new(7.4, 7.4, 7.4),
        CFrame.new(0, 3.6, 0.5), CFG.COR_VIDRO, Enum.Material.Glass, ESF, 0.6)
    vidro.Reflectance = 0.1
    criar(modelo, raiz, "Escotilha", Vector3.new(0.7, 2.6, 2.6),
        CFrame.new(0, 7.1, 0.5) * giraY, N, METAL, CIL)

    -- 6.4 Interior: assentos (piloto + 2 passageiros) e painel
    local function assento(nome, x, z)
        local base = criar(modelo, raiz, nome, Vector3.new(1.6, 0.5, 1.6), CFrame.new(x, 0.55, z), CINZA)
        criar(modelo, raiz, nome .. "Encosto", Vector3.new(1.6, 1.9, 0.35), CFrame.new(x, 1.65, z + 0.8), CINZA)
        return base
    end
    assento("AssentoPiloto", 0, 0.8)
    assento("AssentoPassL", -1.5, 2.0)
    assento("AssentoPassR", 1.5, 2.0)

    criar(modelo, raiz, "Painel", Vector3.new(3.2, 0.9, 0.9),
        CFrame.new(0, 1.6, -1.7) * CFrame.Angles(math.rad(-25), 0, 0), N)
    for _, x in ipairs({ -0.8, 0.8 }) do
        criar(modelo, raiz, "Tela", Vector3.new(0.9, 0.5, 0.1),
            CFrame.new(x, 1.95, -2.05), Color3.fromRGB(0, 220, 255), Enum.Material.Neon)
    end

    -- 6.5 Estrutura metálica traseira + reservatório vermelho
    for _, x in ipairs({ -1.9, 1.9 }) do
        criar(modelo, raiz, "BarraMetal", Vector3.new(0.35, 5, 0.35), CFrame.new(x, 2.8, 4.6), M, METAL)
    end
    criar(modelo, raiz, "TravessaMetal", Vector3.new(4.15, 0.35, 0.35), CFrame.new(0, 5.3, 4.6), M, METAL)
    criar(modelo, raiz, "Reservatorio", Vector3.new(1.8, 0.5, 0.5),
        CFrame.new(-2.7, 3.2, 4.6) * giraY, Color3.fromRGB(200, 30, 30), PLAST, CIL)

    -- Referência do assento do piloto
    refs.assento = modelo:FindFirstChild("AssentoPiloto")

    -- 6.6 Actuadores físicos (velocidade + estabilização)
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.zero
    bv.Velocity = Vector3.zero
    bv.P = 2000
    bv.Parent = raiz

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(5e5, 5e5, 5e5)
    bg.P = 8000
    bg.D = 900
    bg.CFrame = cfSpawn.Rotation
    bg.Parent = raiz

    modelo.Parent = Workspace
    return modelo, raiz, refs, bv, bg
end

----------------------------------------------------------------------
-- 7. HUD DE TELEMETRIA + BOTÕES TÁCTEIS
----------------------------------------------------------------------
local CIANO = Color3.fromRGB(0, 210, 255)

local function novo(classe, props, pai)
    local o = Instance.new(classe)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = pai
    return o
end

local function corNivel(p)
    if p > 50 then return Color3.fromRGB(0, 220, 140)
    elseif p > 25 then return Color3.fromRGB(255, 190, 0)
    else return Color3.fromRGB(255, 60, 60) end
end

local function criarHUD()
    local gui = Instance.new("ScreenGui")
    gui.Name = "SubmarinoHUD"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 50
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local okParent = pcall(function()
        gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not okParent or not gui.Parent then
        gui.Parent = Jogador:WaitForChild("PlayerGui")
    end

    local h = { gui = gui }

    -- Painel de telemetria (canto superior direito)
    local painel = novo("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.new(0, 210, 0, 136), BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(8, 16, 24), BackgroundTransparency = 0.25,
    }, gui)
    novo("UICorner", { CornerRadius = UDim.new(0, 8) }, painel)
    novo("UIStroke", { Color = CIANO, Thickness = 1.2, Transparency = 0.3,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, painel)

    novo("TextLabel", {
        Size = UDim2.new(1, -20, 0, 16), Position = UDim2.new(0, 10, 0, 4),
        BackgroundTransparency = 1, Text = "TELEMETRIA  •  SUBMERSÍVEL",
        TextColor3 = CIANO, Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, painel)

    novo("TextLabel", {
        Size = UDim2.new(0, 70, 0, 24), Position = UDim2.new(0, 10, 0, 22),
        BackgroundTransparency = 1, Text = "PROFUND.",
        TextColor3 = Color3.fromRGB(150, 200, 220), Font = Enum.Font.GothamMedium, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, painel)
    h.prof = novo("TextLabel", {
        Size = UDim2.new(0, 120, 0, 24), Position = UDim2.new(0, 80, 0, 22),
        BackgroundTransparency = 1, Text = "0.0 m",
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, painel)

    local function criarBarra(y, rotulo)
        novo("TextLabel", {
            Size = UDim2.new(0, 58, 0, 16), Position = UDim2.new(0, 10, 0, y),
            BackgroundTransparency = 1, Text = rotulo,
            TextColor3 = Color3.fromRGB(150, 200, 220), Font = Enum.Font.GothamMedium, TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, painel)
        local fundo = novo("Frame", {
            Size = UDim2.new(0, 92, 0, 10), Position = UDim2.new(0, 68, 0, y + 3),
            BackgroundColor3 = Color3.fromRGB(30, 40, 50), BorderSizePixel = 0,
        }, painel)
        novo("UICorner", { CornerRadius = UDim.new(0, 5) }, fundo)
        local fill = novo("Frame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 220, 140), BorderSizePixel = 0,
        }, fundo)
        novo("UICorner", { CornerRadius = UDim.new(0, 5) }, fill)
        local valor = novo("TextLabel", {
            Size = UDim2.new(0, 44, 0, 16), Position = UDim2.new(0, 164, 0, y),
            BackgroundTransparency = 1, Text = "100%", TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
        }, painel)
        return { fill = fill, valor = valor }
    end
    h.o2 = criarBarra(50, "OXIGÉNIO")
    h.bat = criarBarra(70, "BATERIA")
    h.lastro = criarBarra(90, "LASTRO")

    h.motor = novo("TextLabel", {
        Size = UDim2.new(0, 120, 0, 18), Position = UDim2.new(0, 10, 0, 112),
        BackgroundTransparency = 1, Text = "MOTOR: PARADO", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    }, painel)
    h.luz = novo("TextLabel", {
        Size = UDim2.new(0, 80, 0, 18), Position = UDim2.new(0, 120, 0, 112),
        BackgroundTransparency = 1, Text = "LUZES: OFF", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
    }, painel)

    -- Aviso central
    h.aviso = novo("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
        Size = UDim2.new(0, 300, 0, 26), Visible = false, BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(200, 40, 40), BackgroundTransparency = 0.15,
        Text = "", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
        TextSize = 12, TextWrapped = true,
    }, gui)
    novo("UICorner", { CornerRadius = UDim.new(0, 6) }, h.aviso)

    -- Botões
    local TAM, GAP = 54, 6
    local function cluster(ancora, pos)
        return novo("Frame", {
            AnchorPoint = ancora, Position = pos, BackgroundTransparency = 1,
            Size = UDim2.new(0, TAM * 3 + GAP * 2, 0, TAM * 2 + GAP),
        }, gui)
    end
    local function baseBotao(pai, texto, col, row)
        local b = novo("TextButton", {
            Text = texto, Font = Enum.Font.GothamBold, TextSize = 12,
            TextColor3 = Color3.new(1, 1, 1), TextWrapped = true,
            Position = UDim2.new(0, (TAM + GAP) * col, 0, (TAM + GAP) * row),
            Size = UDim2.new(0, TAM, 0, TAM), AutoButtonColor = false, BorderSizePixel = 0,
            BackgroundColor3 = Color3.fromRGB(10, 30, 45), BackgroundTransparency = 0.3,
        }, pai)
        novo("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
        novo("UIStroke", { Color = CIANO, Thickness = 1.2, Transparency = 0.4,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
        return b
    end
    local function ehToque(i)
        return i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1
    end
    -- botão que age enquanto está premido
    local function botaoSegurar(pai, texto, col, row, chave)
        local b = baseBotao(pai, texto, col, row)
        local function premir(on)
            ent[chave] = on
            b.BackgroundTransparency = on and 0.05 or 0.3
        end
        b.InputBegan:Connect(function(i) if ehToque(i) then premir(true) end end)
        b.InputEnded:Connect(function(i) if ehToque(i) then premir(false) end end)
        b.MouseLeave:Connect(function() premir(false) end)
        return b
    end
    local function botaoClique(pai, texto, col, row, fn)
        local b = baseBotao(pai, texto, col, row)
        b.Activated:Connect(fn)
        return b
    end

    local esq = cluster(Vector2.new(0, 1), UDim2.new(0, 16, 1, -16))
    botaoSegurar(esq, "▲\nFRENTE", 1, 0, "frente")
    botaoSegurar(esq, "◄", 0, 1, "esq")
    botaoSegurar(esq, "▼\nRÉ", 1, 1, "tras")
    botaoSegurar(esq, "►", 2, 1, "dir")

    local dir = cluster(Vector2.new(1, 1), UDim2.new(1, -16, 1, -16))
    botaoSegurar(dir, "SUBIR", 0, 0, "subir")
    botaoSegurar(dir, "DESCER", 0, 1, "descer")
    botaoSegurar(dir, "NARIZ ▲", 1, 0, "narizCima")
    botaoSegurar(dir, "NARIZ ▼", 1, 1, "narizBaixo")
    h.dir = dir
    h.fnLuz = function() end
    h.botLuz = botaoClique(dir, "LUZ", 2, 0, function() h.fnLuz() end)
    h.botEmbarque = botaoClique(dir, "SAIR", 2, 1, function() h.fnEmbarque() end)

    -- Botão "trazer submarino" (abaixo do painel)
    h.botTrazer = novo("TextButton", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 152),
        Size = UDim2.new(0, 110, 0, 24), Text = "TRAZER SUB", AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(10, 30, 45), BackgroundTransparency = 0.3,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 11, BorderSizePixel = 0,
    }, gui)
    novo("UICorner", { CornerRadius = UDim.new(0, 8) }, h.botTrazer)
    novo("UIStroke", { Color = CIANO, Thickness = 1, Transparency = 0.4,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, h.botTrazer)

    return h
end

local function ajustarBarra(b, pct, corFixa)
    pct = math.clamp(pct, 0, 100)
    b.fill.Size = UDim2.new(pct / 100, 0, 1, 0)
    b.fill.BackgroundColor3 = corFixa or corNivel(pct)
    b.valor.Text = string.format("%d%%", math.floor(pct + 0.5))
end

----------------------------------------------------------------------
-- 8. LUZES, EMBARQUE E CONTROLOS DO JOGADOR
----------------------------------------------------------------------
local function definirLuzes(on)
    if on and S.bateria <= 0 then on = false end
    S.luzes = on
    for _, s in ipairs(Refs.spots) do s.Enabled = on end
    for _, l in ipairs(Refs.lampadas) do
        if on then
            l.Material = Enum.Material.Neon
            l.Color = Color3.fromRGB(255, 250, 225)
        else
            l.Material = PLAST
            l.Color = Color3.fromRGB(70, 72, 78)
        end
    end
end

-- Liga/desliga os controlos padrão do Roblox (thumbstick, salto, WASD)
local function controlesJogador(ativar)
    pcall(function()
        local pm = Jogador:FindFirstChild("PlayerScripts"):FindFirstChild("PlayerModule")
        local c = require(pm):GetControls()
        if ativar then c:Enable() else c:Disable() end
    end)
end

local function frenteDoJogador()
    local char = Jogador.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local look = hrp.CFrame.LookVector
    local plano = Vector3.new(look.X, 0, look.Z)
    if plano.Magnitude < 0.01 then plano = Vector3.new(0, 0, -1) end
    plano = plano.Unit
    return hrp, plano, math.atan2(-plano.X, -plano.Z)
end

local function embarcar()
    if S.piloto then return end
    local char = Jogador.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end
    if (hrp.Position - Raiz.Position).Magnitude > CFG.DIST_EMBARQUE then
        avisar("Aproxima-te do submarino para entrar.")
        return
    end
    controlesJogador(false)
    local assentoCF = CFrame.new(0, CFG.ALTURA_PILOTO, 0.85)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = Raiz.CFrame * assentoCF
    weldPiloto = Instance.new("Weld")
    weldPiloto.Name = "SoldaPiloto"
    weldPiloto.Part0, weldPiloto.Part1, weldPiloto.C0 = Raiz, hrp, assentoCF
    weldPiloto.Parent = hrp
    hum.Sit = true
    humPiloto = hum
    S.piloto = true
    atualizarBotaoEmbarque()
end

local function desembarcar()
    if not S.piloto then return end
    S.piloto = false
    for k in pairs(ent) do ent[k] = false end
    if weldPiloto then weldPiloto:Destroy() weldPiloto = nil end
    local char = Jogador.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = Raiz.CFrame * CFrame.new(0, 9.5, 2)
    end
    if humPiloto then humPiloto.Sit = false humPiloto = nil end
    controlesJogador(true)
    atualizarBotaoEmbarque()
end

atualizarBotaoEmbarque = function()
    if hud and hud.botEmbarque then
        hud.botEmbarque.Text = S.piloto and "SAIR" or "ENTRAR"
    end
end

local function alternarEmbarque()
    if S.piloto then desembarcar() else embarcar() end
end

-- Traz o submarino para a frente do jogador (útil para o pôr junto à água)
local function trazerSubmarino()
    if S.piloto then desembarcar() end
    local hrp, plano, yaw = frenteDoJogador()
    if not hrp then return end
    S.yaw, S.pitch, S.vel, S.lastro = yaw, 0, 0, 0.5
    Modelo:PivotTo(CFrame.new(hrp.Position + plano * 22 + Vector3.new(0, 5, 0)) * CFrame.Angles(0, yaw, 0))
    Raiz.AssemblyLinearVelocity = Vector3.zero
    Raiz.AssemblyAngularVelocity = Vector3.zero
end

----------------------------------------------------------------------
-- 9. FÍSICA: LASTRO, NAVEGAÇÃO 3D E ESTABILIZAÇÃO (cada frame)
----------------------------------------------------------------------
local tAgua, tHUD, angHelice = 0, 0, 0

local function passo(dt)
    dt = math.min(dt, 0.1)
    local pos = Raiz.Position

    -- 9.1 Água (5x por segundo é suficiente)
    tAgua += dt
    if tAgua >= 0.2 then
        tAgua = 0
        detectarAgua(pos)
    end
    S.profundidade = (S.emAgua and S.superficieY)
        and math.max(0, S.superficieY - pos.Y) or 0

    -- 9.2 Entradas (só com o piloto a bordo; sem bateria = sem motores)
    local ativo = S.piloto
    local semEnergia = S.bateria <= 0
    local acel, guin, nariz = 0, 0, 0
    if ativo and not semEnergia then
        acel  = (ent.frente and 1 or 0) - (ent.tras and 1 or 0)
        guin  = (ent.esq and 1 or 0) - (ent.dir and 1 or 0)
        nariz = (ent.narizCima and 1 or 0) - (ent.narizBaixo and 1 or 0)
    end
    local lastIn = ativo and ((ent.descer and 1 or 0) - (ent.subir and 1 or 0)) or 0

    -- 9.3 LASTRO: 0 = tanques vazios (sobe) | 1 = cheios (desce)
    if S.emergencia then
        S.lastro = math.max(0, S.lastro - CFG.LASTRO_VEL * 2 * dt)  -- sopra lastro
    elseif lastIn ~= 0 then
        S.lastro = math.clamp(S.lastro + lastIn * CFG.LASTRO_VEL * dt, 0, 1)
    elseif CFG.LASTRO_RETORNO > 0 then
        -- sem comando: volta ao neutro = mantém a profundidade
        S.lastro += (0.5 - S.lastro) * math.min(1, dt * CFG.LASTRO_RETORNO)
    end
    local vy = (0.5 - S.lastro) * 2 * CFG.VEL_VERTICAL

    -- 9.4 Direção: guinada livre, nariz limitado e auto-nivelado
    S.yaw += guin * CFG.VEL_GUINADA * dt
    if nariz ~= 0 then
        S.pitch = math.clamp(S.pitch + nariz * CFG.VEL_NARIZ * dt, -CFG.NARIZ_MAX, CFG.NARIZ_MAX)
    else
        S.pitch += (0 - S.pitch) * math.min(1, dt * CFG.NIVELAR)
    end
    -- Roll fixo em 0 = nunca capota (estabilização automática)
    local orient = CFrame.Angles(0, S.yaw, 0) * CFrame.Angles(S.pitch, 0, 0)

    -- 9.5 Velocidade suavizada ao longo do eixo do nariz (navegação 3D)
    local alvoVel = (acel > 0 and CFG.VEL_MAX) or (acel < 0 and -CFG.VEL_MAX * 0.5) or 0
    S.vel += (alvoVel - S.vel) * (1 - math.exp(-dt * CFG.ACELERACAO))
    local vel = orient.LookVector * S.vel + Vector3.new(0, vy, 0)

    -- não deixa o submarino sair da água pela superfície
    if S.superficieY and pos.Y >= S.superficieY - 1.2 and vel.Y > 0 then
        vel = Vector3.new(vel.X, 0, vel.Z)
    end

    -- 9.6 Aplicar: dentro de água controla-se a velocidade; fora, cai
    BG.CFrame = orient
    if S.emAgua then
        BV.MaxForce = Vector3.new(1e7, 1e7, 1e7)
        BV.Velocity = vel
    else
        BV.MaxForce = Vector3.zero
    end

    -- 9.7 Hélices a girar (visual)
    local giro = math.abs(S.vel) / CFG.VEL_MAX
    if giro > 0.01 then
        angHelice = (angHelice + dt * (2 + 28 * giro) * (S.vel >= 0 and 1 or -1)) % (math.pi * 2)
        for _, h in ipairs(Refs.helices) do
            h.weld.C0 = h.base * CFrame.Angles(0, 0, angHelice)
        end
    end

    -- 9.8 HUD e consumo: ~8x por segundo (poupa CPU no mobile)
    tHUD += dt
    if tHUD < 0.12 then return end
    local dtH = tHUD
    tHUD = 0

    local profM = S.profundidade * CFG.STUD_METRO
    local noSup = (not S.emAgua) or S.profundidade <= CFG.LIMITE_SUPERFICIE

    if S.piloto then
        -- Oxigénio
        if noSup then
            S.oxigenio = math.min(100, S.oxigenio + CFG.O2_RECARGA * dtH)
            if S.emergencia and S.oxigenio >= 25 then S.emergencia = false end
        else
            S.oxigenio = math.max(0, S.oxigenio - (100 / CFG.O2_DURACAO) * (1 + profM / 100) * dtH)
            if S.oxigenio <= 0 then S.emergencia = true end
        end
        -- Bateria
        if noSup and CFG.BAT_RECARGA > 0 then
            S.bateria = math.min(100, S.bateria + CFG.BAT_RECARGA * dtH)
        else
            local uso = 0.25 + 0.75 * math.abs(S.vel) / CFG.VEL_MAX + (S.luzes and 0.5 or 0)
            S.bateria = math.max(0, S.bateria - (100 / CFG.BAT_DURACAO) * uso * dtH)
        end
        if S.bateria <= 0 and S.luzes then definirLuzes(false) end
        -- Mantém o boneco sentado
        if humPiloto and not humPiloto.Sit then humPiloto.Sit = true end
    end

    -- Escuridão com a profundidade
    local alvoEscuro = (CFG.ESCURIDAO and S.piloto and S.emAgua)
        and math.clamp(profM / CFG.PROF_ESCURA, 0, 1) or 0
    Efeito.Brightness += (-0.3 * alvoEscuro - Efeito.Brightness) * 0.35
    Efeito.Contrast += (0.1 * alvoEscuro - Efeito.Contrast) * 0.35
    Efeito.TintColor = Color3.new(1 - 0.35 * alvoEscuro, 1 - 0.12 * alvoEscuro, 1)
    Efeito.Enabled = alvoEscuro > 0.01 or Efeito.Brightness < -0.01

    -- Painel
    hud.prof.Text = string.format("%.1f m", profM)
    hud.prof.TextColor3 = profM > CFG.PROF_ESCURA and Color3.fromRGB(255, 90, 90) or Color3.new(1, 1, 1)
    ajustarBarra(hud.o2, S.oxigenio)
    ajustarBarra(hud.bat, S.bateria)
    ajustarBarra(hud.lastro, S.lastro * 100, CIANO)

    if S.bateria <= 0 then
        hud.motor.Text, hud.motor.TextColor3 = "MOTOR: SEM ENERGIA", Color3.fromRGB(255, 80, 80)
    elseif math.abs(S.vel) < 0.5 then
        hud.motor.Text, hud.motor.TextColor3 = "MOTOR: PARADO", Color3.fromRGB(190, 200, 210)
    else
        hud.motor.Text = string.format("MOTOR: %s %d%%", S.vel >= 0 and "AVANTE" or "RÉ",
            math.floor(math.abs(S.vel) / CFG.VEL_MAX * 100 + 0.5))
        hud.motor.TextColor3 = Color3.fromRGB(0, 220, 140)
    end
    hud.luz.Text = S.luzes and "LUZES: ON" or "LUZES: OFF"
    hud.luz.TextColor3 = S.luzes and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(190, 200, 210)

    -- Avisos (por prioridade)
    local msg, cor
    if S.emergencia then
        msg, cor = "OXIGÉNIO CRÍTICO — SUBIDA DE EMERGÊNCIA", Color3.fromRGB(200, 40, 40)
    elseif S.piloto and not S.emAgua then
        msg, cor = "FORA DA ÁGUA — leva o submarino para o mar", Color3.fromRGB(200, 130, 0)
    elseif S.piloto and S.bateria <= 0 then
        msg, cor = "BATERIA ESGOTADA — só o lastro funciona", Color3.fromRGB(200, 130, 0)
    elseif os.clock() < S.avisoAte then
        msg, cor = S.avisoTxt, Color3.fromRGB(20, 90, 140)
    end
    hud.aviso.Visible = msg ~= nil
    if msg then
        hud.aviso.Text = msg
        hud.aviso.BackgroundColor3 = cor
    end
end

----------------------------------------------------------------------
-- 10. TECLADO (PC)
----------------------------------------------------------------------
local TECLAS = {
    [Enum.KeyCode.W] = "frente", [Enum.KeyCode.Up] = "frente",
    [Enum.KeyCode.S] = "tras",   [Enum.KeyCode.Down] = "tras",
    [Enum.KeyCode.A] = "esq",    [Enum.KeyCode.Left] = "esq",
    [Enum.KeyCode.D] = "dir",    [Enum.KeyCode.Right] = "dir",
    [Enum.KeyCode.Space] = "subir",
    [Enum.KeyCode.LeftShift] = "descer", [Enum.KeyCode.LeftControl] = "descer",
    [Enum.KeyCode.Q] = "narizCima", [Enum.KeyCode.E] = "narizBaixo",
}

local function alternarLuzes()
    if S.piloto then definirLuzes(not S.luzes) end
end

----------------------------------------------------------------------
-- 11. DESTRUIÇÃO / LIMPEZA
----------------------------------------------------------------------
local function destruir()
    for _, c in ipairs(conexoes) do pcall(function() c:Disconnect() end) end
    conexoes = {}
    pcall(desembarcar)
    controlesJogador(true)
    pcall(function() Modelo:Destroy() end)
    pcall(function() hud.gui:Destroy() end)
    pcall(function() Efeito:Destroy() end)
    ENV.__SubmarinoPanoramico = nil
end

----------------------------------------------------------------------
-- 12. INICIALIZAÇÃO
----------------------------------------------------------------------
local char = Jogador.Character or Jogador.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart")
local hrp0, plano0, yaw0 = frenteDoJogador()
S.yaw = yaw0

-- Efeito de escuridão em profundidade (cliente)
Efeito = Instance.new("ColorCorrectionEffect")
Efeito.Name = "SubProfundidade"
Efeito.Enabled = false
Efeito.Parent = Lighting

-- Cria o submarino 20 studs à tua frente
local cfSpawn = CFrame.new(hrp0.Position + plano0 * 20 + Vector3.new(0, 5, 0)) * CFrame.Angles(0, yaw0, 0)
Modelo, Raiz, Refs, BV, BG = construirSubmarino(cfSpawn)

-- HUD e ligações dos botões
hud = criarHUD()
hud.fnLuz = alternarLuzes
hud.fnEmbarque = alternarEmbarque
hud.botTrazer.Activated:Connect(trazerSubmarino)

-- Entradas de teclado
conectar(UserInputService.InputBegan, function(i, gp)
    if gp then return end
    local k = TECLAS[i.KeyCode]
    if k then
        ent[k] = true
    elseif i.KeyCode == Enum.KeyCode.L then
        alternarLuzes()
    elseif i.KeyCode == Enum.KeyCode.X then
        alternarEmbarque()
    end
end)
conectar(UserInputService.InputEnded, function(i)
    local k = TECLAS[i.KeyCode]
    if k then ent[k] = false end
end)

-- Se o boneco morrer/renascer, larga o comando
conectar(Jogador.CharacterAdded, function()
    if S.piloto then
        S.piloto = false
        weldPiloto, humPiloto = nil, nil
        for k in pairs(ent) do ent[k] = false end
    end
    controlesJogador(true)
    atualizarBotaoEmbarque()
end)

-- Loop principal de física (Heartbeat)
conectar(RunService.Heartbeat, passo)

ENV.__SubmarinoPanoramico = {
    Destruir = destruir, Embarcar = embarcar, Desembarcar = desembarcar, Config = CFG,
}

-- Entra automaticamente no submarino
task.defer(function()
    task.wait(0.4)
    embarcar()
    avisar("Submarino pronto. Leva-o para a água!", 4)
end)
