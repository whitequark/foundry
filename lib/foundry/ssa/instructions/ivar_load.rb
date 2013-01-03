module Foundry
  class SSA::IvarLoadInsn < Furnace::SSA::GenericInstruction
    syntax do |s|
      s.operand :object
      s.operand :variable, VI::Symbol
    end
  end
end