#ifndef PINE_GRAPHICS_BACKEND_H
#define PINE_GRAPHICS_BACKEND_H

#include <stdbool.h>
#include <stdint.h>

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
  uint32_t width;
  uint32_t height;
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
} PineGraphicsBackend;

// backend factory functions (implemented per platform)
PineGraphicsBackend *pine_create_metal_backend(void);
PineGraphicsBackend *pine_create_vulkan_backend(void);
PineGraphicsBackend *pine_create_d3d12_backend(void);

#ifdef __cplusplus
}
#endif

#endif // PINE_GRAPHICS_BACKEND_H
