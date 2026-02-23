# LexisMinhash top-level module documentation.
#
# This module exposes the public API types: `Engine`, `Signature`, `Similarity`, and
# `LSHIndex`. See individual type docs for usage examples.
module LexisMinhash
  # Linear probing bucket table for cache-efficient LSH storage
  struct BucketEntry
    property key : UInt64
    property doc_id : Int32

    # Create a new BucketEntry for `key` and `doc_id`
    def initialize(@key : UInt64, @doc_id : Int32)
    end
  end

  # LinearBucketTable is a simple open-addressing hash table with linear
  # probing. It stores `BucketEntry` values and is used by each LSH band to
  # record document ids for a given band hash.
  class LinearBucketTable
    @data : Slice(BucketEntry)
    @occupied : Slice(Bool)
    @count : Int32 = 0

    # Capacity should be ~2x expected entries for good performance
    # Create a table with `capacity` slots
    def initialize(capacity : Int32)
      @data = Slice(BucketEntry).new(capacity) { BucketEntry.new(0_u64, 0) }
      @occupied = Slice(Bool).new(capacity, false)
    end

    # Insert a key/doc_id pair into the table. No-op if the table is full or
    # the pair already exists.
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

    # Iterate candidate doc ids matching the given key by scanning the cluster.
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

    # Clear the table, marking all slots as empty
    def clear : Nil
      @occupied.fill(false)
      @count = 0
    end

    # Number of occupied entries
    def size : Int32
      @count
    end

    # Total capacity (number of slots)
    def capacity : Int32
      @data.size
    end

    # Load factor (occupied / capacity)
    def load_factor : Float64
      @count.to_f64 / @data.size.to_f64
    end
  end

  # In-memory LSH index using Int32 doc IDs and linear probing storage
  # LSHIndex is an in-memory locality-sensitive hashing index. It stores
  # signatures per document and a set of per-band hash tables (LinearBucketTable)
  # to quickly retrieve candidate document ids for a query.
  class LSHIndex
    @signatures : Hash(Int32, Array(UInt32))
    @tables : Array(LinearBucketTable)
    @bands : Int32

    # @rows unused: configuration drives row count from Engine; remove to avoid confusion

    # Initialize with expected number of documents for capacity planning
    # Table capacity is ~2x expected docs per band for good load factor
    # Initialize index with `bands` and `expected_docs` for capacity planning.
    def initialize(bands : Int32 = 20, expected_docs : Int32 = 1000)
      @signatures = Hash(Int32, Array(UInt32)).new
      # Each band gets a table with ~2x expected entries
      table_capacity = expected_docs * 2
      @tables = Array.new(bands) { LinearBucketTable.new(table_capacity) }
      @bands = bands
      @rows = 5
    end

    # Compute signature for text and insert into all band tables
    def add(doc_id : Int32, text : String) : Nil
      signature = Engine.compute_signature(text)
      @signatures[doc_id] = signature

      band_hashes = Engine.generate_bands(signature, @bands)
      band_hashes.each do |band_idx, band_hash|
        @tables[band_idx].insert(band_hash, doc_id)
      end
    end

    # Add a document using a precomputed signature
    def add_with_signature(doc_id : Int32, signature : Array(UInt32)) : Nil
      @signatures[doc_id] = signature.dup

      band_hashes = Engine.generate_bands(signature, @bands)
      band_hashes.each do |band_idx, band_hash|
        @tables[band_idx].insert(band_hash, doc_id)
      end
    end

    # Add a document using TF-IDF style weights
    def add_with_weights(doc_id : Int32, text : String, weights : Hash(String, Float64)) : Nil
      signature = Engine.compute_signature(text, weights)
      @signatures[doc_id] = signature

      band_hashes = Engine.generate_bands(signature, @bands)
      band_hashes.each do |band_idx, band_hash|
        @tables[band_idx].insert(band_hash, doc_id)
      end
    end

    # Query by plain text (unweighted)
    def query(text : String) : Set(Int32)
      signature = Engine.compute_signature(text)
      query_by_signature(signature)
    end

    # Query by precomputed signature
    def query_by_signature(signature : Array(UInt32)) : Set(Int32)
      candidates = Set(Int32).new

      band_hashes = Engine.generate_bands(signature, @bands)
      band_hashes.each do |band_idx, band_hash|
        @tables[band_idx].find_candidates(band_hash) do |doc_id|
          candidates << doc_id
        end
      end

      candidates
    end

    # Query and return candidates with similarity scores, sorted desc
    def query_with_scores(text : String) : Array({Int32, Float64})
      signature = Engine.compute_signature(text)
      query_with_scores_by_signature(signature)
    end

    # Query with weights (TF-IDF)
    def query_with_weights(text : String, weights : Hash(String, Float64)) : Set(Int32)
      signature = Engine.compute_signature(text, weights)
      query_by_signature(signature)
    end

    # Query by signature where the original add used weights (keeps signature
    # semantics consistent)
    def query_with_weights_by_signature(signature : Array(UInt32), weights : Hash(String, Float64)) : Set(Int32)
      query_by_signature(signature)
    end

    # Query by signature and return scored results
    def query_with_scores_by_signature(signature : Array(UInt32)) : Array({Int32, Float64})
      candidates = query_by_signature(signature)

      candidates.map do |doc_id|
        other_sig = @signatures[doc_id]?
        score = other_sig ? Engine.similarity(signature, other_sig) : 0.0_f64
        {doc_id, score}
      end.sort_by! { |_doc, score| -score }
    end

    # Find all similar document pairs above `threshold` similarity
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

    # Retrieve stored signature by doc id (returns `nil` if not present)
    def get_signature(doc_id : Int32) : Array(UInt32)?
      @signatures[doc_id]?
    end

    # Number of stored documents
    def size : Int32
      @signatures.size
    end

    # Returns load factors for each band's table
    # Returns load factor per band table
    def load_factors : Array(Float64)
      @tables.map(&.load_factor)
    end

    # Clear the index and all tables
    def clear : Nil
      @signatures.clear
      @tables.each(&.clear)
    end
  end
end
