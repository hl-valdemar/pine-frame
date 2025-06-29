#ifndef MACOS_BRIDGE_H
#define MACOS_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations
typedef struct PineWindow PineWindow;

// Window configuration structure
typedef struct {
  int32_t width;
  int32_t height;
  int32_t x;
  int32_t y;
  const char *title;
  bool resizable;
  bool visible;
} PineWindowConfig;

// Platform initialization
bool pine_platform_init(void);
void pine_platform_shutdown(void);

// Window management
PineWindow *pine_window_create(const PineWindowConfig *config);
void pine_window_destroy(PineWindow *window);
void pine_window_show(PineWindow *window);
void pine_window_hide(PineWindow *window);
bool pine_window_should_close(PineWindow *window);

// Event processing
void pine_platform_poll_events(void);

#ifdef __cplusplus
}
#endif

#endif // MACOS_BRIDGE_H
