# overlays/sing-box-lx.nix
#
# sing-box-lx — отдельная деривация форка Leadaxe/sing-box-lx (branch lx).
# НЕ .override от pkgs.sing-box: upstream package.nix тянет baggage
# (cronet-go, postInstall с systemd units, polkit rules, cronet-go.patch),
# который форку не нужен. Канонический паттерн для Go-форков в nixpkgs —
# своя деривация через buildGoModule с нуля.
#
# Go toolchain: final.go-custom (своя деривация из src, CGO_ENABLED=0).
# НЕ pkgs.go_1_25 / buildGo125Module — те тянут glibc-2.42-67 (missing
# outputs static/debug) → rebuild → stage0 bootstrap → tinycc-musl →
# repo.or.cz anti-bot. См. overlays/go-custom.nix.
#
# src: fetchgit с fetchSubmodules=true. go.mod lx содержит 3 replace-директивы
#   (wireguard-go, sing-tun, gvisor → ./submodules/*), которые требуют
#   субмодули. fetchFromGitHub без submodules не сработает.
#
# vendorHash: lib.fakeHash → nix build выдаст `got: sha256-XXX` → подставить.
final: prev: {
  sing-box-lx =
    (prev.buildGoModule.override {
      # Переопределяем go на уровне buildGoModule (callPackage) — иначе
      # buildGo126Module привязывает go_1_26 в nativeBuildInputs, который
      # тянет glibc-2.42-67. .override { go = ... } перебивает callPackage-аргумент.
      go = final.go-custom;
    }) rec {
      pname = "sing-box-lx";
      version = "1.14.0-lx.29";

      src = prev.fetchgit {
        url = "https://github.com/Leadaxe/sing-box-lx.git";
        rev = "ff40cf98cb80ca6c9e9ae823ad392045cb4d23de";
        fetchSubmodules = true;
        hash = "sha256-syM4iES5FPG2RH8RilsrVmboF8LvhSDgeVbUSJRBE44=";
      };

      # Go toolchain — наш кастомный (go 1.25.13 из src, статический, без glibc).
      go = final.go-custom;

      # vendorHash вычислен первой сборкой (lib.fakeHash → nix build выдал got).
      vendorHash = "sha256-K2+VDAhnHWawAD2To0GEH0XiznAKnpUMg4xZElGMx7U=";

      # Минимальный набор для TPROXY-клиента + xhttp + Clash API (дизайн-док 10.design, §Build tags).
      # badlinkname/tfogo_checklinkname0 — нужны для with_purego-патчей линкера.
      tags = [
        "with_xhttp"
        "with_utls"
        "with_clash_api"
        "with_quic"
        "with_wireguard"
        "with_gvisor"
        "with_dhcp"
        "with_tailscale"
        "badlinkname"
        "tfogo_checklinkname0"
      ];

      subPackages = ["cmd/sing-box"];

      ldflags = [
        "-X=github.com/sagernet/sing-box/constant.Version=${version}"
        "-checklinkname=0"
        "-s"
        "-w"
      ];

      env.CGO_ENABLED = 0;

      doCheck = false;

      meta = with prev.lib; {
        description = "Sing-box fork with xhttp transport and tailscale endpoint";
        homepage = "https://github.com/Leadaxe/sing-box-lx";
        license = licenses.gpl3Plus;
        mainProgram = "sing-box";
        platforms = platforms.linux;
      };
    };
}