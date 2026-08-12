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

function Assert-CatalogContext {
    param(
        [object[]]$CatalogRows,
        [object[]]$TranslationRows,
        [string[]]$Columns,
        [string]$Label
    )

    $translationById = @{}
    foreach ($row in $TranslationRows) {
        $translationById[$row.id] = $row
    }
    foreach ($source in $CatalogRows) {
        $translated = $translationById[$source.id]
        foreach ($column in $Columns) {
            if ([string]$source.$column -cne [string]$translated.$column) {
                throw "$Label context mismatch: id=$($source.id) column=$column"
            }
        }
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
$inputJa = Read-Tsv 'translation/ja/input.tsv'
$uiJa = Read-Tsv 'translation/ja/ui.tsv'

$expectedCounts = @{
    strings  = 2152
    rooms    = 253
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
Assert-UniqueValues $inputJa 'input' 'Japanese input overrides'
Assert-UniqueValues $uiJa 'key' 'Japanese UI strings'

Assert-SameSet @($roomCatalog.id) @($roomJa.id) 'Room translation ID'
Assert-SameSet @($objectCatalog.id) @($objectJa.id) 'Object translation ID'
Assert-SameSet @($messageCatalog.id) @($messageJa.id) 'Message translation ID'
Assert-SameSet @($commandCatalog.verb) @($verbJa.verb) 'Command verb'

$dropVerb = $verbJa | Where-Object verb -eq 'DROP'
if ($dropVerb.japanese -cne '捨てる' -or
    $dropVerb.aliases -notmatch '(^| )落とす( |$)' -or
    $dropVerb.aliases -notmatch '(^| )置く( |$)') {
    throw 'DROP must use 捨てる and retain 落とす plus contextual 置く as aliases'
}

$moveVerb = $verbJa | Where-Object verb -eq 'MOVE'
if ($moveVerb.aliases -notmatch '(^| )どける( |$)') {
    throw 'MOVE must retain どける as an alias'
}

$versionNotice = $messageJa | Where-Object id -eq 'message.gverbs.V-VERSION.111.01'
if ($versionNotice.japanese -notmatch 'Copyright \(c\) 2025 Microsoft' -or
    $versionNotice.japanese -match '無断複製|転載を禁ず') {
    throw 'Startup notice must show the Microsoft MIT copyright without the obsolete no-copy notice'
}

$trademarkNotice = $messageJa | Where-Object id -eq 'message.gverbs.V-VERSION.112.01'
if ($trademarkNotice.japanese -match 'Infocom, Inc\.の登録商標') {
    throw 'Startup trademark notice must not identify the defunct Infocom, Inc. as the current registrant'
}

Assert-CatalogContext $roomCatalog $roomJa @('english', 'source_file', 'line', 'room', 'property') 'Room translation'
Assert-CatalogContext $objectCatalog $objectJa @('english', 'source_file', 'line', 'object', 'property') 'Object translation'
Assert-CatalogContext $messageCatalog $messageJa @('english', 'source_file', 'line', 'routine', 'container') 'Message translation'

$blankRooms = @($roomJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) })
$blankObjects = @($objectJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) -and $_.status -ne 'format' })
$blankVerbs = @($verbJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) })
$blankMessages = @($messageJa | Where-Object { [string]::IsNullOrWhiteSpace($_.japanese) -and $_.status -ne 'format' })
$blankInput = @($inputJa | Where-Object { [string]::IsNullOrWhiteSpace($_.input) -or [string]::IsNullOrWhiteSpace($_.english) })
$blankUi = @($uiJa | Where-Object { [string]::IsNullOrWhiteSpace($_.key) -or [string]::IsNullOrWhiteSpace($_.value) })
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
if ($blankInput.Count -gt 0) {
    throw "Blank Japanese input overrides: $($blankInput.input -join ', ')"
}
if ($blankUi.Count -gt 0) {
    throw "Blank Japanese UI strings: $($blankUi.key -join ', ')"
}

$inputByAlias = @{}
foreach ($row in $inputJa) {
    $inputByAlias[$row.input] = $row.english
}
$requiredInputAliases = [ordered]@{
    '家' = 'house'
    '自分' = 'me'
    '自分自身' = 'myself'
    'セルフ' = 'self'
    '私' = 'me'
    'わたし' = 'me'
    '白い家' = 'white house'
    '幽霊たち' = 'ghosts'
    '幽霊' = 'ghosts'
    'ゆうれい' = 'ghosts'
    '壁' = 'wall'
    '花崗岩の壁' = 'granite wall'
    'ボタン' = 'button'
    'ラグ' = 'rug'
    'ランプ' = 'lamp'
    '工具箱' = 'chest'
    '棚' = 'case'
    'ケース' = 'case'
    'ニンニク' = 'garlic'
    'にんにく' = 'garlic'
    'ろうそく' = 'candles'
    '石炭' = 'coal'
    'プラスチック' = 'plastic'
    '空気' = 'air'
    '戸' = 'door'
    '落とし戸' = 'trap door'
    '落し戸' = 'trap door'
    '蓋' = 'cover'
    'ふた' = 'cover'
    '黄色のボタン' = 'yellow button'
    '黄色いボタン' = 'yellow button'
    '茶色のボタン' = 'brown button'
    '茶色いボタン' = 'brown button'
    '赤いボタン' = 'red button'
    '赤のボタン' = 'red button'
    '青いボタン' = 'blue button'
    '青のボタン' = 'blue button'
    '死体' = 'body'
    '落ち葉' = 'leaf'
    '手' = 'hand'
}
foreach ($alias in $requiredInputAliases.Keys) {
    if (-not $inputByAlias.ContainsKey($alias) -or $inputByAlias[$alias] -cne $requiredInputAliases[$alias]) {
        throw "Japanese input alias mismatch: $alias -> $($requiredInputAliases[$alias])"
    }
}

$politePattern = '(です|ます|ません|でした|ました|でしょう|ください|下さい|ございます|いたします|ましょう)(?=$|[。！？?!、」』）)]|か|ね|よ|が|けれど|けど|ので|から|し)'
$politeRows = @($roomJa + $objectJa + $messageJa | Where-Object { $_.japanese -match $politePattern })
if ($politeRows.Count -gt 0) {
    throw "Polite-style Japanese remains: $($politeRows.id -join ', ')"
}

$expectedDirections = @('NORTH', 'SOUTH', 'EAST', 'WEST', 'NORTHEAST', 'NORTHWEST', 'SOUTHEAST', 'SOUTHWEST', 'UP', 'DOWN', 'IN', 'OUT', 'LAND')
Assert-SameSet $expectedDirections @($directions.english) 'Direction'
$upDirection = $directions | Where-Object english -eq 'UP'
foreach ($alias in @('登る', '上る', '昇る', '上がる')) {
    if ($upDirection.aliases -notmatch ('(^| )' + [regex]::Escape($alias) + '( |$)')) {
        throw "UP must retain $alias as an alias"
    }
}
$downDirection = $directions | Where-Object english -eq 'DOWN'
foreach ($alias in @('降りる', '下りる', '下る', '降る')) {
    if ($downDirection.aliases -notmatch ('(^| )' + [regex]::Escape($alias) + '( |$)')) {
        throw "DOWN must retain $alias as an alias"
    }
}
$requiredUi = @('status.line', 'catalog.report', 'smoke.commands', 'smoke.expected')
foreach ($key in $requiredUi) {
    if ($key -notin @($uiJa.key)) {
        throw "Required Japanese UI string is missing: $key"
    }
}

$messageEn = Read-Tsv 'translation/en/messages.tsv'
$objectEn = Read-Tsv 'translation/en/objects.tsv'
$roomEn = Read-Tsv 'translation/en/rooms.tsv'
$verbEn = Read-Tsv 'translation/en/verbs.tsv'
$directionEn = Read-Tsv 'translation/en/directions.tsv'
$inputEn = Read-Tsv 'translation/en/input.tsv'
$uiEn = Read-Tsv 'translation/en/ui.tsv'

Assert-UniqueValues $messageEn 'id' 'English message translations'
Assert-UniqueValues $objectEn 'id' 'English object translations'
Assert-UniqueValues $roomEn 'id' 'English room translations'
Assert-UniqueValues $verbEn 'verb' 'English verb translations'
Assert-UniqueValues $directionEn 'english' 'English direction translations'
Assert-UniqueValues $inputEn 'input' 'English input overrides'
Assert-UniqueValues $uiEn 'key' 'English UI strings'
Assert-SameSet @($messageCatalog.id) @($messageEn.id) 'English message translation ID'
Assert-SameSet @($objectCatalog.id) @($objectEn.id) 'English object translation ID'
Assert-SameSet @($roomCatalog.id) @($roomEn.id) 'English room translation ID'
Assert-SameSet @($verbJa.verb) @($verbEn.verb) 'English command verb'
Assert-SameSet $expectedDirections @($directionEn.english) 'English direction'

$nonIdentityEnglish = @($messageEn + $objectEn + $roomEn | Where-Object { $_.translation -cne $_.english })
if ($nonIdentityEnglish.Count -gt 0) {
    throw "English language pack is not source-identical: $($nonIdentityEnglish.id -join ', ')"
}
foreach ($key in $requiredUi) {
    if ($key -notin @($uiEn.key)) {
        throw "Required English UI string is missing: $key"
    }
}

Write-Host ('language packs OK: ja/en rooms={0}, objects={1}, messages={2}, verbs={3}, directions={4}' -f $roomJa.Count, $objectJa.Count, $messageJa.Count, $verbJa.Count, $directions.Count)
