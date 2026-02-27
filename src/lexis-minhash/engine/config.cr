module LexisMinhash
  module Engine
    # Mutex protecting configure/default config updates
    @@mutex = Mutex.new
    @@default_cfg : Config = generate_config(SIGNATURE_SIZE, NUM_BANDS, SHINGLE_SIZE, MIN_WORDS, DEFAULT_WEIGHT, nil)

    # Immutable engine configuration used for pure/functional APIs.
    struct Config
      getter signature_size : Int32
      getter num_bands : Int32
      getter rows_per_band : Int32
      getter shingle_size : Int32
      getter min_words : Int32
      getter default_weight : Float64
      getter a : Slice(UInt64)
      getter b : Slice(UInt64)

      def initialize(
        @signature_size : Int32,
        @num_bands : Int32,
        @rows_per_band : Int32,
        @shingle_size : Int32,
        @min_words : Int32,
        @default_weight : Float64,
        @a : Slice(UInt64),
        @b : Slice(UInt64)
      )
      end
    end

    # Generate a Config instance. When `seed` is provided the coefficient
    # arrays `a` and `b` are filled deterministically using a simple LCG so
    # results are reproducible across runs. When `seed` is nil, uses
    # Random::Secure as before.
    def self.generate_config(
      signature_size : Int32 = SIGNATURE_SIZE,
      num_bands : Int32 = NUM_BANDS,
      shingle_size : Int32 = SHINGLE_SIZE,
      min_words : Int32 = MIN_WORDS,
      default_weight : Float64 = DEFAULT_WEIGHT,
      seed : Int64? = nil
    ) : Config
      rows = signature_size // num_bands

      a_slice = if seed
        seed_u64 = seed.to_u64
        arr_a = Pointer(UInt64).malloc(signature_size)
        arr_b = Pointer(UInt64).malloc(signature_size)
        signature_size.times do |i|
          arr_a[i] = ((((seed_u64 &* 6364136223846793005_u64) &+ i.to_u64) &+ 1442695040888963407_u64) | 1_u64)
          arr_b[i] = (((seed_u64 &* 6364136223846793005_u64) &+ (i.to_u64 &* 0x9e3779b97f4a7c15_u64)) &+ 1442695040888963407_u64)
        end
        Slice.new(arr_a, signature_size)
      else
        Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) | 1 }
      end

      b_slice = if seed
        seed_u64 = seed.to_u64
        arr_b = Pointer(UInt64).malloc(signature_size)
        signature_size.times do |i|
          arr_b[i] = (((seed_u64 &* 6364136223846793005_u64) &+ (i.to_u64 &* 0x9e3779b97f4a7c15_u64)) &+ 1442695040888963407_u64)
        end
        Slice.new(arr_b, signature_size)
      else
        Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) }
      end

      Config.new(signature_size, num_bands, rows, shingle_size, min_words, default_weight, a_slice, b_slice)
    end

    # Return or generate the runtime default config. Thread-safe.
    def self.default_config : Config
      @@default_cfg
    end

    # Configure the engine by creating a new default_config from supplied params.
    def self.configure(
      signature_size : Int32 = SIGNATURE_SIZE,
      num_bands : Int32 = NUM_BANDS,
      shingle_size : Int32 = SHINGLE_SIZE,
      min_words : Int32 = MIN_WORDS,
      default_weight : Float64 = DEFAULT_WEIGHT,
      seed : Int64? = nil,
    ) : Nil
      @@mutex.synchronize do
        if signature_size % num_bands != 0
          raise ArgumentError.new("signature_size must be divisible by num_bands")
        end
        @@default_cfg = generate_config(signature_size, num_bands, shingle_size, min_words, default_weight, seed)
      end
    end

    # Return current engine configuration as a tuple for backward compatibility
    def self.config : {Int32, Int32, Int32, Int32, Int32, Float64}
      cfg = default_config
      {cfg.signature_size, cfg.num_bands, cfg.rows_per_band, cfg.shingle_size, cfg.min_words, cfg.default_weight}
    end

    def self.default_weight : Float64
      default_config.default_weight
    end
  end
end
