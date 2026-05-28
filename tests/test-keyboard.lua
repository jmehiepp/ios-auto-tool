require("runner")

run_suite("Keyboard", function()

    it("type_text does not throw", function()
        -- Open Notes first so there's a text field
        app.launch("com.apple.mobilenotes")
        sleep(1500)
        keyboard.type("hello test")
        sleep(300)
    end)

    it("press_key Home does not throw", function()
        keyboard.press("home")
        sleep(500)
    end)

    it("press_key volume_up does not throw", function()
        keyboard.press("volume_up")
        sleep(200)
    end)

    it("press_key volume_down does not throw", function()
        keyboard.press("volume_down")
        sleep(200)
    end)

    it("set_clipboard stores and retrieves text", function()
        local text = "iosautotool_test_" .. os.time()
        device.set_clipboard(text)
        sleep(100)
        local got = device.get_clipboard()
        assert_eq(got, text, "clipboard roundtrip")
    end)

end)

report()
