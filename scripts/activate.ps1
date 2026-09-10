# activate.ps1 — dot-source this to get a "(zamhealthwatch)" shell prompt for this project,
# the same visual cue Python's venv gives you.
#
# Usage (from the project root, in PowerShell):
#     . .\scripts\activate.ps1
# Exit:
#     deactivate
#
# NOTE: this is purely cosmetic/organizational, not dependency isolation like Python's venv.
# Mix already isolates each project's dependencies in its own deps/ and _build/ folders,
# so there's nothing here to "activate" in that sense — this just makes it obvious at a
# glance which project's shell you're sitting in when you have more than one open.

if ($env:ZAMHEALTHWATCH_ACTIVE -eq "1") {
    Write-Host "Already in the (zamhealthwatch) environment." -ForegroundColor Yellow
    return
}

$global:_zhw_old_prompt = (Get-Item Function:\prompt).ScriptBlock
$global:_zhw_project_root = Split-Path -Parent $PSScriptRoot

$env:ZAMHEALTHWATCH_ACTIVE = "1"
$env:MIX_ENV = "dev"

Set-Item Function:\prompt -Value {
    "(zamhealthwatch) " + (& $global:_zhw_old_prompt)
}

function global:deactivate {
    if ($env:ZAMHEALTHWATCH_ACTIVE -ne "1") {
        Write-Host "Not currently active." -ForegroundColor Yellow
        return
    }
    Set-Item Function:\prompt -Value $global:_zhw_old_prompt
    Remove-Item Env:ZAMHEALTHWATCH_ACTIVE -ErrorAction SilentlyContinue
    Remove-Item Env:MIX_ENV -ErrorAction SilentlyContinue
    Remove-Item Variable:global:_zhw_old_prompt -ErrorAction SilentlyContinue
    Remove-Item Variable:global:_zhw_project_root -ErrorAction SilentlyContinue
    Write-Host "Left the (zamhealthwatch) environment." -ForegroundColor Green
    Remove-Item Function:global:deactivate -ErrorAction SilentlyContinue
}

if ((Get-Location).Path -ne $global:_zhw_project_root) {
    Set-Location $global:_zhw_project_root
}

Write-Host "(zamhealthwatch) environment active. Type 'deactivate' to leave it." -ForegroundColor Green
