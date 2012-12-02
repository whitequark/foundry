module Foundry::Interpreter
  class Base < Furnace::AST::Processor
    attr_reader :binding, :outer

    def initialize(executable, self_=nil, args=nil, block=nil, outer=nil)
      @executable   = executable
      @self, @args  = self_, args
      @block        = block

      @binding      = @executable.binding
      @outer        = outer

      @current_insn = nil
      @scope_stack  = []
    end

    #
    # Processing
    #

    def process(node)
      prev_current_insn = @current_insn
      @current_insn = node if node

      super
    ensure
      @current_insn = prev_current_insn
    end

    def handler_missing(node)
      raise "Missing handler for node\n#{node.inspect}"
    end

    #
    # Stack traces
    #

    def collect_backtrace_part(include_current)
      last_function = nil

      if include_current
        stack = @scope_stack + [ @current_insn ]
      else
        stack = @scope_stack
      end

      stack.map do |insn|
        if insn.function
          last_function = insn.function
        end

        BacktraceItem.new(insn.file, insn.line, last_function).freeze
      end.reverse.freeze
    end

    def collect_backtrace(include_current=true)
      if @outer
        ([ collect_backtrace_part(include_current) ] + @outer.collect_backtrace(false)).freeze
      else
        [ collect_backtrace_part(include_current) ].freeze
      end
    end

    def evaluate
      process @executable.code
    end

    #
    # Initial contexts
    #

    def on_self(node)
      @self
    end

    def on_args(node)
      @args
    end

    def on_proc_ref(node)
      @block
    end

    def on_const_base(node)
      VI::Object
    end

    #
    # Variables
    #

    def on_let(node)
      vars, *body = node.children

      old_env = @binding

      if @binding
        @binding = @binding.chain
      else
        @binding = VI.new_binding
      end

      vars.each do |name, value|
        @binding.define name, process(value)
      end

      @scope_stack.push(node)

      process_all(body).last || VI::NIL
    ensure
      @scope_stack.pop

      @binding = old_env
    end

    def on_var(node)
      var, = node.children

      @binding.apply(var)
    end

    def on_mut!(node)
      var, value = node.children

      @binding.mutate(var, process(value))
    end

    def on_eval_mut!(node)
      var, value = node.children

      unless @binding.defined?(var)
        @binding.define(var, VI::NIL)
      end

      @binding.mutate(var, process(value))
    end

    #
    # Control flow
    #

    def on_block(node)
      @scope_stack.push node

      process_all(node.children).last || VI::NIL
    ensure
      @scope_stack.pop
    end

    #
    # Tuples and de/composition
    #

    def on_array(node)
      result = []

      node.children.map do |elem|
        if elem.type == :splat
          value, = elem.children
          result += process(value).to_ary
        else
          result << process(elem)
        end
      end

      VI.new_tuple(result)
    end

    def on_array_ref(node)
      array_node, index = node.children
      array = process(array_node)

      array[index]
    end

    def on_array_fetch(node)
      array_node, index, default_node = node.children
      array = process(array)

      if index >= array.size || index < -array.size
        process(default_node)
      else
        array[index]
      end
    end

    def on_array_slice(node)
      array_node, from, to = node.children
      array = process(array_node)

      VI.new_tuple(array.to_a[from..to])
    end

    def on_array_bigger_than(node)
      array_node, length = node.children
      array = process(array_node)

      array.size > length ? VI::TRUE : VI::FALSE
    end

    def on_array_unshift(node)
      array, value = process_all(node.children)

      VI.new_tuple([ value ] + array.to_a)
    end

    #
    # Literals
    #

    def on_nil(node)
      VI::NIL
    end

    def on_false(node)
      VI::FALSE
    end

    def on_true(node)
      VI::TRUE
    end

    def on_symbol(node)
      value, = node.children
      VI.new_symbol(value)
    end

    def on_integer(node)
      value, = node.children
      VI.new_integer(value)
    end

    def on_string(node)
      value, = node.children
      VI.new_string(value)
    end

    #
    # Constants
    #

    def find_const_in(scopes, name)
      scopes.each do |scope|
        if scope.const_defined?(name, false)
          return scope.const_get(name, false)
        end
      end

      VI::UNDEF
    end

    def on_const_ref_in(node)
      cref_node, name = node.children

      cref = process(cref_node)
      if cref.size == 0
        cref = VI.new_tuple([ VI::Object ])
      end

      const = find_const_in(cref, name)
      if const == VI::UNDEF
        const = find_const_in(cref[0].ancestors, name)
      end

      unless const == VI::UNDEF
        const
      else
        raise Error.new(self, "uninitialized constant #{name}")
      end
    end

    def on_const_fetch(node)
      parent_node, name = node.children

      modulus = process(parent_node)

      if !modulus.is_a? VI::Module
        raise Error.new(self, "#{modulus.inspect}:#{modulus.class.name} is not a class/module")
      else
        const = modulus.const_get(name)

        if const == VI::UNDEF
          raise Error.new(self, "uninitialized constant #{name} for #{modulus.name}")
        else
          const
        end
      end
    end

    def on_const_declare(node)
      scope_node, name, value_node = node.children

      scope = process(scope_node)
      scope = VI::Object if scope.nil?

      value = process(value_node)

      if scope.const_defined?(name, false)
        raise Error.new(self, "already initialized constant #{name}")
      else
        scope.const_set(name, value)
      end
    end

    #
    # Classes and modules
    #

    def on_define_module(node)
      scope_node, name = node.children

      scope = process(scope_node)
      scope = VI::Object if scope.nil?

      modulus = scope.const_get(name)

      unless modulus == VI::UNDEF
        unless modulus.is_a? VI::Module
          raise Error.new(self, "#{name} is not a module")
        end
      else
        modulus = VI.new_module
        scope.const_set name, modulus
      end

      modulus
    end

    def on_define_class(node)
      scope_node, name, superclass_node = node.children

      if superclass_node.nil?
        superclass = VI::Object
      else
        superclass = process(superclass_node)
      end

      scope = process(scope_node)
      scope = VI::Object if scope.nil?

      klass = scope.const_get(name)

      unless klass == VI::UNDEF
        unless klass.is_a? VI::Class
          raise Error.new(self, "#{name} is not a class")
        end
      else
        klass = VI.new_class(superclass)
        scope.const_set name, klass
      end

      klass
    end

    #
    # Instance variables
    #

    def on_ivar(node)
      target_node, name_node = node.children

      process(target_node).
        instance_variable_get(process(name_node).value)
    end

    def on_iasgn(node)
      target_node, name_node, value_node = node.children

      process(target_node).
        instance_variable_set(process(name_node).value, process(value_node))
    end

    def on_ilist(node)
      target_node, = node.children

      process(target_node).
        instance_variables
    end

    #
    # Methods and closures
    #

    def on_def(node)
      target_node, name_node, body_node = node.children

      name = process(name_node).value

      proc = VI.new_proc(
          body_node.updated(nil, nil, function: name),
          @binding)

      target = process(target_node)
      target.define_method(name, proc)

      VI::NIL
    end

    def on_proc(node)
      body_node, = node.children

      VI.new_proc(
          body_node.updated(nil, nil, function: '<closure>'),
          @binding)
    end

    def on_alias(node)
      (to_name, ), (from_name, ) = node.children.map(&:children)
      definee = @binding.apply(:Defn)

      method = definee.instance_method(from_name)

      if method == VI::UNDEF && @binding.apply(:Defn).is_a?(VI::Module)
        method = definee.method(from_name)
      end

      if method == VI::UNDEF
        raise Error.new(self, "undefined method #{from_name} for #{definee.name}")
      end

      definee.define_method(to_name, method)

      VI::NIL
    end

    #
    # Calls
    #

    def on_call(node)
      receiver_node, name, arguments_node, block_node = node.children

      receiver  = process(receiver_node)
      arguments = process(arguments_node)
      block     = process(block_node)

      if receiver.respond_to? name
        receiver.method(name).call(receiver, arguments, block, self)
      else
        raise Error.new(self, "undefined method #{name} for #{receiver.class.name}")
      end
    end

    def on_proc_call(node)
      closure_node, arguments_node, block_node = node.children

      closure   = process(closure_node)
      arguments = process(arguments_node)
      block     = process(block_node)

      closure.call(self, arguments, block, self)
    end

    def on_check_arity(node)
      args_node, from, to = node.children
      args = process(args_node)

      if args.size < from || (!to.nil? && args.size > to)
        if from != to
          to = '.' if to.nil?
          raise Error.new(self, "wrong number of arguments (#{args.size} for #{from}..#{to})")
        else
          raise Error.new(self, "wrong number of arguments (#{args.size} for #{from})")
        end
      end

      VI::NIL
    end

    def on_check_block(node)
      block_node, = node.children
      block = process(block_node)

      if block.equal? VI::NIL
        raise Error.new(self, "no block given")
      end

      block
    end

    def on_of_caller_env(node)
      var_node, = node.children
      var = process(var_node).value

      @outer.env.apply(var)
    end

    #
    # Control flow
    #

    def on_if(node)
      cond_node, true_branch, false_branch = node.children

      cond_value = process(cond_node)

      if cond_value.equal?(VI::NIL) ||
           cond_value.equal?(VI::FALSE)

        process(false_branch)
      else
        process(true_branch)
      end
    end

    def process_loop(node, break_on)
      cond_node, body_node = node.children

      while true
        cond_value = process(cond_node)

        if cond_value.equal?(VI::NIL) ||
              cond_value.equal?(VI::FALSE)
          break VI::NIL if break_on == false
        else
          break VI::NIL if break_on == true
        end

        process(body_node)
      end
    end

    def on_while(node)
      process_loop(node, false)
    end

    def on_until(node)
      process_loop(node, true)
    end
  end
end