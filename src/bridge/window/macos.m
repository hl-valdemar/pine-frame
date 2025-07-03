#import "../window.h"
#import <Cocoa/Cocoa.h>

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
          NSLog(@"Replaced low priority event with high priority event");
          return true;
        }
        scan_idx = (scan_idx + 1) % DEFAULT_MAX_EVENTS;
      }
    }

    // log warning about dropped events periodically
    if (queue->events_dropped % 100 == 1) { // log every 100 drops
      NSLog(@"WARNING: Event queue overflow! Dropped %zu events total",
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
      NSLog(@"WARNING: Event queue is %zu%% full (%zu/%d events)",
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

// batch processing for better performance
static size_t event_queue_pop_batch(EventQueue *queue, PineEvent *events,
                                    size_t max_events) {
  size_t popped = 0;
  while (popped < max_events && queue->count > 0) {
    events[popped] = queue->events[queue->head];
    queue->head = (queue->head + 1) % DEFAULT_MAX_EVENTS;
    queue->count--;
    popped++;
  }
  return popped;
}

static void event_queue_get_stats(const EventQueue *queue,
                                  size_t *current_count,
                                  size_t *high_water_mark,
                                  size_t *events_dropped) {
  if (current_count)
    *current_count = queue->count;
  if (high_water_mark)
    *high_water_mark = queue->high_water_mark;
  if (events_dropped)
    *events_dropped = queue->events_dropped;
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

  // graphics integration
  void *swapchain; // opaque pointer to graphics swapchain
};

// global application state
static NSApplication *g_app = nil;
static bool g_platform_initialized = false;

// PineNSWindow implementation
@implementation PineNSWindow

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

- (void)windowDidResize:(NSNotification *)notification {
  // graphics backend will handle resize through the swapchain
  // NOTE: we could add a resize event here if needed
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

PineWindow *pine_window_create(const PineWindowDesc *config) {
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
        [[PineNSWindow alloc] initWithContentRect:windowRect
                                        styleMask:styleMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

    // set the back-reference
    window->ns_window.pineWindow = window;

    // IMPORTANT: prevent automatic release when window is closed
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

    // // create a simple NSView as content view (graphics backend will
    // replace
    // // this)
    // NSView *contentView = [[NSView alloc] initWithFrame:windowRect];
    // [window->ns_window setContentView:contentView];
    // [contentView release];

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

void *pine_window_get_native_handle(PineWindow *window) {
  if (!window) {
    return NULL;
  }

  return (__bridge void *)window->ns_window;
}

void pine_window_get_size(PineWindow *window, uint32_t *width,
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

void pine_window_set_swapchain(PineWindow *window, PineSwapchain *swapchain) {
  if (!window) {
    return;
  }

  window->swapchain = swapchain;
}

PineSwapchain *pine_window_get_swapchain(PineWindow *window) {
  if (!window) {
    return NULL;
  }

  return window->swapchain;
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
