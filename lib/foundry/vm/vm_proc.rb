module Foundry
  class VMProc < VMObject
    attr_reader :code, :binding, :lambda

    define_mapped_ivars :binding, :lambda

    def vm_initialize(code, binding)
      @code    = code
      @binding = binding
      @lambda  = VI::FALSE
    end

    def lambda?
      @lambda == VI::TRUE
    end

    def call(self_, arguments, block, outer)
      Runtime.interpreter.
        new(self, self_, arguments, block, outer).
        evaluate
    end

    def inspect
      "{Proc}"
    end
  end
end