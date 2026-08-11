[CmdletBinding()]
param([string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

function Read-Tsv {
    param([string]$RelativePath)

    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required TSV was not found: $RelativePath"
    }
    return @(Import-Csv -LiteralPath $path -Delimiter "`t")
}

function Assert-UniqueValues {
    param(
        [object[]]$Rows,
        [string]$Column,
        [string]$Label
    )

    $duplicates = @($Rows | Group-Object $Column | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "$Label contains duplicate $Column values: $($duplicates.Name -join ', ')"
    }
}

function Assert-SameSet {
    param(
        [string[]]$Expected,
        [string[]]$Actual,
        [string]$Label
    )

    $expectedSet = @($Expected | Sort-Object -Unique)
    $actualSet = @($Actual | Sort-Object -Unique)
    $missing = @($expectedSet | Where-Object { $_ -notin $actualSet })
    $extra = @($actualSet | Where-Object { $_ -notin $expectedSet })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "$Label set mismatch. Missing=[$($missing -join ', ')] Extra=[$($extra -join ', ')]"
    }
}

$stringCatalog = Read-Tsv 'translation/catalog/strings.tsv'
$roomCatalog = Read-Tsv 'translation/catalog/rooms.tsv'
$objectCatalog = Read-Tsv 'translation/catalog/objects.tsv'
$objectJa = Read-Tsv 'translation/ja/objects.tsv'
$roomJa = Read-Tsv 'translation/ja/rooms.tsv'
$commandCatalog = Read-Tsv 'translation/catalog/commands.tsv'
$messageCatalog = Read-Tsv 'translation/catalog/messages.tsv'
$messageJa = Read-Tsv 'translation/ja/messages.tsv'
$verbJa = Read-Tsv 'translation/ja/verbs.tsv'
$directions = Read-Tsv 'translation/ja/directions.tsv'

$expectedCounts = @{
    strings  = 2152
    rooms    = 197
    objects  = 198
    messages = 1377
    commands = 267
}
$actualCounts = @{
    strings  = $stringCatalog.Count
    rooms    = $roomCatalog.Count
    objects  = $objectCatalog.Count
    messages = $messageCatalog.Count
    commands = $commandCatalog.Count
}
foreach ($name in $expectedCounts.Keys) {
    if ($actualCounts[$name] -ne $expectedCounts[$name]) {
        throw "Unexpected $name catalog count: expected=$($expectedCounts[$name]) actual=$($actualCounts[$name])"
    }
}

Assert-UniqueValues $roomCatalog 'id' 'Room catalog'
Assert-UniqueValues $objectCatalog 'id' 'Object catalog'
Assert-UniqueValues $messageCatalog 'id' 'Message catalog'
Assert-UniqueValues $commandCatalog 'id' 'Command catalog'
Assert-UniqueValues $roomJa 'id' 'Japanese room translations'
Assert-UniqueValues $objectJa 'id' 'Japanese object translations'
Assert-UniqueValues $messageJa 'id' 'Japanese message translations'
Assert-UniqueValues $verbJa 'verb' 'Japanese verb translations'
Assert-UniqueValues $directions 'english' 'Japanese direction translations'

Assert-SameSet @($roomCatalog.id) @($roomJa.id) 'Room translation ID'
Assert-SameSet @($objectCatalog.id) @($objectJa.id) 'Object translation ID'
Assert-SameSet @($messageCatalog.id) @($messageJa.id) 'Message translation ID'
Assert-SameSet @($commandCatalog.verb) @($verbJa.verb) 'Command verb'

$blankRooms = @($roomJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) })
$blankObjects = @($objectJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) -and $_.status -ne 'format' })
$blankVerbs = @($verbJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) })
$blankMessages = @($messageJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) -and $_.status -ne 'format' })
if ($blankRooms.Count -gt 0) {
    throw "Blank Japanese room translations: $($blankRooms.id -join ', ')"
}
if ($blankObjects.Count -gt 0) {
    throw "Blank Japanese object translations: $($blankObjects.id -join ', ')"
}
if ($blankVerbs.Count -gt 0) {
    throw "Blank Japanese verb translations: $($blankVerbs.verb -join ', ')"
}
if ($blankMessages.Count -gt 0) {
    throw "Blank Japanese message translations: $($blankMessages.id -join ', ')"
}

$expectedDirections = @('NORTH', 'SOUTH', 'EAST', 'WEST', 'NORTHEAST', 'NORTHWEST', 'SOUTHEAST', 'SOUTHWEST', 'UP', 'DOWN', 'IN', 'OUT', 'LAND')
Assert-SameSet $expectedDirections @($directions.english) 'Direction'

Write-Host ('translation catalog OK: rooms={0}, objects={1}, messages={2}, verbs={3}, directions={4}' -f $roomJa.Count, $objectJa.Count, $messageJa.Count, $verbJa.Count, $directions.Count)
