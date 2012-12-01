class Proc
=begin no singleton classes
  def self.allocate
    raise TypeError, "allocator undefined for Proc"
  end

  def self.new(&block)
    unless block
      block = FoundryRt.of_caller_env :Block

      unless block
        raise ArgumentError, "tried to create a Proc object without a block"
      end
    end

    block
  end
=end
  def call(*args, &block)
    FoundryRt.proc_call self, args, block
  end

  def binding
    @binding
  end

  def lambda_style!
    @lambda = true
  end

  def lambda?
    !!@lambda
  end
end