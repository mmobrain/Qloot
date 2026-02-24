local addonName, ns = ...

Qloot = CreateFrame("Frame", "QlootMainFrame")
Qloot.State = {
    isLooting = false,
    lootWindowHidden = false,
    isItemLocked = false,
    inventoryFullSoundPlayed = false,
}

local isTBC = (select(4, GetBuildInfo()) == 20400)
local isWOTLK = (select(4, GetBuildInfo()) == 30300)

-- Log structures for skipped items
Qloot.SkippedLinks = {}
Qloot.SessionLog = {}
Qloot.MAX_LOG_LINES = 5000

function Qloot:LoadDefaults()
    if not QlootDB then QlootDB = {} end
    
    local defaults = {
        enabled = true,
        lootDelay = 110,
        showOnLocked = true,
        showOnFull = true,
        playFullSound = true,
        fullSoundID = 1,
        debugMode = false,
        warnUnlooted = true,
        shiftBypass = true,        
        filterEnabled = true,
        filterList = "",
    }
    
    for k, v in pairs(defaults) do
        if QlootDB[k] == nil then
            QlootDB[k] = v
        end
    end
end


function Qloot:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Qloot:|r " .. msg)
end

function Qloot:Debug(msg)
    if QlootDB and QlootDB.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF9900[Qloot Debug]|r " .. msg)
    end
end

function Qloot:ShowLogWindow()
    if not self.LogFrame then
        local f = CreateFrame("Frame", "QlootLogFrame", UIParent)
        f:SetSize(460, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        
        if Qloot.Skin and Qloot.Skin.ApplyWindow then
            Qloot.Skin.ApplyWindow(f, "Qloot Skip Log")
        else
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1, insets = {left=0, right=0, top=0, bottom=0},
            })
            f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            f:SetBackdropBorderColor(0, 0, 0, 1)
            
            local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            title:SetPoint("TOP", 0, -6)
            title:SetText("Qloot Skip Log")
            
            local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", 0, 0)
            close:SetScript("OnClick", function() f:Hide() end)
        end
        
        local sf = CreateFrame("ScrollFrame", "QlootLogScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 15, -30)
        sf:SetPoint("BOTTOMRIGHT", -35, 15)
        
        local editBox = CreateFrame("EditBox", "QlootLogEditBox", sf)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetWidth(390)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Hide() end)
        
        sf:SetScrollChild(editBox)
        f.Text = editBox
        self.LogFrame = f
    end
    
    local lines = {}
    if #self.SessionLog == 0 then
        table.insert(lines, "No items have been skipped this session.")
    else
        local displayLimit = math.min(#self.SessionLog, 200)
        for i = #self.SessionLog, #self.SessionLog - displayLimit + 1, -1 do
            local entry = self.SessionLog[i]
            
            -- Conditionally format the source string to omit "from Unknown"
            local sourceStr = ""
            if entry.source and entry.source ~= "Unknown" then
                sourceStr = " from " .. entry.source
            end
            
            table.insert(lines, string.format("[%s] Skipped %s%s (Rule: %s)", entry.time, entry.link, sourceStr, entry.rule))
        end
        
        if #self.SessionLog > 200 then
            table.insert(lines, string.format("... and %d older entries hidden for performance.", #self.SessionLog - 200))
        end
    end
    
    self.LogFrame.Text:SetText(table.concat(lines, "\n"))
    self.LogFrame.Text:SetCursorPosition(0)
    self.LogFrame.Text:ClearFocus()
    self.LogFrame:Show()
end

function Qloot:Initialize()
    self:LoadDefaults()
    
    if self.CompileFilters then self:CompileFilters() end
    LootFrame:UnregisterEvent("LOOT_OPENED")
    if self.HookErrorMessages then self:HookErrorMessages() end
    
    self:Print("Loaded. Type /qloot for options.")
    if QlootDB.debugMode then self:Debug("Debug mode is ENABLED") end
end

local QlootEvents = CreateFrame("Frame")
QlootEvents:RegisterEvent("ADDON_LOADED")
QlootEvents:RegisterEvent("PLAYER_LOGIN")

QlootEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            Qloot:LoadDefaults()
        end
    elseif event == "PLAYER_LOGIN" then
        Qloot:Initialize()
        
        self:RegisterEvent("LOOT_READY")
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("LOOT_CLOSED")
        self:RegisterEvent("LOOT_BIND_CONFIRM")
        self:RegisterEvent("OPEN_MASTER_LOOT_LIST")
        self:RegisterEvent("UI_ERROR_MESSAGE")
        
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        if Qloot.OnLootReady then Qloot:OnLootReady() end
        
    elseif event == "LOOT_CLOSED" then
        if Qloot.OnLootClosed then Qloot:OnLootClosed() end
        
    elseif event == "UI_ERROR_MESSAGE" then
        if Qloot.HandleErrorMessage then Qloot:HandleErrorMessage(...) end
        
    elseif event == "LOOT_BIND_CONFIRM" or event == "OPEN_MASTER_LOOT_LIST" then
        if Qloot.State.isLooting and Qloot.State.lootWindowHidden then
            if Qloot.ShowLootFrame then Qloot:ShowLootFrame(true) end
        end
    end
end)
