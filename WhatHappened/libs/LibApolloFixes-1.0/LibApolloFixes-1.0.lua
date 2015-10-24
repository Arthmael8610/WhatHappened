local MAJOR, MINOR = "Lib:ApolloFixes-1.0", 7
-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
    return -- no upgrade needed
end
-- Set a reference to the actual package or create an empty table
local Lib = APkg and APkg.tPackage or {}

-------------------------------------------------------------------------------
--- Upvalues
-------------------------------------------------------------------------------
local tinsert, pairs, ipairs = table.insert, pairs, ipairs
local next, select, strmatch, dlocal = next, select, string.match, debug.getlocal

-- Wildstar APIs
local Apollo, XmlDoc = Apollo, XmlDoc
local Event_FireGenericEvent = Event_FireGenericEvent

-------------------------------------------------------------------------------
--- Local Variables
-------------------------------------------------------------------------------
-- Will contain an array of strings, the names of all Addons available loaded or not.
local tAddonList = {}

-- Use already stored original LoadForm in case of upgrade or get reference to the original LoadForm
Lib.fnOldLoadForm = Lib.fnOldLoadForm or Apollo.LoadForm
-- This will be the number of obscured addons, used to determine if XML has been read in GetAddons()
local nNumObscured = 0
-- This list should be comprehensive as of 1.0.8.6745
-- Format is: ["FormName"] = "AddonName"
Lib.tObscuredAddons = Lib.tObscuredAddons or {
    ["ImprovedSalvageForm"]              = "ImprovedSalvage",
    ["ItemPreviewForm"]                  = "ItemPreview",
    ["TradeskillContainerForm"]          = "TradeskillContainer",
    ["TradeskillSchematicsForm"]         = "TradeskillSchematics",
    ["TradeskillTalentsForm"]            = "TradeskillTalents",
    ["WarpartyRegistrationForm"]         = "WarpartyRegister",
    ["WarpartyBattleForm"]               = "WarpartyBattle",
    ["TutorialTesterForm"]               = "TutorialPrompts",
    ["PathSoldierMissionMain"]           = "PathSoldierMissions",
    ["PathSettlerrMissionMain"]          = "PathSettlerMissions",
    ["PathScientistExperimentationForm"] = "PathScientistExperimentation",
    ["PathScientistCustomizeForm"]       = "PathScientistCustomize",
    ["PowerMapRangeFinder"]              = "PathExplorerMissions",
    ["InteractionOnUnit"]                = "HUDInteract",
    ["HousingRemodelWindow"]             = "HousingRemodel",
    ["HousingLandscapeWindow"]           = "HousingLandscape",
    ["HousingListWindow"]                = "HousingList",
    ["DecorPreviewWindow"]               = "DecorPreview",
    ["PlugPreviewWindow"]                = "PlugPreview",
    ["MannequinWindow"]                  = "Mannequin",
    ["HousingDatachronWindow"]           = "HousingDatachron",
    ["CircleRegistrationForm"]           = "CircleRegistration",
    ["GroupLeaderOptions"]               = "GroupDisplayOptions",
    ["FloaterPanel"]                     = "FloatTextPanel",
    ["ChallengeLogForm"]                 = "ChallengeLog",
    ["ChallengeRewardPanelForm"]         = "ChallengeRewardPanel",
    ["ArenaTeamRegistrationForm"]        = "ArenaTeamRegister",
}
-- Determine number of obscured addons
for k,v in pairs(Lib.tObscuredAddons) do
    nNumObscured = nNumObscured + 1
end

-- Use already stored original GetAddon in case of upgrade or get reference to the original GetAddon
Lib.fnOldGetAddon = Lib.fnOldGetAddon or Apollo.GetAddon
-- Populated once Addons are located within LoadForm
Lib.tFoundAddons = Lib.tFoundAddons or {}
-------------------------------------------------------------------------------
--- Local Functions
-------------------------------------------------------------------------------

local function GetAddons()
    -- Table of addons, returning a copy so original one cannot be edited
    local tReturnedList = {}
    -- Only parse XML once, if we don't have more than the number of obscured we can't have done this
    if #tAddonList <= nNumObscured then
        -- Addon Asset folders contain the full path, we parse off everything before the 1st occurance of Addons (regardless of capitalization)
        local strWildstarDir = strmatch(Apollo.GetAssetFolder(), "(.-)[\\/][Aa][Dd][Dd][Oo][Nn][Ss]")
        -- Read in the Addons.xml file which is generated by Carbine and stores load states among other things
        local tAddonXML = XmlDoc.CreateFromFile(strWildstarDir.."\\Addons.xml"):ToTable()
        for k,v in pairs(tAddonXML) do
            -- We only care about the <Addon> tags
            if v.__XmlNode == "Addon" then
                if v.Carbine == "1" then -- Carbine Addons are the same name as thier folder (Apparently its a string 1 not a number 1)
                    tinsert(tAddonList, v.Folder)
                else  -- User addons can have different folder/addon names so we have to parse their toc
                    local xmlTOC = XmlDoc.CreateFromFile(strWildstarDir.."\\Addons\\"..v.Folder.."\\toc.xml")
                    if xmlTOC then
                        local tTocTable = xmlTOC:ToTable()
                        tinsert(tAddonList, tTocTable.Name)
                    end
                end
            end
        end
  end
    -- Iterate through the list of addons and add them to our returned table
    for _,strAddon in ipairs(tAddonList) do
        tinsert(tReturnedList, strAddon)
    end
    -- Return a copy of our addon list
    return tReturnedList
end

local function GetReplacement(strAddonName)
    -- Table of addons that replaced strAddonName
    local tReplacements = {}
    local tAddons

    -- If GetAddons is our internal function we can use the internal list
    if Apollo.GetAddons == GetAddons then
        if #tAddonList <= nNumObscured then
            GetAddons()
        end
        tAddons = tAddonList
    else
        -- Assumption: If Carbine provides a GetAddons it returns strings
        tAddons = Apollo.GetAddons()
    end

    for _, strAddon in ipairs(tAddons) do
        local tAddonInfo = Apollo.GetAddonInfo(strAddon)
        if tAddonInfo and tAddonInfo.bRunning and (#tAddonInfo.arReplacedAddons > 0) then
            for _, strReplace in ipairs(tAddonInfo.arReplacedAddons) do
                if strReplace == strAddonName then
                    tinsert(tReplacements, strAddon)
                    break
                end
            end
        end
    end
    return tReplacements
end

local function GetAddon(strAddonName)
    -- If this is one we found, return that
    if Lib.tFoundAddons[strAddonName] then
        return Lib.tFoundAddons[strAddonName]
    else
        -- Otherwise return the normal result
        return Lib.fnOldGetAddon(strAddonName)
    end
end

-- Gets all locals at a specified number of calls previous
local function DebugLocals(nLevel)
    local tVars, nIdx = {}, 1
    while true do
        local ln, lv = dlocal(nLevel, nIdx)
        if ln ~= nil then
            tVars[ln] = lv
        else
            break
        end
        nIdx = nIdx + 1
    end
    return tVars
end

local function HookedLoadForm(...)
    -- Arg 2 is the Form Name
    local strForm = select(2, ...)
    if Lib.tObscuredAddons[strForm] then
        -- Pull local variables from 3 levels up (DebugLocals, HookedLoadForm, <What We Want>)
        local tDebugLocals = DebugLocals(3)
        local strAddonName = Lib.tObscuredAddons[strForm]
        -- Self at this point is the addon we are looking for so save that!
        Lib.tFoundAddons[strAddonName] = tDebugLocals.self
        -- Since we can now lookup this addon, lets add it to GetAddons()
        tinsert(tAddonList, Lib.tObscuredAddons[strForm])
        -- Found it so stop looking for this addon
        Lib.tObscuredAddons[strForm] = nil

        -- Send Notification
        Event_FireGenericEvent("ObscuredAddonVisible", strAddonName)

        -- If this was the last thing we're looking for remove the hook
        if not next(Lib.tObscuredAddons) then
            Apollo.LoadForm = Lib.fnOldLoadForm
        end
    end
    -- Return the saved functions result
    return Lib.fnOldLoadForm(...)
end

-- Setup Hooks
Apollo.LoadForm       = HookedLoadForm
Apollo.GetAddons      = GetAddons
Apollo.GetReplacement = GetReplacement
Apollo.GetAddon       = GetAddon

Apollo.RegisterPackage(Lib, MAJOR, MINOR, {})
