-- Run all test suites. Paste this into Web IDE or send via MCP lua-run.
-- Each suite loads runner.lua from the same directory.
local base = "/Library/IOSAutoTool/tests/"
package.path = base .. "?.lua;" .. package.path

local suites = {
    "test-device",
    "test-screen",
    "test-touch",
    "test-keyboard",
    "test-app",
    "test-system",
}

local total_pass, total_fail = 0, 0

for _, name in ipairs(suites) do
    log("══════════════ " .. name .. " ══════════════")
    -- Reset counters between suites (runner globals)
    _G._pass, _G._fail, _G._skip = 0, 0, 0
    _G._results = {}

    local ok, err = pcall(require, name)
    if not ok then
        log("[ERROR] Failed to load " .. name .. ": " .. tostring(err))
        total_fail = total_fail + 1
    else
        total_pass = total_pass + (_G._pass or 0)
        total_fail = total_fail + (_G._fail or 0)
    end
end

log("")
log("══════════════════════════════════")
log(string.format("TOTAL: %d pass / %d fail", total_pass, total_fail))
if total_fail > 0 then
    log("RESULT: FAILED")
else
    log("RESULT: ALL PASS")
end
