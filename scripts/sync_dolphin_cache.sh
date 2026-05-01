#!/bin/bash
USER_NAME=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo "~$USER_NAME")

RAM_CACHE="$USER_HOME/.var/app/org.DolphinEmu.dolphin-emu/cache/dolphin-emu"
SD_BACKUP="$USER_HOME/dolphin_shader_backup"

case "$1" in
    start)
        echo "Carregando Shaders..."
        cp -r "$SD_BACKUP/." "$RAM_CACHE/" ;;
    stop)
        echo "Salvando Shaders..."
        rsync -av --delete "$RAM_CACHE/." "$SD_BACKUP/" ;;
esac