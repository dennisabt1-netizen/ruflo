#!/usr/bin/env bash
# ==============================================================================
#  ruflo-setup.sh — Vollautomatisches Ruflo-Setup (Agent-Harness für Claude Code)
# ==============================================================================
#  Erledigt:
#    1. Preflight  : Node >= 20, npm, Schreibrechte
#    2. Install    : ruflo global via npm
#    3. Init       : Projekt-Scaffold (.claude/, .claude-flow/, .agents/, MCP)
#    4. Runtime    : Daemon + Swarm starten
#    5. MCP        : Registrierung mit globalem Binary (NICHT npx -> Timeout-Bug)
#    6. Verify     : Health-Checks, Exit-Code != 0 bei Fehler
#
#  Benutzung:
#    chmod +x ruflo-setup.sh
#    ./ruflo-setup.sh                    # aktuelles Verzeichnis
#    ./ruflo-setup.sh ~/projekte/meinapp # Zielverzeichnis
#
#  Optionen (Umgebungsvariablen):
#    RUFLO_VERSION=3.38.12   Version pinnen (Default: latest)
#    SKIP_INSTALL=1          npm-Install überspringen (schon vorhanden)
#    SKIP_MCP=1              MCP-Registrierung überspringen
#    SKIP_SWARM=1            Daemon/Swarm nicht starten
#    ALL_SKILLS=1            alle 267 Plugin-Skills mitinstallieren
#    FORCE_REINIT=1          bestehendes Scaffold überschreiben
# ==============================================================================

set -Eeuo pipefail

# ---------- Konfiguration -----------------------------------------------------
RUFLO_VERSION="${RUFLO_VERSION:-latest}"
MCP_NAME="claude-flow"
MIN_NODE_MAJOR=20
TARGET_DIR="${1:-$PWD}"
LOG_FILE=""

# ---------- Ausgabe -----------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_BLU=$'\033[36m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""
fi

STEP_NO=0
step() { STEP_NO=$((STEP_NO + 1)); printf '\n%s[%d/6] %s%s\n' "$C_BOLD$C_BLU" "$STEP_NO" "$*" "$C_RESET"; }
ok()   { printf '  %s✓%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
info() { printf '  %s·%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YLW" "$C_RESET" "$*" >&2; }
fail() { printf '\n%s✗ FEHLER:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }

on_error() {
  local rc=$? line=${1:-?}
  printf '\n%s✗ Abbruch in Zeile %s (Exit %s)%s\n' "$C_RED$C_BOLD" "$line" "$rc" "$C_RESET" >&2
  [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]] && {
    printf '%sLetzte Log-Zeilen (%s):%s\n' "$C_DIM" "$LOG_FILE" "$C_RESET" >&2
    tail -n 20 "$LOG_FILE" >&2
  }
  exit "$rc"
}
trap 'on_error $LINENO' ERR

banner() {
  printf '%s' "$C_BOLD$C_BLU"
  cat <<'EOF'
  ___         _   _
 | _ \ _  _ _| |_| | ___
 |   /| || | |  _| |/ _ \    Ruflo Setup
 |_|_\ \_,_|_|\__|_|\___/    Agent-Harness für Claude Code / Codex
EOF
  printf '%s\n' "$C_RESET"
}

# ---------- 1. Preflight ------------------------------------------------------
preflight() {
  step "Preflight — Umgebung prüfen"

  command -v node >/dev/null 2>&1 || fail "Node.js nicht gefunden. Installiere Node >= ${MIN_NODE_MAJOR} (https://nodejs.org)."
  command -v npm  >/dev/null 2>&1 || fail "npm nicht gefunden."

  local node_ver node_major
  node_ver="$(node -v)"; node_major="${node_ver#v}"; node_major="${node_major%%.*}"
  [[ "$node_major" -ge "$MIN_NODE_MAJOR" ]] \
    || fail "Node ${node_ver} zu alt — benötigt >= v${MIN_NODE_MAJOR}."
  ok "Node ${node_ver} / npm $(npm -v)"

  mkdir -p "$TARGET_DIR" 2>/dev/null || fail "Zielverzeichnis nicht anlegbar: $TARGET_DIR"
  TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
  [[ -w "$TARGET_DIR" ]] || fail "Keine Schreibrechte in: $TARGET_DIR"
  ok "Zielverzeichnis: $TARGET_DIR"

  LOG_FILE="$TARGET_DIR/.ruflo-setup.log"
  : > "$LOG_FILE"
  info "Log: $LOG_FILE"

  # npm-Global-Prefix prüfen — Schreibrechte ohne sudo?
  local prefix
  prefix="$(npm config get prefix 2>/dev/null || echo "")"
  if [[ -n "$prefix" && -d "$prefix" && ! -w "$prefix" ]]; then
    warn "npm-Prefix '$prefix' ist nicht beschreibbar — Install braucht evtl. sudo."
    warn "Besser: 'npm config set prefix ~/.npm-global' + PATH anpassen."
  fi

  command -v claude >/dev/null 2>&1 \
    && ok "Claude Code CLI gefunden" \
    || warn "Claude Code CLI nicht gefunden — Schritt 5 (MCP) wird übersprungen."
}

# ---------- 2. Install --------------------------------------------------------
install_ruflo() {
  step "Install — ruflo global"

  if [[ "${SKIP_INSTALL:-0}" == "1" ]] && command -v ruflo >/dev/null 2>&1; then
    ok "übersprungen (SKIP_INSTALL=1) — vorhanden: $(ruflo --version 2>/dev/null | tail -1)"
    return 0
  fi

  info "npm install -g ruflo@${RUFLO_VERSION}  (3–6 Min, native Builds)"
  if ! npm install -g "ruflo@${RUFLO_VERSION}" >>"$LOG_FILE" 2>&1; then
    warn "Install fehlgeschlagen — Retry mit --no-audit --no-fund"
    npm install -g "ruflo@${RUFLO_VERSION}" --no-audit --no-fund >>"$LOG_FILE" 2>&1 \
      || fail "npm-Install fehlgeschlagen. Details: $LOG_FILE"
  fi

  hash -r 2>/dev/null || true
  command -v ruflo >/dev/null 2>&1 \
    || fail "'ruflo' nicht im PATH. Prüfe: npm bin -g  →  PATH ergänzen."
  ok "$(ruflo --version 2>/dev/null | tail -1) → $(command -v ruflo)"
}

# ---------- 3. Init -----------------------------------------------------------
init_project() {
  step "Init — Projekt-Scaffold"
  cd "$TARGET_DIR"

  if [[ -f "CLAUDE.md" && -d ".claude" && "${FORCE_REINIT:-0}" != "1" ]]; then
    ok "Scaffold existiert bereits — Init übersprungen (FORCE_REINIT=1 zum Überschreiben)"
    return 0
  fi

  local args=(init --force)
  [[ "${ALL_SKILLS:-0}" == "1" ]] || args+=(--no-skills-sh)

  info "ruflo ${args[*]}"
  ruflo "${args[@]}" >>"$LOG_FILE" 2>&1 || fail "ruflo init fehlgeschlagen. Details: $LOG_FILE"

  local missing=()
  for p in CLAUDE.md .claude .claude-flow .mcp.json; do
    [[ -e "$p" ]] || missing+=("$p")
  done
  [[ ${#missing[@]} -eq 0 ]] || fail "Scaffold unvollständig, fehlt: ${missing[*]}"

  ok "Scaffold erstellt: CLAUDE.md, .claude/, .claude-flow/, .mcp.json"
  info "Skills: $(find .claude/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ') · Commands: $(find .claude/commands -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ') · Agents: $(find .claude/agents -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "${ALL_SKILLS:-0}" == "1" ]]; then
    info "Installiere alle Plugin-Skills (npx skills add ruvnet/ruflo --all)"
    npx -y skills add ruvnet/ruflo --all >>"$LOG_FILE" 2>&1 \
      && ok "Plugin-Skills installiert" \
      || warn "Plugin-Skills fehlgeschlagen (nicht kritisch) — siehe Log"
  fi
}

# ---------- 4. Runtime --------------------------------------------------------
start_runtime() {
  step "Runtime — Daemon + Swarm"

  if [[ "${SKIP_SWARM:-0}" == "1" ]]; then
    ok "übersprungen (SKIP_SWARM=1)"
    return 0
  fi
  cd "$TARGET_DIR"

  if ruflo daemon start >>"$LOG_FILE" 2>&1; then
    ok "Daemon gestartet"
  else
    grep -qi "already running" "$LOG_FILE" \
      && ok "Daemon läuft bereits" \
      || warn "Daemon-Start unklar — siehe Log"
  fi

  ruflo swarm init >>"$LOG_FILE" 2>&1 \
    && ok "Swarm initialisiert ($(grep -o 'swarm-[0-9a-z-]*' "$LOG_FILE" | tail -1))" \
    || warn "Swarm-Init fehlgeschlagen — siehe Log"
}

# ---------- 5. MCP ------------------------------------------------------------
# WICHTIG: 'npx ruflo@latest mcp start' scheitert am MCP-Health-Check
# (Registry-Lookup + Download läuft in den Timeout). Immer das globale Binary.
register_mcp() {
  step "MCP — Server bei Claude Code registrieren"

  if [[ "${SKIP_MCP:-0}" == "1" ]]; then ok "übersprungen (SKIP_MCP=1)"; return 0; fi
  command -v claude >/dev/null 2>&1 || { warn "Claude Code CLI fehlt — übersprungen"; return 0; }

  cd "$TARGET_DIR"
  local ruflo_bin; ruflo_bin="$(command -v ruflo)"

  # Alt-Registrierung entfernen (Scope MUSS mitgegeben werden, sonst Fehler)
  if claude mcp list 2>/dev/null | grep -q "^${MCP_NAME}:"; then
    info "Bestehende Registrierung entfernen"
    claude mcp remove "$MCP_NAME" -s local  >>"$LOG_FILE" 2>&1 || true
    claude mcp remove "$MCP_NAME" -s project >>"$LOG_FILE" 2>&1 || true
  fi

  info "claude mcp add ${MCP_NAME} -- ${ruflo_bin} mcp start"
  claude mcp add "$MCP_NAME" -- "$ruflo_bin" mcp start >>"$LOG_FILE" 2>&1 \
    || fail "MCP-Registrierung fehlgeschlagen. Details: $LOG_FILE"
  ok "MCP-Server registriert (globales Binary, kein npx)"
}

# ---------- 6. Verify ---------------------------------------------------------
verify() {
  step "Verify — Health-Checks"
  cd "$TARGET_DIR"
  local rc=0

  # Hinweis: 'ruflo status' meldet fälschlich STOPPED (liest anderen State-Store).
  # Verlässlich ist 'ruflo daemon status'.
  if [[ "${SKIP_SWARM:-0}" != "1" ]]; then
    local dstat; dstat="$(ruflo daemon status 2>&1 || true)"
    local workers; workers="$(printf '%s' "$dstat" | grep -cE '\|[[:space:]]*(idle|running)[[:space:]]*\|' || true)"
    if [[ "${workers:-0}" -gt 0 ]]; then
      ok "Daemon aktiv — ${workers} Worker bereit"
    else
      warn "Keine aktiven Worker erkannt (prüfe: ruflo daemon status)"; rc=1
    fi
  fi

  if [[ "${SKIP_MCP:-0}" != "1" ]] && command -v claude >/dev/null 2>&1; then
    info "MCP-Health-Check (kann ~30s dauern)"
    local mstat; mstat="$(claude mcp list 2>&1 || true)"
    if printf '%s' "$mstat" | grep -q "${MCP_NAME}.*Connected"; then
      ok "MCP: ${MCP_NAME} → Connected"
    else
      warn "MCP nicht verbunden:"; printf '%s\n' "$mstat" | sed 's/^/      /' >&2; rc=1
    fi
  fi

  [[ -f "$TARGET_DIR/CLAUDE.md" ]] && ok "CLAUDE.md vorhanden" || { warn "CLAUDE.md fehlt"; rc=1; }
  return "$rc"
}

# ---------- Summary -----------------------------------------------------------
summary() {
  local rc="$1"
  printf '\n%s%s%s\n' "$C_BOLD" "────────────────────────────────────────────────────────" "$C_RESET"
  if [[ "$rc" -eq 0 ]]; then
    printf '%s✓ Ruflo-Setup abgeschlossen%s\n' "$C_GRN$C_BOLD" "$C_RESET"
  else
    printf '%s! Setup mit Warnungen abgeschlossen%s\n' "$C_YLW$C_BOLD" "$C_RESET"
  fi
  cat <<EOF

  Projekt : $TARGET_DIR
  Log     : $LOG_FILE

  Nächste Schritte:
    cd "$TARGET_DIR"
    claude                      # Claude Code starten — Hooks routen automatisch
    ruflo daemon status         # Worker-Übersicht (NICHT 'ruflo status')
    ruflo metaharness score     # Readiness-Scorecard
    ruflo daemon stop           # Background-Worker beenden

  Bekannte Eigenheiten:
    · 'ruflo status' zeigt fälschlich STOPPED → 'ruflo daemon status' nutzen
    · MCP nie via 'npx ruflo@latest' registrieren → Health-Check-Timeout
    · 'claude mcp remove' braucht immer '-s local' oder '-s project'
EOF
  printf '%s%s%s\n' "$C_BOLD" "────────────────────────────────────────────────────────" "$C_RESET"
}

# ---------- Main --------------------------------------------------------------
main() {
  banner
  preflight
  install_ruflo
  init_project
  start_runtime
  register_mcp

  set +e; verify; local vrc=$?; set -e
  summary "$vrc"
  exit "$vrc"
}

main "$@"
