# Changelog

All notable changes to this 3.3.5a backport are listed here. Newest on top.
Version numbers follow the `.toc` `## Version:` and only change on an explicit release.

## [2.72-Release] — 2026-07-08 (2)

### Fixed — periodic ~1s stutters in arena (GC pressure from hot-path garbage)
Three allocation fountains generated enough Lua garbage in arena for the client's
GC to hitch visibly every so often:

- **`ScanAuras` (`EventListener.lua`) ran `Gladdy:DeepCopy(button.auras)` on EVERY
  `UNIT_AURA` of every arena unit** — a recursive copy of up to ~60 aura tuples,
  doubling the per-scan allocations. Replaced with a double-buffer swap
  (`auras`/`lastAuras` trade places; the stale container is wiped at the next scan).
  Also added same-frame coalescing: multiple `UNIT_AURA` for one unit in one frame
  now scan once (`UnitAura` always reads current state, so nothing is lost);
  `JOINED_ARENA` clears the stamp so its forced rescan still runs.
- **TotemPlates nameplate scanner allocated 30+ tables per 0.15s tick**:
  `{ WorldFrame:GetChildren() }` + a fresh `currentPlates` set each tick, plus
  `{GetRegions()}`/`{GetChildren()}` inside `IsNameplate` for every WorldFrame
  child. Now uses two reused tables + a varargs collector (zero heap traffic),
  and `IsNameplate`/`GetNameplateNameText` use `GetNum*`/`select` instead of
  building tables.
- **`TotemPlates.OnUpdate` built the string `"totem" .. id` every frame per totem
  plate.** The options key is now precomputed once per totem data entry
  (`entry.optionKey`).

## [2.72-Release] — 2026-07-08

First real-arena test (Triumvirate). Two findings:

### Fixed — `CooldownCheck` crash on number-form cooldown entries
- `EventListener.lua:104`: `attempt to index local 'cooldown' (a number value)`.
  Cooldown-list entries are either a table (`{cd = 30, ...}`) or a plain number
  (`[2565] = 60` — Shield Block). `CooldownCheck` indexed `.dispel` without a
  type check, so EVERY number-form cooldown spell crashed the handler and its
  cooldown icon never started — for both the `UNIT_SPELLCAST_SUCCEEDED` and the
  CLEU path. In the import since day one; first reachable now that cast/CLEU
  tracking actually fires. Now `type(cooldown) == "table"` gates the flag read.
- The same function's `if not cooldown then return end` also made the
  class-or-race fallback below unreachable, so RACIAL cooldowns (keyed by race,
  e.g. Will of the Forsaken) never started their icons from casts. Early return
  removed; the dispel branch keeps its entry-present guard.

### Fixed — dead enemies kept showing stale health (no "DEAD", bars frozen)
- On clients with a NATIVE `RegisterUnitEvent` (awesome_wotlk-based, e.g.
  Triumvirate) the Compat block that registers the genuine 3.3.5a unit events
  was skipped entirely — but the modern names the modules register
  (`UNIT_HEALTH_FREQUENT`, `UNIT_POWER_UPDATE`, `UNIT_MAXPOWER`) never fire
  there either. Health/power bars only updated on spot/seen snapshots, and the
  0-hp death path never ran: a dead enemy sat at its last snapshot (seen live:
  54% on a corpse). The `RegisterUnitEvent` wrapper now installs on both client
  kinds: the modern event goes through the native API when present, the 3.3.5a
  legacy events (`UNIT_HEALTH`, `UNIT_MANA`/`UNIT_RAGE`/…) are always registered
  as aliases and translated back to the modern name in dispatch. Translation is
  per-frame (only for events that frame requested), so foreign addons calling
  the native `RegisterUnitEvent` keep their own event names.

## [2.72-Release] — 2026-07-04

### Fixed — widget-metatable shims
- **Every added widget method now installs with `rawset`.** On this client the
  FRAME-type method table carries a `__newindex` guard that silently swallows a
  plain `meta.Name = fn` for a method that doesn't exist yet, leaving it nil.
  `Compat.lua` added its post-3.3.5a shims (`SetSize`/`GetSize`,
  `SetResizeBounds`, `Cooldown:Clear`, `RegisterUnitEvent`, the strata/level/
  clip/ignore-alpha no-ops, `SetColorTexture`, `SetSpellByID`, …) by plain
  assignment, so on a stock 3.3.5a client — where these shims actually run (they
  no-op on the awesome_wotlk test client) — the adds were dropped and the methods
  stayed nil, a latent crash. They now use `rawset`; the native-wrapping shims
  (`CreateTexture`, `SetMask`, `SetHyperlink`, the fileID setters) keep plain
  assignment since overriding an EXISTING key never trips the guard.

## [2.72-Release] — 2026-07-02

Full-addon audit against the real 3.3.5a (12340) API. Same theme as the CLEU fix:
handlers written for the modern client signature silently read shifted/absent fields
on 3.3.5a. All fixes hold on both stock 3.3.5a and awesome_wotlk.dll clients.

### Fixed — aura scanning (root cause, feeds most modules)
- **`UnitAura` field misalignment** in `EventListener.lua` (`ScanAuras` + the friendly-unit
  `UNIT_AURA` path). On 3.3.5a `UnitAura` returns `rank` as the 2nd value (removed in
  Legion), so the modern destructuring shifted every field by one: `spellID` received
  `shouldConsolidate` (usually nil), which broke out of the scan loop at the first aura.
  Buffs/Debuffs rows, the Auras CC display, aura-based spec detection and cooldown-buff
  detection all read garbage / never ran. Both call sites now use the genuine
  `name, rank, icon, count, debuffType, duration, expirationTime, unitCaster,
  isStealable, shouldConsolidate, spellId` layout.

### Fixed — Diminishing Returns tracking was never wired up
- Diminishings listens for `UNIT_AURA_GAIN/REFRESH/FADE`, but nothing ever sent those
  messages: upstream produces them from the retail (10.0+) `UNIT_AURA` updateInfo
  payload, which does not exist on 3.3.5a — so the DR module was completely dead (the
  CLEU `CLOG_AURA_*` sends have no consumer and carry no expirationTime, upstream-like).
  `ScanAuras` now reproduces updateInfo by diffing the current scan against `lastAuras`
  and emits `UNIT_AURA_GAIN` (new aura), `UNIT_AURA_REFRESH` (expirationTime changed
  >0.2s) and `UNIT_AURA_FADE` (aura gone) with `(unit, spellID, expirationTime, isHarmful)`.
- `Diminishings:Test` passed no `isHarmful` to the REFRESH/FADE handlers, so multi-stack
  DR test icons never advanced past the first level.

### Fixed — interrupt display was dead (also dead upstream)
- `Constants_Wrath.lua` keys the interrupt table by spell NAME, but `Auras:SPELL_INTERRUPT`
  and the EventListener channel-interrupt path look up with the NUMERIC combat-log
  spellID via `GetInterruptsCanonical()`, whose rebuild guard (`#hash == 0`) also never
  latched. The canonical map is now built once and maps every rank id → the name key
  (Kick 1766/1767/1768/1769/38768, Pummel 6552/6554, Shield Bash 72/1671/1672/29704,
  Spell Lock 19244/19647, Feral Charge 16979/19675, Counterspell 2139, Wind Shear 57994,
  Mind Freeze 47528).

### Fixed — everything keyed on `UNIT_SPELLCAST_SUCCEEDED`'s spellID (stock)
- On 3.3.5a the payload is `(unit, spellName, rank, lineID)` — the trailing `spellID`
  only exists on 4.0.1+ clients. Trinket detection (42292/59752), racial detection,
  spellcast cooldown tracking and cast-based spec detection were all keyed on that nil
  id, i.e. dead on stock. The handler now resolves the id from the spell name via
  `Gladdy:GetSpellIdByName`, whose cache build was itself broken (it iterated the
  NAME-keyed specSpells/specBuffs looking for numeric keys → the cache was always
  empty). It now builds from the numeric-keyed sources: trinket ids, the per-class
  cooldown list (incl. new rank lists), interrupts and racials.
- **Spec detection indexed name-keyed tables with numeric ids.** `specSpells`/`specBuffs`
  are keyed by `GetSpellInfo(id)` name; every consumer now indexes with the spell NAME
  (which also makes the "Berserk Feral"/"Intercept Felguard" exceptionNames work as
  designed). `Gladdy.specBuffs` was additionally **never assigned** — the first lookup
  that fell through `specSpells` errored ("attempt to index field 'specBuffs'").

### Fixed — `Gladdy.cooldownBuffs` did not exist (crash once scanning worked)
- EventListener indexes `Gladdy.cooldownBuffs` (incl. `.racials`) unconditionally, but
  upstream only defines it in `Constants_BCC.lua` — on Wrath it was nil (masked so far
  by the UnitAura misalignment breaking out of the loop first). Added a WotLK version to
  `Constants_Wrath.lua`: Fear Ward, rogue tells (Sprint/Shadowstep/Vanish/Cloak of
  Shadows/Blind) and racial buffs (Berserking, Blood Fury, Stoneform, Will of the
  Forsaken, Gift of the Naaru) with WotLK cooldown/uptime math.
- The `RACIAL_USED` message from ScanAuras sent `(unit, spellName, cd, spellName)` while
  the receiver expects `(unit, startTime, spellName)` — its name check compared a name
  against a number and always dropped the message. Now sends `(unit, GetTime(), spellName)`.
- `CooldownUsed` guards a nil class (possible on the cooldown-buff path before
  `SpotEnemy` resolves) instead of indexing the cooldown list with nil.

### Fixed — cast bar end-of-cast detection + crash
- `Modules/Castbar.lua` compared `select(2, ...)` (the spell NAME on 3.3.5a) against the
  numeric `castID`; Blizzard's own 3.3.5 CastingBarFrame compares `select(4, ...)`
  (payload `unit, spellName, rank, lineID`). SUCCEEDED/STOP/FAILED/INTERRUPTED never
  matched, so enemy bars ran to full even for cancelled/failed casts. All three sites
  now use `select(4, ...)`.
- A copy-paste line assigned the INTERRUPTIBLE handler onto `UNIT_SPELLCAST_CHANNEL_UPDATE`
  (overwriting the real channel-update handler) and left the registered
  `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` with NO handler — a guaranteed nil-call error the
  moment it fired. The line now targets `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` as intended.

### Fixed — TotemPulse crashed on every combat-log event
- `Modules/TotemPulse.lua` extracted npc ids with `strsplit("-", guid)` — the
  dash-separated GUID format is Legion+; 3.3.5a GUIDs are hex strings, so
  `tonumber(nil, 10)` raised "bad argument" on EVERY CLEU event while the module was
  enabled. New `npcIdFromGuid`: prefers awesome_wotlk's native `GetCreatureIDFromGUID`,
  falls back to `tonumber(guid:sub(6, 12), 16)` (the extraction the TurboPlates backport
  uses on this client), still supports the dash format.

### Fixed — WotLK class/spell data completeness
- **Multi-rank cooldowns never matched max-rank casts.** The cooldown list keyed several
  abilities by one rank id only, so a level-80 cast (different id) was untracked: Kick,
  Pummel, Shield Bash, Intercept, Charge, Kidney Shot, Evasion, Vanish, Sprint, Frost
  Nova, Psychic Scream, Shadow Word: Death, Bash, Nature's Grasp, Starfall, Hammer of
  Justice, Hand of Protection, Howl of Terror, Death Coil, Spell Lock, Devour Magic,
  Shadowburn, Shadowfury, Freezing Trap, Wyvern Sting now carry full 3.3.5a
  `spellIDs` rank lists (resolved through the existing canonical mapping).
- **Racial variants:** Blood Elf Arcane Torrent energy/runic ids (25046/50613) and all
  Draenei Gift of the Naaru class variants (59542–59548) added, so the id-based racial
  check works for every class.
- Cloak of Shadows cooldown corrected 60s → 90s (raised in patch 3.1).
- **Spec icons render again**: the optional "Show Spec Icon" feature used retail numeric
  fileIDs which 3.3.5a cannot resolve (blank icons); all 30 class/spec icons are now
  derived from core 3.3.5a spells via `GetSpellInfo`.

### Fixed — smaller crashes/logic
- `Frame.lua`: the OnUpdate-based `ActivationAnimation` stand-in only implemented
  `Play`, but Options.lua/Frame.lua call `IsPlaying()`/`Stop()` first → nil-call error
  when toggling test-frame options. All three methods provided now.
- `Modules/RangeCheck.lua`: `IsItemInRange(16114, unit)` returns nil on 3.3.5a for a
  bare itemID (needs an owned item name/link), which read as "never in melee range";
  falls back to `CheckInteractDistance`. Also removed the `IsCurrentSpell` call —
  the function does not exist on 3.3.5a (both branches returned 1 anyway).
- `Modules/Announcements.lua`: `GetSchoolString` is not guaranteed on 3.3.5a — falls
  back to the school names in Gladdy's own spell-school colour table.
- `Modules/ArenaCountDown.lua`: the tens digit used float division (45/10 % 10 = 4.5 →
  invalid texture path), so two-digit countdown numbers were broken; now floored.
- `Modules/BuffsDebuffs.lua`: `Gladdy.enabledAuras` is nested by aura type, so the flat
  `[spellID]` lookup always missed and CC auras were duplicated into the buff/debuff
  rows regardless of the "Show CC" option.
- `Util.lua` `Gladdy:SetTextColor`: operator-precedence bug dropped the closing `|r`
  (colour bled into following text) and crashed on nil text.
- EventListener friendly-unit scan: used the raw name lookup instead of the resolved
  `cooldownBuff` entry → nil-index when a buff matched via its numeric id key.

## [2.72-Release] — 2026-06-30

### Fixed — combat log (root cause, biggest impact)
- **`COMBAT_LOG_EVENT_UNFILTERED` field misalignment** in `EventListener.lua` and
  `Modules/TotemPulse.lua`. The handlers had a spurious leading `_` parameter plus a
  `hideCaster` field (a 4.0.1+ field that does **not** exist on stock 3.3.5a). The module
  dispatcher (`EventListener.OnEvent`) passes `(self, ...payload)` **without** the event
  name — like every other handler in the file (e.g. `ARENA_OPPONENT_UPDATE(unit, reason)`) —
  so the leading `_` shifted every field by one and `hideCaster` shifted it again. Result:
  `eventType` held a GUID and `sourceGUID`/`destGUID` never matched, so **all** combat-log
  tracking was silently dead on stock 3.3.5a: interrupts, diminishing returns, death
  detection, smoke bomb, and instant-cast / aura-applied cooldowns. Corrected both
  signatures to the real 3.3.5a layout (`timestamp, subEvent, sourceGUID, sourceName,
  sourceFlags, destGUID, destName, destFlags, …`). awesome_wotlk.dll does not change the
  combat-log signature, so this is correct on both stock and the awesome_wotlk test client.

### Fixed — Death Knight
- **Blank Death Knight class icon.** `classIcons["DEATHKNIGHT"]` derived its texture from
  `GetSpellInfo(72360)`, but 72360 is a Wrath-Classic-era id that does not resolve on
  3.3.5a, so DKs showed no class icon. Now derived from Obliterate (49020) with a Death
  Grip (49576) fallback — both core 3.3.5a DK abilities. (No DK icon BLP is bundled.)

### Changed — strict WotLK class data
- Removed all post-WotLK **Monk** data from the loaded tables in `Constants_shared.lua`
  (`classIcons`, spec icons, spec colors, `classRangeSpells`). Death Knight remains fully
  supported. No Monk / Demon Hunter / Evoker data is loaded anywhere.

### Fixed — nil guards (arena leave / reset / options)
- `Modules/Cooldowns.lua` `ResetUnit`: guard a missing `spellCooldownFrame` (the cooldown
  frame may not exist while the module is disabled or before it is built), matching the
  contract every other module's `ResetUnit` already honors.
- `Modules/Castbar.lua` `ResetUnit`: guard a nil cast bar for the same reason.
- `Modules/Cooldowns.lua` `CreateTextureMarkup` fallback: return an empty markup for a nil
  icon instead of letting `string.format("%s", nil)` abort the whole options build (which
  left Gladdy unregistered with AceConfig, so the config window would not open).
- `Frame.lua` legacy→new-layout migration: only run when both `arena1` and `arena2`
  buttons exist, and only flip `newLayout` then, so an old profile defers the one-time
  migration instead of indexing a nil button (and half-finishing the migration).

### Fixed — stock 3.3.5a API gaps (masked by the awesome_wotlk test client)
Full audit for calls to functions that do not exist on stock 3.3.5a. All were working on
the awesome_wotlk test client (a superset) but would nil-crash on a plain 3.3.5a client.
Added guarded shims in `Compat.lua` mapping each onto the genuine 3.3.5a primitive (the
`if not` guard makes them inert where the method already exists):
- **`Region:SetSize` / `Region:GetSize`** (Cata 4.0) → `SetWidth`/`SetHeight`,
  `GetWidth`/`GetHeight`. Used by LibCustomGlow (Cooldowns glow), AceConfigDialog +
  AceGUI TabGroup/TreeGroup (the options window), the GladdySearchEditBox widget, and
  Healthbar's absorb overlay. Added to the Frame/Button/Cooldown/StatusBar/Texture/
  FontString method tables (each widget type has its own on 3.3.5a).
- **`Frame:SetResizeBounds`** (Dragonflight 10.0) → `SetMinResize`/`SetMaxResize`. Used by
  AceGUI Frame/TreeGroup/Window containers when the options window is built.
- **`Cooldown:Clear`** (Cata 4.0) → `SetCooldown(0, 0)`. Used by Auras/Racial/Trinket to
  wipe the cooldown spiral.
Audit also confirmed clean: no `CombatLogGetCurrentEventInfo`, no `Mixin`/`CreateFromMixins`,
no `SetShown`, no `table.unpack`/`table.pack`, no Lua 5.2 syntax; every `C_*` reference (in
the addon and bundled libs) is already guarded with an `if`/`or` fallback or commented out;
`C_Timer` is polyfilled in AceTimer.

### Notes
- Verified: every `.lua` parses under Lua 5.1; Death Knight cooldown/interrupt/aura/spec
  data in `Constants_Wrath.lua` uses correct 3.3.5a spell ids (Mind Freeze 47528,
  Strangulate 47476, Death Grip 49576, Anti-Magic Shell 48707, Icebound Fortitude 48792,
  Anti-Magic Zone 51052, Lichborne 49039, Death Pact 48743, Empower Rune Weapon 47568,
  Raise Dead 46584, Summon Gargoyle 49206, Dancing Rune Weapon 49028, Hungering Cold
  49203, Pet Gnaw 47481, Bone Shield 49222).
- Known limitation: spec icons (the optional "Show Spec Icon" toggle, off by default) use
  numeric fileIDs for every class, which 3.3.5a cannot resolve, so they render blank
  (no error). The default class icons use real texture paths and work.
