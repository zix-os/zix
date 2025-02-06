{
  lib,
  stdenv,
  mkMesonLibrary,

  boost,
  brotli,
  libarchive,
  libsodium,
  nlohmann_json,
  openssl,

  # Configuration Options

  version,
  nixVersion,
}:

let
  inherit (lib) fileset;
in

mkMesonLibrary (finalAttrs: {
  pname = "zix-util";
  inherit version;

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
    openssl
  ];

  propagatedBuildInputs = [
    boost
    libarchive
    nlohmann_json
  ];

  preConfigure =
    # "Inline" .version so it's not a symlink, and includes the suffix.
    # Do the meson utils, without modification.
    #
    # TODO: change release process to add `pre` in `.version`, remove it
    # before tagging, and restore after.
    ''
      chmod u+w ./.version
      echo ${nixVersion.version} > ../../.version

      chmod u+w ./.zix-version
      echo ${version} > ../../.zix-version
    '';

  mesonFlags = [
    (lib.mesonBool "cpuid" (stdenv.hostPlatform.isx86_64 || stdenv.hostPlatform.isAarch64))
  ];

  env = {
    # Needed for Meson to find Boost.
    # https://github.com/NixOS/nixpkgs/issues/86131.
    BOOST_INCLUDEDIR = "${lib.getDev boost}/include";
    BOOST_LIBRARYDIR = "${lib.getLib boost}/lib";
  };

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
