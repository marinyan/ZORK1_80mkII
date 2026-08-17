[CmdletBinding()]
param(
    [int]$Successes = 3,
    [int]$MaxAttempts = 30,
    [switch]$Explore,
    [string]$WalkthroughPath,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (-not $WalkthroughPath) {
    $WalkthroughPath = Join-Path $RepoRoot '.local/zork1-v2-walkthrough/walkthrough.txt'
}
$WalkthroughPath = [IO.Path]::GetFullPath($WalkthroughPath)
if (-not (Test-Path -LiteralPath $WalkthroughPath)) {
    throw "Walkthrough was not found: $WalkthroughPath"
}

$logRoot = Join-Path $RepoRoot $(if ($Explore) { 'build/exploration-logs' } else { 'build/full-play-logs' })
$nouns = @{
    'axe' = '斧'
    'bauble' = '飾り玉'
    'basket' = '籠'
    'barrow' = '石塚'
    'bell' = '鐘'
    'book' = '本'
    'bottle' = '瓶'
    'bracelet' = '腕輪'
    'buoy' = 'ブイ'
    'candles' = '蝋燭'
    'canary' = 'カナリア'
    'case' = '棚'
    'chalice' = '聖杯'
    'coal' = '石炭'
    'coffin' = '棺'
    'coins' = '硬貨の詰まった革袋'
    'diamond' = 'ダイヤモンド'
    'egg' = '卵'
    'emerald' = 'エメラルド'
    'garlic' = 'ニンニク'
    'jade' = '翡翠の置物'
    'lamp' = 'ランプ'
    'lid' = '機械の蓋'
    'machine' = '機械'
    'map' = '地図'
    'matchbook' = 'マッチ'
    'painting' = '絵画'
    'plastic' = 'プラスチック'
    'platinum bar' = '延べ棒'
    'pot of gold' = '金貨の壺'
    'pump' = 'ポンプ'
    'rope' = 'ロープ'
    'rug' = 'ラグ'
    'sack' = '袋'
    'sand' = '砂'
    'scarab' = 'スカラベ像'
    'sceptre' = '杖'
    'screwdriver' = 'ドライバー'
    'shovel' = 'シャベル'
    'skull' = 'どくろ'
    'sword' = '剣'
    'torch' = 'たいまつ'
    'trap door' = '落とし戸'
    'trident' = '三叉槍'
    'trunk' = 'トランク'
    'window' = '窓'
    'wrench' = 'レンチ'
    'yellow button' = '黄色のボタン'
}
$specialCommands = @{
    'd' = '下'
    'dig sand' = '砂を掘る'
    'e' = '東'
    'east' = '東'
    'echo' = '叫ぶ'
    'enter boat' = 'ボートに乗る'
    'exit' = 'ボートから降りる'
    'give egg to thief' = '泥棒に卵を渡す'
    'inflate plastic with pump' = 'ポンプでプラスチックを膨らませる'
    'kill thief with axe' = '斧で泥棒を攻撃する'
    'kill troll with sword' = '剣でトロールを攻撃する'
    'launch' = '進水'
    'light candles with match' = 'マッチで蝋燭を点ける'
    'light match' = 'マッチを擦る'
    'look' = '見る'
    'move rug' = 'ラグをどける'
    'n' = '北'
    'ne' = '北東'
    'nw' = '北西'
    'odysseus' = 'オデュッセウス'
    'open trap door' = '落とし戸を開ける'
    'pray' = '祈る'
    'ring bell' = '鐘を鳴らす'
    'rub mirror' = '鏡をこする'
    's' = '南'
    'se' = '南東'
    'sw' = '南西'
    'tie rope to railing' = '手すりにロープを結ぶ'
    'turn bolt' = 'レンチでボルトを回す'
    'turn off lamp' = 'ランプを消す'
    'turn on lamp' = 'ランプを点ける'
    'turn on switch' = 'ドライバーでスイッチを回す'
    'u' = '上'
    'up' = '上'
    'w' = '西'
    'wait' = '待つ'
    'wave sceptre' = '杖を振る'
    'wind canary' = 'カナリアのぜんまいを巻く'
}

function ConvertTo-JapaneseCommand {
    param([string]$Command)

    if ($specialCommands.ContainsKey($Command)) {
        return $specialCommands[$Command]
    }
    if ($Command -match '^take (.+) from case$') {
        return '棚から{0}を取る' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^take (.+)$') {
        return '{0}を取る' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^drop (.+)$') {
        return '{0}を捨てる' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^put (.+) in (.+)$') {
        return '{0}の中に{1}を置く' -f $nouns[$Matches[2]], $nouns[$Matches[1]]
    }
    if ($Command -match '^open (.+)$') {
        return '{0}を開ける' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^close (.+)$') {
        return '{0}を閉じる' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^read (.+)$') {
        return '{0}を読む' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^push (.+)$') {
        return '{0}を押す' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^lower (.+)$') {
        return '{0}を下げる' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^raise (.+)$') {
        return '{0}を上げる' -f $nouns[$Matches[1]]
    }
    if ($Command -match '^enter (.+)$') {
        return '{0}に入る' -f $nouns[$Matches[1]]
    }
    throw "No Japanese command mapping: $Command"
}

$steps = @(
    Get-Content -LiteralPath $WalkthroughPath |
        ForEach-Object {
            [pscustomobject]@{
                English = $_
                Japanese = ConvertTo-JapaneseCommand $_
            }
        }
)
if ($steps.Count -eq 0) {
    throw 'Walkthrough contains no commands.'
}
if ($steps.Japanese | Where-Object { $_ -match '[A-Za-z]' }) {
    throw 'Walkthrough still contains an ASCII word after Japanese conversion.'
}

$explorationCommands = @{
    3 = @('巣を調べる', '卵を調べる', '卵を嗅ぐ', '聞く')
    8 = @('窓を調べる', '家を調べる', '窓を叩く')
    10 = @('袋を調べる', '袋を嗅ぐ', '袋を振る')
    11 = @('瓶を調べる', '水を調べる')
    15 = @('棚を調べる', '剣を調べる', 'ランプを調べる', 'ラグを調べる')
    19 = @('見る', 'ロープを調べる', 'テーブルを調べる', 'ナイフを調べる')
    25 = @('ラグを調べる', '落とし戸を調べる', '蓋を調べる')
    32 = @('見る', '絵画を調べる', '絵を調べる')
    53 = @('聞く', '壁を調べる')
    60 = @('マッチを調べる', '案内を読む')
    62 = @('工具箱を調べる', 'ボタンを調べる', '黄色いボタンを調べる', '歯磨き粉を調べる', 'チューブを調べる')
    67 = @('ボルトを調べる', '制御盤を調べる', '球を調べる', '貯水池を調べる', '水門を調べる')
    81 = @('サイクロプスを調べる', 'サイクロプスに挨拶する')
    98 = @('手すりを調べる', 'ドームを調べる', 'ロープを調べる')
    101 = @('たいまつを調べる', '台座を調べる')
    103 = @('鐘を調べる')
    106 = @('本を調べる', '蝋燭を調べる', '祭壇を調べる', '碑文を読む')
    117 = @('どくろを調べる', '死体を調べる', '幽霊を調べる')
    150 = @('棺を調べる')
    151 = @('杖を調べる')
    163 = @('虹を調べる', '滝を調べる', '杖を調べる')
    194 = @('三叉槍を調べる')
    237 = @('鏡を調べる')
    243 = @('翡翠の置物を調べる', '置物を調べる')
    249 = @('腕輪を調べる')
    257 = @('石炭を調べる')
    287 = @('機械を調べる', '機械の蓋を調べる', 'スイッチを調べる')
    293 = @('ダイヤモンドを調べる')
    335 = @('プラスチックを調べる', 'ポンプを調べる', 'ラベルを読む', '取扱説明書を読む')
    339 = @('ボートを調べる')
    345 = @('ブイを調べる')
    348 = @('シャベルを調べる', '砂を調べる')
    354 = @('スカラベ像を調べる')
    358 = @('エメラルドを調べる')
    383 = @('硬貨の詰まった革袋を調べる')
    405 = @('カナリアを調べる', '卵を調べる', '聖杯を調べる')
    420 = @('小鳥を調べる', '飾り玉を調べる')
    429 = @('地図を調べる', '得点を見る', '診断する')
}

$assembly = Join-Path $RepoRoot 'windows/Zork1.Windows/bin/Release/net10.0/Zork1Japanese.dll'
if (-not (Test-Path -LiteralPath $assembly)) {
    throw "Build output was not found: $assembly"
}
$dotnet = (Get-Command dotnet -ErrorAction Stop).Source

function Read-ZorkResponse {
    param(
        [IO.StreamReader]$Reader,
        [Text.StringBuilder]$Transcript
    )

    $response = [Text.StringBuilder]::new()
    while (($line = $Reader.ReadLine()) -ne $null) {
        [void]$response.AppendLine($line)
        [void]$Transcript.AppendLine($line)
        if ($line -match '^［.+］$') {
            break
        }
    }
    return $response.ToString()
}

$completed = 0
for ($attempt = 1; $attempt -le $MaxAttempts -and $completed -lt $Successes; $attempt++) {
    $attemptLog = Join-Path $logRoot ('attempt-{0:D2}' -f $attempt)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $dotnet
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    [void]$startInfo.ArgumentList.Add($assembly)
    [void]$startInfo.ArgumentList.Add('--log-dir')
    [void]$startInfo.ArgumentList.Add($attemptLog)

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Could not start the Windows interpreter.'
    }
    $process.StandardInput.AutoFlush = $true
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $transcript = [Text.StringBuilder]::new()
    [void](Read-ZorkResponse $process.StandardOutput $transcript)

    $trollDead = $false
    $thiefDead = $false
    $afterThief = $false
    $needSword = $false
    $needAxe = $false
    $playerDead = $false
    $healedAfterThief = $false
    $explorationReachedEnd = $false

    function Invoke-JapaneseCommand {
        param([string]$Command)

        if ($process.HasExited) {
            return ''
        }
        $process.StandardInput.WriteLine($Command)
        $response = Read-ZorkResponse $process.StandardOutput $transcript
        if ($Explore -and
            $Command -cne 'ランプを点ける' -and
            $response -match '真っ暗だ|暗すぎて何も見えない') {
            $process.StandardInput.WriteLine('ランプを点ける')
            $response += Read-ZorkResponse $process.StandardOutput $transcript
        }
        return $response
    }

    $stepNumber = 0
    foreach ($step in $steps) {
        $stepNumber++
        if ($step.English -eq 'kill troll with sword' -and $trollDead) {
            continue
        }
        if ($step.English -eq 'kill thief with axe' -and $thiefDead) {
            continue
        }

        if ($step.English -eq 'drop sword' -and -not $trollDead) {
            foreach ($retry in 1..20) {
                if ($needSword) {
                    $recovery = Invoke-JapaneseCommand '剣を取る'
                    $needSword = $recovery -match '持っていない|見当たらない'
                }
                $response = Invoke-JapaneseCommand '剣でトロールを攻撃する'
                if ($response -match 'あなたは死んだ') {
                    $playerDead = $true
                    break
                }
                $trollDead = $response -match 'トロール.*(死んだ|息を引き取|死体は消え)'
                $needSword = $response -match 'それは持っていない|剣.*(弾き飛ば|手から|持っていない)'
                if ($trollDead) {
                    break
                }
            }
            if ($playerDead) {
                break
            }
        }
        if ($step.English -eq 'drop axe' -and $afterThief -and -not $thiefDead) {
            foreach ($retry in 1..20) {
                if ($needAxe) {
                    $recovery = Invoke-JapaneseCommand '斧を取る'
                    $needAxe = $recovery -match '持っていない|見当たらない'
                }
                $response = Invoke-JapaneseCommand '斧で泥棒を攻撃する'
                if ($response -match 'あなたは死んだ') {
                    $playerDead = $true
                    break
                }
                $thiefDead = $response -match '泥棒.*(死んだ|息を引き取|死体)'
                $needAxe = $response -match 'それは持っていない|斧.*(滑り落ち|弾き飛ば|手から|持っていない)'
                if ($thiefDead) {
                    break
                }
            }
            if ($playerDead) {
                break
            }
        }

        if ($thiefDead -and -not $healedAfterThief) {
            [void](Invoke-JapaneseCommand 'ランプを消す')
            foreach ($recoveryTurn in 1..150) {
                [void](Invoke-JapaneseCommand '待つ')
            }
            [void](Invoke-JapaneseCommand 'ランプを点ける')
            $healedAfterThief = $true
        }

        if ($step.English -eq 'kill troll with sword' -and $needSword) {
            $recovery = Invoke-JapaneseCommand '剣を取る'
            $needSword = $recovery -match '持っていない|見当たらない'
            if ($recovery -match 'あなたは死んだ') {
                $playerDead = $true
                break
            }
        }
        if ($step.English -eq 'kill thief with axe' -and $needAxe) {
            $recovery = Invoke-JapaneseCommand '斧を取る'
            $needAxe = $recovery -match '持っていない|見当たらない'
            if ($recovery -match 'あなたは死んだ') {
                $playerDead = $true
                break
            }
        }

        $response = Invoke-JapaneseCommand $step.Japanese
        if ($response -match 'あなたは死んだ') {
            $playerDead = $true
            break
        }
        if ($Explore -and
            $stepNumber -eq 376 -and
            $response -match '血まみれの斧がここにある') {
            [void](Invoke-JapaneseCommand '斧を取る')
        }
        if ($step.English -eq 'take axe' -and
            $response -match '見当たらない|取れない') {
            # The roaming thief can steal the only safe weapon before this visit.
            # Once that happens, this source-faithful route cannot finish the fight.
            break
        }

        if ($step.English -eq 'kill troll with sword') {
            $trollDead = $response -match 'トロール.*(死んだ|息を引き取|死体は消え)'
            $needSword = $response -match 'それは持っていない|剣.*(弾き飛ば|手から|持っていない)'
        }
        if ($step.English -eq 'give egg to thief') {
            $afterThief = $true
        }
        if ($step.English -eq 'kill thief with axe') {
            $thiefDead = $response -match '泥棒.*(死んだ|息を引き取|死体)'
            $needAxe = $response -match 'それは持っていない|斧.*(滑り落ち|弾き飛ば|手から|持っていない)'
        }

        if ($thiefDead -and -not $healedAfterThief) {
            [void](Invoke-JapaneseCommand 'ランプを消す')
            foreach ($recoveryTurn in 1..150) {
                [void](Invoke-JapaneseCommand '待つ')
            }
            [void](Invoke-JapaneseCommand 'ランプを点ける')
            $healedAfterThief = $true
        }

        if ($afterThief -and $step.English -eq 'take painting') {
            foreach ($recoveryCommand in @(
                'スカラベ像を取る',
                'エメラルドを取る',
                '硬貨の詰まった革袋を取る'
            )) {
                $recovery = Invoke-JapaneseCommand $recoveryCommand
                if ($recovery -match 'あなたは死んだ') {
                    $playerDead = $true
                    break
                }
            }
            if ($playerDead) {
                break
            }
        }

        if ($afterThief -and $step.English -eq 'put painting in case') {
            foreach ($recoveryCommand in @(
                '棚の中にスカラベ像を置く',
                '棚の中にエメラルドを置く'
            )) {
                [void](Invoke-JapaneseCommand $recoveryCommand)
            }
        }

        if ($Explore -and $explorationCommands.ContainsKey($stepNumber)) {
            foreach ($explorationCommand in $explorationCommands[$stepNumber]) {
                $explorationResponse = Invoke-JapaneseCommand $explorationCommand
                if ($explorationResponse -match 'あなたは死んだ') {
                    $playerDead = $true
                    break
                }
            }
            if ($playerDead) {
                break
            }
            if ($stepNumber -eq 429) {
                $explorationReachedEnd = $true
            }
        }

        if ($Explore -and $stepNumber -in 101, 229, 313) {
            [void](Invoke-JapaneseCommand 'ランプを消す')
        }
        if ($Explore -and $stepNumber -eq 244) {
            [void](Invoke-JapaneseCommand 'ランプを点ける')
        }
        if ($Explore -and $stepNumber -eq 281) {
            foreach ($discard in @(
                'マッチを捨てる',
                '案内を捨てる',
                '本を捨てる',
                'ニンニクを捨てる',
                'ナイフを捨てる',
                '袋を捨てる',
                '瓶を捨てる',
                '鐘を捨てる',
                '蝋燭を捨てる',
                '剣を捨てる',
                '斧を捨てる'
            )) {
                [void](Invoke-JapaneseCommand $discard)
            }
            [void](Invoke-JapaneseCommand '持ち物')
        }
    }

    if (-not $process.HasExited -and
        ($explorationReachedEnd -or $transcript.ToString().Contains(
            '『ZORK』三部作の第一部を制覇した',
            [StringComparison]::Ordinal))) {
        $quitResponse = Invoke-JapaneseCommand '終了'
        if (-not $process.HasExited -and $quitResponse -match '終了するか|Yで終了') {
            [void](Invoke-JapaneseCommand 'はい')
        }
    }

    if (-not $process.HasExited) {
        $process.StandardInput.Close()
        [void]$transcript.Append($process.StandardOutput.ReadToEnd())
    }
    $process.WaitForExit()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) {
        throw "Zork exited with code $($process.ExitCode) on attempt $attempt.`n$stderr"
    }
    $process.Dispose()

    $text = $transcript.ToString()
    $won = if ($Explore) {
        $explorationReachedEnd
    }
    else {
        $text.Contains('『ZORK』三部作の第一部を制覇した', [StringComparison]::Ordinal) -and
            $text.Contains('得点 350', [StringComparison]::Ordinal)
    }
    $deathCount = [regex]::Matches($text, 'あなたは死んだ').Count
    if ($won) {
        $logFile = Get-ChildItem -LiteralPath $attemptLog -Filter '*.jsonl' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        $events = Get-Content -LiteralPath $logFile.FullName |
            ForEach-Object { $_ | ConvertFrom-Json }
        $nonJapaneseInput = @($events | Where-Object {
            $_.type -eq 'input' -and $_.inputKind -ne 'japanese'
        })
        if ($nonJapaneseInput.Count -gt 0) {
            throw "Completed attempt $attempt used a non-Japanese input: $($nonJapaneseInput.rawInput -join ', ')"
        }
        if ($text -match 'という語は分からない|文の形は理解できない|文には動詞がない') {
            throw "Completed attempt $attempt contains a parser error."
        }
        if ($text -match '(?m)^\(with\b') {
            throw "Completed attempt $attempt contains an untranslated implicit-instrument message."
        }
        if ($Explore -and $text -match 'Frobozz Magic Gunk Company|All-Purpose Gunk|ろうそくには燃えている') {
            throw "Completed exploration attempt $attempt contains an untranslated or malformed side-path response."
        }
        $completed++
    }
    Write-Host ('attempt={0} completed={1} deaths={2} successes={3}/{4}' -f `
        $attempt, $won, $deathCount, $completed, $Successes)
}

if ($completed -lt $Successes) {
    throw "Only $completed of $Successes requested playthroughs completed in $MaxAttempts attempts."
}

$testName = if ($Explore) { 'Japanese exploration playthroughs' } else { 'Japanese full playthroughs' }
Write-Host "${testName} OK: $completed"
