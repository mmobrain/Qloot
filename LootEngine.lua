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

-- Max attempts to wait for vendor price cache before giving up and looting anyway.
-- At default 110ms delay: 5 tries ≈ 440ms. Sufficient for a local private server.
-- If vendorPrice is unavailable after this, the item is looted as a safe fallback.
local PENDING_VALUE_MAX_TRIES = 4

-- ============================================================================
-- FILTER COMPILER & MATCHER
-- ============================================================================

function Qloot:ParseValueToken(token)
    if not token then return nil end

    token = token:match("^%s*(.-)%s*$")
    if token == "" then return nil end

    -- Allow optional spaces: v<50s, v< 50s, v <50 s (permissive)
    local op, amount, suffix = token:match("^[vV]%s*([<>])%s*(%d+)%s*([gGsScC]?)%s*$")
    if not op then return nil end

    local copper = tonumber(amount)
    if not copper then return nil end

    suffix = (suffix or ""):lower()
    if suffix == "g" then
        copper = copper * 10000
    elseif suffix == "s" then
        copper = copper * 100
    else
        -- 'c' or empty suffix means copper
    end

    return op, copper
end

function Qloot:PrimeItemInfo(itemLink)
    if not itemLink then return end

    if not self.ScanTip then
        local tip = CreateFrame("GameTooltip", "QlootScanTip", UIParent, "GameTooltipTemplate")
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:Hide()
        self.ScanTip = tip
    end

    self.ScanTip:ClearLines()
    self.ScanTip:SetHyperlink(itemLink)
end

function Qloot:GetVendorPrice(itemLink)
    if not itemLink then return nil end

    local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemLink)
    if vendorPrice ~= nil then
        return vendorPrice
    end

    -- Try by itemID as well (sometimes helps depending on cache state)
    local itemID = tonumber(itemLink:match("item:(%d+):"))
    if itemID then
        _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemID)
        if vendorPrice ~= nil then
            return vendorPrice
        end
    end

    -- Prime cache for a later retry
    self:PrimeItemInfo(itemLink)
    return nil
end


function Qloot:CompileFilters()
    self.Filters = {
        qualities = {},
        exactNames = {},
        patterns = {},
        valueRules = {},
        compoundRules = {},
    }

    -- Tracks invalid rules already reported this session to avoid chat spam
    self.ReportedInvalidRules = self.ReportedInvalidRules or {}

    if not QlootDB or not QlootDB.filterList then return end

    for line in string.gmatch(QlootDB.filterList, "[^\r\n]+") do
        local raw = line:match("^%s*(.-)%s*$")
        if raw and raw ~= "" then

            -- Compound rule: q0&v<50s (AND logic on one line)
            if raw:find("&", 1, true) then
                local rule = { raw = raw, conditions = {} }
                local invalid = false

                for part in string.gmatch(raw, "[^&]+") do
                    part = part:match("^%s*(.-)%s*$")
                    if part ~= "" then
                        local q = part:match("^[qQ](%d)$")
                        if q then
                            table.insert(rule.conditions, { type = "quality", value = tonumber(q) })
                        else
                            local op, copper = self:ParseValueToken(part)
                            if op then
                                table.insert(rule.conditions, { type = "value", op = op, threshold = copper })
                            else
                                invalid = true
                                break
                            end
                        end
                    end
                end

                if not invalid and #rule.conditions >= 2 then
                    table.insert(self.Filters.compoundRules, rule)
                    self:Debug("Compiled compound rule: " .. raw)
                else
                    self:Debug("Ignored invalid compound rule: " .. raw)

                    -- Report to player once per session per rule
                    if not self.ReportedInvalidRules[raw] then
                        self.ReportedInvalidRules[raw] = true
                        self:Print("|cffff4444Invalid filter rule ignored:|r |cffffd100\"" .. raw .. "\"|r  (check filters (/qloot))")
                    end
                end

            else
                -- Simple rules (legacy behavior + value rule)
                local q = raw:match("^[qQ](%d)$")
                if q then
                    self.Filters.qualities[tonumber(q)] = raw
                else
                    local op, copper = self:ParseValueToken(raw)
                    if op then
                        table.insert(self.Filters.valueRules, { op = op, copper = copper, raw = raw })
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
    end
end



function Qloot:GetFilterMatch(link, quality)
    -- Money/currency has no item link: never let quality/value rules consume it.
    if not link then
        return nil, false
    end

    local itemName = GetItemInfo(link) or link:match("%[(.-)%]")
    if not itemName then
        -- If even the name isn't available, we're effectively pending item cache.
        self:PrimeItemInfo(link)
        return nil, true
    end

    local lowerName = itemName:lower()

    -- Exact name rules
    if self.Filters.exactNames[lowerName] then
        return self.Filters.exactNames[lowerName], false
    end

    -- Compound rules (AND)
    if self.Filters.compoundRules and #self.Filters.compoundRules > 0 then
        for _, rule in ipairs(self.Filters.compoundRules) do
            local match = true
            local vendorPrice = nil
            local needsValue = false

            for _, cond in ipairs(rule.conditions) do
                if cond.type == "quality" then
                    if quality ~= cond.value then
                        match = false
                        break
                    end
                elseif cond.type == "value" then
                    needsValue = true
                end
            end

            if match and needsValue then
                vendorPrice = self:GetVendorPrice(link)
                if vendorPrice == nil then
                    return nil, true -- pending vendor value
                end

                for _, cond in ipairs(rule.conditions) do
                    if cond.type == "value" then
                        if cond.op == "<" then
                            if not (vendorPrice < cond.threshold) then match = false break end
                        else -- ">"
                            if not (vendorPrice > cond.threshold) then match = false break end
                        end
                    end
                end
            end

            if match then
                return rule.raw, false
            end
        end
    end

    -- Simple quality rules (qN) - guarded by link to avoid money/q0 bug
    if link and quality and self.Filters.qualities[quality] then
        return self.Filters.qualities[quality], false
    end

    -- Simple value rules
    if self.Filters.valueRules and #self.Filters.valueRules > 0 then
        local vendorPrice = self:GetVendorPrice(link)
        if vendorPrice == nil then
            return nil, true
        end

        for _, rule in ipairs(self.Filters.valueRules) do
            if rule.op == "<" and vendorPrice < rule.copper then
                return rule.raw, false
            elseif rule.op == ">" and vendorPrice > rule.copper then
                return rule.raw, false
            end
        end
    end

    -- Wildcards/patterns
    for _, p in ipairs(self.Filters.patterns) do
        if lowerName:find(p.pattern) then
            return p.raw, false
        end
    end

    return nil, false
end



-- ============================================================================
-- LOOT SOURCE CAPTURE & NATIVE AUTO-LOOT BYPASS
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

    -- Ultimate fallback if player used an "Interact with Target" keybind instead of clicking    
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
        local filterRule, pendingValue = self:GetFilterMatch(link, quality)
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
                if pendingValue and link then
                    -- Prime cache early to improve chance vendor price is available before we loot
                    self:PrimeItemInfo(link)
                end

                table.insert(self.LootQueue.items, {
                    slotIndex = i,
                    itemLink  = link,
                    quantity  = quantity,
                    rarity    = quality,
                    pendingValue = (pendingValue and true) or false,
                    pendingSince = pendingValue and GetTime() or nil,
                    pendingTries = 0,
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

    local link = GetLootSlotLink(itemData.slotIndex)
    local _, _, quantity, quality, locked = GetLootSlotInfo(itemData.slotIndex)

    if locked then
        self:ShowLootFrame(true)
        self:Debug("Slot " .. itemData.slotIndex .. " became LOCKED - showing window")
        table.remove(self.LootQueue.items, 1)
        return
    end

    -- Re-check filter right before looting (lets vendor price cache arrive between passes)
    local filterRule, pendingValue = self:GetFilterMatch(link, quality)
    if filterRule then
        self:Debug("Slot " .. itemData.slotIndex .. " filtered at execution by rule: " .. filterRule)

        if link then self.SkippedLinks[link] = true end
        table.insert(self.SessionLog, {
            time   = date("%H:%M:%S"),
            link   = link or "currency",
            rule   = filterRule,
            source = self.lastLootSource or "Unknown"
        })
        if #self.SessionLog > Qloot.MAX_LOG_LINES then table.remove(self.SessionLog, 1) end

        table.remove(self.LootQueue.items, 1)
        return
    end

    -- Vendor price still unknown: defer this slot to the end of the queue.
    -- Only defer if there are other NON-pending items ahead; otherwise the item
    -- is either alone or surrounded by other pending items - no benefit in waiting.
    if pendingValue and link then
        local hasOtherReadyItems = false
        for i = 2, #self.LootQueue.items do
            if not self.LootQueue.items[i].pendingValue then
                hasOtherReadyItems = true
                break
            end
        end

        itemData.pendingTries = (itemData.pendingTries or 0) + 1

        if hasOtherReadyItems and itemData.pendingTries <= PENDING_VALUE_MAX_TRIES then
            self:PrimeItemInfo(link)

            -- Move to back so other ready slots are processed first.
            -- pendingTries only counts full passes (each time item returns to front
            -- after at least one non-pending item was processed ahead of it).
            table.remove(self.LootQueue.items, 1)
            table.insert(self.LootQueue.items, itemData)

            self:Debug("Deferring slot " .. itemData.slotIndex .. " (vendor value pending, pass " .. itemData.pendingTries .. "/" .. PENDING_VALUE_MAX_TRIES .. ")")
            return
        else
            -- Either alone in queue, all others also pending, or max passes reached.
            -- Loot as safe fallback rather than silently skipping.
            self:Debug("Slot " .. itemData.slotIndex .. " vendor price never cached (pass " .. (itemData.pendingTries or 0) .. ") - looting as fallback")
        end
    end

    if not self:CanLootItem(link, quantity) then
        self:Debug("Inventory FULL - cannot loot " .. (link or "item"))
        self:OnInventoryFull()
        return
    end

    self:Debug("Looting slot " .. itemData.slotIndex .. ": " .. (link or "currency"))
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
