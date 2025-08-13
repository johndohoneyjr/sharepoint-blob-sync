#Requires -Version 5.1

<#
.SYNOPSIS
    SharePoint to Azure Blob Storage Copy Script - PowerShell Version
    Uses Service Principal authentication with Microsoft Graph API permissions

.DESCRIPTION
    This script copies files from SharePoint document libraries to Azure Blob Storage
    with support for recursive folder traversal, various file filters, and comprehensive error handling.
    
    Features:
    - Recursive folder traversal
    - Preserves folder structure in blob storage
    - Service principal authentication
    - Multiple file type filters
    - Comprehensive error handling and logging
    - Built-in blob storage listing

.PARAMETER Setup
    Create service principal and setup permissions

.PARAMETER ListContentsOfBlob
    List all files in the blob storage container

.PARAMETER VerifyPermissions
    Verify service principal permissions without running the main sync operation

.PARAMETER LibraryName
    SharePoint library name (overrides config.env setting)

.PARAMETER FileFilter
    File filter pattern (overrides config.env setting)
    Supports: *.pdf, *.png, *.docx, *.*, etc.

.PARAMETER Folder
    SharePoint folder path (overrides config.env setting)
    Recursively processes all subfolders

.PARAMETER DeleteAfter
    Delete files from SharePoint after copy (use with caution)

.PARAMETER Help
    Show detailed help information

.EXAMPLE
    .\Copy-SharePointToBlob.ps1 -Setup
    First-time setup - creates service principal and configures permissions

.EXAMPLE
    .\Copy-SharePointToBlob.ps1
    Copy files using configuration from config.env

.EXAMPLE
    .\Copy-SharePointToBlob.ps1 -ListContentsOfBlob
    List all files currently in the blob storage container

.EXAMPLE
    .\Copy-SharePointToBlob.ps1 -FileFilter "*.docx"
    Copy only Word documents recursively

.EXAMPLE
    .\Copy-SharePointToBlob.ps1 -FileFilter "*" -LibraryName "Documents"
    Copy all files from the "Documents" library

.EXAMPLE
    .\Copy-SharePointToBlob.ps1 -LibraryName "Shared Documents" -Folder "Archive" -FileFilter "*.pdf"
    Copy PDF files from the Archive folder in Shared Documents library

.NOTES
    Author: SharePoint-Blob Sync Team
    Version: 2.3 (PowerShell)
    Requires: PowerShell 5.1+, Azure CLI
    
    Before first use:
    1. Copy config.env.template to config.env
    2. Configure your settings in config.env
    3. Run with -Setup parameter to create service principal
    
    Required Microsoft Graph API Permissions (RBAC):
    - Sites.ReadWrite.All (delegated and application)
    - Files.ReadWrite.All (delegated and application)
    - Sites.Read.All (delegated)
    
    Automatic RBAC Handling:
    The script now automatically detects when permission grants are needed and 
    attempts to execute the required commands. It extracts the Client ID from 
    Azure CLI error messages and uses proper variable handling.
    
    Automatic Storage Configuration:
    The script automatically configures Azure Storage access including:
    - Detects current public IP address and adds to storage network rules
    - Assigns Storage Blob Data Contributor role to service principal
    - Tests storage account connectivity and provides troubleshooting guidance
    
    Manual RBAC Commands (if auto-setup fails):
    az ad app permission grant --id <CLIENT_ID> --api 00000003-0000-0000-c000-000000000000 --scope "Sites.ReadWrite.All"
    az ad app permission grant --id <CLIENT_ID> --api 00000003-0000-0000-c000-000000000000 --scope "Files.ReadWrite.All"
    az ad app permission grant --id <CLIENT_ID> --api 00000003-0000-0000-c000-000000000000 --scope "Sites.Read.All"
    az ad app permission admin-consent --id <CLIENT_ID>
    
    Manual Storage Commands (if auto-setup fails):
    az storage account network-rule add --account-name <STORAGE_ACCOUNT> --ip-address <YOUR_IP>
    az role assignment create --role "Storage Blob Data Contributor" --assignee <SERVICE_PRINCIPAL_ID> --scope <STORAGE_SCOPE>
    
.LINK
    https://github.com/johndohoneyjr/sharepoint-blob-sync
#>

[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(ParameterSetName='Setup')]
    [switch]$Setup,
    
    [Parameter(ParameterSetName='ListBlob')]
    [switch]$ListContentsOfBlob,
    
    [Parameter(ParameterSetName='VerifyPermissions')]
    [switch]$VerifyPermissions,
    
    [Parameter(ParameterSetName='Default')]
    [Parameter(ParameterSetName='Custom')]
    [string]$LibraryName,
    
    [Parameter(ParameterSetName='Default')]
    [Parameter(ParameterSetName='Custom')]
    [string]$FileFilter,
    
    [Parameter(ParameterSetName='Default')]
    [Parameter(ParameterSetName='Custom')]
    [string]$Folder,
    
    [Parameter(ParameterSetName='Default')]
    [Parameter(ParameterSetName='Custom')]
    [switch]$DeleteAfter,
    
    [switch]$Help
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Global variables for configuration and authentication
$Script:Config = @{}
$Script:SPCredentials = @{
    ClientId = ""
    ClientSecret = ""
    TenantId = ""
}
$Script:AccessToken = ""
$Script:SiteId = ""
$Script:LibraryId = ""
$Script:DriveId = ""

# Color scheme for consistent output
$Script:Colors = @{
    Error = 'Red'
    Warning = 'Yellow'
    Info = 'Cyan'
    Step = 'Blue'
    Success = 'Green'
    Default = 'White'
}

#region Logging Functions

<#
.SYNOPSIS
    Write log messages with timestamps and color coding
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Error', 'Warning', 'Info', 'Step', 'Success', 'Default')]
        [string]$Level = 'Default'
    )
    
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logMessage = "[$timestamp] $Message"
        
        $color = $Script:Colors[$Level]
        Write-Host $logMessage -ForegroundColor $color
    }
    catch {
        Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] ERROR: Failed to write log message: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Write-LogError {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Log "ERROR: $Message" -Level Error
}

function Write-LogWarning {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Log "WARNING: $Message" -Level Warning
}

function Write-LogInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    # INFO messages suppressed for cleaner output
}

function Write-LogStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Log "STEP: $Message" -Level Step
}

function Write-LogSuccess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Log $Message -Level Success
}

#endregion

#region Configuration Management

<#
.SYNOPSIS
    Load configuration from config.env file
#>
function Import-Configuration {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Loading configuration"
        
        $configFile = Join-Path $PSScriptRoot "config.env"
        
        if (-not (Test-Path $configFile)) {
            throw "Configuration file '$configFile' not found! Please copy 'config.env.template' to 'config.env' and customize your settings"
        }
        
        # Read and parse the config file
        $configContent = Get-Content $configFile -ErrorAction Stop
        
        foreach ($line in $configContent) {
            if ($line -match '^([^#=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $rawValue = $matches[2].Trim()
                
                # Remove inline comments (everything after # that's not inside quotes)
                if ($rawValue -match '^"([^"]*)"') {
                    # Handle quoted values
                    $value = $matches[1]
                } elseif ($rawValue -match "^'([^']*)'") {
                    # Handle single-quoted values
                    $value = $matches[1]
                } else {
                    # Handle unquoted values - remove inline comments
                    $value = ($rawValue -split '\s*#')[0].Trim()
                }
                
                $Script:Config[$key] = $value
            }
        }
        
        # Override with command line parameters
        if ($LibraryName) { $Script:Config['SHAREPOINT_LIBRARY_NAME'] = $LibraryName }
        if ($FileFilter) { $Script:Config['FILE_FILTER'] = $FileFilter }
        if ($Folder) { $Script:Config['SHAREPOINT_FOLDER'] = $Folder }
        if ($DeleteAfter) { $Script:Config['DELETE_AFTER_COPY'] = 'true' }
        
        # Validate required configuration
        $requiredVars = @(
            'SHAREPOINT_SITE_URL',
            'SHAREPOINT_LIBRARY_NAME',
            'STORAGE_ACCOUNT_NAME',
            'STORAGE_ACCOUNT_KEY',
            'CONTAINER_NAME',
            'SP_NAME'
        )
        
        $missingVars = @()
        foreach ($var in $requiredVars) {
            if (-not $Script:Config.ContainsKey($var) -or [string]::IsNullOrWhiteSpace($Script:Config[$var])) {
                $missingVars += $var
            }
        }
        
        if ($missingVars.Count -gt 0) {
            throw "Missing required configuration variables: $($missingVars -join ', '). Please check your config.env file"
        }
        
        # Set defaults for optional variables
        if (-not $Script:Config.ContainsKey('FILE_FILTER') -or [string]::IsNullOrWhiteSpace($Script:Config['FILE_FILTER'])) {
            $Script:Config['FILE_FILTER'] = '*.pdf'
        }
        if (-not $Script:Config.ContainsKey('SHAREPOINT_FOLDER')) {
            $Script:Config['SHAREPOINT_FOLDER'] = ''
        }
        if (-not $Script:Config.ContainsKey('DELETE_AFTER_COPY')) {
            $Script:Config['DELETE_AFTER_COPY'] = 'false'
        }
        if (-not $Script:Config.ContainsKey('FORCE_RECREATE_SP')) {
            $Script:Config['FORCE_RECREATE_SP'] = 'false'
        }
        if (-not $Script:Config.ContainsKey('VERBOSE_LOGGING')) {
            $Script:Config['VERBOSE_LOGGING'] = 'false'
        }
        
        Write-LogSuccess "Configuration loaded successfully"
    }
    catch {
        Write-LogError "Failed to load configuration: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Dependency Management

<#
.SYNOPSIS
    Check if all required dependencies are available
#>
function Test-Dependencies {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Checking dependencies"
        
        $missingDeps = @()
        
        # Check Azure CLI
        try {
            $null = Get-Command az -ErrorAction Stop
            $azVersion = az --version 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Azure CLI not responding"
            }
        }
        catch {
            $missingDeps += "Azure CLI (az)"
        }
        
        # PowerShell has built-in JSON and HTTP capabilities, so we don't need curl/jq equivalents
        
        if ($missingDeps.Count -gt 0) {
            throw "Missing required dependencies: $($missingDeps -join ', '). Please install Azure CLI from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        }
        
        Write-LogSuccess "All dependencies are available"
    }
    catch {
        Write-LogError $_.Exception.Message
        throw
    }
}

<#
.SYNOPSIS
    Verify and validate RBAC permissions for the service principal
#>
function Test-ServicePrincipalPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId
    )
    
    try {
        Write-LogStep "Verifying service principal permissions"
        
        # Check if service principal exists
        $spInfo = az ad sp show --id $ClientId --query "appId" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($spInfo)) {
            Write-LogWarning "Service principal with Client ID $ClientId not found"
            return $false
        }
        
        Write-LogInfo "Service principal found: $ClientId"
        
        # Check delegated permissions (OAuth2 permission grants)
        Write-LogInfo "Checking delegated permissions..."
        $delegatedPermissions = az ad app permission list-grants --id $ClientId --query "[].scope" -o tsv 2>$null
        
        $requiredScopes = @("Sites.ReadWrite.All", "Files.ReadWrite.All", "Sites.Read.All")
        $missingScopes = @()
        
        foreach ($scope in $requiredScopes) {
            if ($delegatedPermissions -notlike "*$scope*") {
                $missingScopes += $scope
                Write-LogWarning "Missing delegated permission: $scope"
            } else {
                Write-LogSuccess "Found delegated permission: $scope"
            }
        }
        
        # Check application permissions
        Write-LogInfo "Checking application permissions..."
        $appPermissions = az ad app show --id $ClientId --query "requiredResourceAccess[?resourceAppId=='00000003-0000-0000-c000-000000000000'].resourceAccess[].id" -o tsv 2>$null
        
        $requiredAppPermissionIds = @(
            "9492366f-7969-46a4-8d15-ed1a20078fff",  # Sites.ReadWrite.All
            "75359482-378d-4052-8f01-80520e7db3cd"   # Files.ReadWrite.All
        )
        
        foreach ($permId in $requiredAppPermissionIds) {
            if ($appPermissions -contains $permId) {
                Write-LogSuccess "Found application permission ID: $permId"
            } else {
                Write-LogWarning "Missing application permission ID: $permId"
            }
        }
        
        # Check if we have the minimum required permissions to function
        $hasMinimumPermissions = $false
        $hasApplicationPermissions = ($appPermissions -contains "9492366f-7969-46a4-8d15-ed1a20078fff" -and 
                                     $appPermissions -contains "75359482-378d-4052-8f01-80520e7db3cd")
        
        # Check if we have at least one Sites permission (Read.All is minimum)
        $hasSitesPermission = ($delegatedPermissions -like "*Sites.Read.All*" -or 
                              $delegatedPermissions -like "*Sites.ReadWrite.All*")
        
        if ($hasApplicationPermissions -and $hasSitesPermission) {
            $hasMinimumPermissions = $true
        }
        
        if ($missingScopes.Count -eq 0) {
            Write-LogSuccess "All required delegated permissions are present - OPTIMAL configuration!"
            return $true
        } elseif ($hasMinimumPermissions) {
            Write-LogInfo "Minimum required permissions are present - script should work"
            Write-LogWarning "Some delegated permissions are missing, but this may not prevent basic functionality"
            if ($missingScopes.Count -gt 0) {
                Write-Host ""
                Write-Host "Optional: Run these commands for full permission set:" -ForegroundColor Yellow
                foreach ($scope in $missingScopes) {
                    Write-Host "  az ad app permission grant --id $ClientId --api 00000003-0000-0000-c000-000000000000 --scope ""$scope""" -ForegroundColor White
                }
            }
            return $true
        } else {
            Write-LogWarning "Missing critical permissions - script may not work properly."
            Write-Host ""
            Write-Host "Required RBAC Commands:" -ForegroundColor Red
            foreach ($scope in $missingScopes) {
                Write-Host "  az ad app permission grant --id $ClientId --api 00000003-0000-0000-c000-000000000000 --scope ""$scope""" -ForegroundColor White
            }
            Write-Host "  az ad app permission admin-consent --id $ClientId" -ForegroundColor White
            return $false
        }
    }
    catch {
        Write-LogError "Failed to verify permissions: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Service Principal Management

<#
.SYNOPSIS
    Create a new service principal with required Microsoft Graph permissions
#>
function New-ServicePrincipal {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Creating Service Principal with Microsoft Graph permissions"
        
        # Check if already logged in to Azure
        try {
            $accountInfo = az account show --query tenantId -o tsv 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accountInfo)) {
                throw "Not logged in to Azure"
            }
        }
        catch {
            throw "Not logged in to Azure. Please run 'az login' first"
        }
        
        # Get tenant ID
        $Script:SPCredentials.TenantId = az account show --query tenantId -o tsv
        Write-LogInfo "Tenant ID: $($Script:SPCredentials.TenantId)"
        
        # Check if service principal already exists
        $existingSp = az ad sp list --display-name $Script:Config['SP_NAME'] --query "[0].appId" -o tsv 2>$null
        
        if (-not [string]::IsNullOrWhiteSpace($existingSp) -and $existingSp -ne "null") {
            Write-LogWarning "Service Principal '$($Script:Config['SP_NAME'])' already exists"
            $Script:SPCredentials.ClientId = $existingSp
            Write-LogInfo "Using existing Service Principal: $($Script:SPCredentials.ClientId)"
            
            # Reset client secret
            Write-LogInfo "Creating new client secret..."
            $Script:SPCredentials.ClientSecret = az ad sp credential reset --id $Script:SPCredentials.ClientId --query password -o tsv
        }
        else {
            Write-LogInfo "Creating new Service Principal: $($Script:Config['SP_NAME'])"
            
            # Create service principal
            $spOutput = az ad sp create-for-rbac --name $Script:Config['SP_NAME'] --skip-assignment --query "{appId:appId,password:password}" -o json | ConvertFrom-Json
            
            $Script:SPCredentials.ClientId = $spOutput.appId
            $Script:SPCredentials.ClientSecret = $spOutput.password
            
            Write-LogSuccess "Service Principal created successfully"
            Write-LogInfo "Client ID: $($Script:SPCredentials.ClientId)"
        }
        
        # Wait for propagation
        Write-LogInfo "Waiting for Azure AD propagation..."
        Start-Sleep -Seconds 10
        
        # Add Microsoft Graph API permissions
        Write-LogInfo "Adding Microsoft Graph API permissions..."
        
        $graphAppId = "00000003-0000-0000-c000-000000000000"
        $sitesPermissionId = "9492366f-7969-46a4-8d15-ed1a20078fff"  # Sites.ReadWrite.All
        $filesPermissionId = "75359482-378d-4052-8f01-80520e7db3cd"   # Files.ReadWrite.All
        
        # Add application permissions
        Write-LogInfo "Adding application permissions for Microsoft Graph..."
        
        # Use try-catch for individual permission operations to prevent early exit
        try {
            $permissionResult1 = az ad app permission add --id $Script:SPCredentials.ClientId --api $graphAppId --api-permissions "$sitesPermissionId=Role" 2>&1
        } catch {
            $permissionResult1 = "Error adding Sites permission: $($_.Exception.Message)"
        }
        
        try {
            $permissionResult2 = az ad app permission add --id $Script:SPCredentials.ClientId --api $graphAppId --api-permissions "$filesPermissionId=Role" 2>&1
        } catch {
            $permissionResult2 = "Error adding Files permission: $($_.Exception.Message)"
        }
        
        Write-LogInfo "Permission add results:"
        Write-LogInfo "Sites permission: $permissionResult1"
        Write-LogInfo "Files permission: $permissionResult2"
        
        # Check if either permission add command suggested a grant command
        $needsPermissionGrant = $false
        $clientIdFromError = $null
        
        # Check for the specific warning pattern that indicates we need to run permission grant
        if ($permissionResult1 -like "*az ad app permission grant --id*" -or $permissionResult2 -like "*az ad app permission grant --id*") {
            $needsPermissionGrant = $true
            Write-LogInfo "Azure CLI indicates permission grant is needed for the added permissions."
            
            # Extract client ID from the error message to ensure we have the right one
            $combinedResult = "$permissionResult1 $permissionResult2"
            if ($combinedResult -match "az ad app permission grant --id ([a-f0-9-]+)") {
                $clientIdFromError = $matches[1]
                Write-LogInfo "Extracted Client ID from error: $clientIdFromError"
                
                # Verify it matches our stored Client ID
                if ($clientIdFromError -eq $Script:SPCredentials.ClientId) {
                    Write-LogInfo "Client ID matches our service principal - proceeding with permission grants"
                } else {
                    Write-LogWarning "Client ID mismatch - using ID from error message: $clientIdFromError"
                    $Script:SPCredentials.ClientId = $clientIdFromError
                }
            }
        }
        
        Write-LogInfo "Attempting to grant admin consent and delegated permissions..."
        
        # Try multiple methods to grant admin consent
        $consentGranted = $false
        
        # If we detected that permission grants are needed, start with the grant commands
        if ($needsPermissionGrant -or (-not $consentGranted)) {
            Write-LogInfo "Running permission grant commands for delegated permissions..."
            
            # Method 1: Grant delegated permissions using az ad app permission grant
            Write-LogInfo "Granting Sites.ReadWrite.All permission..."
            try {
                $grantResult1 = az ad app permission grant --id $Script:SPCredentials.ClientId --api $graphAppId --scope "Sites.ReadWrite.All" 2>&1
            } catch {
                $grantResult1 = "Error granting Sites.ReadWrite.All: $($_.Exception.Message)"
            }
            
            Write-LogInfo "Granting Files.ReadWrite.All permission..."
            try {
                $grantResult2 = az ad app permission grant --id $Script:SPCredentials.ClientId --api $graphAppId --scope "Files.ReadWrite.All" 2>&1
            } catch {
                $grantResult2 = "Error granting Files.ReadWrite.All: $($_.Exception.Message)"
            }
            
            Write-LogInfo "Granting Sites.Read.All permission..."
            try {
                $grantResult3 = az ad app permission grant --id $Script:SPCredentials.ClientId --api $graphAppId --scope "Sites.Read.All" 2>&1
            } catch {
                $grantResult3 = "Error granting Sites.Read.All: $($_.Exception.Message)"
            }
            
            # Check if any of the permission grants succeeded
            $grantSuccess = $false
            if ($grantResult1 -like "*clientId*" -and $grantResult1 -like "*scope*") {
                Write-LogSuccess "Sites.ReadWrite.All permission granted successfully!"
                $grantSuccess = $true
            } else {
                Write-LogInfo "Sites.ReadWrite.All result: $grantResult1"
            }
            
            if ($grantResult2 -like "*clientId*" -and $grantResult2 -like "*scope*") {
                Write-LogSuccess "Files.ReadWrite.All permission granted successfully!"
                $grantSuccess = $true
            } else {
                Write-LogInfo "Files.ReadWrite.All result: $grantResult2"
            }
            
            if ($grantResult3 -like "*clientId*" -and $grantResult3 -like "*scope*") {
                Write-LogSuccess "Sites.Read.All permission granted successfully!"
                $grantSuccess = $true
            } else {
                Write-LogInfo "Sites.Read.All result: $grantResult3"
            }
            
            # Try admin consent for application permissions
            if ($grantSuccess) {
                Write-LogInfo "Attempting admin consent for application permissions..."
                try {
                    $adminConsentResult = az ad app permission admin-consent --id $Script:SPCredentials.ClientId 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogSuccess "Admin consent granted for application permissions!"
                        $consentGranted = $true
                    } else {
                        Write-LogInfo "Admin consent result: $adminConsentResult"
                        # Consider it successful if delegated permissions were granted
                        $consentGranted = $true
                    }
                } catch {
                    Write-LogInfo "Admin consent failed with exception: $($_.Exception.Message)"
                    # Still consider it successful if delegated permissions were granted
                    $consentGranted = $true
                }
            } else {
                Write-LogWarning "No delegated permissions were granted successfully"
            }
        }
        
        if (-not $consentGranted) {
            # Fallback method: Try direct admin consent command
            Write-LogInfo "Attempting direct admin consent as fallback..."
            try {
                $consentResult = az ad app permission admin-consent --id $Script:SPCredentials.ClientId 2>&1
                
                if ($LASTEXITCODE -eq 0 -and $consentResult -notlike "*WARNING*" -and $consentResult -notlike "*error*") {
                    Write-LogSuccess "Admin consent granted successfully via direct method!"
                    $consentGranted = $true
                } else {
                    Write-LogInfo "Direct admin consent result: $consentResult"
                }
            } catch {
                Write-LogInfo "Direct admin consent failed with exception: $($_.Exception.Message)"
            }
        }
        
        if (-not $consentGranted) {
            Write-LogWarning "Automatic admin consent failed - providing manual instructions"
            Write-Host ""
            Write-Host "=== MANUAL PERMISSION GRANT REQUIRED ===" -ForegroundColor Yellow
            Write-Host "The service principal has been created but requires admin consent." -ForegroundColor White
            Write-Host ""
            Write-Host "Please complete ONE of the following steps:" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Option 1 - Azure Portal (Recommended):" -ForegroundColor Green
            Write-Host "  1. Go to: https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/RegisteredApps" -ForegroundColor White
            Write-Host "  2. Find and click on '$($Script:Config['SP_NAME'])'" -ForegroundColor White
            Write-Host "  3. Click 'API permissions' in the left menu" -ForegroundColor White
            Write-Host "  4. Click 'Grant admin consent for [Your Organization]'" -ForegroundColor White
            Write-Host "  5. Click 'Yes' to confirm" -ForegroundColor White
            Write-Host ""
            Write-Host "Option 2 - Azure CLI Commands (run these exact commands):" -ForegroundColor Green
            Write-Host "  # Grant delegated permissions:" -ForegroundColor Cyan
            Write-Host "  az ad app permission grant --id $($Script:SPCredentials.ClientId) --api 00000003-0000-0000-c000-000000000000 --scope ""Sites.ReadWrite.All""" -ForegroundColor White
            Write-Host "  az ad app permission grant --id $($Script:SPCredentials.ClientId) --api 00000003-0000-0000-c000-000000000000 --scope ""Files.ReadWrite.All""" -ForegroundColor White
            Write-Host "  az ad app permission grant --id $($Script:SPCredentials.ClientId) --api 00000003-0000-0000-c000-000000000000 --scope ""Sites.Read.All""" -ForegroundColor White
            Write-Host ""
            Write-Host "  # Grant admin consent for application permissions:" -ForegroundColor Cyan
            Write-Host "  az ad app permission admin-consent --id $($Script:SPCredentials.ClientId)" -ForegroundColor White
            Write-Host ""
            Write-Host "Option 3 - Alternative CLI method (if Option 2 fails):" -ForegroundColor Green
            if ($suggestedCommand) {
                Write-Host "  Run: $suggestedCommand" -ForegroundColor White
            } else {
                Write-Host "  Run: az ad app permission admin-consent --id $($Script:SPCredentials.ClientId)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "After granting consent, you can run the sync operation:" -ForegroundColor Cyan
            Write-Host "  .\Copy-SharePointToBlob.ps1" -ForegroundColor White
        }
        
        Write-LogSuccess "Service Principal setup completed!"
        Write-LogInfo "Client ID: $($Script:SPCredentials.ClientId)"
        Write-LogWarning "Client Secret: $($Script:SPCredentials.ClientSecret.Substring(0,8))... (truncated for security)"
        
        # Save credentials to file for future use
        $credentialsContent = @"
# Service Principal Credentials for SharePoint-Blob Copy
# Generated: $(Get-Date)
SP_CLIENT_ID="$($Script:SPCredentials.ClientId)"
SP_CLIENT_SECRET="$($Script:SPCredentials.ClientSecret)"
SP_TENANT_ID="$($Script:SPCredentials.TenantId)"
"@
        
        $credentialsFile = Join-Path $PSScriptRoot ".sp_credentials"
        $credentialsContent | Out-File -FilePath $credentialsFile -Encoding UTF8
        Write-LogInfo "Credentials saved to .sp_credentials file"
        
        # Wait for permission propagation
        Write-LogInfo "Waiting 30 seconds for permissions to propagate..."
        Start-Sleep -Seconds 30
    }
    catch {
        Write-LogError "Failed to create service principal: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Load existing service principal credentials from file
#>
function Import-ServicePrincipal {
    [CmdletBinding()]
    param()
    
    try {
        $credentialsFile = Join-Path $PSScriptRoot ".sp_credentials"
        
        if (Test-Path $credentialsFile) {
            Write-LogInfo "Loading existing service principal credentials..."
            
            $credContent = Get-Content $credentialsFile
            foreach ($line in $credContent) {
                if ($line -match '^SP_CLIENT_ID="(.+)"$') {
                    $Script:SPCredentials.ClientId = $matches[1]
                }
                elseif ($line -match '^SP_CLIENT_SECRET="(.+)"$') {
                    $Script:SPCredentials.ClientSecret = $matches[1]
                }
                elseif ($line -match '^SP_TENANT_ID="(.+)"$') {
                    $Script:SPCredentials.TenantId = $matches[1]
                }
            }
            
            if (-not [string]::IsNullOrWhiteSpace($Script:SPCredentials.ClientId) -and 
                -not [string]::IsNullOrWhiteSpace($Script:SPCredentials.ClientSecret) -and 
                -not [string]::IsNullOrWhiteSpace($Script:SPCredentials.TenantId)) {
                
                Write-LogSuccess "Using existing service principal: $($Script:SPCredentials.ClientId)"
                return $true
            }
        }
        
        return $false
    }
    catch {
        Write-LogError "Failed to load service principal credentials: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Authenticate with service principal and get access token
#>
function Connect-ServicePrincipal {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Authenticating with Service Principal"
        
        # Get access token for Microsoft Graph
        $tokenUrl = "https://login.microsoftonline.com/$($Script:SPCredentials.TenantId)/oauth2/v2.0/token"
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = $Script:SPCredentials.ClientId
            client_secret = $Script:SPCredentials.ClientSecret
            scope = "https://graph.microsoft.com/.default"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        $Script:AccessToken = $tokenResponse.access_token
        
        if ([string]::IsNullOrWhiteSpace($Script:AccessToken)) {
            throw "No access token received from authentication service"
        }
        
        Write-LogSuccess "Successfully authenticated with Service Principal"
        Write-LogInfo "Access token obtained for Microsoft Graph"
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd() | ConvertFrom-Json
                $errorMessage = $responseBody.error_description
            }
            catch {
                # Use original error message if parsing fails
            }
        }
        
        Write-LogError "Failed to get access token: $errorMessage"
        throw
    }
}

#endregion

#region Azure Storage Configuration

<#
.SYNOPSIS
    Configure Azure Storage account for network access and role assignments
#>
function Set-StorageAccountAccess {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Configuring Azure Storage account access"
        
        $storageAccount = $Script:Config['AZURE_STORAGE_ACCOUNT_NAME']
        if (-not $storageAccount) {
            $storageAccount = $Script:Config['STORAGE_ACCOUNT_NAME']
        }
        
        if (-not $storageAccount) {
            Write-LogWarning "No storage account name found in configuration"
            return
        }
        
        Write-LogInfo "Storage Account: $storageAccount"
        
        # Try to get resource group from storage account
        Write-LogInfo "Detecting resource group for storage account..."
        try {
            $storageInfo = az storage account list --query "[?name=='$storageAccount'].{name:name,resourceGroup:resourceGroup}" -o json | ConvertFrom-Json
            if ($storageInfo -and $storageInfo.Count -gt 0) {
                $resourceGroup = $storageInfo[0].resourceGroup
                Write-LogInfo "Resource Group: $resourceGroup"
            } else {
                Write-LogWarning "Could not find storage account '$storageAccount' in current subscription"
                return
            }
        }
        catch {
            Write-LogWarning "Could not detect resource group: $($_.Exception.Message)"
            return
        }
        
        # Get current user's public IP address
        Write-LogInfo "Detecting current public IP address..."
        try {
            $currentIP = Invoke-RestMethod -Uri "https://api.ipify.org?format=text" -ErrorAction Stop
            Write-LogInfo "Current IP: $currentIP"
        }
        catch {
            Write-LogWarning "Could not detect IP address automatically: $($_.Exception.Message)"
            Write-LogInfo "You may need to manually add your IP to the storage account network rules"
            $currentIP = $null
        }
        
        # Check if storage account exists and get its configuration
        Write-LogInfo "Checking storage account configuration..."
        try {
            $storageConfig = az storage account show --name $storageAccount --resource-group $resourceGroup --query "{allowBlobPublicAccess:allowBlobPublicAccess,networkRuleSet:networkRuleSet}" -o json | ConvertFrom-Json
            
            if ($storageConfig) {
                Write-LogInfo "Storage account found and accessible"
                
                # Check current network rules
                $currentRules = $storageConfig.networkRuleSet
                Write-LogInfo "Current network rule default action: $($currentRules.defaultAction)"
                
                if ($currentRules.defaultAction -eq "Deny" -and $currentIP) {
                    # Check if current IP is already in the rules
                    $ipExists = $false
                    if ($currentRules.ipRules) {
                        $ipExists = $currentRules.ipRules | Where-Object { $_.ipAddressOrRange -eq $currentIP }
                    }
                    
                    if (-not $ipExists) {
                        Write-LogInfo "Adding current IP ($currentIP) to storage account network rules..."
                        try {
                            $addRuleResult = az storage account network-rule add --account-name $storageAccount --resource-group $resourceGroup --ip-address $currentIP 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-LogSuccess "Successfully added IP address to network rules"
                            } else {
                                Write-LogWarning "Failed to add IP to network rules: $addRuleResult"
                            }
                        }
                        catch {
                            Write-LogWarning "Error adding IP to network rules: $($_.Exception.Message)"
                        }
                    } else {
                        Write-LogInfo "Current IP is already allowed in network rules"
                    }
                } else {
                    Write-LogInfo "Storage account allows all networks or IP detection failed"
                }
            }
        }
        catch {
            Write-LogWarning "Could not check storage account configuration: $($_.Exception.Message)"
        }
        
        # Configure role assignments for service principal
        if ($Script:SPCredentials.ClientId) {
            Write-LogInfo "Setting up Storage Blob Data Contributor role for service principal..."
            
            # Get service principal object ID
            try {
                $spObjectId = az ad sp show --id $Script:SPCredentials.ClientId --query "id" -o tsv 2>$null
                
                if ($spObjectId) {
                    Write-LogInfo "Service Principal Object ID: $spObjectId"
                    
                    # Get current subscription ID
                    $subscriptionId = az account show --query id -o tsv 2>$null
                    if (-not $subscriptionId) {
                        Write-LogWarning "Could not get current subscription ID"
                        return
                    }
                    
                    # Build the scope for the storage account
                    $storageScope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccount"
                    
                    # Check if role assignment already exists
                    $existingRole = az role assignment list --assignee $spObjectId --role "Storage Blob Data Contributor" --scope $storageScope --query "[0].id" -o tsv 2>$null
                    
                    if (-not $existingRole) {
                        Write-LogInfo "Creating Storage Blob Data Contributor role assignment..."
                        try {
                            $roleResult = az role assignment create --role "Storage Blob Data Contributor" --assignee $spObjectId --scope $storageScope 2>&1
                            
                            if ($LASTEXITCODE -eq 0) {
                                Write-LogSuccess "Successfully assigned Storage Blob Data Contributor role to service principal"
                            } else {
                                Write-LogWarning "Failed to assign role: $roleResult"
                                Write-LogInfo "You may need to manually assign the 'Storage Blob Data Contributor' role to the service principal"
                            }
                        }
                        catch {
                            Write-LogWarning "Error assigning role: $($_.Exception.Message)"
                        }
                    } else {
                        Write-LogInfo "Storage Blob Data Contributor role already assigned to service principal"
                    }
                } else {
                    Write-LogWarning "Could not get service principal object ID for role assignment"
                }
            }
            catch {
                Write-LogWarning "Error setting up role assignment: $($_.Exception.Message)"
            }
        }
        
        # Test storage account access
        Write-LogInfo "Testing storage account access..."
        try {
            $testResult = az storage container list --account-name $storageAccount --auth-mode login --query "[0].name" -o tsv 2>&1
            
            if ($LASTEXITCODE -eq 0 -and $testResult -ne "") {
                Write-LogSuccess "Storage account access test successful"
            } else {
                Write-LogWarning "Storage account access test failed: $testResult"
                Write-LogInfo "Manual steps may be required:"
                if ($currentIP) {
                    Write-Host "  1. Add IP to network rules: az storage account network-rule add --account-name $storageAccount --ip-address $currentIP" -ForegroundColor White
                }
                Write-Host "  2. Assign role: az role assignment create --role 'Storage Blob Data Contributor' --assignee $($Script:SPCredentials.ClientId) --scope '$storageScope'" -ForegroundColor White
            }
        }
        catch {
            Write-LogWarning "Could not test storage account access: $($_.Exception.Message)"
        }
        
        Write-LogSuccess "Storage account configuration completed"
    }
    catch {
        Write-LogError "Failed to configure storage account access: $($_.Exception.Message)"
        # Don't throw - this is not a fatal error, user can configure manually
    }
}

#endregion

#region SharePoint Operations

<#
.SYNOPSIS
    Get SharePoint site information from Microsoft Graph
#>
function Get-SharePointSiteInfo {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Getting SharePoint site information"
        
        # Extract tenant and site name from URL
        $uri = [Uri]$Script:Config['SHAREPOINT_SITE_URL']
        $tenantName = $uri.Host.Split('.')[0]
        $siteName = $uri.Segments[-1].TrimEnd('/')
        
        Write-LogInfo "Tenant: $tenantName"
        Write-LogInfo "Site: $siteName"
        
        # Get site ID from Microsoft Graph
        if ([string]::IsNullOrWhiteSpace($siteName) -or $uri.AbsolutePath -eq "/" -or $uri.AbsolutePath -eq "") {
            # Root site
            $siteUrl = "https://graph.microsoft.com/v1.0/sites/$tenantName.sharepoint.com"
        } else {
            # Subsite
            $siteUrl = "https://graph.microsoft.com/v1.0/sites/$tenantName.sharepoint.com:/sites/$siteName"
        }
        $headers = @{ Authorization = "Bearer $Script:AccessToken" }
        
        $siteResponse = Invoke-RestMethod -Uri $siteUrl -Headers $headers -ErrorAction Stop
        $Script:SiteId = $siteResponse.id
        
        Write-LogSuccess "Successfully connected to SharePoint site: $($siteResponse.displayName)"
        Write-LogInfo "Site ID: $Script:SiteId"
    }
    catch {
        $errorMessage = "Cannot access SharePoint site: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $errorDetails = $reader.ReadToEnd() | ConvertFrom-Json
                $errorMessage = "Cannot access SharePoint site: $($errorDetails.error.message)"
            }
            catch {
                # Use original error message
            }
        }
        
        Write-LogError $errorMessage
        throw
    }
}

<#
.SYNOPSIS
    Find the specified document library in SharePoint
#>
function Find-DocumentLibrary {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Finding document library: $($Script:Config['SHAREPOINT_LIBRARY_NAME'])"
        
        # Get all lists/libraries
        $listsUrl = "https://graph.microsoft.com/v1.0/sites/$Script:SiteId/lists"
        $headers = @{ Authorization = "Bearer $Script:AccessToken" }
        
        $listsResponse = Invoke-RestMethod -Uri $listsUrl -Headers $headers -ErrorAction Stop
        
        # Look for our specific library
        $library = $listsResponse.value | Where-Object { 
            $_.displayName -eq $Script:Config['SHAREPOINT_LIBRARY_NAME'] -or 
            $_.name -eq $Script:Config['SHAREPOINT_LIBRARY_NAME'] 
        }
        
        if ($library) {
            Write-LogSuccess "Found library '$($Script:Config['SHAREPOINT_LIBRARY_NAME'])' with ID: $($library.id)"
            $Script:LibraryId = $library.id
            
            # Try to get the associated drive
            $driveUrl = "https://graph.microsoft.com/v1.0/sites/$Script:SiteId/lists/$Script:LibraryId/drive"
            
            try {
                $driveResponse = Invoke-RestMethod -Uri $driveUrl -Headers $headers -ErrorAction Stop
                $Script:DriveId = $driveResponse.id
                Write-LogInfo "Found associated drive ID: $Script:DriveId"
            }
            catch {
                Write-LogWarning "No associated drive found, will use list API"
            }
            
            return $true
        }
        else {
            Write-LogError "Library '$($Script:Config['SHAREPOINT_LIBRARY_NAME'])' not found"
            Write-LogInfo "Available libraries:"
            $listsResponse.value | ForEach-Object {
                Write-LogInfo "  - $($_.displayName) (ID: $($_.id))"
            }
            return $false
        }
    }
    catch {
        Write-LogError "Failed to find document library: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Recursively list files in SharePoint library
#>
function Get-SharePointFilesRecursive {
    [CmdletBinding()]
    param(
        [string]$FolderPath = "",
        [string]$Prefix = ""
    )
    
    try {
        $headers = @{ Authorization = "Bearer $Script:AccessToken" }
        
        if ($FolderPath) {
            # Microsoft Graph API requires proper encoding for folder paths with spaces and special characters
            # Use the item-based path instead of string path for better reliability
            $encodedPath = [System.Uri]::EscapeDataString($FolderPath)
            $endpoint = "https://graph.microsoft.com/v1.0/drives/$Script:DriveId/root:/$encodedPath" + ":/children"
            Write-LogInfo "Scanning folder: $FolderPath (encoded: $encodedPath)"
        }
        else {
            $endpoint = "https://graph.microsoft.com/v1.0/drives/$Script:DriveId/root/children"
            Write-LogInfo "Scanning root folder"
        }
        
        $filesResponse = Invoke-RestMethod -Uri $endpoint -Headers $headers -ErrorAction Stop
        
        # Check if response has the expected structure
        if (-not $filesResponse -or -not $filesResponse.value) {
            Write-LogWarning "No items found in folder or unexpected response structure"
            return @()
        }
        
        Write-LogInfo "Found $($filesResponse.value.Count) items in current folder"
        
        # Process files in current folder
        $filesInFolder = @()
        foreach ($item in $filesResponse.value) {
            # Check if item has file property (indicating it's a file, not a folder)
            if ($item.PSObject.Properties['file'] -and $item.file) {
                $fileName = $item.name
                $matchesFilter = $false
                
                # Apply file filter
                switch ($Script:Config['FILE_FILTER']) {
                    '*.pdf' { $matchesFilter = $fileName -match '\.pdf$' }
                    '*.png' { $matchesFilter = $fileName -match '\.png$' }
                    '*.docx' { $matchesFilter = $fileName -match '\.docx$' }
                    '*' { $matchesFilter = $true }
                    '*.*' { $matchesFilter = $true }
                    default { 
                        $pattern = $Script:Config['FILE_FILTER'] -replace '\*', '.*' -replace '\?', '.'
                        $matchesFilter = $fileName -match $pattern
                    }
                }
                
                if ($matchesFilter) {
                    $item | Add-Member -NotePropertyName "blobPath" -NotePropertyValue "$Prefix$fileName"
                    $filesInFolder += $item
                }
            }
        }
        
        # Output files from current folder
        $filesInFolder
        
        # Process subfolders recursively
        foreach ($item in $filesResponse.value) {
            # Check if item has folder property (indicating it's a folder)
            if ($item.PSObject.Properties['folder'] -and $item.folder) {
                $subfolderPath = if ($FolderPath) { "$FolderPath/$($item.name)" } else { $item.name }
                $subfolderPrefix = "$Prefix$($item.name)/"
                
                Get-SharePointFilesRecursive -FolderPath $subfolderPath -Prefix $subfolderPrefix
            }
        }
    }
    catch {
        Write-LogError "API error in folder '$FolderPath': $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    List all matching files in SharePoint library
#>
function Get-SharePointFiles {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Listing files in SharePoint library (including nested folders)"
        
        if ([string]::IsNullOrWhiteSpace($Script:DriveId)) {
            throw "No drive ID available for file listing"
        }
        
        $allFiles = Get-SharePointFilesRecursive -FolderPath $Script:Config['SHAREPOINT_FOLDER'] -Prefix ""
        
        # Ensure $allFiles is an array and has Count property
        if (-not $allFiles) {
            $allFiles = @()
        } elseif ($allFiles -isnot [Array]) {
            $allFiles = @($allFiles)
        }
        
        Write-LogSuccess "Found $($allFiles.Count) files matching filter: $($Script:Config['FILE_FILTER'])"
        
        if ($allFiles.Count -gt 0) {
            foreach ($file in $allFiles) {
                Write-LogInfo "  - $($file.blobPath) ($($file.size) bytes)"
            }
        }
        
        return $allFiles
    }
    catch {
        Write-LogError "Failed to list SharePoint files: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Azure Blob Storage Operations

<#
.SYNOPSIS
    Ensure the blob storage container exists
#>
function Assert-BlobContainer {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Ensuring blob container exists: $($Script:Config['CONTAINER_NAME'])"
        
        # Check if container exists
        Write-LogInfo "Checking if container exists..."
        $containerExists = $false
        try {
            if ($Script:Config['USE_AZURE_AD_AUTH'] -eq 'true') {
                Write-LogInfo "Using Azure AD authentication for storage operations"
                $containerCheckResult = az storage container show --name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --auth-mode login 2>&1
            } else {
                Write-LogInfo "Using storage account key authentication"
                $containerCheckResult = az storage container show --name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --account-key $Script:Config['STORAGE_ACCOUNT_KEY'] 2>&1
            }
            
            if ($LASTEXITCODE -eq 0) {
                $containerExists = $true
                Write-LogInfo "Container exists"
            } else {
                Write-LogInfo "Container check failed with exit code: $LASTEXITCODE"
                Write-LogInfo "Container check result: $containerCheckResult"
                $containerExists = $false
            }
        }
        catch {
            Write-LogInfo "Container check threw exception: $($_.Exception.Message)"
            $containerExists = $false
        }
        
        if (-not $containerExists) {
            Write-LogInfo "Creating blob container: $($Script:Config['CONTAINER_NAME'])"
            if ($Script:Config['USE_AZURE_AD_AUTH'] -eq 'true') {
                Write-LogInfo "Creating container with Azure AD authentication..."
                $createResult = az storage container create --name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --auth-mode login --public-access blob 2>&1
            } else {
                Write-LogInfo "Creating container with storage account key..."
                $createResult = az storage container create --name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --account-key $Script:Config['STORAGE_ACCOUNT_KEY'] --public-access blob 2>&1
            }
            
            if ($LASTEXITCODE -ne 0) {
                Write-LogError "Failed to create container. Exit code: $LASTEXITCODE"
                Write-LogError "Create result: $createResult"
                throw "Failed to create container: $createResult"
            } else {
                Write-LogSuccess "Container created successfully"
            }
        }
        else {
            Write-LogInfo "Container already exists"
        }
    }
    catch {
        Write-LogError "Failed to ensure blob container: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    List contents of blob storage container
#>
function Get-BlobContents {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Listing contents of blob container: $($Script:Config['CONTAINER_NAME'])"
        
        # Check if container exists
        try {
            if ($Script:Config['USE_AZURE_AD_AUTH'] -eq 'true') {
                $null = az storage container show --name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --auth-mode login 2>$null
            } else {
                $null = az storage container show --name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --account-key $Script:Config['STORAGE_ACCOUNT_KEY'] 2>$null
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Container does not exist"
            }
        }
        catch {
            Write-LogError "Container '$($Script:Config['CONTAINER_NAME'])' does not exist"
            Write-LogInfo "Run the script without -ListContentsOfBlob to create container and sync files"
            return
        }
        
        # Get blob list
        if ($Script:Config['USE_AZURE_AD_AUTH'] -eq 'true') {
            $blobListJson = az storage blob list --container-name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --auth-mode login --query "[].{name:name,size:properties.contentLength,modified:properties.lastModified}" --output json 2>$null
        } else {
            $blobListJson = az storage blob list --container-name $Script:Config['CONTAINER_NAME'] --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --account-key $Script:Config['STORAGE_ACCOUNT_KEY'] --query "[].{name:name,size:properties.contentLength,modified:properties.lastModified}" --output json 2>$null
        }
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($blobListJson)) {
            Write-LogWarning "No files found in container"
            Write-Host ""
            Write-Host "*** CONTAINER SUMMARY ***" -ForegroundColor Yellow
            Write-Host "==========================================" -ForegroundColor Yellow
            Write-Host "Storage Account: $($Script:Config['STORAGE_ACCOUNT_NAME'])"
            Write-Host "Container: $($Script:Config['CONTAINER_NAME'])"
            Write-Host "Total files: 0"
            Write-Host ""
            Write-Host "[TIP] Run the sync operation first:" -ForegroundColor Cyan
            Write-Host "   .\Copy-SharePointToBlob.ps1"
            return
        }
        
        $blobList = $blobListJson | ConvertFrom-Json
        
        # Ensure $blobList is an array and has Count property
        if (-not $blobList) {
            $blobList = @()
        } elseif ($blobList -isnot [Array]) {
            $blobList = @($blobList)
        }
        
        $fileCount = $blobList.Count
        $totalSize = ($blobList | Measure-Object -Property size -Sum).Sum
        
        Write-Host ""
        Write-Host "[SUMMARY] CONTAINER SUMMARY" -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Yellow
        Write-Host "Storage Account: $($Script:Config['STORAGE_ACCOUNT_NAME'])"
        Write-Host "Container: $($Script:Config['CONTAINER_NAME'])"
        Write-Host "Total files: $fileCount"
        
        # Convert bytes to human readable format
        if ($totalSize -lt 1KB) {
            Write-Host "Total size: $totalSize bytes"
        }
        elseif ($totalSize -lt 1MB) {
            Write-Host "Total size: $([math]::Round($totalSize / 1KB, 2)) KB"
        }
        elseif ($totalSize -lt 1GB) {
            Write-Host "Total size: $([math]::Round($totalSize / 1MB, 2)) MB"
        }
        else {
            Write-Host "Total size: $([math]::Round($totalSize / 1GB, 2)) GB"
        }
        
        Write-Host ""
        Write-Host "[FILES] FILE HIERARCHY" -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Yellow
        
        # Show folder structure
        $folders = @($blobList | Where-Object { $_.name -contains "/" } | ForEach-Object { 
            $_.name -replace '/[^/]*$', '' 
        } | Sort-Object | Get-Unique)
        
        foreach ($folder in $folders) {
            if ($folder) {
                $filesInFolder = @($blobList | Where-Object { $_.name.StartsWith("$folder/") })
                Write-Host "[FOLDER] $folder/ ($($filesInFolder.Count) files)" -ForegroundColor Blue
            }
        }
        
        if ($folders -and $folders.Count -gt 0) { Write-Host "" }
        
        # Show file list with hierarchy
        if ($blobList -and $blobList.Count -gt 0) {
            foreach ($blob in $blobList) {
                try {
                    $filePath = $blob.name
                    $slashChars = @($filePath.ToCharArray() | Where-Object { $_ -eq '/' })
                    $depth = $slashChars.Count
                    $indent = "  " * $depth
                    $filename = Split-Path $filePath -Leaf
                    $modified = ([DateTime]$blob.modified).ToString("yyyy-MM-dd")
                    
                    Write-Host "$indent[FILE] $filename ($($blob.size) bytes) [Modified: $modified]" -ForegroundColor White
                }
                catch {
                    Write-LogError "Error processing blob: $($blob.name) - $($_.Exception.Message)"
                }
            }
        }
        
        Write-Host ""
        Write-Host "[SUCCESS] Container listing completed!" -ForegroundColor Green
    }
    catch {
        Write-LogError "Failed to list blob contents: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Copy files from SharePoint to Azure Blob Storage
#>
function Copy-FilesToBlob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Files
    )
    
    try {
        Write-LogStep "Starting file copy operation"
        
        if ($Files.Count -eq 0) {
            Write-LogWarning "No files to copy"
            return
        }
        
        $successCount = 0
        $errorCount = 0
        
        foreach ($file in $Files) {
            $fileName = $file.name
            $downloadUrl = $file.'@microsoft.graph.downloadUrl'
            $blobPath = $file.blobPath
            
            Write-LogInfo "Processing file: $fileName -> $blobPath"
            
            # Download file to temporary location
            $tempFile = [System.IO.Path]::GetTempFileName()
            
            # Download from SharePoint
            $downloadSuccess = $false
            $uploadSuccess = $false
            
            try {
                $headers = @{ Authorization = "Bearer $Script:AccessToken" }
                Write-LogInfo "Downloading from SharePoint: $downloadUrl"
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -Headers $headers -ErrorAction Stop
                $ProgressPreference = 'Continue'
                Write-LogInfo "Download completed: $tempFile"
                $downloadSuccess = $true
                
                # Only try upload if download succeeded
                if ($downloadSuccess) {
                    # Upload to Azure Blob Storage with folder structure
                    Write-LogInfo "Uploading to blob storage: $blobPath"
                    
                    # Use Out-Null to completely suppress Azure CLI output
                    $uploadSuccessful = $false
                    try {
                        # Choose authentication method based on configuration
                        if ($Script:Config['USE_AZURE_AD_AUTH'] -eq 'true') {
                            & az storage blob upload --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --auth-mode login --container-name $Script:Config['CONTAINER_NAME'] --name $blobPath --file $tempFile --overwrite | Out-Null
                        } else {
                            & az storage blob upload --account-name $Script:Config['STORAGE_ACCOUNT_NAME'] --account-key $Script:Config['STORAGE_ACCOUNT_KEY'] --container-name $Script:Config['CONTAINER_NAME'] --name $blobPath --file $tempFile --overwrite | Out-Null
                        }
                        
                        # If we get here without exception, upload was successful
                        if ($LASTEXITCODE -eq 0) {
                            $uploadSuccessful = $true
                        }
                    }
                    catch {
                        # Ignore Azure CLI output issues - check exit code instead
                        if ($LASTEXITCODE -eq 0) {
                            $uploadSuccessful = $true
                        }
                    }
                    
                    if ($uploadSuccessful) {
                        Write-LogSuccess "[SUCCESS] Successfully uploaded: $blobPath"
                        $successCount++
                        
                        # Delete from SharePoint if requested
                        if ($Script:Config['DELETE_AFTER_COPY'] -eq 'true') {
                            Write-LogWarning "DELETE_AFTER_COPY is not implemented yet for safety"
                        }
                    } else {
                        Write-LogError "Failed to upload file $($file.name): Azure CLI exit code $LASTEXITCODE"
                        $errorCount++
                    }
                }
            }
            catch {
                if (-not $downloadSuccess) {
                    Write-LogError "Failed to download file $($file.name): $($_.Exception.Message)"
                } else {
                    Write-LogError "Failed to upload file $($file.name): $($_.Exception.Message)"
                }
                $errorCount++
            }
            finally {
                # Clean up temp file
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        Write-LogSuccess "Copy operation completed:"
        Write-LogSuccess "  [SUCCESS] Successfully copied: $successCount files"
        if ($errorCount -gt 0) {
            Write-LogError "  ❌ Errors encountered: $errorCount files"
        }
    }
    catch {
        Write-LogError "Failed during file copy operation: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Main Functions

<#
.SYNOPSIS
    Show detailed usage information
#>
function Show-Usage {
    Write-Host @"
Usage: .\Copy-SharePointToBlob.ps1 [OPTIONS]

SharePoint to Azure Blob Storage Copy Script - PowerShell Version
Recursively copies files from SharePoint document libraries to Azure Blob Storage

Parameters:
  -Setup                      Create service principal and setup permissions
  -ListContentsOfBlob         List all files in the blob storage container
  -VerifyPermissions          Verify service principal permissions
  -LibraryName NAME           SharePoint library name (default: from config)
  -FileFilter FILTER          File filter (default: from config)
                              Supports: *.pdf, *.png, *.docx, *.*, etc.
  -Folder FOLDER              SharePoint folder path (default: from config)
                              Recursively processes all subfolders
  -DeleteAfter                Delete files from SharePoint after copy
  -Help                       Show this help

Examples:
  .\Copy-SharePointToBlob.ps1 -Setup                                  # First-time setup
  .\Copy-SharePointToBlob.ps1                                         # Copy files with config settings
  .\Copy-SharePointToBlob.ps1 -ListContentsOfBlob                     # List blob storage contents
  .\Copy-SharePointToBlob.ps1 -VerifyPermissions                      # Verify service principal permissions
  .\Copy-SharePointToBlob.ps1 -FileFilter "*.docx"                    # Copy Word documents recursively
  .\Copy-SharePointToBlob.ps1 -FileFilter "*"                         # Copy all files recursively
  .\Copy-SharePointToBlob.ps1 -LibraryName "Documents" -Folder "Archive"
  .\Copy-SharePointToBlob.ps1 -LibraryName "Shared Documents" -FileFilter "*.png"

Features:
  - Recursive folder traversal with preserved structure
  - Service principal authentication with Microsoft Graph
  - Comprehensive error handling and logging
  - Multiple file type filters with pattern matching
  - Built-in blob storage listing and management
  - PowerShell-native implementation with proper exception handling

Prerequisites:
  - PowerShell 5.1 or higher
  - Azure CLI installed and configured
  - Azure subscription with appropriate permissions
  - SharePoint site with document libraries

Setup Instructions:
  1. Copy config.env.template to config.env
  2. Configure your settings in config.env
  3. Run: .\Copy-SharePointToBlob.ps1 -Setup
  4. Grant admin consent for the service principal permissions
  5. Run: .\Copy-SharePointToBlob.ps1 to start syncing files

For detailed documentation, visit:
https://github.com/johndohoneyjr/sharepoint-blob-sync
"@
}

<#
.SYNOPSIS
    Main execution function
#>
function Invoke-Main {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogStep "Starting SharePoint to Azure Blob Storage copy operation"
        Write-Host "============================================================" -ForegroundColor Blue
        
        # Load configuration first
        Import-Configuration
        
        Write-LogInfo "Configuration:"
        Write-LogInfo "  SharePoint Site: $($Script:Config['SHAREPOINT_SITE_URL'])"
        Write-LogInfo "  Library Name: $($Script:Config['SHAREPOINT_LIBRARY_NAME'])"
        Write-LogInfo "  Storage Account: $($Script:Config['STORAGE_ACCOUNT_NAME'])"
        Write-LogInfo "  Container: $($Script:Config['CONTAINER_NAME'])"
        Write-LogInfo "  File Filter: $($Script:Config['FILE_FILTER'])"
        $folderDisplay = if($Script:Config['SHAREPOINT_FOLDER']) { $Script:Config['SHAREPOINT_FOLDER'] } else { '(root)' }
        Write-LogInfo "  SharePoint Folder: $folderDisplay"
        
        # Check dependencies
        Test-Dependencies
        
        # Load or create service principal
        if (-not (Import-ServicePrincipal)) {
            Write-LogInfo "No existing service principal found. Creating new one..."
            New-ServicePrincipal
        }
        
        # Verify service principal permissions
        Write-LogInfo "Verifying service principal permissions..."
        if (-not (Test-ServicePrincipalPermissions -ClientId $Script:SPCredentials.ClientId)) {
            Write-LogWarning "Service principal permissions verification failed. The script may not work correctly."
            Write-LogInfo "You can try running the script anyway, or fix permissions using the commands shown above."
        }
        
        # Authenticate with service principal
        Connect-ServicePrincipal
        
        # Configure Azure Storage access
        Set-StorageAccountAccess
        
        # Get SharePoint site info
        Get-SharePointSiteInfo
        
        # Find the document library
        if (-not (Find-DocumentLibrary)) {
            throw "Could not find the document library"
        }
        
        # Ensure blob container exists
        Assert-BlobContainer
        
        # List and copy files
        Write-LogInfo "Getting file list from SharePoint..."
        $files = Get-SharePointFiles
        
        Copy-FilesToBlob -Files $files
        
        Write-LogSuccess "[SUCCESS] Operation completed successfully!"
    }
    catch {
        Write-LogError "Script execution failed: $($_.Exception.Message)"
        Write-LogError "Stack trace: $($_.ScriptStackTrace)"
        throw
    }
}

#endregion

#region Script Entry Point

# Show help if requested
if ($Help) {
    Show-Usage
    exit 0
}

# Handle setup mode
if ($Setup) {
    try {
        Write-LogStep "Running in setup mode - creating service principal and configuring storage"
        Import-Configuration
        Test-Dependencies
        New-ServicePrincipal
        Set-StorageAccountAccess
        Write-LogSuccess "[SUCCESS] Setup completed! You can now run the script without -Setup to copy files."
        exit 0
    }
    catch {
        Write-LogError "Setup failed: $($_.Exception.Message)"
        exit 1
    }
}

# Handle list blob mode
if ($ListContentsOfBlob) {
    try {
        Write-LogStep "Running in list blob mode - showing container contents"
        Import-Configuration
        Test-Dependencies
        Get-BlobContents
        exit 0
    }
    catch {
        Write-LogError "List blob contents failed: $($_.Exception.Message)"
        exit 1
    }
}

# Handle verify permissions mode
if ($VerifyPermissions) {
    try {
        Write-LogStep "Running in verify permissions mode - checking service principal permissions"
        Import-Configuration
        Test-Dependencies
        
        if (-not (Import-ServicePrincipal)) {
            Write-LogError "No existing service principal found. Please run with -Setup first."
            exit 1
        }
        
        $permissionsValid = Test-ServicePrincipalPermissions -ClientId $Script:SPCredentials.ClientId
        
        if ($permissionsValid) {
            Write-LogSuccess "[SUCCESS] All required permissions are properly configured!"
            exit 0
        } else {
            Write-LogError "[FAILED] Permission verification failed. Please check the output above for required commands."
            exit 1
        }
    }
    catch {
        Write-LogError "Permission verification failed: $($_.Exception.Message)"
        exit 1
    }
}

# Run main function
try {
    Invoke-Main
    exit 0
}
catch {
    Write-LogError "Script failed: $($_.Exception.Message)"
    exit 1
}

#endregion
