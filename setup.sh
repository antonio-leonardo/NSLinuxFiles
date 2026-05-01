#!/bin/bash

# --- 1. CONFIGURAÇÃO DO REPOSITÓRIO OFICIAL ---
# Link direto para os arquivos brutos do seu repositório
REPO_RAW_URL="https://raw.githubusercontent.com/antonio-leonardo/NSLinuxFiles/main"

# --- 2. CAPTURA DINÂMICA DE CONTEXTO ---
# Detecta o usuário que iniciou a sessão (mesmo via sudo)
REAL_USER=${SUDO_USER:-$(whoami)}
# Obtém o caminho absoluto da HOME do usuário
REAL_HOME=$(eval echo "~$REAL_USER")

# Cores para o terminal (Interface do usuário)
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}   NSLinuxFiles - Instalador Oficial (Switch)${NC}"
echo -e "${BLUE}   Repositório: github.com/antonio-leonardo/NSLinuxFiles${NC}"
echo -e "${BLUE}   Instalando para: ${NC}$REAL_USER"
echo -e "${BLUE}====================================================${NC}"

# --- PASSO 0: DEPENDÊNCIAS (FLATPAK & DOLPHIN) ---
# Garante que o ambiente de execução esteja pronto com o ID oficial.
echo -e "${BLUE}[0/6] Verificando Flatpak e Dolphin (org.DolphinEmu.dolphin-emu)...${NC}"
if ! command -v flatpak &> /dev/null; then
    sudo apt update && sudo apt install -y flatpak
fi
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
# Instalando o emulador oficial via Flathub.
sudo flatpak install -y flathub org.DolphinEmu.dolphin-emu

# --- PASSO 1: CONFIGURAÇÃO DE SWAP (4GB) ---
# Previne falhas de memória (OOM) no Tegra X1 durante a emulação[cite: 1].
if [ ! -f /swapfile ]; then
    echo -e "${BLUE}[1/6] Criando arquivo de SWAP de 4GB...${NC}"
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
else
    echo -e "${GREEN}[1/6] SWAP de 4GB já configurado.${NC}"
fi

# --- PASSO 2: DOWNLOAD DOS SCRIPTS DE PERFORMANCE ---
# Baixa as ferramentas de overclock e gestão de cache.
echo -e "${BLUE}[2/6] Baixando scripts do repositório remoto...${NC}"
mkdir -p "$REAL_HOME/dolphin_shader_backup"

# Download do script de Extreme Lock (1785MHz/921MHz/1600MHz)[cite: 1].
curl -sSL "$REPO_RAW_URL/scripts/dolphin_boost.sh" -o "$REAL_HOME/dolphin_boost.sh"
# Download do utilitário de persistência de shaders[cite: 2].
curl -sSL "$REPO_RAW_URL/scripts/sync_dolphin_cache.sh" -o "$REAL_HOME/sync_dolphin_cache.sh"

chown "$REAL_USER:$REAL_USER" "$REAL_HOME/dolphin_boost.sh" "$REAL_HOME/sync_dolphin_cache.sh"
chmod +x "$REAL_HOME/dolphin_boost.sh"[cite: 1]
chmod +x "$REAL_HOME/sync_dolphin_cache.sh"[cite: 2]

# --- PASSO 3: SUDOERS BYPASS (UM CLIQUE) ---
# Autoriza o script de boost a alterar o hardware sem pedir senha[cite: 1].
echo -e "${BLUE}[3/6] Aplicando bypass de senha para o Overclock...${NC}"
SUDO_FILE="/etc/sudoers.d/dolphin-boost"
echo "$REAL_USER ALL=(ALL) NOPASSWD: $REAL_HOME/dolphin_boost.sh" | sudo tee "$SUDO_FILE" > /dev/null
sudo chmod 0440 "$SUDO_FILE"

# --- PASSO 4: CONFIGURAÇÃO DE CONTROLES (X11) ---
# Baixa o mapeamento para Mobapad Force e Joy-Cons.
echo -e "${BLUE}[4/6] Configurando drivers de Joystick/Mouse (Xorg)...${NC}"
sudo mkdir -p /usr/share/X11/xorg.conf.d/
sudo curl -sSL "$REPO_RAW_URL/configs/50-joystick.conf" -o /usr/share/X11/xorg.conf.d/50-joystick.conf[cite: 3]

# --- PASSO 5: ATALHO DE ÁREA DE TRABALHO ---
# Cria o gatilho visual para facilitar a execução pelo usuário leigo[cite: 1].
echo -e "${BLUE}[5/6] Criando ícone 'Dolphin Turbo' no Desktop...${NC}"
DESKTOP_DIR="$REAL_HOME/Desktop"
[ ! -d "$DESKTOP_DIR" ] && DESKTOP_DIR="$REAL_HOME/Área de Trabalho"

cat <<EOF > "$DESKTOP_DIR/Dolphin_Turbo.desktop"
[Desktop Entry]
Type=Application
Name=Dolphin Turbo (OC)
Comment=Inicia com Overclock Máximo (NSLinuxFiles)
Exec=sudo $REAL_HOME/dolphin_boost.sh
Icon=org.DolphinEmu.dolphin-emu
Terminal=true
Categories=Game;Emulator;
EOF
chown "$REAL_USER:$REAL_USER" "$DESKTOP_DIR/Dolphin_Turbo.desktop"
chmod +x "$DESKTOP_DIR/Dolphin_Turbo.desktop"

# --- PASSO 6: CONCLUSÃO ---
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   INSTALAÇÃO CONCLUÍDA!${NC}"
echo -e "   Repositório: github.com/antonio-leonardo/NSLinuxFiles"
echo -e "   Reinicie o seu Switch e use o ícone na Área de Trabalho."
echo -e "${GREEN}====================================================${NC}"