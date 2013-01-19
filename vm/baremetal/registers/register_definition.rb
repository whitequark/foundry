module Registers
  class RegisterDefinition
    def initialize(Class klass)
      @class  = klass
      @offset = 0
    end

    def reserved(Integer size)
      @offset += size
    end

    FLAG_TYPES = [:r, :w, :rw, :r_c0, :r_c1]

    def flag(Symbol name, Symbol type)
      check_type(type, FLAG_TYPES)

      mask = 1 << @offset

      @class.define_method(name) do
        (self.value & mask) ? true : false
      end if r?(type)

      @class.define_method(:"#{name}=") do |new_value|
        self.value = (self.value & ~mask) | (new_value ? mask : 0)
      end if w?(type)

      @class.define_method(:"clear_#{name}") do
        self.value = mask
      end if c1?(type)

      @class.define_method(:"clear_#{name}") do
        self.value &= ~mask
      end if c0?(type)

      @offset += 1
    end

    FIELD_TYPES = [:r, :w, :rw]

    def field(Symbol name, Symbol type, Integer width)
      check_type(type, FIELD_TYPES)

      int_ty = Integer.reify(width: width)

      mask   = (2 ** width) - 1
      offset = @offset

      @class.define_method(name) do || => int_ty
        (self.value & mask) >> offset
      end if r?(type)

      @class.define_method(:"#{name}=") do |int_ty new_value|
        self.value = (self.value & ~mask) | ((new_value << offset) & mask)
      end if w?(type)

      @offset += width
    end

    protected

    def check_type(type, list)
      unless list.include?(type)
        raise ArgumentError, "Invalid field type #{type}"
      end
    end

    def r?(type)
      [:r, :rw, :r_c0, :r_c1].include? type
    end

    def w?(type)
      [:w, :rw].include? type
    end

    def c0?(type)
      type == :r_c0
    end

    def c1?(type)
      type == :r_c1
    end
  end
end