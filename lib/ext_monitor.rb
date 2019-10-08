require "monitor"
require "ext_monitor/version"
require "ext_monitor/ext_monitor"

module MonitorMixin
  class ConditionVariable
    remove_method :wait

    #
    # Releases the lock held in the associated monitor and waits; reacquires the lock on wakeup.
    #
    # If +timeout+ is given, this method returns after +timeout+ seconds passed,
    # even if no other thread doesn't signal.
    #
    def wait(timeout = nil)
      @monitor.__send__(:mon_check_owner)
      count = @monitor.__send__(:mon_exit_for_cond)
      begin
        @cond.wait(@monitor.instance_variable_get(:@mon_data).mutex_for_cond, timeout)
        return true
      ensure
        @monitor.__send__(:mon_enter_for_cond, count)
      end
    end
  end

  remove_method :mon_try_enter, :mon_enter, :mon_exit, :mon_locked?, :mon_owned?,
    :mon_synchronize, :mon_initialize, :mon_check_owner, :mon_enter_for_cond,
    :mon_exit_for_cond

  # Attempts to enter exclusive section.  Returns +false+ if lock fails.
  #
  def mon_try_enter
    (defined?(@mon_data) ? @mon_data : use_monitor_core).try_enter
  end

  # Enters exclusive section.
  #
  def mon_enter
    (defined?(@mon_data) ? @mon_data : use_monitor_core).enter
  end

  #
  # Leaves exclusive section.
  #
  def mon_exit
    (defined?(@mon_data) ? @mon_data : use_monitor_core).exit
  end

  #
  # Returns true if this monitor is locked by any thread
  #
  def mon_locked?
    (defined?(@mon_data) ? @mon_data : use_monitor_core).locked?
  end

  #
  # Returns true if this monitor is locked by current thread.
  #
  def mon_owned?
    (defined?(@mon_data) ? @mon_data : use_monitor_core).owned?
  end

  #
  # Enters exclusive section and executes the block.  Leaves the exclusive
  # section automatically when the block exits.  See example under
  # +MonitorMixin+.
  #
  def mon_synchronize(&b)
    @mon_data.enter
    begin
      yield
    ensure
      @mon_data.exit
    end
  end

  # Initializes the MonitorMixin after being included in a class or when an
  # object has been extended with the MonitorMixin
  def mon_initialize
    if defined?(@mon_data) && @mon_data_owner_object_id == self.object_id
      raise ThreadError, "already initialized"
    end
    @mon_data = ::Thread::MonitorCore.new
    @mon_data_owner_object_id = self.object_id
  end

  def mon_check_owner
    (defined?(@mon_data) ? @mon_data : use_monitor_core).check_owner
  end


  def mon_enter_for_cond(count)
    (defined?(@mon_data) ? @mon_data : use_monitor_core).enter_for_cond(Thread.current, count)
  end

  def mon_exit_for_cond
    (defined?(@mon_data) ? @mon_data : use_monitor_core).exit_for_cond
  end

  def use_monitor_core
    # below doesn't call RUBY_VM_CHECK_INTS
    @mon_data = ::Thread::MonitorCore.new(@mon_mutex, @mon_owner, @mon_count)
    @mon_data_owner_object_id = self.object_id
    remove_instance_variable(:@mon_mutex)
    remove_instance_variable(:@mon_owner)
    remove_instance_variable(:@mon_count)
    @mon_data
  end
end
class Monitor
  alias try_mon_enter mon_try_enter
  alias try_enter try_mon_enter
  alias enter mon_enter
  alias exit mon_exit
end
