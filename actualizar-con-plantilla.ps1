$ErrorActionPreference = 'Stop'

$project = $PSScriptRoot
$template = Join-Path $project (".proyecto-base-tailwind-" + [guid]::NewGuid().ToString('N'))

try {
    & git clone --depth 1 --branch main https://github.com/programmigproof/proyecto-base-tailwind.git $template
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo clonar la plantilla (codigo $LASTEXITCODE)."
    }

    & robocopy $template $project /E /XD .git /XC /XN /XO
    $copyExitCode = $LASTEXITCODE
    if ($copyExitCode -ge 8) {
        throw "No se pudieron copiar todos los archivos (codigo $copyExitCode). Revisa el proyecto antes de volver a ejecutar el actualizador."
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
