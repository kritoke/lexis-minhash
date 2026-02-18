module LexisMinhash
  # Similarity measures for comparing documents
  #
  # This module provides various similarity metrics for comparing
  # document representations, including weighted overlap for TF-IDF
  # or other weighted document representations.
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
  end
end
