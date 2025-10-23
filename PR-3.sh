#!/bin/bash

# Script to update job_stage from Pre_prod to Prod
# This script performs the following operations:
# 1. Request JiraID input
# 2. Verify values between QA and Stage files
# 3. Checkout to master branch
# 4. Git pull
# 5. Checkout to new branch
# 6. Update job_stage value to Prod
# 7. Show diff
# 8. Ask to proceed
# 9. Commit changes
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

# Step 2: Verify values match between files
print_info "Verifying ruleset values match between files..."

# Extract ruleset value from QA file (line 8)
QA_RULESET=$(sed -n '8p' "$QA_FILE" | sed 's/.*: *"\(.*\)"/\1/')

# Extract ruleset value from Stage file (line 25)
STAGE_RULESET=$(sed -n '25p' "$STAGE_FILE" | sed 's/.*name: *\(.*\)/\1/')

print_info "QA file ruleset (line 8): $QA_RULESET"
print_info "Stage file ruleset (line 25): $STAGE_RULESET"

if [[ "$QA_RULESET" != "$STAGE_RULESET" ]]; then
    print_error "Ruleset values don't match!"
    print_error "QA file (line 8): $QA_RULESET"
    print_error "Stage file (line 25): $STAGE_RULESET"
    exit 1
fi

print_success "Ruleset values match: $QA_RULESET"

# Step 3: Check current job_stage value (line 11)
print_info "Checking current job_stage value..."
CURRENT_JOB_STAGE=$(sed -n '11p' "$QA_FILE" | sed 's/.*value: *"\([^"]*\)".*/\1/')

print_info "Current job_stage (line 11): $CURRENT_JOB_STAGE"

if [[ "$CURRENT_JOB_STAGE" == "Prod" ]]; then
    print_warning "job_stage is already set to 'Prod'. Nothing to update."
    exit 0
fi

# Step 4: Checkout to master branch
print_info "Checking out to master branch..."
git checkout master

# Step 5: Git pull
print_info "Pulling latest changes from master..."
git pull origin master

# Step 6: Checkout to new branch or existing branch
BRANCH_NAME="tcsfsq-${JIRA_ID}-prod-update"
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

# Step 7: Update job_stage to Prod (line 11)
print_info "Updating job_stage to 'Prod' in QA file (line 11)..."

# Create a backup of the original QA file
cp "$QA_FILE" "${QA_FILE}.backup"

# Update line 11 specifically - the job_stage value to Prod
sed -i.tmp '11s/value: *"[^"]*"/value: "Prod"/' "$QA_FILE"
rm "${QA_FILE}.tmp"

# Verify the change was made by checking line 11
NEW_JOB_STAGE=$(sed -n '11p' "$QA_FILE" | sed 's/.*value: *"\([^"]*\)".*/\1/')
print_info "New job_stage value (line 11): $NEW_JOB_STAGE"

if [[ "$NEW_JOB_STAGE" == "Prod" ]]; then
    print_success "Successfully updated job_stage to: Prod"
else
    print_error "Failed to update job_stage. Restoring backup..."
    mv "${QA_FILE}.backup" "$QA_FILE"
    exit 1
fi

# Remove backup file
rm "${QA_FILE}.backup"

# Step 8: Show diff
print_info "Showing diff of changes:"
echo "----------------------------------------"
git diff "$QA_FILE" || true
echo "----------------------------------------"

# Step 9: Ask to proceed
echo ""
print_warning "Review the changes above."
echo -n "Do you want to proceed with committing and pushing these changes? (yes/no): "
read -r USER_CHOICE

case "$USER_CHOICE" in
    [Yy]|[Yy][Ee][Ss])
        # Step 10: Commit and push changes
        print_info "Adding and committing changes..."
        git add "$QA_FILE"
        COMMIT_MESSAGE="TCSFSQ: ${JIRA_ID} update to Prod"
        git commit -m "$COMMIT_MESSAGE"
        print_success "Committed changes with message: $COMMIT_MESSAGE"
        
        print_info "Pushing commit to remote repository..."
        git push origin "$BRANCH_NAME"
        print_success "Successfully pushed branch: $BRANCH_NAME"
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