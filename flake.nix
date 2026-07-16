{
  description = "Lexis MinHash - Crystal LSH Library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    openspec.url = "github:Fission-AI/OpenSpec";
  };

  outputs = { self, nixpkgs, flake-utils, openspec }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        crystal_1_19 = pkgs.stdenv.mkDerivation rec {
          pname = "crystal";
          version = "1.19.1";
          src = pkgs.fetchurl {
            url = "https://github.com/crystal-lang/crystal/releases/download/${version}/crystal-${version}-1-linux-aarch64.tar.gz";
            sha256 = "18zp6kn94fgzdi9ylbfs2zjqyklymv2dicj9z5fha77s31ywkgz4";
          };
          installPhase = ''
            mkdir -p $out
            cp -r ./* $out/
          '';
        };
        crystalToolbox = with pkgs; [
          crystal_1_19
          pcre
          sqlite
          openssl
          openssl.dev
          pkg-config
          protobuf
          protobufc
        ];
        buildToolbox = with pkgs; [
          git
          curl
          bashInteractive
          coreutils
          findutils
          gnumake
          gnused
          gnugrep
        ];
        toolbox = crystalToolbox ++ buildToolbox;
      in
      {
        packages.default = pkgs.buildEnv {
          name = "lexis-minhash-tools";
          paths = toolbox;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = toolbox ++ [ openspec.packages.${system}.default ];

          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.boehmgc pkgs.libevent pkgs.openssl pkgs.file pkgs.pcre pkgs.pcre2 pkgs.gmp ]}:$LD_LIBRARY_PATH"
            export APP_ENV=development
            export TZ=America/Chicago
            export LC_ALL=en_US.UTF-8
            export LANG=en_US.UTF-8
            export PATH="${crystal_1_19}/bin:$PWD/bin:$HOME/.local/bin:$PATH"
            echo "❄️  Lexis MinHash Development Environment Loaded"
            echo "📦 Crystal: $(crystal --version 2>/dev/null | head -n1 || echo 'not available')"
          '';
        };
      });
}
