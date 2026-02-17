# Lexis MinHash - Locality-Sensitive Hashing for text similarity detection
# Used to group duplicate or similar documents from various sources
require "deque"
require "mutex"
require "random/secure"
require "set"

require "./lexis-minhash/engine"
require "./lexis-minhash/index"

module LexisMinhash
  # Document interface for custom document types
  module Document
    abstract def text : String
  end

  # Simple document wrapper for text strings
  struct SimpleDocument
    include Document

    getter text : String

    def initialize(@text : String)
    end
  end
end

# Backward compatibility: allow Engine to accept Document interface
module LexisMinhash::Engine
  # Compute signature from a Document (backward compatibility)
  def self.compute_signature(document : LexisMinhash::Document) : Array(UInt32)
    compute_signature(document.text)
  end
end
