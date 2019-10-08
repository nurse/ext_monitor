#include "ext_monitor.h"

struct monitor_core {
    long count;
    const VALUE owner;
    const VALUE mutex;
};

static void
mcore_mark(void *ptr)
{
    struct monitor_core *mc = ptr;
    rb_gc_mark(mc->owner);
    rb_gc_mark(mc->mutex);
}

static size_t
mcore_memsize(const void *ptr)
{
    return sizeof(struct monitor_core);
}

static const rb_data_type_t mcore_data_type = {
    "thread/monitor_data",
    {mcore_mark, RUBY_TYPED_DEFAULT_FREE, mcore_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static VALUE
mcore_alloc(VALUE klass)
{
    struct monitor_core *mc;
    VALUE obj;

    obj = TypedData_Make_Struct(klass, struct monitor_core, &mcore_data_type, mc);
    RB_OBJ_WRITE(obj, &mc->mutex, Qnil);
    RB_OBJ_WRITE(obj, &mc->owner, Qnil);
    mc->count = 0;

    return obj;
}

static struct monitor_core *
mcore_ptr(VALUE mcore)
{
    struct monitor_core *mc;
    TypedData_Get_Struct(mcore, struct monitor_core, &mcore_data_type, mc);
    return mc;
}

/*
 *  call-seq:
 *     MonitorCore.new
 *     MonitorCore.new(mutex, owner, count)
 *
 * returns MonitorCore object
 */
static VALUE
mcore_init(int argc, VALUE *argv, VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);

    if (argc == 0) {
        RB_OBJ_WRITE(mcore, &mc->mutex, rb_mutex_new());
        RB_OBJ_WRITE(mcore, &mc->owner, Qnil);
        mc->count = 0;
    }
    else if(argc == 3) {
        RB_OBJ_WRITE(mcore, &mc->mutex, argv[0]);
        RB_OBJ_WRITE(mcore, &mc->owner, argv[1]);
        mc->count = NUM2LONG(argv[2]);
    }
    else {
        rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 0 or 3)", argc);
    }

    return mcore;
}

static int
mc_owner_p(struct monitor_core *mc)
{
    return mc->owner == rb_thread_current();
}

static VALUE
mcore_try_enter(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);

    if (!mc_owner_p(mc)) {
        if (!rb_mutex_trylock(mc->mutex)) {
            return Qfalse;
        }
        RB_OBJ_WRITE(mcore, &mc->owner, rb_thread_current());
        mc->count = 0;
    }
    mc->count += 1;
    return Qtrue;
}

static VALUE
mcore_enter(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    if (!mc_owner_p(mc)) {
        rb_mutex_lock(mc->mutex);
        RB_OBJ_WRITE(mcore, &mc->owner, rb_thread_current());
        mc->count = 0;
    }
    mc->count++;
    return Qnil;
}

static VALUE
mcore_exit(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    mc->count--;
    if (mc->count == 0) {
        RB_OBJ_WRITE(mcore, &mc->owner, Qnil);
        rb_mutex_unlock(mc->mutex);
    }
    return Qnil;
}

static VALUE
mcore_locked_p(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    return rb_mutex_locked_p(mc->mutex);
}

static VALUE
mcore_owned_p(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    return (rb_mutex_locked_p(mc->mutex) && mc_owner_p(mc)) ? Qtrue : Qfalse;
}

static VALUE
mcore_owner(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    return mc->owner;
}

static VALUE
mcore_check_owner(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    if (!mc_owner_p(mc)) {
        rb_raise(rb_eThreadError, "current thread not owner");
    }
    return Qnil;
}

static VALUE
mcore_enter_for_cond(VALUE mcore, VALUE target_thread, VALUE count)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    RB_OBJ_WRITE(mcore, &mc->owner, target_thread);
    mc->count = NUM2LONG(count);
    return Qnil;
}

static VALUE
mcore_exit_for_cond(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    long cnt = mc->count;
    if (!mc_owner_p(mc)) {
        rb_raise(rb_eThreadError, "current thread not owner");
    }
    RB_OBJ_WRITE(mcore, &mc->owner, Qnil);
    mc->count = 0;
    return LONG2NUM(cnt);
}

static VALUE
mcore_mutex_for_cond(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    return mc->mutex;
}

#if 0
static VALUE
mcore_sync_body(VALUE mcore)
{
    return rb_yield_values(0);
}

static VALUE
mcore_sync_ensure(VALUE mcore)
{
    return mcore_exit(mcore);
}

static VALUE
mcore_synchronize(VALUE mcore)
{
    mcore_enter(mcore);
    return rb_ensure(mcore_sync_body, mcore, mcore_sync_ensure, mcore);
}
#endif

/*
 *  call-seq:
 *     monitor_core.inspect   -> string
 *
 */
VALUE
mcore_inspect(VALUE mcore)
{
    struct monitor_core *mc = mcore_ptr(mcore);
    return rb_sprintf("#<%s:%p mutex:%"PRIsVALUE" owner:%"PRIsVALUE" count:%ld>",
            rb_obj_classname(mcore), (void*)mcore, mc->mutex, mc->owner, mc->count);
}

void
Init_ext_monitor(void)
{
    /* Thread::MonitorCore (internal data for Monitor) */
    VALUE rb_cMonitorCore = rb_define_class_under(rb_cThread, "MonitorCore", rb_cObject);
    rb_define_alloc_func(rb_cMonitorCore, mcore_alloc);
    rb_define_method(rb_cMonitorCore, "initialize", mcore_init, -1);
    rb_define_method(rb_cMonitorCore, "try_enter", mcore_try_enter, 0);
    rb_define_method(rb_cMonitorCore, "enter", mcore_enter, 0);
    rb_define_method(rb_cMonitorCore, "exit", mcore_exit, 0);
    rb_define_method(rb_cMonitorCore, "locked?", mcore_locked_p, 0);
    rb_define_method(rb_cMonitorCore, "owned?", mcore_owned_p, 0);
    rb_define_method(rb_cMonitorCore, "owner", mcore_owner, 0);
    rb_define_method(rb_cMonitorCore, "check_owner", mcore_check_owner, 0);
    rb_define_method(rb_cMonitorCore, "enter_for_cond", mcore_enter_for_cond, 2); // thread, count
    rb_define_method(rb_cMonitorCore, "exit_for_cond", mcore_exit_for_cond, 0);
    rb_define_method(rb_cMonitorCore, "mutex_for_cond", mcore_mutex_for_cond, 0);
#if 0
    // Ruby definition is faster than C-impl now.
    rb_define_method(rb_cMonitorCore, "synchronize", mcore_synchronize, 0);
#endif
    rb_define_method(rb_cMonitorCore, "inspect", mcore_inspect, 0);
}
