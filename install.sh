#!/bin/bash

# Installationsskript für caelestia-dots auf Arch Linux
# HINWEIS: Dieses Skript sollte auf einer minimalen Arch-Installation ausgeführt werden.

# Funktion zur Ausgabe von Informationen
info() {
    echo -e "\e[1;34m[INFO]\e[0m $1"
}

# Funktion zur Ausgabe von Warnungen
warn() {
    echo -e "\e[1;33m[WARN]\e[0m $1"
}

# Funktion zur Ausgabe von Fehlern
error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1"
    exit 1
}

# 1. System aktualisieren
info "Aktualisiere das System..."
sudo pacman -Syu --noconfirm || error "Systemaktualisierung fehlgeschlagen."

# 2. Notwendige Pakete für yay und NVIDIA-Treiber installieren
info "Installiere 'git', 'base-devel' und NVIDIA-Treiber..."
sudo pacman -S --needed git base-devel --noconfirm
sudo pacman -S --noconfirm nvidia nvidia-utils nvidia-settings lib32-nvidia-utils || warn "NVIDIA-Treiberinstallation fehlgeschlagen. Fahre fort, aber erwarte Probleme."

# 3. yay (AUR-Helper) installieren
if ! command -v yay &> /dev/null
then
    info "Installiere yay..."
    git clone https://aur.archlinux.org/yay.git
    (cd yay && makepkg -si --noconfirm)
    rm -rf yay
    info "yay wurde installiert."
else
    info "yay ist bereits installiert."
fi

# 4. Abhängigkeiten und tuigreet installieren
info "Installiere Abhängigkeiten über das 'caelestia-meta' Paket und 'greetd' mit 'tuigreet'..."
yay -S --noconfirm caelestia-meta greetd greetd-tuigreet || error "Installation der Abhängigkeiten fehlgeschlagen."

# 5. tuigreet als Greeter konfigurieren
info "Konfiguriere tuigreet..."
sudo tee /etc/greetd/config.toml > /dev/null <<EOF
[terminal]
# Der VT, auf dem der Greeter gestartet wird
vt = 1

[default_session]
# Der Befehl, der nach dem Login ausgeführt wird
command = "tuigreet --cmd Hyprland"
user = "greeter"
EOF

# 6. caelestia-dots Repository klonen
info "Klone das caelestia-dots Repository nach ~/.local/share/caelestia..."
mkdir -p ~/.local/share
git clone https://github.com/caelestia-dots/caelestia.git ~/.local/share/caelestia || error "Klonen des Repositories fehlgeschlagen."

# 7. Konfigurationen symlinken
info "Symlinke die Konfigurationsdateien..."
CONFIG_DIR=~/.config
DOTFILES_DIR=~/.local/share/caelestia

ln -sfn "$DOTFILES_DIR/hypr" "$CONFIG_DIR/hypr"
ln -sfn "$DOTFILES_DIR/foot" "$CONFIG_DIR/foot"
ln -sfn "$DOTFILES_DIR/fish" "$CONFIG_DIR/fish"
ln -sfn "$DOTFILES_DIR/fastfetch" "$CONFIG_DIR/fastfetch"
ln -sfn "$DOTFILES_DIR/uwsm" "$CONFIG_DIR/uwsm"
ln -sfn "$DOTFILES_DIR/btop" "$CONFIG_DIR/btop"
# Füge hier weitere Symlinks hinzu, falls nötig

# 8. Auswahl für optionale Anwendungen
info "Du kannst nun optionale, gemoddete Anwendungen installieren."
read -p "Möchtest du Discord (mit OpenAsar und Equicord) installieren? (j/N): " discord_choice
read -p "Möchtest du Spotify (mit Spicetify) installieren? (j/N): " spotify_choice
read -p "Möchtest du VSCodium installieren? (j/N): " vscodium_choice
read -p "Möchtest du den Zen Browser installieren? (j/N): " zen_choice

# Discord
if [[ "$discord_choice" =~ ^[jJ]$ ]]; then
    info "Installiere Discord mit OpenAsar und Equicord..."
    yay -S --noconfirm discord
    # Installation von OpenAsar und Equicord (benötigt nodejs/npm)
    sudo pacman -S --noconfirm npm
    sudo npm install -g equicord openasar
    openasar patch
fi

# Spotify
if [[ "$spotify_choice" =~ ^[jJ]$ ]]; then
    info "Installiere Spotify und Spicetify..."
    yay -S --noconfirm spotify
    # Spicetify installieren
    curl -fsSL https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.sh | sh
    # Spicetify Konfiguration anwenden
    mkdir -p ~/.config/spicetify
    ln -sfn "$DOTFILES_DIR/spicetify" "$CONFIG_DIR/spicetify"
    spicetify config current_theme caelestia color_scheme caelestia custom_apps marketplace
    spicetify apply
fi

# VSCodium
if [[ "$vscodium_choice" =~ ^[jJ]$ ]]; then
    info "Installiere VSCodium..."
    yay -S --noconfirm vscodium-bin
fi

# Zen Browser
if [[ "$zen_choice" =~ ^[jJ]$ ]]; then
    info "Installiere Zen Browser..."
    yay -S --noconfirm zen-browser-bin
fi


# 9. greetd Service aktivieren
info "Aktiviere den greetd Service..."
sudo systemctl enable greetd

info "Installation abgeschlossen!"
warn "Bitte starte dein System jetzt neu, um alle Änderungen zu übernehmen."
read -p "Möchtest du jetzt neustarten? (j/N): " reboot_choice
if [[ "$reboot_choice" =~ ^[jJ]$ ]]; then
    sudo reboot
fi

exit 0
