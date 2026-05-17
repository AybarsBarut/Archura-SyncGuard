$ErrorActionPreference = "Continue"

$projectRoot = Split-Path -Parent $PSCommandPath
Set-Location -LiteralPath $projectRoot

& powershell -NoProfile -ExecutionPolicy Bypass -File "version controller\version-checker.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Version checker hata verdi. Uygulama yine baslatilmaya calisilacak."
}

$appPath = Join-Path $projectRoot "app.exe"
if (Test-Path -LiteralPath $appPath -PathType Leaf) {
    Start-Process -FilePath $appPath -WorkingDirectory $projectRoot
}
else {
    Write-Warning "app.exe bulunamadi. Ana uygulama komutunu start.ps1 icinde guncelleyin."
}
