# apps/sing-box-lx/config.nix
# Чистая функция генерации sing-box config для sing-box-lx.
# Возвращает: { configText, configAttrs }
#
# Зависимости (всё рядом, плоская структура):
#   ./parser.nix                  — парсер trojan:// + hysteria2:// + vless+xhttp://
#   ./fetch-subscription.nix       — декодер base64 подписки
#   ../../vars/routes.nix         — маршруты (proxy/direct домены, IP CIDR)
#   ../../vars/filters.nix        — фильтры outbound-тегов
#   ../../vars/reject.nix         — reject IP CIDR, сервера для исключения
#   ../../vars/urltest.nix        — параметры urltest
#   ../../vars/servers.nix        — статические сервер-ссылки
#   ../../vars/subscription.nix   — URL/SHA256 подписки (ОТКЛЮЧЕНО, домен умер)
{
  self,
  pkgs,
  lib,
  inbounds ? [
    {
      type = "socks";
      tag = "socks-in";
      listen = "127.0.0.1";
      listen_port = 7890;
    }
    {
      type = "http";
      tag = "http-in";
      listen = "127.0.0.1";
      listen_port = 7891;
    }
    {
      type = "tproxy";
      tag = "tproxy-in";
      listen = "127.0.0.1";
      listen_port = 7892;
    }
  ],
  dnsLocalServer ? {
    type = "local";
    tag = "local";
  },
  dnsStrategy ? "prefer_ipv4",
  dnsFakeip ? null,
}: let
  # vars/ — плоско, рядом с overlays/apps/interfaces.
  varsPath = "${self.outPath}/vars";
  vpnRoutes = import "${varsPath}/routes.nix";
  vpnReject = import "${varsPath}/reject.nix";
  vpnFilters = import "${varsPath}/filters.nix";
  urltestParams = import "${varsPath}/urltest.nix";

  # 1. Парсер VPN-ссылок (trojan://, hysteria2://, vless+xhttp://)
  parseServerUrl = import ./parser.nix {inherit lib;};

  # 2. Импорт скрипта фетча подписки
  fetchSubscription = import ./fetch-subscription.nix {
    inherit pkgs lib;
    parser = parseServerUrl;
  };

  # 3. ИСТОЧНИКИ СЕРВЕРОВ
  # А) Статические (ручные ссылки из vars/servers.nix — hysteria2, vless+xhttp)
  staticServers = import "${varsPath}/servers.nix";
  staticOutbounds = map parseServerUrl staticServers.serverUrls;

  # Б) Динамические подписки — ОТКЛЮЧЕНО (подставьте свой URL/sha256 в
  # vars/subscription.nix и раскомментируйте блок ниже).
  # subscription = import "${varsPath}/subscription.nix";
  # premiumOutbounds = fetchSubscription {
  #   inherit (subscription) url sha256;
  #   name = "lx-premium";
  # };
  premiumOutbounds = [];

  # 4. Дедуплицируем теги в каждом источнике отдельно
  deduplicateTags = outbounds: let
    go = remaining: seen: acc:
      if remaining == []
      then acc
      else let
        head = builtins.head remaining;
        tail = builtins.tail remaining;
        baseTag = head.tag;
        newTag =
          if builtins.elem baseTag seen
          then "${baseTag}-${toString (builtins.length (builtins.filter (t: t == baseTag || lib.hasPrefix "${baseTag}-" t) seen))}"
          else baseTag;
        newSeen = seen ++ [newTag];
      in
        go tail newSeen (acc ++ [(head // {tag = newTag;})]);
  in
    go outbounds [] [];

  # 5. Фильтруем серверы по паттернам из vars (РКН режет их в первую очередь)
  matchesAnyPattern = tag: patterns: lib.any (p: lib.hasInfix p tag) patterns;
  filterByTag = builtins.filter (o: !(matchesAnyPattern o.tag vpnFilters.rejectOutboundTagPatterns));
  filterByIp = builtins.filter (o: !(builtins.elem o.server vpnReject.rejectServerIps));

  # 6. Применяем фильтры + дедупликацию к каждому источнику отдельно
  staticDeduped = deduplicateTags (filterByIp (filterByTag staticOutbounds));
  premiumDeduped = deduplicateTags (filterByIp (filterByTag premiumOutbounds));

  filteredOutbounds = staticDeduped ++ premiumDeduped;
  staticTags = map (o: o.tag) staticDeduped;
  premiumTags = map (o: o.tag) premiumDeduped;
  allOutboundTags = staticTags ++ premiumTags;

  # === КОНФИГУРАЦИЯ ===
  configAttrs = {
    log = {
      level = "info";
      timestamp = true;
    };
    dns =
      {
        servers = [
          dnsLocalServer
          {
            type = "tls";
            tag = "remote";
            server = "8.8.8.8";
            detour = "auto-proxy";
          }
        ];
        rules = [
          {
            domain = vpnRoutes.directDomains.exact;
            server = "local";
          }
          {
            domain_suffix = vpnRoutes.directDomains.suffix;
            server = "local";
          }
          {
            domain = vpnRoutes.proxyDomains.exact;
            server = "remote";
          }
          {
            domain_suffix = vpnRoutes.proxyDomains.suffix;
            server = "remote";
          }
        ];
        final = "local";
        strategy = dnsStrategy;
      }
      // (
        if dnsFakeip != null
        then {fakeip = dnsFakeip;}
        else {}
      );
    inbounds = inbounds;
    outbounds =
      [
        # urltest: direct первым → auto.now = direct по умолчанию.
        # Все серверы (static + premium) в auto.
        ({
            type = "urltest";
            tag = "auto";
            outbounds = ["direct"] ++ allOutboundTags;
          }
          // urltestParams)
        # selector: direct → auto → static → premium. Ручной выбор в веб-морде.
        {
          type = "selector";
          tag = "auto-proxy";
          outbounds = ["direct" "auto"] ++ staticTags ++ premiumTags;
          default = "direct";
        }
        {
          type = "direct";
          tag = "direct";
        }
      ]
      ++ filteredOutbounds;
    route = {
      default_domain_resolver = {server = "local";};
      final = "auto-proxy";
      rules = [
        {
          ip_cidr = vpnReject.rejectIpCidrs;
          action = "reject";
        }
        {
          ip_cidr = vpnRoutes.directIpCidrs;
          action = "direct";
        }
        {
          domain = vpnRoutes.directDomains.exact;
          action = "direct";
        }
        {
          domain_suffix = vpnRoutes.directDomains.suffix;
          action = "direct";
        }
        {
          domain = vpnRoutes.proxyDomains.exact;
          action = "route";
          outbound = "auto-proxy";
        }
        {
          domain_suffix = vpnRoutes.proxyDomains.suffix;
          action = "route";
          outbound = "auto-proxy";
        }
        {
          domain_keyword = ["ads" "ad" "analytics"];
          action = "reject";
        }
      ];
      auto_detect_interface = true;
    };
  };

  configText = builtins.toJSON configAttrs;
in {
  inherit configAttrs configText;
}