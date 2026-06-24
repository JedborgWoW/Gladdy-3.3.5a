--[[--------------------------------------------------------------------------
    Gladdy - WoW 3.3.5a (WotLK 3.3.5) compatibility shims

    Loaded FIRST in the .toc (before embeds.xml) so the globals and metatable
    methods defined here exist before any library or module runs.

    Design goal: keep all upstream / library code byte-for-byte untouched so
    future merges stay trivial. Every 3.3.5a incompatibility is handled here
    by shimming a missing global or method - never by editing the caller.

    Each block notes WHY the shim is needed (letters refer to the backport
    task list).
----------------------------------------------------------------------------]]

local _G = _G

--==========================================================================
-- WOW_PROJECT_ID: does not exist on 3.3.5a. Several libs branch on it
-- (LibClassAuras, DRList, LibSharedMedia, AceGUI-ColorPicker). Pin it to
-- WRATH_CLASSIC so they all take the nearest Classic code path, and so any
-- numeric comparison against it can never error on a nil value.
--==========================================================================
WOW_PROJECT_MAINLINE = WOW_PROJECT_MAINLINE or 1
WOW_PROJECT_CLASSIC = WOW_PROJECT_CLASSIC or 2
WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC or 11
if WOW_PROJECT_ID == nil then
    WOW_PROJECT_ID = WOW_PROJECT_WRATH_CLASSIC
end

--==========================================================================
-- (C) GetCurrentRegion / GetCurrentRegionName: added in WoD (6.0), missing on
-- 3.3.5a. AceDB-3.0 calls GetCurrentRegion() unguarded at load time
-- (regionTable[GetCurrentRegion()]); without this the call aborts AceDB and
-- the whole addon fails to load. regionTable is { "US","KR","EU","TW","CN" },
-- so returning 1 / "US" yields a valid region key.
--==========================================================================
if type(_G.GetCurrentRegion) ~= "function" then
    function _G.GetCurrentRegion() return 1 end
end
if type(_G.GetCurrentRegionName) ~= "function" then
    function _G.GetCurrentRegionName() return "US" end
end

--==========================================================================
-- (J) Modern group API: GetNumGroupMembers / IsInRaid / IsInGroup were added
-- in MoP. Map them onto the 3.3.5a GetNumRaidMembers / GetNumPartyMembers so
-- any current or future-merged caller keeps working.
--==========================================================================
if type(_G.GetNumGroupMembers) ~= "function" then
    function _G.GetNumGroupMembers()
        local raid = GetNumRaidMembers()
        if raid > 0 then return raid end
        return GetNumPartyMembers()
    end
end
if type(_G.IsInRaid) ~= "function" then
    function _G.IsInRaid() return GetNumRaidMembers() > 0 end
end
if type(_G.IsInGroup) ~= "function" then
    function _G.IsInGroup() return GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 end
end

--==========================================================================
-- (I) securecallfunction: retail (10.0) secure-call helper. CallbackHandler
-- and ChatThrottleLib already fall back to `securecallfunction or pcall`, but
-- providing a real implementation routes errors to the error handler like
-- retail does instead of silently swallowing them.
--==========================================================================
if type(_G.securecallfunction) ~= "function" then
    function _G.securecallfunction(func, ...)
        local results = { pcall(func, ...) }
        if results[1] then
            return unpack(results, 2, table.maxn(results))
        end
        geterrorhandler()(results[2])
    end
end

--==========================================================================
-- Enum.SpellBookSpellBank: retail (10.x) enum. LibSpellRange-1.0 picks its
-- spell-book token at load with
--     playerBook = GetSpellBookItemName and "spell" or Enum.SpellBookSpellBank.Player
-- On 3.3.5a GetSpellBookItemName is nil, so it falls through to the enum and
-- indexing the missing Enum.SpellBookSpellBank.Player aborts the lib at load.
-- Map the enum onto the classic book-type strings ("spell"/"pet") so the
-- fallback yields the correct 3.3.5a value instead of erroring.
--==========================================================================
_G.Enum = _G.Enum or {}
if _G.Enum.SpellBookSpellBank == nil then
    _G.Enum.SpellBookSpellBank = { Player = "spell", Pet = "pet" }
end

--==========================================================================
-- Ambiguate(name, context): added in WoD (6.0). AceComm-3.0's CHAT_MSG_ADDON
-- handler calls Ambiguate(sender, "none") unguarded; without it every received
-- addon message errors (42x in the report). On retail "none" returns the name
-- unchanged (realm kept) and "short" strips the realm - reproduce that. 3.3.5a
-- senders usually carry no realm anyway, so this is a safe no-op for "none".
--==========================================================================
if type(_G.Ambiguate) ~= "function" then
    function _G.Ambiguate(name, context)
        if type(name) ~= "string" then return name end
        if context == "short" then
            return name:match("^([^-]+)") or name
        end
        return name
    end
end

--==========================================================================
-- RegisterAddonMessagePrefix: added in 4.1, missing on 3.3.5a (and C_ChatInfo
-- does not exist either). AceComm:RegisterComm calls it unguarded, so Gladdy's
-- own VersionCheck would error the first time it registers in an arena. On
-- 3.3.5a SendAddonMessage needs no prefix registration, so a no-op is correct.
--==========================================================================
if type(_G.RegisterAddonMessagePrefix) ~= "function" then
    function _G.RegisterAddonMessagePrefix() end
end

--==========================================================================
-- Metatable method shims. In 3.3.5a every widget type has its own method
-- table at getmetatable(obj).__index; adding a missing method there makes it
-- available on every object of that type. Grab one throwaway object per type.
-- (Done while CreateFrame is still the original, before it is wrapped below.)
--==========================================================================
local uiParent = _G.UIParent
local sampleFrame = CreateFrame("Frame", nil, uiParent)
local sampleButton = CreateFrame("Button", nil, uiParent)
local sampleCooldown = CreateFrame("Cooldown", nil, uiParent)
local sampleTexture = sampleFrame:CreateTexture()

local frameMeta = getmetatable(sampleFrame).__index
local buttonMeta = getmetatable(sampleButton).__index
local cooldownMeta = getmetatable(sampleCooldown).__index
local textureMeta = getmetatable(sampleTexture).__index

local function noop() end

-- (H) Retail frame methods used unguarded by AceConfigDialog-3.0:
--     SetPropagateKeyboardInput (Legion), SetFixedFrameStrata/Level (9.0).
--     No-op them - the dialog still works, it just can't pin strata/level.
if not frameMeta.SetPropagateKeyboardInput then frameMeta.SetPropagateKeyboardInput = noop end
if not frameMeta.SetFixedFrameStrata then frameMeta.SetFixedFrameStrata = noop end
if not frameMeta.SetFixedFrameLevel then frameMeta.SetFixedFrameLevel = noop end

-- (H) Frame:SetClipsChildren (Legion) is called unguarded by ExportImport on the
--     AceGUI MultiLineEditBox frame. No-op it - on 3.3.5a children just aren't
--     clipped to the frame bounds, which is purely cosmetic for the export box.
if not frameMeta.SetClipsChildren then frameMeta.SetClipsChildren = noop end

-- (D) Texture inheritance templates added after 3.3.5a. The Healthbar absorb bar
--     does frame:CreateTexture(nil, layer, "TotalAbsorbBarTemplate"/...) and
--     CreateTexture errors when asked to inherit from a template that doesn't
--     exist, aborting the whole button creation. Wrap CreateTexture to retry
--     without the template (and drop the post-3.3.5a subLevel arg). The resulting
--     plain texture is harmless: absorbs don't exist on 3.3.5a, so the bar is
--     never populated (UNIT_ABSORB_AMOUNT_CHANGED never fires) and stays hidden.
local origCreateTexture = frameMeta.CreateTexture
frameMeta.CreateTexture = function(self, name, layer, template, subLevel)
    if type(template) == "string" then
        local ok, tex = pcall(origCreateTexture, self, name, layer, template)
        if ok and tex then return tex end
        return origCreateTexture(self, name, layer)
    end
    return origCreateTexture(self, name, layer)
end

-- (H) Cooldown:SetHideCountdownNumbers (Legion) is called unguarded by every
--     icon module. No-op it - 3.3.5a cooldowns never draw built-in numbers.
if not cooldownMeta.SetHideCountdownNumbers then cooldownMeta.SetHideCountdownNumbers = noop end

-- (H) Texture:SetMask / SetMaskTexture (7.0) used unguarded by every icon
--     module for rounded icons. No-op: icons simply stay square on 3.3.5a.
if not textureMeta.SetMask then textureMeta.SetMask = noop end
if not textureMeta.SetMaskTexture then textureMeta.SetMaskTexture = noop end

-- (G) Texture:SetColorTexture (Legion). On 3.3.5a SetTexture(r,g,b,a) already
--     sets a solid colour, so forward to it.
if not textureMeta.SetColorTexture then
    function textureMeta.SetColorTexture(self, r, g, b, a)
        return self:SetTexture(r, g, b, a or 1)
    end
end

--==========================================================================
-- (F) Numeric texture fileIDs (post-MoP). 3.3.5a cannot resolve a fileID to a
-- file; it needs the string path. Several AceGUI widgets and AceConfigDialog
-- pass fileIDs to SetTexture / SetNormal|Pushed|HighlightTexture (the path is
-- in a same-line comment upstream). Translate the known UI fileIDs back to
-- their paths here, leaving the upstream files untouched.
--
-- NOTE: SetTexture(r,g,b,a) (solid colour) also takes numbers, but those are
-- <= 1, so only integers > 1 (real fileIDs) are translated. Unknown fileIDs
-- (e.g. the spell/spec icon IDs in Constants) map to nil -> a blank icon,
-- which is the same harmless result they had before, but never an error.
--==========================================================================
local fileIDToPath = {
    [130763] = "Interface\\Buttons\\UI-DialogBox-Button-Up",
    [130761] = "Interface\\Buttons\\UI-DialogBox-Button-Down",
    [130762] = "Interface\\Buttons\\UI-DialogBox-Button-Highlight",
    [130939] = "Interface\\ChatFrame\\ChatFrameColorSwatch",
    [188523] = "Tileset\\Generic\\Checkers",
    [136810] = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    [131080] = "Interface\\DialogFrame\\UI-DialogBox-Header",
    [137057] = "Interface\\Tooltips\\UI-Tooltip-Border",
    [137056] = "Interface\\Tooltips\\UI-Tooltip-Background",
    [251966] = "Interface\\PaperDollInfoFrame\\UI-GearManager-Title-Background",
    [251963] = "Interface\\PaperDollInfoFrame\\UI-GearManager-Border",
    [130843] = "Interface\\Buttons\\UI-RadioButton",
    [130755] = "Interface\\Buttons\\UI-CheckBox-Up",
    [130751] = "Interface\\Buttons\\UI-CheckBox-Check",
    [130753] = "Interface\\Buttons\\UI-CheckBox-Highlight",
    [136580] = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight",
    [130838] = "Interface\\Buttons\\UI-PlusButton-UP",
    [130836] = "Interface\\Buttons\\UI-PlusButton-DOWN",
    [130821] = "Interface\\Buttons\\UI-MinusButton-UP",
    [130820] = "Interface\\Buttons\\UI-MinusButton-DOWN",
    [130940] = "Interface\\ChatFrame\\ChatFrameExpandArrow",
}

local function wrapTextureSetter(meta, methodName)
    local original = meta[methodName]
    if not original then return end
    meta[methodName] = function(self, a1, ...)
        if type(a1) == "number" and a1 > 1 then
            -- a real fileID: translate to a path (or nil -> blank, never error)
            return original(self, fileIDToPath[a1])
        end
        return original(self, a1, ...)
    end
end

wrapTextureSetter(textureMeta, "SetTexture")
wrapTextureSetter(buttonMeta, "SetNormalTexture")
wrapTextureSetter(buttonMeta, "SetPushedTexture")
wrapTextureSetter(buttonMeta, "SetHighlightTexture")
wrapTextureSetter(buttonMeta, "SetDisabledTexture")

--==========================================================================
-- (A) #132 ACCESS_VIOLATION (hard native crash). GameTooltip:SetSpellByID
-- does not exist on 3.3.5a, AND GameTooltip:SetHyperlink("spell:<id>") with a
-- spellID the core does not know crashes the client natively. Validate every
-- spell hyperlink with GetSpellInfo first, and shim SetSpellByID to route
-- through that validated path. Wrapping the shared GameTooltip method table
-- covers GameTooltip and every GameTooltipTemplate frame (AceConfigDialog's
-- tooltip, the GladdySearchEditBox spell tooltip, etc.).
--==========================================================================
local tooltipMeta = getmetatable(_G.GameTooltip).__index
local origSetHyperlink = tooltipMeta.SetHyperlink
if origSetHyperlink then
    tooltipMeta.SetHyperlink = function(self, link, ...)
        if type(link) == "string" then
            local spellId = link:match("^spell:(%d+)")
            if spellId and not GetSpellInfo(tonumber(spellId)) then
                return -- unknown spell -> SetHyperlink would hard-crash the client
            end
        end
        return origSetHyperlink(self, link, ...)
    end
end
if not tooltipMeta.SetSpellByID then
    function tooltipMeta.SetSpellByID(self, spellId)
        if not spellId or not GetSpellInfo(spellId) then return end
        return self:SetHyperlink("spell:" .. spellId)
    end
end

--==========================================================================
-- (D) "BackdropTemplate" does not exist on 3.3.5a (all frames have a backdrop
-- natively); passing it to CreateFrame errors. The current tree has none left,
-- but wrapping CreateFrame to strip the token keeps it safe across future
-- upstream merges. Done LAST so the metatable sampling above used the original
-- CreateFrame.
--==========================================================================
local origCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template, ...)
    if type(template) == "string" and template:find("BackdropTemplate") then
        template = template:gsub("BackdropTemplate", "")
        template = template:gsub(",%s*,", ","):gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
        if template == "" then template = nil end
    end
    return origCreateFrame(frameType, name, parent, template, ...)
end
