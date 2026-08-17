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
$templatesJa = Read-Tsv 'translation/ja/templates.tsv'

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
Assert-UniqueValues $templatesJa 'key' 'Japanese output templates'

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

$ringVerb = $verbJa | Where-Object verb -eq 'RING'
if ($ringVerb.japanese -cne '鳴らす' -or $ringVerb.aliases -match '鐘を鳴らす') {
    throw 'RING must leave 鐘 as the command object instead of absorbing it into a verb alias'
}

$shakeVerb = $verbJa | Where-Object verb -eq 'SHAKE'
$swingVerb = $verbJa | Where-Object verb -eq 'SWING'
$waveVerb = $verbJa | Where-Object verb -eq 'WAVE'
if ($shakeVerb.japanese -cne '揺らす' -or
    $swingVerb.japanese -cne '振り回す' -or
    $waveVerb.japanese -cne '振る' -or
    $waveVerb.aliases -notmatch '(^| )振りかざす( |$)') {
    throw 'SHAKE, SWING, and WAVE must use distinct primary Japanese input verbs'
}

$tieVerb = $verbJa | Where-Object verb -eq 'TIE'
if ($tieVerb.aliases -notmatch '(^| )結びつける( |$)') {
    throw 'TIE must retain 結びつける as an alias'
}

$raiseVerb = $verbJa | Where-Object verb -eq 'RAISE'
foreach ($alias in @('かざす', '翳す', 'かかげる', '掲げる')) {
    if ($raiseVerb.aliases -notmatch ('(^| )' + [regex]::Escape($alias) + '( |$)')) {
        throw "RAISE must retain $alias as an alias"
    }
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

$openContentsTerminator = $messageJa | Where-Object id -eq 'message.gverbs.V-OPEN.985.01'
if ($openContentsTerminator.japanese -cne '' -or $openContentsTerminator.status -cne 'format') {
    throw 'Container contents shown after 中身： must not end in a Japanese full stop'
}

$contentsConjunction = $messageJa | Where-Object id -eq 'message.gverbs.PRINT-CONTENTS.1737.01'
if ($contentsConjunction.japanese -cne '' -or $contentsConjunction.status -cne 'format') {
    throw 'Japanese content lists must use only the list separator without translating and'
}

$paintingDescription = $objectJa | Where-Object id -eq 'object.PAINTING.FDESC'
if ($paintingDescription.japanese -notmatch 'あなたにも.*ならず者の仲間入り' -or
    $paintingDescription.japanese -match '破壊者にもまだ手の届く宝') {
    throw 'Painting description must preserve the joke that the player can join the vandals'
}

$sceptreName = $objectJa | Where-Object id -eq 'object.SCEPTRE.DESC'
$sceptreDescription = $objectJa | Where-Object id -eq 'object.SCEPTRE.FDESC'
if ($sceptreName.japanese -cne '杖' -or
    $sceptreDescription.japanese -notmatch '古代エジプトの王笏と思われる、装飾された杖') {
    throw 'Sceptre must use 杖 as its playable name while preserving its royal origin'
}

$damLobbyDescription = $roomJa | Where-Object id -eq 'room.DAM-LOBBY.LDESC'
if ($damLobbyDescription.japanese -notmatch '関係者以外立入禁止.*開け放し' -or
    $damLobbyDescription.japanese -match 'PRIVATE') {
    throw 'Dam lobby must localize Private while preserving the open-doorway contrast'
}

$thiefBagWarning = $messageJa | Where-Object id -eq 'message.1actions.THIEF-VS-ADVENTURER.1771.01'
if ($thiefBagWarning.japanese -notmatch '俺を殺してからにしろ' -or
    $thiefBagWarning.japanese -match '死体を越える|口は利かない') {
    throw 'Thief introduction must express over his dead body as a natural threat'
}

$largeBagWarning = $messageJa | Where-Object id -eq 'message.1actions.LARGE-BAG-F.2102.01'
if ($largeBagWarning.japanese -notmatch '生きているうちは' -or
    $largeBagWarning.japanese -match '死体を越える') {
    throw 'Large bag warning must express that the living thief prevents taking it'
}

$torchRoomDescription = $messageJa | Where-Object id -eq 'message.1actions.TORCH-ROOM-FCN.1021.01'
if ($torchRoomDescription.japanese -notmatch '床から約二十フィートの高さにあるその縁' -or
    $torchRoomDescription.japanese -match '高さ二十フィートの木製手すり') {
    throw 'Torch Room must identify the dome edge, not the railing, as twenty feet up'
}

$loudRoomDescription = $messageJa | Where-Object id -eq 'message.1actions.LOUD-ROOM-FCN.1670.01'
$quietLoudRoomDescription = $messageJa | Where-Object id -eq 'message.1actions.LOUD-ROOM-FCN.1668.01'
if ($loudRoomDescription.japanese.StartsWith(' ', [StringComparison]::Ordinal) -or
    $quietLoudRoomDescription.japanese.StartsWith(' ', [StringComparison]::Ordinal)) {
    throw 'Loud Room continuation must not begin with an English-style separator space'
}

$heroBlowSeparator = $messageJa | Where-Object id -eq 'message.1actions.HERO-BLOW.3506.01'
if ($heroBlowSeparator.japanese -cne '' -or $heroBlowSeparator.status -cne 'format') {
    throw 'Combat adjective and villain name must not be separated by a space in Japanese'
}
$heroBlowEnding = $messageJa | Where-Object id -eq 'message.1actions.HERO-BLOW.3507.01'
if ($heroBlowEnding.japanese -cne 'は身を守れず、そのまま死んだ。') {
    throw 'Combat death fragment must join naturally after the translated villain name'
}

$echoTemplate = $templatesJa | Where-Object key -eq 'echo-command'
if ($echoTemplate.english -cne 'echo echo ...' -or $echoTemplate.translation -cne '叫ぶ、叫ぶ……') {
    throw 'Dynamic ECHO output must use a readable Japanese separator'
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
    '郵便受け' = 'mailbox'
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
    'マッチ' = 'match'
    'マッチを擦る' = 'light match'
    'マッチをこする' = 'light match'
    '工具箱' = 'chest'
    '棚' = 'case'
    'ケース' = 'case'
    'ニンニク' = 'garlic'
    'にんにく' = 'garlic'
    'ろうそく' = 'candles'
    '蝋燭' = 'candles'
    '松明' = 'torch'
    'ねじ回し' = 'screwdriver'
    'どくろ' = 'skull'
    'ドクロ' = 'skull'
    '髑髏' = 'skull'
    '杖' = 'sceptre'
    '王笏' = 'sceptre'
    '王杖' = 'sceptre'
    'カナリアのぜんまい' = 'canary'
    '機械の蓋' = 'machine'
    '進水' = 'launch boat'
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
    '絵画' = 'painting'
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
$requiredUi = @('port.version', 'status.line', 'catalog.report', 'smoke.commands', 'smoke.expected')
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
