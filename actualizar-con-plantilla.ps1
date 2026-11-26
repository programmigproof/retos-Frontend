$ErrorActionPreference = 'Stop'

$project = $PSScriptRoot
$parent = Split-Path -LiteralPath $project -Parent
$name = Split-Path -LiteralPath $project -Leaf
$backup = Join-Path $parent ("{0}-respaldo-{1}" -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$template = Join-Path $env:TEMP ("proyecto-base-tailwind-" + [guid]::NewGuid().ToString('N'))

try {
    & git clone --depth 1 --branch main https://github.com/programmigproof/proyecto-base-tailwind.git $template
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo clonar la plantilla (codigo $LASTEXITCODE)."
    }

    Copy-Item -LiteralPath $project -Destination $backup -Recurse

    & robocopy $template $project /E /XD .git /XC /XN /XO
    $copyExitCode = $LASTEXITCODE
    if ($copyExitCode -ge 8) {
        throw "No se pudieron copiar todos los archivos (codigo $copyExitCode). El respaldo esta en: $backup"
    }
}
finally {
    if (Test-Path -LiteralPath $template) {
        Remove-Item -LiteralPath $template -Recurse -Force
    }
}

Push-Location -LiteralPath $project
try {
    & npm install
    if ($LASTEXITCODE -ne 0) {
        throw "npm install fallo (codigo $LASTEXITCODE)."
    }

    & npm run dev
    if ($LASTEXITCODE -ne 0) {
        throw "npm run dev fallo (codigo $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}
