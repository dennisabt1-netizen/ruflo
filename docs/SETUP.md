# ruflo-setup.sh

Vollautomatisches Setup für **Ruflo** — das Agent-Meta-Harness für Claude Code und Codex.

Ein Aufruf installiert Ruflo global, scaffoldet das Projekt, startet Daemon und Swarm, registriert den MCP-Server bei Claude Code und verifiziert alles per Health-Check.

```bash
chmod +x ruflo-setup.sh
./ruflo-setup.sh ~/projekte/meinapp
```

---

## Inhalt

- [Warum dieses Skript](#warum-dieses-skript)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Optionen](#optionen)
- [Was passiert in den 6 Schritten](#was-passiert-in-den-6-schritten)
- [Ergebnis im Projektverzeichnis](#ergebnis-im-projektverzeichnis)
- [Verifikation](#verifikation)
- [Bekannte Eigenheiten von Ruflo](#bekannte-eigenheiten-von-ruflo)
- [Troubleshooting](#troubleshooting)
- [Deinstallation](#deinstallation)
- [Exit-Codes](#exit-codes)
- [CI-Nutzung](#ci-nutzung)

---

## Warum dieses Skript

Die manuelle Installation aus der Ruflo-Doku funktioniert, hat aber drei Fallstricke, die jeweils in einem stillen oder irreführenden Fehler enden. Das Skript umgeht alle drei:

| Fallstrick | Auswirkung ohne Skript | Behandlung im Skript |
|---|---|---|
| MCP-Registrierung via `npx ruflo@latest` | `claude mcp list` zeigt dauerhaft **Failed to connect** — der Registry-Lookup läuft in den Health-Check-Timeout | Registriert den absoluten Pfad des global installierten Binaries |
| `claude mcp remove claude-flow` ohne Scope | Bricht mit `already exists` ab, Alt-Registrierung bleibt kaputt bestehen | Entfernt explizit aus `-s local` **und** `-s project` |
| `ruflo status` | Meldet `STOPPED` und Nullwerte, obwohl Daemon und Swarm laufen (liest einen anderen State-Store, `V3 Mode: Disabled`) | Verify nutzt `ruflo daemon status` und zählt echte Worker-Zeilen |

Zusätzlich: Node-Versionsprüfung vor jeder Änderung, Warnung bei nicht beschreibbarem npm-Prefix, Idempotenz (zweiter Lauf zerstört kein bestehendes Scaffold), `ERR`-Trap mit Zeilennummer und Log-Auszug.

---

## Voraussetzungen

| Komponente | Anforderung | Prüfung |
|---|---|---|
| Node.js | >= v20 | Hard-Fail im Preflight |
| npm | beliebig aktuell | Hard-Fail im Preflight |
| Claude Code CLI (`claude`) | optional | Fehlt sie, wird Schritt 5 (MCP) übersprungen, kein Abbruch |
| Shell | Bash 4+ (macOS, Linux, WSL, Git-Bash) | — |

Windows-Hinweis: Das Skript braucht eine POSIX-Shell. In nativem PowerShell oder cmd nutze stattdessen direkt `npx ruflo@latest init wizard`.

Beim npm-Global-Install kann sudo nötig sein, wenn `npm config get prefix` auf ein Systemverzeichnis wie `/usr/local` zeigt. Saubere Alternative ohne sudo:

```bash
npm config set prefix ~/.npm-global
export PATH="$HOME/.npm-global/bin:$PATH"   # dauerhaft in ~/.zshrc oder ~/.bashrc
```

---

## Installation

```bash
# Rechte setzen
chmod +x ruflo-setup.sh

# Variante A — aktuelles Verzeichnis als Projekt
./ruflo-setup.sh

# Variante B — Zielverzeichnis angeben (wird bei Bedarf erstellt)
./ruflo-setup.sh ~/projekte/meinapp
```

Laufzeit: rund 5 Minuten, davon der überwiegende Teil npm-Download und native Builds. Mit `SKIP_INSTALL=1` unter 60 Sekunden.

---

## Optionen

Alle Optionen werden als Umgebungsvariablen gesetzt.

| Variable | Wirkung |
|---|---|
| `RUFLO_VERSION=3.38.12` | Version pinnen statt `latest` — empfohlen für reproduzierbare Setups |
| `SKIP_INSTALL=1` | npm-Install überspringen, wenn `ruflo` bereits global vorhanden ist |
| `SKIP_MCP=1` | Keine Registrierung bei Claude Code |
| `SKIP_SWARM=1` | Daemon und Swarm nicht starten (nur Scaffold) |
| `ALL_SKILLS=1` | Zusätzlich alle 267 Plugin-Skills via `npx skills add ruvnet/ruflo --all` |
| `FORCE_REINIT=1` | Bestehendes Scaffold überschreiben (ohne diese Variable wird es geschützt) |

Beispiele:

```bash
SKIP_INSTALL=1 ./ruflo-setup.sh                       # Re-Setup eines Projekts
ALL_SKILLS=1 RUFLO_VERSION=3.38.12 ./ruflo-setup.sh   # volle Skill-Suite, gepinnt
SKIP_MCP=1 SKIP_SWARM=1 ./ruflo-setup.sh              # nur Dateien scaffolden
```

---

## Was passiert in den 6 Schritten

**1 · Preflight** — Node >= 20 und npm prüfen, Zielverzeichnis anlegen und auf Schreibrechte testen, Logdatei initialisieren, npm-Prefix auf Schreibbarkeit prüfen, Claude Code CLI erkennen. Bricht ab, bevor irgendetwas geändert wird.

**2 · Install** — `npm install -g ruflo@$RUFLO_VERSION`. Bei Fehlschlag automatischer Retry mit `--no-audit --no-fund`. Danach PATH-Cache leeren und Binary verifizieren.

**3 · Init** — `ruflo init --force` im Zielverzeichnis. Standardmäßig mit `--no-skills-sh` (schlanker); mit `ALL_SKILLS=1` inklusive Plugin-Skills. Anschließend Pflichtdateien gegenprüfen: `CLAUDE.md`, `.claude/`, `.claude-flow/`, `.mcp.json`.

**4 · Runtime** — `ruflo daemon start` (bereits laufender Daemon wird erkannt, kein Fehler) und `ruflo swarm init`. Die Swarm-ID wird aus dem Log extrahiert und ausgegeben.

**5 · MCP** — Alt-Registrierung scope-sauber entfernen, dann `claude mcp add claude-flow -- /pfad/zu/ruflo mcp start`. Bewusst mit absolutem Pfad statt `npx`.

**6 · Verify** — Worker aus `ruflo daemon status` zählen, `claude mcp list` auf `Connected` prüfen, `CLAUDE.md` bestätigen. Jeder fehlgeschlagene Check setzt den Exit-Code auf 1, ohne den Rest abzubrechen.

---

## Ergebnis im Projektverzeichnis

```
meinapp/
├── CLAUDE.md               # Swarm-Guidance und Konfiguration für Claude Code
├── .mcp.json               # MCP-Server-Definition (projektlokal)
├── .claude/
│   ├── settings.json       # 7 Hook-Typen aktiviert
│   ├── skills/             # 30 Skills
│   ├── commands/           # 148 Command-Definitionen
│   ├── agents/             # 18 Agent-Definitionen
│   └── helpers/
├── .claude-flow/
│   ├── config.yaml         # V3-Runtime-Konfiguration
│   ├── data/  logs/  sessions/
├── .agents/                # cross-agent Skill-Discovery
├── .swarm/
├── ruvector.db             # Vektor-Memory
└── .ruflo-setup.log        # vollständiges Setup-Log
```

Getestete Referenzwerte: 12 Verzeichnisse, 111 Dateien, 7 aktive Background-Worker (`map`, `audit`, `optimize`, `consolidate`, `testgaps`, `backup`, `harness`), Swarm-Topologie `hierarchical` mit max. 15 Agents.

---

## Verifikation

```bash
cd ~/projekte/meinapp

ruflo daemon status        # Worker-Tabelle — die verlässliche Statusquelle
claude mcp list            # muss "claude-flow: ... ✓ Connected" zeigen
ruflo metaharness score    # 5-dimensionale Readiness-Scorecard
```

Danach Claude Code im Projektverzeichnis starten. Die Hooks routen Tasks automatisch, Agents koordinieren sich im Hintergrund, Memory persistiert über Sessions hinweg. Ein Erlernen der MCP-Tools oder CLI-Commands ist nicht nötig.

Worker beenden:

```bash
ruflo daemon stop
```

---

## Bekannte Eigenheiten von Ruflo

- **`ruflo status` ist unzuverlässig.** Zeigt `RuFlo V3 [STOPPED]`, `Swarm not running` und Memory-Backend `none`, obwohl Daemon und Swarm laufen. Ursache: anderer State-Store bei `V3 Mode: Disabled`. Immer `ruflo daemon status` verwenden.
- **MCP nie über `npx` registrieren.** `npx ruflo@latest mcp start` als MCP-Command führt zu dauerhaftem `Failed to connect`.
- **`claude mcp remove` braucht immer einen Scope** (`-s local` oder `-s project`), sonst Abbruch mit `already exists`.
- **`latest` kann Verhalten ändern.** Bei einem Harness mit 7 automatisch laufenden Background-Workern ist ein gepinntes `RUFLO_VERSION` die sicherere Wahl.

---

## Troubleshooting

**`Node vXX zu alt — benötigt >= v20`**
Node aktualisieren, z. B. per `nvm install 20 && nvm use 20`.

**`'ruflo' nicht im PATH`**
`npm bin -g` ausgeben lassen und das Verzeichnis dem PATH hinzufügen. Oder Prefix umstellen wie unter [Voraussetzungen](#voraussetzungen) beschrieben.

**`npm-Prefix ... ist nicht beschreibbar`**
Nur eine Warnung. Entweder mit sudo installieren oder — besser — den Prefix auf `~/.npm-global` setzen.

**`MCP nicht verbunden`**
Prüfen, ob `claude mcp list` als Command tatsächlich einen absoluten Pfad statt `npx` zeigt. Falls nicht:
```bash
claude mcp remove claude-flow -s local
claude mcp add claude-flow -- "$(command -v ruflo)" mcp start
claude mcp list
```

**`Keine aktiven Worker erkannt`**
`ruflo daemon stop && ruflo daemon start`, dann erneut `ruflo daemon status`.

**`Scaffold unvollständig, fehlt: ...`**
`.ruflo-setup.log` im Projektverzeichnis lesen. Häufigste Ursache: abgebrochener npm-Install, hinterlässt ein unvollständiges Paket. Abhilfe: `npm cache clean --force`, dann Skript ohne `SKIP_INSTALL` erneut ausführen.

**Setup war unterbrochen, jetzt inkonsistent**
```bash
FORCE_REINIT=1 ./ruflo-setup.sh ~/projekte/meinapp
```

---

## Deinstallation

```bash
cd ~/projekte/meinapp
ruflo daemon stop
claude mcp remove claude-flow -s local

# Projekt-Artefakte entfernen
rm -rf .claude .claude-flow .agents .swarm
rm -f CLAUDE.md .mcp.json ruvector.db .ruflo-setup.log

# Global entfernen
npm uninstall -g ruflo
```

---

## Exit-Codes

| Code | Bedeutung |
|---|---|
| `0` | Alle Health-Checks grün |
| `1` | Setup durchgelaufen, mindestens ein Check mit Warnung |
| sonstige | Harter Abbruch — die `ERR`-Trap gibt Zeilennummer und die letzten 20 Log-Zeilen aus |

---

## CI-Nutzung

Das Skript ist non-interaktiv und CI-tauglich:

```yaml
- name: Ruflo Setup
  run: |
    chmod +x ruflo-setup.sh
    RUFLO_VERSION=3.38.12 SKIP_MCP=1 ./ruflo-setup.sh "$GITHUB_WORKSPACE"
```

`SKIP_MCP=1` ist in CI sinnvoll, weil dort keine Claude Code CLI vorhanden ist. Version immer pinnen für reproduzierbare Builds.

---

## Referenzen

- [Ruflo auf GitHub](https://github.com/ruvnet/ruflo) — Quellrepository und vollständige Doku
- [ruflo auf npm](https://www.npmjs.com/package/ruflo) — Paket und Versionshistorie
- [Ruflo UI Beta](https://flo.ruv.io/) — Web-Oberfläche
- Lizenz: MIT
