#ifndef MACOS_BRIDGE_H
#define MACOS_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// forward declarations
typedef struct PineWindow PineWindow;

// window configuration structure
typedef struct {
  int32_t width;
  int32_t height;
  int32_t x;
  int32_t y;
  const char *title;
  bool resizable;
  bool visible;
} PineWindowConfig;

// event types
typedef enum {
  PINE_EVENT_NONE = 0,
  PINE_EVENT_KEY_DOWN,
  PINE_EVENT_KEY_UP,
  PINE_EVENT_WINDOW_CLOSE,
} PineEventType;

// Key codes (macOS virtual key codes)
typedef enum {
  PINE_KEY_UNKNOWN = -1,
  PINE_KEY_A = 0,
  PINE_KEY_S = 1,
  PINE_KEY_D = 2,
  PINE_KEY_F = 3,
  PINE_KEY_H = 4,
  PINE_KEY_G = 5,
  PINE_KEY_Z = 6,
  PINE_KEY_X = 7,
  PINE_KEY_C = 8,
  PINE_KEY_V = 9,
  PINE_KEY_B = 11,
  PINE_KEY_Q = 12,
  PINE_KEY_W = 13,
  PINE_KEY_E = 14,
  PINE_KEY_R = 15,
  PINE_KEY_Y = 16,
  PINE_KEY_T = 17,
  PINE_KEY_1 = 18,
  PINE_KEY_2 = 19,
  PINE_KEY_3 = 20,
  PINE_KEY_4 = 21,
  PINE_KEY_6 = 22,
  PINE_KEY_5 = 23,
  PINE_KEY_9 = 25,
  PINE_KEY_7 = 26,
  PINE_KEY_8 = 28,
  PINE_KEY_0 = 29,
  PINE_KEY_O = 31,
  PINE_KEY_U = 32,
  PINE_KEY_I = 34,
  PINE_KEY_P = 35,
  PINE_KEY_ENTER = 36,
  PINE_KEY_L = 37,
  PINE_KEY_J = 38,
  PINE_KEY_K = 40,
  PINE_KEY_N = 45,
  PINE_KEY_M = 46,
  PINE_KEY_TAB = 48,
  PINE_KEY_SPACE = 49,
  PINE_KEY_BACKSPACE = 51,
  PINE_KEY_ESCAPE = 53,
  PINE_KEY_LEFT = 123,
  PINE_KEY_RIGHT = 124,
  PINE_KEY_DOWN = 125,
  PINE_KEY_UP = 126,
} PineKeyCode;

// event structure
typedef struct {
  PineEventType type;
  union {
    struct {
      PineKeyCode key;
      bool shift;
      bool control;
      bool opt;
      bool command; // macOS specific
    } key_event;
  } data;
} PineEvent;

// platform initialization
bool pine_platform_init(void);
void pine_platform_shutdown(void);

// window management
PineWindow *pine_window_create(const PineWindowConfig *config);
void pine_window_destroy(PineWindow *window);
void pine_window_show(PineWindow *window);
void pine_window_hide(PineWindow *window);
bool pine_window_should_close(PineWindow *window);
void pine_window_request_close(PineWindow *window);

// event processing
void pine_platform_poll_events(void);
bool pine_window_poll_event(PineWindow *window, PineEvent *event);

#ifdef __cplusplus
}
#endif

#endif // MACOS_BRIDGE_H
