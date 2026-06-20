# Gladdy - WotLK 3.3.5a

### The most powerful arena addon for WoW 3.3.5a

[![Donate](https://raw.githubusercontent.com/XiconQoo/Gladdy/readme-media/Paypal-Donate.png)](https://www.paypal.me/dnbjunkee/10)

**Backport of [Gladdy Classic v2.72](https://github.com/XiconQoo/Gladdy-TBC) to WoW 3.3.5a (WoTLK private servers).**

Based on https://github.com/miraage/gladdy

## Origin

This is a backport of the Gladdy Classic addon, originally developed by **miraage**, maintained by **Schaka**, and later maintained and extensively developed by **XiconQoo** and **DnB_Junkee** (Knall).

The goal of Gladdy is to make a highly configurable arena addon. Everything can be arranged left or right independently, with black borders and extensive UI customization options.

## 3.3.5a Backport

This version has been backported from WoTLK Classic (3.4.x) to work on **WoW 3.3.5a private servers**. All modern/retail APIs have been replaced with 3.3.5a-compatible alternatives.

**Backported by:** [JedborgWoW](https://github.com/JedborgWoW)

### Key backport changes:
- Removed all `C_` namespace APIs (`C_Timer`, `C_NamePlate`, `C_AddOns`, `C_PvP`, `C_UnitAuras`, `C_Spell`, `C_CreatureInfo`, etc.)
- Rewrote `COMBAT_LOG_EVENT_UNFILTERED` handling for 3.3.5a event signature
- Replaced `BackdropTemplateMixin` with native 3.3.5a backdrop support
- Replaced `CreateColor()` with table literals
- Added compatibility polyfills for `C_Timer.After`, `FindAuraByName`, `GetSpellIdByName`
- TBC, Cataclysm, and MoP specific code removed (WoTLK only)
- Interface version set to 30300

## Modules

- Announcements
- ArenaCountDown
- Auras
- BuffsDebuffs
- CastBar
- ClassIcon
- Clicks
- CombatIndicator
- Cooldowns
- Diminishings
- ExportImport
- Highlight
- Pets
- Racial
- RangeCheck
- ShadowsightTimer
- Targets
- TotemPlates
- TotemPulse
- Trinket
- VersionCheck
- XiconProfiles

## Valid Slash Commands

- **/gladdy ui** - shows configuration panel
- **/gladdy test** - standard 3v3 test mode
- **/gladdy test1** to **/gladdy test5** - test mode with 1-5 frames active
- **/gladdy hide** - hides the frames
- **/gladdy reset** - resets current profile to default settings

## Screenshots

![sample1](https://raw.githubusercontent.com/XiconQoo/Gladdy/readme-media/sample1.jpg)
![sample2](https://raw.githubusercontent.com/XiconQoo/Gladdy/readme-media/sample2.jpg)
![sample3](https://raw.githubusercontent.com/XiconQoo/Gladdy/readme-media/sample3.png)

## Original Authors & Contributors

### Authors
- **miraage** - Original Gladdy creator
- **Schaka** - Previous maintainer
- **XiconQoo** - Maintainer & primary developer of Gladdy Classic
- **DnB_Junkee / Knall** - Co-maintainer & developer

### Contributors
- XyzKangUI
- ManneN1
- AlexFolland
- dfherr
- veiz
- Flamanis

### Special Thanks
- Macumba
- RMO
- Ur0b0r0s aka DrainTheLock
- Klimp
- Hydra
- Xyz

### 3.3.5a Backport
- **JedborgWoW** - Backport to WoW 3.3.5a

## License

This project is licensed under the **GNU General Public License v2.0** - see the [LICENSE](LICENSE) file for details.
