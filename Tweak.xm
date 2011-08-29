#include <objc/runtime.h>

#define RELEASE_SAFELY(__POINTER) { \
 if (__POINTER)                     \
 {                                  \
  [__POINTER release];              \
  __POINTER = nil;                  \
 }                                  \
}

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
-(oneway void)release;
- (void)kill;
-(id)bundleIdentifier;
- (BOOL)shouldIgnoreApplication;
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

- (void)dealloc
{
    RELEASE_SAFELY(_activeTask);
    [super dealloc];
}

- (id)init
{
    if (nil != (self = [super init]))
        _activeTask = nil;
    return self;
}

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
    
    /*
     * mail and phone are special since
     * kill
     */
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

#define IS_MAIL_APP(obj)  ([obj isEqualToString:@"com.apple.mobilemail"])
#define IS_PHONE_APP(obj) ([obj isEqualToString:@"com.apple.mobilephone"])

static unsigned mailAppExeCount = 0;
static unsigned phoneAppExeCount = 0;

%hook SBApplication
%new(@@:)
- (BOOL)shouldIgnoreApplication
{
    if (IS_MAIL_APP([self bundleIdentifier]))
    {
        if (mailAppExeCount > 1)
            goto NOT_IGNORE;
        mailAppExeCount++;
        goto IGNORE;
    }
    else if (IS_PHONE_APP([self bundleIdentifier]))
    {
        if (phoneAppExeCount > 1)
            goto NOT_IGNORE;
        phoneAppExeCount++;
        goto IGNORE;
    }
NOT_IGNORE:
    return NO;
IGNORE:
    return YES;
}

-(void)launch
{
    %orig;
    if ([self shouldIgnoreApplication])
        return;
    watchdog.activeTask = self;
}

-(void)activate
{
    %orig;
    if ([self shouldIgnoreApplication])
        return;    
    watchdog.activeTask = self;
}

-(void)deactivate
{
   if (IS_MAIL_APP([self bundleIdentifier]))
        mailAppExeCount = 0;
    else if (IS_PHONE_APP([self bundleIdentifier]))
        phoneAppExeCount = 0;
        
    %orig;
    watchdog.activeTask = nil;
}

-(void)kill
{
    if (IS_MAIL_APP([self bundleIdentifier]))
        mailAppExeCount = 0;
    else if (IS_PHONE_APP([self bundleIdentifier]))
        phoneAppExeCount = 0;
        
    %orig;
    watchdog.activeTask = nil;

}

%end
