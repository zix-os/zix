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
  editline,
  lowdown,
  nlohmann_json,

  # Configuration Options

  version,
  nixVersion,

  # Whether to enable Markdown rendering in the Nix binary.
  enableMarkdown ? !stdenv.hostPlatform.isWindows,

  # Which interactive line editor library to use for Nix's repl.
  #
  # Currently supported choices are:
  #
  # - editline (default)
  # - readline
  readlineFlavor ? if stdenv.hostPlatform.isLinux then "zig" else "editline",
}:

let
  inherit (lib) fileset;
in

mkMesonLibrary (finalAttrs: {
  pname = "zix-cmd";
  inherit version;

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

  buildInputs = [
    (
      {
        inherit editline;
        zig = null;
      }
      .${readlineFlavor}
    )
  ] ++ lib.optional enableMarkdown lowdown;

  propagatedBuildInputs = [
    nix-util
    nix-store
    nix-fetchers
    nix-expr
    nix-flake
    nix-main
    nlohmann_json
  ];

  preConfigure =
    # "Inline" .version so it's not a symlink, and includes the suffix.
    # Do the meson utils, without modification.
    ''
      chmod u+w ./.version
      echo ${nixVersion.version} > ../../.version

      chmod u+w ./.zix-version
      echo ${version} > ../../.zix-version
    '';

  mesonFlags = [
    (lib.mesonEnable "markdown" enableMarkdown)
    (lib.mesonOption "readline-flavor" readlineFlavor)
  ];

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
