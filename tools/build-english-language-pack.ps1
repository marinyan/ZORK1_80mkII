[CmdletBinding()]
param([string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$catalogRoot = Join-Path $RepoRoot 'translation/catalog'
$jaRoot = Join-Path $RepoRoot 'translation/ja'
$outputRoot = Join-Path $RepoRoot 'translation/en'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

function Read-Tsv([string]$Path) {
    return @(Import-Csv -LiteralPath $Path -Delimiter "`t")
}

function Write-Tsv([object[]]$Rows, [string]$Name) {
    $path = Join-Path $outputRoot $Name
    $Rows | Export-Csv -LiteralPath $path -Delimiter "`t" -NoTypeInformation -Encoding utf8 -UseQuotes Always
}

$messages = foreach ($row in Read-Tsv (Join-Path $catalogRoot 'messages.tsv')) {
    [pscustomobject][ordered]@{
        id = $row.id
        english = $row.english
        translation = $row.english
        status = 'source'
        notes = '原文表示'
        source_file = $row.source_file
        line = $row.line
        routine = $row.routine
        container = $row.container
    }
}
Write-Tsv $messages 'messages.tsv'

$objects = foreach ($row in Read-Tsv (Join-Path $catalogRoot 'objects.tsv')) {
    [pscustomobject][ordered]@{
        id = $row.id
        english = $row.english
        translation = $row.english
        status = 'source'
        notes = '原文表示'
        source_file = $row.source_file
        line = $row.line
        object = $row.object
        property = $row.property
    }
}
Write-Tsv $objects 'objects.tsv'

$rooms = foreach ($row in Read-Tsv (Join-Path $catalogRoot 'rooms.tsv')) {
    [pscustomobject][ordered]@{
        id = $row.id
        english = $row.english
        translation = $row.english
        status = 'source'
        notes = '原文表示'
        source_file = $row.source_file
        line = $row.line
        room = $row.room
        property = $row.property
    }
}
Write-Tsv $rooms 'rooms.tsv'

$verbs = foreach ($row in Read-Tsv (Join-Path $jaRoot 'verbs.tsv')) {
    [pscustomobject][ordered]@{
        verb = $row.verb
        input = $row.verb.TrimStart([char]92).ToLowerInvariant()
        aliases = ''
        disposition = $row.disposition
        notes = '原作入力'
    }
}
Write-Tsv $verbs 'verbs.tsv'

$directionAliases = @{
    NORTH = 'n'; SOUTH = 's'; EAST = 'e'; WEST = 'w'
    NORTHEAST = 'ne'; NORTHWEST = 'nw'; SOUTHEAST = 'se'; SOUTHWEST = 'sw'
    UP = 'u'; DOWN = 'd'; IN = 'enter'; OUT = 'exit'; LAND = 'shore'
}
$directions = foreach ($row in Read-Tsv (Join-Path $jaRoot 'directions.tsv')) {
    [pscustomobject][ordered]@{
        english = $row.english
        input = $row.english.ToLowerInvariant()
        aliases = $directionAliases[$row.english]
        status = 'source'
    }
}
Write-Tsv $directions 'directions.tsv'

$input = @(
    [pscustomobject][ordered]@{ input = 'yes'; english = 'yes'; notes = 'confirmation' }
    [pscustomobject][ordered]@{ input = 'no'; english = 'no'; notes = 'confirmation' }
    [pscustomobject][ordered]@{ input = 'look'; english = 'look'; notes = 'command' }
    [pscustomobject][ordered]@{ input = 'inventory'; english = 'inventory'; notes = 'command' }
    [pscustomobject][ordered]@{ input = 'quit'; english = 'quit'; notes = 'command' }
)
Write-Tsv $input 'input.tsv'

$ui = @(
    [pscustomobject][ordered]@{
        key = 'status.line'
        value = '\n[{0}  Score {1}  Moves {2}]\n'
        notes = 'location, score and moves'
    }
    [pscustomobject][ordered]@{
        key = 'catalog.report'
        value = 'Output strings: {0}\nInput words: {1}\nAmbiguous source strings: {2}'
        notes = 'catalog summary'
    }
    [pscustomobject][ordered]@{
        key = 'smoke.commands'
        value = 'look\nopen mailbox\ntake leaflet\nread leaflet\nnorth\neast\nopen window\nenter\nlook\nwest\nlook\ntake lamp\nlight lamp\ninventory\nquit\nyes'
        notes = 'automated play commands'
    }
    [pscustomobject][ordered]@{
        key = 'smoke.expected'
        value = 'West of House\nmailbox\nleaflet\nKitchen\nLiving Room\nlantern'
        notes = 'required automated play output'
    }
    [pscustomobject][ordered]@{
        key = 'character.33'
        value = '!'
        notes = 'single-character exclamation mark'
    }
    [pscustomobject][ordered]@{
        key = 'character.44'
        value = ','
        notes = 'single-character comma'
    }
    [pscustomobject][ordered]@{
        key = 'character.46'
        value = '.'
        notes = 'single-character period'
    }
    [pscustomobject][ordered]@{
        key = 'character.63'
        value = '?'
        notes = 'single-character question mark'
    }
)
Write-Tsv $ui 'ui.tsv'

Write-Host "English language pack: $outputRoot"
