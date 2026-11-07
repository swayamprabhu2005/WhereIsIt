#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: reporter.sh
# Purpose: RFC 4180 CSV & Formatted TXT Investigation Report Generation
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
    # shellcheck source=src/scanner.sh
    source "$SCRIPT_DIR/scanner.sh"
fi

REPORTS_DIR="$PROJECT_ROOT/reports"

# ------------------------------------------------------------------------------
# Report Export Menu (Feature 10)
# ------------------------------------------------------------------------------
export_report_menu() {
    local keyword="$1"
    local results_file="${2:-$PROJECT_ROOT/data/last_search_results.tsv}"

    if [ ! -f "$results_file" ] || [ ! -s "$results_file" ]; then
        error "No active search results to export."
        press_enter_to_continue
        return 1
    fi

    clear_screen
    print_banner
    print_header "INVESTIGATION REPORT GENERATION"
    printf "Export discovered investigation findings into structured, auditable formats.\n\n"

    printf "  %s1.%s Plain Text Forensic Report (.txt)\n" "$C_CYAN" "$C_RESET"
    printf "  %s2.%s RFC 4180 Compliant Spreadsheet (.csv)\n" "$C_CYAN" "$C_RESET"
    printf "  %s3.%s Export Both Formats (.txt and .csv)\n" "$C_CYAN" "$C_RESET"
    print_divider
    printf "  %s0.%s Cancel Export\n" "$C_CYAN" "$C_RESET"
    print_divider

    printf "%sSelect report format [0-3]: %s" "$C_WHITE" "$C_RESET"
    read -r choice
    case "$choice" in
        1) export_txt_report "$keyword" "$results_file" ;;
        2) export_csv_report "$keyword" "$results_file" ;;
        3)
            export_txt_report "$keyword" "$results_file"
            export_csv_report "$keyword" "$results_file"
            ;;
        0|*)
            info "Export cancelled."
            sleep 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Export TXT Report
# ------------------------------------------------------------------------------
export_txt_report() {
    local keyword="$1"
    local results_file="$2"

    ensure_dir "$REPORTS_DIR"
    local clean_kw
    clean_kw="$(echo "$keyword" | sed 's/[^a-zA-Z0-9_-]/_/g')"
    [ -z "$clean_kw" ] && clean_kw="Investigation"

    local base_filename="REPORT_${clean_kw}_$(get_timestamp).txt"
    local out_path="$REPORTS_DIR/$base_filename"

    # Overwrite protection
    if [ -f "$out_path" ]; then
        if ! prompt_confirm "File already exists. Overwrite?" "N"; then
            info "Export cancelled."
            return 0
        fi
    fi

    local total_count file_count folder_count
    total_count="$(wc -l < "$results_file" | tr -d '[:space:]')"
    file_count="$(awk -F'\t' '$3 == "f" {c++} END {print c+0}' "$results_file")"
    folder_count="$(awk -F'\t' '$3 == "d" {c++} END {print c+0}' "$results_file")"

    local error_count
    error_count="$(get_scan_error_count)"

    {
        echo "================================================================================"
        echo "                    WHERE IS IT - INVESTIGATION REPORT"
        echo "================================================================================"
        echo "Investigation Query:     $keyword"
        echo "Generated Timestamp:     $(get_display_timestamp)"
        echo "Application Version:     $APP_NAME v$APP_VERSION"
        echo "Operating System / Env:  Windows (Git Bash Posix Subsystem)"
        echo "Total Discovered Items:  $total_count"
        echo "  * Matching Files:      $file_count"
        echo "  * Matching Folders:    $folder_count"
        echo "Inaccessible Locations:  $error_count"
        echo "================================================================================"
        echo ""
        echo "SECTION 1: DISCOVERED LOCATIONS AND ARTIFACTS"
        echo "--------------------------------------------------------------------------------"
        printf "%-5s %-6s %-8s %-12s %-20s %s\n" "No." "Type" "Rank" "Size" "Modified Time" "Windows Path"
        printf "%s\n" "--------------------------------------------------------------------------------"
        
        while IFS=$'\t' read -r idx rank r_type bname ext r_size mtime_int win_path r_path; do
            local type_str="[FILE]"
            local sz_str="---"
            if [ "$r_type" = "d" ]; then
                type_str="[DIR] "
            else
                sz_str="$(format_bytes "$r_size")"
            fi
            local m_str
            m_str="$(format_epoch "$mtime_int")"
            local rank_str="Rank-$rank"

            printf "%-5s %-6s %-8s %-12s %-20s %s\n" "$idx" "$type_str" "$rank_str" "$sz_str" "$m_str" "$win_path"
        done < "$results_file"

        echo ""
        echo "================================================================================"
        echo "SECTION 2: INACCESSIBLE LOCATIONS & PERMISSION AUDIT"
        echo "--------------------------------------------------------------------------------"
        if [ "$error_count" -gt 0 ] && [ -f "$SCAN_ERROR_LOG" ]; then
            echo "The following paths were restricted by operating system permissions or I/O locks:"
            cat "$SCAN_ERROR_LOG"
        else
            echo "Zero inaccessible path errors encountered during scan."
        fi
        echo "================================================================================"
        echo "End of Investigation Report"
    } > "$out_path"

    success "Text report generated: $(to_win_path "$out_path")"
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Export RFC 4180 Compliant CSV Report
# ------------------------------------------------------------------------------
export_csv_report() {
    local keyword="$1"
    local results_file="$2"

    ensure_dir "$REPORTS_DIR"
    local clean_kw
    clean_kw="$(echo "$keyword" | sed 's/[^a-zA-Z0-9_-]/_/g')"
    [ -z "$clean_kw" ] && clean_kw="Investigation"

    local base_filename="REPORT_${clean_kw}_$(get_timestamp).csv"
    local out_path="$REPORTS_DIR/$base_filename"

    if [ -f "$out_path" ]; then
        if ! prompt_confirm "File already exists. Overwrite?" "N"; then
            info "Export cancelled."
            return 0
        fi
    fi

    {
        # CSV Header
        echo '"Index","Rank","Type","Name","Extension","Size_Bytes","Human_Size","Modified_Epoch","Modified_Time","Windows_Path","POSIX_Path"'

        while IFS=$'\t' read -r idx rank r_type bname ext r_size mtime_int win_path r_path; do
            local type_label="File"
            [ "$r_type" = "d" ] && type_label="Directory"
            local h_sz
            h_sz="$(format_bytes "$r_size")"
            local h_date
            h_date="$(format_epoch "$mtime_int")"

            # Escape all text fields
            local e_idx e_rank e_type e_name e_ext e_bytes e_hsz e_mepoch e_mdate e_wpath e_ppath
            e_idx="$(escape_csv_field "$idx")"
            e_rank="$(escape_csv_field "$rank")"
            e_type="$(escape_csv_field "$type_label")"
            e_name="$(escape_csv_field "$bname")"
            e_ext="$(escape_csv_field "$ext")"
            e_bytes="$(escape_csv_field "$r_size")"
            e_hsz="$(escape_csv_field "$h_sz")"
            e_mepoch="$(escape_csv_field "$mtime_int")"
            e_mdate="$(escape_csv_field "$h_date")"
            e_wpath="$(escape_csv_field "$win_path")"
            e_ppath="$(escape_csv_field "$r_path")"

            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
                "$e_idx" "$e_rank" "$e_type" "$e_name" "$e_ext" "$e_bytes" "$e_hsz" "$e_mepoch" "$e_mdate" "$e_wpath" "$e_ppath"
        done < "$results_file"
    } > "$out_path"

    success "CSV report generated: $(to_win_path "$out_path")"
    press_enter_to_continue
}
