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
        @b : Slice(UInt64),
      )
      end
    end

    # Splitmix64 stateful random number generator
    # Provides high-quality randomness for coefficient generation
    private class SplitMix64
      @state : UInt64

      def initialize(seed : UInt64)
        @state = seed
      end

      # Generate next random UInt64 using splitmix64 algorithm
      def next : UInt64
        @state = @state &+ 0x9e3779b97f4a7c15_u64
        z = @state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9_u64
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb_u64
        z ^ (z >> 31)
      end
    end

    # Generate a Config instance. When `seed` is provided the coefficient
    # arrays `a` and `b` are filled deterministically using splitmix64 so
    # results are reproducible across runs. When `seed` is nil, uses
    # Random::Secure as before.
    def self.generate_config(
      signature_size : Int32 = SIGNATURE_SIZE,
      num_bands : Int32 = NUM_BANDS,
      shingle_size : Int32 = SHINGLE_SIZE,
      min_words : Int32 = MIN_WORDS,
      default_weight : Float64 = DEFAULT_WEIGHT,
      seed : Int64? = nil,
    ) : Config
      rows = signature_size // num_bands

      if seed
        # Use splitmix64 for deterministic, high-quality coefficient generation
        rng = SplitMix64.new(seed.to_u64)

        arr_a = Pointer(UInt64).malloc(signature_size)
        arr_b = Pointer(UInt64).malloc(signature_size)

        signature_size.times do |i|
          # 'a' coefficients must be odd for mathematical correctness in multiply-shift hashing
          arr_a[i] = rng.next | 1_u64
          arr_b[i] = rng.next
        end

        a_slice = Slice.new(arr_a, signature_size)
        b_slice = Slice.new(arr_b, signature_size)
      else
        # Use cryptographically secure random for non-deterministic configurations
        a_slice = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) | 1 }
        b_slice = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) }
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

        if shingle_size > Engine::MAX_SHINGLE_SIZE
          raise ArgumentError.new("shingle_size must not exceed #{Engine::MAX_SHINGLE_SIZE}")
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
