//
//  UIApplication+TealiumTracker.m
//
//  Created by Jason Koo on 10/16/13.
//  Copyright (c) 2013 Tealium. All rights reserved.
//

#import "UIApplication+TealiumTracker.h"

@interface LastEvent : NSObject

/// A weak event view to avoid lastEvent to retain dismissed views
@property (nonatomic, weak) UIView* lastEventView;
@property (nonatomic, strong) NSDate *lastEventTS;

-(instancetype)initWithView:(UIView *)view date: (NSDate *)date;

@end

@implementation LastEvent

- (instancetype)initWithView:(UIView *)view date:(NSDate *)date
{
    self = [super init];
    if (self) {
        self.lastEventView = view;
        self.lastEventTS = date;
    }
    return self;
}
@end

@implementation UIApplication (TealiumTracker)

void (*oSendEvent)(id, SEL, UIEvent *e);

+ (void)load {
    
    Method origMethod1 = class_getInstanceMethod(self, @selector(sendEvent:));
    oSendEvent = (void *)method_getImplementation(origMethod1);
    if(!class_addMethod(self, @selector(sendEvent:), (IMP)TealiumSendEvent, method_getTypeEncoding(origMethod1))) method_setImplementation(origMethod1, (IMP)TealiumSendEvent);

}

// duplicate suppression
static LastEvent * _lastEvent;
static int _maxScans = 6;

static void TealiumSendEvent(UIApplication *self, SEL _cmd, UIEvent *e) {
    
    // Extract target touch object
    NSSet *touches = e.allTouches;
    UITouch *touch = (UITouch*)[touches anyObject];
    id view = touch.view;
    
    // check for tracking viability - duplicate suppression
    BOOL isViable = YES;
    
    if (touch.phase == UITouchPhaseEnded && view){
        NSDate *now = [NSDate date];
        if ([now compare:_lastEvent.lastEventTS] == NSOrderedAscending && _lastEvent.lastEventView == view) {
            isViable = NO;
        }
        if (isViable &&
            [view respondsToSelector:@selector(isUserInteractionEnabled)]){
            isViable = [view isUserInteractionEnabled];
        }
        if (isViable){
            
            __weak UIView *weakTargetView = [self tealiumViewToAutoTrack:view scanCount:0];
            
            if (weakTargetView) {
                
                [[NSNotificationCenter defaultCenter] postNotificationName:@"com.tealium.autotracking.event" object:weakTargetView];

            }
        }
        _lastEvent = [[LastEvent alloc] initWithView:view date:[NSDate dateWithTimeInterval:0.1 sinceDate:now]];
        
    }
    
    // Forward event to original target object
    oSendEvent(self, _cmd, e);
}

- (UIView *) tealiumViewToAutoTrack:(UIView *)view scanCount:(int)scanCount {

    NSString *vClass = NSStringFromClass([view class]);

    // if private skip and move up the chain
    if (![vClass hasPrefix:@"_"]) {
        if ([view isKindOfClass:[UIControl class]]) return view;
        if ([[view gestureRecognizers] count]) return view;
    }
    
    UIView *parent = view.superview;
    
    if (parent && ![parent isKindOfClass:[UITableViewCell class]] && scanCount < _maxScans){
        scanCount++;
        return [self tealiumViewToAutoTrack:parent scanCount:scanCount];
    }
    return nil;
}

@end
