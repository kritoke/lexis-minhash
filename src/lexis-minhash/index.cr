module LexisMinhash
  # Linear probing bucket table for cache-efficient LSH storage
  struct BucketEntry
    property key : UInt64
    property doc_id : Int32

    def initialize(@key : UInt64, @doc_id : Int32)
    end
  end

  class LinearBucketTable
    @data : Slice(BucketEntry)
    @occupied : Slice(Bool)
    @count : Int32 = 0

    # Capacity should be ~2x expected entries for good performance
    def initialize(capacity : Int32)
      @data = Slice(BucketEntry).new(capacity) { BucketEntry.new(0_u64, 0) }
      @occupied = Slice(Bool).new(capacity, false)
    end

    def insert(key : UInt64, doc_id : Int32) : Nil
      return if @count >= @data.size

      idx = (key % @data.size.to_u64).to_i32

      # Linear probing: find empty slot or duplicate
      while @occupied[idx]
        # Skip if already exists
        return if @data[idx].key == key && @data[idx].doc_id == doc_id
        idx = (idx + 1) % @data.size
      end

      @data[idx] = BucketEntry.new(key, doc_id)
      @occupied[idx] = true
      @count += 1
    end

    def find_candidates(key : UInt64, &) : Nil
      return if @count == 0

      idx = (key % @data.size.to_u64).to_i32
      start_idx = idx

      # Scan cluster until we hit an empty slot
      while @occupied[idx]
        if @data[idx].key == key
          yield @data[idx].doc_id
        end
        idx = (idx + 1) % @data.size

        # Safety: don't loop forever if table is full
        break if idx == start_idx
      end
    end

    def clear : Nil
      @occupied.fill(false)
      @count = 0
    end

    def size : Int32
      @count
    end

    def capacity : Int32
      @data.size
    end

    def load_factor : Float64
      @count.to_f64 / @data.size.to_f64
    end
  end

  # In-memory LSH index using Int32 doc IDs and linear probing storage
  class LSHIndex
    @signatures : Hash(Int32, Slice(UInt32))
    @tables : Array(LinearBucketTable)
    @bands : Int32
    @rows : Int32

    # Initialize with expected number of documents for capacity planning
    # Table capacity is ~2x expected docs per band for good load factor
    def initialize(bands : Int32 = 20, expected_docs : Int32 = 1000)
      @signatures = Hash(Int32, Slice(UInt32)).new
      # Each band gets a table with ~2x expected entries
      table_capacity = expected_docs * 2
      @tables = Array.new(bands) { LinearBucketTable.new(table_capacity) }
      @bands = bands
      @rows = 5
    end

    def add(doc_id : Int32, text : String) : Nil
      signature = Engine.compute_signature(text)
      @signatures[doc_id] = signature

      band_hashes = Engine.generate_bands(signature)
      band_hashes.each do |band_idx, band_hash|
        @tables[band_idx].insert(band_hash, doc_id)
      end
    end

    def add_with_signature(doc_id : Int32, signature : Slice(UInt32)) : Nil
      @signatures[doc_id] = signature.dup

      band_hashes = Engine.generate_bands(signature)
      band_hashes.each do |band_idx, band_hash|
        @tables[band_idx].insert(band_hash, doc_id)
      end
    end

    def query(text : String) : Set(Int32)
      signature = Engine.compute_signature(text)
      query_by_signature(signature)
    end

    def query_by_signature(signature : Slice(UInt32)) : Set(Int32)
      candidates = Set(Int32).new

      band_hashes = Engine.generate_bands(signature)
      band_hashes.each do |band_idx, band_hash|
        @tables[band_idx].find_candidates(band_hash) do |doc_id|
          candidates << doc_id
        end
      end

      candidates
    end

    def query_with_scores(text : String) : Array({Int32, Float64})
      signature = Engine.compute_signature(text)
      query_with_scores_by_signature(signature)
    end

    def query_with_scores_by_signature(signature : Slice(UInt32)) : Array({Int32, Float64})
      candidates = query_by_signature(signature)

      candidates.map do |doc_id|
        other_sig = @signatures[doc_id]?
        score = other_sig ? Engine.similarity(signature, other_sig) : 0.0_f64
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
            if Engine.similarity(signature, other_sig) >= threshold
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

    # Returns load factors for each band's table
    def load_factors : Array(Float64)
      @tables.map(&.load_factor)
    end

    def clear : Nil
      @signatures.clear
      @tables.each(&.clear)
    end
  end
end
