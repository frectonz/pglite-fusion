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
      devShells = forAllSystems (
        pkgs:
        let
          cargo-pgrx = import ./nix/pgrx.nix { inherit pkgs; };
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              cargo-pgrx
              pkgs.bacon
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
        }
      );

      packages = forAllSystems (
        pkgs:
        let
          postgresql = pkgs.postgresql.dev;
          cargo-pgrx = import ./nix/pgrx.nix { inherit pkgs; };

          pname = "pglite-fusion";
          version = "0.0.2";

          postgres = pkgs.dockerTools.pullImage {
            imageName = "postgres";
            imageDigest = "sha256:026d0ab72b34310b68160ab9299aa1add5544e4dc3243456b94f83cb1c119c2c";
            sha256 = "sha256-Bwd07vmTNRS1Ntd2sKvYXx/2GGaEVmGGjKukDmuSfD0=";
          };

          extension = pkgs.stdenv.mkDerivation {
            inherit pname version;

            src = import ./nix/build.nix { inherit pkgs cargo-pgrx postgresql; };

            buildPhase = ''
              install --directory $out/usr/share/postgresql/16/extension
              cp -r $src/nix/store/wc1a06ip2fajrjkfbw7cvxzw1c949a6g-postgresql-16.4/share/postgresql/extension/* $out/usr/share/postgresql/16/extension
              install --directory $out/usr/lib/postgresql/16/lib
              cp -r $src/nix/store/wc1a06ip2fajrjkfbw7cvxzw1c949a6g-postgresql-16.4/lib/* $out/usr/lib/postgresql/16/lib
            '';
          };
        in
        rec {
          image = pkgs.dockerTools.buildLayeredImage {
            name = pname;
            fromImage = postgres;

            contents = [ extension ];
            config = {
              Env = [ "POSTGRES_HOST_AUTH_METHOD=trust" ];

              Expose = 5432;
              Cmd = [ "postgres" ];
              Entrypoint = [ "docker-entrypoint.sh" ];
            };
          };

          deploy = pkgs.writeShellScriptBin "deploy" ''
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${image} docker://docker.io/frectonz/${pname}:pg16-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg16-${version} docker://docker.io/frectonz/${pname}:latest --dest-creds="frectonz:$ACCESS_TOKEN"
          '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
