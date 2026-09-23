# Minecraft 1.20.1 + Fabric Modpack Installer

Ein Windows-PowerShell-Installationssystem für einen **Minecraft-1.20.1-Client mit Fabric** und exakt versionierten Mods von **Modrinth**. Installiert wird ausschließlich **Fabric / 1.20.1**.

[🌐 GitHub Pages](https://92mxs21.github.io/fabric-1.20.1-modpack/) · [Modrinth](https://modrinth.com) · [Fabric](https://fabricmc.net)

---

## 🚀 Installation (einfachster Weg)

1. **`start-install.cmd` herunterladen** – Button „Schnellstart laden" auf der [Website](https://92mxs21.github.io/fabric-1.20.1-modpack/) oder direkt [start-install.cmd](start-install.cmd).
2. **Doppelklick** auf die Datei. Falls Windows nachfragt: *Weitere Informationen → Trotzdem ausführen*.
3. Das PowerShell-Fenster macht alles selbst: Java, Fabric-Profil, 7 Mods, Backup. Danach Launcher öffnen → Profil `fabric-loader-…` → spielen.

Der `start-install.cmd` lädt den Installer beim Start einmalig aus diesem Repo
(`irm … | iex` mit `-ExecutionPolicy Bypass`) – ohne manuelle Eingaben.

### Fortgeschritten: Einzeiler

Wer lieber direkt in PowerShell arbeitet (oder ohne Datei-Download):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/92mxs21/fabric-1.20.1-modpack/main/install.ps1 | iex"
```

Bereits in einem PowerShell-Fenster? Dann einfach:

```powershell
irm https://raw.githubusercontent.com/92mxs21/fabric-1.20.1-modpack/main/install.ps1 | iex
```

Das Script erkennt automatisch `%APPDATA%\.minecraft`, prüft/lädt Java, installiert das
Fabric-Profil (neuester Loader für 1.20.1) und legt anschließend die Mods in `mods/` an.
**Nicht benötigte, bereits vorhandene `.jar`-Mods** werden vorher in einen datierten
`<Zeitstempel>modbackup`-Ordner verschoben (z. B. `20260923-143000modbackup`).

Während der Downloads zeigt das Script live, **bei welcher Mod** es gerade steht: Prozent,
geladene/gesamte MB, MB/s und geschätzte Restzeit – plus Gesamtfortschritt (x/y Mods, MB).

## 📦 Was installiert wird

| Mod | Version | Datei (Fabric/1.20.1) | Bemerkung |
|---|---|---|---|
| Architectury | 9.2.14 | `architectury-9.2.14-fabric.jar` | Multi-Loader-API |
| Cloth Config | 11.1.136 | `cloth-config-11.1.136-fabric.jar` | Konfigurations-API |
| Dreamshift | 0.1.4.3.1 | `dreamshift-0.1.4.3.1-fabric.jar` | Speichern & Basis-Rückkehr |
| Fabric API | 0.92.12+1.20.1 | `fabric-api-0.92.12+1.20.1.jar` | Basis-API |
| Immersive Portals | 5.2.0 | `immersive-portals-5.2.0-mc1.20.1-fabric.jar` | Portale zwischen Dimensionen |
| Sodium | 0.5.13 | `sodium-fabric-0.5.13+mc1.20.1.jar` | Deutlich mehr FPS |
| Simple Voice Chat | 2.4.32 | `voicechat-fabric-1.20.1-2.4.32.jar` | Sprachchat im Spiel |

Die Datei-URLs **und** SHA1-Prüfsummen aller Mods sind in
[`config/modpack.json`](config/modpack.json) fest gepinnt. Dadurch fragt das Script für die
Mods **keine Modrinth-API ab** (schneller & robuster); nur wenn ein gepinnter Hash nicht zu
einer frisch heruntergeladenen Datei passt, wird einmalig die API als Fallback befragt.
Jeder Download wird per SHA1 geprüft.

## ⚙️ Nutzung des Scripts

| Befehl | Bedeutung |
|---|---|
| `.\install.ps1` | Normale Installation (erkanntes `.minecraft`) |
| `.\install.ps1 -MinecraftDir C:\pfad\zu\.minecraft` | Anderes Verzeichnis |
| `.\install.ps1 -ConfigPath meinpack.json` | Eigene Paket-Konfiguration |
| `.\install.ps1 -DryRun` | Nur Vorschau, verändert nichts |
| `.\install.ps1 -Force` | Erzwingt Neuinstallation (auch vorhandene Dateien) |

### Anforderungen

- Windows mit PowerShell 5.1+ (vorinstalliert)
- Der offizielle Minecraft-Launcher (hat `.minecraft` mindestens einmal angelegt)
- Java 17 fürs Spielen – falls kein Java gefunden wird, lädt das Script automatisch **Temurin JRE 17** herunter (nur für den Fabric Installer; der Launcher nutzt danach seinen eigenen Runtime)

### Wie es funktioniert

1. Konfiguration aus `config/modpack.json` laden
2. Minecraft-Verzeichnis bestimmen (`-MinecraftDir` oder `%APPDATA%\.minecraft`)
3. Java prüfen (Autodownload bei Bedarf)
4. Neuesten **Fabric Loader** für 1.20.1 von `meta.fabricmc.net` ermitteln (6h-Cache in `%LOCALAPPDATA%\fabric-modpack-tools`)
5. Offiziellen Fabric Installer (neueste Version) herunterladen
6. Profil per CLI installieren:
   `java -jar fabric-installer.jar client -mcversion 1.20.1 -loader <neueste> -dir <verzeichnis>`
7. Mod-Dateien aus der gepinnten Config lesen (kein API-Call, Fallback: Modrinth API)
8. Fremde `.jar`-Mods nach `<Zeitstempel>modbackup` (direkt neben `mods/`) verschieben
9. Mods herunterladen + SHA1-verifizieren (idempotent – korrekte Dateien werden übersprungen; Live-Fortschritt mit % / MB / MB/s / Restzeit)

## 🔧 Konfiguration (`config/modpack.json`)

```jsonc
{
  "minecraftVersion": "1.20.1",      // fest auf 1.20.1
  "loader": "fabric",                // nur Fabric
  "autoDownloadJava": true,          // Temurin JRE 17 bei Bedarf laden
  "versions": {                      // Anzeige-Versionen für die Website
    "minecraft": "1.20.1",
    "loader": "0.19.5",
    "installer": "1.1.2",
    "script": "1.2.0"
  },
  "mods": [
    {
      "name": "Sodium",
      "slug": "sodium",                    // Modrinth-Slug
      "version": "0.5.13",                 // gewünschte Version
      "modrinthVersion": "mc1.20.1-0.5.13-fabric", // exakte Modrinth-Versionsnummer
      "bemerkung": "Deutlich mehr FPS",    // kurzer Hinweis (Website/README)
      "file": "sodium-fabric-0.5.13+mc1.20.1.jar", // gepinnter Dateiname
      "size": 971552,                      // exakte Dateigröße in Bytes
      "sha1": "bcdbf37d…",                 // gepinnte SHA1-Prüfsumme
      "url": "https://cdn.modrinth.com/…"  // direkte Download-URL
    }
  ]
}
```

`file`/`size`/`sha1`/`url` sind optional: fehlen sie, fällt das Script auf die Modrinth-API
zurück (`loaders=fabric`, `game_versions=1.20.1`). `modrinthVersion` ist optional – ohne sie
sucht das Script anhand der normalisierten Versionsnummer (`mc1.20.1-0.5.13-fabric` → `0.5.13`).
Es wird immer nur die primäre `.jar`-Datei eines Fabric-/1.20.1-Releases installiert.

> **Encoding-Hinweis:** `install.ps1` **muss UTF-8 mit BOM** sein (Umlaute ä/ö/ü). Nicht als
> ANSI speichern – sonst ist die Ausgabe ein Buchstabensalat.

## 🏗️ Projektstruktur

```
├── install.ps1            # Hauptscript v1.2.0 (idempotent, Live-Fortschritt + Restzeit)
├── start-install.cmd      # Schnellstarter: Doppelklick -> lädt & startet install.ps1
├── index.html             # GitHub Pages Website (Dark Theme, Download-Buttons, Mod-Tabelle live)
├── style.css              # Website-Styling (dark, animierter Hintergrund, Fonts lokal)
├── assets/
│   ├── mc/                # Echte Mojang-Texturen aus dem 1.20.1-Client
│   └── fonts/             # VT323 + Press Start 2P (OFL) – lokal, kein CDN nötig
├── config/
│   └── modpack.json       # Versions-Pinning inkl. file/sha1/url
└── README.md
```

Die Website (Repo-Wurzel, GitHub Pages) liest die Mod-Liste **live aus
`config/modpack.json`** (gleiche Origin – kein CDN-Cache-Problem) und zeigt
Mod-Name, Pixel-Icon, Version und Bemerkung an. Es gibt **keine externen Requests**
(Fonts/CSS/JS liegen im Repo). Die Seite enthält bewusst **keinen
„kopiere & paste diesen PowerShell-Befehl“-Aufruf** – das liefert der Schnellstarter
(`start-install.cmd`) per Doppelklick, ohne dass Adblocker (uBlock Origin & Co.)
einen „ClickFix“-Schutz auslösen.

## ⚠️ Hinweis

Kein offizielles Mojang-, Microsoft- oder Fabric-Produkt. Minecraft ist eine Marke
von Mojang/Microsoft. Die Mods gehören ihren jeweiligen Autoren.