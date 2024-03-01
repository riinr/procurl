{
  description = "Dev Environment";

  inputs.dsf.url     = "github:cruel-intentions/devshell-files";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.dsf.inputs.nixpkgs.follows = "nixpkgs";

  outputs = inputs: inputs.dsf.lib.shell inputs [
    # "hello"      # import nix package
    ./project.nix  # import nix module
  ];
}
