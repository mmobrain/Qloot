local addonName, ns = ...

local version = "0.0.5"

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

    p:SetSize(640, 450)
    p:SetPoint("CENTER")
    p:SetFrameStrata("HIGH")
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)

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

    local leftContent = CreateFrame("Frame", nil, p)
    leftContent:SetPoint("TOPLEFT", 10, -35)
    leftContent:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", 320, 10)
    
    local rightContent = CreateFrame("Frame", nil, p)
    rightContent:SetPoint("TOPLEFT", p, "TOPLEFT", 330, -35)
    rightContent:SetPoint("BOTTOMRIGHT", -10, 10)
    
    local function ApplyInsetSkin(f)
        if Qloot.Skin and Qloot.Skin.ApplyInset then
            Qloot.Skin.ApplyInset(f)
        else
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            f:SetBackdropColor(0, 0, 0, 0.3)
            f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
        end
    end
    
    ApplyInsetSkin(leftContent)
    ApplyInsetSkin(rightContent)

    -- ==================== LEFT PANE ====================
    local behaviorHeader = leftContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    behaviorHeader:SetPoint("TOPLEFT", 12, -8)
    behaviorHeader:SetText("Behavior")
    behaviorHeader:SetTextColor(1, 0.82, 0)

    local function CreateCheck(label, key, x, y)
        local cb = CreateFrame("CheckButton", "QlootCheck_"..key, leftContent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(QlootDB[key])
        
        local text = _G[cb:GetName().."Text"]
        if text then
            text:SetText(label)
            text:SetTextColor(1, 1, 1)
        end
        
        cb:SetScript("OnClick", function(self)
            QlootDB[key] = (self:GetChecked() == 1)
        end)
        return cb
    end

    CreateCheck("Enable Auto Loot",                "enabled",       12, -28)
    CreateCheck("Show Window on Locked/BoP Items", "showOnLocked",  12, -58)
    CreateCheck("Show Window on Full Inventory",   "showOnFull",    12, -88)
    CreateCheck("Play Sound on Full Inventory",    "playFullSound", 12, -118)
    CreateCheck("Warn Leftover Items",             "warnUnlooted",  12, -148)
    CreateCheck("Shift-key to Skip Auto-Loot",     "shiftBypass",   12, -178)    

    -- NEW: Filtering toggle (keeps rules but disables execution)
    local filterToggle = CreateCheck("Enable Loot Filtering", "filterEnabled", 12, -208)
    filterToggle:SetScript("OnClick", function(self)
        QlootDB.filterEnabled = (self:GetChecked() == 1)
        if Qloot.CompileFilters then
            Qloot:CompileFilters()
        end
    end)
    
    CreateCheck("Debug Mode",                      "debugMode",     12, -238)

    local perfHeader = leftContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    perfHeader:SetPoint("TOPLEFT", 12, -268)
    perfHeader:SetText("Performance")
    perfHeader:SetTextColor(1, 0.82, 0)

    local slider = CreateFrame("Slider", "QlootDelaySlider", leftContent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 18, -290)
    slider:SetWidth(270)
    slider:SetMinMaxValues(50, 500)
    slider:SetValueStep(10)

    local currentDelay = QlootDB.lootDelay or 110
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

    local reloadBtn = CreateFrame("Button", nil, leftContent, "UIPanelButtonTemplate")
    reloadBtn:SetSize(120, 25)
    reloadBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    reloadBtn:SetText("Apply (Reload UI)")
    reloadBtn:SetScript("OnClick", ReloadUI)

    local note = leftContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("BOTTOMLEFT", 10, 10)
    note:SetText("v" .. version .. " by Skulltrail")
    note:SetTextColor(0.6, 0.6, 0.6)

    -- ==================== RIGHT PANE ====================
    local filterHeader = rightContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterHeader:SetPoint("TOPLEFT", 12, -8)
    filterHeader:SetText("Loot Filters (Do Not Loot)")
    filterHeader:SetTextColor(1, 0.82, 0)

    local filterSub = rightContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterSub:SetPoint("TOPLEFT", 12, -24)
    filterSub:SetText("Rules: q0, q1... or exact name, or wildcard (Scroll*)")
    filterSub:SetTextColor(0.8, 0.8, 0.8)

    local filterBg = CreateFrame("Frame", nil, rightContent)
    filterBg:SetPoint("TOPLEFT", 12, -45)
    filterBg:SetPoint("BOTTOMRIGHT", -30, 45)
    filterBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    filterBg:SetBackdropColor(0, 0, 0, 0.6)
    filterBg:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    filterBg:EnableMouse(true)

    local filterScroll = CreateFrame("ScrollFrame", "QlootFilterScroll", filterBg, "UIPanelScrollFrameTemplate")
    filterScroll:SetPoint("TOPLEFT", 4, -4)
    filterScroll:SetPoint("BOTTOMRIGHT", -4, 4)

    local filterEdit = CreateFrame("EditBox", "QlootFilterEdit", filterScroll)
    filterEdit:SetMultiLine(true)
    filterEdit:SetAutoFocus(false)
    filterEdit:SetFontObject("ChatFontNormal")
    filterEdit:SetWidth(230)
    filterEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    filterScroll:SetScrollChild(filterEdit)
    filterEdit:SetText(QlootDB.filterList or "")
    filterEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            QlootDB.filterList = self:GetText()
            Qloot:CompileFilters()
        end
    end)
    
    -- DRAG AND DROP LOGIC
    local function HandleItemDrop()
        if not CursorHasItem() then return end
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" then
            local itemName = GetItemInfo(itemLink) or GetItemInfo(itemID)
            if not itemName and itemLink then
                itemName = itemLink:match("%[(.-)%]")
            end
            if itemName then
                local currentText = filterEdit:GetText()
                local appendText = itemName
                if currentText ~= "" and currentText:sub(-1) ~= "\n" then
                    appendText = "\n" .. itemName
                end
                filterEdit:SetText(currentText .. appendText .. "\n")
                ClearCursor() -- Drops the item successfully without deleting it
                
                QlootDB.filterList = filterEdit:GetText()
                Qloot:CompileFilters()
            end
        end
    end

    filterEdit:SetScript("OnReceiveDrag", HandleItemDrop)
    filterEdit:HookScript("OnMouseUp", HandleItemDrop)
    
    filterBg:SetScript("OnReceiveDrag", HandleItemDrop)
    filterBg:SetScript("OnMouseUp", HandleItemDrop)

    local logBtn = CreateFrame("Button", nil, rightContent, "UIPanelButtonTemplate")
    logBtn:SetSize(120, 25)
    logBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    logBtn:SetText("View Skip Log")
    logBtn:SetScript("OnClick", function() Qloot:ShowLogWindow() end)
end


SLASH_QLOOT1 = "/qloot"
SlashCmdList["QLOOT"] = function()
    Qloot:CreateConfigPanel()
end
