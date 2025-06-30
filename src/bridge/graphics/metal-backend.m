#import "../graphics.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// Metal-specific context
struct PineGraphicsContext {
  id<MTLDevice> device;
  id<MTLCommandQueue> command_queue;
};

// Metal-specific swapchain
struct PineSwapchain {
  PineGraphicsContext *context;
  CAMetalLayer *metal_layer;
  NSView *metal_view;
  id<CAMetalDrawable> current_drawable;
  id<MTLCommandBuffer> current_command_buffer;
  id<MTLRenderCommandEncoder> current_encoder; // Track current encoder
  MTLRenderPassDescriptor *render_pass_descriptor;
};

// Metal-specific render pass
struct PineRenderPass {
  id<MTLRenderCommandEncoder> encoder;
  id<MTLCommandBuffer> command_buffer;
  id<CAMetalDrawable> drawable;
  PineSwapchain *swapchain; // Back reference to swapchain
};

// Custom view for Metal rendering
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
  if (self.window) {
    self.metalLayer.contentsScale = self.window.backingScaleFactor;
  }
}

@end

// Implementation functions

static PineGraphicsContext *metal_create_context(void) {
  PineGraphicsContext *ctx = malloc(sizeof(PineGraphicsContext));
  if (!ctx)
    return NULL;

  ctx->device = MTLCreateSystemDefaultDevice();
  if (!ctx->device) {
    free(ctx);
    return NULL;
  }

  ctx->command_queue = [ctx->device newCommandQueue];
  if (!ctx->command_queue) {
    free(ctx);
    return NULL;
  }

  return ctx;
}

static void metal_destroy_context(PineGraphicsContext *ctx) {
  if (!ctx)
    return;

  ctx->command_queue = nil;
  ctx->device = nil;
  free(ctx);
}

static PineSwapchain *
metal_create_swapchain(PineGraphicsContext *ctx,
                       const PineSwapchainConfig *config) {
  if (!ctx || !config || !config->native_window_handle)
    return NULL;

  @autoreleasepool {
    PineSwapchain *swapchain = malloc(sizeof(PineSwapchain));
    if (!swapchain)
      return NULL;

    swapchain->context = ctx;
    swapchain->current_drawable = nil;
    swapchain->current_command_buffer = nil;
    swapchain->current_encoder = nil;
    swapchain->render_pass_descriptor = nil;

    // Get the NSWindow from the native handle
    NSWindow *window = (__bridge NSWindow *)config->native_window_handle;

    // Create metal view
    NSRect contentRect = [[window contentView] bounds];
    swapchain->metal_view = [[PineMetalView alloc] initWithFrame:contentRect];
    swapchain->metal_view.autoresizingMask =
        NSViewWidthSizable | NSViewHeightSizable;

    // Configure metal layer
    swapchain->metal_layer =
        ((PineMetalView *)swapchain->metal_view).metalLayer;
    swapchain->metal_layer.device = ctx->device;
    swapchain->metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    swapchain->metal_layer.framebufferOnly = YES;

    // Set as content view
    [window setContentView:swapchain->metal_view];

    // Update drawable size
    CGSize viewSize = swapchain->metal_view.bounds.size;
    CGFloat scale = window.backingScaleFactor;
    swapchain->metal_layer.drawableSize =
        CGSizeMake(viewSize.width * scale, viewSize.height * scale);

    return swapchain;
  }
}

static void metal_destroy_swapchain(PineSwapchain *swapchain) {
  if (!swapchain)
    return;

  @autoreleasepool {
    // End any pending encoder
    if (swapchain->current_encoder) {
      [swapchain->current_encoder endEncoding];
      swapchain->current_encoder = nil;
    }

    swapchain->current_drawable = nil;
    swapchain->current_command_buffer = nil;
    swapchain->render_pass_descriptor = nil;

    [swapchain->metal_view removeFromSuperview];
    [swapchain->metal_view release];

    free(swapchain);
  }
}

static void metal_resize_swapchain(PineSwapchain *swapchain, uint32_t width,
                                   uint32_t height) {
  if (!swapchain)
    return;

  @autoreleasepool {
    CGFloat scale = swapchain->metal_view.window.backingScaleFactor;
    swapchain->metal_layer.drawableSize =
        CGSizeMake(width * scale, height * scale);
  }
}

static PineRenderPass *metal_begin_render_pass(PineSwapchain *swapchain,
                                               const PinePassAction *action) {
  if (!swapchain)
    return NULL;

  // End any previous encoder that wasn't properly ended
  if (swapchain->current_encoder) {
    NSLog(@"Warning: Previous render encoder was not ended properly");
    [swapchain->current_encoder endEncoding];
    swapchain->current_encoder = nil;
  }

  // Get drawable
  id<CAMetalDrawable> drawable = [swapchain->metal_layer nextDrawable];
  if (!drawable)
    return NULL;

  // Create command buffer
  id<MTLCommandBuffer> cmd_buffer =
      [swapchain->context->command_queue commandBuffer];
  if (!cmd_buffer)
    return NULL;

  // Create render pass descriptor
  MTLRenderPassDescriptor *desc =
      [MTLRenderPassDescriptor renderPassDescriptor];
  MTLRenderPassColorAttachmentDescriptor *color_att = desc.colorAttachments[0];
  color_att.texture = drawable.texture;

  if (action && action->color.action == PINE_ACTION_CLEAR) {
    color_att.loadAction = MTLLoadActionClear;
    color_att.clearColor = MTLClearColorMake(action->color.r, action->color.g,
                                             action->color.b, action->color.a);
  } else if (action && action->color.action == PINE_ACTION_LOAD) {
    color_att.loadAction = MTLLoadActionLoad;
  } else {
    color_att.loadAction = MTLLoadActionDontCare;
  }
  color_att.storeAction = MTLStoreActionStore;

  // Create encoder
  id<MTLRenderCommandEncoder> encoder =
      [cmd_buffer renderCommandEncoderWithDescriptor:desc];
  if (!encoder)
    return NULL;

  // Store current drawable/command buffer/encoder in swapchain
  swapchain->current_drawable = drawable;
  swapchain->current_command_buffer = cmd_buffer;
  swapchain->current_encoder = encoder;

  PineRenderPass *pass = malloc(sizeof(PineRenderPass));
  pass->encoder = encoder;
  pass->command_buffer = cmd_buffer;
  pass->drawable = drawable;
  pass->swapchain = swapchain;

  return pass;
}

static void metal_end_render_pass(PineRenderPass *pass) {
  if (!pass)
    return;

  [pass->encoder endEncoding];

  // Clear the encoder reference from swapchain
  if (pass->swapchain && pass->swapchain->current_encoder == pass->encoder) {
    pass->swapchain->current_encoder = nil;
  }

  free(pass);
}

static void metal_present(PineSwapchain *swapchain) {
  if (!swapchain || !swapchain->current_command_buffer ||
      !swapchain->current_drawable) {
    NSLog(@"Warning: Attempting to present without valid command buffer or "
          @"drawable");
    return;
  }

  // Make sure any encoder is ended
  if (swapchain->current_encoder) {
    NSLog(@"Warning: Encoder still active during present, ending it now");
    [swapchain->current_encoder endEncoding];
    swapchain->current_encoder = nil;
  }

  [swapchain->current_command_buffer
      presentDrawable:swapchain->current_drawable];
  [swapchain->current_command_buffer commit];
  [swapchain->current_command_buffer waitUntilCompleted];

  swapchain->current_command_buffer = nil;
  swapchain->current_drawable = nil;
}

static void metal_get_capabilities(PineGraphicsContext *ctx,
                                   PineGraphicsCapabilities *caps) {
  if (!ctx || !caps)
    return;

  // Query Metal device capabilities
  caps->compute_shaders = true;
  caps->tessellation = [ctx->device supportsFamily:MTLGPUFamilyCommon1];
  caps->geometry_shaders = false; // Metal doesn't support geometry shaders
  caps->max_texture_size = 16384; // Typical for modern GPUs
  caps->max_vertex_attributes = 31;
}

// Frame management
static NSAutoreleasePool *g_frame_pool = nil;

static void metal_begin_frame(void) {
  if (g_frame_pool) {
    [g_frame_pool release];
  }
  g_frame_pool = [[NSAutoreleasePool alloc] init];
}

static void metal_end_frame(void) {
  if (g_frame_pool) {
    [g_frame_pool release];
    g_frame_pool = nil;
  }
}

// Backend factory
PineGraphicsBackend *pine_create_metal_backend(void) {
  static PineGraphicsBackend backend = {
      .create_context = metal_create_context,
      .destroy_context = metal_destroy_context,
      .create_swapchain = metal_create_swapchain,
      .destroy_swapchain = metal_destroy_swapchain,
      .resize_swapchain = metal_resize_swapchain,
      .begin_render_pass = metal_begin_render_pass,
      .end_render_pass = metal_end_render_pass,
      .present = metal_present,
      .begin_frame = metal_begin_frame,
      .end_frame = metal_end_frame,
      .get_capabilities = metal_get_capabilities,
  };

  return &backend;
}
