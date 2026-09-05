# Contributing to ActionHud

ActionHud is a compact HUD built around Blizzard's action bars and event APIs. Read [README.md](README.md) for supported features and [STATUS.md](STATUS.md) for current validation limits.

## Design Guidelines

- Reuse the embedded Ace3 and support libraries. Keep new dependencies focused and justified, and preserve optional FenCore/Mechanic fallbacks.
- React to events instead of adding `OnUpdate` loops. Use scoped unit events for the units a module displays.
- Route geometry changes through `LayoutManager:RequestLayout()`. Keep lifecycle reconciliation, measurement, positioning, and rendering in their existing phases.
- Keep action resolution, icon, cooldown, state, and proc updates focused. Preserve the UnitFrames identity/lifecycle/layout/rendering split and separate runtime code from `Settings/`.
- Treat protected values as opaque. Use the existing safe API wrappers and comparison helpers; verify every operand before arithmetic.
- Read defaults from `Core/Defaults.lua` through AceDB instead of repeating them in reset controls.

Agents should also read [AGENTS.md](AGENTS.md). See [Runtime lifecycle and layout](docs/runtime-layout.md) before changing enablement or geometry, and [Performance profiling](docs/performance.md) before optimizing hot paths.

## Workflow

1. Fork or check out the repository and create a branch for the change.
2. Make a focused change and add regression coverage for behavior changes where appropriate.
3. Run the checks below and perform the applicable in-game validation.
4. Open a pull request describing the problem, resulting behavior, verification, and any checks still pending.

Keep the active load graph in `ActionHud.toc` and `embeds.xml` consistent with `.pkgmeta`. New runtime Lua belongs in the load graph. First-party Lua retained only for reference must be excluded from the package. Dormant cooldown-viewer modules should remain excluded until their APIs have been validated against the target client build.

Update user-facing documentation when controls or commands change. Put pending changes under **Unreleased** in [CHANGELOG.md](CHANGELOG.md); keep published release entries as history.

## Local Checks

Use Python in a virtual environment with the pinned dependencies. For example, from the addon root in PowerShell:

```powershell
python -m venv _test_/venv
.\_test_\venv\Scripts\python.exe -m pip install --requirement requirements-dev.txt
.\_test_\venv\Scripts\python.exe Tests/run.py
```

On other platforms, use the equivalent virtual-environment Python executable. If the environment is already active, `python Tests/run.py` is sufficient.

The runner validates the TOC/XML dependency graph, package exclusions, and literal localization keys; compiles first-party Lua with Lua 5.1; and runs Python validator tests plus Lua regression and integration suites.

The integration host loads every active TOC/XML script, including the real embedded AceAddon, AceDB, AceEvent, AceConfig, and FenUI libraries. It models timers, scoped events, and protected geometry. It does not reproduce native WoW taint, secret values, or visual rendering.

Install Luacheck **1.2.0** (the LuaRocks release is `1.2.0-1`) and run with your environment's Python:

```text
python Tests/quality.py --lint
```

If Luacheck is outside PATH, pass `--luacheck /path/to/luacheck`. The command verifies the version and derives its file list from the active TOC/XML graph. The standalone `.luacheckrc` uses explicit WoW globals; do not suppress an undefined global simply to make a failing check pass.

[GitHub Actions](.github/workflows/quality.yml) runs the same repository, regression, and lint checks on pull requests and pushes to main.

## In-Game Validation

Test the paths affected by your change after installing the development build and reloading:

- **Action slots:** Druid forms, Rogue stealth, page changes, proc overrides, shared slots, empty cooldown/charge slots, range tint, and assist glows.
- **Layout and lifecycle:** enable/disable persistence, stack inclusion, profile switch/copy/reset, independent dragging, UI scale changes, and entering combat mid-drag.
- **Protected APIs and unit frames:** instanced combat, restricted health/prediction data, maximum-health changes, and deferred secure geometry after leaving combat.

Record the client build, character/class, relevant settings, and results in the pull request. Automated mocks do not replace combat validation. See the [quality review](docs/quality-review.md#required-in-game-validation) for the pending checks from the current implementation pass.

## Localization

All UI strings use literal `L["KEY"]` lookups and must be defined in [Locales/enUS.lua](Locales/enUS.lua). Use AceLocale-3.0 in settings and runtime UI code. The repository validator checks literal key coverage; keep dynamic text in localized format strings.

## Bug Reports

Include:

- ActionHud version and WoW client version/build.
- Expected behavior, actual behavior, and reproducible steps.
- Class/spec, combat or instance context, affected module, and relevant settings.
- The full Lua error and stack trace if available, plus screenshots for visual issues.
- For performance issues, the scenario and `/ah perf report` output from a recording started with `/ah perf on` and stopped with `/ah perf off`.

`/ah` and `/actionhud` open settings; they do not produce a debug dump. Optional debug logs require ActionHud's **Debug Mode** in Mechanic and an active Mechanic sink. See [Performance profiling](docs/performance.md).
