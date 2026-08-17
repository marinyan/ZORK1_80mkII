[CmdletBinding()]
param(
    [int]$Successes = 3,
    [int]$MaxAttempts = 30,
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

$logRoot = Join-Path $RepoRoot 'build/full-play-logs'
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

    function Invoke-JapaneseCommand {
        param([string]$Command)

        if ($process.HasExited) {
            return ''
        }
        $process.StandardInput.WriteLine($Command)
        return Read-ZorkResponse $process.StandardOutput $transcript
    }

    foreach ($step in $steps) {
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
    }

    if (-not $process.HasExited -and
        $transcript.ToString().Contains(
            '『ZORK』三部作の第一部を制覇した',
            [StringComparison]::Ordinal)) {
        [void](Invoke-JapaneseCommand '終了')
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
    $won = $text.Contains('『ZORK』三部作の第一部を制覇した', [StringComparison]::Ordinal) -and
        $text.Contains('得点 350', [StringComparison]::Ordinal)
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
        $completed++
    }
    Write-Host ('attempt={0} completed={1} deaths={2} successes={3}/{4}' -f `
        $attempt, $won, $deathCount, $completed, $Successes)
}

if ($completed -lt $Successes) {
    throw "Only $completed of $Successes requested playthroughs completed in $MaxAttempts attempts."
}

Write-Host "Japanese full playthroughs OK: $completed"
