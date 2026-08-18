param(
    [switch]$Run,
    [switch]$Smoke,
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'windows/Zork1.Windows/Zork1.Windows.csproj'

if ($Publish) {
    $output = Join-Path $root 'build/windows-x64'
    dotnet publish $project -c Release -r win-x64 --self-contained false `
        -p:PublishSingleFile=true -o $output
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $output 'LICENSE.txt') -Force
    $thirdParty = Join-Path $output 'THIRD-PARTY-LICENSES'
    New-Item -ItemType Directory -Path $thirdParty -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'references/zork1/LICENSE') `
        -Destination (Join-Path $thirdParty 'ZORK1-MIT.txt') -Force
    Write-Host "Windows実行ファイル: $output/Zork1Japanese.exe"
    exit 0
}

dotnet build $project -c Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Smoke) {
    $parserCases = @(
        @{ Input = '剣 使う トロール'; Expected = 'attack troll with sword' },
        @{ Input = '使う 剣 トロール'; Expected = 'attack troll with sword' },
        @{ Input = '剣をトロールに使う'; Expected = 'attack troll with sword' },
        @{ Input = 'トロールに剣を使う'; Expected = 'attack troll with sword' },
        @{ Input = '剣でトロールを攻撃'; Expected = 'attack troll with sword' },
        @{ Input = 'トロールを剣で攻撃'; Expected = 'attack troll with sword' },
        @{ Input = '剣で トロールを 攻撃'; Expected = 'attack troll with sword' },
        @{ Input = 'トロールを 剣で 攻撃'; Expected = 'attack troll with sword' },
        @{ Input = '剣でトロールを攻撃する'; Expected = 'attack troll with sword' },
        @{ Input = 'トロールを剣で攻撃する'; Expected = 'attack troll with sword' },
        @{ Input = '使う 剣 自分'; Expected = 'attack me with sword' },
        @{ Input = '剣 使う セルフ'; Expected = 'attack me with sword' },
        @{ Input = '回す ボルト'; Expected = 'turn bolt' },
        @{ Input = '使う レンチ ボルト'; Expected = 'turn bolt with wrench' },
        @{ Input = '回す ボルト レンチ'; Expected = 'turn bolt with wrench' },
        @{ Input = 'レンチでボルトを回す'; Expected = 'turn bolt with wrench' },
        @{ Input = 'ボルトをレンチで回す'; Expected = 'turn bolt with wrench' },
        @{ Input = '手すりにロープを結ぶ'; Expected = 'tie rope to railing' },
        @{ Input = 'ロープを手すりに結ぶ'; Expected = 'tie rope to railing' },
        @{ Input = 'ロープを手すりに結びつける'; Expected = 'tie rope to railing' },
        @{ Input = '泥棒に卵を渡す'; Expected = 'give egg to thief' },
        @{ Input = '卵を泥棒に渡す'; Expected = 'give egg to thief' },
        @{ Input = '棚から卵を取る'; Expected = 'take egg from case' },
        @{ Input = '卵を棚から取る'; Expected = 'take egg from case' },
        @{ Input = 'ポンプでプラスチックを膨らませる'; Expected = 'inflat plastic with pump' },
        @{ Input = 'プラスチックをポンプで膨らませる'; Expected = 'inflat plastic with pump' },
        @{ Input = 'マッチで蝋燭を点ける'; Expected = 'light candles with match' },
        @{ Input = '蝋燭をマッチで点ける'; Expected = 'light candles with match' },
        @{ Input = '機械の蓋を開ける'; Expected = 'open machine' },
        @{ Input = '機械の蓋を閉じる'; Expected = 'close machine' },
        @{ Input = 'カナリアのぜんまいを巻く'; Expected = 'wind canary' },
        @{ Input = '進水'; Expected = 'launch boat' },
        @{ Input = '待つ'; Expected = 'wait' },
        @{ Input = '全部取る'; Expected = 'take all' },
        @{ Input = 'すべてを取る'; Expected = 'take all' },
        @{ Input = '瓶以外全部取る'; Expected = 'take all except bottle' },
        @{ Input = '瓶以外を全部取る'; Expected = 'take all except bottle' },
        @{ Input = '瓶以外はすべて取る'; Expected = 'take all except bottle' },
        @{ Input = '瓶を除いて全部取る'; Expected = 'take all except bottle' },
        @{ Input = '全部拾う'; Expected = 'take all' },
        @{ Input = '袋以外全部拾う'; Expected = 'take all except bag' },
        @{ Input = '全部落とす'; Expected = 'drop all' },
        @{ Input = '全てを捨てる'; Expected = 'drop all' },
        @{ Input = '瓶以外全部落とす'; Expected = 'drop all except bottle' },
        @{ Input = '袋を除いてすべてを捨てる'; Expected = 'drop all except bag' },
        @{ Input = '瓶と袋を拾う'; Expected = 'take bottle and bag' },
        @{ Input = '瓶、袋を取る'; Expected = 'take bottle and bag' },
        @{ Input = '瓶および袋を取る'; Expected = 'take bottle and bag' },
        @{ Input = '瓶と袋の両方を拾う'; Expected = 'take bottle and bag' },
        @{ Input = '取る 瓶と袋'; Expected = 'take bottle and bag' },
        @{ Input = '落とし戸と蓋を調べる'; Expected = 'examine trap door and cover' },
        @{ Input = '瓶と袋以外全部拾う'; Expected = 'take all except bottle and bag' },
        @{ Input = '瓶と袋を落とす'; Expected = 'drop bottle and bag' },
        @{ Input = '瓶と袋を調べる'; Expected = 'examine bottle and bag' },
        @{ Input = '瓶以外全部調べる'; Expected = 'examine all except bottle' },
        @{ Input = '瓶と袋を押す'; Expected = 'push bottle and bag' },
        @{ Input = '全部を棚の中に置く'; Expected = 'put all in case' },
        @{ Input = '棚の中に瓶以外全部を置く'; Expected = 'put all except bottle in case' },
        @{ Input = '瓶と袋を棚の中に置く'; Expected = 'put bottle and bag in case' },
        @{ Input = '置く 全部 棚'; Expected = 'put all in case' },
        @{ Input = '置く 瓶と袋 棚の中'; Expected = 'put bottle and bag in case' },
        @{ Input = '瓶と袋を棚の中に移す'; Expected = 'put bottle and bag in case' },
        @{ Input = '棚の後ろに瓶と袋を置く'; Expected = 'put bottle and bag behind case' },
        @{ Input = '棚から全部取る'; Expected = 'take all from case' },
        @{ Input = '棚から瓶以外全部取る'; Expected = 'take all except bottle from case' },
        @{ Input = '全部を棚から取る'; Expected = 'take all from case' },
        @{ Input = '瓶と袋を泥棒に渡す'; Expected = 'give bottle and bag to thief' },
        @{ Input = '泥棒に瓶以外全部を渡す'; Expected = 'give all except bottle to thief' },
        @{ Input = '渡す 瓶と袋 泥棒'; Expected = 'give bottle and bag to thief' },
        @{ Input = '窓を叩く'; Expected = 'knock on window' },
        @{ Input = '窓を 叩く'; Expected = 'knock on window' },
        @{ Input = '案内を読む'; Expected = 'read guide' },
        @{ Input = '歯磨き粉を調べる'; Expected = 'examine tube' },
        @{ Input = '制御盤を調べる'; Expected = 'examine panel' },
        @{ Input = '水門を調べる'; Expected = 'examine gate' },
        @{ Input = '貯水池を調べる'; Expected = 'examine water' },
        @{ Input = 'ドームを調べる'; Expected = 'examine dome' },
        @{ Input = '碑文を読む'; Expected = 'read inscription' },
        @{ Input = '滝を調べる'; Expected = 'examine water' },
        @{ Input = '松明を取る'; Expected = 'take torch' },
        @{ Input = '蝋燭を取る'; Expected = 'take candles' },
        @{ Input = '鐘を鳴らす'; Expected = 'ring bell' },
        @{ Input = 'マッチを擦る'; Expected = 'light match' },
        @{ Input = 'マッチをこする'; Expected = 'light match' },
        @{ Input = 'ねじ回しを落とす'; Expected = 'drop screwdriver' },
        @{ Input = '王笏を振る'; Expected = 'wave sceptre' },
        @{ Input = '王笏を振りかざす'; Expected = 'wave sceptre' },
        @{ Input = '王笏を揺らす'; Expected = 'shake sceptre' },
        @{ Input = '王笏を振り回す'; Expected = 'swing sceptre' },
        @{ Input = '杖を振る'; Expected = 'wave sceptre' },
        @{ Input = '杖をかざす'; Expected = 'raise sceptre' },
        @{ Input = '杖を翳す'; Expected = 'raise sceptre' },
        @{ Input = '杖をかかげる'; Expected = 'raise sceptre' },
        @{ Input = '杖を掲げる'; Expected = 'raise sceptre' },
        @{ Input = '王笏を掲げる'; Expected = 'raise sceptre' },
        @{ Input = '王杖をかざす'; Expected = 'raise sceptre' },
        @{ Input = 'どくろを取る'; Expected = 'take skull' },
        @{ Input = 'ドクロを取る'; Expected = 'take skull' },
        @{ Input = '髑髏を取る'; Expected = 'take skull' }
    )
    foreach ($case in $parserCases) {
        $actual = dotnet run --no-build --project $project -c Release -- `
            --translate-input $case.Input
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if ($actual -cne $case.Expected) {
            Write-Error "入力変換テスト失敗: $($case.Input) -> $actual (期待値: $($case.Expected))"
            exit 2
        }
    }
    $bulkTransferOutput = @(
        '北',
        '東',
        '窓を開ける',
        '窓に入る',
        '全部拾う',
        '西',
        '全部落とす',
        '瓶以外全部拾う',
        '袋以外全部落とす',
        '全部拾う',
        '持ち物',
        '終了',
        'はい'
    ) | dotnet run --no-build --project $project -c Release -- --no-log
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $bulkTransferText = $bulkTransferOutput -join "`n"
    foreach ($expectation in @(
        "ガラス瓶：取った。`n茶色の袋：取った。",
        "茶色の袋：置いた。`nガラス瓶：置いた。",
        "茶色の袋：取った。`n剣：取った。`n真鍮製ランタン：取った。",
        "真鍮製ランタン：置いた。`n剣：置いた。",
        "持ち物：`nガラス瓶`nガラス瓶の中にあるもの：`n水`n真鍮製ランタン`n剣`n茶色の袋"
    )) {
        if ($bulkTransferText.Contains($expectation, [StringComparison]::Ordinal)) {
            continue
        }
        Write-Error "一括取得・投棄テスト失敗: 必要な応答がない: $expectation"
        exit 2
    }
    $multipleObjectOutput = @(
        '北',
        '東',
        '窓を開ける',
        '窓に入る',
        '瓶と袋を調べる',
        '瓶と袋を押す',
        '瓶と袋を拾う',
        '西',
        '棚を開ける',
        '全部を棚の中に置く',
        '棚から瓶以外全部取る',
        '袋を棚の中に置く',
        '棚から全部取る',
        '瓶と袋を落とす',
        '瓶と袋以外全部拾う',
        '持ち物',
        '終了',
        'はい'
    ) | dotnet run --no-build --project $project -c Release -- --no-log
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $multipleObjectText = $multipleObjectOutput -join "`n"
    foreach ($expectation in @(
        "ガラス瓶：ガラス瓶の中にあるもの：`n水`n茶色の袋：茶色の袋は閉まっている。",
        "ガラス瓶：「押す」：",
        "茶色の袋：「押す」：",
        "ガラス瓶：取った。`n茶色の袋：取った。",
        "茶色の袋：できた。`nガラス瓶：できた。",
        "茶色の袋：取った。`nガラス瓶：取った。",
        "ガラス瓶：置いた。`n茶色の袋：置いた。",
        "剣：取った。`n真鍮製ランタン：取った。",
        "持ち物：`n真鍮製ランタン`n剣"
    )) {
        if ($multipleObjectText.Contains($expectation, [StringComparison]::Ordinal)) {
            continue
        }
        Write-Error "複数対象入力テスト失敗: 必要な応答がない: $expectation"
        exit 2
    }
    $echoOutput = dotnet run --no-build --project $project -c Release -- `
        --translate-output-line 'echo echo ...'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ($echoOutput -cne '叫ぶ、叫ぶ……') {
        Write-Error "出力変換テスト失敗: echo echo ... -> $echoOutput"
        exit 2
    }
    $implicitToolOutput = dotnet run --no-build --project $project -c Release -- `
        --translate-output-line '(with the shovel)'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ($implicitToolOutput -cne '（シャベルで）') {
        Write-Error "出力変換テスト失敗: (with the shovel) -> $implicitToolOutput"
        exit 2
    }
    foreach ($case in @(
        @{ Input = 'The candles are burning.'; Expected = 'ろうそくは燃えている。' },
        @{ Input = 'The candles are out.'; Expected = 'ろうそくは消えている。' },
        @{ Input = "There's nothing special about the tube."; Expected = 'チューブには、これといって変わったところはない。' },
        @{ Input = "There's nothing special about the quantity of water."; Expected = '水には、これといって変わったところはない。' },
        @{ Input = "There's nothing special about the control panel."; Expected = '制御盤には、これといって変わったところはない。' }
    )) {
        $actual = dotnet run --no-build --project $project -c Release -- `
            --translate-output-line $case.Input
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if ($actual -cne $case.Expected) {
            Write-Error "出力変換テスト失敗: $($case.Input) -> $actual (期待値: $($case.Expected))"
            exit 2
        }
    }
    $smokeLogRoot = Join-Path $root 'build/smoke-logs'
    $smokeLogDirectory = Join-Path $smokeLogRoot ([Guid]::NewGuid().ToString('N'))
    dotnet run --no-build --project $project -c Release -- `
        --smoke --log-dir $smokeLogDirectory
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $logFile = Get-ChildItem -LiteralPath $smokeLogDirectory -Filter '*.jsonl' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $logFile) {
        Write-Error 'プレイログテスト失敗: JSON Linesログが生成されていない'
        exit 2
    }
    $events = Get-Content -LiteralPath $logFile.FullName |
        ForEach-Object { $_ | ConvertFrom-Json }
    $session = $events | Where-Object type -eq 'session' | Select-Object -First 1
    if (-not $session -or $session.edition -cne 'faithful' -or $session.language -cne 'ja') {
        Write-Error 'プレイログテスト失敗: 忠実版または言語パックの識別情報が正しくない'
        exit 2
    }
    $translatedLook = $events | Where-Object {
        $_.type -eq 'input' -and
        $_.rawInput -ceq '見る' -and
        $_.translatedInput -ceq 'look' -and
        $_.zMachineInput -ceq 'look' -and
        $_.inputKind -ceq 'japanese'
    } | Select-Object -First 1
    if (-not $translatedLook) {
        Write-Error 'プレイログテスト失敗: 日本語入力と変換後コマンドが記録されていない'
        exit 2
    }
    if (-not ($events | Where-Object type -eq 'output' | Select-Object -First 1)) {
        Write-Error 'プレイログテスト失敗: 応答が記録されていない'
        exit 2
    }
    if (-not ($events | Where-Object type -eq 'session-end' | Select-Object -First 1)) {
        Write-Error 'プレイログテスト失敗: セッション終了が記録されていない'
        exit 2
    }
    exit 0
}

if ($Run) {
    dotnet run --no-build --project $project -c Release
}
