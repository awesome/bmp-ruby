module BMP
  # Minimal fixed-layout binary struct backed by a binary String.
  #
  # Replaces the subset of the bit-struct gem (Ruby License) that bmp-ruby
  # and ico use, with the same class-level DSL and the same serialized bytes:
  #
  #   default_options :endian => :little
  #   unsigned :name, 8 | 16 | 32, 'description', :default => 0
  #   char     :name, bits,        'description', :default => 'BM'
  #   rest     :name,              'description'
  #   note     'free text'
  #
  # Semantics kept from BitStruct 0.15.0 (see test/test_packed_struct.rb):
  # instances are Strings (so Array#join and IO.write emit the bytes),
  # unsigned values wrap modulo 2**bits like Array#pack, char values are
  # truncated or NUL-padded to their width, `rest` holds the trailing bytes,
  # and `new(bytes)` overlays the given bytes onto the defaults.
  #
  # Only little-endian, byte-aligned fields are supported; anything else
  # raises ArgumentError at class-definition time instead of writing
  # different bytes.
  class PackedStruct < String
    class FieldNameError < StandardError; end

    Field = Struct.new(:name, :kind, :offset, :length, :default)

    UNSIGNED_FORMATS = { 8 => 'C', 16 => 'v', 32 => 'V' }.freeze

    class << self
      def fields
        @fields ||= (superclass.respond_to?(:fields) ? superclass.fields.dup : [])
      end

      def default_options(opts = nil)
        @default_options ||= { :endian => :little }
        return @default_options if opts.nil?
        check_endian!(opts[:endian])
        @default_options = @default_options.merge(opts)
      end

      def unsigned(name, bits, *args)
        opts = extract_opts(args)
        check_endian!(opts[:endian])
        raise ArgumentError, "unsigned :#{name} must be 8, 16 or 32 bits" unless UNSIGNED_FORMATS.key?(bits)
        add_field(name, :unsigned, bits / 8, opts.fetch(:default, 0))
      end

      def char(name, bits, *args)
        opts = extract_opts(args)
        raise ArgumentError, "char :#{name} must be a whole number of bytes" unless bits.is_a?(Integer) && bits > 0 && bits % 8 == 0
        add_field(name, :char, bits / 8, opts.fetch(:default, ''))
      end

      def rest(name, *_args)
        add_field(name, :rest, nil, '')
      end

      def note(*_args); end

      # Byte length of the fixed (non-rest) part.
      def round_byte_length
        fields.reject { |f| f.kind == :rest }.inject(0) { |sum, f| sum + f.length }
      end

      def initial_value
        fields.map { |f| encode(f, f.default) }.join.force_encoding(Encoding::BINARY)
      end

      def encode(field, value)
        case field.kind
        when :unsigned
          raise TypeError, "#{field.name} expects an Integer, got #{value.class}" unless value.is_a?(Integer)
          [value].pack(UNSIGNED_FORMATS[field.length * 8])
        when :char
          bytes = value.to_s.dup.force_encoding(Encoding::BINARY)
          bytes = bytes.byteslice(0, field.length)
          bytes + ("\0" * (field.length - bytes.bytesize))
        when :rest
          value.to_s.dup.force_encoding(Encoding::BINARY)
        end
      end

      private

      def extract_opts(args)
        args.last.is_a?(Hash) ? args.last : {}
      end

      def check_endian!(endian)
        return if endian.nil? || endian == :little
        raise ArgumentError, "only :little endian is supported (got #{endian.inspect})"
      end

      def add_field(name, kind, length, default)
        name = name.to_sym
        raise ArgumentError, "a field cannot follow the rest field" if fields.any? { |f| f.kind == :rest }
        if method_defined?(name) || fields.any? { |f| f.name == name }
          raise FieldNameError, "Field #{name} is already defined as a method."
        end

        field = Field.new(name, kind, round_byte_length, length, default)
        fields << field

        define_method(name) { read_field(field) }
        define_method("#{name}=") { |value| write_field(field, value) }
        field
      end
    end

    def initialize(value = nil)
      initial = self.class.initial_value
      if value
        bytes = value.to_s.dup.force_encoding(Encoding::BINARY)
        initial = bytes + (initial.byteslice(bytes.bytesize..-1) || '')
      end
      super(initial)
      force_encoding(Encoding::BINARY)
      yield self if block_given?
    end

    def to_h
      self.class.fields.each_with_object({}) { |f, h| h[f.name] = read_field(f) }
    end

    def inspect
      "#<#{self.class} " + to_h.map { |k, v| "#{k}=#{v.inspect}" }.join(', ') + '>'
    end

    private

    def read_field(field)
      case field.kind
      when :unsigned
        byteslice(field.offset, field.length).unpack(UNSIGNED_FORMATS[field.length * 8]).first
      when :char
        byteslice(field.offset, field.length)
      when :rest
        byteslice(field.offset..-1) || ''.b
      end
    end

    def write_field(field, value)
      bytes = self.class.encode(field, value)
      head  = byteslice(0, field.offset)
      tail  = field.kind == :rest ? '' : (byteslice((field.offset + field.length)..-1) || '')
      replace((head + bytes + tail).force_encoding(Encoding::BINARY))
      value
    end
  end
end
