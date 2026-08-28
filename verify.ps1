#Requires -Version 5.1
<#
.SYNOPSIS
  Bring the whole Copilot demo up on Windows, from nothing.

.DESCRIPTION
  Installs its own prerequisites (Node, Git), fetches the two SEB repos,
  installs every dependency, runs each repo's tests, starts all three servers
  and opens the browser. Ctrl-C stops everything.

  Nothing here needs admin rights: Node and Git are installed per-user, as
  portable unpacked builds under %LOCALAPPDATA%\Programs\seb-workshop.

.EXAMPLE
  .\verify.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\verify.ps1
#>
[CmdletBinding()]
param(
    # Clone from this GitHub owner instead of seb-oss.
    [string] $ForkOwner = $env:FORK_OWNER,

    # Skip the test phase and go straight to the servers.
    [switch] $SkipTests,

    # Install and test, but do not start the servers.
    [switch] $SkipServers,

    # Re-run the dependency installs even if node_modules is already there.
    [switch] $Reinstall,

    # Used when the script re-invokes itself to run one step in parallel.
    [string] $InternalStep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Invoke-WebRequest is roughly an order of magnitude faster without the meter.
$ProgressPreference = 'SilentlyContinue'

$NodeVersion = '24.20.0'
$GitVersion  = '2.47.1'
$Root        = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ToolsDir    = Join-Path $env:LOCALAPPDATA 'Programs\seb-workshop'
$LogDir      = Join-Path $env:TEMP 'seb-verify'

$script:Failed  = $false
$script:Steps   = @()
$script:Servers = @()

# --------------------------------------------------------------- primitives

function Write-Head { param([string] $Text) Write-Host ''; Write-Host $Text }

function Write-Step {
    param([string] $Name, [string] $Status, [string] $Detail)
    $colour = if ($Status -eq 'ok') { 'Green' } else { 'Red' }
    Write-Host ('  {0,-32}' -f $Name) -NoNewline
    Write-Host $Status -ForegroundColor $colour -NoNewline
    if ($Detail) { Write-Host "  -> $Detail" } else { Write-Host '' }
}

# Native commands do not raise on a non-zero exit, so anything that must succeed
# goes through here.
function Invoke-Native {
    param([Parameter(Mandatory)][string] $File, [string[]] $Arguments = @())
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Expand-ZipFile {
    param([string] $Path, [string] $Destination)
    # Expand-Archive is very slow for archives with many entries.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $Destination)
}

function Get-RemoteFile {
    param([string] $Uri, [string] $OutFile)
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 900
}

# ------------------------------------------------------------ prerequisites

# Anything speaking TLS through a corporate middlebox needs the intercepting CA.
# Windows already trusts it, so export its roots into a PEM Node understands.
function New-CaBundle {
    $pem = Join-Path $ToolsDir 'windows-ca-bundle.pem'
    if (Test-Path $pem) { return $pem }

    $sb = New-Object System.Text.StringBuilder
    foreach ($store in 'Cert:\LocalMachine\Root', 'Cert:\LocalMachine\CA',
                       'Cert:\CurrentUser\Root',  'Cert:\CurrentUser\CA') {
        Get-ChildItem $store -ErrorAction SilentlyContinue | ForEach-Object {
            $b64 = [Convert]::ToBase64String($_.RawData, 'InsertLineBreaks')
            [void]$sb.AppendLine("# $($_.Subject)")
            [void]$sb.AppendLine('-----BEGIN CERTIFICATE-----')
            [void]$sb.AppendLine($b64)
            [void]$sb.AppendLine('-----END CERTIFICATE-----')
        }
    }
    Set-Content -Path $pem -Value $sb.ToString() -Encoding Ascii
    return $pem
}

function Get-SystemProxy {
    if ($env:HTTPS_PROXY) { return $env:HTTPS_PROXY }
    if ($env:HTTP_PROXY)  { return $env:HTTP_PROXY }

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $ie  = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($ie -and $ie.PSObject.Properties['ProxyEnable'] -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) {
        $server = ($ie.ProxyServer -split ';' | Select-Object -First 1) -replace '^.*=', ''
        if ($server) { return "http://$server" }
    }

    $winhttp = (netsh winhttp show proxy 2>$null | Out-String)
    if ($winhttp -match 'Proxy Server\(s\)\s*:\s*(\S+)') {
        $server = ($Matches[1] -split ';' | Select-Object -First 1) -replace '^.*=', ''
        if ($server -and $server -ne '(none)') { return "http://$server" }
    }
    return $null
}

# npm and yarn 1 read HTTP_PROXY themselves; corepack (Node's fetch) and yarn 4
# do not, and fail with ENOTFOUND, so hand them the proxy under their own names.
function Initialize-Network {
    $proxy = Get-SystemProxy
    $ca    = New-CaBundle

    $env:NODE_EXTRA_CA_CERTS = $ca
    if ($proxy) {
        if (-not $env:HTTP_PROXY)  { $env:HTTP_PROXY  = $proxy }
        if (-not $env:HTTPS_PROXY) { $env:HTTPS_PROXY = $proxy }
        $env:NODE_USE_ENV_PROXY    = '1'
        $env:YARN_HTTP_PROXY       = $env:HTTP_PROXY
        $env:YARN_HTTPS_PROXY      = $env:HTTPS_PROXY
        $env:YARN_HTTPS_CA_FILE_PATH = $ca
        Write-Step 'proxy' 'ok' $proxy
    }
    if (-not $env:NO_PROXY) { $env:NO_PROXY = 'localhost,127.0.0.1' }
    elseif ($env:NO_PROXY -notmatch 'localhost') { $env:NO_PROXY = "$env:NO_PROXY,localhost,127.0.0.1" }
}

function Install-Node {
    # green's jest-diff refuses to install on Node 23, so only 22 and 24 count.
    $current = Get-Command node -ErrorAction SilentlyContinue
    if ($current) {
        $major = ((& node -v) -replace '^v', '' -split '\.')[0] -as [int]
        if ($major -in 22, 24) {
            Write-Step 'node' 'ok' (& node -v)
            return (Split-Path -Parent $current.Source)
        }
    }

    $dir = Join-Path $ToolsDir "node-v$NodeVersion-win-x64"
    if (-not (Test-Path (Join-Path $dir 'node.exe'))) {
        $zip = Join-Path $env:TEMP "node-v$NodeVersion-win-x64.zip"
        Write-Step 'node' 'installing' "v$NodeVersion (portable, no admin)"
        Get-RemoteFile "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip" $zip

        # Best effort integrity check; skipped if the checksum file is blocked.
        try {
            $sums = (Invoke-WebRequest "https://nodejs.org/dist/v$NodeVersion/SHASUMS256.txt" -UseBasicParsing -TimeoutSec 120).Content
            $want = ($sums -split "`n" | Where-Object { $_ -match "node-v$NodeVersion-win-x64\.zip" }) -split '\s+' | Select-Object -First 1
            $got  = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
            if ($want -and $got -ne $want.ToLower()) { throw "checksum mismatch for $zip" }
        } catch [System.Net.WebException] {
            Write-Verbose 'checksum file unreachable, skipping verification'
        }

        Expand-ZipFile $zip $ToolsDir
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }
    Write-Step 'node' 'ok' "v$NodeVersion (portable)"
    return $dir
}

function Install-Git {
    $current = Get-Command git -ErrorAction SilentlyContinue
    if ($current) {
        Write-Step 'git' 'ok' ((& git --version) -replace 'git version ', '')
        return (Split-Path -Parent $current.Source)
    }

    $dir = Join-Path $ToolsDir "MinGit-$GitVersion"
    if (-not (Test-Path (Join-Path $dir 'cmd\git.exe'))) {
        $zip = Join-Path $env:TEMP "MinGit-$GitVersion.zip"
        Write-Step 'git' 'installing' "MinGit $GitVersion (portable, no admin)"
        Get-RemoteFile ("https://github.com/git-for-windows/git/releases/download/" +
                        "v$GitVersion.windows.1/MinGit-$GitVersion-64-bit.zip") $zip
        Expand-ZipFile $zip $dir
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }
    Write-Step 'git' 'ok' "MinGit $GitVersion (portable)"
    return (Join-Path $dir 'cmd')
}

function Initialize-Tools {
    New-Item -ItemType Directory -Force -Path $ToolsDir, $LogDir | Out-Null

    $nodeDir = Install-Node
    $gitDir  = Install-Git
    $env:PATH = "$nodeDir;$gitDir;$env:PATH"

    # nx shells out to `yarn` for green's dependent tasks, so the shim has to be
    # a real file on PATH -- `corepack yarn` being resolvable is not enough.
    if (-not (Get-Command yarn -ErrorAction SilentlyContinue)) {
        & corepack enable --install-directory $nodeDir 2>&1 | Out-Null
    }

    # Storybook's telemetry cache file throws EBUSY on Windows from inside an
    # async handler, killing the dev server seconds after it starts serving.
    $env:STORYBOOK_DISABLE_TELEMETRY = '1'
    $env:DO_NOT_TRACK = '1'
}

# ---------------------------------------------------------------- run steps

# Steps run concurrently -- the repos are independent -- and each writes its own
# log. Wait-Steps blocks and reports in the order queued.
function Start-Step {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Slug,
        [Parameter(Mandatory)][string] $WorkDir,
        [Parameter(Mandatory)][string[]] $Command
    )
    $out = Join-Path $LogDir "$Slug.log"
    $err = Join-Path $LogDir "$Slug.err.log"
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList (@('/c') + $Command) `
        -WorkingDirectory $WorkDir -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    # Touching Handle caches it. Without this, a -PassThru process object that is
    # stored and read back later reports a null ExitCode instead of the real one.
    $null = $proc.Handle
    $script:Steps += [pscustomobject]@{ Name = $Name; Slug = $Slug; Proc = $proc; Out = $out; Err = $err }
}

# Runs one of this script's own multi-command steps in a child PowerShell so it
# can be queued next to the plain command steps.
function Start-InternalStep {
    param([string] $Name, [string] $Slug, [string] $Step)
    Start-Step -Name $Name -Slug $Slug -WorkDir $Root -Command @(
        'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"", '-InternalStep', $Step,
        '-ForkOwner', "`"$ForkOwner`""
    )
}

function Wait-Steps {
    if (-not $script:Steps) { return }
    foreach ($step in $script:Steps) {
        $step.Proc.WaitForExit()
        if (Test-Path $step.Err) {
            $stderr = Get-Content $step.Err -ErrorAction SilentlyContinue
            if ($stderr) {
                Add-Content $step.Out '', '----- stderr -----'
                $stderr | Add-Content $step.Out
            }
            Remove-Item $step.Err -Force -ErrorAction SilentlyContinue
        }
        if ($step.Proc.ExitCode -eq 0) {
            Write-Step $step.Name 'ok'
        } else {
            Write-Step $step.Name 'FAIL' $step.Out
            $script:Failed = $true
        }
    }
    $script:Steps = @()
}

# ------------------------------------------------------------------- clone

# green and Spark-packages are not vendored here. Clone them at the pinned
# commit, apply the trim from patches/, and commit it as "workshop-base" so a
# feature branch diffs clean against it.
function Invoke-CloneFork {
    param([string] $Repo)
    $sha   = (Get-Content (Join-Path $Root "patches\$Repo.sha") -Raw).Trim()
    $owner = if ($ForkOwner) { $ForkOwner } else { 'seb-oss' }

    Invoke-Native git @('clone', '--filter=blob:none', '--no-checkout',
                        "https://github.com/$owner/$Repo.git", (Join-Path $Root $Repo))
    Invoke-Native git @('-C', (Join-Path $Root $Repo), 'checkout', '-q', $sha)
    Invoke-Native git @('-C', (Join-Path $Root $Repo), 'apply', (Join-Path $Root "patches\$Repo.patch"))
    Invoke-Baseline $Repo

    # Pushing needs a fork. Do it here if gh is authenticated, otherwise skip --
    # you only need it at PR time, and the README says how.
    if (-not $ForkOwner -and (Get-Command gh -ErrorAction SilentlyContinue)) {
        & gh auth status *> $null
        if ($LASTEXITCODE -eq 0) {
            Push-Location (Join-Path $Root $Repo)
            & gh repo fork --remote --remote-name origin *> $null
            Pop-Location
        }
    }
}

# Put the trim on a real branch and commit it, so the worktree reads clean and
# your ticket shows up as your changes, not the trim's.
function Invoke-Baseline {
    param([string] $Repo)
    $path = Join-Path $Root $Repo
    Invoke-Native git @('-C', $path, 'checkout', '-q', '-B', 'workshop-base')

    & git -C $path diff --quiet
    if ($LASTEXITCODE -ne 0) {
        Invoke-Native git @('-C', $path,
            '-c', 'user.name=workshop', '-c', 'user.email=workshop@localhost',
            'commit', '-aqm', 'Workshop trim - base for the ticket, not for upstream')
    }
    # yarn.lock is tracked, so info/exclude cannot hide it -- skip-worktree can.
    if (Test-Path (Join-Path $path 'yarn.lock')) {
        & git -C $path update-index --skip-worktree yarn.lock 2>&1 | Out-Null
    }
}

# nx's postinstall rebuilds the project graph and can spin at 100% CPU for the
# better part of an hour on Windows. It is redundant -- nx rebuilds on demand --
# and the hook no-ops without an nx.json, so park the file for the install.
function Install-GreenDeps {
    $nxJson = Join-Path $Root 'green\nx.json'
    $parked = "$nxJson.parked"
    $moved  = $false
    if (Test-Path $nxJson) { Move-Item $nxJson $parked -Force; $moved = $true }
    try {
        Push-Location (Join-Path $Root 'green')
        & corepack yarn@1.22.22 install --ignore-engines --network-timeout 600000 --network-concurrency 16
        $code = $LASTEXITCODE
        Pop-Location
        if ($code -ne 0) { throw "green install failed with exit code $code" }
    } finally {
        if ($moved) { Move-Item $parked $nxJson -Force }
    }
}

# ----------------------------------------------------------------- servers

function Start-Server {
    param([string] $Name, [string] $Slug, [string] $WorkDir, [string[]] $Command)
    $out = Join-Path $LogDir "$Slug.log"
    $err = Join-Path $LogDir "$Slug.err.log"
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList (@('/c') + $Command) `
        -WorkingDirectory $WorkDir -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $proc.Handle
    $script:Servers += [pscustomobject]@{ Name = $Name; Proc = $proc; Log = $out }
    Write-Host "  started $Name  -> $out"
}

# localhost must not go through the corporate proxy, so bypass WebRequest's
# default proxy handling entirely.
function Test-Url {
    param([string] $Url)
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Proxy = $null
        $req.Timeout = 5000
        $req.Method = 'GET'
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch {
        return $false
    }
}

function Wait-Url {
    param([string] $Name, [string] $Url, [int] $Seconds, [string] $Log)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Url $Url) { Write-Host ('  {0,-16}{1}' -f $Name, $Url.TrimEnd('/')); return }
        Start-Sleep -Seconds 2
    }
    Write-Host ('  {0,-16}TIMEOUT -> {1}' -f $Name, $Log) -ForegroundColor Red
    $script:Failed = $true
}

function Stop-Tree {
    param([int] $ProcessId)
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Tree -ProcessId $_.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Stop-Servers {
    foreach ($server in $script:Servers) {
        if ($server.Proc -and -not $server.Proc.HasExited) { Stop-Tree -ProcessId $server.Proc.Id }
    }
    $script:Servers = @()
}

# ------------------------------------------------------------ internal step

# Re-invoked by Start-InternalStep in a child process; does one job and exits.
if ($InternalStep) {
    switch -Regex ($InternalStep) {
        '^clone:(.+)$'    { Invoke-CloneFork  $Matches[1]; exit 0 }
        '^baseline:(.+)$' { Invoke-Baseline   $Matches[1]; exit 0 }
        '^install:green$' { Install-GreenDeps;             exit 0 }
        default           { throw "unknown internal step '$InternalStep'" }
    }
}

# ------------------------------------------------------------------- main

Write-Head 'Prerequisites'
Initialize-Tools
Initialize-Network

Write-Head 'Repos'
foreach ($repo in 'green', 'Spark-packages') {
    $path = Join-Path $Root $repo
    if (-not (Test-Path $path)) {
        Start-InternalStep "clone + trim $repo" "clone-$repo" "clone:$repo"
    } else {
        & git -C $path rev-parse --verify -q workshop-base 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Start-InternalStep "baseline $repo" "baseline-$repo" "baseline:$repo"
        }
    }
}
Wait-Steps

Write-Head 'Dependencies (installing all three in parallel; green is the slow one)'
if ($Reinstall -or -not (Test-Path (Join-Path $Root 'seb-demo-payments\node_modules'))) {
    Start-Step 'seb-demo-payments (npm)' 'install-glue' $Root `
        @('npm', '--prefix', 'seb-demo-payments', 'install', '--no-audit', '--no-fund')
}
if ($Reinstall -or (-not (Test-Path (Join-Path $Root 'Spark-packages\.yarn\cache')) -and
                    -not (Test-Path (Join-Path $Root 'Spark-packages\node_modules')))) {
    Start-Step 'Spark-packages (yarn 4)' 'install-spark' (Join-Path $Root 'Spark-packages') `
        @('corepack', 'yarn', 'install')
}
if ($Reinstall -or -not (Test-Path (Join-Path $Root 'green\node_modules'))) {
    Start-InternalStep 'green (yarn 1)' 'install-green' 'install:green'
}
Wait-Steps

if (-not $SkipTests) {
    Write-Head 'Tests'
    Start-Step 'Spark-packages  openapi-*' 'test-spark' (Join-Path $Root 'Spark-packages') `
        @('corepack', 'yarn', 'turbo', 'run', 'test', '--filter=./packages/openapi-*')
    Start-Step 'green           core (node)' 'test-green' (Join-Path $Root 'green') `
        @('npx', 'nx', 'run', 'core:test:node')
    Start-Step 'seb-demo-payments api' 'test-glue' $Root `
        @('npm', '--prefix', 'seb-demo-payments', 'test')
    Wait-Steps
}

if ($SkipServers) {
    Write-Head $(if ($script:Failed) { "Something failed above - see the logs in $LogDir" }
                 else { 'All three repos are working.' })
    exit $(if ($script:Failed) { 1 } else { 0 })
}

try {
    Write-Head 'Servers'
    # Ctrl-C leaves this cache half-written and the next run dies on it with
    # EBUSY. Dropping it only costs the rebuild we are about to wait for anyway.
    Remove-Item -Recurse -Force (Join-Path $Root 'green\node_modules\.cache\storybook\default\dev-server') `
        -ErrorAction SilentlyContinue

    Start-Server 'payments api    :3001' 'api'  (Join-Path $Root 'seb-demo-payments') @('npm', 'run', 'dev', '-w', 'api')
    Start-Server 'payments web    :5173' 'web'  (Join-Path $Root 'seb-demo-payments') @('npm', 'run', 'dev', '-w', 'web')
    Start-Server 'green storybook :4400' 'book' (Join-Path $Root 'green') @('npx', 'nx', 'run', 'core:storybook')

    Write-Head 'Waiting for servers (storybook builds green first, give it a few minutes)'
    Wait-Url 'payments api'    'http://localhost:3001/accounts' 60  (Join-Path $LogDir 'api.log')
    Wait-Url 'payments web'    'http://localhost:5173/'         60  (Join-Path $LogDir 'web.log')
    Wait-Url 'green storybook' 'http://localhost:4400/'         600 (Join-Path $LogDir 'book.log')

    Start-Process 'http://localhost:5173'
    Start-Process 'http://localhost:4400'

    Write-Host ''
    if ($script:Failed) {
        Write-Host "Something failed above - see the logs in $LogDir. Servers still up; Ctrl-C to stop." -ForegroundColor Yellow
    } else {
        Write-Host 'All three repos are working. Ctrl-C to stop.' -ForegroundColor Green
    }

    while ($true) {
        Start-Sleep -Seconds 1
        if (-not ($script:Servers | Where-Object { -not $_.Proc.HasExited })) { break }
    }
} finally {
    Write-Host ''
    Write-Host 'Stopping servers...'
    Stop-Servers
}

exit $(if ($script:Failed) { 1 } else { 0 })
