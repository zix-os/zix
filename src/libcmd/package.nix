{
  lib,
  stdenv,
  mkMesonLibrary,

  nix-util,
  nix-store,
  nix-fetchers,
  nix-expr,
  nix-flake,
  nix-main,
  lowdown,
  nlohmann_json,

  # Configuration Options

  version,
  nixVersion,
  zixVersion,

  # Whether to enable Markdown rendering in the Nix binary.
  enableMarkdown ? !stdenv.hostPlatform.isWindows,
}:

let
  inherit (lib) fileset;
in

mkMesonLibrary (finalAttrs: {
  pname = "zix-cmd";
  inherit version nixVersion;

  workDir = ./.;
  fileset = fileset.unions [
    ../../nix-meson-build-support
    ./nix-meson-build-support
    ../../.version
    ./.version
    ../../.zix-version
    ./.zix-version
    ./meson.build
    ./meson.options
    (fileset.fileFilter (file: file.hasExt "cc") ./.)
    (fileset.fileFilter (file: file.hasExt "hh") ./.)
    (fileset.fileFilter (file: file.hasExt "zig") ./.)
  ];

  buildInputs = lib.optional enableMarkdown lowdown;

  propagatedBuildInputs = [
    nix-util
    nix-store
    nix-fetchers
    nix-expr
    nix-flake
    nix-main
    nlohmann_json
  ];

  mesonFlags = [
    (lib.mesonEnable "markdown" enableMarkdown)
  ];

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
