# Пакетный прогон сценария Vanessa Automation: отчет в reports\run-<дата-время>
# (status.txt, junit.xml, steps.log, manager.log, screenshots).
# Менеджер тестирования поднимается в базе-менеджере, тестовый клиент — в рабочей базе.
# Порты 48050-48099, чтобы не задеть клиента тестирования, подключенного к MCP (48000-48049).
# Значения по умолчанию — окружение этого проекта (скилл testing-with-vanessa, раздел «Под своё окружение»).
param(
    [Parameter(Mandatory = $true)][string]$Feature,
    [string]$Profile = 'bsp32',
    [string]$User = 'Администратор',
    [string]$BasePath = 'Q:\infobase\AIZCODE.DZ8',
    [string]$ManagerBase = 'C:\vanessa\va-manager85',
    [switch]$PreLaunchClient,
    [int]$ClientPort = 48050,
    [int]$TimeoutMinutes = 10,
    [string]$Exe = 'C:\Program Files\1cv8\8.5.1.1529\bin\1cv8c.exe'
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$epf = Join-Path $root 'tools\vanessa-automation-single.epf'

foreach ($path in @($Exe, $epf, $ManagerBase)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Не найдено: $path" }
}
if (-not (Test-Path -LiteralPath (Join-Path $BasePath '1Cv8.1CD'))) {
    throw "В файловой базе не найден 1Cv8.1CD: $BasePath"
}
if (-not (Test-Path -LiteralPath $Feature)) { throw "Не найден сценарий: $Feature" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $root "reports\run-$stamp"
New-Item $report, (Join-Path $report 'screenshots') -ItemType Directory -Force | Out-Null
$paramsPath = Join-Path $report 'VAParams.json'

# Предзапуск тестового клиента (если -PreLaunchClient). На этой машине WshShell.Run не запускает
# bat-файлы, и штатный запуск клиента из Vanessa падает («Не удается дождаться процесса»).
# Тогда клиент запускает этот скрипт, а Vanessa подключается к нему по TCP: в профиле клиента
# задается ИмяКомпьютера 127.0.0.2 — не localhost, чтобы Vanessa не пыталась запустить клиента сама.
$portBase = $ClientPort
$clientProc = $null
if ($PreLaunchClient) {
    $testPort = $null
    foreach ($p in ($ClientPort..($ClientPort + 49))) {
        if (-not (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)) { $testPort = $p; break }
    }
    if (-not $testPort) { throw "Нет свободного порта в диапазоне $ClientPort-$($ClientPort + 49)" }
    $clientArgs = @(
        'ENTERPRISE', "/F`"$BasePath`"", '/TESTCLIENT', '-TPort', "$testPort",
        '/Lru', '/VLru', '/DisableStartupDialogs', '/DisableStartupMessages'
    )
    if ($User) { $clientArgs += "/N$User" }
    Write-Host "Клиент 1С:  $Exe (предзапуск, порт $testPort)"
    $clientProc = Start-Process -FilePath $Exe -ArgumentList $clientArgs -PassThru
    $clientDeadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $clientDeadline) {
        if ($clientProc.HasExited) { throw "Тестовый клиент завершился сразу после запуска (код $($clientProc.ExitCode))" }
        if (Get-NetTCPConnection -LocalPort $testPort -State Listen -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Seconds 1
    }
    if (-not (Get-NetTCPConnection -LocalPort $testPort -State Listen -ErrorAction SilentlyContinue)) {
        throw "Тестовый клиент не открыл порт $testPort за 90 с; процесс остановлен (PID $($clientProc.Id))"
    }
    $portBase = $testPort
}

$params = [ordered]@{
    'КаталогФич' = (Resolve-Path $Feature).Path
    'ВыполнитьСценарии' = $true
    'ЗавершитьРаботуСистемы' = $true
    'ТаймаутЗапуска1С' = 120
    'ИспользоватьКомпонентуVanessaExt' = $true
    'ИскатьЭлементыФормыПоИмени' = $true
    'ДелатьОтчетВФорматеjUnit' = $true
    'КаталогВыгрузкиJUnit' = $report
    'ВыгружатьСтатусВыполненияСценариевВФайл' = $true
    'ПутьКФайлуДляВыгрузкиСтатусаВыполненияСценариев' = (Join-Path $report 'status.txt')
    'ДелатьЛогВыполненияСценариевВТекстовыйФайл' = $true
    'ИмяФайлаЛогВыполненияСценариев' = (Join-Path $report 'steps.log')
    'ДелатьСкриншотПриВозникновенииОшибки' = $true
    'ИспользоватьВнешнююКомпонентуДляСкриншотов' = $true
    'СпособСнятияСкриншотовВнешнейКомпонентой' = 1
    'КаталогВыгрузкиСкриншотов' = (Join-Path $report 'screenshots')
    'ЗакрытьTestClientПослеЗапускаСценариев' = $true
    'ДиапазонПортовTestclient' = "$portBase-$($portBase + 49)"
    'ДанныеКлиентовТестирования' = @([ordered]@{
        'Имя' = $Profile
        'Синоним' = $Profile
        'ТипКлиента' = 'Тонкий'
        'ПутьКИнфобазе' = "File=`"$BasePath`";"
        'ПортЗапускаТестКлиента' = $portBase
        'ИмяКомпьютера' = $(if ($PreLaunchClient) { '127.0.0.2' } else { 'localhost' })
        'ДопПараметры' = $(if ($User) { "/N$User" } else { '' })
    })
}
$json = $params | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($paramsPath, $json, (New-Object Text.UTF8Encoding($false)))

$command = "StartFeaturePlayer;QuietInstallVanessaExt;DisableFirstRunHelper;VAParams=$paramsPath"
$arguments = @(
    'ENTERPRISE', "/F`"$ManagerBase`"", '/TESTMANAGER', '/Lru', '/VLru',
    '/DisableStartupDialogs', '/DisableStartupMessages',
    '/Execute', "`"$epf`"", '/C', "`"$command`"",
    '/Out', "`"$(Join-Path $report 'manager.log')`""
)
Write-Host "Сценарий: $((Resolve-Path $Feature).Path)"
Write-Host "Отчет:    $report"
$process = $null
try {
    $process = Start-Process -FilePath $Exe -ArgumentList $arguments -PassThru -WorkingDirectory $report
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $process.Refresh()
    }
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        throw "Менеджер Vanessa не завершился за $TimeoutMinutes мин; остановлен свой PID $($process.Id). Отчет: $report"
    }
} finally {
    # Свой тестовый клиент закрываем всегда: сама Vanessa может не успеть, если сценарий упал.
    if ($clientProc -and -not $clientProc.HasExited) {
        Stop-Process -Id $clientProc.Id -Force -ErrorAction SilentlyContinue
    }
}

$statusFile = Join-Path $report 'status.txt'
$status = if (Test-Path $statusFile) { (Get-Content $statusFile -Raw).Trim() } else { '' }
$junitFile = Join-Path $report 'junit.xml'
if (-not (Test-Path $junitFile)) { throw "Нет отчета jUnit; статус '$status'; лог менеджера: $report\manager.log" }
[xml]$junit = Get-Content $junitFile -Raw -Encoding UTF8
$cases = @($junit.SelectNodes('//testcase'))
$failed = @($cases | Where-Object { $_.failure -or $_.error -or $_.skipped })
foreach ($case in $cases) {
    $mark = if ($case.failure -or $case.error -or $case.skipped) { 'X' } else { 'v' }
    Write-Host ("{0} {1}" -f $mark, $case.name)
}
if ($status -ne '0' -or $cases.Count -eq 0 -or $failed.Count -gt 0) {
    throw "Сценарии не прошли: статус '$status', сценариев $($cases.Count), сбоев $($failed.Count). Отчет: $report"
}
Write-Host "Готово: сценариев $($cases.Count), статус 0. Отчет: $report"
