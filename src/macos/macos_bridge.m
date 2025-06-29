#import "macos_bridge.h"
#import <Cocoa/Cocoa.h>

// forward declaration for the window delegate
@interface WindowDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, assign) struct PineWindow *pineWindow;
@end

// internal window structure
struct PineWindow {
  NSWindow *ns_window;
  WindowDelegate *delegate;
  bool should_close;
};

// global application state
static NSApplication *g_app = nil;
static bool g_platform_initialized = false;

// WindowDelegate implementation
@implementation WindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
  if (self.pineWindow) {
    self.pineWindow->should_close = true;
  }
  return NO; // we'll handle closing manually
}
@end

bool pine_platform_init(void) {
  if (g_platform_initialized) {
    return true;
  }

  @autoreleasepool {
    g_app = [NSApplication sharedApplication];
    [g_app setActivationPolicy:NSApplicationActivationPolicyRegular];

    // create a minimal menu bar to make the app behave properly
    NSMenu *menubar = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:appMenuItem];
    [g_app setMainMenu:menubar];

    NSMenu *appMenu = [[NSMenu alloc] init];
    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSString *quitTitle = [@"Quit " stringByAppendingString:appName];
    NSMenuItem *quitMenuItem =
        [[NSMenuItem alloc] initWithTitle:quitTitle
                                   action:@selector(terminate:)
                            keyEquivalent:@"q"];
    [appMenu addItem:quitMenuItem];
    [appMenuItem setSubmenu:appMenu];

    // ensure the app is properly launched
    [g_app finishLaunching];

    g_platform_initialized = true;
    return true;
  }
}

void pine_platform_shutdown(void) {
  if (!g_platform_initialized) {
    return;
  }

  g_app = nil;
  g_platform_initialized = false;
}

PineWindow *pine_window_create(const PineWindowConfig *config) {
  if (!g_platform_initialized) {
    return NULL;
  }

  @autoreleasepool {
    PineWindow *window = malloc(sizeof(PineWindow));
    if (!window) {
      return NULL;
    }

    window->should_close = false;

    // create window rect
    NSRect windowRect =
        NSMakeRect(config->x, config->y, config->width, config->height);

    // determine window style
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable;
    if (config->resizable) {
      styleMask |= NSWindowStyleMaskResizable;
    }

    // create the NSWindow
    window->ns_window =
        [[NSWindow alloc] initWithContentRect:windowRect
                                    styleMask:styleMask
                                      backing:NSBackingStoreBuffered
                                        defer:NO];

    // IMPORTANT: Prevent automatic release when window is closed
    [window->ns_window setReleasedWhenClosed:NO];

    // set window properties
    NSString *title = config->title
                          ? [NSString stringWithUTF8String:config->title]
                          : @"Pine Window";
    [window->ns_window setTitle:title];
    [window->ns_window center];

    // create and set up the delegate
    window->delegate = [[WindowDelegate alloc] init];
    window->delegate.pineWindow = window;
    [window->ns_window setDelegate:window->delegate];

    // show window if requested
    if (config->visible) {
      [window->ns_window makeKeyAndOrderFront:nil];
    }

    return window;
  }
}

void pine_window_destroy(PineWindow *window) {
  if (!window) {
    return;
  }

  @autoreleasepool {
    if (window->delegate) {
      // clear the back-reference to prevent use-after-free
      window->delegate.pineWindow = NULL;
      [window->ns_window setDelegate:nil];
      // properly release the delegate
      [window->delegate release];
      window->delegate = nil;
    }

    if (window->ns_window) {
      [window->ns_window close];
      // since releasedWhenClosed is NO, we need to release manually
      [window->ns_window release];
      window->ns_window = nil;
    }

    free(window);
  }
}

void pine_window_show(PineWindow *window) {
  if (!window || !window->ns_window) {
    return;
  }

  @autoreleasepool {
    [window->ns_window makeKeyAndOrderFront:nil];
  }
}

void pine_window_hide(PineWindow *window) {
  if (!window || !window->ns_window) {
    return;
  }

  @autoreleasepool {
    [window->ns_window orderOut:nil];
  }
}

bool pine_window_should_close(PineWindow *window) {
  if (!window) {
    return false;
  }

  return window->should_close;
}

void pine_platform_poll_events(void) {
  if (!g_platform_initialized) {
    return;
  }

  @autoreleasepool {
    NSEvent *event;
    while ((event = [g_app nextEventMatchingMask:NSEventMaskAny
                                       untilDate:[NSDate distantPast]
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES])) {
      [g_app sendEvent:event];
    }
  }
}
