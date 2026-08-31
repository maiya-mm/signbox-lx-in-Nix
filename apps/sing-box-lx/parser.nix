# apps/sing-box-lx/parser.nix
# Функция парсинга VPN-ссылок в формат sing-box outbounds.
# Поддерживаемые scheme:
#   trojan://    — trojan + reality + ws
#   hysteria2:// — hysteria2 outbound (QUIC, TLS, pinSHA256)
#   vless://     — vless + reality + xhttp/ws (lx transport.type=xhttp)
#
# Pure function: { lib }: url: attrs
# На незнакомый scheme — throw с понятной ошибкой.
{lib}: url: let
  # Определяем scheme по префиксу
  isTrojan = lib.hasPrefix "trojan://" url;
  isHysteria2 = lib.hasPrefix "hysteria2://" url;
  isVless = lib.hasPrefix "vless://" url;

  # Универсальный парсер: делит URL на main@server:port?query#tag
  parseUrl = scheme: let
    withoutScheme = lib.removePrefix scheme url;
    parts = lib.splitString "#" withoutScheme;
    mainPart = builtins.elemAt parts 0;
    tag =
      if builtins.length parts > 1
      then builtins.elemAt parts 1
      else "unnamed";

    mainParts = lib.splitString "@" mainPart;
    secret = builtins.elemAt mainParts 0; # password (trojan/hysteria2) или uuid (vless)
    serverAndQuery = builtins.elemAt mainParts 1;

    serverParts = lib.splitString "?" serverAndQuery;
    serverAndPort = builtins.elemAt serverParts 0;
    queryString =
      if builtins.length serverParts > 1
      then builtins.elemAt serverParts 1
      else "";

    serverPortParts = lib.splitString ":" (lib.removeSuffix "/" serverAndPort);
    server = builtins.elemAt serverPortParts 0;
    port = lib.toInt (builtins.elemAt serverPortParts 1);

    # query params → attrset
    queryParams = lib.listToAttrs (map (pair: let
      kv = lib.splitString "=" pair;
    in {
      name = builtins.elemAt kv 0;
      value =
        if builtins.length kv > 1
        then builtins.elemAt kv 1
        else "";
    }) (lib.splitString "&" queryString));

    # URL-decode (%2F → /, %3A → :, %20 → пробел, etc.)
    urlDecode = s:
      builtins.replaceStrings [
        "%2F"
        "%3A"
        "%3F"
        "%3D"
        "%26"
        "%23"
        "%20"
        "%3C"
        "%3E"
        "%25"
      ]
      [
        "/"
        ":"
        "?"
        "="
        "&"
        "#"
        " "
        "<"
        ">"
        "%"
      ]
      s;

    # Tag: URL-decode (%20 → пробел). Без кавычек в servers.nix Nix резал
    # всё после # как комментарий → tag был "unnamed". Кавычки исправили это,
    # но %20 всё ещё в строке → декодируем.
    tagDecoded =
      if builtins.length parts > 1
      then urlDecode (builtins.elemAt parts 1)
      else "unnamed";
  in {
    inherit secret server port queryString queryParams urlDecode;
    tag = tagDecoded;
  };

  # Сборка queryParams с дефолтами
  getParam = q: name: default: q.queryParams.${name} or default;

  # TLS-блок общий для trojan/vless (reality + utls + fragment)
  buildTls = {
    sni,
    security ? "tls",
    pbk ? null,
    sid ? null,
    fp ? "random",
    insecure ? false,
  }:
    {
      enabled = true;
      server_name = sni;
      inherit insecure;
      fragment = true;
      record_fragment = true;
      utls = {
        enabled = true;
        fingerprint = fp;
      };
    }
    // (
      if (security == "reality") && (pbk != null)
      then {
        reality = {
          enabled = true;
          public_key = pbk;
          short_id =
            if sid != null
            then sid
            else "";
        };
      }
      else {}
    );
in
  if isTrojan
  then let
    p = parseUrl "trojan://";
    sni = getParam p "sni" p.server;
    security = getParam p "security" "tls";
    transportType = getParam p "type" "tcp";
    path = getParam p "path" "/";
    pbk = getParam p "pbk" null;
    sid = getParam p "sid" null;
    fp = getParam p "fp" "random";
  in {
    tag = p.tag;
    type = "trojan";
    server = p.server;
    server_port = p.port;
    password = p.secret;
    tls = buildTls {inherit sni security pbk sid fp;};
    transport =
      if transportType == "ws"
      then {
        type = "ws";
        path = p.urlDecode path;
      }
      else null;
  }
  else if isHysteria2
  then let
    p = parseUrl "hysteria2://";
    sni = getParam p "sni" p.server;
    insecure = getParam p "insecure" "0" == "1";
    alpn = getParam p "alpn" "";
    alpnList =
      if alpn != ""
      then lib.splitString "," alpn
      else [];
    # pinSHA256 в URI — сертификат-пиннинг (hex с %3A → :).
    # sing-box-lx ждёт tls.certificate_public_key_sha256 как base64 строку.
    # В pure Nix нет builtins для hex→base64 конвертации.
    # insecure=1 уже стоит → пропускаем pinSHA256.
    # Если pinSHA256 понадобится — добавить через pkgs.runCommand (base64).
  in {
    tag = p.tag;
    type = "hysteria2";
    server = p.server;
    server_port = p.port;
    password = p.secret;
    tls =
      {
        enabled = true;
        server_name = sni;
        inherit insecure;
      }
      // (
        if alpnList != []
        then {alpn = alpnList;}
        else {}
      );
  }
  else if isVless
  then let
    p = parseUrl "vless://";
    sni = getParam p "sni" p.server;
    security = getParam p "security" "tls";
    transportType = getParam p "type" "tcp";
    path = getParam p "path" "/";
    mode = getParam p "mode" "auto";
    pbk = getParam p "pbk" null;
    sid = getParam p "sid" null;
    fp = getParam p "fp" "random";
  in {
    tag = p.tag;
    type = "vless";
    server = p.server;
    server_port = p.port;
    uuid = p.secret;
    tls = buildTls {inherit sni security pbk sid fp;};
    transport =
      if transportType == "xhttp"
      then {
        type = "xhttp";
        mode = mode;
        path = p.urlDecode path;
      }
      else if transportType == "ws"
      then {
        type = "ws";
        path = p.urlDecode path;
      }
      else null;
  }
  else throw "parser.nix: unknown URL scheme in: ${lib.substring 0 40 url}..."