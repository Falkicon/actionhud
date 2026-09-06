# Performance profiling

Profiling is opt-in and lasts for the current session. It works without Mechanic installed.

| Command | Behavior |
| --- | --- |
| `/ah perf on` | Clear old samples and start recording. |
| `/ah perf off` | Stop recording and retain results. |
| `/ah perf` or `/ah perf report` | Print calls, total milliseconds, average milliseconds, and peak milliseconds for each operation. |
| `/ah perf reset` | Clear samples without changing recording state. |

When Mechanic is installed, its ActionHud performance rows show average cost, with counts, totals, and peaks in each row's description. Profiling remains off until explicitly started; simply installing Mechanic does not enable it.

`Core/Performance.lua` stores aggregate counters instead of individual samples. When disabled, `ns.RecordPerformance` is nil, so instrumented paths skip both timing calls and counter allocation. Report snapshots are copies and cannot change internal counters.

Tracked operations include action-bar refreshes, action cooldown updates, resource events, trinket cooldown updates, unit-frame updates, and layout passes. These scopes can overlap: a layout pass includes module rendering. Do not sum all totals as if they were independent addon CPU time. The counters measure instrumented work, not all addon activity or allocations.

For a comparison, reset and record the same scenario before and after a change: ordinary combat, repeated target changes, or Edit Mode changes. Compare both call counts and average/peak cost. Save the printed report before starting another run. Test the same character, settings, and encounter conditions; these counters do not establish performance gains on their own.

Debug logging is separate. It requires the ActionHud Debug Mode setting in Mechanic and an active Mechanic sink. `ActionHud:Logf(category, pattern, ...)` checks that logging is enabled before formatting. Pass values to this helper instead of eagerly calling `string.format` at hot call sites.
