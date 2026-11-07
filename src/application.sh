#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: application.sh
# Purpose: Application Footprint Explorer (Windows standard paths & forensic categorization)
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
    # shellcheck source=src/scanner.sh
    source "$SCRIPT_DIR/scanner.sh"
    # shellcheck source=src/inspector.sh
    source "$SCRIPT_DIR/inspector.sh"
fi

APP_FOOTPRINT_REPORT="$PROJECT_ROOT/reports/app_footprint_report.txt"

# ------------------------------------------------------------------------------
# Application Footprint Explorer Menu & Presets
# ------------------------------------------------------------------------------
application_footprint_menu() {
    while true; do
        clear_screen
        print_banner
        print_header "APPLICATION FOOTPRINT EXPLORER"
        printf "Investigate application footprints across Windows installations, user profiles, caches, and storage.\n\n"

        printf "  %s1.%s Google Chrome\n" "$C_CYAN" "$C_RESET"
        printf "  %s2.%s Mozilla Firefox\n" "$C_CYAN" "$C_RESET"
        printf "  %s3.%s Microsoft Edge\n" "$C_CYAN" "$C_RESET"
        printf "  %s4.%s Visual Studio Code (VS Code)\n" "$C_CYAN" "$C_RESET"
        printf "  %s5.%s Discord\n" "$C_CYAN" "$C_RESET"
        printf "  %s6.%s Steam\n" "$C_CYAN" "$C_RESET"
        printf "  %s7.%s Spotify\n" "$C_CYAN" "$C_RESET"
        printf "  %s8.%s Git / Git Bash\n" "$C_CYAN" "$C_RESET"
        printf "  %s9.%s Custom Application Name / Keyword\n" "$C_CYAN" "$C_RESET"
        print_divider
        printf "  %s0.%s Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect application preset [0-9]: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "$choice" in
            1) run_application_investigation "Chrome" "Google/Chrome" ;;
            2) run_application_investigation "Firefox" "Mozilla/Firefox" ;;
            3) run_application_investigation "Edge" "Microsoft/Edge" ;;
            4) run_application_investigation "Code" "Microsoft VS Code" ;;
            5) run_application_investigation "Discord" "Discord" ;;
            6) run_application_investigation "Steam" "Steam" ;;
            7) run_application_investigation "Spotify" "Spotify" ;;
            8) run_application_investigation "Git" "Git" ;;
            9)
                printf "Enter application name or keyword to investigate: "
                read -r custom_app
                if [ -n "$custom_app" ]; then
                    run_application_investigation "$custom_app" "$custom_app"
                fi
                ;;
            0) break ;;
            *) warn "Invalid selection." ; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Footprint Investigation Engine
# ------------------------------------------------------------------------------
run_application_investigation() {
    local app_name="$1"
    local app_keyword="$2"

    clear_screen
    print_banner
    print_header "FOOTPRINT AUDIT: '$app_name'"
    info "Investigating standard Windows locations and additional attached drives..."
    printf "%sForensic Notice:%s Findings are categorized by filesystem location role.\n" "$C_GRAY" "$C_RESET"
    printf "%sDistinction:%s [CONFIRMED] indicates direct name match; [INFERRED] indicates association by container path.\n\n" "$C_GRAY" "$C_RESET"

    # Identify candidate scan roots
    local candidate_roots=()
    
    # 1. Standard Program Files
    [ -d "/c/Program Files" ] && candidate_roots+=("/c/Program Files")
    [ -d "/c/Program Files (x86)" ] && candidate_roots+=("/c/Program Files (x86)")
    [ -d "/c/ProgramData" ] && candidate_roots+=("/c/ProgramData")

    # 2. User AppData, Downloads, Documents
    if [ -d "/c/Users" ]; then
        for u in /c/Users/*; do
            [ ! -d "$u" ] && continue
            local uname
            uname="$(basename "$u")"
            [[ "$uname" =~ ^(All Users|Default|Default User|Public)$ ]] && continue
            
            [ -d "$u/AppData/Local" ] && candidate_roots+=("$u/AppData/Local")
            [ -d "$u/AppData/Roaming" ] && candidate_roots+=("$u/AppData/Roaming")
            [ -d "$u/Downloads" ] && candidate_roots+=("$u/Downloads")
        done
    fi

    # 3. Secondary drives if available (e.g. /d, /e)
    for alt in /d /e; do
        if [ -d "$alt" ] && [ "$alt" != "/" ]; then
            candidate_roots+=("$alt")
        fi
    done

    # If in test environment (e.g. ./test-drive exists)
    if [ -d "$PROJECT_ROOT/test-drive" ]; then
        candidate_roots+=("$PROJECT_ROOT/test-drive")
    fi

    info "Identified ${#candidate_roots[@]} investigation probe zones."

    local temp_app_raw="$PROJECT_ROOT/data/tmp_app_raw.tsv"
    ensure_dir "$PROJECT_ROOT/data"
    : > "$temp_app_raw"

    local symlink_flag="-P"
    [ "$CFG_FOLLOW_SYMLINKS" = "1" ] && symlink_flag="-L"

    init_scan_log
    local start_time
    start_time=$(date +%s)

    # Search for items matching app name or keyword
    for root_zone in "${candidate_roots[@]}"; do
        search_status "Probing zone: $root_zone"
        find "$symlink_flag" "$root_zone" -maxdepth 5 \
            -iname "*${app_name}*" \
            -printf '%y|%s|%T@|%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_app_raw"
    done

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    # Categorize findings
    # Categories:
    # 1. INSTALLATION
    # 2. USER DATA
    # 3. CACHE & LOGS
    # 4. CONFIG & PREFERENCES
    # 5. BACKUPS & INSTALLERS
    # 6. OTHER
    local temp_app_categorized="$PROJECT_ROOT/data/tmp_app_cat.tsv"
    : > "$temp_app_categorized"

    local total_app_items=0
    local count_install=0
    local count_userdata=0
    local count_cache=0
    local count_config=0
    local count_installers=0
    local count_other=0

    while IFS='|' read -r itype isize imtime ipath || [ -n "$ipath" ]; do
        [ -z "$ipath" ] && continue
        total_app_items=$((total_app_items + 1))

        local ipath_lower="${ipath,,}"
        local bname
        bname="$(basename "$ipath")"
        local bname_lower="${bname,,}"
        local category="OTHER"
        local status="INFERRED"

        # Check confirmed vs inferred
        if [[ "$bname_lower" == "${app_name,,}"* ]] || [[ "$bname_lower" == *"${app_name,,}"* ]]; then
            status="CONFIRMED"
        fi

        # Categorize
        if [[ "$ipath_lower" =~ /program\ files|/program\ files\ \(x86\)|/appdata/local/programs ]]; then
            category="INSTALLATION"
            count_install=$((count_install + 1))
        elif [[ "$ipath_lower" =~ /cache|/code\ cache|/gpucache|/crashpad|/crashdumps|/logs ]]; then
            category="CACHE & LOGS"
            count_cache=$((count_cache + 1))
        elif [[ "$bname_lower" =~ \.(ini|json|xml|yaml|yml|cfg|conf|pref|preferences)$ ]] || [[ "$bname_lower" =~ settings|config|user\ data ]]; then
            category="CONFIG & SETTINGS"
            count_config=$((count_config + 1))
        elif [[ "$bname_lower" =~ \.(exe|msi|iso|zip|tar\.gz)$ ]] && [[ "$ipath_lower" =~ /downloads|/backup|installer|setup ]]; then
            category="INSTALLER & BACKUP"
            count_installers=$((count_installers + 1))
        elif [[ "$ipath_lower" =~ /appdata/roaming|/appdata/local ]]; then
            category="USER DATA"
            count_userdata=$((count_userdata + 1))
        else
            category="OTHER"
            count_other=$((count_other + 1))
        fi

        local mtime_int="${imtime%.*}"
        local win_path
        win_path="$(to_win_path "$ipath")"

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$category" "$status" "$itype" "$bname" "$isize" "$mtime_int" "$win_path" "$ipath" >> "$temp_app_categorized"
    done < "$temp_app_raw"

    rm -f "$temp_app_raw"

    # Display Footprint Summary
    clear_screen
    print_banner
    print_header "APPLICATION FOOTPRINT AUDIT RESULTS: '$app_name'"
    
    printf "%sDiscovered %d application-associated footprint locations in %d second(s):%s\n\n" \
        "$C_GREEN" "$total_app_items" "$elapsed" "$C_RESET"

    printf "  %s* Installation Binaries & Folders:%s  %d items\n" "$C_CYAN" "$C_RESET" "$count_install"
    printf "  %s* User Data & Profiles:%s            %d items\n" "$C_BLUE" "$C_RESET" "$count_userdata"
    printf "  %s* Cache, Dumps & Logs:%s             %d items\n" "$C_YELLOW" "$C_RESET" "$count_cache"
    printf "  %s* Configurations & Preferences:%s    %d items\n" "$C_MAGENTA" "$C_RESET" "$count_config"
    printf "  %s* Installers & Backups:%s            %d items\n" "$C_ORANGE" "$C_RESET" "$count_installers"
    printf "  %s* Other Identified Items:%s          %d items\n" "$C_GRAY" "$C_RESET" "$count_other"
    print_divider

    if [ "$total_app_items" -eq 0 ]; then
        info "No footprint items discovered for '$app_name'."
        rm -f "$temp_app_categorized"
        press_enter_to_continue
        return 0
    fi

    # Display grouped preview
    printf "%s%-20s %-12s %-6s %-10s %s%s\n" \
        "$C_BOLD$C_BLUE" "Category" "Match Type" "Type" "Size" "Path" "$C_RESET"
    print_divider

    local shown=0
    while IFS=$'\t' read -r cat stat itype bname isize mtime_int win_path ipath || [ -n "$ipath" ]; do
        [ -z "$ipath" ] && continue
        shown=$((shown + 1))

        local type_str="[FILE]"
        [ "$itype" = "d" ] && type_str="[DIR] "

        local h_size="---"
        [ "$itype" = "f" ] && h_size="$(format_bytes "$isize")"

        local stat_badge="$C_GREEN$stat$C_RESET"
        [ "$stat" = "INFERRED" ] && stat_badge="$C_GRAY$stat$C_RESET"

        printf "%s%-20s%s %-12s %-6s %-10s %s%s%s\n" \
            "$C_CYAN" "$cat" "$C_RESET" \
            "$stat_badge" "$type_str" "$h_size" \
            "$C_WHITE" "$win_path" "$C_RESET"

        if [ "$shown" -ge 35 ]; then
            printf "%s... [Showing first 35 items. Export report to inspect all %d locations] ...%s\n" "$C_YELLOW" "$total_app_items" "$C_RESET"
            break
        fi
    done < "$temp_app_categorized"

    print_divider
    printf "%sActions:%s [E] Export Footprint Report | [M] Back\n" "$C_BOLD" "$C_RESET"
    printf "Select option: "
    read -r app_act
    if [ "${app_act^^}" = "E" ]; then
        ensure_dir "$PROJECT_ROOT/reports"
        local rep_file="$PROJECT_ROOT/reports/APP_FOOTPRINT_${app_name}_$(get_timestamp).txt"
        {
            echo "================================================================================"
            echo "WHERE IS IT - APPLICATION FOOTPRINT AUDIT REPORT"
            echo "Application: $app_name"
            echo "Investigation Timestamp: $(get_display_timestamp)"
            echo "Total Footprint Items:   $total_app_items"
            echo "Category Breakdown:"
            echo "  * Installation:      $count_install"
            echo "  * User Data:         $count_userdata"
            echo "  * Cache & Logs:      $count_cache"
            echo "  * Config & Settings: $count_config"
            echo "  * Installers:        $count_installers"
            echo "  * Other:             $count_other"
            echo "================================================================================"
            echo ""
            printf "%-22s %-12s %-6s %-12s %s\n" "CATEGORY" "MATCH" "TYPE" "SIZE" "PATH"
            printf "%s\n" "--------------------------------------------------------------------------------"
            while IFS=$'\t' read -r cat stat itype bname isize mtime_int win_path ipath; do
                local sz="---"
                [ "$itype" = "f" ] && sz="$(format_bytes "$isize")"
                printf "%-22s %-12s %-6s %-12s %s\n" "$cat" "$stat" "$itype" "$sz" "$win_path"
            done < "$temp_app_categorized"
        } > "$rep_file"
        success "Report saved to: $(to_win_path "$rep_file")"
        press_enter_to_continue
    fi

    rm -f "$temp_app_categorized"
}
