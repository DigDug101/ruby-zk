module ZK
  module Locker
    # Common code for the shared and exclusive lock implementations
    # 
    # One thing to note about this implementation is that the API unfortunately
    # __does not__ follow the convention where bang ('!') methods raise
    # exceptions when they fail. This was an oversight on the part of the
    # author, and it may be corrected sometime in the future.
    #
    class LockerBase
      include ZK::Logging
      include ZK::Exceptions

      # @private
      attr_accessor :zk

      # our absolute lock node path
      #
      # @example 
      #
      #   '/_zklocking/foobar/__blah/lock000000007'
      #
      # @return [String]
      attr_reader :lock_path

      # @private
      attr_reader :root_lock_path

      # the data set for this lock at instantiation time
      attr_reader :data

      # Extracts the integer from the zero-padded sequential lock path
      #
      # @return [Integer] our digit
      # @private
      def self.digit_from_lock_path(path)
        path[/0*(\d+)$/, 1].to_i
      end

      # Create a new lock instance.
      #
      # @override new(client, name, root_lock_node=nil)
      #   Create a new lock instance with an optional alternate root 
      #
      #   @param [Client::Threaded] client a client instance
      #
      #   @param [String] name Unique name that will be used to generate a key.
      #     All instances created with the same `root_lock_node` and `name` will be
      #     holding the same lock.
      #
      #   @param [String] root_lock_node the root path on the server under which all
      #     locks will be generated, the default is Locker.default_root_lock_node
      #
      # @override new(client, name, opts={})
      #   @param [Client::Threaded] client a client instance
      #
      #   @param [String] name Unique name that will be used to generate a key.
      #     All instances created with the same `root_lock_node` and `name` will be
      #     holding the same lock.
      #
      #   @option opts [String] :root_lock_node (nil) the root path on the
      #     server under which all locks will be generated, the default is
      #     Locker.default_root_lock_node
      #
      #   @option opts [String] :data (nil) by default the lock node does not
      #     contain any data. Using this option, you can store data in the lock
      #     node that can be retrieved with the {#data} method. For now, data
      #     can only be set at Locker instantiation time.
      #
      def initialize(client, name, *args) 
        @zk     = client
        @path   = name

        opts = args.extract_options!

        @root_lock_node = args.first || opts[:root_lock_node] || Locker.default_root_lock_node

        if data = opts.fetch(:data, nil)
          @data = data.dup.freeze
        else
          @data = nil
        end

        @locked         = false
        @waiting        = false
        @lock_path      = nil
        @parent_stat    = nil
        @root_lock_path = "#{@root_lock_node}/#{@path.gsub("/", "__")}"

        @mutex  = Monitor.new
        @cond   = @mutex.new_cond
        @node_deletion_watcher = nil
      end

      # block caller until lock is aquired, then yield
      #
      # there is no non-blocking version of this method
      #
      def with_lock
        lock(true)
        yield
      ensure
        unlock
      end

      # the basename of our lock path
      #
      # @example
      #
      #   > locker.lock_path
      #   # => '/_zklocking/foobar/__blah/lock000000007'
      #   > locker.lock_basename
      #   # => 'lock000000007'
      #
      # @return [nil] if lock_path is not set
      # @return [String] last path component of our lock path
      def lock_basename
        synchronize { lock_path and File.basename(lock_path) }
      end

      # returns our current idea of whether or not we hold the lock, which does
      # not actually check the state on the server.
      #
      # The reason for the equivocation around _thinking_ we hold the lock is
      # to contrast our current state and the actual state on the server. If you
      # want to make double-triple certain of the state of the lock, use {#assert!}
      #
      # @return [true] if we hold the lock
      # @return [false] if we don't hold the lock
      #
      def locked?
        synchronize { !!@locked }
      end

      # * If this instance holds the lock {#locked? is true} we return true (as
      #   we have already succeeded in acquiring the lock)
      # * If this instance doesn't hold the lock, we'll do a check on the server 
      #   to see if there are any participants _who hold the lock and would
      #   prevent us from acquiring the lock_. 
      #   * If this instance could acquire the lock we will return true. 
      #   * If another client would prevent us from acquiring the lock, we return false. 
      #
      # @note It should be obvious, but there is no way to guarantee that
      #   between the time this method checks the server and taking any action to
      #   acquire the lock, another client may grab the lock before us (or
      #   converseley, another client may release the lock). This is simply meant
      #   as an advisory, and may be useful in some cases.
      #
      def acquirable?
        raise NotImplementedError
      end
      
      # @return [true] if we held the lock and this method has
      #   unlocked it successfully
      #
      # @return [false] if we did not own the lock.
      #
      # @note There is more than one way you might not "own the lock" 
      #   see [issue #34](https://github.com/slyphon/zk/issues/34)
      #
      def unlock
        rval = false
        @mutex.synchronize do
          if @locked
            logger.debug { "unlocking" }
            rval = cleanup_lock_path!
            @locked = false
            @node_deletion_watcher = nil
            @cond.broadcast
          end
        end
        rval
      end

      # (see #unlock)
      # @deprecated the use of unlock! is deprecated and may be removed or have
      #   its semantics changed in a future release
      def unlock!
        unlock
      end

      # @param blocking [true,false] if true we block the caller until we can obtain
      #   a lock on the resource
      # 
      # @return [true] if we're already obtained a shared lock, or if we were able to
      #   obtain the lock in non-blocking mode.
      #
      # @return [false] if we did not obtain the lock in non-blocking mode
      #
      # @return [void] if we obtained the lock in blocking mode. 
      #
      # @raise [InterruptedSession] raised when blocked waiting for a lock and
      #   the underlying client's session is interrupted. 
      #
      # @see ZK::Client::Unixisms#block_until_node_deleted more about possible execptions
      def lock(blocking=false)
        raise NotImplementedError
      end

      # (see #lock)
      # @deprecated the use of lock! is deprecated and may be removed or have
      #   its semantics changed in a future release
      def lock!(blocking=false)
        lock(blocking)
      end

      # The data contained in the owner's lock node.
      #
      # @abstract override in subclasses
      # @raise NotImplementedError by default
      #
      def owner_data
        raise NotImplementedError
      end

      # returns true if this locker is waiting to acquire lock 
      # this should be used in tests only. 
      #
      # @private
      def waiting? 
        @mutex.synchronize do
          !!(@node_deletion_watcher and @node_deletion_watcher.blocked?)
        end
      end

      # blocks the caller until this lock is blocked
      # @private
      def wait_until_blocked(timeout=nil)
        time_to_stop = timeout ? (Time.now + timeout) : nil

        @mutex.synchronize do
          if @node_deletion_watcher
            logger.debug { "@node_deletion_watcher already assigned, not waiting" }
          else
            logger.debug { "going to wait up to #{timeout} sec for a @node_deletion_watcher to be assigned" }

            @cond.wait(timeout) 
            raise "Timeout waiting for @node_deletion_watcher" unless @node_deletion_watcher
          end
        end
        logger.debug { "ok, @node_deletion_watcher: #{@node_deletion_watcher}, going to call wait_until_blocked" }

        @node_deletion_watcher.wait_until_blocked(timeout)
      end

      # This is for users who wish to check that the assumption is correct
      # that they actually still hold the lock. (check for session interruption,
      # perhaps a lock is obtained in one method and handed to another)
      #
      # This, unlike {#locked?} will actually go and check the conditions
      # that constitute "holding the lock" with the server.
      #
      # @raise [InterruptedSession] raised when the zk session has either
      #   closed or is in an invalid state.
      #
      # @raise [LockAssertionFailedError] raised if the lock is not held
      #
      # @example 
      #   
      #   def process_jobs
      #     @lock.with_lock do
      #       @jobs.each do |j| 
      #         @lock.assert!
      #         perform_job(j)
      #       end
      #     end
      #   end
      #
      #   def perform_job(j)
      #     puts "hah! he thinks we're workin!"
      #     sleep(60)
      #   end
      #
      def assert!
        @mutex.synchronize do
          raise LockAssertionFailedError, "have not obtained the lock yet"            unless locked?
          raise LockAssertionFailedError, "not connected"                             unless zk.connected?
          raise LockAssertionFailedError, "lock_path was #{lock_path.inspect}"        unless lock_path
          raise LockAssertionFailedError, "the lock path #{lock_path} did not exist!" unless zk.exists?(lock_path)
          raise LockAssertionFailedError, "the parent node was replaced!"             unless root_lock_path_same?
          raise LockAssertionFailedError, "we do not actually hold the lock"          unless got_lock?
        end
      end

      private
        def synchronize
          @mutex.synchronize { yield }
        end

        def digit_from(path)
          self.class.digit_from_lock_path(path)
        end

        def lock_children(watch=false)
          zk.children(root_lock_path, :watch => watch)
        end

        def ordered_lock_children(watch=false)
          lock_children(watch).tap do |ary|
            ary.sort! { |a,b| digit_from(a) <=> digit_from(b) }
          end
        end

        # root_lock_path is /_zklocking/foobar
        #
        def create_root_path!
          zk.mkdir_p(@root_lock_path)
        end

        # performs the checks that (according to the recipe) mean that we hold
        # the lock. used by (#assert!)
        #
        def got_lock?
          raise NotImplementedError
        end

        # prefix is the string that will appear in front of the sequence num,
        # defaults to 'lock'
        #
        # this method also saves the stat of root_lock_path at the time of creation
        # to ensure we don't accidentally remove a lock we don't own. see 
        # [rule #34](https://github.com/slyphon/zk/issues/34)...er, *issue* #34.
        #
        def create_lock_path!(prefix='lock')
          @mutex.synchronize do
            d = data || ''
            @lock_path = @zk.create("#{root_lock_path}/#{prefix}", d, :mode => :ephemeral_sequential)
            @parent_stat = @zk.stat(root_lock_path)
          end

          logger.debug { "got lock path #{@lock_path}" }
          @lock_path
        rescue NoNode
          create_root_path!
          retry
        end

        # if the root_lock_path has the same stat .ctime as the one
        # we cached when we created our lock path, then we can be sure
        # that we actually own the lock_path 
        #
        # see [issue #34](https://github.com/slyphon/zk/issues/34)
        #
        def root_lock_path_same?
          @mutex.synchronize do
            return false unless @parent_stat

            cur_stat = zk.stat(root_lock_path)  
            cur_stat.exists? and (cur_stat.ctime == @parent_stat.ctime)
          end
        end

        # we make a best-effort to clean up, this case is rife with race
        # conditions if there is a lot of contention for the locks, so if we
        # can't remove a path or if that path happens to not be empty we figure
        # either we got pwned or that someone else will run this same method
        # later and get to it
        #
        def cleanup_lock_path!
          rval = false

          @mutex.synchronize do
            if root_lock_path_same?
              logger.debug { "removing lock path #{@lock_path}" }

              zk.delete(@lock_path, :ignore => :no_node)
              zk.delete(root_lock_path, :ignore => [:not_empty, :no_node])
              rval = true
            end

            @lock_path = @parent_stat = nil
          end

          rval
        end
    end # LockerBase
  end # Locker
end # ZK
