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
}

function Verify-Checksums {
    param ($ChecksumFile)

    if (-not (Test-Path $ChecksumFile)) {
        Write-Host "Checksum file not found: $ChecksumFile" -ForegroundColor Red
        return
    }

    Write-Host "`nVerifying checksums..." -ForegroundColor Cyan
    $stored = Import-Csv -Path $ChecksumFile
    $errors = 0

    foreach ($entry in $stored) {
        if (Test-Path $entry.FilePath) {
            $currentHash = (Get-FileHash -Path $entry.FilePath -Algorithm $entry.Algorithm).Hash
            if ($currentHash -ieq $entry.Hash) {
                Write-Host "OK: $($entry.FilePath)" -ForegroundColor Green
            } else {
                Write-Host "MISMATCH: $($entry.FilePath)" -ForegroundColor Yellow
                $errors++
            }
        } else {
            Write-Host "MISSING: $($entry.FilePath)" -ForegroundColor Red
            $errors++
        }
    }

    Write-Host "`nVerification complete. Errors: $errors" -ForegroundColor Cyan
}

function Compare-Directories {
    Write-Host "`n--- Directory Comparison ---" -ForegroundColor Cyan
    $source = Read-Host "Enter path to SOURCE directory"
    $target = Read-Host "Enter path to TARGET directory (e.g., mapped network share)"

    if (-not (Test-Path $source) -or -not (Test-Path $target)) {
        Write-Host "One or both directories do not exist." -ForegroundColor Red
        return
    }

    Write-Host "`nHashing source directory..." -ForegroundColor Cyan
    $sourceHashes = Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($source.Length).TrimStart('\')
        $hash = Get-FileHash -Path $_.FullName -Algorithm $Algorithm
        [PSCustomObject]@{ Relative = $rel; Hash = $hash.Hash }
    }

    Write-Host "Hashing target directory..." -ForegroundColor Cyan
    $targetHashes = Get-ChildItem -Path $target -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($target.Length).TrimStart('\')
        $hash = Get-FileHash -Path $_.FullName -Algorithm $Algorithm
        [PSCustomObject]@{ Relative = $rel; Hash = $hash.Hash }
    }

    $targetMap = @{}
    foreach ($t in $targetHashes) { $targetMap[$t.Relative] = $t.Hash }

    $errors = 0
    foreach ($s in $sourceHashes) {
        if ($targetMap.ContainsKey($s.Relative)) {
            if ($s.Hash -ieq $targetMap[$s.Relative]) {
                Write-Host "MATCH: $($s.Relative)" -ForegroundColor Green
            } else {
                Write-Host "MISMATCH: $($s.Relative)" -ForegroundColor Yellow
                $errors++
            }
        } else {
            Write-Host "MISSING in target: $($s.Relative)" -ForegroundColor Red
            $errors++
        }
    }

    Write-Host "`nComparison complete. Issues found: $errors" -ForegroundColor Cyan
}

# === Main Menu ===
Write-Host "`n1. Generate checksums to file"
Write-Host "2. Verify checksums from file"
Write-Host "3. Compare two directories"
$choice = Read-Host "Select an option (1, 2, or 3)"

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
        Compare-Directories
    }
    default {
        Write-Host "Invalid option." -ForegroundColor Red
    }
}
