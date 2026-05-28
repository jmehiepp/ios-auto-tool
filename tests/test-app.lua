require("runner")

-- Settings app is always present on any jailbroken device
local TEST_APP = "com.apple.Preferences"

run_suite("App Control", function()

    it("launch Settings does not throw", function()
        app.launch(TEST_APP)
        sleep(1500)
    end)

    it("get_front_app returns bundle id string", function()
        local bid = app.get_front_app()
        assert_not_nil(bid, "get_front_app returned nil")
        assert_true(type(bid) == "string" and #bid > 0, "empty bundle id")
    end)

    it("front app is Settings after launch", function()
        app.launch(TEST_APP)
        sleep(1500)
        local bid = app.get_front_app()
        assert_eq(bid, TEST_APP, "front app mismatch")
    end)

    it("kill Settings does not throw", function()
        app.kill(TEST_APP)
        sleep(500)
    end)

    it("list_apps returns non-empty table", function()
        local apps = app.list()
        assert_not_nil(apps, "list returned nil")
        assert_true(type(apps) == "table", "list not a table")
        assert_gt(#apps, 0, "app list empty")
    end)

    it("get_name returns display name for Settings", function()
        local name = app.get_name(TEST_APP)
        assert_not_nil(name, "get_name nil")
        assert_true(#name > 0, "empty app name")
    end)

end)

report()
