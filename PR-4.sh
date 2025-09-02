#!/bin/bash

# Script to update Production ruleset from Stage
# This script performs the following operations:
# 1. Request JiraID input
# 2. Verify QA job_stage is "Prod"
# 3. Verify values between QA and Stage files
# 4. Checkout to main branch
# 5. Git pull
# 6. Checkout to new branch
# 7. Update Production ruleset from Stage
# 8. Show diff
# 9. Ask to proceed
# 10. Request CMR-ID
# 11. Commit changes
# 12. Push commit

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
QA_FILE="envs/integration/env-2a/ts-csp-s3-file-sync-qa-values.yaml"
STAGE_FILE="envs/stage/stg-1/ts-csp-s3-file-sync-values.yaml"
PROD_FILE="envs/prod/prd-1/ts-csp-s3-file-sync-values.yaml"

# Check if files exist
if [[ ! -f "$QA_FILE" ]]; then
    print_error "QA file not found: $QA_FILE"
    exit 1
fi

if [[ ! -f "$STAGE_FILE" ]]; then
    print_error "Stage file not found: $STAGE_FILE"
    exit 1
fi

if [[ ! -f "$PROD_FILE" ]]; then
    print_error "Production file not found: $PROD_FILE"
    exit 1
fi

# Step 2: Verify QA job_stage is "Prod"
print_info "Verifying QA job_stage is 'Prod'..."
QA_JOB_STAGE=$(sed -n '11p' "$QA_FILE" | sed 's/.*value: *"\([^"]*\)".*/\1/')

print_info "QA job_stage (line 11): $QA_JOB_STAGE"

if [[ "$QA_JOB_STAGE" != "Prod" ]]; then
    print_error "QA job_stage must be 'Prod' but found: $QA_JOB_STAGE"
    print_error "Please run the stage-to-prod script first to update QA job_stage to 'Prod'"
    exit 1
fi

print_success "QA job_stage is correctly set to: $QA_JOB_STAGE"

# Step 3: Verify values match between QA and Stage files
print_info "Verifying ruleset values match between QA and Stage files..."

# Extract ruleset value from QA file (line 8)
QA_RULESET=$(sed -n '8p' "$QA_FILE" | sed 's/.*: *"\([^"]*\)"/\1/')

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

# Step 4: Checkout to main branch
print_info "Checking out to main branch..."
git checkout main

# Step 5: Git pull
print_info "Pulling latest changes from main..."
git pull origin main

# Step 6: Checkout to new branch
BRANCH_NAME="tcsfs-${JIRA_ID}-to-prod"
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

# Step 7: Update Production ruleset from Stage (line 25)
print_info "Updating Production ruleset from Stage (line 25)..."

# Get current production ruleset
CURRENT_PROD_RULESET=$(sed -n '25p' "$PROD_FILE" | sed 's/.*name: *\(.*\)/\1/')
print_info "Current Production ruleset (line 25): $CURRENT_PROD_RULESET"

if [[ "$CURRENT_PROD_RULESET" == "$STAGE_RULESET" ]]; then
    print_warning "Production ruleset is already same as Stage ruleset: $STAGE_RULESET"
    print_warning "No update needed. Exiting..."
    exit 0
fi

# Create a backup of the original Production file
cp "$PROD_FILE" "${PROD_FILE}.backup"

# Update line 25 - the production ruleset value from stage
sed -i.tmp "25s/name: .*/name: $STAGE_RULESET/" "$PROD_FILE"
rm "${PROD_FILE}.tmp"

# Verify the change was made by checking line 25
NEW_PROD_RULESET=$(sed -n '25p' "$PROD_FILE" | sed 's/.*name: *\(.*\)/\1/')
print_info "New Production ruleset (line 25): $NEW_PROD_RULESET"

if [[ "$NEW_PROD_RULESET" == "$STAGE_RULESET" ]]; then
    print_success "Successfully updated Production ruleset to: $NEW_PROD_RULESET"
else
    print_error "Failed to update Production ruleset. Restoring backup..."
    mv "${PROD_FILE}.backup" "$PROD_FILE"
    exit 1
fi

# Remove backup file
rm "${PROD_FILE}.backup"

# Step 8: Show diff
print_info "Showing diff of changes:"
echo "----------------------------------------"
git diff "$PROD_FILE" || true
echo "----------------------------------------"

# Step 9: Ask to proceed
echo ""
print_warning "Review the changes above."
echo -n "Do you want to proceed with committing and pushing these changes? (yes/no): "
read -r USER_CHOICE

case "$USER_CHOICE" in
    [Yy]|[Yy][Ee][Ss])
        # Step 10: Request CMR-ID
        echo -n "CMR-ID: "
        read -r CMR_ID
        
        if [[ -z "$CMR_ID" ]]; then
            print_error "CMR-ID cannot be empty"
            exit 1
        fi
        
        print_info "Using CMR-ID: $CMR_ID"
        
        # Step 11: Commit changes
        print_info "Adding and committing changes..."
        git add "$PROD_FILE"
        COMMIT_MESSAGE="${CMR_ID}: TCFS ${JIRA_ID} to PRD-1"
        git commit -m "$COMMIT_MESSAGE"
        print_success "Committed changes with message: $COMMIT_MESSAGE"
        
        # Step 12: Push changes
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
