module Foundry
  class SSA::TupleSliceInsn < Furnace::SSA::Instruction
    attr_accessor :from, :to

    syntax do |s|
      s.operand :tuple
    end

    def initialize(basic_block, from, to, operands=[], name=nil)
      super(basic_block, operands, name)
      @from, @to = from, to
    end

    def pretty_parameters(p)
      p.text @from, '..', @to, ','
    end

    def use_count
      1
    end

    def type
      VI::Foundry_Tuple
    end
  end
end