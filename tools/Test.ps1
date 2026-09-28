param(
    [string]$Rojo = 'rojo',
    [string]$Wally = 'wally',
    [string]$Studio = '',
    [ValidateRange(30, 1800)]
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent

function Invoke-CheckedTool {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code $LASTEXITCODE)."
    }
}

function Resolve-StudioExecutable {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "Roblox Studio executable not found: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    if ($IsWindows) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $versionsRoot = Join-Path $localAppData 'Roblox/Versions'
        if (Test-Path -LiteralPath $versionsRoot -PathType Container) {
            $candidate = Get-ChildItem -LiteralPath $versionsRoot -Directory |
                ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'RobloxStudioBeta.exe') -ErrorAction SilentlyContinue } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if ($candidate) {
                return $candidate.FullName
            }
        }
    } elseif ($IsMacOS) {
        $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $candidates = @(
            '/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio',
            (Join-Path $userProfile 'Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio')
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    } else {
        throw 'Runtime tests require Roblox Studio on Windows or macOS.'
    }

    throw 'Roblox Studio was not found. Install Studio or pass its executable path with -Studio.'
}

Push-Location $projectRoot
try {
    Invoke-CheckedTool $Wally @('install') 'Shared Wally dependency installation failed'
    Invoke-CheckedTool $Wally @('install', '--project-path', 'tests') 'Test Wally dependency installation failed'

    $verificationDirectory = Join-Path $projectRoot '.verification'
    New-Item -ItemType Directory -Force -Path $verificationDirectory | Out-Null

    $placePath = Join-Path $verificationDirectory 'mythic-legends-tests.rbxlx'
    $outputPath = Join-Path $verificationDirectory 'tests.log'
    $studioLogPath = Join-Path $verificationDirectory 'studio-tests.log'
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    if (Test-Path -LiteralPath $studioLogPath) {
        Remove-Item -LiteralPath $studioLogPath -Force
    }

    Invoke-CheckedTool $Rojo @('build', 'test.project.json', '-o', $placePath) 'Test place build failed'

    $studioExecutable = Resolve-StudioExecutable $Studio
    $runnerPath = Join-Path $projectRoot 'tests/RunTests.lua'
    $studioArguments = @(
        '--task', 'RunScript',
        '--localPlaceFile', $placePath,
        '--runScriptFile', $runnerPath,
        '--outputFile', $outputPath,
        '--quitAfterExecution'
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $studioExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $studioArguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $processStarted = $false
    try {
        $processStarted = $process.Start()
        if (-not $processStarted) {
            throw 'Roblox Studio did not start.'
        }

        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill($true)
            } catch {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
            $process.WaitForExit()
            $studioOutput = $standardOutputTask.GetAwaiter().GetResult()
            $studioError = $standardErrorTask.GetAwaiter().GetResult()
            [IO.File]::WriteAllText($studioLogPath, "$studioOutput$studioError")
            throw "Roblox Studio tests exceeded the $TimeoutSeconds-second timeout."
        }
        $process.WaitForExit()
        $studioOutput = $standardOutputTask.GetAwaiter().GetResult()
        $studioError = $standardErrorTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($studioLogPath, "$studioOutput$studioError")
        $studioExitCode = $process.ExitCode
    } finally {
        if ($processStarted -and -not $process.HasExited) {
            try {
                $process.Kill($true)
            } catch {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }
        $process.Dispose()
    }

    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Roblox Studio produced no test output: $outputPath"
    }

    $testOutput = Get-Content -LiteralPath $outputPath -Raw
    Write-Output $testOutput.TrimEnd()

    $resultMarkers = [regex]::Matches(
        $testOutput,
        '(?m)^MYTHIC_LEGENDS_TESTS:(PASS|FAIL)(?: [^\r\n]*)?\r?$'
    )
    if ($resultMarkers.Count -ne 1) {
        throw "Expected exactly one test result marker, found $($resultMarkers.Count)."
    }
    if ($resultMarkers[0].Groups[1].Value -eq 'FAIL') {
        throw 'Jest Roblox reported a test failure.'
    }
    if ($studioExitCode -ne 0) {
        throw "Roblox Studio exited with code $studioExitCode."
    }
} finally {
    Pop-Location
}
