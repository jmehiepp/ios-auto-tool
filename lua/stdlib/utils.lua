-- Sleep in seconds (fractional supported)
function sleepSec(s)
    sleep(math.max(1, math.floor(s * 1000)))
end

-- Retry fn() until truthy or timeout_ms elapses; returns result or nil
function waitFor(fn, timeout_ms, interval_ms)
    timeout_ms  = timeout_ms  or 5000
    interval_ms = interval_ms or 200
    local elapsed = 0
    while elapsed < timeout_ms do
        local r = fn()
        if r then return r end
        sleep(interval_ms)
        elapsed = elapsed + interval_ms
    end
    return nil
end

-- Shallow-print a table to log()
function dump(t, _indent)
    _indent = _indent or ""
    if type(t) ~= "table" then log(_indent .. tostring(t)); return end
    for k, v in pairs(t) do
        if type(v) == "table" then
            log(_indent .. tostring(k) .. ":")
            dump(v, _indent .. "  ")
        else
            log(_indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- Safe require (returns nil instead of error if module missing)
function tryRequire(name)
    local ok, mod = pcall(require, name)
    return ok and mod or nil
end
