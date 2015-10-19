-----------------------------------------------------------------------------------------------
-- Client Lua Script for WTF
-----------------------------------------------------------------------------------------------

require "Window"
require "ChatSystemLib"
require "ChatChannelLib"
require "GroupLib"

-----------------------------------------------------------------------------------------------
-- Upvalues
-----------------------------------------------------------------------------------------------
local MAJOR, MINOR = "WhatHappened-2.2", 2

local error, floor, ipairs, pairs, tostring = error, math.floor, ipairs, pairs, tostring
local strformat = string.format

-- Wildstar APIs
local Apollo, ApolloColor, ApolloTimer = Apollo, ApolloColor, ApolloTimer
local GameLib, XmlDoc = GameLib, XmlDoc
local Event_FireGenericEvent, Print = Event_FireGenericEvent, Print

-----------------------------------------------------------------------------------------------
-- WTF Module Definition
-----------------------------------------------------------------------------------------------
local WhatHappened = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("WhatHappened", false, {"ChatLog"})

-----------------------------------------------------------------------------------------------
-- Locals
-----------------------------------------------------------------------------------------------
-- Packages/Addons
local GeminiColor, tChatLog
local strChatAddon = "ChatLog"

-- Array to contain death logs
local tDeathInfos = {}
-- Queue for keeping track of Combat events
local tCombatQueue

-- Array of colors, populated through saved variables
local tColors = {
    crWhite = ApolloColor.new("white")
}

-- ApolloTimer handle
local atChatTimer
-- Local function, declared later
local GenerateLog

-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
local ktDamageTypeToName = {
    [GameLib.CodeEnumDamageType.Fall]      = Apollo.GetString("DamageType_Fall"),
    [GameLib.CodeEnumDamageType.Magic]     = Apollo.GetString("DamageType_Magic"),
    [GameLib.CodeEnumDamageType.Physical]  = Apollo.GetString("DamageType_Physical"),
    [GameLib.CodeEnumDamageType.Suffocate] = Apollo.GetString("DamageType_Suffocate"),
    [GameLib.CodeEnumDamageType.Tech]      = Apollo.GetString("DamageType_Tech"),
}

local arChatColor =
    {
        [ChatSystemLib.ChatChannel_Command]         = ApolloColor.new("ChatCommand"),
        [ChatSystemLib.ChatChannel_System]          = ApolloColor.new("ChatSystem"),
        [ChatSystemLib.ChatChannel_Debug]           = ApolloColor.new("ChatDebug"),
        [ChatSystemLib.ChatChannel_Say]             = ApolloColor.new("ChatSay"),
        [ChatSystemLib.ChatChannel_Yell]            = ApolloColor.new("ChatShout"),
        [ChatSystemLib.ChatChannel_Whisper]         = ApolloColor.new("ChatWhisper"),
        [ChatSystemLib.ChatChannel_Party]           = ApolloColor.new("ChatParty"),
        [ChatSystemLib.ChatChannel_AnimatedEmote]   = ApolloColor.new("ChatEmote"),
        [ChatSystemLib.ChatChannel_Zone]            = ApolloColor.new("ChatZone"),
        [ChatSystemLib.ChatChannel_ZoneGerman]      = ApolloColor.new("ChatZone"),
        [ChatSystemLib.ChatChannel_ZoneFrench]      = ApolloColor.new("ChatZone"),
        [ChatSystemLib.ChatChannel_ZonePvP]         = ApolloColor.new("ChatPvP"),
        [ChatSystemLib.ChatChannel_Trade]           = ApolloColor.new("ChatTrade"),
        [ChatSystemLib.ChatChannel_Guild]           = ApolloColor.new("ChatGuild"),
        [ChatSystemLib.ChatChannel_GuildOfficer]    = ApolloColor.new("ChatGuildOfficer"),
        [ChatSystemLib.ChatChannel_Society]         = ApolloColor.new("ChatCircle2"),
        [ChatSystemLib.ChatChannel_Custom]          = ApolloColor.new("ChatCustom"),
        [ChatSystemLib.ChatChannel_NPCSay]          = ApolloColor.new("ChatNPC"),
        [ChatSystemLib.ChatChannel_NPCYell]         = ApolloColor.new("ChatNPC"),
        [ChatSystemLib.ChatChannel_NPCWhisper]      = ApolloColor.new("ChatNPC"),
        [ChatSystemLib.ChatChannel_Datachron]       = ApolloColor.new("ChatNPC"),
        [ChatSystemLib.ChatChannel_Combat]          = ApolloColor.new("ChatGeneral"),
        [ChatSystemLib.ChatChannel_Realm]           = ApolloColor.new("ChatSupport"),
        [ChatSystemLib.ChatChannel_Loot]            = ApolloColor.new("ChatLoot"),
        [ChatSystemLib.ChatChannel_Emote]           = ApolloColor.new("ChatEmote"),
        [ChatSystemLib.ChatChannel_PlayerPath]      = ApolloColor.new("ChatGeneral"),
        [ChatSystemLib.ChatChannel_Instance]        = ApolloColor.new("ChatInstance"),
        [ChatSystemLib.ChatChannel_WarParty]        = ApolloColor.new("ChatWarParty"),
        [ChatSystemLib.ChatChannel_WarPartyOfficer] = ApolloColor.new("ChatWarPartyOfficer"),
        [ChatSystemLib.ChatChannel_Advice]          = ApolloColor.new("ChatAdvice"),
        [ChatSystemLib.ChatChannel_AdviceGerman]    = ApolloColor.new("ChatAdvice"),
        [ChatSystemLib.ChatChannel_AdviceFrench]    = ApolloColor.new("ChatAdvice"),
        [ChatSystemLib.ChatChannel_AccountWhisper]  = ApolloColor.new("ChatAccountWisper"),
    }

local tDBDefaults = {
    profile = {
        strFontName  = "Nameplates",
        nNumMessages = 20,
        bAnnounce    = false,
        bAttach      = true,
        bRaidLeader  = false,
        ICChannel    = "testing",
        color = {
            Attacker = "ffffffff",
            Damage   = "ffffffff",
            Ability  = "ffffffff",
            Healing  = "ff008000"
        }
    }
}

local tReplacementAddons = {
  "BetterChatLog",
  "ImprovedChatLog",
  "ChatFixed",
  "Fixed Chat Log"
}
-----------------------------------------------------------------------------------------------
-- Standard Queue
-----------------------------------------------------------------------------------------------
local Queue = {}
function Queue.new()
    return {first = 0, last = -1}
end

function Queue.PushLeft(queue, value)
    local first = queue.first - 1
    queue.first = first
    queue[first] = value
end

function Queue.PushRight(queue, value)
    local last = queue.last + 1
    queue.last = last
    queue[last] = value
end

function Queue.PopLeft(queue)
    local first = queue.first
    if first > queue.last then error("queue is empty") end
    local value = queue[first]
    queue[first] = nil        -- to allow garbage collection
    queue.first = first + 1
    return value
end

function Queue.PopRight(queue)
    local last = queue.last
    if queue.first > last then error("queue is empty") end
    local value = queue[last]
    queue[last] = nil         -- to allow garbage collection
    queue.last = last - 1
    return value
end

function Queue.Size(queue)
    return queue.last - queue.first + 1
end

-----------------------------------------------------------------------------------------------
-- Startup
-----------------------------------------------------------------------------------------------
function WhatHappened:OnInitialize()
    self.db = Apollo.GetPackage("Gemini:DB-1.0").tPackage:New(self, tDBDefaults, true)
    GeminiColor = Apollo.GetPackage("GeminiColor").tPackage

    -- Slash commands
    Apollo.RegisterSlashCommand("wh", "OnWhatHappenedOn", self)
    Apollo.RegisterSlashCommand("wtf", "OnWhatHappenedOn", self)
    Apollo.RegisterSlashCommand("announce", "OnAnnounceToggle", self)

    --Combat Event Handlers
    Apollo.RegisterEventHandler("CombatLogDamage", "OnCombatLogDamage", self)
    Apollo.RegisterEventHandler("CombatLogHeal", "OnCombatLogHeal", self)
    Apollo.RegisterEventHandler("CombatLogDeath", "OnDeath", self)
    Apollo.RegisterEventHandler("UnitEnteredCombat", "OnEnteredCombat", self)

    -- Configuration Event Handlers
    Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
    Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
    Apollo.RegisterEventHandler("WindowManagementRegister", "OnWindowManagementReady", self)

--testing
    -- Load XML
    self.xml = XmlDoc.CreateFromFile("WhatHappened.xml")
end

function WhatHappened:OnEnable()

    Print("WhatHappened Has Loaded and is ready to GO!")
    Print('Thank You for using my addon and please consider donating if possible!')

    tCombatQueue = Queue.new()
    self.wndWhat = Apollo.LoadForm(self.xml, "WhatWindow", nil, self)

    -- Colors Setup
    local wndColorList = self.wndWhat:FindChild("OptionsSubForm:ColorsList")
    for strColorName, strColorHex in pairs(self.db.profile.color) do
        tColors["cr" .. strColorName] = ApolloColor.new(strColorHex)
        local wndColor = Apollo.LoadForm(self.xml, "ColorItem", wndColorList, self)
        wndColor:SetText(strColorName)
        wndColor:FindChild("ColorSwatch"):SetBGColor(strColorHex)
    end
    wndColorList:ArrangeChildrenVert(0)


    -- Set Current NumMessages
    self.wndWhat:FindChild("OptionsSubForm:CombatHistory:HistoryCount"):SetText(self.db.profile.nNumMessages)
    self.wndWhat:FindChild("OptionsSubForm:CombatHistory:SliderContainer:SliderBar"):SetValue(self.db.profile.nNumMessages)

    --Set Announce Option
    self.wndWhat:FindChild("OptionsSubForm:DeathAnnounce:btnDeathAnnounce"):SetCheck(self.db.profile.bAnnounce)

    -- Pre populate WhoSelection
    --local strName = GameLib.GetPlayerUnit():GetName()
    --self:AddDeathInfo(strName)
    --self.wndWhat:FindChild("WhoButton:WhoText"):SetText(strName)

    -- Get reference to ChatLog addon, or its replacement
    tChatLog = Apollo.GetAddon(strChatAddon)
end

function WhatHappened:OnDependencyError(strDep, strError)
  if strDep == "ChatLog" then
    local tReplaced = Apollo.GetReplacement(strDep)
    for nIdx, strReplacementName in ipairs(tReplaced) do
      local tReplacement = Apollo.GetAddonInfo(strReplacementName)
      if tReplacement and tReplacement.eStatus > 2 then
        strChatAddon = strReplacementName
        return true
      end
    end
  end
  return false
end



-----------------------------------------------------------------------------------------------
-- Slash Commands
-----------------------------------------------------------------------------------------------
-- Define general functions here
function WhatHappened:OnWhatHappenedOn(strCommand, strParam)
    if strParam == "reset" then
        self.db:ResetProfile()
        return
    end
end

-----------------------------------------------------------------------------------------------
-- Event Handlers and Timers
-----------------------------------------------------------------------------------------------
function WhatHappened:OnWindowManagementReady()
    -- ChatLog does all its setup when it hears this event.. so we need to wait a little bit for that to finish
    if self.db.profile.bAttach then
        atChatTimer = ApolloTimer.Create(0.5, false, "OnChatTimer", self)
    end
end

function WhatHappened:OnChatTimer()
    if tChatLog and tChatLog.tChatWindows then
        tChatLog.tChatWindows[1]:AttachTab(self.wndWhat)
    end
end

function WhatHappened:OnCombatLogDamage(tEventArgs)
    local unitMe = GameLib.GetPlayerUnit()
    -- Self inflicted damage doesn't count!
    if tEventArgs.unitCaster == unitMe then return end
    -- We're only tracking damage to ourselves
    if tEventArgs.unitTarget ~= unitMe then return end
    -- We don't care about extra damage when we're dead either
    if unitMe:IsDead() then return end


    tEventArgs.strCasterName = tEventArgs.unitCaster and tEventArgs.unitCaster:GetName() or "Unknown"
    tEventArgs.unitCaster = nil

    Queue.PushRight(tCombatQueue, tEventArgs)
    if Queue.Size(tCombatQueue) > self.db.profile.nNumMessages then
        Queue.PopLeft(tCombatQueue)
    end
end

function WhatHappened:OnCombatLogHeal(tEventArgs)
  local unitMe = GameLib.GetPlayerUnit()
  -- We don't care about extra damage when we're dead either
  if unitMe:IsDead() then return end

  tEventArgs.strCasterName = tEventArgs.strCasterName or (tEventArgs.unitCaster and tEventArgs.unitCaster:GetName() or "Unknown")
  tEventArgs.unitCaster = nil

  Queue.PushRight(tCombatQueue, tEventArgs)
  if Queue.Size(tCombatQueue) > self.db.profile.nNumMessages then
    Queue.PopLeft(tCombatQueue)
  end
end

function WhatHappened:OnDeath()
    local tMessage = {}
    local strName = GameLib.GetPlayerUnit():GetName()
    tDeathInfos[strName] = {}
    local tDeathInfo = tDeathInfos[strName]
    while Queue.Size(tCombatQueue) > 0 do
        local tEventArgs = Queue.PopLeft(tCombatQueue)
        tDeathInfo[#tDeathInfo + 1] = tEventArgs
    end
    self.wndWhat:FindChild("WhoButton:WhoText"):SetText(strName)
    GenerateLog(self, strName)
end

function WhatHappened:OnEnteredCombat(unitId, bInCombat)
    if bInCombat or unitId ~= GameLib.GetPlayerUnit() then return end
    -- We left combat, clear out the queue
    tCombatQueue = Queue.new()
end

function WhatHappened:OnAnnounceToggle()
    self.db.profile.bAnnounce = true
end
function WhatHappened:OnAnnounceToggleOff()
    self.db.profile.bAnnounce = false
end
---------------------------------------------------------------------------------------------------
-- Who Functions
---------------------------------------------------------------------------------------------------
function WhatHappened:AddDeathInfo(strName)
    -- Clear out info if already existant
    if tDeathInfos[strName] then
        tDeathInfos[strName] = {}
        return tDeathInfos[strName]
    end

    tDeathInfos[strName] = {}
    local wndWhoList = self.wndWhat:FindChild("PlayerWindow:PlayerMenuContent")
    local wndWhoEntry = Apollo.LoadForm(self.xml, "WhoEntry", wndWhoList, self)
    wndWhoEntry:FindChild("NameText"):SetText(strName)
    wndWhoEntry:SetData(strName)
    wndWhoList:ArrangeChildrenVert(0)

    return tDeathInfos[strName]
end

function WhatHappened:OnWhoSelect(wndHandler, wndControl, eMouseButton)
    local wndParent = wndControl:GetParent()
    local wndMenu = wndParent:FindChild("PlayerWindow")

    if wndHandler:IsChecked() then
        wndMenu:Invoke()
    else
        wndMenu:Close()
    end
end

function WhatHappened:OnWhoEntryClick(wndHandler, wndControl, eMouseButton)
    local strName = wndControl:GetData()
    self.wndWhat:FindChild("WhoButton:WhoText"):SetText(strName)
    GenerateLog(self, strName)
    self.wndWhat:FindChild("WhoButton"):SetCheck(false)
    wndControl:GetParent():GetParent():Close() -- Ancestor Chain: Btn->PlayerMenuContent->PlayerWindow
end

---------------------------------------------------------------------------------------------------
-- Log Display
---------------------------------------------------------------------------------------------------
function GenerateLog(self, strName)
  local tDeathInfo = tDeathInfos[strName]
  if not tDeathInfo then return end

  local wndWhatLog = self.wndWhat:FindChild("WhatLog")
  wndWhatLog:DestroyChildren()

local strFinalEvent

  for nIdx, tEventArgs in ipairs(tDeathInfo) do
    local wndWhatLine = Apollo.LoadForm(self.xml, "WhatLine", wndWhatLog, self)
    local xml = XmlDoc.new()
    xml:AddLine(tEventArgs.strCasterName, tColors.crAttacker, self.db.profile.strFontName, "Left")
    xml:AppendText(": ", tColors.crWhite, self.db.profile.strFontName, "Left")
    xml:AppendText(tEventArgs.splCallingSpell:GetName(), tColors.crAbility, self.db.profile.strFontName, "Left")
    xml:AppendText(" for ", tColors.crWhite, self.db.profile.strFontName, "Left")

    if tEventArgs.strCasterName ~= nil or tEventArgs.nDamageAmount ~= nil then
      strFinalEvent = tEventArgs.strCasterName .. ", Death Blow: " .. tEventArgs.nDamageAmount or 0
    end

    if tEventArgs.nDamageAmount then  --check if its an attack!
      xml:AppendText((tEventArgs.nDamageAmount or 0) .. " " .. (tEventArgs.eDamageType and ktDamageTypeToName[tEventArgs.eDamageType] or "Unknown"), tColors.crDamage, self.db.profile.strFontName, "Left")
      xml:AppendText(" Damage", tColors.crWhite, self.db.profile.strFontName, "Left")
      if tEventArgs.nOverkill and tEventArgs.nOverkill > 0 then
        xml:AppendText(", Overkill: ", tColors.crWhite, self.db.profile.strFontName, "Left")
        xml:AppendText(tostring(tEventArgs.nOverkill), tColors.crDamage, self.db.profile.strFontName, "Left")
      end
    elseif tEventArgs.nHealAmount then  --check if its a heal!
      xml:AppendText(tEventArgs.nHealAmount, tColors.crHealing, self.db.profile.strFontName, "Left")
      xml:AppendText(" Healing", tColors.crWhite, self.db.profile.strFontName, "Left")
      if tEventArgs.nOverheal > 0 then
        xml:AppendText(", Overheal: ", tColors.crWhite, self.db.profile.strFontName, "Left")
        xml:AppendText(tostring(tEventArgs.nOverheal), tColors.crHealing, self.db.profile.strFontName, "Left")
      end

    end

    wndWhatLine:SetDoc(xml)
    wndWhatLine:SetHeightToContentHeight()

  end
  wndWhatLog:ArrangeChildrenVert(0)

  --Announce your Death to the party.
    if self.db.profile.bAnnounce then
        local strDeathMsg = " I Was Killed By: " .. strFinalEvent
        ChatSystemLib.Command(("/%s %s"):format("Party", strDeathMsg))
    end
end
---------------------------------------------------------------------------------------------------
-- WhatWindow Options Functions
---------------------------------------------------------------------------------------------------
function WhatHappened:OnOptionsToggle(wndHandler, wndControl, eMouseButton)
    self.wndWhat:FindChild("OptionsSubForm"):Show(wndControl:IsChecked())
end

function WhatHappened:OnHistorySliderChanged(wndHandler, wndControl, fNewValue, fOldValue)
    local wndCount = self.wndWhat:FindChild("OptionsSubForm:CombatHistory:HistoryCount")
    local nNewVal = floor(fNewValue)
    wndCount:SetText(nNewVal)
    self.db.profile.nNumMessages = nNewVal
end

function WhatHappened:OnColorUpdate(strColor, wndControl)
    wndControl:FindChild("ColorSwatch"):SetBGColor(strColor)
    local strColorName = wndControl:GetText()
    self.db.profile.color[strColorName] = strColor
    tColors["cr" .. strColorName] = ApolloColor.new(strColor)
end

function WhatHappened:OnColorItemClick(wndHandler, wndControl, eMouseButton)
    local tColorOpts = {
        callback = "OnColorUpdate",
        bCustomColor = true,
        bAlpha = false,
        strInitialColor = self.db.profile.color[wndControl:GetText()]
    }
    GeminiColor:ShowColorPicker(self, tColorOpts, wndControl)
end
