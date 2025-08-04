#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Example script demonstrating SharePoint Blob Sync scheduler setup

.DESCRIPTION
    This script provides examples of how to set up and manage the
    SharePoint to Azure Blob Storage sync scheduler with different
    configurations.

.EXAMPLE
    .\Setup-Examples.ps1
    Run interactive examples

.NOTES
    File Name      : Setup-Examples.ps1
    Author         : SharePoint Blob Sync Team
    Prerequisite   : Administrator privileges, Setup-Scheduler.ps1
#>

# Color functions
function Write-Info { param([string]$Text) Write-Host $Text -ForegroundColor Cyan }
function Write-Success { param([string]$Text) Write-Host $Text -ForegroundColor Green }
function Write-Warning { param([string]$Text) Write-Host $Text -ForegroundColor Yellow }

function Show-Examples {
    Write-Info "=== SHAREPOINT BLOB SYNC SCHEDULER EXAMPLES ==="
    Write-Info "==============================================="
    Write-Host ""
    
    Write-Info "1. BASIC SETUP (5 minutes interval)"
    Write-Success "   .\Setup-Scheduler.ps1"
    Write-Host ""
    
    Write-Info "2. CUSTOM INTERVALS"
    Write-Success "   # Every 10 minutes"
    Write-Success "   .\Setup-Scheduler.ps1 -IntervalMinutes 10"
    Write-Host ""
    Write-Success "   # Every 2 hours"
    Write-Success "   .\Setup-Scheduler.ps1 -IntervalHours 2"
    Write-Host ""
    Write-Success "   # Daily at 9:00 AM"
    Write-Success "   .\Setup-Scheduler.ps1 -DailyAt `"09:00`""
    Write-Host ""
    
    Write-Info "3. MANAGEMENT COMMANDS"
    Write-Success "   # Check status"
    Write-Success "   .\Setup-Scheduler.ps1 -Status"
    Write-Host ""
    Write-Success "   # Remove task"
    Write-Success "   .\Setup-Scheduler.ps1 -Remove"
    Write-Host ""
    Write-Success "   # Start immediately after setup"
    Write-Success "   .\Setup-Scheduler.ps1 -StartNow"
    Write-Host ""
    
    Write-Info "4. MANUAL SYNC TESTING"
    Write-Success "   # Test sync manually"
    Write-Success "   .\Run-Sync.ps1"
    Write-Host ""
    Write-Success "   # Verbose logging"
    Write-Success "   .\Run-Sync.ps1 -LogLevel Verbose"
    Write-Host ""
    Write-Success "   # Force sync with retries"
    Write-Success "   .\Run-Sync.ps1 -ForceSync -MaxRetries 5"
    Write-Host ""
    
    Write-Info "5. MONITORING"
    Write-Success "   # View recent logs"
    Write-Success "   Get-Content .\logs\sync_`$(Get-Date -Format 'yyyyMMdd').log -Tail 20"
    Write-Host ""
    Write-Success "   # Check current status"
    Write-Success "   Get-Content .\logs\sync_status.json | ConvertFrom-Json"
    Write-Host ""
}

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    $issues = @()
    
    # Check if running as administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (!$isAdmin) {
        $issues += "Not running as Administrator (required for scheduled task management)"
    }
    
    # Check for required scripts
    $requiredScripts = @("Setup-Scheduler.ps1", "Run-Sync.ps1", "Copy-SharePointToBlob.ps1", "Quick-Test.ps1")
    foreach ($script in $requiredScripts) {
        if (!(Test-Path $script)) {
            $issues += "Missing required script: $script"
        }
    }
    
    # Check config file
    if (!(Test-Path "config.env")) {
        $issues += "Missing config.env file (copy from config.env.template and configure)"
    }
    
    if ($issues.Count -eq 0) {
        Write-Success "✓ All prerequisites met"
        return $true
    }
    else {
        Write-Warning "Prerequisites check failed:"
        foreach ($issue in $issues) {
            Write-Warning "  - $issue"
        }
        return $false
    }
}

function Show-InteractiveMenu {
    do {
        Write-Host ""
        Write-Info "=== INTERACTIVE SCHEDULER SETUP ==="
        Write-Info "1. Setup every 5 minutes (default)"
        Write-Info "2. Setup every 15 minutes" 
        Write-Info "3. Setup every hour"
        Write-Info "4. Setup daily at 9:00 AM"
        Write-Info "5. Check current status"
        Write-Info "6. Remove scheduled task"
        Write-Info "7. Test manual sync"
        Write-Info "8. View recent logs"
        Write-Info "9. Show all examples"
        Write-Info "0. Exit"
        Write-Host ""
        
        $choice = Read-Host "Select option (0-9)"
        
        switch ($choice) {
            "1" {
                Write-Info "Setting up 5-minute interval sync..."
                & .\Setup-Scheduler.ps1 -StartNow
            }
            "2" {
                Write-Info "Setting up 15-minute interval sync..."
                & .\Setup-Scheduler.ps1 -IntervalMinutes 15 -StartNow
            }
            "3" {
                Write-Info "Setting up hourly sync..."
                & .\Setup-Scheduler.ps1 -IntervalHours 1 -StartNow
            }
            "4" {
                Write-Info "Setting up daily sync at 9:00 AM..."
                & .\Setup-Scheduler.ps1 -DailyAt "09:00" -StartNow
            }
            "5" {
                Write-Info "Checking scheduler status..."
                & .\Setup-Scheduler.ps1 -Status
            }
            "6" {
                Write-Warning "Removing scheduled task..."
                & .\Setup-Scheduler.ps1 -Remove
            }
            "7" {
                Write-Info "Running manual sync test..."
                & .\Run-Sync.ps1 -LogLevel Normal
            }
            "8" {
                Write-Info "Recent sync logs:"
                $logFile = ".\logs\sync_$(Get-Date -Format 'yyyyMMdd').log"
                if (Test-Path $logFile) {
                    Get-Content $logFile -Tail 10
                }
                else {
                    Write-Warning "No log file found for today: $logFile"
                }
            }
            "9" {
                Show-Examples
            }
            "0" {
                Write-Info "Exiting..."
                break
            }
            default {
                Write-Warning "Invalid choice. Please select 0-9."
            }
        }
        
        if ($choice -ne "0") {
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
    } while ($choice -ne "0")
}

# Main execution
try {
    Write-Info "*** SharePoint Blob Sync - Scheduler Examples ***"
    Write-Host ""
    
    if (!(Test-Prerequisites)) {
        Write-Warning "Please fix the prerequisites before continuing."
        exit 1
    }
    
    # Check if any parameters were passed - if not, show interactive menu
    if ($args.Count -eq 0) {
        Show-InteractiveMenu
    }
    else {
        Show-Examples
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
