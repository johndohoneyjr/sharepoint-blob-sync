#!/bin/bash

# Crontab Setup Script for SharePoint Sync
# This script configures crontab to run the SharePoint sync every hour

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sharepoint-sync-cron.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

log_info() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "SharePoint Sync Crontab Setup Script"
    echo ""
    echo "Options:"
    echo "  --install               Install the cron job (runs every hour)"
    echo "  --install-custom CRON   Install with custom cron expression"
    echo "  --uninstall             Remove the cron job"
    echo "  --status                Show current cron job status"
    echo "  --test                  Test run the sync script manually"
    echo "  --help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --install                          # Run every hour"
    echo "  $0 --install-custom '0 */2 * * *'     # Run every 2 hours"
    echo "  $0 --install-custom '0 9,17 * * *'    # Run at 9 AM and 5 PM"
    echo "  $0 --status                           # Check if cron job exists"
    echo "  $0 --test                             # Test the sync script"
    echo ""
    echo "Cron Expression Format:"
    echo "  ┌───────────── minute (0 - 59)"
    echo "  │ ┌─────────── hour (0 - 23)"
    echo "  │ │ ┌───────── day of month (1 - 31)"
    echo "  │ │ │ ┌─────── month (1 - 12)"
    echo "  │ │ │ │ ┌───── day of week (0 - 6) (Sunday to Saturday)"
    echo "  │ │ │ │ │"
    echo "  * * * * *"
}

# Function to check if cron job already exists
check_existing_cron() {
    if crontab -l 2>/dev/null | grep -q "$SYNC_SCRIPT"; then
        return 0  # Exists
    else
        return 1  # Doesn't exist
    fi
}

# Function to install cron job
install_cron() {
    local cron_expression="$1"
    local cron_line="$cron_expression $SYNC_SCRIPT >/dev/null 2>&1"
    
    log "Installing SharePoint sync cron job..."
    log_info "Cron expression: $cron_expression"
    log_info "Script path: $SYNC_SCRIPT"
    
    # Check if script exists and is executable
    if [ ! -f "$SYNC_SCRIPT" ]; then
        log_error "Sync script not found: $SYNC_SCRIPT"
        exit 1
    fi
    
    if [ ! -x "$SYNC_SCRIPT" ]; then
        log_info "Making sync script executable..."
        chmod +x "$SYNC_SCRIPT"
    fi
    
    # Check if cron job already exists
    if check_existing_cron; then
        log_warning "Cron job already exists. Removing old entry first..."
        uninstall_cron_silent
    fi
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    
    if [ $? -eq 0 ]; then
        log "✅ Cron job installed successfully!"
        log_info "The SharePoint sync will run: $cron_expression"
        log_info "Logs will be stored in: $SCRIPT_DIR/logs/"
    else
        log_error "Failed to install cron job"
        exit 1
    fi
}

# Function to uninstall cron job (silent version)
uninstall_cron_silent() {
    crontab -l 2>/dev/null | grep -v "$SYNC_SCRIPT" | crontab -
}

# Function to uninstall cron job
uninstall_cron() {
    log "Removing SharePoint sync cron job..."
    
    if ! check_existing_cron; then
        log_warning "No cron job found for SharePoint sync"
        return 0
    fi
    
    uninstall_cron_silent
    
    if [ $? -eq 0 ]; then
        log "✅ Cron job removed successfully!"
    else
        log_error "Failed to remove cron job"
        exit 1
    fi
}

# Function to show cron job status
show_status() {
    log "Checking SharePoint sync cron job status..."
    
    if check_existing_cron; then
        log "✅ Cron job is installed:"
        crontab -l | grep "$SYNC_SCRIPT"
        echo ""
        log_info "Log directory: $SCRIPT_DIR/logs/"
        
        # Show recent log files
        local log_dir="$SCRIPT_DIR/logs"
        if [ -d "$log_dir" ]; then
            log_info "Recent log files:"
            ls -la "$log_dir"/*.log 2>/dev/null | tail -5 || log_info "No log files found yet"
        fi
    else
        log_warning "No cron job found for SharePoint sync"
        log_info "Run '$0 --install' to set up the cron job"
    fi
}

# Function to test the sync script
test_sync() {
    log "Testing SharePoint sync script..."
    
    if [ ! -f "$SYNC_SCRIPT" ]; then
        log_error "Sync script not found: $SYNC_SCRIPT"
        exit 1
    fi
    
    if [ ! -x "$SYNC_SCRIPT" ]; then
        log_info "Making sync script executable..."
        chmod +x "$SYNC_SCRIPT"
    fi
    
    log_info "Running sync script manually..."
    "$SYNC_SCRIPT"
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log "✅ Test completed successfully!"
    else
        log_error "Test failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Function to setup initial environment
setup_environment() {
    log "Setting up cron job environment..."
    
    # Create logs directory
    mkdir -p "$SCRIPT_DIR/logs"
    
    # Make scripts executable
    chmod +x "$SYNC_SCRIPT" 2>/dev/null || true
    chmod +x "$0" 2>/dev/null || true
    
    log_info "Environment setup completed"
}

# Main script execution
main() {
    case "${1:-}" in
        --install)
            setup_environment
            install_cron "0 * * * *"  # Every hour
            ;;
        --install-custom)
            if [ -z "$2" ]; then
                log_error "Custom cron expression required"
                echo "Example: $0 --install-custom '0 */2 * * *'"
                exit 1
            fi
            setup_environment
            install_cron "$2"
            ;;
        --uninstall)
            uninstall_cron
            ;;
        --status)
            show_status
            ;;
        --test)
            test_sync
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Invalid option: ${1:-'(none)'}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
