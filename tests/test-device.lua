require("runner")

run_suite("Device", function()

    it("device_info returns model string", function()
        local info = device.info()
        assert_not_nil(info, "device_info nil")
        assert_not_nil(info.model, "missing model")
        assert_true(#info.model > 0, "empty model")
    end)

    it("device_info returns ios version", function()
        local info = device.info()
        assert_not_nil(info.ios, "missing ios version")
        -- e.g. "17.2.1" — must have at least one dot
        assert_true(info.ios:find("%.") ~= nil, "ios version format unexpected: " .. tostring(info.ios))
    end)

    it("device_info returns screen dimensions > 0", function()
        local info = device.info()
        assert_gt(info.screen_w, 0, "screen_w")
        assert_gt(info.screen_h, 0, "screen_h")
    end)

    it("device_info returns ip address", function()
        local info = device.info()
        assert_not_nil(info.ip, "missing ip")
        -- basic IPv4 pattern check
        assert_true(info.ip:match("%d+%.%d+%.%d+%.%d+") ~= nil or info.ip == "unknown",
            "ip format unexpected: " .. tostring(info.ip))
    end)

    it("get_clipboard returns string", function()
        local v = device.get_clipboard()
        assert_true(type(v) == "string", "clipboard not a string")
    end)

    it("set_clipboard roundtrip", function()
        device.set_clipboard("ping_123")
        sleep(50)
        assert_eq(device.get_clipboard(), "ping_123", "clipboard roundtrip")
    end)

end)

report()
