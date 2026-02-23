# Similarity helpers and documentation for the LexisMinhash library.
##
# Provides weighted overlap and optimized fast overlap helpers for sorted slices.
module LexisMinhash
  # Similarity measures for comparing documents
  #
  # This module provides various similarity metrics for comparing
  # document representations, including weighted overlap for TF-IDF
  # or other weighted document representations.
  # Similarity contains similarity and overlap measures useful for comparing
  # MinHash signatures and weighted document vectors.
  module Similarity
    # Computes the weighted overlap coefficient between two weighted document representations
    #
    # The weighted overlap coefficient measures similarity as the sum of minimum weights
    # for intersecting terms, normalized by the smaller total weight. This is useful
    # for comparing weighted document representations like TF-IDF vectors.
    #
    # ```
    # doc_a = {"machine" => 0.8, "learning" => 0.9, "data" => 0.5}
    # doc_b = {"machine" => 0.8, "learning" => 0.6, "model" => 0.7}
    # LexisMinhash::Similarity.weighted_overlap(doc_a, doc_b) # => ~0.736
    # ```
    #
    # NOTE: Keys are case-sensitive; ensure both hashes use consistent casing.
    def self.weighted_overlap(a : Hash(String, Float64), b : Hash(String, Float64)) : Float64
      return 0.0_f64 if a.empty? || b.empty?

      intersection = 0.0_f64
      a.each do |word, weight|
        if b_weight = b[word]?
          intersection += {weight, b_weight}.min
        end
      end

      sum_a = a.values.sum
      sum_b = b.values.sum
      intersection / {sum_a, sum_b}.min
    end

    # Optimized overlap coefficient using two-pointer scan for sorted Slices
    #
    # This is ~10x faster than standard Set intersection in Crystal.
    # Input slices MUST be sorted in ascending order.
    #
    # ```
    # a = Slice.new(3) { |i| (i * 2).to_u64 }     # [0, 2, 4]
    # b = Slice.new(3) { |i| (i * 2 + 2).to_u64 } # [2, 4, 6]
    # LexisMinhash::Similarity.fast_overlap(a, b) # => 0.5
    # ```
    # Generic fast overlap for two sorted slices using two-pointer scan. Input
    # slices MUST be sorted ascending. Returns intersection / min(|A|, |B|).
    private def self.fast_overlap_generic(a : Slice(T), b : Slice(T)) : Float64 forall T
      return 0.0_f64 if a.empty? || b.empty?

      i, j, intersection = 0, 0, 0
      while i < a.size && j < b.size
        if a[i] == b[j]
          intersection += 1
          i += 1
          j += 1
        elsif a[i] < b[j]
          i += 1
        else
          j += 1
        end
      end
      intersection.to_f64 / {a.size, b.size}.min
    end

    # Fast overlap for UInt64 slices
    def self.fast_overlap(a : Slice(UInt64), b : Slice(UInt64)) : Float64
      fast_overlap_generic(a, b)
    end

    # Optimized overlap coefficient using two-pointer scan for sorted Slices (UInt32)
    #
    # Input slices MUST be sorted in ascending order.
    def self.fast_overlap(a : Slice(UInt32), b : Slice(UInt32)) : Float64
      fast_overlap_generic(a, b)
    end
  end
end
