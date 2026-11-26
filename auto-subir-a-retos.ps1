$ErrorActionPreference = 'Stop'

$project = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$targetRemote = 'https://github.com/programmigproof/retos-Frontend.git'
$remoteName = 'retos'
$quietSeconds = 4
$excludedParts = @('.git', '.vscode', 'node_modules')

function Invoke-Git {
    param([string[]]$Arguments)

    & git -C $repoRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo git $($Arguments -join ' ') (codigo $LASTEXITCODE)."
    }
}

function Test-ExcludedPath {
    param([string]$RelativePath)

    foreach ($part in ($RelativePath -split '[\\/]')) {
        if ($part -in $excludedParts) {
            return $true
        }
    }

    return $false
}

function Get-RelativePath {
    param([string]$FullPath)

    $full = [System.IO.Path]::GetFullPath($FullPath)
    $projectPrefix = $project + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    return $full.Substring($repoRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}

$folderName = (Get-Item -LiteralPath $project).Name
$branch = $folderName.ToLowerInvariant() -replace '\s+', '-' -replace '[^a-z0-9._-]', '-' -replace '-{2,}', '-'
$branch = $branch.Trim('-', '.')
$branch = $branch -replace '\.{2,}', '-'
if (-not $branch -or $branch -in @('main', 'master')) {
    throw "El nombre de carpeta no produce una rama segura: '$branch'."
}
& git check-ref-format --branch $branch | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "El nombre de carpeta no es valido como rama Git: '$branch'."
}

if (-not (Test-Path -LiteralPath (Join-Path $project '.git'))) {
    & git -C $project init
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo inicializar Git (codigo $LASTEXITCODE)."
    }
}

$repoRoot = & git -C $project rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
    throw 'La carpeta actual no esta dentro de un repositorio Git.'
}
$repoRoot = [System.IO.Path]::GetFullPath(($repoRoot | Select-Object -First 1).Trim()).TrimEnd('\', '/')
if (-not $project.Equals($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Ejecuta este monitor desde la raiz del proyecto.'
}

$remoteNames = & git -C $repoRoot remote
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudieron consultar los remotos Git.'
}

$configuredRemoteName = $null
foreach ($candidate in $remoteNames) {
    $configuredUrl = & git -C $repoRoot remote get-url $candidate
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo consultar la URL del remoto '$candidate'."
    }
    if ($configuredUrl -match 'github\.com[:/]programmigproof/retos-Frontend(?:\.git)?$') {
        $configuredRemoteName = $candidate
        break
    }
}

if (-not $configuredRemoteName) {
    if ($remoteNames -contains $remoteName) {
        throw "El remoto '$remoteName' ya existe, pero no apunta a $targetRemote."
    }
    & git -C $repoRoot remote add $remoteName $targetRemote
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo configurar el remoto '$remoteName' (codigo $LASTEXITCODE)."
    }
    $configuredRemoteName = $remoteName
}
$remoteName = $configuredRemoteName

$stagedBefore = & git -C $repoRoot diff --cached --name-only
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo inspeccionar el indice de Git.'
}
if (@($stagedBefore).Count -gt 0) {
    throw 'Hay cambios ya preparados en Git. Confirma o descarta esos cambios antes de iniciar la subida automatica.'
}

$remoteBranch = & git -C $repoRoot ls-remote --exit-code --heads $remoteName $branch
$remoteBranchExitCode = $LASTEXITCODE
if ($remoteBranchExitCode -notin @(0, 2)) {
    throw "No se pudo consultar la rama remota '$branch'."
}
$remoteBranchExists = $remoteBranchExitCode -eq 0

$currentBranch = & git -C $repoRoot branch --show-current
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo consultar la rama local.'
}
$currentBranch = ($currentBranch | Select-Object -First 1).Trim()
$localBranch = & git -C $repoRoot show-ref --verify --quiet "refs/heads/$branch"
$localBranchExists = $LASTEXITCODE -eq 0
$localSha = $null
if ($localBranchExists) {
    $localSha = & git -C $repoRoot rev-parse "refs/heads/$branch"
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo resolver el commit local de '$branch'."
    }
    $localSha = ($localSha | Select-Object -First 1).Trim()
}

if ($remoteBranchExists) {
    $branchRefspec = '+refs/heads/{0}:refs/remotes/{1}/{0}' -f $branch, $remoteName
    Invoke-Git -Arguments @('fetch', $remoteName, $branchRefspec)
    $remoteSha = & git -C $repoRoot rev-parse "refs/remotes/$remoteName/$branch"
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo resolver el commit remoto de '$branch'."
    }
    $remoteSha = ($remoteSha | Select-Object -First 1).Trim()

    if ($localBranchExists) {
        & git -C $repoRoot merge-base --is-ancestor $localSha $remoteSha
        $localIsBehind = $LASTEXITCODE -eq 0
        if ($localIsBehind) {
            Invoke-Git -Arguments @('update-ref', "refs/heads/$branch", $remoteSha, $localSha)
            $baseSha = $remoteSha
        }
        else {
            & git -C $repoRoot merge-base --is-ancestor $remoteSha $localSha
            if ($LASTEXITCODE -ne 0) {
                throw "La rama local y '$remoteName/$branch' divergen. No se sobrescribira ninguna rama."
            }
            $baseSha = $localSha
        }
    }
    else {
        Invoke-Git -Arguments @('update-ref', "refs/heads/$branch", $remoteSha)
        $baseSha = $remoteSha
    }

    Invoke-Git -Arguments @('symbolic-ref', 'HEAD', "refs/heads/$branch")
    Invoke-Git -Arguments @('read-tree', $baseSha)
}
elseif ($localBranchExists) {
    if ($currentBranch -ne $branch) {
        throw "La rama local '$branch' ya existe, pero no esta activa ni en el remoto. No se cambiara de rama automaticamente."
    }
    $baseSha = $localSha
    Invoke-Git -Arguments @('read-tree', $baseSha)
}
else {
    Invoke-Git -Arguments @('symbolic-ref', 'HEAD', "refs/heads/$branch")
    Invoke-Git -Arguments @('read-tree', '--empty')
}

$trackedPaths = & git -C $repoRoot ls-files
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudieron consultar los archivos rastreados.'
}
foreach ($trackedPath in $trackedPaths) {
    if (Test-ExcludedPath -RelativePath $trackedPath) {
        & git --literal-pathspecs -C $repoRoot rm --cached --ignore-unmatch -- $trackedPath
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo excluir el archivo rastreado: $trackedPath"
        }
    }
}

$stagedPaths = & git -C $repoRoot diff --cached --name-only
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudieron revisar los archivos preparados.'
}
$excludedStaged = @($stagedPaths | Where-Object { Test-ExcludedPath -RelativePath $_ })
if ($excludedStaged.Count -gt 0) {
    throw "Hay archivos excluidos preparados en Git: $($excludedStaged -join ', ')"
}

Invoke-Git -Arguments @('add', '--all', '--', '.')
$stagedPaths = & git -C $repoRoot diff --cached --name-only
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudieron revisar los archivos preparados.'
}
$excludedStaged = @($stagedPaths | Where-Object { Test-ExcludedPath -RelativePath $_ })
if ($excludedStaged.Count -gt 0) {
    throw "La subida se detuvo porque hay archivos excluidos preparados: $($excludedStaged -join ', ')"
}

& git -C $repoRoot diff --cached --quiet
$diffExitCode = $LASTEXITCODE
if ($diffExitCode -eq 1) {
    $message = 'Project sync: ' + $branch + ' ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Invoke-Git -Arguments @('commit', '-m', $message)
}
elseif ($diffExitCode -ne 0) {
    throw 'No se pudo comprobar si habia cambios preparados.'
}

Invoke-Git -Arguments @('push', '--set-upstream', $remoteName, $branch)

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
Write-Host "Vigilando '$project' y publicando solo en '$remoteName/$branch'. Ctrl+C para detener."
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
                Invoke-Git -Arguments @('--literal-pathspecs', 'add', '--all', '--', $relativePath)
            }

            $stagedPaths = & git -C $repoRoot diff --cached --name-only
            if ($LASTEXITCODE -ne 0) {
                throw 'No se pudieron revisar los cambios preparados.'
            }
            $excludedStaged = @($stagedPaths | Where-Object { Test-ExcludedPath -RelativePath $_ })
            if ($excludedStaged.Count -gt 0) {
                throw "La subida se detuvo porque hay archivos excluidos preparados: $($excludedStaged -join ', ')"
            }

            & git -C $repoRoot diff --cached --quiet
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
