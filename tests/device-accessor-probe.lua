-- Manual device test: run only in this project's private fixture .app bundle.
-- Emits booleans for synthetic values, never original identifiers or names.
local ffi = require('ffi')
ffi.cdef[[
void *objc_getClass(const char *); void *sel_registerName(const char *);
void objc_msgSend(void); int _NSGetExecutablePath(char *, unsigned int *);
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
local buffer, size = ffi.new('char[4096]'), ffi.new('unsigned int[1]',4096)
assert(C._NSGetExecutablePath(buffer,size) == 0)
local prefix = assert(ffi.string(buffer):match('^(.-)/var/mobile/Library/IOSAutoTool/diagnostics/'))
local library = ffi.load(prefix..'/Library/MobileSubstrate/DynamicLibraries/iosautotool-spoof.dylib',true)
local device = call(cls('UIDevice'),'currentDevice')
local screen = call(cls('UIScreen'),'mainScreen')
local checks = {}
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
local expected = os.getenv('IOSAT_EXPECT_CONFIG') == '1'
local failed, total = 0, 0
for name, matches in pairs(checks) do
    total = total + 1
    if matches ~= expected then failed = failed + 1 end
    print('DEVICE_CHECK '..name..' matches_fixture='..tostring(matches)..' expected='..tostring(expected))
end
print('DEVICE_PROBE total='..total..' failed='..failed..' selected_fixture='..tostring(identifier=='com.iosautotool.deviceprobe'))
assert(failed == 0, 'Device accessor fixture mismatch')
