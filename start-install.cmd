@echo off
title Fabric 1.20.1 Modpack Installer
echo.
echo  Startet den Modpack-Installierer.
echo  Das Script wird einmalig als lokale Datei in den Temp-Ordner
echo  geladen und dort ausgefuehrt. Kein Script-Einzeiler noetig.
echo  Minecraft 1.20.1 + Fabric + 7 gepinnte Mods.
echo.
echo  Kein offizielles Produkt von Mojang/Microsoft.
echo.
pause
set "URL=https://raw.githubusercontent.com/92mxs21/fabric/main/install.ps1"
set "DEST=%TEMP%\fabric-modpack-install.ps1"
echo  Lade install.ps1 ...
curl.exe -L -s -o "%DEST%" "%URL%"
if errorlevel 1 (
  echo.
  echo  Download fehlgeschlagen. Bitte Internet pruefen und erneut starten.
  pause
  exit /b 1
)
for %%A in ("%DEST%") do set "SIZE=%%~zA"
if %SIZE% LSS 20000 (
  echo.
  echo  Datei unvollstaendig. Bitte erneut starten.
  pause
  exit /b 1
)
echo  Starte Installation (lokale Datei: %DEST%) ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%"
echo.
echo  Fertig.
pause