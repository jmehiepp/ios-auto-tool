local factory = assert(loadfile('lua/stdlib/legacy.lua'))()
local calls, clock = {}, 0
local native = setmetatable({}, {__index=_G})
local function recorder(name) return function(...) calls[name]={...} end end
for _, name in ipairs{'tap','doubleTap','longPress','swipe','touchDown','touchMove','touchUp','touchReset',
  'appRun','appKill','pressHome','pressVolume','typeText','setClipboard','log','keepScreen','releaseScreen'} do native[name]=recorder(name) end
native.screenGeometry=function() return 375,667,750,1334 end
native.usleep=function(us) calls.us=us; clock=clock+us/1000 end
native.sleep=function(ms) calls.ms=ms; clock=clock+ms end
native.monotonicMillis=function() return clock end
native._legacyGetColor=function(x,y) return x==42 and y==43 and 0x123456 or nil end
native._legacyOCR=function() return {{text='hello',x=20,y=40,w=50,h=10}} end
native.getFrontApp=function() return 'com.apple.springboard' end
native.getRunningApps=function() return {{bundleId='test.bundle'}} end
native.shell=function() return 'result',4 end
native.httpRequest=function(options) calls.http=options; return 'ok',200 end
native.jsonEncode=function() return '{"test":true}' end
local env = factory(native)
assert(env._G==env and env.sleep~=native.sleep)
env.sleep(1); assert(calls.us==1000000)
env.sleep(); env.sleep(120); assert(calls.us==60000000)
env.sleep(120,1); assert(calls.us==100000000)
env.sleep(.1,.2); assert(calls.us>=100000 and calls.us<=200000)
assert(not pcall(env.sleep,-1) and not pcall(env.sleep,math.huge))
env.mSleep(123); assert(calls.ms==123)
env.tap(600,1000); assert(calls.tap[1]==300 and calls.tap[2]==500)
env.longPress(600,1000,.5); assert(calls.longPress[3]==500)
env.swipe(0,0,600,1000,5); assert(calls.swipe[3]==300 and calls.swipe[5]==800)
env.touchDown(99,100,200); assert(calls.touchDown[1]==50 and calls.touchDown[2]==100)
env.touchUp(500,600); assert(calls.touchUp[1]==50 and calls.touchUp[2]==100)
env.touchUp(99,300,400); assert(calls.touchUp[1]==150 and calls.touchUp[2]==200)
assert(env.screenWidth()==750 and env.screenHeight()==1334)
assert(env.getColor(42,43)==0x123456 and env.getColor(0,0)==nil)
local list,text=env.ocr(); assert(text=='hello' and list[1].rectangle.bottomRight.x==70 and list[1].rectangle.bottomRight.y==50)
assert(select('#',env.appRun('test'))==0 and select('#',env.shell('x'))==1)
assert(env.apps()[1]=='test.bundle' and env.getForegroundApp()=='')
assert(env.rgbToInt(env.intToRgb(0xabcdef))==0xabcdef)
env.httpGet('https://example.test',{test='value'});assert(calls.http.headers.test=='value')
env.httpPost('https://example.test',{test=true},{test='value'});assert(calls.http.body=='{"test":true}' and calls.http.headers.test=='value')
assert(env.waitForColor(42,43,0x123456,.2)==true)
assert(env.waitForColor(0,0,1,.2)==false)
env.customValue=true; assert(factory(native).customValue==nil and native.customValue==nil)
print('Legacy timing, coordinate, shape and environment contract tests passed')
