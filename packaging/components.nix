{
  lib,
  src,
  officialRelease,
}:

scope:

let
  inherit (scope) callPackage;

  mkVersion = baseVersion:
    rec {
      inherit baseVersion;

      versionSuffix = lib.optionalString (!officialRelease) "pre";

      fineVersionSuffix =
        lib.optionalString (!officialRelease)
          "pre${
            builtins.substring 0 8 (src.lastModifiedDate or src.lastModified or "19700101")
          }_${src.shortRev or "dirty"}";

      fineVersion = baseVersion + fineVersionSuffix;

      version = baseVersion + versionSuffix;
    };

  nixVersion = mkVersion (lib.fileContents ../.version);
  zixVersion = mkVersion (lib.fileContents ../.zix-version);
in

# This becomes the pkgs.zixComponents attribute set
{
  version = with zixVersion; baseVersion + versionSuffix;
  inherit (zixVersion) versionSuffix;
  inherit nixVersion;

  nix-util = callPackage ../src/libutil/package.nix { };
  nix-util-c = callPackage ../src/libutil-c/package.nix { };
  nix-util-test-support = callPackage ../src/libutil-test-support/package.nix { };
  nix-util-tests = callPackage ../src/libutil-tests/package.nix { };

  nix-store = callPackage ../src/libstore/package.nix { };
  nix-store-c = callPackage ../src/libstore-c/package.nix { };
  nix-store-test-support = callPackage ../src/libstore-test-support/package.nix { };
  nix-store-tests = callPackage ../src/libstore-tests/package.nix { };

  nix-fetchers = callPackage ../src/libfetchers/package.nix { };
  nix-fetchers-tests = callPackage ../src/libfetchers-tests/package.nix { };

  nix-expr = callPackage ../src/libexpr/package.nix { };
  nix-expr-c = callPackage ../src/libexpr-c/package.nix { };
  nix-expr-test-support = callPackage ../src/libexpr-test-support/package.nix { };
  nix-expr-tests = callPackage ../src/libexpr-tests/package.nix { };

  nix-flake = callPackage ../src/libflake/package.nix { };
  nix-flake-c = callPackage ../src/libflake-c/package.nix { };
  nix-flake-tests = callPackage ../src/libflake-tests/package.nix { };

  nix-main = callPackage ../src/libmain/package.nix { };
  nix-main-c = callPackage ../src/libmain-c/package.nix { };

  nix-cmd = callPackage ../src/libcmd/package.nix { };

  nix-cli = callPackage ../src/nix/package.nix { version = zixVersion.fineVersion; };

  nix-functional-tests = callPackage ../src/nix-functional-tests/package.nix {
    version = zixVersion.fineVersion;
  };

  nix-manual = callPackage ../doc/manual/package.nix { version = zixVersion.fineVersion; };
  nix-internal-api-docs = callPackage ../src/internal-api-docs/package.nix { version = zixVersion.fineVersion; };
  nix-external-api-docs = callPackage ../src/external-api-docs/package.nix { version = zixVersion.fineVersion; };

  nix-perl-bindings = callPackage ../src/perl/package.nix { };

  nix-everything = callPackage ../packaging/everything.nix { };
}
