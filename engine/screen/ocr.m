#import "ocr.h"
#import <Vision/Vision.h>
#include <string.h>
#include <stdlib.h>

static char g_languages[256] = "vi-VN,en-US,zh-Hans";

void ocr_set_languages(const char *languages) {
    if (languages) strncpy(g_languages, languages, sizeof(g_languages) - 1);
}

static NSArray<NSString *> *parse_languages(const char *lang_str) {
    NSString *s = [NSString stringWithUTF8String:lang_str ?: g_languages];
    return [s componentsSeparatedByString:@","];
}

static NSArray<VNRecognizedTextObservation *> *run_vision(UIImage *image,
                                                          const char *languages)
{

    if (!image.CGImage) return nil;
    VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] init];
    // A launch daemon has no EAGL display context. Keep preprocessing and
    // inference on the CPU rather than entering Core Image's GL context path.
    req.usesCPUOnly = YES;
    req.recognitionLevel   = VNRequestTextRecognitionLevelAccurate;
    req.usesLanguageCorrection = YES;
    NSArray *supported = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:
        req.recognitionLevel revision:req.revision error:nil];
    NSMutableArray *selected = [NSMutableArray array];
    for (NSString *language in parse_languages(languages ?: g_languages))
        if ([supported containsObject:language]) [selected addObject:language];
    req.recognitionLanguages = selected.count ? selected : @[@"en-US"];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
        initWithCGImage:image.CGImage options:@{}];
    NSError *err = nil;
    if (![handler performRequests:@[req] error:&err]) return nil;
    return req.results ?: @[];
}

char *ocr_image(UIImage *image, const char *languages) {
    if (!image) return NULL;
    NSArray<VNRecognizedTextObservation *> *obs = run_vision(image, languages);
    if (!obs) return NULL;
    NSMutableString *sb = [NSMutableString string];
    for (VNRecognizedTextObservation *o in obs) {
        NSString *top = [o topCandidates:1].firstObject.string;
        if (top) { [sb appendString:top]; [sb appendString:@"\n"]; }
    }
    const char *utf8 = sb.UTF8String;
    return utf8 ? strdup(utf8) : NULL;
}

OcrObservation *ocr_image_detailed(UIImage *image, const char *languages,
                                   int *out_count)
{
    *out_count = 0;
    if (!image) return NULL;

    NSArray<VNRecognizedTextObservation *> *obs = run_vision(image, languages);
    int n = (int)obs.count;
    if (n == 0) return NULL;

    OcrObservation *arr = calloc((size_t)n, sizeof(OcrObservation));
    if (!arr) return NULL;

    CGSize sz = image.size;
    for (int i = 0; i < n; i++) {
        VNRecognizedTextObservation *o = obs[i];
        NSString *top = [o topCandidates:1].firstObject.string;
        arr[i].text       = top ? strdup(top.UTF8String) : strdup("");
        arr[i].confidence = [o topCandidates:1].firstObject.confidence;

        // Vision bbox is normalized, origin bottom-left — convert to UIKit coords
        CGRect bb = o.boundingBox;
        arr[i].x = (float)(bb.origin.x * sz.width);
        arr[i].y = (float)((1.0 - bb.origin.y - bb.size.height) * sz.height);
        arr[i].w = (float)(bb.size.width  * sz.width);
        arr[i].h = (float)(bb.size.height * sz.height);
    }
    *out_count = n;
    return arr;
}
