#!/usr/bin/env bash

# Just keep
set -o pipefail

VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display error messages
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to display warnings
warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

# Function to display success messages
success() {
    echo -e "${GREEN}$1${NC}"
}

# Function to display info messages
info() {
    echo -e "${BLUE}$1${NC}"
}

# Function to check if gh is authenticated
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        error "Not authenticated with GitHub CLI. Please run 'gh auth login' first"
    fi
}

# Function to validate PR exists
validate_pr() {
    local pr_number=$1
    local repo=$2
    local pr_info
    
    if [ -n "$repo" ]; then
        pr_info=$(gh pr view "$pr_number" --repo "$repo" --json number,state 2>/dev/null) || \
            error "Pull request #$pr_number not found in repository $repo"
    else
        pr_info=$(gh pr view "$pr_number" --json number,state 2>/dev/null) || \
            error "Pull request #$pr_number not found in current repository"
    fi
    
    local pr_state=$(echo "$pr_info" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
    info "Found PR #$pr_number (Status: $pr_state)"
}

# Function to display help menu
show_help() {
    cat << EOF
difft-pr - View GitHub Pull Request diffs using Difftastic

Usage: $(basename "$0") [OPTIONS] <pr-number>

Options:
    -h, --help              Show this help message
    -v, --version          Show version information
    -b, --background       Set background color (dark/light) [default: dark]
    -r, --repo OWNER/REPO  Specify the GitHub repository (if not in repo directory)

Examples:
    $(basename "$0") 123                    # View PR #123 in current repository
    $(basename "$0") -b light 123           # View PR with light background
    $(basename "$0") -r owner/repo 123      # View PR from specific repository

Requirements:
    - GitHub CLI (gh) must be installed and authenticated
    - Difftastic (difft) must be installed
    - For local repository use, must be in a git repository

Note: This script requires both GitHub CLI and Difftastic to be installed.
For more information:
    GitHub CLI: https://cli.github.com
    Difftastic: https://github.com/Wilfred/difftastic
EOF
    exit 0
}

# Function to display version
show_version() {
    echo "difft-pr version $VERSION"
    exit 0
}

# Check for dependencies with detailed error messages
check_dependencies() {
    local missing_deps=0

    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) is not installed. Please install it:
    - On Ubuntu/Debian: sudo apt install gh
    - On macOS: brew install gh
    - Other methods: https://cli.github.com/manual/installation"
        missing_deps=1
    fi

    if ! command -v difft &> /dev/null; then
        error "Difftastic is not installed. Please install it:
    - On Ubuntu/Debian: cargo install difftastic
    - On macOS: brew install difftastic
    - Other methods: https://github.com/Wilfred/difftastic#installation"
        missing_deps=1
    fi

    # Check for required utilities
    if ! command -v csplit &> /dev/null; then
        error "csplit is not installed. Please install coreutils:
    - On Ubuntu/Debian: sudo apt install coreutils
    - On macOS: brew install coreutils"
        missing_deps=1
    fi

    if [ $missing_deps -eq 1 ]; then
        exit 1
    fi
}

# Function to process a single diff file
process_diff_file() {
    local diff_file="$1"
    local file_extension="$2"
    local in_hunk=false
    
    # Clear and create new temporary files with correct extension
    local old_file="$TEMP_DIR/old_content${file_extension}"
    local new_file="$TEMP_DIR/new_content${file_extension}"
    > "$old_file"
    > "$new_file"
    
    # Process the diff content line by line
    while IFS= read -r line; do
        # Skip headers until we hit the first hunk
        if [[ "$line" =~ ^@@ ]]; then
            in_hunk=true
            continue
        fi
        
        if [ "$in_hunk" = true ]; then
            if [[ "$line" =~ ^\+ ]]; then
                echo "${line:1}" >> "$new_file"
            elif [[ "$line" =~ ^- ]]; then
                echo "${line:1}" >> "$old_file"
            else
                # Context lines (no +/- prefix) go to both files
                echo "$line" >> "$old_file"
                echo "$line" >> "$new_file"
            fi
        fi
    done < "$diff_file"
    
    echo "$old_file:$new_file"
}

# Initialize variables
BACKGROUND="dark"
REPO=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--version)
            show_version
            ;;
        -b|--background)
            if [[ "$2" != "dark" && "$2" != "light" ]]; then
                error "Background must be either 'dark' or 'light'"
            fi
            BACKGROUND="$2"
            shift 2
            ;;
        -r|--repo)
            if [[ ! "$2" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
                error "Invalid repository format. Use 'owner/repo'"
            fi
            REPO="$2"
            shift 2
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                PR_NUMBER="$1"
                shift
            else
                error "Invalid argument: $1. Use --help for usage information."
            fi
            ;;
    esac
done

# Check dependencies
check_dependencies

# Check GitHub CLI authentication
check_gh_auth

# Validate PR number
if [ -z "$PR_NUMBER" ]; then
    error "Pull request number is required. Use --help for usage information."
fi

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    error "Pull request number must be a positive integer"
fi

# Validate PR exists and get its status
validate_pr "$PR_NUMBER" "$REPO"

# Create a temporary directory with error handling
TEMP_DIR=$(mktemp -d) || error "Failed to create temporary directory"
trap 'rm -rf "$TEMP_DIR"' EXIT

info "Fetching pull request diff..."

# Get the PR diff using GitHub CLI
if [ -n "$REPO" ]; then
    gh pr diff "$PR_NUMBER" --repo "$REPO" > "$TEMP_DIR/pr.diff" || error "Failed to fetch PR diff. Make sure:
    - The repository and PR exist
    - You have access to the repository"
else
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not in a git repository. Either:
    - Run this command from within a git repository, or
    - Specify the repository with -r owner/repo"
    fi
    
    gh pr diff "$PR_NUMBER" > "$TEMP_DIR/pr.diff" || error "Failed to fetch PR diff. Make sure:
    - The PR exists
    - You have access to the repository"
fi

# Debug: Show diff content
if [ -s "$TEMP_DIR/pr.diff" ]; then
    info "Diff file size: $(wc -l < "$TEMP_DIR/pr.diff") lines"
else
    error "Received empty diff from GitHub"
fi

# Check if the diff file contains actual git diff content
if ! grep -q "^diff --git" "$TEMP_DIR/pr.diff"; then
    error "Invalid diff format received from GitHub. The PR might not contain any changes."
fi

info "Processing diff files..."

# Create a directory for split files
mkdir -p "$TEMP_DIR/splits"

# Split the diff into individual files
awk '
    BEGIN { file_count = 0; current_file = ""; }
    /^diff --git/ {
        if (current_file != "") {
            close(current_file);
        }
        file_count++;
        current_file = sprintf("'"$TEMP_DIR"'/splits/diff-%03d", file_count);
        print > current_file;
        next;
    }
    current_file != "" {
        print >> current_file;
    }
' "$TEMP_DIR/pr.diff"

# Debug: Show number of split files
split_files=$(ls "$TEMP_DIR/splits"/diff-* 2>/dev/null | wc -l || echo 0)
info "Found $split_files file(s) to process"

if [ "$split_files" -eq 0 ]; then
    error "No diff files found after processing"
fi

# Counter for number of files processed
files_processed=0
files_failed=0

# For each split diff file
for diff_file in "$TEMP_DIR/splits"/diff-*; do
    if [ -f "$diff_file" ]; then
        # Extract the file paths
        old_file=$(grep '^--- a/' "$diff_file" | sed 's|^--- a/||') || continue
        new_file=$(grep '^+++ b/' "$diff_file" | sed 's|^+++ b/||') || continue
        
        if [ -n "$old_file" ] && [ -n "$new_file" ]; then
            info "Processing diff for: $new_file"
            
            # Extract file extension
            file_extension=""
            if [[ "$new_file" =~ \. ]]; then
                file_extension=".${new_file##*.}"
            fi
            
            # Debug: Show content of the diff file
            info "Diff chunk size: $(wc -l < "$diff_file") lines"
            
            # Process the diff file and get temp file paths
            temp_files=$(process_diff_file "$diff_file" "$file_extension")
            old_temp_file=${temp_files%:*}
            new_temp_file=${temp_files#*:}
            
            # Check if both files have content
            if [ ! -s "$old_temp_file" ] && [ ! -s "$new_temp_file" ]; then
                warn "No content changes found in $new_file"
                continue
            fi
            
            echo -e "\n=== Showing diff for: $new_file ===\n"

            # Use difftastic to show the diff
            DIFFT_BACKGROUND="$BACKGROUND" difft "$old_temp_file" "$new_temp_file" 2>"$TEMP_DIR/difft_error.log"
            difft_status=$?
            
            if [ $difft_status -eq 0 ]; then
                ((files_processed++))
                echo "Processed file: $new_file"
            else
                warn "Failed to process diff for $new_file (exit code: $difft_status)"
                if [ -s "$TEMP_DIR/difft_error.log" ]; then
                    warn "Difftastic error: $(cat "$TEMP_DIR/difft_error.log")"
                fi
                ((files_failed++))
            fi
        else
            warn "Could not extract file paths from diff for file: $(basename "$diff_file")"
            warn "Diff content: $(head -n 1 "$diff_file")"
        fi
    fi
done

if [ $files_processed -eq 0 ]; then
    if [ $files_failed -gt 0 ]; then
        error "Failed to process any files successfully ($files_failed files failed)"
    else
        warn "No files were processed. The PR might not contain any changes."
        # Debug: Show the original diff content
        warn "Original diff content:"
        cat "$TEMP_DIR/pr.diff"
    fi
else
    success "Successfully processed $files_processed file(s)"
    if [ $files_failed -gt 0 ]; then
        warn "Failed to process $files_failed file(s)"
    fi
fi 