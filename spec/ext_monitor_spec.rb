RSpec.describe ExtMonitor do
  it "has a version number" do
    expect(ExtMonitor::VERSION).not_to be nil
  end

  describe "Monitor" do
    describe "mon_enter" do
      it "serializes processing" do
        monitor = Monitor.new
        ary = []
        queue = Queue.new
        th = Thread.start {
          queue.pop
          monitor.enter
          for i in 6 .. 10
            ary.push(i)
            Thread.pass
          end
          monitor.exit
        }
        th2 = Thread.start {
          monitor.enter
          queue.enq(nil)
          for i in 1 .. 5
            ary.push(i)
            Thread.pass
          end
          monitor.exit
        }
        [th, th2].map(&:join)
        expect((1..10).to_a).to eq ary
      end

      it "can enter again after a thread is killed without exit" do
        monitor = Monitor.new
        th = Thread.start {
          monitor.enter
          Thread.current.kill
          monitor.exit
        }
        th.join
        monitor.enter
        monitor.exit
        th2 = Thread.start {
          monitor.enter
          monitor.exit
        }
        [th, th2].map(&:join)
      end
    end

    describe "mon_synchronize" do
      it do
        monitor = Monitor.new
        ary = []
        queue = Queue.new
        th = Thread.start {
          queue.pop
          monitor.synchronize do
            for i in 6 .. 10
              ary.push(i)
              Thread.pass
            end
          end
        }
        th2 = Thread.start {
          monitor.synchronize do
            queue.enq(nil)
            for i in 1 .. 5
              ary.push(i)
              Thread.pass
            end
          end
        }
        [th, th2].map(&:join)
        expect((1..10).to_a).to eq ary
      end

      it "can synchronize again after a thread is killed without exit" do
        monitor = Monitor.new
        ary = []
        queue = Queue.new
        t1 = Thread.start {
          queue.pop
          monitor.synchronize {
            ary << :t1
          }
        }
        t2 = Thread.start {
          queue.pop
          monitor.synchronize {
            ary << :t2
          }
        }
        t3 = Thread.start {
          monitor.synchronize do
            queue.enq(nil)
            queue.enq(nil)
            expect([]).to eq ary
            t1.kill
            t2.kill
            ary << :main
          end
          expect([:main]).to eq ary
        }
        [t1, t2, t3].map(&:join)
      end
    end

    describe "mon_try_enter" do
      it do
        monitor = Monitor.new
        queue1 = Queue.new
        queue2 = Queue.new
        th = Thread.start {
          queue1.deq
          monitor.enter
          queue2.enq(nil)
          queue1.deq
          monitor.exit
          queue2.enq(nil)
        }
        th2 = Thread.start {
          expect(monitor.try_enter).to be true
          monitor.exit
          queue1.enq(nil)
          queue2.deq
          expect(monitor.try_enter).to be false
          queue1.enq(nil)
          queue2.deq
          expect(monitor.try_enter).to be true
        }
        [th, th2].map(&:join)
      end

      it "can try_enter again after a thread is killed without exit" do
        monitor = Monitor.new
        th = Thread.start {
          expect(monitor.try_enter).to be true
          Thread.current.kill
          monitor.exit
        }
        th.join
        expect(monitor.try_enter).to be true
        monitor.exit
        th2 = Thread.start {
          expect(monitor.try_enter).to be true
          monitor.exit
        }
        [th, th2].map(&:join)
      end
    end

    describe "mon_locked? and mon_owned?" do
      it do
        monitor = Monitor.new
        queue1 = Queue.new
        queue2 = Queue.new
        th = Thread.start {
          monitor.enter
          queue1.enq(nil)
          queue2.deq
          monitor.exit
          queue1.enq(nil)
        }
        queue1.deq
        expect(monitor.mon_locked?).to be true
        expect(!monitor.mon_owned?).to be true

        queue2.enq(nil)
        queue1.deq
        expect(!monitor.mon_locked?)

        monitor.enter
        expect(monitor.mon_locked?).to be true
        expect(monitor.mon_owned?).to be true
        monitor.exit

        monitor.synchronize do
          expect(monitor.mon_locked?).to be true
          expect(monitor.mon_owned?).to be true
        end
        th.join
      end
    end

    describe "new_cond" do
      it "works" do
        monitor = Monitor.new
        cond = monitor.new_cond

        a = "foo"
        queue1 = Queue.new
        th = Thread.start do
          queue1.deq
          monitor.synchronize do
            a = "bar"
            cond.signal
          end
        end
        th2 = Thread.start do
          monitor.synchronize do
            queue1.enq(nil)
            expect(a).to eq "foo"
            result1 = cond.wait
            expect(result1).to be true
            expect(a).to eq "bar"
          end
        end
        [th, th2].map(&:join)
      end
    end

    describe "test_timedwait" do
      it do
        monitor = Monitor.new
        cond = monitor.new_cond
        b = "foo"
        queue2 = Queue.new
        th = Thread.start do
          queue2.deq
          monitor.synchronize do
            b = "bar"
            cond.signal
          end
        end
        th2 = Thread.start do
          monitor.synchronize do
            queue2.enq(nil)
            expect(b).to eq "foo"
            result2 = cond.wait(0.1)
            expect(result2).to be true
            expect(b).to eq "bar"
          end
        end
        [th, th2].map(&:join)
      end

      it do
        monitor = Monitor.new
        cond = monitor.new_cond
        c = "foo"
        queue3 = Queue.new
        th = Thread.start do
          queue3.deq
          monitor.synchronize do
            c = "bar"
            cond.signal
          end
        end
        th2 = Thread.start do
          monitor.synchronize do
            expect(c).to eq "foo"
            result3 = cond.wait(0.1)
            expect(result3).to be true # wait always returns true in Ruby 1.9
            expect(c).to eq "foo"
            queue3.enq(nil)
            result4 = cond.wait
            expect(result4).to be true
            expect(c).to eq "bar"
          end
        end
        [th, th2].map(&:join)
      end
    end

    describe "wait and interrupt" do
      it "works even if with interrupts" do
        monitor = Monitor.new
        queue = Queue.new
        cond = monitor.new_cond
        monitor.define_singleton_method(:mon_enter_for_cond) do |*args|
          queue.deq
          super(*args)
        end
        th = Thread.start {
          monitor.synchronize do
            begin
              cond.wait(1)
            rescue Interrupt
              monitor.instance_variable_get(:@mon_data).owner
            end
          end
        }
        sleep(0.1)
        th.raise(Interrupt)
        queue.enq(nil)
        expect(th.value).to eq th
      end
    end
  end
end
