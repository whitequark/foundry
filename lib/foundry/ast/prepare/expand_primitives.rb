module Foundry
  module AST::Prepare
    class ExpandPrimitives < AST::Processor
      def on_call(node)
        receiver, name, arguments = node.children
        if name == :primitive &&
            receiver.type == :const_ref &&
            receiver.children.first == :Foundry

          primitive, *primitive_args = arguments.children
          node.updated(primitive.children.first,
            primitive_args)
        end
      end
    end
  end
end