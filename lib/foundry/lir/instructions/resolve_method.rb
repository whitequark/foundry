module Foundry
  class LIR::ResolveMethodInsn < Furnace::SSA::Instruction
    syntax do |s|
      s.operand :receiver
      s.operand :method,    VI::Symbol
    end

    def type
      LIR::Function
    end
  end
end