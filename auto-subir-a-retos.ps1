$ErrorActionPreference = 'Stop'

$project = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$targetRemote = 'https://github.com/programmigproof/retos-Frontend.git'
$remoteName = 'retos'
$quietSeconds = 4

function Invoke-Git {
    param([string[]]$Arguments)

    & git -C $project @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo git $($Arguments -join ' ') (codigo $LASTEXITCODE)."
    }
}

function Get-RelativePath {
    param([string]$FullPath)

    $full = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($project + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    return $full.Substring($project.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}

function Test-ExcludedPath {
    param([string]$RelativePath)

    $parts = $RelativePath -split '[\\/]'
    foreach ($part in $parts) {
        if ($part -in @('.git', '.vscode', 'node_modules')) {
            return $true
        }
    }

    return $false
}

function Add-ExistingProjectFiles {
    param([string]$Directory)

    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.PSIsContainer) {
            if ($item.Name -in @('.git', '.vscode', 'node_modules')) {
                continue
            }

            Add-ExistingProjectFiles -Directory $item.FullName
            continue
        }

        $relativePath = Get-RelativePath -FullPath $item.FullName
        if ($relativePath -and -not (Test-ExcludedPath -RelativePath $relativePath)) {
            & git --literal-pathspecs -C $project add --all -- $relativePath
            if ($LASTEXITCODE -ne 0) {
                throw "No se pudo preparar el archivo: $relativePath"
            }
        }
    }
}

$repoRoot = & git -C $project rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
    throw 'La carpeta del script no esta dentro de un repositorio Git.'
}
$repoRoot = [System.IO.Path]::GetFullPath(($repoRoot | Select-Object -First 1).Trim()).TrimEnd('\', '/')
if (-not $repoRoot.Equals($project, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Guarda el script en la raiz del repositorio para evitar publicar otra carpeta.'
}

$folderName = (Get-Item -LiteralPath $project).Name
$branch = $folderName.ToLowerInvariant() -replace '\s+', '-' -replace '[^a-z0-9._-]', '-' -replace '-{2,}', '-'
$branch = $branch.Trim('-', '.')
$branch = $branch -replace '\.{2,}', '-'
if (-not $branch -or $branch -in @('main', 'master')) {
    throw "El nombre de carpeta no produce una rama segura: '$branch'."
}
& git -C $project check-ref-format --branch $branch | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "El nombre de carpeta no es valido como rama Git: '$branch'."
}

$stagedBefore = & git -C $project diff --cached --name-only
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo inspeccionar el indice de Git.'
}
if (@($stagedBefore).Count -gt 0) {
    throw 'Hay cambios ya preparados en Git. Confirma o descarta esos cambios antes de iniciar la subida automatica.'
}

$configuredRemote = & git -C $project remote get-url $remoteName 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Git -Arguments @('remote', 'add', $remoteName, $targetRemote)
    $configuredRemote = $targetRemote
}
if ($configuredRemote -notmatch 'github\.com[:/]programmigproof/retos-Frontend(?:\.git)?$') {
    throw "El remoto '$remoteName' apunta a otro repositorio: $configuredRemote"
}

$remoteBranch = & git -C $project ls-remote --exit-code --heads $remoteName $branch
$remoteBranchExitCode = $LASTEXITCODE
if ($remoteBranchExitCode -notin @(0, 2)) {
    throw "No se pudo consultar la rama remota '$branch'."
}
$remoteBranchExists = $remoteBranchExitCode -eq 0
$currentBranch = & git -C $project branch --show-current
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo consultar la rama local.'
}
$currentBranch = ($currentBranch | Select-Object -First 1).Trim()

if ($currentBranch -ne $branch) {
    $localBranch = & git -C $project show-ref --verify --quiet "refs/heads/$branch"
    $localBranchExists = $LASTEXITCODE -eq 0

    if ($remoteBranchExists) {
        Invoke-Git -Arguments @('fetch', $remoteName, $branch)
        if ($localBranchExists) {
            Invoke-Git -Arguments @('switch', $branch)
            Invoke-Git -Arguments @('branch', '--set-upstream-to', "$remoteName/$branch", $branch)
        }
        else {
            Invoke-Git -Arguments @('switch', '--track', '-c', $branch, "$remoteName/$branch")
        }
    }
    elseif ($localBranchExists) {
        Invoke-Git -Arguments @('switch', $branch)
    }
    else {
        Invoke-Git -Arguments @('switch', '-c', $branch)
    }
}

Invoke-Git -Arguments @('push', '--set-upstream', $remoteName, $branch)

Add-ExistingProjectFiles -Directory $project

$stagedPaths = & git -C $project diff --cached --name-only
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudieron revisar los archivos preparados.'
}
$excludedStaged = @($stagedPaths | Where-Object { Test-ExcludedPath -RelativePath $_ })
if ($excludedStaged.Count -gt 0) {
    throw "La subida se detuvo porque hay archivos excluidos preparados: $($excludedStaged -join ', ')"
}
if (@($stagedPaths).Count -gt 0) {
    $initialMessage = 'Initial project sync: ' + $branch
    Invoke-Git -Arguments @('commit', '-m', $initialMessage)
    Invoke-Git -Arguments @('push', $remoteName, $branch)
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $project
$watcher.Filter = '*'
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::DirectoryName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
$watcher.InternalBufferSize = 65536

$sourceIds = @()
foreach ($eventName in @('Changed', 'Created', 'Deleted', 'Renamed', 'Error')) {
    $sourceId = "AutoSubirRetos-$eventName"
    Register-ObjectEvent -InputObject $watcher -EventName $eventName -SourceIdentifier $sourceId | Out-Null
    $sourceIds += $sourceId
}

$pendingPaths = @{}
$lastChange = $null
$watcher.EnableRaisingEvents = $true
Write-Host "Vigilando '$project' y publicando en '$remoteName/$branch'. Ctrl+C para detener."
Write-Host 'Se excluyen .git, .vscode y node_modules.'

try {
    while ($true) {
        $eventRecord = Wait-Event -Timeout 1
        if ($eventRecord) {
            if ($eventRecord.SourceIdentifier -eq 'AutoSubirRetos-Error') {
                throw "El monitor de archivos fallo: $($eventRecord.SourceEventArgs.GetException().Message)"
            }

            $eventArgs = $eventRecord.SourceEventArgs
            $changedPaths = @($eventArgs.FullPath)
            if ($eventArgs -is [System.IO.RenamedEventArgs]) {
                $changedPaths += $eventArgs.OldFullPath
            }

            foreach ($changedPath in $changedPaths) {
                $relativePath = Get-RelativePath -FullPath $changedPath
                if ($relativePath -and -not (Test-ExcludedPath -RelativePath $relativePath)) {
                    $pendingPaths[$relativePath] = $true
                    $lastChange = Get-Date
                }
            }

            Remove-Event -EventIdentifier $eventRecord.EventIdentifier
        }

        if ($lastChange -and ((Get-Date) - $lastChange).TotalSeconds -ge $quietSeconds) {
            foreach ($relativePath in @($pendingPaths.Keys)) {
                & git --literal-pathspecs -C $project add --all -- $relativePath
                if ($LASTEXITCODE -ne 0) {
                    throw "No se pudo preparar el cambio: $relativePath"
                }
            }

            $stagedPaths = & git -C $project diff --cached --name-only
            if ($LASTEXITCODE -ne 0) {
                throw 'No se pudieron revisar los cambios preparados.'
            }
            $excludedStaged = @($stagedPaths | Where-Object { Test-ExcludedPath -RelativePath $_ })
            if ($excludedStaged.Count -gt 0) {
                throw "La subida se detuvo porque hay archivos excluidos preparados: $($excludedStaged -join ', ')"
            }

            & git -C $project diff --cached --quiet
            $diffExitCode = $LASTEXITCODE
            if ($diffExitCode -eq 1) {
                $message = 'Auto-sync ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                Invoke-Git -Arguments @('commit', '-m', $message)
                Invoke-Git -Arguments @('push', $remoteName, $branch)
                Write-Host "Cambios publicados en '$remoteName/$branch'."
            }
            elseif ($diffExitCode -ne 0) {
                throw 'No se pudo comprobar si habia cambios preparados.'
            }

            $pendingPaths.Clear()
            $lastChange = $null
        }
    }
}
finally {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    foreach ($sourceId in $sourceIds) {
        Get-EventSubscriber | Where-Object { $_.SourceIdentifier -eq $sourceId } | Unregister-Event
    }
}
