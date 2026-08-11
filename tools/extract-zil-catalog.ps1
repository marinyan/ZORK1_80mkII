[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $SourceRoot) {
    $SourceRoot = Join-Path $repoRoot 'references/zork1'
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'translation/catalog'
}

function Get-LineNumber {
    param(
        [string]$Text,
        [int]$Index
    )

    if ($Index -le 0) {
        return 1
    }
    return ([regex]::Matches($Text.Substring(0, $Index), "`n").Count + 1)
}

function ConvertFrom-ZilString {
    param([string]$Value)

    return $Value.Replace('\"', '"').Replace('\n', "`n")
}

function ConvertTo-TsvField {
    param($Value)

    if ($null -eq $Value) {
        return ''
    }

    $escaped = ([string]$Value).Replace('\', '\\').Replace("`r`n", '\n').Replace("`n", '\n').Replace("`t", '\t').Replace('"', '""')
    return '"' + $escaped + '"'
}

function Write-Tsv {
    param(
        [string]$Path,
        [string[]]$Columns,
        [object[]]$Rows
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($Columns -join "`t"))
    foreach ($row in $Rows) {
        $values = foreach ($column in $Columns) {
            ConvertTo-TsvField $row.$column
        }
        $lines.Add(($values -join "`t"))
    }
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($false))
}

function Get-ZilStringEnd {
    param(
        [string]$Text,
        [int]$StartIndex
    )

    $index = $StartIndex + 1
    while ($index -lt $Text.Length) {
        if ($Text[$index] -eq '\' -and $index + 1 -lt $Text.Length) {
            $index += 2
            continue
        }
        if ($Text[$index] -eq '"') {
            return ($index + 1)
        }
        $index++
    }
    return $Text.Length
}

function Get-ZilExpressionEnd {
    param(
        [string]$Text,
        [int]$StartIndex
    )

    $index = $StartIndex
    while ($index -lt $Text.Length -and [char]::IsWhiteSpace($Text[$index])) { $index++ }
    if ($index -ge $Text.Length) { return $Text.Length }

    if ($Text[$index] -eq '"') {
        return Get-ZilStringEnd $Text $index
    }

    if ($Text[$index] -in @('<', '(')) {
        $closers = [System.Collections.Generic.List[char]]::new()
        while ($index -lt $Text.Length) {
            $current = $Text[$index]
            if ($current -eq '"') {
                $index = Get-ZilStringEnd $Text $index
                continue
            }
            if ($current -eq ';') {
                $index = Get-ZilExpressionEnd $Text ($index + 1)
                continue
            }
            if ($current -eq '<') { $closers.Add('>') }
            elseif ($current -eq '(') { $closers.Add(')') }
            elseif ($closers.Count -gt 0 -and $current -eq $closers[$closers.Count - 1]) {
                $closers.RemoveAt($closers.Count - 1)
                if ($closers.Count -eq 0) { return ($index + 1) }
            }
            $index++
        }
        return $Text.Length
    }

    while ($index -lt $Text.Length -and
        -not [char]::IsWhiteSpace($Text[$index]) -and
        $Text[$index] -notin @('<', '>', '(', ')', ';', '"')) {
        $index++
    }
    return $index
}

function Remove-ZilComments {
    param([string]$Text)

    $characters = $Text.ToCharArray()
    $index = 0
    while ($index -lt $Text.Length) {
        if ($Text[$index] -eq '"') {
            $index = Get-ZilStringEnd $Text $index
            continue
        }
        if ($Text[$index] -ne ';') {
            $index++
            continue
        }

        $end = Get-ZilExpressionEnd $Text ($index + 1)
        for ($commentIndex = $index; $commentIndex -lt $end; $commentIndex++) {
            if ($characters[$commentIndex] -notin @("`r", "`n")) {
                $characters[$commentIndex] = ' '
            }
        }
        $index = $end
    }
    return -join $characters
}

function Test-Zork1Condition {
    param([string]$Condition)

    $normalized = [regex]::Replace($Condition, '\s+', ' ').Trim()
    if ($normalized -in @('T', 'ELSE')) { return $true }

    $equalResults = @(
        [regex]::Matches($normalized, '<==\?\s+,ZORK-NUMBER(?<values>(?:\s+\d+)+)>') |
            ForEach-Object {
                $values = @($_.Groups['values'].Value.Trim() -split '\s+' | ForEach-Object { [int]$_ })
                return (1 -in $values)
            }
    )
    $notEqualResults = @(
        [regex]::Matches($normalized, '<N==\?\s+,ZORK-NUMBER(?<values>(?:\s+\d+)+)>') |
            ForEach-Object {
                $values = @($_.Groups['values'].Value.Trim() -split '\s+' | ForEach-Object { [int]$_ })
                return (1 -notin $values)
            }
    )
    $results = @($equalResults + $notEqualResults)
    if ($results.Count -eq 0) { return $false }
    if ($normalized.StartsWith('<OR ')) { return ($true -in $results) }
    if ($normalized.StartsWith('<AND ')) { return ($false -notin $results) }
    return [bool]$results[0]
}

function Select-Zork1Source {
    param([string]$Text)

    $characters = $Text.ToCharArray()
    foreach ($macroMatch in [regex]::Matches($Text, '%<COND\b')) {
        $formStart = $macroMatch.Index + 1
        $formEnd = Get-ZilExpressionEnd $Text $formStart
        $formText = $Text.Substring($formStart, $formEnd - $formStart)
        if ($formText -notmatch '\bZORK-NUMBER\b') { continue }

        $branches = [System.Collections.Generic.List[object]]::new()
        $index = $formStart + 5
        while ($index -lt $formEnd - 1) {
            if ($Text[$index] -eq '"') {
                $index = Get-ZilStringEnd $Text $index
                continue
            }
            if ($Text[$index] -ne '(') {
                $index++
                continue
            }

            $branchEnd = Get-ZilExpressionEnd $Text $index
            $conditionStart = $index + 1
            while ($conditionStart -lt $branchEnd -and [char]::IsWhiteSpace($Text[$conditionStart])) { $conditionStart++ }
            if ($conditionStart -lt $branchEnd -and $Text[$conditionStart] -eq '<') {
                $conditionEnd = Get-ZilExpressionEnd $Text $conditionStart
            } else {
                $conditionEnd = $conditionStart
                while ($conditionEnd -lt $branchEnd -and
                    -not [char]::IsWhiteSpace($Text[$conditionEnd]) -and
                    $Text[$conditionEnd] -ne ')') {
                    $conditionEnd++
                }
            }
            $condition = $Text.Substring($conditionStart, $conditionEnd - $conditionStart)
            $branches.Add([pscustomobject]@{
                Start     = $index
                End       = $branchEnd
                Condition = $condition
            })
            $index = $branchEnd
        }

        $selected = $null
        foreach ($branch in $branches) {
            if (Test-Zork1Condition $branch.Condition) {
                $selected = $branch
                break
            }
        }
        foreach ($branch in $branches) {
            if ($null -ne $selected -and $branch.Start -eq $selected.Start) { continue }
            for ($branchIndex = $branch.Start; $branchIndex -lt $branch.End; $branchIndex++) {
                if ($characters[$branchIndex] -notin @("`r", "`n")) {
                    $characters[$branchIndex] = ' '
                }
            }
        }
    }
    return -join $characters
}

function Get-ZilStrings {
    param(
        [string]$Text,
        [string]$SourceFile
    )

    $Text = Select-Zork1Source (Remove-ZilComments $Text)
    $results = [System.Collections.Generic.List[object]]::new()
    $angleStack = [System.Collections.Generic.List[string]]::new()
    $parenStack = [System.Collections.Generic.List[string]]::new()
    $topKind = ''
    $topName = ''
    $i = 0

    while ($i -lt $Text.Length) {
        $ch = $Text[$i]

        if ($ch -eq '<') {
            $j = $i + 1
            while ($j -lt $Text.Length -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            $tokenStart = $j
            while ($j -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$j]) -and $Text[$j] -ne '>' -and $Text[$j] -ne '"') { $j++ }
            $token = $Text.Substring($tokenStart, $j - $tokenStart)

            if ($angleStack.Count -eq 0) {
                $topKind = $token
                while ($j -lt $Text.Length -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
                $nameStart = $j
                while ($j -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$j]) -and $Text[$j] -ne '>' -and $Text[$j] -ne '"') { $j++ }
                $topName = $Text.Substring($nameStart, $j - $nameStart)
            }

            $angleStack.Add($token)
            $i++
            continue
        }

        if ($ch -eq '>' -and $angleStack.Count -gt 0) {
            $angleStack.RemoveAt($angleStack.Count - 1)
            if ($angleStack.Count -eq 0) {
                $topKind = ''
                $topName = ''
            }
            $i++
            continue
        }

        if ($ch -eq '(') {
            $j = $i + 1
            while ($j -lt $Text.Length -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
            $tokenStart = $j
            while ($j -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$j]) -and $Text[$j] -ne ')') { $j++ }
            $parenStack.Add($Text.Substring($tokenStart, $j - $tokenStart))
            $i++
            continue
        }

        if ($ch -eq ')' -and $parenStack.Count -gt 0) {
            $parenStack.RemoveAt($parenStack.Count - 1)
            $i++
            continue
        }

        if ($ch -ne '"' -or ($i -gt 0 -and $Text[$i - 1] -eq '\')) {
            $i++
            continue
        }

        $stringStart = $i
        $i++
        $value = [Text.StringBuilder]::new()
        while ($i -lt $Text.Length) {
            $current = $Text[$i]
            if ($current -eq '\' -and $i + 1 -lt $Text.Length) {
                [void]$value.Append($current)
                $i++
                [void]$value.Append($Text[$i])
                $i++
                continue
            }
            if ($current -eq '"') {
                $i++
                break
            }
            [void]$value.Append($current)
            $i++
        }

        $angleParent = if ($angleStack.Count -gt 0) { $angleStack[$angleStack.Count - 1] } else { '' }
        $parenParent = if ($parenStack.Count -gt 0) { $parenStack[$parenStack.Count - 1] } else { '' }
        $results.Add([pscustomobject]@{
            source_file  = $SourceFile
            line         = Get-LineNumber $Text $stringStart
            top_kind     = $topKind
            top_name     = $topName
            angle_parent = $angleParent
            angle_path   = ($angleStack -join '/')
            paren_parent = $parenParent
            english      = ConvertFrom-ZilString $value.ToString()
        })
    }

    return $results
}

function Get-CommandRows {
    param([string]$SyntaxPath)

    $text = Select-Zork1Source (Remove-ZilComments ([IO.File]::ReadAllText($SyntaxPath)))
    $excludedRanges = [System.Collections.Generic.List[object]]::new()
    $depth = 0
    $formStart = -1
    $inString = $false
    for ($index = 0; $index -lt $text.Length; $index++) {
        $current = $text[$index]
        if ($inString) {
            if ($current -eq '\') {
                $index++
            } elseif ($current -eq '"') {
                $inString = $false
            }
            continue
        }
        if ($current -eq '"' -and -not ($index -gt 0 -and $text[$index - 1] -eq '\')) {
            $inString = $true
            continue
        }
        if ($current -eq '<') {
            if ($depth -eq 0) { $formStart = $index }
            $depth++
            continue
        }
        if ($current -eq '>' -and $depth -gt 0) {
            $depth--
            if ($depth -eq 0 -and $formStart -ge 0) {
                $formText = $text.Substring($formStart, $index - $formStart + 1)
                if ($formText -match '(?s)^<COND\s+\(<==\?\s+,ZORK-NUMBER\s+(2|3)>') {
                    $excludedRanges.Add([pscustomobject]@{ Start = $formStart; End = $index })
                }
                $formStart = -1
            }
        }
    }

    function Test-IsZork1SourceRange {
        param([int]$Index)
        return -not (@($excludedRanges | Where-Object { $Index -ge $_.Start -and $Index -le $_.End }).Count -gt 0)
    }

    $synonyms = @{}
    foreach ($match in [regex]::Matches($text, '(?ms)<SYNONYM\s+(?<body>[^>]*)>')) {
        if (-not (Test-IsZork1SourceRange $match.Index)) { continue }
        $tokens = ([regex]::Replace($match.Groups['body'].Value, '\s+', ' ').Trim()) -split ' '
        if ($tokens.Count -lt 2) { continue }
        $existing = if ($synonyms.ContainsKey($tokens[0])) { @($synonyms[$tokens[0]]) } else { @() }
        $synonyms[$tokens[0]] = @($existing + @($tokens | Select-Object -Skip 1) | Sort-Object -Unique)
    }

    $counts = @{}
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($text, '(?ms)<SYNTAX\s+(?<body>[^>]*)>')) {
        if (-not (Test-IsZork1SourceRange $match.Index)) { continue }
        $body = [regex]::Replace($match.Groups['body'].Value, '\s+', ' ').Trim()
        $parts = $body -split '\s+=\s+', 2
        if ($parts.Count -ne 2) { continue }
        $pattern = $parts[0].Trim()
        $handler = $parts[1].Trim()
        $verb = ($pattern -split ' ')[0]
        if (-not $counts.ContainsKey($verb)) { $counts[$verb] = 0 }
        $counts[$verb]++
        $aliasList = if ($synonyms.ContainsKey($verb)) { $synonyms[$verb] -join ' ' } else { '' }
        $rows.Add([pscustomobject]@{
            id              = ('command.{0}.{1:D2}' -f $verb, $counts[$verb])
            source_file     = 'gsyntax.zil'
            line            = Get-LineNumber $text $match.Index
            verb            = $verb
            english_pattern = $pattern
            handler         = $handler
            synonyms        = $aliasList
        })
    }
    return $rows
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Zork I source directory was not found: $SourceRoot"
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$allStrings = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $SourceRoot -Filter '*.zil' | Sort-Object Name) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($entry in Get-ZilStrings $text $file.Name) {
        $allStrings.Add($entry)
    }
}

$descriptionProperties = @('DESC', 'LDESC', 'FDESC', 'TEXT')
$rooms = @(
    $allStrings |
        Where-Object { $_.top_kind -eq 'ROOM' -and $_.paren_parent -in $descriptionProperties } |
        ForEach-Object {
            [pscustomobject]@{
                id          = ('room.{0}.{1}' -f $_.top_name, $_.paren_parent)
                source_file = $_.source_file
                line        = $_.line
                room        = $_.top_name
                property    = $_.paren_parent
                english     = $_.english
            }
        }
)

$objects = @(
    $allStrings |
        Where-Object { $_.top_kind -eq 'OBJECT' -and $_.paren_parent -in $descriptionProperties } |
        ForEach-Object {
            [pscustomobject]@{
                id          = ('object.{0}.{1}' -f $_.top_name, $_.paren_parent)
                source_file = $_.source_file
                line        = $_.line
                object      = $_.top_name
                property    = $_.paren_parent
                english     = $_.english
            }
        }
)

$outputForms = @('TELL', 'PRINTI', 'PRINC', 'JIGS-UP', 'OPEN-CLOSE', 'HACK-HACK', 'STUPID-CONTAINER', 'MUNG-ROOM', 'PUTP')
$messageCounts = @{}
$messages = @(
    $allStrings |
        Where-Object {
            $pathParts = @($_.angle_path -split '/')
            $hasOutputForm = @($pathParts | Where-Object { $_ -in $outputForms }).Count -gt 0
            $isMessageTable = $_.top_kind -eq 'GLOBAL' -and $_.angle_parent -in @('TABLE', 'LTABLE', 'GLOBAL')
            ($hasOutputForm -and $_.top_kind -ne 'PRINC') -or $isMessageTable
        } |
        ForEach-Object {
            $outputContainers = @($_.angle_path -split '/' | Where-Object { $_ -in $outputForms })
            $container = if ($outputContainers.Count -gt 0) { $outputContainers[$outputContainers.Count - 1] } else { $_.angle_parent }
            $key = ('{0}:{1}:{2}' -f $_.source_file, $_.top_name, $_.line)
            if (-not $messageCounts.ContainsKey($key)) { $messageCounts[$key] = 0 }
            $messageCounts[$key]++
            [pscustomobject]@{
                id          = ('message.{0}.{1}.{2}.{3:D2}' -f ([IO.Path]::GetFileNameWithoutExtension($_.source_file)), $_.top_name, $_.line, $messageCounts[$key])
                source_file = $_.source_file
                line        = $_.line
                routine     = $_.top_name
                container   = $container
                english     = $_.english
            }
        }
)

$commands = @(Get-CommandRows (Join-Path $SourceRoot 'gsyntax.zil'))

Write-Tsv (Join-Path $OutputRoot 'strings.tsv') @('source_file', 'line', 'top_kind', 'top_name', 'angle_parent', 'angle_path', 'paren_parent', 'english') @($allStrings)
Write-Tsv (Join-Path $OutputRoot 'rooms.tsv') @('id', 'source_file', 'line', 'room', 'property', 'english') $rooms
Write-Tsv (Join-Path $OutputRoot 'objects.tsv') @('id', 'source_file', 'line', 'object', 'property', 'english') $objects
Write-Tsv (Join-Path $OutputRoot 'messages.tsv') @('id', 'source_file', 'line', 'routine', 'container', 'english') $messages
Write-Tsv (Join-Path $OutputRoot 'commands.tsv') @('id', 'source_file', 'line', 'verb', 'english_pattern', 'handler', 'synonyms') $commands

Write-Host ('strings={0} rooms={1} objects={2} messages={3} commands={4}' -f $allStrings.Count, $rooms.Count, $objects.Count, $messages.Count, $commands.Count)
