require 'rubygems'

require 'logger'
require 'zookeeper'
require 'forwardable'
require 'thread'
require 'monitor'
require 'set'

require 'zk/logging'
require 'zk/exceptions'
require 'zk/threadpool'
require 'zk/event_handler_subscription'
require 'zk/event_handler'
require 'zk/message_queue'
# require 'zk/locker_base'
require 'zk/locker'
require 'zk/extensions'
require 'zk/election'
require 'zk/mongoid'
require 'zk/client'
require 'zk/pool'
require 'zk/find'
require 'zk/group'

module ZK
  ZK_ROOT = File.expand_path('../..', __FILE__)

  KILL_TOKEN = Object.new unless defined?(KILL_TOKEN) 

  unless @logger
    @logger = Logger.new($stderr).tap { |n| n.level = Logger::ERROR }
  end

  # The logger used by the ZK library. uses a Logger stderr with Logger::ERROR
  # level. The only thing that should ever be logged are exceptions that are
  # swallowed by background threads.
  #
  # You can change this logger by setting ZK#logger= to an object that
  # implements the stdllb Logger API.
  #
  def self.logger
    @logger
  end

  # Assign the Logger instance to be used by ZK
  def self.logger=(logger)
    @logger = logger
  end

  # Create a new ZK::Client instance. If no arguments are given, the default
  # config of 'localhost:2181' will be used. Otherwise all args will be passed
  # to ZK::Client#new
  #
  # if a block is given, it will be yielded the client *before* the connection
  # is established, this is useful for registering connected-state handlers.
  #
  def self.new(*args, &block)
    # XXX: might need to do some param parsing here
   
    opts = args.pop if args.last.kind_of?(Hash)
    args = %w[localhost:2181] if args.empty?

    # ignore opts for now
    Client.new(*args, &block)
  end

  # Like new, yields a connection to the given block and closes it when the
  # block returns
  def self.open(*args)
    cnx = new(*args)
    yield cnx
  ensure
    cnx.close! if cnx
  end

  # creates a new ZK::Pool::Bounded with the default options.
  def self.new_pool(host, opts={})
    ZK::Pool::Bounded.new(host, opts)
  end

  # Eventually this will implement proper File.join-like behavior, but only
  # using the '/' char for a separator. for right now, this simply delegates to
  # File.join
  #--
  # like File.join but ignores $INPUT_RECORD_SEPARATOR (i.e. $/, which is
  # platform dependent) and only uses the '/' character
  def self.join(*paths)
    File.join(*paths)
  end

  protected
    def self.chomp_sep(str)
      p = (p[0] == ?/ ) ? p[1..-1] : p
      p = (p[-1] == ?/) ? p[0..-2] : p
    end
end

