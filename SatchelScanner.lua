-- Original concept by: Exzu / EU-Aszune
-- Adjustments by: Reeknab / Shadow Council
-- Fixed/cleaned by: (you) + ChatGPT
------------------------------------------------------------
-- === CONFIG / STATE ===
------------------------------------------------------------
local REFRESH_INTERVAL = 30
local LAST_SATCHELS = {}
local MainFrame
local refreshTicker
local running = true
local dungeonIDs = {}
SLASH_SATCHELSCANNER1 = "/satchel"
------------------------------------------------------------
-- === HELPER FUNCTIONS ===
------------------------------------------------------------

local function BuildDungeonList()
    wipe(dungeonIDs)
    for i = 1, GetNumRandomDungeons() do
        local id, name = GetLFGRandomDungeonInfo(i)
        if id and name then
            dungeonIDs[id] = name
        end
    end
end

local function toggleScan()
    running = not running
end

local function hideMainFrame()
    if MainFrame then
        MainFrame:Hide()
    end
end

------------------------------------------------------------
-- === UI CONSTRUCTION ===
------------------------------------------------------------

local function drawWindow()
    if MainFrame then
        MainFrame:Show()
        return
    end

    --------------------------------------------------------
    -- Main Window
    --------------------------------------------------------
    MainFrame = CreateFrame("Frame", "SatchelScannerFrame", UIParent, "BasicFrameTemplateWithInset")
    MainFrame:SetSize(360, 200) -- Half the previous height
    MainFrame:SetPoint("CENTER")
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)

    -- === Title Text ===
    MainFrame.title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    MainFrame.title:SetPoint("CENTER", MainFrame.TitleBg, "CENTER", 0, 0)
    MainFrame.title:SetText("Satchel Scanner")

    -- === Refresh Button ===
    local refresh = CreateFrame("Button", nil, MainFrame, "UIPanelButtonTemplate")
    refresh:SetSize(60, 20) -- smaller button, fits title bar
    refresh:SetPoint("RIGHT", MainFrame.TitleBg, "RIGHT", -6, 0)
    refresh:SetText("Refresh")

    -- We'll define RefreshDungeonList below and attach it at the end
    refresh:SetScript("OnClick", function()
        if RefreshDungeonList then
            RefreshDungeonList()
        end
    end)

    --------------------------------------------------------
    -- Scroll Frame
    --------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", nil, MainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(1, 1)
    MainFrame.scrollChild = scrollChild

    --------------------------------------------------------
    -- Role Icon Coordinates
    --------------------------------------------------------
    local function GetRoleTexCoords(role)
        if role == "TANK" then return 0, 19 / 64, 22 / 64, 41 / 64 end
        if role == "HEALER" then return 20 / 64, 39 / 64, 1 / 64, 20 / 64 end
        if role == "DAMAGER" then return 20 / 64, 39 / 64, 22 / 64, 41 / 64 end
    end

    --------------------------------------------------------
    -- Dungeon Row Factory
    --------------------------------------------------------
    local function CreateDungeonRow(parent, yOffset, name, id, roleStatus)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(300, 24)
        row:SetPoint("TOPLEFT", 0, -yOffset)

        -- === Dungeon Name Text with truncation ===
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 5, 0)
        text:SetWidth(180) -- Max width before truncating
        text:SetJustifyH("LEFT")
        text:SetNonSpaceWrap(false)
        text:SetText(name)

        -- === Role Icons ===
        local roles = {"TANK", "HEALER", "DAMAGER"}
        local x = 200

        for _, role in ipairs(roles) do
            local icon = CreateFrame("Button", nil, row)
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", x, 0)
            x = x + 26

            local tex = icon:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
            tex:SetTexCoord(GetRoleTexCoords(role))
            icon.texture = tex

            local hasSatchel = roleStatus[role]
            if hasSatchel then
                tex:SetVertexColor(0, 1, 0)

                icon:SetScript("OnClick", function()
                    -- Open the Group Finder if not visible
                    if not PVEFrame or not PVEFrame:IsShown() then
                        ToggleLFDParentFrame()
                    end

                    -- Select Random Dungeon category
                    LFDParentFrame:SetAttribute("selectedTab", 1)
                    LFDQueueFrame_SetType(id)
                    LFDQueueFrame.type = id

                    -- Delay role assignment to ensure Blizzard buttons exist
                    C_Timer.After(0.1, function()
                        -- Assign roles
                        SetLFGRoles(role == "TANK", role == "HEALER", role == "DAMAGER")

                        -- Safe updates
                        if LFG_UpdateAvailableRoles then pcall(LFG_UpdateAvailableRoles) end
                        if LFDQueueFrame_UpdateRoleButtons then pcall(LFDQueueFrame_UpdateRoleButtons) end
                        if LFDQueueFrameSpecificList_Update then pcall(LFDQueueFrameSpecificList_Update) end

                        -- Focus LFD tab visually
                        if PVEFrameTab1 then PVEFrameTab1:Click() end
                    end)
                end)

                icon:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(string.format("%s: Click to prepare queue as %s", name, role))
                    GameTooltip:Show()
                end)
                icon:SetScript("OnLeave", GameTooltip_Hide)
            else
                tex:SetVertexColor(0.3, 0.3, 0.3)
                icon:Disable()
            end
        end

        return row
    end

    --------------------------------------------------------
    -- Dungeon List Refresh Function
    --------------------------------------------------------
    function RefreshDungeonList()
        for _, child in ipairs({scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local yOffset = 0
        local numDungeons = GetNumRandomDungeons()
        for i = 1, numDungeons do
            local id, name = GetLFGRandomDungeonInfo(i)
            if id and name then
                local eligible, forTank, forHealer, forDamage = GetLFGRoleShortageRewards(id, 1)
                if eligible and (forTank or forHealer or forDamage) then
                    local roleStatus = {TANK = forTank, HEALER = forHealer, DAMAGER = forDamage}
                    CreateDungeonRow(scrollChild, yOffset, name, id, roleStatus)
                    yOffset = yOffset + 26
                end
            end
        end
        scrollChild:SetHeight(yOffset)
    end

    --------------------------------------------------------
    -- Auto-refresh timer
    --------------------------------------------------------
    if not refreshTicker then
        refreshTicker = C_Timer.NewTicker(REFRESH_INTERVAL, RefreshDungeonList)
    end

    -- Initial population
    RefreshDungeonList()
end


------------------------------------------------------------
-- === EVENT HANDLER ===
------------------------------------------------------------

local SatchelScannerFrame = CreateFrame("Frame")
SatchelScannerFrame:RegisterEvent("ADDON_LOADED")
SatchelScannerFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "SatchelScanner" then
        BuildDungeonList()
        drawWindow()
        MainFrame:Show()
    end
end)

SlashCmdList["SATCHELSCANNER"] = function()
    if MainFrame and MainFrame:IsShown() then
        MainFrame:Hide()
    else
        if not MainFrame then
            drawWindow()
        end
        MainFrame:Show()
    end
end
