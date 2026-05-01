#!/bin/bash

# --- 1. CAPTURA DINÂMICA DE CONTEXTO ---
# Detecta o usuário real (quem invocou o script) e seu diretório HOME
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOME=$(eval echo "~$REAL_USER")

# Cores para o terminal (UX/Interface)
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}   NSLinuxFiles - Automação Extreme Performance${NC}"
echo -e "${BLUE}   Usuário Detectado: ${NC}$REAL_USER"
echo -e "${BLUE}   Diretório Alvo:    ${NC}$REAL_HOME"
echo -e "${BLUE}====================================================${NC}"

# --- PASSO 0: DEPENDÊNCIAS (FLATPAK & DOLPHIN) ---
# Garante que o ambiente de execução esteja pronto.
echo -e "${BLUE}[0/6] Verificando dependências: Flatpak e Dolphin...${NC}"

# Instala o gerenciador flatpak se necessário
if ! command -v flatpak &> /dev/null; then
    echo "Instalando gerenciador Flatpak..."
    sudo apt update && sudo apt install -y flatpak
fi

# Adiciona o repositório Flathub
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Instala o Dolphin Emulator oficial via Flathub
if ! flatpak list | grep -q "org.DolphinEmu.dolphin-emu"; then
    echo "Instalando Dolphin Emulator (org.DolphinEmu.dolphin-emu)..."
    sudo flatpak install -y flathub org.DolphinEmu.dolphin-emu
else
    echo -e "${GREEN}Dolphin já está instalado.${NC}"
fi

# --- PASSO 1: CONFIGURAÇÃO DE SWAP (4GB) ---
# Essencial para evitar crashes devido à limitação de 4GB RAM física do Switch.
if [ ! -f /swapfile ]; then
    echo -e "${BLUE}[1/6] Configurando SWAP de 4GB...${NC}"
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
else
    echo -e "${GREEN}[1/6] SWAP já configurado.${NC}"
fi

# --- PASSO 2: INSTALAÇÃO DOS SCRIPTS ---
# Move os scripts para a HOME e garante permissão de execução.
echo -e "${BLUE}[2/6] Implantando scripts de performance...${NC}"

# Cria pasta de backup de shaders se não existir[cite: 1, 2]
mkdir -p "$REAL_HOME/dolphin_shader_backup"

# Copia os arquivos da estrutura do repositório para o sistema real
# Ajuste o caminho de origem conforme a estrutura do seu GitHub
cp home/antonioleonardo/dolphin_boost.sh "$REAL_HOME/dolphin_boost.sh"
cp home/antonioleonardo/sync_dolphin_cache.sh "$REAL_HOME/sync_dolphin_cache.sh"

chown "$REAL_USER:$REAL_USER" "$REAL_HOME/dolphin_boost.sh" "$REAL_HOME/sync_dolphin_cache.sh"
chmod +x "$REAL_HOME/dolphin_boost.sh"
chmod +x "$REAL_HOME/sync_dolphin_cache.sh"[cite: 2]

# --- PASSO 3: CONFIGURAÇÃO DO SUDOERS (BYPASS) ---
# Permite ao script travar frequências de hardware sem pedir senha[cite: 1].
echo -e "${BLUE}[3/6] Configurando bypass de privilégios para Overclock...${NC}"
SUDO_FILE="/etc/sudoers.d/dolphin-boost"
echo "$REAL_USER ALL=(ALL) NOPASSWD: $REAL_HOME/dolphin_boost.sh" | sudo tee "$SUDO_FILE" > /dev/null
sudo chmod 0440 "$SUDO_FILE"

# --- PASSO 4: CONFIGURAÇÃO DE CONTROLES (X11) ---
# Aplica o mapeamento para Joy-Cons e Mobapad Force.
echo -e "${BLUE}[4/6] Aplicando drivers de controle (Xorg)...${NC}"
sudo mkdir -p /usr/share/X11/xorg.conf.d/
sudo cp usr/share/X11/xorg.conf.d/50-joystick.conf /usr/share/X11/xorg.conf.d/[cite: 3]

# --- PASSO 5: ATALHO DE ÁREA DE TRABALHO ---
# Cria o ícone de gatilho para o modo Turbo[cite: 1].
echo -e "${BLUE}[5/6] Criando atalho Dolphin Turbo na Área de Trabalho...${NC}"
# Detecta se a pasta se chama Desktop ou Área de Trabalho
DESKTOP_DIR="$REAL_HOME/Desktop"
if [ ! -d "$DESKTOP_DIR" ] && [ -d "$REAL_HOME/Área de Trabalho" ]; then
    DESKTOP_DIR="$REAL_HOME/Área de Trabalho"
fi

cat <<EOF > "$DESKTOP_DIR/Dolphin_Turbo.desktop"
[Desktop Entry]
Type=Application
Name=Dolphin Turbo (OC)
Comment=Performance Máxima: CPU 1.7GHz | GPU 921MHz
Exec=sudo $REAL_HOME/dolphin_boost.sh
Icon=org.DolphinEmu.dolphin-emu
Terminal=true
Categories=Game;Emulator;
EOF

chown "$REAL_USER:$REAL_USER" "$DESKTOP_DIR/Dolphin_Turbo.desktop"
chmod +x "$DESKTOP_DIR/Dolphin_Turbo.desktop"

# --- PASSO 6: LIMPEZA E FINALIZAÇÃO ---
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "   1. Reinicie o console para ativar os drivers de controle."
echo -e "   2. Inicie o Dolphin uma vez para criar as pastas de perfil."
echo -e "   3. Use o ícone 'Dolphin Turbo' para jogar com Overclock."
echo -e "${GREEN}====================================================${NC}"