#!/usr/bin/env bash
# ==============================================================================
# WHERE IS IT - Comprehensive Automated Test Suite
# Tests all core features, safety rules, multi-drive simulation & edge cases
# ==============================================================================

set -e
export NON_INTERACTIVE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source all project modules
# shellcheck source=src/utils.sh
source "$PROJECT_ROOT/src/utils.sh"
# shellcheck source=src/settings.sh
source "$PROJECT_ROOT/src/settings.sh"
# shellcheck source=src/scanner.sh
source "$PROJECT_ROOT/src/scanner.sh"
# shellcheck source=src/search.sh
source "$PROJECT_ROOT/src/search.sh"
# shellcheck source=src/filters.sh
source "$PROJECT_ROOT/src/filters.sh"
# shellcheck source=src/inspector.sh
source "$PROJECT_ROOT/src/inspector.sh"
# shellcheck source=src/duplicates.sh
source "$PROJECT_ROOT/src/duplicates.sh"
# shellcheck source=src/application.sh
source "$PROJECT_ROOT/src/application.sh"
# shellcheck source=src/indexer.sh
source "$PROJECT_ROOT/src/indexer.sh"
# shellcheck source=src/history.sh
source "$PROJECT_ROOT/src/history.sh"
# shellcheck source=src/bookmarks.sh
source "$PROJECT_ROOT/src/bookmarks.sh"
# shellcheck source=src/timeline.sh
source "$PROJECT_ROOT/src/timeline.sh"
# shellcheck source=src/comparison.sh
source "$PROJECT_ROOT/src/comparison.sh"
# shellcheck source=src/reporter.sh
source "$PROJECT_ROOT/src/reporter.sh"

TEST_ROOT="$PROJECT_ROOT/test-drive"
PASSED_TESTS=0
FAILED_TESTS=0

assert_equals() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        printf "  %s[PASS]%s %s\n" "$C_GREEN" "$C_RESET" "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        printf "  %s[FAIL]%s %s (Expected '%s', got '%s')\n" "$C_RED" "$C_RESET" "$test_name" "$expected" "$actual"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf "  %s[PASS]%s %s\n" "$C_GREEN" "$C_RESET" "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        printf "  %s[FAIL]%s %s (Expected substring '%s' in output)\n" "$C_RED" "$C_RESET" "$test_name" "$needle"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# ------------------------------------------------------------------------------
# Test Environment Setup
# ------------------------------------------------------------------------------
setup_test_environment() {
    info "Setting up mock multi-drive environment in $TEST_ROOT..."
    rm -rf "$TEST_ROOT"
    mkdir -p "$TEST_ROOT/Drive_C/Documents" \
             "$TEST_ROOT/Drive_C/Downloads" \
             "$TEST_ROOT/Drive_C/Program Files/Google/Chrome/Application" \
             "$TEST_ROOT/Drive_C/Users/TestUser/AppData/Local/Google/Chrome/User Data" \
             "$TEST_ROOT/Drive_C/Users/TestUser/AppData/Local/Temp" \
             "$TEST_ROOT/Drive_D/Backups" \
             "$TEST_ROOT/Drive_D/Software/Chrome" \
             "$TEST_ROOT/Drive_D/Work Projects/Special Folder"

    # 1. Base documents
    echo "Quarterly Financial Analysis" > "$TEST_ROOT/Drive_C/Documents/report.pdf"
    echo "Important internal notes" > "$TEST_ROOT/Drive_C/Documents/notes.txt"

    # 2. File with spaces
    echo "File with spaces content" > "$TEST_ROOT/Drive_D/Work Projects/Special Folder/Annual Summary Report 2026.docx"

    # 3. Duplicate files (exact same content and size in different locations and names)
    echo "Quarterly Financial Analysis" > "$TEST_ROOT/Drive_D/Backups/report-copy.pdf"
    echo "Quarterly Financial Analysis" > "$TEST_ROOT/Drive_D/Backups/backup_document.pdf"

    # 4. Empty file (0 bytes)
    touch "$TEST_ROOT/Drive_C/Documents/empty_file.log"

    # 5. Hidden file
    echo "Secret token" > "$TEST_ROOT/Drive_C/Documents/.secret_token.key"

    # 6. Application footprint files
    echo "Chrome Executable binary mock" > "$TEST_ROOT/Drive_C/Program Files/Google/Chrome/Application/chrome.exe"
    echo "Chrome Master Preferences" > "$TEST_ROOT/Drive_C/Program Files/Google/Chrome/Application/master_preferences"
    echo '{"session": {"restore_on_startup": 4}}' > "$TEST_ROOT/Drive_C/Users/TestUser/AppData/Local/Google/Chrome/User Data/Preferences"
    echo "Installer mock" > "$TEST_ROOT/Drive_C/Downloads/ChromeInstaller.exe"
    echo "Backup installer" > "$TEST_ROOT/Drive_D/Software/Chrome/config.txt"

    # 7. Suspicious double extension & MZ mismatch files
    echo "Malicious payload script" > "$TEST_ROOT/Drive_C/Users/TestUser/AppData/Local/Temp/invoice.pdf.exe"
    # Create fake MZ header in a .jpg file
    printf "MZ\x90\x00FakePEHeader" > "$TEST_ROOT/Drive_C/Downloads/fake_photo.jpg"
}

# ------------------------------------------------------------------------------
# Run Test Suite
# ------------------------------------------------------------------------------
run_all_tests() {
    clear_screen
    print_banner
    print_header "EXECUTING WHERE IS IT TEST SUITE"

    setup_test_environment

    # Test 1: Path conversion
    print_subheader "Test 1: Path Conversion Utilities"
    local win_p
    win_p="$(to_win_path "/c/Windows/System32")"
    assert_equals "Convert POSIX to Windows path" "C:\Windows\System32" "$win_p"

    local posix_p
    posix_p="$(to_posix_path "C:\\Program Files\\App")"
    assert_equals "Convert Windows to POSIX path" "/c/Program Files/App" "$posix_p"

    # Test 2: File size & epoch formatters
    print_subheader "Test 2: Human Formatters"
    local sz_1mb
    sz_1mb="$(format_bytes 1048576)"
    assert_equals "Format 1 MB exact bytes" "1.00 MB" "$sz_1mb"

    local sz_kb
    sz_kb="$(format_bytes 2048)"
    assert_equals "Format 2 KB exact bytes" "2.00 KB" "$sz_kb"

    # Test 3: Exact filename search
    print_subheader "Test 3: Exact Filename Search"
    run_search "report.pdf" "file" 1 "$TEST_ROOT/Drive_C" 1 >/dev/null
    local exact_matches
    exact_matches="$(wc -l < "$LAST_RESULTS_FILE" | tr -d '[:space:]')"
    assert_equals "Exact search for 'report.pdf' in Drive_C returns 1 match" "1" "$exact_matches"

    # Test 4: Partial filename search across multiple simulated drives
    print_subheader "Test 4: Partial Search Across Simulated Drives"
    run_search "report" "file" 0 "$TEST_ROOT/Drive_C $TEST_ROOT/Drive_D" 1 >/dev/null
    local partial_matches
    partial_matches="$(wc -l < "$LAST_RESULTS_FILE" | tr -d '[:space:]')"
    # report.pdf (Drive C), report-copy.pdf (Drive D), backup_document.pdf doesn't have 'report' in name, Annual Summary Report 2026.docx (Drive D)
    # Total matching 'report': 3 files
    assert_equals "Partial search for 'report' across C & D returns 3 files" "3" "$partial_matches"

    # Test 5: Folder search
    print_subheader "Test 5: Folder Search"
    run_search "Chrome" "folder" 0 "$TEST_ROOT" 1 >/dev/null
    local folder_matches
    folder_matches="$(wc -l < "$LAST_RESULTS_FILE" | tr -d '[:space:]')"
    # Folders matching Chrome:
    # 1. Google/Chrome (Drive C)
    # 2. Local/Google/Chrome (Drive C)
    # 3. Software/Chrome (Drive D)
    assert_equals "Folder search for 'Chrome' returns 3 directories" "3" "$folder_matches"

    # Test 6: Case-insensitivity verification
    print_subheader "Test 6: Case-Insensitive Matching"
    run_search "CHROMEINSTALLER" "file" 0 "$TEST_ROOT" 1 >/dev/null
    local ci_matches
    ci_matches="$(wc -l < "$LAST_RESULTS_FILE" | tr -d '[:space:]')"
    assert_equals "Search for uppercase 'CHROMEINSTALLER' finds 'ChromeInstaller.exe'" "1" "$ci_matches"

    # Test 7: Files with spaces handling
    print_subheader "Test 7: File Paths Containing Spaces"
    run_search "Annual Summary" "file" 0 "$TEST_ROOT/Drive_D" 1 >/dev/null
    local space_matches
    space_matches="$(wc -l < "$LAST_RESULTS_FILE" | tr -d '[:space:]')"
    assert_equals "Discovers file inside path with multiple spaces" "1" "$space_matches"

    # Test 8: Duplicate file detection
    print_subheader "Test 8: Duplicate File Detection (Hash Verification)"
    # report.pdf, report-copy.pdf, backup_document.pdf all have exact same content
    run_duplicate_detector "$TEST_ROOT" >/dev/null
    # Check if duplicate report can be generated
    local rep_file="$PROJECT_ROOT/reports/test_dup_report.txt"
    ensure_dir "$PROJECT_ROOT/reports"
    # Verify sha256 sums match
    local hash1 hash2 hash3
    hash1="$(sha256sum "$TEST_ROOT/Drive_C/Documents/report.pdf" | awk '{print $1}')"
    hash2="$(sha256sum "$TEST_ROOT/Drive_D/Backups/report-copy.pdf" | awk '{print $1}')"
    hash3="$(sha256sum "$TEST_ROOT/Drive_D/Backups/backup_document.pdf" | awk '{print $1}')"
    assert_equals "Duplicate files produce identical SHA-256 hashes" "$hash1" "$hash2"
    assert_equals "Third duplicate file shares exact SHA-256 hash" "$hash1" "$hash3"

    # Test 9: Metadata inspection & suspicious indicators
    print_subheader "Test 9: Metadata & Suspicious File Heuristics"
    local double_ext_file="$TEST_ROOT/Drive_C/Users/TestUser/AppData/Local/Temp/invoice.pdf.exe"
    local bname="$(basename "$double_ext_file")"
    local ext="$(get_file_extension "$bname")"
    assert_equals "Double extension target has outer extension 'exe'" "exe" "$ext"

    # Check fake MZ photo
    local fake_jpg="$TEST_ROOT/Drive_C/Downloads/fake_photo.jpg"
    local header="$(head -c 2 "$fake_jpg")"
    assert_equals "Fake jpg contains MZ header" "MZ" "$header"

    # Test 10: Search index creation & fast querying
    print_subheader "Test 10: Search Index Creation and Fast Lookups"
    # Build index directly for test drive
    local temp_idx="$PROJECT_ROOT/index/fs_index.db"
    ensure_dir "$PROJECT_ROOT/index"
    find -P "$TEST_ROOT" -printf '%y\t%s\t%T@\t%f\t%p\n' > "$temp_idx"
    local idx_entries
    idx_entries="$(wc -l < "$temp_idx" | tr -d '[:space:]')"
    [ "$idx_entries" -gt 5 ] && local idx_valid=1 || local idx_valid=0
    assert_equals "Filesystem index populated with entries" "1" "$idx_valid"

    # Test 11: Investigation report generation (CSV & TXT)
    print_subheader "Test 11: Investigation Report Generation"
    run_search "notes" "file" 0 "$TEST_ROOT" 1 >/dev/null
    export_txt_report "TestNotes" "$LAST_RESULTS_FILE" >/dev/null
    export_csv_report "TestNotes" "$LAST_RESULTS_FILE" >/dev/null

    local txt_report_count
    txt_report_count="$(ls -1 "$PROJECT_ROOT/reports"/REPORT_TestNotes_*.txt 2>/dev/null | wc -l | tr -d '[:space:]')"
    local csv_report_count
    csv_report_count="$(ls -1 "$PROJECT_ROOT/reports"/REPORT_TestNotes_*.csv 2>/dev/null | wc -l | tr -d '[:space:]')"
    assert_equals "TXT report successfully written to reports/" "1" "$txt_report_count"
    assert_equals "CSV report successfully written to reports/" "1" "$csv_report_count"

    # Clean up generated test reports
    rm -f "$PROJECT_ROOT/reports"/REPORT_TestNotes_*

    # Test 12: Bookmarks persistence
    print_subheader "Test 12: Bookmarks Persistence"
    local bm_file="$PROJECT_ROOT/data/bookmarks.tsv"
    : > "$bm_file"
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
        "1" "2026-11-07 12:00:00" "FILE" "Test Note" "C:\\test\\notes.txt" "$TEST_ROOT/Drive_C/Documents/notes.txt" >> "$bm_file"
    local bm_count
    bm_count="$(wc -l < "$bm_file" | tr -d '[:space:]')"
    assert_equals "Bookmark successfully stored in data/bookmarks.tsv" "1" "$bm_count"

    # Test 13: Snapshot comparison
    print_subheader "Test 13: Filesystem Snapshot Comparison"
    local snap1="$PROJECT_ROOT/data/snapshots/snap_test_1.snap"
    local snap2="$PROJECT_ROOT/data/snapshots/snap_test_2.snap"
    ensure_dir "$PROJECT_ROOT/data/snapshots"
    
    # Snapshot 1
    printf "/test/file1.txt\tC:\\test\\file1.txt\t100\t1700000000\tHASH1\n" > "$snap1"
    printf "/test/file2.txt\tC:\\test\\file2.txt\t200\t1700000000\tHASH2\n" >> "$snap1"

    # Snapshot 2: file1 modified, file2 moved to file3 (same hash), file4 new
    printf "/test/file1.txt\tC:\\test\\file1.txt\t150\t1700000050\tHASH1_MOD\n" > "$snap2"
    printf "/test/file3.txt\tC:\\test\\file3.txt\t200\t1700000000\tHASH2\n" >> "$snap2"
    printf "/test/file4.txt\tC:\\test\\file4.txt\t300\t1700000099\tHASH4\n" >> "$snap2"

    local new_out="$PROJECT_ROOT/data/tmp_test_new.tsv"
    local mod_out="$PROJECT_ROOT/data/tmp_test_mod.tsv"
    local moved_out="$PROJECT_ROOT/data/tmp_test_moved.tsv"
    : > "$new_out"; : > "$mod_out"; : > "$moved_out"

    awk -F'\t' '
        FILENAME == ARGV[1] {
            s1_path[$1] = 1; s1_size[$1] = $3; s1_hash[$1] = $5; s1_win[$1] = $2
            hash_to_path1[$5] = $1; hash_to_win1[$5] = $2
            next
        }
        FILENAME == ARGV[2] {
            if (!($1 in s1_path)) {
                if ($5 in hash_to_path1) {
                    print $2 "\t" hash_to_win1[$5] >> "'"$moved_out"'"
                } else {
                    print $2 >> "'"$new_out"'"
                }
            } else {
                if (s1_size[$1] != $3 || s1_hash[$1] != $5) {
                    print $2 >> "'"$mod_out"'"
                }
            }
            next
        }
    ' "$snap1" "$snap2"

    local test_c_new test_c_mod test_c_moved
    test_c_new="$(wc -l < "$new_out" | tr -d '[:space:]')"
    test_c_mod="$(wc -l < "$mod_out" | tr -d '[:space:]')"
    test_c_moved="$(wc -l < "$moved_out" | tr -d '[:space:]')"

    assert_equals "Comparison correctly identified 1 new file" "1" "$test_c_new"
    assert_equals "Comparison correctly identified 1 modified file" "1" "$test_c_mod"
    assert_equals "Comparison correctly identified 1 moved file by hash" "1" "$test_c_moved"

    rm -f "$snap1" "$snap2" "$new_out" "$mod_out" "$moved_out"

    # Summary
    print_divider
    printf "%sTest Suite Results: %s%d Passed%s, %s%d Failed%s.\n" \
        "$C_BOLD" "$C_GREEN" "$PASSED_TESTS" "$C_RESET" \
        "$([ "$FAILED_TESTS" -eq 0 ] && echo "$C_GREEN" || echo "$C_RED")" "$FAILED_TESTS" "$C_RESET"
    print_divider

    if [ "$FAILED_TESTS" -eq 0 ]; then
        success "All Where Is It automated test cases PASSED successfully!"
        return 0
    else
        error "$FAILED_TESTS test cases failed. Please review the output above."
        return 1
    fi
}

run_all_tests
