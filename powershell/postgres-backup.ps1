# Configuration
$dbUsername     = "postgres"
$dbPassword     = ""
$keepDays       = 7
$postgresBinDir = "C:\Program Files\PostgreSQL\9.4\bin"
$backupDir      = "C:\PostgreSQL Backups"
$dbDumpDir      = "$backupDir\dump"
$globalDumpDir  = "$backupDir\global"

# NOTE: it is not recommended to change anything below this line.
$currentDate    = Get-Date -UFormat "%Y%m%d"
$Env:Path       = "$postgresBinDir"
$Env:PGPASSWORD = "$dbPassword"

# Hide the progress bar shown by "Compress-Archive"
$ProgressPreference = 'SilentlyContinue'

Write-Host "Creating dump directories ..."
New-Item -ItemType Directory -Force -Path "$dbDumpDir" | Out-Null
New-Item -ItemType Directory -Force -Path "$globalDumpDir" | Out-Null

Write-Host "Dumping globals to '$globalDumpDir\global.$currentDate.sql' ..."
pg_dumpall -U "$dbUsername" --globals-only | Out-File "$globalDumpDir\global.$currentDate.sql"

Write-Host "Compressing '$globalDumpDir\global.$currentDate.sql' ..."
Compress-Archive -Force `
    -Path "$globalDumpDir\global.$currentDate.sql" `
    -DestinationPath "$globalDumpDir\global.$currentDate.zip"
Remove-Item "$globalDumpDir\global.$currentDate.sql"

# Dump each database separately and compress the dump file
psql -U "$dbUsername" -A -q -t `
    -c "SELECT datname FROM pg_database WHERE (datname != 'template0') ORDER BY datname;" `
    postgres `
| ForEach-Object -Process {
    $database = $_

    Write-Host "Dumping database '$database' to '$dbDumpDir\$database.$currentDate.sql' ..."
    pg_dump -U "$dbUsername" "$database" | Out-File "$dbDumpDir\$database.$currentDate.sql"

    Write-Host "Compressing '$dbDumpDir\$database.$currentDate.sql' ..."
    Compress-Archive -Force `
        -Path "$dbDumpDir\$database.$currentDate.sql" `
        -DestinationPath "$dbDumpDir\$database.$currentDate.zip"
    Remove-Item "$dbDumpDir\$database.$currentDate.sql"
}

Write-Host "Removing old backup files ..."
Get-ChildItem -Path "$dbDumpDir","$globalDumpDir" -Recurse -Force `
    | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt (Get-Date).AddDays(-$keepDays) } `
    | Remove-Item -Force
