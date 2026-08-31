# vars/routes.nix
# Правила маршрутизации: какие домены идут через VPN, какие напрямую.
{
  # 🔥 Домены, которые ЗАВРАЧИВАЕМ в VPN
  proxyDomains = {
    exact = [
      "telegram.org"
      "t.me"
    ];
    suffix = [
      ".youtube.com"
      ".googlevideo.com"
      ".google.com"
      ".discord.com"
      ".discordapp.com"
      ".twitter.com"
      ".x.com"
      ".reddit.com"
      ".instagram.com"
      ".facebook.com"
    ];
  };

  # Домены, которые ТОЧНО идут НАПРЯМУЮ (защита рабочих/локальных ресурсов)
  directDomains = {
    exact = [
      "yandex.ru"
    ];
    suffix = [
      ".gosuslugi.ru"
      # Добавляй сюда свои корпоративные/локальные домены:
      # ".your-corp.example"
    ];
  };

  # IP-диапазоны, которые всегда напрямую (локальная сеть)
  directIpCidrs = [
    "192.168.0.0/16"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "127.0.0.0/8"
  ];
}