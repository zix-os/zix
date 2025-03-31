{
  lib,
  stdenv,
  lndir,
  buildEnv,

  nix-util,
  nix-util-c,
  nix-util-tests,

  nix-store,
  nix-store-c,
  nix-store-tests,

  nix-fetchers,
  nix-fetchers-tests,

  nix-expr,
  nix-expr-c,
  nix-expr-tests,

  nix-flake,
  nix-flake-c,
  nix-flake-tests,

  nix-main,
  nix-main-c,

  nix-cmd,

  nix-cli,

  nix-functional-tests,

  nix-manual,
  nix-internal-api-docs,
  nix-external-api-docs,

  nix-perl-bindings,

  testers,
}:

let
  libs =
    {
      inherit
        nix-util
        nix-util-c
        nix-store
        nix-store-c
        nix-fetchers
        nix-expr
        nix-expr-c
        nix-flake
        nix-flake-c
        nix-main
        nix-main-c
        nix-cmd
        ;
    }
    // lib.optionalAttrs
      (!stdenv.hostPlatform.isStatic && stdenv.buildPlatform.canExecute stdenv.hostPlatform)
      {
        # Currently fails in static build
        inherit
          nix-perl-bindings
          ;
      };

  dev = stdenv.mkDerivation (finalAttrs: {
    name = "zix-${nix-cli.version}-dev";
    pname = "zix";
    version = nix-cli.version;
    dontUnpack = true;
    dontBuild = true;
    libs = map lib.getDev (lib.attrValues libs);
    installPhase = ''
      mkdir -p $out/nix-support
      echo $libs >> $out/nix-support/propagated-build-inputs
    '';
    passthru = {
      tests = {
        pkg-config = testers.hasPkgConfigModules {
          package = finalAttrs.finalPackage;
        };
      };

      # If we were to fully emulate output selection here, we'd confuse the Nix CLIs,
      # because they rely on `drvPath`.
      dev = finalAttrs.finalPackage.out;

      libs = throw "`nix.dev.libs` is not meant to be used; use `nix.libs` instead.";
    };
    meta = {
      mainProgram = "nix";
      pkgConfigModules = [
        "nix-cmd"
        "nix-expr"
        "nix-expr-c"
        "nix-fetchers"
        "nix-flake"
        "nix-flake-c"
        "nix-main"
        "nix-main-c"
        "nix-store"
        "nix-store-c"
        "nix-util"
        "nix-util-c"
      ];
    };
  });
  devdoc = buildEnv {
    name = "zix-${nix-cli.version}-devdoc";
    paths = [
      nix-internal-api-docs
      nix-external-api-docs
    ];
  };

in
(buildEnv {
  name = "zix-${nix-cli.version}";
  paths = [
    nix-cli
    nix-manual.man
  ];

  /**
    Unpacking is handled in this package's constituent components
  */
  dontUnpack = true;
  /**
    Building is handled in this package's constituent components
  */
  dontBuild = true;

  /**
    `doCheck` controles whether tests are added as build gate for the combined package.
    This includes both the unit tests and the functional tests, but not the
    integration tests that run in CI (the flake's `hydraJobs` and some of the `checks`).
  */
  doCheck = true;

  /**
    `fixupPhase` currently doesn't understand that a symlink output isn't writable.

    We don't compile or link anything in this derivation, so fixups aren't needed.
  */
  dontFixup = true;

  checkInputs =
    [
      # Make sure the unit tests have passed
      nix-util-tests.tests.run
      nix-store-tests.tests.run
      nix-expr-tests.tests.run
      nix-fetchers-tests.tests.run
      nix-flake-tests.tests.run

      # Make sure the functional tests have passed
      nix-functional-tests
    ]
    ++ lib.optionals
      (!stdenv.hostPlatform.isStatic && stdenv.buildPlatform.canExecute stdenv.hostPlatform)
      [
        # Perl currently fails in static build
        # TODO: Split out tests into a separate derivation?
        nix-perl-bindings
      ];

  nativeBuildInputs = [
    lndir
  ];

  installPhase =
    let
      devPaths = lib.mapAttrsToList (_k: lib.getDev) finalAttrs.finalPackage.libs;
    in
    ''
      mkdir -p $out $dev

      # Merged outputs
      lndir ${nix-cli} $out
      for lib in ${lib.escapeShellArgs devPaths}; do
        lndir $lib $dev
      done

      # Forwarded outputs
      ln -sT ${nix-manual} $doc
      ln -sT ${nix-manual.man} $man
    '';

  passthru = {
    inherit (nix-cli) version;

    /**
      These are the libraries that are part of the Nix project. They are used
      by the Nix CLI and other tools.

      If you need to use these libraries in your project, we recommend to use
      the `-c` C API libraries exclusively, if possible.

      We also recommend that you build the complete package to ensure that the unit tests pass.
      You could do this in CI, or by passing it in an unused environment variable. e.g in a `mkDerivation` call:

      ```nix
        buildInputs = [ nix.libs.nix-util-c nix.libs.nix-store-c ];
        # Make sure the nix libs we use are ok
        unusedInputsForTests = [ nix ];
        disallowedReferences = nix.all;
      ```
    */
    inherit libs;

    /**
      Developer documentation for `nix`, in `share/doc/nix/{internal,external}-api/`.

      This is not a proper output; see `outputs` for context.
    */
    inherit devdoc;

    /**
      Extra tests that test this package, but do not run as part of the build.
      See <https://nixos.org/manual/nixpkgs/stable/index.html#var-passthru-tests>
    */
    tests = {
      pkg-config = testers.hasPkgConfigModules {
        package = finalAttrs.finalPackage;
      };
    };
  };

  meta = {
    mainProgram = "nix";
    description = "The Nix package manager";
    pkgConfigModules = dev.meta.pkgConfigModules;
  };

})
