#!/bin/bash

# --- DETECÇÃO DINÂMICA DE USUÁRIO ---
USER_NAME=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo "~$USER_NAME")

# --- 1. PASTAS E MONTAGEM ---
RAM_CACHE="$USER_HOME/.var/app/org.DolphinEmu.dolphin-emu/cache/dolphin-emu"
SD_BACKUP="$USER_HOME/dolphin_shader_backup"

mkdir -p "$SD_BACKUP"
sudo mount -a

# --- 2. EXTREME LOCK (HARDWARE) ---
# Aplica os clocks que validamos para o Tegra X1.
echo "L4T Linux: Aplicando Overclock Máximo..."
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
echo 1785000 | sudo tee /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq > /dev/null
echo 921600000 | sudo tee /sys/kernel/debug/bpmp/debug/clk/gpu/rate > /dev/null
echo 1 | sudo tee /sys/kernel/debug/bpmp/debug/clk/gpu/mrq_rate_locked > /dev/null
echo 1600000000 | sudo tee /sys/kernel/debug/bpmp/debug/clk/emc/rate > /dev/null

# --- 3. PRÉ-JOGO: CARREGAR CACHE ---
echo "Injetando Shaders na RAM..."
rsync -av "$SD_BACKUP/" "$RAM_CACHE/"

# --- 4. EXECUÇÃO E GESTÃO TÉRMICA ---
export mesa_glthread=true
flatpak run org.DolphinEmu.dolphin-emu &

sleep 3
PID=$(pgrep -f "dolphin-emu")

if [ ! -z "$PID" ]; then
    sudo renice -n -20 -p $PID
    while [ -d /proc/$PID ]; do
        TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP_C=$((TEMP / 1000))
        # Curva de ventoinha dinâmica para proteção do hardware.
        if [ "$TEMP_C" -lt 50 ]; then FAN=150; elif [ "$TEMP_C" -lt 68 ]; then FAN=215; else FAN=250; fi
        echo $FAN | sudo tee /sys/devices/pwm-fan/target_pwm > /dev/null
        sleep 10
    done
fi

# --- 5. PÓS-JOGO: SINCRONIZAÇÃO ---
echo "Sincronizando Shaders para o SD..."
rsync -av --delete "$RAM_CACHE/" "$SD_BACKUP/"
echo 0 | sudo tee /sys/devices/pwm-fan/target_pwm > /dev/null