local addonName, ns = ...

local isWOTLK = (select(4, GetBuildInfo()) == 30300)
local autoLootCVarName = isWOTLK and "autoLootDefault" or "autoLootCorpse"

-- Queue Structure
Qloot.LootQueue = {
    items = {}, 
    isProcessing = false,
    lastLootTime = 0,
    DELAY = 0.1 
}

-- ============================================================================
-- FILTER COMPILER & MATCHER
-- ============================================================================
function Qloot:CompileFilters()
    self.Filters = { qualities = {}, exactNames = {}, patterns = {} }
    if not QlootDB or not QlootDB.filterList then return end
    
    for line in string.gmatch(QlootDB.filterList, "[^\r\n]+") do
        local raw = line:match("^%s*(.-)%s*$")
        if raw and raw ~= "" then
            local q = raw:match("^[qQ](%d)$")
            if q then
                self.Filters.qualities[tonumber(q)] = raw
            elseif raw:find("%*") then
                local escaped = raw:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
                local pat = "^" .. escaped:gsub("%*", ".*") .. "$"
                table.insert(self.Filters.patterns, { pattern = pat:lower(), raw = raw })
            else
                self.Filters.exactNames[raw:lower()] = raw
            end
        end
    end
end

function Qloot:GetFilterMatch(link, quality)
    if quality and self.Filters.qualities[quality] then
        return self.Filters.qualities[quality]
    end
    
    if not link then return nil end
    
    local itemName = GetItemInfo(link) or link:match("%[(.-)%]")
    if not itemName then return nil end
    
    local lowerName = itemName:lower()
    
    if self.Filters.exactNames[lowerName] then
        return self.Filters.exactNames[lowerName]
    end
    
    for _, p in ipairs(self.Filters.patterns) do
        if lowerName:find(p.pattern) then
            return p.raw
        end
    end
    
    return nil
end

-- ============================================================================
-- LOOT SOURCE CAPTURE & C++ AUTO-LOOT BYPASS
-- ============================================================================
Qloot.shiftAtInteract  = false
Qloot.shiftCaptureTime = 0
Qloot.lastLootSource = "Unknown"
local SHIFT_CAPTURE_TTL = 2.0 

local CVarTracker = CreateFrame("Frame")
CVarTracker:RegisterEvent("MODIFIER_STATE_CHANGED")
CVarTracker:RegisterEvent("PLAYER_LOGIN")
CVarTracker:SetScript("OnEvent", function(self, event, key, state)
    if event == "PLAYER_LOGIN" then
        SetCVar(autoLootCVarName, IsShiftKeyDown() and "1" or "0")
    elseif key == "LSHIFT" or key == "RSHIFT" then
        SetCVar(autoLootCVarName, state == 1 and "1" or "0")
    end
end)

-- Tracks the source name if a player interacts with an item in their bags (Clams, Lockboxes)
hooksecurefunc("UseContainerItem", function(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if link then
        local itemName = link:match("%[(.-)%]") or GetItemInfo(link)
        if itemName then
            Qloot.lastLootSource = itemName
        end
    end
end)

-- Tracks the source name of physical corpses/objects right-clicked in the 3D world
WorldFrame:HookScript("OnMouseDown", function(_, button)
    if button == "RightButton" then
        -- Priority 1: Mouseover (Most accurate for 3D world clicks)
        local name = UnitName("mouseover")
        
        -- Priority 2: GameTooltip (Good for chests, gameobjects, things without "Unit" status)
        if not name and GameTooltip:IsShown() and GameTooltipTextLeft1 then
            name = GameTooltipTextLeft1:GetText()
        end
        
        -- Priority 3: Target (Fallback if the user clicked their current target very fast)
        if not name then
            name = UnitName("target")
        end
        
        Qloot.lastLootSource = name or "Unknown"
        
        if QlootDB and QlootDB.shiftBypass then
            local isShift = (IsShiftKeyDown() and true) or false
            Qloot.shiftAtInteract  = isShift
            Qloot.shiftCaptureTime = GetTime()
            SetCVar(autoLootCVarName, isShift and "1" or "0")
        end
    end
end)

-- ============================================================================
-- THROTTLE ENGINE
-- ============================================================================
local QlootThrottle = CreateFrame("Frame")
QlootThrottle:SetScript("OnUpdate", function(self, elapsed)
    elapsed = math.min(elapsed, 0.1)
    if not Qloot.State.isLooting then return end
    
    Qloot.LootQueue.DELAY = (QlootDB.lootDelay or 110) / 1000

    if #Qloot.LootQueue.items == 0 then
        Qloot.LootQueue.isProcessing = false
        if Qloot.State.lootWindowHidden and not Qloot.State.isItemLocked then
             CloseLoot()
             Qloot:Debug("Loot window closed - queue empty")
        end
        return
    end
    
    local currentTime = GetTime()
    if currentTime - Qloot.LootQueue.lastLootTime >= Qloot.LootQueue.DELAY then
        Qloot:ProcessNextLootItem()
        Qloot.LootQueue.lastLootTime = currentTime
    end
end)

-- ============================================================================
-- LOOT POPULATION
-- ============================================================================
function Qloot:ShouldBypassAutoLoot()
    if not QlootDB.shiftBypass then return false end
    
    local captureAge = GetTime() - self.shiftCaptureTime
    if captureAge <= SHIFT_CAPTURE_TTL then
        return self.shiftAtInteract
    else
        return (IsShiftKeyDown() and true) or false
    end
end

function Qloot:OnLootReady()
    if not QlootDB.enabled then
        self:Debug("Addon disabled - skipping loot")
        return
    end

    if self:ShouldBypassAutoLoot() then
        self:Debug("Shift held - bypassing Qloot, showing manual window")
        self.State.isLooting = true
        self.State.lootWindowHidden = false
        self:ShowLootFrame(true)
        return
    end

    local numItems = GetNumLootItems()
    self:Debug("LOOT_READY fired - " .. numItems .. " items detected")

    if numItems == 0 then
        CloseLoot()
        self:Debug("No items to loot - closing")
        return
    end

    -- Ultimate fallback if they used an "Interact with Target" keybind instead of clicking
    if (not self.lastLootSource or self.lastLootSource == "Unknown") and UnitExists("target") then
        self.lastLootSource = UnitName("target")
    end

    self.State.isLooting = true
    self.State.lootWindowHidden = true
    self.State.isItemLocked = false
    self.State.inventoryFullSoundPlayed = false

    wipe(self.LootQueue.items)
    wipe(self.SkippedLinks)

    local lockedCount = 0
    for i = 1, numItems do
        local link = GetLootSlotLink(i)
        local _, _, quantity, quality, locked = GetLootSlotInfo(i)

        -- FILTER CHECK
        local filterRule = self:GetFilterMatch(link, quality)
        if filterRule then
            self:Debug("Slot " .. i .. " filtered out by rule: " .. filterRule)
            if link then self.SkippedLinks[link] = true end
            
            table.insert(self.SessionLog, { 
                time = date("%H:%M:%S"), 
                link = link or "currency", 
                rule = filterRule, 
                source = self.lastLootSource or "Unknown" 
            })
            if #self.SessionLog > Qloot.MAX_LOG_LINES then table.remove(self.SessionLog, 1) end
            
        else
            if not locked then
                table.insert(self.LootQueue.items, {
                    slotIndex = i,
                    itemLink  = link,
                    quantity  = quantity,
                    rarity    = quality,
                })
                self:Debug("Queued slot " .. i .. ": " .. (link or "currency") .. " x" .. (quantity or 1))
            else
                self.State.isItemLocked = true
                lockedCount = lockedCount + 1
                self:Debug("Slot " .. i .. " is LOCKED (BoP/Roll): " .. (link or "unknown"))
            end
        end
    end

    self.LootQueue.lastLootTime = 0

    if self.State.isItemLocked and QlootDB.showOnLocked then
        self:ShowLootFrame(true)
        self.LootQueue.isProcessing = true
        self:Debug("Showing loot window (" .. lockedCount .. " locked items) - processing " .. #self.LootQueue.items .. " unlocked in background")
    elseif #self.LootQueue.items > 0 then
        self:ShowLootFrame(false)
        self.LootQueue.isProcessing = true
        self:Debug("Auto-looting " .. #self.LootQueue.items .. " items (window hidden)")
    else
        if self.State.isItemLocked then
            self:ShowLootFrame(true)
            self:Debug("All available items locked - showing loot window")
        else
            CloseLoot()
            self:Debug("All items filtered - closing loot window quietly")
        end
        self.LootQueue.isProcessing = false
    end
end

-- ============================================================================
-- EXECUTION
-- ============================================================================
function Qloot:ProcessNextLootItem()
    if #self.LootQueue.items == 0 then return end
    
    local itemData = self.LootQueue.items[1]
    
    if not GetLootSlotInfo(itemData.slotIndex) then
        self:Debug("Slot " .. itemData.slotIndex .. " no longer valid - skipping")
        table.remove(self.LootQueue.items, 1)
        return
    end
    
    local _, _, _, _, locked = GetLootSlotInfo(itemData.slotIndex)
    if locked then
        self:ShowLootFrame(true)
        self:Debug("Slot " .. itemData.slotIndex .. " became LOCKED - showing window")
        table.remove(self.LootQueue.items, 1)
        return
    end
    
    if not self:CanLootItem(itemData.itemLink, itemData.quantity) then
        self:Debug("Inventory FULL - cannot loot " .. (itemData.itemLink or "item"))
        self:OnInventoryFull()
        return
    end
    
    self:Debug("Looting slot " .. itemData.slotIndex .. ": " .. (itemData.itemLink or "currency"))
    LootSlot(itemData.slotIndex)
    
    table.remove(self.LootQueue.items, 1)
end

-- ============================================================================
-- UTILITIES
-- ============================================================================
function Qloot:CanLootItem(itemLink, quantity)
    if not itemLink then return true end -- Currency/Gold doesn't consume bag slots
    
    local itemFamily = GetItemFamily(itemLink)
    local totalFree = 0
    
    -- Check Bags
    for i = 0, NUM_BAG_SLOTS do
        local free, bagFamily = GetContainerNumFreeSlots(i)
        
        -- FIX: If a player doesn't have a bag equipped in this slot, bagFamily returns nil.
        -- We coerce it to 0 to prevent bit.band from throwing a "number expected" error.
        bagFamily = bagFamily or 0 
        
        if bagFamily == 0 or (itemFamily and bit.band(itemFamily, bagFamily) > 0) then
            totalFree = totalFree + free
        end
    end
    
    if totalFree > 0 then 
        self:Debug("Bag space OK (" .. totalFree .. " free slots)")
        return true 
    end
    
    -- Check Stacking (If bags are full, check if we can slip it into an incomplete stack)
    local have = GetItemCount(itemLink) or 0
    if have > 0 then
        local _, _, _, _, _, _, _, stackSize = GetItemInfo(itemLink)
        if stackSize and stackSize > 1 then
            local remainder = have % stackSize
            if remainder > 0 and (stackSize - remainder) >= quantity then
                self:Debug("Can stack into existing items")
                return true
            end
        end
    end
    
    self:Debug("Inventory check FAILED - no space for " .. (itemLink or "item"))
    return false
end


function Qloot:OnInventoryFull()
    self:Debug("OnInventoryFull triggered")
    if QlootDB.playFullSound and not self.State.inventoryFullSoundPlayed then
         local soundFiles = {
            [1] = "Sound\\Interface\\PickupPutDown\\RocksOre01.wav",
            [2] = "sound\\character\\gnome\\gnomemale\\errormessages\\gnomemaleerrinventoryfull01.wav",
            [3] = "sound\\character\\dwarf\\dwarfmale\\errormessages\\dwarfmaleerrorinventoryfull02.wav",
        }
        PlaySoundFile(soundFiles[QlootDB.fullSoundID] or soundFiles[1], "Sound")
        self.State.inventoryFullSoundPlayed = true
    end
    
    self:ShowLootFrame(true)
    wipe(self.LootQueue.items)
    self.LootQueue.isProcessing = false
end

function Qloot:OnLootClosed()
    if QlootDB.warnUnlooted and self.State.isLooting then
        local numItems = GetNumLootItems()
        if numItems > 0 then
            local leftover = {}
            for i = 1, numItems do
                local link = GetLootSlotLink(i)
                if link and not self.SkippedLinks[link] then
                    table.insert(leftover, link)
                end
            end
            
            if #leftover > 0 then
                self:Print("|cffff0000Unlooted items left:|r " .. table.concat(leftover, ", "))
            end
        end
    end

    self:Debug("LOOT_CLOSED event - resetting state")
    self.State.isLooting = false
    self.State.lootWindowHidden = false
    self.State.isItemLocked = false
    wipe(self.LootQueue.items)
    self.LootQueue.isProcessing = false
    
    -- Clear the source name so it's fresh for next interaction
    self.lastLootSource = "Unknown"
end

function Qloot:HookErrorMessages()
end

function Qloot:HandleErrorMessage(msg)
    if not self.State.isLooting then return end
    
    if msg == ERR_INV_FULL or msg == ERR_ITEM_MAX_COUNT then
        self:Debug("UI Error: " .. msg .. " - triggering inventory full handler")
        self:OnInventoryFull()
    elseif msg == ERR_LOOT_ROLL_PENDING then
        self:Debug("UI Error: Roll pending - showing loot window")
        if self.State.lootWindowHidden then
            self:ShowLootFrame(true)
        end
    end
end
