# frozen_string_literal: true

require 'puma'

FORCE_AUTO_TRIM_TIME = 1.0

$log_file = File.open('/tmp/puma_2655.log', 'w')
at_exit { $log_file.close }

class BugLogger
  def self.log(msg, data={})
    thread_str = Thread.current.name.nil? ? Thread.current.inspect : Thread.current.name
    data = {
      pid: Process.pid,
      thread: thread_str,
    }.merge(data)
    data_str = data.map {|k, v| "#{k}=#{v.inspect}"}.join(" ")
    $log_file.puts("[#{Time.now}] #{msg} #{data_str}".strip)
    $log_file.flush
  end
end

class Puma::ThreadPool
  attr_accessor :control

  def busy_threads
    with_mutex do
      # --- DIFF STARTS HERE ---
      if @control
        BugLogger.log("busy_threads", {'@waiting': @waiting, '@spawned': @spawned, '@waiting': @waiting, '@todo.size': @todo.size, busy_threads: @spawned - @waiting + @todo.size})
      end
      # --- DIFF ENDS HERE ---
      @spawned - @waiting + @todo.size
    end
  end

  def spawn_thread
    @spawned += 1

    th = Thread.new(@spawned) do |spawned|
      Puma.set_thread_name 'threadpool %03i' % spawned
      # --- DIFF STARTS HERE ---
      if @control
        BugLogger.log("spawning thread", {'@spawned': @spawned})
      end
      # --- DIFF ENDS HERE ---
      todo  = @todo
      block = @block
      mutex = @mutex
      not_empty = @not_empty
      not_full = @not_full

      extra = @extra.map { |i| i.new }

      while true
        work = nil

        mutex.synchronize do
          while todo.empty?
            if @trim_requested > 0
              @trim_requested -= 1
              @spawned -= 1
              @workers.delete th

              # --- DIFF STARTS HERE ---
              if @control
                BugLogger.log("trimming thread", {'@spawned': @spawned, '@waiting': @waiting, '@trim_requested': @trim_requested})
              end
              # --- DIFF ENDS HERE ---

              Thread.exit
            end

            @waiting += 1
            if @out_of_band_pending && trigger_out_of_band_hook
              @out_of_band_pending = false
            end
            not_full.signal
            begin
              not_empty.wait mutex
            ensure
              @waiting -= 1
            end
          end

          work = todo.shift
        end

        if @clean_thread_locals
          ThreadPool.clean_thread_locals
        end

        begin
          # --- DIFF STARTS HERE ---
          if @control
            BugLogger.log("executing work", {'@spawned': @spawned, '@waiting': @waiting, 'todo.size': todo.size})
          end
          # --- DIFF ENDS HERE ---

          @out_of_band_pending = true if block.call(work, *extra)
        rescue Exception => e
          STDERR.puts "Error reached top of thread-pool: #{e.message} (#{e.class})"
        end
      end
    end

    @workers << th

    th
  end

  def <<(work)
    with_mutex do
      if @shutdown
        raise "Unable to add work while shutting down"
      end

      @todo << work

      # --- DIFF STARTS HERE ---
      if @control
        BugLogger.log("adding work", {'@spawned': @spawned, '@waiting': @waiting, '@todo.size': @todo.size})
      end

      if @waiting < @todo.size and @spawned < @max
        spawn_thread
      end

      @not_empty.signal
    end
  end

  def trim(force=false)
    with_mutex do
      free = @waiting - @todo.size

      # --- DIFF STARTS HERE ---
      if @control
        BugLogger.log("checking if thread trimming is needed", {free: free, '@spawned': @spawned, '@todo.size': @todo.size, '@waiting': @waiting, '@trim_requested': @trim_requested})
      end
      # --- DIFF ENDS HERE ---

      if (force or free > 0) and @spawned - @trim_requested > @min
        @trim_requested += 1

        # --- DIFF STARTS HERE ---
        if @control
          BugLogger.log("requesting thread trim", {free: free, '@spawned': @spawned, '@todo.size': @todo.size, '@waiting': @waiting, '@trim_requested': @trim_requested})
        end
        # --- DIFF ENDS HERE ---

        @not_empty.signal
      end
    end
  end

  # Override auto_trim! to enforce our own auto trim time in order to trigger
  # the bug faster.
  alias_method :_orig_auto_trim!, :auto_trim!
  def auto_trim!(_timeout)
    _orig_auto_trim!(FORCE_AUTO_TRIM_TIME)
  end
end

class Puma::Server
  def run(background=true, thread_name: 'server')
    BasicSocket.do_not_reverse_lookup = true

    @events.fire :state, :booting

    @status = :run

    @thread_pool = ThreadPool.new(
      @min_threads,
      @max_threads,
      ::Puma::IOBuffer,
      &method(:process_client)
    )

    # --- DIFF STARTS HERE ---
    # Set flag to enable custom logs in Puma::ThreadPool
    if @app.is_a?(Puma::App::Status)
      @thread_pool.control = true
    end
    # --- DIFF ENDS HERE ---

    @thread_pool.out_of_band_hook = @options[:out_of_band]
    @thread_pool.clean_thread_locals = @options[:clean_thread_locals]

    if @queue_requests
      @reactor = Reactor.new(@io_selector_backend, &method(:reactor_wakeup))
      @reactor.run
    end

    if @reaping_time
      @thread_pool.auto_reap!(@reaping_time)
    end

    if @auto_trim_time
      @thread_pool.auto_trim!(@auto_trim_time)
    end

    @check, @notify = Puma::Util.pipe unless @notify

    @events.fire :state, :running

    if background
      @thread = Thread.new do
        Puma.set_thread_name thread_name
        handle_servers
      end
      return @thread
    else
      handle_servers
    end
  end
end

port 9292
threads 1, 1
activate_control_app 'auto'
state_path '/tmp/puma_2655.yaml'
