# vars/filters.nix
# Паттерны для исключения outbound-тегов из urltest/selector.
# Если тег сервера содержит любой из этих паттернов — сервер не попадёт в конфиг.
{
  rejectOutboundTagPatterns = [ "RUS" ];
}