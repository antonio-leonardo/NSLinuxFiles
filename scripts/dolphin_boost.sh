#!/bin/bash
set -Eeuo pipefail

# --- DETECCAO DINAMICA DE USUARIO ---
USER_NAME=${SUDO_USER:-$(id -un)}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
[ -n "$USER_HOME" ] || { echo "ERRO: nao foi possivel determinar o HOME de '$USER_NAME'." >&2; exit 1; }

USER_ID=$(id -u "$USER_NAME")
USER_GROUP=$(id -g "$USER_NAME")

# --- PASTAS, LIMITES E SYSFS ---
RAM_CACHE="${DOLPHIN_RAM_CACHE:-$USER_HOME/.var/app/org.DolphinEmu.dolphin-emu/cache/dolphin-emu}"
SD_BACKUP="${DOLPHIN_SHADER_BACKUP:-$USER_HOME/dolphin_shader_backup}"
CACHE_SIZE="${DOLPHIN_CACHE_SIZE:-1G}"
UNMOUNT_CACHE_ON_EXIT="${DOLPHIN_UNMOUNT_CACHE_ON_EXIT:-1}"

LOCK_DIR="$USER_HOME/.cache/dolphin-boost"
LOCK_FILE="$LOCK_DIR/cache.lock"
STATE_DIR=$(mktemp -d /tmp/dolphin-boost.XXXXXX)

THERMAL_SENSOR="${DOLPHIN_THERMAL_SENSOR:-/sys/class/thermal/thermal_zone0/temp}"
FAN_PWM="/sys/devices/pwm-fan/target_pwm"
GPU_RATE="/sys/kernel/debug/bpmp/debug/clk/gpu/rate"
GPU_LOCK="/sys/kernel/debug/bpmp/debug/clk/gpu/mrq_rate_locked"
EMC_RATE="/sys/kernel/debug/bpmp/debug/clk/emc/rate"

CACHE_READY=0
CACHE_MOUNTED_BY_US=0
ORIGINAL_FAN=""
FAN_MANAGED=0

log() {
    printf '%s\n' "$*"
}

die() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

write_sysfs() {
    local value=$1
    local path=$2

    if [ "$(id -u)" -eq 0 ]; then
        printf '%s\n' "$value" > "$path"
    else
        printf '%s\n' "$value" | sudo tee "$path" > /dev/null
    fi
}

state_key() {
    printf '%s' "$1" | sed 's#[^A-Za-z0-9_.-]#_#g'
}

save_sysfs() {
    local path=$1
    local key

    [ -r "$path" ] || return 0
    key=$(state_key "$path")
    cat "$path" > "$STATE_DIR/$key"
    printf '%s\t%s\n' "$key" "$path" >> "$STATE_DIR/saved_sysfs"
}

restore_saved_sysfs() {
    local key path value

    [ -f "$STATE_DIR/saved_sysfs" ] || return 0
    while IFS=$'\t' read -r key path; do
        [ -f "$STATE_DIR/$key" ] || continue
        value=$(cat "$STATE_DIR/$key")
        write_sysfs "$value" "$path" 2>/dev/null || true
    done < "$STATE_DIR/saved_sysfs"
}

glob_paths() {
    local pattern=$1
    compgen -G "$pattern" || true
}

validate_safe_path() {
    local path="$1"
    local label="$2"
    local resolved

    [[ "$path" == *..* ]] && die "caminho invalido para $label (traversal detectado): '$path'"

    resolved=$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")
    case "$resolved" in
        /proc/*|/sys/*|/etc/*|/dev/*|/run/*|/root/*|/bin/*|/sbin/*|/usr/*|/lib/*|/boot/*)
            die "caminho restrito para $label: '$resolved'. Use um caminho dentro de $USER_HOME."
            ;;
    esac
}

save_glob() {
    local pattern=$1
    local path

    while IFS= read -r path; do
        [ -n "$path" ] && save_sysfs "$path"
    done < <(glob_paths "$pattern")
}

write_glob() {
    local value=$1
    local pattern=$2
    local found=0
    local path

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        found=1
        write_sysfs "$value" "$path"
    done < <(glob_paths "$pattern")

    [ "$found" -eq 1 ] || die "nenhum caminho sysfs encontrado para '$pattern'. Verifique se o kernel L4T esta carregado corretamente e se o modulo cpufreq esta ativo."
}

require_cmds() {
    local cmd
    for cmd in flock flatpak mount mountpoint pgrep renice rsync; do
        command -v "$cmd" > /dev/null 2>&1 || die "comando obrigatorio ausente: $cmd"
    done
}

prepare_lock() {
    mkdir -p "$LOCK_DIR"
    touch "$LOCK_FILE"
    if [ "$(id -u)" -eq 0 ]; then
        chown "$USER_ID:$USER_GROUP" "$LOCK_DIR" "$LOCK_FILE" 2>/dev/null || true
    fi

    exec 9>"$LOCK_FILE"
    flock -n 9 || die "outra sincronizacao/execucao do Dolphin Turbo ja esta em andamento."
}

dolphin_running() {
    pgrep -u "$USER_NAME" -f 'org\.DolphinEmu\.dolphin-emu|dolphin-emu' > /dev/null 2>&1
}

dir_has_entries() {
    [ -n "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

ensure_debugfs() {
    if [ ! -d /sys/kernel/debug/bpmp ] && ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
        as_root mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
    fi

    [ -e "$GPU_RATE" ] || die "BPMP indisponivel em $GPU_RATE. Verifique o L4T/debugfs."
    [ -e "$GPU_LOCK" ] || die "BPMP indisponivel em $GPU_LOCK. Verifique o L4T/debugfs."
    [ -e "$EMC_RATE" ] || die "BPMP indisponivel em $EMC_RATE. Verifique o L4T/debugfs."
    [ -e "$FAN_PWM" ] || die "controle de ventoinha indisponivel em $FAN_PWM."
    [ -r "$THERMAL_SENSOR" ] || die "sensor termico indisponivel em $THERMAL_SENSOR."
}

seed_backup_from_existing_cache() {
    if mountpoint -q "$RAM_CACHE"; then
        return 0
    fi

    if dir_has_entries "$RAM_CACHE" && ! dir_has_entries "$SD_BACKUP"; then
        log "Criando backup inicial do cache existente..."
        rsync -a "$RAM_CACHE/" "$SD_BACKUP/"
    fi
}

ensure_ram_cache() {
    mkdir -p "$RAM_CACHE" "$SD_BACKUP"
    if [ "$(id -u)" -eq 0 ]; then
        chown "$USER_ID:$USER_GROUP" "$RAM_CACHE" "$SD_BACKUP" 2>/dev/null || true
    fi

    seed_backup_from_existing_cache

    if mountpoint -q "$RAM_CACHE"; then
        log "Cache em RAM ja esta montado."
        return 0
    fi

    log "Montando cache do Dolphin em RAM (${CACHE_SIZE})..."
    if as_root mount -t tmpfs -o "rw,nosuid,nodev,relatime,size=${CACHE_SIZE},mode=700,uid=${USER_ID},gid=${USER_GROUP}" tmpfs "$RAM_CACHE"; then
        CACHE_MOUNTED_BY_US=1
        return 0
    fi

    log "AVISO: nao foi possivel montar tmpfs; o cache continuara no armazenamento atual."
}

sync_cache_from_backup() {
    log "Injetando shaders no cache..."
    rsync -a --info=progress2 "$SD_BACKUP/" "$RAM_CACHE/"
    CACHE_READY=1
}

sync_cache_to_backup() {
    if ! dir_has_entries "$RAM_CACHE" && dir_has_entries "$SD_BACKUP"; then
        log "AVISO: cache atual vazio; preservando backup existente."
        return 0
    fi

    log "Sincronizando shaders para o backup..."
    rsync -a --info=progress2 --delete "$RAM_CACHE/" "$SD_BACKUP/"
}

read_temp_c() {
    local temp

    if temp=$(cat "$THERMAL_SENSOR" 2>/dev/null) && [[ "$temp" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$((temp / 1000))"
        return 0
    fi

    printf '999\n'
}

fan_for_temp() {
    local temp_c=$1

    if [ "$temp_c" -lt 48 ]; then
        printf '150\n'
    elif [ "$temp_c" -lt 58 ]; then
        printf '190\n'
    elif [ "$temp_c" -lt 63 ]; then
        printf '225\n'
    elif [ "$temp_c" -lt 68 ]; then
        printf '250\n'
    else
        printf '255\n'
    fi
}

thermal_sleep_for() {
    local temp_c=$1

    if [ "$temp_c" -ge 63 ]; then
        printf '3\n'
    elif [ "$temp_c" -ge 58 ]; then
        printf '5\n'
    else
        printf '8\n'
    fi
}

apply_boost() {
    log "L4T Linux: aplicando overclock maximo..."

    ORIGINAL_FAN=$(cat "$FAN_PWM" 2>/dev/null || true)
    FAN_MANAGED=1
    save_glob '/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
    save_glob '/sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq'
    save_sysfs "$GPU_RATE"
    save_sysfs "$GPU_LOCK"
    save_sysfs "$EMC_RATE"

    write_glob performance '/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
    write_glob 1785000 '/sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq'
    write_sysfs 921600000 "$GPU_RATE"
    write_sysfs 1 "$GPU_LOCK"
    write_sysfs 1600000000 "$EMC_RATE"
}

restore_fan() {
    if [ -n "$ORIGINAL_FAN" ]; then
        write_sysfs "$ORIGINAL_FAN" "$FAN_PWM" 2>/dev/null || true
    else
        write_sysfs 0 "$FAN_PWM" 2>/dev/null || true
    fi
}

cleanup() {
    local status=$?
    local temp_c

    trap - EXIT INT TERM

    if [ "$FAN_MANAGED" -eq 1 ] && [ -e "$FAN_PWM" ]; then
        temp_c=$(read_temp_c)
        if [ "$temp_c" -ge 55 ]; then
            write_sysfs 220 "$FAN_PWM" 2>/dev/null || true
        fi
    fi

    restore_saved_sysfs

    if [ "$CACHE_READY" -eq 1 ]; then
        sync_cache_to_backup || status=1
    fi

    if [ "$CACHE_MOUNTED_BY_US" -eq 1 ] && [ "$UNMOUNT_CACHE_ON_EXIT" = "1" ]; then
        as_root umount "$RAM_CACHE" 2>/dev/null || log "AVISO: nao foi possivel desmontar $RAM_CACHE; ele ficara em RAM ate reboot/desmontagem manual."
    fi

    if [ "$FAN_MANAGED" -eq 1 ] && [ -e "$FAN_PWM" ]; then
        temp_c=$(read_temp_c)
        if [ "$temp_c" -ge 60 ]; then
            log "Aguardando resfriamento curto antes de restaurar a ventoinha..."
            write_sysfs 220 "$FAN_PWM" 2>/dev/null || true
            sleep 8
        fi
        restore_fan
    fi

    rm -rf "$STATE_DIR"
    exit "$status"
}

run_dolphin() {
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$USER_NAME" env \
            HOME="$USER_HOME" \
            USER="$USER_NAME" \
            LOGNAME="$USER_NAME" \
            XDG_RUNTIME_DIR="/run/user/$USER_ID" \
            DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$USER_ID/bus}" \
            DISPLAY="${DISPLAY:-:0}" \
            XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}" \
            mesa_glthread=true \
            flatpak run org.DolphinEmu.dolphin-emu
    else
        mesa_glthread=true flatpak run org.DolphinEmu.dolphin-emu
    fi
}

monitor_thermal() {
    local app_pid=$1
    local temp_c fan sleep_for
    local pids

    for _ in $(seq 1 15); do
        sleep 1
        pids=$(pgrep -u "$USER_NAME" -f 'org\.DolphinEmu\.dolphin-emu|dolphin-emu' || true)
        if [ -n "$pids" ]; then
            as_root renice -n -20 -p $pids > /dev/null 2>&1 || true
            break
        fi

        kill -0 "$app_pid" 2>/dev/null || return 0
    done

    while kill -0 "$app_pid" 2>/dev/null; do
        temp_c=$(read_temp_c)
        fan=$(fan_for_temp "$temp_c")
        write_sysfs "$fan" "$FAN_PWM" 2>/dev/null || true
        sleep_for=$(thermal_sleep_for "$temp_c")
        sleep "$sleep_for"
    done
}

main() {
    local app_pid
    local app_status=0

    validate_safe_path "$RAM_CACHE" "DOLPHIN_RAM_CACHE"
    validate_safe_path "$SD_BACKUP" "DOLPHIN_SHADER_BACKUP"

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    require_cmds
    prepare_lock
    ensure_debugfs

    if dolphin_running; then
        die "Dolphin ja esta em execucao; feche-o antes de iniciar o modo Turbo."
    fi

    ensure_ram_cache
    sync_cache_from_backup
    apply_boost

    log "Abrindo Dolphin..."
    run_dolphin &
    app_pid=$!

    monitor_thermal "$app_pid"
    wait "$app_pid" || app_status=$?
    exit "$app_status"
}

main "$@"
