{
  pkgs,
  version,
  postgresql,
}:
(pkgs.buildPgrxExtension {
  pname = "pglite_fusion";
  inherit version postgresql;

  cargo-pgrx = pkgs.cargo-pgrx;

  src = pkgs.lib.cleanSource ../.;
  cargoLock.lockFile = ../Cargo.lock;

  doCheck = false;
}).overrideAttrs
  (old: {
    # buildPgrxExtension blanket-marks every pgrx extension broken on darwin,
    # but this one is known to build there.
    meta = old.meta // {
      broken = false;
    };
  })
