{pkgs, ...}:
let nimctx = pkgs.buildNimPackage {
  pname    = "nimctx";
  version  = "0.1.0";
  src      = pkgs.fetchgit (builtins.fromJSON (builtins.readFile ./nimctx.lock)).src;
  lockFile = ./nimctx.lock;
  doCheck  = false;
  buildInputs = [ pkgs.sqlite ];
};
in
{
  packages = [nimctx];
}
