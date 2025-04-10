{
  lib,
  stdenv,
  mkMesonDerivation,
  pkg-config,
  perl,
  perlPackages,
  nix-store,
  version,
  nixVersion,
  curl,
  bzip2,
  libsodium,
}:

let
  inherit (lib) fileset;
in

perl.pkgs.toPerlModule (
  mkMesonDerivation (finalAttrs: {
    pname = "zix-perl";
    inherit version nixVersion;

    workDir = ./.;
    fileset = fileset.unions (
      [
        ./.version
        ../../.version
        ./.zix-version
        ../../.zix-version
        ./MANIFEST
        ./lib
        ./meson.build
        ./meson.options
      ]
      ++ lib.optionals finalAttrs.doCheck [
        ./.yath.rc.in
        ./t
      ]
    );

    nativeBuildInputs = [
      pkg-config
      perl
      curl
    ];

    buildInputs = [
      nix-store
    ] ++ finalAttrs.passthru.externalBuildInputs;

    # Hack for sake of the dev shell
    passthru.externalBuildInputs = [
      bzip2
      libsodium
    ];

    # `perlPackages.Test2Harness` is marked broken for Darwin
    doCheck = !stdenv.isDarwin;

    nativeCheckInputs = [
      perlPackages.Test2Harness
    ];

    preConfigure =
      # "Inline" .version so its not a symlink, and includes the suffix
      ''
        chmod u+w .version
        echo ${finalAttrs.nixVersion} > .version

        chmod u+w .zix-version
        echo ${finalAttrs.version} > .zix-version
      '';

    mesonFlags = [
      (lib.mesonOption "dbi_path" "${perlPackages.DBI}/${perl.libPrefix}")
      (lib.mesonOption "dbd_sqlite_path" "${perlPackages.DBDSQLite}/${perl.libPrefix}")
      (lib.mesonEnable "tests" finalAttrs.doCheck)
    ];

    mesonCheckFlags = [
      "--print-errorlogs"
    ];

    strictDeps = false;
  })
)
