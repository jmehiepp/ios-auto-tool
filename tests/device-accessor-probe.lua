-- Manual device test: run only in this project's private fixture .app bundle.
-- Emits booleans for synthetic values, never original identifiers or names.
local ffi = require('ffi')
ffi.cdef[[
void *objc_getClass(const char *); void *sel_registerName(const char *);
void objc_msgSend(void);
unsigned int _dyld_image_count(void); const char *_dyld_get_image_name(unsigned int);
typedef struct {double x,y,w,h;} IATProbeRect;
typedef struct {double latitude,longitude;} IATProbeCoordinate;
typedef struct {char sysname[256],nodename[256],release[256],version[256],machine[256];} IATProbeUts;
int uname(IATProbeUts *);
]]
local C, sel = ffi.C, ffi.C.sel_registerName
local msg = ffi.cast('void *(*)(void *,void *)', C.objc_msgSend)
local textptr = ffi.cast('const char *(*)(void *,void *)', C.objc_msgSend)
local function call(object, name) return msg(object, sel(name)) end
local function cls(name) return C.objc_getClass(name) end
local function text(object)
    if object == nil then return '' end
    local p = textptr(object, sel('UTF8String'))
    return p ~= nil and ffi.string(p) or ''
end
local bundle = call(cls('NSBundle'),'mainBundle')
local identifier = text(call(bundle,'bundleIdentifier'))
assert(identifier == 'com.iosautotool.deviceprobe' or identifier == 'com.iosautotool.controlprobe',
       'Probe must run in an owned fixture bundle')
local device = call(cls('UIDevice'),'currentDevice')
local screen = call(cls('UIScreen'),'mainScreen')
local checks = {}
local loaded = false
for i=0,tonumber(C._dyld_image_count())-1 do
    local name = C._dyld_get_image_name(i)
    if name ~= nil and ffi.string(name):match('/iosautotool%-spoof%.dylib$') then loaded = true end
end
checks.tweak_image_loaded = loaded -- actual loader/filter; do not force-inject it
checks.device_name = text(call(device,'name')) == 'IOSAT Synthetic Fixture'
checks.device_family = text(call(device,'model')) == 'IOSAT Fixture Device'
checks.ios_version = text(call(device,'systemVersion')) == '99.0.1'
checks.idfv = text(call(call(device,'identifierForVendor'),'UUIDString')) == '12345678-1234-4321-8765-123456789ABC'
local system = ffi.new('IATProbeUts[1]')
checks.device_model = C.uname(system) == 0 and ffi.string(system[0].machine) == 'iPhone999,1'
checks.locale = text(call(call(cls('NSLocale'),'currentLocale'),'localeIdentifier')) == 'fr_FR'
checks.timezone = text(call(call(cls('NSTimeZone'),'localTimeZone'),'name')) == 'Pacific/Honolulu'
local rect = ffi.cast('IATProbeRect (*)(void *,void *)', C.objc_msgSend)(screen,sel('bounds'))
checks.screen_resolution = rect.w == 360 and rect.h == 640
local number = ffi.cast('double (*)(void *,void *)', C.objc_msgSend)
checks.screen_scale = number(screen,sel('scale')) == 1.5
local native = ffi.cast('IATProbeRect (*)(void *,void *)', C.objc_msgSend)(screen,sel('nativeBounds'))
checks.native_bounds = native.w == 540 and native.h == 960
local float = ffi.cast('float (*)(void *,void *)', C.objc_msgSend)
checks.battery_level = math.abs(float(device,sel('batteryLevel')) - 0.37) < 0.001
local integer = ffi.cast('long (*)(void *,void *)', C.objc_msgSend)
checks.battery_state = integer(device,sel('batteryState')) == 3
checks.proximity = integer(device,sel('proximityState')) == 1
local carrier = call(call(cls('CTCarrier'),'alloc'),'init')
checks.carrier_name = text(call(carrier,'carrierName')) == 'IOSAT Fixture Carrier'
checks.mcc = text(call(carrier,'mobileCountryCode')) == '999'
checks.mnc = text(call(carrier,'mobileNetworkCode')) == '99'
checks.iso_country = text(call(carrier,'isoCountryCode')) == 'zz'
local init_location = ffi.cast('void *(*)(void *,void *,double,double)', C.objc_msgSend)
local location = init_location(call(cls('CLLocation'),'alloc'),sel('initWithLatitude:longitude:'),1,2)
local coordinate = ffi.cast('IATProbeCoordinate (*)(void *,void *)',C.objc_msgSend)(location,sel('coordinate'))
checks.gps = math.abs(coordinate.latitude-50.123)<0.00001 and math.abs(coordinate.longitude-60.456)<0.00001
checks.gps_altitude = number(location,sel('altitude')) == 99
checks.gps_accuracy = number(location,sel('horizontalAccuracy')) == 5
local at = ffi.cast('void *(*)(void *,void *,unsigned long)',C.objc_msgSend)
local applications = call(call(cls('LSApplicationWorkspace'),'defaultWorkspace'),'allInstalledApplications')
assert(applications ~= nil, 'Application listing unavailable in this fixture')
local sileo_present = false
for i=0,tonumber(integer(applications,sel('count')))-1 do
    local application = at(applications,sel('objectAtIndex:'),i)
    if text(call(application,'applicationIdentifier')) == 'org.coolstar.SileoStore' then sileo_present = true end
end
checks.app_list = not sileo_present
local make_string = ffi.cast('void *(*)(void *,void *,const char *)',C.objc_msgSend)
local app_source = make_string(cls('NSString'),sel('stringWithUTF8String:'),'window.__iosatFixtureAppScript=1;')
local script_init = ffi.cast('void *(*)(void *,void *,void *,long,int)',C.objc_msgSend)
local app_script = script_init(call(cls('WKUserScript'),'alloc'),sel('initWithSource:injectionTime:forMainFrameOnly:'),app_source,0,0)
local configuration = call(call(cls('WKWebViewConfiguration'),'alloc'),'init')
local controller = call(call(cls('WKUserContentController'),'alloc'),'init')
local send_object = ffi.cast('void (*)(void *,void *,void *)',C.objc_msgSend)
send_object(controller,sel('addUserScript:'),app_script)
send_object(configuration,sel('setUserContentController:'),controller)
controller = call(configuration,'userContentController')
local scripts = call(controller,'userScripts')
local owned_source, document_start, preserved = '', false, false
for i=0,tonumber(integer(scripts,sel('count')))-1 do
    local script = at(scripts,sel('objectAtIndex:'),i)
    local source = text(call(script,'source'))
    if source:find('window.__iosatFixtureAppScript=1;',1,true) then preserved = true end
    if source:find('/* IOSAutoTool.Device.Web */',1,true) then
        owned_source = source
        document_start = integer(script,sel('injectionTime')) == 0 and integer(script,sel('isForMainFrameOnly')) == 0
    end
end
checks.webgl_vendor_script = owned_source:find('IOSAT Fixture Vendor',1,true) ~= nil
checks.webgl_renderer_script = owned_source:find('IOSAT Fixture Renderer',1,true) ~= nil
checks.canvas_script = owned_source:match('"canvas"%s*:%s*true') ~= nil
checks.web_script_document_start = document_start
checks.app_script_preserved = preserved
local expected = os.getenv('IOSAT_EXPECT_CONFIG') == '1'
local failed, total = 0, 0
for name, matches in pairs(checks) do
    total = total + 1
    local field_expected = name == 'app_script_preserved' or (expected and name ~= os.getenv('IOSAT_EXPECT_DISABLED_MODULE'))
    if matches ~= field_expected then failed = failed + 1 end
    print('DEVICE_CHECK '..name..' matches_fixture='..tostring(matches)..' expected='..tostring(field_expected))
end
print('DEVICE_PROBE total='..total..' failed='..failed..' selected_fixture='..tostring(identifier=='com.iosautotool.deviceprobe'))
assert(failed == 0, 'Device accessor fixture mismatch')
