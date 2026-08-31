# vars/reject.nix
# IP-адреса и CIDR для reject (маршрут action=reject).
{
  # IP-адреса proxy серверов которые нужно исключить из urltest
  # (эти серверы не будут добавлены в outbound group).
  # Замени на свои — здесь плейсхолдеры.
  rejectServerIps = [
    "203.0.113.10"  # example-server-1 — dial errors, connection reset
    "198.51.100.42" # example-server-2 — dial errors
    "192.0.2.135"   # example-server-3 — dial errors
  ];

  # CIDR для destination IP (куда подключаешься).
  # Reject rule применяется к трафику, не к proxy серверам.
  # Здесь — диапазоны которые надо блокировать целиком (например РКН-блокировки
  # на стороне провайдера, рекламные сети, etc.). Замени на свои.
  rejectIpCidrs = [
    "198.51.100.0/24"
    "203.0.113.0/24"
  ];
}