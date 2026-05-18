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
            ++ pkgs.lib.optionals isDarwin [
              # Apple frameworks (AppKit, Foundation, CoreGraphics, CoreText,
              # QuartzCore, WebKit, AVKit, MapKit) are provided by the default
              # Apple SDK now that darwin.apple_sdk_11_0 has been removed.
              # See https://github.com/NixOS/nixpkgs (Darwin migration notes).
              pkgs.apple-sdk_15

              # iOS device deployment & Xcode project generation
              pkgs.ios-deploy
              pkgs.xcodegen
            ];

          shellHook = ''
            echo "isonim-cocoa dev shell — nim $(nim --version 2>&1 | head -1)"
          '';
        };
      }
    );
}
