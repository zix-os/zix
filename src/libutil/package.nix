{
  lib,
  stdenv,
  mkMesonLibrary,

  boost,
  brotli,
  libarchive,
  libsodium,
  nlohmann_json,

  # Configuration Options

  version,
  nixVersion,
}:

let
  inherit (lib) fileset;
in

mkMesonLibrary (finalAttrs: {
  pname = "zix-util";
  inherit version nixVersion;

  workDir = ./.;
  fileset = fileset.unions [
    ../../nix-meson-build-support
    ./nix-meson-build-support
    ../../.version
    ./.version
    ../../.zix-version
    ./.zix-version
    ./widecharwidth
    ./meson.build
    ./meson.options
    ./linux/meson.build
    ./unix/meson.build
    ./windows/meson.build
    (fileset.fileFilter (file: file.hasExt "cc") ./.)
    (fileset.fileFilter (file: file.hasExt "hh") ./.)
    (fileset.fileFilter (file: file.hasExt "zig") ./.)
  ];

  buildInputs = [
    brotli
    libsodium
  ];

  propagatedBuildInputs = [
    boost
    libarchive
    nlohmann_json
  ];

  mesonFlags = [
    (lib.mesonBool "cpuid" (stdenv.hostPlatform.isx86_64 || stdenv.hostPlatform.isAarch64))
  ];

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
