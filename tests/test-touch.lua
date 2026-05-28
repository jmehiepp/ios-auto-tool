require("runner")

run_suite("Touch", function()

    it("tap does not throw", function()
        touch.tap(100, 200)
        sleep(100)
    end)

    it("double_tap does not throw", function()
        touch.double_tap(100, 200)
        sleep(100)
    end)

    it("long_press does not throw", function()
        touch.long_press(100, 200, 500)
        sleep(600)
    end)

    it("swipe does not throw", function()
        touch.swipe(100, 500, 100, 200, 300)
        sleep(400)
    end)

    it("manual down/move/up sequence", function()
        touch.down(0, 150, 300)
        sleep(50)
        touch.move(0, 150, 250)
        sleep(50)
        touch.up(0, 150, 250)
        sleep(100)
    end)

end)

report()
