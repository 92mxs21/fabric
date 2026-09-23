<#
================================================================================
  Minecraft 1.20.1 + Fabric Modpack-Installer (Windows PowerShell)
================================================================================
  Installiert NUR Minecraft 1.20.1 mit:
   - offiziellem Fabric Installer (CLI, neueste Loader-Version automatisch)
   - exakt versionierten Mods von Modrinth (Architectury, Cloth Config,
     Dreamshift, Fabric API, Immersive Portals, Sodium, Simple Voice Chat)

  Eigenschaften:
   - Idempotent: Wiederholte Ausführung ist gefahrlos, bereits vorhandene und
     korrekte Dateien werden übersprungen.
   - Vorherige nicht benötigte .jar-Mods werden in einen datierten
     <Zeitstempel>modbackup-Ordner verschoben.
   - Übersichtliche Fortschrittsausgabe, Fehlerbehandlung mit Retry und
     SHA1-Verifikation aller Downloads.
   - Funktioniert als lokale Datei ODER per Einzeiler:
       powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/92mxs21/fabric-1.20.1-modpack/main/install.ps1 | iex"

  Aufruf:
   .\install.ps1                        (Standard: erkanntes .minecraft)
   .\install.ps1 -MinecraftDir C:\mc    (anderes Verzeichnis)
   .\install.ps1 -DryRun                (nur Planung, nichts verändern)
   .\install.ps1 -Force                 (Installer + Mods erzwingen)

  Parameter:
   -MinecraftDir [string]   Zielordner (Standard: %APPDATA%\.minecraft)
   -ConfigPath   [string]   Pfad zur modpack.json (Standard: config\modpack.json
                            neben dem Script bzw. Remote aus dem Repo)
   -DryRun                  Nur prüfen und anzeigen, nichts installieren
   -Force                   Installiert auch bereits vorhandene Dateien neu
================================================================================
#>

#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MinecraftDir,
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$Force
)

#------------------------------------------------------------------------------
# Konstanten
#------------------------------------------------------------------------------
$script:RawBase        = 'https://raw.githubusercontent.com/92mxs21/fabric-1.20.1-modpack/main'
$script:FabricMetaBase = 'https://meta.fabricmc.net/v2'
$script:FabricMaven    = 'https://maven.fabricmc.net'
$script:ModrinthApi    = 'https://api.modrinth.com/v2'
$script:UserAgent      = 'Install-PS1/1.1.0 (Fabric 1.20.1 Modpack; +https://github.com/92mxs21/fabric-1.20.1-modpack)'
$script:ScriptVersion  = '1.1.0'

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# TLS 1.2 für ältere Windows PowerShell 5.1 erzwingen
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# Ausgabekodierung auf UTF-8 stellen, damit Umlaute (ä/ö/ü/ß) überall sauber
# angezeigt werden: interaktiv, per "irm ... | iex" und in umgeleiteter Ausgabe
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

#------------------------------------------------------------------------------
# Ausgabe-Helfer
#------------------------------------------------------------------------------
function Write-StepTitle([string]$Text) {
    Write-Host ''
    Write-Host ("  > " + $Text) -ForegroundColor Cyan
}
function Write-Info([string]$Text)  { Write-Host ("      " + $Text) -ForegroundColor Gray }
function Write-Ok([string]$Text)    { Write-Host ("      [OK]   " + $Text) -ForegroundColor Green }
function Write-Warn([string]$Text)  { Write-Host ("      [WARN] " + $Text) -ForegroundColor Yellow }
function Write-Err([string]$Text)   { Write-Host ("      [FEHLER] " + $Text) -ForegroundColor Red }

# Beendet das Script sauber. Der Exit-Code wird nur gesetzt, wenn das Script
# als Unterprozess (powershell -File ...) aufgerufen wurde. Bei interaktiver
# Ausführung oder "irm ... | iex" bleibt das Fenster geöffnet.
function Set-ScriptExit([int]$Code) {
    if ($PSCommandPath -and -not $script:InvocationLine) { exit $Code }
}

#------------------------------------------------------------------------------
# Netzwerk-Helfer
#------------------------------------------------------------------------------
function Invoke-GetJson {
    param([string]$Uri)
    $lastError = $null
    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        try {
            $data = Invoke-RestMethod -Uri $Uri -Headers @{ 'User-Agent' = $script:UserAgent } -TimeoutSec 45
            $ok = $true
            break
        } catch {
            $lastError = $_.Exception.Message
            if ($i -lt 3) { Start-Sleep -Seconds (2 * $i) }
        }
    }
    if (-not $ok) { throw "API-Anfrage fehlgeschlagen ($Uri)`n      $lastError" }
    # Über die Pipeline ausgeben (kein "return" im try-Block, sonst werden
    # JSON-Arrays verschachtelt zurückgegeben und landen als ein Objekt)
    $data
}

function Invoke-FileDownload {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Label,
        [int64]$ExpectedSize = 0,
        [int]$Retries = 3
    )
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 0) { Remove-Item $OutFile -Force }
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFileAsync([Uri]$Url, $OutFile)
            # Echter Download-Prozess: im Haupt-Thread pollen und prozentualen
            # Fortschritt samt MB und MB/s anzeigen (kein Event-Handler: der liefe
            # auf einem Thread ohne Runspace und würde in PowerShell abstürzen)
            $lastPct    = -1
            $lastBytes  = [int64]0
            $lastTick   = [Environment]::TickCount
            $speed      = 0.0
            $hadOutput  = $false
            $firstBytes = $false
            while ($wc.IsBusy) {
                Start-Sleep -Milliseconds 300
                if (-not (Test-Path $OutFile)) { continue }
                $cur  = [int64](Get-Item $OutFile).Length
                $now  = [Environment]::TickCount
                $dt   = $now - $lastTick
                if ($dt -ge 600) {
                    if ($dt -gt 0) {
                        $speed = [math]::Round((($cur - $lastBytes) * 1000.0) / $dt / 1MB, 2)
                    }
                    $lastTick  = $now
                    $lastBytes = $cur
                    $hadOutput = $true
                    if ($ExpectedSize -gt 0) {
                        $pct = [math]::Min(99, [math]::Floor(($cur * 100) / $ExpectedSize))
                        if ($pct -ne $lastPct) {
                            $lastPct = $pct
                            Write-Host ("`r      {0,-22} {1,3} %  ({2,7:N1} / {3,7:N1} MB, {4,6:N1} MB/s)" -f $Label, $pct, ($cur / 1MB), ($ExpectedSize / 1MB), $speed) -NoNewline
                        }
                    } else {
                        # Größe unbekannt (z. B. Temurin-JRE zum Download vorbereiten):
                        # nur geladene MB anzeigen, sobald überhaupt Bytes fließen
                        if (-not $firstBytes -and $cur -gt 0) {
                            $firstBytes = $true
                            Write-Info "Starte Download: $Label -> $OutFile"
                        }
                        Write-Host ("`r      {0,-22} {1,7:N1} MB geladen, {2,6:N1} MB/s" -f $Label, ($cur / 1MB), $speed) -NoNewline
                    }
                }
            }
            $wc.Dispose()
            if ($hadOutput) { Write-Host ' ' }
            if (-not ($hadOutput -or $firstBytes)) { Write-Info "Starte Download: $Label -> $OutFile" }
            if (-not (Test-Path $OutFile)) { throw 'Datei wurde nicht erstellt.' }
            $finalSize = (Get-Item $OutFile).Length
            if ($finalSize -le 0) { throw 'Datei ist leer.' }
            if ($ExpectedSize -gt 0 -and $finalSize -ne $ExpectedSize) {
                throw "Größe unerwartet (erwartet: $ExpectedSize, erhalten: $finalSize)."
            }
            Write-Ok "$Label heruntergeladen ($([math]::Round($finalSize / 1MB, 1)) MB)."
            return
        } catch {
            Write-Host ''
            Write-Warn "Download fehlgeschlagen (Versuch $i/$Retries): $($_.Exception.Message)"
            if ($i -lt $Retries) { Start-Sleep -Seconds 2 }
        }
    }
    throw "Download fehlgeschlagen: $Url"
}

#------------------------------------------------------------------------------
# Versions-Normalisierung: "mc1.20.1-0.5.13-fabric" -> "0.5.13"
#------------------------------------------------------------------------------
function ConvertTo-NormalizedVersion {
    param([string]$Value)
    $v = $Value.Trim().ToLowerInvariant()
    $v = [regex]::Replace($v, '^mc\d+(\.\d+)*-', '')            # mc1.20.1-...
    $v = [regex]::Replace($v, '^fabric-\d+(\.\d+)*-', '')       # fabric-1.20.1-...
    $v = [regex]::Replace($v, '(\+fabric|-fabric)$', '')        # +fabric / -fabric
    $v = [regex]::Replace($v, '\+(mc)?\d+(\.\d+)*$', '')        # +1.20.1 etc.
    return $v
}

#------------------------------------------------------------------------------
# Java
#------------------------------------------------------------------------------
function Get-JavaMajor {
    param([string]$JavaPath)
    try {
        $line = (& $JavaPath '-version' 2>&1 | Select-Object -First 1 | Out-String)
        if ($line -match 'version "([0-9]+)') {
            $major = [int]$Matches[1]
            if ($major -eq 1) { return 8 }   # "1.8.0_..." => Java 8
            return $major
        }
    } catch {}
    return 0
}

function Find-Java {
    $cands = @()
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }
    if ($env:JAVA_HOME) { $cands += (Join-Path $env:JAVA_HOME 'bin\java.exe') }
    # Tiefensuche begrenzen (-Depth), damit riesige Ordnertrees (z. B. Program Files\Microsoft) nicht abgesucht werden
    $cands += @(Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Filter java.exe -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $cands += @(Get-ChildItem 'C:\Program Files\Java' -Filter java.exe -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $cands += @(Get-ChildItem 'C:\Program Files\Microsoft' -Filter java.exe -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $cands += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'fabric-modpack-jre') -Filter java.exe -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object FullName)
    foreach ($c in @($cands | Select-Object -Unique)) {
        if ($c -and (Test-Path $c)) {
            $major = Get-JavaMajor $c
            if ($major -gt 0) { return [pscustomobject]@{ Path = $c; Major = $major } }
        }
    }
    return $null
}

function Install-TemurinJre {
    $tools = Join-Path $env:LOCALAPPDATA 'fabric-modpack-jre'
    New-Item -ItemType Directory -Path $tools -Force | Out-Null
    $zip = Join-Path $tools 'jre17.zip'
    $exe = $null
    Write-Info 'Lade Temurin JRE 17 herunter (für den Fabric Installer) ...'
    Invoke-FileDownload -Url 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jre/hotspot/normal/eclipse' -OutFile $zip -Label 'Temurin JRE 17'
    Write-Info 'Entpacke JRE ...'
    Expand-Archive -Path $zip -DestinationPath (Join-Path $tools 'jre17') -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    $exe = @(Get-ChildItem (Join-Path $tools 'jre17') -Filter java.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    if (-not $exe -or -not (Test-Path $exe)) { throw 'Temurin JRE konnte nicht installiert werden.' }
    return $exe
}

#------------------------------------------------------------------------------
# Fabric (Loader-Versionen + Installer)
#------------------------------------------------------------------------------
function Get-FabricVersions {
    param([string]$McVer)
    $loaders = @(Invoke-GetJson "$script:FabricMetaBase/versions/loader/$McVer")
    if ($loaders.Count -eq 0) { throw "Keine Fabric-Loader-Versionen für $McVer verfügbar." }
    $stable = $loaders | Where-Object { $_.loader.stable -eq $true } | Select-Object -First 1
    if (-not $stable) { $stable = $loaders | Select-Object -First 1 }
    $installers = @(Invoke-GetJson "$script:FabricMetaBase/versions/installer")
    if ($installers.Count -eq 0) { throw 'Keine Fabric-Installer-Version verfügbar.' }
    return [pscustomobject]@{
        LoaderVersion    = $stable.loader.version
        InstallerVersion = $installers[0].version
    }
}

function Get-InstalledFabricLoader {
    param([string]$McDir, [string]$McVer)
    $versDir = Join-Path $McDir 'versions'
    if (-not (Test-Path $versDir)) { return $null }
    $pattern = "^fabric-loader-(.+)-$([regex]::Escape($McVer))$"
    foreach ($folder in @(Get-ChildItem $versDir -Directory -Filter 'fabric-loader-*' -ErrorAction SilentlyContinue)) {
        if ($folder.Name -match $pattern) { return $Matches[1] }
    }
    return $null
}

function Invoke-FabricInstaller {
    param([string]$InstallerJar, [string]$JavaPath, [string]$McDir, [string]$McVer, [string]$LoaderVer)
    if ($script:DryRun) {
        Write-Info "DryRun: Befehl wäre:`n      & `"$JavaPath`" -jar `"$InstallerJar`" client -dir `"$McDir`" -mcversion $McVer -loader $LoaderVer"
        return
    }
    $output = & $JavaPath '-jar' $InstallerJar 'client' '-dir' $McDir '-mcversion' $McVer '-loader' $LoaderVer 2>&1
    foreach ($line in $output) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            Write-Warn ($line.ToString())
        } else {
            Write-Info ($line.ToString())
        }
    }
    if ($LASTEXITCODE -ne 0) { throw "Fabric Installer endete mit Exit-Code $LASTEXITCODE." }
}

#------------------------------------------------------------------------------
# Modrinth
#------------------------------------------------------------------------------
function Resolve-ModrinthMod {
    param($Mod)
    $mcVer = $script:Config.minecraftVersion
    $query = '?game_versions=' + [uri]::EscapeDataString("`"[$mcVer]`"") + '&loaders=' + [uri]::EscapeDataString('["fabric"]')
    $versions = @(Invoke-GetJson "$script:ModrinthApi/project/$($Mod.slug)/version$query")

    $wantExact = if ($Mod.modrinthVersion) { [string]$Mod.modrinthVersion } else { [string]$Mod.version }
    $v = $versions | Where-Object { $_.version_number -eq $wantExact } | Select-Object -First 1
    if (-not $v) {
        $wantNorm = ConvertTo-NormalizedVersion $wantExact
        $v = $versions | Where-Object {
            ($_.loaders -contains 'fabric') -and
            ($_.game_versions -contains $mcVer) -and
            ((ConvertTo-NormalizedVersion $_.version_number) -eq $wantNorm)
        } | Select-Object -First 1
    }
    if (-not $v) {
        throw "Version '$wantExact' für Mod '$($Mod.slug)' wurde für Fabric/$mcVer nicht gefunden."
    }
    if (-not ($v.loaders -contains 'fabric')) {
        throw "Mod '$($Mod.slug)' ist nicht als Fabric-Mod verfügbar (nur: $($v.loaders -join ', '))."
    }
    if (-not ($v.game_versions -contains $mcVer)) {
        throw "Mod '$($Mod.slug)' ist nicht für $mcVer verfügbar (nur: $($v.game_versions -join ', '))."
    }
    $file = $v.files | Where-Object { $_.primary -eq $true } | Select-Object -First 1
    if (-not $file) { $file = $v.files | Select-Object -First 1 }
    if (-not $file) { throw "Mod '$($Mod.slug)' hat keine Datei." }
    if (-not ($file.filename -like '*.jar')) {
        throw "Primär-Datei von Mod '$($Mod.slug)' ist keine .jar-Datei (Fabric/$mcVer)."
    }
    return [pscustomobject]@{
        Name             = $Mod.name
        Slug             = $Mod.slug
        RequestedVersion = [string]$Mod.version
        VersionNumber    = $v.version_number
        FileName         = $file.filename
        Url              = $file.url
        Size             = [int64]$file.size
        Sha1             = $file.hashes.sha1
        GameVersions     = ($v.game_versions -join ', ')
        Loaders          = ($v.loaders -join ', ')
    }
}

function Get-Sha1 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA1).Hash.ToLowerInvariant()
}

#------------------------------------------------------------------------------
# Backup nicht benötigter Mods -> datierter mods-backup-Ordner
#------------------------------------------------------------------------------
function New-ModsBackup {
    param([string]$ModsDir, [string[]]$KeepFileNames)
    $toMove = @(Get-ChildItem $ModsDir -Filter *.jar -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $KeepFileNames })
    if ($toMove.Count -eq 0) {
        Write-Info 'Keine fremden .jar-Mods gefunden -> kein Backup nötig.'
        return $null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    # Datierter Backup-Ordner direkt neben "mods": <Zeitstempel>modbackup
    $dest = Join-Path (Split-Path $ModsDir -Parent) ($stamp + 'modbackup')
    Write-Info "Verschiebe $($toMove.Count) nicht benötigte .jar-Mod(s) nach:"
    Write-Info $dest
    if ($script:DryRun) {
        foreach ($t in $toMove) { Write-Info "  - $($t.Name)" }
        return $dest
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    foreach ($t in $toMove) {
        Move-Item -Path $t.FullName -Destination (Join-Path $dest $t.Name) -Force
        Write-Info "  - $($t.Name)"
    }
    Write-Ok "$($toMove.Count) Mod(s) nach '$dest' gesichert."
    return $dest
}

#------------------------------------------------------------------------------
# Launcher-Profile-Datei sicherstellen (Fabric Installer 1.x bricht sonst ab,
# wenn weder launcher_profiles.json noch launcher_profiles_microsoft_store.json
# existiert. Der echte Launcher legt sie beim ersten Start an.)
#------------------------------------------------------------------------------
function Ensure-LauncherProfiles {
    param([string]$McDir)
    $win32 = Join-Path $McDir 'launcher_profiles.json'
    $store = Join-Path $McDir 'launcher_profiles_microsoft_store.json'
    if ((Test-Path $win32) -or (Test-Path $store)) { return }
    if ($script:DryRun) {
        Write-Info 'DryRun: würde eine minimale launcher_profiles.json anlegen.'
        return
    }
    $minimal = @{ profiles = @{}; settings = @{}; selectedProfile = '' } | ConvertTo-Json -Depth 3
    Set-Content -Path $win32 -Value $minimal -Encoding UTF8
    Write-Info "Minimale launcher_profiles.json angelegt ($win32)"
}

#------------------------------------------------------------------------------
# Hauptprogramm
#------------------------------------------------------------------------------
$script:DryRun = [bool]$DryRun
$script:Force  = [bool]$Force
$script:InvocationLine = $MyInvocation.Line
try {
    # ------------------------------------------------------------------ Header
    Write-Host ''
    Write-Host '========================================================================' -ForegroundColor DarkCyan
    Write-Host ("  Minecraft 1.20.1 + Fabric Modpack-Installer   v{0}" -f $script:ScriptVersion) -ForegroundColor Cyan
    Write-Host '  Offizieller Fabric Installer (CLI)  |  Mods von Modrinth  |  nur Fabric/1.20.1' -ForegroundColor Cyan
    if ($script:DryRun) { Write-Host '  *** TROCKENLAUF (DryRun) - es wird nichts veraendert ***' -ForegroundColor Yellow }
    Write-Host '  Idempotent  |  Backup vor der Installation  |  SHA1-Verifikation' -ForegroundColor DarkGray
    Write-Host '========================================================================' -ForegroundColor DarkCyan

    # ------------------------------------------------------------- 1) Konfiguration
    Write-StepTitle 'Schritt 1/10: Konfiguration laden'
    if (-not $ConfigPath) {
        $localConfig = $null
        if ($PSScriptRoot) { $localConfig = Join-Path $PSScriptRoot 'config\modpack.json' }
        if ($localConfig -and (Test-Path $localConfig)) {
            $ConfigPath = $localConfig
        } else {
            $ConfigPath = Join-Path $env:TEMP 'modpack-1.20.1.json'
            Write-Info 'Keine lokale Konfiguration gefunden - lade modpack.json aus dem Repository ...'
            Invoke-FileDownload -Url "$script:RawBase/config/modpack.json" -OutFile $ConfigPath -Label 'modpack.json'
        }
    }
    if (-not (Test-Path $ConfigPath)) { throw "Konfiguration nicht gefunden: $ConfigPath" }
    $script:Config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $mcVer = [string]$script:Config.minecraftVersion
    if ($mcVer -ne '1.20.1') { Write-Warn "Konfigurierte Minecraft-Version '$mcVer' weicht von 1.20.1 ab." }
    Write-Ok "Konfiguration geladen ($ConfigPath)"
    Write-Info "Minecraft-Version: $mcVer | Loader: $($script:Config.loader) | Mods: $($script:Config.mods.Count)"

    # ----------------------------------------------------------- 2) Verzeichnis
    Write-StepTitle 'Schritt 2/10: Minecraft-Verzeichnis bestimmen'
    $mcDir = $MinecraftDir
    if (-not $mcDir) {
        $guess = Join-Path $env:APPDATA '.minecraft'
        if (Test-Path $guess) { $mcDir = $guess }
        else { throw "Kein .minecraft unter '$guess' gefunden. Übergib '-MinecraftDir <Pfad>'.`n      Hinweis: Starte den offiziellen Launcher einmal, damit der Ordner angelegt wird." }
    }
    if (-not (Test-Path $mcDir)) { New-Item -ItemType Directory -Path $mcDir -Force | Out-Null }
    $modsDir = Join-Path $mcDir 'mods'
    if (-not (Test-Path $modsDir)) { New-Item -ItemType Directory -Path $modsDir -Force | Out-Null }
    Write-Ok "Verzeichnis: $mcDir"

    # --------------------------------------------------------------- 3) Java
    Write-StepTitle 'Schritt 3/10: Java prüfen'
    $java = Find-Java
    if ($java) {
        Write-Ok "Java $($java.Major) gefunden ($($java.Path))"
        if ($java.Major -lt 8) {
            throw "Java 8 oder neuer wird für den Fabric Installer benötigt (gefunden: $($java.Major))."
        }
        if ($java.Major -lt 17) {
            Write-Info 'Hinweis: Jede Java-Version ab 8 funktioniert für die Installation. Zum Spielen bringt der offizielle Launcher seinen eigenen Java-Runtime mit.'
        }
    } else {
        if ($script:Config.autoDownloadJava -eq $false) {
            throw 'Kein Java gefunden und autoDownloadJava ist deaktiviert. Installiere Java 17 oder aktiviere autoDownloadJava in der Konfiguration.'
        }
        Write-Warn 'Kein Java gefunden - lade Temurin JRE 17 automatisch herunter.'
        $autoJava = Install-TemurinJre
        $java = [pscustomobject]@{ Path = $autoJava; Major = 17 }
        Write-Ok "Java 17 installiert ($($java.Path))"
    }
    if ($script:DryRun) { Write-Info 'DryRun: Java würde nur zum Installieren des Fabric-Loaders verwendet.' }

    # ------------------------------------------------ 4) Fabric Installer laden
    Write-StepTitle 'Schritt 4/10: Fabric Installer / Loader-Versionen ermitteln'
    $fab = Get-FabricVersions -McVer $mcVer
    $installerVer = $fab.InstallerVersion
    $loaderVer    = $fab.LoaderVersion
    Write-Ok "Fabric Loader (neueste für $mcVer): $loaderVer"
    Write-Ok "Fabric Installer: $installerVer"

    Write-StepTitle 'Schritt 5/10: Fabric Installer herunterladen'
    $toolsDir = Join-Path $env:LOCALAPPDATA 'fabric-modpack-tools'
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $installerJar = Join-Path $toolsDir "fabric-installer-$installerVer.jar"
    $installerUrl = "$script:FabricMaven/net/fabricmc/fabric-installer/$installerVer/fabric-installer-$installerVer.jar"
    if ($script:DryRun) {
        Write-Info "DryRun: Download übersprungen (wäre: $installerUrl)"
    } elseif ((Test-Path $installerJar) -and ((Get-Item $installerJar).Length -gt 100000) -and -not $script:Force) {
        Write-Ok "Installer ist bereits vorhanden ($installerJar)"
    } else {
        Invoke-FileDownload -Url $installerUrl -OutFile $installerJar -Label 'Fabric Installer'
        Write-Ok 'Fabric Installer heruntergeladen.'
    }

    # ----------------------------------------------- 6) Fabric-Profil installieren
    Write-StepTitle 'Schritt 6/10: Fabric-Profil für 1.20.1 installieren'
    $installedLoader = Get-InstalledFabricLoader -McDir $mcDir -McVer $mcVer
    if ($installedLoader -and ($installedLoader -eq $loaderVer) -and -not $script:Force) {
        Write-Ok "Fabric Profil 'fabric-loader-$loaderVer-$mcVer' ist bereits aktuell installiert."
    } else {
        if ($installedLoader) { Write-Warn "Vorhandener Loader: $installedLoader -> aktualisiere auf $loaderVer" }
        # Fabric Installer braucht eine erkannte Launcher-Profile-Datei
        Ensure-LauncherProfiles -McDir $mcDir
        Invoke-FabricInstaller -InstallerJar $installerJar -JavaPath $java.Path -McDir $mcDir -McVer $mcVer -LoaderVer $loaderVer
        if ($script:DryRun) { Write-Info "DryRun: Fabric-Profil 'fabric-loader-$loaderVer-$mcVer' würde installiert." }
        else { Write-Ok "Fabric Profil 'fabric-loader-$loaderVer-$mcVer' installiert." }
    }

    # --------------------------------------------------- 7) Modrinth-Metadaten
    Write-StepTitle 'Schritt 7/10: Mod-Informationen von Modrinth abrufen'
    $resolvedMods = @()
    $modCount = $script:Config.mods.Count
    $mi = 0
    foreach ($m in $script:Config.mods) {
        $mi++
        try {
            $resolved = Resolve-ModrinthMod -Mod $m
            $mb = [math]::Round($resolved.Size / 1MB, 1)
            Write-Ok "($mi/$modCount) $($resolved.Name) $($resolved.RequestedVersion) -> $($resolved.VersionNumber) [$($resolved.FileName), $mb MB]"
            $resolvedMods += $resolved
        } catch {
            throw "Mod '$($m.name)' ($($m.slug)): $($_.Exception.Message)"
        }
    }
    $targetFileNames = @($resolvedMods | ForEach-Object FileName)

    # ----------------------------------------------------------- 8) Backup
    Write-StepTitle 'Schritt 8/10: Alte Mods in datiertes Backup verschieben'
    $backupDir = New-ModsBackup -ModsDir $modsDir -KeepFileNames $targetFileNames

    # ------------------------------------------------------ 9) Mods herunterladen
    Write-StepTitle 'Schritt 9/10: Mods herunterladen und verifizieren'
    if ($resolvedMods.Count -eq 0) { throw 'Keine Mods in der Konfiguration vorhanden.' }
    $di = 0
    foreach ($r in $resolvedMods) {
        $di++
        $dest = Join-Path $modsDir $r.FileName
        if ((Test-Path $dest) -and (-not $script:Force)) {
            $existingHash = Get-Sha1 $dest
            if ($existingHash -eq $r.Sha1.ToLowerInvariant()) {
                Write-Ok "($di/$($resolvedMods.Count)) $($r.Name) ist bereits korrekt installiert."
                continue
            }
            Write-Warn "($di/$($resolvedMods.Count)) $($r.Name): vorhandene Datei ungültig - lade neu."
            Remove-Item $dest -Force
        }
        if ($script:DryRun) {
            Write-Info "DryRun: Download übersprungen -> $($r.FileName)"
            continue
        }
        Invoke-FileDownload -Url $r.Url -OutFile $dest -Label $r.Name -ExpectedSize $r.Size
        $hash = Get-Sha1 $dest
        if ($hash -ne $r.Sha1.ToLowerInvariant()) {
            Remove-Item $dest -Force -ErrorAction SilentlyContinue
            throw "SHA1-Prüfung fehlgeschlagen für $($r.FileName) (erwartet: $($r.Sha1))."
        }
        Write-Ok "($di/$($resolvedMods.Count)) $($r.Name) installiert und verifiziert."
    }

    # ------------------------------------------------------------- 10) Fertig
    Write-StepTitle 'Schritt 10/10: Abschluss'
    Write-Ok 'Installation abgeschlossen.'
    Write-Info "Minecraft       : 1.20.1 (Vanilla-Dateien lädt der Launcher beim ersten Start)"
    Write-Info "Fabric Loader   : $loaderVer (Profil: fabric-loader-$loaderVer-$mcVer)"
    Write-Info "Mods installiert: $($resolvedMods.Count)"
    if ($backupDir) {
        Write-Info "Backup-Ordner  : $backupDir"
    } else {
        Write-Info 'Backup-Ordner  : (kein Backup nötig)'
    }
    Write-Host ''
    Write-Host '  Nächste Schritte:' -ForegroundColor Cyan
    Write-Host '   1. Öffne den offiziellen Minecraft-Launcher.' -ForegroundColor Gray
    Write-Host "   2. Wähle beim Play-Button das Profil 'fabric-loader-$loaderVer-$mcVer'." -ForegroundColor Gray
    Write-Host '   3. Starte das Spiel - Vanilla 1.20.1 und Mods werden geladen.' -ForegroundColor Gray
    Write-Host ''
    Set-ScriptExit 0
} catch {
    Write-Host ''
    Write-Err $_.Exception.Message
    Write-Err 'Installation abgebrochen. Der vorherige Zustand ist weitgehend erhalten;'
    Write-Err 'bereits geladene Mods außerhalb des Backups wurden nicht gelöscht.'
    Set-ScriptExit 1
}