param(
    [ValidateSet('ALL', 'RED-01', 'RED-02', 'RED-03')]
    [string]$Prueba = 'ALL'
)
$ErrorActionPreference = 'Stop'
$repoS06 = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoS06
try {
    $evidenceS06 = Join-Path $repoS06 'evidence/s06'
    New-Item -ItemType Directory -Path $evidenceS06 -Force | Out-Null
    $testArgsS06 = @('test', 'test/unit/s06_red_test.dart', '--no-pub', '--reporter', 'expanded', '--concurrency', '1')
    if ($Prueba -ne 'ALL') {
        $testArgsS06 += @('--plain-name', $Prueba)
    }
    Write-Host "S06 - Pruebas RED - $Prueba"
    Write-Host "flutter $($testArgsS06 -join ' ')"
    & flutter @testArgsS06 2>&1 | Tee-Object -FilePath (Join-Path $evidenceS06 "$Prueba.txt")
    $testExitS06 = $LASTEXITCODE
    Write-Host "Codigo de salida: $testExitS06 (1 esperado mientras las funciones esten pendientes)."
    exit $testExitS06
} finally {
    Pop-Location
}
