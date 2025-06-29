#import "macos_bridge.h"
#import <Cocoa/Cocoa.h>

// simple event queue implementation
#define MAX_EVENTS 256

typedef struct {
  PineEvent events[MAX_EVENTS];
  size_t head;
  size_t tail;
  size_t count;
} EventQueue;

static void event_queue_init(EventQueue *queue) {
  queue->head = 0;
  queue->tail = 0;
  queue->count = 0;
}

static bool event_queue_push(EventQueue *queue, const PineEvent *event) {
  if (queue->count >= MAX_EVENTS) {
    return false; // queue full
  }

  queue->events[queue->tail] = *event;
  queue->tail = (queue->tail + 1) % MAX_EVENTS;
  queue->count++;
  return true;
}

static bool event_queue_pop(EventQueue *queue, PineEvent *event) {
  if (queue->count == 0) {
    return false; // queue empty
  }

  *event = queue->events[queue->head];
  queue->head = (queue->head + 1) % MAX_EVENTS;
  queue->count--;
  return true;
}

// forward declaration for the window delegate
@interface WindowDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, assign) struct PineWindow *pineWindow;
@end

// custom NSWindow subclass to capture key events
@interface PineNSWindow : NSWindow
@property(nonatomic, assign) struct PineWindow *pineWindow;
@end

// internal window structure
struct PineWindow {
  PineNSWindow *ns_window;
  WindowDelegate *delegate;
  bool should_close;
  EventQueue event_queue;
};

// global application state
static NSApplication *g_app = nil;
static bool g_platform_initialized = false;

// convert macOS keycode to PineKeyCode
static PineKeyCode convert_keycode(unsigned short keyCode) {
  switch (keyCode) {
  case 0:
    return PINE_KEY_A;
  case 1:
    return PINE_KEY_S;
  case 2:
    return PINE_KEY_D;
  case 3:
    return PINE_KEY_F;
  case 4:
    return PINE_KEY_H;
  case 5:
    return PINE_KEY_G;
  case 6:
    return PINE_KEY_Z;
  case 7:
    return PINE_KEY_X;
  case 8:
    return PINE_KEY_C;
  case 9:
    return PINE_KEY_V;
  case 11:
    return PINE_KEY_B;
  case 12:
    return PINE_KEY_Q;
  case 13:
    return PINE_KEY_W;
  case 14:
    return PINE_KEY_E;
  case 15:
    return PINE_KEY_R;
  case 16:
    return PINE_KEY_Y;
  case 17:
    return PINE_KEY_T;
  case 18:
    return PINE_KEY_1;
  case 19:
    return PINE_KEY_2;
  case 20:
    return PINE_KEY_3;
  case 21:
    return PINE_KEY_4;
  case 22:
    return PINE_KEY_6;
  case 23:
    return PINE_KEY_5;
  case 25:
    return PINE_KEY_9;
  case 26:
    return PINE_KEY_7;
  case 28:
    return PINE_KEY_8;
  case 29:
    return PINE_KEY_0;
  case 31:
    return PINE_KEY_O;
  case 32:
    return PINE_KEY_U;
  case 34:
    return PINE_KEY_I;
  case 35:
    return PINE_KEY_P;
  case 37:
    return PINE_KEY_L;
  case 38:
    return PINE_KEY_J;
  case 40:
    return PINE_KEY_K;
  case 45:
    return PINE_KEY_N;
  case 46:
    return PINE_KEY_M;
  case 49:
    return PINE_KEY_SPACE;
  case 36:
    return PINE_KEY_ENTER;
  case 48:
    return PINE_KEY_TAB;
  case 51:
    return PINE_KEY_BACKSPACE;
  case 53:
    return PINE_KEY_ESCAPE;
  case 123:
    return PINE_KEY_LEFT;
  case 124:
    return PINE_KEY_RIGHT;
  case 125:
    return PINE_KEY_DOWN;
  case 126:
    return PINE_KEY_UP;
  default:
    return PINE_KEY_UNKNOWN;
  }
}

// PineNSWindow implementation
@implementation PineNSWindow

- (void)keyDown:(NSEvent *)event {
  if (self.pineWindow) {
    PineEvent pine_event = {0};
    pine_event.type = PINE_EVENT_KEY_DOWN;
    pine_event.data.key_event.key = convert_keycode([event keyCode]);
    pine_event.data.key_event.shift =
        ([event modifierFlags] & NSEventModifierFlagShift) != 0;
    pine_event.data.key_event.control =
        ([event modifierFlags] & NSEventModifierFlagControl) != 0;
    pine_event.data.key_event.alt =
        ([event modifierFlags] & NSEventModifierFlagOption) != 0;
    pine_event.data.key_event.command =
        ([event modifierFlags] & NSEventModifierFlagCommand) != 0;

    event_queue_push(&self.pineWindow->event_queue, &pine_event);
  }
}

- (void)keyUp:(NSEvent *)event {
  if (self.pineWindow) {
    PineEvent pine_event = {0};
    pine_event.type = PINE_EVENT_KEY_UP;
    pine_event.data.key_event.key = convert_keycode([event keyCode]);
    pine_event.data.key_event.shift =
        ([event modifierFlags] & NSEventModifierFlagShift) != 0;
    pine_event.data.key_event.control =
        ([event modifierFlags] & NSEventModifierFlagControl) != 0;
    pine_event.data.key_event.alt =
        ([event modifierFlags] & NSEventModifierFlagOption) != 0;
    pine_event.data.key_event.command =
        ([event modifierFlags] & NSEventModifierFlagCommand) != 0;

    event_queue_push(&self.pineWindow->event_queue, &pine_event);
  }
}

@end

// WindowDelegate implementation
@implementation WindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
  if (self.pineWindow) {
    self.pineWindow->should_close = true;

    // also push a close event
    PineEvent event = {0};
    event.type = PINE_EVENT_WINDOW_CLOSE;
    event_queue_push(&self.pineWindow->event_queue, &event);
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
    event_queue_init(&window->event_queue);

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

    // create the custom NSWindow
    window->ns_window =
        [[PineNSWindow alloc] initWithContentRect:windowRect
                                        styleMask:styleMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

    // set the back-reference
    window->ns_window.pineWindow = window;

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

    // make window accept key events
    [window->ns_window makeFirstResponder:window->ns_window];

    // show window if requested
    if (config->visible) {
      [window->ns_window makeKeyAndOrderFront:nil];
      [g_app activateIgnoringOtherApps:YES];
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
      window->ns_window.pineWindow = NULL;
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

void pine_window_request_close(PineWindow *window) {
  if (!window) {
    return;
  }

  window->should_close = true;

  // also push a close event
  PineEvent event = {0};
  event.type = PINE_EVENT_WINDOW_CLOSE;
  event_queue_push(&window->event_queue, &event);
}

bool pine_window_poll_event(PineWindow *window, PineEvent *event) {
  if (!window || !event) {
    return false;
  }

  return event_queue_pop(&window->event_queue, event);
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
