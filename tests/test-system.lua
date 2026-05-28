require("runner")

local TMP = "/tmp/iosautotool_test_" .. os.time()

run_suite("System", function()

    it("shell_exec returns exit code 0 for true", function()
        local code = system.exec("true")
        assert_eq(code, 0, "exit code")
    end)

    it("shell_exec returns non-zero for false", function()
        local code = system.exec("false")
        assert_gt(code, 0, "expected non-zero exit")
    end)

    it("shell_exec_output returns stdout", function()
        local out = system.exec_output("echo hello")
        assert_true(out:find("hello") ~= nil, "stdout missing 'hello'")
    end)

    it("write_file creates file", function()
        system.write_file(TMP, "test content")
        local code = system.exec("test -f " .. TMP)
        assert_eq(code, 0, "file not created")
    end)

    it("read_file returns written content", function()
        local content = system.read_file(TMP)
        assert_eq(content, "test content", "content mismatch")
    end)

    it("list_dir returns table for /tmp", function()
        local entries = system.list_dir("/tmp")
        assert_not_nil(entries)
        assert_true(type(entries) == "table")
        assert_gt(#entries, 0, "empty /tmp listing")
    end)

    it("http_get returns 200 for httpbin", function()
        local res = system.http_get("http://httpbin.org/status/200")
        assert_eq(res.status, 200, "http status")
    end)

    it("cleanup temp file", function()
        system.exec("rm -f " .. TMP)
        local code = system.exec("test -f " .. TMP)
        assert_gt(code, 0, "file still exists")
    end)

end)

report()
