<# 
Version Controller
Windows PowerShell 5.1 ve PowerShell 7 uyumlu, Git gerektirmeyen GitHub zip tabanli guncelleyici.

Desteklenen argumanlar:
  --check-only
  --force
  --silent
  --restore-latest-backup
  --no-backup
  --help
#>

$Script:CliArgs = @($args)
$Script:ProjectRoot = $null
$Script:ControllerDir = $null
$Script:Config = $null
$Script:Silent = $false

# Komut satiri argumanlarini PowerShell surumlerinden bagimsiz bicimde okur.
function Test-Argument {
    param([Parameter(Mandatory = $true)][string]$Name)

    $forms = @("--$Name", "-$Name", "/$Name")
    foreach ($arg in $Script:CliArgs) {
        if ($forms -contains $arg.ToLowerInvariant()) {
            return $true
        }
    }
    return $false
}

# Konsol ciktisini --silent modunda kisar.
function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")][string]$Level = "Info",
        [switch]$Always
    )

    if ($Script:Silent -and -not $Always) {
        return
    }

    $prefix = switch ($Level) {
        "Success" { "[OK]" }
        "Warning" { "[UYARI]" }
        "Error" { "[HATA]" }
        default { "[BILGI]" }
    }

    Write-Host "$prefix $Message"
}

# Yardim ekranini gosterir.
function Show-Help {
    $help = @"
Version Controller kullanim:

  powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1"
  powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --check-only
  powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --force
  powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --restore-latest-backup

Argumanlar:
  --check-only             Sadece remote versiyonu kontrol eder, indirme yapmaz.
  --force                  Versiyon ayni olsa bile repoyu indirip senkronize eder.
  --silent                 Konsola minimum cikti yazar.
  --restore-latest-backup  En son backup klasorunden geri yukleme yapar.
  --no-backup              Bu calistirmada backup almaz.
  --help                   Bu yardim bilgisini gosterir.
"@
    Write-Host $help
}

# Script konumundan proje root dizinini bulur.
function Initialize-Paths {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }

    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw "Script yolu algilanamadi."
    }

    $Script:ControllerDir = Split-Path -Parent $scriptPath
    $Script:ProjectRoot = Split-Path -Parent $Script:ControllerDir

    if (-not (Test-Path -LiteralPath $Script:ProjectRoot -PathType Container)) {
        throw "Proje root dizini bulunamadi: $Script:ProjectRoot"
    }
}

# Varsayilan config objesini uretir.
function New-DefaultConfig {
    [PSCustomObject]@{
        repositoryOwner = "KULLANICI_ADI"
        repositoryName = "REPO_ADI"
        branch = "main"
        versionFilePath = "version controller/version.md"
        downloadMode = "zip"
        excludeFiles = @(
            "version controller/config.json",
            ".env",
            "user-data.json",
            "settings.local.json"
        )
        backupBeforeUpdate = $true
        backupFolder = "version controller/backups"
        autoRestartAfterUpdate = $false
        startCommand = "start.bat"
    }
}

# config.json dosyasini okur; yoksa ornek config olusturur.
function Read-Config {
    $configPath = Join-Path $Script:ControllerDir "config.json"

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        $defaultConfig = New-DefaultConfig
        $json = $defaultConfig | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $configPath -Value $json -Encoding UTF8
        throw "config.json bulunamadi. Ornek config olusturuldu: $configPath. Lutfen repositoryOwner ve repositoryName alanlarini duzenleyin."
    }

    try {
        $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        $config = $raw | ConvertFrom-Json
    }
    catch {
        throw "config.json okunamadi veya JSON formati hatali: $($_.Exception.Message)"
    }

    $required = @("repositoryOwner", "repositoryName", "branch", "versionFilePath", "downloadMode", "excludeFiles", "backupBeforeUpdate", "backupFolder", "autoRestartAfterUpdate", "startCommand")
    foreach ($name in $required) {
        if (-not ($config.PSObject.Properties.Name -contains $name)) {
            throw "config.json icinde '$name' alani eksik."
        }
    }

    if ($config.downloadMode -ne "zip") {
        throw "Bu surum yalnizca downloadMode='zip' degerini destekler."
    }

    if ($config.repositoryOwner -eq "KULLANICI_ADI" -or $config.repositoryName -eq "REPO_ADI") {
        throw "config.json icindeki repositoryOwner ve repositoryName alanlarini gercek GitHub bilgileriyle guncelleyin."
    }

    $Script:Config = $config
    return $config
}

# SemVer formatini dogrular ve parcalara ayirir.
function ConvertTo-SemVerParts {
    param([Parameter(Mandatory = $true)][string]$Version)

    $clean = $Version.Trim()
    if ($clean -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
        throw "Gecersiz SemVer formati: '$Version'. Beklenen format: MAJOR.MINOR.PATCH"
    }

    @(
        [int]$Matches[1],
        [int]$Matches[2],
        [int]$Matches[3]
    )
}

# Local version.md dosyasindan local versiyonu okur.
function Read-LocalVersion {
    param([Parameter(Mandatory = $true)]$Config)

    $versionPath = Join-Path $Script:ProjectRoot $Config.versionFilePath
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw "Local version.md bulunamadi: $versionPath"
    }

    $content = Get-Content -LiteralPath $versionPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "Local version.md bos: $versionPath"
    }

    [void](ConvertTo-SemVerParts -Version $content)
    return $content.Trim()
}

# GitHub raw URL icin path segmentlerini guvenli bicimde encode eder.
function ConvertTo-UrlPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $segments = $Path -replace '\\', '/' -split '/'
    $encoded = foreach ($segment in $segments) {
        [System.Uri]::EscapeDataString($segment)
    }
    return ($encoded -join '/')
}

# GitHub raw version.md dosyasindan remote versiyonu okur.
function Get-RemoteVersion {
    param([Parameter(Mandatory = $true)]$Config)

    $owner = [System.Uri]::EscapeDataString($Config.repositoryOwner)
    $repo = [System.Uri]::EscapeDataString($Config.repositoryName)
    $branch = [System.Uri]::EscapeDataString($Config.branch)
    $versionPath = ConvertTo-UrlPath -Path $Config.versionFilePath
    $rawUrl = "https://raw.githubusercontent.com/$owner/$repo/$branch/$versionPath"

    try {
        $response = Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $remoteVersion = ($response.Content -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1).Trim()
        [void](ConvertTo-SemVerParts -Version $remoteVersion)
        return $remoteVersion
    }
    catch {
        throw "GitHub remote version okunamadi. URL: $rawUrl Detay: $($_.Exception.Message)"
    }
}

# Iki SemVer degerini sayisal olarak karsilastirir. Sonuc: -1, 0, 1.
function Compare-SemVer {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $leftParts = ConvertTo-SemVerParts -Version $Left
    $rightParts = ConvertTo-SemVerParts -Version $Right

    for ($i = 0; $i -lt 3; $i++) {
        if ($leftParts[$i] -gt $rightParts[$i]) { return 1 }
        if ($leftParts[$i] -lt $rightParts[$i]) { return -1 }
    }

    return 0
}

# GitHub repository zip dosyasini gecici klasore indirir.
function Download-GitHubZip {
    param([Parameter(Mandatory = $true)]$Config)

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("version-controller-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $zipPath = Join-Path $tempRoot "repo.zip"
    $owner = [System.Uri]::EscapeDataString($Config.repositoryOwner)
    $repo = [System.Uri]::EscapeDataString($Config.repositoryName)
    $branch = ConvertTo-UrlPath -Path $Config.branch
    $zipUrl = "https://codeload.github.com/$owner/$repo/zip/refs/heads/$branch"

    try {
        Write-Status "GitHub zip indiriliyor: $zipUrl"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf) -or (Get-Item -LiteralPath $zipPath).Length -eq 0) {
            throw "Indirilen zip dosyasi bos."
        }

        return $zipPath
    }
    catch {
        throw "Zip indirme basarisiz. Detay: $($_.Exception.Message)"
    }
}

# Indirilen zip dosyasini gecici klasore acar.
function Extract-Zip {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    $extractPath = Join-Path (Split-Path -Parent $ZipPath) "extract"
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    try {
        if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
            Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath -Force
        }
        else {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $extractPath)
        }

        $dirs = Get-ChildItem -LiteralPath $extractPath -Directory
        if ($dirs.Count -eq 1) {
            return $dirs[0].FullName
        }

        return $extractPath
    }
    catch {
        throw "Zip acma basarisiz. Detay: $($_.Exception.Message)"
    }
}

# Windows uyumlu normalize edilmis relative path uretir.
function Get-RelativePathSafe {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $baseUri = New-Object System.Uri (($BasePath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar))
    $fullUri = New-Object System.Uri $FullPath
    $relative = $baseUri.MakeRelativeUri($fullUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace('/', '\')
}

# Relative pathleri karsilastirma icin normalize eder.
function Normalize-RelativePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    return ($Path.Trim().TrimStart('\', '/').Replace('/', '\')).ToLowerInvariant()
}

# Exclude listesi ve sistem korumalari icin path eslesmesi yapar.
function Test-IsExcluded {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)]$Config,
        [switch]$ForBackup
    )

    $normalized = Normalize-RelativePath -Path $RelativePath
    $backupFolder = Normalize-RelativePath -Path $Config.backupFolder
    $implicitExcludes = @(
        ".git",
        $backupFolder,
        "version controller\update-log.md"
    )

    $allExcludes = @()
    if (-not $ForBackup) {
        $allExcludes += @($Config.excludeFiles)
    }
    $allExcludes += $implicitExcludes

    foreach ($exclude in $allExcludes) {
        $ex = Normalize-RelativePath -Path $exclude
        if ([string]::IsNullOrWhiteSpace($ex)) {
            continue
        }

        if ($normalized -eq $ex -or $normalized.StartsWith($ex.TrimEnd('\') + '\')) {
            return $true
        }
    }

    return $false
}

# Guncelleme oncesi proje dosyalarini tarihli backup klasorune kopyalar.
function Backup-Project {
    param([Parameter(Mandatory = $true)]$Config)

    $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
    $backupRoot = Join-Path $Script:ProjectRoot $Config.backupFolder
    $backupPath = Join-Path $backupRoot "backup-$timestamp"

    try {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

        $items = Get-ChildItem -LiteralPath $Script:ProjectRoot -Force
        foreach ($item in $items) {
            $relative = Get-RelativePathSafe -BasePath $Script:ProjectRoot -FullPath $item.FullName
            if (Test-IsExcluded -RelativePath $relative -Config $Config -ForBackup) {
                continue
            }

            $destination = Join-Path $backupPath $relative
            if ($item.PSIsContainer) {
                Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
            }
            else {
                $parent = Split-Path -Parent $destination
                if (-not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
            }
        }

        Write-Status "Backup alindi: $backupPath" "Success"
        return $backupPath
    }
    catch {
        throw "Backup alinamadi. Detay: $($_.Exception.Message)"
    }
}

# Iki dosyanin icerik olarak farkli olup olmadigini kontrol eder.
function Test-FileChanged {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        return $true
    }

    $sourceHash = Get-FileHash -LiteralPath $Source -Algorithm SHA256
    $destinationHash = Get-FileHash -LiteralPath $Destination -Algorithm SHA256
    return $sourceHash.Hash -ne $destinationHash.Hash
}

# Remote zipten acilan dosyalari local proje ile senkronize eder.
function Sync-Files {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)]$Config
    )

    $changes = New-Object System.Collections.Generic.List[string]
    $sourceMap = @{}

    try {
        $sourceFiles = Get-ChildItem -LiteralPath $SourceRoot -Recurse -Force -File
        foreach ($sourceFile in $sourceFiles) {
            $relative = Get-RelativePathSafe -BasePath $SourceRoot -FullPath $sourceFile.FullName
            $normalized = Normalize-RelativePath -Path $relative
            $sourceMap[$normalized] = $true

            if (Test-IsExcluded -RelativePath $relative -Config $Config) {
                continue
            }

            $destination = Join-Path $Script:ProjectRoot $relative
            $destinationDir = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            if (Test-FileChanged -Source $sourceFile.FullName -Destination $destination) {
                $action = if (Test-Path -LiteralPath $destination -PathType Leaf) { "Guncellendi" } else { "Eklendi" }
                Copy-Item -LiteralPath $sourceFile.FullName -Destination $destination -Force
                $changes.Add("${action}: $relative")
            }
        }

        $localFiles = Get-ChildItem -LiteralPath $Script:ProjectRoot -Recurse -Force -File
        foreach ($localFile in $localFiles) {
            $relative = Get-RelativePathSafe -BasePath $Script:ProjectRoot -FullPath $localFile.FullName
            $normalized = Normalize-RelativePath -Path $relative

            if (Test-IsExcluded -RelativePath $relative -Config $Config) {
                continue
            }

            if (-not $sourceMap.ContainsKey($normalized)) {
                Remove-Item -LiteralPath $localFile.FullName -Force
                $changes.Add("Silindi: $relative")
            }
        }

        $emptyDirs = Get-ChildItem -LiteralPath $Script:ProjectRoot -Recurse -Force -Directory |
            Sort-Object FullName -Descending
        foreach ($dir in $emptyDirs) {
            $relative = Get-RelativePathSafe -BasePath $Script:ProjectRoot -FullPath $dir.FullName
            if (Test-IsExcluded -RelativePath $relative -Config $Config) {
                continue
            }

            $hasChildren = Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $hasChildren) {
                Remove-Item -LiteralPath $dir.FullName -Force
                $changes.Add("Bos klasor silindi: $relative")
            }
        }

        return @($changes)
    }
    catch {
        throw "Dosya senkronizasyonu basarisiz. Detay: $($_.Exception.Message)"
    }
}

# update-log.md dosyasina calisma sonucunu yazar.
function Write-UpdateLog {
    param(
        [string]$LocalVersion,
        [string]$RemoteVersion,
        [bool]$Updated,
        [string[]]$ChangedFiles = @(),
        [string]$ErrorDetail = "",
        [string]$Message = ""
    )

    try {
        $logPath = Join-Path $Script:ControllerDir "update-log.md"
        $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $changedText = if ($ChangedFiles -and $ChangedFiles.Count -gt 0) {
            ($ChangedFiles | ForEach-Object { "- $_" }) -join [Environment]::NewLine
        }
        else {
            "- Degisen dosya yok"
        }

        $entry = @"

## $date

- Local version: $LocalVersion
- Remote version: $RemoteVersion
- Update yapildi mi: $Updated
- Mesaj: $Message
- Hata: $ErrorDetail

### Degisen Dosyalar
$changedText
"@

        Add-Content -LiteralPath $logPath -Value $entry -Encoding UTF8
    }
    catch {
        Write-Status "Log yazilamadi: $($_.Exception.Message)" "Warning" -Always
    }
}

# Belirtilen backup klasorunu proje root'a geri yukler.
function Restore-Backup {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)]$Config
    )

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        throw "Backup klasoru bulunamadi: $BackupPath"
    }

    try {
        Write-Status "Backup geri yukleniyor: $BackupPath" "Warning"

        $backupFiles = Get-ChildItem -LiteralPath $BackupPath -Recurse -Force -File
        foreach ($backupFile in $backupFiles) {
            $relative = Get-RelativePathSafe -BasePath $BackupPath -FullPath $backupFile.FullName
            $destination = Join-Path $Script:ProjectRoot $relative
            $destinationDir = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $backupFile.FullName -Destination $destination -Force
        }

        $localFiles = Get-ChildItem -LiteralPath $Script:ProjectRoot -Recurse -Force -File
        $backupMap = @{}
        foreach ($backupFile in $backupFiles) {
            $relative = Get-RelativePathSafe -BasePath $BackupPath -FullPath $backupFile.FullName
            $backupMap[(Normalize-RelativePath -Path $relative)] = $true
        }

        foreach ($localFile in $localFiles) {
            $relative = Get-RelativePathSafe -BasePath $Script:ProjectRoot -FullPath $localFile.FullName
            $normalized = Normalize-RelativePath -Path $relative
            $backupFolder = Normalize-RelativePath -Path $Config.backupFolder

            if ($normalized.StartsWith($backupFolder.TrimEnd('\') + '\')) {
                continue
            }

            if (-not $backupMap.ContainsKey($normalized)) {
                Remove-Item -LiteralPath $localFile.FullName -Force
            }
        }

        Write-Status "Backup geri yukleme tamamlandi." "Success"
    }
    catch {
        throw "Backup geri yukleme basarisiz. Detay: $($_.Exception.Message)"
    }
}

# En yeni backup klasorunu bulur.
function Get-LatestBackup {
    param([Parameter(Mandatory = $true)]$Config)

    $backupRoot = Join-Path $Script:ProjectRoot $Config.backupFolder
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        return $null
    }

    Get-ChildItem -LiteralPath $backupRoot -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

# Basarisiz update sonrasi kullanici isterse backup'tan geri doner.
function Request-RestoreOnFailure {
    param(
        [string]$BackupPath,
        [Parameter(Mandatory = $true)]$Config
    )

    if ([string]::IsNullOrWhiteSpace($BackupPath) -or $Script:Silent) {
        return
    }

    try {
        $answer = Read-Host "Update yarida kaldi. Backup'tan geri donulsun mu? (E/H)"
        if ($answer -match '^(e|evet|y|yes)$') {
            Restore-Backup -BackupPath $BackupPath -Config $Config
        }
    }
    catch {
        Write-Status "Geri yukleme sorusu tamamlanamadi: $($_.Exception.Message)" "Warning" -Always
    }
}

# Guncelleme sonrasi opsiyonel start komutunu calistirir.
function Invoke-AutoRestart {
    param([Parameter(Mandatory = $true)]$Config)

    if (-not $Config.autoRestartAfterUpdate) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Config.startCommand)) {
        return
    }

    $commandPath = Join-Path $Script:ProjectRoot $Config.startCommand
    if (Test-Path -LiteralPath $commandPath) {
        Write-Status "autoRestartAfterUpdate aktif. Baslatiliyor: $($Config.startCommand)"
        Start-Process -FilePath $commandPath -WorkingDirectory $Script:ProjectRoot
    }
    else {
        Write-Status "startCommand bulunamadi: $commandPath" "Warning"
    }
}

# Ana akisi calistirir.
function Start-UpdateCheck {
    $Script:Silent = Test-Argument -Name "silent"

    if (Test-Argument -Name "help") {
        Show-Help
        return
    }

    Initialize-Paths

    $localVersion = "Bilinmiyor"
    $remoteVersion = "Bilinmiyor"
    $backupPath = $null
    $zipRoot = $null

    try {
        $config = Read-Config

        if (Test-Argument -Name "restore-latest-backup") {
            $latestBackup = Get-LatestBackup -Config $config
            if (-not $latestBackup) {
                throw "Geri yuklenecek backup bulunamadi."
            }
            Restore-Backup -BackupPath $latestBackup.FullName -Config $config
            Write-UpdateLog -LocalVersion $localVersion -RemoteVersion $remoteVersion -Updated $false -Message "En son backup geri yuklendi: $($latestBackup.FullName)"
            return
        }

        $localVersion = Read-LocalVersion -Config $config
        Write-Status "Local version: $localVersion"

        $remoteVersion = Get-RemoteVersion -Config $config
        Write-Status "Remote version: $remoteVersion"

        $comparison = Compare-SemVer -Left $remoteVersion -Right $localVersion
        $force = Test-Argument -Name "force"
        $checkOnly = Test-Argument -Name "check-only"

        if ($checkOnly) {
            $message = if ($comparison -gt 0) { "Yeni versiyon mevcut." } elseif ($comparison -eq 0) { "Zaten guncel." } else { "Remote versiyon localden dusuk." }
            Write-Status $message "Info" -Always
            Write-UpdateLog -LocalVersion $localVersion -RemoteVersion $remoteVersion -Updated $false -Message "Sadece kontrol: $message"
            return
        }

        if ($comparison -lt 0 -and -not $force) {
            $message = "Remote versiyon local versiyondan dusuk. Islem yapilmadi."
            Write-Status $message "Warning" -Always
            Write-UpdateLog -LocalVersion $localVersion -RemoteVersion $remoteVersion -Updated $false -Message $message
            return
        }

        if ($comparison -eq 0 -and -not $force) {
            $message = "Zaten guncel. Indirme yapilmadi."
            Write-Status $message "Success" -Always
            Write-UpdateLog -LocalVersion $localVersion -RemoteVersion $remoteVersion -Updated $false -Message $message
            return
        }

        $reason = if ($force) { "--force kullanildi; senkronizasyon baslatiliyor." } else { "Yeni versiyon bulundu; update baslatiliyor." }
        Write-Status $reason "Info" -Always

        $zipPath = Download-GitHubZip -Config $config
        $zipRoot = Split-Path -Parent $zipPath
        $sourceRoot = Extract-Zip -ZipPath $zipPath

        $shouldBackup = [bool]$config.backupBeforeUpdate -and -not (Test-Argument -Name "no-backup")
        if ($shouldBackup) {
            $backupPath = Backup-Project -Config $config
        }
        else {
            Write-Status "Backup bu calistirmada atlandi." "Warning"
        }

        $changes = Sync-Files -SourceRoot $sourceRoot -Config $config
        Write-UpdateLog -LocalVersion $localVersion -RemoteVersion $remoteVersion -Updated $true -ChangedFiles $changes -Message "Update tamamlandi."
        Write-Status "Update tamamlandi. Local version artik remote ile ayni olmalidir: $remoteVersion" "Success" -Always

        Invoke-AutoRestart -Config $config
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Status $errorMessage "Error" -Always
        Write-UpdateLog -LocalVersion $localVersion -RemoteVersion $remoteVersion -Updated $false -ErrorDetail $errorMessage -Message "Islem basarisiz."
        Request-RestoreOnFailure -BackupPath $backupPath -Config $Script:Config
    }
    finally {
        if ($zipRoot -and (Test-Path -LiteralPath $zipRoot -PathType Container)) {
            Remove-Item -LiteralPath $zipRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Start-UpdateCheck
