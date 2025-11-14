-- Revised Satchel Scanner (LFG/LFR passive icons + Open Finder button)
-- Original concept by: Exzu / EU-Aszune
-- Adjustments by: Reeknab / Shadow Council
-- Fixed/cleaned by: (you) + ChatGPT
------------------------------------------------------------
-- === CONFIG / STATE ===
------------------------------------------------------------
local REFRESH_INTERVAL = 15
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
    MainFrame:SetSize(360, 200)
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

    --------------------------------------------------------
    -- Refresh Button
    --------------------------------------------------------
    local refresh = CreateFrame("Button", nil, MainFrame, "UIPanelButtonTemplate")
    refresh:SetSize(60, 20)
    refresh:SetPoint("RIGHT", MainFrame.TitleBg, "RIGHT", 0, 0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function()
        if RefreshDungeonList then
            RefreshDungeonList()
        end
    end)

    --------------------------------------------------------
    -- NEW: Open Group Finder Button
    --------------------------------------------------------
    local openGF = CreateFrame("Button", nil, MainFrame, "UIPanelButtonTemplate")
    openGF:SetSize(80, 20)
    openGF:SetPoint("RIGHT", refresh, "LEFT", -195, 0)
    openGF:SetText("Finder")
    openGF:SetScript("OnClick", function()
        PVEFrame_ToggleFrame("GroupFinderFrame")
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
    -- Dungeon / Raid Row Factory
    --------------------------------------------------------
    function CreateDungeonRow(parent, yOffset, name, id, roleStatus, isLFR)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(330, 24)
        row:SetPoint("TOPLEFT", 0, -yOffset)

        -- === Name ===
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 5, 0)
        text:SetWidth(180)
        text:SetJustifyH("LEFT")
        text:SetNonSpaceWrap(false)
        text:SetText(name)

        -- === Passive Role Icons ===
        local roles = {"TANK", "HEALER", "DAMAGER"}
        local x = 200

        for _, role in ipairs(roles) do
            local icon = CreateFrame("Frame", nil, row)
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", x, 0)
            x = x + 26

            local tex = icon:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
            tex:SetTexCoord(GetRoleTexCoords(role))
            icon.texture = tex

            if not roleStatus[role] then
                tex:SetVertexColor(0.3, 0.3, 0.3)
            end
        end

        --------------------------------------------------------------------
        -- === NEW: Lockout Icon (LFR only) ===
        --------------------------------------------------------------------
        if isLFR then
            local encounters = GetLFGDungeonNumEncounters(id)
            local killed = 0

            if encounters and encounters > 0 then
                for i = 1, encounters do
                    local bossName, _, isKilled = GetLFGDungeonEncounterInfo(id, i)
                    if isKilled then
                        killed = killed + 1
                    end
                end
            end

            local iconPath
            if killed == encounters then
                iconPath = "Interface\\RaidFrame\\ReadyCheck-Ready"      -- green check
            elseif killed > 0 then
                iconPath = "Interface\\RaidFrame\\ReadyCheck-Waiting"    -- yellow ?
            else
                iconPath = "Interface\\RaidFrame\\ReadyCheck-NotReady"   -- red X
            end

            local lockIcon = CreateFrame("Frame", nil, row)
            lockIcon:SetSize(20, 20)
            lockIcon:SetPoint("LEFT", x + 4, 0)

            local tex = lockIcon:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture(iconPath)
        end

        return row
    end

    --------------------------------------------------------
    -- Refresh Function
    --------------------------------------------------------
    function RefreshDungeonList()
        for _, child in ipairs({scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local yOffset = 0

        -- Random Dungeons
        for i = 1, GetNumRandomDungeons() do
            local id, name = GetLFGRandomDungeonInfo(i)
            if id and name then
                local eligible, forTank, forHealer, forDamage = GetLFGRoleShortageRewards(id, 1)
                if eligible and (forTank or forHealer or forDamage) then
                    local roleStatus = {TANK = forTank, HEALER = forHealer, DAMAGER = forDamage}
                    CreateDungeonRow(scrollChild, yOffset, name, id, roleStatus, false)
                    yOffset = yOffset + 26
                end
            end
        end

        -- LFR
        local numRF = GetNumRFDungeons and GetNumRFDungeons() or 0
        for i = 1, numRF do
            local dungeonID, name = GetRFDungeonInfo(i)
            if dungeonID and name then
                local eligible, forTank, forHealer, forDamage = GetLFGRoleShortageRewards(dungeonID, 1)
                if eligible and (forTank or forHealer or forDamage) then
                    local roleStatus = {TANK = forTank, HEALER = forHealer, DAMAGER = forDamage}
                    CreateDungeonRow(scrollChild, yOffset, name, dungeonID, roleStatus, true)
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

------------------------------------------------------------
-- === SLASH COMMAND ===
------------------------------------------------------------
SlashCmdList["SATCHELSCANNER"] = function()
    if MainFrame and MainFrame:IsShown() then
        MainFrame:Hide()
    else
        if not MainFrame then drawWindow() end
        MainFrame:Show()
    end
end
