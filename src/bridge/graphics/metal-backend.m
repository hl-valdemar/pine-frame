#import "../graphics-backend.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// enable logs in debug builds
#ifdef DEBUG
void FilteredLog(const char *level, const char *scope, const char *format,
                 ...) {
  // print to stderr with custom formatting
  fprintf(stderr, "[%s] (%s): ", level, scope);

  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);

  fprintf(stderr, "\n");
}
#else  // disable logs in release builds
void FilteredLog(const char *level, const char *scope, const char *format,
                 ...) {}
#endif /* DEBUG */

#define MAX_FRAMES_IN_FLIGHT 3 // triple buffering for smooth performance

// metal-specific context
struct PineGraphicsContext {
  id<MTLDevice> device;
  id<MTLCommandQueue> command_queue;
};

// per-frame resources
typedef struct {
  dispatch_semaphore_t in_flight_semaphore; // cpu-gpu sync
  id<MTLCommandBuffer> command_buffer;
  bool is_encoding; // track if frame is currently encoding
} FrameResources;

// metal-specific swapchain
struct PineSwapchain {
  PineGraphicsContext *context;
  CAMetalLayer *metal_layer;
  NSView *metal_view;

  // current frame state
  id<CAMetalDrawable> current_drawable;
  id<MTLRenderCommandEncoder> current_encoder;

  // frame management
  FrameResources frames[MAX_FRAMES_IN_FLIGHT];
  uint32_t current_frame_index;

  // synchronization
  dispatch_semaphore_t drawable_semaphore; // limit drawable acquisition
  NSLock *frame_lock;                      // protect frame state

  // statistics
  uint64_t frames_submitted;
  uint64_t frames_completed;
};

// metal-specific render pass
struct PineRenderPass {
  id<MTLRenderCommandEncoder> encoder;
  PineSwapchain *swapchain;
  uint32_t frame_index; // track which frame this pass belongs to
};

// custom view for metal rendering
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

// implementation functions

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

  FilteredLog("info", "metal-backend", "created metal context with device: %s",
              [[ctx->device name] UTF8String]);
  return ctx;
}

static void metal_destroy_context(PineGraphicsContext *ctx) {
  if (!ctx)
    return;

  ctx->command_queue = nil;
  ctx->device = nil;
  free(ctx);
}

static PineSwapchain *metal_create_swapchain(PineGraphicsContext *ctx,
                                             const PineSwapchainDesc *config) {
  if (!ctx || !config || !config->native_window_handle)
    return NULL;

  @autoreleasepool {
    PineSwapchain *swapchain = calloc(1, sizeof(PineSwapchain));
    if (!swapchain)
      return NULL;

    swapchain->context = ctx;
    swapchain->current_drawable = nil;
    swapchain->current_encoder = nil;
    swapchain->current_frame_index = 0;
    swapchain->frames_submitted = 0;
    swapchain->frames_completed = 0;

    // initialize synchronization primitives
    swapchain->drawable_semaphore =
        dispatch_semaphore_create(MAX_FRAMES_IN_FLIGHT);
    swapchain->frame_lock = [[NSLock alloc] init];

    // get the NSWindow from the native handle
    NSWindow *window = (__bridge NSWindow *)config->native_window_handle;

    // create metal view
    NSRect contentRect = [[window contentView] bounds];
    swapchain->metal_view = [[PineMetalView alloc] initWithFrame:contentRect];
    swapchain->metal_view.autoresizingMask =
        NSViewWidthSizable | NSViewHeightSizable;

    // configure metal layer
    swapchain->metal_layer =
        ((PineMetalView *)swapchain->metal_view).metalLayer;
    swapchain->metal_layer.device = ctx->device;
    swapchain->metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    swapchain->metal_layer.framebufferOnly = YES;

    // set maximum drawable count for triple buffering
    swapchain->metal_layer.maximumDrawableCount = MAX_FRAMES_IN_FLIGHT;

    // set as content view
    [window setContentView:swapchain->metal_view];

    // update drawable size
    CGSize viewSize = swapchain->metal_view.bounds.size;
    CGFloat scale = window.backingScaleFactor;
    swapchain->metal_layer.drawableSize =
        CGSizeMake(viewSize.width * scale, viewSize.height * scale);

    // initialize per-frame resources
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
      // each frame gets its own semaphore, initially available
      swapchain->frames[i].in_flight_semaphore = dispatch_semaphore_create(1);
      swapchain->frames[i].command_buffer = nil;
      swapchain->frames[i].is_encoding = false;
    }

    FilteredLog("info", "metal-backend",
                "created swapchain with %d frames in flight",
                MAX_FRAMES_IN_FLIGHT);
    return swapchain;
  }
}

static void metal_destroy_swapchain(PineSwapchain *swapchain) {
  if (!swapchain)
    return;

  @autoreleasepool {
    // wait for all frames to complete
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
      if (swapchain->frames[i].in_flight_semaphore) {
        // wait with timeout to avoid hanging forever
        dispatch_time_t timeout =
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
        long result = dispatch_semaphore_wait(
            swapchain->frames[i].in_flight_semaphore, timeout);
        if (result != 0) {
          FilteredLog("info", "metal-scope",
                      "warning: timed out waiting for frame %d to complete", i);
        }
        dispatch_semaphore_signal(swapchain->frames[i].in_flight_semaphore);
      }
      swapchain->frames[i].command_buffer = nil;
    }

    // clean up any pending encoder
    if (swapchain->current_encoder) {
      [swapchain->current_encoder endEncoding];
      swapchain->current_encoder = nil;
    }

    swapchain->current_drawable = nil;

    [swapchain->metal_view removeFromSuperview];
    [swapchain->metal_view release];
    [swapchain->frame_lock release];

    FilteredLog("info", "metal-backend",
                "destroyed swapchain - submitted: %llu, completed: %llu frames",
                swapchain->frames_submitted, swapchain->frames_completed);

    free(swapchain);
  }
}

static void metal_resize_swapchain(PineSwapchain *swapchain, uint32_t width,
                                   uint32_t height) {
  if (!swapchain)
    return;

  @autoreleasepool {
    [swapchain->frame_lock lock];

    // wait for any in-flight frames to complete before resizing
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
      if (swapchain->frames[i].is_encoding) {
        FilteredLog("info", "metal-backend",
                    "warning: resize requested while frame %d is encoding", i);
      }
    }

    CGFloat scale = swapchain->metal_view.window.backingScaleFactor;
    swapchain->metal_layer.drawableSize =
        CGSizeMake(width * scale, height * scale);

    [swapchain->frame_lock unlock];
  }
}

// TODO: make sure this function doesn't leak memory due to removed @autorelease
// scope, as the command encoder was released prematurely
static PineRenderPass *metal_begin_render_pass(PineSwapchain *swapchain,
                                               const PinePassAction *action) {
  if (!swapchain)
    return NULL;

  [swapchain->frame_lock lock];

  // get current frame resources
  FrameResources *frame = &swapchain->frames[swapchain->current_frame_index];

  // wait for this frame slot to be available (gpu finished with it)
  dispatch_semaphore_wait(frame->in_flight_semaphore, DISPATCH_TIME_FOREVER);

  // clean up any previous encoder that wasn't properly ended
  if (swapchain->current_encoder) {
    FilteredLog("info", "metal-backend",
                "warning: previous render encoder was not ended properly");
    [swapchain->current_encoder endEncoding];
    swapchain->current_encoder = nil;
  }

  // clean up any previous command buffer
  if (frame->command_buffer) {
    frame->command_buffer = nil;
  }

  // wait for a drawable to be available
  // this prevents the cpu from getting too far ahead of the gpu
  dispatch_semaphore_wait(swapchain->drawable_semaphore, DISPATCH_TIME_FOREVER);

  // get drawable (this might still block if layer has no available drawables)
  id<CAMetalDrawable> drawable = [swapchain->metal_layer nextDrawable];
  if (!drawable) {
    // return the semaphores if we fail
    dispatch_semaphore_signal(swapchain->drawable_semaphore);
    dispatch_semaphore_signal(frame->in_flight_semaphore);
    [swapchain->frame_lock unlock];
    FilteredLog("info", "metal-backend", "failed to acquire drawable");
    return NULL;
  }

  // create command buffer for this frame
  id<MTLCommandBuffer> cmd_buffer =
      [swapchain->context->command_queue commandBuffer];
  if (!cmd_buffer) {
    dispatch_semaphore_signal(swapchain->drawable_semaphore);
    dispatch_semaphore_signal(frame->in_flight_semaphore);
    [swapchain->frame_lock unlock];
    return NULL;
  }

  // set a label for debugging
  cmd_buffer.label =
      [NSString stringWithFormat:@"Frame %d", swapchain->current_frame_index];

  // store command buffer in frame resources
  frame->command_buffer = cmd_buffer;
  frame->is_encoding = true;

  // add completion handler for this frame
  __block dispatch_semaphore_t frameSemaphore = frame->in_flight_semaphore;
  __block dispatch_semaphore_t drawableSemaphore =
      swapchain->drawable_semaphore;
  __block uint64_t *frames_completed = &swapchain->frames_completed;

  [cmd_buffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    // signal that this frame slot is available again
    dispatch_semaphore_signal(frameSemaphore);
    // signal that a drawable slot is available
    dispatch_semaphore_signal(drawableSemaphore);
    // update statistics
    __sync_fetch_and_add(frames_completed, 1);
  }];

  // create render pass descriptor
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

  // create encoder
  id<MTLRenderCommandEncoder> encoder =
      [cmd_buffer renderCommandEncoderWithDescriptor:desc];
  if (!encoder) {
    frame->is_encoding = false;
    [swapchain->frame_lock unlock];
    return NULL;
  }

  encoder.label = [NSString stringWithFormat:@"Render Encoder Frame %d",
                                             swapchain->current_frame_index];

  // store current state
  swapchain->current_drawable = drawable;
  swapchain->current_encoder = encoder;

  // create render pass handle
  PineRenderPass *pass = malloc(sizeof(PineRenderPass));
  pass->encoder = encoder;
  pass->swapchain = swapchain;
  pass->frame_index = swapchain->current_frame_index;

  [swapchain->frame_lock unlock];

  return pass;
}

static void metal_end_render_pass(PineRenderPass *pass) {
  if (!pass)
    return;

  @autoreleasepool {
    [pass->swapchain->frame_lock lock];

    [pass->encoder endEncoding];

    // clear the encoder reference from swapchain
    if (pass->swapchain->current_encoder == pass->encoder) {
      pass->swapchain->current_encoder = nil;
    }

    // mark frame as no longer encoding
    pass->swapchain->frames[pass->frame_index].is_encoding = false;

    [pass->swapchain->frame_lock unlock];

    free(pass);
  }
}

static void metal_present(PineSwapchain *swapchain) {
  if (!swapchain) {
    FilteredLog("info", "metal-backend",
                "warning: attempting to present with null swapchain");
    return;
  }

  @autoreleasepool {
    [swapchain->frame_lock lock];

    FrameResources *frame = &swapchain->frames[swapchain->current_frame_index];

    if (!frame->command_buffer || !swapchain->current_drawable) {
      FilteredLog("info", "metal-backend",
                  "warning: attempting to present without valid command buffer "
                  "or drawable");
      [swapchain->frame_lock unlock];
      return;
    }

    // make sure any encoder is ended
    if (swapchain->current_encoder) {
      FilteredLog(
          "info", "metal-backend",
          "warning: encoder still active during present, ending it now");
      [swapchain->current_encoder endEncoding];
      swapchain->current_encoder = nil;
      frame->is_encoding = false;
    }

    // schedule presentation
    [frame->command_buffer presentDrawable:swapchain->current_drawable];

    // commit the command buffer
    [frame->command_buffer commit];

    // update statistics
    swapchain->frames_submitted++;

    // clear references
    swapchain->current_drawable = nil;

    // move to next frame
    swapchain->current_frame_index =
        (swapchain->current_frame_index + 1) % MAX_FRAMES_IN_FLIGHT;

    [swapchain->frame_lock unlock];
  }
}

// Rest of the implementation remains the same...
static void metal_get_capabilities(PineGraphicsContext *ctx,
                                   PineGraphicsCapabilities *caps) {
  if (!ctx || !caps)
    return;

  // query metal device capabilities
  caps->compute_shaders = true;
  caps->tessellation = [ctx->device supportsFamily:MTLGPUFamilyCommon1];
  caps->geometry_shaders = false; // metal doesn't support geometry shaders
  caps->max_texture_size = 16384; // typical for modern GPUs
  caps->max_vertex_attributes = 31;
}

struct PineBuffer {
  id<MTLBuffer> buffer;
  size_t len;
  PineBufferType type;
  PineIndexType index_type;
};

struct PineShader {
  id<MTLFunction> function;
};

struct PinePipeline {
  id<MTLRenderPipelineState> state;
  MTLVertexDescriptor *vertex_descriptor;
};

// buffer implementation
static PineBuffer *metal_create_buffer(PineGraphicsContext *ctx,
                                       const PineBufferDesc *desc) {
  if (!ctx || !desc || !desc->data)
    return NULL;

  PineBuffer *buffer = malloc(sizeof(PineBuffer));
  if (!buffer)
    return NULL;

  buffer->type = desc->type;
  buffer->index_type = desc->index_type;
  buffer->len = desc->len;
  buffer->buffer =
      [ctx->device newBufferWithBytes:desc->data
                               length:desc->len
                              options:MTLResourceStorageModeShared];

  if (!buffer->buffer) {
    free(buffer);
    return NULL;
  }

  return buffer;
}

static void metal_destroy_buffer(PineBuffer *buffer) {
  if (!buffer)
    return;
  buffer->buffer = nil;
  free(buffer);
}

// shader implementation
static PineShader *metal_create_shader(PineGraphicsContext *ctx,
                                       const PineShaderDesc *desc) {
  if (!ctx || !desc || !desc->source)
    return NULL;

  @autoreleasepool {
    NSError *error = nil;
    NSString *source = [NSString stringWithUTF8String:desc->source];

    id<MTLLibrary> library = [ctx->device newLibraryWithSource:source
                                                       options:nil
                                                         error:&error];

    if (!library) {
      FilteredLog("info", "metal-backend", "failed to compile shader: %@",
                  error);
      return NULL;
    }

    // get the main function (we'll use standard names)
    NSString *functionName =
        (desc->type == PINE_SHADER_VERTEX) ? @"vertex_main" : @"fragment_main";
    id<MTLFunction> function = [library newFunctionWithName:functionName];

    if (!function) {
      FilteredLog("info", "metal-backend",
                  "failed to find function %@ in shader", functionName);
      return NULL;
    }

    PineShader *shader = malloc(sizeof(PineShader));
    shader->function = function;

    return shader;
  }
}

static void metal_destroy_shader(PineShader *shader) {
  if (!shader)
    return;
  shader->function = nil;
  free(shader);
}

// pipeline implementation
static PinePipeline *metal_create_pipeline(PineGraphicsContext *ctx,
                                           const PinePipelineDesc *desc) {
  if (!ctx || !desc)
    return NULL;

  @autoreleasepool {
    MTLRenderPipelineDescriptor *pipeline_desc =
        [[MTLRenderPipelineDescriptor alloc] init];
    pipeline_desc.vertexFunction = desc->vertex_shader->function;
    pipeline_desc.fragmentFunction = desc->fragment_shader->function;
    pipeline_desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    // setup vertex descriptor
    MTLVertexDescriptor *vertex_desc = [[MTLVertexDescriptor alloc] init];

    for (size_t i = 0; i < desc->attribute_count; i++) {
      MTLVertexAttributeDescriptor *attr = vertex_desc.attributes[i];
      attr.offset = desc->attributes[i].offset;
      attr.bufferIndex = desc->attributes[i].buffer_index;

      switch (desc->attributes[i].format) {
      case PINE_VERTEX_FORMAT_FLOAT2:
        attr.format = MTLVertexFormatFloat2;
        break;
      case PINE_VERTEX_FORMAT_FLOAT3:
        attr.format = MTLVertexFormatFloat3;
        break;
      case PINE_VERTEX_FORMAT_FLOAT4:
        attr.format = MTLVertexFormatFloat4;
        break;
      }
    }

    vertex_desc.layouts[0].stride = desc->vertex_stride;
    vertex_desc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    pipeline_desc.vertexDescriptor = vertex_desc;

    NSError *error = nil;
    id<MTLRenderPipelineState> state =
        [ctx->device newRenderPipelineStateWithDescriptor:pipeline_desc
                                                    error:&error];

    if (!state) {
      FilteredLog("info", "metal-backend",
                  "failed to create pipeline state: %@", error);
      return NULL;
    }

    PinePipeline *pipeline = malloc(sizeof(PinePipeline));
    pipeline->state = state;
    pipeline->vertex_descriptor = vertex_desc;

    return pipeline;
  }
}

static void metal_destroy_pipeline(PinePipeline *pipeline) {
  if (!pipeline)
    return;

  pipeline->state = nil;
  pipeline->vertex_descriptor = nil;
  free(pipeline);
}

// drawing functions
static void metal_set_pipeline(PineRenderPass *pass, PinePipeline *pipeline) {
  if (!pass || !pipeline)
    return;

  [pass->encoder setRenderPipelineState:pipeline->state];
}

static void metal_set_vertex_buffer(PineRenderPass *pass, uint32_t index,
                                    PineBuffer *buffer) {
  if (!pass || !buffer)
    return;

  [pass->encoder setVertexBuffer:buffer->buffer offset:0 atIndex:index];
}

static void metal_draw(PineRenderPass *pass, uint32_t vertex_count,
                       uint32_t first_vertex) {
  if (!pass)
    return;

  [pass->encoder drawPrimitives:MTLPrimitiveTypeTriangle
                    vertexStart:first_vertex
                    vertexCount:vertex_count];
}

static void metal_draw_indexed(PineRenderPass *pass, PineBuffer *buffer,
                               uint32_t first_index, int32_t vertex_offset) {
  if (!pass || buffer->type != PINE_BUFFER_INDEX)
    return;

  MTLIndexType index_type;
  NSUInteger index_size;
  if (buffer->index_type == PINE_INDEX_TYPE_U16) {
    index_type = MTLIndexTypeUInt16;
    index_size = sizeof(uint16_t);
  } else if (buffer->index_type == PINE_INDEX_TYPE_U32) {
    index_type = MTLIndexTypeUInt32;
    index_size = sizeof(uint32_t);
  }

  [pass->encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:buffer->len / index_size
                             indexType:index_type
                           indexBuffer:buffer->buffer
                     indexBufferOffset:first_index * index_size
                         instanceCount:1
                            baseVertex:vertex_offset
                          baseInstance:0];
}

// backend factory
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
      .get_capabilities = metal_get_capabilities,
      .create_buffer = metal_create_buffer,
      .destroy_buffer = metal_destroy_buffer,
      .create_shader = metal_create_shader,
      .destroy_shader = metal_destroy_shader,
      .create_pipeline = metal_create_pipeline,
      .destroy_pipeline = metal_destroy_pipeline,
      .set_pipeline = metal_set_pipeline,
      .set_vertex_buffer = metal_set_vertex_buffer,
      .draw = metal_draw,
      .draw_indexed = metal_draw_indexed,
  };

  return &backend;
}
