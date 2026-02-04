local addonName, ns = ...

-- Addon Version
local version = "0.0.1"

function Qloot:CreateConfigPanel()
    if Qloot.ConfigPanel then
        Qloot.ConfigPanel:Show()
        return
    end

    if not QlootDB then
        Qloot:LoadDefaults()
    end

    local p = CreateFrame("Frame", "QlootConfig", UIParent)
    Qloot.ConfigPanel = p

    p:SetSize(340, 420) -- Taller to fit new checkboxes
    p:SetPoint("CENTER")
    p:SetFrameStrata("HIGH")
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)

    -- Apply EHTweaks-style Skin with Fallback
    if Qloot.Skin and Qloot.Skin.ApplyWindow then
        Qloot.Skin.ApplyWindow(p, "Qloot Configuration")
    else
        p:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        p:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        p:SetBackdropBorderColor(0, 0, 0, 1)

        local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -6)
        title:SetText("Qloot Configuration")
        
        local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        close:SetScript("OnClick", function() p:Hide() end)
    end

    
    local content = CreateFrame("Frame", nil, p)
    content:SetPoint("TOPLEFT", 10, -35)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    
    if Qloot.Skin and Qloot.Skin.ApplyInset then
        Qloot.Skin.ApplyInset(content)
    else
        content:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        content:SetBackdropColor(0, 0, 0, 0.3)
        content:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end

    -- Section Header: Behavior
    local behaviorHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    behaviorHeader:SetPoint("TOPLEFT", 12, -8)
    behaviorHeader:SetText("Behavior")
    behaviorHeader:SetTextColor(1, 0.82, 0) -- Gold

    local function CreateCheck(label, key, x, y)
        local cb = CreateFrame("CheckButton", "QlootCheck_"..key, content, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(QlootDB[key])
        
        local text = _G[cb:GetName().."Text"]
        if text then
            text:SetText(label)
            text:SetTextColor(1, 1, 1) -- White
        end
        
        cb:SetScript("OnClick", function(self)
            QlootDB[key] = (self:GetChecked() == 1)
        end)
        return cb
    end

    CreateCheck("Enable Auto Loot", "enabled", 12, -28)
    CreateCheck("Show Window on Locked/BoP Items", "showOnLocked", 12, -58)
    CreateCheck("Show Window on Full Inventory", "showOnFull", 12, -88)
    CreateCheck("Play Sound on Full Inventory", "playFullSound", 12, -118)
    CreateCheck("Warn Leftover Items", "warnUnlooted", 12, -148)
    CreateCheck("Debug Mode", "debugMode", 12, -178)

    -- Section Header: Performance
    local perfHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    perfHeader:SetPoint("TOPLEFT", 12, -208)
    perfHeader:SetText("Performance")
    perfHeader:SetTextColor(1, 0.82, 0)

    local slider = CreateFrame("Slider", "QlootDelaySlider", content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 18, -230)
    slider:SetWidth(280)
    slider:SetMinMaxValues(50, 500)
    slider:SetValueStep(10)

    local currentDelay = QlootDB.lootDelay or 150
    _G[slider:GetName() .. "Low"]:SetText("50ms")
    _G[slider:GetName() .. "High"]:SetText("500ms")
    _G[slider:GetName() .. "Text"]:SetText("Loot Delay: " .. currentDelay .. "ms")
    slider:SetValue(currentDelay)

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        QlootDB.lootDelay = value
        _G[self:GetName() .. "Text"]:SetText("Loot Delay: " .. value .. "ms")
        if Qloot.LootQueue then
            Qloot.LootQueue.DELAY = value / 1000
        end
    end)

    local reloadBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reloadBtn:SetSize(120, 25)
    reloadBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    reloadBtn:SetText("Reload UI")
    reloadBtn:SetScript("OnClick", ReloadUI)

    -- Footer: Version & Author
    local note = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("BOTTOMLEFT", 10, 10)
    note:SetText("v" .. version .. " by Skulltrail")
    note:SetTextColor(0.6, 0.6, 0.6)
end

SLASH_QLOOT1 = "/qloot"
SlashCmdList["QLOOT"] = function()
    Qloot:CreateConfigPanel()
end
