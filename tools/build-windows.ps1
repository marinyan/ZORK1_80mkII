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
    dotnet run --no-build --project $project -c Release -- --smoke
    exit $LASTEXITCODE
}

if ($Run) {
    dotnet run --no-build --project $project -c Release
}
