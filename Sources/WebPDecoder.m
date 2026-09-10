#import "WebPDecoder.h"

#if __has_include(<webp/decode.h>)
#import <webp/decode.h>
#elif __has_include(<libwebp/decode.h>)
#import <libwebp/decode.h>
#elif __has_include(<libwebp/webp/decode.h>)
#import <libwebp/webp/decode.h>
#elif __has_include("webp/decode.h")
#import "webp/decode.h"
#elif __has_include("decode.h")
#import "decode.h"
#else
#error "FATAL: libwebp decode.h header not found! WebP decoding cannot function on iOS 12 without libwebp."
#endif

@implementation WebPDecoder

+ (BOOL)isWebPData:(NSData *)data {
    if (!data || data.length < 12) {
        return NO;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    return (bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
            bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P');
}

+ (CGSize)imageSizeWithWebPData:(NSData *)data {
    if (![self isWebPData:data]) {
        return CGSizeZero;
    }
    int width = 0, height = 0;
    if (WebPGetInfo((const uint8_t *)data.bytes, data.length, &width, &height)) {
        if (width > 0 && height > 0) {
            return CGSizeMake(width, height);
        }
    }
    return CGSizeZero;
}

+ (nullable UIImage *)decodeWebPData:(NSData *)data {
    return [self decodeWebPData:data targetSize:CGSizeZero];
}

+ (nullable UIImage *)decodeWebPData:(NSData *)data targetSize:(CGSize)targetSize {
    if (![self isWebPData:data]) {
        return nil;
    }

    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config)) {
        return nil;
    }

    if (WebPGetFeatures((const uint8_t *)data.bytes, data.length, &config.input) != VP8_STATUS_OK) {
        return nil;
    }

    int origWidth = config.input.width;
    int origHeight = config.input.height;
    if (origWidth <= 0 || origHeight <= 0) {
        return nil;
    }

    // Downscale during decode to conserve iPad Air 1GB RAM budget (< 180MB ceiling)
    if (targetSize.width > 0 && targetSize.height > 0) {
        CGFloat screenScale = [UIScreen mainScreen].scale;
        CGFloat maxTarget = MAX(targetSize.width, targetSize.height) * MAX(screenScale, 1.0);
        int maxOrig = MAX(origWidth, origHeight);
        if (maxTarget > 0 && maxTarget < maxOrig) {
            CGFloat ratio = maxTarget / (CGFloat)maxOrig;
            config.options.use_scaling = 1;
            config.options.scaled_width = MAX(1, (int)(origWidth * ratio));
            config.options.scaled_height = MAX(1, (int)(origHeight * ratio));
        }
    }

    config.output.colorspace = MODE_RGBA;
    if (WebPDecode((const uint8_t *)data.bytes, data.length, &config) != VP8_STATUS_OK) {
        WebPFreeDecBuffer(&config.output);
        return nil;
    }

    int outWidth = config.options.use_scaling ? config.options.scaled_width : origWidth;
    int outHeight = config.options.use_scaling ? config.options.scaled_height : origHeight;
    uint8_t *rgba = config.output.u.RGBA.rgba;
    size_t rgbaSize = config.output.u.RGBA.size;

    if (!rgba || rgbaSize == 0 || outWidth <= 0 || outHeight <= 0) {
        WebPFreeDecBuffer(&config.output);
        return nil;
    }

    NSData *copiedData = [NSData dataWithBytes:rgba length:rgbaSize];
    WebPFreeDecBuffer(&config.output);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)copiedData);
    if (!provider) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef imageRef = CGImageCreate(
        outWidth,
        outHeight,
        8,
        32,
        4 * outWidth,
        colorSpace,
        kCGBitmapByteOrderDefault | kCGImageAlphaLast,
        provider,
        NULL,
        NO,
        kCGRenderingIntentDefault
    );

    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    if (!imageRef) {
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    return image;
}

@end

