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
-- GetSpellInfo: on retail/Classic, GetSpellInfo(nil) (or a non-positive id)
-- returns nil; on this 3.3.5a core it raises a hard "Invalid spell slot" error
-- that aborts whatever is running (hit whenever a tonumber(name)->nil id reaches
-- it from an option/test builder). Wrap it to return nil for nil / <=0 input like
-- retail, so existence checks (`if GetSpellInfo(x)`) keep working and never error.
-- Compat.lua loads first, so every later `local GetSpellInfo = GetSpellInfo` in a
-- module/lib captures this guarded version. This is the root fix for that class.
--==========================================================================
do
    local origGetSpellInfo = _G.GetSpellInfo
    if type(origGetSpellInfo) == "function" then
        function _G.GetSpellInfo(spell, ...)
            if spell == nil or (type(spell) == "number" and spell <= 0) then
                return nil
            end
            return origGetSpellInfo(spell, ...)
        end
    end
end

--==========================================================================
-- UnitInPhase (Cata) / UnitInRange (Cata): the Range Check module caches and
-- calls these, but neither exists on 3.3.5a (no phasing; UnitInRange is 4.0+) -
-- not even with awesome_wotlk - so the nil upvalue errors on every range tick.
-- Phasing doesn't exist on 3.3.5a, so everyone is in phase (return true);
-- approximate UnitInRange with CheckInteractDistance (~28yd follow range).
-- Compat loads first, so RangeCheck's `local UnitInRange = UnitInRange` captures
-- these.
--==========================================================================
if type(_G.UnitInPhase) ~= "function" then
    function _G.UnitInPhase() return true end
end
if type(_G.UnitInRange) ~= "function" then
    function _G.UnitInRange(unit)
        if not unit then return false, false end
        return (CheckInteractDistance(unit, 4) and true or false), true
    end
end

--==========================================================================
-- Metatable method shims. In 3.3.5a every widget type has its own method
-- table at getmetatable(obj).__index; adding a missing method there makes it
-- available on every object of that type. Grab one throwaway object per type.
-- (Done while CreateFrame is still the original, before it is wrapped below.)
-- IMPORTANT: install NEW methods with rawset(meta, name, fn). On this client the
-- FRAME-type method tables carry a __newindex guard that silently swallows a
-- plain `meta.Name = fn` for a key that doesn't exist yet, leaving the method
-- nil (a latent crash on stock 3.3.5a, where these shims actually run). Every
-- `if not meta.Name` guard below stays chain-aware so a native is never shadowed.
-- (Overriding an EXISTING key with plain assignment is fine -- __newindex only
-- fires for absent keys -- so the native-wrapping shims further down keep `=`.)
--==========================================================================
local uiParent = _G.UIParent
local sampleFrame = CreateFrame("Frame", nil, uiParent)
local sampleButton = CreateFrame("Button", nil, uiParent)
local sampleCooldown = CreateFrame("Cooldown", nil, uiParent)
local sampleStatusBar = CreateFrame("StatusBar", nil, uiParent)
local sampleTexture = sampleFrame:CreateTexture()
local sampleFontString = sampleFrame:CreateFontString()
-- NOTE: deliberately NOT sampling an EditBox here - a bare CreateFrame("EditBox")
-- defaults to autoFocus=true and would grab keyboard focus at load.

local frameMeta = getmetatable(sampleFrame).__index
local buttonMeta = getmetatable(sampleButton).__index
local cooldownMeta = getmetatable(sampleCooldown).__index
local statusBarMeta = getmetatable(sampleStatusBar).__index
local textureMeta = getmetatable(sampleTexture).__index
local fontStringMeta = getmetatable(sampleFontString).__index

local function noop() end

-- (K) Region:SetSize/GetSize (Cata 4.0) and Frame:SetResizeBounds (Dragonflight 10.0)
-- do not exist on stock 3.3.5a, but several bundled libs call them unconditionally:
-- LibCustomGlow (the Cooldowns glow), AceConfigDialog + AceGUI TabGroup/TreeGroup/Frame
-- (the whole options window), the GladdySearchEditBox widget, and Healthbar's absorb
-- overlay. They WORK on the awesome_wotlk test client (which supersets these), so the
-- gap is invisible there, but on stock 3.3.5a every one is a nil-method crash. Map them
-- onto the genuine 3.3.5a primitives (SetWidth/SetHeight, SetMinResize/SetMaxResize).
-- Each widget type has its own method table on 3.3.5a, so add to each separately; the
-- `if not` guard makes this inert wherever the method already exists.
local function addSizeShims(meta)
    if not meta then return end
    if not meta.SetSize then
        rawset(meta, "SetSize", function(self, w, h) self:SetWidth(w); self:SetHeight(h or w) end)
    end
    if not meta.GetSize then
        rawset(meta, "GetSize", function(self) return self:GetWidth(), self:GetHeight() end)
    end
end
for _, meta in ipairs({ frameMeta, buttonMeta, cooldownMeta, statusBarMeta, textureMeta, fontStringMeta }) do
    addSizeShims(meta)
end
if not frameMeta.SetResizeBounds then
    rawset(frameMeta, "SetResizeBounds", function(self, minW, minH, maxW, maxH)
        if self.SetMinResize then self:SetMinResize(minW or 0, minH or 0) end
        if maxW and self.SetMaxResize then self:SetMaxResize(maxW, maxH or maxW) end
    end)
end

-- (K) Cooldown:Clear (Cata 4.0): Auras/Racial/Trinket call cooldown:Clear() to wipe the
-- spiral; absent on stock 3.3.5a. SetCooldown(0, 0) clears it the 3.3.5a way.
if not cooldownMeta.Clear then
    rawset(cooldownMeta, "Clear", function(self) self:SetCooldown(0, 0) end)
end

-- (H) Retail frame methods used unguarded by AceConfigDialog-3.0:
--     SetPropagateKeyboardInput (Legion), SetFixedFrameStrata/Level (9.0).
--     No-op them - the dialog still works, it just can't pin strata/level.
if not frameMeta.SetPropagateKeyboardInput then rawset(frameMeta, "SetPropagateKeyboardInput", noop) end
if not frameMeta.SetFixedFrameStrata then rawset(frameMeta, "SetFixedFrameStrata", noop) end
if not frameMeta.SetFixedFrameLevel then rawset(frameMeta, "SetFixedFrameLevel", noop) end

-- (H) Frame:SetClipsChildren (Legion) is called unguarded by ExportImport on the
--     AceGUI MultiLineEditBox frame. No-op it - on 3.3.5a children just aren't
--     clipped to the frame bounds, which is purely cosmetic for the export box.
if not frameMeta.SetClipsChildren then rawset(frameMeta, "SetClipsChildren", noop) end

-- (H) Frame:SetIgnoreParentAlpha (BfA) is called by TotemPlates on the totem
--     overlay frame so it stays opaque while the nameplate fades. No-op on
--     3.3.5a: the overlay just inherits the nameplate's alpha (cosmetic only).
if not frameMeta.SetIgnoreParentAlpha then rawset(frameMeta, "SetIgnoreParentAlpha", noop) end

-- (H) Frame:SetIgnoreParentScale (BfA) - TotemPlates uses it on its test frame.
--     No-op on 3.3.5a: the frame just inherits the parent's scale (cosmetic).
if not frameMeta.SetIgnoreParentScale then rawset(frameMeta, "SetIgnoreParentScale", noop) end

-- (J) RegisterUnitEvent (MoP): missing on STOCK 3.3.5a. awesome_wotlk-based
--     clients (e.g. Triumvirate) DO expose it natively - but even there the
--     modern event NAMES the modules register (UNIT_HEALTH_FREQUENT = Cata,
--     UNIT_POWER_UPDATE/UNIT_MAXPOWER = Cata/MoP) never actually fire (seen in
--     a real arena 2026-07-08: health froze at spot-time snapshots and the 0-hp
--     death path never ran, so a dead enemy kept showing stale health). So the
--     wrapper must be installed on BOTH kinds of client, not only when
--     RegisterUnitEvent is absent:
--       * the modern event goes through the native RegisterUnitEvent when one
--         exists, else through RegisterEvent. 3.3.5a fires unit events for ALL
--         units, so add a per-frame unit filter: take over the frame's OnEvent
--         with a dispatcher and intercept this frame's SetScript/GetScript
--         ("OnEvent") so the module's handler only runs for a matching unit
--         (unit-less events pass through).
--       * ALSO register the genuine 3.3.5a events and translate them back to
--         the modern name in dispatch (the handlers either are name-agnostic or
--         branch on the modern name). The translation uses a PER-FRAME alias
--         map filled only for events that frame requested, so foreign frames
--         going through a native RegisterUnitEvent keep their event names.
local modernToLegacy = {
    UNIT_HEALTH_FREQUENT = { "UNIT_HEALTH" },
    UNIT_POWER_UPDATE = { "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_RUNIC_POWER", "UNIT_HAPPINESS" },
    UNIT_MAXPOWER = { "UNIT_MAXMANA", "UNIT_MAXRAGE", "UNIT_MAXENERGY", "UNIT_MAXFOCUS", "UNIT_MAXRUNIC_POWER", "UNIT_MAXHAPPINESS" },
}
do
    local origRegisterUnitEvent = frameMeta.RegisterUnitEvent
    local origSetScript = frameMeta.SetScript
    local origGetScript = frameMeta.GetScript
    local function unitDispatch(self, event, unit, ...)
        local filter = self.__gladdyUnitFilter
        if filter and unit ~= nil and not filter[unit] then return end
        local handler = self.__gladdyOnEvent
        if not handler then return end
        -- translate a 3.3.5a event back to the modern name this frame asked for
        local alias = self.__gladdyEventAlias
        return handler(self, alias and alias[event] or event, unit, ...)
    end
    rawset(frameMeta, "RegisterUnitEvent", function(self, event, unit1, unit2)
        self.__gladdyUnitFilter = self.__gladdyUnitFilter or {}
        if unit1 then self.__gladdyUnitFilter[unit1] = true end
        if unit2 then self.__gladdyUnitFilter[unit2] = true end
        if not self.__gladdyUnitDispatch then
            self.__gladdyUnitDispatch = true
            self.__gladdyOnEvent = origGetScript(self, "OnEvent")
            origSetScript(self, "OnEvent", unitDispatch)
            -- per-object intercepts so the module's later SetScript("OnEvent", h)
            -- feeds the dispatcher instead of replacing it
            self.SetScript = function(f, script, handler)
                if script == "OnEvent" then
                    f.__gladdyOnEvent = handler
                else
                    return origSetScript(f, script, handler)
                end
            end
            self.GetScript = function(f, script)
                if script == "OnEvent" then return f.__gladdyOnEvent end
                return origGetScript(f, script)
            end
        end
        if origRegisterUnitEvent then
            origRegisterUnitEvent(self, event, unit1, unit2)
        else
            self:RegisterEvent(event)
        end
        -- also register the genuine 3.3.5a equivalents so the bar updates even
        -- when the client accepts the modern name but never fires it
        local legacies = modernToLegacy[event]
        if legacies then
            self.__gladdyEventAlias = self.__gladdyEventAlias or {}
            for _, leg in ipairs(legacies) do
                self.__gladdyEventAlias[leg] = event
                pcall(self.RegisterEvent, self, leg)
            end
        end
    end)
end

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
if not cooldownMeta.SetHideCountdownNumbers then rawset(cooldownMeta, "SetHideCountdownNumbers", noop) end

-- (H) Texture:SetMask / SetMaskTexture (7.0): every Gladdy icon module masks its
--     icon with "Interface\AddOns\Gladdy\Images\mask" for a rounded look. On stock
--     3.3.5a there is no SetMask, so it must no-op (icons stay square). BUT on a
--     client that DOES provide a native SetMask (awesome_wotlk), applying Gladdy's
--     mask renders the icons fully INVISIBLE (the mask's alpha convention doesn't
--     match this implementation). So intercept only Gladdy's own mask path and
--     skip it (icons stay square but VISIBLE); any other texture/path is delegated
--     to the native SetMask so we don't break masking for other addons globally.
do
    local origSetMask = textureMeta.SetMask
    textureMeta.SetMask = function(self, file, ...)
        if type(file) == "string" and file:find("Gladdy", 1, true) then
            return -- Gladdy icon mask -> skip so the icon stays visible
        end
        if origSetMask then return origSetMask(self, file, ...) end
    end
end
if not textureMeta.SetMaskTexture then rawset(textureMeta, "SetMaskTexture", noop) end

-- (H) Texture:SetIgnoreParentAlpha (BfA) - TotemPlates uses it on the totem
--     selection-highlight texture. No-op on 3.3.5a (cosmetic, see frame shim).
if not textureMeta.SetIgnoreParentAlpha then rawset(textureMeta, "SetIgnoreParentAlpha", noop) end

-- (H) AnimationGroup / Animation methods added after 3.3.5a, used by the
--     Cooldowns activation/flash glow: SetToFinalAlpha (4.0) on the group, and
--     SetTarget (Legion) + SetFromAlpha/SetToAlpha (4.0; 3.3.5a uses SetChange)
--     on the Alpha animations. Unlike Frame/Texture, the AnimationGroup/Animation
--     metatables are NOT reliably shared/writable on 3.3.5a (which is why
--     LibCustomGlow bypasses the animation API entirely), so patching their
--     metatable wouldn't reach the groups Cooldowns creates. Instead wrap
--     frameMeta.CreateAnimationGroup (which IS shared) and inject the missing
--     methods directly onto each group + animation instance. No-op is fine: the
--     glow still shows/hides via the group's OnPlay/OnFinished scripts over its
--     total duration, just without the smooth alpha fade.
local origCreateAnimationGroup = frameMeta.CreateAnimationGroup
if origCreateAnimationGroup then
    frameMeta.CreateAnimationGroup = function(self, ...)
        local group = origCreateAnimationGroup(self, ...)
        if group then
            if not group.SetToFinalAlpha then group.SetToFinalAlpha = noop end
            local origCreateAnimation = group.CreateAnimation
            if origCreateAnimation then
                group.CreateAnimation = function(g, ...)
                    local anim = origCreateAnimation(g, ...)
                    if anim then
                        if not anim.SetTarget then anim.SetTarget = noop end
                        if not anim.SetFromAlpha then anim.SetFromAlpha = noop end
                        if not anim.SetToAlpha then anim.SetToAlpha = noop end
                    end
                    return anim
                end
            end
        end
        return group
    end
end

-- (G) Texture:SetColorTexture (Legion). On 3.3.5a SetTexture(r,g,b,a) already
--     sets a solid colour, so forward to it.
if not textureMeta.SetColorTexture then
    rawset(textureMeta, "SetColorTexture", function(self, r, g, b, a)
        return self:SetTexture(r, g, b, a or 1)
    end)
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
    rawset(tooltipMeta, "SetSpellByID", function(self, spellId)
        if not spellId or not GetSpellInfo(spellId) then return end
        return self:SetHyperlink("spell:" .. spellId)
    end)
end

--==========================================================================
-- (D) Templates that do not exist on 3.3.5a. CreateFrame hard-errors on an
-- unknown template, which aborts the CALLER'S whole file when hit in a main
-- chunk. Done LAST so the metatable sampling above used the original
-- CreateFrame.
--   * "BackdropTemplate" (8.0): all 3.3.5a frames have a backdrop natively -
--     strip the token.
--   * "DialogBorder*Template" (retail dialog nine-slice): AceConfigDialog r81+
--     builds its confirm popup with it IN ITS MAIN CHUNK, so the whole library
--     aborted on load (options then only worked if some other addon registered
--     an older AceConfigDialog). Recreate the look with the native StaticPopup
--     backdrop on the created frame.
--   * Any other unknown template: retry without it - an undecorated frame
--     beats aborting the caller (same policy as the CreateTexture shim).
--==========================================================================
local dialogBorderBackgrounds = {
    DialogBorderTemplate = "Interface\\DialogFrame\\UI-DialogBox-Background",
    DialogBorderOpaqueTemplate = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    DialogBorderDarkTemplate = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
}
local origCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template, ...)
    if type(template) == "string" and template:find("BackdropTemplate") then
        template = template:gsub("BackdropTemplate", "")
        template = template:gsub(",%s*,", ","):gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
        if template == "" then template = nil end
    end
    if type(template) == "string" then
        local dialogBg = dialogBorderBackgrounds[template]
        if dialogBg then
            local frame = origCreateFrame(frameType, name, parent)
            frame:SetBackdrop({
                bgFile = dialogBg,
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
            return frame
        end
        local ok, frame = pcall(origCreateFrame, frameType, name, parent, template, ...)
        if ok and frame then
            return frame
        end
        return origCreateFrame(frameType, name, parent)
    end
    return origCreateFrame(frameType, name, parent, template, ...)
end
