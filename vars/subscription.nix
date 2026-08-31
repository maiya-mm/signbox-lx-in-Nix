# vars/subscription.nix
# Динамическая подписка (base64) от VPN-провайдера.
# Раскомментируй блок в apps/sing-box-lx/config.nix чтобы включить.
#
# sha256 считается по содержимому которое отдаёт URL БЕЗ User-Agent
# (fetchurl качает без UA). Если провайдер отдаёт разный контент по UA —
# придётся sha256 пересчитывать после каждого изменения подписки.
{
  url = "https://your-provider.example/smartsub/YOUR-TOKEN-HERE";
  sha256 = "sha256-REPLACE-WITH-nix-hash-file-OUTPUT";
}