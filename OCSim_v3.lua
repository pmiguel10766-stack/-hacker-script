local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local ex = (getgenv and getgenv()) or _G
if ex.OCSimStop then pcall(ex.OCSimStop) end
local TOTAL_MEM = 2097152
local T = {
	panel = Color3.fromRGB(24, 26, 38), btn = Color3.fromRGB(44, 48, 68), accent = Color3.fromRGB(88, 166, 255),
	ok = Color3.fromRGB(70, 200, 110), bad = Color3.fromRGB(225, 80, 80), text = Color3.fromRGB(235, 238, 245),
}
local function guiParent()
	local ok, h = pcall(function() return gethui() end)
	if ok and typeof(h) == "Instance" then return h end
	return player:WaitForChild("PlayerGui")
end
local old = workspace:FindFirstChild("OC_Sim") if old then old:Destroy() end
local oldg = guiParent():FindFirstChild("OC_SimGui") if oldg then oldg:Destroy() end
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function guid() return HttpService:GenerateGUID(false):lower() end
local model = mk("Model", {Name = "OC_Sim"}, workspace)
local groundY = hrp.Position.Y - 3
local lv, rv = hrp.CFrame.LookVector, hrp.CFrame.RightVector
local flat = Vector3.new(lv.X, 0, lv.Z).Unit
local rightV = Vector3.new(rv.X, 0, rv.Z).Unit
local base = Vector3.new(hrp.Position.X, groundY, hrp.Position.Z) + flat * 10
local function facing(pos) return CFrame.new(pos, Vector3.new(hrp.Position.X, pos.Y, hrp.Position.Z)) end
local function part(name, size, cf, color, mat)
	return mk("Part", {
		Name = name, Size = size, CFrame = cf, Color = color,
		Material = mat or Enum.Material.SmoothPlastic, Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
	}, model)
end
local caseCF = facing(base + rightV * 5 + Vector3.new(0, 1.5, 0))
local case = part("Case", Vector3.new(3, 3, 3), caseCF, Color3.fromRGB(30, 31, 38))
part("CaseTop", Vector3.new(3.05, 0.15, 3.05), caseCF * CFrame.new(0, 1.5, 0), Color3.fromRGB(88, 166, 255), Enum.Material.Metal)
local led = part("Led", Vector3.new(0.7, 0.3, 0.1), caseCF * CFrame.new(-0.7, 0.9, -1.52), Color3.fromRGB(40, 40, 40), Enum.Material.Neon)
for i = 0, 3 do
	part(`Vent{i}`, Vector3.new(1.6, 0.15, 0.1), caseCF * CFrame.new(0.2, 0.2 - i * 0.35, -1.52), Color3.fromRGB(5, 5, 5))
end
local cd = mk("ClickDetector", {MaxActivationDistance = 40}, case)
local deskCF = facing(base + Vector3.new(0, 0.05, 0) + rightV * 1.2)
part("Desk", Vector3.new(11, 0.2, 4.5), deskCF, Color3.fromRGB(70, 52, 40), Enum.Material.Wood)
local monPos = base - rightV * 2.5
local monCF = facing(monPos + Vector3.new(0, 3.9, 0))
part("Bezel", Vector3.new(9, 5.6, 0.5), monCF, Color3.fromRGB(22, 23, 30))
local display = part("Display", Vector3.new(8.4, 5, 0.1), monCF * CFrame.new(0, 0, -0.28), Color3.new(0, 0, 0))
part("Stand", Vector3.new(1, 1.1, 1), facing(monPos + Vector3.new(0, 0.7, 0)), Color3.fromRGB(40, 42, 52))
part("StandBase", Vector3.new(3, 0.2, 2), facing(monPos + Vector3.new(0, 0.3, 0)), Color3.fromRGB(40, 42, 52))
part("Keyboard", Vector3.new(4.2, 0.15, 1.3), facing(monPos + flat * -1 + Vector3.new(0, 0.38, 0)) , Color3.fromRGB(50, 52, 64))
local FONT, TSIZE = Enum.Font.Code, 16
local CW, CH = 9, 16
pcall(function()
	local s = TextService:GetTextSize("MMMMMMMMMM", TSIZE, FONT, Vector2.new(10000, 10000))
	CW, CH = s.X / 10, s.Y
end)
local PADX, PADY = 14, 10
local MAXW, MAXH = math.floor(592 / CW), math.floor(360 / CH)
local scr = {W = MAXW, H = MAXH, ch = {}, fg = {}, bg = {}, fgc = 0xFFFFFF, bgc = 0, on = false}
local dirty, views = {}, {}
local function resetBuf(w, h)
	scr.W, scr.H = w, h
	scr.ch, scr.fg, scr.bg = {}, {}, {}
	for i = 1, w * h do scr.ch[i], scr.fg[i], scr.bg[i] = " ", 0xFFFFFF, 0 end
	for y = 1, MAXH do dirty[y] = true end
end
resetBuf(MAXW, MAXH)
local function clampi(x) return math.floor(tonumber(x) or 0) end
local function rgb(c) return Color3.fromRGB(math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256) end
local esc = {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;"}
local function screenFrame(parent)
	local outer = mk("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(34, 36, 48), BorderSizePixel = 0}, parent)
	mk("UICorner", {CornerRadius = UDim.new(0, 26)}, outer)
	local bg = mk("Frame", {Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0}, outer)
	mk("UICorner", {CornerRadius = UDim.new(0, 18)}, bg)
	return outer, bg
end
local function buildView(bg, isActive)
	local v = {lbl = {}, bgh = {}, active = isActive}
	for y = 1, MAXH do
		local pos = UDim2.fromOffset(PADX, PADY + (y - 1) * CH)
		v.bgh[y] = mk("Frame", {BackgroundTransparency = 1, Position = pos, Size = UDim2.fromOffset(MAXW * CW, CH), ZIndex = 1}, bg)
		v.lbl[y] = mk("TextLabel", {
			BackgroundTransparency = 1, Position = pos, Size = UDim2.fromOffset(MAXW * CW + 24, CH + 2), Font = FONT, TextSize = TSIZE,
			RichText = true, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, Text = "", ZIndex = 2,
		}, bg)
	end
	table.insert(views, v)
	return v
end
local function rowData(y)
	if not scr.on or y > scr.H then return "", {} end
	local W, b0 = scr.W, (y - 1) * scr.W
	local parts, bgs, x = {}, {}, 1
	while x <= W do
		local f, b = scr.fg[b0 + x], scr.bg[b0 + x]
		local x2, buf = x, {}
		while x2 <= W and scr.fg[b0 + x2] == f and scr.bg[b0 + x2] == b do
			buf[#buf + 1] = scr.ch[b0 + x2]
			x2 += 1
		end
		if b ~= 0 then bgs[#bgs + 1] = {x, x2 - x, b} end
		local s = (table.concat(buf):gsub("[&<>\"']", esc))
		if f == 0xFFFFFF then parts[#parts + 1] = s
		else parts[#parts + 1] = string.format('<font color="#%06X">%s</font>', f, s) end
		x = x2
	end
	return table.concat(parts), bgs
end
local function flush()
	for y = 1, MAXH do
		if dirty[y] then
			dirty[y] = nil
			local text, bgs = rowData(y)
			for _, v in ipairs(views) do
				if v.active() then
					v.lbl[y].Text = text
					for _, c in ipairs(v.bgh[y]:GetChildren()) do c:Destroy() end
					for _, s in ipairs(bgs) do
						mk("Frame", {BorderSizePixel = 0, BackgroundColor3 = rgb(s[3]), Position = UDim2.fromOffset((s[1] - 1) * CW, 0), Size = UDim2.fromOffset(s[2] * CW + 0.5, CH)}, v.bgh[y])
					end
				end
			end
		end
	end
end
local function markAll() for y = 1, MAXH do dirty[y] = true end end
local function bufSet(x, y, s, vert)
	x, y = clampi(x), clampi(y)
	local W, H = scr.W, scr.H
	for c in tostring(s):gmatch(utf8.charpattern) do
		if x >= 1 and x <= W and y >= 1 and y <= H then
			local i = (y - 1) * W + x
			scr.ch[i], scr.fg[i], scr.bg[i] = c, scr.fgc, scr.bgc
			dirty[y] = true
		end
		if vert then y += 1 else x += 1 end
	end
end
local function put(x, y, s, fg, bg)
	local f, b = scr.fgc, scr.bgc
	scr.fgc, scr.bgc = fg or 0xFFFFFF, bg or 0
	bufSet(x, y, s)
	scr.fgc, scr.bgc = f, b
end
local function center(y, s, fg) put(math.floor((scr.W - #s) / 2) + 1, y, s, fg) end
local sg = mk("SurfaceGui", {Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(640, 400)}, display)
local _, worldBg = screenFrame(sg)
buildView(worldBg, function() return true end)
local gui = mk("ScreenGui", {Name = "OC_SimGui", ResetOnSpawn = false, DisplayOrder = 50}, guiParent())
local overlay = mk("Frame", {Size = UDim2.fromOffset(640, 400), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 1, Visible = false}, gui)
local ovScale = mk("UIScale", {}, overlay)
local _, ovBg = screenFrame(overlay)
buildView(ovBg, function() return overlay.Visible end)
local function styled(class, props, parent)
	local o = mk(class, props, parent)
	mk("UICorner", {CornerRadius = UDim.new(0, 8)}, o)
	return o
end
local function btn(text, parent, color)
	return styled("TextButton", {Text = text, Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, BackgroundColor3 = color or T.btn, BorderSizePixel = 0}, parent)
end
local cfgPanel = mk("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(340, 190), BackgroundColor3 = T.panel, Visible = false, ZIndex = 30, BorderSizePixel = 0}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 12)}, cfgPanel)
mk("UIStroke", {Color = T.accent, Transparency = 0.4}, cfgPanel)
mk("TextLabel", {Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "Configuracao de Tela", ZIndex = 31}, cfgPanel)
local cfgInfo = mk("TextLabel", {Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 20), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 14, TextColor3 = Color3.fromRGB(160, 165, 185), TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 31}, cfgPanel)
mk("TextLabel", {Position = UDim2.fromOffset(12, 66), Size = UDim2.new(0, 110, 0, 30), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "Resolucao max:", ZIndex = 31}, cfgPanel)
local cfgW = styled("TextBox", {Position = UDim2.fromOffset(122, 66), Size = UDim2.fromOffset(60, 30), Font = Enum.Font.Code, TextSize = 14, TextColor3 = T.text, BackgroundColor3 = Color3.fromRGB(14, 15, 22), Text = "", PlaceholderText = "W", ZIndex = 31, BorderSizePixel = 0}, cfgPanel)
local cfgX = mk("TextLabel", {Position = UDim2.fromOffset(186, 66), Size = UDim2.fromOffset(16, 30), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 14, TextColor3 = T.text, Text = "x", ZIndex = 31}, cfgPanel)
local cfgH = styled("TextBox", {Position = UDim2.fromOffset(206, 66), Size = UDim2.fromOffset(60, 30), Font = Enum.Font.Code, TextSize = 14, TextColor3 = T.text, BackgroundColor3 = Color3.fromRGB(14, 15, 22), Text = "", PlaceholderText = "H", ZIndex = 31, BorderSizePixel = 0}, cfgPanel)
local cfgApply = btn("Aplicar", cfgPanel, T.ok)
cfgApply.Position, cfgApply.Size, cfgApply.ZIndex = UDim2.fromOffset(12, 116), UDim2.fromOffset(150, 34), 31
local cfgClose = btn("Fechar", cfgPanel, T.bad)
cfgClose.Position, cfgClose.Size, cfgClose.ZIndex = UDim2.fromOffset(178, 116), UDim2.fromOffset(150, 34), 31
local cfgMsg = mk("TextLabel", {Position = UDim2.fromOffset(12, 156), Size = UDim2.new(1, -24, 0, 20), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 13, TextColor3 = T.bad, TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 31}, cfgPanel)
local function cfgRefresh()
	cfgInfo.Text = `Atual: {scr.W} x {scr.H}   |   Limite: {MAXW} x {MAXH}`
	cfgW.PlaceholderText, cfgH.PlaceholderText = tostring(scr.W), tostring(scr.H)
	cfgW.Text, cfgH.Text, cfgMsg.Text = "", "", ""
end
cfgApply.MouseButton1Click:Connect(function()
	local w, h = tonumber(cfgW.Text), tonumber(cfgH.Text)
	if not w or not h or w < 20 or h < 5 then
		cfgMsg.Text = "Use numeros: largura >= 20, altura >= 5"
		return
	end
	w, h = math.min(math.floor(w), MAXW), math.min(math.floor(h), MAXH)
	resetBuf(w, h)
	cfgRefresh()
	cfgMsg.TextColor3 = T.ok
	cfgMsg.Text = `Resolucao aplicada: {w} x {h}`
end)
cfgClose.MouseButton1Click:Connect(function() cfgPanel.Visible = false end)
local dock = mk("Frame", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(640, 92), BackgroundColor3 = T.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 14)}, dock)
mk("UIStroke", {Color = T.accent, Transparency = 0.55, Thickness = 1}, dock)
local dockScale = mk("UIScale", {}, dock)
mk("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, dock)
local row1 = mk("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1}, dock)
local box = styled("TextBox", {
	Size = UDim2.new(1, -78, 1, 0), Font = Enum.Font.Code, TextSize = 16, PlaceholderText = "digite aqui e toque Enter",
	PlaceholderColor3 = Color3.fromRGB(120, 125, 150), Text = "", TextColor3 = T.text, BackgroundColor3 = Color3.fromRGB(14, 15, 22),
	ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
}, row1)
mk("UIPadding", {PaddingLeft = UDim.new(0, 10)}, box)
local bSend = btn("Enter", row1, T.accent)
bSend.Position, bSend.Size = UDim2.new(1, -72, 0, 0), UDim2.new(0, 72, 1, 0)
local row2 = mk("Frame", {Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1}, dock)
mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, row2)
local function rb(text, order, color)
	local b = btn(text, row2, color)
	b.Size, b.LayoutOrder = UDim2.new(1 / 14, -3.6, 1, 0), order
	return b
end
local bPower, bTela, bCtrlC, bTab = rb("Power", 1, T.ok), rb("Tela", 2), rb("^C", 3), rb("Tab", 4)
local bUp, bDn, bLf, bRt = rb("↑", 5), rb("↓", 6), rb("←", 7), rb("→", 8)
local bFont = rb("Fonte", 9)
local bItem = rb("Item", 10, T.accent)
local bSize = rb("Medium", 11)
local bCal = rb("Calibrar", 12)
local bEsc = rb("Esc", 13)
local bClose = rb("X", 14, T.bad)
local editor = mk("Frame", {Size = UDim2.new(0.96, 0, 0, 300), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundColor3 = T.panel, Visible = false, ZIndex = 20, BorderSizePixel = 0}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 12)}, editor)
mk("UISizeConstraint", {MaxSize = Vector2.new(640, 300)}, editor)
mk("UIStroke", {Color = T.accent, Transparency = 0.4}, editor)
local edTitle = mk("TextLabel", {Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(8, 2), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "editor", ZIndex = 21}, editor)
local edBox = styled("TextBox", {
	Position = UDim2.fromOffset(6, 30), Size = UDim2.new(1, -12, 1, -76), MultiLine = true, ClearTextOnFocus = false, Font = Enum.Font.Code,
	TextSize = 14, TextColor3 = T.text, BackgroundColor3 = Color3.fromRGB(12, 13, 20), TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, Text = "", ZIndex = 21, BorderSizePixel = 0, TextWrapped = false,
}, editor)
local eSave = btn("Salvar", editor, T.ok)
eSave.Position, eSave.Size, eSave.ZIndex = UDim2.new(0, 6, 1, -40), UDim2.new(0, 110, 0, 34), 21
local eCancel = btn("Cancelar", editor, T.bad)
eCancel.Position, eCancel.Size, eCancel.ZIndex = UDim2.new(0, 124, 1, -40), UDim2.new(0, 110, 0, 34), 21
local M = {state = "off", sig = {}, wake = math.huge, co = nil, bootAddr = nil, t0 = os.clock(), gen = 0, menu = false, input = nil, req = nil}
local ledBase = Color3.fromRGB(40, 40, 40)
local function setLed(c) ledBase = c led.Color = c end
local function flash()
	if M.state == "running" then
		led.Color = Color3.fromRGB(255, 190, 60)
		task.delay(0.06, function() led.Color = ledBase end)
	end
end
local function pushSignal(...)
	if #M.sig < 4096 then table.insert(M.sig, table.pack(...)) end
end
local lf = loadstring
local canLoad = false
if lf then
	local ok, f = pcall(lf, "return 1")
	canLoad = ok and type(f) == "function"
end
local comps, byAddr, disks = {}, {}, {}
local CPU_MAX_COMPONENTS = 16 -- CPU Tier 3
local function addComp(ctype, methods, addr)
	if #comps >= CPU_MAX_COMPONENTS then error("limite de componentes da CPU Tier 3 (" .. CPU_MAX_COMPONENTS .. ")", 2) end
	local c = {addr = addr or guid(), type = ctype, m = methods}
	table.insert(comps, c)
	byAddr[c.addr] = c
	return c
end
local function pathParts(path)
	local p = {}
	for s in tostring(path):gmatch("[^/]+") do
		if s == ".." then table.remove(p) elseif s ~= "." then p[#p + 1] = s end
	end
	return p
end
local function newNode(t) return {t = t, c = t == "d" and {} or nil, data = t == "f" and "" or nil, mt = os.time()} end
local function fsSize(n)
	if n.t == "f" then return #n.data end
	local s = 0
	for _, v in pairs(n.c) do s += fsSize(v) end
	return s
end
local function makeFs(label, restricted)
	local fs = {label = label, root = newNode("d"), h = {}, hn = 0, restricted = restricted and true or false}
	local function at(path)
		local n = fs.root
		for _, p in ipairs(pathParts(path)) do
			if n.t ~= "d" then return nil end
			n = n.c[p]
			if not n then return nil end
		end
		return n
	end
	local function par(path)
		local ps = pathParts(path)
		local name = table.remove(ps)
		if not name then return nil end
		local n = fs.root
		for _, p in ipairs(ps) do
			n = n.c and n.c[p]
			if not n then return nil end
		end
		if n.t ~= "d" then return nil end
		return n, name
	end
	local m = {}
	m.getLabel = function() return fs.label end
	m.setLabel = function(l) fs.label = tostring(l) return fs.label end
	m.isReadOnly = function() return false end
	m.spaceUsed = function() return fsSize(fs.root) end
	m.spaceTotal = function() return 2097152 end
	m.exists = function(p) return at(p) ~= nil end
	m.isDirectory = function(p) local n = at(p) return n ~= nil and n.t == "d" end
	m.size = function(p) local n = at(p) return (n and n.t == "f") and #n.data or 0 end
	m.lastModified = function(p) local n = at(p) return n and n.mt * 1000 or 0 end
	m.list = function(p)
		local n = at(p)
		if not n or n.t ~= "d" then return nil, p end
		local r = {}
		for k, v in pairs(n.c) do r[#r + 1] = k .. (v.t == "d" and "/" or "") end
		table.sort(r)
		return r
	end
	m.makeDirectory = function(p)
		if fs.restricted then return false, "restrito: sistema nao oficial" end
		local n = fs.root
		for _, s in ipairs(pathParts(p)) do
			if not n.c[s] then n.c[s] = newNode("d") elseif n.c[s].t ~= "d" then return false end
			n = n.c[s]
		end
		return true
	end
	m.remove = function(p)
		if fs.restricted then return false, "restrito: sistema nao oficial" end
		local pr, nm = par(p)
		if pr and pr.c[nm] then pr.c[nm] = nil return true end
		return false
	end
	m.rename = function(a, b)
		if fs.restricted then return false, "restrito: sistema nao oficial" end
		local pa, na = par(a)
		local pb, nb = par(b)
		if not (pa and pb and pa.c[na]) then return false end
		local node = pa.c[na]
		pa.c[na] = nil
		pb.c[nb] = node
		return true
	end
	m.open = function(p, mode)
		mode = tostring(mode or "r"):sub(1, 1)
		if mode ~= "r" and fs.restricted then return nil, "restrito: sistema nao oficial" end
		local n = at(p)
		if mode == "r" then
			if not n or n.t ~= "f" then return nil, p end
		else
			if n and n.t == "d" then return nil, p end
			local pr, nm = par(p)
			if not pr then return nil, p end
			if mode == "w" or not n then n = newNode("f") pr.c[nm] = n end
		end
		fs.hn += 1
		fs.h[fs.hn] = {n = n, pos = (mode == "a") and #n.data or 0, w = mode ~= "r", r = mode == "r"}
		flash()
		return fs.hn
	end
	m.read = function(h, count)
		local o = fs.h[h]
		if not o or not o.r then return nil, "bad file descriptor" end
		local d = o.n.data
		if o.pos >= #d then return nil end
		local s = d:sub(o.pos + 1, (count == nil or count == math.huge) and #d or o.pos + math.floor(count))
		o.pos += #s
		return s
	end
	m.write = function(h, data)
		local o = fs.h[h]
		if not o or not o.w then return nil, "bad file descriptor" end
		data = tostring(data)
		local d = o.n.data
		if o.pos >= #d then o.n.data = d .. data
		else o.n.data = d:sub(1, o.pos) .. data .. d:sub(o.pos + #data + 1) end
		o.pos += #data
		o.n.mt = os.time()
		return true
	end
	m.seek = function(h, whence, off)
		local o = fs.h[h]
		if not o then return nil, "bad file descriptor" end
		local b = whence == "cur" and o.pos or (whence == "end" and #o.n.data or 0)
		o.pos = math.max(0, b + (off or 0))
		return o.pos
	end
	m.close = function(h) fs.h[h] = nil return true end
	return fs, m
end
local function addDisk(label, tmp, restricted)
	local fs, m = makeFs(label, restricted)
	local c = addComp("filesystem", m)
	disks[c.addr] = {fs = fs, m = m, tmp = tmp}
	return c.addr, disks[c.addr]
end
local function seed(d, path, data)
	local prev = d.fs.restricted
	d.fs.restricted = false -- so sistema (interno) pode gravar mesmo em disco restrito
	local dir = path:match("^(.*)/[^/]*$")
	if dir and dir ~= "" then d.m.makeDirectory(dir) end
	local h = d.m.open(path, "w")
	d.m.write(h, data)
	d.m.close(h)
	d.fs.restricted = prev
end
local PAL = {0xFFFFFF, 0xFFCC33, 0xCC66CC, 0x6699FF, 0xFFFF33, 0x33CC33, 0xFF6699, 0x333333, 0xCCCCCC, 0x336699, 0x9933CC, 0x333399, 0x663300, 0x336600, 0xFF3333, 0x000000}
local function col(c, pal)
	c = math.floor(tonumber(c) or 0)
	if pal then return PAL[c + 1] or 0 end
	return c % 0x1000000
end
local scrAddr
local gpuM = {
	bind = function() return true end,
	getScreen = function() return scrAddr end,
	getBackground = function() return scr.bgc, false end,
	setBackground = function(c, p) local o = scr.bgc scr.bgc = col(c, p) return o, nil end,
	getForeground = function() return scr.fgc, false end,
	setForeground = function(c, p) local o = scr.fgc scr.fgc = col(c, p) return o, nil end,
	getDepth = function() return 8 end,
	setDepth = function() return 8 end,
	maxDepth = function() return 8 end,
	getResolution = function() return scr.W, scr.H end,
	getViewport = function() return scr.W, scr.H end,
	maxResolution = function() return MAXW, MAXH end,
	setResolution = function(w, h)
		w, h = clampi(w), clampi(h)
		if w < 1 or h < 1 or w > MAXW or h > MAXH then error("unsupported resolution", 2) end
		if w == scr.W and h == scr.H then return false end
		resetBuf(w, h)
		return true
	end,
	set = function(x, y, s, v) bufSet(x, y, s, v) return true end,
	get = function(x, y)
		x, y = clampi(x), clampi(y)
		if x < 1 or y < 1 or x > scr.W or y > scr.H then return nil, "index out of bounds" end
		local i = (y - 1) * scr.W + x
		return scr.ch[i], scr.fg[i], scr.bg[i]
	end,
	fill = function(x, y, w, h, c)
		x, y, w, h = clampi(x), clampi(y), clampi(w), clampi(h)
		c = tostring(c):match(utf8.charpattern) or " "
		for j = math.max(1, y), math.min(scr.H, y + h - 1) do
			for i = math.max(1, x), math.min(scr.W, x + w - 1) do
				local k = (j - 1) * scr.W + i
				scr.ch[k], scr.fg[k], scr.bg[k] = c, scr.fgc, scr.bgc
			end
			dirty[j] = true
		end
		return true
	end,
	copy = function(x, y, w, h, tx, ty)
		x, y, w, h, tx, ty = clampi(x), clampi(y), clampi(w), clampi(h), clampi(tx), clampi(ty)
		local W, H = scr.W, scr.H
		local j0, j1, js = 0, h - 1, 1
		if ty > 0 then j0, j1, js = h - 1, 0, -1 end
		local i0, i1, is = 0, w - 1, 1
		if tx > 0 then i0, i1, is = w - 1, 0, -1 end
		for j = j0, j1, js do
			for i = i0, i1, is do
				local sx, sy, dx, dy = x + i, y + j, x + i + tx, y + j + ty
				if sx >= 1 and sx <= W and sy >= 1 and sy <= H and dx >= 1 and dx <= W and dy >= 1 and dy <= H then
					local a, b = (sy - 1) * W + sx, (dy - 1) * W + dx
					scr.ch[b], scr.fg[b], scr.bg[b] = scr.ch[a], scr.fg[a], scr.bg[a]
					dirty[dy] = true
				end
			end
		end
		return true
	end,
	getPaletteColor = function(i) return PAL[clampi(i) + 1] end,
	setPaletteColor = function(i, v) local o = PAL[clampi(i) + 1] PAL[clampi(i) + 1] = col(v) return o end,
	totalMemory = function() return 8000 end,
	freeMemory = function() return 8000 end,
	getActiveBuffer = function() return 0 end,
	buffers = function() return {} end,
}
local CATALOG = {
	{"Gabinete de computador", "computer", "Liga o computador e guarda as pecas. Ja existe no simulador."},
	{"Tela", "screen", "Mostra texto, controlada por uma GPU. Ja instalada."},
	{"Placa de video (GPU)", "gpu", "Desenha texto e cores na tela. Ja instalada."},
	{"Teclado", "keyboard", "Envia teclas para a tela. Ja instalado."},
	{"Disco rigido (HDD) com init.lua", "filesystem", "Cria um disco novo com /init.lua. Aparece no BIOS para bootar."},
	{"Placa de internet", "internet", "Faz requisicoes HTTP. Ja instalada."},
	{"Editor de texto", "roblox_editor", "Abre o editor do Roblox com o comando edit. Ja instalado."},
	{"Geolyzer", "geolyzer", "Escaneia a dureza dos blocos. Ainda nao emulado."},
	{"Redstone I/O", "redstone", "Le e emite sinais de redstone. Ainda nao emulado."},
	{"Verificador de codigo (scan)", "antivirus", "Aponta padroes suspeitos em arquivos. Comando scan. Ja instalado."},
	{"Gravador (pasta Delta)", "workspace", "Salva arquivos em Delta/Workspace/OpenComputers. Comando save. Ja instalado."},
	{"Relogio (Timer)", "timer", "Conta tempo para os programas. Ainda nao emulado."},
	{"Bateria (Capacitor)", "capacitor", "Guarda energia para o computador. Ainda nao emulada."},
	{"Gerador de energia", "generator", "Gera energia para os blocos. Ainda nao emulado."},
	{"Impressora 3D", "printer3d", "Imprime blocos com cores. Ainda nao emulada."},
	{"Robo", "robot", "Robo que se move e age no mundo. Ainda nao emulado."},
	{"Rack de Servidores", "rack", "Comporta ate 4 servidores. Ainda nao emulado."},
	{"Projetor de hologramas", "hologram", "Projeta hologramas 48x32x48. Ainda nao emulado."},
	{"Conversor de energia", "powerconverter", "Converte energia de outros mods. Ainda nao emulado."},
	{"Distribuidor de energia", "powerdistributor", "Separa redes de energia. Ainda nao emulado."},
	{"Alternar (Switch)", "switch", "Liga redes diferentes so com mensagens. Ainda nao emulado."},
	{"Ponto de acesso", "accesspoint", "Rede sem fio. Ainda nao emulado."},
	{"Cabo", "cable", "Liga blocos de forma barata. Ainda nao emulado."},
	{"Unidade de disco (floppy)", "disk_drive", "Le e grava disquetes. Toque para instalar."},
	{"Desmontador", "disassembler", "Desmonta itens e blocos. Ainda nao emulado."},
	{"Adaptador", "adapter", "Muda o LED e mostra texto no gabinete. Toque para instalar."},
	{"Montador de robos", "assembler", "Monta robos a partir das pecas. Ainda nao emulado."},
	{"Carregador", "charger", "Carrega a energia dos robos. Ainda nao emulado."},
	{"Disquete (floppy)", "floppy", "Toque para criar um disquete e colocar na unidade."},
}
local selectedItem = nil
local diskCount = 2
local userDisks = {} -- HDDs criados pelo Item (os nativos nao podem ser excluidos)
local itemPanel = mk("Frame", {
	Size = UDim2.new(0.96, 0, 0, 300), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	BackgroundColor3 = T.panel, Visible = false, ZIndex = 30, BorderSizePixel = 0,
}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 12)}, itemPanel)
mk("UISizeConstraint", {MaxSize = Vector2.new(640, 300)}, itemPanel)
mk("TextLabel", {
	Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(8, 2), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Itens do OpenComputers", ZIndex = 31,
}, itemPanel)
local itemScroll = mk("ScrollingFrame", {
	Position = UDim2.fromOffset(6, 30), Size = UDim2.new(1, -12, 1, -72), BackgroundColor3 = Color3.fromRGB(12, 13, 20),
	BorderSizePixel = 0, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6, ZIndex = 31,
}, itemPanel)
mk("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, itemScroll)
mk("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4)}, itemScroll)
local itemInfo = mk("TextLabel", {
	Position = UDim2.new(0, 8, 1, -38), Size = UDim2.new(1, -150, 0, 30), BackgroundTransparency = 1,
	Font = Enum.Font.Code, TextSize = 13, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Text = "Toque num bloco para selecionar.", ZIndex = 31,
}, itemPanel)
local itemWorld = styled("TextButton", {
	Position = UDim2.new(1, -140, 1, -36), Size = UDim2.new(0, 70, 0, 30), Text = "No mundo",
	Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, BackgroundColor3 = T.accent, BorderSizePixel = 0, ZIndex = 31,
}, itemPanel)
local itemClose = styled("TextButton", {
	Position = UDim2.new(1, -66, 1, -36), Size = UDim2.new(0, 60, 0, 30), Text = "Fechar",
	Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, BackgroundColor3 = T.bad, BorderSizePixel = 0, ZIndex = 31,
}, itemPanel)
local function isPresent(ctype)
	for _, c in ipairs(comps) do if c.type == ctype then return true end end
	return false
end
local refreshItems, hddOpen, installDrive, installAdapter, makeFloppy
refreshItems = function()
	for _, c in ipairs(itemScroll:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for i, it in ipairs(CATALOG) do
		local name, ctype, desc = it[1], it[2], it[3]
		local b = styled("TextButton", {
			Size = UDim2.new(1, 0, 0, 46), LayoutOrder = i, Text = "", BackgroundColor3 = (selectedItem == i) and T.accent or T.btn,
			BorderSizePixel = 0, ZIndex = 32, AutoButtonColor = true,
		}, itemScroll)
		mk("TextLabel", {
			Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
			Text = name .. (isPresent(ctype) and "  [instalado]" or ""), ZIndex = 33,
		}, b)
		mk("TextLabel", {
			Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 20), BackgroundTransparency = 1,
			Font = Enum.Font.Code, TextSize = 12, TextColor3 = Color3.fromRGB(150, 155, 180), TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = desc, ZIndex = 33,
		}, b)
		b.MouseButton1Click:Connect(function()
			selectedItem = i
			if ctype == "filesystem" then
				hddOpen()
			elseif ctype == "disk_drive" then
				installDrive(name)
			elseif ctype == "adapter" then
				installAdapter(name)
			elseif ctype == "floppy" then
				makeFloppy()
			elseif isPresent(ctype) then
				itemInfo.Text = name .. " ja esta instalado. Use component.list() para ver."
			else
				itemInfo.Text = name .. " ainda nao e emulado. Só aparece no mundo."
			end
			refreshItems()
		end)
	end
end
local worldN = 0
itemWorld.MouseButton1Click:Connect(function()
	if not selectedItem then itemInfo.Text = "Selecione um bloco primeiro." return end
	local it = CATALOG[selectedItem]
	worldN += 1
	local pos = display.CFrame * CFrame.new(-6 - ((worldN - 1) % 4) * 2.6, -1.5 - math.floor((worldN - 1) / 4) * 2.6, 0.5)
	local blk = part("OC_" .. it[2], Vector3.new(2, 2, 2), pos, Color3.fromRGB(88, 166, 255), Enum.Material.Metal)
	mk("BillboardGui", {Size = UDim2.fromOffset(160, 36), StudsOffset = Vector3.new(0, 2, 0), AlwaysOnTop = true}, blk)
	local bb = blk:FindFirstChildOfClass("BillboardGui")
	mk("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.3, BackgroundColor3 = Color3.new(0, 0, 0),
		Font = Enum.Font.Code, TextSize = 13, TextColor3 = T.text, Text = it[1]}, bb)
	itemInfo.Text = it[1] .. " colocado no mundo, ao lado do monitor."
end)
itemClose.MouseButton1Click:Connect(function() itemPanel.Visible = false end)
bItem.MouseButton1Click:Connect(function()
	itemPanel.Visible = not itemPanel.Visible
	if itemPanel.Visible then refreshItems() end
end)
local KBS = {}
local computerC = addComp("computer", {})
local eeprom = {data = "", label = "EEPROM (Lua BIOS)", code = "-- BIOS simulado no hospedeiro: procura /init.lua nos discos e pergunta quando ha mais de um."}
addComp("eeprom", {
	get = function() return eeprom.code end, set = function(c) eeprom.code = tostring(c) end,
	getData = function() return eeprom.data end, setData = function(d) eeprom.data = tostring(d or "") end,
	getLabel = function() return eeprom.label end, setLabel = function(l) eeprom.label = tostring(l) return eeprom.label end,
	getSize = function() return 4096 end, getDataSize = function() return 256 end,
	getChecksum = function() return "00000000" end, makeReadonly = function() return false end,
})
local diskA, dA = addDisk("OpenOS-Lite")
local diskB, dB = addDisk("MiniOS")
local gpuC = addComp("gpu", gpuM)
local scrC = addComp("screen", {
	isOn = function() return scr.on end, turnOn = function() return false, scr.on end, turnOff = function() return false, scr.on end,
	getAspectRatio = function() return 1, 1 end, getKeyboards = function() return KBS end,
	setPrecise = function() end, isPrecise = function() return false end,
	setTouchModeInverted = function() end, isTouchModeInverted = function() return false end,
})
scrAddr = scrC.addr
do
local UIS = game:GetService("UserInputService")
local function screenToCell(sx, sy)
	local cam = workspace.CurrentCamera
	local cf, sz = display.CFrame, display.Size
	local function proj(lx, ly)
		return cam:WorldToViewportPoint((cf * CFrame.new(lx, ly, 0)).Position)
	end
	local a, b = proj(sz.X / 2, 0), proj(-sz.X / 2, 0)
	local left, right = a, b
	if b.X < a.X then left, right = b, a end
	local t, u = proj(0, sz.Y / 2), proj(0, -sz.Y / 2)
	local top, bottom = t, u
	if u.Y < t.Y then top, bottom = u, t end
	local fx = (sx - left.X) / math.max(1, right.X - left.X)
	local fy = (sy - top.Y) / math.max(1, bottom.Y - top.Y)
	if fx < 0 or fx > 1 or fy < 0 or fy > 1 then return nil end
	local px, py = fx * 640, fy * 400
	local col = math.floor((px - (10 + PADX)) / CW) + 1
	local row = math.floor((py - (10 + PADY)) / CH) + 1
	if col < 1 or col > scr.W or row < 1 or row > scr.H then return nil end
	return col, row
end
local calib, calibStep, calibPts, calibSaved = nil, 0, {}, nil
local TL = {c = 3, r = 2}      -- centro do alvo vermelho (cols 2-4, linha 2)
local function brCell() return {c = scr.W - 3, r = scr.H - 1} end -- centro do alvo verde
local function saveCell(x, y)
	local i = (y - 1) * scr.W + x
	return {x = x, y = y, ch = scr.ch[i], fg = scr.fg[i], bg = scr.bg[i]}
end
local function calibDraw(on)
	M.paused = on and true or false
	if on then
		local br = brCell()
		calibSaved = {}
		for x = 2, 4 do table.insert(calibSaved, saveCell(x, TL.r)) end
		for x = br.c - 1, br.c + 1 do table.insert(calibSaved, saveCell(x, br.r)) end
		put(2, TL.r, "   ", 0xFFFFFF, 0xFF2020)
		put(br.c - 1, br.r, "   ", 0xFFFFFF, 0x20FF20)
	elseif calibSaved then
		for _, c in ipairs(calibSaved) do
			local i = (c.y - 1) * scr.W + c.x
			scr.ch[i], scr.fg[i], scr.bg[i] = c.ch, c.fg, c.bg
			dirty[c.y] = true
		end
		calibSaved = nil
	end
end
local function calibWhite()
	local cx, cy = math.floor(scr.W / 2) - 1, math.floor(scr.H / 2)
	for x = cx, cx + 2 do table.insert(calibSaved, saveCell(x, cy)) end
	put(cx, cy, "   ", 0x000000, 0xFFFFFF)
end
local function calibCell(sx, sy)
	local tl, br = calib.tl, calib.br
	local b = brCell()
	local col = math.floor(TL.c + (sx - tl.X) / math.max(1, br.X - tl.X) * (b.c - TL.c) + 0.5)
	local row = math.floor(TL.r + (sy - tl.Y) / math.max(1, br.Y - tl.Y) * (b.r - TL.r) + 0.5)
	if col < 1 or col > scr.W or row < 1 or row > scr.H then return nil end
	return col, row
end
bCal.MouseButton1Click:Connect(function()
	calib, calibStep, calibPts = nil, 1, {}
	calibDraw(true)
	bCal.Text = "toque vermelho"
end)
ex.OCSimInput = UIS.InputBegan:Connect(function(input, gp)
	if gp or M.state ~= "running" or not scr.on then return end
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then return end
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500)
	if not hit or hit.Instance ~= display then return end
	local sx, sy = input.Position.X, input.Position.Y
	if calibStep > 0 then
		if calibStep == 1 then
			calibPts.tl = Vector2.new(sx, sy)
			calibStep = 2
			bCal.Text = "toque verde"
		elseif calibStep == 2 then
			calibPts.br = Vector2.new(sx, sy)
			calib = calibPts
			calibStep = 3
			calibWhite()
			bCal.Text = "toque branco"
		else
			calibStep = 0
			calibDraw(false)
			bCal.Text = "Calibrado"
		end
		return
	end
	local col, row
	if calib then col, row = calibCell(sx, sy)
	else col, row = screenToCell(sx, sy) end
	if not col then return end
	pushSignal("touch", scrC.addr, col, row, 0, "jogador")
end)
local kbC = addComp("keyboard", {})
KBS[1] = kbC.addr
local tmpAddr = addDisk("tmpfs", true)
local httpFn
do
	local g = (getgenv and getgenv()) or _G
	httpFn = g.request or g.http_request or (g.syn and g.syn.request)
end
addComp("internet", {
	isHttpEnabled = function() return true end,
	isTcpEnabled = function() return false end,
	request = function(url, post, headers, method)
		local req = {done = false}
		task.spawn(function()
			if post or headers or (method and method ~= "GET") then
				if httpFn then
					local ok, r = pcall(httpFn, {Url = url, Method = method or (post and "POST" or "GET"), Headers = headers, Body = post})
					if ok and type(r) == "table" then req.data, req.code = r.Body, r.StatusCode else req.err = tostring(r) end
				else req.err = "request() indisponivel neste executor" end
			else
				local ok, r = pcall(function() return game:HttpGet(url) end)
				if ok and type(r) == "string" then req.data = r else req.err = "falha de rede" end
			end
			req.done = true
		end)
		local pos = 1
		return {
			finishConnect = function()
				if not req.done then return false end
				if req.err then return nil, req.err end
				return true
			end,
			response = function() return req.code or 200, "OK", {} end,
			read = function(n)
				if not req.done or req.err or not req.data or pos > #req.data then return nil end
				local e = (n == nil or n == math.huge) and #req.data or pos + math.floor(n) - 1
				local s = req.data:sub(pos, e)
				pos = e + 1
				return s
			end,
			close = function() end,
		}
	end,
})
local SAVE_DIR = "OpenComputers"
addComp("workspace", {
	write = function(name, data)
		local g = (getgenv and getgenv()) or _G
		local wf = g.writefile or writefile
		if not wf then return nil, "writefile indisponivel (use o Delta)" end
		name = tostring(name):gsub("%.%.", ""):gsub("/", "_")
		if name == "" then return nil, "nome invalido" end
		local mf = g.makefolder or makefolder
		local isf = g.isfolder or isfolder
		if mf and isf and not isf(SAVE_DIR) then mf(SAVE_DIR) end
		wf(SAVE_DIR .. "/" .. name, tostring(data or ""))
		return SAVE_DIR .. "/" .. name
	end,
	getPath = function() return SAVE_DIR end,
	read = function(name)
		local g = (getgenv and getgenv()) or _G
		local rf = g.readfile or readfile
		local isf = g.isfile or isfile
		local clean = tostring(name):gsub("%.%.", ""):gsub("/", "_")
		local path = SAVE_DIR .. "/" .. clean
		if isf and not isf(path) then return nil, "arquivo nao existe em Delta/Workspace/" .. path end
		local ok, data = pcall(rf, path)
		if not ok then return nil, tostring(data) end
		return data
	end,
	list = function()
		local g = (getgenv and getgenv()) or _G
		local lf = g.listfiles or listfiles
		if not lf then return {} end
		local ok, files = pcall(lf, SAVE_DIR)
		if not ok then return {} end
		local r = {}
		for _, f in ipairs(files) do r[#r + 1] = tostring(f):match("([^/\\]+)$") end
		return r
	end,
	read = function(name)
		local g = (getgenv and getgenv()) or _G
		local rf = g.readfile or readfile
		local isf = g.isfile or isfile
		local path = SAVE_DIR .. "/" .. tostring(name):gsub("%.%.", ""):gsub("/", "_")
		if isf and not isf(path) then return nil, "nao existe em Workspace/" .. path end
		local ok, data = pcall(rf, path)
		if not ok then return nil, tostring(data) end
		return data
	end,
})
local SUSPECT = {
	{"require com ID numerico", "require%s*%(%s*%d", true},
	{"loadstring (executa texto como codigo)", "loadstring", false},
	{"getfenv/setfenv (esconde escopo)", "getfenv", false},
	{"setfenv (esconde escopo)", "setfenv", false},
	{"HttpGet (baixa codigo da internet)", "HttpGet", false},
	{"GetAsync/PostAsync (requisicao externa)", "GetAsync", false},
	{"PostAsync (envia dados para fora)", "PostAsync", false},
	{"webhook do Discord", "discord.com/api/webhooks", false},
	{"getcookie / cookie", "cookie", false},
	{"setclipboard (copia dados)", "setclipboard", false},
	{"string.byte com muitos numeros (ofuscacao)", "string.char", false},
}
local function analyze(src)
	src = tostring(src or "")
	local hits = {}
	for _, r in ipairs(SUSPECT) do
		if string.find(src, r[2], 1, not r[3]) then hits[#hits + 1] = r[1] end
	end
	local escapes = select(2, string.gsub(src, "\\%d%d%d", ""))
	if escapes > 20 then hits[#hits + 1] = "muitas sequencias \\ddd (texto escondido, " .. escapes .. ")" end
	for line in (src .. "\n"):gmatch("(.-)\n") do
		if #line > 400 then hits[#hits + 1] = "linha muito longa (" .. #line .. " caracteres, ofuscacao?)" break end
	end
	return hits
end
addComp("antivirus", {
	analyze = function(text) return analyze(text) end,
	readws = function(name)
		local g = (getgenv and getgenv()) or _G
		local rf = g.readfile or readfile
		local isf = g.isfile or isfile
		local path = "OpenComputers/" .. tostring(name):gsub("%.%.", ""):gsub("\\", "/")
		if isf and not isf(path) then return nil, "arquivo nao existe em Workspace/" .. path end
		local ok, data = pcall(rf, path)
		if not ok then return nil, "nao foi possivel ler (" .. tostring(data) .. ")" end
		return data
	end,
})
local ed = {}
local function closeEditor(saved)
	editor.Visible = false
	if ed.path then pushSignal("editor_closed", ed.path, saved and true or false) end
	ed.path = nil
end
addComp("roblox_editor", {
	open = function(addr, path)
		local d = disks[addr]
		if not d then return nil, "disco invalido" end
		local h = d.m.open(path, "r")
		local text = ""
		if h then text = d.m.read(h, math.huge) or "" d.m.close(h) end
		ed.addr, ed.path = addr, path
		edTitle.Text = `editando  {d.fs.label}:{path}`
		edBox.Text = text
		editor.Visible = true
		return true
	end,
})
eSave.MouseButton1Click:Connect(function()
	local d = ed.addr and disks[ed.addr]
	if d and ed.path then
		local h = d.m.open(ed.path, "w")
		if h then
			d.m.write(h, edBox.Text)
			d.m.close(h)
			pushSignal("editor_saved", ed.path)
			closeEditor(true)
		else
			edTitle.Text = "erro: nao foi possivel salvar (pasta inexistente?)"
		end
	end
end)
eCancel.MouseButton1Click:Connect(function() closeEditor(false) end)
local function pullFor(co) return co end
local function makeEnv()
	local rawResume, rawYield, rawStatus, rawCreate = coroutine.resume, coroutine.yield, coroutine.status, coroutine.create
	local SYS = {}
	local env = {}
	local function gresume(co, ...)
		local r = table.pack(rawResume(co, ...))
		while r[1] and r[2] == SYS and rawStatus(co) == "suspended" do
			r = table.pack(rawResume(co, rawYield(SYS)))
		end
		return table.unpack(r, 1, r.n)
	end
	local gco = {
		create = rawCreate, resume = gresume, yield = rawYield, status = rawStatus,
		running = coroutine.running, isyieldable = coroutine.isyieldable,
		wrap = function(f)
			local co = rawCreate(f)
			return function(...)
				local r = table.pack(gresume(co, ...))
				if not r[1] then error(r[2], 0) end
				return table.unpack(r, 2, r.n)
			end
		end,
	}
	local function chars(s) local t = {} for c in tostring(s):gmatch(utf8.charpattern) do t[#t + 1] = c end return t end
	local unicode = {
		char = function(...) local t = {} for i, c in ipairs({...}) do t[i] = utf8.char(c) end return table.concat(t) end,
		len = function(s) return utf8.len(tostring(s)) or #tostring(s) end,
		lower = string.lower, upper = string.upper,
		reverse = function(s) local t, r = chars(s), {} for i = #t, 1, -1 do r[#r + 1] = t[i] end return table.concat(r) end,
		sub = function(s, i, j)
			local t = chars(s)
			local n = #t
			i, j = i or 1, j or -1
			if i < 0 then i = n + i + 1 end
			if j < 0 then j = n + j + 1 end
			if i < 1 then i = 1 end
			if j > n then j = n end
			if i > j then return "" end
			return table.concat(t, "", i, j)
		end,
		isWide = function() return false end,
		charWidth = function() return 1 end,
		wlen = function(s) return utf8.len(tostring(s)) or #tostring(s) end,
		wtrunc = function(s, n) return table.concat(chars(s), "", 1, math.max(0, n - 1)) end,
	}
	local computer = {
		address = function() return computerC.addr end,
		tmpAddress = function() return tmpAddr end,
		freeMemory = function() return TOTAL_MEM - 180000 - fsSize(dA.fs.root) end,
		totalMemory = function() return TOTAL_MEM end,
		energy = function() return 5000 end, maxEnergy = function() return 5000 end,
		uptime = function() return os.clock() - M.t0 end,
		beep = function() end,
		pushSignal = function(...) pushSignal(...) return true end,
		pullSignal = function(timeout)
			if timeout == nil then timeout = math.huge end
			M.wake = os.clock() + math.max(0, tonumber(timeout) or 0)
			return rawYield(SYS)
		end,
		shutdown = function(reboot) M.req = reboot and "reboot" or "off" rawYield(SYS) end,
		getBootAddress = function() return M.bootAddr or eeprom.data end,
		setBootAddress = function(a) eeprom.data = tostring(a or "") return true end,
		users = function() return end, addUser = function() return true end, removeUser = function() return false end,
		getArchitecture = function() return "Lua 5.3" end,
		getArchitectures = function() return {"Lua 5.3"} end,
		setArchitecture = function() return false end,
		isRobot = function() return false end, runlevel = function() return 1 end,
		getDeviceInfo = function() return {} end,
	}
	local function proxyOf(addr)
		local c = byAddr[addr]
		if not c then return nil, "no such component" end
		local p = {address = addr, type = c.type, slot = -1}
		for k, f in pairs(c.m) do p[k] = f end
		return p
	end
	local component = {
		list = function(filter, exact)
			local i = 0
			return function()
				while true do
					i += 1
					local c = comps[i]
					if not c then return nil end
					if not filter or (exact and c.type == filter) or (not exact and c.type:find(filter, 1, true)) then return c.addr, c.type end
				end
			end
		end,
		type = function(a) local c = byAddr[a] if c then return c.type end return nil, "no such component" end,
		slot = function() return -1 end,
		proxy = proxyOf,
		invoke = function(a, m, ...)
			local c = byAddr[a]
			if not c then error("no such component", 2) end
			local f = c.m[m]
			if not f then error("no such method", 2) end
			return f(...)
		end,
		methods = function(a)
			local c = byAddr[a]
			if not c then return nil, "no such component" end
			local r = {}
			for k in pairs(c.m) do r[k] = true end
			return r
		end,
		fields = function() return {} end,
		doc = function() return nil end,
		get = function(partial, ctype)
			for _, c in ipairs(comps) do
				if (not ctype or c.type == ctype) and c.addr:sub(1, #partial) == partial then return c.addr end
			end
			return nil, "no such component"
		end,
		isAvailable = function(t) for _, c in ipairs(comps) do if c.type == t then return true end end return false end,
		getPrimary = function(t)
			for _, c in ipairs(comps) do if c.type == t then return proxyOf(c.addr) end end
			error("no primary '" .. t .. "' available", 2)
		end,
	}
	setmetatable(component, {__index = function(_, k)
		for _, c in ipairs(comps) do if c.type == k then return proxyOf(c.addr) end end
	end})
	local function load2(chunk, name, mode, e)
		if type(chunk) == "function" then
			local t = {}
			while true do local p = chunk() if not p or p == "" then break end t[#t + 1] = p end
			chunk = table.concat(t)
		end
		local f, err = loadstring(chunk, name or "=load")
		if not f then return nil, err end
		setfenv(f, e or env)
		return f
	end
	local function checkArg(n, v, ...)
		local t = type(v)
		for _, x in ipairs({...}) do if x == t or (x == "nil" and v == nil) then return true end end
		error("bad argument #" .. n .. " (" .. table.concat({...}, " or ") .. " expected, got " .. t .. ")", 3)
	end
	local hostos = {}
	for _, k in ipairs({"clock", "time", "date", "difftime"}) do hostos[k] = os[k] end
	env.assert, env.error, env.getmetatable, env.ipairs, env.next, env.pairs = assert, error, getmetatable, ipairs, next, pairs
	env.pcall, env.rawequal, env.rawget, env.rawset, env.select, env.setmetatable = pcall, rawequal, rawget, rawset, select, setmetatable
	env.tonumber, env.tostring, env.type, env.xpcall, env.rawlen = tonumber, tostring, type, xpcall, rawlen
	env.load, env.checkArg, env._VERSION = load2, checkArg, "Lua 5.3"
	env.unpack = table.unpack
	local function copyTable(t)
		local c = {}
		for k, v in pairs(t) do c[k] = v end
		return c
	end
	env.math, env.string, env.table, env.utf8 = copyTable(math), copyTable(string), copyTable(table), copyTable(utf8)
	env.bit32 = bit32 and copyTable(bit32) or nil
	env.coroutine, env.os, env.debug = gco, hostos, {traceback = debug.traceback}
	env.unicode, env.computer, env.component = unicode, computer, component
	env._G = env
	return env
end
local powerOff, bootSequence
local function crash(msg)
	M.state, M.co = "halted", nil
	resetBuf(MAXW, MAXH)
	scr.fgc, scr.bgc, scr.on = 0xFFFFFF, 0, true
	put(2, 2, "Unrecoverable error", 0xE65050)
	local y = 4
	for line in tostring(msg):gmatch("[^\n]+") do
		while #line > 0 and y < scr.H do
			put(2, y, line:sub(1, scr.W - 2), 0xFFFFFF)
			line = line:sub(scr.W - 1)
			y += 1
		end
	end
	put(2, scr.H, "Toque Power para desligar e ligar de novo.", 0x8A8FA3)
	setLed(Color3.fromRGB(255, 60, 60))
end
local function startGuest(addr)
	local d = disks[addr]
	local node = d.fs.root.c["init.lua"]
	local f, err = loadstring(node.data, "=init.lua")
	resetBuf(MAXW, MAXH)
	scr.fgc, scr.bgc = 0xFFFFFF, 0
	if not f then crash("erro de sintaxe em /init.lua:\n" .. tostring(err)) return end
	setfenv(f, makeEnv())
	M.co, M.sig, M.wake, M.bootAddr, M.t0, M.req = coroutine.create(f), {}, 0, addr, os.clock(), nil
	M.state = "running"
end
function bootSequence()
	if M.state ~= "off" then return end
	M.gen += 1
	local gen = M.gen
	M.state = "bios"
	setLed(Color3.fromRGB(255, 200, 60))
	resetBuf(MAXW, MAXH)
	scr.fgc, scr.bgc, scr.on = 0xFFFFFF, 0, true
	local row = 2
	center(row, "O P E N C O M P U T E R S   S I M", 0x58A6FF) row += 1
	center(row, string.format("BIOS 2.0  |  CPU Tier 3  |  GPU Tier 3  |  %dK RAM", math.floor(TOTAL_MEM / 1024)), 0x8A8FA3) row += 1
	center(row, string.format("Componentes: %d/%d  |  Lua 5.3 (Luau)", #comps, CPU_MAX_COMPONENTS), 0x8A8FA3) row += 1
	put(2, row, string.rep("-", scr.W - 2), 0x3A3F55) row += 2
	if not canLoad then
		put(2, row, "loadstring indisponivel. Use o Delta Executor.", 0xE65050)
		M.state = "halted"
		return
	end
	put(2, row, "Procurando /init.lua nos discos...", 0xFFFFFF) row += 1
	task.wait(0.4)
	if M.gen ~= gen then return end
	local cands = {}
	for _, c in ipairs(comps) do
		local d = disks[c.addr]
		if d and not d.tmp then
			local n = d.fs.root.c["init.lua"]
			local has = n ~= nil and n.t == "f"
			put(3, row, string.format("%s  %-12s %s", c.addr:sub(1, 8), d.fs.label, has and "[ /init.lua ]" or "[ --------- ]"), has and 0x46C86E or 0x6A6F85)
			row += 1
			if has then table.insert(cands, c.addr) end
		end
	end
	if #cands == 0 then
		put(2, row + 1, "Nenhum /init.lua encontrado. Sistema parado.", 0xE65050)
		M.state = "halted"
		return
	end
	local pick = cands[1]
	if #cands > 1 then
		local def = 1
		for i, a in ipairs(cands) do if a == eeprom.data then def = i end end
		row += 1
		put(2, row, `Achei {#cands} arquivos /init.lua. Qual iniciar?`, 0xFFCC33) row += 1
		for i, a in ipairs(cands) do
			if row >= scr.H - 3 then
				put(4, row, `... e mais {#cands - i + 1} (digite o numero)`, 0x8A8FA3)
				break
			end
			put(4, row, `[{i}] {disks[a].fs.label}  ({a:sub(1, 8)}){i == def and "   <- padrao" or ""}`, 0xFFFFFF)
			row += 1
		end
		put(2, row + 1, "Digite o numero na caixa e toque Enter.", 0x8A8FA3)
		put(2, row + 2, "Enter vazio = padrao.", 0x8A8FA3)
		M.menu, M.input = true, nil
		while M.gen == gen and M.input == nil do task.wait(0.05) end
		M.menu = false
		if M.gen ~= gen then return end
		local idx = tonumber(M.input)
		idx = idx and math.floor(idx) or def
		if not cands[idx] then idx = def end
		pick = cands[idx]
	end
	eeprom.data = pick
	put(2, scr.H - 1, `Iniciando {disks[pick].fs.label}...`, 0x46C86E)
	task.wait(0.7)
	if M.gen ~= gen then return end
	setLed(Color3.fromRGB(60, 255, 60))
	startGuest(pick)
end
function powerOff()
	M.gen += 1
	M.state, M.co, M.sig, M.menu = "off", nil, {}, false
	scr.on = false
	resetBuf(MAXW, MAXH)
	setLed(Color3.fromRGB(40, 40, 40))
end
local function step()
	if M.paused then return end
	local t0 = os.clock()
	while M.state == "running" and os.clock() - t0 < 0.007 do
		local sig
		if #M.sig > 0 then sig = table.remove(M.sig, 1)
		elseif os.clock() >= M.wake then sig = {n = 0}
		else break end
		M.wake = math.huge
		local ok, err = coroutine.resume(M.co, table.unpack(sig, 1, sig.n))
		if M.req then
			local r = M.req
			M.req = nil
			task.spawn(function()
				powerOff()
				if r == "reboot" then task.wait(0.6) bootSequence() end
			end)
			return
		end
		if not ok then crash(debug.traceback(M.co, tostring(err))) return end
		if coroutine.status(M.co) == "dead" then crash("computer halted (o /init.lua terminou)") return end
	end
end
local KEYCODE = {[" "] = 57, ["-"] = 12, ["="] = 13, ["["] = 26, ["]"] = 27, [";"] = 39, ["'"] = 40, [","] = 51, ["."] = 52, ["/"] = 53, ["\\"] = 43, ["`"] = 41}
for _, r in ipairs({{"1234567890", 2}, {"qwertyuiop", 16}, {"asdfghjkl", 30}, {"zxcvbnm", 44}}) do
	for i = 1, #r[1] do KEYCODE[r[1]:sub(i, i)] = r[2] + i - 1 end
end
local function pushKey(chr, code)
	pushSignal("key_down", kbC.addr, chr, code, "jogador")
	pushSignal("key_up", kbC.addr, chr, code, "jogador")
end
local function key(chr, code) if M.state == "running" then pushKey(chr, code) end end
local function sendText(text)
	if M.state == "bios" and M.menu then M.input = text return end
	if M.state ~= "running" then return end
	pcall(function()
		for _, cp in utf8.codes(text) do pushKey(cp, KEYCODE[utf8.char(cp):lower()] or 0) end
	end)
	pushKey(13, 28)
end
local function togglePower()
	if M.state == "off" then task.spawn(bootSequence) else powerOff() end
end
local function stopAll()
	powerOff()
	if ex.OCSimConn then ex.OCSimConn:Disconnect() ex.OCSimConn = nil end
	if ex.OCSimInput then ex.OCSimInput:Disconnect() ex.OCSimInput = nil end
	if ex.OCSimVP then ex.OCSimVP:Disconnect() ex.OCSimVP = nil end
	model:Destroy()
	gui:Destroy()
end
ex.OCSimStop = stopAll
cd.MouseClick:Connect(togglePower)
bPower.MouseButton1Click:Connect(togglePower)
local SIZE_NAMES, SIZE_FACTOR, sizeIdx = {"Small", "Medium", "Large"}, {0.5, 0.75, 1}, 2
local function updateScales()
	local vp = workspace.CurrentCamera.ViewportSize
	dockScale.Scale = math.clamp(vp.X * 0.96 / 640, 0.5, 1.4)
	local base = math.clamp(math.min(vp.X * 0.96 / 640, (vp.Y - 130) / 400), 0.2, 1.5)
	ovScale.Scale = base * SIZE_FACTOR[sizeIdx]
	bSize.Text = SIZE_NAMES[sizeIdx]
end
bSize.MouseButton1Click:Connect(function()
	sizeIdx = sizeIdx % #SIZE_NAMES + 1
	updateScales()
	markAll()
end)
updateScales()
ex.OCSimVP = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	updateScales()
	markAll()
end)
bTela.MouseButton1Click:Connect(function()
	if cfgPanel.Visible then cfgPanel.Visible = false return end
	cfgRefresh()
	cfgPanel.Visible = true
	overlay.Visible = not overlay.Visible
	if overlay.Visible then
		updateScales()
		markAll()
	end
end)
local fontOC = false
bFont.MouseButton1Click:Connect(function()
	fontOC = not fontOC
	bFont.Text = fontOC and "OC" or "RBX"
	bFont.BackgroundColor3 = fontOC and T.ok or T.btn
	for _, v in ipairs(views) do
		for _, l in ipairs(v.lbl) do
			l.Font = fontOC and Enum.Font.Arcade or FONT
		end
	end
end)
bCtrlC.MouseButton1Click:Connect(function() key(3, 46) end)
bEsc.MouseButton1Click:Connect(function() key(0, 1) end)
bTab.MouseButton1Click:Connect(function() key(9, 15) end)
bUp.MouseButton1Click:Connect(function() key(0, 200) end)
bDn.MouseButton1Click:Connect(function() key(0, 208) end)
bLf.MouseButton1Click:Connect(function() key(0, 203) end)
bRt.MouseButton1Click:Connect(function() key(0, 205) end)
bClose.MouseButton1Click:Connect(stopAll)
local function submit()
	local text = box.Text
	box.Text = ""
	sendText(text)
end
bSend.MouseButton1Click:Connect(submit)
box.FocusLost:Connect(function(enter)
	if enter then
		submit()
		task.defer(function() if box.Parent then box:CaptureFocus() end end)
	end
end)
local acc = 0
ex.OCSimConn = RunService.Heartbeat:Connect(function(dt)
	step()
	acc += dt
	if acc >= 0.05 then acc = 0 flush() end
end)
seed(dA, "/init.lua", 
[==[
-- OpenOS-Lite 2.0  (/init.lua do disco 1)
local component, computer, unicode = component, computer, unicode
local gpu = component.proxy(component.list("gpu")())
gpu.bind(component.list("screen")())
local W, H = gpu.maxResolution()
gpu.setResolution(W, H)
local COL = {fg = 0xE6E6E6, bg = 0x0B0E17, dir = 0x5AA9FF, exe = 0x50DC78, err = 0xFF6B6B, dim = 0x8A8FA3, acc = 0xFFCC33, usr = 0x50DC78, hi = 0x5AA9FF}
gpu.setBackground(COL.bg) gpu.setForeground(COL.fg)
gpu.fill(1, 1, W, H, " ")

------------------------------------------------ terminal
local cx, cy, scrolled = 1, 1, 0
local function newline()
	cx = 1
	if cy >= H then
		gpu.copy(1, 2, W, H - 1, 0, -1)
		gpu.fill(1, H, W, 1, " ")
		scrolled = scrolled + 1
	else cy = cy + 1 end
end
local function twrite(s)
	s = tostring(s):gsub("\r", ""):gsub("\t", "    ")
	local i, n = 1, #s
	while i <= n do
		local nl = s:find("\n", i, true)
		local seg = s:sub(i, (nl or n + 1) - 1)
		while #seg > 0 do
			if cx > W then newline() end
			local room = W - cx + 1
			local piece = unicode.sub(seg, 1, room)
			gpu.set(cx, cy, piece)
			cx = cx + unicode.len(piece)
			seg = unicode.sub(seg, room + 1)
		end
		if nl then newline() i = nl + 1 else break end
	end
end
local function cwrite(c, s) gpu.setForeground(c) twrite(s) gpu.setForeground(COL.fg) end
local function perr(m) cwrite(COL.err, tostring(m) .. "\n") end

local term = {}
term.write = twrite
function term.clear() gpu.fill(1, 1, W, H, " ") cx, cy = 1, 1 end
function term.getCursor() return cx, cy end
function term.setCursor(x, y) cx, cy = x, y end
function term.isAvailable() return true end
term.gpu = function() return gpu end
function term.getViewport() return W, H end

function term.read(opts)
	opts = opts or {}
	local hist = opts.history or {}
	local buf, pos, hi, lastLen = {}, 0, #hist + 1, 0
	local sx, sy = cx, cy
	local function text() return table.concat(buf) end
	local function pxy(i)
		local o = sx - 1 + i
		return o % W + 1, sy + math.floor(o / W)
	end
	local function redraw()
		cx, cy, scrolled = sx, sy, 0
		local t = text()
		twrite(t .. string.rep(" ", math.max(1, lastLen - #buf + 1)))
		sy = sy - scrolled
		lastLen = #buf
	end
	local function cursor(on)
		local x, y = pxy(pos)
		if y > H then return end
		local c = gpu.get(x, y)
		if on then gpu.setBackground(0xFFFFFF) gpu.setForeground(0x000000) end
		gpu.set(x, y, c or " ")
		gpu.setBackground(COL.bg) gpu.setForeground(COL.fg)
	end
	local function setBuf(s)
		buf = {}
		for ch in s:gmatch(utf8.charpattern) do buf[#buf + 1] = ch end
		pos = #buf
	end
	local function finish()
		local x, y = pxy(#buf)
		cx, cy = x, math.min(y, H)
		newline()
	end
	local blink = true
	while true do
		cursor(blink)
		local e, _, c, k = computer.pullSignal(0.5)
		cursor(false)
		if e == "touch" then
			-- indicador de clique: mostra a posicao no canto superior direito sem mexer no cursor
			local ox, oy = cx, cy
			gpu.setForeground(COL.acc)
			gpu.set(math.max(1, W - 15), 1, string.format("toque %3d,%-3d", c, k))
			gpu.setForeground(COL.fg)
			cx, cy = ox, oy
		elseif e == nil then blink = not blink
		else
			blink = true
			local changed = false
			if e == "key_down" then
				if k == 28 or c == 13 then
					finish()
					local s = text()
					if s ~= "" and opts.history then table.insert(opts.history, s) end
					return s
				elseif c == 3 then
					finish() cwrite(COL.dim, "^C\n")
					return nil
				elseif k == 14 then
					if pos > 0 then table.remove(buf, pos) pos = pos - 1 changed = true end
				elseif k == 211 then
					if pos < #buf then table.remove(buf, pos + 1) changed = true end
				elseif k == 203 then pos = math.max(0, pos - 1)
				elseif k == 205 then pos = math.min(#buf, pos + 1)
				elseif k == 199 then pos = 0
				elseif k == 207 then pos = #buf
				elseif k == 200 then
					if hi > 1 and #hist > 0 then hi = hi - 1 setBuf(hist[hi]) changed = true end
				elseif k == 208 then
					if hi < #hist then hi = hi + 1 setBuf(hist[hi]) changed = true
					elseif hi == #hist then hi = #hist + 1 setBuf("") changed = true end
				elseif k == 15 then
					if opts.complete then
						local r = opts.complete(text())
						if r then setBuf(r) changed = true end
					end
				elseif c and c >= 32 and c ~= 127 then
					table.insert(buf, pos + 1, utf8.char(c)) pos = pos + 1 changed = true
				end
			elseif e == "touch" then
				-- sinal: ("touch", endereco, coluna, linha, botao, jogador)
				local msg = " touch " .. tostring(c) .. "," .. tostring(k) .. " "
				local ox = math.max(1, W - unicode.len(msg) + 1)
				local ob, of = gpu.getBackground(), gpu.getForeground()
				gpu.setBackground(0x5AA9FF) gpu.setForeground(0x000000)
				gpu.set(ox, 1, msg)
				gpu.setBackground(ob) gpu.setForeground(of)
			elseif e == "clipboard" then
				local s = tostring(c or ""):match("^[^\n]*")
				for ch in s:gmatch(utf8.charpattern) do table.insert(buf, pos + 1, ch) pos = pos + 1 end
				changed = true
			end
			if changed then redraw() end
		end
	end
end

------------------------------------------------ unicode / fs
local fs = {cwd = "/home"}
local mounts = {}
function fs.canonical(p)
	local parts = {}
	for s in tostring(p):gmatch("[^/]+") do
		if s == ".." then table.remove(parts) elseif s ~= "." then parts[#parts + 1] = s end
	end
	return "/" .. table.concat(parts, "/")
end
local function abs(p)
	p = tostring(p)
	if p:sub(1, 1) ~= "/" then p = fs.cwd .. "/" .. p end
	return fs.canonical(p)
end
local function resolve(path)
	local p = abs(path)
	local best
	for _, m in ipairs(mounts) do
		if m.path == "" or p == m.path or p:sub(1, #m.path + 1) == m.path .. "/" then
			if not best or #m.path > #best.path then best = m end
		end
	end
	local rel = p:sub(#best.path + 1)
	if rel == "" then rel = "/" end
	return best.proxy, rel, p
end
local bootAddr = computer.getBootAddress()
mounts[1] = {path = "", proxy = component.proxy(bootAddr)}
mounts[2] = {path = "/tmp", proxy = component.proxy(computer.tmpAddress())}
for addr in component.list("filesystem") do
	if addr ~= bootAddr and addr ~= computer.tmpAddress() then
		mounts[#mounts + 1] = {path = "/mnt/" .. addr:sub(1, 3), proxy = component.proxy(addr)}
	end
end
local function vchildren(p)
	local r = {}
	local pre = (p == "/") and "/" or p .. "/"
	for _, m in ipairs(mounts) do
		if m.path ~= "" and m.path:sub(1, #pre) == pre then
			local nm = m.path:sub(#pre + 1):match("^[^/]+")
			if nm then r[nm] = true end
		end
	end
	return r
end
function fs.exists(p) local px, rel, a = resolve(p) return px.exists(rel) or next(vchildren(a)) ~= nil end
function fs.isDirectory(p) local px, rel, a = resolve(p) return px.isDirectory(rel) or next(vchildren(a)) ~= nil end
function fs.size(p) local px, rel = resolve(p) return px.size(rel) end
function fs.lastModified(p) local px, rel = resolve(p) return px.lastModified(rel) end
function fs.makeDirectory(p) local px, rel = resolve(p) return px.makeDirectory(rel) end
function fs.remove(p) local px, rel = resolve(p) return px.remove(rel) end
function fs.isLink() return false end
function fs.get(p) local px, rel, a = resolve(p) return px, a end
function fs.mounts() local i = 0 return function() i = i + 1 local m = mounts[i] if m then return m.proxy, m.path == "" and "/" or m.path end end end
function fs.name(p) return ((tostring(p):gsub("/+$", "")):match("([^/]*)$")) end
function fs.path(p) return tostring(p):match("^(.*/)[^/]*$") or "" end
function fs.concat(...) return fs.canonical(table.concat({...}, "/")) end
function fs.list(path)
	local px, rel, p = resolve(path)
	local names, seen = {}, {}
	local l = px.list(rel)
	if l then for _, n in ipairs(l) do names[#names + 1] = n seen[(n:gsub("/$", ""))] = true end end
	local v = vchildren(p)
	local any = l ~= nil
	for nm in pairs(v) do any = true if not seen[nm] then names[#names + 1] = nm .. "/" end end
	if not any then return nil, "not a directory" end
	table.sort(names)
	local i = 0
	return function() i = i + 1 return names[i] end
end
function fs.open(path, mode)
	mode = mode or "r"
	local px, rel = resolve(path)
	local h, e = px.open(rel, mode)
	if not h then return nil, e or path end
	local o = {}
	function o:read(n) return px.read(h, n or math.huge) end
	function o:write(d) return px.write(h, d) end
	function o:seek(w, off) return px.seek(h, w, off) end
	function o:close() return px.close(h) end
	return o
end
local function readFile(path)
	local h = fs.open(path, "r")
	if not h then return nil end
	local parts = {}
	while true do local d = h:read(math.huge) if not d then break end parts[#parts + 1] = d end
	h:close()
	return table.concat(parts)
end
local function writeFile(path, data)
	local h, e = fs.open(path, "w")
	if not h then return nil, e end
	h:write(data) h:close()
	return true
end
function fs.copy(a, b)
	local d = readFile(a)
	if not d then return nil, "origem nao existe" end
	if fs.isDirectory(b) then b = fs.concat(b, fs.name(a)) end
	return writeFile(b, d)
end
function fs.rename(a, b)
	local pa, ra = resolve(a)
	if fs.isDirectory(b) then b = fs.concat(b, fs.name(a)) end
	local pb, rb = resolve(b)
	if pa == pb then return pa.rename(ra, rb) end
	local ok = fs.copy(a, b)
	if ok then pa.remove(ra) end
	return ok
end

------------------------------------------------ event / os / io
local event, listeners = {}, {}
function event.push(...) return computer.pushSignal(...) end
function event.listen(name, cb) listeners[#listeners + 1] = {name = name, cb = cb} return true end
function event.ignore(name, cb)
	for i = #listeners, 1, -1 do
		if listeners[i].name == name and listeners[i].cb == cb then table.remove(listeners, i) return true end
	end
	return false
end
function event.pull(timeout, name)
	if type(timeout) == "string" then name, timeout = timeout, nil end
	local deadline = timeout and computer.uptime() + timeout or math.huge
	while true do
		local left = deadline - computer.uptime()
		if left < 0 then return nil end
		local sig = table.pack(computer.pullSignal(left))
		if sig.n > 0 then
			if sig[1] == "key_down" and sig[3] == 3 then error("interrupted", 0) end
			for _, l in ipairs(listeners) do
				if l.name == sig[1] then pcall(l.cb, table.unpack(sig, 1, sig.n)) end
			end
			if not name or sig[1] == name then return table.unpack(sig, 1, sig.n) end
		elseif left <= 0 then return nil end
	end
end

local hostos = os
local env = {PWD = "/home", HOME = "/home", PATH = "/bin:/usr/bin", USER = "root", SHELL = "/bin/sh"}
local os = {}
for k, v in pairs(hostos) do os[k] = v end
function os.sleep(t)
	local d = computer.uptime() + (t or 0)
	repeat event.pull(math.max(0, d - computer.uptime())) until computer.uptime() >= d
end
function os.exit(c) error({exit = true, code = c}, 0) end
function os.getenv(k) if k == nil then return env end if k == "PWD" then return fs.cwd end return env[k] end
function os.setenv(k, v) env[k] = v return v end
function os.tmpname() return "/tmp/tmp" .. math.floor(computer.uptime() * 1000) end
function os.remove(p) return fs.remove(p) end
function os.rename(a, b) return fs.rename(a, b) end
function os.execute(l) return _G.__shell and _G.__shell.execute(l) end
_G.os = os

local io = {}
local function rd(f, fmt)
	if type(fmt) == "number" then
		if f.pos > #f.data then return nil end
		local s = f.data:sub(f.pos, f.pos + fmt - 1)
		f.pos = f.pos + #s
		return s
	end
	fmt = (tostring(fmt or "l"):gsub("^%*", ""))
	if fmt == "a" then local s = f.data:sub(f.pos) f.pos = #f.data + 1 return s end
	if f.pos > #f.data then return nil end
	if fmt == "n" then
		local s, e = f.data:find("^%s*[%+%-]?%d*%.?%d+", f.pos)
		if not s then return nil end
		f.pos = e + 1
		return tonumber(f.data:sub(s, e))
	end
	local e = f.data:find("\n", f.pos, true)
	local line
	if e then line = f.data:sub(f.pos, fmt == "L" and e or e - 1) f.pos = e + 1
	else line = f.data:sub(f.pos) f.pos = #f.data + 1 end
	return line
end
local fileMT = {}
fileMT.__index = fileMT
function fileMT:read(...)
	local f = {...}
	if #f == 0 then return rd(self, "l") end
	local out = {}
	for i, fmt in ipairs(f) do out[i] = rd(self, fmt) end
	return table.unpack(out, 1, #f)
end
function fileMT:lines(fmt) return function() return rd(self, fmt or "l") end end
function fileMT:write(...)
	for _, v in ipairs({...}) do self.h:write(tostring(v)) end
	return self
end
function fileMT:seek(w, off)
	if self.h then return self.h:seek(w or "cur", off or 0) end
	local b = w == "set" and 0 or (w == "end" and #self.data or self.pos - 1)
	self.pos = math.max(1, b + (off or 0) + 1)
	return self.pos - 1
end
function fileMT:close() if self.h then self.h:close() end return true end
function fileMT:flush() return self end
function fileMT:setvbuf() return true end
function io.open(path, mode)
	mode = ((mode or "r"):gsub("b", ""))
	local m = mode:sub(1, 1)
	if m == "r" then
		local d = readFile(path)
		if not d then return nil, path .. ": No such file or directory" end
		return setmetatable({data = d, pos = 1}, fileMT)
	end
	local h, e = fs.open(path, m)
	if not h then return nil, tostring(e) end
	return setmetatable({h = h}, fileMT)
end
function io.lines(path, fmt)
	local f = io.open(path)
	if not f then error(path .. ": No such file or directory", 2) end
	return f:lines(fmt)
end
function io.write(...)
	for _, v in ipairs({...}) do twrite(tostring(v)) end
	return io.stdout
end
function io.read(fmt)
	local l = term.read({history = {}})
	if l == nil then return nil end
	fmt = tostring(fmt or "l"):gsub("^%*", "")
	if fmt == "n" then return tonumber(l) end
	if fmt == "L" then return l .. "\n" end
	return l
end
io.stdout = {write = function(self, ...) io.write(...) return self end, flush = function() end, close = function() end, setvbuf = function() end}
io.stderr = {write = function(self, ...) for _, v in ipairs({...}) do cwrite(COL.err, tostring(v)) end return self end, flush = function() end}
io.stdin = {read = function(_, f) return io.read(f) end, lines = function() return function() return io.read() end end}
_G.io = io
_G.print = function(...)
	local t = table.pack(...)
	for i = 1, t.n do t[i] = tostring(t[i]) end
	twrite(table.concat(t, "\t") .. "\n")
end

------------------------------------------------ package / require
local package = {loaded = {}, preload = {}, path = "/lib/?.lua;/usr/lib/?.lua;./?.lua"}
local function loadfile(path)
	local d = readFile(path)
	if not d then return nil, "cannot open " .. tostring(path) end
	if d:sub(1, 2) == "#!" then d = "--" .. d end
	return load(d, "=" .. abs(path), "t", _G)
end
local function require(name)
	if package.loaded[name] ~= nil then return package.loaded[name] end
	local loader = package.preload[name]
	if not loader then
		local nm = name:gsub("%.", "/")
		for pat in package.path:gmatch("[^;]+") do
			local p = pat:gsub("%?", nm)
			if fs.exists(p) and not fs.isDirectory(p) then loader = loadfile(p) break end
		end
	end
	if not loader then error("module '" .. name .. "' not found", 2) end
	local r = loader(name)
	if r == nil then r = true end
	package.loaded[name] = r
	return r
end
_G.package, _G.require, _G.loadfile = package, require, loadfile
_G.dofile = function(p, ...) local f, e = loadfile(p) if not f then error(e, 0) end return f(...) end

local serialization = {}
local function ser(v, pretty, ind)
	local t = type(v)
	if t == "string" then return string.format("%q", v)
	elseif t == "table" then
		local parts, nl = {}, pretty and "\n" or ""
		local ni = (ind or "") .. (pretty and "  " or "")
		for k, x in pairs(v) do
			local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or "[" .. ser(k) .. "]"
			parts[#parts + 1] = ni .. key .. "=" .. ser(x, pretty, ni)
		end
		return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. (pretty and (ind or "") or "") .. "}"
	end
	return tostring(v)
end
function serialization.serialize(v, pretty) return ser(v, pretty) end
function serialization.unserialize(s)
	local f = load("return " .. tostring(s), "=unserialize", "t", {})
	if not f then return nil end
	local ok, r = pcall(f)
	return ok and r or nil
end
local text = {}
function text.trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function text.split(s, sep) local r = {} for p in (tostring(s) .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do r[#r + 1] = p end return r end
local function tokenize(line)
	local t, i = {}, 1
	while i <= #line do
		local c = line:sub(i, i)
		if c:match("%s") then i = i + 1
		elseif c == '"' then
			local j = line:find('"', i + 1, true) or (#line + 1)
			t[#t + 1] = line:sub(i + 1, j - 1)
			i = j + 1
		else
			local j = line:find("%s", i) or (#line + 1)
			t[#t + 1] = line:sub(i, j - 1)
			i = j
		end
	end
	return t
end
text.tokenize = tokenize
local keyboard = {keys = {back = 14, enter = 28, tab = 15, up = 200, down = 208, left = 203, right = 205, delete = 211, home = 199, ["end"] = 207, space = 57, c = 46}}
function keyboard.isControlDown() return false end
function keyboard.isShiftDown() return false end
function keyboard.isAltDown() return false end
local internet = {}
function internet.request(url, data, headers, method)
	local ia = component.list("internet")()
	if not ia then error("sem placa de internet", 2) end
	local h, e = component.invoke(ia, "request", url, data, headers, method)
	if not h then error(e or "falha na requisicao", 2) end
	local connected = false
	return function()
		if not connected then
			while true do
				local ok, err = h.finishConnect()
				if ok then break elseif ok == nil then error(err or "conexao falhou", 0) end
				os.sleep(0.05)
			end
			connected = true
		end
		local d = h.read(math.huge)
		if d == nil then h.close() end
		return d
	end
end
function internet.isHttpEnabled() return true end
local sides = {bottom = 0, top = 1, back = 2, front = 3, right = 4, left = 5, down = 0, up = 1, north = 2, south = 3, west = 4, east = 5}
local colors = {white = 0, orange = 1, magenta = 2, lightblue = 3, yellow = 4, lime = 5, pink = 6, gray = 7, silver = 8, cyan = 9, purple = 10, blue = 11, brown = 12, green = 13, red = 14, black = 15}
for k, v in pairs({component = component, computer = computer, unicode = unicode, filesystem = fs, term = term, event = event,
	serialization = serialization, text = text, keyboard = keyboard, internet = internet, sides = sides, colors = colors, io = io, os = os}) do
	package.loaded[k] = v
end
package.loaded.fs = fs

------------------------------------------------ shell
local cmds = {}
local shell = {}
local function parseOpts(t)
	local a, o = {}, {}
	for _, x in ipairs(t) do
		if x:sub(1, 1) == "-" and #x > 1 and not tonumber(x) then
			for c in x:sub(2):gmatch(".") do o[c] = true end
		else a[#a + 1] = x end
	end
	return a, o
end
function shell.parse(...) return parseOpts({...}) end
function shell.getWorkingDirectory() return fs.cwd end
function shell.setWorkingDirectory(p)
	local a = abs(p)
	if fs.isDirectory(a) then fs.cwd = a return true end
	return nil, "not a directory"
end
function shell.resolve(p) return abs(p) end

local function findProgram(name)
	local c = {}
	if name:find("/") then c = {name, name .. ".lua"}
	else
		for _, d in ipairs({fs.cwd, "/bin", "/usr/bin"}) do c[#c + 1] = d .. "/" .. name c[#c + 1] = d .. "/" .. name .. ".lua" end
	end
	for _, p in ipairs(c) do
		if fs.exists(p) and not fs.isDirectory(p) then return abs(p) end
	end
end
function shell.execute(line)
	local args = tokenize(line)
	local name = table.remove(args, 1)
	if not name then return true end
	local ok, e = pcall(function()
		if cmds[name] then
			local a, o = parseOpts(args)
			cmds[name](a, o)
		else
			local p = findProgram(name)
			if not p then return perr(name .. ": comando nao encontrado") end
			local f, err = loadfile(p)
			if not f then return perr(err) end
			f(table.unpack(args))
		end
	end)
	if not ok then
		if type(e) == "table" and e.exit then return true end
		if tostring(e) == "interrupted" then cwrite(COL.err, "interrompido\n") else perr(e) end
		return false
	end
	return true
end
_G.__shell = shell
package.loaded.shell = shell

cmds.clear = function() term.clear() end
cmds.cls = cmds.clear
cmds.pwd = function() twrite(fs.cwd .. "\n") end
cmds.echo = function(a) twrite(table.concat(a, " ") .. "\n") end
cmds.date = function() twrite(os.date("%Y-%m-%d %H:%M:%S") .. "\n") end
cmds.uname = function() twrite("OpenOS-Lite 2.0 (OC Sim)\n") end
cmds.uptime = function() twrite(string.format("uptime: %d s\n", math.floor(computer.uptime()))) end
cmds.free = function()
	local t, f = computer.totalMemory(), computer.freeMemory()
	twrite(string.format("total %d\nusado %d\nlivre %d\n", t, t - f, f))
end
cmds.df = function()
	twrite("Disco          Usado      Total  Montado\n")
	for px, mp in fs.mounts() do
		twrite(string.format("%-12s %8d %10d  %s\n", (px.getLabel() or "?"):sub(1, 12), px.spaceUsed(), px.spaceTotal(), mp))
	end
end
cmds.components = function()
	for a, t in component.list() do
		cwrite(COL.dim, a:sub(1, 8) .. "  ") twrite(t .. "\n")
	end
end
cmds.lscomponents = cmds.components
cmds.reboot = function() computer.shutdown(true) end
cmds.shutdown = function() computer.shutdown(false) end
cmds.sleep = function(a) os.sleep(tonumber(a[1]) or 1) end
cmds.which = function(a) local p = a[1] and (cmds[a[1]] and "(interno)" or findProgram(a[1])) twrite((p or "nao encontrado") .. "\n") end
cmds.label = function(a)
	local px = fs.get("/")
	if a[1] then px.setLabel(a[1]) end
	twrite((px.getLabel() or "") .. "\n")
end
cmds.cd = function(a)
	local ok, e = shell.setWorkingDirectory(a[1] or "/home")
	if not ok then perr("cd: " .. tostring(a[1]) .. ": " .. e) end
end
cmds.ls = function(a, o)
	local p = a[1] or "."
	if not fs.exists(p) then return perr("ls: " .. p .. ": nao existe") end
	if not fs.isDirectory(p) then return twrite(p .. "\n") end
	local items = {}
	for n in fs.list(p) do items[#items + 1] = n end
	local function color(n) return n:sub(-1) == "/" and COL.dir or (n:match("%.lua$") and COL.exe or COL.fg) end
	if o.l then
		for _, n in ipairs(items) do
			local isd = n:sub(-1) == "/"
			twrite(string.format("%s %8d  ", isd and "d" or "-", isd and 0 or fs.size(fs.concat(p, n))))
			cwrite(color(n), n .. "\n")
		end
	else
		local maxw = 1
		for _, n in ipairs(items) do maxw = math.max(maxw, unicode.len(n)) end
		local colw = maxw + 2
		local per = math.max(1, math.floor(W / colw))
		local k = 0
		for _, n in ipairs(items) do
			cwrite(color(n), n .. string.rep(" ", colw - unicode.len(n)))
			k = k + 1
			if k % per == 0 then twrite("\n") end
		end
		if k % per ~= 0 then twrite("\n") end
	end
end
cmds.dir = cmds.ls
cmds.cat = function(a)
	for _, p in ipairs(a) do
		local d = readFile(p)
		if not d then perr("cat: " .. p .. ": nao existe")
		else twrite(d) if #d > 0 and d:sub(-1) ~= "\n" then twrite("\n") end end
	end
end
cmds.mkdir = function(a) for _, p in ipairs(a) do fs.makeDirectory(p) end end
cmds.touch = function(a) for _, p in ipairs(a) do if not fs.exists(p) then writeFile(p, "") end end end
cmds.rm = function(a, o)
	for _, p in ipairs(a) do
		if not fs.exists(p) then perr("rm: " .. p .. ": nao existe")
		elseif fs.isDirectory(p) and not (o.r or o.f) then perr("rm: " .. p .. ": e diretorio (use -r)")
		else
			local ok, e = fs.remove(p)
			if not ok then perr("rm: " .. p .. ": " .. tostring(e or "falhou")) end
		end
	end
end
cmds.del = cmds.rm
cmds.cp = function(a)
	if #a < 2 then return twrite("uso: cp origem destino\n") end
	local ok, e = fs.copy(a[1], a[2])
	if not ok then perr("cp: " .. tostring(e)) end
end
cmds.mv = function(a)
	if #a < 2 then return twrite("uso: mv origem destino\n") end
	if not fs.rename(a[1], a[2]) then perr("mv: falhou") end
end
cmds.wget = function(a)
	local url = a[1]
	if not url then return twrite("uso: wget url [arquivo]\n") end
	local name = a[2] or url:match("([^/]+)$") or "index"
	local t = {}
	for c in internet.request(url) do t[#t + 1] = c end
	local data = table.concat(t)
	local ok, e = writeFile(name, data)
	if not ok then return perr("wget: " .. tostring(e)) end
	twrite(string.format("salvo: %s (%d bytes)\n", name, #data))
end
cmds.edit = function(a)
	local path = a[1]
	if not path then return twrite("uso: edit arquivo\n") end
	local ed = component.list("roblox_editor")()
	if not ed then return perr("edit: sem componente roblox_editor") end
	local px, rel = resolve(path)
	local ok, e = component.invoke(ed, "open", px.address, rel)
	if not ok then return perr("edit: " .. tostring(e)) end
	cwrite(COL.dim, "Editor aberto. Toque em Salvar ou Cancelar...\n")
	event.pull(nil, "editor_closed")
end
cmds.scan = function(a)
	if not a[1] then return twrite("uso: scan arquivo.lua   ou   scan ws:NOME.lua (pasta OpenComputers do Delta)\n") end
	local av = component.list("antivirus")()
	if not av then return perr("scan: sem verificador") end
	local data
	if a[1]:sub(1, 3) == "ws:" then
		local d, e = component.invoke(av, "readws", a[1]:sub(4))
		if not d then return perr("scan: " .. tostring(e)) end
		data = d
	else
		data = readFile(a[1])
		if not data then return perr("scan: " .. a[1] .. ": nao existe") end
	end
	local hits = component.invoke(av, "analyze", data)
	if #hits == 0 then
		cwrite(COL.ok or COL.exe, "Nenhum padrao suspeito encontrado.\n")
		cwrite(COL.dim, "Isso NAO prova que o codigo e seguro. Leia antes de rodar.\n")
	else
		cwrite(COL.err, "Padroes suspeitos (" .. #hits .. "):\n")
		for _, h in ipairs(hits) do twrite("  - " .. h .. "\n") end
		cwrite(COL.dim, "Nao rode esse codigo sem entender o que ele faz.\n")
	end
end
cmds.load = function(a)
	if not a[1] then return twrite("uso: load arquivo.lua  (le de Delta/Workspace/OpenComputers)\n") end
	local ws = component.list("workspace")()
	if not ws then return perr("load: sem componente workspace") end
	local data, err = component.invoke(ws, "read", a[1])
	if not data then return perr("load: " .. tostring(err)) end
	local ok, e = writeFile(a[1], data)
	if not ok then return perr("load: " .. tostring(e)) end
	cwrite(COL.exe, "carregado: " .. a[1] .. " (" .. #data .. " bytes)\n")
end
cmds.save = function(a)
	if not a[1] then return twrite("uso: save arquivo.lua  (salva em Delta/Workspace/OpenComputers)\n") end
	local d = readFile(a[1])
	if not d then return perr("save: " .. a[1] .. ": nao existe") end
	local ws = component.list("workspace")()
	if not ws then return perr("save: sem componente workspace") end
	local path, err = component.invoke(ws, "write", fs.name(a[1]), d)
	if not path then return perr("save: " .. tostring(err)) end
	cwrite(COL.exe, "salvo: " .. path .. " (" .. #d .. " bytes)\n")
end
cmds.load = function(a)
	local ws = component.list("workspace")()
	if not ws then return perr("load: sem componente workspace") end
	if not a[1] then
		local names = component.invoke(ws, "list")
		if #names == 0 then return twrite("nenhum arquivo em Delta/Workspace/OpenComputers\n") end
		for _, n in ipairs(names) do twrite("  " .. n .. "\n") end
		return cwrite(COL.dim, "uso: load NOME  (copia para a pasta atual)\n")
	end
	local data, err = component.invoke(ws, "read", a[1])
	if not data then return perr("load: " .. tostring(err)) end
	local dest = fs.concat(fs.cwd, a[2] or fs.name(a[1]))
	local ok, e = writeFile(dest, data)
	if not ok then return perr("load: " .. tostring(e)) end
	cwrite(COL.exe, "carregado: " .. dest .. " (" .. #data .. " bytes)\n")
end
cmds.boot = function(a)
	local list = {}
	for addr in component.list("filesystem") do
		if addr ~= computer.tmpAddress() and component.invoke(addr, "exists", "/init.lua") then list[#list + 1] = addr end
	end
	if a[1] then
		local sel = list[tonumber(a[1]) or 0]
		if not sel then return perr("boot: opcao invalida") end
		computer.setBootAddress(sel)
		return cwrite(COL.exe, "padrao do BIOS alterado. Use reboot.\n")
	end
	for i, addr in ipairs(list) do
		twrite(string.format("[%d] %s  %s%s\n", i, addr:sub(1, 8), component.invoke(addr, "getLabel") or "", addr == computer.getBootAddress() and "  (atual)" or ""))
	end
	cwrite(COL.dim, "boot <n> define o padrao do BIOS\n")
end
local function resultsOut(r)
	if r.n > 1 then
		local t = {}
		for i = 2, r.n do t[#t + 1] = type(r[i]) == "table" and serialization.serialize(r[i]) or tostring(r[i]) end
		twrite(table.concat(t, "\t") .. "\n")
	end
end
cmds.lua = function(a)
	if a[1] then
		local f, e = loadfile(a[1])
		if not f then return perr(e) end
		return f(table.unpack(a, 2))
	end
	cwrite(COL.hi, "Lua 5.3 REPL ")
	cwrite(COL.dim, "(exit para sair)\n")
	local hist = {}
	while true do
		cwrite(COL.acc, "lua> ")
		local l = term.read({history = hist})
		if l ~= nil then
			if l == "exit" or l == "os.exit()" then return end
			if l ~= "" then
				local f = load("return " .. l, "=stdin", "t", _G)
				local e
				if not f then f, e = load(l, "=stdin", "t", _G) end
				if not f then perr(e)
				else
					local r = table.pack(pcall(f))
					if not r[1] then if not (type(r[2]) == "table" and r[2].exit) then perr(r[2]) end else resultsOut(r) end
				end
			end
		end
	end
end
cmds.help = function()
	local names = {}
	for k in pairs(cmds) do names[#names + 1] = k end
	table.sort(names)
	cwrite(COL.hi, "comandos: ") twrite(table.concat(names, "  ") .. "\n")
	cwrite(COL.dim, "programas .lua em /bin, /usr/bin ou na pasta atual rodam pelo nome.\n")
	cwrite(COL.dim, "require() carrega de /lib e /usr/lib. Use edit/wget para criar scripts.\n")
end

local function complete(t)
	local head, tok = t:match("^(.*%s)(%S*)$")
	local first = false
	if not head then head, tok, first = "", t, true end
	local dir, base = tok:match("^(.*/)([^/]*)$")
	if not dir then dir, base = "", tok end
	local cands = {}
	local function add(n) if n:sub(1, #base) == base then cands[#cands + 1] = n end end
	local d = dir == "" and "." or dir
	if fs.isDirectory(d) then for n in fs.list(d) do add(n) end end
	if first and dir == "" then for k in pairs(cmds) do add(k) end end
	if #cands == 0 then return nil end
	table.sort(cands)
	local pre = cands[1]
	for _, c in ipairs(cands) do while c:sub(1, #pre) ~= pre do pre = pre:sub(1, -2) end end
	if #cands == 1 and pre:sub(-1) ~= "/" then pre = pre .. " " end
	if #pre <= #base then return nil end
	return head .. dir .. pre
end

------------------------------------------------ inicio
local host = computer.address():sub(1, 3)
cwrite(COL.hi, "OpenOS-Lite 2.0") cwrite(COL.dim, "  |  OC Sim  |  Lua 5.3 (Luau)\n")
cwrite(COL.dim, string.format("RAM %dk livres  |  boot %s  |  digite 'help'\n\n", math.floor(computer.freeMemory() / 1024), bootAddr:sub(1, 8)))
local history = {}
while true do
	cwrite(COL.usr, "root@" .. host) cwrite(COL.fg, ":") cwrite(COL.dir, fs.cwd) cwrite(COL.fg, "# ")
	local line = term.read({history = history, complete = complete})
	if line and line ~= "" then shell.execute(line) end
end
]==])
seed(dA, "/home/hello.lua", 
[==[
print("Ola do OpenOS-Lite!")
local component = require("component")
local gpu = component.gpu
print("resolucao:", gpu.getResolution())
print("RAM livre:", require("computer").freeMemory())
]==])
seed(dA, "/home/cor.lua", 
[==[
local gpu = require("component").gpu
local term = require("term")
for i = 0, 7 do
	gpu.setBackground(0x202020 + i * 0x203040)
	io.write("  cor " .. i .. "  ")
end
gpu.setBackground(0x0B0E17)
print()
]==])
seed(dA, "/etc/motd", "OpenOS-Lite 2.0\n")
seed(dB, "/init.lua", 
[==[
-- MiniOS 0.2 (/init.lua do disco 2): GUI simples com area de trabalho
-- Clique (touch) ou setas + Enter abrem apps. Esc fecha a janela.
local gpu = component.proxy(component.list("gpu")())
gpu.bind(component.list("screen")())
local W, H = gpu.maxResolution()
gpu.setResolution(W, H)

local C = {bg = 0x1B1030, bar = 0x2A1B4A, txt = 0xFFFFFF, dim = 0x9A8CC8, sel = 0x7B4FD6, win = 0x33245A, ok = 0x77FFAA, err = 0xFF6B6B, title = 0xFFCC33}

local function paint(bg, fg)
	if bg then gpu.setBackground(bg) end
	if fg then gpu.setForeground(fg) end
end

local log, line = {}, ""
local function logLine(s, fg) table.insert(log, {tostring(s), fg or C.txt}) while #log > 200 do table.remove(log, 1) end end

local function evalLine(src)
	logLine("> " .. src, C.dim)
	local f, err = load("return " .. src, "=mini")
	if not f then f, err = load(src, "=mini") end
	if not f then return logLine(err, C.err) end
	local r = table.pack(pcall(f))
	if not r[1] then return logLine(r[2], C.err) end
	local parts = {}
	for i = 2, r.n do parts[#parts + 1] = tostring(r[i]) end
	if #parts > 0 then logLine(table.concat(parts, "\t"), C.ok) end
end

local apps
local view, sel = "desk", 1

local function drawWindowFrame(title)
	paint(C.bar, C.title)
	gpu.fill(1, 1, W, 1, " ")
	gpu.set(2, 1, title)
	paint(nil, C.err)
	gpu.set(W - 2, 1, "[X]")
	paint(C.bg, C.txt)
	gpu.fill(1, 2, W, H - 1, " ")
end

local function drawTerminal()
	drawWindowFrame("Terminal")
	local top = H - 2
	local rows = {}
	for i = #log, 1, -1 do
		table.insert(rows, 1, log[i])
		if #rows >= top - 2 then break end
	end
	local y = 3
	for _, r in ipairs(rows) do
		paint(nil, r[2])
		gpu.set(2, y, r[1]:sub(1, W - 2))
		y = y + 1
	end
	paint(nil, C.ok)
	gpu.fill(1, H, W, 1, " ")
	gpu.set(2, H, "> " .. line:sub(-(W - 4)))
end

local function drawUptime()
	drawWindowFrame("Uptime")
	paint(nil, C.txt)
	gpu.set(3, 4, "Tempo ligado: " .. math.floor(computer.uptime()) .. " s")
	gpu.set(3, 5, "RAM livre: " .. computer.freeMemory() .. " bytes")
	gpu.set(3, 7, "Esc ou [X] fecha")
end

local function drawAbout()
	drawWindowFrame("Sobre")
	paint(nil, C.txt)
	gpu.set(3, 4, "MiniOS 0.2 - GUI de teste")
	gpu.set(3, 5, "Rodando no OpenComputers Sim")
	gpu.set(3, 7, "Feito em Lua 5.3 (Luau)")
end


-- Snake: setas mudam a direcao, R reinicia quando perde
local snake = {}
local function snakeFree(x, y)
	for _, b in ipairs(snake.body) do if b.x == x and b.y == y then return false end end
	return true
end
local function placeFood()
	for _ = 1, 500 do
		local x, y = math.random(2, W - 1), math.random(3, H - 1)
		if snakeFree(x, y) then snake.food = {x = x, y = y} return end
	end
end
local function startSnake()
	snake = {body = {{x = 10, y = 8}, {x = 9, y = 8}, {x = 8, y = 8}}, dx = 1, dy = 0, score = 0, over = false}
	placeFood()
end
local function stepSnake()
	if snake.over or not snake.body then return end
	local h = snake.body[1]
	local nx, ny = h.x + snake.dx, h.y + snake.dy
	if nx < 2 or nx > W - 1 or ny < 3 or ny > H - 1 or not snakeFree(nx, ny) then
		snake.over = true
		return
	end
	table.insert(snake.body, 1, {x = nx, y = ny})
	if nx == snake.food.x and ny == snake.food.y then
		snake.score = snake.score + 1
		placeFood()
	else
		table.remove(snake.body)
	end
end
local function keySnake(chr, code)
	if snake.over then
		if chr == 114 or chr == 82 then startSnake() end
		return
	end
	local nd = {[200] = {0, -1}, [208] = {0, 1}, [203] = {-1, 0}, [205] = {1, 0}}
	local d = nd[code]
	if d and not (d[1] == -snake.dx and d[2] == -snake.dy) then snake.dx, snake.dy = d[1], d[2] end
end
local function drawSnake()
	drawWindowFrame("Snake  pontos: " .. (snake.score or 0))
	if not snake.body then return end
	paint(nil, C.err)
	gpu.set(snake.food.x, snake.food.y, "*")
	paint(nil, C.ok)
	for _, b in ipairs(snake.body) do gpu.set(b.x, b.y, "#") end
	if snake.over then
		paint(nil, C.err)
		gpu.set(math.max(2, math.floor(W / 2) - 10), math.floor(H / 2), "GAME OVER - R reinicia")
	end
end

apps = {
	{name = "Terminal", draw = drawTerminal, open = function() line = "" end},
	{name = "Snake", draw = drawSnake, open = startSnake, tick = stepSnake, key = keySnake},
	{name = "Uptime", draw = drawUptime},
	{name = "Sobre", draw = drawAbout},
}

local current = nil

local function drawDesk()
	paint(C.bg, C.txt)
	gpu.fill(1, 1, W, H, " ")
	for i, a in ipairs(apps) do
		local x, y = iconPos(i)
		paint(i == sel and C.sel or C.win, C.txt)
		gpu.fill(x, y, 10, 3, " ")
		gpu.set(x + 1, y + 1, a.name:sub(1, 8))
	end
	paint(C.bar, C.dim)
	gpu.fill(1, H, W, 1, " ")
	gpu.set(2, H, "MiniOS 0.2 | clique ou setas + Enter | Esc fecha app")
	paint(C.bg, C.txt)
end

function iconPos(i)
	return 4 + ((i - 1) % 4) * 16, 4 + math.floor((i - 1) / 4) * 5
end

local function redraw()
	if current then current.draw() else drawDesk() end
end

local function openApp(i)
	current = apps[i]
	if current.open then current.open() end
	redraw()
end

local function closeApp()
	current = nil
	redraw()
end

local function hitIcon(col, row)
	for i = 1, #apps do
		local x, y = iconPos(i)
		if col >= x and col < x + 10 and row >= y and row < y + 3 then return i end
	end
end

while true do
	redraw()
	local tickRate = (current and current.tick) and 0.15 or nil
	local e, _, a, b, c, d = computer.pullSignal(tickRate)
	if e == nil and current and current.tick then
		current.tick()
	elseif e == "touch" then
		local col, row = a, b
		if current then
			if row == 1 and col >= W - 3 then closeApp() end
		else
			local i = hitIcon(col, row)
			if i then sel = i openApp(i) end
		end
	elseif e == "key_down" then
		local chr, code = a, b
		if current then
			if code == 1 then closeApp()
			elseif current.key then current.key(chr, code)
			elseif current == apps[1] then
				if code == 28 then evalLine(line) line = ""
				elseif code == 14 then line = line:sub(1, -2)
				elseif chr and chr >= 32 then line = line .. utf8.char(chr) end
			end
		else
			if code == 203 then sel = math.max(1, sel - 1)
			elseif code == 205 then sel = math.min(#apps, sel + 1)
			elseif code == 200 then sel = math.max(1, sel - 4)
			elseif code == 208 then sel = math.min(#apps, sel + 4)
			elseif code == 28 then openApp(sel) end
		end
	end
end
]==])
seed(dB, "/readme.txt", "Segundo disco com outro /init.lua.\n")
local hdd = mk("Frame", {Size = UDim2.new(0.8, 0, 0, 220), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = T.panel, Visible = false, ZIndex = 40, BorderSizePixel = 0}, gui)
mk("UISizeConstraint", {MaxSize = Vector2.new(360, 220)}, hdd)
mk("UICorner", {CornerRadius = UDim.new(0, 12)}, hdd)
mk("UIStroke", {Color = T.accent, Transparency = 0.4}, hdd)
mk("TextLabel", {Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Qual sistema?", ZIndex = 41}, hdd)
local hddMsg = mk("TextLabel", {Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 0), BackgroundTransparency = 1,
	Font = Enum.Font.Code, TextSize = 13, TextColor3 = Color3.fromRGB(200, 205, 220), TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "", ZIndex = 41}, hdd)
hddMsg.Size = UDim2.new(1, -24, 0, 60)
local function hddClose() hdd.Visible = false end
local function hddCreate(label, initSrc, restricted)
	if #comps >= CPU_MAX_COMPONENTS then
		hddClose()
		itemInfo.Text = "Limite de componentes da CPU Tier 3 (" .. CPU_MAX_COMPONENTS .. "). Nao da para adicionar outro disco."
		return
	end
	diskCount += 1
	local addr = addDisk((restricted and "RESTRITO" or "HDD") .. diskCount, false, restricted)
	table.insert(userDisks, addr)
	seed(disks[addr], "/readme.txt", "Disco criado pelo Item (" .. label .. ").\n")
	seed(disks[addr], "/init.lua", initSrc)
	hddClose()
	itemInfo.Text = label .. " criado (" .. addr:sub(1, 8) .. "). Reinicie para escolher no BIOS."
end
local function initOf(addr) return disks[addr] and disks[addr].fs.root.c["init.lua"] and disks[addr].fs.root.c["init.lua"].data or "" end
local function hddButton(text, y, color)
	return styled("TextButton", {Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 36), Text = text,
		Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, BackgroundColor3 = color or T.btn,
		BorderSizePixel = 0, ZIndex = 41}, hdd)
end
local hb1 = hddButton("1  OpenOS-Lite", 96)
local hb2 = hddButton("2  MiniOS", 138)
local hb3 = hddButton("3  Outro sistema", 180)
local hbOK = styled("TextButton", {Position = UDim2.new(1, -92, 1, -40), Size = UDim2.fromOffset(80, 30), Text = "OK",
	Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, BackgroundColor3 = T.ok, BorderSizePixel = 0,
	Visible = false, ZIndex = 42}, hdd)
local hbCancel = styled("TextButton", {Position = UDim2.new(0, 12, 1, -40), Size = UDim2.fromOffset(80, 30), Text = "Cancelar",
	Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, BackgroundColor3 = T.bad, BorderSizePixel = 0, ZIndex = 41}, hdd)
local function setWarn(on)
	hbOK.Visible = on
	hb1.Visible, hb2.Visible, hb3.Visible = not on, not on, not on
end
hddOpen = function()
	hddMsg.Text = "Escolha o sistema que vai no novo disco:"
	setWarn(false)
	hdd.Visible = true
end
hb1.MouseButton1Click:Connect(function() hddCreate("OpenOS-Lite", initOf(diskA)) end)
hb2.MouseButton1Click:Connect(function() hddCreate("MiniOS", initOf(diskB)) end)
hb3.MouseButton1Click:Connect(function()
	hddMsg.Text = "AVISO: sistemas de fora podem conter codigo malicioso (roubar conta, senha ou cookie). Este simulador NAO baixa nem roda nada da internet. Se quiser usar um sistema de outra pessoa, abra o codigo, leia tudo e copie com 'edit'. Nunca rode codigo que peca senha ou acesso ao Roblox."
	setWarn(true)
end)
hbOK.MouseButton1Click:Connect(function()
	hddCreate("Sistema nao oficial (restrito)", "-- Sistema nao oficial e RESTRITO: nao pode ser editado nem apagado pelo simulador.\nlocal gpu = component.proxy(component.list('gpu')())\ngpu.bind(component.list('screen')())\nlocal W, H = gpu.maxResolution()\ngpu.setResolution(W, H)\ngpu.fill(1, 1, W, H, ' ')\ngpu.set(2, 2, 'Sistema nao oficial (restrito)')\nwhile true do computer.pullSignal() end\n", true)
	setWarn(false)
end)
hbCancel.MouseButton1Click:Connect(hddClose)
local pendingDel = false
local itemDel = styled("TextButton", {
	Position = UDim2.new(1, -212, 1, -36), Size = UDim2.fromOffset(70, 30), Text = "Excluir HDD",
	Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = T.text, BackgroundColor3 = T.bad, BorderSizePixel = 0, ZIndex = 31,
}, itemPanel)
itemInfo.Size = UDim2.new(1, -290, 0, 30)
itemDel.MouseButton1Click:Connect(function()
	if M.state ~= "off" then
		pendingDel = false
		itemInfo.Text = "Desligue o computador antes de excluir um disco."
		return
	end
	if #userDisks == 0 then
		pendingDel = false
		itemInfo.Text = "Nenhum HDD criado pelo Item para excluir."
		return
	end
	if not pendingDel then
		pendingDel = true
		itemInfo.Text = "Toque em Excluir HDD de novo para confirmar (o ultimo HDD criado)."
		return
	end
	pendingDel = false
	local addr = table.remove(userDisks)
	for i, c in ipairs(comps) do
		if c.addr == addr then table.remove(comps, i) break end
	end
	byAddr[addr] = nil
	disks[addr] = nil
	itemInfo.Text = "HDD excluido (" .. addr:sub(1, 8) .. ")."
	refreshItems()
end)
local driveLabel = "Unidade de disco"
local driveFloppy = nil   -- endereco do disquete que esta dentro da unidade
local lastEjected = nil   -- ultimo disquete ejetado (pode ser colocado de volta)
local floppyComp = {}     -- addr -> registro do componente, guardado enquanto esta ejetado
local floppyCount = 0
local function removeComp(addr)
	for i, c in ipairs(comps) do
		if c.addr == addr then
			table.remove(comps, i)
			byAddr[addr] = nil
			return c
		end
	end
end
local function restoreComp(c)
	table.insert(comps, c)
	byAddr[c.addr] = c
end
local driveM = {
	isEmpty = function() return driveFloppy == nil end,
	getLabel = function() return driveLabel end,
	setLabel = function(l) driveLabel = tostring(l) return driveLabel end,
	media = function() return driveFloppy end,
	eject = function()
		if not driveFloppy then return false, "unidade vazia" end
		local c = removeComp(driveFloppy)
		if c then floppyComp[driveFloppy] = c end
		lastEjected, driveFloppy = driveFloppy, nil
		return true
	end,
	insert = function()
		if driveFloppy then return false, "ja tem disquete" end
		local c = lastEjected and floppyComp[lastEjected]
		if not c then return false, "nenhum disquete para inserir" end
		if #comps >= CPU_MAX_COMPONENTS then return false, "limite de componentes" end
		restoreComp(c)
		driveFloppy, lastEjected = lastEjected, nil
		return true
	end,
}
local adapterLbl, adapterBB = nil, nil
local adapterM = {
	getName = function() return "oc_sim_adapter" end,
	setLed = function(c)
		local v = math.floor(tonumber(c) or 0) % 0x1000000
		setLed(Color3.fromRGB(math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256))
		return true
	end,
	say = function(text)
		if not adapterBB then
			adapterBB = mk("BillboardGui", {Size = UDim2.fromOffset(240, 40), StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true}, case)
			adapterLbl = mk("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.3, BackgroundColor3 = Color3.new(0, 0, 0),
				Font = Enum.Font.Code, TextSize = 13, TextColor3 = T.text, TextWrapped = true}, adapterBB)
		end
		adapterLbl.Text = tostring(text):sub(1, 80)
		return true
	end,
	clear = function()
		if adapterBB then adapterBB:Destroy() adapterBB, adapterLbl = nil, nil end
		return true
	end,
}
installDrive = function(name)
	if isPresent("disk_drive") then itemInfo.Text = name .. " ja esta instalada." return end
	local ok, err = pcall(addComp, "disk_drive", driveM)
	itemInfo.Text = ok and (name .. " instalada no computador.") or tostring(err)
end
installAdapter = function(name)
	if isPresent("adapter") then itemInfo.Text = name .. " ja esta instalado." return end
	local ok, err = pcall(addComp, "adapter", adapterM)
	itemInfo.Text = ok and (name .. " instalado. Use component.adapter.say('oi').") or tostring(err)
end
makeFloppy = function()
	if not isPresent("disk_drive") then itemInfo.Text = "Instale a Unidade de disco primeiro." return end
	if driveFloppy then itemInfo.Text = "A unidade ja tem disquete. Ejete antes." return end
	floppyCount += 1
	local ok, addr = pcall(addDisk, "FLOPPY" .. floppyCount, false, false)
	if not ok then itemInfo.Text = tostring(addr) return end
	driveFloppy = addr
	itemInfo.Text = "Disquete FLOPPY" .. floppyCount .. " colocado na unidade."
end
local _, dGui = addDisk("GUIOS")
seed(dGui, "/init.lua", 
[==[
-- GUIOS 1.0 (/init.lua do disco GUIOS): janelas, clique e teclado
local gpu = component.proxy(component.list("gpu")())
gpu.bind(component.list("screen")())
local W, H = gpu.maxResolution()
gpu.setResolution(W, H)

local C = {bg = 0x1E2A3A, bar = 0x2F4A6B, bar2 = 0x3C6A99, win = 0x26354A, txt = 0xFFFFFF, dim = 0x9FB3CC, ok = 0x77FFAA, err = 0xFF6B6B, btn = 0x3A5577, key = 0xFFCC33}

local function fill(x, y, w, h, bg)
	gpu.setBackground(bg)
	gpu.fill(x, y, w, h, " ")
end
local function txt(x, y, s, fg, bg)
	if bg then gpu.setBackground(bg) end
	gpu.setForeground(fg or C.txt)
	gpu.set(x, y, tostring(s))
end

local windows = {}
local focus = nil

local function raise(win)
	for i, w in ipairs(windows) do
		if w == win then table.remove(windows, i) break end
	end
	table.insert(windows, win)
	focus = win
end

local function newWindow(title, x, y, w, h, app)
	local win = {title = title, x = x, y = y, w = w, h = h, app = app}
	table.insert(windows, win)
	raise(win)
	if app.init then app.init(win) end
end

local function closeWin(win)
	for i, w in ipairs(windows) do
		if w == win then table.remove(windows, i) break end
	end
	focus = windows[#windows]
end

------------------------------------------------ APPS
local notesApp = {
	init = function(win) win.lines = {""} end,
	draw = function(win)
		local maxRows = win.h - 2
		local start = math.max(1, #win.lines - maxRows + 1)
		local row = 0
		for i = start, #win.lines do
			row = row + 1
			local s = win.lines[i]
			if i == #win.lines and win == focus then s = s .. "_" end
			txt(win.x + 1, win.y + row, s:sub(1, win.w - 2), C.txt, C.win)
		end
	end,
	key = function(win, chr, code)
		local L = win.lines
		if code == 28 then table.insert(L, "")
		elseif code == 14 then
			if #L[#L] > 0 then L[#L] = L[#L]:sub(1, -2)
			elseif #L > 1 then table.remove(L) end
		elseif chr and chr >= 32 then
			L[#L] = L[#L] .. utf8.char(chr)
		end
	end,
}

local CALC = {{"7", "8", "9", "/"}, {"4", "5", "6", "*"}, {"1", "2", "3", "-"}, {"0", ".", "=", "+"}}

local function calcEval(win)
	if not win.op or not win.acc then return end
	local b = tonumber(win.disp) or 0
	local a = win.acc
	local r
	if win.op == "+" then r = a + b
	elseif win.op == "-" then r = a - b
	elseif win.op == "*" then r = a * b
	else r = b ~= 0 and a / b or 0 end
	if r == math.floor(r) then win.disp = tostring(math.floor(r)) else win.disp = tostring(r) end
	win.acc, win.op = nil, nil
end

local function calcPress(win, k)
	if k == "C" then
		win.disp, win.acc, win.op, win.new = "0", nil, nil, true
	elseif k:match("%d") or k == "." then
		if win.new then win.disp = (k == ".") and "0." or k win.new = false
		elseif #win.disp < 12 then win.disp = win.disp .. k end
	elseif k == "=" then
		calcEval(win)
		win.new = true
	else
		if win.op then calcEval(win) end
		win.acc = tonumber(win.disp) or 0
		win.op = k
		win.new = true
	end
end

local calcApp = {
	init = function(win) win.disp, win.new = "0", true end,
	draw = function(win)
		fill(win.x + 1, win.y + 1, win.w - 2, 1, C.bg)
		txt(win.x + 2, win.y + 1, win.disp:sub(-(win.w - 4)), C.ok, C.bg)
		for r, row in ipairs(CALC) do
			for c, label in ipairs(row) do
				local bx, by = win.x + 1 + (c - 1) * 5, win.y + 3 + (r - 1) * 2
				fill(bx, by, 4, 1, C.btn)
				txt(bx + 1, by, label, C.txt, C.btn)
			end
		end
		local cy = win.y + 3 + 4 * 2
		fill(win.x + 1, cy, win.w - 2, 1, C.err)
		txt(win.x + 2, cy, "C (limpar)", C.txt, C.err)
	end,
	touch = function(win, col, row)
		if row == win.y + 3 + 4 * 2 then return calcPress(win, "C") end
		for r, rowT in ipairs(CALC) do
			for c, label in ipairs(rowT) do
				local bx, by = win.x + 1 + (c - 1) * 5, win.y + 3 + (r - 1) * 2
				if row == by and col >= bx and col < bx + 4 then return calcPress(win, label) end
			end
		end
	end,
	key = function(win, chr, code)
		local ch = chr and chr >= 32 and utf8.char(chr) or ""
		if code == 28 then calcPress(win, "=")
		elseif ch:match("%d") or ch == "." or ch == "+" or ch == "-" or ch == "*" or ch == "/" then calcPress(win, ch)
		elseif ch == "c" or ch == "C" then calcPress(win, "C") end
	end,
}

local aboutApp = {
	draw = function(win)
		txt(win.x + 2, win.y + 2, "GUIOS 1.0", C.key, C.win)
		txt(win.x + 2, win.y + 3, "Tempo ligado: " .. math.floor(computer.uptime()) .. " s", C.txt, C.win)
		txt(win.x + 2, win.y + 4, "Tab troca de janela", C.dim, C.win)
		txt(win.x + 2, win.y + 5, "Esc fecha a janela", C.dim, C.win)
	end,
}

local icons = {
	{name = "Notas", open = function() newWindow("Notas", 4, 4, 40, 14, notesApp) end},
	{name = "Calculadora", open = function() newWindow("Calculadora", 30, 6, 24, 15, calcApp) end},
	{name = "Sobre", open = function() newWindow("Sobre", 12, 12, 40, 7, aboutApp) end},
}
local function iconPos(i) return 3 + (i - 1) * 14, 2 end

------------------------------------------------ DESENHO
local function redraw()
	fill(1, 1, W, H, C.bg)
	for i, ic in ipairs(icons) do
		local x, y = iconPos(i)
		fill(x, y, 12, 3, C.btn)
		txt(x + 1, y + 1, ic.name:sub(1, 10), C.txt, C.btn)
	end
	for _, w in ipairs(windows) do
		local f = (w == focus)
		fill(w.x, w.y, w.w, w.h, C.win)
		fill(w.x, w.y, w.w, 1, f and C.bar2 or C.bar)
		txt(w.x + 1, w.y, w.title:sub(1, w.w - 6), C.txt, f and C.bar2 or C.bar)
		txt(w.x + w.w - 4, w.y, "[X]", C.err, f and C.bar2 or C.bar)
		if w.app.draw then w.app.draw(w) end
	end
	fill(1, H, W, 1, C.bar)
	txt(2, H, "GUIOS | clique para abrir | Tab: trocar | Esc: fechar", C.dim, C.bar)
end

------------------------------------------------ ENTRADA
local function onTouch(col, row)
	for i = #windows, 1, -1 do
		local w = windows[i]
		if col >= w.x and col <= w.x + w.w - 1 and row >= w.y and row <= w.y + w.h - 1 then
			if row == w.y and col >= w.x + w.w - 4 and col <= w.x + w.w - 2 then return closeWin(w) end
			raise(w)
			if row > w.y and w.app.touch then w.app.touch(w, col, row) end
			return
		end
	end
	for i, ic in ipairs(icons) do
		local x, y = iconPos(i)
		if col >= x and col < x + 12 and row >= y and row < y + 3 then return ic.open() end
	end
end

while true do
	redraw()
	local e, _, a, b = computer.pullSignal()
	if e == "touch" then
		onTouch(a, b)
	elseif e == "key_down" then
		local chr, code = a, b
		if code == 1 and focus then closeWin(focus)
		elseif code == 15 and #windows > 1 then raise(windows[1])
		elseif focus and focus.app.key then focus.app.key(focus, chr, code) end
	end
end
]==])
end
print("[OC Sim v3] pronto. Toque no gabinete ou em Power. Dois /init.lua = menu no BIOS.")
