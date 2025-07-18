#import "../log.h"
#import "../window-backend.h"
#import <Cocoa/Cocoa.h>

#define LOG_SCOPE "cocoa-backend"

// simple event queue implementation
#define DEFAULT_MAX_EVENTS 256
#define CRITICAL_EVENT_THRESHOLD 200 // warn when queue is ~80% full

typedef struct {
  PineEvent events[DEFAULT_MAX_EVENTS];
  size_t head;
  size_t tail;
  size_t count;

  // metrics for monitoring
  size_t total_events_processed;
  size_t events_dropped;
  size_t high_water_mark; // maximum queue usage seen
} EventQueue;

typedef enum {
  EVENT_PRIORITY_LOW = 0,
  EVENT_PRIORITY_NORMAL = 1,
  EVENT_PRIORITY_HIGH = 2,
} EventPriority;

// helper to determine event priority
static EventPriority get_event_priority(const PineEvent *event) {
  switch (event->type) {
  case PINE_EVENT_WINDOW_CLOSE:
    return EVENT_PRIORITY_HIGH; // never drop close events
  case PINE_EVENT_KEY_DOWN:
  case PINE_EVENT_KEY_UP:
    // check for important keys like escape
    if (event->data.key_event.key == PINE_KEY_ESCAPE) {
      return EVENT_PRIORITY_HIGH;
    }
    return EVENT_PRIORITY_NORMAL;
  default:
    return EVENT_PRIORITY_LOW;
  }
}

static void event_queue_init(EventQueue *queue) {
  queue->head = 0;
  queue->tail = 0;
  queue->count = 0;
  queue->total_events_processed = 0;
  queue->events_dropped = 0;
  queue->high_water_mark = 0;
}

static bool event_queue_push(EventQueue *queue, const PineEvent *event) {
  if (queue->count >= DEFAULT_MAX_EVENTS) {
    queue->events_dropped++;

    // for high priority events, try to make room by dropping low priority ones
    EventPriority new_priority = get_event_priority(event);
    if (new_priority == EVENT_PRIORITY_HIGH) {
      // scan queue for a low priority event to replace
      size_t scan_idx = queue->head;
      for (size_t i = 0; i < queue->count; i++) {
        EventPriority existing_priority =
            get_event_priority(&queue->events[scan_idx]);
        if (existing_priority == EVENT_PRIORITY_LOW) {
          // replace this event
          queue->events[scan_idx] = *event;
          pine_log(PINE_LOG_LEVEL_WARN, LOG_SCOPE,
                   "replaced low priority event with high priority event");
          return true;
        }
        scan_idx = (scan_idx + 1) % DEFAULT_MAX_EVENTS;
      }
    }

    // log warning about dropped events periodically
    if (queue->events_dropped % 100 == 1) { // log every 100 drops
      pine_log(PINE_LOG_LEVEL_WARN, LOG_SCOPE,
               "event queue overflow! dropped %zu events total",
               queue->events_dropped);
    }

    return false;
  }

  queue->events[queue->tail] = *event;
  queue->tail = (queue->tail + 1) % DEFAULT_MAX_EVENTS;
  queue->count++;
  queue->total_events_processed++;

  // update high water mark
  if (queue->count > queue->high_water_mark) {
    queue->high_water_mark = queue->count;

    // warn if getting close to limit
    if (queue->count >= CRITICAL_EVENT_THRESHOLD) {
      pine_log(PINE_LOG_LEVEL_WARN, LOG_SCOPE,
               "event queue is %zu%% full (%zu/%d events)",
               (queue->count * 100) / DEFAULT_MAX_EVENTS, queue->count,
               DEFAULT_MAX_EVENTS);
    }
  }

  return true;
}

static bool event_queue_pop(EventQueue *queue, PineEvent *event) {
  if (queue->count == 0) {
    return false; // queue empty
  }

  *event = queue->events[queue->head];
  queue->head = (queue->head + 1) % DEFAULT_MAX_EVENTS;
  queue->count--;
  return true;
}

// forward declaration for the window delegate
@interface CocoaWindowDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, assign) struct PineWindow *pineWindow;
@end

// custom NSWindow subclass to capture key events
@interface CocoaNSWindow : NSWindow
@property(nonatomic, assign) struct PineWindow *pineWindow;
@end

// internal window structure
struct PineWindow {
  CocoaNSWindow *ns_window;
  CocoaWindowDelegate *delegate;
  bool should_close;
  EventQueue event_queue;

  // graphics integration
  void *swapchain; // opaque pointer to graphics swapchain
};

// global application state
static NSApplication *g_app = nil;
static bool g_platform_initialized = false;

// CocoaNSWindow implementation
@implementation CocoaNSWindow

- (void)keyDown:(NSEvent *)event {
  if (self.pineWindow) {
    PineEvent pine_event = {0};
    pine_event.type = PINE_EVENT_KEY_DOWN;
    pine_event.data.key_event.key = [event keyCode];
    pine_event.data.key_event.shift =
        ([event modifierFlags] & NSEventModifierFlagShift) != 0;
    pine_event.data.key_event.control =
        ([event modifierFlags] & NSEventModifierFlagControl) != 0;
    pine_event.data.key_event.opt =
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
    pine_event.data.key_event.key = [event keyCode];
    pine_event.data.key_event.shift =
        ([event modifierFlags] & NSEventModifierFlagShift) != 0;
    pine_event.data.key_event.control =
        ([event modifierFlags] & NSEventModifierFlagControl) != 0;
    pine_event.data.key_event.opt =
        ([event modifierFlags] & NSEventModifierFlagOption) != 0;
    pine_event.data.key_event.command =
        ([event modifierFlags] & NSEventModifierFlagCommand) != 0;

    event_queue_push(&self.pineWindow->event_queue, &pine_event);
  }
}

@end

// CocoaWindowDelegate implementation
@implementation CocoaWindowDelegate

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

- (void)windowDidResize:(NSNotification *)notification {
  // graphics backend will handle resize through the swapchain
  // NOTE: we could add a resize event here if needed
}

@end

// implementation functions
static bool cocoa_platform_init(void) {
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

    pine_log(PINE_LOG_LEVEL_INFO, LOG_SCOPE, "initialized cocoa platform");

    g_platform_initialized = true;
    return true;
  }
}

static void cocoa_platform_shutdown(void) {
  if (!g_platform_initialized) {
    return;
  }

  g_app = nil;
  g_platform_initialized = false;

  pine_log(PINE_LOG_LEVEL_INFO, LOG_SCOPE, "shutdown cocoa platform");
}

static PineWindow *cocoa_window_create(const PineWindowDesc *config) {
  if (!g_platform_initialized) {
    return NULL;
  }

  @autoreleasepool {
    PineWindow *window = malloc(sizeof(PineWindow));
    if (!window) {
      return NULL;
    }

    window->should_close = false;
    window->swapchain = NULL;
    event_queue_init(&window->event_queue);

    // create window rect
    NSRect windowRect = NSMakeRect(config->position.x, config->position.y,
                                   config->width, config->height);

    // determine window style
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable;
    if (config->resizable) {
      styleMask |= NSWindowStyleMaskResizable;
    }

    // create the custom NSWindow
    window->ns_window =
        [[CocoaNSWindow alloc] initWithContentRect:windowRect
                                         styleMask:styleMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];

    // set the back-reference
    window->ns_window.pineWindow = window;

    // NOTE: prevent automatic release when window is closed. this is important.
    [window->ns_window setReleasedWhenClosed:NO];

    // set window properties
    NSString *title = config->title
                          ? [NSString stringWithUTF8String:config->title]
                          : @"Pine Window";
    [window->ns_window setTitle:title];

    // center if desired (overrides (x,y) config)
    if (config->position.center) {
      [window->ns_window center];
    }

    // create and set up the delegate
    window->delegate = [[CocoaWindowDelegate alloc] init];
    window->delegate.pineWindow = window;
    [window->ns_window setDelegate:window->delegate];

    // make window accept key events
    [window->ns_window makeFirstResponder:window->ns_window];

    // show window if requested
    if (config->visible) {
      [window->ns_window makeKeyAndOrderFront:nil];
      // [g_app activateIgnoringOtherApps:YES]; // probably not necessary(?)
    }

    return window;
  }
}

static void cocoa_window_destroy(PineWindow *window) {
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

static void cocoa_window_show(PineWindow *window) {
  if (!window || !window->ns_window) {
    return;
  }

  @autoreleasepool {
    [window->ns_window makeKeyAndOrderFront:nil];
  }
}

static void cocoa_window_hide(PineWindow *window) {
  if (!window || !window->ns_window) {
    return;
  }

  @autoreleasepool {
    [window->ns_window orderOut:nil];
  }
}

static bool cocoa_window_should_close(PineWindow *window) {
  if (!window) {
    return false;
  }

  return window->should_close;
}

static void cocoa_window_request_close(PineWindow *window) {
  if (!window) {
    return;
  }

  window->should_close = true;

  // also push a close event
  PineEvent event = {0};
  event.type = PINE_EVENT_WINDOW_CLOSE;
  event_queue_push(&window->event_queue, &event);
}

static void *cocoa_window_get_native_handle(PineWindow *window) {
  if (!window) {
    return NULL;
  }

  return (__bridge void *)window->ns_window;
}

static void cocoa_window_get_size(PineWindow *window, uint32_t *width,
                                  uint32_t *height) {
  if (!window || !window->ns_window) {
    return;
  }

  @autoreleasepool {
    NSRect contentRect = [[window->ns_window contentView] bounds];
    if (width)
      *width = (uint32_t)contentRect.size.width;
    if (height)
      *height = (uint32_t)contentRect.size.height;
  }
}

static void cocoa_window_set_swapchain(PineWindow *window,
                                       PineSwapchain *swapchain) {
  if (!window) {
    return;
  }

  window->swapchain = swapchain;
}

static PineSwapchain *cocoa_window_get_swapchain(PineWindow *window) {
  if (!window) {
    return NULL;
  }

  return window->swapchain;
}

static bool cocoa_window_poll_event(PineWindow *window, PineEvent *event) {
  if (!window || !event) {
    return false;
  }

  return event_queue_pop(&window->event_queue, event);
}

static void cocoa_platform_poll_events(void) {
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

// backend factory
PineWindowBackend *pine_create_cocoa_backend(void) {
  static PineWindowBackend backend = {
      .platform_init = cocoa_platform_init,
      .platform_shutdown = cocoa_platform_shutdown,
      .platform_poll_events = cocoa_platform_poll_events,
      .window_create = cocoa_window_create,
      .window_destroy = cocoa_window_destroy,
      .window_show = cocoa_window_show,
      .window_hide = cocoa_window_hide,
      .window_should_close = cocoa_window_should_close,
      .window_request_close = cocoa_window_request_close,
      .window_get_native_handle = cocoa_window_get_native_handle,
      .window_get_size = cocoa_window_get_size,
      .window_poll_event = cocoa_window_poll_event,
      .window_set_swapchain = cocoa_window_set_swapchain,
      .window_get_swapchain = cocoa_window_get_swapchain,
  };

  return &backend;
}
