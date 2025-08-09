#ifndef PINE_GRAPHICS_BACKEND_H
#define PINE_GRAPHICS_BACKEND_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

// forward declarations
typedef struct PineGraphicsContext PineGraphicsContext;
typedef struct PineSwapchain PineSwapchain;
typedef struct PineRenderPass PineRenderPass;

// backend capabilities
typedef struct {
  bool compute_shaders;
  bool tessellation;
  bool geometry_shaders;
  uint32_t max_texture_size;
  uint32_t max_vertex_attributes;
} PineGraphicsCapabilities;

// swapchain config
typedef struct {
  void *native_window_handle; // NSWindow* on macOS, HWND on Windows, etc.
  bool vsync;
} PineSwapchainDesc;

// render pass types
typedef enum {
  PINE_ACTION_DONTCARE = 0,
  PINE_ACTION_CLEAR = 1,
  PINE_ACTION_LOAD = 2,
} PineLoadAction;

typedef struct {
  PineLoadAction action;
  float r, g, b, a;
} PineColorAttachment;

typedef struct {
  PineLoadAction action;
  float depth;
  uint8_t stencil;
} PineDepthStencilAttachment;

typedef struct {
  PineColorAttachment color;
  PineDepthStencilAttachment depth_stencil;
} PinePassAction;

// buffer types
typedef struct PineBuffer PineBuffer;

typedef enum {
  PINE_BUFFER_VERTEX,
  PINE_BUFFER_INDEX,
  PINE_BUFFER_UNIFORM,
} PineBufferKind;

typedef enum {
  PINE_INDEX_TYPE_U16 = 0,
  PINE_INDEX_TYPE_U32 = 1,
} PineIndexType;

typedef struct {
  const void *data;
  size_t len;
  PineBufferKind kind;
  PineIndexType index_type;
} PineBufferDesc;

// shader types
typedef struct PineShader PineShader;

typedef struct {
  const char *source;
  enum {
    PINE_SHADER_VERTEX,
    PINE_SHADER_FRAGMENT,
  } kind;
} PineShaderDesc;

// pipeline types
typedef struct PinePipeline PinePipeline;

typedef struct {
  enum {
    PINE_VERTEX_FORMAT_FLOAT2,
    PINE_VERTEX_FORMAT_FLOAT3,
    PINE_VERTEX_FORMAT_FLOAT4,
  } format;
  size_t offset;
  uint32_t buffer_index;
} PineVertexAttribute;

typedef struct {
  PineShader *vertex_shader;
  PineShader *fragment_shader;
  PineVertexAttribute *attributes;
  size_t attribute_count;
  size_t vertex_stride;
} PinePipelineDesc;

// graphics backend interface (vtable pattern)
typedef struct {
  // context management
  PineGraphicsContext *(*create_context)(void);
  void (*destroy_context)(PineGraphicsContext *ctx);

  // swapchain management
  PineSwapchain *(*create_swapchain)(PineGraphicsContext *ctx,
                                     const PineSwapchainDesc *config);
  void (*destroy_swapchain)(PineSwapchain *swapchain);
  void (*resize_swapchain)(PineSwapchain *swapchain, uint32_t width,
                           uint32_t height);

  // rendering
  PineRenderPass *(*begin_render_pass)(PineSwapchain *swapchain,
                                       const PinePassAction *action);
  void (*end_render_pass)(PineRenderPass *pass);
  void (*present)(PineSwapchain *swapchain);

  // capabilities query
  void (*get_capabilities)(PineGraphicsContext *ctx,
                           PineGraphicsCapabilities *caps);

  // resource creation
  PineBuffer *(*create_buffer)(PineGraphicsContext *ctx,
                               const PineBufferDesc *desc);
  void (*destroy_buffer)(PineBuffer *buffer);

  PineShader *(*create_shader)(PineGraphicsContext *ctx,
                               const PineShaderDesc *desc);
  void (*destroy_shader)(PineShader *shader);

  PinePipeline *(*create_pipeline)(PineGraphicsContext *ctx,
                                   const PinePipelineDesc *desc);
  void (*destroy_pipeline)(PinePipeline *pipeline);

  // drawing
  void (*set_pipeline)(PineRenderPass *pass, PinePipeline *pipeline);
  void (*set_vertex_buffer)(PineRenderPass *pass, uint32_t index,
                            PineBuffer *vertex_buffer);
  void (*set_uniform_buffer)(PineRenderPass *pass, uint32_t index,
                             uint32_t offset, PineBuffer *uniform_buffer);
  void (*draw)(PineRenderPass *pass, uint32_t vertex_count,
               uint32_t first_vertex);
  void (*draw_indexed)(PineRenderPass *pass, PineBuffer *index_buffer,
                       uint32_t first_index, int32_t vertex_offset);
} PineGraphicsBackend;

// backend factory functions (implemented per platform)
PineGraphicsBackend *pine_create_metal_backend(void);
PineGraphicsBackend *pine_create_vulkan_backend(void);
PineGraphicsBackend *pine_create_d3d12_backend(void);

#ifdef __cplusplus
}
#endif

#endif // PINE_GRAPHICS_BACKEND_H
