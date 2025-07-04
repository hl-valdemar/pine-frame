#include "log.h"
#include <stdarg.h>
#include <stdio.h>

// enable logs in debug builds
#ifdef DEBUG
void pine_log(PineLogLevel level, const char *scope, const char *format, ...) {
  const char *level_str;
  switch (level) {
  case PINE_LOG_LEVEL_INFO:
    level_str = "info";
    break;
  case PINE_LOG_LEVEL_WARN:
    level_str = "warning";
    break;
  case PINE_LOG_LEVEL_ERROR:
    level_str = "error";
    break;
  case PINE_LOG_LEVEL_DEBUG:
    level_str = "debug";
    break;
  default:
    level_str = "debug";
    break;
  }

  // print to stderr with custom formatting
  fprintf(stderr, "[%s] (%s): ", level_str, scope);

  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);

  fprintf(stderr, "\n");
}
#else  // disable logs in release builds
void pine_log(PineLogLevel level, const char *scope, const char *format, ...) {}
#endif /* DEBUG */
