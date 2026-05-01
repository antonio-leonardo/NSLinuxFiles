#!/bin/bash

# --- DETECÇÃO DINÂMICA DE CONTEXTO ---
# Captura o usuário que chamou o sudo ou o usuário logado
USER_NAME=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo "~$USER_NAME")

# --- 1. PASTAS E MONTAGEM (DINÂMICO) ---
# O caminho agora se adapta a qualquer usuário logado
RAM_CACHE="$USER_HOME/.var/app/org.DolphinEmu.dolphin-emu/cache/dolphin-emu"
SD_BACKUP="$USER_HOME/dolphin_shader_backup"

mkdir -p "$SD_BACKUP"
sudo mount -a

# --- 2. TRAVA DE HARDWARE (EXTREME LOCK) ---
echo "L4T Linux: Aplicando Overclock Máximo..."
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
echo 1785000 | sudo tee /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq > /dev/null
echo 921600000 | sudo tee /sys/kernel/debug/bpmp/debug/clk/gpu/rate > /dev/null
echo 1 | sudo tee /sys/kernel/debug/bpmp/debug/clk/gpu/mrq_rate_locked > /dev/null
echo performance | sudo tee /sys/class/devfreq/57000000.gpu/governor > /dev/null
echo 1600000000 | sudo tee /sys/kernel/debug/bpmp/debug/clk/emc/rate > /dev/null
echo 1 | sudo tee /sys/kernel/debug/bpmp/debug/clk/emc/mrq_rate_locked > /dev/null
echo 1 | sudo tee /sys/kernel/debug/tegra_cpufreq/low_latency_index > /dev/null
echo 1 | sudo tee /sys/kernel/debug/tegra_host/force_idDQ_on > /dev/null

# --- 3. PRÉ-JOGO: CARREGAR CACHE (SD -> RAM) ---
echo "Injetando Shaders na RAM..."
rsync -av "$SD_BACKUP/" "$RAM_CACHE/"

# --- 4. EXECUÇÃO E GESTÃO TÉRMICA DINÂMICA ---
export mesa_glthread=true
export __GL_THREADED_OPTIMIZATIONS=1

flatpak run org.DolphinEmu.dolphin-emu &

# Espera curta apenas para o processo ser registrado no sistema
sleep 3
PID=$(pgrep -f "dolphin-emu")

if [ ! -z "$PID" ]; then
    sudo renice -n -20 -p $PID
    echo "Performance Rocky Balboa Ativada! Monitorando via /proc/$PID..."

    # Loop de monitoramento: Roda enquanto o diretório do processo existir
    while [ -d /proc/$PID ]; do
        # Lê a temperatura real do SoC
        TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP_C=$((TEMP / 1000))

        # Define a rotação baseada na temperatura atual (Única Fonte de Verdade)
        if [ "$TEMP_C" -lt 50 ]; then
            FAN=150
        elif [ "$TEMP_C" -lt 60 ]; then
            FAN=185
        elif [ "$TEMP_C" -lt 68 ]; then
            FAN=215
        else
            FAN=250 # Proteção máxima contra Throttling térmico
        fi

        # Aplica a rotação calculada
        echo $FAN | sudo tee /sys/devices/pwm-fan/target_pwm > /dev/null
        
        # O sleep fica no fim do loop para garantir que a primeira execução seja imediata
        sleep 10
    done
fi

# --- 5. PÓS-JOGO: PERSISTÊNCIA E CLEANUP ---
echo "Dolphin encerrado. Sincronizando Shaders para o SD..."
rsync -av --delete "$RAM_CACHE/" "$SD_BACKUP/"

# Restaura a ventoinha para o modo silencioso/automático do SO
echo 0 | sudo tee /sys/devices/pwm-fan/target_pwm > /dev/null
echo "Setup finalizado. Sistema resfriado e Shaders salvos com sucesso."