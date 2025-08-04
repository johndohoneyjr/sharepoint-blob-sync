#!/bin/bash

# Test Script: Verify Blob Storage Contents
# This script lists files in the Azure Blob Storage container to verify the copy operation

set -e

# Load configuration from parent directory
if [ -f "../config.env" ]; then
    source "../config.env"
else
    echo "❌ Error: config.env not found in parent directory"
    echo "Please ensure config.env exists and is properly configured"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_info() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

log_step() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] STEP: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Function to check if container exists
check_container() {
    log_step "Checking if container exists: $CONTAINER_NAME"
    
    if az storage container show \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" &> /dev/null; then
        log "✅ Container '$CONTAINER_NAME' exists"
        return 0
    else
        echo "❌ Container '$CONTAINER_NAME' does not exist"
        echo "Please run the main script first to create the container and copy files"
        return 1
    fi
}

# Function to count total files
count_files() {
    log_step "Counting files in container"
    
    local file_count
    file_count=$(az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --query "length(@)" \
        --output tsv 2>/dev/null || echo "0")
    
    echo ""
    echo "📊 SUMMARY"
    echo "=========================================="
    echo "Total files in container: $file_count"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Container: $CONTAINER_NAME"
    echo ""
    
    return $file_count
}

# Function to show file hierarchy
show_hierarchy() {
    log_step "Retrieving file hierarchy"
    
    echo "📁 FILE HIERARCHY"
    echo "=========================================="
    
    # Get all blobs with their metadata
    local blob_list
    blob_list=$(az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --query "[].{name:name,size:properties.contentLength,modified:properties.lastModified}" \
        --output json 2>/dev/null)
    
    if [ "$?" -ne 0 ] || [ "$blob_list" = "[]" ]; then
        echo "No files found in container"
        return 1
    fi
    
    # Process and display hierarchy
    echo "$blob_list" | jq -r '.[] | "\(.name) (\(.size) bytes) [Modified: \(.modified | split("T")[0])]"' | while read -r file_info; do
        local file_path=$(echo "$file_info" | cut -d' ' -f1)
        local file_details=$(echo "$file_info" | cut -d' ' -f2-)
        
        # Count directory depth
        local depth=$(echo "$file_path" | tr -cd '/' | wc -c | tr -d ' ')
        local indent=""
        
        # Create indentation based on depth
        for i in $(seq 1 $depth); do
            indent="  $indent"
        done
        
        # Extract filename
        local filename=$(basename "$file_path")
        
        echo "${indent}📄 $filename $file_details"
    done
    
    echo ""
}

# Function to show folder structure
show_folder_structure() {
    log_step "Analyzing folder structure"
    
    echo "📂 FOLDER STRUCTURE"
    echo "=========================================="
    
    # Get unique folder paths
    local folders
    folders=$(az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --query "[].name" \
        --output tsv 2>/dev/null | \
        grep "/" | \
        sed 's|/[^/]*$||' | \
        sort -u)
    
    if [ -n "$folders" ]; then
        echo "$folders" | while read -r folder; do
            if [ -n "$folder" ]; then
                local file_count_in_folder
                file_count_in_folder=$(az storage blob list \
                    --container-name "$CONTAINER_NAME" \
                    --account-name "$STORAGE_ACCOUNT_NAME" \
                    --account-key "$STORAGE_ACCOUNT_KEY" \
                    --prefix "$folder/" \
                    --query "length(@)" \
                    --output tsv 2>/dev/null)
                
                echo "📁 $folder/ ($file_count_in_folder files)"
            fi
        done
    else
        echo "All files are in the root directory"
    fi
    
    echo ""
}

# Function to show file types
show_file_types() {
    log_step "Analyzing file types"
    
    echo "📋 FILE TYPES"
    echo "=========================================="
    
    # Get file extensions and count them
    az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --query "[].name" \
        --output tsv 2>/dev/null | \
        sed 's/.*\.//' | \
        sort | uniq -c | sort -nr | \
        while read -r count ext; do
            echo "  .$ext: $count files"
        done
    
    echo ""
}

# Function to show size statistics
show_size_stats() {
    log_step "Calculating size statistics"
    
    echo "💾 SIZE STATISTICS"
    echo "=========================================="
    
    # Get total size
    local total_size
    total_size=$(az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --query "sum([].properties.contentLength)" \
        --output tsv 2>/dev/null)
    
    if [ -n "$total_size" ] && [ "$total_size" -gt 0 ]; then
        # Convert bytes to human readable format
        if [ "$total_size" -lt 1024 ]; then
            echo "Total size: ${total_size} bytes"
        elif [ "$total_size" -lt 1048576 ]; then
            echo "Total size: $((total_size / 1024)) KB"
        elif [ "$total_size" -lt 1073741824 ]; then
            echo "Total size: $((total_size / 1048576)) MB"
        else
            echo "Total size: $((total_size / 1073741824)) GB"
        fi
        
        # Show average file size
        local file_count
        file_count=$(az storage blob list \
            --container-name "$CONTAINER_NAME" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --account-key "$STORAGE_ACCOUNT_KEY" \
            --query "length(@)" \
            --output tsv 2>/dev/null)
        
        if [ "$file_count" -gt 0 ]; then
            local avg_size=$((total_size / file_count))
            echo "Average file size: $avg_size bytes"
        fi
    else
        echo "No size information available"
    fi
    
    echo ""
}

# Function to show recent files
show_recent_files() {
    log_step "Finding recently modified files"
    
    echo "🕒 RECENTLY MODIFIED FILES (Last 10)"
    echo "=========================================="
    
    az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --query "sort_by(@, &properties.lastModified)[-10:].{name:name,modified:properties.lastModified,size:properties.contentLength}" \
        --output table 2>/dev/null || echo "No recent files found"
    
    echo ""
}

# Main execution
main() {
    echo "🧪 Azure Blob Storage Test Report"
    echo "Generated: $(date)"
    echo "=================================================="
    echo ""
    
    log_info "Configuration:"
    log_info "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log_info "  Container: $CONTAINER_NAME"
    echo ""
    
    # Check if Azure CLI is available
    if ! command -v az &> /dev/null; then
        echo "❌ Azure CLI not found. Please install it first:"
        echo "   brew install azure-cli"
        exit 1
    fi
    
    # Check container existence
    if ! check_container; then
        exit 1
    fi
    
    # Run all tests
    count_files
    show_folder_structure
    show_file_types
    show_size_stats
    show_recent_files
    show_hierarchy
    
    echo "✅ Test completed successfully!"
    echo ""
    echo "💡 Tips:"
    echo "   - Run '../copy_sharepoint_to_blob.sh' to sync new files"
    echo "   - Check Azure Portal for detailed blob properties"
    echo "   - Use 'az storage blob list' for custom queries"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Test script to verify Azure Blob Storage contents after SharePoint sync"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo ""
        echo "Reports:"
        echo "  - File count and total size"
        echo "  - Folder structure and hierarchy"
        echo "  - File type distribution"
        echo "  - Recently modified files"
        echo "  - Complete file listing with details"
        exit 0
        ;;
esac

# Run main function
main
