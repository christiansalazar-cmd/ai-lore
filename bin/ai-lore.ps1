<#
.SYNOPSIS
  ai-lore --- install shared AI assets (skills, MCP servers, rules) into the current
  project's .cursor/ folder. Native Windows PowerShell twin of bin/ai-lore (bash).

.DESCRIPTION
  No external dependencies: uses built-in PowerShell JSON and menus.
  Run from inside one of your projects:  ai-lore setup
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Command = "setup",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

# --- Resolve repo home (parent of bin/) -------------------------------------
$ScriptDir = Split-Path -Parent $PSCommandPath
$AiLoreHome = if ($env:AI_LORE_HOME) { $env:AI_LORE_HOME } else { Split-Path -Parent $ScriptDir }

# Where 'ai-lore add' writes copies. Defaults to the library; the add flow points
# this at a temporary git worktree so the user's checkout is never touched.
$script:DestRoot = $AiLoreHome

# --- Catalog discovery -------------------------------------------------------
function Get-Skills {
  $root = Join-Path $AiLoreHome "skills"
  if (-not (Test-Path $root)) { return @() }
  Get-ChildItem -Path $root -Recurse -Filter "SKILL.md" -File | ForEach-Object {
    $dir = $_.Directory.FullName
    $rel = $dir.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
    [pscustomobject]@{ Label = $rel; Path = $dir; Leaf = Split-Path -Leaf $dir }
  } | Sort-Object Label
}

function Get-Mcps {
  $root = Join-Path $AiLoreHome "mcps"
  if (-not (Test-Path $root)) { return @() }
  Get-ChildItem -Path $root -Recurse -Filter "mcp.template.json" -File | ForEach-Object {
    $dir = $_.Directory.FullName
    [pscustomobject]@{ Label = (Split-Path -Leaf $dir); Path = $_.FullName }
  } | Sort-Object Label
}

function Get-Rules {
  $root = Join-Path $AiLoreHome "rules"
  if (-not (Test-Path $root)) { return @() }
  Get-ChildItem -Path $root -Recurse -Filter "*.mdc" -File | ForEach-Object {
    [pscustomobject]@{ Label = $_.Name; Path = $_.FullName }
  } | Sort-Object Label
}

# --- Selection UI (Out-GridView if available, else numbered prompt) ----------
function Select-ItemsNumbered {
  param([string]$Title, [object[]]$Items, [switch]$Multi)
  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan
  for ($i = 0; $i -lt $Items.Count; $i++) {
    Write-Host ("  {0}) {1}" -f ($i + 1), $Items[$i].Label)
  }
  if ($Multi) {
    $raw = (Read-Host "Choose multiple (e.g. 1,3 or 'all', blank to skip)").Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    if ($raw.ToLower() -eq "all") { return $Items }
    $picked = @()
    foreach ($tok in ($raw -split '[,\s]+')) {
      if ($tok -match '^\d+$') {
        $n = [int]$tok
        if ($n -ge 1 -and $n -le $Items.Count) { $picked += $Items[$n - 1] }
      }
    }
    return $picked
  }
  else {
    $raw = (Read-Host "Choose [1-$($Items.Count)] (blank to cancel)").Trim()
    if ($raw -match '^\d+$') {
      $n = [int]$raw
      if ($n -ge 1 -and $n -le $Items.Count) { return @($Items[$n - 1]) }
    }
    return @()
  }
}

# Turn on ANSI/VT escape processing so we can redraw the menu in place
# (works in Cursor's terminal, Windows Terminal, ConPTY). Cached after first call.
$script:AnsiReady = $null
function Enable-Ansi {
  if ($null -ne $script:AnsiReady) { return $script:AnsiReady }
  $script:AnsiReady = $false
  try {
    if (-not ('AiLore.VT' -as [type])) {
      Add-Type -Namespace AiLore -Name VT -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@ -ErrorAction Stop
    }
    $h = [AiLore.VT]::GetStdHandle(-11)
    $mode = [uint32]0
    if ([AiLore.VT]::GetConsoleMode($h, [ref]$mode)) {
      [void][AiLore.VT]::SetConsoleMode($h, $mode -bor 0x0004)
      $script:AnsiReady = $true
    }
  }
  catch { $script:AnsiReady = $false }
  return $script:AnsiReady
}

# In-terminal arrow-key menu. Draws the list ONCE, then redraws only the list
# rows in place on each keypress (no stacking, no full-menu regeneration).
function Show-ConsoleMenu {
  param([string]$Title, [object[]]$Items, [switch]$Multi)
  $esc = [char]27
  $selected = @{}
  $idx = 0
  $n = $Items.Count

  Write-Host ""
  Write-Host "  $Title" -ForegroundColor Cyan
  if ($Multi) {
    Write-Host "  up/down move - space toggle - a all - enter/ctrl+s save - esc cancel" -ForegroundColor DarkGray
  }
  else {
    Write-Host "  up/down move - enter select - esc cancel" -ForegroundColor DarkGray
  }

  # Render one row's text (with selection marker / checkbox), padded/trimmed to width.
  $renderRow = {
    param($i)
    $pointer = if ($i -eq $idx) { '>' } else { ' ' }
    $box = ''
    if ($Multi) { $box = if ($selected.ContainsKey($i)) { '[x] ' } else { '[ ] ' } }
    $text = "   $pointer $box$($Items[$i].Label)"
    $width = [Math]::Max(1, [Console]::WindowWidth - 1)
    if ($text.Length -gt $width) { $text = $text.Substring(0, $width) } else { $text = $text.PadRight($width) }
    return $text
  }

  $prevVis = $true
  try { $prevVis = [Console]::CursorVisible } catch {}
  try { [Console]::CursorVisible = $false } catch {}

  # Initial full draw of the list rows.
  for ($i = 0; $i -lt $n; $i++) {
    $row = & $renderRow $i
    if ($i -eq $idx) { Write-Host $row -ForegroundColor Black -BackgroundColor Cyan } else { Write-Host $row }
  }

  try {
    while ($true) {
      $key = [Console]::ReadKey($true)
      $done = $false
      switch ($key.Key) {
        'UpArrow' { $idx = ($idx - 1 + $n) % $n }
        'DownArrow' { $idx = ($idx + 1) % $n }
        'Spacebar' {
          if ($Multi) {
            if ($selected.ContainsKey($idx)) { $selected.Remove($idx) | Out-Null } else { $selected[$idx] = $true }
          }
        }
        'Enter' { $done = $true }
        'Escape' { $selected = @{}; $idx = -1; $done = $true }
        default {
          if ($Multi) {
            if ($key.KeyChar -eq 'a' -or $key.KeyChar -eq 'A') {
              if ($selected.Count -eq $n) { $selected.Clear() } else { for ($i = 0; $i -lt $n; $i++) { $selected[$i] = $true } }
            }
            elseif (($key.Modifiers -band [ConsoleModifiers]::Control) -and $key.Key -eq 'S') { $done = $true }
          }
        }
      }

      if ($done) {
        if ($idx -lt 0 -and -not $Multi) { return @() }                 # Esc on single-select
        if ($Multi) {
          $res = @(); for ($i = 0; $i -lt $n; $i++) { if ($selected.ContainsKey($i)) { $res += $Items[$i] } }
          return $res
        }
        return @($Items[$idx])
      }

      # Redraw only the list rows in place: move cursor up N lines, clear+rewrite each.
      [Console]::Out.Write("$esc[${n}A")
      for ($i = 0; $i -lt $n; $i++) {
        [Console]::Out.Write("$esc[2K")
        $row = & $renderRow $i
        if ($i -eq $idx) { Write-Host $row -ForegroundColor Black -BackgroundColor Cyan } else { Write-Host $row }
      }
    }
  }
  finally {
    try { [Console]::CursorVisible = $prevVis } catch {}
  }
}

function Select-Items {
  param([string]$Title, [object[]]$Items, [switch]$Multi)
  if (-not $Items -or $Items.Count -eq 0) { return @() }

  # Use the arrow-key TUI only with a real interactive console; otherwise numbered.
  $interactive = $true
  try {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { $interactive = $false }
  }
  catch { $interactive = $false }

  if ($interactive -and (Enable-Ansi)) {
    try {
      return (Show-ConsoleMenu -Title $Title -Items $Items -Multi:$Multi)
    }
    catch {
      # Any console issue (odd host, etc.) -> safe fallback.
      return (Select-ItemsNumbered -Title $Title -Items $Items -Multi:$Multi)
    }
  }
  return (Select-ItemsNumbered -Title $Title -Items $Items -Multi:$Multi)
}

function Confirm-Action {
  param([string]$Prompt)
  $ans = (Read-Host "$Prompt [y/N]").Trim()
  return ($ans -match '^(y|yes)$')
}

# Ask "install all" vs "select", then return the chosen catalog items.
function Resolve-Selection {
  param([string]$Noun, [object[]]$Items)
  if (-not $Items -or $Items.Count -eq 0) { return @() }
  $mode = @(Select-Items -Title "$Noun" -Items @(
      [pscustomobject]@{ Label = "Install all $Noun"; Action = "all" },
      [pscustomobject]@{ Label = "Select $Noun individually"; Action = "select" },
      [pscustomobject]@{ Label = "Back"; Action = "back" }
    ))
  $action = if ($mode.Count -gt 0) { $mode[0].Action } else { "back" }
  switch ($action) {
    "all" { return $Items }
    "select" { return @(Select-Items -Title "Select $Noun" -Items $Items -Multi) }
    default { return @() }
  }
}

# --- Native JSON helpers (no Python, works on Windows PowerShell 5.1) --------
function ConvertTo-OrderedHashtable {
  param($InputObject)
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $h = [ordered]@{}
    foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-OrderedHashtable $InputObject[$k] }
    return $h
  }
  if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-OrderedHashtable $p.Value }
    return $h
  }
  if ($InputObject -is [object[]]) {
    return @($InputObject | ForEach-Object { ConvertTo-OrderedHashtable $_ })
  }
  return $InputObject
}

function Read-McpJson {
  param([string]$Path)
  if (Test-Path $Path) {
    try {
      $obj = Get-Content -Raw -Path $Path | ConvertFrom-Json
      return (ConvertTo-OrderedHashtable $obj)
    }
    catch { return [ordered]@{} }
  }
  return [ordered]@{}
}

function Save-McpJson {
  param([string]$Path, $Data)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  # Write UTF-8 WITHOUT a BOM. Windows PowerShell 5.1's "Set-Content -Encoding UTF8"
  # prepends a BOM, which breaks json.loads (CI) and the Python merge helper.
  $json = ($Data | ConvertTo-Json -Depth 30)
  [System.IO.File]::WriteAllText($Path, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Merge-McpTemplate {
  param([string]$TargetPath, [string]$TemplatePath)
  $data = Read-McpJson $TargetPath
  $tmpl = ConvertTo-OrderedHashtable (Get-Content -Raw -Path $TemplatePath | ConvertFrom-Json)
  if (-not $tmpl.Contains("mcpServers")) {
    Write-Host "  merge: template has no mcpServers: $TemplatePath" -ForegroundColor Yellow
    return @()
  }
  if (-not $data.Contains("mcpServers")) { $data["mcpServers"] = [ordered]@{} }

  $servers = @()
  foreach ($name in $tmpl["mcpServers"].Keys) {
    $newCfg = $tmpl["mcpServers"][$name]
    $existing = $data["mcpServers"][$name]
    if ($existing -is [System.Collections.IDictionary] -and $newCfg -is [System.Collections.IDictionary]) {
      # Preserve non-empty env values the user already filled in.
      if ($existing.Contains("env") -and $newCfg.Contains("env")) {
        foreach ($k in @($existing["env"].Keys)) {
          $v = $existing["env"][$k]
          if (-not [string]::IsNullOrEmpty([string]$v)) { $newCfg["env"][$k] = $v }
        }
      }
    }
    $data["mcpServers"][$name] = $newCfg
    $servers += $name
  }
  Save-McpJson $TargetPath $data
  Write-Host "  merged $($servers.Count) server(s) into $TargetPath"
  return $servers
}

function Read-SecretMasked {
  param([string]$Prompt)
  $sec = Read-Host -AsSecureString -Prompt $Prompt
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Set-McpEnv {
  param([string]$TargetPath, [string]$Server, [string]$Var, [string]$Value)
  $data = Read-McpJson $TargetPath
  if (-not $data.Contains("mcpServers")) { $data["mcpServers"] = [ordered]@{} }
  if (-not ($data["mcpServers"][$Server] -is [System.Collections.IDictionary])) { $data["mcpServers"][$Server] = [ordered]@{} }
  if (-not ($data["mcpServers"][$Server]["env"] -is [System.Collections.IDictionary])) { $data["mcpServers"][$Server]["env"] = [ordered]@{} }
  $data["mcpServers"][$Server]["env"][$Var] = $Value
  Save-McpJson $TargetPath $data
}

function Get-EmptyEnvVars {
  param([string]$TargetPath, [string]$TemplatePath)
  $data = Read-McpJson $TargetPath
  $tmpl = ConvertTo-OrderedHashtable (Get-Content -Raw -Path $TemplatePath | ConvertFrom-Json)
  $out = @()
  foreach ($name in $tmpl["mcpServers"].Keys) {
    $env = $tmpl["mcpServers"][$name]["env"]
    if (-not ($env -is [System.Collections.IDictionary])) { continue }
    foreach ($var in $env.Keys) {
      $cur = $null
      if ($data["mcpServers"] -and $data["mcpServers"][$name] -and $data["mcpServers"][$name]["env"]) {
        $cur = $data["mcpServers"][$name]["env"][$var]
      }
      if ([string]::IsNullOrEmpty([string]$cur)) {
        $out += [pscustomobject]@{ Server = $name; Var = $var }
      }
    }
  }
  return $out
}

function Add-GitignoreLine {
  param([string]$File, [string]$Line)
  $dir = Split-Path -Parent $File
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path $File) {
    $existing = Get-Content -Path $File -ErrorAction SilentlyContinue
    if ($existing -contains $Line) { return }
  }
  Add-Content -Path $File -Value $Line
}

# --- Install actions ---------------------------------------------------------
function Install-Skills {
  param([string]$Target)
  $items = @(Get-Skills)
  if ($items.Count -eq 0) { Write-Host "No skills found."; return }
  $sel = @(Resolve-Selection -Noun "skills" -Items $items)
  if ($sel.Count -eq 0) { Write-Host "No skills selected."; return }
  foreach ($s in $sel) {
    $dest = Join-Path $Target ".cursor\skills\$($s.Leaf)"
    if ((Test-Path $dest) -and -not $Force) {
      if (-not (Confirm-Action "Overwrite existing $($s.Leaf)?")) { Write-Host "  skipped: $dest"; continue }
    }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -Recurse -Force -Path $s.Path -Destination $dest
    Write-Host "  installed: $dest"
  }
}

function Install-Rules {
  param([string]$Target)
  $items = @(Get-Rules)
  if ($items.Count -eq 0) { Write-Host "No rules found."; return }
  $sel = @(Resolve-Selection -Noun "rules" -Items $items)
  if ($sel.Count -eq 0) { Write-Host "No rules selected."; return }
  $destDir = Join-Path $Target ".cursor\rules"
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  foreach ($r in $sel) {
    $dest = Join-Path $destDir $r.Label
    if ((Test-Path $dest) -and -not $Force) {
      if (-not (Confirm-Action "Overwrite existing rule $($r.Label)?")) { Write-Host "  skipped: $dest"; continue }
    }
    Copy-Item -Force -Path $r.Path -Destination $dest
    Write-Host "  installed: $dest"
  }
}

function Install-Mcps {
  param([string]$Target)
  $items = @(Get-Mcps)
  if ($items.Count -eq 0) { Write-Host "No MCP templates found."; return }
  $sel = @(Resolve-Selection -Noun "MCP servers" -Items $items)
  if ($sel.Count -eq 0) { Write-Host "No MCP servers selected."; return }

  $mcpJson = Join-Path $Target ".cursor\mcp.json"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mcpJson) | Out-Null

  foreach ($m in $sel) {
    Merge-McpTemplate -TargetPath $mcpJson -TemplatePath $m.Path | Out-Null
    $needs = @(Get-EmptyEnvVars -TargetPath $mcpJson -TemplatePath $m.Path)
    if ($needs.Count -eq 0) {
      Write-Host "  $($m.Label): no key needed - ready to go." -ForegroundColor DarkGray
      continue
    }
    foreach ($need in $needs) {
      Write-Host "  MCP '$($need.Server)' needs $($need.Var)."
      if (Confirm-Action "    Enter a value for $($need.Var) now?") {
        $secret = Read-SecretMasked -Prompt "    $($need.Var) (hidden)"
        if (-not [string]::IsNullOrEmpty($secret)) {
          Set-McpEnv -TargetPath $mcpJson -Server $need.Server -Var $need.Var -Value $secret
          Write-Host "    set $($need.Var) for $($need.Server)."
        }
        else { Write-Host "    left empty; fill it in later in .cursor\mcp.json." }
      }
      else { Write-Host "    left empty; fill it in later in .cursor\mcp.json." }
    }
  }
  Add-GitignoreLine -File (Join-Path $Target ".gitignore") -Line ".cursor/mcp.json"
  Write-Host "  note: added .cursor/mcp.json to .gitignore (contains keys)"
}

# --- Contribute back (ai-lore add) -------------------------------------------
function Get-ProjectSkills {
  param([string]$Target)
  $root = Join-Path $Target ".cursor\skills"
  if (-not (Test-Path $root)) { return @() }
  Get-ChildItem -Path $root -Recurse -Filter "SKILL.md" -File | ForEach-Object {
    $dir = $_.Directory.FullName
    [pscustomobject]@{ Label = (Split-Path -Leaf $dir); Path = $dir }
  } | Sort-Object Label
}

function Get-ProjectRules {
  param([string]$Target)
  $root = Join-Path $Target ".cursor\rules"
  if (-not (Test-Path $root)) { return @() }
  Get-ChildItem -Path $root -Recurse -Filter "*.mdc" -File | ForEach-Object {
    [pscustomobject]@{ Label = $_.Name; Path = $_.FullName }
  } | Sort-Object Label
}

function Get-ProjectMcps {
  param([string]$Target)
  $mcpJson = Join-Path $Target ".cursor\mcp.json"
  if (-not (Test-Path $mcpJson)) { return @() }
  $data = Read-McpJson $mcpJson
  if (-not $data.Contains("mcpServers")) { return @() }
  @($data["mcpServers"].Keys) | Sort-Object | ForEach-Object {
    [pscustomobject]@{ Label = $_ }
  }
}

# Write one server block as a standalone template with all env values blanked.
function Export-ServerTemplate {
  param([string]$SourceMcpJson, [string]$Server, [string]$OutTemplate)
  $data = Read-McpJson $SourceMcpJson
  if (-not $data.Contains("mcpServers") -or -not $data["mcpServers"].Contains($Server)) {
    return $false
  }
  $cfg = $data["mcpServers"][$Server]
  if ($cfg["env"] -is [System.Collections.IDictionary]) {
    foreach ($k in @($cfg["env"].Keys)) { $cfg["env"][$k] = "" }
  }
  $out = [ordered]@{ mcpServers = [ordered]@{ $Server = $cfg } }
  Save-McpJson $OutTemplate $out
  return $true
}

# Returns $true if it actually wrote a change, $false if skipped/identical.
function Copy-IntoLibrary {
  param([string]$Src, [string]$Dest)
  $rel = $Dest
  if ($Dest.StartsWith($script:DestRoot)) { $rel = $Dest.Substring($script:DestRoot.Length).TrimStart('\', '/') }
  if (Test-Path $Dest) {
    if (Test-Identical -Src $Src -Dest $Dest) {
      Write-Host "  already up to date: $rel" -ForegroundColor DarkGray
      return $false
    }
    if (-not $Force) {
      if (-not (Confirm-Action "Overwrite existing $rel in the library?")) {
        Write-Host "  skipped: $rel"
        return $false
      }
    }
    Remove-Item -Recurse -Force $Dest
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
  Copy-Item -Recurse -Force -Path $Src -Destination $Dest
  Write-Host "  added: $rel" -ForegroundColor Green
  return $true
}

function Test-Identical {
  param([string]$Src, [string]$Dest)
  if ((Test-Path $Src -PathType Container) -ne (Test-Path $Dest -PathType Container)) { return $false }
  if (Test-Path $Src -PathType Container) {
    $a = Get-ChildItem -Recurse -File $Src | Sort-Object FullName
    $b = Get-ChildItem -Recurse -File $Dest | Sort-Object FullName
    if ($a.Count -ne $b.Count) { return $false }
    for ($i = 0; $i -lt $a.Count; $i++) {
      $ra = $a[$i].FullName.Substring($Src.Length)
      $rb = $b[$i].FullName.Substring($Dest.Length)
      if ($ra -ne $rb) { return $false }
      if ((Get-FileHash $a[$i].FullName).Hash -ne (Get-FileHash $b[$i].FullName).Hash) { return $false }
    }
    return $true
  }
  return ((Get-FileHash $Src).Hash -eq (Get-FileHash $Dest).Hash)
}

function Add-ProjectSkills {
  param([string]$Target, [System.Collections.ArrayList]$Names)
  $items = @(Get-ProjectSkills -Target $Target)
  if ($items.Count -eq 0) { Write-Host "No skills in $Target\.cursor\skills."; return }
  $sel = @(Select-Items -Title "Select skills to contribute" -Items $items -Multi)
  if ($sel.Count -eq 0) { Write-Host "No skills selected."; return }
  foreach ($s in $sel) {
    if (Copy-IntoLibrary -Src $s.Path -Dest (Join-Path $script:DestRoot "skills\$($s.Label)")) {
      [void]$Names.Add($s.Label)
    }
  }
}

function Add-ProjectRules {
  param([string]$Target, [System.Collections.ArrayList]$Names)
  $items = @(Get-ProjectRules -Target $Target)
  if ($items.Count -eq 0) { Write-Host "No rules in $Target\.cursor\rules."; return }
  $sel = @(Select-Items -Title "Select rules to contribute" -Items $items -Multi)
  if ($sel.Count -eq 0) { Write-Host "No rules selected."; return }
  foreach ($r in $sel) {
    if (Copy-IntoLibrary -Src $r.Path -Dest (Join-Path $script:DestRoot "rules\$($r.Label)")) {
      [void]$Names.Add($r.Label)
    }
  }
}

function Add-ProjectMcps {
  param([string]$Target, [System.Collections.ArrayList]$Names)
  $items = @(Get-ProjectMcps -Target $Target)
  if ($items.Count -eq 0) { Write-Host "No MCP servers in $Target\.cursor\mcp.json."; return }
  $sel = @(Select-Items -Title "Select MCP servers to contribute (keys are stripped)" -Items $items -Multi)
  if ($sel.Count -eq 0) { Write-Host "No MCP servers selected."; return }
  $mcpJson = Join-Path $Target ".cursor\mcp.json"
  foreach ($m in $sel) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
      if (Export-ServerTemplate -SourceMcpJson $mcpJson -Server $m.Label -OutTemplate $tmp) {
        $dest = Join-Path $script:DestRoot "mcps\$($m.Label)\mcp.template.json"
        if (Copy-IntoLibrary -Src $tmp -Dest $dest) { [void]$Names.Add($m.Label) }
      }
      else { Write-Host "  could not extract server: $($m.Label)" }
    }
    finally { Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
  }
}

function Get-GitDefaultBranch {
  $ref = (git -C $AiLoreHome symbolic-ref --quiet refs/remotes/origin/HEAD 2>$null)
  if ($ref) { return ($ref -replace '^refs/remotes/origin/', '') }
  $cur = (git -C $AiLoreHome rev-parse --abbrev-ref HEAD 2>$null)
  if ($cur) { return $cur }
  return "main"
}

function Test-HasOrigin {
  git -C $AiLoreHome remote get-url origin *> $null
  return ($LASTEXITCODE -eq 0)
}

function Test-GhReady {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $false }
  gh auth status *> $null
  return ($LASTEXITCODE -eq 0)
}

function Get-RepoSlug {
  $url = (git -C $AiLoreHome remote get-url origin 2>$null)
  if (-not $url) { return "" }
  $url = $url -replace '\.git$', ''
  if ($url -match 'github\.com[:/](.+)$') { return $Matches[1] }
  return ""
}

function ConvertTo-Slug {
  param([string]$Text)
  $s = ($Text.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
  if ([string]::IsNullOrEmpty($s)) { return "project" }
  return $s
}

function Invoke-Add {
  # git/gh write progress to stderr; with ErrorActionPreference=Stop that would
  # crash the run. We check $LASTEXITCODE explicitly instead, so relax it here
  # (dynamically scoped, so the git helper functions below inherit it too).
  $ErrorActionPreference = 'Continue'
  $target = (Get-Location).Path
  $homeResolved = (Resolve-Path $AiLoreHome).Path
  if ($target -eq $homeResolved -or $target.StartsWith($homeResolved + [IO.Path]::DirectorySeparatorChar)) {
    Write-Host "Refusing to run inside the ai-lore source repo." -ForegroundColor Red
    Write-Host "cd into one of your projects first, then run: ai-lore add"
    return
  }
  if (-not (Test-Path (Join-Path $AiLoreHome ".git"))) {
    Write-Host "ai-lore library at $AiLoreHome is not a git repo; cannot open a PR." -ForegroundColor Red
    return
  }
  if (-not (Test-Path (Join-Path $target ".cursor"))) {
    Write-Host "No .cursor/ folder here. Nothing to contribute from $target." -ForegroundColor Red
    return
  }

  Write-Host "`n== ai-lore add ==" -ForegroundColor Cyan
  Write-Host "Project: $target"
  Write-Host "Library: $AiLoreHome"

  $projectName = Split-Path -Leaf $target
  git -C $AiLoreHome fetch origin --quiet 2>$null
  $defaultBranch = Get-GitDefaultBranch
  $hasOrigin = Test-HasOrigin
  $base = "HEAD"
  if ($hasOrigin) {
    git -C $AiLoreHome rev-parse --verify --quiet "origin/$defaultBranch" *> $null
    if ($LASTEXITCODE -eq 0) { $base = "origin/$defaultBranch" }
  }
  $branch = "contrib/$(ConvertTo-Slug $projectName)-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
  $worktree = Join-Path ([IO.Path]::GetTempPath()) ("ailore_wt_" + [guid]::NewGuid().ToString("N"))

  git -C $AiLoreHome worktree add -b $branch $worktree $base *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Could not create a temporary worktree for the contribution." -ForegroundColor Red
    return
  }

  $names = New-Object System.Collections.ArrayList
  $prevDest = $script:DestRoot
  $script:DestRoot = $worktree
  try {
    while ($true) {
      $action = @(Select-Items -Title "What do you want to contribute back to ai-lore?" -Items @(
          [pscustomobject]@{ Label = "Skills" },
          [pscustomobject]@{ Label = "Rules" },
          [pscustomobject]@{ Label = "MCP servers" },
          [pscustomobject]@{ Label = "Done" }
        ))
      $choice = if ($action.Count -gt 0) { $action[0].Label } else { "Done" }
      switch ($choice) {
        "Skills" { Add-ProjectSkills -Target $target -Names $names }
        "Rules" { Add-ProjectRules -Target $target -Names $names }
        "MCP servers" { Add-ProjectMcps -Target $target -Names $names }
        default { break }
      }
      if ($choice -eq "Done") { break }
    }

    if ($names.Count -eq 0) {
      Write-Host "`nNothing new to contribute."
      return
    }

    $joined = ($names -join ", ")
    $msg = "add: $joined from $projectName"
    Write-Host "`nStaged additions: $joined"
    if (-not (Confirm-Action "Open a pull request to contribute these to ai-lore?")) {
      Write-Host "Cancelled. Nothing was pushed."
      return
    }

    git -C $worktree add -A
    git -C $worktree commit -m $msg | Out-Null
    Write-Host "Committed on branch $branch." -ForegroundColor Green

    if (-not $hasOrigin) {
      Write-Host "`nNo 'origin' remote, so nothing was pushed."
      Write-Host "The contribution is on local branch '$branch' in $AiLoreHome."
      return
    }

    git -C $worktree push -u origin $branch *> $null
    if ($LASTEXITCODE -ne 0) {
      Write-Host "`nPush failed (check your git credentials)." -ForegroundColor Yellow
      Write-Host "Retry with: git -C `"$AiLoreHome`" push -u origin $branch"
      return
    }
    Write-Host "Pushed $branch to origin."

    $prBody = "Contributed via 'ai-lore add' from project '$projectName'.`n`nAdds: $joined`n`nMCP API keys were stripped before commit."
    if (Test-GhReady) {
      Push-Location $worktree
      try {
        $prUrl = (gh pr create --base $defaultBranch --head $branch --title $msg --body $prBody 2>$null)
        if ($prUrl) {
          Write-Host "Pull request opened: $prUrl" -ForegroundColor Green
          # Try to enable auto-merge so the PR merges itself once CI passes. Needs
          # "Allow auto-merge" enabled on the repo; harmless no-op otherwise.
          gh pr merge $prUrl --auto --squash *> $null
          if ($LASTEXITCODE -eq 0) {
            Write-Host "Auto-merge enabled: it will merge once checks pass."
          }
          else {
            Write-Host "Auto-merge not enabled (turn on 'Allow auto-merge' in repo settings); merge it manually after checks pass." -ForegroundColor Yellow
          }
        }
      }
      finally { Pop-Location }
      if ($prUrl) { return }
      Write-Host "Branch pushed, but 'gh pr create' did not return a URL. Open it manually below." -ForegroundColor Yellow
    }

    $slug = Get-RepoSlug
    Write-Host "`nOpen a pull request:"
    if ($slug) {
      Write-Host "  https://github.com/$slug/compare/$defaultBranch...$branch`?expand=1"
    }
    Write-Host "  or run: gh pr create --base $defaultBranch --head $branch --fill"
  }
  finally {
    $script:DestRoot = $prevDest
    git -C $AiLoreHome worktree remove --force $worktree *> $null
    if (Test-Path $worktree) { Remove-Item -Recurse -Force $worktree -ErrorAction SilentlyContinue }
  }
}

# --- Subcommands -------------------------------------------------------------
function Invoke-List {
  Write-Host "`n== Skills ==" -ForegroundColor Cyan
  Get-Skills | ForEach-Object { Write-Host "  - $($_.Label)" }
  Write-Host "`n== MCP servers ==" -ForegroundColor Cyan
  Get-Mcps | ForEach-Object { Write-Host "  - $($_.Label)" }
  Write-Host "`n== Rules ==" -ForegroundColor Cyan
  Get-Rules | ForEach-Object { Write-Host "  - $($_.Label)" }
}

function Invoke-Setup {
  $target = (Get-Location).Path
  $homeResolved = (Resolve-Path $AiLoreHome).Path
  if ($target -eq $homeResolved -or $target.StartsWith($homeResolved + [IO.Path]::DirectorySeparatorChar)) {
    Write-Host "Refusing to run inside the ai-lore source repo." -ForegroundColor Red
    Write-Host "cd into one of your projects first, then run: ai-lore setup"
    return
  }

  Write-Host "`n== ai-lore setup ==" -ForegroundColor Cyan
  Write-Host "Source : $AiLoreHome"
  Write-Host "Project: $target"
  Write-Host "Targets: $target\.cursor\{skills, mcp.json, rules}"

  while ($true) {
    $action = @(Select-Items -Title "What do you want to install into this project?" -Items @(
        [pscustomobject]@{ Label = "Skills" },
        [pscustomobject]@{ Label = "MCP servers" },
        [pscustomobject]@{ Label = "Rules" },
        [pscustomobject]@{ Label = "Done" }
      ))
    $choice = if ($action.Count -gt 0) { $action[0].Label } else { "Done" }
    switch ($choice) {
      "Skills" { Install-Skills -Target $target }
      "MCP servers" { Install-Mcps -Target $target }
      "Rules" { Install-Rules -Target $target }
      default { break }
    }
    if ($choice -eq "Done") { break }
  }

  Write-Host "`nDone. Reload Cursor to pick up changes in $target\.cursor\." -ForegroundColor Green
}

function Show-Usage {
  @"
ai-lore - install shared AI assets into the current project (Cursor).

Usage:
  ai-lore setup [-Force]   Interactive install into the current folder's .cursor (default)
  ai-lore add [-Force]     Contribute this project's skills/rules/MCPs back to ai-lore
  ai-lore list             Show available skills, MCP servers, and rules
  ai-lore help             Show this help

Notes:
  - Run 'ai-lore setup' from inside one of your projects (not the ai-lore repo).
  - 'ai-lore add' copies from this project's .cursor\ into the ai-lore library and
    auto-commits. MCP keys are stripped before they are written.
  - Files are COPIED, so your projects keep working if ai-lore moves or updates.
  - MCP API keys go into .cursor\mcp.json and are gitignored automatically.

AI_LORE_HOME = $AiLoreHome
"@ | Write-Host
}

switch ($Command.ToLower()) {
  "setup" { Invoke-Setup }
  "add" { Invoke-Add }
  "list" { Invoke-List }
  "help" { Show-Usage }
  "-h" { Show-Usage }
  "--help" { Show-Usage }
  default { Write-Host "Unknown command: $Command" -ForegroundColor Red; Show-Usage }
}
