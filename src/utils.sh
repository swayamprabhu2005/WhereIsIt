#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: utils.sh
# Purpose: Shared utility functions, ANSI formatting, path helpers, safe I/O
# ==============================================================================

# Ensure bash version 4+
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "Error: 'Where Is It' requires Bash 4.0 or higher. Found: $BASH_VERSION" >&2
    exit 1
fi

# Determine project root directory dynamically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Global Application Information
APP_NAME="WHERE IS IT"
APP_SUBTITLE="Digital File System Investigator"
APP_VERSION="1.0.0"
APP_AUTHOR="Portfolio / College Project"

# ------------------------------------------------------------------------------
# ANSI Color Palette
# ------------------------------------------------------------------------------
init_colors() {
    local enable_color="${1:-1}"
    if [ "$enable_color" = "1" ] && [ -t 1 ]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_UNDER=$'\033[4m'
        
        # Foregrounds
        C_RED=$'\033[38;5;196m'
        C_GREEN=$'\033[38;5;46m'
        C_YELLOW=$'\033[38;5;226m'
        C_BLUE=$'\033[38;5;39m'
        C_MAGENTA=$'\033[38;5;201m'
        C_CYAN=$'\033[38;5;51m'
        C_WHITE=$'\033[38;5;231m'
        C_GRAY=$'\033[38;5;244m'
        C_DARK_GRAY=$'\033[38;5;239m'
        
        # Distinct accents
        C_ORANGE=$'\033[38;5;208m'
        C_PURPLE=$'\033[38;5;141m'
        C_TEAL=$'\033[38;5;37m'
    else
        C_RESET=""
        C_BOLD=""
        C_DIM=""
        C_UNDER=""
        C_RED=""
        C_GREEN=""
        C_YELLOW=""
        C_BLUE=""
        C_MAGENTA=""
        C_CYAN=""
        C_WHITE=""
        C_GRAY=""
        C_DARK_GRAY=""
        C_ORANGE=""
        C_PURPLE=""
        C_TEAL=""
    fi
}
init_colors 1

# ------------------------------------------------------------------------------
# Terminal Control & ASCII Banner
# ------------------------------------------------------------------------------
get_terminal_width() {
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    if [ "$cols" -lt 40 ]; then
        cols=80
    fi
    echo "$cols"
}

clear_screen() {
    clear 2>/dev/null || printf "\033c"
}

print_banner() {
    local cols
    cols=$(get_terminal_width)
    
    printf "%s%s" "$C_CYAN" "$C_BOLD"
    cat << "EOF"
  _       ____  __________  ______   _________   ________
 | |     / / / / / ____/ / / / ____/  /  _/ ___/  /  _/_  __/
 | | /| / / /_/ / __/ / /_/ / __/     / / \__ \   / /  / /   
 | |/ |/ / __  / /___/ _, _/ /___   _/ / ___/ / _/ /  / /    
 |__/|__/_/ /_/_____/_/ |_/_____/  /___//____/ /___/ /_/     
EOF
    printf "%s" "$C_RESET"
    
    printf "%s%s========================================================================%s\n" "$C_BLUE" "$C_BOLD" "$C_RESET"
    printf "%s%s  %s v%s - %s%s\n" "$C_WHITE" "$C_BOLD" "$APP_NAME" "$APP_VERSION" "$APP_SUBTITLE" "$C_RESET"
    printf "%s  Windows File System Investigation & Forensic Triage Utility (Git Bash)%s\n" "$C_GRAY" "$C_RESET"
    printf "%s%s========================================================================%s\n\n" "$C_BLUE" "$C_BOLD" "$C_RESET"
}

print_header() {
    local text="$1"
    printf "\n%s%s=== %s ===%s\n" "$C_CYAN" "$C_BOLD" "$text" "$C_RESET"
}

print_subheader() {
    local text="$1"
    printf "%s%s--- %s ---%s\n" "$C_BLUE" "$C_BOLD" "$text" "$C_RESET"
}

print_divider() {
    local cols
    cols=$(get_terminal_width)
    local width=72
    [ "$cols" -lt "$width" ] && width="$cols"
    local line
    line=$(printf '%*s' "$width" '' | tr ' ' '-')
    printf "%s%s%s\n" "$C_DARK_GRAY" "$line" "$C_RESET"
}

# ------------------------------------------------------------------------------
# Logging & Status Indicators
# ------------------------------------------------------------------------------
info() {
    printf "%s[INFO]%s %s\n" "$C_BLUE" "$C_RESET" "$*"
}

success() {
    printf "%s%s[SUCCESS]%s %s\n" "$C_GREEN" "$C_BOLD" "$C_RESET" "$*"
}

warn() {
    printf "%s%s[WARNING]%s %s\n" "$C_YELLOW" "$C_BOLD" "$C_RESET" "$*"
}

error() {
    printf "%s%s[ERROR]%s %s\n" "$C_RED" "$C_BOLD" "$C_RESET" "$*" >&2
}

search_status() {
    printf "%s[*]%s %s\n" "$C_CYAN" "$C_RESET" "$*"
}

# ------------------------------------------------------------------------------
# Path Conversion Helpers (POSIX <-> Windows)
# ------------------------------------------------------------------------------
# Converts Windows path (e.g. C:\Users or C:/Users) to POSIX (/c/Users)
to_posix_path() {
    local win_path="$1"
    [ -z "$win_path" ] && echo "" && return 0

    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$win_path" 2>/dev/null && return 0
    fi

    # Pure-bash fallback
    local posix_path="$win_path"
    # Replace backslashes with forward slashes
    posix_path="${posix_path//\\//}"
    # Replace C: with /c
    if [[ "$posix_path" =~ ^([a-zA-Z]):/(.*)$ ]]; then
        local drive="${BASH_REMATCH[1],,}"
        local rest="${BASH_REMATCH[2]}"
        posix_path="/$drive/$rest"
    elif [[ "$posix_path" =~ ^([a-zA-Z]):$ ]]; then
        local drive="${BASH_REMATCH[1],,}"
        posix_path="/$drive"
    fi
    echo "$posix_path"
}

# Converts POSIX path (e.g. /c/Users or ./relative) to Windows (C:\Users)
to_win_path() {
    local posix_path="$1"
    [ -z "$posix_path" ] && echo "" && return 0

    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$posix_path" 2>/dev/null && return 0
    fi

    # Pure-bash fallback
    local win_path="$posix_path"
    if [[ "$win_path" =~ ^/([a-zA-Z])/(.*)$ ]]; then
        local drive="${BASH_REMATCH[1]^^}"
        local rest="${BASH_REMATCH[2]}"
        win_path="${drive}:/${rest}"
    elif [[ "$win_path" =~ ^/([a-zA-Z])$ ]]; then
        local drive="${BASH_REMATCH[1]^^}"
        win_path="${drive}:\\"
    fi
    win_path="${win_path//\//\\}"
    echo "$win_path"
}

# Extracts filename extension safely in lowercase (e.g., "report.PDF" -> "pdf")
get_file_extension() {
    local filename
    filename="$(basename "$1")"
    if [[ "$filename" == *.* ]] && [[ "$filename" != .* ]]; then
        local ext="${filename##*.}"
        echo "${ext,,}"
    elif [[ "$filename" =~ ^\.[^.]+\.(.*)$ ]]; then
        local ext="${filename##*.}"
        echo "${ext,,}"
    else
        echo ""
    fi
}

# ------------------------------------------------------------------------------
# Formatting Utilities
# ------------------------------------------------------------------------------
# Formats raw bytes to human-readable B, KB, MB, GB, TB
format_bytes() {
    local bytes="${1:-0}"
    # Ensure bytes is an integer
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return
    fi

    awk -v b="$bytes" 'BEGIN {
        if (b < 1024) {
            printf "%d B\n", b
        } else if (b < 1048576) {
            printf "%.2f KB\n", b / 1024
        } else if (b < 1073741824) {
            printf "%.2f MB\n", b / 1048576
        } else if (b < 1099511627776) {
            printf "%.2f GB\n", b / 1073741824
        } else {
            printf "%.2f TB\n", b / 1099511627776
        }
    }'
}

# Formats epoch seconds to readable ISO 8601 string: YYYY-MM-DD HH:MM:SS
format_epoch() {
    local epoch="$1"
    if [[ "$epoch" =~ ^[0-9]+$ ]] && [ "$epoch" -gt 0 ]; then
        date -d "@$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown"
    else
        echo "N/A"
    fi
}

# RFC 4180 CSV escaping for reliable CSV export
escape_csv_field() {
    local field="$1"
    # Replace all double-quotes with two double-quotes
    local escaped="${field//\"/\"\"}"
    # Always enclose in double-quotes to be safe against commas, quotes, and newlines
    printf '"%s"' "$escaped"
}

# ------------------------------------------------------------------------------
# User Prompts & Input Helpers
# ------------------------------------------------------------------------------
prompt_input() {
    local prompt_msg="$1"
    local default_val="$2"
    local user_val=""

    if [ -n "$default_val" ]; then
        printf "%s%s%s [%s%s%s]: " "$C_WHITE" "$prompt_msg" "$C_RESET" "$C_YELLOW" "$default_val" "$C_RESET"
    else
        printf "%s%s%s: " "$C_WHITE" "$prompt_msg" "$C_RESET"
    fi

    read -r user_val
    if [ -z "$user_val" ]; then
        echo "$default_val"
    else
        echo "$user_val"
    fi
}

prompt_confirm() {
    local prompt_msg="$1"
    local default_ans="${2:-Y}" # Y or N
    local prompt_suffix="[Y/n]"
    [ "${default_ans^^}" = "N" ] && prompt_suffix="[y/N]"

    printf "%s%s%s %s%s%s: " "$C_YELLOW" "$prompt_msg" "$C_RESET" "$C_CYAN" "$prompt_suffix" "$C_RESET"
    read -r ans
    ans="${ans:-$default_ans}"
    case "${ans^^}" in
        Y|YES) return 0 ;;
        *) return 1 ;;
    esac
}

press_enter_to_continue() {
    if [ ! -t 0 ] || [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        return 0
    fi
    printf "\n%sPress [Enter] to continue...%s" "$C_GRAY" "$C_RESET"
    read -r _
}

# ------------------------------------------------------------------------------
# Directory & File Helpers
# ------------------------------------------------------------------------------
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" 2>/dev/null || {
            error "Failed to create directory: $dir"
            return 1
        }
    fi
}

# Generates clean, timestamped filenames (e.g. 20261107_134522)
get_timestamp() {
    date "+%Y%m%d_%H%M%S"
}

get_display_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}
