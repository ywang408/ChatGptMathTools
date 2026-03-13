#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [Alias('Path', 'FullName')]
    [string[]]$InputPath,

    [switch]$InPlace,

    [string]$Suffix = '.converted'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ChatGptMathTools.psd1') -Force

Convert-ChatGptMathFile -InputPath $InputPath -InPlace:$InPlace.IsPresent -Suffix $Suffix |
    ForEach-Object {
        Write-Host "Converted: $($_.InputPath) -> $($_.OutputPath)"
    }
