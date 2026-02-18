# Lexis MinHash - Locality-Sensitive Hashing for text similarity detection
#
# A Crystal library for detecting similar text documents using the MinHash
# technique with rolling hash and multiply-shift hashing for O(n) performance.
#
# ## Installation
#
# Add to `shard.yml`:
#
# ```yaml
# dependencies:
#   lexis-minhash:
#     github: kritoke/lexis-minhash
# ```
#
# ## Quick Start
#
# ```
# require "lexis-minhash"
#
# sig1 = LexisMinhash::Engine.compute_signature("Document text")
# sig2 = LexisMinhash::Engine.compute_signature("Similar document")
# similarity = LexisMinhash::Engine.similarity(sig1, sig2)
# ```
#
# ## Documentation
#
# - [README.md](../README.md) - Basic usage and API reference
# - [API.md](./API.md) - Advanced usage patterns and recommendations
require "deque"
require "mutex"
require "random/secure"
require "set"

require "./lexis-minhash/engine"
require "./lexis-minhash/index"
require "./lexis-minhash/similarity"

module LexisMinhash
  # Document interface for custom document types
  #
  # Implement this module to use custom document types with the library:
  #
  # ```
  # struct MyDocument
  #   include LexisMinhash::Document
  #
  #   getter text : String
  #
  #   def initialize(@text : String)
  #   end
  # end
  # ```
  module Document
    # Returns the text content of the document
    abstract def text : String
  end

  # Simple document wrapper for text strings
  #
  # Convenience struct for wrapping plain text strings when using
  # the Document interface pattern.
  struct SimpleDocument
    include Document

    getter text : String

    # Creates a new SimpleDocument with the given text
    def initialize(@text : String)
    end
  end
end

# Backward compatibility: allow Engine to accept Document interface
module LexisMinhash::Engine
  # Computes a MinHash signature from a Document
  #
  # Provides backward compatibility for code using the Document interface.
  # See `LexisMinhash::Document` for implementation details.
  def self.compute_signature(document : LexisMinhash::Document) : Array(UInt32)
    compute_signature(document.text)
  end
end
