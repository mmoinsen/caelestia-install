#!/usr/bin/env bash
# caelestia-install.sh
# Vollständiges Arch install script (rEFInd, Nightshift (redshift/gammastep), Gaming (Steam+Proton-GE), greetd/tuigreet, etc.)
# --- Hinweise: Script NICHT als root ausführen. Starte es als normaler Benutzer mit sudo-Rechten. ---

set -euo pipefail
IFS=$'\n\t'

# -------------------------
# Defaults / Optionen
# -------------------------
REPO="https://github.com/caelestia-dots/caelestia.git"
DEST="${HOME}/.local/share/caelestia"

# Option flags (initialisiert)
USE_PARU=0
AUR_HELPER=""
OPT_SPOTIFY=0
OPT_VSCODE=""        # "codium" | "code" | ""
OPT_DISCORD=0
OPT_ZEN=0
OPT_NOCONFIRM=0
OPT_NVIDIA=0
OPT_TUIGREET=1
OPT_NIGHTSHIFT="redshift"   # redshift | gammastep | none
OPT_GAMING=0
OPT_REFIND=0

# pacman options -- wird nach Parsing gesetzt
PACMAN_OPTS="-S --needed"

# -------------------------
# Hilfsfunktionen
# -------------------------
print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  --noconfirm                 don't prompt pacman / AUR confirmations
  --spotify                   install Spotify + Spicetify
  --discord                   install OpenAsar / Equicord (AUR)
  --zen                       install Zen browser configs
  --paru                      use paru as AUR helper (will install paru)
  --nvidia                    install NVIDIA drivers & attempt to set kernel param for rEFInd/GRUB
  --no-tuigreet               skip tuigreet/greetd config
  --nightshift=redshift|gammastep|none
                              choose nightshift tool (default: redshift)
  --gaming                    install Steam + Vulkan + lib32 + Proton-GE (AUR)
  --refind                    force rEFInd handling for kernel param (auto-detect otherwise)
  --vscode=codium|code        install vscodium (codium) or vscode (code)
  -h, --help                  show this help
EOF
}

die() { echo "ERROR: $*"; exit 1; }

check_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    die "Bitte Script **nicht** als root ausführen. Starte es als normaler Benutzer mit sudo-Rechten."
  fi
}

build_pacman_opts() {
  PACMAN_OPTS="-S --needed"
  if [ "${OPT_NOCONFIRM}" -eq 1 ]; then
    PACMAN_OPTS="$PACMAN_OPTS --noconfirm"
  fi
}

# -------------------------
# Robustes Argument-Parsing
# -------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --noconfirm)
      OPT_NOCONFIRM=1
      shift
      ;;
    --spotify)
      OPT_SPOTIFY=1
      shift
      ;;
    --discord)
      OPT_DISCORD=1
      shift
      ;;
    --zen)
      OPT_ZEN=1
      shift
      ;;
    --paru)
      USE_PARU=1
      shift
      ;;
    --nvidia)
      OPT_NVIDIA=1
      shift
      ;;
    --no-tuigreet)
      OPT_TUIGREET=0
      shift
      ;;
    --gaming)
      OPT_GAMING=1
      shift
      ;;
    --refind)
      OPT_REFIND=1
      shift
      ;;
    --nightshift=*)
      OPT_NIGHTSHIFT="${1#*=}"
      shift
      ;;
    --vscode=*)
      OPT_VSCODE="${1#*=}"
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    --) # stop parsing
      shift
      break
      ;;
    *)
      die "Unknown option: $1. Use --help to list options."
      ;;
  esac
done

# Build pacman options after parsing
build_pacman_opts

# -------------------------
# Funktionalität (module)
# -------------------------
check_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo wird benötigt. Bitte installiere sudo und füge deinen Benutzer zu sudoers hinzu."
  fi
}

install_basic_packages() {
  echo "==> Installing base packages..."
  local PKGS=(
    git base-devel fish jq curl wget unzip
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    hyprpicker hypridle wl-clipboard cliphist wireplumber
    trash-cli foot fastfetch starship btop imagemagick
    bluez bluez-utils NetworkManager
    pipewire pipewire-alsa pipewire-pulse pipewire-jack
    xdg-utils dbus greetd
  )
  sudo pacman -Syu $PACMAN_OPTS "${PKGS[@]}"
}

install_aur_helper() {
  if [ "$USE_PARU" -eq 1 ]; then
    if command -v paru >/dev/null 2>&1; then
      AUR_HELPER="paru"
    else
      echo "==> Installing paru..."
      sudo pacman -S $PACMAN_OPTS git base-devel
      tmpd=$(mktemp -d)
      git clone https://aur.archlinux.org/paru.git "$tmpd"
      pushd "$tmpd" >/dev/null
      makepkg -si --noconfirm
      popd >/dev/null
      rm -rf "$tmpd"
      AUR_HELPER="paru"
    fi
  else
    if command -v paru >/dev/null 2>&1; then
      AUR_HELPER="paru"
    elif command -v yay >/dev/null 2>&1; then
      AUR_HELPER="yay"
    else
      AUR_HELPER=""
    fi
  fi
  echo "AUR helper: ${AUR_HELPER:-none}"
}

install_aur_packages() {
  if [ -z "$AUR_HELPER" ]; then
    echo "Kein AUR-Helper vorhanden — AUR-Pakete werden übersprungen. (Setze --paru um paru zu installieren.)"
    return
  fi

  local AUR_PKGS=()
  if [ "$OPT_DISCORD" -eq 1 ]; then
    # Paketnamen in AUR können variieren; überprüfe ggf. lokal
    AUR_PKGS+=(openasar-bin equicord)
  fi
  if [ "$OPT_SPOTIFY" -eq 1 ]; then
    AUR_PKGS+=(spicetify-cli)
  fi
  if [ "$OPT_VSCODE" = "codium" ]; then
    AUR_PKGS+=(vscodium-bin)
  fi
  if [ "$OPT_NVIDIA" -eq 1 ]; then
    AUR_PKGS+=(hyprland-nvidia)
  fi
  if [ "$OPT_GAMING" -eq 1 ]; then
    AUR_PKGS+=(proton-ge-custom-bin)
  fi

  if [ "${#AUR_PKGS[@]}" -gt 0 ]; then
    echo "==> Installing AUR packages: ${AUR_PKGS[*]}"
    # Use AUR helper without sudo (helpers call sudo as needed)
    $AUR_HELPER -S --needed "${AUR_PKGS[@]}" ${OPT_NOCONFIRM:+--noconfirm}
  fi
}

detect_refind() {
  [ -f /boot/refind_linux.conf ] || [ -d /boot/EFI/refind ] && return 0
  return 1
}

patch_refind_kernel_param() {
  if [ -f /boot/refind_linux.conf ]; then
    sudo cp /boot/refind_linux.conf /boot/refind_linux.conf.bak || true
    echo "==> Patching /boot/refind_linux.conf (adding nvidia-drm.modeset=1 where missing)..."
    sudo awk '{
      if ($0 ~ /^#/ || $0 ~ /^$/) { print $0; next }
      if (index($0,"nvidia-drm.modeset=1") == 0) print $0 " nvidia-drm.modeset=1"; else print $0
    }' /boot/refind_linux.conf | sudo tee /boot/refind_linux.conf >/dev/null
    echo "Backup saved to /boot/refind_linux.conf.bak"
  else
    echo "Keine /boot/refind_linux.conf gefunden — bitte manuell prüfen (rEFInd evtl. an anderem Ort)."
  fi
}

configure_nvidia_refind() {
  echo "==> Installing NVIDIA drivers..."
  sudo pacman -S $PACMAN_OPTS nvidia nvidia-utils nvidia-settings lib32-nvidia-utils

  if [ "$OPT_REFIND" -eq 1 ] || detect_refind; then
    patch_refind_kernel_param
    echo "Bitte neu starten, damit Kernel-Parameter wirksam werden."
  elif [ -f /etc/default/grub ]; then
    echo "rEFInd nicht erkannt, fallback: patch GRUB"
    if ! grep -q "nvidia-drm.modeset=1" /etc/default/grub; then
      sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&nvidia-drm.modeset=1 /' /etc/default/grub || true
      if command -v grub-mkconfig >/dev/null 2>&1; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg || true
      fi
      echo "GRUB angepasst (falls vorhanden). Bitte neu starten."
    fi
  else
    echo "Weder rEFInd noch GRUB automatisch erkannt — füge 'nvidia-drm.modeset=1' manuell in deinem Bootloader ein."
  fi
}

enable_multilib_if_missing() {
  if ! grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null; then
    echo "==> Enabling [multilib] in /etc/pacman.conf ..."
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak || true
    sudo sed -i '/#\[multilib\]/,/#Include/{ s/^#// }' /etc/pacman.conf || true
    sudo pacman -Syu $PACMAN_OPTS
  else
    echo "[multilib] already enabled"
  fi
}

install_gaming_stack() {
  echo "==> Installing gaming stack (Steam, Vulkan, lib32, Mangohud, Gamescope, Lutris)..."
  enable_multilib_if_missing
  sudo pacman -S $PACMAN_OPTS steam vulkan-icd-loader lib32-vulkan-icd-loader lib32-nvidia-utils mangohud gamescope lutris
}

setup_repo_and_run_installfish() {
  echo "==> Cloning caelestia repo to $DEST ..."
  if [ -d "$DEST" ]; then
    git -C "$DEST" pull --ff-only || true
  else
    git clone "$REPO" "$DEST"
  fi

  if ! command -v fish >/dev/null 2>&1; then
    echo "fish not installed, installing..."
    sudo pacman -S $PACMAN_OPTS fish
  fi

  FISH_CMD="$DEST/install.fish"
  if [ ! -f "$FISH_CMD" ]; then
    die "install.fish not found in repo ($FISH_CMD). Abbruch."
  fi

  # Build fish flags consistent with user's chosen options
  local FISH_OPTS=()
  [ "$OPT_NOCONFIRM" -eq 1 ] && FISH_OPTS+=("--noconfirm")
  [ "$OPT_SPOTIFY" -eq 1 ] && FISH_OPTS+=("--spotify")
  [ "$OPT_DISCORD" -eq 1 ] && FISH_OPTS+=("--discord")
  [ "$OPT_ZEN" -eq 1 ] && FISH_OPTS+=("--zen")
  [ -n "$OPT_VSCODE" ] && FISH_OPTS+=("--vscode=$OPT_VSCODE")
  [ "$USE_PARU" -eq 1 ] && FISH_OPTS+=("--paru")

  echo "==> Running upstream install.fish with flags: ${FISH_OPTS[*]:-none}"
  fish "$FISH_CMD" "${FISH_OPTS[@]}"
}

setup_greetd_tuigreet() {
  if [ "$OPT_TUIGREET" -eq 0 ]; then
    echo "Tuigreet/Greetd installation skipped."
    return
  fi
  echo "==> Installing/configuring greetd + tuigreet..."
  sudo pacman -S $PACMAN_OPTS greetd-tuigreet || true

  # wrapper to start hyprland for logged-in user
  WRAPPER="/usr/local/bin/caelestia-start-hyprland"
  sudo tee "$WRAPPER" >/dev/null <<'EOF'
#!/usr/bin/env bash
exec Hyprland
EOF
  sudo chmod +x "$WRAPPER"

  # backup & write config
  if [ -f /etc/greetd/config.toml ]; then
    sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak || true
  fi

  sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[default]
command = ["/usr/bin/tuigreet", "--cmd", "/usr/local/bin/caelestia-start-hyprland"]
terminal = false
user = "greeter"
timeout = 0
EOF

  sudo systemctl enable --now greetd.service || sudo systemctl restart greetd.service || true
}

install_nightshift() {
  case "$OPT_NIGHTSHIFT" in
    redshift)
      echo "==> Installing Redshift and enabling systemd-user service..."
      sudo pacman -S $PACMAN_OPTS redshift || true
      mkdir -p "${HOME}/.config/systemd/user"
      mkdir -p "${HOME}/.config/redshift"
      cat > "${HOME}/.config/systemd/user/redshift.service" <<EOF
[Unit]
Description=Redshift (adjust screen color temperature)
After=graphical-session.target

[Service]
ExecStart=/usr/bin/redshift -l 0:0 -t 6500:3600
Restart=on-failure

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload || true
      systemctl --user enable --now redshift.service || true
      ;;
    gammastep)
      echo "==> Installing Gammastep and enabling systemd-user service..."
      sudo pacman -S $PACMAN_OPTS gammastep || true
      mkdir -p "${HOME}/.config/systemd/user"
      cat > "${HOME}/.config/systemd/user/gammastep.service" <<EOF
[Unit]
Description=Gammastep (adjust screen color temperature)
After=graphical-session.target

[Service]
ExecStart=/usr/bin/gammastep
Restart=on-failure

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload || true
      systemctl --user enable --now gammastep.service || true
      ;;
    none)
      echo "Nightshift disabled by user."
      ;;
    *)
      echo "Unknown nightshift option: $OPT_NIGHTSHIFT (supported: redshift|gammastep|none)"
      ;;
  esac
}

enable_services_for_widgets() {
  echo "==> Enabling services required for widgets (NetworkManager, bluetooth, pipewire/wireplumber)..."
  sudo systemctl enable --now NetworkManager.service
  sudo systemctl enable --now bluetooth.service || true
  sudo systemctl enable --now pipewire.service wireplumber.service || true
}

post_checks_and_notes() {
  cat <<EOF

==================== DONE ====================

• Repo installiert unter: $DEST (install.fish wurde ausgeführt).
• rEFInd/GRUB Kernel-Param 'nvidia-drm.modeset=1' wurde (wenn NVIDIA gewählt) versucht zu setzen; prüfe:
  /boot/refind_linux.conf.bak und /etc/default/grub.bak
• Nightshift: $OPT_NIGHTSHIFT (systemd-user Unit wurde erzeugt / aktiviert falls installiert).
• Gaming-Stack: $( [ "$OPT_GAMING" -eq 1 ] && echo "installiert (inkl. Proton-GE AUR falls AUR-Helper vorhanden)" || echo "nicht installiert").
• greetd/tuigreet konfiguriert (falls nicht deaktiviert).
• Services: NetworkManager, bluetooth, pipewire aktiviert.
• Wenn Probleme auftreten: prüfe journalctl, systemctl status und die Backups.

EOF
}

# -------------------------
# Main
# -------------------------
main() {
  check_not_root
  check_sudo
  install_basic_packages
  install_aur_helper

  if [ "$OPT_GAMING" -eq 1 ]; then
    install_gaming_stack
  fi

  if [ "$OPT_NVIDIA" -eq 1 ]; then
    configure_nvidia_refind
  fi

  # install AUR packages last (some base pkgs may be required)
  if [ -n "$AUR_HELPER" ] || [ "$OPT_DISCORD" -eq 1 ] || [ "$OPT_SPOTIFY" -eq 1 ] || [ "$OPT_GAMING" -eq 1 ]; then
    install_aur_packages
  fi

  setup_repo_and_run_installfish
  setup_greetd_tuigreet
  install_nightshift
  enable_services_for_widgets
  post_checks_and_notes
}

main "$@"
