#!/usr/bin/env bash
# caelestia-install.sh – vollständige Arch-Rice-Automatisierung inkl. rEFInd, Night-Shift, Gaming & Proton-GE
set -euo pipefail
IFS=$'\n\t'

REPO="https://github.com/caelestia-dots/caelestia.git"
DEST="${HOME}/.local/share/caelestia"

AUR_HELPER=""
USE_PARU=0
OPT_SPOTIFY=0
OPT_VSCODE=""
OPT_DISCORD=0
OPT_ZEN=0
OPT_NOCONFIRM=0
OPT_NVIDIA=0
OPT_TUIGREET=1
OPT_NIGHTSHIFT="redshift"    # options: redshift | gammastep | none
OPT_GAMING=0
OPT_REFIND=0

PACMAN_OPTS="-S --needed"
[ "$OPT_NOCONFIRM" -eq 1 ] && PACMAN_OPTS="$PACMAN_OPTS --noconfirm"

print_help(){
  cat <<EOF
Usage: $0 [options]
--noconfirm           no prompts
--spotify             Spotify + Spicetify
--discord             OpenAsar/Equicord
--zen                 Zen-Browser
--paru                use paru as AUR helper (installs if missing)
--nvidia              NVIDIA + Wayland (rEFInd or GRUB patch)
--refind              force rEFInd detection for kernel param patch
--nightshift=redshift|gammastep|none
                      Night-shift tool (default redshift, or disable with none)
--gaming              install Steam + Vulkan + Lutris + Proton-GE
--vscode=codium|code  VSCodium or VSCode
-h, --help            show help
EOF
}

# --- argument parsing ---
for arg in "$@"; do
  case "$arg" in
    --noconfirm) OPT_NOCONFIRM=1 ;;
    --spotify) OPT_SPOTIFY=1 ;;
    --discord) OPT_DISCORD=1 ;;
    --zen) OPT_ZEN=1 ;;
    --paru) USE_PARU=1 ;;
    --nvidia) OPT_NVIDIA=1 ;;
    --no-tuigreet) OPT_TUIGREET=0 ;;
    --gaming) OPT_GAMING=1 ;;
    --refind) OPT_REFIND=1 ;;
    --nightshift=*) OPT_NIGHTSHIFT="${arg#*=}" ;;
    --vscode=*) OPT_VSCODE="${arg#*=}" ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown option: $arg"; print_help; exit 1 ;;
  esac
done

# --- helper functions ---
check_sudo(){
  if ! command -v sudo >/dev/null; then
    echo "Error: sudo required."
    exit 1
  fi
}

install_basic_packages(){
  echo "==> Installing base packages..."
  PKGS=(
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

install_aur_helper(){
  if [ "$USE_PARU" -eq 1 ]; then
    if command -v paru >/dev/null; then AUR_HELPER="paru"
    else
      echo "==> Installing paru..."
      sudo pacman -S $PACMAN_OPTS git base-devel
      tmp=$(mktemp -d)
      git clone https://aur.archlinux.org/paru.git "$tmp"
      pushd "$tmp" >/dev/null
      makepkg -si --noconfirm
      popd >/dev/null
      rm -rf "$tmp"
      AUR_HELPER="paru"
    fi
  else
    if command -v paru >/dev/null; then AUR_HELPER="paru"
    elif command -v yay >/dev/null; then AUR_HELPER="yay"; fi
  fi
  echo "AUR helper: ${AUR_HELPER:-none}"
}

install_aur_packages(){
  [ -z "$AUR_HELPER" ] && { echo "Skipping AUR packages; no helper."; return; }
  AUR_PKGS=()
  [ "$OPT_DISCORD" -eq 1 ] && AUR_PKGS+=(openasar-bin equicord)
  [ "$OPT_SPOTIFY" -eq 1 ] && AUR_PKGS+=(spicetify-cli)
  [ "$OPT_VSCODE" = "codium" ] && AUR_PKGS+=(vscodium-bin)
  [ "$OPT_NVIDIA" -eq 1 ] && AUR_PKGS+=(hyprland-nvidia)
  [ "$OPT_GAMING" -eq 1 ] && AUR_PKGS+=(proton-ge-custom-bin)
  [ ${#AUR_PKGS[@]} -gt 0 ] && echo "==> Installing AUR: ${AUR_PKGS[*]}" && sudo $AUR_HELPER -S --needed "${AUR_PKGS[@]}" ${OPT_NOCONFIRM:+--noconfirm}
}

detect_refind(){
  [ -f /boot/refind_linux.conf ] || [ -d /boot/EFI/refind ] && return 0
  return 1
}

patch_refind_kernel_param(){
  sudo cp /boot/refind_linux.conf /boot/refind_linux.conf.bak || true
  echo "==> Patching refind_linux.conf..."
  sudo awk '{
    if ($0~/^#/ || $0~/^$/){ print; next }
    if (index($0,"nvidia-drm.modeset=1")==0) print $0 " nvidia-drm.modeset=1"; else print
  }' /boot/refind_linux.conf | sudo tee /boot/refind_linux.conf >/dev/null
  echo "Backup at /boot/refind_linux.conf.bak"
}

configure_nvidia_refind(){
  echo "==> Installing NVIDIA drivers..."
  sudo pacman -S $PACMAN_OPTS nvidia nvidia-utils nvidia-settings lib32-nvidia-utils
  if [ "$OPT_REFIND" -eq 1 ] || detect_refind; then
    patch_refind_kernel_param
    echo "Please reboot to apply rEFInd kernel parameters."
  elif [ -f /etc/default/grub ]; then
    echo "Fallback: patching GRUB..."
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&nvidia-drm.modeset=1 /' /etc/default/grub || true
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "Reboot to apply."
  else
    echo "No rEFInd or GRUB detected — manually add 'nvidia-drm.modeset=1'."
  fi
}

enable_multilib_if_missing(){
  if grep -Pzoq "^\[multilib\]\n#Include" /etc/pacman.conf || ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "==> Enabling [multilib]..."
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak || true
    sudo sed -i '/#\[multilib\]/,/#Include/{s/^#//}' /etc/pacman.conf
    sudo pacman -Syu $PACMAN_OPTS
  fi
}

install_gaming_stack(){
  enable_multilib_if_missing
  echo "==> Installing Gaming stack..."
  sudo pacman -S $PACMAN_OPTS steam vulkan-icd-loader lib32-vulkan-icd-loader lib32-nvidia-utils mangohud gamescope lutris
}

setup_repo_and_run_installfish(){
  echo "==> Cloning caelestia repo..."
  [ -d "$DEST" ] && git -C "$DEST" pull --ff-only || git clone "$REPO" "$DEST"
  [ -f "$DEST/install.fish" ] || { echo "install.fish missing"; exit 1; }
  FISH_OPTS=()
  [ "$OPT_NOCONFIRM" -eq 1 ] && FISH_OPTS+=("--noconfirm")
  [ "$OPT_SPOTIFY" -eq 1 ] && FISH_OPTS+=("--spotify")
  [ "$OPT_DISCORD" -eq 1 ] && FISH_OPTS+=("--discord")
  [ "$OPT_ZEN" -eq 1 ] && FISH_OPTS+=("--zen")
  [ "$OPT_VSCODE" ] && FISH_OPTS+=("--vscode=$OPT_VSCODE")
  [ "$USE_PARU" -eq 1 ] && FISH_OPTS+=("--paru")
  echo "==> Running upstream install.fish with flags: ${FISH_OPTS[*]:-none}"
  fish "$DEST/install.fish" "${FISH_OPTS[@]}"
}

setup_greetd_tuigreet(){
  [ "$OPT_TUIGREET" -eq 1 ] || return
  echo "==> Configuring greetd + tuigreet..."
  sudo pacman -S $PACMAN_OPTS greetd-tuigreet || true
  WRAPPER=/usr/local/bin/caelestia-start-hyprland
  sudo tee "$WRAPPER" >/dev/null <<EOF
#!/usr/bin/env bash
exec Hyprland
EOF
  sudo chmod +x "$WRAPPER"
  sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak || true
  sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[default]
command = ["/usr/bin/tuigreet", "--cmd", "/usr/local/bin/caelestia-start-hyprland"]
terminal = false
user = "greeter"
timeout = 0
EOF
  sudo systemctl enable --now greetd
}

install_nightshift(){
  case "$OPT_NIGHTSHIFT" in
    redshift)
      echo "==> Installing Redshift + systemd-user service..."
      sudo pacman -S $PACMAN_OPTS redshift
      mkdir -p "${HOME}/.config/systemd/user"
      cat > "${HOME}/.config/systemd/user/redshift.service" <<EOF
[Unit]
Description=Redshift (screen color temperature)

[Service]
ExecStart=/usr/bin/redshift -l 0:0 -t 6500:3600
Restart=on-failure

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload
      systemctl --user enable --now redshift.service
      ;;
    gammastep)
      echo "==> Installing Gammastep + systemd-user service..."
      sudo pacman -S $PACMAN_OPTS gammastep
      mkdir -p "${HOME}/.config/systemd/user"
      cat > "${HOME}/.config/systemd/user/gammastep.service" <<EOF
[Unit]
Description=Gammastep (screen color temperature)

[Service]
ExecStart=/usr/bin/gammastep
Restart=on-failure

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload
      systemctl --user enable --now gammastep.service
      ;;
    none)
      echo "No nightshift tool selected."
      ;;
    *)
      echo "Unknown nightshift option: $OPT_NIGHTSHIFT"
      ;;
  esac
}

enable_services_for_widgets(){
  echo "==> Enabling NetworkManager, bluetooth, pipewire..."
  sudo systemctl enable --now NetworkManager
  sudo systemctl enable --now bluetooth || true
  sudo systemctl enable --now pipewire pipewire-alsa pipewire-pulse wireplumber || true
}

post_checks_and_notes(){
  cat <<EOF

==================== DONE ====================

• Repo installiert unter: $DEST – install.fish ausgeführt, um alle Upstream‐Configs exakt zu übernehmen.
• rEFInd/GRUB: Kernel‐Param ‘nvidia-drm.modeset=1’ wurde gesetzt (falls NVIDIA gewählt).
• Night-Shift: $([ "$OPT_NIGHTSHIFT" = redshift ] && echo "Redshift" || ([ "$OPT_NIGHTSHIFT" = gammastep ] && echo "Gammastep" || echo "None")) mit systemd‐User aktiviert.
• Gaming-Stack (Steam, Vulkan, Lutris, Proton-GE): $( [ "$OPT_GAMING" -eq 1 ] && echo "installiert" || echo "nicht installiert").
• greetd/tuigreet läuft als Login‐Manager.
• Bluetooth/Wi-Fi-Widgets: NetworkManager, bluetooth, pipewire aktiviert.
• Sicher vor Reboot: prüfe /boot/refind_linux.conf.bak, multilib-Status, systemctl-user Services, Bootloader-Config, backups.

EOF
}

main(){
  check_sudo
  install_basic_packages
  install_aur_helper
  [ "$OPT_GAMING" -eq 1 ] && install_gaming_stack
  [ "$OPT_NVIDIA" -eq 1 ] && configure_nvidia_refind
  install_aur_packages
  setup_repo_and_run_installfish
  setup_greetd_tuigreet
  install_nightshift
  enable_services_for_widgets
  post_checks_and_notes
}

main "$@"
