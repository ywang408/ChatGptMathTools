#Requires -Version 5.1

param(
    [string]$BackupPath,

    [switch]$NoBackup,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ChatGptMathTools.psd1') -Force

$result = Convert-ChatGptMathClipboard -BackupPath $BackupPath -NoBackup:$NoBackup.IsPresent -PassThru:$PassThru.IsPresent

if ($PassThru) {
    $result
}
else {
    Write-Host 'Clipboard text converted and copied back.'
    if (-not $NoBackup -and $null -ne $result.BackupPath) {
        Write-Host "Backup saved to: $($result.BackupPath)"
    }
}
