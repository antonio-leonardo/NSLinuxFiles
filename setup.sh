#!/bin/bash

# --- 1. AVISO LEGAL E CONFIRMAÇÃO ---
echo -e "\033[0;31m****************************************************"
echo "   ATENÇÃO: AVISO DE SEGURANÇA E RESPONSABILIDADE"
echo -e "****************************************************\033[0m"
echo "Este script aplicará Overclock Máximo (1785MHz CPU / 921MHz GPU)."
echo "Isso pode reduzir a vida útil da bateria e do console."
echo ""
echo "PREMISSA: Você deve estar rodando o L4T Linux Jammy 22.04 oficial."
echo "LINK: https://wiki.switchroot.org/wiki/linux/l4t-ubuntu-jammy-installation-guide"
echo ""
echo "TUDO O QUE VOCÊ FIZER É POR SUA CONTA E RISCO."
echo "O autor não se responsabiliza por danos ao seu Nintendo Switch."
echo ""
read -p "Você aceita os termos e deseja prosseguir? (s/n): " confirm

if [[ $confirm != [sS] ]]; then
    echo "Instalação cancelada pelo usuário."
    exit 1
fi

# --- 2. CONFIGURAÇÃO DO REPOSITÓRIO E CONTEXTO ---
REPO_RAW_URL="https://raw.githubusercontent.com/antonio-leonardo/NSLinuxFiles/main"
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
if [ -z "$REAL_HOME" ]; then
    echo "ERRO: não foi possível determinar o diretório home de '$REAL_USER'."
    exit 1
fi

# --- PASSO 0: DEPENDÊNCIAS (FLATPAK, RSYNC & DOLPHIN) ---
# Instala o Dolphin oficial e as ferramentas usadas pelos scripts.
echo -e "\033[0;34m[0/6] Instalando dependências e Dolphin oficial...\033[0m"
MISSING_PACKAGES=()
command -v flatpak &> /dev/null || MISSING_PACKAGES+=(flatpak)
command -v rsync &> /dev/null || MISSING_PACKAGES+=(rsync)
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    sudo apt update && sudo apt install -y "${MISSING_PACKAGES[@]}" || { echo "ERRO: falha ao instalar dependências obrigatórias."; exit 1; }
fi
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y flathub org.DolphinEmu.dolphin-emu || { echo "ERRO: falha ao instalar o Dolphin. Verifique sua conexão e tente novamente."; exit 1; }

# --- PASSO 1: CONFIGURAÇÃO DE SWAP (4GB) ---
# Garante estabilidade para evitar fechamentos inesperados.
if [ ! -f /swapfile ]; then
    echo -e "\033[0;34m[1/6] Configurando SWAP de 4GB...\033[0m"
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
fi

# --- PASSO 2: DOWNLOAD DOS SCRIPTS ---
# Baixa as ferramentas de Extreme Lock (1785/921/1600) e Sincronização.
echo -e "\033[0;34m[2/6] Baixando scripts de performance...\033[0m"
mkdir -p "$REAL_HOME/dolphin_shader_backup"
curl -sSL "$REPO_RAW_URL/scripts/dolphin_boost.sh" -o /tmp/dolphin_boost.sh || { echo "ERRO: falha no download de dolphin_boost.sh. Verifique sua conexão."; exit 1; }
curl -sSL "$REPO_RAW_URL/scripts/sync_dolphin_cache.sh" -o "$REAL_HOME/sync_dolphin_cache.sh" || { echo "ERRO: falha no download de sync_dolphin_cache.sh. Verifique sua conexão."; exit 1; }
sudo install -o root -g root -m 0755 /tmp/dolphin_boost.sh /usr/local/sbin/dolphin-boost
chmod +x "$REAL_HOME/sync_dolphin_cache.sh"

# --- PASSO 3: SUDOERS BYPASS ---
# Autoriza a mudança de clocks sem interrupção de senha.
echo -e "\033[0;34m[3/6] Configurando bypass de senha para o Overclock...\033[0m"
SUDO_FILE="/etc/sudoers.d/dolphin-boost"
SUDOERS_RULE="$REAL_USER ALL=(root) NOPASSWD: /usr/local/sbin/dolphin-boost"
echo "$SUDOERS_RULE" > /tmp/sudoers_check
if sudo visudo -c -f /tmp/sudoers_check &>/dev/null; then
    echo "$SUDOERS_RULE" | sudo tee "$SUDO_FILE" > /dev/null
    sudo chmod 0440 "$SUDO_FILE"
else
    echo "ERRO: regra sudoers inválida. Abortando."; exit 1
fi
rm -f /tmp/sudoers_check

# --- PASSO 4: CONFIGURAÇÃO DE CONTROLES (X11) ---
# Habilita suporte para Mobapad Force e Joy-Cons como mouse/teclado.
echo -e "\033[0;34m[4/6] Aplicando mapeamento de Joystick (Xorg)...\033[0m"
sudo mkdir -p /usr/share/X11/xorg.conf.d/
sudo curl -sSL "$REPO_RAW_URL/configs/50-joystick.conf" -o /usr/share/X11/xorg.conf.d/50-joystick.conf || { echo "ERRO: falha no download da configuração de joystick."; exit 1; }

# --- PASSO 5: ATALHO DE ÁREA DE TRABALHO ---
# Cria o gatilho para o modo Turbo no Desktop.
DESKTOP_DIR="$REAL_HOME/Desktop"
[ ! -d "$DESKTOP_DIR" ] && DESKTOP_DIR="$REAL_HOME/Área de Trabalho"
mkdir -p "$DESKTOP_DIR"
cat <<EOF > "$DESKTOP_DIR/Dolphin_Turbo.desktop"
[Desktop Entry]
Type=Application
Name=Dolphin Turbo (OC)
Comment=Extreme Performance: 1.7GHz CPU | 921MHz GPU
Exec=sudo /usr/local/sbin/dolphin-boost
Icon=org.DolphinEmu.dolphin-emu
Terminal=true
Categories=Game;Emulator;
EOF
chmod +x "$DESKTOP_DIR/Dolphin_Turbo.desktop"

echo -e "\033[0;32mINSTALAÇÃO CONCLUÍDA! Reinicie o Switch para ativar os drivers.\033[0m"
