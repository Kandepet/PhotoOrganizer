require 'ffi'

module PHash

  extend FFI::Library

  ffi_lib ENV.fetch('PHASH_LIB','pHash')

  # compute dct robust image hash
  #
  # param file string variable for name of file
  # param hash of type ulong64 (must be 64-bit variable)
  # return int value - -1 for failure, 1 for success
  #
  # int ph_dct_imagehash(const char* file, ulong64 &hash);
  #
  attach_function :ph_dct_imagehash, [:string, :pointer], :int, :blocking => true

  # no info in pHash.h
  #
  # int ph_hamming_distance(const ulong64 hash1,const ulong64 hash2);
  #
  attach_function :ph_hamming_distance, [:uint64, :uint64], :int, :blocking => true


  class Data

    attr_reader :hash, :length
    attr_accessor :path

    def initialize(hash, path, length = nil)
      @hash, @path, @length = hash, path, length
    end

    def similarity(other, *args)
      PHash.send("image_similarity", self, other, *args)
    end
    alias_method :%, :similarity

    def distance(other, *args)
      PHash.send("image_hamming_distance", self, other, *args)
    end
    alias_method :-, :similarity

    def to_s
       "#{@path} : #{@hash}"
    end
  end

  # Class to store image hash and compare to other
  class ImageHash < Data
  end

  class << self
    # Get image file hash using <tt>ph_dct_imagehash</tt>
    def image_hash(path)
      hash_p = FFI::MemoryPointer.new :ulong_long
      if -1 != ph_dct_imagehash(path.to_s, hash_p)
        hash = hash_p.get_uint64(0)
        hash_p.free

        ImageHash.new(hash, path)
      end
    end

    # Get distance between two image hashes using <tt>ph_hamming_distance</tt>
    def image_hamming_distance(hash_a, hash_b)
      hash_a.is_a?(ImageHash) or raise ArgumentError.new('hash_a is not an ImageHash')
      hash_b.is_a?(ImageHash) or raise ArgumentError.new('hash_b is not an ImageHash')

      ph_hamming_distance(hash_a.hash, hash_b.hash)
    end

    # Get similarity from hamming_distance
    # hamming distance is from 0 - 64. Greater the distance, more dis-similar they are.
    def image_similarity(hash_a, hash_b)
      1 - image_hamming_distance(hash_a, hash_b) / 64.0
    end
  end

end
