local addonName, ns = ...

-- Queue Structure
Qloot.LootQueue = {
    items = {}, -- { {slotIndex=1, itemLink="...", quantity=1}, ... }
    isProcessing = false,
    lastLootTime = 0,
    DELAY = 0.1 -- Runtime default, updated from DB
}

-- ============================================================================
-- THROTTLE ENGINE
-- ============================================================================
local QlootThrottle = CreateFrame("Frame")
QlootThrottle:SetScript("OnUpdate", function(self, elapsed)
    -- ANTI-FREEZE CAP: Prevent Alt-Tab catch-up bursts
    elapsed = math.min(elapsed, 0.1)
    
    -- Safety check
    if not Qloot.State.isLooting then return end
    
    -- Sync delay with DB
    Qloot.LootQueue.DELAY = (QlootDB.lootDelay or 150) / 1000

    -- Only process if queue has items
    if #Qloot.LootQueue.items == 0 then
        Qloot.LootQueue.isProcessing = false
        -- If player finished looting, verify if addon shouldn't be showing the window
        -- If the window was hidden, addon should likely close the loot interaction now
        if Qloot.State.lootWindowHidden and not Qloot.State.isItemLocked then
             CloseLoot()
             Qloot:Debug("Loot window closed - queue empty")
        end
        return
    end
    
    -- Check time
    local currentTime = GetTime()
    local timeSince = currentTime - Qloot.LootQueue.lastLootTime
    
    if timeSince >= Qloot.LootQueue.DELAY then
        Qloot:ProcessNextLootItem()
        Qloot.LootQueue.lastLootTime = currentTime
    end
end)

-- ============================================================================
-- LOOT POPULATION
-- ============================================================================
function Qloot:OnLootReady()
    if not QlootDB.enabled then 
        self:Debug("Addon disabled - skipping loot")
        return 
    end
    
    if IsShiftKeyDown() then 
        self:Debug("Shift held - manual loot mode")
        return 
    end

    local numItems = GetNumLootItems()
    self:Debug("LOOT_READY fired - " .. numItems .. " items detected")
    
    if numItems == 0 then 
        CloseLoot()
        self:Debug("No items to loot - closing")
        return 
    end
    
    self.State.isLooting = true
    self.State.lootWindowHidden = true
    self.State.isItemLocked = false
    self.State.inventoryFullSoundPlayed = false
    
    -- Clear previous queue
    wipe(self.LootQueue.items)
    
    -- Populate Queue
    -- 1..numItems order. 
    local lockedCount = 0
    for i = 1, numItems do
        local link = GetLootSlotLink(i)
        local _, _, quantity, quality, locked = GetLootSlotInfo(i)
        
        -- Logic: If it's locked (Master Loot/Roll), we must show window later
        if not locked then
             table.insert(self.LootQueue.items, {
                slotIndex = i,
                itemLink = link,
                quantity = quantity,
                rarity = quality
            })
            self:Debug("Queued slot " .. i .. ": " .. (link or "currency") .. " x" .. (quantity or 1))
        else
            self.State.isItemLocked = true
            lockedCount = lockedCount + 1
            self:Debug("Slot " .. i .. " is LOCKED (BoP/Roll): " .. (link or "unknown"))
        end
    end
    
    -- Reset timer so first item loots immediately (or after 1 frame)
    self.LootQueue.lastLootTime = 0
    
    -- Decision: Show Window vs Auto Loot
    if self.State.isItemLocked and QlootDB.showOnLocked then
        self:ShowLootFrame(true)
        -- We still process the unlocked items in the background!
        self.LootQueue.isProcessing = true
        self:Debug("Showing loot window (" .. lockedCount .. " locked items) - processing " .. #self.LootQueue.items .. " unlocked in background")
    elseif #self.LootQueue.items > 0 then
        self:ShowLootFrame(false)
        self.LootQueue.isProcessing = true
        self:Debug("Auto-looting " .. #self.LootQueue.items .. " items (window hidden)")
    else
        -- Nothing to auto-loot, just show frame
        self:ShowLootFrame(true)
        self.LootQueue.isProcessing = false
        self:Debug("All items locked - showing loot window")
    end
end

-- ============================================================================
-- EXECUTION
-- ============================================================================
function Qloot:ProcessNextLootItem()
    if #self.LootQueue.items == 0 then return end
    
    -- Peek at next item
    local itemData = self.LootQueue.items[1]
    
    -- RE-VALIDATION: Check if slot is still valid
    if not GetLootSlotInfo(itemData.slotIndex) then
        self:Debug("Slot " .. itemData.slotIndex .. " no longer valid - skipping")
        table.remove(self.LootQueue.items, 1)
        return
    end
    
    -- RE-VALIDATION: Check if it became locked
    local _, _, _, _, locked = GetLootSlotInfo(itemData.slotIndex)
    if locked then
        self:ShowLootFrame(true)
        self:Debug("Slot " .. itemData.slotIndex .. " became LOCKED - showing window")
        -- Remove from queue to prevent infinite loop on locked item
        table.remove(self.LootQueue.items, 1)
        return
    end
    
    -- INVENTORY CHECK
    if not self:CanLootItem(itemData.itemLink, itemData.quantity) then
        self:Debug("Inventory FULL - cannot loot " .. (itemData.itemLink or "item"))
        self:OnInventoryFull()
        return
    end
    
    -- LOOT IT
    self:Debug("Looting slot " .. itemData.slotIndex .. ": " .. (itemData.itemLink or "currency"))
    LootSlot(itemData.slotIndex)
    
    -- Remove from queue
    table.remove(self.LootQueue.items, 1)
end

-- ============================================================================
-- UTILITIES
-- ============================================================================
function Qloot:CanLootItem(itemLink, quantity)
    if not itemLink then return true end -- Currency?
    
    local itemFamily = GetItemFamily(itemLink)
    local totalFree = 0
    
    -- Check Bags
    for i = 0, NUM_BAG_SLOTS do
        local free, bagFamily = GetContainerNumFreeSlots(i)
        if bagFamily == 0 or (itemFamily and bit.band(itemFamily, bagFamily) > 0) then
            totalFree = totalFree + free
        end
    end
    
    if totalFree > 0 then 
        self:Debug("Bag space OK (" .. totalFree .. " free slots)")
        return true 
    end
    
    -- Check Stacking
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
    wipe(self.LootQueue.items) -- Abort queue
    self.LootQueue.isProcessing = false
end

function Qloot:OnLootClosed()
    -- Check for unlooted items
    if QlootDB.warnUnlooted and self.State.isLooting then
        local numItems = GetNumLootItems()
        if numItems > 0 then
            local leftover = {}
            for i = 1, numItems do
                local link = GetLootSlotLink(i)
                if link then
                    table.insert(leftover, link)
                end
            end
            
            if #leftover > 0 then
                -- Join item links with commas
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
end

function Qloot:HookErrorMessages()
    -- Hooked in Core.lua OnEvent
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
