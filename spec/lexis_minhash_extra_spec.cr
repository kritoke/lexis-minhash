require "spec"
require "../src/lexis-minhash"

describe "ShingleRoller" do
  it "rolls bytes and exposes current_shingle and reset" do
    r = LexisMinhash::ShingleRoller.new(3)
    bytes = "abcd".each_byte.to_a
    vals = bytes.map { |b| r.roll(b) }
    # At least the last roll should return a hash (window filled)
    vals.last.should_not be_nil
    # Current shingle should reflect last 3 characters
    r.current_shingle.should eq("bcd")
    r.reset
    r.current_shingle.should be_nil
  end
end

describe "Signature and Bytes roundtrips" do
  it "Signature to_blob and from_blob roundtrip preserves data" do
    sig = LexisMinhash::Signature.compute("Roundtrip test document")
    blob = sig.to_blob
    restored = LexisMinhash::Signature.from_blob(blob)
    restored.data.to_a.should eq(sig.data.to_a)
  end

  it "bytes_to_signature_slice roundtrips slice signatures" do
    slice = LexisMinhash::Engine.compute_signature_slice("slice roundtrip test")
    bytes = LexisMinhash::Engine.signature_to_bytes(slice)
    restored = LexisMinhash::Engine.bytes_to_signature_slice(bytes)
    restored.to_a.should eq(slice.to_a)
  end
end

describe "Prehash and hashed-weight APIs" do
  it "prehash_weights and hashed-weighted signature produce same shape" do
    weights = {"quick" => 2.0_f64, "brown" => 1.5_f64, "fox j" => 3.0_f64}
    hashed = LexisMinhash::Engine.prehash_weights(weights)
    sig1 = LexisMinhash::Engine.compute_signature_with_prehashed_weights("The quick brown fox jumps", weights)
    sig2 = LexisMinhash::Engine.compute_signature("The quick brown fox jumps", hashed)
    sig1.size.should eq(sig2.size)
  end
end

describe "Hash-based signature APIs" do
  it "compute_signature_from_hashes works with simple hashes (weighted and non-weighted)" do
    # simple deterministic UInt64 values
    h = [1_u64, 2_u64, 3_u64]
    sig = LexisMinhash::Engine.compute_signature_from_hashes(h)
    sig.size.should eq(LexisMinhash::Engine.config[0])

    w = [1.0_f64, 2.0_f64, 0.5_f64]
    sigw = LexisMinhash::Engine.compute_signature_from_hashes(h, w)
    sigw.size.should eq(sig.size)
  end
end

describe "Similarity helpers and LSHIndex extras" do
  it "fast_overlap returns expected value for UInt32 slices" do
    a = Slice.new(5) { |i| i.to_u32 }
    b = Slice.new(3) { |i| (i + 1).to_u32 }
    # intersection = [1,2,3] => 3/3 == 1.0
    LexisMinhash::Similarity.fast_overlap(a, b).should be_close(1.0_f64, 1e-9)
  end

  it "query_with_weights_by_signature and get_signature behave without raising" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 50)
    sig = LexisMinhash::Engine.compute_signature("signature query test")
    index.add_with_signature(42, sig)
    index.get_signature(42).should_not be_nil

    weights = {"signa" => 2.0_f64}
    results = index.query_with_weights_by_signature(sig, weights)
    results.should be_a(Set(Int32))
  end
end
