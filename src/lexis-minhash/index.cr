module LexisMinhash
  # In-memory LSH index for efficient candidate retrieval
  class LSHIndex
    @buckets : Hash(UInt64, Set(String))
    @signatures : Hash(String, Array(UInt32))

    def initialize
      @buckets = Hash(UInt64, Set(String)).new
      @signatures = Hash(String, Array(UInt32)).new
    end

    def add(doc_id : String, document : Document) : Nil
      signature = Engine.compute_signature(document)
      @signatures[doc_id] = signature
      bands = Engine.generate_bands(signature)
      bands.each do |_band_index, band_hash|
        @buckets[band_hash] ||= Set(String).new
        @buckets[band_hash] << doc_id
      end
    end

    def query(document : Document, max_candidates : Int32 = 100) : Set(String)
      signature = Engine.compute_signature(document)
      query_by_signature(signature, max_candidates)
    end

    def query_by_signature(signature : Array(UInt32), max_candidates : Int32 = 100) : Set(String)
      bands = Engine.generate_bands(signature)
      candidates = Set(String).new

      bands.each do |_band_index, band_hash|
        if bucket = @buckets[band_hash]
          candidates.concat(bucket)
        end
        break if candidates.size >= max_candidates
      end

      candidates
    end

    def query_with_scores(document : Document, max_candidates : Int32 = 100) : Array({String, Float64})
      signature = Engine.compute_signature(document)
      query_with_scores_by_signature(signature, max_candidates)
    end

    def query_with_scores_by_signature(signature : Array(UInt32), max_candidates : Int32 = 100) : Array({String, Float64})
      candidates = query_by_signature(signature, max_candidates)

      candidates.map do |doc_id|
        other_sig = @signatures[doc_id]?
        score = other_sig ? Engine.similarity(signature, other_sig) : 0.0_f64
        {doc_id, score}
      end.sort_by! { |_doc, score| -score }
    end

    def find_similar_pairs(threshold : Float64 = 0.75) : Set({String, String})
      pairs = Set({String, String}).new
      checked = Set({String, String}).new

      @signatures.each do |doc_id, signature|
        candidates = query_by_signature(signature, max_candidates: 50)

        candidates.each do |other_id|
          next if doc_id == other_id
          pair_key = doc_id < other_id ? {doc_id, other_id} : {other_id, doc_id}
          next if checked.includes?(pair_key)
          checked << pair_key

          if other_sig = @signatures[other_id]?
            if Engine.similarity(signature, other_sig) >= threshold
              pairs << {doc_id, other_id}
            end
          end
        end
      end

      pairs
    end

    def size : Int32
      @signatures.size
    end

    def clear : Nil
      @buckets.clear
      @signatures.clear
    end
  end

  # Fast LSH index using Int32 doc IDs and optimized storage
  class FastLSHIndex
    @signatures : Hash(Int32, Slice(UInt32))
    @tables : Array(Hash(UInt64, Array(Int32)))
    @bands : Int32
    @rows : Int32

    def initialize(bands : Int32 = 20)
      @signatures = Hash(Int32, Slice(UInt32)).new
      @tables = Array.new(bands) { Hash(UInt64, Array(Int32)).new }
      @bands = bands
      @rows = 5
    end

    def add(doc_id : Int32, text : String) : Nil
      signature = FastEngine.compute_signature(text)
      @signatures[doc_id] = signature

      band_hashes = FastEngine.generate_bands(signature)
      band_hashes.each_with_index do |band_hash, band_idx|
        (@tables[band_idx][band_hash] ||= [] of Int32) << doc_id
      end
    end

    def add_with_signature(doc_id : Int32, signature : Slice(UInt32)) : Nil
      @signatures[doc_id] = signature.dup

      band_hashes = FastEngine.generate_bands(signature)
      band_hashes.each_with_index do |band_hash, band_idx|
        (@tables[band_idx][band_hash] ||= [] of Int32) << doc_id
      end
    end

    def query(text : String) : Set(Int32)
      signature = FastEngine.compute_signature(text)
      query_by_signature(signature)
    end

    def query_by_signature(signature : Slice(UInt32)) : Set(Int32)
      candidates = Set(Int32).new

      band_hashes = FastEngine.generate_bands(signature)
      band_hashes.each_with_index do |band_hash, band_idx|
        if matches = @tables[band_idx][band_hash]?
          matches.each { |id| candidates << id }
        end
      end

      candidates
    end

    def query_with_scores(text : String) : Array({Int32, Float64})
      signature = FastEngine.compute_signature(text)
      query_with_scores_by_signature(signature)
    end

    def query_with_scores_by_signature(signature : Slice(UInt32)) : Array({Int32, Float64})
      candidates = query_by_signature(signature)

      candidates.map do |doc_id|
        other_sig = @signatures[doc_id]?
        score = other_sig ? FastEngine.similarity(signature, other_sig) : 0.0_f64
        {doc_id, score}
      end.sort_by! { |_doc, score| -score }
    end

    def find_similar_pairs(threshold : Float64 = 0.75) : Set({Int32, Int32})
      pairs = Set({Int32, Int32}).new
      checked = Set({Int32, Int32}).new

      @signatures.each do |doc_id, signature|
        candidates = query_by_signature(signature)

        candidates.each do |other_id|
          next if doc_id == other_id
          pair_key = doc_id < other_id ? {doc_id, other_id} : {other_id, doc_id}
          next if checked.includes?(pair_key)
          checked << pair_key

          if other_sig = @signatures[other_id]?
            if FastEngine.similarity(signature, other_sig) >= threshold
              pairs << {doc_id, other_id}
            end
          end
        end
      end

      pairs
    end

    def get_signature(doc_id : Int32) : Slice(UInt32)?
      @signatures[doc_id]?
    end

    def size : Int32
      @signatures.size
    end

    def clear : Nil
      @signatures.clear
      @tables.each(&.clear)
    end
  end
end
