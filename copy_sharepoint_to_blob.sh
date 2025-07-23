#!/bin/bash

# SharePoint to Azure Blob Storage Copy Script
# Uses Service Principal authentication with Microsoft Graph API permissions

set -e

# Load configuration from file
load_config() {
    local config_file="config.env"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file '$config_file' not found!"
        log_info "Please copy 'config.env.template' to 'config.env' and customize your settings"
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
        log_info "Please check your config.env file"
        exit 1
    fi
    
    # Set defaults for optional variables
    FILE_FILTER="${FILE_FILTER:-*.pdf}"
    SHAREPOINT_FOLDER="${SHAREPOINT_FOLDER:-}"
    DELETE_AFTER_COPY="${DELETE_AFTER_COPY:-false}"
    FORCE_RECREATE_SP="${FORCE_RECREATE_SP:-false}"
    VERBOSE_LOGGING="${VERBOSE_LOGGING:-false}"
}

# Service Principal Configuration (will be loaded from .sp_credentials)
SP_CLIENT_ID=""
SP_CLIENT_SECRET=""
SP_TENANT_ID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" >&2
}

log_info() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" >&2
}

log_step() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] STEP: $1${NC}" >&2
}

# Function to check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
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
        log_info "Install with: brew install ${missing_deps[*]}"
        exit 1
    fi
    
    log "All dependencies are available"
}

# Function to create service principal with required permissions
create_service_principal() {
    log_step "Creating Service Principal with Microsoft Graph permissions"
    
    # Check if already logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Get tenant ID
    SP_TENANT_ID=$(az account show --query tenantId -o tsv)
    log_info "Tenant ID: $SP_TENANT_ID"
    
    # Check if service principal already exists
    local existing_sp
    existing_sp=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null)
    
    if [ -n "$existing_sp" ] && [ "$existing_sp" != "null" ]; then
        log_warning "Service Principal '$SP_NAME' already exists"
        SP_CLIENT_ID="$existing_sp"
        log_info "Using existing Service Principal: $SP_CLIENT_ID"
        
        # Reset client secret
        log_info "Creating new client secret..."
        SP_CLIENT_SECRET=$(az ad sp credential reset --id "$SP_CLIENT_ID" --query password -o tsv)
    else
        log "Creating new Service Principal: $SP_NAME"
        
        # Create service principal
        local sp_output
        sp_output=$(az ad sp create-for-rbac --name "$SP_NAME" --skip-assignment --query "{appId:appId,password:password}" -o json)
        
        SP_CLIENT_ID=$(echo "$sp_output" | jq -r '.appId')
        SP_CLIENT_SECRET=$(echo "$sp_output" | jq -r '.password')
        
        log "Service Principal created successfully"
        log_info "Client ID: $SP_CLIENT_ID"
    fi
    
    # Wait a moment for propagation
    sleep 10
    
    # Add Microsoft Graph API permissions
    log_info "Adding Microsoft Graph API permissions..."
    
    # Get Microsoft Graph API app ID
    local graph_app_id="00000003-0000-0000-c000-000000000000"
    
    # Add Sites.ReadWrite.All permission (Application permission)
    local sites_permission_id="9492366f-7969-46a4-8d15-ed1a20078fff"  # Sites.ReadWrite.All
    local files_permission_id="75359482-378d-4052-8f01-80520e7db3cd"   # Files.ReadWrite.All
    
    # Add application permissions
    az ad app permission add --id "$SP_CLIENT_ID" --api "$graph_app_id" --api-permissions "$sites_permission_id=Role"
    az ad app permission add --id "$SP_CLIENT_ID" --api "$graph_app_id" --api-permissions "$files_permission_id=Role"
    
    log_info "Permissions added. Granting admin consent..."
    
    # Grant admin consent
    az ad app permission admin-consent --id "$SP_CLIENT_ID"
    
    log "Service Principal setup completed successfully!"
    log_info "Client ID: $SP_CLIENT_ID"
    log_warning "Client Secret: ${SP_CLIENT_SECRET:0:8}... (truncated for security)"
    
    # Save credentials to file for future use
    cat > .sp_credentials << EOF
# Service Principal Credentials for SharePoint-Blob Copy
# Generated: $(date)
SP_CLIENT_ID="$SP_CLIENT_ID"
SP_CLIENT_SECRET="$SP_CLIENT_SECRET"
SP_TENANT_ID="$SP_TENANT_ID"
EOF
    
    log_info "Credentials saved to .sp_credentials file"
    
    # Wait for permission propagation
    log_info "Waiting 30 seconds for permissions to propagate..."
    sleep 30
}

# Function to load existing service principal credentials
load_service_principal() {
    if [ -f ".sp_credentials" ]; then
        log_info "Loading existing service principal credentials..."
        source .sp_credentials
        
        if [ -n "$SP_CLIENT_ID" ] && [ -n "$SP_CLIENT_SECRET" ] && [ -n "$SP_TENANT_ID" ]; then
            log "Using existing service principal: $SP_CLIENT_ID"
            return 0
        fi
    fi
    
    return 1
}

# Function to authenticate with service principal
authenticate_service_principal() {
    log_step "Authenticating with Service Principal"
    
    # Get access token for Microsoft Graph
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
        log_info "Full response: $token_response"
        exit 1
    fi
    
    log "Successfully authenticated with Service Principal"
    log_info "Access token obtained for Microsoft Graph"
}

# Function to get SharePoint site information
get_site_info() {
    log_step "Getting SharePoint site information"
    
    # Extract tenant and site name from URL
    local tenant_name site_name
    tenant_name=$(echo "$SHAREPOINT_SITE_URL" | sed 's|https://||' | cut -d'.' -f1)
    site_name=$(echo "$SHAREPOINT_SITE_URL" | sed 's|.*/sites/||')
    
    log_info "Tenant: $tenant_name"
    log_info "Site: $site_name"
    
    # Get site ID from Microsoft Graph
    local site_response
    site_response=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://graph.microsoft.com/v1.0/sites/${tenant_name}.sharepoint.com:/sites/${site_name}")
    
    SITE_ID=$(echo "$site_response" | jq -r '.id // empty')
    
    if [ -z "$SITE_ID" ]; then
        local error_message
        error_message=$(echo "$site_response" | jq -r '.error.message // "Unknown error"')
        log_error "Cannot access SharePoint site: $error_message"
        log_info "Response: $site_response"
        exit 1
    fi
    
    local site_display_name
    site_display_name=$(echo "$site_response" | jq -r '.displayName // "Unknown"')
    
    log "Successfully connected to SharePoint site: $site_display_name"
    log_info "Site ID: $SITE_ID"
}

# Function to find document library
find_library() {
    log_step "Finding document library: $SHAREPOINT_LIBRARY_NAME"
    
    # Get all lists/libraries
    local lists_response
    lists_response=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://graph.microsoft.com/v1.0/sites/$SITE_ID/lists")
    
    # Look for our specific library
    local library_id
    library_id=$(echo "$lists_response" | jq -r --arg name "$SHAREPOINT_LIBRARY_NAME" '.value[] | select(.displayName == $name or .name == $name) | .id // empty')
    
    if [ -n "$library_id" ]; then
        log "Found library '$SHAREPOINT_LIBRARY_NAME' with ID: $library_id"
        LIBRARY_ID="$library_id"
        
        # Try to get the associated drive
        local drive_response
        drive_response=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
            "https://graph.microsoft.com/v1.0/sites/$SITE_ID/lists/$LIBRARY_ID/drive")
        
        DRIVE_ID=$(echo "$drive_response" | jq -r '.id // empty')
        
        if [ -n "$DRIVE_ID" ]; then
            log_info "Found associated drive ID: $DRIVE_ID"
        else
            log_warning "No associated drive found, will use list API"
        fi
        
        return 0
    fi
    
    # If not found, list available libraries
    log_error "Library '$SHAREPOINT_LIBRARY_NAME' not found"
    log_info "Available libraries:"
    echo "$lists_response" | jq -r '.value[] | "  - \(.displayName) (ID: \(.id))"'
    
    return 1
}

# Function to ensure blob container exists
ensure_blob_container() {
    log_step "Ensuring blob container exists: $CONTAINER_NAME"
    
    # Check if container exists
    if ! az storage container show \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" &> /dev/null; then
        
        log "Creating blob container: $CONTAINER_NAME"
        az storage container create \
            --name "$CONTAINER_NAME" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --account-key "$STORAGE_ACCOUNT_KEY" \
            --public-access blob
            
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create container"
            exit 1
        fi
    else
        log "Container already exists"
    fi
}

# Function to recursively list files in SharePoint library
list_sharepoint_files_recursive() {
    local folder_path="$1"
    local prefix="$2"
    
    local files_response
    local endpoint
    
    if [ -n "$folder_path" ]; then
        # URL encode the folder path
        local encoded_path
        encoded_path=$(printf '%s' "$folder_path" | sed 's/ /%20/g' | sed 's/&/%26/g')
        endpoint="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/root:/$encoded_path:/children"
        log_info "Scanning folder: $folder_path"
    else
        endpoint="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/root/children"
        log_info "Scanning root folder"
    fi
    
    files_response=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$endpoint")
    
    # Check if API call was successful
    if echo "$files_response" | jq -e '.error' >/dev/null 2>&1; then
        local error_message
        error_message=$(echo "$files_response" | jq -r '.error.message // "Unknown error"')
        log_error "API error in folder '$folder_path': $error_message"
        log_info "Full response: $files_response"
        return 1
    fi
    
    # Process files in current folder
    local files_in_folder
    if [ "$FILE_FILTER" = "*.pdf" ]; then
        files_in_folder=$(echo "$files_response" | jq --arg prefix "$prefix" '[.value[]? | select(.file != null and (.name | test("\\.pdf$"; "i"))) | .blobPath = ($prefix + .name)]')
    elif [ "$FILE_FILTER" = "*.png" ]; then
        files_in_folder=$(echo "$files_response" | jq --arg prefix "$prefix" '[.value[]? | select(.file != null and (.name | test("\\.png$"; "i"))) | .blobPath = ($prefix + .name)]')
    elif [ "$FILE_FILTER" = "*" ] || [ "$FILE_FILTER" = "*.*" ]; then
        files_in_folder=$(echo "$files_response" | jq --arg prefix "$prefix" '[.value[]? | select(.file != null) | .blobPath = ($prefix + .name)]')
    else
        # Handle custom filter patterns
        local filter_regex
        filter_regex=$(echo "$FILE_FILTER" | sed 's/\*/\.\*/g' | sed 's/\?/\./g')
        files_in_folder=$(echo "$files_response" | jq --arg prefix "$prefix" --arg filter "$filter_regex" '[.value[]? | select(.file != null and (.name | test($filter; "i"))) | .blobPath = ($prefix + .name)]')
    fi
    
    # Output files from current folder
    if [ "$(echo "$files_in_folder" | jq 'length')" -gt 0 ]; then
        echo "$files_in_folder" | jq -c '.[]'
    fi
    
    # Process subfolders recursively
    local folders
    folders=$(echo "$files_response" | jq -r '.value[]? | select(.folder != null) | .name')
    
    while IFS= read -r folder_name; do
        if [ -n "$folder_name" ]; then
            local subfolder_path
            local subfolder_prefix
            
            if [ -n "$folder_path" ]; then
                subfolder_path="$folder_path/$folder_name"
                subfolder_prefix="$prefix$folder_name/"
            else
                subfolder_path="$folder_name"
                subfolder_prefix="$prefix$folder_name/"
            fi
            
            # Recursive call for subfolder
            list_sharepoint_files_recursive "$subfolder_path" "$subfolder_prefix"
        fi
    done <<< "$folders"
}

# Function to list files in SharePoint library
list_sharepoint_files() {
    log_step "Listing files in SharePoint library (including nested folders)"
    
    if [ -z "$DRIVE_ID" ]; then
        log_error "No drive ID available for file listing"
        return 1
    fi
    
    local all_files_json="[]"
    local temp_file="/tmp/sp_files_$$"
    
    # Get all files recursively and collect them
    if list_sharepoint_files_recursive "$SHAREPOINT_FOLDER" "" > "$temp_file"; then
        # Convert line-delimited JSON to array
        if [ -s "$temp_file" ]; then
            all_files_json=$(jq -s '.' "$temp_file")
        fi
        rm -f "$temp_file"
    else
        rm -f "$temp_file"
        return 1
    fi
    
    local file_count
    file_count=$(echo "$all_files_json" | jq 'length')
    
    log "Found $file_count files matching filter: $FILE_FILTER"
    
    if [ "$file_count" -gt 0 ]; then
        # Log file details to stderr so it doesn't interfere with JSON output
        echo "$all_files_json" | jq -r '.[] | "  - \(.blobPath) (\(.size) bytes)"' >&2
    fi
    
    # Return only the JSON data to stdout
    echo "$all_files_json"
}

# Function to list blob storage contents
list_blob_contents() {
    log_step "Listing contents of blob container: $CONTAINER_NAME"
    
    # Check if container exists
    if ! az storage container show \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" &> /dev/null; then
        log_error "Container '$CONTAINER_NAME' does not exist"
        log_info "Run the script without --list-contents-of-blob to create container and sync files"
        exit 1
    fi
    
    # Get blob list
    local blob_list
    blob_list=$(az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --query "[].{name:name,size:properties.contentLength,modified:properties.lastModified}" \
        --output json 2>/dev/null)
    
    if [ "$?" -ne 0 ] || [ "$blob_list" = "[]" ]; then
        log_warning "No files found in container"
        echo ""
        echo "📊 CONTAINER SUMMARY"
        echo "=========================================="
        echo "Storage Account: $STORAGE_ACCOUNT_NAME"
        echo "Container: $CONTAINER_NAME"
        echo "Total files: 0"
        echo ""
        echo "💡 Run the sync operation first:"
        echo "   ./copy_sharepoint_to_blob.sh"
        return 0
    fi
    
    local file_count
    file_count=$(echo "$blob_list" | jq 'length')
    
    # Calculate total size
    local total_size
    total_size=$(echo "$blob_list" | jq 'map(.size | tonumber) | add // 0')
    
    echo ""
    echo "📊 CONTAINER SUMMARY"
    echo "=========================================="
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Container: $CONTAINER_NAME"
    echo "Total files: $file_count"
    
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
    
    echo ""
    echo "📁 FILE HIERARCHY"
    echo "=========================================="
    
    # Show folder structure
    local folders
    folders=$(echo "$blob_list" | jq -r '.[].name' | grep "/" | sed 's|/[^/]*$||' | sort -u)
    
    if [ -n "$folders" ]; then
        echo "$folders" | while read -r folder; do
            if [ -n "$folder" ]; then
                local file_count_in_folder
                file_count_in_folder=$(echo "$blob_list" | jq --arg prefix "$folder/" '[.[] | select(.name | startswith($prefix))] | length')
                echo "📁 $folder/ ($file_count_in_folder files)"
            fi
        done
        echo ""
    fi
    
    # Show file list with hierarchy
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
    echo "✅ Container listing completed!"
}

# Function to copy files to blob storage
copy_files_to_blob() {
    local files_json="$1"
    
    log_step "Starting file copy operation"
    
    local file_count
    file_count=$(echo "$files_json" | jq 'length')
    
    if [ "$file_count" -eq 0 ]; then
        log_warning "No files to copy"
        return 0
    fi
    
    local success_count=0
    local error_count=0
    
    # Process each file
    while IFS= read -r file_info; do
        local file_name file_download_url blob_path
        file_name=$(echo "$file_info" | jq -r '.name')
        file_download_url=$(echo "$file_info" | jq -r '.["@microsoft.graph.downloadUrl"]')
        blob_path=$(echo "$file_info" | jq -r '.blobPath // .name')
        
        log_info "Processing file: $file_name -> $blob_path"
        
        # Download file to temporary location
        local temp_file="/tmp/sp_download_$$_$(basename "$file_name")"
        
        if curl -s -H "Authorization: Bearer $ACCESS_TOKEN" -o "$temp_file" "$file_download_url"; then
            # Upload to Azure Blob Storage with folder structure
            if az storage blob upload \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --account-key "$STORAGE_ACCOUNT_KEY" \
                --container-name "$CONTAINER_NAME" \
                --name "$blob_path" \
                --file "$temp_file" \
                --overwrite &> /dev/null; then
                
                log "✅ Successfully uploaded: $blob_path"
                ((success_count++))
                
                # Clean up temp file
                rm -f "$temp_file"
                
                # Delete from SharePoint if requested
                if [ "$DELETE_AFTER_COPY" = true ]; then
                    log_warning "DELETE_AFTER_COPY is not implemented yet for safety"
                fi
            else
                log_error "Failed to upload $blob_path to blob storage"
                ((error_count++))
                rm -f "$temp_file"
            fi
        else
            log_error "Failed to download $file_name from SharePoint"
            ((error_count++))
        fi
    done < <(echo "$files_json" | jq -c '.[]')
    
    log "Copy operation completed:"
    log "  ✅ Successfully copied: $success_count files"
    if [ "$error_count" -gt 0 ]; then
        log "  ❌ Errors encountered: $error_count files"
    fi
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "SharePoint to Azure Blob Storage Copy Script"
    echo "Recursively copies files from SharePoint document libraries to Azure Blob Storage"
    echo ""
    echo "Options:"
    echo "  --setup                     Create service principal and setup permissions"
    echo "  --list-contents-of-blob     List all files in the blob storage container"
    echo "  --library-name NAME         SharePoint library name (default: from config)"
    echo "  --file-filter FILTER        File filter (default: from config)"
    echo "                              Supports: *.pdf, *.png, *.docx, *.*, etc."
    echo "  --folder FOLDER             SharePoint folder path (default: from config)"
    echo "                              Recursively processes all subfolders"
    echo "  --delete-after              Delete files from SharePoint after copy"
    echo "  --help                      Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --setup                                  # First-time setup"
    echo "  $0                                          # Copy files with config settings"
    echo "  $0 --list-contents-of-blob                  # List blob storage contents"
    echo "  $0 --file-filter '*.docx'                   # Copy Word documents recursively"
    echo "  $0 --file-filter '*'                        # Copy all files recursively"
    echo "  $0 --library-name 'Documents' --folder 'Archive'"
    echo "  $0 --library-name 'Shared Documents' --file-filter '*.png'"
    echo ""
    echo "Features:"
    echo "  - Recursive folder traversal"
    echo "  - Preserves folder structure in blob storage"
    echo "  - Service principal authentication"
    echo "  - Multiple file type filters"
    echo "  - Error handling and logging"
    echo "  - Built-in blob storage listing"
}

# Main script execution
main() {
    log "Starting SharePoint to Azure Blob Storage copy operation"
    echo "============================================================" >&2
    
    # Load configuration first
    load_config
    
    log_info "Configuration:"
    log_info "  SharePoint Site: $SHAREPOINT_SITE_URL"
    log_info "  Library Name: $SHAREPOINT_LIBRARY_NAME"
    log_info "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log_info "  Container: $CONTAINER_NAME"
    log_info "  File Filter: $FILE_FILTER"
    log_info "  SharePoint Folder: ${SHAREPOINT_FOLDER:-'(root)'}"
    
    # Check dependencies
    check_dependencies
    
    # Load or create service principal
    if ! load_service_principal; then
        log_info "No existing service principal found. Creating new one..."
        create_service_principal
    fi
    
    # Authenticate with service principal
    authenticate_service_principal
    
    # Get SharePoint site info
    get_site_info
    
    # Find the document library
    if ! find_library; then
        log_error "Could not find the document library"
        exit 1
    fi
    
    # Ensure blob container exists
    ensure_blob_container
    
    # List and copy files
    local files_json
    log_info "Getting file list from SharePoint..."
    files_json=$(list_sharepoint_files)
    
    log_info "Raw response length: ${#files_json}"
    log_info "First 200 characters: ${files_json:0:200}"
    
    # Validate JSON before processing
    if ! echo "$files_json" | jq empty 2>/dev/null; then
        log_error "Invalid JSON response from list_sharepoint_files"
        log_info "Full response: $files_json"
        exit 1
    fi
    
    copy_files_to_blob "$files_json"
    
    log "🎉 Operation completed successfully!"
}

# Handle command line arguments
SETUP_MODE=false
LIST_BLOB_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --setup)
            SETUP_MODE=true
            shift
            ;;
        --list-contents-of-blob)
            LIST_BLOB_MODE=true
            shift
            ;;
        --library-name)
            SHAREPOINT_LIBRARY_NAME="$2"
            shift 2
            ;;
        --file-filter)
            FILE_FILTER="$2"
            shift 2
            ;;
        --folder)
            SHAREPOINT_FOLDER="$2"
            shift 2
            ;;
        --delete-after)
            DELETE_AFTER_COPY=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Handle setup mode
if [ "$SETUP_MODE" = true ]; then
    log "Running in setup mode - creating service principal only"
    load_config
    check_dependencies
    create_service_principal
    log "🎉 Setup completed! You can now run the script without --setup to copy files."
    exit 0
fi

# Handle list blob mode
if [ "$LIST_BLOB_MODE" = true ]; then
    log "Running in list blob mode - showing container contents"
    load_config
    check_dependencies
    list_blob_contents
    exit 0
fi

# Run main function
main
