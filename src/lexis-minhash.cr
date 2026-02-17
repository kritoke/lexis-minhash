# Lexis MinHash - Locality-Sensitive Hashing for text similarity detection
# Used to group duplicate or similar documents from various sources
require "digest/sha256"
require "set"
require "mutex"
require "deque"
require "random/secure"

require "./lexis-minhash/engine"
require "./lexis-minhash/fast_engine"
require "./lexis-minhash/index"

# The main module containing all Lexis MinHash functionality
module LexisMinhash
  # The Document interface that must be implemented by any document type
  # that wants to use the Lexis MinHash engine.
  module Document
    # Returns the text content of the document for signature calculation
    abstract def text : String
  end

  # Default implementation of the Document interface for simple text strings
  struct SimpleDocument
    include Document

    getter text : String

    def initialize(@text : String)
    end
  end

  # Configuration for the MinHash engine
  struct Config
    getter signature_size : Int32
    getter num_bands : Int32
    getter shingle_size : Int32
    getter min_words : Int32
    getter stop_words : Set(String)

    def initialize(
      @signature_size : Int32 = 100,
      @num_bands : Int32 = 20,
      @shingle_size : Int32 = 3,
      @min_words : Int32 = 6,
      @stop_words : Set(String) = Set(String).new,
    )
    end

    def rows_per_band : Int32
      @signature_size // @num_bands
    end
  end

  # Default stop words for clustering
  DEFAULT_STOP_WORDS = Set.new([
    "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
    "be", "have", "has", "had", "do", "does", "did", "will", "would",
    "could", "should", "may", "might", "must", "shall", "can", "need",
    "this", "that", "these", "those", "it", "its", "they", "them",
    "time", "times", "day", "days", "week", "weeks", "month", "months",
    "year", "years", "today", "yesterday", "tomorrow", "morning", "afternoon", "evening",
    "new", "news", "latest", "update", "updates", "report", "reports",
    "breaking", "exclusive", "special", "alert", "alerts", "coverage",
    "says", "said", "saying", "tell", "tells", "told", "claim", "claims", "claimed",
    "just", "now", "how", "what", "when", "where", "why", "also", "too",
    "up", "down", "out", "over", "after", "before", "between", "under", "above",
    "one", "two", "three", "first", "second", "third", "top", "bottom",
    "get", "gets", "got", "make", "makes", "made", "take", "takes", "took",
    "see", "sees", "saw", "know", "knows", "knew", "think", "thinks", "thought",
    "want", "wants", "use", "uses", "used", "find", "finds", "found",
    "build", "building", "built", "using", "via", "making", "way",
    "youre", "your", "work", "works", "working",
  ])
end
