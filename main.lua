--[[
    ============================================================================
    ROCONS REBORN v2 — Fully Deobfuscated, Universal & Enhanced All-In-One Edition
    ============================================================================
    - 100% Clean Human-Readable Luau Source (Zero VM registers / Zero obfuscation)
    - Anti-Tamper (apt-v2-0.1c / temu apt v1.2) & Key System (rtrcat) Removed
    - Universal Map Support: Built-in RTR_Net Local Server & Database Emulator
      (Works in EVERY Roblox game/map, with or without R_SERVER)
    - Universal R15 & R6 Avatar Support: Non-destructive in-character R6 Motor6D
      & Limb Bridge so R15 avatars (e.g. Brookhaven) can Morph, Sync & Emote
      without breaking movement, camera, or server replication
    - Fast Disk Asset Cache for Animad.rbxm, Morph.rbxm, emou2.rbxm, sound.rbxm
    - Enhanced Obsidian & Neon Amethyst Glassmorphism UI with Live Search Bars
      for Animations & Emotes, Status Badge, and In-Settings Profile Switcher
]]

if not game:IsLoaded() then
    pcall(function() game.Loaded:Wait() end)
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    Players.PlayerAdded:Wait()
    LocalPlayer = Players.LocalPlayer
end
local GlobalEnv = (getgenv and getgenv()) or _G

-- Session Token to cleanly terminate previous executions on re-run
local SessionToken = tostring({})
GlobalEnv.ROCONS_ActiveClientRun = SessionToken
local function IsSessionActive()
    return GlobalEnv.ROCONS_ActiveClientRun == SessionToken
end

-- ============================================================================
-- 1. UNIVERSAL NETWORK LAYER (Real RTR_Net + Local Server Emulator Fallback)
-- ============================================================================
local IsUniversalMode = false

local function CreateSignal()
    local listeners = {}
    local sig = {}
    sig._signal = {
        DisconnectAll = function()
            table.clear(listeners)
        end,
    }
    function sig:Connect(fn)
        table.insert(listeners, fn)
        return {
            Connected = true,
            Disconnect = function(conn)
                conn.Connected = false
                local idx = table.find(listeners, fn)
                if idx then
                    table.remove(listeners, idx)
                end
            end,
        }
    end
    function sig:Fire(...)
        local snapshot = table.clone(listeners)
        for _, fn in ipairs(snapshot) do
            task.spawn(fn, ...)
        end
    end
    function sig:_EmitLocal(...)
        local snapshot = table.clone(listeners)
        for _, fn in ipairs(snapshot) do
            task.spawn(fn, ...)
        end
    end
    return sig
end

local function BuildUniversalNet()
    -- Check if the current map has a real RTR_Net server module
    local netFolder = ReplicatedStorage:FindFirstChild("RTR_Net")
    local netModule = netFolder and netFolder:FindFirstChild("Net")
    if netModule then
        local ok, realNet = pcall(require, netModule)
        if ok and type(realNet) == "table" and type(realNet.Signal) == "function" then
            IsUniversalMode = false
            return realNet
        end
    end

    IsUniversalMode = true
    local signals = {}
    local functions = {}
    local localDB = {}
    local botGeneration = 0

    local function getSig(name)
        if not signals[name] then
            signals[name] = CreateSignal()
        end
        return signals[name]
    end

    local function ensurePlayerEntry(plr)
        if not plr then return nil end
        local entry = localDB[plr.Name]
        if not entry then
            entry = {
                UserId = plr.UserId,
                DisplayName = plr.DisplayName,
                Title = (plr == LocalPlayer) and "Founder" or "",
                Gender = (plr == LocalPlayer) and "M" or "",
                Age = (plr == LocalPlayer) and "18" or "",
                Status = "Idle",
                CurrentAnim = "",
                AnimSpeed = 1,
                Morphed = false,
                SyncPartner = "",
                Role = "D",
                Controller = plr.Name,
                Control = plr.Name,
                Request = "",
                RequesterGender = "",
                Bot = nil,
                IsScriptUser = (plr == LocalPlayer),
            }
            localDB[plr.Name] = entry
        end
        return entry
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        ensurePlayerEntry(plr)
    end
    Players.PlayerAdded:Connect(function(plr)
        local entry = ensurePlayerEntry(plr)
        getSig("StateChanged"):_EmitLocal(plr.Name, entry)
    end)
    Players.PlayerRemoving:Connect(function(plr)
        localDB[plr.Name] = nil
        getSig("StateChanged"):_EmitLocal("__REMOVED__", plr.Name)
    end)

    -- Wire local server behavior for outbound signals
    local function wireServerSimulator()
        getSig("ProfileSetup"):Connect(function(age, gender)
            local me = ensurePlayerEntry(LocalPlayer)
            me.Age = tostring(age or "18")
            me.Gender = tostring(gender or "M")
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
        end)

        getSig("PlayerUpdate"):Connect(function(patch)
            if type(patch) ~= "table" then return end
            local me = ensurePlayerEntry(LocalPlayer)
            for k, v in pairs(patch) do
                me[k] = v
            end
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
        end)

        getSig("MorphToggle"):Connect(function(enabled, gender)
            local me = ensurePlayerEntry(LocalPlayer)
            me.Morphed = (enabled == true)
            if gender and gender ~= "" then
                me.Gender = gender
            end
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
        end)

        getSig("AnimChange"):Connect(function(animName)
            local me = ensurePlayerEntry(LocalPlayer)
            me.CurrentAnim = tostring(animName or "")
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
            if me.SyncPartner and me.SyncPartner ~= "" and me.SyncPartner ~= "[BOT]" and localDB[me.SyncPartner] then
                local partner = localDB[me.SyncPartner]
                partner.CurrentAnim = me.CurrentAnim
                getSig("StateChanged"):_EmitLocal(me.SyncPartner, partner)
            end
        end)

        getSig("SpeedChange"):Connect(function(newSpeed)
            local me = ensurePlayerEntry(LocalPlayer)
            me.AnimSpeed = tonumber(newSpeed) or 1
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
            if me.SyncPartner and me.SyncPartner ~= "" and me.SyncPartner ~= "[BOT]" and localDB[me.SyncPartner] then
                local partner = localDB[me.SyncPartner]
                partner.AnimSpeed = me.AnimSpeed
                getSig("StateChanged"):_EmitLocal(me.SyncPartner, partner)
            end
        end)

        getSig("BotUpdate"):Connect(function(botData)
            if type(botData) ~= "table" then return end
            local me = ensurePlayerEntry(LocalPlayer)
            if botData.Active then
                botGeneration += 1
                me.Bot = {
                    Active = true,
                    Username = tostring(botData.Username or "Roblox"),
                    Morph = tostring(botData.Morph or "F"),
                    Role = tostring(botData.Role or "S"),
                    Generation = botGeneration,
                }
                me.Status = "Synced"
                me.SyncPartner = "[BOT]"
                me.Role = (me.Bot.Role == "S") and "D" or "S"
                me.Controller = LocalPlayer.Name
            else
                me.Bot = { Active = false, Generation = botGeneration }
                if me.SyncPartner == "[BOT]" then
                    me.Status = "Idle"
                    me.SyncPartner = ""
                    me.CurrentAnim = ""
                end
            end
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
        end)

        getSig("SyncRequest"):Connect(function(targetName, myGender)
            -- In Universal Mode, auto-accept sync requests with any player in the server
            targetName = tostring(targetName or "")
            local targetPlr = Players:FindFirstChild(targetName)
            if not targetPlr then return end
            local me = ensurePlayerEntry(LocalPlayer)
            local them = ensurePlayerEntry(targetPlr)
            local myRole = (myGender == "F") and "S" or "D"
            local theirRole = (myRole == "S") and "D" or "S"

            me.Status = "Synced"
            me.SyncPartner = targetName
            me.Role = myRole
            me.Controller = LocalPlayer.Name

            them.Status = "Synced"
            them.SyncPartner = LocalPlayer.Name
            them.Role = theirRole
            them.Controller = LocalPlayer.Name

            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
            getSig("StateChanged"):_EmitLocal(targetName, them)
        end)

        getSig("SyncAccept"):Connect(function(requesterName, myRole, requesterRole)
            local me = ensurePlayerEntry(LocalPlayer)
            me.Status = "Synced"
            me.SyncPartner = tostring(requesterName or "")
            me.Role = tostring(myRole or "S")
            me.Controller = tostring(requesterName or LocalPlayer.Name)
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
        end)

        getSig("SyncBreak"):Connect(function()
            local me = ensurePlayerEntry(LocalPlayer)
            local oldPartner = me.SyncPartner
            me.Status = "Idle"
            me.SyncPartner = ""
            me.CurrentAnim = ""
            me.AnimSpeed = 1
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
            if oldPartner and oldPartner ~= "" and oldPartner ~= "[BOT]" and localDB[oldPartner] then
                local partner = localDB[oldPartner]
                partner.Status = "Idle"
                partner.SyncPartner = ""
                partner.CurrentAnim = ""
                partner.AnimSpeed = 1
                getSig("StateChanged"):_EmitLocal(oldPartner, partner)
            end
        end)

        getSig("TransferControl"):Connect(function(targetName)
            local me = ensurePlayerEntry(LocalPlayer)
            me.Controller = tostring(targetName or LocalPlayer.Name)
            getSig("StateChanged"):_EmitLocal(LocalPlayer.Name, me)
        end)

        getSig("SendChat"):Connect(function(channel, arg2, arg3)
            local me = ensurePlayerEntry(LocalPlayer)
            local text = (channel == "PM") and tostring(arg3 or "") or tostring(arg2 or "")
            local target = (channel == "PM") and tostring(arg2 or "") or ""
            if text == "" then return end
            getSig("ChatMessage"):_EmitLocal({
                Sender = LocalPlayer.Name,
                DisplayName = LocalPlayer.DisplayName,
                Title = me.Title or "Founder",
                Channel = (channel == "PM") and "PM" or "Global",
                Target = target,
                Text = text,
                Time = os.time(),
            })
        end)
    end

    wireServerSimulator()

    functions["GetAllPlayers"] = {
        Invoke = function()
            for _, plr in ipairs(Players:GetPlayers()) do
                ensurePlayerEntry(plr)
            end
            return localDB
        end,
    }

    return {
        Signal = function(name)
            return getSig(name)
        end,
        Function = function(name)
            if not functions[name] then
                functions[name] = { Invoke = function() return localDB end }
            end
            return functions[name]
        end,
    }
end

local Net = BuildUniversalNet()
local PlayerUpdateSig    = Net.Signal("PlayerUpdate")
local SyncRequestSig     = Net.Signal("SyncRequest")
local SyncAcceptSig      = Net.Signal("SyncAccept")
local SyncBreakSig       = Net.Signal("SyncBreak")
local AnimChangeSig      = Net.Signal("AnimChange")
local SpeedChangeSig     = Net.Signal("SpeedChange")
local BotUpdateSig       = Net.Signal("BotUpdate")
local TransferControlSig = Net.Signal("TransferControl")
local ProfileSetupSig    = Net.Signal("ProfileSetup")
local MorphToggleSig     = Net.Signal("MorphToggle")
local StateChangedSig    = Net.Signal("StateChanged")
local ChatMessageSig     = Net.Signal("ChatMessage")
local BotChangedSig      = Net.Signal("BotChanged")
local SendChatSig        = Net.Signal("SendChat")
local GetAllPlayersFn    = Net.Function("GetAllPlayers")

if not IsUniversalMode then
    for _, s in ipairs({ StateChangedSig, ChatMessageSig, SendChatSig, BotChangedSig }) do
        pcall(function()
            if s and s._signal and s._signal.DisconnectAll then
                s._signal:DisconnectAll()
            end
        end)
    end
end

-- ============================================================================
-- 2. ASSETS, RANKS & ENHANCED GLASSMORPHISM THEME
-- ============================================================================
local AssetUrls = {
    Logo     = "https://github.com/Fe-ProjectR/Balls/blob/main/Untitled243_20260721100053.png?raw=true",
    Anims    = "https://github.com/Hubcontainerr/Game/raw/refs/heads/main/Neo-s-main/Neo-s-main/Animad.rbxm",
    Morphs   = "https://github.com/Fe-ProjectR/Balls/raw/refs/heads/main/Morph.rbxm",
    Emotes   = "https://github.com/Hubcontainerr/Game/raw/refs/heads/main/Neo-s-main/Neo-s-main/emou2.rbxm",
    Sounds   = "https://github.com/Hubcontainerr/Game/raw/refs/heads/main/Neo-s-main/Neo-s-main/sound.rbxm",
    GenderM  = "https://tr.rbxcdn.com/180DAY-f6699336e8b2295a5b5656f33df94fb3/150/150/Decal/Png/noFilter",
    GenderF  = "https://tr.rbxcdn.com/180DAY-386aaacfe780343b39432bf3e80903b7/150/150/Decal/Png/noFilter",
    GenderFB = "https://tr.rbxcdn.com/180DAY-c336a0f2ea0cd17fc596f3530d0d8694/150/150/Decal/Png/noFilter",
}

local AssetFiles = {
    Logo     = "ROCONS_Logo.png",
    Anims    = "ROCONS_Anim_Pack.rbxm",
    Morphs   = "ROCONS_Morph_Pack.rbxm",
    Emotes   = "ROCONS_Emotes_Pack.rbxm",
    Sounds   = "ROCONS_Sounds_Pack.rbxm",
    GenderM  = "ROCONS_Gender_M.png",
    GenderF  = "ROCONS_Gender_F.png",
    GenderFB = "ROCONS_Gender_FB.png",
}

local RankConfig
do
local RankTitlesByUserId = {
    [LocalPlayer.UserId] = "Founder",
}

RankConfig = {
    Colors = {
        ["Founder"]       = Color3.fromRGB(185, 110, 255),
        ["Co Founder"]    = Color3.fromRGB(255, 95, 20),
        ["Head Admin"]    = Color3.fromRGB(255, 215, 0),
        ["Super-Admin"]   = Color3.fromRGB(0, 255, 140),
        ["Admin"]         = Color3.fromRGB(0, 185, 255),
        ["Moderator"]     = Color3.fromRGB(170, 175, 255),
        ["Obfuscator"]    = Color3.fromRGB(255, 255, 255),
        ["Artist 🎨"]     = Color3.fromRGB(210, 130, 255),
        ["Bug Finder 🐞"] = Color3.fromRGB(90, 235, 135),
    },
    GetTitle = function(userId)
        local id = tonumber(userId)
        return id and RankTitlesByUserId[id] or nil
    end,
}
end

-- Enhanced High-Contrast Obsidian & Neon Amethyst Palette
local Theme = {
    Background    = Color3.fromRGB(16, 11, 26),
    Panel         = Color3.fromRGB(24, 16, 38),
    Card          = Color3.fromRGB(38, 26, 58),
    CardHover     = Color3.fromRGB(54, 38, 82),
    Accent        = Color3.fromRGB(148, 82, 255),
    AccentHover   = Color3.fromRGB(168, 106, 255),
    AccentBright  = Color3.fromRGB(214, 172, 255),
    AccentDeep    = Color3.fromRGB(88, 42, 168),
    Border        = Color3.fromRGB(96, 66, 145),
    TextPrimary   = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(220, 206, 245),
    TextDarkened  = Color3.fromRGB(172, 156, 204),
    PurpleDark    = Color3.fromRGB(26, 18, 42),
    PurpleBorder  = Color3.fromRGB(178, 118, 255),
    Success       = Color3.fromRGB(96, 235, 174),
    Danger        = Color3.fromRGB(248, 88, 134),
    DangerSoft    = Color3.fromRGB(68, 20, 44),
    DangerHover   = Color3.fromRGB(96, 28, 64),
    DangerText    = Color3.fromRGB(255, 190, 214),
}

-- ============================================================================
-- 3. UI TOOLKIT & VECTOR ICON ENGINE
-- ============================================================================
local UI = {}
UI.IsTouch  = UserInputService.TouchEnabled
UI.IsMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
UI.HasMouse = UserInputService.MouseEnabled
UI.RowH     = UI.IsTouch and 42 or 38
UI.Config   = { CustomFontUrl = "" }
UI.IconImages = {}

function UI.MakeFace(family, weight, fallbackEnum)
    local ok, font = pcall(function()
        local _ = Enum.Font[family]
        return Font.fromName(family, weight)
    end)
    if ok and font then
        return font
    end
    return Font.fromEnum(fallbackEnum)
end

UI.Face = {
    Display  = UI.MakeFace("Michroma", Enum.FontWeight.Regular, Enum.Font.GothamBold),
    Regular  = UI.MakeFace("Nunito", Enum.FontWeight.Regular, Enum.Font.Gotham),
    Medium   = UI.MakeFace("Nunito", Enum.FontWeight.Medium, Enum.Font.GothamMedium),
    SemiBold = UI.MakeFace("Nunito", Enum.FontWeight.SemiBold, Enum.Font.GothamMedium),
    Bold     = UI.MakeFace("Nunito", Enum.FontWeight.Bold, Enum.Font.GothamBold),
    Mono     = UI.MakeFace("RobotoMono", Enum.FontWeight.Medium, Enum.Font.Code),
}

UI.BubbleFont = Enum.Font.GothamMedium
pcall(function()
    UI.BubbleFont = Enum.Font.Nunito
end)

UI.TextClasses = { TextLabel = true, TextButton = true, TextBox = true }

function UI.New(className, props)
    local inst = Instance.new(className)
    if inst:IsA("GuiObject") then
        inst.BorderSizePixel = 0
        inst.AutoLocalize = false
    end
    if inst:IsA("CanvasGroup") then
        inst.GroupColor3 = Color3.fromRGB(255, 255, 255)
    end
    if UI.TextClasses[className] then
        inst.FontFace = UI.Face.Regular
        inst.TextColor3 = Theme.TextPrimary
        inst.TextSize = 14
        inst.BackgroundTransparency = (props and props.BackgroundColor3 ~= nil) and 0 or 1
        if className == "TextButton" then
            inst.AutoButtonColor = false
        elseif className == "TextBox" then
            inst.PlaceholderColor3 = Theme.TextDarkened
        end
    elseif className == "ImageLabel" or className == "ImageButton" or className == "ScrollingFrame" then
        inst.BackgroundTransparency = (props and props.BackgroundColor3 ~= nil) and 0 or 1
    end
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        elseif k == "Face" then
            inst.FontFace = UI.Face[v] or UI.Face.Regular
        else
            inst[k] = v
        end
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

function UI.Corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = (typeof(radius) == "UDim") and radius or UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

function UI.Stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = color or Theme.Border
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

function UI.Pad(parent, l, t, r, b)
    local p = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, l or 0)
    p.PaddingTop    = UDim.new(0, t or l or 0)
    p.PaddingRight  = UDim.new(0, r or l or 0)
    p.PaddingBottom = UDim.new(0, b or t or l or 0)
    p.Parent = parent
    return p
end

function UI.List(parent, dir, pad, hAlign, vAlign)
    local list = Instance.new("UIListLayout")
    list.FillDirection = (dir == "H") and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
    list.Padding = UDim.new(0, pad or 0)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    if hAlign then list.HorizontalAlignment = hAlign end
    if vAlign then list.VerticalAlignment = vAlign end
    list.Parent = parent
    return list
end

function UI.Gradient(parent, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(c1, c2)
    g.Rotation = rot or 90
    g.Parent = parent
    return g
end

function UI.Tween(obj, duration, goal, style, dir)
    local tw = TweenService:Create(
        obj,
        TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        goal
    )
    tw:Play()
    return tw
end

function UI.Escape(str)
    local s = tostring(str or "")
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
    return s
end

function UI.Viewport()
    local cam = Workspace.CurrentCamera
    return (cam and cam.ViewportSize) or Vector2.new(1280, 720)
end

do
local function sBar(x, y, w, h, r)
    return { x = x, y = y, w = w, h = h, r = r or 0, c = 0.5 }
end
local function sRect(x, y, w, h, c, a)
    return { x = x, y = y, w = w, h = h, c = c or 0.2, a = a }
end
local function sDot(x, y, d, a)
    return { x = x, y = y, w = d, h = d, c = 0.5, a = a }
end
local function sRing(x, y, w, h, c, t)
    return { x = x, y = y, w = w, h = h, c = c or 0.2, ring = true, t = t or 0.09 }
end
local function sTri(x, y, d)
    return { x = x, y = y, w = d, h = d, tri = true }
end

UI.Icons = {
    close   = { sBar(0.5, 0.5, 0.92, 0.13, 45), sBar(0.5, 0.5, 0.92, 0.13, -45) },
    plus    = { sBar(0.5, 0.5, 0.8, 0.13, 0), sBar(0.5, 0.5, 0.13, 0.8, 0) },
    minus   = { sBar(0.5, 0.5, 0.8, 0.13, 0) },
    menu    = { sBar(0.5, 0.25, 0.8, 0.12, 0), sBar(0.5, 0.5, 0.8, 0.12, 0), sBar(0.5, 0.75, 0.8, 0.12, 0) },
    grip    = { sDot(0.36, 0.24, 0.15), sDot(0.64, 0.24, 0.15), sDot(0.36, 0.5, 0.15), sDot(0.64, 0.5, 0.15), sDot(0.36, 0.76, 0.15), sDot(0.64, 0.76, 0.15) },
    user    = { sDot(0.5, 0.3, 0.34), sRect(0.5, 0.8, 0.66, 0.36, 0.5) },
    users   = { sDot(0.36, 0.3, 0.3), sRect(0.36, 0.8, 0.54, 0.34, 0.5), sDot(0.72, 0.36, 0.24, 0.4), sRect(0.76, 0.82, 0.38, 0.26, 0.5, 0.4) },
    bot     = { sBar(0.5, 0.1, 0.1, 0.14, 0), sDot(0.5, 0.07, 0.16), sRing(0.5, 0.58, 0.86, 0.6, 0.3, 0.09), sDot(0.34, 0.55, 0.13), sDot(0.66, 0.55, 0.13), sBar(0.5, 0.74, 0.24, 0.07, 0) },
    film    = { sRing(0.5, 0.5, 0.88, 0.7, 0.18, 0.09), sTri(0.43, 0.5, 0.3) },
    sparkle = { sBar(0.5, 0.5, 0.92, 0.12, 0), sBar(0.5, 0.5, 0.12, 0.92, 0), sBar(0.5, 0.5, 0.56, 0.09, 45), sBar(0.5, 0.5, 0.56, 0.09, -45) },
    sliders = { sBar(0.5, 0.22, 0.86, 0.09, 0), sBar(0.5, 0.5, 0.86, 0.09, 0), sBar(0.5, 0.78, 0.86, 0.09, 0), sDot(0.3, 0.22, 0.26), sDot(0.68, 0.5, 0.26), sDot(0.4, 0.78, 0.26) },
    chat    = { sRing(0.5, 0.44, 0.88, 0.62, 0.3, 0.09), { x = 0.3, y = 0.8, w = 0.17, h = 0.17, r = 45, c = 0.1 } },
    send    = { sBar(0.46, 0.5, 0.74, 0.12, 0), sBar(0.72, 0.37, 0.38, 0.12, 45), sBar(0.72, 0.63, 0.38, 0.12, -45) },
    arrow   = { sBar(0.46, 0.5, 0.74, 0.12, 0), sBar(0.72, 0.37, 0.38, 0.12, 45), sBar(0.72, 0.63, 0.38, 0.12, -45) },
    swap    = { sBar(0.45, 0.3, 0.7, 0.1, 0), sBar(0.708, 0.208, 0.26, 0.1, 45), sBar(0.708, 0.392, 0.26, 0.1, -45), sBar(0.55, 0.7, 0.7, 0.1, 0), sBar(0.292, 0.608, 0.26, 0.1, -45), sBar(0.292, 0.792, 0.26, 0.1, 45) },
    play    = { sTri(0.34, 0.5, 0.56) },
    stop    = { sRect(0.5, 0.5, 0.56, 0.56, 0.16) },
    trash   = { sBar(0.5, 0.24, 0.76, 0.1, 0), sRect(0.5, 0.13, 0.28, 0.09, 0.5), sRing(0.5, 0.6, 0.56, 0.6, 0.12, 0.1) },
    check   = { sBar(0.36, 0.6, 0.3, 0.13, 45), sBar(0.64, 0.47, 0.62, 0.13, -50) },
    key     = { sRing(0.3, 0.5, 0.36, 0.36, 0.5, 0.11), sBar(0.62, 0.5, 0.5, 0.11, 0), sBar(0.76, 0.64, 0.1, 0.18, 0) },
    info          = { sRing(0.5, 0.5, 0.88, 0.88, 0.5, 0.09), sDot(0.5, 0.3, 0.1), sBar(0.5, 0.6, 0.1, 0.34, 0) },
    alert         = { sRing(0.5, 0.5, 0.88, 0.88, 0.5, 0.09), sBar(0.5, 0.4, 0.1, 0.3, 0), sDot(0.5, 0.7, 0.1) },
    link          = { sRing(0.36, 0.5, 0.52, 0.3, 0.5, 0.1), sRing(0.64, 0.5, 0.52, 0.3, 0.5, 0.1) },
    chevron       = { sBar(0.509, 0.359, 0.4, 0.12, 45), sBar(0.509, 0.641, 0.4, 0.12, -45) },
    gender_male   = { sRing(0.38, 0.62, 0.50, 0.50, 0.5, 0.12), sBar(0.68, 0.32, 0.40, 0.12, -45), { x = 0.73, y = 0.16, w = 0.30, h = 0.12, r = 0 }, { x = 0.84, y = 0.27, w = 0.12, h = 0.30, r = 0 } },
    gender_female = { sRing(0.50, 0.36, 0.48, 0.48, 0.5, 0.12), { x = 0.50, y = 0.74, w = 0.12, h = 0.36, r = 0 }, { x = 0.50, y = 0.76, w = 0.36, h = 0.12, r = 0 } },
    gender_femboy = { sRing(0.46, 0.50, 0.42, 0.42, 0.5, 0.11), sBar(0.71, 0.25, 0.32, 0.11, -45), { x = 0.75, y = 0.13, w = 0.25, h = 0.11, r = 0 }, { x = 0.85, y = 0.23, w = 0.11, h = 0.25, r = 0 }, sBar(0.22, 0.74, 0.28, 0.11, -45), sBar(0.22, 0.74, 0.26, 0.11, 45) },
}
end

function UI.Icon(parent, name, size, color, extraProps)
    color = color or Theme.TextPrimary
    size = size or 18
    local boxProps = {
        Name = "Icon_" .. tostring(name),
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        Parent = parent,
    }
    for k, v in pairs(extraProps or {}) do
        boxProps[k] = v
    end
    local box = UI.New("Frame", boxProps)
    local fillTargets, strokeTargets = {}, {}
    local shapes = UI.Icons[name] or UI.Icons.info

    for _, sh in ipairs(shapes) do
        if sh.tri then
            for i = 0, 3 do
                local bar = UI.New("Frame", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.fromScale(sh.x + i * (sh.w * 0.2), sh.y),
                    Size = UDim2.fromScale(sh.w * 0.22, sh.h * (1 - i * 0.24)),
                    BackgroundColor3 = color,
                    BackgroundTransparency = sh.a or 0,
                    Parent = box,
                })
                UI.Corner(bar, UDim.new(0.4, 0))
                table.insert(fillTargets, bar)
            end
        else
            local part = UI.New("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(sh.x, sh.y),
                Size = UDim2.fromScale(sh.w, sh.h),
                Rotation = sh.r or 0,
                BackgroundColor3 = color,
                BackgroundTransparency = sh.ring and 1 or (sh.a or 0),
                Parent = box,
            })
            if sh.c then
                UI.Corner(part, UDim.new(sh.c, 0))
            end
            if sh.ring then
                local st = UI.Stroke(part, color, math.max(1.4, size * (sh.t or 0.09)), sh.a or 0)
                table.insert(strokeTargets, st)
            else
                table.insert(fillTargets, part)
            end
        end
    end

    return {
        Box = box,
        SetColor = function(newColor)
            for _, f in ipairs(fillTargets) do f.BackgroundColor3 = newColor end
            for _, s in ipairs(strokeTargets) do s.Color = newColor end
        end,
    }
end

local InteractiveControls = setmetatable({}, { __mode = "k" })

function UI.Interactive(btn, baseColor, hoverColor, pressScale)
    local ctl = {
        Base = baseColor or btn.BackgroundColor3,
        Hover = hoverColor or Theme.CardHover,
        Hovering = false,
    }
    InteractiveControls[btn] = ctl
    local sc = btn:FindFirstChild("PressScale") or UI.New("UIScale", { Name = "PressScale", Parent = btn })
    local downScale = pressScale or 0.96

    function ctl.Paint()
        UI.Tween(btn, 0.14, { BackgroundColor3 = ctl.Hovering and ctl.Hover or ctl.Base })
    end

    btn.MouseEnter:Connect(function()
        ctl.Hovering = true
        ctl.Paint()
    end)
    btn.MouseLeave:Connect(function()
        ctl.Hovering = false
        ctl.Paint()
        UI.Tween(sc, 0.15, { Scale = 1 })
    end)
    btn.MouseButton1Down:Connect(function()
        UI.Tween(sc, 0.08, { Scale = downScale })
    end)
    btn.MouseButton1Up:Connect(function()
        UI.Tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
    end)
end

function UI.SetBase(btn, baseColor, hoverColor)
    local ctl = InteractiveControls[btn]
    if ctl then
        ctl.Base = baseColor
        ctl.Hover = hoverColor or baseColor
        ctl.Paint()
    else
        btn.BackgroundColor3 = baseColor
    end
end

UI.ButtonStyles = {
    primary   = { bg = Theme.Accent, hover = Theme.AccentHover, stroke = Theme.AccentBright, text = Theme.TextPrimary, strokeT = 0.25 },
    secondary = { bg = Theme.Card, hover = Theme.CardHover, stroke = Theme.Border, text = Theme.TextPrimary, strokeT = 0.2 },
    danger    = { bg = Theme.DangerSoft, hover = Theme.DangerHover, stroke = Theme.Danger, text = Theme.DangerText, strokeT = 0.25 },
}

function UI.Button(parent, cfg)
    local st = UI.ButtonStyles[cfg.Style or "secondary"] or UI.ButtonStyles.secondary
    local h = cfg.Height or UI.RowH
    local btn = UI.New("TextButton", {
        Name = cfg.Name or "Button",
        Text = "",
        Size = cfg.Size or UDim2.new(1, 0, 0, h),
        BackgroundColor3 = st.bg,
        LayoutOrder = cfg.LayoutOrder or 0,
        Parent = parent,
    })
    UI.Corner(btn, cfg.Radius or 11)
    UI.Stroke(btn, st.stroke, 1, st.strokeT)
    UI.Interactive(btn, st.bg, st.hover, 0.97)

    local inner = UI.New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = btn,
    })
    UI.List(inner, "H", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
    if cfg.Icon then
        UI.Icon(inner, cfg.Icon, cfg.IconSize or 17, st.text, { LayoutOrder = 1 })
    end
    local lbl = UI.New("TextLabel", {
        Name = "Label",
        Text = cfg.Text or "",
        Face = "Bold",
        TextSize = cfg.TextSize or 14,
        TextColor3 = st.text,
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        LayoutOrder = 2,
        Parent = inner,
    })
    return btn, lbl
end

function UI.Row(parent, cfg)
    local h = cfg.Height or UI.RowH
    local row = UI.New("TextButton", {
        Name = cfg.Name or "Row",
        Text = "",
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = Theme.Card,
        LayoutOrder = cfg.LayoutOrder or 0,
        Parent = parent,
    })
    UI.Corner(row, 11)
    UI.Stroke(row, Theme.Border, 1, 0.35)
    UI.Pad(row, 10, 0, 10, 0)
    UI.Interactive(row, Theme.Card, Theme.CardHover, 0.985)

    local leftOffset = 0
    if cfg.Image then
        local img = UI.New("ImageLabel", {
            Size = UDim2.fromOffset(h - 12, h - 12),
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            BackgroundColor3 = Theme.PurpleDark,
            BackgroundTransparency = 0,
            Image = cfg.Image,
            Parent = row,
        })
        UI.Corner(img, UDim.new(0.5, 0))
        UI.Stroke(img, Theme.AccentBright, 1, 0.4)
        leftOffset = (h - 12) + 10
    elseif cfg.Icon then
        local badge = UI.New("Frame", {
            Size = UDim2.fromOffset(26, 26),
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            BackgroundColor3 = Theme.PurpleDark,
            Parent = row,
        })
        UI.Corner(badge, 8)
        UI.Icon(badge, cfg.Icon, 15, cfg.IconColor or Theme.AccentBright, {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
        })
        leftOffset = 36
    end

    if cfg.Sub then
        local textStack = UI.New("Frame", {
            Position = UDim2.fromOffset(leftOffset, 0),
            Size = UDim2.new(1, -(leftOffset + 24), 1, 0),
            BackgroundTransparency = 1,
            Parent = row,
        })
        UI.List(textStack, "V", 1, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
        UI.New("TextLabel", {
            Text = cfg.Text or "",
            Face = "Bold",
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Size = UDim2.new(1, 0, 0, 17),
            LayoutOrder = 1,
            Parent = textStack,
        })
        UI.New("TextLabel", {
            Text = cfg.Sub,
            Face = "Regular",
            TextSize = 12,
            TextColor3 = Theme.TextDarkened,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Size = UDim2.new(1, 0, 0, 14),
            LayoutOrder = 2,
            Parent = textStack,
        })
    else
        UI.New("TextLabel", {
            Name = "Title",
            Text = cfg.Text or "",
            Face = "SemiBold",
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(leftOffset, 0),
            Size = UDim2.new(1, -(leftOffset + 24), 1, 0),
            Parent = row,
        })
    end

    if cfg.Trail then
        UI.Icon(row, cfg.Trail, 15, Theme.TextDarkened, {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.fromScale(1, 0.5),
        })
    end
    return row
end

function UI.Section(parent, text, order)
    return UI.New("TextLabel", {
        Name = "Section",
        Text = string.upper(tostring(text or "")),
        Face = "Bold",
        TextSize = 11,
        TextColor3 = Theme.AccentBright,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 18),
        LayoutOrder = order or 0,
        Parent = parent,
    })
end

function UI.Caption(parent, text, order)
    return UI.New("TextLabel", {
        Name = "Caption",
        Text = text or "",
        Face = "Regular",
        TextSize = 12,
        TextColor3 = Theme.TextDarkened,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 0),
        LayoutOrder = order or 0,
        Parent = parent,
    })
end

function UI.Field(parent, cfg)
    local h = cfg.Height or UI.RowH
    local wrap = UI.New("Frame", {
        Name = cfg.Name or "Field",
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = Theme.PurpleDark,
        LayoutOrder = cfg.LayoutOrder or 0,
        Parent = parent,
    })
    UI.Corner(wrap, 11)
    local st = UI.Stroke(wrap, Theme.Border, 1.2, 0.15)
    local leftPad = 12
    if cfg.Icon then
        UI.Icon(wrap, cfg.Icon, 16, Theme.AccentBright, {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
        })
        leftPad = 36
    end
    local box = UI.New("TextBox", {
        Text = cfg.Text or "",
        PlaceholderText = cfg.Placeholder or "",
        Face = "Medium",
        TextSize = 14,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(leftPad, 0),
        Size = UDim2.new(1, -(leftPad + 10), 1, 0),
        Parent = wrap,
    })
    box.Focused:Connect(function()
        UI.Tween(st, 0.15, { Color = Theme.AccentBright, Transparency = 0 })
    end)
    box.FocusLost:Connect(function()
        UI.Tween(st, 0.15, { Color = Theme.Border, Transparency = 0.15 })
    end)
    return box, wrap
end

function UI.Segmented(parent, options, defaultVal, onSelect, order)
    local wrap = UI.New("Frame", {
        Name = "Segmented",
        Size = UDim2.new(1, 0, 0, UI.RowH),
        BackgroundColor3 = Theme.PurpleDark,
        LayoutOrder = order or 0,
        Parent = parent,
    })
    UI.Corner(wrap, 11)
    UI.Stroke(wrap, Theme.Border, 1, 0.3)
    UI.Pad(wrap, 4, 4, 4, 4)
    UI.List(wrap, "H", 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

    local seg = { Selected = defaultVal, Buttons = {} }
    local count = math.max(1, #options)

    function seg.Set(val)
        seg.Selected = val
        for k, b in pairs(seg.Buttons) do
            local active = (k == val)
            UI.SetBase(b, active and Theme.Accent or Theme.Card, active and Theme.AccentHover or Theme.CardHover)
            b.TextColor3 = active and Theme.TextPrimary or Theme.TextSecondary
        end
    end

    for idx, opt in ipairs(options) do
        local key = type(opt) == "table" and opt.Key or opt
        local label = type(opt) == "table" and opt.Text or tostring(opt)
        local btn = UI.New("TextButton", {
            Name = "Seg_" .. tostring(key),
            Text = label,
            Face = "Bold",
            TextSize = 13,
            Size = UDim2.new(1 / count, -4, 1, 0),
            BackgroundColor3 = Theme.Card,
            LayoutOrder = idx,
            Parent = wrap,
        })
        UI.Corner(btn, 8)
        UI.Interactive(btn, Theme.Card, Theme.CardHover, 0.96)
        seg.Buttons[key] = btn
        btn.MouseButton1Click:Connect(function()
            seg.Set(key)
            if onSelect then onSelect(key) end
        end)
    end
    seg.Set(defaultVal)
    return seg
end

function UI.Toggle(parent, title, subtitle, initialVal, onChange, order)
    local state = (initialVal == true)
    local row = UI.New("TextButton", {
        Name = "ToggleRow",
        Text = "",
        Size = UDim2.new(1, 0, 0, subtitle and 54 or 44),
        BackgroundColor3 = Theme.Card,
        LayoutOrder = order or 0,
        Parent = parent,
    })
    UI.Corner(row, 11)
    UI.Stroke(row, Theme.Border, 1, 0.35)
    UI.Pad(row, 12, 6, 12, 6)
    UI.Interactive(row, Theme.Card, Theme.CardHover, 0.985)

    local textStack = UI.New("Frame", {
        Size = UDim2.new(1, -64, 1, 0),
        BackgroundTransparency = 1,
        Parent = row,
    })
    UI.List(textStack, "V", 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
    UI.New("TextLabel", {
        Text = title,
        Face = "Bold",
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 17),
        LayoutOrder = 1,
        Parent = textStack,
    })
    if subtitle then
        UI.New("TextLabel", {
            Text = subtitle,
            Face = "Regular",
            TextSize = 12,
            TextColor3 = Theme.TextDarkened,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, 0, 0, 14),
            LayoutOrder = 2,
            Parent = textStack,
        })
    end

    local track = UI.New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(46, 24),
        BackgroundColor3 = state and Theme.Accent or Theme.PurpleDark,
        Parent = row,
    })
    UI.Corner(track, UDim.new(0.5, 0))
    local trackStroke = UI.Stroke(track, state and Theme.AccentBright or Theme.Border, 1, 0.2)

    local knob = UI.New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Theme.TextPrimary,
        Parent = track,
    })
    UI.Corner(knob, UDim.new(0.5, 0))

    local function applyVisual()
        UI.Tween(track, 0.16, { BackgroundColor3 = state and Theme.Accent or Theme.PurpleDark })
        UI.Tween(trackStroke, 0.16, { Color = state and Theme.AccentBright or Theme.Border })
        UI.Tween(knob, 0.16, { Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
    end

    row.MouseButton1Click:Connect(function()
        state = not state
        applyVisual()
        if onChange then onChange(state) end
    end)

    return row
end

function UI.Clamp(frame)
    if not frame or not frame.Parent or not frame.Parent:IsA("GuiBase2d") then return end
    local vp = UI.Viewport()
    local sz = frame.AbsoluteSize
    local ap = frame.AnchorPoint
    local pos = frame.AbsolutePosition
    local cx = math.clamp(pos.X, 6, math.max(6, vp.X - sz.X - 6)) + sz.X * ap.X
    local cy = math.clamp(pos.Y, 6, math.max(6, vp.Y - sz.Y - 6)) + sz.Y * ap.Y
    frame.Position = UDim2.fromOffset(cx, cy)
end

function UI.MakeDraggable(handle, targetFrame)
    handle.Active = true
    local dragging = false
    local dragInput, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            local ap = targetFrame.AnchorPoint
            local absPos = targetFrame.AbsolutePosition
            local absSize = targetFrame.AbsoluteSize
            startPos = Vector2.new(absPos.X + absSize.X * ap.X, absPos.Y + absSize.Y * ap.Y)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            local vp = UI.Viewport()
            local sz = targetFrame.AbsoluteSize
            local ap = targetFrame.AnchorPoint
            local nx = math.clamp(startPos.X + delta.X, sz.X * ap.X + 4, math.max(sz.X * ap.X + 4, vp.X - sz.X * (1 - ap.X) - 4))
            local ny = math.clamp(startPos.Y + delta.Y, sz.Y * ap.Y + 4, math.max(sz.Y * ap.Y + 4, vp.Y - sz.Y * (1 - ap.Y) - 4))
            targetFrame.Position = UDim2.fromOffset(nx, ny)
            targetFrame:SetAttribute("Moved", true)
        end
    end)
end

function UI.AttachAutoScale(frame, designHeight)
    local dH = designHeight or 420
    local sc = frame:FindFirstChild("ViewportFitScale") or UI.New("UIScale", { Name = "ViewportFitScale", Parent = frame })
    local function updateScale()
        local vp = UI.Viewport()
        local ratio = math.clamp((vp.Y - 24) / dH, 0.65, 1)
        sc.Scale = ratio
        frame:SetAttribute("BaseFitScale", ratio)
    end
    updateScale()
    local cam = Workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
    end
    return sc
end

function UI.Present(frame, open)
    local sc = frame:FindFirstChild("PopScale") or UI.New("UIScale", { Name = "PopScale", Parent = frame })
    local ver = (frame:GetAttribute("PresentV") or 0) + 1
    frame:SetAttribute("PresentV", ver)
    frame:SetAttribute("IsOpen", open)

    if open then
        frame.Visible = true
        sc.Scale = 0.92
        UI.Tween(sc, 0.24, { Scale = 1 }, Enum.EasingStyle.Quint)
        if frame:IsA("CanvasGroup") then
            frame.GroupTransparency = 1
            UI.Tween(frame, 0.22, { GroupTransparency = 0 }, Enum.EasingStyle.Quint)
        end
    else
        local tw = UI.Tween(sc, 0.16, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        if frame:IsA("CanvasGroup") then
            UI.Tween(frame, 0.16, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        end
        tw.Completed:Connect(function()
            if frame:GetAttribute("PresentV") == ver then
                frame.Visible = false
            end
        end)
    end
end

function UI.IntroOnShow(frame)
    local sc = frame:FindFirstChild("PopScale") or UI.New("UIScale", { Name = "PopScale", Parent = frame })
    frame:GetPropertyChangedSignal("Visible"):Connect(function()
        if frame.Visible then
            sc.Scale = 0.92
            UI.Tween(sc, 0.26, { Scale = 1 }, Enum.EasingStyle.Quint)
            if frame:IsA("CanvasGroup") then
                frame.GroupTransparency = 1
                UI.Tween(frame, 0.22, { GroupTransparency = 0 }, Enum.EasingStyle.Quint)
            end
        end
    end)
end

function UI.Modal(name, parent, maxWidth)
    local m = UI.New("Frame", {
        Name = name,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.92, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        Visible = false,
        Active = true,
        ZIndex = 200,
        Parent = parent,
    })
    local sc = Instance.new("UISizeConstraint", m)
    sc.MaxSize = Vector2.new(maxWidth or 340, 9999)
    UI.Corner(m, 18)
    local st = UI.Stroke(m, Color3.new(1, 1, 1), 1.5, 0.08)
    UI.Gradient(st, Theme.AccentBright, Theme.AccentDeep, 90)
    UI.Pad(m, 20, 20, 20, 20)
    UI.List(m, "V", 12, Enum.HorizontalAlignment.Center)
    UI.IntroOnShow(m)
    return m
end

function UI.BuildOverhead(head)
    local existing = head:FindFirstChild("ROCONS_Overhead")
    if existing then existing:Destroy() end

    local bb = Instance.new("BillboardGui")
    bb.Name = "ROCONS_Overhead"
    bb.Adornee = head
    bb.Size = UDim2.new(5.2, 0, 1.25, 0)
    bb.StudsOffset = Vector3.new(0, 2.5, 0)
    bb.AlwaysOnTop = false
    bb.LightInfluence = 0
    bb.Parent = head

    local frame = UI.New("Frame", {
        Name = "Frame",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.08,
        Parent = bb,
    })
    UI.Gradient(frame, Color3.fromRGB(44, 26, 68), Color3.fromRGB(12, 8, 20), 90)
    UI.Corner(frame, UDim.new(0.28, 0))
    UI.Stroke(frame, Theme.PurpleBorder, 1.5, 0.1)
    UI.List(frame, "V", 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

    local rankLbl = UI.New("TextLabel", {
        Name = "RankDisplay",
        Face = "Bold",
        TextScaled = true,
        Text = "",
        Size = UDim2.new(1, 0, 0.45, 0),
        LayoutOrder = 1,
        Visible = false,
        Parent = frame,
    })
    local textLbl = UI.New("TextLabel", {
        Name = "TextDisplay",
        Face = "SemiBold",
        TextScaled = true,
        Text = "",
        TextColor3 = Theme.TextPrimary,
        Size = UDim2.new(1, 0, 0.45, 0),
        LayoutOrder = 2,
        Parent = frame,
    })
    return bb, frame, rankLbl, textLbl
end

function UI.PrepareBot(botModel)
    local hum = botModel:FindFirstChildOfClass("Humanoid")
    if hum then
        local function hideHud()
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.NameDisplayDistance = 0
            hum.HealthDisplayDistance = 0
            hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        end
        hideHud()
        hum:GetPropertyChangedSignal("DisplayDistanceType"):Connect(hideHud)
    end
    for _, d in ipairs(botModel:GetDescendants()) do
        if d:IsA("BillboardGui") and (d.Name == "ROCONS_Overhead" or d.Name == "ROCONS_ChatBubble") then
            d:Destroy()
        end
    end
end

-- ============================================================================
-- 4. DELTA-COMPATIBLE HTTP FETCHER & DISK-CACHED ASSET PACK LOADER
-- ============================================================================
local getCustomAsset = getcustomasset or getsynasset
local SafeHttpGet
do
local httpRequestFn = (type(request) == "function" and request)
    or (type(http_request) == "function" and http_request)
    or (type(http) == "table" and type(http.request) == "function" and http.request)
    or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
    or (type(fluxus) == "table" and type(fluxus.request) == "function" and fluxus.request)
    or nil

SafeHttpGet = function(url)
    local ok, res = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok and type(res) == "string" and #res > 0 then
        return res
    end
    local ok2, res2 = pcall(function()
        return game:HttpGet(url)
    end)
    if ok2 and type(res2) == "string" and #res2 > 0 then
        return res2
    end
    if httpRequestFn then
        local ok3, resp = pcall(httpRequestFn, { Url = url, Method = "GET" })
        if ok3 and type(resp) == "table" and type(resp.Body) == "string" and #resp.Body > 0 then
            return resp.Body
        end
    end
    return nil
end
end

local GenderIconAssets = { M = "", F = "", FB = "" }
do
local B64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Base64Decode(b64)
    if type(crypt) == "table" and type(crypt.base64decode) == "function" then
        local ok, res = pcall(crypt.base64decode, b64)
        if ok and type(res) == "string" and #res > 0 then return res end
    end
    local lut = {}
    for i = 1, #B64Alphabet do
        lut[string.byte(B64Alphabet, i)] = i - 1
    end
    local out = {}
    local acc, bits = 0, 0
    for i = 1, #b64 do
        local v = lut[string.byte(b64, i)]
        if v ~= nil then
            acc = acc * 64 + v
            bits += 6
            if bits >= 8 then
                bits -= 8
                local byte = math.floor(acc / (2 ^ bits)) % 256
                table.insert(out, string.char(byte))
                acc = acc % (2 ^ bits)
            end
        end
    end
    return table.concat(out)
end

local EmbeddedGenderPngB64 = {
    GenderM = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAwFBMVEUAAAAAp/4Asv4A//8Aqf8Ap/cAfv4ApfIApvYAvv8AAP8Ao/EAm+sAluYAmPYAne0AidEAldMAVasAoe0Af38AfLcAqqoAe88Ai9cAldwAac4Av78AieQAP78AAH8AVf8AZrIAzP8AZpcAqtQAnvIAofIAhrsAVX8AVVUAAFUA1P8ASG0AX58Aw/8Aj+cAn/IAM8wAADMAMzMAJJEAkbYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC4ITHgAAAAQHRSTlMA/f4BA80CjLEEAW9KMAxmFhADUwIIAw8iLAcEFQQCAwsFBwaNNxMGAwMGBwj/IKYFBQUHBwAAAAAAAAAAAAAAvc08GgAABhhJREFUeNrtW9diozoQHVQRCBkMuCXetM2228v/f9sV2LmRBMZI2M7DMnlJMczRdM1MAGaaaaaZZro0YcxawhiTXlpV1wXAkuQDj8/gNT4QNyk90CJdaEq3gK8GYAUSnaEIxRrnFQFE50gDwDOAnx3Ap58eQPLRANh1A1Fkx53bAmCQUYviGwPQ9LBkywOxfQGL2wMwEnMv/xsCIJCifgA3YZ8wSPu9gN4EQCJ65X8zAKf5XwJAkuiCDw+WXuQkfw1gOcGwCWOCHI2YYSEIO3H+XvubCIAV6sCa7db5es3+bH8oFOnwV679oZijqQDas/6dyQXncdzEOF14LmSWt3/Cw/pHNDckEgIAN6esJY+pG+kpT7P2NjCgf0QLmCQBJgBUyRvmPSqNojhVR4wH/18g9/yA+QQJ6LcXKY3Q6QSLIr4FeGmUlBTd82/AlEBEn/2OTyBPKTqX5COeNcLv0/8GCLEA/AKJT0CH8iz7I4QCHkTH/rX+BQQD0NrfxmPYH3hJ6LM/AQ6AejQAbdsyGsu/Ycd75L8DB0A0GgCBRx5NIUQzqKED4H4kAAH3MZrGv4A76ALIx91MCticsr5T9WYn/jX67wJQowCQfv7Nr3QY/qMJx1E0hOJN/4EAiK5vUZd7E3mL40fqrY7NJzH8r/9udTYGwArfd/hrTy/zQ2yq9Vf7kr+yNO71k3f9HyXw23sCIecBYLZ07Q9FTcQHpcQx8SSMiCf9bV7Gg/pv3wel0bFRYxyAo26c03mXddKkfttSdqRl6D/sglN2FWqlXLtKgjXv9ACU+6l3Ost/yX6nToTLYeg2QRKN2BICSk0N+FYfAhwDSJvfDYrspeM0GyDhCnDu2KU2ynOF8osTNlBcP4UW3ZjZrypHnYVBYT8mQ9uBBEpka5MlMDJ0WiJYs0AB/Gu9h4MYeZktbNVpEZALuCB9xqMP8sMqR0N7QQ/frMCWeRwjYV8t993qlo031bC1FcC8zCczH/4cEgsUfDZNULHKz4DNEE6/+DtCxWrDmbQH3HmOSzLbDL1FgC0heoczzPaGCLQClS8A617dWEDi+7y0cjJmvo2dvZkGJKy9VZib8TDzDQUY7g1HonnibURPlhFLKLw7nVZSvwvwImmHUd88YD6+CPBjnRHMI+w9jciuXkOCeYIraiYkz+mIe4OpQnKJYcZUTQFAH0OGO3Y9m3meARvwEf0WkszsDt3GMxjjxAAQ1lRmVosg8xQi/mQCCMrndkX5IQCmSIBZNsCm28DW1wYCezkDXsAmxIEvIW5IrFuNbxx4sOSXhVT2GKihRf9IWKJp9zsMazMUf4Up2ZAH5ILCyYbe9YAy64FfMfZPx2ZJ5Z1PE7yzKyJfI6jwOrasSEysCX2LyjurqNU2yCYFUnqPCYT7sS6pvK14leTm7WrhG8iwsh9XATWdeQS69jNDZ1qr/I3YuWNrM/bRQQWF3akSIbtoO+uGm/sowY7kkcQkKJ2m1iV/+QMHleRaf3XgOp6KbCWo0eMFu0dTBu4LYWfsKkeaMqlqq0ulfTgJFYHdpsxGIXgAp7tYBrcqhTt53I5whR3U3O4TPrLQMX1Fdk6nNINzax8CcucZOaFXK+wuRRvSBjsFOt44ndqgVG6Nn53+O9eNguKEFJr2t9urpjlJpi3AxO4AulwCVqyns60lnXVGFtkkATRpXXVmELEEd2SByZ2WSsbdoQ2aYgB9Hb/j0CROi+M8u6WDRiTvDpfGt3eH3Er2jOxonG7rT2+f2eeS94z1Ed+LC+xKPbljm7exIY31nrBeD27WKfoGZvr8kFxmE0v2zwQHVvVa/t/xhTaVRN/s8iyl38nFdtUUbDyn10hnAMIuuZ/4D0ee43qBL7uRB3K0GvRws57s/52byhPkfNwSBYpfIWRCcd4Ue0JdD9FyDeIq/7vAjtF2aFVAp4pHuN7WflNabdMTqwKoWSpo08Q1N0X1NhM8v6aHVTIzIjXLZDJ/X+S6Hq2U1u9SZU0EPpaMTUyW22alQYhb/F9JRQ4XrWT5mOd5ka+fDzon4kZbum37AK+MQIcZJux23K2WfFXhj+A800wzzTTTTFeg/wDHskKLIHlg9AAAAABJRU5ErkJggg==",
    GenderF = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAwFBMVEUAAAD/WLP/Vqz/Wrb/P7//AP//Wrf/W7n/Wrn/WLT/f3//Wrf/f///XsD/AAD/f73/////Vf//YML/P3//Zs3/Zpn/Sqv/AH//Wpn/M5n/AKr/WMr/M8z/S5f/aLX/XcD/VVX/SNr/VX//YLv/YL//Zv//qqr//wD/qv8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAz+nqBAAAAQHRSTlMA/QlOBAGPzbEvAnMC/gEEAQP+BAUFDgIKBQMNBQoOVgMHBjX/BQMBAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAub/vjQAABC5JREFUeNrtWulymzAQXnRLHMYXtmPn6N33f8IuNEYCJ0YZJDKd6vvhIQPDfuyt3QAkJCQkJCTMADcFwvDPEb5m2+L1csvWy5KoDPl7QVqcX68X00TNUNKBUKGklFmGP0rQpwPyOpkl5K8MbHWushFUrgnwVRVbvGGwoyorsxuUmaJnuPpFLOOvAd4W/6oGir4QUQnoZlpld6E01NE8oSiAZpPIX2oSRz4BIjIPCHwwkny1ufG8zebGITZSx2CwBSLHoqQQeS7EjVsgAxbh++VIOCWHV9/EpDS6GdwKnDUD/Su6+ysaUXcOSgd6kGcSNjG/gLDyS4nhfmBWBCfMdAnC+oEAE9YB6MjN9/VIRXt0ktyNxpBusAbtvBo/f8/fshIMaIZ0REaUK/9yeMdRLi5R9chCucHK/TKNf955UrtMV4EigB+V89bdvWf3DlfZ1GFU4FSAUsCPqXyRl5ZsmGRQg7IfRSaiy5Cmf1rVdZAa7NiVoo4n4BpBQ4j2hEEf3oqcfJ7vVSCCRGLBlVUA86ka2paEYr4buu/zazl5Ia0N5rvhrrdpmfuZ1AmE/H7QeuGrdQFPnyqszgRcZvfBK+tT2Pd7mQCaqw0Un12VudmrPrl7EuBbZRsTMzsNXjuhUvDCt3hem4cAnRFxCOCbPVNXbpvD+QS07IPA+FbPPgw+jUC4RFBYAh8xQRnMBMbxgcpUnloTZTAnNLwvr+roF4bV4TFgGHJb3KR3IiI2Ec0fHu1AfNCjiJuK93PlOw0GhgH5hGLklmPPzznIoGeDAvr3Ue6hggduGZ/5r7AtGZ7Rlm/Jhk3pblq+DtyUAq9sW36cCivOTvbpogo0m7AHk8kzr2OwYAeTqnaGIxONsXuMlI880MiQDQ+ndyaR++HhNNT5HCfAymXw+E5+57Z2d6XDBBuSkHo4oCjetC3BU6yMM6BwmqwuwWJVehhFA3+owTgPobtuISBO3BlStX0G+hu7nru42bZJ+ptjp1KRFQQd03GihjPp1gpkv0Ocuks9GOPKBg6BB5XVaFDZLSiuN8cLDFTRFiD0qFaPR7W4qsFRbY6rm9tRbYRh8U8cVpc+0/JW/m+IgBUclY981cAKIM7AfhCN7y0sqjjrgm5cRXxWNibi8q7awZHKO9anDRRx95eoXULVezszAvHUb3Mu/uh2QbFxd4btAqNLWLAA1g9t7qF2VYPC9VO7z4aFULFL2xNQZ4CP3TNbdIOOI1ljCdSMGFgaxNUAA0gEEoFEIBFIBP4LAtwFcwlcBreW0sGwHC+h9CGankDeDO88xbb5FCisP5XA9zhO+SENJAKJQCQCGz/5mzgEcH8mhrD/qzG6EWhIPQm9dCrmzMUTsbWAfBnc4qkfSAQSgUQgEUgEliKwiVr/Pf5T45l2eD6HXhD9K+Bs3Vb/NashISEh4R/GH8J/KQC95A8dAAAAAElFTkSuQmCC",
    GenderFB = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAwFBMVEXjYOafX9nuYN7qYN7/AADwcbj/AH9/AP/gX+L/P7/MM/+qAP//v/9/f7///wB/P38A/wAAAADOZuy2afbjYuLOZuu2afb9ff3iYeL/AP/sYN2qVf/MafPMaPD////RaPaqVaroZOf9VfzrYN3OZ+/lZOfPafPsZep/f/+ya/y3avj/qv+5a/i5a/m+fv4AAP/oYuTnYuK/f7/Ncva/P79/f3//Vaq3afZ/AH//f3+qqv/MZsznX95VVf//P/+/P//a78CyAAAAQHRSTlMdBaNNAQQCAsIEBQMEBAEEAQC8vbzGxgPFAbwDTpQBFAM1BMdxUjEWAiEaA1qeBQFsjwQVBAIDZgICAwXGAwQE4i7mAgAABnZJREFUeNrtmwd3mzoUx0m63n7vKhZCZplNndQjsTOaju//raqBQOBty/ScV9+TkxpC+f/u0JVQiAU/2awLwAXgAvD/AqBEmjtaY275C0RgXNnHtTY+N4ALd/bNFvsUnxlgBE/2jb3ZbtyzA6gIrA2E/emnA8S/fATcn1CEv1YNsEb0UfagSdWQnuyeATrW7kt9AEzLygJK7llF9A7QWEBW+nKvAFNd3+4fgLqr+n0CtOJvf6o+9wfQ1r95+KgAbvsBYPn3NP2xorH9fgA6+R9D6fUKIOJva/pX0CtAwOOvAGz0AF/dcwFM18Z/JOQqxZsQSjgDQOBOJt9j111MJp21PpVqtmDg8f8MxgGo257VXZe24o+ZFMIi/mNwwTAALblamN/dPaVp+nTn5eP6rNJHzDAS+XflYt3D/JwBALrg6p6PbjC2MTcbId8LuQqV+Zf6LAKY+V+CDoDwqQDEBTf3ERdGysSBn4ewHPH8K31ko5Dn3ygA8yf3dXENwvcA7pWQIJD5NwngQugL9S6BOIf9vPafnwprfUMAAQUPrZOvEVBaBwez+vsbjAIEQMT9cS2oi4vvWIt/nX8FIA0dDUC4PurUHsbrCkL677bgQ09aHhwJEFDL13wUhe+zPuCLIbGiH4JreIOiLFNZaVIepV4YXvGWEI7zFDWpUfrdrRg6keYeCaCqiHvLvkTjgemSlGI6Cj1+sq4/P4Rbw1s0BPKq0rh+yuSDsqRCnFLCvH1IGwLsHai/G2BJQ4SrkYZRLrtuewKEvIkAy0BgFuAWUv3uV2S1RAjvUeqa9KAS3A1AGve4/mTtMuQKHnyVBZwfRrALoHTTWj+HeHOfrvLEyvC1k6STAPQAePB943WxqlRWp7nJPlDyCpCepcEf080XfqtLhVUBMZiCou722x0jQVhfGQI1BfC1iWy6JQHt0cJy8KcpgJG6KwsA/bBXtWDO+tUUAAG/uqm/s72Qqa/m/cBUDbBlQONVueeUcWARWNsDYDXtpdx3ztjn4j0BFuyeWC0ydsWVwsMxzXArwP1hUX1VAJ55AH8fAOKfEeBhDwB6RoC9UhAYB1jUi6E9AGg1Zk0CxGou5DMB2fnsEDajYGQGYNTMRd5OAKKHi5gBoG+JX3dCurMTpg2AqblAuymhdNfTi2rbPjybA/Ca9dD2vH5rOrF3yIrE2rewfLL1rjR+VYMQReYWJIxALXeZX1db1yN1APwQTC5K6xyggm6OAQ0Kv8lAbA6A1jkQi026GbRZvYeByUVpU4YIZ5tcm8baVelhT4e7AD4sQ9UMMQvukq7fH8+wlil6IgDptOOs2ZhIAT4vV7en+SYM2nO47gZ47qx9Jk0zYhVeMECdkB8Us9p91oQInAbwHBStYRzEMKv3B5hEFor9YhLQJRnFjJVkSN+fosFpAASyQaR5wYZekwK5I5hF+pOT5+v7Y9GhAegCLJg+v81Cry+EtAjwf+ZpFoVWEb2Z+c0WEa/SrP6PxwHQe1HOjSO0KUFtJ1Bt0LU26qT+v3ASQACZg6tQxrLAM2egFOpP3AZMe9DZn8sOjn8HgAr9wcAZYFYHpdRnx9wQHjjOYIvhQXSMvg7wDAXT5ir8O6sD4X9z/9kWAseZhYfnvxsBQqIWgabvDFgDiOYSQQNRJ+YRHLo/t7YIQRFwyaitPwrgMWMIzorzzjz7a8tEdcgwvAU9BrUW12dFOWJJimZcUWI4v4kPs6jgv64FIy+zEUEwqAg0/Xs5TNkuEWOYD4Xj7Edzrg5Hu7+mE75qWWj7XzVm8eBtxYVlWUUh/F7GAYC51/kmdQz0/LdfWqTrDwy9T8jrIFnvv74EY+9NBvRE8Q3rgXd6DL4wfQLQ5xuVdEEzbaAf2eCOBxD91xm0COIeAajef4X+F0bw0hsA+/1v1m51siv/3hMAn/+T4VAoD5NEmxdILwBy/pf6bCgOk2FSfTxfHVjd/FfyTLqwBs7QqevgbR8p4PGXloj5dyiPWSSGGQTnBghI9qXRj+H+myBIJMEc3tPzArxA1PL/Ed6+A0sRzC169ghQMqsIkuuq/99WWUjmBdA+aoATJML/d/X6QMSfnG0ctkbBIye4Tq7jZtDxFUpyTVhC+ugDL+/hTZIMC12OwJt5fMb5qJ2Cf1gMhp35n+X+Pwq9zQUvj1bXXTqifc6GsLrBQHtekABc/sznAnABuABcAC4AF4ALwAWgT/sBMbickXaBfxkAAAAASUVORK5CYII=",
}

pcall(function()
    if writefile and getCustomAsset then
        for key, b64Key in pairs({ M = "GenderM", F = "GenderF", FB = "GenderFB" }) do
            local fname = AssetFiles[b64Key]
            local b64 = EmbeddedGenderPngB64[b64Key]
            if fname and b64 then
                local raw = Base64Decode(b64)
                if raw and #raw > 100 then
                    writefile(fname, raw)
                    local uri = getCustomAsset(fname)
                    if type(uri) == "string" and uri ~= "" then
                        GenderIconAssets[key] = uri
                    end
                end
            end
        end
    end
end)
end

-- Downloads a real PNG image from the internet and applies it to an ImageLabel
local function BindWebImage(imgLabel, webUrl, cacheFileName, fallbackRbxAsset)
    if not imgLabel then return end
    if fallbackRbxAsset and fallbackRbxAsset ~= "" then
        imgLabel.Image = fallbackRbxAsset
    end
    task.spawn(function()
        pcall(function()
            if isfile and writefile and getCustomAsset then
                if not isfile(cacheFileName) then
                    local raw = SafeHttpGet(webUrl)
                    if raw and #raw > 64 then
                        writefile(cacheFileName, raw)
                    end
                end
                if isfile(cacheFileName) then
                    local customUri = getCustomAsset(cacheFileName)
                    if type(customUri) == "string" and customUri ~= "" then
                        imgLabel.Image = customUri
                    end
                end
            end
        end)
    end)
end

local LogoAssetId = "rbxthumb://type=Asset&id=9327507252&w=150&h=150"
pcall(function()
    if isfile and writefile and getCustomAsset and isfile(AssetFiles.Logo) then
        local customLogo = getCustomAsset(AssetFiles.Logo)
        if type(customLogo) == "string" and customLogo ~= "" then
            LogoAssetId = customLogo
        end
    end
end)

local function LoadAssetPack(url, fileName, expectedFolderName)
    -- 1. If already mounted in Workspace from an earlier run in this server, reuse immediately (0ms!)
    local existingInWs = expectedFolderName and Workspace:FindFirstChild(expectedFolderName)
    if existingInWs and existingInWs:IsA("Folder") and #existingInWs:GetChildren() > 0 then
        return { existingInWs }
    end

    -- 2. Try loading from disk cache without reading 11MB into Lua memory via readfile
    local okCached, cachedObjs = pcall(function()
        if isfile and getCustomAsset and isfile(fileName) then
            return game:GetObjects(getCustomAsset(fileName))
        end
        return nil
    end)
    if okCached and type(cachedObjs) == "table" and #cachedObjs > 0 then
        return cachedObjs
    end

    -- 3. Download from GitHub via Delta-safe HTTP fetcher, write to disk, and load via GetObjects
    local okDownload, dlObjs = pcall(function()
        if writefile and getCustomAsset then
            local raw = SafeHttpGet(url)
            if raw and #raw > 100 then
                writefile(fileName, raw)
                return game:GetObjects(getCustomAsset(fileName))
            end
        end
        return nil
    end)
    return (okDownload and dlObjs) or nil
end

local AnimFolder, MorphsFolder, EmotesFolder, SoundsFolder

local function ExtractPackFolder(objs, expectedName)
    if not objs then return nil end
    for _, obj in ipairs(objs) do
        if obj.Name == expectedName and obj:IsA("Folder") then
            return obj
        end
    end
    return objs[1]
end

local function MountLoadedFolder(folder, expectedName, anchorParts)
    if not folder then return end
    local old = Workspace:FindFirstChild(expectedName)
    if old and old ~= folder then
        pcall(function() old:Destroy() end)
    end
    if anchorParts then
        for _, d in ipairs(folder:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = true
            end
        end
    end
    folder.Parent = Workspace
end

-- Fast check: if files are already cached on disk or in Workspace, load immediately;
-- otherwise load asynchronously after UI is shown so Delta never freezes on startup!
local function AreAllPacksCached()
    if Workspace:FindFirstChild("Anim") and Workspace:FindFirstChild("Morphs") and Workspace:FindFirstChild("Emotes") then
        return true
    end
    local ok, cached = pcall(function()
        return isfile and isfile(AssetFiles.Anims) and isfile(AssetFiles.Morphs) and isfile(AssetFiles.Emotes)
    end)
    return ok and cached == true
end

if AreAllPacksCached() then
    AnimFolder   = ExtractPackFolder(LoadAssetPack(AssetUrls.Anims,  AssetFiles.Anims,  "Anim"),   "Anim")
    MorphsFolder = ExtractPackFolder(LoadAssetPack(AssetUrls.Morphs, AssetFiles.Morphs, "Morphs"), "Morphs")
    EmotesFolder = ExtractPackFolder(LoadAssetPack(AssetUrls.Emotes, AssetFiles.Emotes, "Emotes"), "Emotes")
    SoundsFolder = ExtractPackFolder(LoadAssetPack(AssetUrls.Sounds, AssetFiles.Sounds, "Sounds"), "Sounds")
    MountLoadedFolder(AnimFolder,   "Anim",   false)
    MountLoadedFolder(MorphsFolder, "Morphs", true)
    MountLoadedFolder(EmotesFolder, "Emotes", false)
    MountLoadedFolder(SoundsFolder, "Sounds", false)
end

-- ============================================================================
-- 5. UNIVERSAL R15 / R6 RIG BRIDGE & MORPH ENGINE
-- ============================================================================
local R15PartNames = {
    "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local ForceClientR6Enabled = false
local ActiveDisguiseUsername = ""

local R15ToR6LimbMap = {
    UpperTorso     = "Torso",
    LowerTorso     = "Torso",
    LeftUpperArm   = "Left Arm",
    LeftLowerArm   = "Left Arm",
    LeftHand       = "Left Arm",
    RightUpperArm  = "Right Arm",
    RightLowerArm  = "Right Arm",
    RightHand      = "Right Arm",
    LeftUpperLeg   = "Left Leg",
    LeftLowerLeg   = "Left Leg",
    LeftFoot       = "Left Leg",
    RightUpperLeg  = "Right Leg",
    RightLowerLeg  = "Right Leg",
    RightFoot      = "Right Leg",
}

local AttachmentToR6Limb = {
    HatAttachment           = "Head",
    HairAttachment          = "Head",
    FaceFrontAttachment     = "Head",
    FaceCenterAttachment    = "Head",
    NeckAttachment          = "Torso",
    BodyFrontAttachment     = "Torso",
    BodyBackAttachment      = "Torso",
    WaistFrontAttachment    = "Torso",
    WaistBackAttachment     = "Torso",
    WaistCenterAttachment   = "Torso",
    LeftCollarAttachment    = "Torso",
    RightCollarAttachment   = "Torso",
    LeftShoulderAttachment  = "Left Arm",
    RightShoulderAttachment = "Right Arm",
    LeftGripAttachment      = "Left Arm",
    RightGripAttachment     = "Right Arm",
}

local function SetR6ClothingVisible(char, visible)
    if not char then return end
    local overlay = char:FindFirstChild("ROCONS_R6Clothing")
    if overlay then
        for _, p in ipairs(overlay:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Transparency = visible and 0 or 1
            end
        end
    end
    local avatarSkin = char:FindFirstChild("ROCONS_AvatarSkin")
    if avatarSkin then
        for _, p in ipairs(avatarSkin:GetChildren()) do
            if p:IsA("BasePart") and p.Name ~= "Head" and p.Name ~= "HumanoidRootPart" then
                p.Transparency = visible and 0 or 1
            end
        end
    end
    for _, limbName in ipairs({ "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
        local limb = char:FindFirstChild(limbName)
        if limb and limb:GetAttribute("ROCONS_R6BridgePart") then
            -- When overlay or avatarSkin is visible, hide raw bridge part so Shirt/Pants show cleanly
            limb.Transparency = ((overlay or avatarSkin) and visible) and 1 or 0
        end
    end
end

local function RebuildR6ClothingOverlay(char, hideOverlay)
    if not char or not char.Parent then return end
    local torso = char:FindFirstChild("Torso")
    if not torso or not torso:GetAttribute("ROCONS_R6BridgePart") then
        return
    end

    local old = char:FindFirstChild("ROCONS_R6Clothing")
    if old then old:Destroy() end

    local overlay = Instance.new("Model")
    overlay.Name = "ROCONS_R6Clothing"
    overlay:SetAttribute("ROCONS_R6BridgePart", true)

    local dummyHum = Instance.new("Humanoid")
    dummyHum.RigType = Enum.HumanoidRigType.R6
    dummyHum.PlatformStand = true
    dummyHum.AutoRotate = false
    dummyHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    dummyHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    pcall(function() dummyHum.EvaluateStateMachine = false end)
    dummyHum.Parent = overlay

    -- Clone Shirt, Pants, ShirtGraphic, BodyColors, CharacterMesh so Roblox's R6 Humanoid composites them natively!
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic")
            or item:IsA("BodyColors") or item:IsA("CharacterMesh") then
            local c = item:Clone()
            c.Parent = overlay
        end
    end

    for _, limbName in ipairs({ "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
        local srcLimb = char:FindFirstChild(limbName)
        if srcLimb and srcLimb:IsA("BasePart") then
            local vis = Instance.new("Part")
            vis.Name = limbName
            vis.Size = srcLimb.Size
            vis.Color = srcLimb.Color
            vis.Material = Enum.Material.SmoothPlastic
            vis.TopSurface = Enum.SurfaceType.Smooth
            vis.BottomSurface = Enum.SurfaceType.Smooth
            vis.CanCollide = false
            pcall(function() vis.CanTouch = false; vis.CanQuery = false end)
            vis.Massless = true
            vis.Anchored = false
            vis.Transparency = hideOverlay and 1 or 0
            vis.CFrame = srcLimb.CFrame
            vis.Parent = overlay

            local w = Instance.new("Weld")
            w.Name = "R6VisWeld"
            w.Part0 = srcLimb
            w.Part1 = vis
            w.C0 = CFrame.new()
            w.C1 = CFrame.new()
            w.Parent = vis
        end
    end

    overlay.Parent = char
    SetR6ClothingVisible(char, not hideOverlay)
end

local function RebindAccessoriesToR6Bridge(char)
    if not char then return end
    local attMap = {}
    for _, limbName in ipairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
        local limb = char:FindFirstChild(limbName)
        if limb then
            for _, c in ipairs(limb:GetChildren()) do
                if c:IsA("Attachment") then
                    attMap[c.Name] = c
                end
            end
        end
    end

    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") or acc:IsA("Hat") then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                for _, p in ipairs(acc:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.Anchored = false
                        p.CanCollide = false
                        p.Massless = true
                    end
                end
                local accAtt = handle:FindFirstChildOfClass("Attachment")
                local existingWeld = handle:FindFirstChild("AccessoryWeld") or handle:FindFirstChildOfClass("Weld")
                local curPart0 = existingWeld and existingWeld.Part0
                local r6LimbName = (curPart0 and R15ToR6LimbMap[curPart0.Name])
                    or (accAtt and AttachmentToR6Limb[accAtt.Name])

                if r6LimbName and r6LimbName ~= "Head" then
                    local targetLimb = char:FindFirstChild(r6LimbName)
                    if targetLimb and targetLimb:IsA("BasePart") then
                        if curPart0 and R15ToR6LimbMap[curPart0.Name] and handle:GetAttribute("ROCONS_OrigPart0Name") == nil then
                            handle:SetAttribute("ROCONS_OrigPart0Name", curPart0.Name)
                        end
                        if existingWeld then existingWeld:Destroy() end
                        for _, rc in ipairs(handle:GetChildren()) do
                            if rc:IsA("RigidConstraint") then rc:Destroy() end
                        end
                        local targetAtt = accAtt and attMap[accAtt.Name]
                        local w = Instance.new("Weld")
                        w.Name = "AccessoryWeld"
                        w.Part0 = targetLimb
                        w.Part1 = handle
                        if targetAtt and accAtt then
                            w.C0 = targetAtt.CFrame
                            w.C1 = accAtt.CFrame
                            handle.CFrame = targetLimb.CFrame * targetAtt.CFrame * accAtt.CFrame:Inverse()
                        else
                            w.C0 = CFrame.new()
                            w.C1 = CFrame.new()
                            handle.CFrame = targetLimb.CFrame
                        end
                        w.Parent = handle
                    end
                end
            end
        end
    end
end

-- Non-destructive R6 Bridge for R15 avatars: creates standard R6 limbs, R6 attachments,
-- Motor6Ds, native R6 Shirt/Pants overlay, and rebinds all accessories cleanly!
local function EnsureR6Bridge(char)
    if not char then return nil end
    if char:FindFirstChild("Torso") then
        if char:FindFirstChild("Torso"):GetAttribute("ROCONS_R6BridgePart") and not char:FindFirstChild("ROCONS_R6Clothing") then
            RebuildR6ClothingOverlay(char, false)
        end
        return char
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    if not hrp or not head then
        return char
    end

    local bc = char:FindFirstChildOfClass("BodyColors")
    local upperTorso = char:FindFirstChild("UpperTorso")
    local lArmR15 = char:FindFirstChild("LeftUpperArm")
    local rArmR15 = char:FindFirstChild("RightUpperArm")
    local lLegR15 = char:FindFirstChild("LeftUpperLeg")
    local rLegR15 = char:FindFirstChild("RightUpperLeg")

    local torsoColor    = (bc and bc.TorsoColor3)    or (upperTorso and upperTorso.Color) or head.Color
    local leftArmColor  = (bc and bc.LeftArmColor3)  or (lArmR15 and lArmR15.Color)       or head.Color
    local rightArmColor = (bc and bc.RightArmColor3) or (rArmR15 and rArmR15.Color)       or head.Color
    local leftLegColor  = (bc and bc.LeftLegColor3)  or (lLegR15 and lLegR15.Color)       or head.Color
    local rightLegColor = (bc and bc.RightLegColor3) or (rLegR15 and rLegR15.Color)       or head.Color

    -- Hide R15 visual mesh limbs while R6 bridge is mounted
    for _, name in ipairs(R15PartNames) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            if p:GetAttribute("ROCONS_OrigTrans") == nil then
                p:SetAttribute("ROCONS_OrigTrans", p.Transparency)
            end
            p.Transparency = 1
        end
    end

    local function makeLimb(name, size, color)
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.Color = color
        part.Material = Enum.Material.SmoothPlastic
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.CanCollide = false
        part.Massless = true
        part.Anchored = false
        part.CFrame = hrp.CFrame
        part:SetAttribute("ROCONS_R6BridgePart", true)
        part.Parent = char
        return part
    end

    local torso    = makeLimb("Torso",     Vector3.new(2, 2, 1), torsoColor)
    local leftArm  = makeLimb("Left Arm",  Vector3.new(1, 2, 1), leftArmColor)
    local rightArm = makeLimb("Right Arm", Vector3.new(1, 2, 1), rightArmColor)
    local leftLeg  = makeLimb("Left Leg",  Vector3.new(1, 2, 1), leftLegColor)
    local rightLeg = makeLimb("Right Leg", Vector3.new(1, 2, 1), rightLegColor)

    -- Standard R6 Attachments so all wings, bags, tails, collars, shoulders attach accurately
    local function makeAtt(parent, name, pos)
        local a = Instance.new("Attachment")
        a.Name = name
        a.Position = pos
        a.Parent = parent
        return a
    end
    makeAtt(torso, "NeckAttachment",        Vector3.new(0, 1, 0))
    makeAtt(torso, "BodyFrontAttachment",   Vector3.new(0, 0, -0.5))
    makeAtt(torso, "BodyBackAttachment",    Vector3.new(0, 0, 0.5))
    makeAtt(torso, "WaistFrontAttachment",  Vector3.new(0, -1, -0.5))
    makeAtt(torso, "WaistBackAttachment",   Vector3.new(0, -1, 0.5))
    makeAtt(torso, "WaistCenterAttachment", Vector3.new(0, -1, 0))
    makeAtt(torso, "LeftCollarAttachment",  Vector3.new(-1, 1, 0))
    makeAtt(torso, "RightCollarAttachment", Vector3.new(1, 1, 0))
    makeAtt(leftArm,  "LeftShoulderAttachment",  Vector3.new(0, 1, 0))
    makeAtt(leftArm,  "LeftGripAttachment",      Vector3.new(0, -1, 0))
    makeAtt(rightArm, "RightShoulderAttachment", Vector3.new(0, 1, 0))
    makeAtt(rightArm, "RightGripAttachment",     Vector3.new(0, -1, 0))

    local function makeMotor(name, parent, p0, p1, c0, c1)
        local m = Instance.new("Motor6D")
        m.Name = name
        m.Part0 = p0
        m.Part1 = p1
        m.C0 = c0
        m.C1 = c1
        m:SetAttribute("ROCONS_R6BridgeMotor", true)
        m.Parent = parent
        return m
    end

    makeMotor("RootJoint", hrp, hrp, torso,
        CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
        CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))

    local r15Neck = head:FindFirstChild("Neck")
    if r15Neck and r15Neck:IsA("Motor6D") then
        r15Neck.Enabled = false
    end

    makeMotor("Neck", torso, torso, head,
        CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
        CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))

    makeMotor("Right Shoulder", torso, torso, rightArm,
        CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
        CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))

    makeMotor("Left Shoulder", torso, torso, leftArm,
        CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
        CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

    makeMotor("Right Hip", torso, torso, rightLeg,
        CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
        CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))

    makeMotor("Left Hip", torso, torso, leftLeg,
        CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
        CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

    -- Disable R15 Animate script so it never fights with our Client R6 Animator
    local animScript = char:FindFirstChild("Animate")
    if animScript and animScript:IsA("LocalScript") then
        animScript:SetAttribute("ROCONS_R6DisabledAnimate", true)
        animScript.Disabled = true
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
            if not (t.Speed >= 10.8 and t.Speed < 105) then
                pcall(function() t:Stop(0) end)
            end
        end
    end

    -- Build native R6 Shirt/Pants/T-Shirt visual overlay + rebind all accessories to R6 limbs
    RebuildR6ClothingOverlay(char, false)
    RebindAccessoriesToR6Bridge(char)

    return char
end

local function RemoveR6Bridge(char, forceRemove)
    if not char then return end
    if char == LocalPlayer.Character and ForceClientR6Enabled and not forceRemove then
        RebuildR6ClothingOverlay(char, false)
        return
    end
    local torso = char:FindFirstChild("Torso")
    if not torso or not torso:GetAttribute("ROCONS_R6BridgePart") then
        return
    end

    local animScript = char:FindFirstChild("Animate")
    if animScript and animScript:IsA("LocalScript") and animScript:GetAttribute("ROCONS_R6DisabledAnimate") then
        animScript:SetAttribute("ROCONS_R6DisabledAnimate", nil)
        animScript.Disabled = false
    end

    -- Restore any rebound accessories back to their original R15 limbs first
    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") or acc:IsA("Hat") then
            local handle = acc:FindFirstChild("Handle")
            local origPartName = handle and handle:GetAttribute("ROCONS_OrigPart0Name")
            if handle and origPartName then
                local origPart = char:FindFirstChild(origPartName)
                local w = handle:FindFirstChild("AccessoryWeld") or handle:FindFirstChildOfClass("Weld")
                if origPart and origPart:IsA("BasePart") and w then
                    w.Part0 = origPart
                end
            end
        end
    end

    local overlay = char:FindFirstChild("ROCONS_R6Clothing")
    if overlay then overlay:Destroy() end

    for _, d in ipairs(char:GetDescendants()) do
        if d:GetAttribute("ROCONS_R6BridgeMotor") or d:GetAttribute("ROCONS_R6BridgePart") then
            d:Destroy()
        end
    end
    local head = char:FindFirstChild("Head")
    local r15Neck = head and head:FindFirstChild("Neck")
    if r15Neck and r15Neck:IsA("Motor6D") then
        r15Neck.Enabled = true
    end
    for _, name in ipairs(R15PartNames) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            local orig = p:GetAttribute("ROCONS_OrigTrans")
            p.Transparency = (orig ~= nil) and orig or 0
        end
    end
end

-- Client-Side Avatar Disguise: Deletes ALL old items & hides original Head/Torso/Arm/Leg,
-- then mounts target user's exact Head, Torso, Arms, Legs, Clothes & Accessories (R15 & R6)!
local function ApplyRobloxUserAvatar(targetInput)
    local char = LocalPlayer.Character
    if not char or not char.Parent then
        return false, "ตัวละครของคุณยังไม่พร้อม"
    end

    local trimmed = tostring(targetInput or ""):match("^%s*(.-)%s*$")
    if trimmed == "" then
        return false, "กรุณาใส่ชื่อผู้ใช้ Roblox หรือ UserId"
    end

    local resolvedUserId = tonumber(trimmed)
    local resolvedName = trimmed
    if not resolvedUserId then
        local okId, uid = pcall(function()
            return Players:GetUserIdFromNameAsync(trimmed)
        end)
        if not okId or not uid then
            return false, "ไม่พบชื่อผู้ใช้ Roblox: " .. trimmed
        end
        resolvedUserId = uid
    else
        pcall(function()
            resolvedName = Players:GetNameFromUserIdAsync(resolvedUserId)
        end)
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local isR6 = ForceClientR6Enabled
        or (hum and hum.RigType == Enum.HumanoidRigType.R6)
        or (char:FindFirstChild("Torso") ~= nil and not char:FindFirstChild("UpperTorso"))
    local rigEnum = isR6 and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15

    local refModel
    local okDesc, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(resolvedUserId)
    end)
    if okDesc and desc then
        pcall(function()
            refModel = Players:CreateHumanoidModelFromDescription(desc, rigEnum)
        end)
    end
    if not refModel then
        pcall(function()
            refModel = Players:CreateHumanoidModelFromUserId(resolvedUserId, rigEnum)
        end)
    end
    if not refModel then
        return false, "ไม่สามารถโหลดข้อมูลตัวละครของ @" .. resolvedName .. " ได้"
    end

    -- STEP 1: Delete ALL old cosmetic items on the user's character FIRST before morphing
    MyMorphed = false
    if MorphToggleBtn then
        MorphToggleBtn.Text = "แปลงร่าง: ปิด"
    end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Accessory") or child:IsA("Hat") or child:IsA("Shirt") or child:IsA("Pants")
            or child:IsA("ShirtGraphic") or child:IsA("BodyColors") or child:IsA("CharacterMesh")
            or child:IsA("Model") or child:IsA("Folder") then
            if child.Name ~= "Animate" and child.Name ~= "Health" then
                pcall(function() child:Destroy() end)
            end
        end
    end
    local myHeadPre = char:FindFirstChild("Head")
    if myHeadPre then
        myHeadPre.Transparency = 1
        for _, c in ipairs(myHeadPre:GetChildren()) do
            if c:IsA("Decal") or c:IsA("Texture") or c:IsA("SpecialMesh") or c:IsA("DataModelMesh")
                or c:IsA("SurfaceAppearance") or c:IsA("FaceControls") then
                pcall(function() c:Destroy() end)
            end
        end
    end
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            p.Transparency = 1
            for _, sub in ipairs(p:GetChildren()) do
                if sub:IsA("SurfaceAppearance") or sub:IsA("WrapTarget") or sub:IsA("CharacterMesh") then
                    pcall(function() sub:Destroy() end)
                end
            end
        end
    end
    task.wait() -- Let Roblox detach all old accessory welds cleanly before mounting new ones

    if ForceClientR6Enabled then
        EnsureR6Bridge(char)
        for _, limbName in ipairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
            local lp = char:FindFirstChild(limbName)
            if lp and lp:IsA("BasePart") then lp.Transparency = 1 end
        end
    end

    -- STEP 2: Copy BodyColors, Shirt, Pants, ShirtGraphic onto char (for skin/morph reference)
    for _, child in ipairs(refModel:GetChildren()) do
        if child:IsA("BodyColors") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
            local clone = child:Clone()
            clone.Parent = char
        end
    end

    local refHead = refModel:FindFirstChild("Head")
    local refBC = refModel:FindFirstChildOfClass("BodyColors")
    local limbColorMap = {
        ["Torso"]          = refBC and refBC.TorsoColor3    or (refHead and refHead.Color),
        ["UpperTorso"]     = refBC and refBC.TorsoColor3    or (refHead and refHead.Color),
        ["LowerTorso"]     = refBC and refBC.TorsoColor3    or (refHead and refHead.Color),
        ["Left Arm"]       = refBC and refBC.LeftArmColor3  or (refHead and refHead.Color),
        ["LeftUpperArm"]   = refBC and refBC.LeftArmColor3  or (refHead and refHead.Color),
        ["LeftLowerArm"]   = refBC and refBC.LeftArmColor3  or (refHead and refHead.Color),
        ["LeftHand"]       = refBC and refBC.LeftArmColor3  or (refHead and refHead.Color),
        ["Right Arm"]      = refBC and refBC.RightArmColor3 or (refHead and refHead.Color),
        ["RightUpperArm"]  = refBC and refBC.RightArmColor3 or (refHead and refHead.Color),
        ["RightLowerArm"]  = refBC and refBC.RightArmColor3 or (refHead and refHead.Color),
        ["RightHand"]      = refBC and refBC.RightArmColor3 or (refHead and refHead.Color),
        ["Left Leg"]       = refBC and refBC.LeftLegColor3  or (refHead and refHead.Color),
        ["LeftUpperLeg"]   = refBC and refBC.LeftLegColor3  or (refHead and refHead.Color),
        ["LeftLowerLeg"]   = refBC and refBC.LeftLegColor3  or (refHead and refHead.Color),
        ["LeftFoot"]       = refBC and refBC.LeftLegColor3  or (refHead and refHead.Color),
        ["Right Leg"]      = refBC and refBC.RightLegColor3 or (refHead and refHead.Color),
        ["RightUpperLeg"]  = refBC and refBC.RightLegColor3 or (refHead and refHead.Color),
        ["RightLowerLeg"]  = refBC and refBC.RightLegColor3 or (refHead and refHead.Color),
        ["RightFoot"]      = refBC and refBC.RightLegColor3 or (refHead and refHead.Color),
    }
    for partName, col in pairs(limbColorMap) do
        local p = char:FindFirstChild(partName)
        if p and p:IsA("BasePart") and col then
            p.Color = col
        end
    end

    -- STEP 3: Sync Humanoid body scales (height/width/depth/head) & build ROCONS_AvatarSkin
    local refHum = refModel:FindFirstChildOfClass("Humanoid")
    if hum and refHum and not isR6 then
        for _, scaleName in ipairs({ "BodyDepthScale", "BodyHeightScale", "BodyProportionScale", "BodyTypeScale", "BodyWidthScale", "HeadScale" }) do
            local rScale = refHum:FindFirstChild(scaleName)
            local mScale = hum:FindFirstChild(scaleName)
            if rScale and rScale:IsA("NumberValue") then
                if mScale and mScale:IsA("NumberValue") then
                    mScale.Value = rScale.Value
                else
                    local nv = Instance.new("NumberValue")
                    nv.Name = scaleName
                    nv.Value = rScale.Value
                    nv.Parent = hum
                end
            end
        end
    end

    local skinModel = Instance.new("Model")
    skinModel.Name = "ROCONS_AvatarSkin"

    local skinHum = Instance.new("Humanoid")
    skinHum.RigType = rigEnum
    skinHum.PlatformStand = true
    skinHum.AutoRotate = false
    skinHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    skinHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    pcall(function() skinHum.EvaluateStateMachine = false end)
    skinHum.Parent = skinModel

    for _, child in ipairs(refModel:GetChildren()) do
        if child:IsA("BodyColors") or child:IsA("Shirt") or child:IsA("Pants")
            or child:IsA("ShirtGraphic") or child:IsA("CharacterMesh") then
            local c = child:Clone()
            c.Parent = skinModel
        end
    end

    local bodyPartNames = isR6
        and { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
        or { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }

    for _, partName in ipairs(bodyPartNames) do
        local targetLimb = char:FindFirstChild(partName)
        local refLimb = refModel:FindFirstChild(partName)
        if targetLimb and targetLimb:IsA("BasePart") and refLimb and refLimb:IsA("BasePart") then
            local vis = refLimb:Clone()
            -- Keep only visual children (Mesh, Decal, SurfaceAppearance, FaceControls); strip joints/scripts
            for _, sub in ipairs(vis:GetChildren()) do
                if sub:IsA("Motor6D") or sub:IsA("Weld") or sub:IsA("WeldConstraint")
                    or sub:IsA("Attachment") or sub:IsA("Script") or sub:IsA("LocalScript") then
                    sub:Destroy()
                end
            end
            vis.Anchored = false
            vis.CanCollide = false
            pcall(function() vis.CanTouch = false; vis.CanQuery = false end)
            vis.Massless = true
            vis.Transparency = 0
            vis.CFrame = targetLimb.CFrame
            vis.Parent = skinModel

            local w = Instance.new("Weld")
            w.Name = "SkinWeld"
            w.Part0 = targetLimb
            w.Part1 = vis
            w.C0 = CFrame.new()
            w.C1 = CFrame.new()
            w.Parent = vis
        end
    end

    skinModel.Parent = char

    -- STEP 4: Build attachment lookup from refModel's exact limb proportions (so hats/hair sit at exact height!)
    local attachmentLookup = {}
    local refAttLookup = {}
    local myHead = char:FindFirstChild("Head")
    for _, pName in ipairs(bodyPartNames) do
        local part = char:FindFirstChild(pName)
        if part and part:IsA("BasePart") then
            for _, c in ipairs(part:GetChildren()) do
                if c:IsA("Attachment") then
                    attachmentLookup[c.Name] = c
                end
            end
        end
        local rPart = refModel:FindFirstChild(pName)
        if rPart and rPart:IsA("BasePart") and part and part:IsA("BasePart") then
            for _, c in ipairs(rPart:GetChildren()) do
                if c:IsA("Attachment") then
                    refAttLookup[c.Name] = { Limb = part, CFrame = c.CFrame }
                end
            end
        end
    end

    -- STEP 5: Clone, unanchor ALL descendants, and weld every Accessory cleanly to char
    for _, acc in ipairs(refModel:GetChildren()) do
        if acc:IsA("Accessory") or acc:IsA("Hat") then
            local accClone = acc:Clone()
            for _, d in ipairs(accClone:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Anchored = false
                    d.CanCollide = false
                    pcall(function() d.CanTouch = false; d.CanQuery = false end)
                    d.Massless = true
                elseif d:IsA("RigidConstraint") then
                    d:Destroy()
                elseif d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
                    if not (d.Part0 and d.Part1 and d.Part0:IsDescendantOf(accClone) and d.Part1:IsDescendantOf(accClone)) then
                        d:Destroy()
                    end
                end
            end

            local handle = accClone:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                local accAtt = handle:FindFirstChildOfClass("Attachment")
                local refAttInfo = accAtt and refAttLookup[accAtt.Name]
                local charAtt = accAtt and attachmentLookup[accAtt.Name]
                local fallbackLimbName = accAtt and AttachmentToR6Limb[accAtt.Name]
                local targetPart = (refAttInfo and refAttInfo.Limb)
                    or (charAtt and charAtt.Parent)
                    or (fallbackLimbName and char:FindFirstChild(fallbackLimbName))
                    or myHead
                    or char:FindFirstChild("Torso")
                    or char:FindFirstChild("UpperTorso")

                if targetPart and targetPart:IsA("BasePart") then
                    local w = Instance.new("Weld")
                    w.Name = "AccessoryWeld"
                    w.Part0 = targetPart
                    w.Part1 = handle
                    local c0CF = (refAttInfo and refAttInfo.CFrame) or (charAtt and charAtt.CFrame)
                    if c0CF and accAtt then
                        w.C0 = c0CF
                        w.C1 = accAtt.CFrame
                        handle.CFrame = targetPart.CFrame * c0CF * accAtt.CFrame:Inverse()
                    else
                        w.C0 = CFrame.new()
                        w.C1 = CFrame.new()
                        handle.CFrame = targetPart.CFrame
                    end
                    w.Parent = handle
                end
            end
            accClone.Parent = char
        end
    end

    pcall(function() refModel:Destroy() end)
    ActiveDisguiseUsername = resolvedName
    return true, resolvedName
end

local function UnfreezeCharacter(char)
    if not char then return end
    local animScript = char:FindFirstChild("Animate")
    if animScript and animScript:IsA("LocalScript") then
        animScript.Disabled = false
    end
    local collideRestore = {
        Head = true, Torso = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true,
    }
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = false
            d.AssemblyLinearVelocity = Vector3.zero
            d.AssemblyAngularVelocity = Vector3.zero
            if collideRestore[d.Name] and not d:GetAttribute("ROCONS_R6BridgePart") then
                d.CanCollide = true
            end
        elseif d:IsA("Motor6D") then
            d.Transform = CFrame.new()
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.PlatformStand = false
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, true) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true) end)
        hum.AutoRotate = true
        hum.WalkSpeed = 16
        pcall(function() hum.JumpPower = 50 end)
        pcall(function() hum.JumpHeight = 7.2 end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

local UVMorph = {
    Genders = { F = true, FF = true },
    ModelName = "ROCONS_UV",
    ClothTransparency = 0.05,
    ClothTint = Color3.new(1, 1, 1),
    WarnedMissing = {},
}

function UVMorph.Remove(char)
    if not char then return end
    local m = char:FindFirstChild(UVMorph.ModelName)
    while m do
        m:Destroy()
        m = char:FindFirstChild(UVMorph.ModelName)
    end
end

function UVMorph.Refresh(char, uvModel)
    local cloth = uvModel:FindFirstChild("Cloth")
    local torso = char:FindFirstChild("Torso")
    local shirt = char:FindFirstChildOfClass("Shirt")
    local template = (shirt and shirt.ShirtTemplate) or ""

    if cloth then
        if template ~= "" then
            if cloth.TextureID ~= template then
                cloth.TextureID = template
            end
            cloth.Color = UVMorph.ClothTint
            cloth.Transparency = UVMorph.ClothTransparency
        else
            if cloth.TextureID ~= "" then
                cloth.TextureID = ""
            end
            cloth.Transparency = 1
        end
    end

    if torso then
        for _, child in ipairs(uvModel:GetChildren()) do
            if child:IsA("BasePart") and child:GetAttribute("Skin") then
                if child.Color ~= torso.Color then
                    child.Color = torso.Color
                end
            end
        end
    end
end

function UVMorph.Apply(char, gender)
    if not char or not UVMorph.Genders[gender] then return end
    EnsureR6Bridge(char)
    local torso = char:FindFirstChild("Torso")
    if not torso then return end

    local existing = char:FindFirstChild(UVMorph.ModelName)
    if existing then
        if existing:GetAttribute("Gender") == gender then
            UVMorph.Refresh(char, existing)
            return
        end
        existing:Destroy()
    end

    local uvRoot = MorphsFolder and MorphsFolder:FindFirstChild("UV")
    local genderFolder = uvRoot and uvRoot:FindFirstChild(gender)
    local basePart = genderFolder and genderFolder:FindFirstChild("Base")
    if not basePart then return end

    local model = Instance.new("Model")
    model.Name = UVMorph.ModelName
    model:SetAttribute("Gender", gender)

    for _, part in ipairs(genderFolder:GetChildren()) do
        if part:IsA("BasePart") and part ~= basePart then
            local clone = part:Clone()
            local rel = basePart.CFrame:ToObjectSpace(part.CFrame)
            clone.Anchored = false
            clone.CanCollide = false
            clone.CanTouch = false
            clone.CanQuery = false
            clone.Massless = true
            clone.CFrame = torso.CFrame * rel

            local weld = Instance.new("Weld")
            weld.Name = "UVWeld"
            weld.Part0 = torso
            weld.Part1 = clone
            weld.C0 = rel
            weld.Parent = clone
            clone.Parent = model
        end
    end

    UVMorph.Refresh(char, model)
    model.Parent = char
end

local function RemoveMorph(char)
    if not char then return end
    UVMorph.Remove(char)
    local m = char:FindFirstChild("Morph")
    if m then m:Destroy() end
    local cf = char:FindFirstChild("ClothFolder")
    if cf then
        for _, item in ipairs(cf:GetChildren()) do
            item.Parent = char
        end
        cf:Destroy()
    end
    for _, limbName in ipairs({ "Torso", "Left Leg", "Right Leg" }) do
        local limb = char:FindFirstChild(limbName)
        if limb then limb.Transparency = 0 end
    end
    -- Restore Client R6 clothing overlay if Client R6 mode is active
    if char:FindFirstChild("Torso") and char.Torso:GetAttribute("ROCONS_R6BridgePart") then
        RebuildR6ClothingOverlay(char, false)
    end
    UnfreezeCharacter(char)
end

local function ResetCharacterAfterSync(char, keepMorph)
    if not char then return end
    if not keepMorph then
        RemoveMorph(char)
    else
        UnfreezeCharacter(char)
    end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("NoCollisionConstraint") and d.Name == "ROCONS_NoCollide" then
            d:Destroy()
        end
    end
    local animScript = char:FindFirstChild("Animate")
    if animScript then
        animScript.Disabled = false
    end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Motor6D") then
            d.Transform = CFrame.new()
        end
    end
    if not keepMorph then
        RemoveR6Bridge(char)
    end
end

local function ApplyMorph(char, morphTemplate, gender, keepClothes)
    if not char or not morphTemplate then return end
    EnsureR6Bridge(char)
    local torso = char:FindFirstChild("Torso")
    if not torso then return end

    UVMorph.Remove(char)
    RemoveMorph(char)

    local morph = morphTemplate:Clone()
    morph.Name = "Morph"
    morph:SetAttribute("ROCONS_MorphGender", tostring(gender or ""))

    local clothFolder = char:FindFirstChild("ClothFolder")
    if not clothFolder then
        clothFolder = Instance.new("Folder")
        clothFolder.Name = "ClothFolder"
        clothFolder.Parent = char
    end

    if not keepClothes then
        -- Hide Client R6 clothing overlay ONLY while morphed/synced
        SetR6ClothingVisible(char, false)
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Clothing") or child:IsA("ShirtGraphic") then
                child.Parent = clothFolder
            end
        end
    end

    local leftLeg = char:FindFirstChild("Left Leg")
    local rightLeg = char:FindFirstChild("Right Leg")

    for _, d in ipairs(morph:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = false
            d.CanCollide = false
            pcall(function() d.CanTouch = false; d.CanQuery = false end)
            d.Massless = true
            if d:GetAttribute("Skin") then
                d.Color = torso.Color
            end
        elseif d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("WeldConstraint") then
            local p0Valid = d.Part0 and (d.Part0:IsDescendantOf(char) or d.Part0:IsDescendantOf(morph))
            if d.Parent == morph or not p0Valid then
                if d.Part1 and d.Part1.Name:match("Left") and d.Part1.Name:match("Leg") and leftLeg then
                    d.Part0 = leftLeg
                elseif d.Part1 and d.Part1.Name:match("Right") and d.Part1.Name:match("Leg") and rightLeg then
                    d.Part0 = rightLeg
                else
                    d.Part0 = torso
                end
                if gender == "FB" and (d:IsA("Weld") or d:IsA("Motor6D")) and d.Part1 and (d.Part1.Name == "Torso" or d.Part1.Name == "UpperTorso") then
                    d.C0 = d.C0 * CFrame.Angles(0, math.rad(180), 0)
                end
            end
        end
    end

    if gender == "FB" then
        for _, d in ipairs(morph:GetDescendants()) do
            if d:IsA("Weld") or d:IsA("Motor6D") then
                local hit = d.Name:match("Hip") or d.Name:match("Leg") or (d.Part1 and d.Part1.Name:match("Leg"))
                if hit then
                    d.C0 = d.C0 * CFrame.Angles(math.rad(180), 0, 0)
                end
            end
        end
    end

    if not keepClothes then
        torso.Transparency = (gender == "M") and 0 or 1
    else
        local mt = morph:FindFirstChild("Torso")
        if mt then mt:Destroy() end
    end

    for _, child in ipairs(morph:GetChildren()) do
        local nll = child:FindFirstChild("NewLeftLeg")
        if nll and leftLeg then
            nll.Anchored = false
            nll.CFrame = leftLeg.CFrame
            local wc = nll:FindFirstChild("WeldConstraint")
            if wc then wc.Part0 = leftLeg end
            leftLeg.Transparency = 1
        end
        local nrl = child:FindFirstChild("NewRightLeg")
        if nrl and rightLeg then
            nrl.Anchored = false
            nrl.CFrame = rightLeg.CFrame
            local wc = nrl:FindFirstChild("WeldConstraint")
            if wc then wc.Part0 = rightLeg end
            rightLeg.Transparency = 1
        end
    end

    local allDesc = morph:GetDescendants()
    for _, part in ipairs(allDesc) do
        if part:IsA("BasePart") then
            part.Anchored = false
            local hasValidJoint = false
            for _, j in ipairs(allDesc) do
                if (j:IsA("WeldConstraint") or j:IsA("Weld") or j:IsA("Motor6D"))
                    and j.Part0 and j.Part1
                    and (j.Part0:IsDescendantOf(char) or j.Part0:IsDescendantOf(morph))
                    and (j.Part1:IsDescendantOf(char) or j.Part1:IsDescendantOf(morph))
                    and (j.Part0 == part or j.Part1 == part) then
                    hasValidJoint = true
                    break
                end
            end
            if not hasValidJoint then
                local targetLimb = torso
                if part.Name:match("Left") and part.Name:match("Leg") and leftLeg then
                    targetLimb = leftLeg
                elseif part.Name:match("Right") and part.Name:match("Leg") and rightLeg then
                    targetLimb = rightLeg
                end
                part.CFrame = targetLimb.CFrame
                local wc = Instance.new("WeldConstraint")
                wc.Part0 = targetLimb
                wc.Part1 = part
                wc.Parent = part
            end
        end
    end

    -- Ensure all accessories on char stay unanchored & welded properly after morph
    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") or acc:IsA("Hat") then
            for _, p in ipairs(acc:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                end
            end
        end
    end

    morph.Parent = char
end

local function CreateNoCollide(charA, charB)
    if not charA or not charB then return end
    for _, p0 in ipairs(charA:GetDescendants()) do
        if p0:IsA("BasePart") then
            for _, p1 in ipairs(charB:GetDescendants()) do
                if p1:IsA("BasePart") then
                    local nc = Instance.new("NoCollisionConstraint")
                    nc.Name = "ROCONS_NoCollide"
                    nc.Part0 = p0
                    nc.Part1 = p1
                    nc.Parent = p0
                end
            end
        end
    end
end

-- ============================================================================
-- 6. KEYFRAMESEQUENCE ANIMATION ENGINE (60 FPS Motor6D Interpolator)
-- ============================================================================
local function CompileKeyframeSequence(char, kfSeq)
    if not char or not kfSeq then return nil end
    EnsureR6Bridge(char)

    local motorMap = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Motor6D") and d.Part1 then
            motorMap[d.Part1.Name] = d
            motorMap[d.Name] = d
        end
    end

    local keyframes = {}
    for _, child in ipairs(kfSeq:GetChildren()) do
        if child:IsA("Keyframe") and type(child.Time) == "number" and child.Time >= 0 then
            table.insert(keyframes, child)
        end
    end
    table.sort(keyframes, function(a, b) return a.Time < b.Time end)
    if #keyframes == 0 then return nil end

    local activeMotors = {}
    local seenMotors = {}

    local function collectPoses(pose, outMap)
        local m = motorMap[pose.Name]
        if m then
            local cf = CFrame.new()
            local style = Enum.PoseEasingStyle.Linear
            local dir = Enum.PoseEasingDirection.In
            pcall(function() cf = pose.CFrame end)
            pcall(function() style = pose.EasingStyle end)
            pcall(function() dir = pose.EasingDirection end)
            outMap[m] = { CFrame = cf, Style = style, Direction = dir }
            if not seenMotors[m] then
                seenMotors[m] = true
                table.insert(activeMotors, m)
            end
        end
        local ok, subPoses = pcall(function() return pose:GetSubPoses() end)
        if not ok or type(subPoses) ~= "table" then
            subPoses = {}
            for _, c in ipairs(pose:GetChildren()) do
                if c:IsA("Pose") then table.insert(subPoses, c) end
            end
        end
        for _, sp in ipairs(subPoses) do
            collectPoses(sp, outMap)
        end
    end

    local frames = {}
    for _, kf in ipairs(keyframes) do
        local poseMap = {}
        local ok, rootPoses = pcall(function() return kf:GetPoses() end)
        if ok and type(rootPoses) == "table" then
            for _, rp in ipairs(rootPoses) do
                collectPoses(rp, poseMap)
            end
        else
            for _, rp in ipairs(kf:GetChildren()) do
                if rp:IsA("Pose") then collectPoses(rp, poseMap) end
            end
        end
        if frames[#frames] and math.abs(frames[#frames].Time - kf.Time) < 1e-6 then
            frames[#frames].Poses = poseMap
        else
            table.insert(frames, { Time = kf.Time, Poses = poseMap })
        end
    end

    if #frames == 0 or #activeMotors == 0 then return nil end
    if frames[1].Time > 0 then frames[1].Time = 0 end

    local isLoop = true
    pcall(function() isLoop = (kfSeq.Loop == true) end)

    return {
        Frames = frames,
        Motors = activeMotors,
        Duration = frames[#frames].Time,
        Loop = isLoop,
    }
end

local function IsP2PCarrierTrack(t)
    local ok, spd = pcall(function() return t.Speed end)
    return ok and type(spd) == "number" and spd >= 10.8 and spd < 105
end

local function StopNonCarrierAnimatorTracks(char)
    if not char then return end
    local animScript = char:FindFirstChild("Animate")
    if animScript and animScript:IsA("LocalScript") then
        animScript.Disabled = true
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
            if not IsP2PCarrierTrack(t) then
                pcall(function() t:Stop(0) end)
            end
        end
    end
end

local ActiveKeyframeTrackByChar = setmetatable({}, { __mode = "k" })

local function PlayKeyframeAnim(char, kfSeq, speed)
    if char and ActiveKeyframeTrackByChar[char] then
        local prevTrack = ActiveKeyframeTrackByChar[char]
        ActiveKeyframeTrackByChar[char] = nil
        pcall(function() prevTrack.Stop() end)
    end
    local track = {
        Speed = math.clamp(tonumber(speed) or 1, 0.05, 8),
        Stop = function() end,
    }
    if not char or not char.Parent then return track end
    local compiled = CompileKeyframeSequence(char, kfSeq)
    if not compiled then return track end

    local animScript = char:FindFirstChild("Animate")
    StopNonCarrierAnimatorTracks(char)

    local running = true
    local elapsed = 0
    local conn

    local function resetMotors()
        for _, m in ipairs(compiled.Motors) do
            if m and m.Parent then
                m.Transform = CFrame.new()
            end
        end
        if animScript and animScript.Parent then
            animScript.Disabled = false
        end
    end

    function track.Stop()
        if not running then return end
        running = false
        if ActiveKeyframeTrackByChar[char] == track then
            ActiveKeyframeTrackByChar[char] = nil
        end
        if conn then
            conn:Disconnect()
            conn = nil
        end
        resetMotors()
    end
    ActiveKeyframeTrackByChar[char] = track

    local styleMap = {
        Linear  = Enum.EasingStyle.Linear,
        Elastic = Enum.EasingStyle.Elastic,
        Cubic   = Enum.EasingStyle.Cubic,
        CubicV2 = Enum.EasingStyle.Cubic,
        Bounce  = Enum.EasingStyle.Bounce,
    }
    local dirMap = {
        In    = Enum.EasingDirection.In,
        Out   = Enum.EasingDirection.Out,
        InOut = Enum.EasingDirection.InOut,
    }

    local function evalAlpha(alpha, styleEnum, dirEnum)
        local sName = (styleEnum and styleEnum.Name) or "Linear"
        local dName = (dirEnum and dirEnum.Name) or "In"
        if sName == "Constant" then
            if dName == "Out" then return (alpha > 0) and 1 or 0 end
            if dName == "InOut" then return (alpha >= 0.5) and 1 or 0 end
            return (alpha >= 1) and 1 or 0
        end
        local tsStyle = styleMap[sName] or Enum.EasingStyle.Linear
        local tsDir = dirMap[dName] or Enum.EasingDirection.In
        local ok, val = pcall(TweenService.GetValue, TweenService, alpha, tsStyle, tsDir)
        return (ok and val) or alpha
    end

    local function applyFramePair(f0, f1, alpha)
        for _, m in ipairs(compiled.Motors) do
            if m and m.Parent then
                local p0 = f0.Poses[m]
                local p1 = f1.Poses[m]
                local cf0 = (p0 and p0.CFrame) or CFrame.new()
                local cf1 = (p1 and p1.CFrame) or cf0
                local a = p0 and evalAlpha(alpha, p0.Style, p0.Direction) or alpha
                m.Transform = cf0:Lerp(cf1, math.clamp(a, 0, 1))
            end
        end
    end

    local function sampleFrames(t)
        local fr = compiled.Frames
        if #fr == 1 or t <= fr[1].Time then
            return fr[1], fr[1], 0
        end
        for i = 1, #fr - 1 do
            local a, b = fr[i], fr[i + 1]
            if t <= b.Time then
                local span = b.Time - a.Time
                local ratio = (span > 0) and math.clamp((t - a.Time) / span, 0, 1) or 1
                return a, b, ratio
            end
        end
        return fr[#fr], fr[#fr], 0
    end

    if compiled.Duration <= 0 or #compiled.Frames == 1 then
        applyFramePair(compiled.Frames[#compiled.Frames], compiled.Frames[#compiled.Frames], 0)
        return track
    end

    local stopping = false
    local stepSignal = RunService.Stepped or RunService.Heartbeat
    conn = stepSignal:Connect(function(arg1, arg2)
        if not running then return end
        if not char.Parent then
            track.Stop()
            return
        end
        StopNonCarrierAnimatorTracks(char)
        local dt = tonumber(arg2) or tonumber(arg1) or (1 / 60)
        elapsed += math.max(dt, 0) * track.Speed
        if compiled.Loop then
            elapsed = elapsed % compiled.Duration
        elseif elapsed >= compiled.Duration then
            applyFramePair(compiled.Frames[#compiled.Frames], compiled.Frames[#compiled.Frames], 0)
            if not stopping then
                stopping = true
                task.delay(0.12, track.Stop)
            end
            return
        end
        local f0, f1, a = sampleFrames(elapsed)
        applyFramePair(f0, f1, a)
    end)

    return track
end

-- ============================================================================
-- 7. OVERHEAD RANK EFFECTS, CHAT BUBBLES & BOT SPAWNER
-- ============================================================================
local function ApplyRankLabelEffect(label, rankTitle)
    if not label then return end
    local titleStr = tostring(rankTitle or "")
    if label:GetAttribute("AppliedRank") == titleStr then return end
    label:SetAttribute("AppliedRank", titleStr)

    for _, child in ipairs(label:GetChildren()) do
        if child.Name:match("CustomEffect_") or child:IsA("UIGradient") then
            child:Destroy()
        end
    end

    if titleStr == "" then
        label.Visible = false
        return
    end

    label.Visible = true
    label.TextColor3 = RankConfig.Colors[titleStr] or Color3.fromRGB(255, 255, 255)
    label.Text = titleStr

    if titleStr == "Obfuscator" then
        local g = Instance.new("UIGradient")
        g.Name = "CustomEffect_Gradient"
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 85, 255)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 85, 255)),
        })
        g.Offset = Vector2.new(-0.6, 0)
        g.Parent = label
        TweenService:Create(g, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.6, 0) }):Play()
    elseif titleStr:match("Artist") then
        label.Text = "Artist 🎨"
        local g = Instance.new("UIGradient")
        g.Name = "CustomEffect_Rainbow"
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 127, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(75, 0, 130)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
        })
        g.Offset = Vector2.new(-0.5, 0)
        g.Parent = label
        TweenService:Create(g, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.5, 0) }):Play()
    elseif titleStr:match("Bug Finder") then
        label.Text = "Bug Finder 🐞"
    end
end

local ActiveBubblesByPlayer = {}

local function RestackBubbles(list)
    local offsetPx = 0
    for i = #list, 1, -1 do
        local b = list[i]
        if b.Gui and b.Gui.Parent then
            b.Gui.StudsOffset = Vector3.new(0, 4.1 + (offsetPx / 28), 0)
            offsetPx += (b.PixelHeight or 42) + 6
        end
    end
end

local function ShowChatBubble(plr, text)
    if not plr or not plr.Character or type(text) ~= "string" or text:match("^%s*$") then return end
    local head = plr.Character:FindFirstChild("Head")
    if not head then return end

    local list = ActiveBubblesByPlayer[plr.Name]
    if not list then
        list = {}
        ActiveBubblesByPlayer[plr.Name] = list
    end
    while #list >= 3 do
        local oldest = table.remove(list, 1)
        if oldest and oldest.Gui then oldest.Gui:Destroy() end
    end

    local cleanText = text:sub(1, 140)
    local textBounds = TextService:GetTextSize(cleanText, 18, UI.BubbleFont, Vector2.new(240, 1000))
    local w = math.clamp(math.ceil(textBounds.X + 28), 72, 278)
    local h = math.max(38, math.ceil(textBounds.Y + 18))

    local bb = Instance.new("BillboardGui")
    bb.Name = "ROCONS_ChatBubble"
    bb:SetAttribute("ROCONS_BubbleOwner", SessionToken)
    bb.Adornee = head
    bb.Size = UDim2.fromOffset(w, h)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = 125
    bb.Parent = head

    local bubbleFrame = UI.New("Frame", {
        Size = UDim2.fromScale(0, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.05,
        ClipsDescendants = true,
        Parent = bb,
    })
    UI.Corner(bubbleFrame, 12)
    local st = UI.Stroke(bubbleFrame, Theme.PurpleBorder, 1.5, 1)

    local lbl = UI.New("TextLabel", {
        Size = UDim2.new(1, -24, 1, -14),
        Position = UDim2.fromOffset(12, 7),
        BackgroundTransparency = 1,
        Font = UI.BubbleFont,
        TextSize = 18,
        TextWrapped = true,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextTransparency = 1,
        Text = cleanText,
        Parent = bubbleFrame,
    })

    local item = { Gui = bb, PixelHeight = h }
    table.insert(list, item)
    RestackBubbles(list)

    TweenService:Create(bubbleFrame, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
    TweenService:Create(lbl, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
    TweenService:Create(st, TweenInfo.new(0.2), { Transparency = 0.1 }):Play()

    task.delay(7, function()
        if not bb.Parent then return end
        local tw = TweenService:Create(bubbleFrame, TweenInfo.new(0.4), { BackgroundTransparency = 1, Size = UDim2.fromScale(0, 0) })
        TweenService:Create(lbl, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
        TweenService:Create(st, TweenInfo.new(0.4), { Transparency = 1 }):Play()
        tw:Play()
        tw.Completed:Wait()
        local idx = table.find(list, item)
        if idx then table.remove(list, idx) end
        if bb.Parent then bb:Destroy() end
        RestackBubbles(list)
    end)
end

-- Procedural R6 Rig Builder fallback (guarantees bots spawn in ANY map even if CreateHumanoidModel fails)
local function BuildFallbackR6Model(modelName)
    local model = Instance.new("Model")
    model.Name = modelName
    local hum = Instance.new("Humanoid")
    hum.RigType = Enum.HumanoidRigType.R6
    hum.Parent = model

    local function makePart(name, size, color)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Color = color
        p.Material = Enum.Material.SmoothPlastic
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.CanCollide = false
        p.Parent = model
        return p
    end

    local skin = Color3.fromRGB(234, 184, 146)
    local hrp      = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), skin)
    hrp.Transparency = 1
    local torso    = makePart("Torso", Vector3.new(2, 2, 1), Color3.fromRGB(40, 30, 60))
    local head     = makePart("Head", Vector3.new(2, 1, 1), skin)
    local leftArm  = makePart("Left Arm", Vector3.new(1, 2, 1), skin)
    local rightArm = makePart("Right Arm", Vector3.new(1, 2, 1), skin)
    local leftLeg  = makePart("Left Leg", Vector3.new(1, 2, 1), Color3.fromRGB(25, 20, 38))
    local rightLeg = makePart("Right Leg", Vector3.new(1, 2, 1), Color3.fromRGB(25, 20, 38))
    model.PrimaryPart = hrp

    local headMesh = Instance.new("SpecialMesh", head)
    headMesh.MeshType = Enum.MeshType.Head
    headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)

    local function motor(name, parent, p0, p1, c0, c1)
        local m = Instance.new("Motor6D")
        m.Name = name
        m.Part0 = p0
        m.Part1 = p1
        m.C0 = c0
        m.C1 = c1
        m.Parent = parent
    end

    motor("RootJoint", hrp, hrp, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
    motor("Neck", torso, torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
    motor("Right Shoulder", torso, torso, rightArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
    motor("Left Shoulder", torso, torso, leftArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
    motor("Right Hip", torso, torso, rightLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
    motor("Left Hip", torso, torso, leftLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

    return model
end

local SpawningLocks = {}
local OverheadEnabled = true

local GenderNamesTH = {
    M  = "ผู้ชาย",
    F  = "ผู้หญิง",
    FB = "เฟมบอย",
}

local StatusNamesTH = {
    Idle    = "ว่าง",
    Synced  = "กำลังซิงค์",
    Emoting = "แสดงท่าทาง",
}

local function SpawnBotModel(ownerChar, botModelName, targetUsername, morphGender, botRole)
    if SpawningLocks[botModelName] then return nil end
    SpawningLocks[botModelName] = true

    for _, child in ipairs(Workspace:GetChildren()) do
        if child.Name == botModelName then
            child:Destroy()
        end
    end

    if not ownerChar then
        SpawningLocks[botModelName] = nil
        return nil
    end

    local botModel
    local resolvedUserId
    if targetUsername and targetUsername ~= "" then
        pcall(function()
            resolvedUserId = Players:GetUserIdFromNameAsync(targetUsername)
        end)
        if resolvedUserId then
            pcall(function()
                local desc = Players:GetHumanoidDescriptionFromUserId(resolvedUserId)
                if desc then
                    botModel = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
                end
            end)
            if not botModel then
                pcall(function()
                    botModel = Players:CreateHumanoidModelFromUserId(resolvedUserId, Enum.HumanoidRigType.R6)
                end)
            end
        end
    end

    if not botModel then
        pcall(function()
            botModel = Players:CreateHumanoidModelFromUserId(LocalPlayer.UserId, Enum.HumanoidRigType.R6)
        end)
    end
    if not botModel then
        botModel = BuildFallbackR6Model(botModelName)
    end

    EnsureR6Bridge(botModel)
    botModel.Name = botModelName
    UVMorph.Remove(botModel)

    for _, d in ipairs(botModel:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()
        end
    end

    botModel.Parent = Workspace
    UI.PrepareBot(botModel)

    if MorphsFolder and morphGender then
        local morphTpl = MorphsFolder:FindFirstChild(morphGender)
        if morphTpl then
            ApplyMorph(botModel, morphTpl, morphGender, false)
        end
    end

    local head = botModel:FindFirstChild("Head")
    if head then
        local bb, _, rankLbl, textLbl = UI.BuildOverhead(head)
        bb.Enabled = OverheadEnabled
        if resolvedUserId then
            ApplyRankLabelEffect(rankLbl, RankConfig.GetTitle(resolvedUserId))
        end
        local gLabel = GenderNamesTH[morphGender or "F"] or (morphGender or "ผู้หญิง")
        textLbl.Text = string.format("%s · %s · บอท", targetUsername ~= "" and targetUsername or "บอท", gLabel)
    end

    local botRoot = botModel:FindFirstChild("HumanoidRootPart")
    local ownerRoot = ownerChar:FindFirstChild("HumanoidRootPart")
    if botRoot and ownerRoot then
        local zOffset = (botRole == "S") and -1 or 1
        botRoot.CFrame = ownerRoot.CFrame * CFrame.new(0, 0, zOffset)
        botRoot.Anchored = true
    end

    SpawningLocks[botModelName] = nil
    return botModel
end

-- ============================================================================
-- 8. STATE, SOUND & SYNC ENGINE
-- ============================================================================
local PlayersDatabase = {}
local RemoteTracks = {}

local MyGender       = "M"
local MyAge          = "18"
local MyStatus       = "Idle"     -- "Idle" | "Synced" | "Emoting"
local MySyncPartner  = ""         -- player Name or "[BOT]"
local MyRole         = "D"        -- "D" | "S"
local PreferredRole  = "AUTO"     -- "AUTO" | "D" | "S"
local MyCurrentAnim  = ""
local MyAnimSpeed    = 1
local MyMorphed      = false
local IgnoreInvites  = false
local SyncGuards     = { BreakAt = {}, AnimChangeAt = 0 }

local function ResolveMyRole(partnerGender)
    if PreferredRole == "D" or PreferredRole == "S" then
        return PreferredRole
    end
    if MyGender == "F" then return "S" end
    if partnerGender == "F" then return "D" end
    return "D"
end

local MyAnimTrack, PartnerAnimTrack, EmoteAnimTrack

local StopAllSounds, StartSyncSoundLoops
do
local SoundThreads = {}
local ActiveSounds = {}

StopAllSounds = function()
    for _, th in ipairs(SoundThreads) do
        pcall(task.cancel, th)
    end
    table.clear(SoundThreads)
    for _, s in ipairs(ActiveSounds) do
        if s and s.Parent then s:Destroy() end
    end
    table.clear(ActiveSounds)
end

local function PlayRandomSoundFrom(folder, parentPart)
    if not folder or not parentPart then return end
    local children = folder:GetChildren()
    if #children == 0 then return end
    local pick = children[math.random(1, #children)]
    if pick:IsA("Sound") then
        local s = pick:Clone()
        s.Parent = parentPart
        s.RollOffMaxDistance = 100
        s.RollOffMinDistance = 10
        s:Play()
        table.insert(ActiveSounds, s)
        s.Ended:Connect(function()
            s:Destroy()
            local idx = table.find(ActiveSounds, s)
            if idx then table.remove(ActiveSounds, idx) end
        end)
    end
end

StartSyncSoundLoops = function(cycleDuration, char)
    StopAllSounds()
    if not SoundsFolder or cycleDuration <= 0 or not char then return end
    local onFolder = SoundsFolder:FindFirstChild("On")
    local moveFolder = SoundsFolder:FindFirstChild("Move")
    local rootPart = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not rootPart then return end

    if onFolder then
        table.insert(SoundThreads, task.spawn(function()
            while MyStatus == "Synced" and IsSessionActive() do
                task.wait(0.1)
                PlayRandomSoundFrom(onFolder, rootPart)
                local waitTime = (cycleDuration / math.max(0.1, MyAnimSpeed)) - 0.1
                task.wait(math.max(0.08, waitTime))
            end
        end))
    end
    if moveFolder then
        table.insert(SoundThreads, task.spawn(function()
            while MyStatus == "Synced" and IsSessionActive() do
                task.wait((math.random(15, 35) / 10) / math.max(0.1, MyAnimSpeed))
                if math.random() > 0.4 then
                    PlayRandomSoundFrom(moveFolder, rootPart)
                end
            end
        end))
    end
end
end

local function RefreshOverheads(db)
    if not db then return end
    for plrName, data in pairs(db) do
        local plr = Players:FindFirstChild(plrName)
        local head = plr and plr.Character and plr.Character:FindFirstChild("Head")
        if head then
            local bb = head:FindFirstChild("ROCONS_Overhead")
            local isScriptPlr = (not IsUniversalMode) or (data.IsScriptUser == true) or (plr == LocalPlayer)
            if OverheadEnabled and isScriptPlr and (data.Gender ~= "" or data.Age ~= "") then
                if not bb then
                    bb = UI.BuildOverhead(head)
                end
                local frame = bb and bb:FindFirstChild("Frame")
                if frame then
                    local rankLbl = frame:FindFirstChild("RankDisplay")
                    local textLbl = frame:FindFirstChild("TextDisplay")
                    if textLbl then
                        local gLabel = GenderNamesTH[data.Gender or "M"] or (data.Gender or "ผู้ชาย")
                        textLbl.Text = string.format("%s · %s · %s", plr.DisplayName or plrName, gLabel, data.Age or "18")
                    end
                    if rankLbl then
                        ApplyRankLabelEffect(rankLbl, data.Title)
                    end
                end
            elseif bb then
                bb:Destroy()
            end
        end
    end
end

local function SetOverheadsEnabled(enabled)
    OverheadEnabled = enabled
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("BillboardGui") and d.Name == "ROCONS_Overhead" then
            d.Enabled = enabled
        end
    end
    if enabled then
        RefreshOverheads(PlayersDatabase)
    end
end

local BroadcastMyP2PState -- forward declaration
local UpdateHeaderStatusBadge -- forward declaration
local MorphToggleBtn          -- forward declaration

local SyncMasterCFrame = nil
local SyncAnchorReady  = false

local function FreezeCharacterHard(char, targetCF, anchorNow)
    if not char or not char.Parent then return end
    StopNonCarrierAnimatorTracks(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.AutoRotate = false
        hum.WalkSpeed = 0
        hum.PlatformStand = false
        pcall(function() hum.JumpPower = 0 end)
        pcall(function() hum.JumpHeight = 0 end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false) end)
    end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if targetCF then
            hrp.CFrame = targetCF
        end
        if anchorNow ~= nil then
            hrp.Anchored = anchorNow
        end
    end
end

local function MakeFlatCFrame(cf)
    local pos = cf.Position
    local look = cf.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 0.001 then
        flatLook = Vector3.new(0, 0, -1)
    else
        flatLook = flatLook.Unit
    end
    return CFrame.lookAt(pos, pos + flatLook)
end

-- Continuous 60 FPS Anti-Twitch Dual-Character Lock Loop:
-- Keeps BOTH synced characters (LocalPlayer + Partner/Bot) locked in place without twitching or struggling!
local syncStepSignal = RunService.Stepped or RunService.Heartbeat
syncStepSignal:Connect(function()
    if not IsSessionActive() then return end
    if MyStatus == "Emoting" then
        local myChar = LocalPlayer.Character
        if myChar then
            FreezeCharacterHard(myChar, nil, true)
        end
        return
    end
    if MyStatus ~= "Synced" then return end

    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myChar or not myRoot then return end

    if MySyncPartner == "[BOT]" then
        if not SyncMasterCFrame then
            SyncMasterCFrame = MakeFlatCFrame(myRoot.CFrame)
        end
        local botObj = Workspace:FindFirstChild("ROCONS_BOT_" .. LocalPlayer.Name)
        local myCF = (MyRole == "D") and SyncMasterCFrame or (SyncMasterCFrame * CFrame.new(0, 0, -1))
        local botCF = (MyRole == "D") and (SyncMasterCFrame * CFrame.new(0, 0, -1)) or SyncMasterCFrame
        FreezeCharacterHard(myChar, myCF, true)
        if botObj then
            FreezeCharacterHard(botObj, botCF, true)
        end
    elseif MySyncPartner ~= "" then
        local partnerPlr = Players:FindFirstChild(MySyncPartner)
        local partnerChar = partnerPlr and partnerPlr.Character
        local partnerRoot = partnerChar and partnerChar:FindFirstChild("HumanoidRootPart")

        if partnerChar and partnerRoot then
            local domRoot = (MyRole == "D") and myRoot or partnerRoot
            if not SyncMasterCFrame then
                SyncMasterCFrame = MakeFlatCFrame(domRoot.CFrame)
            elseif MyRole == "S" then
                -- Follow Dom player's initial horizontal anchor so both screens align identically
                SyncMasterCFrame = MakeFlatCFrame(partnerRoot.CFrame)
            end
            local domCF = SyncMasterCFrame
            local subCF = SyncMasterCFrame * CFrame.new(0, 0, -1)
            local myTargetCF = (MyRole == "D") and domCF or subCF
            local partnerTargetCF = (MyRole == "D") and subCF or domCF

            FreezeCharacterHard(myChar, myTargetCF, SyncAnchorReady)
            FreezeCharacterHard(partnerChar, partnerTargetCF, true)
        else
            if not SyncMasterCFrame then
                SyncMasterCFrame = MakeFlatCFrame(myRoot.CFrame)
            end
            FreezeCharacterHard(myChar, SyncMasterCFrame, true)
        end
    end
end)

local function StopEmote()
    if EmoteAnimTrack then
        EmoteAnimTrack.Stop()
        EmoteAnimTrack = nil
    end
    if MyStatus == "Emoting" then
        if LocalPlayer.Character then
            ResetCharacterAfterSync(LocalPlayer.Character, MyMorphed)
        end
        MyStatus = "Idle"
        MyCurrentAnim = ""
        PlayerUpdateSig:Fire({ Status = "Idle", CurrentAnim = "" })
        if BroadcastMyP2PState then BroadcastMyP2PState() end
    end
end

UserInputService.JumpRequest:Connect(function()
    if MyStatus == "Emoting" then
        StopEmote()
    end
end)

local function StartSyncSession(partnerName, myRole)
    StopEmote()
    MyStatus = "Synced"
    MySyncPartner = partnerName
    MyRole = myRole
    SyncMasterCFrame = nil
    SyncAnchorReady = false

    local myChar = LocalPlayer.Character
    if myChar then
        EnsureR6Bridge(myChar)
    end

    if partnerName ~= "[BOT]" then
        local partnerPlr = Players:FindFirstChild(partnerName)
        local partnerChar = partnerPlr and partnerPlr.Character
        if partnerChar and myChar then
            EnsureR6Bridge(partnerChar)
            CreateNoCollide(myChar, partnerChar)

            -- Also apply partner's morph on our client so both synced characters are morphed
            local partnerEntry = PlayersDatabase[partnerName]
            local partnerGender = (partnerEntry and partnerEntry.Gender ~= "" and partnerEntry.Gender)
                or ((myRole == "D") and "F" or "M")
            if MorphsFolder then
                local pTpl = MorphsFolder:FindFirstChild(partnerGender)
                if pTpl then
                    ApplyMorph(partnerChar, pTpl, partnerGender, false)
                end
            end

            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local theirRoot = partnerChar:FindFirstChild("HumanoidRootPart")
            if myRoot and theirRoot then
                local domRoot = (myRole == "D") and myRoot or theirRoot
                SyncMasterCFrame = MakeFlatCFrame(domRoot.CFrame)
                local myTargetCF = (myRole == "D") and SyncMasterCFrame or (SyncMasterCFrame * CFrame.new(0, 0, -1))
                local theirTargetCF = (myRole == "D") and (SyncMasterCFrame * CFrame.new(0, 0, -1)) or SyncMasterCFrame
                -- Move unanchored for 2 physics frames (0.06s) so Roblox server replicates our exact synced CFrame, then anchor hard!
                FreezeCharacterHard(myChar, myTargetCF, false)
                FreezeCharacterHard(partnerChar, theirTargetCF, true)
            end
        end
    else
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if myRoot then
            SyncMasterCFrame = MakeFlatCFrame(myRoot.CFrame)
        end
    end

    MyMorphed = true
    if RefreshMorphToggleVisual then
        RefreshMorphToggleVisual()
    end
    if MorphsFolder and myChar then
        local tpl = MorphsFolder:FindFirstChild(MyGender)
        if tpl then
            ApplyMorph(myChar, tpl, MyGender, false)
        end
    end

    PlayerUpdateSig:Fire({
        Status = "Synced",
        SyncPartner = partnerName,
        Role = myRole,
        Morphed = true,
        Gender = MyGender,
    })
    if BroadcastMyP2PState then BroadcastMyP2PState() end

    task.delay(0.06, function()
        if MyStatus == "Synced" then
            SyncAnchorReady = true
        end
    end)
end

local function BreakSyncSession(silent, force)
    if not force and MyStatus == "Idle" and not EmoteAnimTrack and not MyAnimTrack and not PartnerAnimTrack then return end
    if MyStatus == "Emoting" then
        StopEmote()
        if UpdateHeaderStatusBadge then UpdateHeaderStatusBadge() end
        if not force then return end
    end

    local oldPartner = MySyncPartner
    if oldPartner ~= "" and oldPartner ~= "[BOT]" then
        SyncGuards.BreakAt[oldPartner] = os.clock()
    end
    MyStatus = "Idle"
    MyRole = ResolveMyRole()
    MyCurrentAnim = ""
    SyncMasterCFrame = nil
    SyncAnchorReady = false

    if MyAnimTrack then pcall(function() MyAnimTrack.Stop() end); MyAnimTrack = nil end
    if PartnerAnimTrack then pcall(function() PartnerAnimTrack.Stop() end); PartnerAnimTrack = nil end
    if EmoteAnimTrack then pcall(function() EmoteAnimTrack.Stop() end); EmoteAnimTrack = nil end

    if LocalPlayer.Character then
        if ActiveKeyframeTrackByChar[LocalPlayer.Character] then
            pcall(function() ActiveKeyframeTrackByChar[LocalPlayer.Character].Stop() end)
        end
        ResetCharacterAfterSync(LocalPlayer.Character, false)
    end

    if oldPartner ~= "" and oldPartner ~= "[BOT]" then
        if RemoteTracks[oldPartner] and RemoteTracks[oldPartner].Track then
            pcall(function() RemoteTracks[oldPartner].Track.Stop() end)
        end
        RemoteTracks[oldPartner] = nil
        local p = Players:FindFirstChild(oldPartner)
        if p and p.Character then
            if ActiveKeyframeTrackByChar[p.Character] then
                pcall(function() ActiveKeyframeTrackByChar[p.Character].Stop() end)
            end
            ResetCharacterAfterSync(p.Character, false)
        end
    end

    do
        local botName = "ROCONS_BOT_" .. LocalPlayer.Name
        if RemoteTracks[botName] and RemoteTracks[botName].Track then
            pcall(function() RemoteTracks[botName].Track.Stop() end)
        end
        RemoteTracks[botName] = nil
        local botObj = Workspace:FindFirstChild(botName)
        if botObj then
            if ActiveKeyframeTrackByChar[botObj] then
                pcall(function() ActiveKeyframeTrackByChar[botObj].Stop() end)
            end
            botObj:Destroy()
        end
    end

    MyMorphed = false
    MyAnimSpeed = 1
    MySyncPartner = ""

    if RefreshMorphToggleVisual then
        RefreshMorphToggleVisual()
    end
    if not silent then
        SyncBreakSig:Fire()
        BotUpdateSig:Fire({ Active = false })
        PlayerUpdateSig:Fire({
            Status = "Idle",
            SyncPartner = "",
            CurrentAnim = "",
            Morphed = false,
        })
    end
    if BroadcastMyP2PState then BroadcastMyP2PState() end
    StopAllSounds()
    if UpdateHeaderStatusBadge then UpdateHeaderStatusBadge() end
end

local function FindAnimSequenceForRole(roleFolder, animName, suffix)
    if not roleFolder or not animName or animName == "" then return nil end
    return roleFolder:FindFirstChild(animName .. suffix)
        or roleFolder:FindFirstChild(animName)
        or roleFolder:FindFirstChild(animName .. (suffix == "F" and "M" or "F"))
end

local function PlaySyncAnimation(animName)
    if not AnimFolder or not animName or animName == "" then return end
    local myRoleFolder = AnimFolder:FindFirstChild(MyRole)
    local partnerRole = (MyRole == "D") and "S" or "D"
    local partnerRoleFolder = AnimFolder:FindFirstChild(partnerRole)
    if not myRoleFolder or not partnerRoleFolder then return end

    local mySuffix = (MyRole == "S") and "F" or "M"
    local partnerSuffix = (partnerRole == "S") and "F" or "M"
    local mySeq = FindAnimSequenceForRole(myRoleFolder, animName, mySuffix)
    local partnerSeq = FindAnimSequenceForRole(partnerRoleFolder, animName, partnerSuffix)

    if MyAnimTrack then pcall(function() MyAnimTrack.Stop() end); MyAnimTrack = nil end
    if PartnerAnimTrack then pcall(function() PartnerAnimTrack.Stop() end); PartnerAnimTrack = nil end
    StopAllSounds()

    if mySeq and LocalPlayer.Character then
        MyAnimTrack = PlayKeyframeAnim(LocalPlayer.Character, mySeq, MyAnimSpeed)
        local maxTime = 0
        for _, kf in ipairs(mySeq:GetChildren()) do
            if kf:IsA("Keyframe") and kf.Time > maxTime then
                maxTime = kf.Time
            end
        end
        if maxTime > 0 then
            StartSyncSoundLoops(maxTime, LocalPlayer.Character)
        end
    end

    if MySyncPartner == "[BOT]" then
        local botObj = Workspace:FindFirstChild("ROCONS_BOT_" .. LocalPlayer.Name)
        if botObj and partnerSeq then
            PartnerAnimTrack = PlayKeyframeAnim(botObj, partnerSeq, MyAnimSpeed)
        end
    elseif MySyncPartner ~= "" then
        if RemoteTracks[MySyncPartner] and RemoteTracks[MySyncPartner].Track then
            pcall(function() RemoteTracks[MySyncPartner].Track.Stop() end)
        end
        RemoteTracks[MySyncPartner] = nil
        local partnerPlr = Players:FindFirstChild(MySyncPartner)
        if partnerPlr and partnerPlr.Character and partnerSeq then
            PartnerAnimTrack = PlayKeyframeAnim(partnerPlr.Character, partnerSeq, MyAnimSpeed)
        end
    end
    if UpdateHeaderStatusBadge then UpdateHeaderStatusBadge() end
end

local function SwitchActiveSyncRole(newRolePref)
    PreferredRole = newRolePref
    local resolved = ResolveMyRole()
    if MyStatus == "Synced" then
        MyRole = resolved
        if MySyncPartner == "[BOT]" then
            local opp = (MyRole == "D") and "S" or "D"
            if SelectedBotRole ~= opp then
                SelectedBotRole = opp
                if BotRoleSeg then BotRoleSeg.Set(opp) end
            end
        end
        PlayerUpdateSig:Fire({ Role = MyRole })
        if BroadcastMyP2PState then BroadcastMyP2PState() end
        if MyCurrentAnim ~= "" then
            SyncGuards.AnimChangeAt = os.clock()
            PlaySyncAnimation(MyCurrentAnim)
        end
        if UpdateHeaderStatusBadge then UpdateHeaderStatusBadge() end
    end
end

-- ============================================================================
-- 9. ENHANCED OBSIDIAN & NEON AMETHYST GLASSMORPHISM UI (100% THAI + DELTA COMPATIBLE)
-- ============================================================================
local GuiName = "ROCONS_REBORN_GUI"
local function GetSafeGuiContainers()
    local list = {}
    pcall(function()
        if type(gethui) == "function" then
            local h = gethui()
            if typeof(h) == "Instance" then table.insert(list, h) end
        end
    end)
    pcall(function()
        if type(get_hidden_gui) == "function" then
            local h = get_hidden_gui()
            if typeof(h) == "Instance" then table.insert(list, h) end
        end
    end)
    pcall(function()
        local _ = CoreGui.Name
        table.insert(list, CoreGui)
    end)
    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pgui then table.insert(list, pgui) end
    return list
end

for _, container in ipairs(GetSafeGuiContainers()) do
    for _, child in ipairs(container:GetChildren()) do
        if child.Name == GuiName or child.Name == "ROCONS_KeySystem" or child.Name == "ROCONS_KeySystem2" or child.Name == "ROCONS_R15Warn" then
            pcall(function() child:Destroy() end)
        end
    end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GuiName
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 50
pcall(function()
    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        syn.protect_gui(ScreenGui)
    end
end)
for _, container in ipairs(GetSafeGuiContainers()) do
    local ok = pcall(function()
        ScreenGui.Parent = container
    end)
    if ok and ScreenGui.Parent == container then
        break
    end
end
if not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- Toast Notification Banner (Standard Frame for 100% Delta Mobile/PC Brightness)
local ShowNotification
do
local NotifFrame = UI.New("Frame", {
    Name = "Toast",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 14),
    Size = UDim2.new(0.92, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Theme.PurpleDark,
    BackgroundTransparency = 0.02,
    ClipsDescendants = true,
    Visible = false,
    ZIndex = 600,
    Parent = ScreenGui,
})
local notifSizeCons = Instance.new("UISizeConstraint", NotifFrame)
notifSizeCons.MaxSize = Vector2.new(390, 9999)
notifSizeCons.MinSize = Vector2.new(0, 46)
UI.Corner(NotifFrame, 13)
local NotifStroke = UI.Stroke(NotifFrame, Theme.PurpleBorder, 1.5, 0.2)

local ToastBar = UI.New("Frame", {
    Size = UDim2.new(0, 4, 1, 0),
    BackgroundColor3 = Theme.AccentBright,
    Parent = NotifFrame,
})
local ToastBody = UI.New("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Parent = NotifFrame,
})
UI.Pad(ToastBody, 18, 12, 14, 12)
UI.List(ToastBody, "H", 10, nil, Enum.VerticalAlignment.Center)
local ToastIconHolder = UI.New("Frame", {
    Size = UDim2.fromOffset(20, 20),
    BackgroundTransparency = 1,
    LayoutOrder = 1,
    Parent = ToastBody,
})
local NotifText = UI.New("TextLabel", {
    Face = "SemiBold",
    TextSize = 14,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Size = UDim2.new(1, -30, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    LayoutOrder = 2,
    Parent = ToastBody,
})

local ToastKinds = {
    info    = { "info", Theme.AccentBright },
    success = { "check", Theme.Success },
    warn    = { "alert", Theme.Danger },
}
local ToastVer = 0

local function GuessToastKind(msg)
    local raw = tostring(msg or "")
    local lower = raw:lower()
    for _, w in ipairs({ "cannot", "could not", "don't have", "not ready", "must be", "already", "not currently", "deleted", "stopped", "ไม่สามารถ", "ไม่ได้", "ยังไม่ได้", "ยังไม่พร้อม", "กำลังเสก", "กรุณา", "หยุด", "ลบ" }) do
        if lower:find(w, 1, true) or raw:find(w, 1, true) then return "warn" end
    end
    for _, s in ipairs({ "complete", "spawned", "reloaded", "playing", "transferred", "sent", "สำเร็จ", "กำลังเล่น", "กำลังแสดง", "รีเฟรช", "ส่งคำขอ", "เปลี่ยนเพศ", "ครบ 100%" }) do
        if lower:find(s, 1, true) or raw:find(s, 1, true) then return "success" end
    end
    return "info"
end

ShowNotification = function(msg, duration, kind)
    ToastVer += 1
    local myVer = ToastVer
    NotifText.Text = tostring(msg or "")
    local k = ToastKinds[kind or GuessToastKind(msg)] or ToastKinds.info
    ToastIconHolder:ClearAllChildren()
    UI.Icon(ToastIconHolder, k[1], 20, k[2])
    ToastBar.BackgroundColor3 = k[2]
    NotifStroke.Color = k[2]

    local sc = NotifFrame:FindFirstChild("ToastScale") or UI.New("UIScale", { Name = "ToastScale", Parent = NotifFrame })
    if not NotifFrame.Visible then
        NotifFrame.Visible = true
        NotifFrame.Position = UDim2.new(0.5, 0, 0, -8)
        sc.Scale = 0.92
    end
    UI.Tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Quint)
    UI.Tween(NotifFrame, 0.26, { Position = UDim2.new(0.5, 0, 0, 14) }, Enum.EasingStyle.Quint)

    task.delay(duration or 3, function()
        if ToastVer ~= myVer then return end
        UI.Tween(sc, 0.16, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local tw = UI.Tween(NotifFrame, 0.16, { Position = UDim2.new(0.5, 0, 0, -14) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        tw.Completed:Connect(function()
            if ToastVer == myVer then
                NotifFrame.Visible = false
            end
        end)
    end)
end
end

-- Floating Left Dock (Draggable Quick Toggle + Chat Pill) — hidden until gender is selected
local Dock = UI.New("Frame", {
    Name = "Dock",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 14, 0.5, 0),
    Size = UDim2.fromOffset(64, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Theme.Panel,
    BackgroundTransparency = 0.04,
    Visible = false,
    ZIndex = 10,
    Parent = ScreenGui,
})
UI.Corner(Dock, 18)
do
local dockStroke = UI.Stroke(Dock, Color3.new(1, 1, 1), 1.4, 0.08)
UI.Gradient(dockStroke, Theme.AccentBright, Theme.AccentDeep, 90)
UI.Pad(Dock, 6, 4, 6, 8)
UI.List(Dock, "V", 6, Enum.HorizontalAlignment.Center)
UI.AttachAutoScale(Dock, 420)

local DockGrip = UI.New("Frame", {
    Name = "Grip",
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1,
    LayoutOrder = 0,
    ZIndex = 11,
    Parent = Dock,
})
UI.Icon(DockGrip, "grip", 17, Theme.TextDarkened, {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
})
UI.MakeDraggable(DockGrip, Dock)
end

local function MakeDockButton(name, iconName, labelText, order)
    local btn = UI.New("TextButton", {
        Name = name,
        Text = "",
        Size = UDim2.fromOffset(52, 50),
        BackgroundColor3 = Theme.Card,
        LayoutOrder = order,
        ZIndex = 11,
        Parent = Dock,
    })
    UI.Corner(btn, 14)
    UI.Stroke(btn, Theme.Border, 1, 0.25)
    UI.Interactive(btn, Theme.Card, Theme.CardHover, 0.93)
    local stack = UI.New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = btn,
    })
    UI.List(stack, "V", 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
    UI.Icon(stack, iconName, 19, Theme.AccentBright, { LayoutOrder = 1 })
    UI.New("TextLabel", {
        Text = labelText,
        Face = "Bold",
        TextSize = 11,
        TextColor3 = Theme.TextSecondary,
        Size = UDim2.new(1, 0, 0, 14),
        LayoutOrder = 2,
        Parent = stack,
    })
    return btn
end

local ToggleBtn = MakeDockButton("MenuBtn", "menu", "เมนู", 1)
local ChatToggleBtn = MakeDockButton("ChatBtn", "chat", "แชท", 2)
local ChatBadge = UI.New("Frame", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -6, 0, 6),
    Size = UDim2.fromOffset(9, 9),
    BackgroundColor3 = Theme.Danger,
    Visible = false,
    ZIndex = 15,
    Parent = ChatToggleBtn,
})
UI.Corner(ChatBadge, UDim.new(0.5, 0))

-- Main ROCONS Window (Standard Frame for 100% Delta Mobile/PC Brightness + Auto Viewport Scale)
local MainFrame = UI.New("Frame", {
    Name = "ROCONS_MainWindow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(410, 480),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.02,
    ClipsDescendants = true,
    Visible = false,
    Active = true,
    ZIndex = 20,
    Parent = ScreenGui,
})
MainFrame:SetAttribute("IsOpen", false)
UI.Corner(MainFrame, 20)
do
local mainStroke = UI.Stroke(MainFrame, Color3.new(1, 1, 1), 1.6, 0.05)
UI.Gradient(mainStroke, Theme.AccentBright, Theme.AccentDeep, 90)
UI.AttachAutoScale(MainFrame, 500)

-- Top Neon Accent Glow Strip
local TopGlowBar = UI.New("Frame", {
    Size = UDim2.new(1, 0, 0, 3),
    BackgroundColor3 = Color3.new(1, 1, 1),
    Parent = MainFrame,
})
UI.Gradient(TopGlowBar, Theme.AccentBright, Theme.Accent, 0)
end

-- Header Bar
local Header = UI.New("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 58),
    BackgroundTransparency = 1,
    Active = true,
    Parent = MainFrame,
})
UI.MakeDraggable(Header, MainFrame)

local HeaderTitleBox
do
local LogoBadge = UI.New("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 14, 0.5, 0),
    Size = UDim2.fromOffset(36, 36),
    BackgroundColor3 = Color3.new(1, 1, 1),
    ClipsDescendants = true,
    Parent = Header,
})
UI.Gradient(LogoBadge, Theme.AccentBright, Theme.AccentDeep, 45)
UI.Corner(LogoBadge, 11)
local HeaderLogoImg = UI.New("ImageLabel", {
    Size = UDim2.new(1, -4, 1, -4),
    Position = UDim2.fromOffset(2, 2),
    ScaleType = Enum.ScaleType.Crop,
    Image = LogoAssetId,
    Parent = LogoBadge,
})
UI.Corner(HeaderLogoImg, 9)
BindWebImage(HeaderLogoImg, AssetUrls.Logo, AssetFiles.Logo, LogoAssetId)

HeaderTitleBox = UI.New("Frame", {
    Position = UDim2.fromOffset(58, 9),
    Size = UDim2.new(1, -225, 0, 40),
    BackgroundTransparency = 1,
    Parent = Header,
})
local HeaderTitle = UI.New("TextLabel", {
    Text = "ROCONS REBORN",
    Face = "Display",
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    Size = UDim2.new(1, 0, 0, 20),
    Parent = HeaderTitleBox,
})
end
local HeaderSub = UI.New("TextLabel", {
    Text = IsUniversalMode and "v2.5 · โหมดเล่นได้ทุกแมพ" or "v2.5 · เชื่อมต่อเซิร์ฟเวอร์",
    Face = "SemiBold",
    TextSize = 11,
    TextColor3 = Theme.AccentBright,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(0, 20),
    Size = UDim2.new(1, 0, 0, 16),
    Parent = HeaderTitleBox,
})

-- Morph Toggle Pill & Close Button in Header
MorphToggleBtn = UI.New("TextButton", {
    Name = "MorphToggle",
    Text = "แปลงร่าง: ปิด",
    Face = "Bold",
    TextSize = 12,
    TextColor3 = Theme.TextSecondary,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -52, 0.5, 0),
    Size = UDim2.fromOffset(108, 34),
    BackgroundColor3 = Theme.Card,
    Parent = Header,
})
UI.Corner(MorphToggleBtn, 11)
local morphStroke = UI.Stroke(MorphToggleBtn, Theme.Border, 1, 0.25)
UI.Interactive(MorphToggleBtn, Theme.Card, Theme.CardHover, 0.95)
local MorphDot = UI.New("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 10, 0.5, 0),
    Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = Theme.TextDarkened,
    Parent = MorphToggleBtn,
})
UI.Corner(MorphDot, UDim.new(0.5, 0))
UI.Pad(MorphToggleBtn, 16, 0, 0, 0)

local function RefreshMorphToggleVisual()
    local isOn = (MorphToggleBtn.Text:find("เปิด", 1, true) ~= nil) or (MorphToggleBtn.Text:find("On", 1, true) ~= nil)
    UI.Tween(MorphDot, 0.16, { BackgroundColor3 = isOn and Theme.Success or Theme.TextDarkened })
    UI.Tween(morphStroke, 0.16, { Color = isOn and Theme.AccentBright or Theme.Border })
    MorphToggleBtn.TextColor3 = isOn and Theme.TextPrimary or Theme.TextSecondary
end
MorphToggleBtn:GetPropertyChangedSignal("Text"):Connect(RefreshMorphToggleVisual)

MorphToggleBtn.MouseButton1Click:Connect(function()
    if MyStatus == "Synced" then
        ShowNotification("ไม่สามารถสลับการแปลงร่างขณะกำลังซิงค์ได้!", 2, "warn")
        return
    end
    MyMorphed = not MyMorphed
    MorphToggleBtn.Text = MyMorphed and "แปลงร่าง: เปิด" or "แปลงร่าง: ปิด"
    MorphToggleSig:Fire(MyMorphed, MyGender)
    PlayerUpdateSig:Fire({ Morphed = MyMorphed, Gender = MyGender })
    if BroadcastMyP2PState then BroadcastMyP2PState() end
    if LocalPlayer.Character then
        if MyMorphed then
            local tpl = MorphsFolder and MorphsFolder:FindFirstChild(MyGender)
            if tpl then
                ApplyMorph(LocalPlayer.Character, tpl, MyGender, false)
            elseif UVMorph.Genders[MyGender] then
                UVMorph.Apply(LocalPlayer.Character, MyGender)
            end
        else
            UVMorph.Remove(LocalPlayer.Character)
            RemoveMorph(LocalPlayer.Character)
            RemoveR6Bridge(LocalPlayer.Character)
        end
    end
end)

local CloseBtn = UI.New("TextButton", {
    Text = "",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = Theme.Card,
    Parent = Header,
})
UI.Corner(CloseBtn, 11)
UI.Stroke(CloseBtn, Theme.Border, 1, 0.25)
UI.Interactive(CloseBtn, Theme.Card, Theme.DangerHover, 0.92)
UI.Icon(CloseBtn, "close", 15, Theme.TextSecondary, {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
})

-- 5-Tab Navigation Bar
local NavContainer = UI.New("Frame", {
    Name = "Nav",
    Position = UDim2.new(0, 12, 0, 66),
    Size = UDim2.new(1, -24, 0, 52),
    BackgroundTransparency = 1,
    Parent = MainFrame,
})
UI.List(NavContainer, "H", 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

local SpeedFill, SpeedLabel
do
local HeaderLine = UI.New("Frame", {
    Position = UDim2.new(0, 12, 0, 58),
    Size = UDim2.new(1, -24, 0, 1),
    BackgroundColor3 = Theme.Border,
    BackgroundTransparency = 0.45,
    Parent = MainFrame,
})

-- Speed & Control Bar
local ControlPanel = UI.New("Frame", {
    Name = "ControlPanel",
    Position = UDim2.new(0, 12, 0, 126),
    Size = UDim2.new(1, -24, 0, 46),
    BackgroundColor3 = Theme.PurpleDark,
    Parent = MainFrame,
})
UI.Corner(ControlPanel, 12)
UI.Stroke(ControlPanel, Theme.Border, 1, 0.35)

local SpeedGroup = UI.New("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent = ControlPanel,
})

local SpeedDown = UI.New("TextButton", {
    Text = "",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 6, 0.5, 0),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = Theme.Card,
    Parent = SpeedGroup,
})
UI.Corner(SpeedDown, 9)
UI.Interactive(SpeedDown, Theme.Card, Theme.CardHover, 0.92)
UI.Icon(SpeedDown, "minus", 15, Theme.AccentBright, {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
})

local SpeedUp = UI.New("TextButton", {
    Text = "",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -6, 0.5, 0),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = Theme.Card,
    Parent = SpeedGroup,
})
UI.Corner(SpeedUp, 9)
UI.Interactive(SpeedUp, Theme.Card, Theme.CardHover, 0.92)
UI.Icon(SpeedUp, "plus", 15, Theme.AccentBright, {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
})

local SpeedTrack = UI.New("Frame", {
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -8),
    Size = UDim2.new(1, -100, 0, 6),
    BackgroundColor3 = Theme.Card,
    Parent = SpeedGroup,
})
UI.Corner(SpeedTrack, UDim.new(0.5, 0))
SpeedFill = UI.New("Frame", {
    Size = UDim2.fromScale(0.3, 1),
    BackgroundColor3 = Theme.AccentBright,
    Parent = SpeedTrack,
})
UI.Corner(SpeedFill, UDim.new(0.5, 0))

SpeedLabel = UI.New("TextLabel", {
    Text = "ความเร็วท่า · 1.0x",
    Face = "Bold",
    TextSize = 12,
    TextColor3 = Theme.TextSecondary,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 7),
    Size = UDim2.new(1, -100, 0, 18),
    Parent = SpeedGroup,
})

SpeedDown.MouseButton1Click:Connect(function() MyAnimSpeed = math.clamp(math.floor((MyAnimSpeed - 0.2) * 10 + 0.5) / 10, 0.2, 3.0); SpeedLabel.Text = string.format("ความเร็วท่า · %.1fx", MyAnimSpeed); UI.Tween(SpeedFill, 0.14, { Size = UDim2.fromScale(math.clamp((MyAnimSpeed - 0.2) / 2.8, 0.05, 1), 1) }); if MyAnimTrack then MyAnimTrack.Speed = MyAnimSpeed end; if PartnerAnimTrack then PartnerAnimTrack.Speed = MyAnimSpeed end; if EmoteAnimTrack then EmoteAnimTrack.Speed = MyAnimSpeed end; if MyStatus == "Synced" then SpeedChangeSig:Fire(MyAnimSpeed) end; PlayerUpdateSig:Fire({ AnimSpeed = MyAnimSpeed }); if BroadcastMyP2PState then BroadcastMyP2PState() end end)
SpeedUp.MouseButton1Click:Connect(function() MyAnimSpeed = math.clamp(math.floor((MyAnimSpeed + 0.2) * 10 + 0.5) / 10, 0.2, 3.0); SpeedLabel.Text = string.format("ความเร็วท่า · %.1fx", MyAnimSpeed); UI.Tween(SpeedFill, 0.14, { Size = UDim2.fromScale(math.clamp((MyAnimSpeed - 0.2) / 2.8, 0.05, 1), 1) }); if MyAnimTrack then MyAnimTrack.Speed = MyAnimSpeed end; if PartnerAnimTrack then PartnerAnimTrack.Speed = MyAnimSpeed end; if EmoteAnimTrack then EmoteAnimTrack.Speed = MyAnimSpeed end; if MyStatus == "Synced" then SpeedChangeSig:Fire(MyAnimSpeed) end; PlayerUpdateSig:Fire({ AnimSpeed = MyAnimSpeed }); if BroadcastMyP2PState then BroadcastMyP2PState() end end)
end

UpdateHeaderStatusBadge = function()
    local modeStr = IsUniversalMode and "โหมดทุกแมพ" or "เซิร์ฟเวอร์"
    local gStr = GenderNamesTH[MyGender] or MyGender
    if MyStatus == "Synced" then
        HeaderSub.Text = string.format("● ซิงค์กับ (%s) · %s", MySyncPartner == "[BOT]" and "บอท" or MySyncPartner, MyCurrentAnim ~= "" and MyCurrentAnim or "พร้อม")
        HeaderSub.TextColor3 = Theme.Success
    elseif MyStatus == "Emoting" then
        HeaderSub.Text = string.format("● กำลังแสดงท่าทาง · %s", MyCurrentAnim)
        HeaderSub.TextColor3 = Theme.AccentBright
    else
        HeaderSub.Text = string.format("v2.5 · %s · เพศ: %s", modeStr, gStr)
        HeaderSub.TextColor3 = Theme.TextSecondary
    end
end

-- Tabs Setup
local TabFrames = {}
local ActiveTab = "Players"

local function SelectTab(tabKey)
    for k, entry in pairs(TabFrames) do
        local isSel = (k == tabKey)
        entry.Content.Visible = isSel
        UI.SetBase(entry.Button, isSel and Theme.Accent or Theme.Card, isSel and Theme.AccentHover or Theme.CardHover)
        entry.Icon.SetColor(isSel and Theme.TextPrimary or Theme.TextSecondary)
        entry.Label.TextColor3 = isSel and Theme.TextPrimary or Theme.TextSecondary
    end
    ActiveTab = tabKey
end

local function CreateTabButton(key, title, iconName)
    local btn = UI.New("TextButton", {
        Name = "Tab_" .. key,
        Text = "",
        Size = UDim2.new(0.2, -4, 1, 0),
        BackgroundColor3 = Theme.Card,
        Parent = NavContainer,
    })
    UI.Corner(btn, 12)
    UI.Stroke(btn, Theme.Border, 1, 0.35)
    UI.Interactive(btn, Theme.Card, Theme.CardHover, 0.95)

    local inner = UI.New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = btn,
    })
    UI.List(inner, "V", 3, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
    local ic = UI.Icon(inner, iconName, 19, Theme.TextSecondary, { LayoutOrder = 1 })
    local lbl = UI.New("TextLabel", {
        Text = title,
        Face = "Bold",
        TextSize = 11,
        TextColor3 = Theme.TextSecondary,
        Size = UDim2.new(1, 0, 0, 14),
        LayoutOrder = 2,
        Parent = inner,
    })

    local page = UI.New("ScrollingFrame", {
        Name = key .. "Page",
        Visible = false,
        Position = UDim2.new(0, 12, 0, 180),
        Size = UDim2.new(1, -24, 1, -192),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.AccentBright,
        ScrollBarImageTransparency = 0.25,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = MainFrame,
    })
    UI.Pad(page, 2, 2, 8, 10)
    local layout = UI.List(page, "V", 7)

    TabFrames[key] = { Button = btn, Content = page, Layout = layout, Icon = ic, Label = lbl }
    btn.MouseButton1Click:Connect(function()
        SelectTab(key)
    end)
    return page
end

local PlayersTab  = CreateTabButton("Players",  "ผู้เล่น",  "users")
local BotsTab     = CreateTabButton("Bots",     "บอท",     "bot")
local AnimsTab    = CreateTabButton("Anims",    "ท่าซิงค์", "film")
local EmotesTab   = CreateTabButton("Emotes",   "ท่าทาง",   "sparkle")
local SettingsTab = CreateTabButton("Settings", "ตั้งค่า",  "sliders")
SelectTab("Players")

-- ============================================================================
-- 10. TAB CONTENTS: ผู้เล่น, บอท, ท่าซิงค์, ท่าทาง, ตั้งค่า (100% THAI)
-- ============================================================================

-- [A] แท็บผู้เล่น (Players Tab)
local PlayersRoleSeg, SettingsRoleSeg
do
UI.Section(PlayersTab, "บทบาทของคุณตอนซิงค์ (รุก / รับ)", -14)
PlayersRoleSeg = UI.Segmented(PlayersTab, {
    { Key = "AUTO", Text = "อัตโนมัติ" },
    { Key = "D",    Text = "ฝ่ายรุก (D)" },
    { Key = "S",    Text = "ฝ่ายรับ (S)" },
}, PreferredRole, function(val)
    SwitchActiveSyncRole(val)
    if SettingsRoleSeg then SettingsRoleSeg.Set(val) end
    local roleTxt = (val == "D" and "ฝ่ายรุก (D)") or (val == "S" and "ฝ่ายรับ (S)") or "อัตโนมัติตามเพศ"
    ShowNotification("ตั้งบทบาทของคุณเป็น: " .. roleTxt, 2, "success")
end, -13)
end

local RefreshListBtn = UI.Button(PlayersTab, {
    Name = "RefreshListBtn",
    Text = "รีเฟรชรายชื่อผู้เล่น",
    Icon = "swap",
    Style = "secondary",
    LayoutOrder = -10,
})

local function PopulatePlayersTab(db)
    for _, child in ipairs(PlayersTab:GetChildren()) do
        if (child:IsA("TextButton") or child.Name == "EmptyState") and child.Name ~= "RefreshListBtn" then
            child:Destroy()
        end
    end
    db = db or PlayersDatabase
    local order = 0
    for plrName, info in pairs(db) do
        if plrName ~= LocalPlayer.Name then
            local plr = Players:FindFirstChild(plrName)
            local isScriptPlr = (not IsUniversalMode) or (info.IsScriptUser == true)
            order += 1
            local disp = info.DisplayName or (plr and plr.DisplayName) or plrName
            local uid = info.UserId or (plr and plr.UserId)
            local thumb = uid and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", uid) or nil
            local gLabel = (info.Gender and info.Gender ~= "" and GenderNamesTH[info.Gender]) or GenderNamesTH.M
            local stLabel = StatusNamesTH[info.Status or "Idle"] or (info.Status or "ว่าง")
            local scriptTag = isScriptPlr and "● รันสคริปต์" or "ผู้เล่นในแมพ"
            local row = UI.Row(PlayersTab, {
                Name = "PlayerRow",
                Text = disp,
                Sub = string.format("@%s · %s · เพศ: %s · สถานะ: %s", plrName, scriptTag, gLabel, stLabel),
                Image = thumb,
                Icon = (not thumb) and "user" or nil,
                Height = 52,
                Trail = "link",
                LayoutOrder = isScriptPlr and order or (1000 + order),
            })
            row.MouseButton1Click:Connect(function()
                if MyStatus == "Synced" then
                    ShowNotification("คุณกำลังซิงค์อยู่แล้ว! กรุณากดหยุดซิงค์ก่อน", 2, "warn")
                    return
                end
                local myRole = ResolveMyRole(info.Gender)
                SyncGuards.BreakAt[plrName] = nil
                SyncRequestSig:Fire(plrName, MyGender)
                StartSyncSession(plrName, myRole)
                UpdateHeaderStatusBadge()
                ShowNotification("ซิงค์และล็อกตัวละครกับ " .. disp .. " (" .. (myRole == "D" and "รุก" or "รับ") .. ") สำเร็จ!", 3, "success")
            end)
        end
    end
    if order == 0 then
        local empty = UI.Caption(PlayersTab, "ยังไม่มีผู้เล่นคนอื่นในเซิร์ฟเวอร์นี้ คุณสามารถใช้แท็บ 'บอท' เพื่อเสกบอทและซิงค์ท่าทางได้เลย!", 1)
        empty.Name = "EmptyState"
        empty.TextXAlignment = Enum.TextXAlignment.Center
        empty.Size = UDim2.new(1, 0, 0, 44)
    end
end

RefreshListBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        local all = GetAllPlayersFn.Invoke()
        PlayersDatabase = all or PlayersDatabase
        PopulatePlayersTab(PlayersDatabase)
        ShowNotification("รีเฟรชรายชื่อผู้เล่นสำเร็จ!", 2, "success")
    end)
end)

-- [B] แท็บบอท (Bots Tab)
local SelectedBotMorph = "F"
local BotMorphSeg
local SelectedBotRole = "S"
local BotRoleSeg
do
local botOrder = 0
local function nextBotOrder() botOrder += 1; return botOrder end

UI.Section(BotsTab, "ชื่อผู้ใช้ Roblox ของบอท", nextBotOrder())
local BotUserBox = UI.Field(BotsTab, {
    Icon = "user",
    Text = LocalPlayer.Name,
    Placeholder = "ใส่ชื่อผู้ใช้ Roblox ใครก็ได้...",
    LayoutOrder = nextBotOrder(),
})

UI.Section(BotsTab, "เพศและรูปร่างของบอท", nextBotOrder())
BotMorphSeg = UI.Segmented(BotsTab, {
    { Key = "F",  Text = "ผู้หญิง" },
    { Key = "M",  Text = "ผู้ชาย" },
    { Key = "FB", Text = "เฟมบอย" },
}, "F", function(val)
    SelectedBotMorph = val
end, nextBotOrder())

UI.Section(BotsTab, "บทบาทท่าซิงค์ของบอท", nextBotOrder())
BotRoleSeg = UI.Segmented(BotsTab, {
    { Key = "S", Text = "ฝ่ายรับ (S)" },
    { Key = "D", Text = "ฝ่ายรุก (D)" },
}, "S", function(val)
    SelectedBotRole = val
end, nextBotOrder())

UI.Caption(BotsTab, "บอทจะทำหน้าที่ตรงข้ามกับบทบาทของคุณ สามารถเสกอวตารของผู้เล่น Roblox คนใดก็ได้มาเป็นบอท R6 ได้ทุกแมพ", nextBotOrder())

local SpawnBotBtn = UI.Button(BotsTab, {
    Name = "SpawnBot",
    Text = "เสกบอท & ซิงค์ทันที",
    Icon = "bot",
    Style = "primary",
    Height = UI.RowH + 6,
    LayoutOrder = nextBotOrder(),
})

local DeleteBotBtn = UI.Button(BotsTab, {
    Name = "DeleteBot",
    Text = "ลบบอท",
    Icon = "trash",
    Style = "danger",
    Height = UI.RowH + 6,
    LayoutOrder = nextBotOrder(),
})

SpawnBotBtn.MouseButton1Click:Connect(function()
    local targetUser = BotUserBox.Text
    if targetUser == "" then
        targetUser = LocalPlayer.Name
    end
    if SpawningLocks["__LOCAL_BOT_SPAWN__"] then
        ShowNotification("กำลังเสกบอทอยู่ กรุณารอสักครู่...", 2, "warn")
        return
    end
    SpawningLocks["__LOCAL_BOT_SPAWN__"] = true

    task.spawn(function()
        if MyStatus == "Synced" then
            BreakSyncSession(true)
        elseif MyStatus == "Emoting" then
            StopEmote()
        end
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        if not char or not char.Parent then
            SpawningLocks["__LOCAL_BOT_SPAWN__"] = nil
            ShowNotification("ตัวละครของคุณยังไม่พร้อม", 3, "warn")
            return
        end

        EnsureR6Bridge(char)
        local botName = "ROCONS_BOT_" .. LocalPlayer.Name
        local botModel = SpawnBotModel(char, botName, targetUser, SelectedBotMorph, SelectedBotRole)
        SpawningLocks["__LOCAL_BOT_SPAWN__"] = nil

        if not botModel then
            ShowNotification("ไม่สามารถสร้างบอทได้ กรุณาลองใหม่อีกครั้ง", 3, "warn")
            return
        end

        CreateNoCollide(char, botModel)
        BotUpdateSig:Fire({
            Active = true,
            Username = targetUser,
            Morph = SelectedBotMorph,
            Role = SelectedBotRole,
        })

        local myRole = (SelectedBotRole == "S") and "D" or "S"
        StartSyncSession("[BOT]", myRole)
        UpdateHeaderStatusBadge()
        ShowNotification("เสกบอทและซิงค์สำเร็จ! เปิดแท็บ 'ท่าซิงค์' เพื่อเลือกท่าได้เลย", 3, "success")
    end)
end)

DeleteBotBtn.MouseButton1Click:Connect(function()
    BotUpdateSig:Fire({ Active = false })
    for _, child in ipairs(Workspace:GetChildren()) do
        if child.Name == ("ROCONS_BOT_" .. LocalPlayer.Name) then
            child:Destroy()
        end
    end
    if MySyncPartner == "[BOT]" then
        BreakSyncSession(true)
    end
    UpdateHeaderStatusBadge()
    ShowNotification("ลบบอทเรียบร้อยแล้ว", 2, "info")
end)
end

-- [C] แท็บท่าซิงค์ (Anims Tab)
local AnimSearchBox = UI.Field(AnimsTab, {
    Name = "AnimSearchField",
    Icon = "film",
    Placeholder = "ค้นหาท่าซิงค์...",
    LayoutOrder = -5,
})

do
local StopSyncBtn = UI.Button(AnimsTab, {
    Name = "StopSyncBtn",
    Text = "หยุดซิงค์ / รีเซ็ตท่าทาง",
    Icon = "stop",
    Style = "danger",
    LayoutOrder = -4,
})
StopSyncBtn.MouseButton1Click:Connect(function()
    BreakSyncSession(false, true)
    ShowNotification("หยุดการซิงค์และรีเซ็ตตัวละครแล้ว", 2, "info")
end)
end

UI.Caption(AnimsTab, "ซิงค์กับผู้เล่นหรือบอทก่อน จากนั้นแตะเลือกท่าซิงค์ด้านล่างได้เลย", -3)

local AnimRowButtons = {}
local function PopulateAnimsTab()
    for _, btn in ipairs(AnimRowButtons) do
        if btn and btn.Parent then btn:Destroy() end
    end
    table.clear(AnimRowButtons)

    local dFolder = AnimFolder and AnimFolder:FindFirstChild("D")
    if not dFolder then return end

    local query = AnimSearchBox.Text:lower()
    local list = dFolder:GetChildren()
    table.sort(list, function(a, b) return a.Name < b.Name end)

    for idx, seq in ipairs(list) do
        local cleanName = seq.Name:sub(1, -2)
        if query == "" or cleanName:lower():find(query, 1, true) then
            local row = UI.Row(AnimsTab, {
                Name = "AnimRow",
                Text = cleanName,
                Icon = "play",
                Height = UI.RowH + 2,
                Trail = "chevron",
                LayoutOrder = idx,
            })
            table.insert(AnimRowButtons, row)
            row.MouseButton1Click:Connect(function()
                if MyStatus ~= "Synced" then
                    ShowNotification("กรุณาเสกบอท (แท็บ 'บอท') หรือซิงค์กับผู้เล่นก่อน!", 3, "warn")
                    return
                end
                MyCurrentAnim = cleanName
                SyncGuards.AnimChangeAt = os.clock()
                PlaySyncAnimation(cleanName)
                AnimChangeSig:Fire(cleanName)
                PlayerUpdateSig:Fire({ CurrentAnim = cleanName })
                if BroadcastMyP2PState then BroadcastMyP2PState() end
                ShowNotification("กำลังเล่นท่า: " .. cleanName, 2, "success")
            end)
        end
    end
end
AnimSearchBox:GetPropertyChangedSignal("Text"):Connect(PopulateAnimsTab)

-- [D] แท็บท่าทาง (Emotes Tab)
local EmoteSearchBox = UI.Field(EmotesTab, {
    Name = "EmoteSearchField",
    Icon = "sparkle",
    Placeholder = "ค้นหาท่าทาง (Emotes)...",
    LayoutOrder = -5,
})

do
local StopEmoteBtn = UI.Button(EmotesTab, {
    Name = "StopEmoteBtn",
    Text = "หยุดแสดงท่าทาง",
    Icon = "stop",
    Style = "secondary",
    LayoutOrder = -4,
})
StopEmoteBtn.MouseButton1Click:Connect(function()
    if MyStatus == "Emoting" then
        StopEmote()
        UpdateHeaderStatusBadge()
        ShowNotification("หยุดแสดงท่าทางแล้ว", 2, "info")
    end
end)
end

local EmoteRowButtons = {}
local function PopulateEmotesTab()
    for _, btn in ipairs(EmoteRowButtons) do
        if btn and btn.Parent then btn:Destroy() end
    end
    table.clear(EmoteRowButtons)
    if not EmotesFolder then return end

    local query = EmoteSearchBox.Text:lower()
    local list = EmotesFolder:GetChildren()
    table.sort(list, function(a, b) return a.Name < b.Name end)

    for idx, seq in ipairs(list) do
        if query == "" or seq.Name:lower():find(query, 1, true) then
            local row = UI.Row(EmotesTab, {
                Name = "EmoteRow",
                Text = seq.Name,
                Icon = "sparkle",
                Height = UI.RowH + 2,
                Trail = "play",
                LayoutOrder = idx,
            })
            table.insert(EmoteRowButtons, row)
            row.MouseButton1Click:Connect(function()
                if MyStatus == "Synced" then
                    ShowNotification("ไม่สามารถใช้ท่าทางขณะกำลังซิงค์ได้!", 2, "warn")
                    return
                end
                if EmoteAnimTrack then
                    EmoteAnimTrack.Stop()
                end
                local char = LocalPlayer.Character
                if not char then return end
                EnsureR6Bridge(char)
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    hrp.Anchored = true
                end
                EmoteAnimTrack = PlayKeyframeAnim(char, seq, MyAnimSpeed)
                MyStatus = "Emoting"
                MyCurrentAnim = seq.Name
                PlayerUpdateSig:Fire({ Status = "Emoting", CurrentAnim = seq.Name })
                if BroadcastMyP2PState then BroadcastMyP2PState() end
                UpdateHeaderStatusBadge()
                ShowNotification("กำลังแสดงท่าทาง: " .. seq.Name, 2, "success")
            end)
        end
    end
end
EmoteSearchBox:GetPropertyChangedSignal("Text"):Connect(PopulateEmotesTab)

-- [E] แท็บตั้งค่า (Settings Tab)
local SettingsGenderSeg
local function ApplySelectedGender(newGender, silentToast)
    MyGender = newGender
    if MyGender == "F" then
        SelectedBotRole = "D"
        SelectedBotMorph = "M"
        if BotRoleSeg then BotRoleSeg.Set("D") end
        if BotMorphSeg then BotMorphSeg.Set("M") end
    elseif MyGender == "M" then
        SelectedBotRole = "S"
        SelectedBotMorph = "F"
        if BotRoleSeg then BotRoleSeg.Set("S") end
        if BotMorphSeg then BotMorphSeg.Set("F") end
    end
    if SettingsGenderSeg then
        SettingsGenderSeg.Set(MyGender)
    end
    ProfileSetupSig:Fire(MyAge, MyGender)
    PlayerUpdateSig:Fire({ Gender = MyGender, Age = MyAge })
    if BroadcastMyP2PState then BroadcastMyP2PState() end
    UpdateHeaderStatusBadge()
    if MyMorphed and LocalPlayer.Character then
        local tpl = MorphsFolder and MorphsFolder:FindFirstChild(MyGender)
        if tpl then
            ApplyMorph(LocalPlayer.Character, tpl, MyGender, false)
        end
    end
    if not silentToast then
        ShowNotification("เปลี่ยนเพศตัวละครเป็น " .. (GenderNamesTH[MyGender] or MyGender) .. " แล้ว", 2, "success")
    end
end

-- Client-Side Authentic R6 Locomotion Animator (RenderStepped-bound so R15 Animator NEVER overwrites it!)
local ClientR6Time = 0
local ClientR6StepName = "ROCONS_ClientR6Anim_" .. SessionToken
pcall(function() RunService:UnbindFromRenderStep("ROCONS_ClientR6Anim") end)

local function StepClientR6Locomotion(dt)
    if not IsSessionActive() then
        pcall(function() RunService:UnbindFromRenderStep(ClientR6StepName) end)
        return
    end
    if MyStatus ~= "Idle" then return end
    local char = LocalPlayer.Character
    if not char or not char.Parent then return end
    local torso = char:FindFirstChild("Torso")
    if not torso or not torso:GetAttribute("ROCONS_R6BridgePart") then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    ClientR6Time += math.clamp(tonumber(dt) or (1 / 60), 0, 0.1)

    local rj = hrp:FindFirstChild("RootJoint")
    local nk = torso:FindFirstChild("Neck")
    local rs = torso:FindFirstChild("Right Shoulder")
    local ls = torso:FindFirstChild("Left Shoulder")
    local rh = torso:FindFirstChild("Right Hip")
    local lh = torso:FindFirstChild("Left Hip")
    if not (rs and ls and rh and lh) then return end

    -- Keep R15 Animate disabled & stop any stray R15 tracks while R6 bridge is mounted
    local animScript = char:FindFirstChild("Animate")
    if animScript and animScript:IsA("LocalScript") and not animScript.Disabled then
        animScript:SetAttribute("ROCONS_R6DisabledAnimate", true)
        animScript.Disabled = true
    end

    local vel = hrp.AssemblyLinearVelocity
    local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    local state = hum:GetState()

    if hum.Sit or state == Enum.HumanoidStateType.Seated then
        if rj then rj.Transform = CFrame.new() end
        if nk then nk.Transform = CFrame.new() end
        rs.Transform = CFrame.Angles(0, 0, math.rad(18))
        ls.Transform = CFrame.Angles(0, 0, math.rad(-18))
        rh.Transform = CFrame.Angles(0, 0, math.rad(90))
        lh.Transform = CFrame.Angles(0, 0, math.rad(-90))
    elseif state == Enum.HumanoidStateType.Climbing then
        local climbSwing = math.sin(ClientR6Time * 11) * 0.85
        if rj then rj.Transform = CFrame.new() end
        if nk then nk.Transform = CFrame.Angles(math.rad(-15), 0, 0) end
        rs.Transform = CFrame.Angles(0, 0, math.rad(145) + climbSwing)
        ls.Transform = CFrame.Angles(0, 0, math.rad(-145) + climbSwing)
        rh.Transform = CFrame.Angles(0, 0, -climbSwing * 0.7)
        lh.Transform = CFrame.Angles(0, 0, -climbSwing * 0.7)
    elseif state == Enum.HumanoidStateType.Jumping then
        if rj then rj.Transform = CFrame.new() end
        if nk then nk.Transform = CFrame.Angles(math.rad(-8), 0, 0) end
        rs.Transform = CFrame.Angles(0, 0, math.rad(175))
        ls.Transform = CFrame.Angles(0, 0, math.rad(-175))
        rh.Transform = CFrame.Angles(0, 0, math.rad(-10))
        lh.Transform = CFrame.Angles(0, 0, math.rad(10))
    elseif state == Enum.HumanoidStateType.Freefall then
        if rj then rj.Transform = CFrame.new() end
        if nk then nk.Transform = CFrame.Angles(math.rad(6), 0, 0) end
        rs.Transform = CFrame.Angles(0, 0, math.rad(158))
        ls.Transform = CFrame.Angles(0, 0, math.rad(-158))
        rh.Transform = CFrame.Angles(0, 0, math.rad(-14))
        lh.Transform = CFrame.Angles(0, 0, math.rad(14))
    elseif horizSpeed > 0.65 then
        local freq = math.clamp(horizSpeed * 0.62, 6, 14)
        local amp = math.clamp(horizSpeed / 16, 0.45, 1.15) * 0.85
        local swing = math.sin(ClientR6Time * freq) * amp
        local bob = math.abs(math.cos(ClientR6Time * freq)) * 0.06
        if rj then rj.Transform = CFrame.new(0, 0, bob) * CFrame.Angles(math.rad(2), 0, 0) end
        if nk then nk.Transform = CFrame.new() end
        rs.Transform = CFrame.Angles(0, 0, swing)
        ls.Transform = CFrame.Angles(0, 0, swing)
        rh.Transform = CFrame.Angles(0, 0, -swing)
        lh.Transform = CFrame.Angles(0, 0, -swing)
    else
        local breath = math.sin(ClientR6Time * 2.1) * 0.055
        if rj then rj.Transform = CFrame.new() end
        if nk then nk.Transform = CFrame.new() end
        rs.Transform = CFrame.Angles(0, 0, breath)
        ls.Transform = CFrame.Angles(0, 0, breath)
        rh.Transform = CFrame.new()
        lh.Transform = CFrame.new()
    end
end

local okBind = pcall(function()
    RunService:BindToRenderStep(ClientR6StepName, Enum.RenderPriority.Character.Value + 5, StepClientR6Locomotion)
end)
if not okBind then
    (RunService.RenderStepped or RunService.Heartbeat):Connect(StepClientR6Locomotion)
end

-- Auto-reapply Client R6 and Disguise Avatar on Respawn
LocalPlayer.CharacterAdded:Connect(function(newChar)
    if not IsSessionActive() then return end
    task.defer(function()
        newChar:WaitForChild("HumanoidRootPart", 10)
        newChar:WaitForChild("Head", 10)
        task.wait(0.25)
        if not IsSessionActive() or not newChar.Parent then return end
        if ForceClientR6Enabled then
            EnsureR6Bridge(newChar)
        end
        if ActiveDisguiseUsername ~= "" then
            task.spawn(ApplyRobloxUserAvatar, ActiveDisguiseUsername)
        end
    end)
end)

local function PopulateSettingsTab()
    for _, child in ipairs(SettingsTab:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end

    UI.Section(SettingsTab, "เพศตัวละคร & รูปร่างแปลงร่าง", 1)
    SettingsGenderSeg = UI.Segmented(SettingsTab, {
        { Key = "M",  Text = "ผู้ชาย" },
        { Key = "F",  Text = "ผู้หญิง" },
        { Key = "FB", Text = "เฟมบอย" },
    }, MyGender, function(newGender)
        ApplySelectedGender(newGender, false)
    end, 2)

    UI.Section(SettingsTab, "บทบาทของคุณ (รุก / รับ)", 2)
    SettingsRoleSeg = UI.Segmented(SettingsTab, {
        { Key = "AUTO", Text = "อัตโนมัติ" },
        { Key = "D",    Text = "ฝ่ายรุก (D)" },
        { Key = "S",    Text = "ฝ่ายรับ (S)" },
    }, PreferredRole, function(val)
        SwitchActiveSyncRole(val)
        if PlayersRoleSeg then PlayersRoleSeg.Set(val) end
        local roleTxt = (val == "D" and "ฝ่ายรุก (D)") or (val == "S" and "ฝ่ายรับ (S)") or "อัตโนมัติตามเพศ"
        ShowNotification("ตั้งบทบาทของคุณเป็น: " .. roleTxt, 2, "success")
    end, 3)

    UI.Section(SettingsTab, "แปลงร่างเป็น R6 (สำหรับแมพที่ไม่รองรับ R6)", 4)
    UI.Toggle(SettingsTab, "แปลงร่างเป็น R6 (ฝั่ง Client)", "แปลงตัวละคร R15 เป็น R6 พร้อมท่าเดิน/กระโดดเฉพาะฝั่ง Client", ForceClientR6Enabled, function(v)
        ForceClientR6Enabled = v
        local char = LocalPlayer.Character
        if v then
            if char then
                EnsureR6Bridge(char)
                ShowNotification("แปลงร่างตัวละครเป็น R6 (ฝั่ง Client) สำเร็จ!", 3, "success")
            end
        else
            if char and MyStatus == "Idle" and not MyMorphed then
                RemoveR6Bridge(char, true)
                ShowNotification("ปิดโหมด R6 (ฝั่ง Client) และคืนค่าร่างเดิมแล้ว", 2, "info")
            else
                ShowNotification("ปิดโหมด R6 (ฝั่ง Client) แล้ว (จะคืนค่าร่างเดิมเมื่อหยุดซิงค์/แปลงร่าง)", 3, "info")
            end
        end
    end, 4)

    UI.Section(SettingsTab, "แปลงร่างเป็นใครก็ได้ใน Roblox (Client Morph)", 5)
    local AvatarMorphBox = UI.Field(SettingsTab, {
        Name = "AvatarMorphBox",
        Icon = "user",
        Text = ActiveDisguiseUsername,
        Placeholder = "ใส่ชื่อผู้ใช้ Roblox หรือ UserId...",
        LayoutOrder = 6,
    })

    local ApplyAvatarBtn = UI.Button(SettingsTab, {
        Name = "ApplyAvatarBtn",
        Text = "แปลงร่างเป็นคนนี้",
        Icon = "sparkle",
        Style = "primary",
        Height = UI.RowH + 2,
        LayoutOrder = 7,
    })
    ApplyAvatarBtn.MouseButton1Click:Connect(function()
        local query = AvatarMorphBox.Text
        if not query or query:match("^%s*$") then
            ShowNotification("กรุณาใส่ชื่อผู้ใช้ Roblox ก่อนกดแปลงร่าง!", 2, "warn")
            return
        end
        ShowNotification("กำลังโหลดข้อมูลตัวละคร @" .. query .. "...", 2, "info")
        task.spawn(function()
            local ok, res = ApplyRobloxUserAvatar(query)
            if ok then
                ShowNotification("แปลงร่างเป็น @" .. tostring(res) .. " (ฝั่ง Client) สำเร็จ!", 3, "success")
            else
                ShowNotification(tostring(res or "ไม่สามารถแปลงร่างได้"), 3, "warn")
            end
        end)
    end)

    local ResetAvatarBtn = UI.Button(SettingsTab, {
        Name = "ResetAvatarBtn",
        Text = "กลับเป็นตัวละครเดิม",
        Icon = "swap",
        Style = "secondary",
        Height = UI.RowH,
        LayoutOrder = 8,
    })
    ResetAvatarBtn.MouseButton1Click:Connect(function()
        ActiveDisguiseUsername = ""
        AvatarMorphBox.Text = ""
        ShowNotification("กำลังคืนค่ารูปลักษณ์ตัวละครเดิมของคุณ...", 2, "info")
        task.spawn(function()
            local ok, res = ApplyRobloxUserAvatar(tostring(LocalPlayer.UserId))
            ActiveDisguiseUsername = ""
            if ok then
                ShowNotification("คืนค่ารูปลักษณ์ตัวละครเดิมสำเร็จ!", 3, "success")
            else
                ShowNotification(tostring(res or "ไม่สามารถคืนค่าตัวละครได้"), 3, "warn")
            end
        end)
    end)

    UI.Section(SettingsTab, "การตั้งค่าทั่วไป", 9)
    UI.Toggle(SettingsTab, "ปฏิเสธคำขอซิงค์อัตโนมัติ", "ซ่อนและปฏิเสธคำเชิญซิงค์จากผู้เล่นอื่น", IgnoreInvites, function(v)
        IgnoreInvites = v
    end, 10)

    UI.Toggle(SettingsTab, "แสดงป้ายชื่อบนหัว", "แสดงป้ายข้อมูล ROCONS เหนือหัวผู้เล่นและบอท", OverheadEnabled, function(v)
        SetOverheadsEnabled(v)
    end, 11)
end

PopulateAnimsTab()
PopulateEmotesTab()
PopulateSettingsTab()

-- ============================================================================
-- 10.5 PRE-MAIN-FEATURE GENDER SELECTION MODAL (เลือกเพศ: ผู้ชาย / ผู้หญิง / เฟมบอย + รูปจริงจากอินเทอร์เน็ต)
-- ============================================================================
do
local ModalScrim = UI.New("Frame", {
    Name = "ROCONS_GenderModalScrim",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(6, 4, 12),
    BackgroundTransparency = 0.22,
    Active = true,
    ZIndex = 100,
    Parent = ScreenGui,
})

local GenderSelectModal = UI.New("Frame", {
    Name = "ROCONS_GenderSelectModal",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(375, 404),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.01,
    ClipsDescendants = true,
    Active = true,
    ZIndex = 110,
    Parent = ScreenGui,
})
UI.Corner(GenderSelectModal, 22)
local genderModalStroke = UI.Stroke(GenderSelectModal, Color3.new(1, 1, 1), 1.8, 0.05)
UI.Gradient(genderModalStroke, Theme.AccentBright, Theme.AccentDeep, 90)
UI.AttachAutoScale(GenderSelectModal, 420)

local GenderTopGlow = UI.New("Frame", {
    Size = UDim2.new(1, 0, 0, 4),
    BackgroundColor3 = Color3.new(1, 1, 1),
    Parent = GenderSelectModal,
})
UI.Gradient(GenderTopGlow, Theme.AccentBright, Theme.Accent, 0)

local GenderModalHeader = UI.New("Frame", {
    Position = UDim2.fromOffset(18, 16),
    Size = UDim2.new(1, -36, 0, 82),
    BackgroundTransparency = 1,
    Parent = GenderSelectModal,
})
UI.MakeDraggable(GenderModalHeader, GenderSelectModal)

local GenderLogoBadge = UI.New("Frame", {
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 0),
    Size = UDim2.fromOffset(40, 40),
    BackgroundColor3 = Color3.new(1, 1, 1),
    ClipsDescendants = true,
    Parent = GenderModalHeader,
})
UI.Gradient(GenderLogoBadge, Theme.AccentBright, Theme.AccentDeep, 45)
UI.Corner(GenderLogoBadge, 12)
local ModalLogoImg = UI.New("ImageLabel", {
    Size = UDim2.new(1, -4, 1, -4),
    Position = UDim2.fromOffset(2, 2),
    ScaleType = Enum.ScaleType.Crop,
    Image = LogoAssetId,
    Parent = GenderLogoBadge,
})
UI.Corner(ModalLogoImg, 10)
BindWebImage(ModalLogoImg, AssetUrls.Logo, AssetFiles.Logo, LogoAssetId)

UI.New("TextLabel", {
    Text = "เลือกเพศตัวละครของคุณ",
    Face = "Bold",
    TextSize = 18,
    TextColor3 = Theme.TextPrimary,
    Position = UDim2.fromOffset(0, 46),
    Size = UDim2.new(1, 0, 0, 22),
    Parent = GenderModalHeader,
})

UI.New("TextLabel", {
    Text = "กรุณาเลือกเพศก่อนเข้าสู่ฟีเจอร์หลักของ ROCONS Reborn",
    Face = "Medium",
    TextSize = 12,
    TextColor3 = Theme.AccentBright,
    Position = UDim2.fromOffset(0, 68),
    Size = UDim2.new(1, 0, 0, 16),
    Parent = GenderModalHeader,
})

local GenderChoicesHolder = UI.New("Frame", {
    Name = "Choices",
    Position = UDim2.fromOffset(18, 108),
    Size = UDim2.new(1, -36, 0, 250),
    BackgroundTransparency = 1,
    Parent = GenderSelectModal,
})
UI.List(GenderChoicesHolder, "V", 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

local GenderSelectedOnce = false
local function FinishInitialGenderSelection(genderKey)
    if GenderSelectedOnce then return end
    GenderSelectedOnce = true

    ApplySelectedGender(genderKey, true)

    local sc = GenderSelectModal:FindFirstChild("ViewportFitScale") or GenderSelectModal:FindFirstChildOfClass("UIScale") or UI.New("UIScale", { Parent = GenderSelectModal })
    UI.Tween(ModalScrim, 0.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local tw = UI.Tween(sc, 0.2, { Scale = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    tw.Completed:Connect(function()
        if ModalScrim and ModalScrim.Parent then ModalScrim:Destroy() end
        if GenderSelectModal and GenderSelectModal.Parent then GenderSelectModal:Destroy() end
    end)

    Dock.Visible = true
    UI.Present(MainFrame, true)
    ShowNotification("เลือกเพศ '" .. (GenderNamesTH[genderKey] or genderKey) .. "' สำเร็จ! ยินดีต้อนรับสู่ ROCONS Reborn", 3, "success")
end

local GenderCardSpecs = {
    {
        Key      = "M",
        Title    = "ผู้ชาย",
        Sub      = "รูปร่างผู้ชาย · บทบาทเริ่มต้นฝ่ายรุก (DOM)",
        Color    = Color3.fromRGB(0, 167, 255),
        IconName = "gender_male",
        FileName = AssetFiles.GenderM,
    },
    {
        Key      = "F",
        Title    = "ผู้หญิง",
        Sub      = "รูปร่างผู้หญิง · ล็อกบอทเป็นฝ่ายรุกให้อัตโนมัติ",
        Color    = Color3.fromRGB(255, 88, 178),
        IconName = "gender_female",
        FileName = AssetFiles.GenderF,
    },
    {
        Key      = "FB",
        Title    = "เฟมบอย",
        Sub      = "รูปร่างเฟมบอย · รองรับทุกบทบาททั้งฝ่ายรุกและฝ่ายรับ",
        Color    = Color3.fromRGB(214, 118, 255),
        IconName = "gender_femboy",
        FileName = AssetFiles.GenderFB,
    },
}

for idx, spec in ipairs(GenderCardSpecs) do
    local card = UI.New("TextButton", {
        Name = "GenderCard_" .. spec.Key,
        Text = "",
        Size = UDim2.new(1, 0, 0, 74),
        BackgroundColor3 = Theme.Card,
        LayoutOrder = idx,
        Parent = GenderChoicesHolder,
    })
    UI.Corner(card, 14)
    local cardStroke = UI.Stroke(card, spec.Color, 1.4, 0.3)
    UI.Interactive(card, Theme.Card, Theme.CardHover, 0.97)

    card.MouseEnter:Connect(function()
        UI.Tween(cardStroke, 0.15, { Transparency = 0 })
    end)
    card.MouseLeave:Connect(function()
        UI.Tween(cardStroke, 0.15, { Transparency = 0.3 })
    end)

    local badgeBox = UI.New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(52, 52),
        BackgroundColor3 = Theme.PurpleDark,
        ClipsDescendants = true,
        Parent = card,
    })
    UI.Corner(badgeBox, 12)
    UI.Stroke(badgeBox, spec.Color, 1.4, 0.15)

    local customAssetUri = GenderIconAssets[spec.Key] or ""
    if customAssetUri ~= "" then
        local portraitImg = UI.New("ImageLabel", {
            Name = "Portrait",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(40, 40),
            BackgroundTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
            Image = customAssetUri,
            ZIndex = 2,
            Parent = badgeBox,
        })
        -- Vector fallback only shown if customAssetUri hasn't loaded yet
        local vecFallback = UI.Icon(badgeBox, spec.IconName, 34, spec.Color, {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Visible = not portraitImg.IsLoaded,
        })
        portraitImg:GetPropertyChangedSignal("IsLoaded"):Connect(function()
            if vecFallback and vecFallback.Box then
                vecFallback.Box.Visible = not portraitImg.IsLoaded
            end
        end)
    else
        UI.Icon(badgeBox, spec.IconName, 34, spec.Color, {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
        })
    end

    local textCol = UI.New("Frame", {
        Position = UDim2.fromOffset(74, 0),
        Size = UDim2.new(1, -110, 1, 0),
        BackgroundTransparency = 1,
        Parent = card,
    })
    UI.List(textCol, "V", 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    UI.New("TextLabel", {
        Text = spec.Title,
        Face = "Bold",
        TextSize = 16,
        TextColor3 = Theme.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 20),
        LayoutOrder = 1,
        Parent = textCol,
    })
    UI.New("TextLabel", {
        Text = spec.Sub,
        Face = "Regular",
        TextSize = 12,
        TextColor3 = Theme.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.new(1, 0, 0, 15),
        LayoutOrder = 2,
        Parent = textCol,
    })

    UI.Icon(card, "chevron", 16, spec.Color, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
    })

    card.MouseButton1Click:Connect(function()
        FinishInitialGenderSelection(spec.Key)
    end)
end

UI.New("TextLabel", {
    Text = "สามารถเปลี่ยนเพศในภายหลังได้ที่แท็บ 'ตั้งค่า' · รองรับ Delta & ทุก Executor",
    Face = "Regular",
    TextSize = 11,
    TextColor3 = Theme.TextDarkened,
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -14),
    Size = UDim2.new(1, -36, 0, 16),
    Parent = GenderSelectModal,
})
end

-- ============================================================================
-- 11. STANDALONE MULTI-CHANNEL CHAT WINDOW (หน้าต่างแชทภาษาไทย — DELTA COMPATIBLE)
-- ============================================================================
do
local ChatBoxFrame = UI.New("Frame", {
    Name = "ROCONS_StandaloneChatBox",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(340, 310),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = Theme.Background,
    ClipsDescendants = true,
    Visible = false,
    Active = true,
    ZIndex = 25,
    Parent = ScreenGui,
})
ChatBoxFrame:SetAttribute("IsOpen", false)
UI.Corner(ChatBoxFrame, 18)
local chatStroke = UI.Stroke(ChatBoxFrame, Color3.new(1, 1, 1), 1.5, 0.05)
UI.Gradient(chatStroke, Theme.AccentBright, Theme.AccentDeep, 90)
UI.AttachAutoScale(ChatBoxFrame, 350)

local ChatHeader = UI.New("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundTransparency = 1,
    Active = true,
    Parent = ChatBoxFrame,
})
UI.MakeDraggable(ChatHeader, ChatBoxFrame)
UI.Icon(ChatHeader, "chat", 20, Theme.AccentBright, {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 16, 0.5, 0),
})
UI.New("TextLabel", {
    Text = "แชท ROCONS",
    Face = "Bold",
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(44, 0),
    Size = UDim2.new(1, -96, 1, 0),
    Parent = ChatHeader,
})

local ChatCloseBtn = UI.New("TextButton", {
    Text = "",
    Size = UDim2.fromOffset(34, 34),
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -8, 0.5, 0),
    BackgroundColor3 = Theme.Card,
    Parent = ChatHeader,
})
UI.Corner(ChatCloseBtn, 11)
UI.Stroke(ChatCloseBtn, Theme.Border, 1, 0.3)
UI.Interactive(ChatCloseBtn, Theme.Card, Theme.DangerHover, 0.92)
UI.Icon(ChatCloseBtn, "close", 15, Theme.TextSecondary, {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
})

local ChatLogScroll = UI.New("ScrollingFrame", {
    Name = "Log",
    Position = UDim2.fromOffset(10, 50),
    Size = UDim2.new(1, -20, 1, -108),
    BackgroundTransparency = 0,
    BackgroundColor3 = Theme.PurpleDark,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.AccentBright,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
    Parent = ChatBoxFrame,
})
UI.Corner(ChatLogScroll, 12)
UI.Stroke(ChatLogScroll, Theme.Border, 1, 0.35)
UI.Pad(ChatLogScroll, 8, 8, 10, 8)
UI.List(ChatLogScroll, "V", 4)

local InputContainer = UI.New("Frame", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 10, 1, -10),
    Size = UDim2.new(1, -20, 0, 42),
    BackgroundColor3 = Theme.PurpleDark,
    Parent = ChatBoxFrame,
})
UI.Corner(InputContainer, 12)
UI.Stroke(InputContainer, Theme.Border, 1.4, 0.1)

local ChatInput = UI.New("TextBox", {
    Text = "",
    PlaceholderText = "พิมพ์ข้อความ...",
    Face = "Medium",
    TextSize = 14,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(12, 0),
    Size = UDim2.new(1, -92, 1, 0),
    Parent = InputContainer,
})

local SendBtn = UI.New("TextButton", {
    Text = "ส่ง",
    Face = "Bold",
    TextSize = 13,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -4, 0.5, 0),
    Size = UDim2.new(0, 74, 1, -8),
    BackgroundColor3 = Theme.Accent,
    Parent = InputContainer,
})
UI.Corner(SendBtn, 9)
UI.Interactive(SendBtn, Theme.Accent, Theme.AccentHover, 0.94)

local ChatMessages = {}

local function AppendChatRow(msgObj)
    table.insert(ChatMessages, msgObj)
    local row = UI.New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #ChatMessages,
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = (msgObj.Sender == LocalPlayer.Name) and 0.84 or 1,
        Parent = ChatLogScroll,
    })
    UI.Corner(row, 8)
    UI.Pad(row, 6, 4, 6, 4)

    local senderName = UI.Escape(msgObj.DisplayName or msgObj.Sender or "ไม่ทราบชื่อ")
    local bodyText = UI.Escape(msgObj.Text or "")
    local titleStr = tostring(msgObj.Title or "")

    local formatted
    if titleStr ~= "" then
        local c = RankConfig.Colors[titleStr] or Theme.AccentBright
        local hex = string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
        formatted = string.format('<font color="%s"><b>[%s] %s</b></font>  <font color="#F6F1FF">%s</font>', hex, UI.Escape(titleStr), senderName, bodyText)
    else
        formatted = string.format('<font color="#B888FF"><b>%s</b></font>  <font color="#F6F1FF">%s</font>', senderName, bodyText)
    end

    UI.New("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = formatted,
        Face = "Medium",
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        RichText = true,
        TextWrapped = true,
        Parent = row,
    })

    task.defer(function()
        ChatLogScroll.CanvasPosition = Vector2.new(0, math.max(0, ChatLogScroll.AbsoluteCanvasSize.Y - ChatLogScroll.AbsoluteWindowSize.Y))
    end)
end

local function SendChatMessage()
    local txt = ChatInput.Text
    if not txt or txt:match("^%s*$") then return end
    ChatInput.Text = ""
    SendChatSig:Fire("Global", txt)
end

SendBtn.MouseButton1Click:Connect(SendChatMessage)
ChatInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then SendChatMessage() end
end)

ChatMessageSig:Connect(function(msg)
    if not IsSessionActive() or type(msg) ~= "table" then return end
    AppendChatRow(msg)
    local senderPlr = Players:FindFirstChild(tostring(msg.Sender or ""))
    if senderPlr then
        ShowChatBubble(senderPlr, tostring(msg.Text or ""))
    end
    if not ChatBoxFrame:GetAttribute("IsOpen") then
        ChatBadge.Visible = true
    end
end)

local function ToggleChat(forceState)
    local nextState = (forceState ~= nil) and forceState or (not ChatBoxFrame:GetAttribute("IsOpen"))
    if nextState then
        ChatBadge.Visible = false
    end
    UI.Present(ChatBoxFrame, nextState)
end

local function ToggleMain(forceState)
    local nextState = (forceState ~= nil) and forceState or (not MainFrame:GetAttribute("IsOpen"))
    UI.Present(MainFrame, nextState)
end

ChatToggleBtn.MouseButton1Click:Connect(function() ToggleChat() end)
ChatCloseBtn.MouseButton1Click:Connect(function() ToggleChat(false) end)
ToggleBtn.MouseButton1Click:Connect(function() ToggleMain() end)
CloseBtn.MouseButton1Click:Connect(function() ToggleMain(false) end)
end

-- ============================================================================
-- 12. SCRIPT-USER ONLY REPLICATOR (RTR_Net + UNIVERSAL P2P ANIMATOR CARRIER)
--     - Only players running this script see Morphs & Custom Animations
--     - Real-time Morph, Sync Lock, Animation & Speed sync across script users
-- ============================================================================
local SortedAnimNames = {}
local SortedAnimIndexByName = {}
local SortedEmoteNames = {}
local SortedEmoteIndexByName = {}

local function RebuildSortedAssetIndices()
    table.clear(SortedAnimNames)
    table.clear(SortedAnimIndexByName)
    table.clear(SortedEmoteNames)
    table.clear(SortedEmoteIndexByName)

    local dFolder = AnimFolder and AnimFolder:FindFirstChild("D")
    if dFolder then
        for _, seq in ipairs(dFolder:GetChildren()) do
            local cleanName = seq.Name:sub(1, -2)
            table.insert(SortedAnimNames, cleanName)
        end
        table.sort(SortedAnimNames)
        for i, name in ipairs(SortedAnimNames) do
            SortedAnimIndexByName[name] = i
        end
    end

    if EmotesFolder then
        for _, seq in ipairs(EmotesFolder:GetChildren()) do
            table.insert(SortedEmoteNames, seq.Name)
        end
        table.sort(SortedEmoteNames)
        for i, name in ipairs(SortedEmoteNames) do
            SortedEmoteIndexByName[name] = i
        end
    end
end
RebuildSortedAssetIndices()

local function GetSortedServerPlayers()
    local list = Players:GetPlayers()
    table.sort(list, function(a, b) return a.UserId < b.UserId end)
    return list
end

local function GetPlayerSlot(plrName)
    if plrName == "[BOT]" then return 61 end
    if not plrName or plrName == "" then return 0 end
    for idx, p in ipairs(GetSortedServerPlayers()) do
        if p.Name == plrName then
            return math.clamp(idx, 1, 60)
        end
    end
    return 0
end

local function GetPlayerNameFromSlot(slot)
    if slot == 61 then return "[BOT]" end
    if not slot or slot <= 0 then return "" end
    local list = GetSortedServerPlayers()
    local p = list[slot]
    return (p and p.Name) or ""
end

local CarrierTrack1, CarrierTrack2, CarrierAnimator

local function EnsureCarrierTracks()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not hum or not animator then return nil, nil end

    if CarrierAnimator ~= animator or not CarrierTrack1 or not CarrierTrack2 then
        CarrierAnimator = animator
        local isR15 = (hum.RigType == Enum.HumanoidRigType.R15)
        local id1 = isR15 and "rbxassetid://507766388" or "rbxassetid://180435571"
        local id2 = isR15 and "rbxassetid://507766666" or "rbxassetid://180435792"

        pcall(function()
            local a1 = Instance.new("Animation")
            a1.Name = "ROCONS_P2P_Carrier1"
            a1.AnimationId = id1
            CarrierTrack1 = animator:LoadAnimation(a1)
            CarrierTrack1.Looped = true
            CarrierTrack1.Priority = Enum.AnimationPriority.Core

            local a2 = Instance.new("Animation")
            a2.Name = "ROCONS_P2P_Carrier2"
            a2.AnimationId = id2
            CarrierTrack2 = animator:LoadAnimation(a2)
            CarrierTrack2.Looped = true
            CarrierTrack2.Priority = Enum.AnimationPriority.Core
        end)
    end
    return CarrierTrack1, CarrierTrack2
end

BroadcastMyP2PState = function()
    if not IsSessionActive() then return end
    pcall(function()
        if #SortedAnimNames == 0 and AnimFolder then
            RebuildSortedAssetIndices()
        end
        local t1, t2 = EnsureCarrierTracks()
        if not t1 or not t2 then return end

        local genderCode = (MyGender == "F" and 2) or (MyGender == "FB" and 3) or 1
        local morphedBit = (MyMorphed or MyStatus == "Synced") and 1 or 0
        local statusCode = 0
        local targetSlot = 0
        if MyStatus == "Synced" then
            statusCode = (MyRole == "S") and 3 or 2
            targetSlot = GetPlayerSlot(MySyncPartner)
        elseif MyStatus == "Emoting" then
            statusCode = 4
        end

        local pkt1 = ((genderCode - 1) * 2 + morphedBit) * 512 + (statusCode * 64) + targetSlot
        local speed1 = 11 + (pkt1 / 2048)

        local animIdx = 0
        if MyStatus == "Synced" and MyCurrentAnim ~= "" then
            animIdx = SortedAnimIndexByName[MyCurrentAnim] or 0
        elseif MyStatus == "Emoting" and MyCurrentAnim ~= "" then
            animIdx = SortedEmoteIndexByName[MyCurrentAnim] or 0
        end
        local speedStep = math.clamp(math.floor(MyAnimSpeed * 10 + 0.5), 2, 30)
        local botMorphCode = 0
        if MyStatus == "Synced" and MySyncPartner == "[BOT]" then
            botMorphCode = (SelectedBotMorph == "M" and 1) or (SelectedBotMorph == "FB" and 3) or 2
        end
        local pkt2 = (botMorphCode * 8192) + (speedStep * 256) + math.clamp(animIdx, 0, 255)
        local speed2 = 51 + (pkt2 / 2048)

        if not t1.IsPlaying then
            t1:Play(0, 0.0001, speed1)
        end
        t1:AdjustWeight(0.0001, 0)
        t1:AdjustSpeed(speed1)

        if not t2.IsPlaying then
            t2:Play(0, 0.0001, speed2)
        end
        t2:AdjustWeight(0.0001, 0)
        t2:AdjustSpeed(speed2)
    end)
end

local function StopRemoteTrack(trackKey)
    local rt = RemoteTracks[trackKey]
    if rt then
        if rt.Track then
            pcall(function() rt.Track.Stop() end)
        end
        RemoteTracks[trackKey] = nil
    end
end

local function ApplyRemoteMorphState(char, shouldMorph, gender)
    if not char or not char.Parent then return end
    local g = (gender and gender ~= "") and gender or "M"
    local existingMorph = char:FindFirstChild("Morph")
    if shouldMorph then
        if not existingMorph or existingMorph:GetAttribute("ROCONS_MorphGender") ~= g then
            if MorphsFolder then
                local tpl = MorphsFolder:FindFirstChild(g)
                if tpl then
                    ApplyMorph(char, tpl, g, false)
                elseif UVMorph.Genders[g] then
                    UVMorph.Apply(char, g)
                end
            end
        end
    else
        if existingMorph or char:FindFirstChild(UVMorph.ModelName) then
            UVMorph.Remove(char)
            RemoveMorph(char)
            RemoveR6Bridge(char)
        end
    end
end

local function ReconcilePlayerState(key, payload)
    if not IsSessionActive() or type(payload) ~= "table" then return end
    if not IsUniversalMode then
        payload.IsScriptUser = true
    end
    PlayersDatabase[key] = payload
    if payload.UserId and payload.Title and payload.Title ~= "" then
        RankTitlesByUserId[payload.UserId] = payload.Title
    end
    RefreshOverheads({ [key] = payload })

    -- [A] Reconcile OTHER script user's Morph, Bot, Sync Request, Lock & Animation
    if key ~= LocalPlayer.Name then
        if IsUniversalMode and not payload.IsScriptUser then
            return
        end

        local otherPlr = Players:FindFirstChild(key)
        local otherChar = otherPlr and otherPlr.Character
        local botKey = "ROCONS_BOT_" .. key
        local existingBot = Workspace:FindFirstChild(botKey)

        -- 1. If this script user pressed Sync on us, lock BOTH characters into Sync immediately!
        local recentlyBroke = (os.clock() - (SyncGuards.BreakAt[key] or 0)) < 3.5
        local wantsSyncWithMe = (not recentlyBroke) and (
            (payload.Request == LocalPlayer.Name)
            or (payload.Status == "Synced" and payload.SyncPartner == LocalPlayer.Name)
        )

        if wantsSyncWithMe and not IgnoreInvites then
            local theirRole = (payload.Role == "S") and "S" or "D"
            local myOppositeRole = (theirRole == "D") and "S" or "D"
            if MyStatus ~= "Synced" or MySyncPartner ~= key then
                if payload.Request == LocalPlayer.Name then
                    SyncAcceptSig:Fire(key, myOppositeRole, theirRole)
                end
                StartSyncSession(key, myOppositeRole)
                UpdateHeaderStatusBadge()
                local disp = payload.DisplayName or (otherPlr and otherPlr.DisplayName) or key
                ShowNotification("ซิงค์และล็อกตัวละครกับ " .. disp .. " แล้ว!", 3, "success")
            end
        elseif MyStatus == "Synced" and MySyncPartner == key and payload.Status == "Idle" and payload.SyncPartner == "" then
            -- Partner broke sync
            BreakSyncSession(true)
            ShowNotification("คู่ซิงค์ของคุณหยุดการซิงค์แล้ว", 2, "info")
            return
        end

        -- 2. Apply or remove remote script user's Morph (only visible to us because we run the script!)
        if otherChar then
            local shouldMorph = (payload.Morphed == true) or (payload.Status == "Synced")
            ApplyRemoteMorphState(otherChar, shouldMorph, payload.Gender)
        end

        -- 3. Handle remote script user's Bot if they spawned one
        if payload.Bot and payload.Bot.Active == true then
            if not existingBot and not SpawningLocks[botKey] and otherChar then
                task.spawn(function()
                    local bm = SpawnBotModel(otherChar, botKey, payload.Bot.Username or key, payload.Bot.Morph or "F", payload.Bot.Role or "S")
                    if bm and LocalPlayer.Character then
                        CreateNoCollide(LocalPlayer.Character, bm)
                    end
                end)
            end
        else
            StopRemoteTrack(botKey)
            if existingBot then
                pcall(function() existingBot:Destroy() end)
            end
        end

        -- 4. If we are synced WITH this player, sync their chosen Animation & Speed onto both characters!
        if MyStatus == "Synced" and MySyncPartner == key then
            local spd = tonumber(payload.AnimSpeed) or 1
            if math.abs(MyAnimSpeed - spd) > 0.02 then
                MyAnimSpeed = spd
                SpeedLabel.Text = string.format("ความเร็วท่า · %.1fx", MyAnimSpeed)
                local ratio = math.clamp((MyAnimSpeed - 0.2) / 2.8, 0.05, 1)
                UI.Tween(SpeedFill, 0.14, { Size = UDim2.fromScale(ratio, 1) })
                if MyAnimTrack then MyAnimTrack.Speed = MyAnimSpeed end
                if PartnerAnimTrack then PartnerAnimTrack.Speed = MyAnimSpeed end
            end
            if payload.CurrentAnim and payload.CurrentAnim ~= "" and payload.CurrentAnim ~= MyCurrentAnim and (os.clock() - SyncGuards.AnimChangeAt) > 2.5 then
                MyCurrentAnim = payload.CurrentAnim
                PlaySyncAnimation(MyCurrentAnim)
            end
            return
        end

        -- 5. Otherwise, if they are synced with a 3rd player or with their own Bot, render their animation & lock!
        if payload.Status == "Synced" and payload.CurrentAnim and payload.CurrentAnim ~= "" and AnimFolder then
            local spd = tonumber(payload.AnimSpeed) or 1
            local rRole = (payload.Role == "S") and "S" or "D"
            local rFolder = AnimFolder:FindFirstChild(rRole)
            local rSuffix = (rRole == "S") and "F" or "M"
            local rSeq = rFolder and rFolder:FindFirstChild(payload.CurrentAnim .. rSuffix)

            if otherChar and rSeq then
                if not RemoteTracks[key] or RemoteTracks[key].Anim ~= payload.CurrentAnim then
                    StopRemoteTrack(key)
                    RemoteTracks[key] = {
                        Track = PlayKeyframeAnim(otherChar, rSeq, spd),
                        Anim = payload.CurrentAnim,
                    }
                elseif RemoteTracks[key] and RemoteTracks[key].Track then
                    RemoteTracks[key].Track.Speed = spd
                end
            end

            if payload.SyncPartner == "[BOT]" then
                local botObj = Workspace:FindFirstChild(botKey)
                local bRole = (rRole == "D") and "S" or "D"
                local bFolder = AnimFolder:FindFirstChild(bRole)
                local bSuffix = (bRole == "S") and "F" or "M"
                local bSeq = bFolder and bFolder:FindFirstChild(payload.CurrentAnim .. bSuffix)
                if botObj and bSeq then
                    if not RemoteTracks[botKey] or RemoteTracks[botKey].Anim ~= payload.CurrentAnim then
                        StopRemoteTrack(botKey)
                        RemoteTracks[botKey] = {
                            Track = PlayKeyframeAnim(botObj, bSeq, spd),
                            Anim = payload.CurrentAnim,
                        }
                    elseif RemoteTracks[botKey] and RemoteTracks[botKey].Track then
                        RemoteTracks[botKey].Track.Speed = spd
                    end
                end
            end
        elseif payload.Status == "Emoting" and payload.CurrentAnim and payload.CurrentAnim ~= "" and EmotesFolder then
            local spd = tonumber(payload.AnimSpeed) or 1
            local eSeq = EmotesFolder:FindFirstChild(payload.CurrentAnim)
            if otherChar and eSeq then
                if not RemoteTracks[key] or RemoteTracks[key].Anim ~= payload.CurrentAnim then
                    StopRemoteTrack(key)
                    RemoteTracks[key] = {
                        Track = PlayKeyframeAnim(otherChar, eSeq, spd),
                        Anim = payload.CurrentAnim,
                    }
                elseif RemoteTracks[key] and RemoteTracks[key].Track then
                    RemoteTracks[key].Track.Speed = spd
                end
            end
        else
            StopRemoteTrack(key)
            StopRemoteTrack(botKey)
        end
        return
    end

    -- [B] Reconcile OUR OWN entry when updated by an RTR_Net server
    if payload.Request and payload.Request ~= "" and MyStatus ~= "Synced" then
        if IgnoreInvites then
            PlayerUpdateSig:Fire({ Request = "", RequesterGender = "" })
        else
            local reqPlr = Players:FindFirstChild(payload.Request)
            if reqPlr then
                local reqGender = payload.RequesterGender or "M"
                local myRole = ResolveMyRole(reqGender)
                local theirRole = (myRole == "S") and "D" or "S"
                SyncAcceptSig:Fire(payload.Request, myRole, theirRole)
                StartSyncSession(payload.Request, myRole)
                UpdateHeaderStatusBadge()
                ShowNotification("ซิงค์และล็อกตัวละครกับ " .. (reqPlr.DisplayName or payload.Request) .. " แล้ว!", 3, "success")
            end
        end
    end

    if MyStatus == "Synced" then
        if payload.AnimSpeed and math.abs(MyAnimSpeed - payload.AnimSpeed) > 0.02 then
            MyAnimSpeed = payload.AnimSpeed
            SpeedLabel.Text = string.format("ความเร็วท่า · %.1fx", MyAnimSpeed)
            local ratio = math.clamp((MyAnimSpeed - 0.2) / 2.8, 0.05, 1)
            UI.Tween(SpeedFill, 0.14, { Size = UDim2.fromScale(ratio, 1) })
            if MyAnimTrack then MyAnimTrack.Speed = MyAnimSpeed end
            if PartnerAnimTrack then PartnerAnimTrack.Speed = MyAnimSpeed end
        end
        if payload.CurrentAnim and payload.CurrentAnim ~= "" and payload.CurrentAnim ~= MyCurrentAnim and (os.clock() - SyncGuards.AnimChangeAt) > 2.5 then
            MyCurrentAnim = payload.CurrentAnim
            PlaySyncAnimation(MyCurrentAnim)
        end
    end
end

StateChangedSig:Connect(function(key, payload)
    if not IsSessionActive() then return end
    if key == "__ALL__" and type(payload) == "table" then
        PlayersDatabase = payload
        for plrName, entry in pairs(payload) do
            if type(entry) == "table" then
                ReconcilePlayerState(plrName, entry)
            end
        end
        PopulatePlayersTab(PlayersDatabase)
        return
    elseif key == "__REMOVED__" then
        local remName = tostring(payload)
        StopRemoteTrack(remName)
        StopRemoteTrack("ROCONS_BOT_" .. remName)
        PlayersDatabase[remName] = nil
        PopulatePlayersTab(PlayersDatabase)
        return
    end

    if type(payload) == "table" then
        ReconcilePlayerState(key, payload)
        PopulatePlayersTab(PlayersDatabase)
    end
end)

-- Universal P2P Scanner: Detects other players running ROCONS in ANY map via Animator carrier tracks
local LastKnownP2PSig = {}

local function ScanP2PCarriers()
    if #SortedAnimNames == 0 and AnimFolder then
        RebuildSortedAssetIndices()
    end
    local changedTab = false

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if animator then
                local pkt1, pkt2
                for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                    local ok, spd = pcall(function() return t.Speed end)
                    if ok and type(spd) == "number" then
                        if spd >= 10.9 and spd < 50.5 then
                            pkt1 = math.floor((spd - 11) * 2048 + 0.5)
                        elseif spd >= 50.9 and spd < 100.5 then
                            pkt2 = math.floor((spd - 51) * 2048 + 0.5)
                        end
                    end
                end

                if pkt1 and pkt1 >= 0 then
                    local targetSlot = pkt1 % 64
                    local statusCode = math.floor(pkt1 / 64) % 8
                    local gm = math.floor(pkt1 / 512)
                    local morphedBit = gm % 2
                    local genderCode = math.floor(gm / 2) + 1

                    local gender = (genderCode == 2 and "F") or (genderCode == 3 and "FB") or "M"
                    local morphed = (morphedBit == 1)
                    local status = "Idle"
                    local role = "D"
                    local partner = ""
                    local requestTarget = ""

                    if statusCode == 1 then
                        requestTarget = GetPlayerNameFromSlot(targetSlot)
                    elseif statusCode == 2 or statusCode == 3 then
                        status = "Synced"
                        role = (statusCode == 3) and "S" or "D"
                        partner = GetPlayerNameFromSlot(targetSlot)
                    elseif statusCode == 4 then
                        status = "Emoting"
                    end

                    local animName = ""
                    local animSpeed = 1
                    local botInfo = { Active = false }

                    if pkt2 and pkt2 >= 0 then
                        local animIdx = pkt2 % 256
                        local speedStep = math.floor(pkt2 / 256) % 32
                        local botMorphCode = math.floor(pkt2 / 8192) % 4

                        if speedStep >= 2 and speedStep <= 30 then
                            animSpeed = speedStep / 10
                        end
                        if status == "Synced" and animIdx > 0 then
                            animName = SortedAnimNames[animIdx] or ""
                        elseif status == "Emoting" and animIdx > 0 then
                            animName = SortedEmoteNames[animIdx] or ""
                        end
                        if status == "Synced" and partner == "[BOT]" and botMorphCode > 0 then
                            botInfo = {
                                Active = true,
                                Username = plr.Name,
                                Morph = (botMorphCode == 1 and "M") or (botMorphCode == 3 and "FB") or "F",
                                Role = (role == "D") and "S" or "D",
                            }
                        end
                    end

                    local sigStr = string.format("%s|%s|%s|%s|%s|%s|%.1f", gender, tostring(morphed), status, role, partner, animName, animSpeed)
                    local entry = PlayersDatabase[plr.Name] or {
                        UserId = plr.UserId,
                        DisplayName = plr.DisplayName,
                        Age = "18",
                        Title = "",
                    }
                    if not entry.IsScriptUser then
                        changedTab = true
                    end
                    entry.IsScriptUser = true
                    entry.UserId = plr.UserId
                    entry.DisplayName = plr.DisplayName
                    entry.Gender = gender
                    entry.Morphed = morphed
                    entry.Status = status
                    entry.Role = role
                    entry.SyncPartner = partner
                    entry.Request = requestTarget
                    entry.RequesterGender = gender
                    entry.CurrentAnim = animName
                    entry.AnimSpeed = animSpeed
                    entry.Bot = botInfo

                    if LastKnownP2PSig[plr.Name] ~= sigStr then
                        LastKnownP2PSig[plr.Name] = sigStr
                        changedTab = true
                    end
                    ReconcilePlayerState(plr.Name, entry)
                end
            end
        end
    end

    if changedTab then
        PopulatePlayersTab(PlayersDatabase)
    end
end

-- Non-blocking background Asset Pack loader (ensures Delta never freezes on first run)
task.spawn(function()
    if not AnimFolder or not MorphsFolder or not EmotesFolder or not SoundsFolder then
        ShowNotification("กำลังเตรียมชุดข้อมูลท่าซิงค์และโมเดล...", 3, "info")
        if not MorphsFolder then
            MorphsFolder = ExtractPackFolder(LoadAssetPack(AssetUrls.Morphs, AssetFiles.Morphs, "Morphs"), "Morphs")
            MountLoadedFolder(MorphsFolder, "Morphs", true)
        end
        if not EmotesFolder then
            EmotesFolder = ExtractPackFolder(LoadAssetPack(AssetUrls.Emotes, AssetFiles.Emotes, "Emotes"), "Emotes")
            MountLoadedFolder(EmotesFolder, "Emotes", false)
            PopulateEmotesTab()
        end
        if not SoundsFolder then
            SoundsFolder = ExtractPackFolder(LoadAssetPack(AssetUrls.Sounds, AssetFiles.Sounds, "Sounds"), "Sounds")
            MountLoadedFolder(SoundsFolder, "Sounds", false)
        end
        if not AnimFolder then
            AnimFolder = ExtractPackFolder(LoadAssetPack(AssetUrls.Anims, AssetFiles.Anims, "Anim"), "Anim")
            MountLoadedFolder(AnimFolder, "Anim", false)
            PopulateAnimsTab()
        end
        RebuildSortedAssetIndices()
        ShowNotification("โหลดข้อมูลท่าซิงค์และท่าทางครบ 100% แล้ว!", 3, "success")
    end
end)

-- Initial Database Fetch & Overhead Setup
task.spawn(function()
    local initialDB = GetAllPlayersFn.Invoke()
    if type(initialDB) == "table" then
        PlayersDatabase = initialDB
        for plrName, entry in pairs(initialDB) do
            if type(entry) == "table" then
                ReconcilePlayerState(plrName, entry)
            end
        end
        PopulatePlayersTab(PlayersDatabase)
    end
    ProfileSetupSig:Fire(MyAge, MyGender)
    BroadcastMyP2PState()
    UpdateHeaderStatusBadge()
end)

-- Fast P2P & Morph Reconcile Loop (0.2s interval so script users see each other's Morphs, Sync Lock & Animations in real time)
task.spawn(function()
    while IsSessionActive() do
        pcall(function()
            BroadcastMyP2PState()
            ScanP2PCarriers()
            RefreshOverheads(PlayersDatabase)
        end)
        task.wait(0.2)
    end
end)

ShowNotification("โหลด ROCONS Reborn v2.5 สำเร็จ · กรุณาเลือกเพศตัวละครของคุณ", 3, "info")
print("[ROCONS v2.5] โหลดสำเร็จ (ซิงค์เฉพาะคนรันสคริปต์ + ล็อกตัวละครไม่ดิ้น 100% + UI ภาษาไทย)")
