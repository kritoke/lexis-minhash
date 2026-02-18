require "benchmark"
require "../src/lexis-minhash"

def probability_of_collision(s : Float64, b : Int32, r : Int32) : Float64
  1.0 - (1.0 - s**r)**b
end

def print_lsh_tuning(target_threshold : Float64, num_hashes : Int32)
  puts "Target Similarity: #{target_threshold} | Total Hashes: #{num_hashes}"
  puts "-" * 60
  printf("%-10s | %-10s | %-10s | %-15s\n", "Bands (b)", "Rows (r)", "Threshold", "Prob @ Target")

  (1..num_hashes).each do |band_count|
    next unless num_hashes % band_count == 0
    row_count = num_hashes // band_count

    calc_threshold = (1.0 / band_count)**(1.0 / row_count)
    prob_at_target = probability_of_collision(target_threshold, band_count, row_count)

    printf("%-10d | %-10d | %-10.3f | %-15.2f%%\n", band_count, row_count, calc_threshold, prob_at_target * 100)
  end
end

puts "=== LSH Parameter Tuning ==="
puts
print_lsh_tuning(target_threshold: 0.75, num_hashes: 100)
puts
puts "=== Performance Benchmark ==="
puts

sample_texts = [
  "The quick brown fox jumps over the lazy dog near the riverbank",
  "Apple announces revolutionary new iPhone with advanced camera technology",
  "Scientists discover breakthrough treatment for rare genetic disorders",
  "Stock markets rally as investors show renewed confidence in economy",
  "Local restaurant wins prestigious culinary award for innovative cuisine",
]

Benchmark.ips do |x|
  x.report("Engine.compute_signature") do
    sample_texts.each do |text|
      LexisMinhash::Engine.compute_signature(text)
    end
  end

  x.report("Engine.compute_signature (weighted)") do
    weights = {
      "quick" => 1.5_f64,
      "brown" => 2.0_f64,
      "jumps" => 1.8_f64,
      "river" => 2.5_f64,
    }
    sample_texts.each do |text|
      LexisMinhash::Engine.compute_signature(text, weights)
    end
  end

  x.report("Engine.compute_signature_slice") do
    sample_texts.each do |text|
      LexisMinhash::Engine.compute_signature_slice(text)
    end
  end
end

puts
puts "=== LSH Index Benchmark ==="
puts

# Test with larger dataset
test_docs = [] of String
100.times do |i|
  test_docs << "Document number #{i} with some unique content about technology"
end

index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)
test_docs.each_with_index { |text, i| index.add(i, text) }

Benchmark.ips do |x|
  x.report("LSHIndex.add (100 docs)") do
    idx = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)
    test_docs.each_with_index { |text, i| idx.add(i, text) }
  end

  x.report("LSHIndex.query") do
    test_docs.each { |text| index.query(text) }
  end

  x.report("LSHIndex.find_similar_pairs") do
    index.find_similar_pairs(threshold: 0.75)
  end
end

puts
puts "=== Load Factors ==="
puts "LSHIndex load factors per band: #{index.load_factors.map(&.round(3))}"

puts
puts "=== Weighted Overlap Benchmark ==="
puts

doc_a = {
  "machine"   => 0.8_f64,
  "learning"  => 0.9_f64,
  "data"      => 0.5_f64,
  "science"   => 0.7_f64,
  "algorithm" => 0.6_f64,
}

doc_b = {
  "machine"  => 0.8_f64,
  "learning" => 0.6_f64,
  "model"    => 0.7_f64,
  "neural"   => 0.5_f64,
  "network"  => 0.4_f64,
}

Benchmark.ips do |x|
  x.report("Similarity.weighted_overlap") do
    LexisMinhash::Similarity.weighted_overlap(doc_a, doc_b)
  end
end
