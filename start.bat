@echo off
setlocal

pushd "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "version controller\version-checker.ps1"
if errorlevel 1 (
  echo Version checker hata verdi. Uygulama yine baslatilmaya calisilacak.
)

if exist "app.exe" (
  start "" "app.exe"
) else (
  echo app.exe bulunamadi. Ana uygulama komutunu start.bat icinde guncelleyin.
  pause
)

popd
endlocal
