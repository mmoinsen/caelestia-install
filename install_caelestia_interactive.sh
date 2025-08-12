#!/usr/bin/env bash
# install-caelestia-interactive.sh
# Interaktives Install-Script für caelestia (Hyprland rice) auf minimalem Arch.
# - Installiert offizielle Pakete mit pacman (interaktiv)
# - Optional: installiert yay (AUR helper) wenn gewünscht
# - Optional: installiert AUR-Pakete mit yay (interaktiv)
# - Klont das Repo und führt install.fish (interaktiv) aus

set -euo pipefail
IFS=$'\n\t'

# --- Konfiguration ---
DEST_DIR="${HOME}/.local/share/caelestia"
REPO_URL="https://github.com/caelestia-dots/caelestia.git"
AUR_HELPER="yay"

# Offizielle Repo-Pakete (kann je nach README variieren) — passe bei Bedarf an
PKGS=(
  base-devel git
  hyprland
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  hyprpicker
  hypridle
  wl-clipboard
  cliphist
  bluez-utils
  inotify-tools
  wireplumber
  trash-cli
  foot
  fish
  fastfetch
  starship
  btop
  jq
  socat
  imagemagick
  curl
  adw-gtk-theme
  papirus-icon-theme
  qt5ct
  qt6ct
  ttf-jetbrains-mono-nerd
)

# AUR-Pakete (optional)
AUR_PKGS=(
  caelestia-meta
  app2unit-git
  caelestia-cli-git
  caelestia-shell-git
)

log() { echo -e "\033[1;34m==>\033[0m $*"; }
err() { echo -e "\033[1;31mERROR:\033[0m $*" >&2; }

ask_yes_no() {
  # Aufruf: ask_yes_no "Frage"
  while true; do
    read -rp "$1 [J/n]: " yn
    case "$yn" in
      ""|[Jj]*) return 0;;
      [Nn]*) return 1;;
      *) echo "Bitte J (ja) oder n (nein) eingeben.";;
    esac
  done
}

# Prüfe pacman
if ! command -v pacman >/dev/null 2>&1; then
  err "pacman nicht gefunden — dieses Skript ist für Arch/Arch-basierte Systeme gedacht."
  exit 1
fi

log "Dieses Skript führt interaktive Schritte aus. Du wirst zu Bestätigungen aufgefordert."

# --- NVIDIA-Treiber Unterstützung (interaktiv) ---
# Dieser Block erkennt eine NVIDIA-GPU (falls lspci verfügbar ist) und bietet an,
# proprietäre Treiber (nvidia / nvidia-dkms) oder den freien nouveau-Treiber zu installieren.
# Die ausgewählten Pakete werden zur PKGS-Liste hinzugefügt, bevor pacman sie installiert.
if command -v lspci >/dev/null 2>&1; then
  if lspci | grep -i 'nvidia' >/dev/null 2>&1; then
    log "NVIDIA-GPU erkannt."
    if ask_yes_no "Möchtest du die proprietären NVIDIA-Treiber installieren (empfohlen für Leistung)?"; then
      if ask_yes_no "Bevorzugst du nvidia-dkms (wiederaufgebaut bei Kernel-Updates) statt nvidia (kernel-spezifisch)?"; then
        NVIDIA_PKGS=(nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings)
        # linux-headers werden für DKMS benötigt; wir fügen das Kernel-Headers-Paket hinzu,
        # das mit dem aktuell installierten Kernel übereinstimmen sollte (z.B. linux-headers).
        NVIDIA_PKGS+=(linux-headers)
      else
        NVIDIA_PKGS=(nvidia nvidia-utils lib32-nvidia-utils nvidia-settings)
      fi
      log "Füge NVIDIA-Pakete zur Installationsliste hinzu: ${NVIDIA_PKGS[*]}"
      PKGS+=("${NVIDIA_PKGS[@]}")
    else
      if ask_yes_no "Möchtest du stattdessen den freien Nouveau-Treiber installieren?"; then
        log "Füge xf86-video-nouveau zur Installationsliste hinzu."
        PKGS+=(xf86-video-nouveau)
      else
        log "NVIDIA-Treiber werden übersprungen."
      fi
    fi
  else
    log "Keine NVIDIA-GPU gefunden (keine Treffer in lspci). Überspringe NVIDIA-spezifische Schritte."
  fi
else
  log "lspci nicht gefunden — automatische NVIDIA-Erkennung übersprungen. Wenn du NVIDIA-Treiber installieren möchtest, füge sie manuell zu PKGS hinzu."
fi

# 1) Systemupdate
if ask_yes_no "System aktualisieren (pacman -Syu)?"; then
  log "Systemupdate..."
  sudo pacman -Syu
else
  log "Systemupdate übersprungen."
fi

# 2) Offizielle Pakete installieren
echo
log "Die folgenden offiziellen Pakete würden installiert (pacman):"
echo "${PKGS[*]}"
if ask_yes_no "Offizielle Pakete jetzt installieren?"; then
  log "Pakete mit pacman installieren..."
  sudo pacman -S --needed "${PKGS[@]}"
else
  log "Installation offizieller Pakete übersprungen."
fi

# 3) AUR-Helper (yay) prüfen / installieren
if ! command -v "$AUR_HELPER" >/dev/null 2>&1; then
  if ask_yes_no "AUR-Helper '$AUR_HELPER' wurde nicht gefunden. Soll '$AUR_HELPER' (aus AUR) jetzt installiert werden?"; then
    log "Baue und installiere $AUR_HELPER (wird im Home des aktuellen Nutzers gebaut)..."
    TMPDIR=$(mktemp -d)
    pushd "$TMPDIR" >/dev/null
    git clone https://aur.archlinux.org/${AUR_HELPER}.git
    cd "$AUR_HELPER"
    echo
    echo "makepkg wird ausgeführt. Du wirst nach root-Rechten für Abhängigkeiten gefragt (sudo)."
    if ask_yes_no "Fortfahren und $AUR_HELPER bauen/installieren?"; then
      makepkg -si
    else
      err "Installation von $AUR_HELPER abgebrochen.";
      popd >/dev/null
      rm -rf "$TMPDIR"
      log "AUR-Schritt übersprungen. AUR-Pakete können nicht installiert werden, solange kein AUR-Helper vorhanden ist."
    fi
    popd >/dev/null
    rm -rf "$TMPDIR"
  else
    log "AUR-Installation übersprungen. Wenn du AUR-Pakete möchtest, installiere später einen AUR-Helper."
  fi
else
  log "AUR-Helper '$AUR_HELPER' ist bereits installiert."
fi

# 4) AUR-Pakete (optional)
if command -v "$AUR_HELPER" >/dev/null 2>&1; then
  echo
  log "Die folgenden AUR-Pakete wären verfügbar (optional):"
  echo "${AUR_PKGS[*]}"
  if ask_yes_no "AUR-Pakete jetzt mit $AUR_HELPER installieren?"; then
    log "Installiere AUR-Pakete mit $AUR_HELPER..."
    # yay ist interaktiv; --needed verhindert Neuinstallation
    $AUR_HELPER -S --needed "${AUR_PKGS[@]}"
  else
    log "AUR-Pakete übersprungen."
  fi
else
  log "Kein AUR-Helper vorhanden — AUR-Pakete werden übersprungen."
fi

# 5) Repo klonen
echo
if [[ -d "$DEST_DIR" ]]; then
  log "Zielordner $DEST_DIR existiert bereits."
  if ask_yes_no "Möchtest du den Ordner löschen und neu klonen (ACHTUNG: überschreibt Dateien)?"; then
    rm -rf "$DEST_DIR"
    log "Lösche $DEST_DIR ..."
    git clone "$REPO_URL" "$DEST_DIR"
  else
    log "Klone übersprungen. Verwende bestehenden Ordner."
  fi
else
  if ask_yes_no "Repo nach $DEST_DIR klonen?"; then
    git clone "$REPO_URL" "$DEST_DIR"
  else
    log "Klone übersprungen. Du kannst das Repo später manuell klonen."
  fi
fi

# 6) install.fish ausführen
INSTALL_SCRIPT="$DEST_DIR/install.fish"
if [[ -f "$INSTALL_SCRIPT" ]]; then
  echo
  log "Install-Script gefunden: $INSTALL_SCRIPT"
  if ask_yes_no "install.fish jetzt ausführen? (Empfehlung: als normaler Nutzer, nicht als root)"; then
    if ask_yes_no "install.fish als normaler Nutzer ausführen? (Wenn nein, wird sudo verwendet)"; then
      log "install.fish wird als $(whoami) ausgeführt..."
      /usr/bin/fish "$INSTALL_SCRIPT" || {
        err "install.fish ist fehlgeschlagen. Schau dir die Ausgabe an."; exit 1;
      }
    else
      log "install.fish wird mit sudo ausgeführt..."
      sudo /usr/bin/fish "$INSTALL_SCRIPT" || {
        err "install.fish (sudo) ist fehlgeschlagen. Schau dir die Ausgabe an."; exit 1;
      }
    fi
  else
    log "Ausführung von install.fish übersprungen."
  fi
else
  err "Install-Script $INSTALL_SCRIPT nicht gefunden. Stelle sicher, dass das Repo korrekt geklont wurde."
fi

log "Fertig. Hinweise:\n- Falls etwas fehlschlägt, kopiere die Fehlermeldung und sende sie mir; ich helfe beim Debuggen.\n- Du kannst dieses Script anpassen (Pakete in PKGS / AUR_PKGS).\n- Wenn du möchtest, mache ich dir auch eine nicht-interaktive Version mit yay und --noconfirm."
