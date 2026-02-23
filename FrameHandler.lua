local addonName, ns = ...
local isWOTLK = (select(4, GetBuildInfo()) == 30300)
local isTBC = (select(4, GetBuildInfo()) == 20400)

-- Hidden frame for reparenting ElvUI loot frame to hide it
Qloot.HiddenFrame = CreateFrame("Frame")
Qloot.HiddenFrame:Hide()

function Qloot:ShowLootFrame(show)
    if IsAddOnLoaded("ElvUI") then
        self:ShowElvUILootFrame(show)
    else
        self:ShowDefaultLootFrame(show)
    end
end

function Qloot:ShowDefaultLootFrame(show)
    if not LootFrame:IsEventRegistered("LOOT_SLOT_CLEARED") then
        return -- Someone else hooked it?
    end
    
    LootFrame.page = 1
    
    if show then
        if isWOTLK then
            -- Standard 3.3.5 display
            LootFrame_OnEvent(LootFrame, "LOOT_OPENED") 
        elseif isTBC then
            ShowUIPanel(LootFrame)
        end
        self.State.lootWindowHidden = false
    else
        -- Safely hide without triggering native CloseLoot()
        local onHide = LootFrame:GetScript("OnHide")
        LootFrame:SetScript("OnHide", nil)
        
        LootFrame:Hide()
        
        -- Restore the script for normal operation later
        LootFrame:SetScript("OnHide", onHide)
        self.State.lootWindowHidden = true
    end
end

function Qloot:ShowElvUILootFrame(show)
    local elvLoot = ElvLootFrame
    if not elvLoot then return end

    if show then
        -- Restore ElvUI parent
        if ElvLootFrameHolder then
            elvLoot:SetParent(ElvLootFrameHolder)
        else
            elvLoot:SetParent(UIParent)
        end
        elvLoot:SetFrameStrata("HIGH")

        -- Force update via ElvUI Loot module.
        local E = ElvUI and unpack(ElvUI)
        if E and type(E.GetModule) == "function" then
            local L = E:GetModule("Loot", true)
            if L and type(L.LOOT_OPENED) == "function" then
                L:LOOT_OPENED()
            end
        end

        self.State.lootWindowHidden = false
    else
        -- Safely hide by reparenting, ensuring ElvUI's OnHide doesn't close loot
        local onHide = elvLoot:GetScript("OnHide")
        elvLoot:SetScript("OnHide", nil)
        
        elvLoot:SetParent(Qloot.HiddenFrame)
        elvLoot:Hide()
        
        elvLoot:SetScript("OnHide", onHide)
        self.State.lootWindowHidden = true
    end
end
