{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*";
    rust-overlay.url = "https://flakehub.com/f/oxalica/rust-overlay/*";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
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
          systems = [
            "x86_64-linux"
            "aarch64-darwin"
          ];
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
            pkgs.cargo-pgrx
            pkgs.cargo-outdated
            pkgs.bacon
            pkgs.rust-analyzer
            pkgs.rust-bin.stable.latest.default
          ];

          inputsFrom = with pkgs; [
            postgresql_14
            postgresql_15
            postgresql_16
            postgresql_17
            postgresql_18
          ];

          nativeBuildInputs = [
            pkgs.rustPlatform.bindgenHook
          ];
        };
      });

      packages = forAllSystems (
        pkgs:
        let
          cargo-pgrx = import ./nix/pgrx.nix { inherit pkgs; };

          pname = "pglite-fusion";
          version = "0.0.6";

          buildPgliteFusionImage =
            {
              imageDigest,
              imageSha256,
              postgresDev,
            }:
            let
              postgresMajor = pkgs.lib.versions.major postgresDev.version;

              postgresImage = pkgs.dockerTools.pullImage {
                imageName = "postgres";
                imageDigest = imageDigest;
                sha256 = imageSha256;
              };

              extension = pkgs.stdenv.mkDerivation {
                pname = "${pname}-pg${postgresMajor}-extension";
                inherit version;

                src = import ./nix/build.nix {
                  inherit pkgs;
                  postgresql = postgresDev;
                };

                buildPhase = ''
                  install --directory $out/usr/share/postgresql/${postgresMajor}/extension
                  cp -r $src/nix/store/*/share/postgresql/extension/* $out/usr/share/postgresql/${postgresMajor}/extension
                  install --directory $out/usr/lib/postgresql/${postgresMajor}/lib
                  cp -r $src/nix/store/*/lib/* $out/usr/lib/postgresql/${postgresMajor}/lib
                '';
              };
            in
            pkgs.dockerTools.buildLayeredImage {
              name = "${pname}-pg${postgresMajor}";
              fromImage = postgresImage;

              contents = [ extension ];
              config = {
                Env = [ "POSTGRES_HOST_AUTH_METHOD=trust" ];

                Expose = 5432;
                Cmd = [ "postgres" ];
                Entrypoint = [ "docker-entrypoint.sh" ];
              };
            };

          pg14 = buildPgliteFusionImage {
            imageDigest = "sha256:78b9deeca08fa9749a00e9d30bc879f8f8d021af854c73e2c339b752cb6d708a";
            imageSha256 = "sha256-09neivfziTGnoHMgFkZNMl6cn9KxNGkMY/5L75s0n14=";
            postgresDev = pkgs.postgresql_14;
          };
          pg15 = buildPgliteFusionImage {
            imageDigest = "sha256:a35b3c0190dac5a82ec1778b34cb4963bdd9d161f80381a6297be6e2c3c13a7c";
            imageSha256 = "sha256-JP+dKruENu05jR5gy7EMGUzC1Jkf+o2haKTlsWvPSh4=";
            postgresDev = pkgs.postgresql_15;
          };
          pg16 = buildPgliteFusionImage {
            imageDigest = "sha256:5d65b8bdb20369ea902b987aa63cfe4983130bc8cd2c25830d126636b80b608d";
            imageSha256 = "sha256-4oDXaECE7kZ4jDbm5IX+HCNWlmubHgHcNisn3/82sjc=";
            postgresDev = pkgs.postgresql_16;
          };
          pg17 = buildPgliteFusionImage {
            imageDigest = "sha256:994cc3113ce004ae73df11f0dbc5088cbe6bb0da1691dd7e6f55474202a4f211";
            imageSha256 = "sha256-mdyrhr4s0k/afSN/MoOgKytTHvQwLAdspCo8bqMvLgE=";
            postgresDev = pkgs.postgresql_17;
          };
          pg18 = buildPgliteFusionImage {
            imageDigest = "sha256:1ffc019dae94eca6b09a49ca67d37398951346de3c3d0cfe23d8d4ca33da83fb";
            imageSha256 = "sha256-DUokM6H8TWhHNwnMbpjvc+vmGeaxjrzlzSsS2A71/M0=";
            postgresDev = pkgs.postgresql_18;
          };
        in
        {
          inherit
            pg14
            pg15
            pg16
            pg17
            pg18
            ;

          deploy = pkgs.writeShellScriptBin "deploy" ''
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg14} docker://docker.io/frectonz/${pname}:pg14-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg14-${version} docker://docker.io/frectonz/${pname}:pg14 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg15} docker://docker.io/frectonz/${pname}:pg15-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg15-${version} docker://docker.io/frectonz/${pname}:pg15 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg16} docker://docker.io/frectonz/${pname}:pg16-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg16-${version} docker://docker.io/frectonz/${pname}:pg16 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg17} docker://docker.io/frectonz/${pname}:pg17-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg17-${version} docker://docker.io/frectonz/${pname}:pg17 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg18} docker://docker.io/frectonz/${pname}:pg18-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg18-${version} docker://docker.io/frectonz/${pname}:pg18 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg18 docker://docker.io/frectonz/${pname}:latest --dest-creds="frectonz:$ACCESS_TOKEN"
          '';
        }
      );

      formatter = forAllSystems (
        pkgs:
        pkgs.treefmt.withConfig {
          runtimeInputs = [ pkgs.nixfmt-rfc-style ];

          settings = {
            on-unmatched = "info";
            formatter.nixfmt = {
              command = "nixfmt";
              includes = [ "*.nix" ];
            };
          };
        }
      );
    };
}
