#!/bin/bash

# ---------------------------------------------------------
# ATUALIZAÇÃO INICIAL
# ---------------------------------------------------------
sudo dnf update -y
sudo dnf upgrade -y

# ---------------------------------------------------------
# REMOVER FIREFOX
# ---------------------------------------------------------
sudo dnf remove -y firefox

# ---------------------------------------------------------
# REPOSITÓRIOS
# ---------------------------------------------------------
sudo dnf install -y dnf-plugins-core

# Brave
sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/x86_64/
sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc

# VS Code
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'

# ---------------------------------------------------------
# INSTALAÇÃO DE PACOTES (RPM)
# ---------------------------------------------------------
sudo dnf install -y \
    brave-browser \
    steam \
    git \
    gnome-tweaks \
    kdeconnectd \
    code \
    @development-tools \
    tlp tlp-rdw \
    auto-cpufreq \
    gamemode \
    zram-generator

# ---------------------------------------------------------
# JAVA 21 E 25 (SEM 17)
# ---------------------------------------------------------
sudo dnf install -y java-21-openjdk java-21-openjdk-devel
sudo dnf install -y java-25-openjdk java-25-openjdk-devel

# ---------------------------------------------------------
# FLATPAKS
# ---------------------------------------------------------
flatpak install -y com.todoist.Todoist
flatpak install -y com.discordapp.Discord
flatpak install -y io.github.mimbrero.WhatsAppDesktop
flatpak install -y com.heroicgameslauncher.hgl
flatpak install -y io.github.jeffshee.Hidamari
flatpak install -y com.mattjakeman.ExtensionManager

# ---------------------------------------------------------
# AJUSTES GNOME (TEMA, CORES, TECLADO, FONTES)
# ---------------------------------------------------------

# Teclado PT-BR
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'br')]"

# Tema escuro
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'

# Cores vívidas (accent color azul)
gsettings set org.gnome.desktop.interface accent-color 'blue'

# Fonte itálica (Cantarell Italic)
sudo dnf install -y google-droid-sans-fonts
gsettings set org.gnome.desktop.interface font-name "Cantarell Italic 11"

# Painel mais rápido (desabilita animações pesadas)
gsettings set org.gnome.desktop.interface enable-animations false

# ---------------------------------------------------------
# OTIMIZAÇÕES DE DESEMPENHO (DESKTOP e NOTEBOOK)
# ---------------------------------------------------------

# Ativar TLP (para notebook)
sudo systemctl enable tlp --now

# Ativar auto-cpufreq (melhor que cpupower)
sudo auto-cpufreq --install

# Gamemode para jogos
sudo systemctl enable --now gamemoded

# ZRAM (melhor swap)
sudo bash -c 'echo -e "[zram0]\ntype = zram\nzram-size = ram / 2" > /etc/systemd/zram-generator.conf'

# Swappiness (reduz lag)
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf

# Desligar watchdog (menos travamentos)
echo "kernel.nmi_watchdog=0" | sudo tee -a /etc/sysctl.conf

# Aplicar sysctl
sudo sysctl -p

# ---------------------------------------------------------
# SSH ROOT
# ---------------------------------------------------------
sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# ---------------------------------------------------------
# GRUB – PRIORIDADE FEDORA
# ---------------------------------------------------------
sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg

BOOT=$(sudo efibootmgr | grep -i fedora | awk '{print $1}' | sed 's/Boot//' | sed 's/\*//')
sudo efibootmgr -o $BOOT

# ---------------------------------------------------------
# FIM
# ---------------------------------------------------------
echo "INSTALAÇÃO E OTIMIZAÇÃO COMPLETAS. REINICIE O SISTEMA."

