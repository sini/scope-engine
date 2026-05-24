{
  lib,
  engine,
  schemaLib,
  graphLib,
  genLib,
}:
let
  fleet = import ./fleet.nix;
in
{
  inherit fleet;
  # Placeholder — wired in milestone 2
  evalSchema = null;
}
