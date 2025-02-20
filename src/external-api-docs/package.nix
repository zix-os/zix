{
  lib,
  mkMesonDerivation,

  doxygen,

  # Configuration Options

  version,
  nixVersion,
}:

let
  inherit (lib) fileset;
in

mkMesonDerivation (finalAttrs: {
  pname = "zix-external-api-docs";
  inherit version nixVersion;

  workDir = ./.;
  fileset =
    let
      cpp = fileset.fileFilter (file: file.hasExt "cc" || file.hasExt "h");
    in
    fileset.unions [
      ./.version
      ../../.version
      ./.zix-version
      ../../.zix-version
      ./meson.build
      ./doxygen.cfg.in
      ./README.md
      # Source is not compiled, but still must be available for Doxygen
      # to gather comments.
      (cpp ../libexpr-c)
      (cpp ../libflake-c)
      (cpp ../libstore-c)
      (cpp ../libutil-c)
    ];

  nativeBuildInputs = [
    doxygen
  ];

  preConfigure = ''
    chmod u+w ./.version
    echo ${finalAttrs.nixVersion} > ./.version

    chmod u+w ./.zix-version
    echo ${finalAttrs.version} > ./.zix-version
  '';

  postInstall = ''
    mkdir -p ''${!outputDoc}/nix-support
    echo "doc external-api-docs $out/share/doc/nix/external-api/html" >> ''${!outputDoc}/nix-support/hydra-build-products
  '';

  meta = {
    platforms = lib.platforms.all;
  };
})
