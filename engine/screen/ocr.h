#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

typedef struct {
    char   *text;       // heap-allocated, caller frees
    float   confidence;
    float   x, y, w, h; // bounding box in image coordinates
} OcrObservation;

// Simple OCR: returns concatenated text (caller frees). languages e.g. "vi-VN,en-US,zh-Hans"
char *ocr_image(UIImage *image, const char *languages);

// Detailed OCR: returns array of observations (caller frees array and each .text)
OcrObservation *ocr_image_detailed(UIImage *image, const char *languages,
                                   int *out_count);

// Global OCR language setting (default: "vi-VN,en-US,zh-Hans")
void ocr_set_languages(const char *languages);
