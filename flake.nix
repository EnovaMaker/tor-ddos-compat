{
  description = "tor-ddos-compat: connection limits for a Tor relay's ORPort on any Linux, with the command set of the stopped tor-ddos scripts";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      checks.${system}.compat = import ./tests/compat.nix { inherit pkgs; src = ./.; };
    };
}
