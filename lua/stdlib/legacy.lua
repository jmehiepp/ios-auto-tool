-- Independently implemented adapters from the documented Lua ABI evidence.
-- Returns a fresh environment; never replace the native globals in the VM.
return function(native)
  local env = setmetatable({}, {__index = native})
  env._G = env
  env.IOSAUTOMATE_COMPAT = 'core-1'
  local function number(value, name)
    value = assert(tonumber(value), (name or 'value') .. ' must be a number')
    assert(value == value and math.abs(value) < math.huge, 'number must be finite')
    return value
  end
  local function seconds(value, cap)
    value = number(value, 'seconds')
    assert(value >= 0, 'seconds must be nonnegative')
    return math.min(value, cap or 86400)
  end
  local function point(x, y)
    local w, h, pw, ph = native.screenGeometry()
    assert(pw > 0 and ph > 0, 'screen geometry unavailable')
    return number(x, 'x') * w / pw, number(y, 'y') * h / ph
  end
  function env.sleep(first, second)
    if first == nil then return end
    first = seconds(first)
    local cap = 60
    if second ~= nil then
      second = number(second)
      if second > first then first = first + math.random() * (second - first)
      elseif math.floor(second) == 1 then cap = 100 end
    end
    native.usleep(math.min(first, cap) * 1000000)
  end
  env.delay = env.sleep
  env.mSleep, env.msleep, env.msleep_ms = native.sleep, native.sleep, native.sleep
  env.usleep = native.usleep
  function env.tap(x, y) native.tap(point(x, y)) end
  function env.doubleTap(x, y) native.doubleTap(point(x, y)) end
  function env.longPress(x, y, duration)
    local px, py = point(x, y)
    native.longPress(px, py, math.floor(seconds(duration or 1) * 1000))
  end
  function env.swipe(x1, y1, x2, y2, duration)
    local ax, ay = point(x1, y1)
    local bx, by = point(x2, y2)
    duration = seconds(duration or .3)
    if duration > 1 then duration = .8 end
    native.swipe(ax, ay, bx, by, math.floor(duration * 1000))
  end
  local lastX, lastY = 0, 0
  local function coordinates(...)
    local args = {...}
    if select('#', ...) > 2 then return args[2], args[3] end
    return args[1], args[2]
  end
  function env.touchDown(...)
    lastX, lastY = coordinates(...)
    native.touchDown(point(lastX, lastY))
  end
  function env.touchMove(...)
    lastX, lastY = coordinates(...)
    native.touchMove(point(lastX, lastY))
  end
  function env.touchUp(...)
    if select('#', ...) >= 3 then lastX, lastY = coordinates(...) end
    native.touchUp(point(lastX, lastY))
  end
  env.touchReset = native.touchReset
  env.handReset = native.touchReset
  function env.screenSize() local _, _, w, h = native.screenGeometry(); return w, h end
  env.getScreenResolution = env.screenSize
  function env.screenWidth() local w = env.screenSize(); return w end
  function env.screenHeight() local _, h = env.screenSize(); return h end
  env.getColor, env.getPixelColor = native._legacyGetColor, native._legacyGetColor
  env.findColor, env.findColors = native._legacyFindColors, native._legacyFindColors
  env.screenshot = native._legacyScreenshot
  function env.getColors(points)
    assert(type(points) == 'table', 'points must be an array')
    local result = {}
    native.keepScreen()
    local ok, err = pcall(function()
      for i, p in ipairs(points) do result[i] = native._legacyGetColor(p[1], p[2]) end
    end)
    native.releaseScreen()
    if not ok then error(err, 0) end
    return result
  end
  function env.ocr(region)
    local list, text = native._legacyOCR(region), {}
    for _, item in ipairs(list) do
      local x, y, w, h = item.x, item.y, item.w, item.h
      item.rectangle = {topLeft={x=x,y=y},topRight={x=x+w,y=y},
        bottomLeft={x=x,y=y+h},bottomRight={x=x+w,y=y+h}}
      text[#text+1] = item.text
    end
    return list, table.concat(text, '\n')
  end
  env.orc, env.recognizeText = env.ocr, env.ocr
  function env.appRun(id) native.appRun(id) end
  env.apprun, env.runApp, env.appActivate = env.appRun, env.appRun, env.appRun
  function env.appKill(id) native.appKill(id) end
  env.appkill, env.killApp, env.killapp = env.appKill, env.appKill, env.appKill
  function env.apps()
    local result = {}
    for i, app in ipairs(native.getRunningApps()) do result[i] = app.bundleId end
    return result
  end
  function env.getForegroundApp()
    local id = native.getFrontApp()
    return id == 'com.apple.springboard' and '' or (id or '')
  end
  env.getforegroundapp, env.frontMostAppId = env.getForegroundApp, env.getForegroundApp
  env.home, env.Home = native.pressHome, native.pressHome
  env.copyText, env.clipText = native.setClipboard, native.getClipboard
  env.inputText, env.typeKeys = native.typeText, native.typeText
  function env.log(value) native.log(tostring(value)) end
  function env.shell(command) local output = native.shell(command); return output end
  env.exec, env.execute = env.shell, env.shell
  function env.pressVolume(direction) native.pressVolume(direction == 'down' and 'down' or 'up') end
  function env.intToRgb(value)
    value = number(value)
    return math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256
  end
  function env.rgbToInt(r,g,b)
    return (math.floor(number(r)) % 256) * 65536 + (math.floor(number(g)) % 256) * 256 + math.floor(number(b)) % 256
  end
  function env.randomInt(low, high) return math.random(low, high) end
  function env.randomFloat(low, high) return number(low) + math.random() * (number(high)-number(low)) end
  function env.randomSleep(low, high) env.sleep(low, high) end
  local function headers(value)
    assert(value == nil or type(value) == 'table', 'headers must be a table')
    return value or {}
  end
  function env.httpGet(url, extra)
    local body, status = native.httpRequest{url=url,method='GET',headers=headers(extra)}
    return body, status
  end
  function env.httpPost(url, body, extra)
    local h = headers(extra)
    if type(body) == 'table' then
      body = native.jsonEncode(body)
      h = setmetatable({['Content-Type']='application/json'}, {__index=h})
      -- Native bridge enumerates concrete keys, so keep all supplied headers.
      for k,v in pairs(extra or {}) do h[k]=v end
    end
    return native.httpRequest{url=url,method='POST',body=body,headers=h}
  end
  function env.waitForColor(x,y,rgb,timeout)
    local deadline = native.monotonicMillis() + seconds(timeout or 5) * 1000
    repeat
      if native._legacyGetColor(x,y) == rgb then return true end
      if native.monotonicMillis() >= deadline then return false end
      native.sleep(100)
    until false
  end
  -- Other unresolved original APIs are intentionally not faked as successful.
  return env
end
