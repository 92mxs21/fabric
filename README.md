# Minecraft 1.20.1 + Fabric Modpack Installer

Ein Windows-PowerShell-Installationssystem für einen **Minecraft-1.20.1-Client mit Fabric** und exakt versionierten Mods von **Modrinth**. Installiert wird ausschließlich **Fabric / 1.20.1**.

[🌐 GitHub Pages](https://92mxs21.github.io/fabric-1.20.1-modpack/) · [Modrinth](https://modrinth.com) · [Fabric](https://fabricmc.net)

---

## 🚀 Installation in einem Einzeiler

In PowerShell **oder** in `cmd` einfügen:

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

Alle Versionen wurden gegen die **Modrinth API** verifiziert; jeder Download wird per
SHA1-Prüfsumme geprüft. Die Mod-Versionen sind in [`config/modpack.json`](config/modpack.json) fest gepinnt.

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
4. Neuesten **Fabric Loader** für 1.20.1 von `meta.fabricmc.net` ermitteln
5. Offiziellen Fabric Installer (neueste Version) herunterladen
6. Profil per CLI installieren:
   `java -jar fabric-installer.jar client -mcversion 1.20.1 -loader <neueste> -dir <verzeichnis>`
7. Mod-Infos von der Modrinth API abrufen (nur `loaders=fabric`, `game_versions=1.20.1`)
8. Fremde `.jar`-Mods nach `<Zeitstempel>modbackup` (direkt neben `mods/`) verschieben
9. Mods herunterladen + SHA1-verifizieren (idempotent – korrekte Dateien werden übersprungen)

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
    "script": "1.1.0"
  },
  "mods": [
    {
      "name": "Sodium",
      "slug": "sodium",              // Modrinth-Slug
      "version": "0.5.13",           // gewünschte Version
      "modrinthVersion": "mc1.20.1-0.5.13-fabric", // exakte Modrinth-Versionsnummer
      "bemerkung": "Deutlich mehr FPS"             // kurzer Hinweis (Website/README)
    }
  ]
}
```

`modrinthVersion` ist optional – ohne sie sucht das Script anhand der normalisierten
Versionsnummer (`mc1.20.1-0.5.13-fabric` → `0.5.13`). Es wird immer nur die primäre
`.jar`-Datei eines Fabric-/1.20.1-Releases installiert; Dateien anderer Loader oder
Minecraft-Versionen werden ignoriert.

## 🏗️ Projektstruktur

```
├── install.ps1            # Hauptscript (idempotent, mit Fortschrittsanzeige)
├── index.html             # GitHub Pages Website (One-Line-Befehl)
├── style.css              # Website-Styling (Minecraft-UI, echte Texturen)
├── assets/mc/             # Echte Mojang-Texturen aus dem 1.20.1-Client
├── config/
│   └── modpack.json       # Versions-Pinning der Mods
└── README.md
```

Die Website (Repot-Wurzel, GitHub Pages) liest die Mod-Liste **live aus
`config/modpack.json`** (gleiche Origin – kein CDN-Cache-Problem) und zeigt
Mod-Name, Item-Icon, Version und Bemerkung an.

## ⚠️ Hinweis

Kein offizielles Mojang-, Microsoft- oder Fabric-Produkt. Minecraft ist eine Marke
von Mojang/Microsoft. Die Mods gehören ihren jeweiligen Autoren.