{
  description = "Nix flake to generate development TLS certificates using generate-dev-tls.sh with consistent variable defaults and a parameterized builder function.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }: let
    forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    tlsBuildInputs = pkgs: [ pkgs.bash pkgs.openssl ];

    # Parameterized function to build the cert derivation
    devTlsCerts = { pkgs
      , DAYS ? "365"
      , CA_CN ? "DevCA"
      , SERVER_CN ? "localhost"
      , CLIENT_CN ? "client"
    }:
      pkgs.stdenv.mkDerivation {
        pname = "dev-tls-certs";
        version = "1.0.0";
        src = ./.;
        buildInputs = tlsBuildInputs pkgs;

        buildPhase = ''
          mkdir -p $out
          export DAYS="${DAYS}"
          export CA_CN="${CA_CN}"
          export SERVER_CN="${SERVER_CN}"
          export CLIENT_CN="${CLIENT_CN}"
          bash $src/gen-dev-tls.sh gen $out
        '';

        installPhase = "true";

        meta = with pkgs.lib; {
          description = "Development TLS certificates generated with generate-dev-tls.sh (parameterized)";
          license = licenses.mit;
          platforms = platforms.all;
        };
      };
  in {
    # Expose the helper function for reuse
    lib.devTlsCerts = devTlsCerts;

    packages = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        dev-tls-certs = devTlsCerts { inherit pkgs; };
        default = devTlsCerts { inherit pkgs; };
      }
    );

    devShells = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.mkShell {
          buildInputs = tlsBuildInputs pkgs;
        };
      }
    );
  };
}
