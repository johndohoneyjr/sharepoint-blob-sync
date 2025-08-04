#Requires -Version 5.1

<#
.SYNOPSIS
    Security validation script for SharePoint to Blob copy setup - PowerShell Version

.DESCRIPTION
    Validates security configurations and permissions for the SharePoint to Azure Blob Storage sync setup.
    
    Checks include:
    - Sensitive file detection and .gitignore validation
    - File permissions and access controls
    - Configuration security validation
    - Azure CLI security assessment
    - Service principal security review
    - Network security considerations

.PARAMETER Detailed
    Show detailed security analysis and recommendations

.PARAMETER Fix
    Attempt to automatically fix some security issues (where safe)

.EXAMPLE
    .\Security-Check.ps1
    Run basic security validation

.EXAMPLE
    .\Security-Check.ps1 -Detailed
    Run detailed security analysis

.EXAMPLE
    .\Security-Check.ps1 -Fix
    Run security check and attempt to fix issues

.NOTES
    Author: SharePoint-Blob Sync Team
    Version: 2.0 (PowerShell)
    Requires: PowerShell 5.1+
    
    This script helps ensure your SharePoint-Blob sync setup follows security best practices.
#>

[CmdletBinding()]
param(
    [switch]$Detailed,
    [switch]$Fix
)

# Set error handling
$ErrorActionPreference = 'Continue'

# Security check counters
$script:SecurityIssues = 0
$script:SecurityWarnings = 0
$script:SecurityPassed = 0

# Color functions for consistent output
function Write-ColoredText {
    param(
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Success { 
    param([string]$Text) 
    Write-ColoredText $Text -Color Green 
    $script:SecurityPassed++
}

function Write-SecurityError { 
    param([string]$Text) 
    Write-ColoredText $Text -Color Red 
    $script:SecurityIssues++
}

function Write-SecurityInfo { 
    param([string]$Text) 
    Write-ColoredText $Text -Color Cyan 
}

function Write-SecurityWarning { 
    param([string]$Text) 
    Write-ColoredText $Text -Color Yellow 
    $script:SecurityWarnings++
}

function Write-SecurityStep {
    param([string]$Text) 
    Write-ColoredText $Text -Color Blue 
}

function Write-CheckTitle {
    param([string]$Title, [int]$CheckNumber)
    Write-SecurityInfo "Check $CheckNumber`: $Title"
}

# Helper function to test if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Helper function to get file permissions
function Get-FilePermissions {
    param([string]$FilePath)
    
    try {
        if (Test-Path $FilePath) {
            $acl = Get-Acl $FilePath -ErrorAction Stop
            return $acl.Access
        }
    }
    catch {
        return $null
    }
}

# Main security check execution
try {
    Write-SecurityStep "🔒 Security Check - SharePoint to Blob Copy (PowerShell Version)"
    Write-SecurityStep "================================================================"
    Write-Host ""

    # Check 1: Scan for sensitive files in repository
    Write-CheckTitle "Scanning for sensitive files in repository" 1
    
    $sensitiveFilePatterns = @(
        "config.env",
        ".sp_credentials", 
        "*.key", 
        "*.pem", 
        "*.p12", 
        "*.pfx",
        "*.json",  # Could contain service account keys
        "*secret*",
        "*password*",
        "*.log"    # May contain sensitive information
    )
    
    $foundSensitiveFiles = @()
    $repoRoot = $PSScriptRoot
    
    foreach ($pattern in $sensitiveFilePatterns) {
        try {
            $files = Get-ChildItem -Path $repoRoot -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
            $foundSensitiveFiles += $files.FullName
        }
        catch {
            # Ignore errors from Get-ChildItem
        }
    }
    
    # Remove duplicates and filter out known safe files
    $foundSensitiveFiles = $foundSensitiveFiles | Sort-Object | Get-Unique
    $knownSafeFiles = @(
        "config.env.template",
        "package.json",
        "package-lock.json"
    )
    
    $actualSensitiveFiles = $foundSensitiveFiles | Where-Object {
        $fileName = Split-Path $_ -Leaf
        $fileName -notin $knownSafeFiles
    }
    
    if ($actualSensitiveFiles.Count -eq 0) {
        Write-Success "✅ No sensitive files found in repository"
    }
    else {
        Write-SecurityWarning "⚠️ Sensitive files detected:"
        foreach ($file in $actualSensitiveFiles) {
            $relativePath = $file.Replace($repoRoot, ".")
            Write-SecurityWarning "   - $relativePath"
        }
        Write-SecurityInfo "Ensure these files are in .gitignore and not committed to version control"
    }

    # Check 2: Validate .gitignore configuration
    Write-CheckTitle "Validating .gitignore configuration" 2
    
    $gitignoreFile = Join-Path $repoRoot ".gitignore"
    
    if (Test-Path $gitignoreFile) {
        $gitignoreContent = Get-Content $gitignoreFile -Raw -ErrorAction SilentlyContinue
        $requiredEntries = @(
            "config.env",
            ".sp_credentials", 
            "*.log",
            "*.tmp",
            "temp/",
            "logs/"
        )
        
        $missingEntries = @()
        
        foreach ($entry in $requiredEntries) {
            $escapedEntry = [regex]::Escape($entry)
            if ($gitignoreContent -notmatch $escapedEntry) {
                $missingEntries += $entry
            }
        }
        
        if ($missingEntries.Count -eq 0) {
            Write-Success "✅ .gitignore properly configured"
        }
        else {
            Write-SecurityWarning "⚠️ Missing .gitignore entries:"
            foreach ($entry in $missingEntries) {
                Write-SecurityWarning "   - $entry"
            }
            
            if ($Fix) {
                try {
                    Write-SecurityInfo "Attempting to fix .gitignore..."
                    foreach ($entry in $missingEntries) {
                        Add-Content -Path $gitignoreFile -Value $entry -ErrorAction Stop
                    }
                    Write-Success "✅ Added missing entries to .gitignore"
                    $script:SecurityWarnings-- # Decrement since we fixed it
                    $script:SecurityPassed++
                }
                catch {
                    Write-SecurityError "❌ Failed to update .gitignore: $($_.Exception.Message)"
                }
            }
        }
    }
    else {
        Write-SecurityError "❌ .gitignore file not found"
        Write-SecurityInfo "Create .gitignore with sensitive file patterns"
        
        if ($Fix) {
            try {
                Write-SecurityInfo "Creating .gitignore file..."
                $gitignoreTemplate = @"
# Sensitive configuration files
config.env
.sp_credentials

# Log files
*.log
logs/

# Temporary files
*.tmp
temp/

# Azure CLI cache
.azure/

# PowerShell execution policy bypass files
*.ps1.txt

# Windows specific
Thumbs.db
Desktop.ini
"@
                $gitignoreTemplate | Out-File -FilePath $gitignoreFile -Encoding UTF8
                Write-Success "✅ Created .gitignore file with security entries"
                $script:SecurityIssues-- # Decrement since we fixed it
                $script:SecurityPassed++
            }
            catch {
                Write-SecurityError "❌ Failed to create .gitignore: $($_.Exception.Message)"
            }
        }
    }

    # Check 3: File permissions validation
    Write-CheckTitle "Checking file permissions" 3
    
    $sensitiveFilesToCheck = @("config.env", ".sp_credentials")
    $permissionIssues = @()
    
    foreach ($file in $sensitiveFilesToCheck) {
        $filePath = Join-Path $repoRoot $file
        if (Test-Path $filePath) {
            $permissions = Get-FilePermissions $filePath
            
            if ($permissions) {
                # Check for overly permissive permissions
                $everyoneAccess = $permissions | Where-Object { 
                    $_.IdentityReference -eq "Everyone" -or 
                    $_.IdentityReference -eq "BUILTIN\Users" 
                }
                
                if ($everyoneAccess) {
                    $permissionIssues += $file
                }
                
                if ($Detailed) {
                    Write-SecurityInfo "   $file permissions:"
                    foreach ($perm in $permissions | Select-Object -First 3) {
                        Write-SecurityInfo "     $($perm.IdentityReference): $($perm.FileSystemRights)"
                    }
                }
            }
        }
    }
    
    if ($permissionIssues.Count -eq 0) {
        Write-Success "✅ File permissions appear secure"
    }
    else {
        Write-SecurityWarning "⚠️ Files with potentially overly permissive access:"
        foreach ($file in $permissionIssues) {
            Write-SecurityWarning "   - $file"
        }
        Write-SecurityInfo "Consider restricting access to current user only"
        Write-SecurityInfo "Use: icacls 'filename' /inheritance:r /grant:r `"$env:USERNAME`":F"
    }

    # Check 4: Configuration security validation
    Write-CheckTitle "Validating configuration security" 4
    
    $configFile = Join-Path $repoRoot "config.env"
    
    if (Test-Path $configFile) {
        $configContent = Get-Content $configFile -Raw -ErrorAction SilentlyContinue
        
        # Check for placeholder values
        $placeholders = @(
            "your-tenant", 
            "your-site", 
            "your-storage-account", 
            "your-container",
            "example.com",
            "changeme",
            "placeholder"
        )
        
        $foundPlaceholders = @()
        foreach ($placeholder in $placeholders) {
            if ($configContent -match $placeholder) {
                $foundPlaceholders += $placeholder
            }
        }
        
        if ($foundPlaceholders.Count -eq 0) {
            Write-Success "✅ Configuration appears to be customized"
        }
        else {
            Write-SecurityWarning "⚠️ Configuration contains placeholder values:"
            foreach ($placeholder in $foundPlaceholders) {
                Write-SecurityWarning "   - $placeholder"
            }
            Write-SecurityInfo "Replace all placeholder values with actual configuration"
        }
        
        # Check for hardcoded secrets (basic check)
        if ($configContent -match "password|secret|key.*=.*[a-zA-Z0-9]{20,}") {
            Write-SecurityWarning "⚠️ Configuration may contain hardcoded secrets"
            Write-SecurityInfo "Consider using Azure Key Vault for production deployments"
        }
    }
    else {
        Write-SecurityInfo "ℹ️ config.env not found (expected for initial setup)"
    }

    # Check 5: Azure CLI security assessment
    Write-CheckTitle "Azure CLI security assessment" 5
    
    try {
        $account = & az account show --query "{name:name,tenantId:tenantId,user:user}" -o json 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $account) {
            $accountInfo = $account | ConvertFrom-Json
            Write-Success "✅ Azure CLI authenticated"
            
            if ($Detailed) {
                Write-SecurityInfo "   Account: $($accountInfo.name)"
                Write-SecurityInfo "   Tenant: $($accountInfo.tenantId)"
                Write-SecurityInfo "   User Type: $($accountInfo.user.type)"
            }
            
            # Check if using service principal vs user account
            if ($accountInfo.user.type -eq "servicePrincipal") {
                Write-SecurityInfo "   Authentication Type: Service Principal (Recommended for automation)"
            }
            else {
                Write-SecurityInfo "   Authentication Type: User Account"
                Write-SecurityInfo "   Consider using service principal for automated scenarios"
            }
            
            # Check for saved credentials
            $azureDir = Join-Path $env:USERPROFILE ".azure"
            if (Test-Path $azureDir) {
                $credFiles = Get-ChildItem $azureDir -Filter "*" -File | Measure-Object
                if ($credFiles.Count -gt 0) {
                    Write-SecurityInfo "   Azure CLI cache directory contains $($credFiles.Count) files"
                    Write-SecurityInfo "   Ensure ~/.azure directory is secure and not shared"
                }
            }
        }
        else {
            Write-SecurityWarning "⚠️ Azure CLI not authenticated"
            Write-SecurityInfo "Run: az login"
        }
    }
    catch {
        Write-SecurityWarning "⚠️ Could not assess Azure CLI security"
    }

    # Check 6: Service principal security review
    Write-CheckTitle "Service principal security review" 6
    
    $spCredentialsFile = Join-Path $repoRoot ".sp_credentials"
    
    if (Test-Path $spCredentialsFile) {
        Write-Success "✅ Service principal credentials file exists"
        
        # Check file age (secrets should be rotated regularly)
        $fileAge = (Get-Date) - (Get-Item $spCredentialsFile).LastWriteTime
        
        if ($fileAge.Days -gt 90) {
            Write-SecurityWarning "⚠️ Service principal credentials are $($fileAge.Days) days old"
            Write-SecurityInfo "Consider rotating service principal secrets regularly (recommended: 90 days)"
        }
        elseif ($fileAge.Days -gt 30) {
            Write-SecurityInfo "ℹ️ Service principal credentials are $($fileAge.Days) days old"
        }
        
        if ($Detailed) {
            # Validate credential format without exposing secrets
            try {
                $spContent = Get-Content $spCredentialsFile -ErrorAction Stop
                $hasClientId = $spContent | Where-Object { $_ -match '^SP_CLIENT_ID=' }
                $hasClientSecret = $spContent | Where-Object { $_ -match '^SP_CLIENT_SECRET=' }
                $hasTenantId = $spContent | Where-Object { $_ -match '^SP_TENANT_ID=' }
                
                if ($hasClientId -and $hasClientSecret -and $hasTenantId) {
                    Write-SecurityInfo "   Service principal credentials format: Valid"
                }
                else {
                    Write-SecurityWarning "   Service principal credentials may be incomplete"
                }
            }
            catch {
                Write-SecurityWarning "   Could not validate service principal credentials format"
            }
        }
    }
    else {
        Write-SecurityInfo "ℹ️ Service principal not configured yet"
        Write-SecurityInfo "Run setup to create service principal with least privilege permissions"
    }

    # Check 7: PowerShell execution policy
    Write-CheckTitle "PowerShell execution policy" 7
    
    $executionPolicy = Get-ExecutionPolicy
    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    
    if ($executionPolicy -eq 'Restricted' -or $currentUserPolicy -eq 'Restricted') {
        Write-SecurityWarning "⚠️ PowerShell execution policy is Restricted"
        Write-SecurityInfo "You may need to run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
    }
    elseif ($executionPolicy -eq 'Unrestricted' -or $currentUserPolicy -eq 'Unrestricted') {
        Write-SecurityWarning "⚠️ PowerShell execution policy is Unrestricted"
        Write-SecurityInfo "Consider using RemoteSigned for better security"
    }
    else {
        Write-Success "✅ PowerShell execution policy: $executionPolicy (Secure)"
    }

    # Check 8: Network security considerations
    Write-CheckTitle "Network security considerations" 8
    
    # Check for proxy settings that might affect security
    $proxySettings = [System.Net.WebRequest]::DefaultWebProxy
    if ($proxySettings -and $proxySettings.Address) {
        Write-SecurityInfo "ℹ️ System proxy detected: $($proxySettings.Address)"
        Write-SecurityInfo "Ensure proxy configuration is secure and trusted"
    }
    
    # Check TLS settings
    $tlsVersions = [System.Net.ServicePointManager]::SecurityProtocol
    if ($tlsVersions -match 'Tls12|Tls13') {
        Write-Success "✅ Secure TLS versions enabled: $tlsVersions"
    }
    else {
        Write-SecurityWarning "⚠️ Insecure TLS configuration detected"
        Write-SecurityInfo "Ensure TLS 1.2 or higher is enabled"
    }

    # Summary
    Write-Host ""
    Write-SecurityStep "📊 SECURITY ASSESSMENT SUMMARY"
    Write-SecurityStep "=============================="
    Write-Success "✅ Security checks passed: $script:SecurityPassed"
    
    if ($script:SecurityWarnings -gt 0) {
        Write-SecurityWarning "⚠️ Security warnings: $script:SecurityWarnings"
    }
    
    if ($script:SecurityIssues -gt 0) {
        Write-SecurityError "❌ Security issues found: $script:SecurityIssues"
    }

    Write-Host ""
    Write-SecurityStep "🛡️ SECURITY RECOMMENDATIONS"
    Write-SecurityStep "==========================="
    Write-SecurityInfo "1. Never commit config.env or .sp_credentials to version control"
    Write-SecurityInfo "2. Use least privilege principle for service principal permissions"
    Write-SecurityInfo "3. Regularly rotate service principal secrets (every 90 days)"
    Write-SecurityInfo "4. Monitor Azure Activity Logs for unusual access patterns"
    Write-SecurityInfo "5. Use Azure Key Vault for production deployments"
    Write-SecurityInfo "6. Enable MFA for Azure accounts with admin permissions"
    Write-SecurityInfo "7. Regularly review and audit access permissions"
    Write-SecurityInfo "8. Use managed identities when possible (for Azure-hosted workloads)"
    Write-SecurityInfo "9. Implement network security groups and firewall rules"
    Write-SecurityInfo "10. Enable logging and monitoring for security events"

    if ($Detailed) {
        Write-Host ""
        Write-SecurityStep "🔧 ADVANCED SECURITY MEASURES"
        Write-SecurityStep "============================="
        Write-SecurityInfo "• Implement Conditional Access policies in Azure AD"
        Write-SecurityInfo "• Use Azure Privileged Identity Management (PIM)"
        Write-SecurityInfo "• Enable Azure Security Center recommendations"
        Write-SecurityInfo "• Implement Azure Sentinel for security monitoring"
        Write-SecurityInfo "• Use Azure Policy to enforce security standards"
        Write-SecurityInfo "• Regular security assessments and penetration testing"
    }

    Write-Host ""
    
    if ($script:SecurityIssues -eq 0) {
        Write-Success "🎉 Security check completed successfully!"
        Write-SecurityInfo "Your SharePoint-Blob sync setup follows security best practices"
        exit 0
    }
    else {
        Write-SecurityWarning "⚠️ Security check completed with $script:SecurityIssues issue(s) found"
        Write-SecurityInfo "Please address the issues above before proceeding to production"
        exit $script:SecurityIssues
    }
}
catch {
    Write-SecurityError "❌ Security check failed with error: $($_.Exception.Message)"
    Write-SecurityInfo "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}

