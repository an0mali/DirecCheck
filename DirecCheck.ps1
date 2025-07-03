param (
    [ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
    [string]$Algorithm = "MD5"
)

function Generate-Checksums {
    param ($TargetDir, $ChecksumFile)

    Write-Host "`nGenerating checksums for files in $TargetDir..." -ForegroundColor Cyan
    $hashes = Get-ChildItem -Path $TargetDir -Recurse -File | ForEach-Object {
        $hash = Get-FileHash -Path $_.FullName -Algorithm $Algorithm
        [PSCustomObject]@{
            Hash      = $hash.Hash
            FilePath  = $_.FullName
            Relative  = $_.FullName.Substring($TargetDir.Length).TrimStart('\')
            Algorithm = $hash.Algorithm
        }
    }
    $hashes | Export-Csv -Path $ChecksumFile -NoTypeInformation
    Write-Host "Checksums saved to $ChecksumFile" -ForegroundColor Green
    mainMenu
}

function Verify-Checksums {
    param ($ChecksumFile)

    if (-not (Test-Path $ChecksumFile)) {
        Write-Host "Checksum file not found: $ChecksumFile" -ForegroundColor Red
        return
    }

    Write-Host "`nVerifying checksums..." -ForegroundColor Cyan
    $stored = Import-Csv -Path $ChecksumFile
    $storedMap = @{}
    foreach ($entry in $stored) {
        $storedMap[$entry.Relative] = $entry
    }

    # Get current hashes from the directory being verified
    $baseDir = Split-Path -Path $stored[0].FilePath -Parent
    $currentHashes = Get-ChildItem -Path $baseDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($baseDir.Length + 1)
        $hash = Get-FileHash -Path $_.FullName -Algorithm $stored[0].Algorithm
        [PSCustomObject]@{ Relative = $rel; Hash = $hash.Hash; FilePath = $_.FullName }
    }

    $currentMap = @{}
    foreach ($entry in $currentHashes) {
        $currentMap[$entry.Relative] = $entry
    }

    $allKeys = ($storedMap.Keys + $currentMap.Keys) | Sort-Object -Unique
    $errors = 0

    foreach ($key in $allKeys) {
        $inStored = $storedMap.ContainsKey($key)
        $inCurrent = $currentMap.ContainsKey($key)

        if ($inStored -and $inCurrent) {
            if ($storedMap[$key].Hash -ieq $currentMap[$key].Hash) {
                Write-Host "MATCH: $key" -ForegroundColor Green
            } else {
                Write-Host "MISMATCH: $key" -ForegroundColor Yellow
                $errors++
            }
        } elseif ($inStored -and -not $inCurrent) {
            Write-Host "MISSING in current: $key" -ForegroundColor Red
            $errors++
        } elseif (-not $inStored -and $inCurrent) {
            Write-Host "NEW in current: $key" -ForegroundColor Blue
            $errors++
        }
    }

    Write-Host "`nVerification complete. Issues found: $errors" -ForegroundColor Cyan
    mainMenu
}

function Compare-SourceToTarget {
    Write-Host "`n--- Compare Source to Target Directory ---" -ForegroundColor Cyan
    $source = Read-Host "Enter path to SOURCE directory"
    $target = Read-Host "Enter path to TARGET directory"

    $source = (Resolve-Path $source).Path.TrimEnd('\')
    $target = (Resolve-Path $target).Path.TrimEnd('\')

    if (-not (Test-Path $source) -or -not (Test-Path $target)) {
        Write-Host "One or both directories do not exist." -ForegroundColor Red
        return
    }

    Write-Host "`nHashing source directory..." -ForegroundColor Cyan
    $sourceHashes = Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($source.Length + 1)
        $hash = Get-FileHash -Path $_.FullName -Algorithm $Algorithm
        [PSCustomObject]@{ Relative = $rel; Hash = $hash.Hash; FullPath = $_.FullName }
    }

    Write-Host "Hashing target directory..." -ForegroundColor Cyan
    $targetHashes = Get-ChildItem -Path $target -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($target.Length + 1)
        $hash = Get-FileHash -Path $_.FullName -Algorithm $Algorithm
        [PSCustomObject]@{ Relative = $rel; Hash = $hash.Hash; FullPath = $_.FullName }
    }

    $sourceMap = @{}
    $targetMap = @{}
    foreach ($s in $sourceHashes) { $sourceMap[$s.Relative] = $s }
    foreach ($t in $targetHashes) { $targetMap[$t.Relative] = $t }

    $allKeys = ($sourceMap.Keys + $targetMap.Keys) | Sort-Object -Unique
    $errors = 0
    $results = @()
    $syncList = @()

foreach ($key in $allKeys) {
    $inSource = $sourceMap.ContainsKey($key)
    $inTarget = $targetMap.ContainsKey($key)

    $srcHash = ""
    $tgtHash = ""

    if ($inSource) { $srcHash = $sourceMap[$key].Hash }
    if ($inTarget) { $tgtHash = $targetMap[$key].Hash }

    if ($inSource -and $inTarget) {
        if ($srcHash -ieq $tgtHash) {
            Write-Host "MATCH: $key" -ForegroundColor Green
            $results += [PSCustomObject]@{
                Status       = "MATCH"
                RelativePath = $key
                SourceHash   = $srcHash
                TargetHash   = $tgtHash
            }
        } else {
            Write-Host "MISMATCH: $key" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Status       = "MISMATCH"
                RelativePath = $key
                SourceHash   = $srcHash
                TargetHash   = $tgtHash
            }
            $syncList += $key
            $errors++
        }
    } elseif ($inSource -and -not $inTarget) {
        Write-Host "MISSING in target: $key" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Status       = "MISSING in target"
            RelativePath = $key
            SourceHash   = $srcHash
            TargetHash   = ""
        }
        $syncList += $key
        $errors++
    } elseif (-not $inSource -and $inTarget) {
        Write-Host "NEW in target: $key" -ForegroundColor DarkGray
        $results += [PSCustomObject]@{
            Status       = "NEW in target"
            RelativePath = $key
            SourceHash   = ""
            TargetHash   = $tgtHash
        }
        $errors++
    }
}



    Write-Host "`nComparison complete. Issues found: $errors" -ForegroundColor Cyan

    $save = Read-Host "`nWould you like to save the results to a CSV file? (Y/N)"
    if ($save -match '^[Yy]$') {
        $outPath = Read-Host "Enter path to save the CSV file (e.g., C:\output\results.csv)"
        try {
            $results | Export-Csv -Path $outPath -NoTypeInformation
            Write-Host "Results saved to $outPath" -ForegroundColor Green
        } catch {
            Write-Host "Failed to save file: $_" -ForegroundColor Red
        }
    }

    if ($syncList.Count -gt 0) {
        $sync = Read-Host "`nWould you like to synchronize the target with the source? This will not delete new files from target (Y/N)"
        if ($sync -match '^[Yy]$') {
            foreach ($rel in $syncList) {
                $srcPath = $sourceMap[$rel].FullPath
                $destPath = Join-Path $target $rel
                $destDir = Split-Path $destPath -Parent

                if (-not (Test-Path $destDir)) {
                    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
                }

                Copy-Item -Path $srcPath -Destination $destPath -Force
                Write-Host "Copied: $rel" -ForegroundColor Cyan
            }
            Write-Host "`nSynchronization complete." -ForegroundColor Green
        }
    } else {
        Write-Host "`nNo files needed to be synchronized." -ForegroundColor DarkGray
    }
    mainMenu
}

function mainMenu {
# === Main Menu ===
Write-Host "`n1. Generate checksums to file"
Write-Host "2. Verify checksums from file"
Write-Host "3. Compare source directory to target directory"
$choice = Read-Host "Select an option, or Ctrl+C to quit (1, 2, 3)"

switch ($choice) {
    "1" {
        $dir = Read-Host "Enter directory to hash"
        $file = Read-Host "Enter path to save checksum file"
        Generate-Checksums -TargetDir $dir -ChecksumFile $file
    }
    "2" {
        $file = Read-Host "Enter path to checksum file"
        Verify-Checksums -ChecksumFile $file
    }
    "3" {
        Compare-SourceToTarget
    }

    default {
        Write-Host "Invalid option." -ForegroundColor Red
    }
}
}

mainMenu