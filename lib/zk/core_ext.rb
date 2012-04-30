# @private
class ::Exception
  unless method_defined?(:to_std_format)
    def to_std_format
      ary = ["#{self.class}: #{message}"]
      ary.concat(backtrace || [])
      ary.join("\n\t")
    end
  end
end

# @private
class ::Thread
  def zk_mongoid_lock_registry
    self[:_zk_mongoid_lock_registry]
  end

  def zk_mongoid_lock_registry=(obj)
    self[:_zk_mongoid_lock_registry] = obj
  end
end

# @private
class ::Hash
  # taken from ActiveSupport 3.0.12, but we don't replace it if it exists
  unless method_defined?(:extractable_options?)
    def extractable_options?
      instance_of?(Hash)
    end
  end
end

# @private
class ::Array
  unless method_defined?(:extract_options!)
    def extract_options!
      if last.is_a?(Hash) && last.extractable_options?
        pop
      else
        {}
      end
    end
  end

  # backport this from 1.9.x to 1.8.7
  #
  # this obviously cannot replicate the copy-on-write semantics of the 
  # 1.9.3 version, and only provides a naieve filtering functionality.
  #
  # also, does not handle the "returning an enumerator" case
  unless method_defined?(:select!)
    def select!(&b)
      replace(select(&b))
    end
  end
end

# @private
module ::Kernel
  unless method_defined?(:silence_warnings)
    def silence_warnings
      with_warnings(nil) { yield }
    end
  end

  unless method_defined?(:with_warnings)
    def with_warnings(flag)
      old_verbose, $VERBOSE = $VERBOSE, flag
      yield
    ensure
      $VERBOSE = old_verbose
    end
  end
end

