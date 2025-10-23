#!/bin/bash

# Script to update ruleset value from QA to Stage environment
# This script performs the following operations:
# 1. Request JiraID input
# 2. Checkout to master branch
# 3. Git pull
# 4. Checkout to new branch
# 5. Read value from QA file
# 6. Update value in Stage file
# 7. Show diff
# 8. Commit changes
# 9. Request user confirmation
# 10. Push commit

set -e  # Exit on any error

# ANSI color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "This script must be run from within a git repository"
    exit 1
fi

# Step 1: Request JiraID input
echo -n "JiraID: "
read -r JIRA_ID

if [[ -z "$JIRA_ID" ]]; then
    print_error "JiraID cannot be empty"
    exit 1
fi

print_info "Using JiraID: $JIRA_ID"

# Define file paths
QA_FILE="envs/box-dev/us-dev-2/ts-csp-s3-file-sync-qa-values.yaml"
STAGE_FILE="envs/stage/stg-1/ts-csp-s3-file-sync-values.yaml"

# Check if files exist
if [[ ! -f "$QA_FILE" ]]; then
    print_error "QA file not found: $QA_FILE"
    exit 1
fi

if [[ ! -f "$STAGE_FILE" ]]; then
    print_error "Stage file not found: $STAGE_FILE"
    exit 1
fi

# Step 2: Checkout to master branch
print_info "Checking out to master branch..."
git checkout master

# Step 3: Git pull
print_info "Pulling latest changes from master..."
git pull origin master

# Step 4: Checkout to new branch or existing branch
BRANCH_NAME="tcsfs-${JIRA_ID}-stage-change"
print_info "Checking for existing branch: $BRANCH_NAME"

# Check if branch exists locally
if git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
    print_warning "Branch $BRANCH_NAME already exists locally. Checking out to existing branch..."
    git checkout "$BRANCH_NAME"
    print_info "Pulling latest changes for existing branch..."
    git pull origin "$BRANCH_NAME" 2>/dev/null || print_warning "Could not pull from remote (branch may not exist remotely yet)"
else
    # Check if branch exists on remote
    if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
        print_warning "Branch $BRANCH_NAME exists on remote. Checking out and tracking remote branch..."
        git checkout -b "$BRANCH_NAME" origin/"$BRANCH_NAME"
    else
        print_info "Creating new branch: $BRANCH_NAME"
        git checkout -b "$BRANCH_NAME"
    fi
fi

# Step 5: Read value from QA file (line 8)
print_info "Reading value from QA file..."
QA_VALUE=$(sed -n '8p' "$QA_FILE" | sed 's/.*: *"\(.*\)"/\1/')

if [[ -z "$QA_VALUE" ]]; then
    print_error "Could not extract value from line 8 of $QA_FILE"
    exit 1
fi

print_success "Extracted value from QA file: $QA_VALUE"

# Step 6: Update value in Stage file (line 25)
print_info "Updating value in Stage file..."

# Read the current value from stage file for comparison
CURRENT_STAGE_VALUE=$(sed -n '25p' "$STAGE_FILE" | sed 's/.*name: *\(.*\)/\1/')
print_info "Current stage file value: $CURRENT_STAGE_VALUE"

# Create a backup of the original stage file
cp "$STAGE_FILE" "${STAGE_FILE}.backup"

# Update line 25 in the stage file
sed -i.tmp "25s/name: .*/name: $QA_VALUE/" "$STAGE_FILE"
rm "${STAGE_FILE}.tmp"

print_success "Updated Stage file with new value: $QA_VALUE"

# Step 7: Show diff
print_info "Showing diff of changes:"
echo "----------------------------------------"
git diff "$STAGE_FILE" || true
echo "----------------------------------------"

# Step 8: Commit file
print_info "Adding and committing changes..."
git add "$STAGE_FILE"
COMMIT_MESSAGE="TCSFS: ${JIRA_ID} File update to stage"
git commit -m "$COMMIT_MESSAGE"
print_success "Committed changes with message: $COMMIT_MESSAGE"

# Step 9: Request user to proceed
echo ""
print_warning "Review the changes above."
echo -n "Do you want to push the commit? (yes/no): "
read -r USER_CHOICE

case "$USER_CHOICE" in
    [Yy]|[Yy][Ee][Ss])
        # Step 10: Push the commit
        print_info "Pushing commit to remote repository..."
        git push origin "$BRANCH_NAME"
        print_success "Successfully pushed branch: $BRANCH_NAME"
        print_info "You can now create a pull request for this branch"
        ;;
    [Nn]|[Nn][Oo])
        print_warning "Commit not pushed. Branch $BRANCH_NAME remains local."
        print_info "To push later, run: git push origin $BRANCH_NAME"
        ;;
    *)
        print_error "Invalid input. Please enter 'yes' or 'no'"
        print_warning "Commit not pushed. Branch $BRANCH_NAME remains local."
        exit 1
        ;;
esac

print_success "Script completed successfully!"
