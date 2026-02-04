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

function Qloot:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Qloot:|r " .. msg)
end

function Qloot:Debug(msg)
    if QlootDB and QlootDB.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF9900[Qloot Debug]|r " .. msg)
    end
end

function Qloot:LoadDefaults()
    if not QlootDB then QlootDB = {} end
    
    local defaults = {
        enabled = true,
        lootDelay = 150,           -- Milliseconds
        showOnLocked = true,
        showOnFull = true,
        playFullSound = true,
        fullSoundID = 1,
        debugMode = false,         -- Default off
        warnUnlooted = true,       -- Default on
    }
    
    for k, v in pairs(defaults) do
        if QlootDB[k] == nil then
            QlootDB[k] = v
        end
    end
end

function Qloot:Initialize()
    self:LoadDefaults()
    
    -- Unregister default loot frame from auto-showing
    LootFrame:UnregisterEvent("LOOT_OPENED")
    
    -- Set auto-loot CVar
    if isWOTLK then
        SetCVar("autoLootDefault", "1")
    elseif isTBC then
        SetCVar("autoLootCorpse", "1")
    end
    
    if self.HookErrorMessages then self:HookErrorMessages() end
    
    self:Print("Loaded. Type /qloot for options.")
    if QlootDB.debugMode then self:Debug("Debug mode is ENABLED") end
end

-- Event Handler
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
