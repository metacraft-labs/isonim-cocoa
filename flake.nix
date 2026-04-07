{
  description = "IsoNim-Cocoa — Apple platform renderer via Cocoa/UIKit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        isDarwin = pkgs.lib.hasSuffix "darwin" system;
      in
      {
        devShells.default = pkgs.mkShell {
          packages =
            [
              pkgs.nim
              pkgs.nimble
              pkgs.just
            ]
            ++ pkgs.lib.optionals isDarwin (
              with pkgs.darwin.apple_sdk.frameworks;
              [
                AppKit
                Foundation
                CoreGraphics
                CoreText
                QuartzCore
              ]
            );

          shellHook = ''
            echo "isonim-cocoa dev shell — nim $(nim --version 2>&1 | head -1)"
          '';
        };
      }
    );
}
