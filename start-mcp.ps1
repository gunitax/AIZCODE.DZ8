# Запуск Vanessa Automation с MCP-сервером для этого проекта (скилл testing-with-vanessa,
# раздел «Под своё окружение»): окно 1 — клиент тестирования на рабочей базе,
# окно 2 — менеджер тестирования в базе-менеджере, MCP на http://localhost:48100/mcp.
# Оба окна держать открытыми, пока работает агент; агента запускать после менеджера.
param(
    [string]$User = 'Администратор'
)

$ErrorActionPreference = 'Stop'

$exe = 'C:\Program Files\1cv8\8.5.1.1529\bin\1cv8c.exe'
$workBase = 'Q:\infobase\AIZCODE.DZ8'
$managerBase = 'C:\vanessa\va-manager85'
$root = $PSScriptRoot
$logs = Join-Path $root 'logs'
$profile = Join-Path $logs 'VAParams-mcp.json'
$epf = Join-Path $root 'tools\vanessa-automation-single.epf'

foreach ($path in @($exe, $epf, $profile, (Join-Path $workBase '1Cv8.1CD'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Не найдено: $path" }
}

# Клиент тестирования на рабочей базе: порт 48000 — из профиля VAParams-mcp.json.
# Если клиент уже слушает порт (повторный запуск скрипта), второй не плодить.
$clientRunning = [bool](Get-NetTCPConnection -LocalPort 48000 -State Listen -ErrorAction SilentlyContinue)
if (-not $clientRunning) {
    $clientArgs = @(
        'ENTERPRISE', "/F`"$workBase`"", "/N$User", '/TESTCLIENT', '-TPort', '48000',
        '/Lru', '/VLru'
    )
    Start-Process -FilePath $exe -ArgumentList $clientArgs -WorkingDirectory $logs
    Start-Sleep -Seconds 5
} else {
    Write-Host 'Клиент тестирования уже запущен (порт 48000) — не перезапускаю.'
}

# Менеджер тестирования с MCP-сервером — в базе-менеджере. StartFeaturePlayer плюс загрузка
# и выполнение tools\mcp\reg-mcp.feature на старте: этот сценарий включает Vanessa Editor,
# инициализирует редактор и регистрирует инструменты MCP (без него наружу торчит только
# infobase_info). КаталогФич обязан быть каталогом (не файлом): если это файл, Vanessa
# сбрасывает флаг редактора. Ключ SPPR не использовать: он ломает автозапуск сценариев.
$command = "StartFeaturePlayer;QuietInstallVanessaExt;ЗагрузитьФичи;ВыполнитьСценарии;КаталогФич=$root\tools\mcp;runMcp;mcpPort=48100;VAParams=$profile"
$managerArgs = @(
    'ENTERPRISE', "/F`"$managerBase`"", '/TESTMANAGER', '/Lru', '/VLru',
    '/DisableStartupDialogs', '/DisableStartupMessages',
    '/Out', "`"$(Join-Path $logs 'manager.log')`"",
    '/Execute', "`"$epf`"",
    '/C', "`"$command`""
)
# Рабочий каталог — logs: менеджер пишет туда кэш редактора сценариев (%1\VAEditorCacheFiles).
Start-Process -FilePath $exe -ArgumentList $managerArgs -WorkingDirectory $logs

Write-Host 'Запущены клиент тестирования (порт 48000) и менеджер с MCP.'
Write-Host 'MCP:  http://localhost:48100/mcp'
Write-Host 'Логи: ' (Join-Path $logs 'manager.log')
Write-Host 'Агента запускать после того, как менеджер откроется.'
