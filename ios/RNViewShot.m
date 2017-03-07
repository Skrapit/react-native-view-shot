
#import "RNViewShot.h"
#import <AVFoundation/AVFoundation.h>
#import <React/RCTLog.h>
#import <React/UIView+React.h>
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>
#import <React/RCTUIManager.h>
#import <React/RCTBridge.h>
#import <React/RCTWebView.h>
#import <objc/runtime.h>

@implementation RNViewShot

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (dispatch_queue_t)methodQueue
{
  return self.bridge.uiManager.methodQueue;
}

- (NSDictionary *)constantsToExport
{
  return @{
           @"CacheDir" : [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject],
           @"DocumentDir": [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject],
           @"MainBundleDir" : [[NSBundle mainBundle] bundlePath],
           @"MovieDir": [NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES) firstObject],
           @"MusicDir": [NSSearchPathForDirectoriesInDomains(NSMusicDirectory, NSUserDomainMask, YES) firstObject],
           @"PictureDir": [NSSearchPathForDirectoriesInDomains(NSPicturesDirectory, NSUserDomainMask, YES) firstObject],
           };
}

// forked from RN implementation
// https://github.com/facebook/react-native/blob/f35b372883a76b5666b016131d59268b42f3c40d/React/Modules/RCTUIManager.m#L1367

RCT_EXPORT_METHOD(takeSnapshot:(nonnull NSNumber *)target
                  withOptions:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    
    // Get view
    UIView *view;
    view = viewRegistry[target];
    if (!view) {
      reject(RCTErrorUnspecified, [NSString stringWithFormat:@"No view found with reactTag: %@", target], nil);
      return;
    }
    
    // Get options
    CGSize size = [RCTConvert CGSize:options];
    NSString *format = [RCTConvert NSString:options[@"format"] ?: @"png"];
    NSString *result = [RCTConvert NSString:options[@"result"] ?: @"file"];
    BOOL isFullWebView = [RCTConvert BOOL:options[@"fullWebView"] ?: NO];
    BOOL isScrollContent = [RCTConvert BOOL:options[@"scrollContent"] ?: NO];
    
    // Capture image
    if (size.width < 0.1 || size.height < 0.1) {
      size = view.bounds.size;
    }
    
    BOOL success = NO;
    UIImage *image = nil;
    UIView *contentView = view.subviews[0];
    
    // Captured image handler
    void (^captureHandler)(UIImage *, RCTPromiseResolveBlock, RCTPromiseRejectBlock) = ^void(UIImage *image, RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject) {
      // Convert image to data (on a background thread)
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSData *data;
        if ([format isEqualToString:@"png"]) {
          data = UIImagePNGRepresentation(image);
        } else if ([format isEqualToString:@"jpeg"] || [format isEqualToString:@"jpg"]) {
          CGFloat quality = [RCTConvert CGFloat:options[@"quality"] ?: @1];
          data = UIImageJPEGRepresentation(image, quality);
        } else {
          reject(RCTErrorUnspecified, [NSString stringWithFormat:@"Unsupported image format: %@. Try one of: png | jpg | jpeg", format], nil);
          return;
        }
        
        NSError *error = nil;
        NSString *res = nil;
        if ([result isEqualToString:@"file"]) {
          // Save to a temp file
          NSString *path;
          if (options[@"path"]) {
            path = options[@"path"];
            NSString * folder = [path stringByDeletingLastPathComponent];
            NSFileManager * fm = [NSFileManager defaultManager];
            if(![fm fileExistsAtPath:folder]) {
              [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:NULL error:&error];
              [fm createFileAtPath:path contents:nil attributes:nil];
            }
          }
          else {
            path = RCTTempFilePath(format, &error);
          }
          if (path && !error) {
            if ([data writeToFile:path options:(NSDataWritingOptions)0 error:&error]) {
              res = path;
            }
          }
        }
        else if ([result isEqualToString:@"base64"]) {
          // Return as a base64 raw string
          res = [data base64EncodedStringWithOptions: NSDataBase64Encoding64CharacterLineLength];
        }
        else if ([result isEqualToString:@"data-uri"]) {
          // Return as a base64 data uri string
          NSString *base64 = [data base64EncodedStringWithOptions: NSDataBase64Encoding64CharacterLineLength];
          res = [NSString stringWithFormat:@"data:image/%@;base64,%@", format, base64];
        }
        else {
          reject(RCTErrorUnspecified, [NSString stringWithFormat:@"Unsupported result: %@. Try one of: file | base64 | data-uri", result], nil);
          return;
        }
        if (res && !error) {
          resolve(res);
          return;
        }
        
        // If we reached here, something went wrong
        if (error) reject(RCTErrorUnspecified, error.localizedDescription, error);
        else reject(RCTErrorUnspecified, @"viewshot unknown error", nil);
      });
    };

    // Start capture
    if (isFullWebView) {
      // Snapshot full content of webview
      if ([contentView isKindOfClass:[RCTView class]] && contentView.subviews.count > 0 && [contentView.subviews[0] isKindOfClass:[RCTWebView class]]) {
        RCTWebView *rctWebView = contentView.subviews[0];
        UIView *scrollView = ((UIWebView *)rctWebView.subviews[0]).scrollView;
        if (isScrollContent) {
          [self captureScrollContent:scrollView withHandler:^(UIImage *image) {
            captureHandler(image, resolve, reject);
          }];
        } else {
          [self captureContent:scrollView withHandler:^(UIImage *image) {
            captureHandler(image, resolve, reject);
          }];
        }
      }
    } else {
      UIGraphicsBeginImageContextWithOptions(size, NO, 0);
      success = [view drawViewHierarchyInRect:(CGRect){CGPointZero, size} afterScreenUpdates:NO];
      image = UIGraphicsGetImageFromCurrentImageContext();
      UIGraphicsEndImageContext();
      
      
      if (!success || !image) {
        reject(RCTErrorUnspecified, @"Failed to capture view snapshot", nil);
        return;
      }
      captureHandler(image, resolve, reject);
    }
  }];
}

- (void)captureContent:(UIScrollView *)target withHandler:(void (^)(UIImage *capturedImage))completionHandler {
  
  //Put a fake Cover of View
  UIView *snapshotView = [target snapshotViewAfterScreenUpdates: NO];
  snapshotView.frame = CGRectMake(target.frame.origin.x, target.frame.origin.y, snapshotView.frame.size.width, snapshotView.frame.size.height);
  [target.superview addSubview:snapshotView];
  
  //Backup all properties of scrollview if needed
  CGRect bakFrame = target.frame;
  CGPoint bakOffset = target.contentOffset;
  UIView *bakSuperView = target.superview;
  NSInteger bakIndex = [target.superview.subviews indexOfObject:target];
  
  // Scroll To Bottom show all cached view
  if (target.frame.size.height < target.contentSize.height) {
    target.contentOffset = CGPointMake(0, target.contentSize.height - target.frame.size.height);
  }
  
  [self renderImageView:target withHandler:^(UIImage *capturedImage) {
    [target removeFromSuperview];
    target.frame = bakFrame;
    target.contentOffset = bakOffset;
    [bakSuperView insertSubview:target atIndex:bakIndex];
    
    [snapshotView removeFromSuperview];
    
    completionHandler(capturedImage);
  }];
}

- (void)renderImageView:(UIScrollView *)target withHandler:(void (^)(UIImage *capturedImage))completionHandler {
  // Rebuild scrollView superView and their hold relationship
  UIView *tempRenderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, target.contentSize.width, target.contentSize.height)];
  [target removeFromSuperview];
  [tempRenderView addSubview:target];
  
  target.contentOffset = CGPointZero;
  target.frame = tempRenderView.bounds;
  
  // Swizzling setFrame
  Method method = class_getInstanceMethod([target class], @selector(setFrame:));
  Method swizzledMethod = class_getInstanceMethod([target class], @selector(swSetFrame:));
  method_exchangeImplementations(method, swizzledMethod);
  
  // Sometimes ScrollView will Capture nothing without defer;
//  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    CGRect bounds = target.bounds;
    UIGraphicsBeginImageContextWithOptions(bounds.size, NO, [UIScreen mainScreen].scale);
    [target.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *capturedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    method_exchangeImplementations(swizzledMethod, method);
    completionHandler(capturedImage);
//  });
}

// Simulate People Action, all the `fixed` element will be repeate
// SwContentCapture will capture all content without simulate people action, more perfect.
- (void)captureScrollContent:(UIScrollView *)target withHandler:(void (^)(UIImage *capturedImage))completionHandler {
  
  //Put a fake Cover of View
  UIView *snapshotView = [target snapshotViewAfterScreenUpdates: NO];
  snapshotView.frame = CGRectMake(target.frame.origin.x, target.frame.origin.y, snapshotView.frame.size.width, snapshotView.frame.size.height);
  [target.superview addSubview:snapshotView];
  
  // Backup
  CGPoint bakOffset = target.contentOffset;
  
  // Divide
  float page = floorf(target.contentSize.height / target.bounds.size.height);
  
  UIGraphicsBeginImageContextWithOptions(target.contentSize, false, [UIScreen mainScreen].scale);
  
  [self contentScrollPageDraw:target index:0 maxIndex:(NSInteger)page drawHandler:^{
    UIImage * capturedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    // Recover
    [target setContentOffset:bakOffset animated:NO];
    [snapshotView removeFromSuperview];
    completionHandler(capturedImage);
  }];
}

- (void)contentScrollPageDraw:(UIScrollView *)target index:(NSInteger)index maxIndex:(NSInteger)maxIndex drawHandler:(void(^)())handler{
  [target setContentOffset:CGPointMake(0, index * target.frame.size.height) animated:NO];
  
  CGRect splitFrame = CGRectMake(0, index * target.frame.size.height, target.bounds.size.width, target.bounds.size.height);
  
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [target drawViewHierarchyInRect:splitFrame afterScreenUpdates:YES];
    if (index < maxIndex) {
      [self contentScrollPageDraw:target index:index + 1 maxIndex:maxIndex drawHandler:handler];
    } else {
      handler();
    }
  });
}


- (void)swSetFrame:(CGRect)frame {
  // Do nothing, use for swizzling
}

@end
