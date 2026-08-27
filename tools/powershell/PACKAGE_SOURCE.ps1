. "$PSScriptRoot\COMMON.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Get-ProjectRoot
$builds = Join-Path $root 'builds'
New-Item -ItemType Directory -Path $builds -Force | Out-Null

$staging = Join-Path $builds ('source_staging_' + [Guid]::NewGuid().ToString('N'))
$zip = Join-Path $builds 'SD_STORY_RPG_SOURCE.zip'
$zipTemporary = Join-Path $builds ('SD_STORY_RPG_SOURCE_' + [Guid]::NewGuid().ToString('N') + '.tmp')

$sourceEntries = @(
    'godot',
    'data_source',
    'tools',
    'docs',
    'tests',
    'reports',
    'README.md',
    'WORKLOG.md',
    'CHANGELOG.md',
    '.gitignore'
)

# Runtime/source files are retained. Local caches, review/reference media, render
# intermediates, credentials and nested packages are never source-package input.
$excludedDirectoryNames = @(
    '.cache',
    '.godot',
    '.mypy_cache',
    '.pytest_cache',
    '.ruff_cache',
    '.runtime_profile',
    '__pycache__',
    'browser_logs',
    'cache',
    'contact_sheets',
    'contact_sheets_r5',
    'export_templates',
    'intermediate',
    'intermediates',
    'logs',
    'mvp_video_reference',
    'node_modules',
    'placeholders_legacy',
    'reference_cache',
    'render_logs',
    'renders',
    'script_templates',
    'screenshots',
    'temp',
    'tmp',
    'video'
)

$excludedExtensions = @(
    '.7z',
    '.bak',
    '.blend',
    '.blend1',
    '.exr',
    '.gz',
    '.kdbx',
    '.key',
    '.kra',
    '.log',
    '.p12',
    '.pdb',
    '.pem',
    '.pfx',
    '.psd',
    '.pyc',
    '.pyo',
    '.rar',
    '.tar',
    '.temp',
    '.tmp',
    '.zip'
)

$secretFilePatterns = @(
    '.env',
    '.env.*',
    '*credential*.json',
    '*secret*.json',
    'id_ed25519',
    'id_rsa',
    '*.keystore'
)

$textExtensions = @(
    '', '.cfg', '.csv', '.css', '.gd', '.gitignore', '.godot', '.html',
    '.ini', '.js', '.json', '.md', '.ps1', '.psm1', '.py', '.toml',
    '.tres', '.ts', '.tscn', '.txt', '.xml', '.yaml', '.yml'
)

# These expressions deliberately match concrete local filesystem locations, not
# res://, user://, URLs, environment-variable references or neutral placeholders.
$personalPathPatterns = @(
    '(?<![A-Za-z0-9_])(?:[A-Za-z]:[\\/])(?:[^`"''\r\n<>|]+)',
    '(?<![:\\/])(?:\\\\|//)[^\\/\s]+[\\/][^\\/\s]+(?:[\\/][^`"''\r\n<>|]+)?',
    '(?<![:A-Za-z0-9_])/(?:Users|home|mnt|Volumes)/[^`"''\r\n<>|]+'
)

$secretContentPatterns = @(
    '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    '(?i)\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{25,}|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|hf_[A-Za-z0-9]{20,})\b',
    '(?im)^\s*(?:api[_-]?key|secret(?:_key)?|access[_-]?token|auth[_-]?token|password|passwd|client[_-]?secret|private[_-]?key)\s*[:=]\s*["'']?(?!\$\{?|%|\$env:|<|REPLACE|CHANGE|YOUR_|EXAMPLE|NONE|NULL)[A-Za-z0-9+/_=-]{20,}'
)

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )
    $candidateFull = Get-NormalizedFullPath -Path $Candidate
    $parentFull = (Get-NormalizedFullPath -Path $Parent) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidateFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped the permitted staging root: $candidateFull"
    }
}

function Test-SecretFileName {
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($pattern in $secretFilePatterns) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Test-TextFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $leaf = [System.IO.Path]::GetFileName($Path)
    if ($leaf -eq '.gitignore') { return $true }
    return $textExtensions -contains ([System.IO.Path]::GetExtension($Path).ToLowerInvariant())
}

function Assert-NoSecretContent {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Location
    )
    foreach ($pattern in $secretContentPatterns) {
        if ([System.Text.RegularExpressions.Regex]::IsMatch($Content, $pattern)) {
            throw "Potential credential/API key found in source package content: $Location"
        }
    }
}

function Assert-NoPersonalPathContent {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Location
    )
    foreach ($pattern in $personalPathPatterns) {
        if ([System.Text.RegularExpressions.Regex]::IsMatch($Content, $pattern)) {
            throw "Personal absolute path found in source package content: $Location"
        }
    }
}

function Remove-ExcludedStagingContent {
    param([Parameter(Mandatory = $true)][string]$StagingRoot)

    $removedDirectories = 0
    $removedFiles = 0

    Get-ChildItem -LiteralPath $StagingRoot -Directory -Recurse -Force |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if ($excludedDirectoryNames -contains $_.Name) {
                Assert-ChildPath -Candidate $_.FullName -Parent $StagingRoot
                Remove-Item -LiteralPath $_.FullName -Recurse -Force
                $removedDirectories++
            }
        }

    Get-ChildItem -LiteralPath $StagingRoot -File -Recurse -Force | ForEach-Object {
        $extension = $_.Extension.ToLowerInvariant()
        $remove = ($excludedExtensions -contains $extension) -or (Test-SecretFileName -Name $_.Name)

        # Reports remain useful as source evidence, but review captures/reference
        # media are generated artifacts and must not inflate or leak into source.
        $relative = $_.FullName.Substring($StagingRoot.Length).TrimStart('\', '/')
        if ($relative.StartsWith('reports\', [System.StringComparison]::OrdinalIgnoreCase) -and
            $extension -in @('.avi', '.bmp', '.gif', '.jpeg', '.jpg', '.mkv', '.mov', '.mp4', '.png', '.webm', '.webp')) {
            $remove = $true
        }

        if ($remove) {
            Assert-ChildPath -Candidate $_.FullName -Parent $StagingRoot
            Remove-Item -LiteralPath $_.FullName -Force
            $removedFiles++
        }
    }

    return [pscustomobject]@{
        Directories = $removedDirectories
        Files = $removedFiles
    }
}

function Sanitize-And-ValidateStagingText {
    param([Parameter(Mandatory = $true)][string]$StagingRoot)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $changedFiles = 0
    $redactedPaths = 0

    Get-ChildItem -LiteralPath $StagingRoot -File -Recurse -Force | ForEach-Object {
        if (-not (Test-TextFile -Path $_.FullName)) { return }

        $content = [System.IO.File]::ReadAllText($_.FullName)
        Assert-NoSecretContent -Content $content -Location $_.FullName
        $sanitized = $content
        foreach ($pattern in $personalPathPatterns) {
            $matches = [System.Text.RegularExpressions.Regex]::Matches($sanitized, $pattern).Count
            if ($matches -gt 0) {
                $redactedPaths += $matches
                $sanitized = [System.Text.RegularExpressions.Regex]::Replace($sanitized, $pattern, '<LOCAL_PATH_REMOVED>')
            }
        }
        if ($sanitized -cne $content) {
            [System.IO.File]::WriteAllText($_.FullName, $sanitized, $utf8NoBom)
            $changedFiles++
        }
        Assert-NoPersonalPathContent -Content $sanitized -Location $_.FullName
    }

    return [pscustomobject]@{
        ChangedFiles = $changedFiles
        RedactedPaths = $redactedPaths
    }
}

function Assert-ZipIsSafe {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $entryPath = $entry.FullName.Replace('\', '/')
            if ($entryPath.StartsWith('/') -or $entryPath -match '(^|/)\.\.(/|$)' -or $entryPath -match '^[A-Za-z]:') {
                throw "Unsafe absolute/traversal ZIP entry: $entryPath"
            }

            $segments = $entryPath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
            foreach ($segment in $segments) {
                if ($excludedDirectoryNames -contains $segment) {
                    throw "Excluded cache/reference/intermediate directory found in ZIP: $entryPath"
                }
            }

            $leaf = if ($segments.Count -gt 0) { $segments[$segments.Count - 1] } else { '' }
            if ([string]::IsNullOrEmpty($leaf)) { continue }
            $extension = [System.IO.Path]::GetExtension($leaf).ToLowerInvariant()
            if (($excludedExtensions -contains $extension) -or (Test-SecretFileName -Name $leaf)) {
                throw "Excluded or credential-like file found in ZIP: $entryPath"
            }

            if ((Test-TextFile -Path $leaf) -and $entry.Length -gt 0) {
                $stream = $entry.Open()
                try {
                    $reader = New-Object System.IO.StreamReader($stream, $true)
                    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
                } finally {
                    $stream.Dispose()
                }
                Assert-NoSecretContent -Content $content -Location $entryPath
                Assert-NoPersonalPathContent -Content $content -Location $entryPath
            }
        }
    } finally {
        $archive.Dispose()
    }
}

$stagingCreated = $false
try {
    Assert-ChildPath -Candidate $staging -Parent $builds
    Assert-ChildPath -Candidate $zipTemporary -Parent $builds
    New-Item -ItemType Directory -Path $staging | Out-Null
    $stagingCreated = $true

    foreach ($name in $sourceEntries) {
        $source = Join-Path $root $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $staging -Recurse -Force
        }
    }

    $removed = Remove-ExcludedStagingContent -StagingRoot $staging
    $sanitized = Sanitize-And-ValidateStagingText -StagingRoot $staging

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $staging,
        $zipTemporary,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    # Validate the actual archive, not only the staging tree. Any remaining
    # personal path or likely credential aborts before the canonical ZIP changes.
    Assert-ZipIsSafe -ZipPath $zipTemporary
    Move-Item -LiteralPath $zipTemporary -Destination $zip -Force

    Write-Host "Source package: $zip"
    Write-Host "Excluded directories: $($removed.Directories); excluded files: $($removed.Files)"
    Write-Host "Sanitized text files: $($sanitized.ChangedFiles); removed personal paths: $($sanitized.RedactedPaths)"
} finally {
    if ($stagingCreated -and (Test-Path -LiteralPath $staging)) {
        Assert-ChildPath -Candidate $staging -Parent $builds
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
    if (Test-Path -LiteralPath $zipTemporary) {
        Assert-ChildPath -Candidate $zipTemporary -Parent $builds
        Remove-Item -LiteralPath $zipTemporary -Force
    }
}
