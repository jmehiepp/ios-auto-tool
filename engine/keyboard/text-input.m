#import "text-input.h"
#import "key-press.h"
#import <UIKit/UIKit.h>
#import <unistd.h>

// UIKeyboardHIDUsage values for A and V keys
#define HID_KEY_A 0x04
#define HID_KEY_V 0x19
#define CMD_MODIFIER 0x100  // UIKeyModifierCommand

static UIResponder *get_first_responder(void) {
    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].windows.firstObject;
    return [win performSelector:@selector(firstResponder)];
}

static void type_via_uitextinput(NSString *text) {
    UIResponder *responder = get_first_responder();
    if (![responder conformsToProtocol:@protocol(UITextInput)]) return;
    id<UITextInput> input = (id<UITextInput>)responder;
    UITextRange *range = input.selectedTextRange;
    if (!range) {
        // Select all existing text and replace
        UITextPosition *start = [input beginningOfDocument];
        UITextPosition *end   = [input endOfDocument];
        range = [input textRangeFromPosition:start toPosition:end];
    }
    [input replaceRange:range withText:text];
}

void c_type_text(NSString *text) {
    if (!text.length) return;

    // Save clipboard
    NSString *prev = [UIPasteboard generalPasteboard].string;

    // Set clipboard to target text
    [UIPasteboard generalPasteboard].string = text;
    usleep(30000);

    // Try clipboard paste via HID Cmd+V
    c_send_key(HID_KEY_V, CMD_MODIFIER);
    usleep(120000);

    // Verify by checking the first responder (fallback if HID paste didn't work)
    UIResponder *r = get_first_responder();
    if ([r conformsToProtocol:@protocol(UITextInput)]) {
        id<UITextInput> input = (id<UITextInput>)r;
        UITextPosition *start = [input beginningOfDocument];
        UITextPosition *end   = [input endOfDocument];
        NSString *current = [input textInRange:
                             [input textRangeFromPosition:start toPosition:end]];
        // If clipboard paste didn't land, use UITextInput direct inject
        if (![current hasSuffix:text] && ![current isEqualToString:text]) {
            type_via_uitextinput(text);
        }
    }

    // Restore clipboard
    if (prev) [UIPasteboard generalPasteboard].string = prev;
    else [UIPasteboard generalPasteboard].items = @[];
}

void c_keyboard_type(const char *type) {
    NSDictionary *map = @{
        @"default": @(UIKeyboardTypeDefault),
        @"number":  @(UIKeyboardTypeNumberPad),
        @"decimal": @(UIKeyboardTypeDecimalPad),
        @"email":   @(UIKeyboardTypeEmailAddress),
        @"url":     @(UIKeyboardTypeURL),
        @"phone":   @(UIKeyboardTypePhonePad),
        @"web":     @(UIKeyboardTypeWebSearch),
    };
    NSString *key = [NSString stringWithUTF8String:type ?: "default"];
    NSNumber *kbType = map[key] ?: @(UIKeyboardTypeDefault);

    UIResponder *r = get_first_responder();
    if ([r isKindOfClass:[UITextField class]]) {
        ((UITextField *)r).keyboardType = (UIKeyboardType)kbType.integerValue;
        [r reloadInputViews];
    } else if ([r isKindOfClass:[UITextView class]]) {
        ((UITextView *)r).keyboardType = (UIKeyboardType)kbType.integerValue;
        [r reloadInputViews];
    }
}

void c_set_keyboard_language(const char *lang) {
    // TIPreferencesController private API — text input preferences
    Class prefs_class = NSClassFromString(@"TIPreferencesController");
    if (!prefs_class) return;
    id prefs = [prefs_class performSelector:@selector(sharedPreferencesController)];
    NSArray *modes = [prefs performSelector:@selector(enabledInputModes)];
    NSString *target = [NSString stringWithUTF8String:lang];
    for (NSString *mode in modes) {
        if ([mode hasPrefix:target]) {
            [prefs performSelector:@selector(setLastUsedInputMode:) withObject:mode];
            break;
        }
    }
}

void c_set_clipboard(NSString *text) {
    [UIPasteboard generalPasteboard].string = text ?: @"";
}

NSString *c_get_clipboard(void) {
    return [UIPasteboard generalPasteboard].string ?: @"";
}

void c_clear_clipboard(void) {
    [UIPasteboard generalPasteboard].items = @[];
}
