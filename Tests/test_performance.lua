local ns = {}
local now, clockReads = 10, 0
debugprofilestop = function() clockReads = clockReads + 1; return now end
assert(loadfile("Core/Performance.lua"))("ActionHud", ns)
local performance = ns.Performance
assert(not performance.enabled and not ns.RecordPerformance)
local startedAt = ns.RecordPerformance and debugprofilestop()
assert(not startedAt and clockReads == 0, "disabled instrumentation must not read the clock")
performance:Record("ignored", 3)
assert(#performance:GetMetrics() == 0, "disabled profiling must not allocate counters")

performance:SetEnabled(true)
startedAt = debugprofilestop()
now = 12
ns.RecordPerformance("event", startedAt)
performance:Record("event", 4)
performance:Record("event", -1)
local metric = performance:GetMetrics()[1]
assert(metric.calls == 2 and metric.totalMs == 6 and metric.averageMs == 3 and metric.peakMs == 4)
assert(metric.lastMs == 4, "last sample must remain available")
metric.calls = 100
assert(performance:GetMetrics()[1].calls == 2, "snapshots must not expose mutable internal counters")
performance:SetEnabled(false)
assert(not ns.RecordPerformance)
performance:Record("event", 9)
assert(performance:GetMetrics()[1].calls == 2, "stopping must freeze but retain results")
performance:Reset()
assert(#performance:GetMetrics() == 0)
performance:SetEnabled(true)
performance:Record("fresh", 0)
assert(performance:GetMetrics()[1].calls == 1, "zero-duration samples must still count calls")
print("SUCCESS: opt-in profiling counters, immutable snapshots, and disabled fast path")
