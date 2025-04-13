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
          cargo-pgrx = import ./nix/pgrx.nix { inherit pkgs; };

          pname = "pglite-fusion";
          version = "0.0.5";

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
                  inherit pkgs cargo-pgrx;
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

          pg12 = buildPgliteFusionImage {
            imageDigest = "sha256:ee9f333b422b396016648289933a8f2d3ffa79703510b2e0641e3a4a125b96b6";
            imageSha256 = "sha256-f+OkqB6mW8UP0Z6fCCfAB257ztQAtaPQ2T2SVlu8MmY=";
            postgresDev = pkgs.postgresql_12.dev;
          };
          pg13 = buildPgliteFusionImage {
            imageDigest = "sha256:80ff9e2086e68aef09839045df1f07016b869d94cbd12c6462a4b300878cfdac";
            imageSha256 = "sha256-iaUdJa/l0rgNkZR/FUoJ4bzmW/2CRWyk+eMHibBqIus=";
            postgresDev = pkgs.postgresql_13.dev;
          };
          pg14 = buildPgliteFusionImage {
            imageDigest = "sha256:78b9deeca08fa9749a00e9d30bc879f8f8d021af854c73e2c339b752cb6d708a";
            imageSha256 = "sha256-LV2V6kuctIjN4gMxfopZSdivFtz7ks+AGmYQ4ets8b0=";
            postgresDev = pkgs.postgresql_14.dev;
          };
          pg15 = buildPgliteFusionImage {
            imageDigest = "sha256:a35b3c0190dac5a82ec1778b34cb4963bdd9d161f80381a6297be6e2c3c13a7c";
            imageSha256 = "sha256-ZK6eBPA50mY99uSF3+UdT4eBm/3komc6sfWb1qw1N7k=";
            postgresDev = pkgs.postgresql_15.dev;
          };
          pg16 = buildPgliteFusionImage {
            imageDigest = "sha256:5d65b8bdb20369ea902b987aa63cfe4983130bc8cd2c25830d126636b80b608d";
            imageSha256 = "sha256-5JhtZaCLj6SnJzjhC5A2yrP6fipuaQKHSxm3jhxSfNg=";
            postgresDev = pkgs.postgresql_16.dev;
          };
          pg17 = buildPgliteFusionImage {
            imageDigest = "sha256:994cc3113ce004ae73df11f0dbc5088cbe6bb0da1691dd7e6f55474202a4f211";
            imageSha256 = "sha256-OzqtbX89/lBP2mzhSccuad5suUz/uw/gBgeIW3BTbdc=";
            postgresDev = pkgs.postgresql_17.dev;
          };
        in
        {
          inherit
            pg12
            pg13
            pg14
            pg15
            pg16
            pg17
            ;

          deploy = pkgs.writeShellScriptBin "deploy" ''
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg12} docker://docker.io/frectonz/${pname}:pg12-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg12-${version} docker://docker.io/frectonz/${pname}:pg12 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg13} docker://docker.io/frectonz/${pname}:pg13-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg13-${version} docker://docker.io/frectonz/${pname}:pg13 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg14} docker://docker.io/frectonz/${pname}:pg14-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg14-${version} docker://docker.io/frectonz/${pname}:pg14 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg15} docker://docker.io/frectonz/${pname}:pg15-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg15-${version} docker://docker.io/frectonz/${pname}:pg15 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg16} docker://docker.io/frectonz/${pname}:pg16-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg16-${version} docker://docker.io/frectonz/${pname}:pg16 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker-archive:${pg17} docker://docker.io/frectonz/${pname}:pg17-${version} --dest-creds="frectonz:$ACCESS_TOKEN"
            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg17-${version} docker://docker.io/frectonz/${pname}:pg17 --dest-creds="frectonz:$ACCESS_TOKEN"

            ${pkgs.skopeo}/bin/skopeo --insecure-policy copy docker://docker.io/frectonz/${pname}:pg17 docker://docker.io/frectonz/${pname}:latest --dest-creds="frectonz:$ACCESS_TOKEN"
          '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
