# vars/servers.nix
# Список сырых ссылок на VPN-серверы.
# Поддерживаемые scheme: trojan://, hysteria2://, vless:// (с type=xhttp или type=ws).
#
# Эти серверы попадают в selector "auto-proxy" ПОСЛЕ direct и auto,
# а также в urltest "auto" (где sing-box выбирает лучший по пингу).
#
# ⚠️  ВАЖНО: строки в кавычках! Без кавычек Nix резал всё после # как комментарий,
#     и тег сервера превращался в "unnamed". С кавычками — парсится как tag.
#     %20 в теге URL-decode'ится парсером → "Amsterdam Hysteria2".
{
  serverUrls = [
    # --- ПРИМЕРЫ (замени на свои сервера) ---

    # hysteria2: QUIC + TLS + pinSHA256 (сертификат-пиннинг, опускается при insecure=1)
    "hysteria2://YOUR-PASSWORD-HERE@YOUR-SERVER-IP:443/?sni=your.sni.example&alpn=h3&insecure=1#Amsterdam%20Hysteria2"

    # vless + reality + xhttp (lx transport.type=xhttp — главная фича форка)
    "vless://YOUR-UUID-HERE@YOUR-SERVER-IP:8443?encryption=none&security=reality&sni=www.yandex.ru&fp=chrome&pbk=YOUR-PUBLIC-KEY&sid=&type=xhttp&path=%2Fyour-path-here&mode=stream-up#Amsterdam%20XHTTP%20stream-up"

    # trojan + reality + ws (для сравнения/fallback)
    # "trojan://YOUR-PASSWORD@YOUR-SERVER:443?security=reality&sni=your.sni&pbk=YOUR-PBK&sid=YOUR-SID&type=ws&path=%2Fpath#Your%20Tag"

    # Добавлять новые ключи сюда. Если сервер упал - закомментируй строку.
  ];
}