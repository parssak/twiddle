#import "ViewAnimations.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>

void animateBlur(NSView *view, CGFloat from, CGFloat to, NSTimeInterval duration) {
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    blur.name = @"footerBlur";
    [blur setValue:@(to) forKey:kCIInputRadiusKey];
    [CATransaction begin];
    CATransaction.disableActions = YES;
    view.layer.filters = @[blur];
    [CATransaction commit];
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"filters.footerBlur.inputRadius"];
    animation.fromValue = @(from);
    animation.toValue = @(to);
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [view.layer addAnimation:animation forKey:@"footerBlur"];
}

void animateScaleIn(NSView *view, NSTimeInterval duration) {
    [CATransaction begin];
    CATransaction.disableActions = YES;
    view.layer.transform = CATransform3DIdentity;
    [CATransaction commit];
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    animation.fromValue = @.97;
    animation.toValue = @1;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [view.layer addAnimation:animation forKey:@"footerScale"];
}

void clearBlur(NSView *view) {
    [view.layer removeAnimationForKey:@"footerBlur"];
    [view.layer removeAnimationForKey:@"footerScale"];
    [CATransaction begin];
    CATransaction.disableActions = YES;
    view.layer.filters = nil;
    [CATransaction commit];
}
