#import "macos_bridge.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

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

// custom view for Metal rendering
@interface PineMetalView : NSView
@property(nonatomic, retain) CAMetalLayer *metalLayer;
@end

@implementation PineMetalView

+ (Class)layerClass {
  return [CAMetalLayer class];
}

- (CAMetalLayer *)metalLayer {
  return (CAMetalLayer *)self.layer;
}

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.wantsLayer = YES;
    self.layer = [CAMetalLayer layer];
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = YES;
  }
  return self;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  // update the layer's contentsScale when moving to a window
  if (self.window) {
    self.metalLayer.contentsScale = self.window.backingScaleFactor;
  }
}

@end

// internal window structure
struct PineWindow {
  PineNSWindow *ns_window;
  PineMetalView *metal_view;
  WindowDelegate *delegate;
  bool should_close;
  EventQueue event_queue;

  // metal objects
  id<MTLDevice> device;
  id<MTLCommandQueue> command_queue;
  id<CAMetalDrawable> current_drawable;
  id<MTLCommandBuffer> current_command_buffer;
  id<MTLRenderCommandEncoder> current_render_encoder;
  MTLRenderPassDescriptor *render_pass_descriptor;
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
  if (self.pineWindow && self.pineWindow->metal_view) {
    // update drawable size when window resizes
    CGSize viewSize = self.pineWindow->metal_view.bounds.size;
    CGFloat scale = self.pineWindow->ns_window.backingScaleFactor;
    self.pineWindow->metal_view.metalLayer.drawableSize =
        CGSizeMake(viewSize.width * scale, viewSize.height * scale);
  }
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

    // METAL SETUP START //

    // create metal device and command queue
    window->device = MTLCreateSystemDefaultDevice();
    if (!window->device) {
      NSLog(@"Failed to create Metal device");
      [window->ns_window release];
      free(window);
      return NULL;
    }

    window->command_queue = [window->device newCommandQueue];
    if (!window->command_queue) {
      NSLog(@"Failed to create Metal command queue");
      [window->ns_window release];
      free(window);
      return NULL;
    }

    // create the metal view
    NSRect contentRect = [[window->ns_window contentView] bounds];
    window->metal_view = [[PineMetalView alloc] initWithFrame:contentRect];
    window->metal_view.autoresizingMask =
        NSViewWidthSizable | NSViewHeightSizable;

    // configure the metal layer
    window->metal_view.metalLayer.device = window->device;
    window->metal_view.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    window->metal_view.metalLayer.framebufferOnly = YES;

    // set the view as the window's content view
    [window->ns_window setContentView:window->metal_view];

    // update drawable size
    CGSize viewSize = window->metal_view.bounds.size;
    CGFloat scale = window->ns_window.backingScaleFactor;
    window->metal_view.metalLayer.drawableSize =
        CGSizeMake(viewSize.width * scale, viewSize.height * scale);

    // METAL SETUP END //

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

    // clean up metal resources
    window->current_render_encoder = nil;
    window->render_pass_descriptor = nil;
    window->current_command_buffer = nil;
    window->current_drawable = nil;
    window->command_queue = nil;
    window->device = nil;

    if (window->metal_view) {
      [window->metal_view release];
      window->metal_view = nil;
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

// RENDERING FUNCTIONS //

void pine_window_begin_pass(PineWindow *window,
                            const PinePassAction *pass_action) {
  if (!window || !window->metal_view) {
    return;
  }

  // @autoreleasepool {
  // get the next drawable
  window->current_drawable = [window->metal_view.metalLayer nextDrawable];
  if (!window->current_drawable) {
    return;
  }

  // create command buffer
  window->current_command_buffer = [window->command_queue commandBuffer];
  if (!window->current_command_buffer) {
    window->current_drawable = nil;
    return;
  }

  // create render pass descriptor
  window->render_pass_descriptor =
      [MTLRenderPassDescriptor renderPassDescriptor];

  // configure color attachment
  MTLRenderPassColorAttachmentDescriptor *colorAttachment =
      window->render_pass_descriptor.colorAttachments[0];
  colorAttachment.texture = window->current_drawable.texture;

  if (pass_action && pass_action->color.action == PINE_ACTION_CLEAR) {
    colorAttachment.loadAction = MTLLoadActionClear;
    colorAttachment.clearColor =
        MTLClearColorMake(pass_action->color.r, pass_action->color.g,
                          pass_action->color.b, pass_action->color.a);
  } else if (pass_action && pass_action->color.action == PINE_ACTION_LOAD) {
    colorAttachment.loadAction = MTLLoadActionLoad;
  } else {
    colorAttachment.loadAction = MTLLoadActionDontCare;
  }
  colorAttachment.storeAction = MTLStoreActionStore;

  // create render encoder
  window->current_render_encoder = [window->current_command_buffer
      renderCommandEncoderWithDescriptor:window->render_pass_descriptor];
  // }
}

void pine_window_end_pass(PineWindow *window) {
  if (!window || !window->current_render_encoder) {
    return;
  }

  @autoreleasepool {
    [window->current_render_encoder endEncoding];
    [window->current_render_encoder release];
    window->current_render_encoder = nil;
    window->render_pass_descriptor = nil;
  }
}

void pine_window_commit(PineWindow *window) {
  if (!window || !window->current_command_buffer || !window->current_drawable) {
    return;
  }

  @autoreleasepool {
    // present drawable, commit command buffer, and wait for completion
    [window->current_command_buffer presentDrawable:window->current_drawable];
    [window->current_command_buffer commit];
    [window->current_command_buffer waitUntilCompleted];

    // clean up
    window->current_command_buffer = nil;
    window->current_drawable = nil;
  }
}
