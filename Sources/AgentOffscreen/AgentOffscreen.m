// The same pre-order guard as Tests/TestOffscreen, enabled only for invisible app launches.
// Install before SwiftUI or AppKit can create the first window; didUpdate is an extra backstop.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "AgentOffscreen.h"
#include <stdlib.h>
#include <string.h>

void AgentOffscreenInstalled(void) {}

static void swap(Class type, SEL original, SEL replacement) {
  Method old = class_getInstanceMethod(type, original), new = class_getInstanceMethod(type, replacement);
  if (!old || !new) return;
  if (class_addMethod(type, original, method_getImplementation(new), method_getTypeEncoding(new)))
    class_replaceMethod(type, replacement, method_getImplementation(old), method_getTypeEncoding(old));
  else
    method_exchangeImplementations(old, new);
}

@implementation NSWindow (AgentOffscreen)
- (void)agentOffscreen_hide { [self agentOffscreen_setAlphaValue:0]; self.ignoresMouseEvents = YES; }
- (void)agentOffscreen_setAlphaValue:(CGFloat)value { [self agentOffscreen_setAlphaValue:0]; }
- (void)agentOffscreen_orderWindow:(NSWindowOrderingMode)mode relativeTo:(NSInteger)other {
  [self agentOffscreen_hide]; [self agentOffscreen_orderWindow:mode relativeTo:other];
}
- (void)agentOffscreen_orderFront:(id)sender { [self agentOffscreen_hide]; [self agentOffscreen_orderFront:sender]; }
- (void)agentOffscreen_orderFrontRegardless { [self agentOffscreen_hide]; [self agentOffscreen_orderFrontRegardless]; }
- (void)agentOffscreen_makeKeyAndOrderFront:(id)sender { [self agentOffscreen_hide]; [self agentOffscreen_makeKeyAndOrderFront:sender]; }
@end

@implementation NSApplication (AgentOffscreen)
- (void)agentOffscreen_activateIgnoringOtherApps:(BOOL)flag {}
- (void)agentOffscreen_activate {}
@end

__attribute__((constructor)) static void installAgentOffscreen(int argc, const char *argv[]) {
  BOOL invisible = getenv("XCTestConfigurationFilePath") != NULL || getenv("SCOREBUG_NATIVE_SNAPSHOTS") != NULL;
  for (int i = 1; i < argc; i++)
    if (strcmp(argv[i], "--agent-screen") == 0 || strcmp(argv[i], "--screen") == 0) invisible = YES;
  if (!invisible) return;
  Class window = NSWindow.class, app = NSApplication.class;
  swap(window, @selector(setAlphaValue:), @selector(agentOffscreen_setAlphaValue:));
  swap(window, @selector(orderWindow:relativeTo:), @selector(agentOffscreen_orderWindow:relativeTo:));
  swap(window, @selector(orderFront:), @selector(agentOffscreen_orderFront:));
  swap(window, @selector(orderFrontRegardless), @selector(agentOffscreen_orderFrontRegardless));
  swap(window, @selector(makeKeyAndOrderFront:), @selector(agentOffscreen_makeKeyAndOrderFront:));
  swap(app, @selector(activateIgnoringOtherApps:), @selector(agentOffscreen_activateIgnoringOtherApps:));
  swap(app, @selector(activate), @selector(agentOffscreen_activate));
}
