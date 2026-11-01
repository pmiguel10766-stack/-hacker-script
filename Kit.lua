--[[
    KIT DE SOBREVIVÊNCIA E TERROR v1.0
    Repositório: pmiguel10766-stack/-hacker-script
    Ferramentas: Lanterna Tática, GrabPack V4 e Drone DJI Mini RC
--]]

-- Notification de início
game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "Kit Terror & Sobrevivência",
    Text = "A carregar ferramentas...",
    Duration = 3
})

-- 1. Lanterna Tática (Luz.lua)
task.spawn(function()
    pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/pmiguel10766-stack/-hacker-script/refs/heads/main/Luz.lua"))()
    end)
end)

-- 2. Sistema GrabPack V4 (GrabPack.lua)
task.spawn(function()
    pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/pmiguel10766-stack/-hacker-script/refs/heads/main/GrabPack.lua"))()
    end)
end)

-- 3. Drone DJI Mini RC v3
task.spawn(function()
    pcall(function()
        loadstring(game:HttpGet("https://scriptblox.com/raw/Universal-Script-Drone-DJI-RC-v3-Gemini-IA-231489"))()
    end)
end)

-- Notificação de conclusão
game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "Kit Executado!",
    Text = "Luz, GrabPack e Drone ativados com sucesso.",
    Duration = 5
})
