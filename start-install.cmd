@echo off
title Fabric 1.20.1 Modpack Installer
echo.
echo  Startet den Modpack-Installer.
echo  Der Installer wird einmalig von GitHub geladen und ausgefuehrt.
echo  Minecraft 1.20.1 + Fabric + 7 gepinnte Mods.
echo.
echo  Kein offizielles Produkt von Mojang/Microsoft.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/92mxs21/fabric-1.20.1-modpack/main/install.ps1 | iex"
echo.
echo  Das Installer-Fenster ist hier fertig.
pause