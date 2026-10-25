gem "minitest"
require "minitest/autorun"
require "digest"
require "tmpdir"
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require "bmp"

# bit-struct 0.15.0 was replaced by BMP::PackedStruct. These hashes were
# recorded from upstream bmp-ruby 0.1.1 running on bit-struct, so any byte
# drift in the replacement fails here.
class TestByteIdentical < Minitest::Test
  FILES  = File.join(File.expand_path(File.dirname(__FILE__)), "files")
  GOLDEN = File.readlines(File.join(FILES, "golden-bit-struct-0.15.0.sha256"))
             .reject { |l| l.start_with?("#") || l.strip.empty? }
             .map { |l| l.split.reverse }.to_h

  def test_golden_list_is_not_empty
    assert_equal 7, GOLDEN.size
  end

  GOLDEN.each do |bmp_name, sha|
    define_method("test_#{bmp_name.tr('.-', '__')}_matches_bit_struct_output") do
      Dir.mktmpdir do |dir|
        out = File.join(dir, bmp_name)
        BMP.png_to_bmp(File.join(FILES, "input", bmp_name.sub(/\.bmp\z/, ".png")), out)
        assert_equal sha, Digest::SHA256.file(out).hexdigest
      end
    end
  end
end
