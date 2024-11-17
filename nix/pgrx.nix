{ pkgs }:

let
  pname = "cargo-pgrx";
  version = "0.12.8";
in

pkgs.rustPlatform.buildRustPackage rec {
  inherit pname version;

  src = pkgs.fetchCrate {
    inherit version pname;
    hash = "sha256-WHxdhxc3RDsvJrag227Bju/p2OghwrN1LmbDH5RwNec=";
  };

  cargoHash = "sha256-WnKwRfM3teXrL4dWUO7pTmLcsNeRPgCXD18w/O5nhDc=";

  nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.pkg-config
  ];

  buildInputs =
    pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.openssl
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      pkgs.darwin.apple_sdk.frameworks.Security
    ];

  preCheck = ''
    export PGRX_HOME=$(mktemp -d)
  '';

  checkFlags = [
    # requires pgrx to be properly initialized with cargo pgrx init
    "--skip=command::schema::tests::test_parse_managed_postmasters"
  ];
}
