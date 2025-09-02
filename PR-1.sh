#!/bin/bash

# Script to update QA file with new ET-Rules filename and set to Pre_prod
# This script performs the following operations:
# 1. Request JiraID and ET-Rules File Name inputs
# 2. Checkout to main branch
# 3. Git pull
# 4. Checkout to new branch
# 5. Update QA file: line 8 with ET-Rules filename, line 11 with "Pre_prod"
# 6. Show diff
# 7. Ask to proceed
# 8. Commit changes
# 9. Push commit

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

# Step 1: Request inputs
echo -n "JiraID: "
read -r JIRA_ID

if [[ -z "$JIRA_ID" ]]; then
    print_error "JiraID cannot be empty"
    exit 1
fi

echo -n "ET-Rules File Name: "
read -r ET_RULES_FILENAME

if [[ -z "$ET_RULES_FILENAME" ]]; then
    print_error "ET-Rules File Name cannot be empty"
    exit 1
fi

print_info "Using JiraID: $JIRA_ID"
print_info "Using ET-Rules File Name: $ET_RULES_FILENAME"

# Define file path
QA_FILE="envs/integration/env-2a/ts-csp-s3-file-sync-qa-values.yaml"

# Check if file exists
if [[ ! -f "$QA_FILE" ]]; then
    print_error "QA file not found: $QA_FILE"
    exit 1
fi

# Step 2: Checkout to main branch
print_info "Checking out to main branch..."
git checkout main

# Step 3: Git pull
print_info "Pulling latest changes from main..."
git pull origin main

# Step 4: Checkout to new branch
BRANCH_NAME="tcsfsq-${JIRA_ID}-to-stage"
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

# Step 5: Update QA file
print_info "Updating QA file..."

# Get current values
CURRENT_RULESET=$(sed -n '8p' "$QA_FILE" | sed 's/.*: *"\([^"]*\)".*/\1/')
CURRENT_JOB_STAGE=$(sed -n '11p' "$QA_FILE" | sed 's/.*value: *"\([^"]*\)".*/\1/')

print_info "Current Ruleset (line 8): $CURRENT_RULESET"
print_info "Current job_stage (line 11): $CURRENT_JOB_STAGE"

# Check if updates are needed
NEEDS_UPDATE=false

if [[ "$CURRENT_RULESET" != "$ET_RULES_FILENAME" ]]; then
    print_info "Ruleset needs update: $CURRENT_RULESET -> $ET_RULES_FILENAME"
    NEEDS_UPDATE=true
fi

if [[ "$CURRENT_JOB_STAGE" != "Pre_prod" ]]; then
    print_info "job_stage needs update: $CURRENT_JOB_STAGE -> Pre_prod"
    NEEDS_UPDATE=true
fi

if [[ "$NEEDS_UPDATE" == "false" ]]; then
    print_warning "No updates needed. File already has the correct values."
    print_warning "Ruleset: $CURRENT_RULESET"
    print_warning "job_stage: $CURRENT_JOB_STAGE"
    exit 0
fi

# Create a backup of the original QA file
cp "$QA_FILE" "${QA_FILE}.backup"

# Update line 8 - ET-Rules filename
print_info "Updating line 8 with ET-Rules filename: $ET_RULES_FILENAME"
sed -i.tmp "8s/: *\"[^\"]*\"/: \"$ET_RULES_FILENAME\"/" "$QA_FILE"
rm "${QA_FILE}.tmp"

# Update line 11 - job_stage to Pre_prod
print_info "Updating line 11 with job_stage: Pre_prod"
sed -i.tmp '11s/value: *"[^"]*"/value: "Pre_prod"/' "$QA_FILE"
rm "${QA_FILE}.tmp"

# Verify the changes were made
NEW_RULESET=$(sed -n '8p' "$QA_FILE" | sed 's/.*: *"\([^"]*\)".*/\1/')
NEW_JOB_STAGE=$(sed -n '11p' "$QA_FILE" | sed 's/.*value: *"\([^"]*\)".*/\1/')

print_info "New Ruleset (line 8): $NEW_RULESET"
print_info "New job_stage (line 11): $NEW_JOB_STAGE"

# Verify updates were successful
UPDATE_SUCCESS=true

if [[ "$NEW_RULESET" != "$ET_RULES_FILENAME" ]]; then
    print_error "Failed to update Ruleset"
    UPDATE_SUCCESS=false
fi

if [[ "$NEW_JOB_STAGE" != "Pre_prod" ]]; then
    print_error "Failed to update job_stage"
    UPDATE_SUCCESS=false
fi

if [[ "$UPDATE_SUCCESS" == "false" ]]; then
    print_error "Updates failed. Restoring backup..."
    mv "${QA_FILE}.backup" "$QA_FILE"
    exit 1
fi

print_success "Successfully updated QA file:"
print_success "  - Ruleset: $NEW_RULESET"
print_success "  - job_stage: $NEW_JOB_STAGE"

# Remove backup file
rm "${QA_FILE}.backup"

# Step 6: Show diff
print_info "Showing diff of changes:"
echo "----------------------------------------"
git diff "$QA_FILE" || true
echo "----------------------------------------"

# Step 7: Ask to proceed
echo ""
print_warning "Review the changes above."
echo -n "Do you want to proceed with committing and pushing these changes? (yes/no): "
read -r USER_CHOICE

case "$USER_CHOICE" in
    [Yy]|[Yy][Ee][Ss])
        # Step 8: Commit changes
        print_info "Adding and committing changes..."
        git add "$QA_FILE"
        COMMIT_MESSAGE="TCSFSQ: ${JIRA_ID} update to Pre_prod"
        git commit -m "$COMMIT_MESSAGE"
        print_success "Committed changes with message: $COMMIT_MESSAGE"
        
        # Step 9: Push changes
        print_info "Publishing branch to remote repository..."
        git push origin "$BRANCH_NAME"
        print_success "Successfully published branch: $BRANCH_NAME"
        print_info "You can now create a pull request for this branch"
        ;;
    [Nn]|[Nn][Oo])
        print_warning "Operation cancelled by user"
        print_info "Changes are staged but not committed. Branch $BRANCH_NAME remains local."
        ;;
    *)
        print_error "Invalid input. Please enter 'yes' or 'no'"
        print_warning "Operation cancelled. Branch $BRANCH_NAME remains local."
        exit 1
        ;;
esac

print_success "Script completed successfully!"
