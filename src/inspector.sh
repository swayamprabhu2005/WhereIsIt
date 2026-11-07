#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: inspector.sh
# Purpose: Comprehensive metadata inspection & suspicious file indicators
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
fi

# ------------------------------------------------------------------------------
# File Metadata Inspector (Feature 5)
# ------------------------------------------------------------------------------
inspect_metadata() {
    local target_path="$1"
    
    if [ -z "$target_path" ]; then
        error "No target path provided for inspection."
        return 1
    fi

    # Convert to POSIX for internal bash operations
    local ppath
    ppath="$(to_posix_path "$target_path")"

    if [ ! -e "$ppath" ]; then
        error "Target does not exist: $target_path"
        return 1
    fi

    local win_path
    win_path="$(to_win_path "$ppath")"
    local bname
    bname="$(basename "$ppath")"
    local ext
    ext="$(get_file_extension "$bname")"
    [ -z "$ext" ] && ext="[None]"

    clear_screen
    print_banner
    print_header "FILE SYSTEM METADATA INSPECTOR"
    
    # Retrieve stat info
    # %s = size, %Y = mtime, %X = atime, %W = birth/ctime, %a = octal perms, %A = symbolic perms, %F = type
    local stat_data
    stat_data="$(stat -c '%s|%Y|%X|%W|%a|%A|%F' "$ppath" 2>/dev/null)"

    local size_bytes="0"
    local mtime_epoch="0"
    local atime_epoch="0"
    local btime_epoch="0"
    local octal_perms="---"
    local sym_perms="---"
    local raw_type="Unknown"

    if [ -n "$stat_data" ]; then
        IFS='|' read -r size_bytes mtime_epoch atime_epoch btime_epoch octal_perms sym_perms raw_type <<< "$stat_data"
    fi

    local human_size
    human_size="$(format_bytes "$size_bytes")"
    local mtime_str
    mtime_str="$(format_epoch "$mtime_epoch")"
    local atime_str
    atime_str="$(format_epoch "$atime_epoch")"

    # Creation / Birth time if available
    local btime_str="Not reported by filesystem"
    if [ -n "$btime_epoch" ] && [ "$btime_epoch" -gt 0 ] 2>/dev/null; then
        btime_str="$(format_epoch "$btime_epoch")"
    fi

    # Detailed file type identification using 'file' utility
    local detailed_type="Unavailable"
    if command -v file >/dev/null 2>&1; then
        detailed_type="$(file -b "$ppath" 2>/dev/null)"
        [ -z "$detailed_type" ] && detailed_type="$raw_type"
    else
        detailed_type="$raw_type"
    fi

    # Hidden status check
    local is_hidden="No"
    if [[ "$bname" =~ ^\. ]]; then
        is_hidden="Yes (Unix dotfile)"
    fi

    # Read / Write / Execute capabilities for current user
    local can_read="No"
    local can_write="No"
    local can_exec="No"
    [ -r "$ppath" ] && can_read="Yes"
    [ -w "$ppath" ] && can_write="Yes"
    [ -x "$ppath" ] && can_exec="Yes"

    # Display Metadata Card
    printf "  %s%-22s%s %s%s%s\n" "$C_CYAN" "Target Name:" "$C_RESET" "$C_BOLD$C_WHITE" "$bname" "$C_RESET"
    printf "  %s%-22s%s %s\n" "$C_CYAN" "Windows Path:" "$C_RESET" "$win_path"
    printf "  %s%-22s%s %s\n" "$C_CYAN" "POSIX Path:" "$C_RESET" "$ppath"
    printf "  %s%-22s%s %s\n" "$C_CYAN" "Item Category:" "$C_RESET" "$raw_type"
    printf "  %s%-22s%s %s\n" "$C_CYAN" "Identified Format:" "$C_RESET" "$detailed_type"
    printf "  %s%-22s%s %s\n" "$C_CYAN" "File Extension:" "$C_RESET" "$ext"
    printf "  %s%-22s%s %s (%s bytes)\n" "$C_CYAN" "File Size:" "$C_RESET" "$human_size" "$size_bytes"
    print_divider

    printf "  %s%-22s%s %s\n" "$C_BLUE" "Last Modified:" "$C_RESET" "$mtime_str"
    printf "  %s%-22s%s %s\n" "$C_BLUE" "Last Accessed:" "$C_RESET" "$atime_str"
    printf "  %s%-22s%s %s\n" "$C_BLUE" "Creation Time:" "$C_RESET" "$btime_str"
    printf "  %s%-22s%s %s\n" "$C_BLUE" "Hidden Status:" "$C_RESET" "$is_hidden"
    printf "  %s%-22s%s %s (%s)\n" "$C_BLUE" "POSIX Permissions:" "$C_RESET" "$sym_perms" "$octal_perms"
    printf "  %s%-22s%s Read: %s | Write: %s | Execute: %s\n" "$C_BLUE" "Effective Access:" "$C_RESET" "$can_read" "$can_write" "$can_exec"
    print_divider

    # Text Metrics (wc) if text file
    if [ -f "$ppath" ] && [[ "$detailed_type" =~ text|ASCII|UTF-8|source|script ]]; then
        local wc_out
        wc_out="$(wc "$ppath" 2>/dev/null)"
        if [ -n "$wc_out" ]; then
            local lines words chars
            read -r lines words chars _ <<< "$wc_out"
            printf "  %s%-22s%s Lines: %s | Words: %s | Chars: %s\n" "$C_TEAL" "Text Content Metrics:" "$C_RESET" "$lines" "$words" "$chars"
            print_divider
        fi
    fi

    # SHA-256 Checksum calculation
    if [ -f "$ppath" ]; then
        if [ "$CFG_CALC_HASH_ON_INSPECT" = "1" ]; then
            printf "  %s%-22s%s Calculating SHA-256... " "$C_YELLOW" "Cryptographic Hash:" "$C_RESET"
            local hash
            hash="$(sha256sum "$ppath" 2>/dev/null | awk '{print $1}')"
            printf "\r  %s%-22s%s %s%s%s\n" "$C_YELLOW" "SHA-256 Checksum:" "$C_RESET" "$C_GREEN" "$hash" "$C_RESET"
        else
            printf "  %s%-22s%s %s[Skipped - Enable in Settings or press H]%s\n" "$C_YELLOW" "SHA-256 Checksum:" "$C_RESET" "$C_GRAY" "$C_RESET"
        fi
    elif [ -d "$ppath" ]; then
        local child_items
        child_items="$(find "$ppath" -maxdepth 1 2>/dev/null | wc -l)"
        child_items=$((child_items - 1)) # exclude self
        [ "$child_items" -lt 0 ] && child_items=0
        printf "  %s%-22s%s %d immediate items\n" "$C_YELLOW" "Directory Contents:" "$C_RESET" "$child_items"
    fi

    # Suspicious File Indicators check
    evaluate_single_suspicious_indicators "$ppath" "$bname" "$ext" "$size_bytes" "$detailed_type"

    print_divider
    printf "%sInspection Actions:%s [B] Bookmark | [H] Compute/Refresh Hash | [O] Back\n" "$C_BOLD" "$C_RESET"
    printf "%sSelect option: %s" "$C_WHITE" "$C_RESET"
    read -r ins_act
    case "${ins_act^^}" in
        B)
            if [ -f "$PROJECT_ROOT/src/bookmarks.sh" ]; then
                # shellcheck source=src/bookmarks.sh
                source "$PROJECT_ROOT/src/bookmarks.sh"
                add_bookmark_interactive "$ppath"
            fi
            ;;
        H)
            if [ -f "$ppath" ]; then
                search_status "Computing SHA-256 hash..."
                local h
                h="$(sha256sum "$ppath" 2>/dev/null | awk '{print $1}')"
                success "SHA-256: $h"
                press_enter_to_continue
            fi
            ;;
        *)
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Suspicious File Indicators (Enhancement B)
# ------------------------------------------------------------------------------
evaluate_single_suspicious_indicators() {
    local ppath="$1"
    local bname="$2"
    local ext="$3"
    local size="$4"
    local detailed_type="$5"

    local indicators=()

    # Rule 1: Double extensions (e.g. report.pdf.exe, doc.docx.vbs)
    if [[ "$bname" =~ \.(pdf|docx|xlsx|pptx|jpg|png|txt|csv)\.(exe|vbs|bat|cmd|scr|ps1|com|pif)$ ]]; then
        indicators+=("CRITICAL: Deceptive double extension detected (${BASH_REMATCH[0]}).")
    fi

    # Rule 2: Empty files (0 bytes)
    if [ -f "$ppath" ] && [ "$size" -eq 0 ]; then
        indicators+=("INFORMATIONAL: Zero-byte empty file.")
    fi

    # Rule 3: Executable in unexpected user/download directories
    local ppath_lower="${ppath,,}"
    if [[ "$bname" =~ \.(exe|bat|cmd|vbs|ps1|scr|jar)$ ]]; then
        if [[ "$ppath_lower" =~ /temp/|/tmp/|/appdata/local/temp ]]; then
            indicators+=("WARNING: Executable binary residing in temporary directory.")
        fi
    fi

    # Rule 4: Extension & Magic Signature Mismatch
    if [ -f "$ppath" ] && [ "$size" -ge 4 ]; then
        local header
        header="$(head -c 4 "$ppath" 2>/dev/null)"
        
        # Check MZ executable header (4D 5A)
        if [[ "$header" == MZ* ]]; then
            if ! [[ "$ext" =~ ^(exe|dll|sys|ocx|scr|com)$ ]]; then
                indicators+=("HIGH: File has non-executable extension (.$ext) but contains Windows PE/MZ binary header.")
            fi
        fi

        # Check PDF header (%PDF)
        if [ "$ext" = "pdf" ]; then
            if [[ "$header" != %PDF* ]]; then
                indicators+=("WARNING: File has .pdf extension but lacks standard '%PDF' magic header.")
            fi
        fi

        # Check PNG header (\x89PNG)
        if [ "$ext" = "png" ]; then
            if ! [[ "$detailed_type" =~ PNG ]]; then
                indicators+=("WARNING: File has .png extension but signature does not match PNG image format.")
            fi
        fi
    fi

    # Rule 5: Unusual Filenames (trailing dots, hidden trailing spaces)
    if [[ "$bname" =~ \ $ ]] || [[ "$bname" =~ \.$ ]]; then
        indicators+=("SUSPICIOUS: Filename contains trailing whitespace or trailing period.")
    fi

    if [ ${#indicators[@]} -gt 0 ]; then
        print_divider
        printf "%s%s[!] SUSPICIOUS FILE INDICATORS AUDIT:%s\n" "$C_YELLOW" "$C_BOLD" "$C_RESET"
        for ind in "${indicators[@]}"; do
            printf "  %s* %s%s\n" "$C_YELLOW" "$ind" "$C_RESET"
        done
        printf "%s  (Note: Indicators are heuristics for triage only; not a substitute for AV/malware analysis)%s\n" "$C_GRAY" "$C_RESET"
    fi
}

# Audit entire search result set for suspicious files
audit_suspicious_indicators() {
    local results_file="$1"
    if [ ! -f "$results_file" ]; then
        error "No active results to audit."
        press_enter_to_continue
        return 1
    fi

    clear_screen
    print_banner
    print_header "SUSPICIOUS FILE INDICATORS BATCH AUDIT"
    printf "Analyzing discovered search results against anomaly heuristics...\n\n"

    local flagged_count=0
    while IFS=$'\t' read -r idx rank r_type bname ext r_size mtime_int win_path r_path || [ -n "$r_path" ]; do
        [ -z "$r_path" ] && continue
        [ "$r_type" != "f" ] && continue

        local is_flagged=0
        local reason=""

        # Double ext
        if [[ "$bname" =~ \.(pdf|docx|xlsx|pptx|jpg|png|txt|csv)\.(exe|vbs|bat|cmd|scr|ps1|com|pif)$ ]]; then
            is_flagged=1
            reason="Double extension (${BASH_REMATCH[0]})"
        fi

        # Signature mismatch
        if [ -f "$r_path" ] && [ "$r_size" -ge 4 ]; then
            local header
            header="$(head -c 2 "$r_path" 2>/dev/null)"
            if [[ "$header" == "MZ" ]] && ! [[ "$ext" =~ ^(exe|dll|sys|ocx|scr|com)$ ]]; then
                is_flagged=1
                reason="Executable header (MZ) disguised as .$ext"
            fi
        fi

        # Trailing spaces/dots
        if [[ "$bname" =~ \ $ ]] || [[ "$bname" =~ \.$ ]]; then
            is_flagged=1
            reason="Trailing whitespace or dot"
        fi

        if [ "$is_flagged" -eq 1 ]; then
            flagged_count=$((flagged_count + 1))
            printf "  %s[%d]%s %s%-25s%s %s%s%s\n" "$C_RED" "$flagged_count" "$C_RESET" "$C_YELLOW" "$reason" "$C_RESET" "$C_WHITE" "$win_path" "$C_RESET"
        fi
    done < "$results_file"

    print_divider
    if [ "$flagged_count" -eq 0 ]; then
        success "No suspicious heuristics triggered across discovered files."
    else
        warn "Total flagged files: $flagged_count"
        printf "%sNotice: These indicators point to anomalies (e.g. extension tricks or disguised binaries) for investigator review.%s\n" "$C_GRAY" "$C_RESET"
    fi
    press_enter_to_continue
}
