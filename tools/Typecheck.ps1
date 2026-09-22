param(
    [string]$Rojo = 'rojo',
    [string]$LuauLsp = 'luau-lsp',
    [string]$Wally = 'wally',
    [string]$WallyPackageTypes = 'wally-package-types'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $checkerVersion = (& $LuauLsp --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $checkerVersion -ne '1.70.0') {
        throw 'Install the pinned luau-lsp 1.70.0 from aftman.toml.'
    }
    $wallyVersion = (& $Wally --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $wallyVersion -ne 'wally 0.3.2') {
        throw 'Install the pinned Wally 0.3.2 from aftman.toml.'
    }
    $packageTypesVersion = (& $WallyPackageTypes --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $packageTypesVersion -ne 'wally-package-types 1.6.2') {
        throw 'Install the pinned wally-package-types 1.6.2 from aftman.toml.'
    }

    New-Item -ItemType Directory -Force -Path '.tools/luau-lsp', '.verification' | Out-Null
    $definitions = '.tools/luau-lsp/globalTypes.d.luau'
    $definitionsHash = '2B0DF788DC3FD1B572E71EE7FE9E1C55CC23882AFBD5024AECDEC30D9BD7520F'
    if (-not (Test-Path -LiteralPath $definitions)) {
        Invoke-WebRequest `
            'https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.0/scripts/globalTypes.d.luau' `
            -OutFile $definitions
    }
    if ((Get-FileHash -LiteralPath $definitions -Algorithm SHA256).Hash -ne $definitionsHash) {
        throw "Roblox API definitions do not match the pinned snapshot: $definitions"
    }

    # The type-export generator accepts Wally's original one-line entrypoints, not its
    # own previous output. Let Wally regenerate both package trees on every check.
    # This also repairs partially generated output after an interrupted/failed check.
    foreach ($manifestRoot in @('.', 'tests')) {
        & $Wally install --project-path $manifestRoot
        if ($LASTEXITCODE -ne 0) { throw "Wally dependency installation failed: $manifestRoot" }
    }

    & $Rojo sourcemap default.project.json --include-non-scripts --output .verification/sourcemap.json
    if ($LASTEXITCODE -ne 0) { throw 'Rojo sourcemap generation failed.' }

    # Wally's fresh entrypoints now receive export aliases; upstream sources stay untouched.
    foreach ($packages in @('Packages', 'tests/DevPackages')) {
        & $WallyPackageTypes --sourcemap .verification/sourcemap.json $packages `
            *> .verification/package-types.log
        if ($LASTEXITCODE -ne 0) {
            Get-Content .verification/package-types.log
            throw "Generating Wally type exports failed: $packages"
        }
    }

    & $LuauLsp analyze --platform=roblox --flag:LuauSolverV2=true `
        --sourcemap=.verification/sourcemap.json `
        --definitions=@roblox=.tools/luau-lsp/globalTypes.d.luau `
        '--ignore=Packages/**' '--ignore=src/ServerScriptService/Packages/**' `
        '--ignore=tests/DevPackages/**' src tests
    if ($LASTEXITCODE -ne 0) { throw 'Strict first-party Luau analysis failed.' }
} finally {
    Pop-Location
}
