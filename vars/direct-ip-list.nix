# vars/direct-ip-list.nix
# IP-адреса которые ВСЕГДА идут напрямую (мимо VPN).
# Используются в interfaces/systemd.services.sing-box.nix для генерации
# nftables правил (chain prerouting + chain output).
#
# Сюда кладут корпоративные/рабочие ресурсы, локальные сервисы, etc.
{
  directIpCidrs = [
    # Подсети (пример):
    # "10.0.0.0/8"

    # Отдельные IP (пример):
    # "192.168.1.100"

    # Добавлять новые IP сюда
  ];
}