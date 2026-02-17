require "benchmark"
require "../src/lexis-minhash"

def probability_of_collision(s : Float64, b : Int32, r : Int32) : Float64
  1.0 - (1.0 - s**r)**b
end

def print_lsh_tuning(target_threshold : Float64, num_hashes : Int32)
  puts "Target Similarity: #{target_threshold} | Total Hashes: #{num_hashes}"
  puts "-" * 60
  printf("%-10s | %-10s | %-10s | %-15s\n", "Bands (b)", "Rows (r)", "Threshold", "Prob @ Target")

  (1..num_hashes).each do |b|
    next unless num_hashes % b == 0
    r = num_hashes // b

    calc_threshold = (1.0 / b)**(1.0 / r)
    prob_at_target = probability_of_collision(target_threshold, b, r)

    printf("%-10d | %-10d | %-10.3f | %-15.2f%%\n", b, r, calc_threshold, prob_at_target * 100)
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
      doc = LexisMinhash::SimpleDocument.new(text)
      LexisMinhash::Engine.compute_signature(doc)
    end
  end

  x.report("FastEngine.compute_signature") do
    sample_texts.each do |text|
      LexisMinhash::FastEngine.compute_signature(text)
    end
  end
end

puts
puts "=== LSH Index Benchmark ==="
puts

index = LexisMinhash::FastLSHIndex.new(bands: 20)
sample_texts.each_with_index { |text, i| index.add(i, text) }

Benchmark.ips do |x|
  x.report("FastLSHIndex.query") do
    sample_texts.each { |text| index.query(text) }
  end

  x.report("FastLSHIndex.find_similar_pairs") do
    index.find_similar_pairs(threshold: 0.75)
  end
end
