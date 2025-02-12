#!/usr/bin/env bash

set -eo pipefail

VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

    if [ $missing_deps -eq 1 ]; then
        exit 1
    fi
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
                error "Invalid argument: $1"
            fi
            ;;
    esac
done

# Check dependencies
check_dependencies

# Validate PR number
if [ -z "$PR_NUMBER" ]; then
    error "Pull request number is required"
fi

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    error "Pull request number must be a positive integer"
fi

# Create a temporary directory with error handling
TEMP_DIR=$(mktemp -d) || error "Failed to create temporary directory"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Get the PR diff using GitHub CLI
if [ -n "$REPO" ]; then
    gh pr diff "$PR_NUMBER" --repo "$REPO" > "$TEMP_DIR/pr.diff" || error "Failed to fetch PR diff. Make sure:
    - You are authenticated with GitHub CLI (run 'gh auth login')
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
    - You are authenticated with GitHub CLI (run 'gh auth login')
    - The PR exists
    - You have access to the repository"
fi

# Check if the diff is empty
if [ ! -s "$TEMP_DIR/pr.diff" ]; then
    warn "The pull request diff is empty"
    exit 0
fi

# Process the diff file to work with difftastic
csplit -f "$TEMP_DIR/diff-" "$TEMP_DIR/pr.diff" '/^diff --git/' '{*}' > /dev/null || error "Failed to process diff file"

# Counter for number of files processed
files_processed=0

# For each split diff file
for diff_file in "$TEMP_DIR"/diff-*; do
    if [ -f "$diff_file" ]; then
        # Extract the file paths
        old_file=$(grep '^--- a/' "$diff_file" | sed 's|^--- a/||')
        new_file=$(grep '^+++ b/' "$diff_file" | sed 's|^+++ b/||')
        
        if [ -n "$old_file" ] && [ -n "$new_file" ]; then
            echo -e "\n=== Showing diff for: $new_file ===\n"
            
            # Extract the content sections and create temporary files
            awk '/^-/{p=1;next} /^diff/{p=0} p' "$diff_file" | sed 's/^-//' > "$TEMP_DIR/old_content"
            awk '/^+/{p=1;next} /^diff/{p=0} p' "$diff_file" | sed 's/^+//' > "$TEMP_DIR/new_content"
            
            # Use difftastic to show the diff
            DIFFT_BACKGROUND="$BACKGROUND" difft "$TEMP_DIR/old_content" "$TEMP_DIR/new_content" || warn "Failed to process diff for $new_file"
            
            ((files_processed++))
        fi
    fi
done

success "Successfully processed $files_processed file(s)" 