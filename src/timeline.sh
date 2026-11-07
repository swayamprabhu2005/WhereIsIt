#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: timeline.sh
# Purpose: Chronological file activity timelines & recent modification tracking
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

# ------------------------------------------------------------------------------
# Timeline Menu
# ------------------------------------------------------------------------------
timeline_menu() {
    while true; do
        clear_screen
        print_banner
        print_header "FILE SYSTEM CHRONOLOGICAL TIMELINE"
        printf "Reconstruct chronological timelines of file modifications and discovery activity.\n\n"

        printf "  %s1.%s Recent Files Timeline (Last 24 Hours)\n" "$C_CYAN" "$C_RESET"
        printf "  %s2.%s Recent Files Timeline (Last 7 Days)\n" "$C_CYAN" "$C_RESET"
        printf "  %s3.%s Recent Files Timeline (Last 30 Days)\n" "$C_CYAN" "$C_RESET"
        printf "  %s4.%s Custom Scope Timeline Scan\n" "$C_CYAN" "$C_RESET"
        printf "  %s5.%s Generate Timeline from Last Search Results\n" "$C_CYAN" "$C_RESET"
        print_divider
        printf "  %s0.%s Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect timeline mode [0-5]: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "$choice" in
            1) run_timeline_scan 1 ;;
            2) run_timeline_scan 7 ;;
            3) run_timeline_scan 30 ;;
            4)
                printf "Enter modification window in days (e.g. 3, 14, 60): "
                read -r custom_days
                if [[ "$custom_days" =~ ^[0-9]+$ ]] && [ "$custom_days" -gt 0 ]; then
                    run_timeline_scan "$custom_days"
                else
                    error "Invalid number of days."
                    sleep 1
                fi
                ;;
            5)
                local res_file="$PROJECT_ROOT/data/last_search_results.tsv"
                display_timeline_from_results "$res_file" "Last Search"
                ;;
            0) break ;;
            *) warn "Invalid selection." ; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Run Targeted Timeline Scan
# ------------------------------------------------------------------------------
run_timeline_scan() {
    local days="$1"

    read -r -a roots <<< "$(select_scan_targets)"
    if [ ${#roots[@]} -eq 0 ]; then
        error "No targets selected."
        press_enter_to_continue
        return 1
    fi

    clear_screen
    print_banner
    print_header "TIMELINE SCAN: MODIFIED WITHIN LAST $days DAY(S)"
    info "Investigating targets: ${roots[*]}"

    local temp_raw="$PROJECT_ROOT/data/tmp_timeline_raw.tsv"
    ensure_dir "$PROJECT_ROOT/data"
    : > "$temp_raw"

    local symlink_flag="-P"
    [ "$CFG_FOLLOW_SYMLINKS" = "1" ] && symlink_flag="-L"

    local prune_args
    read -r -a prune_args <<< "$(build_find_prune_args)"

    init_scan_log
    local start_time
    start_time=$(date +%s)

    for r in "${roots[@]}"; do
        [ ! -d "$r" ] && continue
        search_status "Scanning: $r"
        if [ ${#prune_args[@]} -gt 0 ]; then
            find "$symlink_flag" "$r" "${prune_args[@]}" \
                -type f -mtime "-$days" \
                -printf '%T@\t%s\t%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_raw"
        else
            find "$symlink_flag" "$r" \
                -type f -mtime "-$days" \
                -printf '%T@\t%s\t%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_raw"
        fi
    done

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    local total_found
    total_found="$(wc -l < "$temp_raw" | tr -d '[:space:]')"

    if [ "$total_found" -eq 0 ]; then
        info "Zero files modified in the selected targets within the last $days day(s)."
        rm -f "$temp_raw"
        press_enter_to_continue
        return 0
    fi

    # Sort descending by mtime (most recent files first)
    local sorted_timeline="$PROJECT_ROOT/data/tmp_timeline_sorted.tsv"
    sort -t$'\t' -k1,1nr "$temp_raw" > "$sorted_timeline"
    rm -f "$temp_raw"

    clear_screen
    print_banner
    print_header "TIMELINE OF RECENT ACTIVITY (LAST $days DAYS)"
    printf "Found %s%d%s files modified within the timeframe (%d seconds):\n\n" "$C_GREEN" "$total_found" "$C_RESET" "$elapsed"

    printf "%s%-20s %-10s %s%s\n" "$C_BOLD$C_BLUE" "Modified Date/Time" "Size" "Windows File Path" "$C_RESET"
    print_divider

    local shown=0
    while IFS=$'\t' read -r epoch_mtime fsize fpath || [ -n "$fpath" ]; do
        [ -z "$fpath" ] && continue
        shown=$((shown + 1))

        local m_int="${epoch_mtime%.*}"
        local date_str
        date_str="$(format_epoch "$m_int")"
        local sz_str
        sz_str="$(format_bytes "$fsize")"
        local win_path
        win_path="$(to_win_path "$fpath")"

        printf "%s%-20s%s %-10s %s%s%s\n" \
            "$C_CYAN" "$date_str" "$C_RESET" \
            "$sz_str" \
            "$C_WHITE" "$win_path" "$C_RESET"

        if [ "$shown" -ge 40 ]; then
            printf "%s... [Showing top 40 most recent. %d total files modified] ...%s\n" "$C_YELLOW" "$total_found" "$C_RESET"
            break
        fi
    done < "$sorted_timeline"
    rm -f "$sorted_timeline"

    print_divider
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Timeline from Search Results
# ------------------------------------------------------------------------------
display_timeline_from_results() {
    local results_file="$1"
    local query_label="$2"

    if [ ! -f "$results_file" ] || [ ! -s "$results_file" ]; then
        error "No search results available to generate timeline."
        press_enter_to_continue
        return 1
    fi

    clear_screen
    print_banner
    print_header "TIMELINE: '$query_label'"
    
    # Sort results by modification epoch column (column 7 in LAST_RESULTS_FILE) descending
    local sorted_temp="$PROJECT_ROOT/data/tmp_res_timeline.tsv"
    sort -t$'\t' -k7,7nr "$results_file" > "$sorted_temp"

    printf "%s%-20s %-6s %-10s %s%s\n" "$C_BOLD$C_BLUE" "Modified Date/Time" "Type" "Size" "Discovered Path" "$C_RESET"
    print_divider

    local shown=0
    while IFS=$'\t' read -r idx rank r_type bname ext r_size mtime_int win_path r_path || [ -n "$r_path" ]; do
        [ -z "$r_path" ] && continue
        shown=$((shown + 1))

        local date_str
        date_str="$(format_epoch "$mtime_int")"
        local sz_str="---"
        [ "$r_type" = "f" ] && sz_str="$(format_bytes "$r_size")"

        local type_badge="[FILE]"
        [ "$r_type" = "d" ] && type_badge="[DIR] "

        printf "%s%-20s%s %-6s %-10s %s%s%s\n" \
            "$C_CYAN" "$date_str" "$C_RESET" \
            "$type_badge" \
            "$sz_str" \
            "$C_WHITE" "$win_path" "$C_RESET"

        if [ "$shown" -ge 40 ]; then
            printf "%s... [Truncated for display preview] ...%s\n" "$C_YELLOW" "$C_RESET"
            break
        fi
    done < "$sorted_temp"
    rm -f "$sorted_temp"

    print_divider
    press_enter_to_continue
}
