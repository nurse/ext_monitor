#include "ext_monitor.h"

VALUE rb_mExtMonitor;

void
Init_ext_monitor(void)
{
  rb_mExtMonitor = rb_define_module("ExtMonitor");
}
