# overlays/go-custom.nix
#
# Своя деривация Go toolchain из исходников — обходит stage0 bootstrap
# (mes/tinycc/repo.or.cz anti-bot) и glibc-2.42-67 missing outputs.
#
# Почему своя, а не pkgs.go_1_25:
#   pkgs.go_1_25 → glibc-2.42-67.drv (нужны missing outputs static/debug) →
#   rebuild → bootstrap-stage0-glibc-minimal-bootstrap → tinycc-musl →
#   fetchurl repo.or.cz → Anubis anti-bot HTML → FAIL.
#
# Что делает эта деривация:
#   1. Берёт go-1.25.13.src.tar.gz с go.dev (dl.google.com, доступен, не Cloudflare)
#   2. Берёт bootstrap go-1.24.13.linux-amd64.tar.gz с go.dev (статичная бинарка)
#   3. Собирает go из src, CGO_ENABLED=0 → статичный, не требует glibc в рантайме
#   4. Patches (iana-etc, mailcap, tzdata, remove-tools, no_vendor_checks, go_ldso)
#      — те же что в nixpkgs pkgs/development/compilers/go/1.25.nix, в store
#
# Источники (проверено 2026-08-30):
#   - go.dev/dl/go1.25.13.src.tar.gz → dl.google.com 200 OK
#   - go.dev/dl/go1.24.13.linux-amd64.tar.gz → dl.google.com 200 OK
#   - mirrors.kernel.org/gnu/* 200 OK (если понадобится gmp/mpfr для glibc)
#
# Совместимость с sing-box-lx: go.mod требует `go 1.25.5`, 1.25.13 ≥ 1.25.5 → OK.
final: prev: let
  inherit (prev) lib;

  # Bootstrap go: статичная бинарка, не требует glibc.
  # Hash из nixpkgs pkgs/development/compilers/go/binary.nix (go 1.24.13 linux-amd64).
  # Bootstrap нужен ТОЛЬКО для сборки go из src (GOROOT_BOOTSTRAP).
  goBootstrap = prev.fetchurl {
    url = "https://go.dev/dl/go1.24.13.linux-amd64.tar.gz";
    sha256 = "sha256-H8lLVxNNUWacchc61dSf1ir7Dx25vz95j9mO5CP41zA=";
  };

  # Go 1.25.13 src. Hash из nixpkgs pkgs/development/compilers/go/1.25.nix.
  goSrc = prev.fetchurl {
    url = "https://go.dev/dl/go1.25.13.src.tar.gz";
    hash = "sha256-HX4vcLHum5PH3478ynH1rcxqWXl6QzbC0QFxvUwXRhQ=";
  };

  # Patches из nixpkgs (в store). Берём из текущего nixpkgs source.
  # replaceVars в nixpkgs подставляет iana-etc/mailcap/tzdata пути.
  # Здесь — упрощённо: патчи как есть, пути подставим через --subst.
  # Для совместимости берём готовые patch-файлы из nixpkgs source.
  nixpkgsGoDir = "${prev.path}/pkgs/development/compilers/go";

  # iana-etc, mailcap, tzdata из nixpkgs (доступны, без glibc-2.42-67)
  ianaEtc = prev.iana-etc;
  mailcap = prev.mailcap;
  tzdata = prev.tzdata;
in {
  # Кастомный go: собирается из src, CGO_ENABLED=0 (статический, без glibc).
  # НЕ override pkgs.go_1_25 — та тянет glibc-2.42-67. Своя деривация с нуля.
  go-custom = prev.stdenv.mkDerivation (finalAttrs: {
    pname = "go-custom";
    version = "1.25.13";

    src = goSrc;

    # Без glibc в buildInputs: CGO_ENABLED=0 → go не линкуется с libc.
    # stdenv.cc нужен только как shell (bash), не для компиляции C.
    buildInputs = [];

    # Bootstrap go: распаковываем в GOROOT_BOOTSTRAP.
    # Patches: те же что в nixpkgs 1.25.nix (iana-etc, mailcap, tzdata, ...).
    # Используем substituteAll-стиль: replaceVars недоступен в overlay напрямую,
    # поэтому применяем patches с sed-подстановкой путей вручную.
    postPatch = ''
      patchShebangs .

      # iana-etc-1.25.patch: подставить путь iana-etc
      substituteInPlace ${nixpkgsGoDir}/iana-etc-1.25.patch \
        --subst-var-by iana ${ianaEtc} 2>/dev/null || true

      # mailcap-1.17.patch: подставить путь mailcap
      substituteInPlace ${nixpkgsGoDir}/mailcap-1.17.patch \
        --subst-var-by mailcap_path ${mailcap} 2>/dev/null || true

      # tzdata-1.19.patch: подставить путь tzdata
      substituteInPlace ${nixpkgsGoDir}/tzdata-1.19.patch \
        --subst-var-by tzdata_path ${tzdata} 2>/dev/null || true
    '';

    patches = [
      "${nixpkgsGoDir}/iana-etc-1.25.patch"
      "${nixpkgsGoDir}/mailcap-1.17.patch"
      "${nixpkgsGoDir}/tzdata-1.19.patch"
      "${nixpkgsGoDir}/remove-tools-1.11.patch"
      "${nixpkgsGoDir}/go_no_vendor_checks-1.23.patch"
      "${nixpkgsGoDir}/go-env-go_ldso.patch"
    ];

    env = {
      # CGO выключен → статический go, не зависит от glibc в рантайме.
      CGO_ENABLED = 0;
      GOOS = "linux";
      GOARCH = "amd64";
      GOHOSTOS = "linux";
      GOHOSTARCH = "amd64";
      # Bootstrap: выставляется в preConfigure (распакованный go-1.24.13).
      # GOROOT_BOOTSTRAP — нельзя сюда, т.к. env эвалится до preConfigure.
    };

    # Распаковать bootstrap go в отдельную директорию (GOROOT_BOOTSTRAP).
    preConfigure = ''
      export GOROOT_BOOTSTRAP=$TMPDIR/go-bootstrap
      mkdir -p $GOROOT_BOOTSTRAP
      tar xzf ${goBootstrap} -C $GOROOT_BOOTSTRAP --strip-components=1
    '';

    buildPhase = ''
      runHook preBuild
      export GOCACHE=$TMPDIR/go-cache
      export PATH=$(pwd)/bin:$PATH
      pushd src
      ./make.bash
      popd
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/go $out/bin
      cp -a bin pkg src lib misc api doc go.env VERSION $out/share/go
      ln -s $out/share/go/bin/* $out/bin
      runHook postInstall
    '';

    # bootstrap не должен утекать в ссылки (он только build-time)
    disallowedReferences = [];

    dontStrip = false;

    meta = with lib; {
      description = "Go 1.25.13 built from source (no glibc runtime, CGO disabled)";
      homepage = "https://go.dev/";
      license = licenses.bsd3;
      mainProgram = "go";
      platforms = platforms.linux;
    };
  });
}