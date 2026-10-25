gem "minitest"
require "minitest/autorun"
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require "bmp"

class TestPackedStruct < Minitest::Test
  class Sample < BMP::PackedStruct
    default_options :endian => :little
    unsigned :fa, 8
    unsigned :fb, 16, 'two bytes', :default => 7
    char     :fc, 16, 'two chars', :default => 'BM'
    unsigned :fd, 32
    rest     :fr, 'trailing bytes'
    note     'ignored'
  end

  def test_defaults_pack_little_endian
    s = Sample.new
    assert_equal "\x00\x07\x00BM\x00\x00\x00\x00".b, s.to_s
    assert_equal Encoding::BINARY, s.encoding
    assert_equal 9, Sample.round_byte_length
  end

  def test_is_a_string_for_join_and_io_write
    assert_kind_of String, Sample.new
    assert_equal Sample.new.to_s * 2, [Sample.new, Sample.new].join
  end

  def test_unsigned_wraps_like_bit_struct
    s = Sample.new
    { 256 => [0, 256], 257 => [1, 257], -1 => [255, 4294967295], 65536 => [0, 65536], 2**32 => [0, 0] }.each do |v, (fa, fd)|
      s.fa = v
      s.fd = v
      assert_equal [fa, fd], [s.fa, s.fd], "value #{v}"
    end
  end

  def test_unsigned_rejects_non_integers
    assert_raises(TypeError) { Sample.new.fa = nil }
    assert_raises(TypeError) { Sample.new.fa = 3.7 }
  end

  def test_char_pads_and_truncates
    s = Sample.new
    s.fc = 'A'
    assert_equal "A\x00".b, s.fc
    s.fc = 'ABC'
    assert_equal 'AB', s.fc
  end

  def test_rest_round_trips_and_new_overlays_defaults
    s = Sample.new
    s.fr = 'hello'
    assert_equal 'hello', s.fr
    copy = Sample.new(s.to_s)
    assert_equal ['hello', 7], [copy.fr, copy.fb]
    assert_equal [1, 7], [Sample.new("\x01".b).fa, Sample.new("\x01".b).fb]
  end

  def test_setters_do_not_disturb_neighbours
    s = Sample.new
    s.fr = 'tail'
    s.fd = 0x01020304
    assert_equal ["\x04\x03\x02\x01".b, 'tail'], [s.to_s[5, 4], s.fr]
  end

  def test_unsupported_layouts_raise
    assert_raises(ArgumentError) { Class.new(BMP::PackedStruct) { unsigned :x, 24 } }
    assert_raises(ArgumentError) { Class.new(BMP::PackedStruct) { unsigned :x, 16, nil, :endian => :big } }
    assert_raises(ArgumentError) { Class.new(BMP::PackedStruct) { rest :r; unsigned :x, 8 } }
    assert_raises(BMP::PackedStruct::FieldNameError) { Class.new(BMP::PackedStruct) { unsigned :size, 8 } }
  end
end
