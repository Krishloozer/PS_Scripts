Write-Host "`nDatabase script execution started."
$serverHost = Read-Host "`nPlease enter the database host name (database server name)"
$dataBaseName =  Read-Host "`nPlease enter the database name (database instance name)"
$scriptFilePath = Read-Host "Please enter the database script file path "
$useWindowsAuthentication = Read-Host "Login SQL with windown authentication to execute the db scripts (Y/N) ? "
if($useWindowsAuthentication.ToLowerInvariant() -ne "y")
{
    $userName = Read-Host "`nDatabase User Name "
    $password = Read-Host "Database Password "
}
try
{
    $dbCreateScript = "DECLARE @dbName sysname = '$dataBaseName'; IF (NOT EXISTS (SELECT name FROM master.dbo.sysdatabases WHERE name = @dbName)) BEGIN DECLARE @cmdCreateDB VARCHAR(250) = 'CREATE DATABASE [' + @dbName + ']' EXECUTE(@cmdCreateDB) PRINT 'DATABASE CREATED SUCCESSFULLY' END ELSE BEGIN PRINT 'DATABASE ALREADY EXISTS IN THIS SERVER' END"
    if($useWindowsAuthentication.ToLowerInvariant() -eq "y")
    {
        Write-Host "`nConnecting to '$serverHost' server to run database script against '$dataBaseName' database instance using windows credential."
        Invoke-Sqlcmd -ServerInstance $serverHost -Query $dbCreateScript -Verbose
        Invoke-Sqlcmd -ServerInstance $serverHost -Database $dataBaseName -InputFile $scriptFilePath -Verbose
    }
    else
    {
        Write-Host "`nConnecting to '$serverHost' server to run database script against '$databaseInstance' database instance using database credential."
        Write-Host "User Name : '$userName', Password : '$password'."
        Invoke-Sqlcmd -ServerInstance $serverHost -Username $userName -Password $password -Query $dbCreateScript -Verbose
        Invoke-Sqlcmd -ServerInstance $serverHost -Username $userName -Password $password -InputFile $scriptFilePath -Verbose
    }
    Write-Host "`nScript execution successful." -ForegroundColor Green
}
catch
{
    Write-Error -Message "Script execution failed."
}