#ifndef PINE_GRAPHICS_BACKEND_H
#define PINE_GRAPHICS_BACKEND_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations
typedef struct PineGraphicsContext PineGraphicsContext;
typedef struct PineSwapchain PineSwapchain;
typedef struct PineRenderPass PineRenderPass;

// Backend capabilities
typedef struct {
  bool compute_shaders;
  bool tessellation;
  bool geometry_shaders;
  uint32_t max_texture_size;
  uint32_t max_vertex_attributes;
} PineGraphicsCapabilities;

// Swapchain config
typedef struct {
  void *native_window_handle; // NSWindow* on macOS, HWND on Windows, etc.
  uint32_t width;
  uint32_t height;
  bool vsync;
} PineSwapchainConfig;

// Render pass types (moved from macos.h)
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

// Graphics backend interface (vtable pattern)
typedef struct {
  // Context management
  PineGraphicsContext *(*create_context)(void);
  void (*destroy_context)(PineGraphicsContext *ctx);

  // Swapchain management
  PineSwapchain *(*create_swapchain)(PineGraphicsContext *ctx,
                                     const PineSwapchainConfig *config);
  void (*destroy_swapchain)(PineSwapchain *swapchain);
  void (*resize_swapchain)(PineSwapchain *swapchain, uint32_t width,
                           uint32_t height);

  // Rendering
  PineRenderPass *(*begin_render_pass)(PineSwapchain *swapchain,
                                       const PinePassAction *action);
  void (*end_render_pass)(PineRenderPass *pass);
  void (*present)(PineSwapchain *swapchain);

  // Frame management
  void (*begin_frame)(void);
  void (*end_frame)(void);

  // Capabilities query
  void (*get_capabilities)(PineGraphicsContext *ctx,
                           PineGraphicsCapabilities *caps);
} PineGraphicsBackend;

// Backend factory functions (implemented per platform)
PineGraphicsBackend *pine_create_metal_backend(void);
PineGraphicsBackend *pine_create_vulkan_backend(void);
PineGraphicsBackend *pine_create_d3d12_backend(void);

#ifdef __cplusplus
}
#endif

#endif // PINE_GRAPHICS_BACKEND_H
