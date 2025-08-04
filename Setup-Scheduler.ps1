#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup Windows Task Scheduler for SharePoint to Azure Blob Storage sync

.DESCRIPTION
    This script creates and manages a Windows scheduled task to run the SharePoint
    to Blob Storage synchronization at configurable intervals. Supports various
    scheduling options including minutes, hours, and daily schedules.

.PARAMETER IntervalMinutes
    Run the sync every X minutes (default: 5 minutes)

.PARAMETER IntervalHours
    Run the sync every X hours (alternative to minutes)

.PARAMETER DailyAt
    Run the sync daily at specific time (e.g., "09:00", "14:30")

.PARAMETER TaskName
    Name of the scheduled task (default: "SharePoint-Blob-Sync")

.PARAMETER Remove
    Remove the existing scheduled task

.PARAMETER Status
    Show the current status of the scheduled task

.PARAMETER StartNow
    Start the scheduled task immediately after creation

.PARAMETER RunAsUser
    Specify the user account to run the task (default: current user)

.PARAMETER LogPath
    Path for task execution logs (default: .\logs\scheduler.log)

.EXAMPLE
    .\Setup-Scheduler.ps1
    Setup with default 5-minute interval

.EXAMPLE
    .\Setup-Scheduler.ps1 -IntervalMinutes 10
    Setup to run every 10 minutes

.EXAMPLE
    .\Setup-Scheduler.ps1 -IntervalHours 2
    Setup to run every 2 hours

.EXAMPLE
    .\Setup-Scheduler.ps1 -DailyAt "09:00"
    Setup to run daily at 9:00 AM

.EXAMPLE
    .\Setup-Scheduler.ps1 -Status
    Check the current status of the scheduled task

.EXAMPLE
    .\Setup-Scheduler.ps1 -Remove
    Remove the scheduled task

.NOTES
    File Name      : Setup-Scheduler.ps1
    Author         : SharePoint Blob Sync Team
    Prerequisite   : Windows PowerShell 5.1+, Administrator privileges
    Version        : 1.0
#>

[CmdletBinding()]
param(
    [int]$IntervalMinutes = 5,
    [int]$IntervalHours,
    [string]$DailyAt,
    [string]$TaskName = "SharePoint-Blob-Sync",
    [switch]$Remove,
    [switch]$Status,
    [switch]$StartNow,
    [string]$RunAsUser = $env:USERNAME,
    [string]$LogPath = ".\logs\scheduler.log"
)

# Set error handling
$ErrorActionPreference = 'Stop'

# Color functions for consistent output
function Write-ColoredText {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White)
    Write-Host $Text -ForegroundColor $Color
}

function Write-Step { param([string]$Text) Write-ColoredText $Text -Color Cyan }
function Write-Success { param([string]$Text) Write-ColoredText $Text -Color Green }
function Write-Warning { param([string]$Text) Write-ColoredText $Text -Color Yellow }
function Write-Error { param([string]$Text) Write-ColoredText $Text -Color Red }
function Write-Info { param([string]$Text) Write-ColoredText $Text -Color Gray }

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TaskStatus {
    param([string]$Name)
    
    try {
        $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $Name
            return @{
                Exists = $true
                State = $task.State
                LastRunTime = $taskInfo.LastRunTime
                NextRunTime = $taskInfo.NextRunTime
                LastTaskResult = $taskInfo.LastTaskResult
            }
        }
        else {
            return @{ Exists = $false }
        }
    }
    catch {
        return @{ Exists = $false; Error = $_.Exception.Message }
    }
}

function Show-TaskStatus {
    param([string]$Name)
    
    Write-Step "*** SCHEDULED TASK STATUS ***"
    Write-Step "=============================="
    
    $status = Get-TaskStatus -Name $Name
    
    if ($status.Exists) {
        Write-Success "Task '$Name' exists"
        Write-Info "   State: $($status.State)"
        Write-Info "   Last Run: $($status.LastRunTime)"
        Write-Info "   Next Run: $($status.NextRunTime)"
        Write-Info "   Last Result: $($status.LastTaskResult)"
        
        # Get trigger information
        try {
            $task = Get-ScheduledTask -TaskName $Name
            Write-Info "   Triggers:"
            foreach ($trigger in $task.Triggers) {
                if ($trigger.CimClass.CimClassName -eq "MSFT_TaskTimeTrigger") {
                    Write-Info "     - Daily at: $($trigger.StartBoundary)"
                }
                elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskRepetitionPattern") {
                    Write-Info "     - Repeats every: $($trigger.Interval)"
                }
            }
        }
        catch {
            Write-Info "   Could not retrieve trigger details"
        }
    }
    else {
        Write-Warning "Task '$Name' does not exist"
        if ($status.Error) {
            Write-Error "   Error: $($status.Error)"
        }
    }
}

function Remove-TaskSchedule {
    param([string]$Name)
    
    Write-Step "*** REMOVING SCHEDULED TASK ***"
    Write-Step "==============================="
    
    $status = Get-TaskStatus -Name $Name
    
    if ($status.Exists) {
        try {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false
            Write-Success "Successfully removed scheduled task '$Name'"
        }
        catch {
            Write-Error "Failed to remove scheduled task: $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-Warning "Task '$Name' does not exist"
    }
    
    return $true
}

function New-TaskSchedule {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string]$User,
        [string]$LogPath,
        [int]$Minutes,
        [int]$Hours,
        [string]$Daily
    )
    
    Write-Step "*** CREATING SCHEDULED TASK ***"
    Write-Step "==============================="
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Write-Info "Created log directory: $logDir"
    }
    
    # Remove existing task if it exists
    $status = Get-TaskStatus -Name $Name
    if ($status.Exists) {
        Write-Warning "Task '$Name' already exists. Removing it first..."
        Remove-TaskSchedule -Name $Name | Out-Null
    }
    
    try {
        # Create the action (what to run)
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
        
        # Create the trigger (when to run)
        $trigger = $null
        
        if ($Daily) {
            Write-Info "Setting up daily schedule at $Daily"
            $trigger = New-ScheduledTaskTrigger -Daily -At $Daily
        }
        elseif ($Hours -gt 0) {
            Write-Info "Setting up hourly schedule every $Hours hours"
            # For hourly, we'll use a daily trigger with repetition
            $trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
            $trigger.Repetition = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours $Hours) -RepetitionDuration ([TimeSpan]::MaxValue)
        }
        else {
            Write-Info "Setting up minute-based schedule every $Minutes minutes"
            # For minutes, we'll use a daily trigger with repetition
            $trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
            $trigger.Repetition = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes $Minutes) -RepetitionDuration ([TimeSpan]::MaxValue)
        }
        
        # Create the principal (who runs it)
        $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive
        
        # Create the settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Register the task
        Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Automated SharePoint to Azure Blob Storage synchronization"
        
        Write-Success "Successfully created scheduled task '$Name'"
        Write-Info "   Script: $ScriptPath"
        Write-Info "   User: $User"
        Write-Info "   Schedule: $(if ($Daily) { "Daily at $Daily" } elseif ($Hours -gt 0) { "Every $Hours hours" } else { "Every $Minutes minutes" })"
        
        return $true
    }
    catch {
        Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
try {
    Write-Step "*** SHAREPOINT BLOB SYNC - TASK SCHEDULER SETUP ***"
    Write-Step "===================================================="
    Write-Host ""
    
    # Check if running as administrator
    if (!(Test-Administrator)) {
        Write-Warning "This script requires administrator privileges to manage scheduled tasks."
        Write-Info "Please run PowerShell as Administrator and try again."
        exit 1
    }
    
    # Validate script paths
    $syncScript = Join-Path $PSScriptRoot "Run-Sync.ps1"
    if (!(Test-Path $syncScript)) {
        Write-Error "Sync runner script not found: $syncScript"
        Write-Info "Please ensure Run-Sync.ps1 exists in the same directory"
        exit 1
    }
    
    # Handle different operations
    if ($Status) {
        Show-TaskStatus -Name $TaskName
        exit 0
    }
    
    if ($Remove) {
        $success = Remove-TaskSchedule -Name $TaskName
        exit $(if ($success) { 0 } else { 1 })
    }
    
    # Validate scheduling parameters
    $scheduleCount = 0
    if ($IntervalMinutes -gt 0) { $scheduleCount++ }
    if ($IntervalHours -gt 0) { $scheduleCount++ }
    if ($DailyAt) { $scheduleCount++ }
    
    if ($scheduleCount -gt 1) {
        Write-Error "Please specify only one scheduling option: -IntervalMinutes, -IntervalHours, or -DailyAt"
        exit 1
    }
    
    if ($DailyAt -and $DailyAt -notmatch '^\d{1,2}:\d{2}$') {
        Write-Error "Invalid time format for -DailyAt. Use HH:MM format (e.g., '09:00', '14:30')"
        exit 1
    }
    
    # Create the scheduled task
    $success = New-TaskSchedule -Name $TaskName -ScriptPath $syncScript -User $RunAsUser -LogPath $LogPath -Minutes $IntervalMinutes -Hours $IntervalHours -Daily $DailyAt
    
    if ($success) {
        Write-Host ""
        Show-TaskStatus -Name $TaskName
        
        if ($StartNow) {
            Write-Host ""
            Write-Step "Starting task immediately..."
            try {
                Start-ScheduledTask -TaskName $TaskName
                Write-Success "Task started successfully"
            }
            catch {
                Write-Warning "Failed to start task immediately: $($_.Exception.Message)"
            }
        }
        
        Write-Host ""
        Write-Step "*** NEXT STEPS ***"
        Write-Step "=================="
        Write-Info "1. Monitor task execution in Task Scheduler (taskschd.msc)"
        Write-Info "2. Check logs in: $LogPath"
        Write-Info "3. Use '.\Setup-Scheduler.ps1 -Status' to check task status"
        Write-Info "4. Use '.\Setup-Scheduler.ps1 -Remove' to remove the task"
        
        Write-Host ""
        Write-Success "[COMPLETE] Scheduled task setup completed successfully!"
        exit 0
    }
    else {
        Write-Error "[FAILED] Scheduled task setup failed"
        exit 1
    }
}
catch {
    Write-Error "[ERROR] Script execution failed: $($_.Exception.Message)"
    Write-Info "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
