local select, string_gsub, tostring, pairs, ipairs = select, string.gsub, tostring, pairs, ipairs
local wipe = wipe
local unpack = unpack
local abs = math.abs

local AURA_TYPE_DEBUFF, AURA_TYPE_BUFF = "DEBUFF", "BUFF"

local UnitName, UnitAura, UnitRace, UnitClass, UnitGUID, UnitIsUnit, UnitExists = UnitName, UnitAura, UnitRace, UnitClass, UnitGUID, UnitIsUnit, UnitExists
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime

local Gladdy = LibStub("Gladdy")
local L = Gladdy.L
local Cooldowns = Gladdy.modules["Cooldowns"]

local EventListener = Gladdy:NewModule("EventListener", 101, {
    test = true,
})

function EventListener:Initialize()
    self.friendlyUnits = {}
    self.activeAuras = {}
    self:RegisterMessage("JOINED_ARENA")
end

function EventListener.OnEvent(self, event, ...)
    EventListener[event](self, ...)
end

function EventListener:JOINED_ARENA()
    self.friendlyUnits = {["player"] = true}
    for i=2, Gladdy.curBracket do
        self.friendlyUnits["party" .. i-1] = true
    end
    self.activeAuras = {}
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("ARENA_OPPONENT_UPDATE")
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("UNIT_SPELLCAST_START")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    -- in case arena has started already we check for units
    for i=1,Gladdy.curBracket do
        if Gladdy.buttons["arena"..i].lastAuras then
            wipe(Gladdy.buttons["arena"..i].lastAuras)
        end
        if Gladdy.buttons["arena"..i].lastCastSpell then
            wipe(Gladdy.buttons["arena"..i].lastCastSpell)
        end
        if UnitExists("arena" .. i) then
            Gladdy:SpotEnemy("arena" .. i, true, true)
        end
        if UnitExists("arenapet" .. i) then
            Gladdy:SendMessage("PET_SPOTTED", "arenapet" .. i)
        end
    end
    Gladdy.bombExpireTime = {}
    self:SetScript("OnEvent", EventListener.OnEvent)
    --detect spec
    self:ARENA_PREP_OPPONENT_SPECIALIZATIONS()
end

function EventListener:Reset()
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
    self.friendlyUnits = {}
    self.activeAuras = {}
    Gladdy.bombExpireTime = {}
end

function Gladdy:SpotEnemy(unit, auraScan, report)
    local button = self.buttons[unit]
    if not unit or not button then
        return
    end
    if UnitExists(unit) then
        button.raceLoc = UnitRace(unit)
        button.race = select(2, UnitRace(unit))
        button.classLoc = select(1, UnitClass(unit))
        button.class = select(2, UnitClass(unit))
        button.name = UnitName(unit)
        Gladdy.guids[UnitGUID(unit)] = unit
    end
    if button.class and button.race and report then
        Gladdy:SendMessage("ENEMY_SPOTTED", unit)
    end
    if auraScan and not button.spec then
        EventListener:ScanAuras(unit)
    end
end

function EventListener:CooldownCheck(eventType, srcUnit, spellName, spellID)
    if not Gladdy.buttons[srcUnit] or not spellName or not spellID then
        return
    end
    -- Resolve spellID to canonical spellID (handles multiple spell ranks)
    local canonicalSpellID = Cooldowns:GetCanonicalSpellID(spellID)
    local cooldown = Gladdy:GetCooldownList()[Gladdy.buttons[srcUnit].class][canonicalSpellID]

    -- Cooldown-list entries are either a plain number (seconds) or a table; only
    -- tables carry flags like .dispel. A nil entry must NOT bail out early either:
    -- racial cooldowns are keyed by RACE, reached via the class-or-race fallback below.
    if eventType == "SPELL_DISPEL" then
        if cooldown then
            Gladdy:SendMessage("DISPEL_USED", srcUnit, canonicalSpellID)
        end
        return
    end
    if type(cooldown) == "table" and cooldown.dispel then
        return
    end
    if Gladdy.db.cooldown and Cooldowns:GetCanonicalSpellID(spellID) then
        local unitClass
        -- Use canonical spellID for consistency
        local spellId = Cooldowns:GetCanonicalSpellID(spellID)
        if Gladdy.db.cooldownCooldowns[tostring(spellId)] then
            if (cooldown) then
                unitClass = Gladdy.buttons[srcUnit].class
            else
                unitClass = Gladdy.buttons[srcUnit].race
            end
            --TODO find a better solution
            if spellID ~= 16188 and spellID ~= 17116 and spellID ~= 16166 and spellID ~= 12043 and spellID ~= 5384 and spellID ~= 132158 or spellID == 14751 or spellID == 89485 then -- Nature's Swiftness CD starts when buff fades
                Gladdy:Debug("INFO", eventType, "- CooldownUsed", srcUnit, "spellID:", spellID, "canonical:", canonicalSpellID)
                Cooldowns:CooldownUsed(srcUnit, unitClass, spellId)
            end
        end
    end
end

-- 3.3.5a COMBAT_LOG_EVENT_UNFILTERED payload (client build 12340):
--   timestamp, subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName,
--   destFlags, [spell/aura fields...]
-- There is NO hideCaster (added 4.0.1) and NO source/destRaidFlags (added 4.2) on
-- stock 3.3.5a, and awesome_wotlk.dll does not change the combat-log signature.
-- The module dispatcher (EventListener.OnEvent) calls EventListener[event](self, ...)
-- i.e. it passes (self, ...payload) WITHOUT the event name - exactly like every other
-- handler in this file (e.g. ARENA_OPPONENT_UPDATE(unit, updateReason)). So this
-- handler must NOT have a leading throwaway arg. A spurious leading "_" plus a
-- "hideCaster" field shifted every field by one on stock 3.3.5a, which silently broke
-- ALL combat-log tracking (interrupts, diminishing returns, death detection, smoke
-- bomb, instant-cast/aura cooldowns) because sourceGUID/destGUID never matched.
-- For SPELL_AURA_* events the field named extraSpellId here is the auraType ("BUFF"/"DEBUFF").
function EventListener:COMBAT_LOG_EVENT_UNFILTERED(timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName, spellSchool, extraSpellId, extraSpellName, extraSpellSchool)
    local srcUnit = Gladdy.guids[sourceGUID] -- can be a PET
    local destUnit = Gladdy.guids[destGUID] -- can be a PET
    if (Gladdy.db.shadowsightTimerEnabled and (eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_AURA_REFRESH") and spellID == 34709) then
        Gladdy.modules["Shadowsight Timer"]:AURA_GAIN(nil, nil, 34709)
    end

    if Gladdy.exceptionNames[spellID] then
        spellName = Gladdy.exceptionNames[spellID]
    end
    -- smoke bomb
    if (eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_AURA_APPLIED") and spellID == 76577 then
        local now = GetTime()
        if (Gladdy.bombExpireTime[sourceGUID] and now >= Gladdy.bombExpireTime[sourceGUID]) or eventType == "SPELL_CAST_SUCCESS" then
            Gladdy.bombExpireTime[sourceGUID] = now + 6
        elseif not Gladdy.bombExpireTime[sourceGUID] then
            Gladdy.bombExpireTime[sourceGUID] = now + 6
        end
    end
    if destUnit then
        -- diminish tracker
        if Gladdy.buttons[destUnit] and Gladdy.db.drEnabled and extraSpellId == AURA_TYPE_DEBUFF then
            if (eventType == "SPELL_AURA_REMOVED") then
                Gladdy:SendMessage("CLOG_AURA_FADE", destUnit, spellID)
            end
            if (eventType == "SPELL_AURA_REFRESH") then
                Gladdy:SendMessage("CLOG_AURA_REFRESH", destUnit, spellID)
            end
            if (eventType == "SPELL_AURA_APPLIED") then
                Gladdy:SendMessage("CLOG_AURA_GAIN", destUnit, spellID)
            end
        end
        -- death detection
        if (eventType == "UNIT_DIED" or eventType == "PARTY_KILL" or eventType == "SPELL_INSTAKILL") then
            if not Gladdy:isFeignDeath(destUnit) then
                Gladdy:SendMessage("UNIT_DEATH", destUnit)
            end
        end
        -- spec detection
        if Gladdy.buttons[destUnit] and (not Gladdy.buttons[destUnit].class or not Gladdy.buttons[destUnit].race) then
            Gladdy:SpotEnemy(destUnit, true, true)
        end
        --interrupt detection
        if Gladdy.buttons[destUnit] then
            if eventType == "SPELL_INTERRUPT" then
                Gladdy:SendMessage("SPELL_INTERRUPT", destUnit,spellID,spellName,spellSchool,extraSpellId,extraSpellName,extraSpellSchool)
            elseif (eventType == "SPELL_CAST_SUCCESS" and Gladdy:GetInterruptsCanonical()[spellID]) then
                local spellNameChanneled, _, _, _, _, _, _, interruptable = UnitChannelInfo(destUnit)
                local spellIdChanneled = spellNameChanneled and Gladdy:GetSpellIdByName(spellNameChanneled)
                if interruptable == false and spellNameChanneled then
                    if Gladdy.buttons[destUnit].lastCastSpell and Gladdy.buttons[destUnit].lastCastSpell.spellName == spellNameChanneled then
                        extraSpellSchool = Gladdy.buttons[destUnit].lastCastSpell.spellSchool
                    end
                    Gladdy:SendMessage("SPELL_INTERRUPT", destUnit,spellID,spellName,spellSchool,spellIdChanneled,spellNameChanneled,extraSpellSchool)
                end
            end
        end
    end
    if srcUnit then
        srcUnit = string_gsub(srcUnit, "pet", "")
        if (not UnitExists(srcUnit)) then
            return
        end
        if not Gladdy.buttons[srcUnit].class or not Gladdy.buttons[srcUnit].race then
            Gladdy:SpotEnemy(srcUnit, true, true)
        end
        if not Gladdy.buttons[srcUnit].spec then
            -- 3.3.5a: specSpells/specBuffs are keyed by spell NAME, not spellID
            self:DetectSpec(srcUnit, (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]))
        end
        if (eventType == "SPELL_DISPEL") then
            EventListener:CooldownCheck(eventType, srcUnit, spellName, spellID)
        end
        if (eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_MISSED" or eventType == "SPELL_DODGED") then
            -- caching last cast spell
            if not Gladdy.buttons[srcUnit].lastCastSpell then
                Gladdy.buttons[srcUnit].lastCastSpell = {}
            end
            Gladdy.buttons[srcUnit].lastCastSpell.spellName = spellName
            Gladdy.buttons[srcUnit].lastCastSpell.spellSchool = spellSchool
            -- cooldown tracker
            EventListener:CooldownCheck(eventType, srcUnit, spellName, spellID)
        end
        if (eventType == "SPELL_AURA_APPLIED") then
            EventListener:CooldownCheck(eventType, srcUnit, spellName, spellID)
        end
        --TODO find a better solution
        if (eventType == "SPELL_AURA_REMOVED" and (spellID == 16188 or spellID == 17116 or spellID == 16166 or spellID == 12043 or spellID == 14751 or spellID == 89485 or spellID == 132158) and Gladdy.buttons[srcUnit].class) then
            local canonicalSpellID = Cooldowns:GetCanonicalSpellID(spellID)
            Gladdy:Debug("INFO", "SPELL_AURA_REMOVED - CooldownUsed", srcUnit, "spellID:", spellID, "canonical:", canonicalSpellID)
            Cooldowns:CooldownUsed(srcUnit, Gladdy.buttons[srcUnit].class, canonicalSpellID)
        end
        if (eventType == "SPELL_AURA_REMOVED" and Gladdy.db.cooldown and Cooldowns:GetCanonicalSpellID(spellID)) then
            local unit = Gladdy:GetArenaUnit(srcUnit, true)
            -- Use canonical spellID for consistency
            local spellId = Cooldowns:GetCanonicalSpellID(spellID)
            if unit then
                --Gladdy:Debug("INFO", "EL:CL:SPELL_AURA_REMOVED (srcUnit)", "Cooldowns:AURA_FADE", unit, spellId)
                Cooldowns:AURA_FADE(unit, spellId, spellName)
            end
        end
    end
end

function EventListener:ARENA_OPPONENT_UPDATE(unit, updateReason)
    --[[ updateReason: seen, unseen, destroyed, cleared ]]

    unit = Gladdy:GetArenaUnit(unit)
    local button = Gladdy.buttons[unit]
    local pet = Gladdy.modules["Pets"].frames[unit]
    Gladdy:Debug("INFO", "ARENA_OPPONENT_UPDATE", unit, updateReason)
    if button or pet then
        if updateReason == "seen" then
            -- ENEMY_SPOTTED
            if button then
                button.stealthed = false
                Gladdy:SendMessage("ENEMY_STEALTH", unit, false)
                if not button.class or not button.race then
                    Gladdy:SpotEnemy(unit, true, true)
                end
            end
            if pet then
                Gladdy:SendMessage("PET_SPOTTED", unit)
            end
        elseif updateReason == "unseen" then
            -- STEALTH
            if button then
                button.stealthed = true
                Gladdy:SendMessage("ENEMY_STEALTH", unit, true)
            end
            if pet then
                Gladdy:SendMessage("PET_STEALTH", unit)
            end
        elseif updateReason == "destroyed" then
            -- LEAVE
            if button then
                Gladdy:SendMessage("UNIT_DESTROYED", unit)
            end
            if pet then
                Gladdy:SendMessage("PET_DESTROYED", unit)
            end
        elseif updateReason == "cleared" then
            --Gladdy:Print("ARENA_OPPONENT_UPDATE", updateReason, unit)
        end
    end
end

function EventListener:ARENA_PREP_OPPONENT_SPECIALIZATIONS()
    -- Not available in 3.3.5a - spec detection relies on combat log
end

--[[
/run local f,sn,dt for i=1,2 do f=(i==1 and "HELPFUL"or"HARMFUL")for n=1,30 do sn,_,_,dt=UnitAura("player",n,f) if(not sn)then break end print(sn,dt,dt and dt:len())end end
--]]
function EventListener:UNIT_AURA(unit)
    local button = Gladdy.buttons[unit]
    if not button then
        local skip = true
        for i=1, Gladdy.curBracket do
            if not Gladdy.buttons["arena" .. i].class then
                skip = false
                break
            end
        end
        if not skip then
            if self.friendlyUnits[unit] then
                for n = 1, 30 do
                    -- 3.3.5a UnitAura returns rank as the 2nd value (removed in Legion):
                    -- name, rank, icon, count, debuffType, duration, expirationTime,
                    -- unitCaster, isStealable, shouldConsolidate, spellId. The modern
                    -- (rank-less) destructuring shifted every field by one and put
                    -- shouldConsolidate into spellID, killing the whole scan.
                    local spellName, _, texture, count, dispelType, duration, expirationTime, unitCaster, _, shouldConsolidate, spellID = UnitAura(unit, n, "HARMFUL")
                    if spellName and (Gladdy.cooldownBuffs[spellName] or Gladdy.cooldownBuffs[spellID]) and unitCaster then
                        local cooldownBuff = Gladdy.cooldownBuffs[spellID] or Gladdy.cooldownBuffs[spellName]
                        for arenaUnit,v in pairs(Gladdy.buttons) do
                            if (UnitIsUnit(arenaUnit, unitCaster)) then
                                if not v.class then
                                    Gladdy:SpotEnemy(arenaUnit, false, true)
                                end
                                if not v.class and Gladdy.expansion == "Wrath" then
                                    -- use the already-resolved entry: the name lookup is nil
                                    -- when the buff matched via its numeric spellID key
                                    Gladdy.buttons[arenaUnit].class = cooldownBuff.class
                                    Cooldowns:UpdateCooldowns(Gladdy.buttons[arenaUnit])
                                end
                                Cooldowns:CooldownUsed(arenaUnit, Gladdy.buttons[arenaUnit].class, cooldownBuff.spellId, cooldownBuff.cd(expirationTime - GetTime()))
                            end
                        end
                    else
                        break
                    end
                end
            end
        end
        return
    end
    EventListener:ScanAuras(unit)
end

function EventListener:ScanAuras(unit)
    local button = Gladdy.buttons[unit]
    if not button then
        return
    end

    if not button.auras then
        button.auras = {}
    end
    wipe(button.auras)
    if not button.lastAuras then
        button.lastAuras = {}
    end

    local unitPet = string_gsub(unit, "%d$", "pet%1")

    Gladdy:SendMessage("AURA_FADE", unit, AURA_TYPE_BUFF)
    Gladdy:SendMessage("AURA_FADE", unit, AURA_TYPE_DEBUFF)
    for i = 1, 2 do
        if not Gladdy.buttons[unit].class or not Gladdy.buttons[unit].race then
            Gladdy:SpotEnemy(unit, false, true)
        end
        local filter = (i == 1 and "HELPFUL" or "HARMFUL")
        local auraType = i == 1 and AURA_TYPE_BUFF or AURA_TYPE_DEBUFF
        for n = 1, 30 do
            -- 3.3.5a UnitAura signature includes rank as the 2nd value (see note above)
            local spellName, _, texture, count, dispelType, duration, expirationTime, unitCaster, _, shouldConsolidate, spellID = UnitAura(unit, n, filter)
            if ( not spellID ) then
                Gladdy:SendMessage("AURA_GAIN_LIMIT", unit, auraType, n - 1)
                break
            end

            if Gladdy.exceptionNames[spellID] then
                spellName = Gladdy.exceptionNames[spellID]
            end
            button.auras[spellID] = { auraType, spellID, spellName, texture, duration, expirationTime, count, dispelType }
            -- Diminishings feed: upstream drives the DR module from the retail UNIT_AURA
            -- updateInfo payload (added/updated/removed aura instances, 10.0+), which does
            -- not exist on 3.3.5a - so nothing ever sent UNIT_AURA_GAIN/REFRESH/FADE and
            -- DR tracking was dead. Reproduce updateInfo by diffing this scan vs lastAuras.
            do
                local lastAura = button.lastAuras[spellID]
                local isHarmful = auraType == AURA_TYPE_DEBUFF
                if not lastAura then
                    Gladdy:SendMessage("UNIT_AURA_GAIN", unit, spellID, expirationTime, isHarmful)
                elseif expirationTime and lastAura[6] and abs(expirationTime - lastAura[6]) > 0.2 then
                    Gladdy:SendMessage("UNIT_AURA_REFRESH", unit, spellID, expirationTime, isHarmful)
                end
            end
            -- 3.3.5a: specSpells/specBuffs are keyed by spell NAME (GetSpellInfo(id) at
            -- load), so index them with the name - a numeric spellID never matches.
            if not button.spec and (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]) and unitCaster then
                if unitCaster and (UnitIsUnit(unit, unitCaster) or UnitIsUnit(unitPet, unitCaster)) then
                    self:DetectSpec(unit, (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]))
                end
            end
            if (Gladdy.cooldownBuffs[spellName] or Gladdy.cooldownBuffs[spellID]) and unitCaster then -- Check for auras that hint used CDs (like Fear Ward)
                local cooldownBuff = Gladdy.cooldownBuffs[spellID] or Gladdy.cooldownBuffs[spellName]
                for arenaUnit,v in pairs(Gladdy.buttons) do
                    if (UnitIsUnit(arenaUnit, unitCaster)) then
                        Cooldowns:CooldownUsed(arenaUnit, v.class, cooldownBuff.spellId, cooldownBuff.cd(expirationTime - GetTime()))
                    end
                end
            end
            if Gladdy.cooldownBuffs.racials[spellName] then
                -- Racial:RACIAL_USED expects (unit, startTime, spellName); the old
                -- (unit, spellName, cd, spellName) form always failed its name check
                Gladdy:SendMessage("RACIAL_USED", unit, GetTime(), spellName)
            end
            local sourceGUID = unitCaster and UnitGUID(unitCaster)
            if spellID == 88611 and Gladdy.bombExpireTime[sourceGUID] then
                duration = 6
                expirationTime = Gladdy.bombExpireTime[sourceGUID]
            end
            Gladdy:SendMessage("AURA_GAIN", unit, auraType, spellID, spellName, texture, duration, expirationTime, count, dispelType, i, unitCaster)
        end
    end
    -- check lastAuras for Cooldown detection of spells that trigger cd if buff fades
    for spellID,v in pairs(button.lastAuras) do
        if not button.auras[spellID] then
            local spellName = v[3]
            -- Diminishings feed (see the diff note above): the aura is gone this scan
            Gladdy:SendMessage("UNIT_AURA_FADE", unit, spellID, v[1] == AURA_TYPE_DEBUFF)
            if Gladdy.db.cooldown and Cooldowns:GetCanonicalSpellID(spellID) then
                -- Use canonical spellID for consistency
                local spellId = Cooldowns:GetCanonicalSpellID(spellID)
                --Gladdy:Debug("INFO", "EL:UNIT_AURA Cooldowns:AURA_FADE", unit, spellId)
                Cooldowns:AURA_FADE(unit, spellId, spellName)
                if spellID == 5384 then -- Feign Death CD Detection needs this
                    Cooldowns:CooldownUsed(unit, Gladdy.buttons[unit].class, 5384)
                end
            end
        end
    end
    wipe(button.lastAuras)
    button.lastAuras = Gladdy:DeepCopy(button.auras)
end

function EventListener:UpdateAuras(unit)
    local button = Gladdy.buttons[unit]
    if not button or button.lastAuras then
        return
    end
    for i=1, #button.lastAuras do
        Gladdy.modules["Auras"]:AURA_GAIN(unit, unpack(button.lastAuras[i]))
    end
end

function EventListener:UNIT_SPELLCAST_START(unit)
    if Gladdy.buttons[unit] then
        local spellName = UnitCastingInfo(unit)
        -- 3.3.5a: specSpells/specBuffs are keyed by spell NAME - look up directly
        if spellName and (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]) and not Gladdy.buttons[unit].spec then
            self:DetectSpec(unit, (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]))
        end
    end
end

function EventListener:UNIT_SPELLCAST_CHANNEL_START(unit)
    if Gladdy.buttons[unit] then
        local spellName = UnitChannelInfo(unit)
        -- 3.3.5a: specSpells/specBuffs are keyed by spell NAME - look up directly
        if spellName and (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]) and not Gladdy.buttons[unit].spec then
            self:DetectSpec(unit, (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]))
        end
    end
end

-- 3.3.5a payload is (unit, spellName, rank, lineID) - the trailing spellID was only
-- added in 4.0.1, so on stock it is ALWAYS nil and everything keyed on it (trinket,
-- racial, cooldown tracking, spec detection) silently never fired. Resolve the id
-- from the spell name; a client that does pass a real spellID keeps using it.
function EventListener:UNIT_SPELLCAST_SUCCEEDED(unit, spellName, rank, lineID, spellID)
    unit = Gladdy:GetArenaUnit(unit, true)
    local button = Gladdy.buttons[unit]
    if button then
        if not button.class or not button.race then
            Gladdy:SpotEnemy(unit, false, true)
        end
        if not spellName then
            spellName = GetSpellInfo(spellID)
        end
        if not spellID and spellName then
            spellID = Gladdy:GetSpellIdByName(spellName)
        end
        local unitRace = button.race
        local unitClass = button.class

        if Gladdy.exceptionNames[spellID] then
            spellName = Gladdy.exceptionNames[spellID]
        end

        -- 3.3.5a: specSpells/specBuffs are keyed by spell NAME, not spellID
        if spellName and (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]) and not button.spec then
            self:DetectSpec(unit, (Gladdy.specSpells[spellName] or Gladdy.specBuffs[spellName]))
        end

        if spellID == 42292 or spellID == 59752 then
            Gladdy:Debug("INFO", "UNIT_SPELLCAST_SUCCEEDED - TRINKET_USED", unit, spellID)
            Gladdy:SendMessage("TRINKET_USED", unit)
        end

        if unitRace and Gladdy:Racials()[unitRace].spellName == spellName and Gladdy:Racials()[unitRace][spellID] then
            Gladdy:Debug("INFO", "UNIT_SPELLCAST_SUCCEEDED - RACIAL_USED", unit, spellID)
            Gladdy:SendMessage("RACIAL_USED", unit)
        end

        EventListener:CooldownCheck("UNIT_SPELLCAST_SUCCEEDED", unit, spellName, spellID)
    end
end

local specCheck = {
    ["PALADIN"] = function(spec) return Gladdy:contains(spec, {L["Holy"], L["Retribution"], L["Protection"]}) end,
    ["SHAMAN"] = function(spec) return Gladdy:contains(spec, {L["Restoration"], L["Enhancement"], L["Elemental"]}) end,
    ["ROGUE"] = function(spec) return Gladdy:contains(spec, {L["Subtlety"], L["Assassination"], L["Combat"]}) end,
    ["WARLOCK"] = function(spec) return Gladdy:contains(spec, {L["Demonology"], L["Destruction"], L["Affliction"]}) end,
    ["PRIEST"] = function(spec) return Gladdy:contains(spec, {L["Shadow"], L["Discipline"], L["Holy"]}) end,
    ["MAGE"] = function(spec) return Gladdy:contains(spec, {L["Frost"], L["Fire"], L["Arcane"]}) end,
    ["DRUID"] = function(spec) return Gladdy:contains(spec, {L["Restoration"], L["Feral"], L["Balance"], L["Guardian"]}) end,
    ["HUNTER"] = function(spec) return Gladdy:contains(spec, {L["Beast Mastery"], L["Marksmanship"], L["Survival"]}) end,
    ["WARRIOR"] = function(spec) return Gladdy:contains(spec, {L["Arms"], L["Protection"], L["Fury"]}) end,
    ["DEATHKNIGHT"] = function(spec) return Gladdy:contains(spec, {L["Unholy"], L["Blood"], L["Frost"]}) end,
}

function EventListener:DetectSpec(unit, spec)
    local button = Gladdy.buttons[unit]
    if (not button or not spec or button.spec or button.class and not specCheck[button.class](spec)) then
        return
    end
    if not button.spec and button.race then
        button.spec = spec
        Gladdy:SendMessage("UNIT_SPEC", unit, spec)
    end
end

function EventListener:Test(unit)
    local button = Gladdy.buttons[unit]
    if (button and Gladdy.testData[unit].testSpec) then
        button.spec = nil
        Gladdy:SpotEnemy(unit, false, true)
        self:DetectSpec(unit, button.testSpec)
    end
end
