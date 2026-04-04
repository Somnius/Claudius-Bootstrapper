#Requires -Version 5.1
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArguments = @()
)
<#
.SYNOPSIS
  Claudius for Windows - Claude Code multi-backend bootstrapper (parity with claudius.sh).
  Config: %USERPROFILE%\.claude\settings.json and claudius-prefs.json
  Run via: claudius.bat, or: powershell -NoProfile -File .\claudius.ps1 [--init] [--dry-run] ...
  All CLI flags work the same when invoking this script directly.
#>
$ErrorActionPreference = 'Stop'
$Script:Version = '0.9.15'
$Script:ClaudeHome = Join-Path $env:USERPROFILE '.claude'
$Script:ClaudeSettings = Join-Path $Script:ClaudeHome 'settings.json'
$Script:ClaudiusPrefs = Join-Path $Script:ClaudeHome 'claudius-prefs.json'
$Script:SessionDirs = @('projects','debug','file-history','tasks','todos','plans','shell-snapshots','session-env','paste-cache')
$Script:CurlTimeout = if ($env:CURL_TIMEOUT) { [int]$env:CURL_TIMEOUT } else { 10 }
$Script:CurlTimeoutCloud = if ($env:CURL_TIMEOUT_CLOUD) { [int]$env:CURL_TIMEOUT_CLOUD } else { 25 }
$Script:LmStudioUrl = if ($env:LMSTUDIO_URL) { $env:LMSTUDIO_URL.TrimEnd('/') } else { 'http://localhost:1234' }
$Script:OllamaUrl = if ($env:OLLAMA_URL) { $env:OLLAMA_URL.TrimEnd('/') } else { 'http://localhost:11434' }
$Script:LlamaCppUrl = if ($env:LLAMA_CPP_URL) { $env:LLAMA_CPP_URL.TrimEnd('/') } else { 'http://127.0.0.1:8080' }
$Script:OpenRouterUrl = if ($env:OPENROUTER_URL) { $env:OPENROUTER_URL.TrimEnd('/') } else { 'https://openrouter.ai/api' }
$Script:NvidiaUrl = if ($env:NVIDIA_URL) { $env:NVIDIA_URL.TrimEnd('/') } else { 'https://integrate.api.nvidia.com' }
$Script:DashOpenAI = if ($env:DASHSCOPE_INTL_OPENAI_BASE) { $env:DASHSCOPE_INTL_OPENAI_BASE.TrimEnd('/') } else { 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1' }
$Script:DashAnthropic = if ($env:DASHSCOPE_INTL_ANTHROPIC_BASE) { $env:DASHSCOPE_INTL_ANTHROPIC_BASE.TrimEnd('/') } else { 'https://dashscope-intl.aliyuncs.com/apps/anthropic' }

$script:CurrentBackend = 'lmstudio'
$script:CurrentBaseUrl = ''
$script:CurrentApiKey = ''
$script:CurrentAuth = 'lmstudio'
$script:CurrentCustomListUrl = $null

# Same as claudius.sh "key|max" lines: use ASCII 124 only via [char], never a bare | in quotes (tokenizer issues on Windows PS).
function New-ClaudiusModelEntryString {
  param([object]$Key, [object]$Max)
  return (([string]$Key) + [string][char]0x7C + ([string]$Max))
}

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Invoke-CurlString {
  param(
    [string]$Url,
    [string]$Method = 'GET',
    [string]$Body = $null,
    [hashtable]$Headers = @{},
    [int]$TimeoutSec = 10,
    [int]$Retries = 0
  )
  # PS 5.1 + curl.exe: splatting a mixed Object[] can omit the URL ("no URL specified"). Use List[string].
  $u = if ($null -eq $Url) { '' } else { $Url.Trim() }
  if ([string]::IsNullOrWhiteSpace($u)) { return '' }
  $a = New-Object 'System.Collections.Generic.List[string]'
  foreach ($x in @('-sS', '--connect-timeout', '2', '--max-time', ([string]$TimeoutSec))) { [void]$a.Add($x) }
  if ($Retries -gt 0) {
    foreach ($x in @('--retry', ([string]$Retries), '--retry-delay', '1')) { [void]$a.Add($x) }
  }
  foreach ($k in @($Headers.Keys)) {
    [void]$a.Add('-H')
    [void]$a.Add(($k + ': ' + [string]$Headers[$k]))
  }
  if ($Method -ne 'GET') { [void]$a.Add('-X'); [void]$a.Add($Method) }
  if ($null -ne $Body -and $Body -ne '') {
    [void]$a.Add('-H')
    [void]$a.Add('Content-Type: application/json')
    [void]$a.Add('-d')
    [void]$a.Add($Body)
  }
  [void]$a.Add($u)
  & curl.exe @($a.ToArray()) 2>$null
}

function Invoke-CurlCode {
  param([string]$Url, [int]$TimeoutSec = 10)
  $out = & curl.exe -sS -o NUL -w '%{http_code}' --connect-timeout 2 --max-time $TimeoutSec $Url 2>$null
  if ($LASTEXITCODE -ne 0) { return '000' }
  return $out
}

function Print-Help {
  $v = $Script:Version
  @"
Usage: claudius.bat [OPTIONS]
       powershell -NoProfile -File path\to\claudius.ps1 [OPTIONS]

Claudius v$v - Claude Code multi-backend bootstrapper (Windows)

Config files (same semantics as macOS/Linux):
  %USERPROFILE%\.claude\settings.json       - ANTHROPIC_BASE_URL, defaultModel, env
  %USERPROFILE%\.claude\claudius-prefs.json - backend, baseUrl, apiKey, lastModel, etc.

Options:
  --help, -h          Show this help
  --init              Reset preferences (same questions as first run)
  --purge             Interactive purge of session data under .claude
  --dry-run, --test   Test flow without writing config or starting Claude
  --by-pass-start     Write config only; do not prompt to start Claude
  --last              Use last model/context from prefs; start Claude

Environment (optional):
  CLAUDIUS_BACKEND, CLAUDIUS_BASE_URL, CLAUDIUS_API_KEY, CLAUDIUS_AUTH_TOKEN
  LMSTUDIO_URL, OLLAMA_URL, LLAMA_CPP_URL, OPENROUTER_URL, NVIDIA_URL
  CURL_TIMEOUT, CURL_TIMEOUT_CLOUD

NVIDIA_URL: integrate.api.nvidia.com is OpenAI chat/completions per NVIDIA; Claude Code uses Anthropic /v1/messages. Use a proxy or another backend for chat.

https://github.com/Somnius/Claudius-Bootstrapper
"@
}

function Warn-NvidiaClaudeCodeProtocol {
  Write-Host ''
  Write-Host '  --- NVIDIA API + Claude Code ---' -ForegroundColor DarkYellow
  Write-Host "  NVIDIA's public NIM API is OpenAI-style (POST /v1/chat/completions; see docs.api.nvidia.com/nim/reference/llm-apis)." -ForegroundColor DarkYellow
  Write-Host '  Claude Code uses Anthropic Messages (POST /v1/messages). Listing models works; chat usually does not.' -ForegroundColor DarkYellow
  Write-Host '  Use a proxy (LiteLLM, claude-code-proxy) as ANTHROPIC_BASE_URL, or OpenRouter / other Anthropic-compatible hosts.' -ForegroundColor DarkYellow
  Write-Host ''
}

function Test-CurlAvailable {
  $null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)
}

function Get-ClaudeExePath {
  foreach ($name in @('claude.exe', 'claude')) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
  }
  $p = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
  if (Test-Path -LiteralPath $p) { return $p }
  $null
}

function Ensure-ClaudePath {
  $bin = Join-Path $env:USERPROFILE '.local\bin'
  if (Test-Path -LiteralPath $bin) {
    if ($env:PATH -notlike "*$bin*") { $env:PATH = "$bin;$env:PATH" }
  }
}

function Show-ClaudeInstallHelp {
  Write-Host ''
  Write-Host 'Claude Code CLI (claude) was not found on PATH.'
  Write-Host 'Install options (pick one):'
  Write-Host '  1) PowerShell (recommended):  irm https://claude.ai/install.ps1 | iex'
  Write-Host '  2) CMD one-liner:             curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd'
  Write-Host '  3) WinGet:                    winget install Anthropic.ClaudeCode'
  Write-Host ''
  Write-Host 'After install, the CLI is often at:'
  Write-Host "  $env:USERPROFILE\.local\bin\claude.exe"
  Write-Host 'If `claude` is not recognized, add that folder to your user PATH, then open a new terminal.'
  Write-Host 'Docs: https://code.claude.com/docs - Git for Windows is required for Claude Code on Windows.'
  Write-Host ''
}

function Try-InstallClaudeWindows {
  $r = Read-Host 'Run the official PowerShell installer now? [y/N]'
  if ($r -notmatch '^(y|yes)$') { return $false }
  try {
    Write-Host 'Running: irm https://claude.ai/install.ps1 | iex'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
    Ensure-ClaudePath
    if (Get-ClaudeExePath) { Write-Host 'Install script finished. If `claude` is still not found, add ~/.local/bin to PATH and open a new terminal.'; return $true }
  } catch {
    Write-Host "Install failed: $_"
  }
  return $false
}

function Ensure-ClaudeInstalled {
  Ensure-ClaudePath
  if (Get-ClaudeExePath) { return $true }
  Show-ClaudeInstallHelp
  $r = Read-Host 'Try to run the official installer now? [Y/n]'
  if ($r -eq '' -or $r -match '^(y|yes)$') {
    if (Try-InstallClaudeWindows) { return $true }
  }
  return $false
}

function Read-Prefs {
  if (-not (Test-Path -LiteralPath $Script:ClaudiusPrefs)) { return $null }
  try {
    Get-Content -LiteralPath $Script:ClaudiusPrefs -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch { $null }
}

function Write-PrefsObject {
  param([psobject]$Obj)
  if (-not (Test-Path -LiteralPath $Script:ClaudeHome)) {
    New-Item -ItemType Directory -Path $Script:ClaudeHome -Force | Out-Null
  }
  ($Obj | ConvertTo-Json -Depth 10) + "`n" | Write-Utf8NoBom -Path $Script:ClaudiusPrefs
}

function Get-Pref {
  param([string]$Key)
  $p = Read-Prefs
  if (-not $p) { return '' }
  $v = $p.$Key
  if ($null -eq $v) { return '' }
  if ($v -is [bool]) { return $v.ToString().ToLower() }
  return $v.ToString()
}

function Merge-Prefs {
  param([string]$Backend, [string]$BaseUrl, [string]$ApiKey)
  $p = Read-Prefs
  if (-not $p) {
    $p = [pscustomobject]@{ showTurnDuration = $true; keepSessionOnExit = $true; backend = $Backend; baseUrl = $BaseUrl; apiKey = $ApiKey; authToken = '' }
  } else {
    $p.backend = $Backend
    $p.baseUrl = $BaseUrl
    $p.apiKey = $ApiKey
  }
  Write-PrefsObject $p
}

function Save-LastModelPrefs {
  param([string]$ModelId, [int]$ContextLength)
  $p = Read-Prefs
  if (-not $p) { $p = [pscustomobject]@{} }
  $p | Add-Member -NotePropertyName lastModel -NotePropertyValue $ModelId -Force
  $p | Add-Member -NotePropertyName lastContextLength -NotePropertyValue $ContextLength -Force
  Write-PrefsObject $p
}

function Get-ShowTurnDuration {
  $p = Read-Prefs
  if (-not $p -or $null -eq $p.showTurnDuration) { return 'true' }
  if ($p.showTurnDuration) { return 'true' }
  return 'false'
}

function Get-KeepSessionOnExit {
  $p = Read-Prefs
  if (-not $p -or $null -eq $p.keepSessionOnExit) { return 'true' }
  if ($p.keepSessionOnExit) { return 'true' }
  return 'false'
}

function Normalize-RemoteUrl {
  param([string]$Raw, [int]$DefaultPort = 1234)
  $r = ($Raw -replace '\s','')
  if ([string]::IsNullOrWhiteSpace($r)) { return $null }
  if ($r -match '^https?://') { return $r.TrimEnd('/') }
  if ($r -match '^([^:]+):(\d+)$') { return "http://$($matches[1]):$($matches[2])" }
  return "http://${r}:$DefaultPort"
}

function OpenRouter-ListUrl {
  param([string]$Base)
  $b = $Base.TrimEnd('/')
  if ($b -like '*/api/v1') { return "$b/models" }
  return "$b/v1/models"
}

function Resolve-Backend {
  $script:CurrentBackend = if ($env:CLAUDIUS_BACKEND) { $env:CLAUDIUS_BACKEND } else { (Get-Pref 'backend') }
  if ([string]::IsNullOrWhiteSpace($script:CurrentBackend)) { $script:CurrentBackend = 'lmstudio' }
  $script:CurrentBaseUrl = if ($env:CLAUDIUS_BASE_URL) { $env:CLAUDIUS_BASE_URL.TrimEnd('/') } else { (Get-Pref 'baseUrl') }
  $script:CurrentApiKey = if ($env:CLAUDIUS_API_KEY) { $env:CLAUDIUS_API_KEY } else { (Get-Pref 'apiKey') }
  if ([string]::IsNullOrWhiteSpace($script:CurrentBaseUrl)) {
    switch ($script:CurrentBackend) {
      'lmstudio' {
        $script:CurrentBaseUrl = $Script:LmStudioUrl
      }
      'ollama' {
        $script:CurrentBaseUrl = $Script:OllamaUrl
      }
      'llamacpp' {
        $script:CurrentBaseUrl = $Script:LlamaCppUrl
      }
      'openrouter' {
        $script:CurrentBaseUrl = $Script:OpenRouterUrl
      }
      'nvidia' {
        $script:CurrentBaseUrl = $Script:NvidiaUrl
      }
      default {
        $script:CurrentBaseUrl = ''
      }
    }
  }
  if ($script:CurrentBackend -eq 'llamacpp' -and $script:CurrentBaseUrl -and $script:CurrentBaseUrl -notmatch '^https?://') {
    $nu = Normalize-RemoteUrl $script:CurrentBaseUrl 8080
    if ($nu) { $script:CurrentBaseUrl = $nu }
  }
  $script:CurrentAuth = switch ($script:CurrentBackend) {
    'lmstudio' { 'lmstudio' }
    'ollama'   { '' }
    'llamacpp' {
      $t = $env:CLAUDIUS_AUTH_TOKEN
      if ([string]::IsNullOrWhiteSpace($t)) { $t = (Get-Pref 'authToken') }
      if ([string]::IsNullOrWhiteSpace($t)) { 'lmstudio' } else { $t }
    }
    default { $script:CurrentApiKey }
  }
  $script:CurrentCustomListUrl = $null
  if ($script:CurrentBackend -eq 'custom' -and $script:CurrentBaseUrl -like '*dashscope-intl.aliyuncs.com*') {
    if ($script:CurrentBaseUrl -like '*compatible-mode*') {
      $script:CurrentCustomListUrl = $script:CurrentBaseUrl
      $saved = (Get-Pref 'baseUrl')
      if (-not $env:CLAUDIUS_BACKEND -and -not $env:CLAUDIUS_BASE_URL -and $saved -like '*compatible-mode*') {
        $script:CurrentBaseUrl = $Script:DashAnthropic
        Merge-Prefs 'custom' $script:CurrentBaseUrl $script:CurrentApiKey | Out-Null
        Write-Host ('  Updated prefs: Alibaba base URL -> ' + $Script:DashAnthropic + ' (Anthropic API for Claude Code).') -ForegroundColor DarkYellow
      } else {
        $script:CurrentBaseUrl = $Script:DashAnthropic
      }
    } elseif ($script:CurrentBaseUrl -like '*apps/anthropic*') {
      $script:CurrentCustomListUrl = $Script:DashOpenAI
    } else {
      $script:CurrentCustomListUrl = $script:CurrentBaseUrl
    }
  }
  if ($script:CurrentBackend -eq 'openrouter' -and $script:CurrentBaseUrl -like '*openrouter.ai/api/v1*') {
    if (-not $env:CLAUDIUS_BACKEND -and -not $env:CLAUDIUS_BASE_URL) {
      $saved = (Get-Pref 'baseUrl')
      if ($saved -like '*openrouter.ai/api/v1*') {
        $script:CurrentBaseUrl = 'https://openrouter.ai/api'
        Merge-Prefs 'openrouter' $script:CurrentBaseUrl $script:CurrentApiKey | Out-Null
        Write-Host '  Updated prefs: OpenRouter base URL -> https://openrouter.ai/api' -ForegroundColor DarkYellow
      }
    } else {
      $script:CurrentBaseUrl = 'https://openrouter.ai/api'
    }
  }
  if ($script:CurrentBackend -eq 'nvidia' -and $script:CurrentBaseUrl) {
    $nb = $script:CurrentBaseUrl.TrimEnd('/')
    if ($nb -like '*/v1') {
      $nb = $nb -replace '/v1$', ''
      $script:CurrentBaseUrl = $nb
      if (-not $env:CLAUDIUS_BASE_URL -and (Test-Path -LiteralPath $Script:ClaudiusPrefs)) {
        $saved = (Get-Pref 'baseUrl')
        if ($saved -like '*/v1') {
          Merge-Prefs 'nvidia' $script:CurrentBaseUrl $script:CurrentApiKey | Out-Null
        }
      }
    }
  }
}

function Check-ServerLmStudio { param([string]$Base) $code = Invoke-CurlCode "$Base/api/v1/models"; return ($code -eq '200') }
function Check-ServerOllama { param([string]$Base) $code = Invoke-CurlCode "$Base/api/tags"; return ($code -eq '200') }
function Check-ServerLlamaCpp {
  param([string]$Base, [string]$Auth)
  $url = "$($Base.TrimEnd('/'))/v1/models"
  if ($Auth) {
    $code = Invoke-CurlCode $url 10
  } else {
    $code = Invoke-CurlCode $url 10
  }
  return ($code -eq '200')
}
function Check-ServerOpenRouter {
  param([string]$Base, [string]$ApiKey)
  $u = OpenRouter-ListUrl $Base
  $code = & curl.exe -sS -o NUL -w '%{http_code}' --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" $u 2>$null
  return ($code -eq '200')
}
function Check-ServerCustom {
  param([string]$Base, [string]$ApiKey)
  $b = $Base.TrimEnd('/') + '/'
  $c1 = & curl.exe -sS -o NUL -w '%{http_code}' --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" "$($b)models" 2>$null
  if ($c1 -eq '200') { return $true }
  $c2 = & curl.exe -sS -o NUL -w '%{http_code}' --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" "$($b)v1/models" 2>$null
  return ($c2 -eq '200')
}
function Check-ServerNewapi {
  param([string]$Base, [string]$ApiKey)
  $u = "$($Base.TrimEnd('/'))/api/models"
  $code = & curl.exe -sS -o NUL -w '%{http_code}' --connect-timeout 2 --max-time $Script:CurlTimeout -H "Authorization: Bearer $ApiKey" $u 2>$null
  return ($code -eq '200')
}
function Check-ServerNvidia {
  param([string]$Base, [string]$ApiKey)
  $u = "$($Base.TrimEnd('/'))/v1/models"
  $code = & curl.exe -sS -o NUL -w '%{http_code}' --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" $u 2>$null
  return ($code -eq '200')
}

function Test-JsonHasDataArray {
  param([string]$Json)
  try {
    $o = $Json | ConvertFrom-Json
    return ($o.data -is [System.Array] -and $o.data.Count -gt 0)
  } catch { return $false }
}

function Fetch-ModelsLmStudio {
  param([string]$Base)
  $r = Invoke-CurlString "$Base/api/v1/models" -TimeoutSec $Script:CurlTimeout
  if ([string]::IsNullOrWhiteSpace($r)) { Write-Host "Error: Could not reach LM Studio at $Base." -ForegroundColor Red; return @() }
  try {
    $d = $r | ConvertFrom-Json
    $out = @()
    foreach ($m in $d.models) {
      if ($m.type -eq 'llm') {
        $mc = if ($m.max_context_length) { [int]$m.max_context_length } else { 32768 }
        $out += (New-ClaudiusModelEntryString $m.key $mc)
      }
    }
    return $out
  } catch {
    Write-Host "Error: Could not parse LM Studio model list." -ForegroundColor Red
    return @()
  }
}

function Fetch-ModelsOllama {
  param([string]$Base)
  $r = Invoke-CurlString "$Base/api/tags" -TimeoutSec $Script:CurlTimeout
  if ([string]::IsNullOrWhiteSpace($r)) { Write-Host "Error: Could not reach Ollama at $Base." -ForegroundColor Red; return @() }
  try {
    $d = $r | ConvertFrom-Json
    $out = @()
    foreach ($m in $d.models) {
      if ($m.name) { $out += (New-ClaudiusModelEntryString $m.name 32768) }
    }
    return $out
  } catch { return @() }
}

function Fetch-ModelsLlamaCpp {
  param([string]$Base, [string]$Auth)
  $url = "$($Base.TrimEnd('/'))/v1/models"
  $h = @{}
  if ($Auth) { $h['Authorization'] = "Bearer $Auth" }
  $r = if ($h.Count) {
    & curl.exe -sS --connect-timeout 2 --max-time $Script:CurlTimeout -H "Authorization: Bearer $Auth" $url 2>$null
  } else {
    Invoke-CurlString $url -TimeoutSec $Script:CurlTimeout
  }
  if ([string]::IsNullOrWhiteSpace($r)) { return @() }
  try {
    $d = $r | ConvertFrom-Json
    $out = @()
    foreach ($x in $d.data) {
      $ctx = 32768
      if ($x.context_length) { $ctx = [int]$x.context_length }
      elseif ($x.max_tokens) { $ctx = [int]$x.max_tokens }
      elseif ($x.max_context_tokens) { $ctx = [int]$x.max_context_tokens }
      elseif ($x.max_input_tokens) { $ctx = [int]$x.max_input_tokens }
      if ($x.id) { $out += (New-ClaudiusModelEntryString $x.id $ctx) }
    }
    return $out
  } catch { return @() }
}

function Fetch-ModelsOpenRouter {
  param([string]$Base, [string]$ApiKey)
  $u = OpenRouter-ListUrl $Base
  $r = & curl.exe -sS --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" $u 2>$null
  if ([string]::IsNullOrWhiteSpace($r)) { Write-Host 'Error: Could not reach OpenRouter.' -ForegroundColor Red; return @() }
  try {
    $d = $r | ConvertFrom-Json
    $out = @()
    foreach ($x in $d.data) {
      $ctx = 32768
      if ($x.context_length) { $ctx = [int]$x.context_length }
      elseif ($x.max_tokens) { $ctx = [int]$x.max_tokens }
      if ($x.id) { $out += (New-ClaudiusModelEntryString $x.id $ctx) }
    }
    return $out
  } catch { return @() }
}

function Fetch-ModelsCustom {
  param([string]$Base, [string]$ApiKey)
  $b = $Base.TrimEnd('/') + '/'
  $r = & curl.exe -sS --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" "$($b)models" 2>$null
  if (-not (Test-JsonHasDataArray $r)) {
    $r = & curl.exe -sS --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" "$($b)v1/models" 2>$null
  }
  if ([string]::IsNullOrWhiteSpace($r)) { return @() }
  try {
    $d = $r | ConvertFrom-Json
    $out = @()
    foreach ($x in $d.data) {
      $ctx = 32768
      if ($x.context_length) { $ctx = [int]$x.context_length }
      elseif ($x.max_tokens) { $ctx = [int]$x.max_tokens }
      if ($x.id) { $out += (New-ClaudiusModelEntryString $x.id $ctx) }
    }
    return $out
  } catch { return @() }
}

function Fetch-ModelsNewapi {
  param([string]$Base, [string]$ApiKey)
  $u = "$($Base.TrimEnd('/'))/api/models"
  $r = & curl.exe -sS --connect-timeout 2 --max-time $Script:CurlTimeout -H "Authorization: Bearer $ApiKey" $u 2>$null
  if ([string]::IsNullOrWhiteSpace($r)) { return @() }
  try {
    $d = $r | ConvertFrom-Json
    $out = @()
    $data = $d.data
    if ($null -eq $data) { return @() }
    if ($data -is [hashtable]) {
      foreach ($v in $data.Values) {
        if ($v -is [System.Array]) { foreach ($name in $v) { if ($name) { $out += (New-ClaudiusModelEntryString $name 32768) } } }
      }
    } else {
      foreach ($prop in $data.PSObject.Properties) {
        $arr = $prop.Value
        if ($arr -is [System.Array]) {
          foreach ($name in $arr) { if ($name) { $out += (New-ClaudiusModelEntryString $name 32768) } }
        }
      }
    }
    return $out
  } catch { return @() }
}

function Fetch-ModelsNvidia {
  param([string]$Base, [string]$ApiKey)
  $u = "$($Base.TrimEnd('/'))/v1/models"
  $r = & curl.exe -sS --connect-timeout 5 --max-time $Script:CurlTimeoutCloud --retry 2 --retry-delay 1 -H "Authorization: Bearer $ApiKey" $u 2>$null
  if ([string]::IsNullOrWhiteSpace($r)) {
    Write-Host "Error: Could not reach NVIDIA API at $Base." -ForegroundColor Red
    return @()
  }
  try {
    $d = $r | ConvertFrom-Json
    $out = @()
    foreach ($x in $d.data) {
      $ctx = 32768
      if ($x.context_length) { $ctx = [int]$x.context_length }
      elseif ($x.max_tokens) { $ctx = [int]$x.max_tokens }
      elseif ($x.max_context_tokens) { $ctx = [int]$x.max_context_tokens }
      elseif ($x.max_input_tokens) { $ctx = [int]$x.max_input_tokens }
      if ($x.id) { $out += (New-ClaudiusModelEntryString $x.id $ctx) }
    }
    return $out
  } catch {
    Write-Host 'Error: Could not parse NVIDIA API model list.' -ForegroundColor Red
    return @()
  }
}

function Get-ModelsForBackend {
  switch ($script:CurrentBackend) {
    'lmstudio'  { Fetch-ModelsLmStudio $script:CurrentBaseUrl }
    'ollama'    { Fetch-ModelsOllama $script:CurrentBaseUrl }
    'llamacpp'  { Fetch-ModelsLlamaCpp $script:CurrentBaseUrl $script:CurrentAuth }
    'openrouter' { Fetch-ModelsOpenRouter $script:CurrentBaseUrl $script:CurrentApiKey }
    'custom'    {
      $listBase = if ($script:CurrentCustomListUrl) { $script:CurrentCustomListUrl } else { $script:CurrentBaseUrl }
      Fetch-ModelsCustom $listBase $script:CurrentApiKey
    }
    'newapi'    { Fetch-ModelsNewapi $script:CurrentBaseUrl $script:CurrentApiKey }
    'nvidia'    { Fetch-ModelsNvidia $script:CurrentBaseUrl $script:CurrentApiKey }
    default     { Fetch-ModelsLmStudio $script:CurrentBaseUrl }
  }
}

function Test-ServerForBackend {
  switch ($script:CurrentBackend) {
    'lmstudio'   { Check-ServerLmStudio $script:CurrentBaseUrl }
    'ollama'     { Check-ServerOllama $script:CurrentBaseUrl }
    'llamacpp'   { Check-ServerLlamaCpp $script:CurrentBaseUrl $script:CurrentAuth }
    'openrouter' { Check-ServerOpenRouter $script:CurrentBaseUrl $script:CurrentApiKey }
    'custom'     {
      $listBase = if ($script:CurrentCustomListUrl) { $script:CurrentCustomListUrl } else { $script:CurrentBaseUrl }
      Check-ServerCustom $listBase $script:CurrentApiKey
    }
    'newapi'     { Check-ServerNewapi $script:CurrentBaseUrl $script:CurrentApiKey }
    'nvidia'     { Check-ServerNvidia $script:CurrentBaseUrl $script:CurrentApiKey }
    default      { Check-ServerLmStudio $script:CurrentBaseUrl }
  }
}

function Get-LoadedLmStudioModel {
  param([string]$ApiBase)
  $r = Invoke-CurlString "$ApiBase/models" -TimeoutSec $Script:CurlTimeout
  if ([string]::IsNullOrWhiteSpace($r)) { return $null }
  try {
    $d = $r | ConvertFrom-Json
    foreach ($m in $d.models) {
      $insts = $m.loaded_instances
      if ($insts -and $insts.Count -gt 0) {
        $cfg = $insts[0]
        $ctx = 32768
        if ($cfg.config -and $cfg.config.context_length) { $ctx = [int]$cfg.config.context_length }
        elseif ($cfg.context_length) { $ctx = [int]$cfg.context_length }
        elseif ($m.max_context_length) { $ctx = [int]$m.max_context_length }
        return (New-ClaudiusModelEntryString $m.key $ctx)
      }
    }
  } catch {}
  return $null
}

function Unload-LmStudioModels {
  param([string]$ApiBase)
  $r = Invoke-CurlString "$ApiBase/models" -TimeoutSec $Script:CurlTimeout
  if ([string]::IsNullOrWhiteSpace($r)) { return }
  try {
    $d = $r | ConvertFrom-Json
    $ids = @()
    foreach ($m in $d.models) {
      foreach ($inst in $m.loaded_instances) {
        if ($inst.id) { $ids += $inst.id }
      }
    }
    if ($ids.Count -eq 0) { return }
    Write-Host '  Unloading previous model(s)...'
    foreach ($id in $ids) {
      $body = (@{ instance_id = $id } | ConvertTo-Json -Compress)
      Invoke-CurlString "$ApiBase/models/unload" -Method POST -Body $body -TimeoutSec 30 | Out-Null
    }
  } catch {}
}

function Load-LmStudioModel {
  param([string]$ModelKey, [int]$ContextLength, [string]$ApiBase)
  Unload-LmStudioModels $ApiBase
  $body = (@{ model = $ModelKey; context_length = $ContextLength } | ConvertTo-Json -Compress)
  Write-Host "Loading model (context $ContextLength)..."
  $resp = & curl.exe -sS -w "`n%{http_code}" --connect-timeout 2 --max-time 300 -X POST -H "Content-Type: application/json" -d $body "$ApiBase/models/load" 2>$null
  $lines = $resp -split "`n"
  $code = $lines[-1]
  if ($code -ne '200') {
    Write-Host "Warning: LM Studio load returned HTTP $code" -ForegroundColor Yellow
    return $false
  }
  Write-Host "  Loaded $ModelKey with context length $ContextLength."
  return $true
}

function Select-Model {
  $lines = @(Get-ModelsForBackend)
  $lines = $lines | Where-Object { $_ }
  if ($lines.Count -eq 0) {
    Write-Host 'No models found. Check backend and try again.' -ForegroundColor Red
    return $null
  }
  $keys = @(); $maxs = @()
  foreach ($ln in $lines) {
    # Each model line is key, ASCII 124, max tokens. Split uses 0x7C only (never bare pipe after subexpr in double quotes).
    $p = $ln.Split([char]0x7C, 2)
    $keys += $p[0]
    $maxs += if ($p.Count -gt 1) { [int]$p[1] } else { 32768 }
  }
  Write-Host "Models available ($($script:CurrentBackend)):"
  Write-Host ''
  for ($i = 0; $i -lt $keys.Count; $i++) {
    $nStr = ($i + 1).ToString().PadLeft(2)
    # Menu line uses one expandable string; do not chain quoted fragments with parens (PS 5.1).
    Write-Host "  $($nStr)) $($keys[$i]) (max $($maxs[$i]) tokens)"
  }
  Write-Host '  q) Quit'
  Write-Host ''
  while ($true) {
    $c = Read-Host "Select model (1-$($keys.Count) or q)"
    if ($c -match '^[qQ]$') { return $null }
    if ($c -match '^\d+$') {
      $n = [int]$c
      if ($n -ge 1 -and $n -le $keys.Count) {
        return (New-ClaudiusModelEntryString $keys[$n - 1] $maxs[$n - 1])
      }
    }
    Write-Host 'Invalid choice.'
  }
}

function Select-ContextLength {
  param([string]$ModelKey, [int]$MaxCtx, [int]$CurrentCtx = -1)
  $minCtx = 2048
  if ($MaxCtx -lt $minCtx) { $minCtx = 1024 }
  if ($MaxCtx -le $minCtx) { return $MaxCtx }
  $step = [math]::Floor(($MaxCtx - $minCtx) / 4)
  $v1 = $minCtx
  $v2 = [math]::Max($minCtx, [math]::Floor(($minCtx + $step) / 256) * 256)
  $v3 = [math]::Min($MaxCtx, [math]::Floor(($minCtx + 2 * $step) / 256) * 256)
  $v4 = [math]::Min($MaxCtx, [math]::Floor(($minCtx + 3 * $step) / 256) * 256)
  $v5 = $MaxCtx
  if ($CurrentCtx -ge 0) {
    Write-Host "Model $ModelKey is already loaded with context length $CurrentCtx."
    Write-Host 'Change context or keep as is?'
    Write-Host ''
    Write-Host "  1) Keep current ($CurrentCtx)"
    Write-Host "  2) $v1"
    Write-Host "  3) $v2"
    Write-Host "  4) $v3"
    Write-Host "  5) $v4"
    Write-Host "  6) $v5"
    Write-Host '  7) Custom'
    Write-Host ''
    while ($true) {
      $ch = Read-Host 'Choose (1-7)'
      switch ($ch) {
        '1' { return $CurrentCtx }
        '2' { return $v1 }
        '3' { return $v2 }
        '4' { return $v3 }
        '5' { return $v4 }
        '6' { return $v5 }
        '7' {
          $x = Read-Host "Enter context length ($minCtx-$MaxCtx)"
          if ($x -match '^\d+$') {
            $xi = [int]$x
            if ($xi -ge $minCtx -and $xi -le $MaxCtx) { return $xi }
          }
          Write-Host "Enter a number between $minCtx and $MaxCtx."
        }
        default { Write-Host 'Invalid.' }
      }
    }
  }
  Write-Host "Context length (tokens) for ${ModelKey}: min $minCtx, max $MaxCtx"
  Write-Host ''
  Write-Host "  1) $v1"
  Write-Host "  2) $v2"
  Write-Host "  3) $v3"
  Write-Host "  4) $v4"
  Write-Host "  5) $v5"
  Write-Host '  6) Custom'
  Write-Host ''
  while ($true) {
    $ch = Read-Host 'Choose (1-6)'
    switch ($ch) {
      '1' { return $v1 }
      '2' { return $v2 }
      '3' { return $v3 }
      '4' { return $v4 }
      '5' { return $v5 }
      '6' {
        $x = Read-Host "Enter context length ($minCtx-$MaxCtx)"
        if ($x -match '^\d+$') {
          $xi = [int]$x
          if ($xi -ge $minCtx -and $xi -le $MaxCtx) { return $xi }
        }
        Write-Host "Enter a number between $minCtx and $MaxCtx."
      }
      default { Write-Host 'Invalid.' }
    }
  }
}

# -----------------------------------------------------------------------------
# RAM/GPU memory pre-check - intentionally not implemented on Windows
# -----------------------------------------------------------------------------
# Removed (v0.9.12): Get-RamAvailableMb, Get-NvidiaFreeMb, Estimate-RequiredMb,
# Test-MemoryAndConfirm. That block mixed WMI, nvidia-smi CSV, regex + $matches,
# and pipe-delimited strings in ways that led to fragile parsing (cascade parse
# errors on PowerShell 5.1 and 7). Pre-check exists on Linux/macOS in claudius.sh.
# On Windows we load the model in LM Studio as before; if VRAM/RAM is insufficient,
# the load API fails - check LM Studio logs. See README changelog 0.9.12.
# -----------------------------------------------------------------------------

function Write-SettingsJson {
  param([string]$ModelId, [string]$BaseUrl, [string]$AuthToken, [string]$ApiKey, [string]$Backend)
  $schema = 'https://json.schemastore.org/claude-code-settings.json'
  $showTurn = (Get-ShowTurnDuration) -eq 'true'
  $apik = $ApiKey
  if ([string]::IsNullOrWhiteSpace($apik)) { $apik = $AuthToken }

  $dashAnthropic = ($Backend -eq 'custom' -and $BaseUrl -like '*dashscope*' -and $BaseUrl -like '*apps/anthropic*')

  $envBlock = [ordered]@{}
  $root = [ordered]@{
    '$schema' = $schema
    'defaultModel' = $ModelId
    'showTurnDuration' = $showTurn
  }

  switch ($Backend) {
    'openrouter' {
      $envBlock['ANTHROPIC_BASE_URL'] = $BaseUrl
      $envBlock['ANTHROPIC_AUTH_TOKEN'] = $apik
      $envBlock['ANTHROPIC_API_KEY'] = ''
      $envBlock['CLAUDE_CODE_ATTRIBUTION_HEADER'] = '0'
    }
    'nvidia' {
      $envBlock['ANTHROPIC_BASE_URL'] = $BaseUrl
      $envBlock['ANTHROPIC_AUTH_TOKEN'] = $apik
      $envBlock['ANTHROPIC_API_KEY'] = ''
      $envBlock['CLAUDE_CODE_ATTRIBUTION_HEADER'] = '0'
    }
    'custom' {
      if ($dashAnthropic) {
        $envBlock['ANTHROPIC_BASE_URL'] = $BaseUrl
        $envBlock['ANTHROPIC_AUTH_TOKEN'] = $apik
        $envBlock['ANTHROPIC_API_KEY'] = ''
        $envBlock['CLAUDE_CODE_ATTRIBUTION_HEADER'] = '0'
      } else {
        $envBlock['ANTHROPIC_BASE_URL'] = $BaseUrl
        $envBlock['ANTHROPIC_API_KEY'] = $apik
      }
    }
    'newapi' {
      $envBlock['ANTHROPIC_BASE_URL'] = $BaseUrl
      $envBlock['ANTHROPIC_API_KEY'] = $apik
    }
    'llamacpp' {
      $envBlock['ANTHROPIC_BASE_URL'] = $BaseUrl
      $envBlock['ANTHROPIC_AUTH_TOKEN'] = $AuthToken
      $envBlock['ANTHROPIC_API_KEY'] = ''
      $envBlock['CLAUDE_CODE_ATTRIBUTION_HEADER'] = '0'
      $envBlock['ENABLE_TOOL_SEARCH'] = 'true'
      $envBlock['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = '100000'
    }
    default {
      $envBlock['ANTHROPIC_BASE_URL'] = $BaseUrl
      $envBlock['ANTHROPIC_AUTH_TOKEN'] = $AuthToken
      if ($Backend -eq 'ollama') {
        $envBlock['ANTHROPIC_AUTH_TOKEN'] = $AuthToken
      }
    }
  }
  $root['env'] = [pscustomobject]$envBlock
  if (-not (Test-Path -LiteralPath $Script:ClaudeHome)) { New-Item -ItemType Directory -Path $Script:ClaudeHome -Force | Out-Null }
  $json = ([pscustomobject]$root | ConvertTo-Json -Depth 10)
  Write-Utf8NoBom -Path $Script:ClaudeSettings -Content ($json + "`n")
  Write-Host "  Updated: $Script:ClaudeSettings (defaultModel = $ModelId)"
}

function Set-VerifyEnv {
  param([string]$ModelId, [string]$BaseUrl, [string]$AuthToken, [string]$ApiKey, [string]$Backend)
  $env:ANTHROPIC_BASE_URL = $BaseUrl
  $env:CLAUDE_CODE_ATTRIBUTION_HEADER = '0'
  $apik = $ApiKey
  if ([string]::IsNullOrWhiteSpace($apik)) { $apik = $AuthToken }
  $dashAnthropic = ($Backend -eq 'custom' -and $BaseUrl -like '*dashscope*' -and $BaseUrl -like '*apps/anthropic*')
  Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
  Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
  switch ($Backend) {
    'openrouter' {
      $env:ANTHROPIC_AUTH_TOKEN = $apik
      $env:ANTHROPIC_API_KEY = ''
    }
    'nvidia' {
      $env:ANTHROPIC_AUTH_TOKEN = $apik
      $env:ANTHROPIC_API_KEY = ''
    }
    'custom' {
      if ($dashAnthropic) {
        $env:ANTHROPIC_AUTH_TOKEN = $apik
        $env:ANTHROPIC_API_KEY = ''
      } else {
        $env:ANTHROPIC_API_KEY = $apik
      }
    }
    'newapi' { $env:ANTHROPIC_API_KEY = $apik }
    'llamacpp' {
      $env:ANTHROPIC_AUTH_TOKEN = $AuthToken
      $env:ANTHROPIC_API_KEY = ''
      $env:ENABLE_TOOL_SEARCH = 'true'
      $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = '100000'
    }
    default {
      $env:ANTHROPIC_AUTH_TOKEN = $AuthToken
    }
  }
  Write-Host ''
  Write-Host 'Verified (for this session):'
  Write-Host "  ANTHROPIC_BASE_URL=$($env:ANTHROPIC_BASE_URL)"
  Write-Host "  defaultModel (this run)= $ModelId"
  Write-Host ''
}

function Prompt-RemoteServer {
  param([string]$FixedBackend = '')
  Write-Host 'Connect to a remote server (e.g. another machine on your network).'
  $hint = ''
  if ($script:CurrentBaseUrl) {
    $hint = $script:CurrentBaseUrl -replace '^https?://',''
  }
  if ($FixedBackend) {
    $addr = Read-Host "Enter server address (host or IP:port) [$hint, Enter=keep]"
  } else {
    $addr = Read-Host "Enter server address (host or IP:port) [$hint]"
  }
  $addr = ($addr -replace '\s','')
  if ([string]::IsNullOrWhiteSpace($addr)) {
    if ($FixedBackend -and $script:CurrentBaseUrl) { $addr = $script:CurrentBaseUrl }
    else { Write-Host '  No address entered. Skipped.'; return $false }
  }
  $defPort = 1234
  if ($FixedBackend) {
    $script:CurrentBackend = $FixedBackend
    switch ($FixedBackend) {
      'lmstudio' { $defPort = 1234 }
      'ollama'   { $defPort = 11434 }
      'llamacpp' { $defPort = 8080 }
    }
  } else {
    Write-Host 'Backend on that server:'
    Write-Host '  1) LM Studio (1234)'
    Write-Host '  2) Ollama (11434)'
    Write-Host '  3) llama.cpp (8080)'
    $bn = Read-Host 'Choose (1-3) [1]'
    if ([string]::IsNullOrWhiteSpace($bn)) { $bn = '1' }
    switch ($bn) {
      '1' { $script:CurrentBackend = 'lmstudio'; $defPort = 1234 }
      '2' { $script:CurrentBackend = 'ollama'; $defPort = 11434 }
      '3' { $script:CurrentBackend = 'llamacpp'; $defPort = 8080 }
      default { $script:CurrentBackend = 'lmstudio'; $defPort = 1234 }
    }
  }
  $nu = Normalize-RemoteUrl $addr $defPort
  if (-not $nu) { Write-Host '  Could not parse address.'; return $false }
  $script:CurrentBaseUrl = $nu
  $script:CurrentAuth = switch ($script:CurrentBackend) {
    'lmstudio' { 'lmstudio' }
    'ollama'   { '' }
    'llamacpp' { if ([string]::IsNullOrWhiteSpace((Get-Pref 'authToken'))) { 'lmstudio' } else { (Get-Pref 'authToken') } }
    default { $script:CurrentApiKey }
  }
  Merge-Prefs $script:CurrentBackend $script:CurrentBaseUrl $script:CurrentApiKey | Out-Null
  Write-Host "  Using $($script:CurrentBackend) @ $($script:CurrentBaseUrl)"
  return $true
}

function Wait-ForServer {
  while (-not (Test-ServerForBackend)) {
    if ($script:CurrentBackend -eq 'lmstudio') {
      Write-Host "LM Studio server is not running at $($script:CurrentBaseUrl)."
      Write-Host ''
      Write-Host '  1) Resume   - server is up; check again'
      Write-Host '  2) Start    - try: lms server start (if lms is on PATH)'
      Write-Host '  3) Remote   - another host:port'
      Write-Host '  4) Abort'
      Write-Host ''
      $ch = Read-Host 'Choose (1-4)'
      switch ($ch) {
        '1' { if (Test-ServerForBackend) { Write-Host 'Server is up.'; return } }
        '2' {
          $lms = Get-Command lms.exe -ErrorAction SilentlyContinue
          if ($lms) {
            Start-Process -FilePath 'lms.exe' -ArgumentList 'server','start' -WindowStyle Hidden
            Start-Sleep -Seconds 3
            if (Test-ServerForBackend) { return }
          } else {
            Write-Host "Command 'lms' not found. Start LM Studio from the GUI, or install LM Studio CLI."
          }
        }
        '3' { if (Prompt-RemoteServer) { if (Test-ServerForBackend) { return } } }
        '4' { exit 1 }
        default { Write-Host 'Invalid.' }
      }
    } elseif ($script:CurrentBackend -eq 'ollama') {
      Write-Host "Ollama not reachable at $($script:CurrentBaseUrl)."
      Write-Host '  1) Resume  2) Start ollama serve  3) Remote  4) Abort'
      $ch = Read-Host 'Choose'
      switch ($ch) {
        '1' { if (Test-ServerForBackend) { return } }
        '2' {
          $o = Get-Command ollama.exe -ErrorAction SilentlyContinue
          if ($o) { Start-Process ollama.exe -ArgumentList 'serve' -WindowStyle Hidden; Start-Sleep 3 }
          if (Test-ServerForBackend) { return }
        }
        '3' { if (Prompt-RemoteServer) { if (Test-ServerForBackend) { return } } }
        '4' { exit 1 }
      }
    } elseif ($script:CurrentBackend -eq 'llamacpp') {
      Write-Host "llama-server not reachable at $($script:CurrentBaseUrl)."
      Write-Host '  1) Resume  2) Remote  3) Abort'
      $ch = Read-Host 'Choose'
      switch ($ch) {
        '1' { if (Test-ServerForBackend) { return } }
        '2' { if (Prompt-RemoteServer -FixedBackend 'llamacpp') { if (Test-ServerForBackend) { return } } }
        '3' { exit 1 }
      }
    } else {
      Write-Host "Cannot reach $($script:CurrentBackend) at $($script:CurrentBaseUrl)."
      Write-Host '  1) Retry  2) Abort'
      $ch = Read-Host 'Choose'
      switch ($ch) {
        '1' { if (Test-ServerForBackend) { return } }
        '2' { exit 1 }
      }
    }
  }
}

function Test-LmStudioInstalled {
  if (Get-Command lms.exe -ErrorAction SilentlyContinue) { return $true }
  $p = Join-Path $env:USERPROFILE '.lmstudio\bin\lms.exe'
  if (Test-Path -LiteralPath $p) { return $true }
  Write-Host "LM Studio CLI not found (no 'lms' on PATH). Install LM Studio from https://lmstudio.ai/"
  return $false
}

function Test-OllamaInstalled {
  if (Get-Command ollama.exe -ErrorAction SilentlyContinue) { return $true }
  Write-Host "Ollama not found. Install from https://ollama.com"
  return $false
}

function Run-Init {
  Write-Host "Claudius first-time setup (preferences saved to $Script:ClaudiusPrefs)"
  Write-Host ''
  $st = Read-Host "Show reply duration after each response? [Y/n]"
  if ([string]::IsNullOrWhiteSpace($st)) { $st = 'y' }
  $showTurn = -not ($st -match '^(n|no)$')
  $ks = Read-Host 'Keep session history when Claude Code exits? [Y/n]'
  if ([string]::IsNullOrWhiteSpace($ks)) { $ks = 'y' }
  $keepSess = -not ($ks -match '^(n|no)$')
  Write-Host 'Which backend should Claudius use?'
  Write-Host '  1) LM Studio (http://localhost:1234)'
  Write-Host '  2) Ollama (http://localhost:11434)'
  Write-Host '  3) OpenRouter (https://openrouter.ai/api - needs API key)'
  Write-Host '  4) Custom (Alibaba, Kimi, DeepSeek, Groq, xAI, OpenAI, Other)'
  Write-Host '  5) NewAPI (gateway - self-host or cloud)'
  Write-Host '  6) llama.cpp server (llama-server, default http://127.0.0.1:8080)'
  Write-Host '  7) NVIDIA API (listing works; host is OpenAI chat not Anthropic /messages - see warning)'
  Write-Host ''
  $bc = Read-Host 'Choose (1-7) [1]'
  if ([string]::IsNullOrWhiteSpace($bc)) { $bc = '1' }
  $backend = 'lmstudio'
  $baseUrl = $Script:LmStudioUrl
  $apiKey = ''
  $authTok = ''
  switch ($bc) {
    '1' { $backend = 'lmstudio'; $baseUrl = $Script:LmStudioUrl }
    '2' { $backend = 'ollama'; $baseUrl = $Script:OllamaUrl }
    '3' {
      $backend = 'openrouter'
      $baseUrl = $Script:OpenRouterUrl
      $apiKey = Read-Host 'OpenRouter API key'
    }
    '5' {
      $backend = 'newapi'
      $baseUrl = Read-Host 'NewAPI base URL [http://localhost:8080]'
      if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = 'http://localhost:8080' }
      $apiKey = Read-Host 'NewAPI API key'
    }
    '4' {
      $backend = 'custom'
      Write-Host 'Custom provider:'
      Write-Host '  1) Alibaba DashScope (intl.) - Anthropic API'
      Write-Host '  2) Kimi - api.moonshot.ai'
      Write-Host '  3) DeepSeek'
      Write-Host '  4) Groq'
      Write-Host '  5) OpenRouter (same as option 3)'
      Write-Host '  6) xAI'
      Write-Host '  7) OpenAI'
      Write-Host '  8) Other - enter URL'
      $cc = Read-Host 'Choose (1-8) [1]'
      if ([string]::IsNullOrWhiteSpace($cc)) { $cc = '1' }
      switch ($cc) {
        '1' { $baseUrl = $Script:DashAnthropic }
        '2' { $baseUrl = 'https://api.moonshot.ai/v1' }
        '3' { $baseUrl = 'https://api.deepseek.com/v1' }
        '4' { $baseUrl = 'https://api.groq.com/openai/v1' }
        '5' { $baseUrl = $Script:OpenRouterUrl }
        '6' { $baseUrl = 'https://api.x.ai/v1' }
        '7' { $baseUrl = 'https://api.openai.com/v1' }
        '8' { $baseUrl = Read-Host 'Custom API base URL' }
        default { $baseUrl = $Script:DashAnthropic }
      }
      $apiKey = Read-Host 'API key'
    }
    '6' {
      $backend = 'llamacpp'
      $bu = Read-Host 'llama.cpp base URL [http://127.0.0.1:8080]'
      if ([string]::IsNullOrWhiteSpace($bu)) { $bu = 'http://127.0.0.1:8080' }
      $baseUrl = Normalize-RemoteUrl $bu 8080
      if (-not $baseUrl) { $baseUrl = 'http://127.0.0.1:8080' }
      $authTok = Read-Host 'Bearer token for ANTHROPIC_AUTH_TOKEN [lmstudio]'
      if ([string]::IsNullOrWhiteSpace($authTok)) { $authTok = 'lmstudio' }
    }
    '7' {
      $backend = 'nvidia'
      $nh = Read-Host "NVIDIA API host [$($Script:NvidiaUrl)]"
      if ([string]::IsNullOrWhiteSpace($nh)) { $nh = $Script:NvidiaUrl }
      $nh = $nh.TrimEnd('/')
      if ($nh -like '*/v1') { $nh = $nh -replace '/v1$', '' }
      $baseUrl = $nh
      $apiKey = Read-Host 'NVIDIA API key (Bearer)'
      Warn-NvidiaClaudeCodeProtocol
    }
    default { $backend = 'lmstudio'; $baseUrl = $Script:LmStudioUrl }
  }
  $obj = [pscustomobject]@{
    showTurnDuration = $showTurn
    keepSessionOnExit = $keepSess
    backend = $backend
    baseUrl = $baseUrl
    apiKey = $apiKey
    authToken = $authTok
  }
  Write-PrefsObject $obj
  Write-Host '  Saved. Run claudius --init again anytime to change these.'
  Write-Host ''
}

function Run-Purge {
  Write-Host "Claudius - purge session data under $Script:ClaudeHome"
  Write-Host ''
  Write-Host '  1) Purge ALL session data (two confirmations)'
  Write-Host '  2) Purge last session only (~2 min)'
  Write-Host '  3) Exit'
  Write-Host ''
  $c = Read-Host 'Choose (1-3)'
  if ($c -eq '1') {
    $a = Read-Host 'Type YES to purge ALL session data'
    if ($a -ne 'YES') { Write-Host 'Cancelled.'; return }
    $a2 = Read-Host 'Confirm again: type DELETE'
    if ($a2 -ne 'DELETE') { Write-Host 'Cancelled.'; return }
    foreach ($d in $Script:SessionDirs) {
      $p = Join-Path $Script:ClaudeHome $d
      if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host 'Purged session directories.'
  } elseif ($c -eq '2') {
    foreach ($d in $Script:SessionDirs) {
      $p = Join-Path $Script:ClaudeHome $d
      if (Test-Path -LiteralPath $p) {
        Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |
          Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) } |
          Remove-Item -Force -ErrorAction SilentlyContinue
      }
    }
    Write-Host 'Recent session files purged (best effort).'
  }
}

function Test-RequiredCommands {
  if (-not (Test-CurlAvailable)) {
    Write-Host 'curl.exe not found. Install Windows curl or use Windows 10 1803+.' -ForegroundColor Red
    return $false
  }
  return $true
}

function Main {
  param([string[]]$ArgsRemaining)
  $dry = $false
  $bypass = $false
  $lastMode = $false
  $argList = [System.Collections.ArrayList]@()
  foreach ($a in $ArgsRemaining) {
    if ($a -eq '--dry-run' -or $a -eq '--test') { $dry = $true; continue }
    if ($a -eq '--by-pass-start') { $bypass = $true; continue }
    if ($a -eq '--last') { $lastMode = $true; continue }
    [void]$argList.Add($a)
  }
  $rest = @($argList)

  if ($rest -contains '--help' -or $rest -contains '-h') { Print-Help; exit 0 }

  if ($rest -contains '--purge') { Run-Purge; exit 0 }

  if ($rest -contains '--init') {
    Run-Init
    $rest = $rest | Where-Object { $_ -ne '--init' }
  }

  if (-not (Test-Path -LiteralPath $Script:ClaudiusPrefs)) {
    Write-Host 'First-time run: checking dependencies...'
    Write-Host ''
    if (-not (Test-RequiredCommands)) { exit 1 }
    Run-Init
    Resolve-Backend
    $ib = (Get-Pref 'backend')
    if ($ib -eq 'lmstudio') { if (-not (Test-LmStudioInstalled)) { exit 1 } }
    elseif ($ib -eq 'ollama') { if (-not (Test-OllamaInstalled)) { exit 1 } }
  }

  Resolve-Backend

  if (-not $dry) {
    if (-not (Ensure-ClaudeInstalled)) {
      Write-Host 'Claude Code CLI is required. Install it, then run claudius again.'
      exit 1
    }
  }

  Write-Host "Claudius v$($Script:Version) - Claude Code multi-backend ($($script:CurrentBackend))"
  Write-Host "Backend: $($script:CurrentBackend) @ $($script:CurrentBaseUrl)"
  if ($script:CurrentBackend -eq 'nvidia') { Warn-NvidiaClaudeCodeProtocol }
  if ($dry) { Write-Host '(dry-run: will not write config or start claude)' }
  Write-Host ''

  Wait-ForServer

  $apiBase = "$($script:CurrentBaseUrl)/api/v1"
  $modelId = ''
  $maxCtx = 32768
  $contextLength = 32768
  $skipLoad = $false

  if ($lastMode) {
    $modelId = Get-Pref 'lastModel'
    $cs = Get-Pref 'lastContextLength'
    if ([string]::IsNullOrWhiteSpace($cs) -or $cs -notmatch '^\d+$') { $contextLength = 32768 } else { $contextLength = [int]$cs }
    if ([string]::IsNullOrWhiteSpace($modelId)) {
      Write-Host 'No last model saved. Run claudius once to select a model.' -ForegroundColor Red
      exit 1
    }
    $maxCtx = $contextLength
    Write-Host ''
    Write-Host "Using last: $modelId (context length $contextLength)"
    Write-Host ''
    if ($script:CurrentBackend -eq 'lmstudio') {
      $loaded = Get-LoadedLmStudioModel $apiBase
      if ($loaded) {
        $pk = $loaded.Split([char]0x7C)
        if ($pk[0] -eq $modelId -and [int]$pk[1] -eq $contextLength) { $skipLoad = $true }
      }
    }
  } else {
    $sel = Select-Model
    if (-not $sel) { exit 1 }
    $modelId = ($sel.Split([char]0x7C))[0]
    $maxCtx = [int](($sel.Split([char]0x7C))[1])
    Write-Host ''
    Write-Host "Selected: $modelId (max $maxCtx tokens)"
    Write-Host ''
    if ($script:CurrentBackend -eq 'lmstudio') {
      $loaded = Get-LoadedLmStudioModel $apiBase
      if ($loaded) {
        $pk = $loaded.Split([char]0x7C)
        if ($pk[0] -eq $modelId) {
          $cur = [int]$pk[1]
          $contextLength = Select-ContextLength -ModelKey $modelId -MaxCtx $maxCtx -CurrentCtx $cur
          if ($contextLength -eq $cur) { $skipLoad = $true }
        } else {
          $contextLength = Select-ContextLength -ModelKey $modelId -MaxCtx $maxCtx
        }
      } else {
        $contextLength = Select-ContextLength -ModelKey $modelId -MaxCtx $maxCtx
      }
      Write-Host ''
      Write-Host "Context length: $contextLength"
      Write-Host ''
    } else {
      $contextLength = $maxCtx
    }
  }

  if ($dry) {
    Write-Host "[dry-run] Would configure $modelId, write $Script:ClaudeSettings"
    exit 0
  }

  if ($script:CurrentBackend -eq 'lmstudio') {
    if ($skipLoad) {
      Write-Host "  Using already-loaded model $modelId with context $contextLength (no reload)."
    } else {
      Write-Host 'Loading model in LM Studio...'
      if (-not (Load-LmStudioModel -ModelKey $modelId -ContextLength $contextLength -ApiBase $apiBase)) {
        Write-Host 'Model load failed. Check LM Studio logs (memory, missing file).' -ForegroundColor Red
        exit 1
      }
    }
  } else {
    Write-Host "  Using model: $modelId (no load step for $($script:CurrentBackend))."
  }

  $effectiveBase = $script:CurrentBaseUrl
  if ($script:CurrentBackend -eq 'newapi') {
    $effectiveBase = "$($script:CurrentBaseUrl.TrimEnd('/'))/v1"
  }

  Save-LastModelPrefs $modelId $contextLength
  Write-Host 'Writing config...'
  Write-SettingsJson -ModelId $modelId -BaseUrl $effectiveBase -AuthToken $script:CurrentAuth -ApiKey $script:CurrentApiKey -Backend $script:CurrentBackend
  Set-VerifyEnv -ModelId $modelId -BaseUrl $effectiveBase -AuthToken $script:CurrentAuth -ApiKey $script:CurrentApiKey -Backend $script:CurrentBackend

  Write-Host ''
  Write-Host 'Model is ready. VS Code / Cursor: map claudeCode.environmentVariables to the same values as in settings.json env.'
  if ($script:CurrentBackend -eq 'nvidia') {
    Write-Host ''
    Write-Host '  NVIDIA: if Claude reports model/access errors, integrate.api is not an Anthropic Messages endpoint - use a proxy or switch backend.' -ForegroundColor DarkYellow
  }
  Write-Host ''

  if ($bypass) {
    Write-Host "Config written. Run: claude --model $modelId"
    exit 0
  }

  $start = 'y'
  if (-not $lastMode) {
    $start = Read-Host 'Start Claude Code in this window now? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($start)) { $start = 'y' }
  }
  if ($start -match '^(n|no)$') {
    Write-Host "Skipped. Run: claude --model $modelId"
    exit 0
  }

  Ensure-ClaudePath
  $claudeExe = Get-ClaudeExePath
  if (-not $claudeExe) {
    Write-Host 'claude.exe not found after setup.'
    exit 1
  }
  Write-Host 'Starting Claude Code...'
  Write-Host ''
  $keep = (Get-KeepSessionOnExit) -eq 'true'
  if ($keep) {
    & $claudeExe --model $modelId
  } else {
    & $claudeExe --model $modelId
  }
}

# Entry: support -File (RemainingArguments), direct .\claudius.ps1 (@args), and claudius.bat (%*)
$cliArgs = @()
if ($RemainingArguments -and $RemainingArguments.Count -gt 0) {
  $cliArgs = @($RemainingArguments)
} elseif ($args -and $args.Count -gt 0) {
  $cliArgs = @($args)
}
Main -ArgsRemaining $cliArgs
