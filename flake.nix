{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      forAllSystems =
        fn:
        let
          systems = [ "x86_64-linux" ];
          overlays = [ (import rust-overlay) ];
        in
        nixpkgs.lib.genAttrs systems (
          system:
          fn (
            import nixpkgs {
              inherit system overlays;
            }
          )
        );
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.bacon
            pkgs.cargo-pgrx
            pkgs.rust-analyzer
            pkgs.rust-bin.stable.latest.default
          ];

          inputsFrom = with pkgs; [
            postgresql_12
            postgresql_13
            postgresql_14
            postgresql_15
            postgresql_16
            postgresql_17
          ];

          nativeBuildInputs = [
            pkgs.rustPlatform.bindgenHook
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
