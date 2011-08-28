#include <objc/runtime.h>

@interface SBUIController : NSObject
+ (id)sharedInstance;
-(BOOL)activateSwitcher;
-(void)dismissSwitcher;
-(void)dismissSwitcherAnimated:(BOOL)animated; // iOS 5 Beta >= 3
@end

@interface SBAppSwitcherController
+ (id)sharedInstance;
-(void)iconCloseBoxTapped:(id)tapped;
@end

@interface SBApplication
- (void)kill;
@end

@class SBApplicationIcon;
@class SBAppSwitcherBarView;

@interface TaskKillerWatchdog : NSObject
{ SBApplication *_activeTask; }
@property (retain) SBApplication *activeTask;
- (void)killCurrentTask;
- (BOOL)activeTaskPresent;
@end

@implementation TaskKillerWatchdog

@synthesize activeTask = _activeTask;

- (id)instanceVariableWithName:(NSString *)name
                    fromObject:(id)fromObject
{
    void *outValue = NULL;
    const char *nameAsConstChar = [name UTF8String];
    
    object_getInstanceVariable(fromObject,
                               nameAsConstChar,
                               &outValue);
    
    return (id)outValue;
}

- (SBUIController *)sharedUIController
{
    Class $SBUIController
    = objc_getClass("SBUIController");
    SBUIController *uiController
    = [$SBUIController sharedInstance];
    
    return uiController;
}

- (SBAppSwitcherController *)sharedAppSwitcherController
{
    Class $SBAppSwitcherController
    = objc_getClass("SBAppSwitcherController");
    SBAppSwitcherController *appSwitcherController
    = [$SBAppSwitcherController sharedInstance];
    
    return appSwitcherController;   
}

- (void)killTask
{
    [self.activeTask kill];
}

- (void)removeTaskFromSwitcher
{
    SBUIController *uiController
    = [self sharedUIController];
    
    [uiController activateSwitcher];
    
    SBAppSwitcherController *appSwitcherController
    = [self sharedAppSwitcherController];
    
    SBAppSwitcherBarView  *bottomBar
    = [self instanceVariableWithName:@"_bottomBar"
                          fromObject:appSwitcherController];
                          
    NSMutableArray *appIcons
    = [self instanceVariableWithName:@"_appIcons"
                          fromObject:bottomBar];
                          
    if (!appIcons || [appIcons count] <= 0)
        return;
        
    SBApplication *appIcon
    = [appIcons objectAtIndex:0];
    
    if (!appIcon)
        return;

    [appSwitcherController
         iconCloseBoxTapped:appIcon];
    
    SEL selector = @selector(dismissSwitcher);
    if ([uiController respondsToSelector:selector])
        [uiController dismissSwitcher];
    else
        [uiController dismissSwitcherAnimated:NO];

}

- (void)killCurrentTask
{
    if (!self.activeTask)
        return;
        
    [self killTask];
    [self performSelector:@selector(removeTaskFromSwitcher)
    withObject:nil afterDelay:.5f];
}

- (BOOL)activeTaskPresent
{
    return (self.activeTask != nil);
}

@end

TaskKillerWatchdog *watchdog;

static BOOL closeProcessCanceled = YES;
static BOOL shouldIgnoreScrollToIconList = NO;

%hook SpringBoard

%new(@@:)
- (void)timerCallback
{
    if (closeProcessCanceled)
        return;
    
    [watchdog killCurrentTask];
}

-(void)applicationDidFinishLaunching:(id)application
{
    watchdog
    = [[TaskKillerWatchdog alloc] init];
    %orig;
}

-(void)menuButtonDown:(GSEventRef)down
{
    %orig;
    if (![watchdog activeTaskPresent])
        return;
    closeProcessCanceled = NO;
    [NSTimer scheduledTimerWithTimeInterval:1.0
    target:self
    selector:@selector(timerCallback)
    userInfo:nil
    repeats:NO];
}

-(void)menuButtonUp:(GSEventRef)up
{
    %orig;
    if (closeProcessCanceled)
        return;
    shouldIgnoreScrollToIconList = YES;
    closeProcessCanceled = YES;
}

%end

%hook SBIconController

-(void)scrollToIconListAtIndex:(int)index animate:(BOOL)animate
{
    if (shouldIgnoreScrollToIconList)
    {
        shouldIgnoreScrollToIconList = NO;
        return;
    }
    %orig;
}

%end

%hook SBApplication

-(void)launch
{
    %orig;
    watchdog.activeTask = self;
}

-(void)activate
{
    %orig;
    watchdog.activeTask = self;
}

-(void)deactivate
{
    %orig;
    watchdog.activeTask = nil;
}

-(void)kill
{
    %orig;
    watchdog.activeTask = nil;

}

%end
