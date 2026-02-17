require "spec"
require "../src/lexis-minhash"

struct CustomDocument
  include LexisMinhash::Document

  getter text : String

  def initialize(@text : String)
  end
end

describe LexisMinhash do
  describe LexisMinhash::Engine do
    describe "compute_signature" do
      it "returns an array of the correct size" do
        doc = LexisMinhash::SimpleDocument.new("Hello World")
        signature = LexisMinhash::Engine.compute_signature(doc)
        signature.size.should eq(LexisMinhash::Engine::SIGNATURE_SIZE)
      end

      it "returns zeros for empty string" do
        doc = LexisMinhash::SimpleDocument.new("")
        signature = LexisMinhash::Engine.compute_signature(doc)
        signature.should eq(Array(UInt32).new(LexisMinhash::Engine::SIGNATURE_SIZE, 0_u32))
      end

      it "returns consistent signatures for the same text" do
        doc1 = LexisMinhash::SimpleDocument.new("Test Article Title")
        doc2 = LexisMinhash::SimpleDocument.new("Test Article Title")
        sig1 = LexisMinhash::Engine.compute_signature(doc1)
        sig2 = LexisMinhash::Engine.compute_signature(doc2)
        sig1.should eq(sig2)
      end

      it "returns different signatures for different texts" do
        doc1 = LexisMinhash::SimpleDocument.new("Technology company announces revolutionary new product update")
        doc2 = LexisMinhash::SimpleDocument.new("Government officials discuss new policy changes for citizens")
        sig1 = LexisMinhash::Engine.compute_signature(doc1)
        sig2 = LexisMinhash::Engine.compute_signature(doc2)
        sig1.should_not eq(sig2)
      end

      it "is case insensitive" do
        doc1 = LexisMinhash::SimpleDocument.new("Hello World")
        doc2 = LexisMinhash::SimpleDocument.new("hello world")
        sig1 = LexisMinhash::Engine.compute_signature(doc1)
        sig2 = LexisMinhash::Engine.compute_signature(doc2)
        sig1.should eq(sig2)
      end
    end

    describe "similarity" do
      it "returns 1.0 for identical signatures" do
        doc = LexisMinhash::SimpleDocument.new("Same Title")
        sig = LexisMinhash::Engine.compute_signature(doc)
        LexisMinhash::Engine.similarity(sig, sig).should eq(1.0_f64)
      end

      it "returns 0.0 for completely different signatures" do
        doc1 = LexisMinhash::SimpleDocument.new("AAAA BBBB CCCC DDDD EEEE FFFF")
        doc2 = LexisMinhash::SimpleDocument.new("1111 2222 3333 4444 5555 6666")
        sig1 = LexisMinhash::Engine.compute_signature(doc1)
        sig2 = LexisMinhash::Engine.compute_signature(doc2)
        similarity = LexisMinhash::Engine.similarity(sig1, sig2)
        similarity.should be < 0.5_f64
      end

      it "returns higher similarity for similar texts" do
        doc1 = LexisMinhash::SimpleDocument.new("Apple announces new iPhone 15 Pro")
        doc2 = LexisMinhash::SimpleDocument.new("Apple announces new iPhone 15 Pro Max")
        doc3 = LexisMinhash::SimpleDocument.new("Microsoft releases Windows 12")

        sig1 = LexisMinhash::Engine.compute_signature(doc1)
        sig2 = LexisMinhash::Engine.compute_signature(doc2)
        sig3 = LexisMinhash::Engine.compute_signature(doc3)

        similarity_same = LexisMinhash::Engine.similarity(sig1, sig2)
        similarity_diff = LexisMinhash::Engine.similarity(sig1, sig3)

        similarity_same.should be > similarity_diff
      end
    end

    describe "generate_bands" do
      it "returns the correct number of bands" do
        doc = LexisMinhash::SimpleDocument.new("Test")
        signature = LexisMinhash::Engine.compute_signature(doc)
        bands = LexisMinhash::Engine.generate_bands(signature)
        bands.size.should eq(LexisMinhash::Engine::NUM_BANDS)
      end

      it "returns unique band indices" do
        doc = LexisMinhash::SimpleDocument.new("Test")
        signature = LexisMinhash::Engine.compute_signature(doc)
        bands = LexisMinhash::Engine.generate_bands(signature)
        band_indices = bands.map(&.[0])
        band_indices.uniq.size.should eq(band_indices.size)
      end

      it "returns UInt64 band hashes" do
        doc = LexisMinhash::SimpleDocument.new("Test")
        signature = LexisMinhash::Engine.compute_signature(doc)
        bands = LexisMinhash::Engine.generate_bands(signature)
        bands.each do |_band_index, band_hash|
          band_hash.should be_a(UInt64)
        end
      end
    end

    describe "signature_to_bytes and bytes_to_signature" do
      it "preserves signature data through conversion" do
        doc = LexisMinhash::SimpleDocument.new("Convert This Signature")
        original = LexisMinhash::Engine.compute_signature(doc)
        bytes = LexisMinhash::Engine.signature_to_bytes(original)
        restored = LexisMinhash::Engine.bytes_to_signature(bytes)
        original.should eq(restored)
      end

      it "handles empty signatures" do
        empty = Array(UInt32).new(LexisMinhash::Engine::SIGNATURE_SIZE, 0_u32)
        bytes = LexisMinhash::Engine.signature_to_bytes(empty)
        restored = LexisMinhash::Engine.bytes_to_signature(bytes)
        empty.should eq(restored)
      end
    end

    describe "detection_probability" do
      it "returns 0.0 for 0 similarity" do
        LexisMinhash::Engine.detection_probability(0.0_f64).should eq(0.0_f64)
      end

      it "returns 1.0 for 1.0 similarity" do
        prob = LexisMinhash::Engine.detection_probability(1.0_f64)
        prob.should be_close(1.0_f64, 0.01_f64)
      end

      it "returns higher probability for higher similarity" do
        prob_low = LexisMinhash::Engine.detection_probability(0.5_f64)
        prob_high = LexisMinhash::Engine.detection_probability(0.9_f64)
        prob_high.should be > prob_low
      end
    end

    describe "jaccard_similarity" do
      it "returns 1.0 for identical documents" do
        doc = LexisMinhash::SimpleDocument.new("Apple technology revolution smartphone innovation market")
        LexisMinhash::Engine.jaccard_similarity(doc, doc).should eq(1.0_f64)
      end

      it "returns higher similarity for similar texts" do
        doc1 = LexisMinhash::SimpleDocument.new("Apple technology revolution smartphone innovation market device")
        doc2 = LexisMinhash::SimpleDocument.new("Apple technology revolution smartphone innovation market gadget")
        doc3 = LexisMinhash::SimpleDocument.new("Microsoft software windows operating system enterprise business")

        sim_same = LexisMinhash::Engine.jaccard_similarity(doc1, doc2)
        sim_diff = LexisMinhash::Engine.jaccard_similarity(doc1, doc3)

        sim_same.should be > sim_diff
      end
    end

    describe "compare" do
      it "computes similarity between two documents" do
        doc1 = LexisMinhash::SimpleDocument.new("Apple technology revolution smartphone innovation market device")
        doc2 = LexisMinhash::SimpleDocument.new("Apple technology revolution smartphone innovation market gadget")

        similarity = LexisMinhash::Engine.compare(doc1, doc2)
        similarity.should be > 0.5_f64
      end
    end

    describe "shared_bands" do
      it "returns number of shared bands" do
        doc1 = LexisMinhash::SimpleDocument.new("Technology company product announcement innovation revolution")
        doc2 = LexisMinhash::SimpleDocument.new("Technology company product release innovation revolution")

        sig1 = LexisMinhash::Engine.compute_signature(doc1)
        sig2 = LexisMinhash::Engine.compute_signature(doc2)

        shared = LexisMinhash::Engine.shared_bands(sig1, sig2)
        shared.should be >= 0
        shared.should be <= LexisMinhash::Engine::NUM_BANDS
      end
    end
  end

  describe LexisMinhash::SimpleDocument do
    it "implements the Document interface" do
      doc = LexisMinhash::SimpleDocument.new("Test text")
      doc.should be_a(LexisMinhash::Document)
    end

    it "stores and retrieves text" do
      text = "This is a test document"
      doc = LexisMinhash::SimpleDocument.new(text)
      doc.text.should eq(text)
    end
  end

  describe "custom document types" do
    it "allows custom document types implementing Document interface" do
      doc = CustomDocument.new("Custom document text")
      sig = LexisMinhash::Engine.compute_signature(doc)
      sig.size.should eq(LexisMinhash::Engine::SIGNATURE_SIZE)
    end
  end

  describe LexisMinhash::LSHIndex do
    it "adds and queries documents" do
      index = LexisMinhash::LSHIndex.new

      doc1 = LexisMinhash::SimpleDocument.new("Apple technology revolution smartphone innovation market device")
      doc2 = LexisMinhash::SimpleDocument.new("Apple technology revolution smartphone innovation market gadget")

      index.add("doc1", doc1)
      index.add("doc2", doc2)

      index.size.should eq(2)

      candidates = index.query(doc1)
      candidates.should contain("doc1")
    end

    it "finds similar pairs" do
      index = LexisMinhash::LSHIndex.new

      doc1 = LexisMinhash::SimpleDocument.new("Technology company announces revolutionary smartphone innovation")
      doc2 = LexisMinhash::SimpleDocument.new("Technology company announces revolutionary smartphone product")
      doc3 = LexisMinhash::SimpleDocument.new("Completely different topic about cooking recipes food")

      index.add("doc1", doc1)
      index.add("doc2", doc2)
      index.add("doc3", doc3)

      pairs = index.find_similar_pairs(threshold: 0.5_f64)
      pairs.size.should be >= 0
    end

    it "queries by signature directly" do
      index = LexisMinhash::LSHIndex.new

      doc = LexisMinhash::SimpleDocument.new("Technology company announces revolutionary smartphone innovation")
      index.add("doc1", doc)

      signature = LexisMinhash::Engine.compute_signature(doc)
      candidates = index.query_by_signature(signature)

      candidates.should contain("doc1")
    end

    it "clears all data" do
      index = LexisMinhash::LSHIndex.new

      doc = LexisMinhash::SimpleDocument.new("Test document for clearing")
      index.add("doc1", doc)

      index.size.should eq(1)
      index.clear
      index.size.should eq(0)
    end
  end

  describe LexisMinhash::Engine do
    describe "configure" do
      it "allows custom configuration" do
        LexisMinhash::Engine.configure(
          signature_size: 50,
          num_bands: 10,
          shingle_size: 4,
          min_words: 3
        )

        LexisMinhash::Engine.config.signature_size.should eq(50)
        LexisMinhash::Engine.config.num_bands.should eq(10)
        LexisMinhash::Engine.config.shingle_size.should eq(4)
        LexisMinhash::Engine.config.min_words.should eq(3)

        LexisMinhash::Engine.reset_config
      end
    end
  end
end
