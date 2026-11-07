#!/usr/bin/env bash
# ==============================================================================
# WHERE IS IT - Standalone Digital File System Investigator
# Main Application Entry Point & Interactive TUI
# ==============================================================================

# Ensure Bash 4.0+
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "Error: 'Where Is It' requires Bash 4.0 or higher." >&2
    exit 1
fi

# Determine project root directory dynamically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export PROJECT_ROOT

# Source application modules
# shellcheck source=src/utils.sh
source "$SCRIPT_DIR/utils.sh"
# shellcheck source=src/settings.sh
source "$SCRIPT_DIR/settings.sh"
# shellcheck source=src/scanner.sh
source "$SCRIPT_DIR/scanner.sh"
# shellcheck source=src/search.sh
source "$SCRIPT_DIR/search.sh"
# shellcheck source=src/filters.sh
source "$SCRIPT_DIR/filters.sh"
# shellcheck source=src/inspector.sh
source "$SCRIPT_DIR/inspector.sh"
# shellcheck source=src/duplicates.sh
source "$SCRIPT_DIR/duplicates.sh"
# shellcheck source=src/application.sh
source "$SCRIPT_DIR/application.sh"
# shellcheck source=src/indexer.sh
source "$SCRIPT_DIR/indexer.sh"
# shellcheck source=src/history.sh
source "$SCRIPT_DIR/history.sh"
# shellcheck source=src/bookmarks.sh
source "$SCRIPT_DIR/bookmarks.sh"
# shellcheck source=src/timeline.sh
source "$SCRIPT_DIR/timeline.sh"
# shellcheck source=src/comparison.sh
source "$SCRIPT_DIR/comparison.sh"
# shellcheck source=src/reporter.sh
source "$SCRIPT_DIR/reporter.sh"

# Signal trap for graceful interruption
cleanup_on_exit() {
    printf "\n%s[!] Interrupted by user. Cleaning up session...%s\n" "$C_YELLOW" "$C_RESET"
    rm -f "$PROJECT_ROOT/data/tmp_"* 2>/dev/null
    exit 0
}
trap cleanup_on_exit SIGINT SIGTERM

# ------------------------------------------------------------------------------
# Help & CLI Argument Handler
# ------------------------------------------------------------------------------
show_help() {
    print_banner
    cat << EOF
Usage: $0 [OPTIONS]

Interactive Mode:
  Run without options to launch the interactive menu interface.

CLI Automation Options:
  -s, --search <KEYWORD>    Search files and folders matching keyword
  -t, --type <TYPE>         Search type: 'file', 'folder', or 'all' (default: all)
  -r, --root <PATH>         Specify target search path or drive (e.g. /c, C:, ./test-drive)
  -e, --exact               Enable exact filename matching
  -d, --duplicates <PATH>   Run duplicate file detector on target path
  -a, --app <NAME>          Run Application Footprint Explorer for named app
  -i, --inspect <PATH>      Inspect full metadata for a specific file or folder
  -c, --compare             Launch snapshot comparison module
  -h, --help                Display this assistance documentation
  -v, --version             Display version information

Examples:
  bash src/main.sh
  bash src/main.sh --search Chrome --type file
  bash src/main.sh --duplicates /c/Users
  bash src/main.sh --app "Visual Studio Code"
  bash src/main.sh --inspect "C:\\Windows\\notepad.exe"
EOF
}

parse_cli_args() {
    local kw=""
    local stype="all"
    local sroot="auto"
    local sexact=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -s|--search)
                kw="$2"
                shift 2
                ;;
            -t|--type)
                stype="$2"
                shift 2
                ;;
            -r|--root)
                sroot="$(to_posix_path "$2")"
                shift 2
                ;;
            -e|--exact)
                sexact=1
                shift
                ;;
            -d|--duplicates)
                local d_target
                d_target="$(to_posix_path "$2")"
                run_duplicate_detector "$d_target"
                exit 0
                ;;
            -a|--app)
                run_application_investigation "$2" "$2"
                exit 0
                ;;
            -i|--inspect)
                local i_target
                i_target="$(to_posix_path "$2")"
                inspect_metadata "$i_target"
                exit 0
                ;;
            -c|--compare)
                comparison_menu
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "$APP_NAME version $APP_VERSION"
                exit 0
                ;;
            *)
                error "Unknown command-line argument: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [ -n "$kw" ]; then
        run_search "$kw" "$stype" "$sexact" "$sroot" 1
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# Main Interactive Menu Loop
# ------------------------------------------------------------------------------
main_menu() {
    while true; do
        clear_screen
        print_banner
        
        printf "%s========================================%s\n" "$C_CYAN" "$C_RESET"
        printf "             %s%sWHERE IS IT%s\n" "$C_WHITE" "$C_BOLD" "$C_RESET"
        printf "       %sDIGITAL FILE INVESTIGATOR%s\n" "$C_GRAY" "$C_RESET"
        printf "%s========================================%s\n\n" "$C_CYAN" "$C_RESET"

        printf "  %s1.%s Search Files\n" "$C_CYAN" "$C_RESET"
        printf "  %s2.%s Search Folders\n" "$C_CYAN" "$C_RESET"
        printf "  %s3.%s Search All Drives\n" "$C_CYAN" "$C_RESET"
        printf "  %s4.%s Advanced Search\n" "$C_CYAN" "$C_RESET"
        printf "  %s5.%s Application Footprint Explorer\n" "$C_CYAN" "$C_RESET"
        printf "  %s6.%s Duplicate File Finder\n" "$C_CYAN" "$C_RESET"
        printf "  %s7.%s File Information Inspector\n" "$C_CYAN" "$C_RESET"
        printf "  %s8.%s Search History\n" "$C_CYAN" "$C_RESET"
        printf "  %s9.%s Manage Search Index\n" "$C_CYAN" "$C_RESET"
        printf "  %s10.%s Investigation Reports\n" "$C_CYAN" "$C_RESET"
        printf "  %s11.%s Settings\n" "$C_CYAN" "$C_RESET"
        printf "  %s12.%s Exit\n" "$C_RED" "$C_RESET"
        print_divider
        printf "  %s[T]%s File Timeline | %s[B]%s Bookmarks | %s[C]%s Snapshot Compare\n" \
            "$C_PURPLE" "$C_RESET" "$C_PURPLE" "$C_RESET" "$C_PURPLE" "$C_RESET"
        print_divider

        printf "%sSelect an option: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "${choice^^}" in
            1)
                printf "Enter file name or keyword to search: "
                read -r kw
                if [ -n "$kw" ]; then
                    run_search "$kw" "file" 0 "auto" 1
                fi
                ;;
            2)
                printf "Enter folder name or keyword to search: "
                read -r kw
                if [ -n "$kw" ]; then
                    run_search "$kw" "folder" 0 "auto" 1
                fi
                ;;
            3)
                printf "Enter keyword to search across all available drives: "
                read -r kw
                if [ -n "$kw" ]; then
                    local all_drives
                    all_drives="$(detect_available_drives)"
                    run_search "$kw" "all" 0 "$all_drives" 1
                fi
                ;;
            4)
                advanced_search_menu
                ;;
            5)
                application_footprint_menu
                ;;
            6)
                run_duplicate_detector "auto"
                ;;
            7)
                printf "Enter file or folder path to inspect (POSIX or Windows format): "
                read -r ins_path
                if [ -n "$ins_path" ]; then
                    inspect_metadata "$ins_path"
                fi
                ;;
            8)
                history_menu
                ;;
            9)
                manage_index_menu
                ;;
            10)
                export_report_menu "Investigation"
                ;;
            11)
                settings_menu
                ;;
            12|Q|EXIT)
                clear_screen
                printf "%s%sThank you for using Where Is It - Digital File System Investigator.%s\n\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
                exit 0
                ;;
            T)
                timeline_menu
                ;;
            B)
                bookmarks_menu
                ;;
            C)
                comparison_menu
                ;;
            *)
                warn "Invalid selection. Please choose an option from the menu."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    parse_cli_args "$@"
else
    main_menu
fi
