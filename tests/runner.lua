-- Minimal test runner for IOSAutoTool integration tests
-- Usage: copy tests/ to /Library/IOSAutoTool/tests/ on device, then run via Web IDE or MCP lua-run

local _pass, _fail, _skip = 0, 0, 0
local _results = {}

local function _fmt(ok, name, msg)
    local status = ok == true and "PASS" or (ok == nil and "SKIP" or "FAIL")
    table.insert(_results, string.format("[%s] %s%s", status, name, msg and (" — " .. msg) or ""))
end

function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        _pass = _pass + 1
        _fmt(true, name)
    else
        _fail = _fail + 1
        _fmt(false, name, tostring(err))
    end
end

function skip(name, _fn)
    _skip = _skip + 1
    _fmt(nil, name, "skipped")
end

function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assert_eq", tostring(b), tostring(a)))
    end
end

function assert_not_nil(v, msg)
    if v == nil then error(msg or "expected non-nil value") end
end

function assert_true(v, msg)
    if not v then error(msg or "expected true") end
end

function assert_gt(a, b, msg)
    if not (a > b) then
        error(string.format("%s: expected %s > %s", msg or "assert_gt", tostring(a), tostring(b)))
    end
end

function run_suite(name, fn)
    log("=== " .. name .. " ===")
    fn()
end

function report()
    log("")
    for _, r in ipairs(_results) do log(r) end
    log(string.format("\nResult: %d pass / %d fail / %d skip", _pass, _fail, _skip))
    if _fail > 0 then
        log("FAILED")
    else
        log("ALL PASS")
    end
end
