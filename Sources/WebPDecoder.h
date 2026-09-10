#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebPDecoder : NSObject

+ (BOOL)isWebPData:(NSData *)data;
+ (CGSize)imageSizeWithWebPData:(NSData *)data;
+ (nullable UIImage *)decodeWebPData:(NSData *)data;
+ (nullable UIImage *)decodeWebPData:(NSData *)data targetSize:(CGSize)targetSize;

@end

NS_ASSUME_NONNULL_END

