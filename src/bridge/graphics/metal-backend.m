#import "../graphics.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <stdint.h>

#define MAX_FRAMES_IN_FLIGHT 2 // or 3 for triple buffering

// metal-specific context
struct PineGraphicsContext {
  id<MTLDevice> device;
  id<MTLCommandQueue> command_queue;
};

// per-frame resources
typedef struct {
  id<MTLCommandBuffer> command_buffer;
  dispatch_semaphore_t semaphore;
} FrameResources;

// metal-specific swapchain
struct PineSwapchain {
  PineGraphicsContext *context;
  CAMetalLayer *metal_layer;
  NSView *metal_view;
  id<CAMetalDrawable> current_drawable;
  id<MTLCommandBuffer> current_command_buffer;
  id<MTLRenderCommandEncoder> current_encoder; // track current encoder
  MTLRenderPassDescriptor *render_pass_descriptor;

  // per-frame resources
  FrameResources frames[MAX_FRAMES_IN_FLIGHT];

  uint32_t current_frame_index;
  dispatch_semaphore_t image_available_semaphore;
};

// metal-specific render pass
struct PineRenderPass {
  id<MTLRenderCommandEncoder> encoder;
  id<MTLCommandBuffer> command_buffer;
  id<CAMetalDrawable> drawable;
  PineSwapchain *swapchain; // back reference to swapchain
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
    PineSwapchain *swapchain = malloc(sizeof(PineSwapchain));
    if (!swapchain)
      return NULL;

    swapchain->context = ctx;
    swapchain->current_drawable = nil;
    swapchain->current_command_buffer = nil;
    swapchain->current_encoder = nil;
    swapchain->render_pass_descriptor = nil;

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

    // set as content view
    [window setContentView:swapchain->metal_view];

    // update drawable size
    CGSize viewSize = swapchain->metal_view.bounds.size;
    CGFloat scale = window.backingScaleFactor;
    swapchain->metal_layer.drawableSize =
        CGSizeMake(viewSize.width * scale, viewSize.height * scale);

    swapchain->current_frame_index = 0;
    swapchain->image_available_semaphore =
        dispatch_semaphore_create(MAX_FRAMES_IN_FLIGHT);

    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
      swapchain->frames[i].semaphore = dispatch_semaphore_create(1);
      swapchain->frames[i].command_buffer = nil;
    }

    return swapchain;
  }
}

static void metal_destroy_swapchain(PineSwapchain *swapchain) {
  if (!swapchain)
    return;

  @autoreleasepool {
    // end any pending encoder
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

  // wait for previous frame using this slot to complete
  dispatch_semaphore_wait(
      swapchain->frames[swapchain->current_frame_index].semaphore,
      DISPATCH_TIME_FOREVER);

  // end any previous encoder that wasn't properly ended
  if (swapchain->current_encoder) {
    NSLog(@"Warning: Previous render encoder was not ended properly");
    [swapchain->current_encoder endEncoding];
    swapchain->current_encoder = nil;
  }

  // get drawable (this might block if none available)
  id<CAMetalDrawable> drawable = [swapchain->metal_layer nextDrawable];
  if (!drawable)
    return NULL;

  // create command buffer for this frame
  id<MTLCommandBuffer> cmd_buffer =
      [swapchain->context->command_queue commandBuffer];
  if (!cmd_buffer)
    return NULL;

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
  if (!encoder)
    return NULL;

  // store current drawable/command buffer/encoder in swapchain
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

  // clear the encoder reference from swapchain
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

  // make sure any encoder is ended
  if (swapchain->current_encoder) {
    NSLog(@"Warning: Encoder still active during present, ending it now");
    [swapchain->current_encoder endEncoding];
    swapchain->current_encoder = nil;
  }

  // get current frame resources
  FrameResources *frame = &swapchain->frames[swapchain->current_frame_index];

  // add completion handler instead of blocking wait
  __block dispatch_semaphore_t frameSemaphore = frame->semaphore;
  [swapchain->current_command_buffer
      addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(frameSemaphore);
      }];

  [swapchain->current_command_buffer
      presentDrawable:swapchain->current_drawable];
  [swapchain->current_command_buffer commit];

  // move to next frame
  swapchain->current_frame_index =
      (swapchain->current_frame_index + 1) % MAX_FRAMES_IN_FLIGHT;

  // clear references
  swapchain->current_command_buffer = nil;
  swapchain->current_drawable = nil;
}

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

  NSError *error = nil;
  NSString *source = [NSString stringWithUTF8String:desc->source];

  id<MTLLibrary> library = [ctx->device newLibraryWithSource:source
                                                     options:nil
                                                       error:&error];

  if (!library) {
    NSLog(@"Failed to compile shader: %@", error);
    return NULL;
  }

  // get the main function (we'll use standard names)
  NSString *functionName =
      (desc->type == PINE_SHADER_VERTEX) ? @"vertex_main" : @"fragment_main";
  id<MTLFunction> function = [library newFunctionWithName:functionName];

  if (!function) {
    NSLog(@"Failed to find function %@ in shader", functionName);
    return NULL;
  }

  PineShader *shader = malloc(sizeof(PineShader));
  shader->function = function;

  return shader;
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
    NSLog(@"Failed to create pipeline state: %@", error);
    return NULL;
  }

  PinePipeline *pipeline = malloc(sizeof(PinePipeline));
  pipeline->state = state;
  pipeline->vertex_descriptor = vertex_desc;

  return pipeline;
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
                            indexCount:buffer->len
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
