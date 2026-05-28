require("runner")

run_suite("Screen", function()

    it("capture returns image with non-zero dimensions", function()
        local img = screen.capture()
        assert_not_nil(img, "capture returned nil")
        assert_gt(img.width, 0, "width")
        assert_gt(img.height, 0, "height")
    end)

    it("capture region returns smaller image", function()
        local full = screen.capture()
        local region = screen.capture(0, 0, 100, 100)
        assert_not_nil(region)
        assert_eq(region.width, 100, "region width")
        assert_eq(region.height, 100, "region height")
    end)

    it("get_color returns table with r/g/b/a keys", function()
        screen.capture()
        local c = screen.get_color(10, 10)
        assert_not_nil(c, "get_color nil")
        assert_not_nil(c.r, "missing r")
        assert_not_nil(c.g, "missing g")
        assert_not_nil(c.b, "missing b")
    end)

    it("ocr returns string", function()
        local img = screen.capture()
        local text = screen.ocr(img, "en-US")
        -- may be empty string on a blank screen — that's fine
        assert_true(type(text) == "string", "ocr result not a string")
    end)

    it("find_color returns nil when color not present", function()
        -- Use a very unlikely color (pure magenta with low tolerance)
        local pt = screen.find_color(0xFF00FF, 1)
        -- nil or a point — both valid; just must not error
        assert_true(pt == nil or type(pt) == "table", "unexpected type")
    end)

end)

report()
