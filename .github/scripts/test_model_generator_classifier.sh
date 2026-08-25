#!/usr/bin/env bash
# Local Test Harness for Model Generator Workflow Failure Classifier
# Tests all step outcome branches and log parsing patterns.

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

run_classifier() {
  local outcome_checkout="${1:-success}"
  local outcome_setup_go="${2:-success}"
  local outcome_pull_initial="${3:-success}"
  local outcome_build="${4:-success}"
  local outcome_generate="${5:-success}"
  local outcome_upload_artifacts="${6:-success}"
  local outcome_check_error="${7:-success}"
  local outcome_update="${8:-success}"
  local outcome_pull_pre_commit="${9:-success}"
  local outcome_commit="${10:-success}"

  export RUNNER_TEMP="$TEMP_DIR"
  local GITHUB_OUTPUT="$TEMP_DIR/github_output"
  local GITHUB_STEP_SUMMARY="$TEMP_DIR/github_summary"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"

  # Run the classifier logic exactly as in model-generator.yml
  (
    ATTACHMENT=""
    DETAIL=""

    extract_detail() {
      local log_path="$1"
      if [ -f "$log_path" ] && [ -s "$log_path" ]; then
        sed 's/\x1b\[[0-9;]*m//g' "$log_path" \
          | grep -a -m1 '^Error: ' \
          | sed 's/^Error: //' \
          | cut -c1-200 \
          | tr -d '\r\n' || true
      fi
    }

    if [ "$outcome_checkout" = "failure" ]; then
      REASON="Check out code failed"
      DETAIL="The repository checkout step failed. Check the workflow run for details."

    elif [ "$outcome_setup_go" = "failure" ]; then
      REASON="Setup Go failed"
      DETAIL="The Go setup step failed. Check the workflow run for details."

    elif [ "$outcome_pull_initial" = "failure" ]; then
      REASON="Initial git pull failed"
      LOG="$RUNNER_TEMP/pull-initial.log"
      [ -f "$LOG" ] && ATTACHMENT="$LOG"
      DETAIL=$(tail -n 5 "$LOG" 2>/dev/null | tr -d '\r' | paste -sd ' ' - || true)

    elif [ "$outcome_build" = "failure" ]; then
      REASON="mesheryctl build failed"
      LOG="$RUNNER_TEMP/build.log"
      [ -f "$LOG" ] && ATTACHMENT="$LOG"
      DETAIL=$(tail -n 5 "$LOG" 2>/dev/null | tr -d '\r' | paste -sd ' ' - || true)

    elif [ "$outcome_generate" = "failure" ]; then
      LOG="$RUNNER_TEMP/generate.log"
      [ -f "$LOG" ] && ATTACHMENT="$LOG"
      DETAIL=$(extract_detail "$LOG")

      if [ ! -s "$LOG" ]; then
        REASON="Model generation failed before output"
      elif grep -qa "Invalid JWT Token" "$LOG"; then
        REASON="Spreadsheet credential rejected"
      elif grep -qa "error parsing relationships" "$LOG"; then
        REASON="Relationship data could not be parsed"
      elif grep -qa "error parsing" "$LOG"; then
        REASON="Spreadsheet tab could not be read"
      elif grep -qa "error updating registry" "$LOG"; then
        REASON="Spreadsheet could not be opened"
      elif grep -qa "isn't specified" "$LOG" || grep -qa "is required" "$LOG"; then
        REASON="Invalid command arguments"
      else
        REASON="Model generation failed"
      fi

    elif [ "$outcome_upload_artifacts" = "failure" ]; then
      REASON="Upload artifacts failed"
      DETAIL="The artifact upload step failed. Check the workflow run for details."

    elif [ "$outcome_check_error" = "failure" ]; then
      REASON="Registry error check failed"
      DETAIL="The registry-generate-error check step failed. Check the workflow run for details."

    elif [ "$outcome_update" = "failure" ]; then
      REASON="Model Updater failed"
      LOG="$RUNNER_TEMP/update.log"
      [ -f "$LOG" ] && ATTACHMENT="$LOG"
      DETAIL=$(extract_detail "$LOG")

    elif [ "$outcome_pull_pre_commit" = "failure" ]; then
      REASON="Git pull before commit failed"
      LOG="$RUNNER_TEMP/pull-pre-commit.log"
      [ -f "$LOG" ] && ATTACHMENT="$LOG"
      DETAIL=$(tail -n 5 "$LOG" 2>/dev/null | tr -d '\r' | paste -sd ' ' - || true)

    elif [ "$outcome_commit" = "failure" ]; then
      REASON="Git auto-commit failed"
      DETAIL="git-auto-commit-action encountered an error while pushing changes to master."

    else
      REASON="Workflow failure"
      DETAIL="An unexpected failure occurred during workflow execution."
    fi

    [ -n "$DETAIL" ] || DETAIL="No specific error message was captured. Check workflow run logs."

    echo "reason=$REASON" >> "$GITHUB_OUTPUT"
    echo "detail=$DETAIL" >> "$GITHUB_OUTPUT"
    echo "attachment=$ATTACHMENT" >> "$GITHUB_OUTPUT"
  )
}

get_output() {
  local key="$1"
  grep "^${key}=" "$TEMP_DIR/github_output" | cut -d'=' -f2-
}

assert_test() {
  local test_name="$1"
  local exp_reason="$2"
  local exp_attachment="$3"
  local exp_detail_contains="$4"

  local actual_reason
  local actual_attachment
  local actual_detail
  actual_reason=$(get_output "reason")
  actual_attachment=$(get_output "attachment")
  actual_detail=$(get_output "detail")

  local failed=0

  if [ "$actual_reason" != "$exp_reason" ]; then
    echo -e "  ${RED}✗ Reason mismatch${NC}: expected '$exp_reason', got '$actual_reason'"
    failed=1
  fi

  if [ "$actual_attachment" != "$exp_attachment" ]; then
    echo -e "  ${RED}✗ Attachment mismatch${NC}: expected '$exp_attachment', got '$actual_attachment'"
    failed=1
  fi

  if [ -n "$exp_detail_contains" ] && [[ "$actual_detail" != *"$exp_detail_contains"* ]]; then
    echo -e "  ${RED}✗ Detail mismatch${NC}: expected to contain '$exp_detail_contains', got '$actual_detail'"
    failed=1
  fi

  if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "${RED}✗ FAIL${NC}: $test_name"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}Running Model Generator Failure Classifier Test Suite${NC}"
echo -e "${YELLOW}======================================================${NC}\n"

# 1. Checkout failure
run_classifier "failure"
assert_test "Checkout step failure" "Check out code failed" "" "repository checkout step failed"

# 2. Setup Go failure
run_classifier "success" "failure"
assert_test "Setup Go step failure" "Setup Go failed" "" "Go setup step failed"

# 3. Initial pull failure
echo "fatal: unable to access repository: Connection timed out" > "$TEMP_DIR/pull-initial.log"
run_classifier "success" "success" "failure"
assert_test "Initial Git Pull failure" "Initial git pull failed" "$TEMP_DIR/pull-initial.log" "Connection timed out"

# 4. Build mesheryctl failure
echo "make: *** [Makefile:42: mesheryctl] Error 2" > "$TEMP_DIR/build.log"
run_classifier "success" "success" "success" "failure"
assert_test "mesheryctl build failure" "mesheryctl build failed" "$TEMP_DIR/build.log" "Error 2"

# 5. Generate: Empty log / failed before output
: > "$TEMP_DIR/generate.log"
run_classifier "success" "success" "success" "success" "failure"
assert_test "Generate: Empty log" "Model generation failed before output" "$TEMP_DIR/generate.log" "No specific error message was captured"

# 6. Generate: Invalid JWT Token
echo -e "Starting generation...\nError: Invalid JWT Token for Google Sheets API" > "$TEMP_DIR/generate.log"
run_classifier "success" "success" "success" "success" "failure"
assert_test "Generate: Invalid JWT Token" "Spreadsheet credential rejected" "$TEMP_DIR/generate.log" "Invalid JWT Token"

# 7. Generate: Relationship parse error
echo -e "Loading data...\nError: error parsing relationships from sheet tab" > "$TEMP_DIR/generate.log"
run_classifier "success" "success" "success" "success" "failure"
assert_test "Generate: Relationship parse error" "Relationship data could not be parsed" "$TEMP_DIR/generate.log" "error parsing relationships"

# 8. Generate: Spreadsheet tab parse error
echo -e "Loading data...\nError: error parsing components sheet" > "$TEMP_DIR/generate.log"
run_classifier "success" "success" "success" "success" "failure"
assert_test "Generate: Sheet parse error" "Spreadsheet tab could not be read" "$TEMP_DIR/generate.log" "error parsing components"

# 9. Generate: Spreadsheet could not be opened
echo -e "Connecting...\nError: error updating registry from remote source" > "$TEMP_DIR/generate.log"
run_classifier "success" "success" "success" "success" "failure"
assert_test "Generate: Spreadsheet open error" "Spreadsheet could not be opened" "$TEMP_DIR/generate.log" "error updating registry"

# 10. Generate: Invalid command arguments
echo -e "Error: --spreadsheet-id is required" > "$TEMP_DIR/generate.log"
run_classifier "success" "success" "success" "success" "failure"
assert_test "Generate: Invalid arguments" "Invalid command arguments" "$TEMP_DIR/generate.log" "--spreadsheet-id is required"

# 11. Generate: Generic unmatched error with ANSI codes
echo -e "\x1b[31mError: \x1b[0munexpected network reset during download" > "$TEMP_DIR/generate.log"
run_classifier "success" "success" "success" "success" "failure"
assert_test "Generate: Generic error with ANSI stripped" "Model generation failed" "$TEMP_DIR/generate.log" "unexpected network reset"

# 12. Upload artifacts failure
run_classifier "success" "success" "success" "success" "success" "failure"
assert_test "Upload artifacts failure" "Upload artifacts failed" "" "artifact upload step failed"

# 13. Check registry error step failure
run_classifier "success" "success" "success" "success" "success" "success" "failure"
assert_test "Check registry error step failure" "Registry error check failed" "" "registry-generate-error check step failed"

# 14. Model Updater failure
echo -e "Updating models...\nError: failed to update model definitions in directory" > "$TEMP_DIR/update.log"
run_classifier "success" "success" "success" "success" "success" "success" "success" "failure"
assert_test "Model Updater failure" "Model Updater failed" "$TEMP_DIR/update.log" "failed to update model definitions"

# 15. Pre-commit pull failure
echo "error: Your local changes to the following files would be overwritten by merge" > "$TEMP_DIR/pull-pre-commit.log"
run_classifier "success" "success" "success" "success" "success" "success" "success" "success" "failure"
assert_test "Pre-commit Git Pull failure" "Git pull before commit failed" "$TEMP_DIR/pull-pre-commit.log" "overwritten by merge"

# 16. Git auto-commit failure
run_classifier "success" "success" "success" "success" "success" "success" "success" "success" "success" "failure"
assert_test "Git auto-commit failure" "Git auto-commit failed" "" "git-auto-commit-action encountered an error"

# 17. Unrecognized fallback
run_classifier "success" "success" "success" "success" "success" "success" "success" "success" "success" "success"
assert_test "Unrecognized fallback failure" "Workflow failure" "" "unexpected failure occurred"

echo -e "\n${YELLOW}------------------------------------------------------${NC}"
echo -e "Test Summary: ${GREEN}${PASS_COUNT} Passed${NC}, ${RED}${FAIL_COUNT} Failed${NC}"
echo -e "${YELLOW}------------------------------------------------------${NC}"

if [ $FAIL_COUNT -ne 0 ]; then
  exit 1
fi
