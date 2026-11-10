--!iosautomate
-- Read-only screen probes, Home/tap smoke and project-owned profile fixtures.
local ffi=require('ffi')
ffi.cdef[[void *objc_getClass(const char *);void *sel_registerName(const char *);void objc_msgSend(void);]]
local passed=0
local function check(ok,name) assert(ok,name); passed=passed+1; print('LEGACY_DEVICE_PASS '..name) end
local t=monotonicMillis(); sleep(.15)
check(monotonicMillis()-t>=120,'seconds timing')
t=monotonicMillis(); mSleep(30); check(monotonicMillis()-t>=20,'millisecond alias')
local w,h=screenSize(); local pw,ph=screenGeometry()
check(w==pw*2 and h==ph*2,'pixel to point geometry on iPhone 6s')
local image=screenshot(); check(image and image:width()==w and image:height()==h,'pixel image dimensions')
keepScreen()
local color=getColor(100,100)
check(type(color)=='number' and color>=0 and color<=0xffffff,'packed RGB')
local r,g,b=image:getColor(100,100)
check(rgbToInt(r,g,b)==color,'image and screen pixel orientation agree')
check(getColor(-1,-1)==nil,'invalid color coordinate')
local results=findColor(color,1,{100,100,1,1})
check(#results==1 and results[1][1]==100 and results[1][2]==100,'findColor list shape and region')
local batch=getColors{{100,100},{-1,-1}}
check(batch[1]==color and batch[2]==0,'batch color failure shape')
results=findColors({{0,0,color},{0,0,color}},1,{100,100,1,1})
check(#results==1,'offset pattern match')
results=findColors({{0,0,color},{-10000,0,color}},1,{100,100,1,1})
check(#results==0,'offset bounds')
local path=os.tmpname(); os.remove(path); path=path..'.png'
local ok,err=pcall(function()
  local crop=image:crop(240,160,32,32); check(crop and crop:save(path),'save owned template image')
  local matches=findImage(path,1,.9,{232,152,64,64})
  check(#matches==1 and matches[1][1]>=240 and matches[1][1]<=280 and matches[1][3]>=.9,'pixel template matching')
  check(#findImage(path,1,.9,{w+10,h+10,32,32})==0,'image region outside screen')
end)
os.remove(path); if not ok then error(err,0) end
local fresh=screenshot()
check(fresh~=nil and getColor(100,100)==color,'fresh screenshot preserves frozen analysis image')
local observations,text=ocr()
check(type(observations)=='table' and type(text)=='string','OCR two return values')
check(#observations>0,'OCR observes screen content')
for _,observation in ipairs(observations) do
  local r=observation.rectangle
  check(r and r.topLeft.x>=0 and r.topLeft.y>=0 and r.bottomRight.x<=w+1 and r.bottomRight.y<=h+1,'OCR pixel rectangle')
end
releaseScreen()
check(require('base64').decode(require('base64').encode('a\0b'))=='a\0b','binary Base64')
local json=require('json'); local roundtrip=json.decode(json.encode({flag=true,n=2,text='xin chào'}))
check(roundtrip.flag==true and roundtrip.n==2 and roundtrip.text=='xin chào','JSON Unicode and booleans')
check(require('plist').load(require('plist').dump({flag=true})).flag==true,'plist roundtrip')
check(require('md5').sumhexa('abc')=='900150983cd24fb0d6963f7d28e17f72','MD5 module')
local lfs=require('lfs'); check(type(lfs.currentdir())=='string','filesystem module')
local names=spoof.listProfiles(); local a,b='USB-Legacy-Profile-A','USB-Legacy-Profile-B'
for _,name in ipairs(names) do assert(name~=a and name~=b,'fixture profile name already exists') end
check(spoof.saveProfile(a),'Lua save profile')
check(spoof.renameProfile(a,b),'Lua rename profile')
check(spoof.applyProfile(b),'Lua apply profile')
check(spoof.deleteProfile(b),'Lua delete profile')
check(#spoof.listProfiles()==#names,'Lua profile cleanup')
print('LEGACY_DEVICE_RESULT passed='..passed..' failed=0')
