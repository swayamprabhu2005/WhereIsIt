#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: settings.sh
# Purpose: Configuration management, default preferences, interactive setup
# ==============================================================================

# Source utils if not already sourced
if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
fi

SETTINGS_FILE="$PROJECT_ROOT/data/settings.conf"

# Default configuration values
DEFAULT_COLOR_ENABLED=1
DEFAULT_MAX_RESULTS=500
DEFAULT_CASE_SENSITIVE=0
DEFAULT_FOLLOW_SYMLINKS=0
DEFAULT_DEFAULT_DRIVE="auto"
DEFAULT_EXCLUDE_DIRS=".git,.svn,\$RECYCLE.BIN,System Volume Information,node_modules"
DEFAULT_REPORT_FORMAT="txt"
DEFAULT_CALC_HASH_ON_INSPECT=1

# Current runtime configuration variables
CFG_COLOR_ENABLED=$DEFAULT_COLOR_ENABLED
CFG_MAX_RESULTS=$DEFAULT_MAX_RESULTS
CFG_CASE_SENSITIVE=$DEFAULT_CASE_SENSITIVE
CFG_FOLLOW_SYMLINKS=$DEFAULT_FOLLOW_SYMLINKS
CFG_DEFAULT_DRIVE=$DEFAULT_DEFAULT_DRIVE
CFG_EXCLUDE_DIRS=$DEFAULT_EXCLUDE_DIRS
CFG_REPORT_FORMAT=$DEFAULT_REPORT_FORMAT
CFG_CALC_HASH_ON_INSPECT=$DEFAULT_CALC_HASH_ON_INSPECT

# ------------------------------------------------------------------------------
# Initialize and Load Configuration
# ------------------------------------------------------------------------------
init_settings() {
    ensure_dir "$PROJECT_ROOT/data"
    if [ ! -f "$SETTINGS_FILE" ]; then
        save_settings
    else
        load_settings
    fi
}

save_settings() {
    ensure_dir "$PROJECT_ROOT/data"
    cat > "$SETTINGS_FILE" << EOF
# Where Is It - Configuration File
# Automatically updated by Settings Manager
COLOR_ENABLED=$CFG_COLOR_ENABLED
MAX_RESULTS=$CFG_MAX_RESULTS
CASE_SENSITIVE=$CFG_CASE_SENSITIVE
FOLLOW_SYMLINKS=$CFG_FOLLOW_SYMLINKS
DEFAULT_DRIVE=$CFG_DEFAULT_DRIVE
EXCLUDE_DIRS=$CFG_EXCLUDE_DIRS
REPORT_FORMAT=$CFG_REPORT_FORMAT
CALC_HASH_ON_INSPECT=$CFG_CALC_HASH_ON_INSPECT
EOF
}

load_settings() {
    if [ -f "$SETTINGS_FILE" ]; then
        while IFS='=' read -r key val || [ -n "$key" ]; do
            # Trim whitespace and skip comments/empty lines
            key="$(echo "$key" | tr -d '[:space:]')"
            [[ "$key" =~ ^#.*$ ]] && continue
            [ -z "$key" ] && continue
            val="${val%"${val##*[![:space:]]}"}" # trim trailing whitespace
            val="${val#"${val%%[![:space:]]*}"}" # trim leading whitespace
            
            case "$key" in
                COLOR_ENABLED) CFG_COLOR_ENABLED="$val" ;;
                MAX_RESULTS) CFG_MAX_RESULTS="$val" ;;
                CASE_SENSITIVE) CFG_CASE_SENSITIVE="$val" ;;
                FOLLOW_SYMLINKS) CFG_FOLLOW_SYMLINKS="$val" ;;
                DEFAULT_DRIVE) CFG_DEFAULT_DRIVE="$val" ;;
                EXCLUDE_DIRS) CFG_EXCLUDE_DIRS="$val" ;;
                REPORT_FORMAT) CFG_REPORT_FORMAT="$val" ;;
                CALC_HASH_ON_INSPECT) CFG_CALC_HASH_ON_INSPECT="$val" ;;
            esac
        done < "$SETTINGS_FILE"
    fi
    init_colors "$CFG_COLOR_ENABLED"
}

reset_settings_to_default() {
    CFG_COLOR_ENABLED=$DEFAULT_COLOR_ENABLED
    CFG_MAX_RESULTS=$DEFAULT_MAX_RESULTS
    CFG_CASE_SENSITIVE=$DEFAULT_CASE_SENSITIVE
    CFG_FOLLOW_SYMLINKS=$DEFAULT_FOLLOW_SYMLINKS
    CFG_DEFAULT_DRIVE=$DEFAULT_DEFAULT_DRIVE
    CFG_EXCLUDE_DIRS=$DEFAULT_EXCLUDE_DIRS
    CFG_REPORT_FORMAT=$DEFAULT_REPORT_FORMAT
    CFG_CALC_HASH_ON_INSPECT=$DEFAULT_CALC_HASH_ON_INSPECT
    save_settings
    init_colors "$CFG_COLOR_ENABLED"
    success "Settings have been reset to factory defaults."
}

# ------------------------------------------------------------------------------
# Interactive Settings Menu
# ------------------------------------------------------------------------------
settings_menu() {
    while true; do
        clear_screen
        print_banner
        print_header "APPLICATION SETTINGS"
        
        printf "  %s1.%s Color Output:             %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ "$CFG_COLOR_ENABLED" = "1" ] && echo "Enabled" || echo "Disabled")" "$C_RESET"
        printf "  %s2.%s Maximum Search Results:   %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$CFG_MAX_RESULTS" "$C_RESET"
        printf "  %s3.%s Default Case Sensitivity: %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ "$CFG_CASE_SENSITIVE" = "1" ] && echo "Case-Sensitive" || echo "Case-Insensitive")" "$C_RESET"
        printf "  %s4.%s Follow Symlinks/Junctions:%s%s%s (Default: Disabled for safety)\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ "$CFG_FOLLOW_SYMLINKS" = "1" ] && echo "Enabled" || echo "Disabled")" "$C_RESET"
        printf "  %s5.%s Default Drive Selection:  %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$CFG_DEFAULT_DRIVE" "$C_RESET"
        printf "  %s6.%s Excluded Directories:     %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$CFG_EXCLUDE_DIRS" "$C_RESET"
        printf "  %s7.%s Default Report Format:    %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "${CFG_REPORT_FORMAT^^}" "$C_RESET"
        printf "  %s8.%s Auto-Hash on Inspect:     %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ "$CFG_CALC_HASH_ON_INSPECT" = "1" ] && echo "Enabled" || echo "Disabled")" "$C_RESET"
        print_divider
        printf "  %s9.%s Reset to Defaults\n" "$C_CYAN" "$C_RESET"
        printf "  %s0.%s Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect an option [0-9]: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "$choice" in
            1)
                if [ "$CFG_COLOR_ENABLED" = "1" ]; then
                    CFG_COLOR_ENABLED=0
                else
                    CFG_COLOR_ENABLED=1
                fi
                init_colors "$CFG_COLOR_ENABLED"
                save_settings
                ;;
            2)
                printf "Enter maximum results limit (e.g., 100, 500, 1000, 5000): "
                read -r new_max
                if [[ "$new_max" =~ ^[0-9]+$ ]] && [ "$new_max" -gt 0 ]; then
                    CFG_MAX_RESULTS="$new_max"
                    save_settings
                    success "Max results set to $new_max"
                else
                    error "Invalid number entered."
                fi
                sleep 1
                ;;
            3)
                if [ "$CFG_CASE_SENSITIVE" = "1" ]; then
                    CFG_CASE_SENSITIVE=0
                else
                    CFG_CASE_SENSITIVE=1
                fi
                save_settings
                ;;
            4)
                if [ "$CFG_FOLLOW_SYMLINKS" = "1" ]; then
                    CFG_FOLLOW_SYMLINKS=0
                    save_settings
                else
                    warn "Enabling symlink traversal may cause infinite recursion or slow scans."
                    if prompt_confirm "Are you sure you want to follow symlinks?" "N"; then
                        CFG_FOLLOW_SYMLINKS=1
                        save_settings
                    fi
                fi
                ;;
            5)
                printf "Enter default drive mode ('auto', 'all', or comma-separated letters e.g. 'c,d'): "
                read -r new_drive
                if [ -n "$new_drive" ]; then
                    CFG_DEFAULT_DRIVE="$new_drive"
                    save_settings
                    success "Default drive set to: $new_drive"
                fi
                sleep 1
                ;;
            6)
                printf "Enter comma-separated folder names to exclude:\n(Current: %s)\n> " "$CFG_EXCLUDE_DIRS"
                read -r new_exc
                if [ -n "$new_exc" ]; then
                    CFG_EXCLUDE_DIRS="$new_exc"
                    save_settings
                    success "Exclude list updated."
                fi
                sleep 1
                ;;
            7)
                if [ "${CFG_REPORT_FORMAT,,}" = "txt" ]; then
                    CFG_REPORT_FORMAT="csv"
                else
                    CFG_REPORT_FORMAT="txt"
                fi
                save_settings
                ;;
            8)
                if [ "$CFG_CALC_HASH_ON_INSPECT" = "1" ]; then
                    CFG_CALC_HASH_ON_INSPECT=0
                else
                    CFG_CALC_HASH_ON_INSPECT=1
                fi
                save_settings
                ;;
            9)
                if prompt_confirm "Reset all settings to default?" "N"; then
                    reset_settings_to_default
                    sleep 1
                fi
                ;;
            0)
                break
                ;;
            *)
                warn "Invalid selection. Please choose an option between 0 and 9."
                sleep 1
                ;;
        esac
    done
}

# Auto-initialize on source
init_settings
