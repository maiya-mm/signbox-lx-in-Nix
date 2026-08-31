# apps/sing-box-lx/fetch-subscription.nix
# Декодирует base64 подписку, URL-decode'ит теги, парсит через parser.
# Поддерживаемые scheme в подписке: trojan://, hysteria2://, vless://
{
  pkgs,
  lib,
  parser,
}: {
  url,
  name ? "lx-subscription",
  sha256,
}: let
  downloaded = pkgs.fetchurl {
    inherit url sha256;
    name = "${name}-subscription.txt";
  };

  # Декодер: base64 → ссылки (trojan://, hysteria2://, vless://) + URL-decode тегов
  decoder = pkgs.writeShellScriptBin "decode-subscription" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        input_file="$1"

        # Пробуем декодировать как base64
        decoded=$(${pkgs.coreutils}/bin/base64 -d "$input_file" 2>/dev/null) || decoded=""

        if [ -n "$decoded" ] && echo "$decoded" | ${pkgs.gnugrep}/bin/grep -qP '^(trojan|vless|hysteria2)://'; then
          raw="$decoded"
        else
          # Fallback: читаем как plain text (любой из scheme)
          raw=$(${pkgs.gnugrep}/bin/grep -oP '^(trojan|vless|hysteria2)://.*' "$input_file" || true)
        fi

        # URL-decode percent-encoded символов (эмодзи в тегах)
        echo "$raw" | ${pkgs.python3}/bin/python3 -c "
    import urllib.parse, sys
    for line in sys.stdin:
        line = line.strip()
        if line:
            print(urllib.parse.unquote(line))
    "
  '';

  linksFile =
    pkgs.runCommand "${name}-links.txt" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      ${decoder}/bin/decode-subscription ${downloaded} > $out
    '';

  linksText = builtins.readFile linksFile;
  linksList = lib.splitString "\n" (lib.trim linksText);
  nonEmptyLinks = builtins.filter (s: s != "") linksList;

  outbounds = map parser nonEmptyLinks;
in
  outbounds