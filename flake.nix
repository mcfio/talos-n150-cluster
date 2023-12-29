{
  description = "manage home-cluster environment with nix";

  inputs = {
    # nixpkgs - set the url to master, want the latest, always
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    }:

    # The shell environment is intended for all systems
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        config.allowUnfree = true;
        inherit system;
      };
    in
    {
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          kubectl
          kubectl-cnpg
          kubectl-view-secret
          talosctl
          kubernetes-helm
          fluxcd
          cilium-cli
          stern
          terraform
          go-task
        ];
        shellHook = ''
          task
        '';
      };
    });
}
