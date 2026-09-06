# ActionHud

A compact action bar HUD for World of Warcraft Retail. It mirrors your primary action bars and combines cooldown feedback, resource bars, optional custom unit frames, equipped trinkets, and selected player buffs.

![WoW Version](https://img.shields.io/badge/WoW-12.1-blue)
![Interface](https://img.shields.io/badge/Interface-120100-green)
[![GitHub](https://img.shields.io/badge/GitHub-Falkicon%2FActionHud-181717?logo=github)](https://github.com/Falkicon/ActionHud)
[![Sponsor](https://img.shields.io/badge/Sponsor-pink?logo=githubsponsors)](https://github.com/sponsors/Falkicon)

ActionHud targets WoW Retail 12.1, as declared in [ActionHud.toc](ActionHud.toc). It uses guarded API wrappers and protected-value passthrough where supported. See [development status](STATUS.md) for validation coverage and remaining in-game checks.

### Complete Your UI for Midnight

Check out these complementary addons to round out your interface:

- **[Danders Frames](https://www.curseforge.com/wow/addons/danders-frames)** – Clean party & raid frames
- **[TweaksUI: Cooldowns](https://www.curseforge.com/wow/addons/cooldown-manager-tweaks)** – Cooldown and buff skinning
- **[ClassyMap](https://www.curseforge.com/wow/addons/classymap)** – Lightweight map replacement
- **[Weekly](https://www.curseforge.com/wow/addons/weekly-to-do-tracker)** – Activity tracker for Midnight and pre-expansion events

## Features

- **Action bar mirroring** — Follows the button count and row layout of Blizzard's **Action Bar 1** and **Action Bar 2** in Edit Mode, including stance/form page changes.
- **Action feedback** — Cooldown sweeps and countdowns, display counts, yellow proc glows, blue Assisted Combat highlights, and usability/range tinting.
- **Cooldown controls** — Under **Action Bars → Cooldowns**, choose whether to show the global cooldown sweep and when countdowns switch to tenths of a second. Decimals default to the final 3 seconds and also apply to trinkets; set the threshold to 0 for whole seconds.
- **Resource bars** — Player and target health/power, plus player class resources. Individual bars can be toggled and sized independently.
- **Custom unit frames** — Optional secure frames for Player, Target, Target of Target, and Focus. Configure dimensions, backgrounds, borders, text, and status icons; optionally hide the corresponding Blizzard frames.
- **Trinket bar** — Tracks equipped on-use trinkets and their cooldowns.
- **Player Buffs** — Optional WoW 12.1 native display for up to 12 selected helpful player auras. Configured slots keep their footprint when an aura is inactive, so icons do not shift; the feature is disabled by default.
- **Layout** — Reorder stack modules, adjust gaps, or position modules independently with draggable overlays.
- **Profiles** — Create, switch, copy, delete, and reset settings profiles through AceDB.
- **Addon Compartment** — Opens ActionHud settings from the compartment menu.

The HUD action icons are display-only; use your normal action bindings or Blizzard action buttons to cast abilities. Blue rotation highlights require Blizzard's **Assisted Highlight** option, accessible through the **Open Gameplay Enhancements** button in ActionHud's general settings.

**Dormant features:** Essential/Utility Cooldown Manager, TrackedBuffs, TrackedDefensives, and DefensiveTracker remain as research source. Their runtime and settings files are excluded from the active TOC and release package. See [STATUS.md](STATUS.md).

## Installation

1. Download the addon from [CurseForge](https://www.curseforge.com/wow/addons/actionhud), or use a repository checkout with its embedded libraries present.
2. Place the `ActionHud` folder in `World of Warcraft\_retail_\Interface\AddOns\`. `ActionHud.toc` should be directly inside that folder.
3. Restart WoW if it was running when the addon was first installed. Use `/reload` when updating an already detected installation.

Ace3 and the required support libraries are embedded. FenCore and !Mechanic are optional.

## Setup

1. Configure **Action Bar 1** and **Action Bar 2** in Blizzard's Edit Mode. Place the abilities you want to monitor on those bars.
2. Open `/ah` outside combat. In **Action Bars**, use **Top Bar Priority** to choose which mirrored bar appears first, then adjust icon dimensions and visibility.
3. In **Layout**, enable **Unlock Module Positions**. Drag the HUD stack or the overlays for independently positioned modules. Disable the toggle when finished.
4. Use the Layout arrows and **Gap After** controls to arrange stack modules. The **Action Bars**, **Resource Bars**, **Trinket Bar**, and **Player Buffs** settings control each module's stack inclusion; custom unit frames are positioned independently.

Layout and secure-frame changes requested during combat wait until combat ends.

## Settings

| Section | Controls |
| --- | --- |
| General | Prerequisites, access to Gameplay Enhancements, and help |
| Layout | Unlock positions, reorder the stack, and adjust gaps |
| Action Bars | Enablement, icon sizing, glows, display counts, priority, and alignment |
| Resource Bars | Health/power/class bar visibility, dimensions, prediction, and positioning |
| Unit Frames | Master and per-unit toggles, dimensions, text, status icons, and Blizzard-frame visibility |
| Trinket Bar | Equipped trinket display, sizing, stack inclusion, and positioning |
| Player Buffs | Selected helpful aura IDs, enablement, icon sizing, columns, spacing, stack inclusion, and positioning |
| Profiles | Create, switch, copy, delete, and reset profiles |

Custom unit frames support value text and optional whole-number health/power percentages. Enable percentages under **Unit Frames → [frame] → Typography & Text → Health Percent / Power Percent**. They default to off and use Blizzard's native percentage calculations for protected values. Each text element has its own position and style controls.

Class-resource rows show the player's secondary resource, such as combo points, Holy Power, shards, runes, Chi, Arcane Charges, or Essence. Availability follows class, specialization, and form. The HUD keeps empty segments visible at zero and uses the actual readable maximum; if that maximum is restricted, it displays a continuous bar. Destruction shards use native raw units for fractional progress. Essence includes readable partial progress and otherwise displays whole points. Rune bars show available count, without individual recharge animations. The custom player frame uses a continuous bar for its secondary resource.

Player Buffs is disabled by default. Under **Player Buffs → Aura Spell IDs**, enter up to 12 ordered, unique aura spell IDs separated by commas or whitespace. The **Warrior Example** fills in `184364`, Enraged Regeneration's aura ID; it does not enable Player Buffs or cast the ability. The display provides native icons, timers, and application stacks. Set **Icon Size**, **Columns**, and **Spacing** to define the fixed slot footprint. Inactive configured slots stay reserved and their icons remain invisible. The module is independently positioned at `(0, -100)` by default; enable **Include in HUD Stack** to place it in the vertical HUD stack, or use **Layout → Unlock Module Positions** to drag it while independent. Its buff timer uses a fixed 3-second threshold, separate from the Action Bars and Trinket Bar countdown threshold. Configuration changes requested during combat wait until combat ends.

## Slash Commands

All commands also accept `/actionhud` in place of `/ah`.

| Command | Behavior |
| --- | --- |
| `/ah` | Open settings outside combat |
| `/ah reset` | Reset the current profile to defaults |
| `/ah perf on` | Clear old samples and start optional performance recording |
| `/ah perf off` | Stop recording and retain results |
| `/ah perf` or `/ah perf report` | Report call counts and total, average, and peak times |
| `/ah perf reset` | Clear samples without changing recording state |

Profiling is off by default and works without Mechanic. See [Performance profiling](docs/performance.md) for how to compare runs and interpret overlapping timings.

## Development

From the addon root, with Python available:

```powershell
python -m pip install --requirement requirements-dev.txt
python Tests/run.py
```

The runner checks manifests, packaging, and localization; compiles first-party Lua with Lua 5.1; and runs Python validator tests plus Lua regression and full-TOC integration suites. CI also runs Luacheck 1.2.0. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, lint commands, and required in-game validation.

| Source | Responsibility |
| --- | --- |
| [ActionHud.toc](ActionHud.toc), [embeds.xml](embeds.xml), [.pkgmeta](.pkgmeta) | Load order, embedded dependencies, and release packaging |
| [ActionHud.lua](ActionHud.lua) | Initialization, profiles, root frame, settings access, and slash commands |
| [Core/Defaults.lua](Core/Defaults.lua) | Shared profile defaults |
| [Core/Performance.lua](Core/Performance.lua) | Optional aggregate timing counters |
| [Core/DraggableContainer.lua](Core/DraggableContainer.lua), [Core/UnitEventRouter.lua](Core/UnitEventRouter.lua) | Shared drag behavior and unit-scoped events |
| [Utils.lua](Utils.lua) | API wrappers, restricted-value guards, fonts, and library fallbacks |
| [LayoutManager.lua](LayoutManager.lua) | Queued layout, lifecycle reconciliation, measurements, and positioning |
| [ActionBars.lua](ActionBars.lua), [Resources.lua](Resources.lua), [Trinkets.lua](Trinkets.lua) | HUD modules |
| [PlayerBuffs.lua](PlayerBuffs.lua) | Optional fixed-footprint native player-aura display |
| [UnitFrames/](UnitFrames/) | Custom unit-frame identity, lifecycle, layout, and rendering |
| [Settings/](Settings/), [Locales/enUS.lua](Locales/enUS.lua) | AceConfig options, including Player Buffs, and UI strings |
| [Mechanic.lua](Mechanic.lua) | Optional Mechanic tools, logging settings, and performance integration |

Read [Runtime lifecycle and layout](docs/runtime-layout.md) before changing module lifecycle or geometry. The [quality review](docs/quality-review.md) records the recent fixes and their verification limits.

## Credits

A special thanks to the authors of:

- **Cooldown Manager Tweaks** – For logic references related to styling native cooldown frames
- **Addon Bars Enhanced** – For inspiration and implementation details on hijacking native frames

## Support

If you find ActionHud useful, consider [sponsoring on GitHub](https://github.com/sponsors/Falkicon) to support continued development and new addons. Every contribution helps!

## License

GPL-3.0 License – see [LICENSE](LICENSE) for details.
