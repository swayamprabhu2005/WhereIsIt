#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: scanner.sh
# Purpose: Multi-drive detection, safe traversal, path pruning, error logging
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
fi

SCAN_ERROR_LOG="$PROJECT_ROOT/data/last_scan_errors.log"

# ------------------------------------------------------------------------------
# Drive Discovery
# ------------------------------------------------------------------------------
# Detects active Windows drives mounted in Git Bash environment
detect_available_drives() {
    local detected_drives=()
    local checked=()
    
    # Method 1: Check standard Git Bash drive roots /[a-z]
    for letter in {c..z} {a..b}; do
        local drive_path="/$letter"
        if [ -d "$drive_path" ] && [ -r "$drive_path" ]; then
            detected_drives+=("$drive_path")
            checked+=("$letter")
        fi
    done

    # If no standard drives detected (e.g. running in custom container or Linux), fallback to root /
    if [ ${#detected_drives[@]} -eq 0 ]; then
        if [ -d "/" ]; then
            detected_drives=("/")
        fi
    fi

    # Output space-separated list of POSIX mount paths
    echo "${detected_drives[*]}"
}

# Returns array of drive letters in uppercase (e.g. "C D E")
get_drive_letters() {
    local raw_drives
    raw_drives="$(detect_available_drives)"
    local letters=()
    for d in $raw_drives; do
        if [[ "$d" =~ ^/([a-zA-Z])$ ]]; then
            letters+=("${BASH_REMATCH[1]^^}")
        else
            letters+=("$d")
        fi
    done
    echo "${letters[*]}"
}

# ------------------------------------------------------------------------------
# Interactive Drive Selection Prompt
# ------------------------------------------------------------------------------
select_scan_targets() {
    local available_drives
    read -r -a available_drives <<< "$(detect_available_drives)"
    local letters
    read -r -a letters <<< "$(get_drive_letters)"

    print_subheader "TARGET LOCATION SELECTION"
    printf "Detected accessible drives: "
    for i in "${!letters[@]}"; do
        printf "%s%s:%s (%s)  " "$C_GREEN" "${letters[$i]}" "$C_RESET" "${available_drives[$i]}"
    done
    printf "\n\n"

    printf "  %s1.%s Search All Detected Drives (%s)\n" "$C_CYAN" "$C_RESET" "${letters[*]}"
    for i in "${!letters[@]}"; do
        printf "  %s%d.%s Search Drive %s: (%s)\n" "$C_CYAN" "$((i + 2))" "$C_RESET" "${letters[$i]}" "${available_drives[$i]}"
    done
    local custom_idx=$(( ${#letters[@]} + 2 ))
    local path_idx=$(( ${#letters[@]} + 3 ))
    printf "  %s%d.%s Custom Multiple Drives (e.g. C, D)\n" "$C_CYAN" "$custom_idx" "$C_RESET"
    printf "  %s%d.%s Custom Folder Path / Root (e.g. ./test-drive or specific directory)\n" "$C_CYAN" "$path_idx" "$C_RESET"
    print_divider

    local choice
    printf "%sSelect search target [1-%d] (Default: 1): %s" "$C_WHITE" "$path_idx" "$C_RESET"
    read -r choice
    choice="${choice:-1}"

    local targets=()
    if [ "$choice" = "1" ]; then
        targets=("${available_drives[@]}")
    elif [ "$choice" -ge 2 ] && [ "$choice" -lt "$custom_idx" ]; then
        local sel_idx=$((choice - 2))
        targets=("${available_drives[$sel_idx]}")
    elif [ "$choice" -eq "$custom_idx" ]; then
        printf "Enter comma-separated drive letters (e.g. C, D): "
        read -r raw_input
        IFS=',' read -ra split_drives <<< "$raw_input"
        for drv in "${split_drives[@]}"; do
            drv="$(echo "$drv" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
            drv="${drv%:}" # remove trailing colon if typed
            local ppath="/${drv,,}"
            if [ -d "$ppath" ]; then
                targets+=("$ppath")
            else
                warn "Drive $drv: not found or inaccessible at $ppath. Skipping."
            fi
        done
        [ ${#targets[@]} -eq 0 ] && targets=("${available_drives[@]}")
    elif [ "$choice" -eq "$path_idx" ]; then
        printf "Enter custom folder or drive path (POSIX or Windows format): "
        read -r raw_custom
        local posix_custom
        posix_custom="$(to_posix_path "$raw_custom")"
        if [ -d "$posix_custom" ]; then
            targets=("$posix_custom")
            success "Target set to: $posix_custom"
        else
            error "Directory does not exist: $posix_custom. Falling back to all drives."
            targets=("${available_drives[@]}")
        fi
    else
        warn "Invalid selection. Defaulting to all drives."
        targets=("${available_drives[@]}")
    fi

    # Output targets space-separated
    echo "${targets[*]}"
}

# ------------------------------------------------------------------------------
# Build Safe Find Pruning Arguments
# ------------------------------------------------------------------------------
# Generates find arguments to prune heavy/system directories based on CFG_EXCLUDE_DIRS
build_find_prune_args() {
    local prune_args=()
    if [ -n "$CFG_EXCLUDE_DIRS" ]; then
        IFS=',' read -ra exc_array <<< "$CFG_EXCLUDE_DIRS"
        local first=1
        prune_args+=("(")
        for item in "${exc_array[@]}"; do
            item="$(echo "$item" | tr -d '[:space:]')"
            [ -z "$item" ] && continue
            if [ "$first" -eq 1 ]; then
                prune_args+=("-name" "$item")
                first=0
            else
                prune_args+=("-o" "-name" "$item")
            fi
        done
        prune_args+=(")" "-prune" "-o")
    fi
    echo "${prune_args[@]}"
}

# ------------------------------------------------------------------------------
# Safe Scan Stream Generator
# ------------------------------------------------------------------------------
# Runs find safely across selected roots and outputs null-delimited or pipe-delimited records
# Handles permission errors, symlinks, and captures inaccessible errors
init_scan_log() {
    ensure_dir "$PROJECT_ROOT/data"
    : > "$SCAN_ERROR_LOG"
}

get_scan_error_count() {
    if [ -f "$SCAN_ERROR_LOG" ]; then
        wc -l < "$SCAN_ERROR_LOG" | tr -d '[:space:]'
    else
        echo "0"
    fi
}
