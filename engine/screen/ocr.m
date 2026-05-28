#import "ocr.h"
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
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
    __block NSArray *results = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    CIImage *ci = [CIImage imageWithCGImage:image.CGImage];
    VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) {
            results = r.results;
            dispatch_semaphore_signal(sem);
        }];
    req.recognitionLevel   = VNRequestTextRecognitionLevelAccurate;
    req.usesLanguageCorrection = YES;
    req.recognitionLanguages   = parse_languages(languages ?: g_languages);

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
        initWithCIImage:ci options:@{}];
    NSError *err = nil;
    [handler performRequests:@[req] error:&err];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return results;
}

char *ocr_image(UIImage *image, const char *languages) {
    if (!image) return NULL;
    NSArray<VNRecognizedTextObservation *> *obs = run_vision(image, languages);
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
