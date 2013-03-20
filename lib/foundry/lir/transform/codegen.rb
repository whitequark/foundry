module Foundry
  class LIR::Transform::Codegen
    def run(translator)
      @lir    = translator.lir_module
      @llvm   = translator.llvm_module

      @types  = Hash.new { |h, type|  h[type]  = emit_type(type)    }
      @data   = Hash.new { |h, datum| h[datum] = emit_object(datum) }
      @values = Hash.new { |h, value| h[value] = emit_value(value)  }

      @phi_fixups = []

      bootstrap_types

      translator.each_function.each_with_index do |func, index|
        begin
          emit_function(func)
        rescue => e
          $stderr.puts "Failure while generating LLVM for function:"
          $stderr.puts func.pretty_print
          raise
        end
      end

      if (errors = @llvm.verify)
        puts "===== LLVM VERIFICATION FAILED ====="
        @llvm.dump
        puts errors
        puts "===== END LLVM VERIFICATION ====="
        exit!
      end
    end

    def int_ptr_type
      # 64 is a safe size for a pointer in LLVM.
      LLVM::Int64
    end

    def bootstrap_types
      {
        VI::NIL      => ['nil',   0b0000],
        VI::TRUE     => ['true',  0b0001],
        VI::FALSE    => ['false', 0b0010],
      }.each do |object, (name, address)|
        pin_object_at_addr(object, name, address)
      end

      { VI::TOPLEVEL => 'TOPLEVEL'
      }.each do |object, name|
        @data[object] = emit_object(object, name)
      end
    end

    def pin_object_at_addr(object, name, address)
      klass       = object.class

      llvm_imp_ty = LLVM::Type.struct([], false, "i.#{klass.name}")
      llvm_imp_ty.element_types = []
      @types[Type.klass(klass)] = llvm_imp_ty.pointer

      @data[object] = int_ptr_type.from_i(address).
            int_to_ptr(llvm_imp_ty.pointer)
    end

    def emit_class_body_type(klass)
      if klass.is_a?(VI::SingletonClass)
        if klass.object.is_a?(VI::Class)
          llvm_name = name("s", klass.object)
        else
          llvm_name = "s.#{klass.__id__}"
        end
      else
        llvm_name = name(nil, klass)
      end

      unless (llvm_ty = @llvm.types[llvm_name])
        llvm_ty = LLVM::Type.struct([], false, llvm_name)
        llvm_ty.element_types = [
            (emit_class_body_type(klass.superclass) unless klass.superclass.nil?),
        ].compact
      end

      llvm_ty
    end

    def emit_type(type)
      case type
      when Type.bottom
        LLVM::Type.void

      when Type::Tuple
        elements_ty      = type.element_types
        llvm_elements_ty = elements_ty.map { |ty| @types[ty] }

        LLVM::Type.struct(llvm_elements_ty,
            false)

      when Type::Binding
        var_types      = type.variable_types
        llvm_var_types = var_types.map { |ty| @types[ty] }

        if type.next
          LLVM::Type.struct([ @types[type.next] ] + llvm_var_types, false)
        else
          LLVM::Type.struct(llvm_var_types, false)
        end

      when Type::Ruby
        klass         = type.klass

        llvm_body_ty  = emit_class_body_type(klass)

        llvm_imp_name = "i.#{llvm_body_ty.name}"

        unless (llvm_imp_ty = @llvm.types[llvm_imp_name])
          llvm_imp_ty = LLVM::Type.struct([], false, llvm_imp_name)

          if klass == VI::Class
            llvm_klass_ptr_ty = llvm_imp_ty.pointer
          else
            llvm_klass_ptr_ty = @types[Type.klass(VI::Class)]
          end

          llvm_imp_ty.element_types = [
              llvm_klass_ptr_ty,
              llvm_body_ty,
          ]
        end

        llvm_imp_ty.pointer

      when Type::MachineInteger
        LLVM::Type.from_ptr(LLVM::C.int_type(type.width.value.to_int), :integer)

      else
        raise RuntimeError, "unable to lower type #{type.inspect}"
      end
    end

    def emit_object(object, name=nil)
      klass = object.class.unreified

      case
      when klass == VI::Tuple
        LLVM::ConstantStruct.const(
            object.to_a.map { |val| @data[val] })

      when klass == VI::Machine_Integer
        width   = object.class.specializations[VMSymbol.new(:width)].to_int
        signed  = object.class.specializations[VMSymbol.new(:signed)] == VI::TRUE

        llvm_ty = LLVM::Type.from_ptr(LLVM::C.int_type(width), :integer)

        LLVM::ConstantInt.from_ptr(
            LLVM::C.const_int(llvm_ty, object.value, signed ? 1 : 0))

      else
        if object.is_a?(VI::Class) && !object.name.nil?
          name = name(nil, object)
        end

        if name && (datum = @llvm.globals[name])
          datum
        else
          if object.singleton_class_defined?
            klass      = object.singleton_class
            klass_name = "S." + (name || object.__id__.to_s)
          else
            klass      = object.class
          end

          llvm_ptr_ty = @types[Type.klass(klass)]
          llvm_ty     = llvm_ptr_ty.element_type

          datum = @llvm.globals.add llvm_ty, name
          datum.initializer = LLVM::ConstantStruct.named_const(
              llvm_ty,
              [
                emit_object(klass, klass_name).bitcast_to(
                  @types[Type.klass(VI::Class)]),
                LLVM::Constant.null(emit_class_body_type(klass))
              ])

          datum
        end
      end
    end

    def emit_value(lir_value)
      case lir_value
      when LIR::Constant
        @data[lir_value.value]

      else
        raise RuntimeError, "unable to lower value #{lir_value}"
      end
    end

    def emit_function_decl(func)
      unless (decl = @llvm.functions[func.name])
        arguments_ty = func.arguments.map { |arg| @types[arg.type] }
        return_ty    = @types[func.return_type]

        decl = @llvm.functions.add(func.name, arguments_ty, return_ty)
      end

      decl
    end

    def emit_function(func)
      llvm_func = emit_function_decl(func)

      @phi_fixups.clear
      @values.clear

      func.arguments.each_with_index do |arg, index|
        llvm_arg = llvm_func.params[index]
        llvm_arg.name = arg.name
        @values[arg] = llvm_arg
      end

      func.each_basic_block do |block|
        @values[block] = llvm_func.basic_blocks.append(block.name)
      end

      func.each_basic_block do |block|
        llvm_block = @values[block]

        llvm_block.build do |builder|
          block.each_instruction do |insn|
            if (llvm_insn = emit_code(builder, insn))
              @values[insn] = llvm_insn
            end
          end
        end
      end

      @phi_fixups.each do |phi|
        llvm_phi = @values[phi]

        phi.operands.each do |basic_block, operand|
          llvm_phi.add_incoming({ @values[basic_block] => @values[operand] })
        end
      end
    end

    def emit_code(builder, insn)
      case insn
      when LIR::BindingInsn
        llvm_binding_ty = @types[insn.type]
        llvm_binding    = builder.alloca(llvm_binding_ty)

        unless insn.type.next.nil?
          llvm_next_binding_ptr = builder.gep(llvm_binding, indices([ 0, 0 ]))
          builder.store(@values[insn.next], llvm_next_binding_ptr)
        end

        llvm_binding

      when LIR::LvarStoreInsn, LIR::LvarLoadInsn
        binding_ty   = insn.binding.type
        llvm_binding = @values[insn.binding]

        insn.depth.times do
          llvm_binding = builder.gep(llvm_binding, indices([ 0, 0 ]))
          binding_ty   = binding_ty.next
        end

        if binding_ty.next
          llvm_lvar_ptr = builder.gep(llvm_binding,
                  indices([ 0, binding_ty.index_of(insn.variable) + 1 ]))
        else
          llvm_lvar_ptr = builder.gep(llvm_binding,
                  indices([ 0, binding_ty.index_of(insn.variable) ]))
        end

        case insn
        when LIR::LvarStoreInsn
          builder.store(@values[insn.value], llvm_lvar_ptr)
        when LIR::LvarLoadInsn
          builder.load(llvm_lvar_ptr)
        end

      when LIR::TupleInsn
        llvm_tuple_ty = @types[insn.type]

        insn.operands.each_with_index.reduce(
              LLVM::Constant.undef(llvm_tuple_ty)) do
                  |llvm_dst, (elem, dst_index)|

          builder.insert_value llvm_dst, @values[elem], dst_index
        end

      when LIR::TupleRefInsn
        builder.extract_value @values[insn.tuple], insn.index

      when LIR::TupleSliceInsn
        llvm_dst_ty = @types[insn.type]
        llvm_src    = @values[insn.tuple]

        insn.range.each_with_index.reduce(
              LLVM::Constant.undef(llvm_dst_ty)) do
                  |llvm_dst, (src_index, dst_index)|

          elem = builder.extract_value llvm_src, src_index
          builder.insert_value llvm_dst, elem, dst_index
        end

      when LIR::IntegerOpInsn
        llvm_left, llvm_right = @values[insn.left], @values[insn.right]

        case insn.operation
        when :+;  builder.add llvm_left, llvm_right
        when :-;  builder.sub llvm_left, llvm_right
        when :*;  builder.mul llvm_left, llvm_right
        when :/;  builder.div llvm_left, llvm_right

        when :<, :<=, :>, :>=, :==, :!=
          llvm_res = case insn.operation
          when :<;  builder.icmp :slt, llvm_left, llvm_right
          when :<=; builder.icmp :sle, llvm_left, llvm_right
          when :>;  builder.icmp :sgt, llvm_left, llvm_right
          when :>=; builder.icmp :sge, llvm_left, llvm_right
          when :==; builder.icmp :eq,  llvm_left, llvm_right
          when :!=; builder.icmp :ne,  llvm_left, llvm_right
          end

          pred_true  = @data[VI::TRUE].bitcast_to(@types[Type.klass(VI::Object)])
          pred_false = @data[VI::FALSE].bitcast_to(@types[Type.klass(VI::Object)])

          builder.select(llvm_res, pred_true, pred_false)

        else
          raise RuntimeError, "unable to lower IntegerOp #{insn.operation}"
        end

      when LIR::InvokeInsn
        fun_name  = insn.callee.value
        fun       = @lir[fun_name]

        llvm_fun  = emit_function_decl(fun)
        llvm_args = insn.arguments.map { |arg| @values[arg] }

        builder.call(llvm_fun, *llvm_args)

      when LIR::BranchInsn
        builder.br(@values[insn.target])

      when LIR::BranchIfInsn
        llvm_ptr  = @values[insn.condition]
        llvm_int  = builder.ptr2int(llvm_ptr, int_ptr_type)

        llvm_and  = builder.and(llvm_int, ~int_ptr_type.from_i(0b0010))
        llvm_cmp  = builder.icmp(:ne, llvm_and, int_ptr_type.from_i(0))

        builder.cond(llvm_cmp,
            @values[insn.true_target],
            @values[insn.false_target])

      when LIR::PhiInsn
        @phi_fixups << insn

        builder.phi(@types[insn.type], {})

      when LIR::ReturnInsn
        if insn.value_type == Type.bottom
          builder.ret_void
        else
          builder.ret(@values[insn.value])
        end

      when LIR::TraceInsn
        value          = insn.operands.first
        llvm_value     = @values[value]
        llvm_trace_fun = @llvm.functions.add("foundry.trace",
              [ int_ptr_type ], LLVM::Type.void)

        if value.type.is_a? Type::MachineInteger
          llvm_int_value = builder.sext(llvm_value, int_ptr_type)
        else
          llvm_int_value = builder.ptr2int(llvm_value, int_ptr_type)
        end

        builder.call(llvm_trace_fun, llvm_int_value)

        @data[VI::NIL]

      else
        raise RuntimeError, "cannot lower #{insn.class}"
      end
    end

    def name(prefix, entity, entity_name=nil)
      name = entity.name

      if name.nil?
        name = entity_name
      end

      if name.nil?
        name = entity.__id__
      else
        name = name.to_s.gsub(/::/, '.')
      end

      if prefix.nil?
        name.to_s
      else
        "#{prefix}.#{name}"
      end
    end

    def indices(values)
      values.map { |value| LLVM::Int32.from_i(value) }
    end
  end
end
