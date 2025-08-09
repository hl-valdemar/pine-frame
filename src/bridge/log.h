// pine log levels
typedef enum {
  PINE_LOG_LEVEL_INFO,
  PINE_LOG_LEVEL_WARN,
  PINE_LOG_LEVEL_ERR,
  PINE_LOG_LEVEL_DEBUG,
} PineLogLevel;

// logging function
void pine_log(PineLogLevel level, const char *scope, const char *format, ...);
