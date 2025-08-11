#!/usr/bin/env bash
# caelestia-arch-installer.sh
# Runs on a minimal Arch install. Must be run as a user with sudo privileges.
# This script clones https://github.com/caelestia-dots/caelestia and delegates config symlinking
# to the repo's own install.fish so configs remain exactly as upstream.

set -euo pipefail
IFS=$'\n\t'

REPO="https://github.com/caelestia-dots/caelestia.git"
DEST="${HOME}/.local/share/caelestia"
AUR_HELPER=""
USE_PARU=0
OPT_SPOTIFY=0
OPT_VSCODE=""   # "codium" or "code" or ""
OPT_DISCORD=0
OPT_ZEN=0
OPT_NOCONFIRM=0
OPT_NVIDIA=0
OPT_TUIGREET=1  # we will install/config by default (you can disable if undesired)

print_help() {
  cat <<EOF
Usage: $0 [options]
Options:
  --noconfirm           don't prompt for pacman/aur confirmations
  --spotify             install spotify + spicetify support
  --vscode=codium|code  install/configure VSCodium or VSCode
  --discord             install OpenAsar/Equicord workflow (AUR)
  --zen                 install Zen browser configs
  --paru                prefer paru as AUR helper (will install if missing)
  --nvidia              try to enable/install NVIDIA + hyprland-nvidia bits
  --no-tuigreet         don't install/configure tuigreet/greetd
  -h, --help            show this message
EOF
}

# parse args
for arg in "$@"; do
  case "$arg" in
    --noconfirm) OPT_NOCONFIRM=1 ;;
    --spotify) OPT_SPOTIFY=1 ;;
    --discord) OPT_DISCORD=1 ;;
    --zen) OPT_ZEN=1 ;;
    --paru) USE_PARU=1 ;;
    --nvidia) OPT_NVIDIA=1 ;;
    --no-tuigreet) OPT_TUIGREET=0 ;;
    --vscode=*) OPT_VSCODE="${arg#*=}" ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown option: $arg"; print_help; exit 1 ;;
  esac
done

PACMAN_OPTS="-S --needed"
if [ "$OPT_NOCONFIRM" -eq 1 ]; then PACMAN_OPTS="$PACMAN_OPTS --noconfirm"; fi

check_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Fehler: sudo wird benötigt. Bitte installiere sudo und füge deinen Benutzer zur sudoers Datei hinzu."
    exit 1
  fi
}

install_basic_packages() {
  echo "==> Installing base packages via pacman..."
  PKGS=(
    git base-devel fish jq curl wget unzip
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    hyprpicker hypridle wl-clipboard cliphist wireplumber
    trash-cli foot fastfetch starship btop imagemagick
    bluez bluez-utils networkmanager pipewire pipewire-alsa pipewire-pulse
    pipewire-jack xdg-utils dbus
  )

  # if not using official hyprland package for nvidia, we still install hyprland package above
  sudo pacman -Syu $PACMAN_OPTS "${PKGS[@]}"
}

install_aur_helper() {
  if [ "$USE_PARU" -eq 1 ]; then
    if command -v paru >/dev/null 2>&1; then
      AUR_HELPER="paru"
    else
      echo "==> Installing paru (AUR helper)..."
      sudo pacman -S $PACMAN_OPTS git base-devel
      tmpdir=$(mktemp -d)
      git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
      pushd "$tmpdir/paru" >/dev/null
      makepkg -si --noconfirm
      popd >/dev/null
      rm -rf "$tmpdir"
      AUR_HELPER="paru"
    fi
  else
    # prefer paru if present, else try yay
    if command -v paru >/dev/null 2>&1; then AUR_HELPER="paru"
    elif command -v yay >/dev/null 2>&1; then AUR_HELPER="yay"; fi
  fi
  echo "Using AUR helper: ${AUR_HELPER:-none}"
}

install_aur_packages() {
  if [ -z "$AUR_HELPER" ]; then
    echo "No AUR helper configured; skipping AUR installs. Set --paru or install yay/paru manually if you want AUR packages."
    return
  fi

  AUR_PKGS=()
  if [ "$OPT_DISCORD" -eq 1 ]; then
    # packages vary; this will try common AUR packages (may ask for confirmation)
    AUR_PKGS+=(discord discord-canary openasar-bin) # note: names vary between systems
  fi
  if [ "$OPT_SPOTIFY" -eq 1 ]; then
    AUR_PKGS+=(spicetify-cli)
  fi
  if [ -n "$OPT_VSCODE" ] && [ "$OPT_VSCODE" = "codium" ]; then
    AUR_PKGS+=(vscodium-bin)
  fi
  if [ "$OPT_NVIDIA" -eq 1 ]; then
    # hyprland-nvidia is often an AUR package; install if present
    AUR_PKGS+=(hyprland-nvidia)
    # some users use openasar, equicord, etc. Optional above
  fi

  if [ "${#AUR_PKGS[@]}" -gt 0 ]; then
    echo "==> Installing AUR packages: ${AUR_PKGS[*]}"
    sudo $AUR_HELPER -S --needed ${AUR_PKGS[*]} ${OPT_NOCONFIRM:+--noconfirm}
  fi
}

setup_repo_and_run_installfish() {
  echo "==> Cloning caelestia repo to $DEST ..."
  if [ -d "$DEST" ]; then
    echo "Repo already exists at $DEST — doing git pull"
    git -C "$DEST" pull --ff-only || true
  else
    git clone "$REPO" "$DEST"
  fi

  # ensure fish is available and script is executable
  if ! command -v fish >/dev/null 2>&1; then
    echo "Fish not found — installing fish..."
    sudo pacman -S $PACMAN_OPTS fish
  fi

  # Run upstream install.fish with equivalent options so configs are applied exactly as upstream
  FISH_CMD="$DEST/install.fish"
  if [ ! -f "$FISH_CMD" ]; then
    echo "Fehler: $FISH_CMD existiert nicht. Abbruch."
    exit 1
  fi

  # build flags for install.fish (match README options)
  FISH_OPTS=()
  [ "$OPT_NOCONFIRM" -eq 1 ] && FISH_OPTS+=("--noconfirm")
  [ "$OPT_SPOTIFY" -eq 1 ] && FISH_OPTS+=("--spotify")
  [ "$OPT_DISCORD" -eq 1 ] && FISH_OPTS+=("--discord")
  [ "$OPT_ZEN" -eq 1 ] && FISH_OPTS+=("--zen")
  if [ -n "$OPT_VSCODE" ]; then FISH_OPTS+=("--vscode=$OPT_VSCODE"); fi
  [ "$USE_PARU" -eq 1 ] && FISH_OPTS+=("--paru")

  echo "==> Running upstream install.fish with flags: ${FISH_OPTS[*]:-none}"
  # execute via fish so we don't reimplement symlink logic
  fish "$FISH_CMD" "${FISH_OPTS[@]}"
}

configure_nvidia() {
  echo "==> NVIDIA setup requested."
  echo "Installing official nvidia drivers (pacman) ..."
  sudo pacman -S $PACMAN_OPTS nvidia nvidia-utils nvidia-settings lib32-nvidia-utils

  # attempt to add nvidia drm modeset to GRUB config (only if grub present)
  if [ -f /etc/default/grub ]; then
    echo "Adding nvidia-drm.modeset=1 to /etc/default/grub (if not already present)..."
    if grep -q "nvidia-drm.modeset=1" /etc/default/grub; then
      echo "already present"
    else
      sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 nvidia-drm.modeset=1\"/" /etc/default/grub || true
      echo "Regenerating grub config..."
      if command -v grub-mkconfig >/dev/null 2>&1; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        echo "Bitte neu starten, damit der Kernel-Parameter aktiv wird."
      else
        echo "Warnung: grub-mkconfig nicht gefunden — du musst den Kernel-Parameter manuell setzen (oder dein Bootloader verwenden)."
      fi
    fi
  else
    echo "Kein /etc/default/grub gefunden — bitte füge den Kernel-Parameter 'nvidia-drm.modeset=1' für deinen Bootloader manuell hinzu (z. B. systemd-boot, rEFInd, etc.)."
  fi
  echo "Falls du hyprland-nvidia via AUR brauchst, wurde das (falls AUR helper gesetzt) oben versucht zu installieren."
  echo "Weitere Feinheiten (z. B. performance patches) sind möglich; siehe ArchWiki / Hyprland NVIDIA resources."
}

setup_greetd_tuigreet() {
  [ "$OPT_TUIGREET" -eq 1 ] || { echo "Tuigreet installation übersprungen."; return; }
  echo "==> Installing greetd + tuigreet..."
  sudo pacman -S $PACMAN_OPTS greetd greetd-tuigreet

  # create a simple wrapper script to start Hyprland as the logged in user
  WRAPPER="/usr/local/bin/caelestia-start-hyprland"
  echo "Creating wrapper $WRAPPER (needs sudo)"
  sudo tee "$WRAPPER" >/dev/null <<'EOF'
#!/usr/bin/env bash
# wrapper called by greetd/tuigreet to start a hyprland session
# NOTE: keep this environment minimal (greetd expects an env-less command),
# so we exec the user's hyprland. If you need environment variables (XDG...), create a small script in /usr/local/bin and make sure it can be called without fancy envs.
exec Hyprland
EOF
  sudo chmod +x "$WRAPPER"

  # create /etc/greetd/config.toml if not exists (backup existing)
  if [ -f /etc/greetd/config.toml ]; then
    sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak || true
  fi

  echo "Writing a minimal /etc/greetd/config.toml to use tuigreet"
  sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[default]
# run tuigreet; upon successful auth, it will run the wrapper above
command = ["/usr/bin/tuigreet", "--cmd", "/usr/local/bin/caelestia-start-hyprland"]
terminal = false
user = "greeter"
timeout = 0
EOF

  echo "Enabling greetd service..."
  sudo systemctl enable --now greetd.service || sudo systemctl restart greetd.service || true
  echo "tuigreet should now be used as greetd greeter. If you want autologin or special env vars, a wrapper or desktop file is required."
}

enable_services_for_widgets() {
  echo "==> Enabling network & bluetooth services to make widgets work (NetworkManager, bluetooth, pipewire/wireplumber)..."
  sudo systemctl enable --now NetworkManager.service
  sudo systemctl enable --now bluetooth.service || true
  sudo systemctl enable --now pipewire.service wireplumber.service || true
  echo "Wenn Probleme mit Widgets bestehen: prüfe 'systemctl status NetworkManager' und 'bluetoothctl' für pairing/debug."
}

post_checks_and_notes() {
  echo
  echo "===================="
  echo "FERTIG: Grobe Checks / Hinweise:"
  echo "- Repo wurde nach: $DEST geklont. Die upstream install.fish wurde ausgeführt, um die Configs EXAKT zu übernehmen."
  echo "- Falls du --nvidia benutzt hast: bitte neu starten, damit Kernel-Parameter wirksam werden."
  echo "- Wenn Bluetooth/Wi-Fi Widgets noch nicht korrekt arbeiten, prüfe:"
  echo "    systemctl status NetworkManager"
  echo "    systemctl status bluetooth"
  echo "    journalctl -b -u greetd --no-pager"
  echo "- Wenn du Secure Boot aktiviert hast und die proprietären NVIDIA-Module/Kernel-Module verwendest, kann Secure Boot die Treiber-Installation blockieren."
  echo "===================="
}

main() {
  check_sudo
  install_basic_packages
  install_aur_helper
  install_aur_packages
  configure_nvidia && true
  setup_repo_and_run_installfish
  setup_greetd_tuigreet
  enable_services_for_widgets
  post_checks_and_notes
}

main "$@"
