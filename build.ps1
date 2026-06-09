# Empacota a Lambda (handler + pymysql) em lambda/build/ingest.zip
# Uso: ./build.ps1   (precisa de Python + pip no PATH)
#
# Obs: NAO usa Compress-Archive de proposito -- no Windows PowerShell 5.1 ele
# grava os caminhos com "\" e a Lambda (Linux) nao encontra o modulo. Aqui o zip
# e montado via .NET com entradas em "/" (compativel com o runtime Linux).

$ErrorActionPreference = "Stop"
$root    = $PSScriptRoot
$src     = Join-Path $root "lambda\ingest"
$staging = Join-Path $root "lambda\build\ingest"
$zip     = Join-Path $root "lambda\build\ingest.zip"

Write-Host "==> Limpando build anterior"
if (Test-Path (Join-Path $root "lambda\build")) {
    Remove-Item -Recurse -Force (Join-Path $root "lambda\build")
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null

Write-Host "==> Instalando dependencias"
python -m pip install -r (Join-Path $src "requirements.txt") -t $staging --quiet --disable-pip-version-check

Write-Host "==> Copiando handler"
Copy-Item (Join-Path $src "handler.py") -Destination $staging

Write-Host "==> Gerando $zip (entradas em '/')"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $base = (Resolve-Path $staging).Path.TrimEnd('\')
    Get-ChildItem -Recurse -File -Path $staging | ForEach-Object {
        $rel = $_.FullName.Substring($base.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $rel) | Out-Null
    }
} finally {
    $archive.Dispose()
}

Write-Host "OK -> $zip"
