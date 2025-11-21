#!/usr/bin/env bash
# fedora-postinstall.sh
# Uso: sudo ./fedora-postinstall.sh
# Objetivo: pós-formatação para Fedora — instalar apps, drivers, otimizações, tentativa de saturação de cores.
set -euo pipefail
LOG=/var/log/fedora-postinstall.log
exec > >(tee -a "$LOG") 2>&1

echo "Iniciando postinstall: $(date)"

# 1) checar se está em Fedora
if ! [ -f /etc/fedora-release ]; then
  echo "Este script é destinado ao Fedora. Abortando."
  exit 1
fi

# 2) atualizar sistema
echo "Atualizando sistema..."
dnf -y update --refresh

# 3) habilitar RPM Fusion (free + nonfree)
echo "Habilitando RPM Fusion (free + nonfree)..."
DNF_RPMF_FREE="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
DNF_RPMF_NONFREE="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
dnf -y install "$DNF_RPMF_FREE" "$DNF_RPMF_NONFREE"
dnf -y upgrade --refresh

# 4) instalar ferramentas básicas de desenvolvimento, flatpak e utilitários
echo "Instalando pacotes básicos..."
dnf -y groupinstall "Development Tools" || true
dnf -y install \
  flatpak \
  dnf-plugins-core \
  rpmfusion-free-release \
  rpmfusion-nonfree-release \
  kernel-devel kernel-headers gcc make \
  tlp fstrim timers \
  cpupower \
  xrandr xorg-x11-server-utils xcalib \
  gnome-tweaks \
  unzip wget curl jq git \
  policycoreutils-python-utils \
  || true

# 5) habilitar fstrim timer (SSD)
if systemctl list-unit-files | grep -q fstrim; then
  systemctl enable --now fstrim.timer || true
fi

# 6) habilitar/ajustar swappiness e zram (simple)
echo "Ajustando swappiness e configurando zram (simples)..."
sysctl_conf=/etc/sysctl.d/99-postinstall-swappiness.conf
cat > "$sysctl_conf" <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl --system || true

# zram via kernel module + simple config (fallback se zram-generator não estiver presente)
if ! rpm -q zram-generator-defaults >/dev/null 2>&1; then
  dnf -y install zram-generator-defaults || true
fi

# 7) configurar governor para performance (desktop; pode reduzir bateria)
echo "Ativando governor 'performance' (requer cpupower)..."
if command -v cpupower >/dev/null 2>&1; then
  systemctl enable --now cpupower.service || true
  cpupower frequency-set -g performance || true
fi

# 8) habilitar Flathub
echo "Habilitando Flathub e atualizando flatpak..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak repair || true

# 9) instalar aplicações via flatpak / dnf / rpm
echo "Instalando aplicações (VSCode, Krita, GIMP, ONLYOFFICE, Discord, Steam, Heroic, Brave, etc.)..."

# Visual Studio Code: baixar RPM oficial e instalar
echo "Instalando Visual Studio Code (RPM oficial)..."
TMP_RPM="/tmp/vscode.rpm"
curl -L "https://update.code.visualstudio.com/latest/linux-rpm-x64/stable" -o "$TMP_RPM" || true
if [ -f "$TMP_RPM" ]; then
  dnf -y install "$TMP_RPM" || true
  rm -f "$TMP_RPM"
fi

# Brave: adicionar repositório e instalar
echo "Instalando Brave browser..."
if ! dnf repolist | grep -q brave; then
  curl -fsSLo /etc/pki/rpm-gpg/brave-core.asc https://brave-browser-rpm-release.s3.brave.com/brave-core.asc || true
  dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/x86_64/ || true
fi
dnf -y install brave-browser || true

# Steam (requer RPM Fusion)
echo "Instalando Steam..."
dnf -y install steam || true

# Flatpak apps (usando IDs do Flathub)
FLATPAK_APPS=(
  org.kde.krita            # Krita
  org.gimp.GIMP            # GIMP
  org.onlyoffice.desktopeditors  # ONLYOFFICE
  com.discordapp.Discord   # Discord
  com.valvesoftware.Steam  # Steam flatpak (opcional)
  com.heroicgameslauncher.hgl # Heroic (Epic)
  com.gigitux.youp         # Youp (WhatsApp wrapper)
  com.ktechpit.Whatsie     # Whatsie (outro whatsapp wrapper)
)
for app in "${FLATPAK_APPS[@]}"; do
  echo "flatpak install -y flathub $app"
  flatpak install -y flathub "$app" || echo "Falha ao instalar flatpak $app (seguindo...)"
done

# Se quiser: instalar Todoist como PWAs/Extensão no navegador (não há um pacote oficial universal). Aqui instalamos Todoist via navegador (recomendado) — deixar para o usuário logar.

# 10) detectar GPU e instalar driver NVIDIA via RPM Fusion se necessário
echo "Detectando GPU..."
GPU_VENDOR="$(lspci -nnk | awk '/VGA compatible controller|3D controller/{print tolower($0)}' | tr -d '\n' || true)"
echo "GPU_VENDOR raw: $GPU_VENDOR"

if echo "$GPU_VENDOR" | grep -qi nvidia; then
  echo "Placa NVIDIA detectada. Instalando drivers NVIDIA (akmod-nvidia) via RPM Fusion..."
  # instalar headers / devtools
  dnf -y install kernel-devel kernel-headers gcc make akmod-nvidia xorg-x11-drv-nvidia-cuda || true
  # desabilitar nouveau no-boot se necessário (adicionar modprobe blacklisting)
  cat >/etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF
  dracut --force || true
  echo "Drivers NVIDIA solicitados. Reboot pode ser necessário para ativar o driver."
else
  echo "NVIDIA não detectada, pulando instalação de driver privativo."
fi

# 11) aplicar otimizações de GRUB — foco em Fedora como padrão (reduzir timeout)
echo "Configurando GRUB para priorizar Fedora (timeout curto)..."
GRUBCFG="/etc/default/grub"
if [ -f "$GRUBCFG" ]; then
  cp "$GRUBCFG" "$GRUBCFG.bak.postinstall.$(date +%s)" || true
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' "$GRUBCFG" || echo "GRUB_TIMEOUT=3" >> "$GRUBCFG"
  sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' "$GRUBCFG" || true
  # rebuild grub.cfg for UEFI and BIOS
  if [ -d /sys/firmware/efi ]; then
    grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg || grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg || true
  else
    grub2-mkconfig -o /boot/grub2/grub.cfg || true
  fi
fi

# 12) tentar aplicar "saturação" de cores automaticamente
# Nota: saturação real depende de icc profiles e Wayland/X11. Abaixo tentamos uma solução xcalib/xrandr para X11.
SAT_SCRIPT_USER="/usr/local/bin/apply-saturation.sh"
cat > "$SAT_SCRIPT_USER" <<'BASH'
#!/usr/bin/env bash
# tenta aplicar aumento de contraste/cores via xcalib/xrandr
OUT=$(xrandr --query | awk '/ connected/{print $1; exit}')
if [ -z "$OUT" ]; then
  echo "Nenhuma saída detectada via xrandr."
  exit 0
fi
# aumentar contraste com xcalib (-co): 110..120 dá cores mais “vivas”. Ajuste conforme preferir.
if command -v xcalib >/dev/null 2>&1; then
  xcalib -alter -co 115
fi
# fallback: ajustar gama (pode saturar levemente)
if command -v xrandr >/dev/null 2>&1; then
  # valores de gama: R:G:B -> aqui aumentamos um pouco R e G para saturação
  xrandr --output "$OUT" --gamma 1.05:1.03:1.00 || true
fi
BASH
chmod +x "$SAT_SCRIPT_USER"

# Criar serviço de usuário systemd para aplicar saturação no login (X11)
echo "Instalando serviço de usuário para aplicar saturação ao login (X11)..."
USER_SERVICE_DIR="/etc/systemd/system/display-saturation.service"
cat > "$USER_SERVICE_DIR" <<EOF
[Unit]
Description=Apply display saturation (xcalib/xrandr) at boot
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply-saturation.sh
RemainAfterExit=true

[Install]
WantedBy=graphical.target
EOF
systemctl daemon-reload || true
systemctl enable --now display-saturation.service || true

# 13) configurar permissões e flatpak overrides para performance (opcional)
# permitir acesso a dispositivos de GPU para flatpaks mais recentes
echo "Aplicando overrides flatpak para permissões de GPU básicas (quando aplicável)..."
flatpak override --filesystem=/dev/dri --talk-name=org.freedesktop.portal.Desktop --env=CLUTTER_PAINT=disable-buffer-age || true

# 14) limpar caches
dnf -y autoremove || true
dnf clean all || true
flatpak repair || true

echo "Postinstall concluído. Log em: $LOG"
echo "Notas importantes:"
echo "- Se você tem NVIDIA, reinicie para completar a instalação do driver (e confira Secure Boot)."
echo "- Se estiver em Wayland (padrão GNOME), a aplicação via xcalib/xrandr pode não funcionar; será necessário usar perfis ICC (gnome-color-manager) ou ferramentas do compositor. O script instalou gnome-tweaks e xcalib; ajuste manual caso necessário."
echo "- Para saturação profissional/ICC: recomendo usar um perfil ICC calibrado ou instalar e usar gnome-color-manager/colord para gerenciar perfis (a automatização completa exige device/monitor info)."
