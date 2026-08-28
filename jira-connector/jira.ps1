#!/usr/bin/env pwsh
# Jira Cloud CLI for Windows PowerShell / PowerShell 7 - the twin of the Bash `jira`.
# Uses only PowerShell built-ins: no curl, Python, Node, or package manager.
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Args
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    param([int]$Code = 0)
    [Console]::Error.WriteLine('usage: ./jira.ps1 <get|search|comment|update|transitions|transition|selfcheck> ...')
    exit $Code
}

function Fail {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
    exit 1
}

function ConvertTo-JiraString {
    param([string]$Text)
    $controls = $Text -replace "[`n`r`t]", ''
    if ($controls -match '[\p{Cc}]') {
        Fail 'comments cannot contain control characters other than tab or newline'
    }
    $Text = $Text -replace '\\', '\\'
    $Text = $Text -replace '"', '\"'
    $Text = $Text -replace "`n", '\n'
    $Text = $Text -replace "`r", '\r'
    $Text = $Text -replace "`t", '\t'
    return $Text
}

# Reads JIRA_* keys from a .env file without executing it. Existing environment
# variables win, so an explicit $env: assignment always overrides the file.
function Import-EnvFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) { continue }
        if ($entry.StartsWith('export ')) { $entry = $entry.Substring(7) }
        $split = $entry.IndexOf('=')
        if ($split -lt 1) { continue }
        $key = $entry.Substring(0, $split).Trim()
        if ($key -notin @('JIRA_BASE_URL', 'JIRA_EMAIL', 'JIRA_API_TOKEN', 'JIRA_PERSONAL_ACCESS_TOKEN')) { continue }
        $value = $entry.Substring($split + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if (-not [Environment]::GetEnvironmentVariable($key)) {
            Set-Item -Path "Env:$key" -Value $value
        }
    }
}

function Invoke-JiraApi {
    param(
        [string]$Path,
        [string]$Method = 'Get',
        [string]$Body
    )
    $uri = "$script:BaseUrl$Path"
    $headers = @{ Authorization = $script:AuthHeader; Accept = 'application/json' }
    $params = @{
        Uri             = $uri
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
    }
    if ($PSBoundParameters.ContainsKey('Body') -and $Body) {
        $params.ContentType = 'application/json; charset=utf-8'
        $params.Body = [Text.Encoding]::UTF8.GetBytes($Body)
    }
    try {
        $response = Invoke-WebRequest @params
    }
    catch {
        $detail = $_.Exception.Message
        $webResponse = $_.Exception.Response
        if ($webResponse -and $webResponse.GetType().GetProperty('StatusCode')) {
            $detail = "HTTP $([int]$webResponse.StatusCode) - $detail"
        }
        Fail "jira request failed: $detail"
    }
    if ($response.Content) { Write-Output $response.Content }
}

if (-not $Args) { $Args = @() }

if ($Command -eq 'selfcheck') {
    $expected = 'a\"b\\c\n'
    if ((ConvertTo-JiraString "a`"b\c`n") -ne $expected) { exit 1 }
    Write-Output 'selfcheck ok'
    exit 0
}

if (-not $Command -or $Command -in @('-h', '--help')) { Show-Usage 0 }

# Windows PowerShell 5.1 still negotiates TLS 1.0 by default; Jira Cloud requires 1.2+.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptDir = Split-Path -Parent $PSCommandPath
foreach ($candidate in @(
        (Join-Path $scriptDir '.env'),
        (Join-Path (Split-Path -Parent $scriptDir) '.env'),
        (Join-Path (Get-Location).Path '.env'))) {
    Import-EnvFile $candidate
}

foreach ($required in @('JIRA_BASE_URL')) {
    if (-not [Environment]::GetEnvironmentVariable($required)) { Fail "Set $required." }
}

# Auth mode is picked automatically: a personal access token means Jira
# Server/Data Center (Bearer + REST v2); otherwise Jira Cloud (Basic + REST v3).
$pat = [Environment]::GetEnvironmentVariable('JIRA_PERSONAL_ACCESS_TOKEN')
if ($pat) {
    $script:AuthHeader = "Bearer $pat"
    $script:Api = '2'
}
else {
    foreach ($required in @('JIRA_EMAIL', 'JIRA_API_TOKEN')) {
        if (-not [Environment]::GetEnvironmentVariable($required)) {
            Fail "Set $required, or set JIRA_PERSONAL_ACCESS_TOKEN for Jira Server/Data Center."
        }
    }
    $pair = "$($env:JIRA_EMAIL):$($env:JIRA_API_TOKEN)"
    $script:AuthHeader = "Basic $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair)))"
    $script:Api = '3'
}
$script:BaseUrl = $env:JIRA_BASE_URL.TrimEnd('/')

switch ($Command) {
    'get' {
        if ($Args.Count -ne 1) { Show-Usage 1 }
        $key = [Uri]::EscapeDataString($Args[0])
        Invoke-JiraApi "/rest/api/$script:Api/issue/$key`?fields=summary,status,assignee,description"
    }
    'search' {
        if ($Args.Count -ne 1) { Show-Usage 1 }
        $query = [Uri]::EscapeDataString($Args[0])
        if ($script:Api -eq '2') {
            Invoke-JiraApi "/rest/api/2/search`?jql=$query&maxResults=20&fields=summary,status"
        }
        else {
            Invoke-JiraApi "/rest/api/3/search/jql`?jql=$query&maxResults=20&fields=summary&fields=status"
        }
    }
    'comment' {
        if ($Args.Count -ne 2) { Show-Usage 1 }
        $key = [Uri]::EscapeDataString($Args[0])
        $text = ConvertTo-JiraString $Args[1]
        if ($script:Api -eq '2') {
            $body = '{"body":"' + $text + '"}'
        }
        else {
            $body = '{"body":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"' + $text + '"}]}]}}'
        }
        Invoke-JiraApi "/rest/api/$script:Api/issue/$key/comment" -Method Post -Body $body
    }
    'update' {
        if ($Args.Count -ne 2) { Show-Usage 1 }
        $key = [Uri]::EscapeDataString($Args[0])
        Invoke-JiraApi "/rest/api/$script:Api/issue/$key" -Method Put -Body "{`"fields`":$($Args[1])}"
        Write-Output '{"ok":true}'
    }
    'transitions' {
        if ($Args.Count -ne 1) { Show-Usage 1 }
        $key = [Uri]::EscapeDataString($Args[0])
        Invoke-JiraApi "/rest/api/$script:Api/issue/$key/transitions"
    }
    'transition' {
        if ($Args.Count -ne 2) { Show-Usage 1 }
        if ($Args[1] -notmatch '^[0-9]+$') { Fail 'transition id must be numeric' }
        $key = [Uri]::EscapeDataString($Args[0])
        Invoke-JiraApi "/rest/api/$script:Api/issue/$key/transitions" -Method Post -Body "{`"transition`":{`"id`":`"$($Args[1])`"}}"
        Write-Output '{"ok":true}'
    }
    default {
        [Console]::Error.WriteLine("unknown command: $Command")
        Show-Usage 1
    }
}
