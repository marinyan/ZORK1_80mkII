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

function ConvertTo-TsvField {
    param($Value)

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    $escaped = $text.Replace("`r`n", '\n').Replace("`n", '\n').Replace("`t", '\t').Replace('"', '""')
    return '"' + $escaped + '"'
}

function Write-Tsv {
    param(
        [string]$RelativePath,
        [string[]]$Columns,
        [object[]]$Rows
    )

    $path = Join-Path $RepoRoot $RelativePath
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(($Columns -join "`t"))
    foreach ($row in $Rows) {
        $values = foreach ($column in $Columns) {
            ConvertTo-TsvField $row.$column
        }
        $lines.Add(($values -join "`t"))
    }
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
}

function Update-TranslationFile {
    param(
        [string]$CatalogPath,
        [string]$TranslationPath,
        [string[]]$ContextColumns
    )

    $catalog = Read-Tsv $CatalogPath
    $translation = Read-Tsv $TranslationPath

    $duplicates = @($translation | Group-Object id | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "$TranslationPath contains duplicate IDs: $($duplicates.Name -join ', ')"
    }

    $translationById = @{}
    foreach ($row in $translation) {
        $translationById[$row.id] = $row
    }

    $missing = @($catalog | Where-Object { -not $translationById.ContainsKey($_.id) })
    $extra = @($translation | Where-Object { $_.id -notin @($catalog.id) })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "$TranslationPath ID mismatch. Missing=[$($missing.id -join ', ')] Extra=[$($extra.id -join ', ')]"
    }

    $rows = foreach ($source in $catalog) {
        $translated = $translationById[$source.id]
        $notes = if ($translated.PSObject.Properties.Name -contains 'notes') { $translated.notes } else { '' }
        $values = [ordered]@{
            id          = $source.id
            english     = $source.english
            japanese    = $translated.japanese
            status      = $translated.status
            notes       = $notes
            source_file = $source.source_file
            line        = $source.line
        }
        foreach ($column in $ContextColumns) {
            $values[$column] = $source.$column
        }
        [pscustomobject]$values
    }

    $columns = @('id', 'english', 'japanese', 'status', 'notes', 'source_file', 'line') + $ContextColumns
    Write-Tsv $TranslationPath $columns @($rows)
    Write-Host ("updated {0}: {1} rows" -f $TranslationPath, $rows.Count)
}

Update-TranslationFile 'translation/catalog/rooms.tsv' 'translation/ja/rooms.tsv' @('room', 'property')
Update-TranslationFile 'translation/catalog/objects.tsv' 'translation/ja/objects.tsv' @('object', 'property')
Update-TranslationFile 'translation/catalog/messages.tsv' 'translation/ja/messages.tsv' @('routine', 'container')
