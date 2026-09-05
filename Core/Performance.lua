-- Opt-in session profiling. No clock reads or metric allocations while disabled.
local _, ns = ...
local Performance = { enabled = false }
ns.Performance = Performance
local metrics = {}

function Performance:Record(name, duration)
	if not self.enabled or type(duration) ~= "number" or duration < 0 then return end
	local metric = metrics[name]
	if not metric then
		metric = { calls = 0, totalMs = 0, peakMs = 0, lastMs = 0 }
		metrics[name] = metric
	end
	metric.calls = metric.calls + 1
	metric.totalMs = metric.totalMs + duration
	metric.peakMs = math.max(metric.peakMs, duration)
	metric.lastMs = duration
end

function Performance:SetEnabled(enabled)
	self.enabled = enabled == true
	-- Existing event instrumentation checks this before reading the clock.
	if self.enabled then
		ns.RecordPerformance = function(name, startedAt)
			if type(startedAt) == "number" then
				Performance:Record(name, debugprofilestop() - startedAt)
			end
		end
	else
		ns.RecordPerformance = nil
	end
end

function Performance:Reset()
	metrics = {}
end

function Performance:GetMetrics()
	local result = {}
	for name, metric in pairs(metrics) do
		result[#result + 1] = {
			name = name, calls = metric.calls, totalMs = metric.totalMs,
			peakMs = metric.peakMs, lastMs = metric.lastMs,
			averageMs = metric.totalMs / metric.calls,
		}
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end
