{
  description = "Perch — macOS Dynamic Island-style Live Hub";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            xcbeautify
            swift-format
            lefthook
            just
          ];

          shellHook = ''
            echo "Perch dev environment ready. Run: just --list"
          '';
        };
      });
}
