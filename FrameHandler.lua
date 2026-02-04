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
        -- It's already unregistered from LOOT_OPENED in Core.lua
        -- Just ensure it's hidden
        LootFrame:Hide()
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
        
        -- Force update (ElvUI specific method trigger)
        local E = unpack(ElvUI)
        local L = E:GetModule('Loot')
        if L then L:LOOT_OPENED() end
        
        self.State.lootWindowHidden = false
    else
        -- Hide by reparenting to our hidden frame
        elvLoot:SetParent(Qloot.HiddenFrame)
        self.State.lootWindowHidden = true
    end
end
