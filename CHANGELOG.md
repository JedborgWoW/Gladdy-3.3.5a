# Changelog

All notable changes to this 3.3.5a backport are listed here. Newest on top.
Version numbers follow the `.toc` `## Version:` and only change on an explicit release.

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
