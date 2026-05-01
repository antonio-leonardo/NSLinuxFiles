#!/bin/bash

# --- DETECÇÃO DINÂMICA DE CONTEXTO ---
USER_NAME=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo "~$USER_NAME")

# Caminhos Dinâmicos
RAM_CACHE="$USER_HOME/.var/app/org.DolphinEmu.dolphin-emu/cache/dolphin-emu"
SD_BACKUP="$USER_HOME/dolphin_shader_backup"

case "$1" in
    start)
        echo "Carregando Shaders do SD para a RAM..."
        # Garante que a RAM está montada
        sudo mount -a
        # Copia do SD para a RAM
        cp -r $SD_BACKUP/. $RAM_CACHE/
        echo "Pronto! Shaders carregados na RAM."
        ;;
    stop)
        echo "Salvando novos Shaders da RAM para o SD..."
        # Sincroniza apenas o que mudou (preserva o SD)
        rsync -av --delete $RAM_CACHE/. $SD_BACKUP/
        echo "Backup concluído com sucesso."
        ;;
esac