#!/bin/bash

# SharePoint to Azure Blob Storage Sync Script - Cron Version
# Optimized for automated execution via crontab
# Runs every hour to sync new/modified files

# Exit on any error
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration from the main config file (secure approach)
load_config() {
    local config_file="$BASE_DIR/config.env"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file '$config_file' not found!"
        log_error "Please ensure config.env exists in the parent directory"
        send_notification "SharePoint Sync Failed" "Configuration file missing" "ERROR"
        exit 1
    fi
    
    # Source the configuration file
    source "$config_file"
    
    # Validate required configuration
    local required_vars=(
        "SHAREPOINT_SITE_URL"
        "SHAREPOINT_LIBRARY_NAME" 
        "STORAGE_ACCOUNT_NAME"
        "STORAGE_ACCOUNT_KEY"
        "CONTAINER_NAME"
        "SP_NAME"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required configuration variables: ${missing_vars[*]}"
        log_error "Please check your config.env file"
        send_notification "SharePoint Sync Failed" "Missing configuration: ${missing_vars[*]}" "ERROR"
        exit 1
    fi
    
    # Set defaults for optional variables
    FILE_FILTER="${FILE_FILTER:-*}"
    SHAREPOINT_FOLDER="${SHAREPOINT_FOLDER:-}"
    DELETE_AFTER_COPY="${DELETE_AFTER_COPY:-false}"
    
    # Cron-specific configuration
    LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
    SYNC_TIMEOUT="${SYNC_TIMEOUT:-3600}"
    MAX_RETRIES="${MAX_RETRIES:-3}"
    RETRY_DELAY="${RETRY_DELAY:-300}"
}

# Logging configuration
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/sharepoint-sync-$(date '+%Y-%m-%d').log"
ERROR_LOG="$LOG_DIR/sharepoint-sync-error-$(date '+%Y-%m-%d').log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG" >&2
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "$LOG_FILE"
}

# Function to send notification (optional - configure as needed)
send_notification() {
    local subject="$1"
    local message="$2"
    local status="$3"  # SUCCESS or ERROR
    
    # Example: Send email notification (uncomment and configure as needed)
    # echo "$message" | mail -s "$subject" admin@example.com
    
    # Example: Send to Slack (uncomment and configure webhook URL)
    # curl -X POST -H 'Content-type: application/json' \
    #   --data "{\"text\":\"$subject: $message\"}" \
    #   YOUR_SLACK_WEBHOOK_URL
    
    # For now, just log the notification
    log_info "NOTIFICATION: $subject - $message"
}

# Function to check if running in cron environment
is_cron_env() {
    [ -z "$TERM" ] || [ "$TERM" = "dumb" ]
}

# Function to setup environment for cron
setup_cron_environment() {
    # Set PATH to include common locations for commands
    export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
    
    # Set Azure CLI location if needed
    if [ -f "/opt/homebrew/bin/az" ]; then
        export PATH="/opt/homebrew/bin:$PATH"
    elif [ -f "/usr/local/bin/az" ]; then
        export PATH="/usr/local/bin:$PATH"
    fi
    
    # Disable Azure CLI telemetry for cron
    export AZURE_CORE_COLLECT_TELEMETRY=false
    
    # Set home directory if not set
    if [ -z "$HOME" ]; then
        export HOME="/Users/$(whoami)"
    fi
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v az &> /dev/null; then
        missing_deps+=("azure-cli")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        send_notification "SharePoint Sync Failed" "Missing dependencies: ${missing_deps[*]}" "ERROR"
        exit 1
    fi
    
    log_info "All dependencies are available"
}

# Function to load service principal credentials
load_service_principal() {
    local credentials_file="$BASE_DIR/.sp_credentials"
    
    if [ ! -f "$credentials_file" ]; then
        log_error "Service principal credentials file not found: $credentials_file"
        log_error "Please run the main script with --setup first"
        send_notification "SharePoint Sync Failed" "Service principal not configured" "ERROR"
        exit 1
    fi
    
    source "$credentials_file"
    
    if [ -z "$SP_CLIENT_ID" ] || [ -z "$SP_CLIENT_SECRET" ] || [ -z "$SP_TENANT_ID" ]; then
        log_error "Invalid service principal credentials"
        send_notification "SharePoint Sync Failed" "Invalid service principal credentials" "ERROR"
        exit 1
    fi
    
    log_info "Service principal credentials loaded successfully"
}

# Function to get access token
get_access_token() {
    log_info "Authenticating with service principal..."
    
    local token_response
    token_response=$(curl -s -X POST "https://login.microsoftonline.com/$SP_TENANT_ID/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$SP_CLIENT_ID" \
        -d "client_secret=$SP_CLIENT_SECRET" \
        -d "scope=https://graph.microsoft.com/.default")
    
    ACCESS_TOKEN=$(echo "$token_response" | jq -r '.access_token // empty')
    
    if [ -z "$ACCESS_TOKEN" ]; then
        local error_description
        error_description=$(echo "$token_response" | jq -r '.error_description // "Unknown error"')
        log_error "Failed to get access token: $error_description"
        send_notification "SharePoint Sync Failed" "Authentication failed: $error_description" "ERROR"
        exit 1
    fi
    
    log_info "Successfully authenticated with service principal"
}

# Function to run the sync operation
run_sync() {
    log "Starting SharePoint to Azure Blob Storage sync operation"
    log_info "Configuration:"
    log_info "  SharePoint Site: $SHAREPOINT_SITE_URL"
    log_info "  Library Name: $SHAREPOINT_LIBRARY_NAME"
    log_info "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log_info "  Container: $CONTAINER_NAME"
    log_info "  File Filter: $FILE_FILTER"
    log_info "  SharePoint Folder: ${SHAREPOINT_FOLDER:-'(root)'}"
    
    # Change to base directory to use the main script
    cd "$BASE_DIR"
    
    # Run the main sync script with output capture
    local sync_output
    local sync_exit_code
    
    if sync_output=$(./copy_sharepoint_to_blob.sh --file-filter "$FILE_FILTER" --library-name "$SHAREPOINT_LIBRARY_NAME" ${SHAREPOINT_FOLDER:+--folder "$SHAREPOINT_FOLDER"} 2>&1); then
        sync_exit_code=0
        log "Sync operation completed successfully"
        
        # Extract file count from output
        local file_count
        file_count=$(echo "$sync_output" | grep -o "Successfully copied: [0-9]* files" | grep -o "[0-9]*" || echo "0")
        
        log_info "Files processed: $file_count"
        
        # Send success notification only if files were processed
        if [ "$file_count" -gt 0 ]; then
            send_notification "SharePoint Sync Successful" "Successfully synced $file_count files" "SUCCESS"
        else
            log_info "No new files to sync"
        fi
    else
        sync_exit_code=$?
        log_error "Sync operation failed with exit code: $sync_exit_code"
        log_error "Error output: $sync_output"
        send_notification "SharePoint Sync Failed" "Sync operation failed. Check logs for details." "ERROR"
        exit $sync_exit_code
    fi
}

# Function to cleanup old log files (configurable retention)
cleanup_logs() {
    find "$LOG_DIR" -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
    log_info "Log cleanup completed (retention: ${LOG_RETENTION_DAYS} days)"
}

# Main execution
main() {
    # Load configuration first (before any operations that might need logging)
    load_config
    
    # Setup environment for cron
    if is_cron_env; then
        setup_cron_environment
        log_info "Running in cron environment"
    else
        log_info "Running in interactive environment"
    fi
    
    # Create lock file to prevent multiple instances
    local lock_file="/tmp/sharepoint-sync.lock"
    
    if [ -f "$lock_file" ]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
        
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another sync process is already running (PID: $lock_pid)"
            exit 1
        else
            log_info "Removing stale lock file"
            rm -f "$lock_file"
        fi
    fi
    
    # Create lock file with current PID
    echo $$ > "$lock_file"
    
    # Ensure lock file is removed on exit
    trap 'rm -f "$lock_file"' EXIT
    
    # Run the sync process
    check_dependencies
    load_service_principal
    run_sync
    cleanup_logs
    
    log "SharePoint sync job completed successfully"
}

# Error handling
trap 'log_error "Script interrupted or failed"; rm -f /tmp/sharepoint-sync.lock; exit 1' INT TERM

# Run main function
main "$@"
