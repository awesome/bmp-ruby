gem "minitest"
require "minitest/autorun"
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require "bmp"

# Opt-in field-by-field parity check against the original bit-struct gem.
# bit-struct is deliberately not a dependency; point at an unpacked copy:
#
#   gem fetch bit-struct -v 0.15.0 && gem unpack bit-struct-0.15.0.gem
#   BIT_STRUCT_LIB=$PWD/bit-struct-0.15.0/lib ruby -Ilib test/test_bit_struct_parity.rb
class TestBitStructParity < Minitest::Test
  LIB = ENV['BIT_STRUCT_LIB']

  def setup
    skip 'set BIT_STRUCT_LIB to run the bit-struct parity check' unless LIB
    self.class.load_bit_struct
  end

  def self.load_bit_struct
    return if defined?(::BitStruct)
    Object.const_set(:Fixnum, Integer) unless Object.const_defined?(:Fixnum) # removed in Ruby 3.2
    $LOADED_FEATURES << File.join(LIB, 'bit-struct', 'yaml.rb') # Syck-era YAML hooks, unused here
    $:.unshift LIB
    require 'bit-struct'
    src = File.read(File.join(File.dirname(__FILE__), '..', 'lib', 'bmp', 'obj.rb'))
    Object.class_eval(src.sub('module BMP', 'module ParityBMP').sub('BMP::PackedStruct', 'BitStruct'))
  end

  def test_obj_bytes_match_bit_struct_for_random_values
    rng = Random.new(20261025)
    unsigned = BMP::Obj.fields.select { |f| f.kind == :unsigned }
    200.times do
      ours   = BMP::Obj.new
      theirs = ParityBMP::Obj.new
      assert_equal theirs.to_s, ours.to_s
      unsigned.each do |f|
        v = rng.rand(-2**(f.length * 8 + 1)..2**(f.length * 8 + 1))
        ours.public_send("#{f.name}=", v)
        theirs.public_send("#{f.name}=", v)
      end
      sig = Array.new(rng.rand(0..3)) { rng.rand(32..126).chr }.join
      ours.signature = theirs.signature = sig
      data = Random.new(rng.rand(2**31)).bytes(rng.rand(0..64))
      ours.pixel_array = theirs.pixel_array = data
      assert_equal theirs.to_s.b, ours.to_s
      unsigned.each { |f| assert_equal theirs.public_send(f.name), ours.public_send(f.name), f.name }
    end
  end
end
