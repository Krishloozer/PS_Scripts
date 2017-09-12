Add-Type -AssemblyName System.IO.Compression.FileSystem

function Unzip
{
    param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

$dbScriptsZipPath = Read-Host "`nEnter path of DBScripts.zip file "
    
    while(-not (($dbScriptsZipPath -ne "") -and (Test-Path $dbScriptsZipPath) -and ([System.IO.Path]::GetExtension("$dbScriptsZipPath") -eq ".zip")))
    {
    
        Write-Host "`nProvided path is invalid..!"
        $dbScriptsZipPath = Read-Host "`nPlease enter valid path of DBScripts.zip file "
    }
    
    $pathToUnzipScripts = Read-Host "`nEnter path to extract the DBScripts.zip `n(E:\ClientAcqPortal) "
    
    while($pathToUnzipScripts -eq "")
    {
        if(-not (Test-Path $pathToUnzipScripts -PathType Container)){
            Write-Host "`nProvided path is not available."
            $yesOrNo = Read-host "`nProceeding will create the folder, Would you like to proceed(Y/N)?"
            if($yesOrNo.ToLowerInvariant() -eq "n"){
                Write-host "`nStopping web deployment script..!"
            }
        }
    }
    
    Write-Host "`nFile from '$dbScriptsZipPath' will be extracted to '$pathToUnzipScripts'"
    if(Test-Path $pathToUnzipScripts){
        Write-Host "`nFiles in the path '$pathToUnzipScripts' will be removed...!"
        if((Get-Item $pathToUnzipScripts).Parent.Name)
        {
            Write-Host "`nRemoving folders and files from '$pathToUnzipScripts'"
            Remove-Item $pathToUnzipScripts -Force -Recurse
            $basePath = $pathToUnzipScripts
        }
        else
        {
            Write-Host "`nNo folders or files available in '$pathToUnzipScripts' to remove"
            $basePath = $dbScriptsZipPath.Substring(0, $file.LastIndexOf('.'))
        }
    }
    else
    {
        $basePath = $pathToUnzipScripts
    }
Write-Host "`nExtracting files from zip folder...!"
$shellVersion = $PSVersionTable.PSVersion.Major
try{
    if($shellVersion -ge 5){
        Write-Host "`nShell Version - '$shellVersion'"
        Expand-Archive $dbScriptsZipPath -DestinationPath $pathToUnzipScripts
    }
    else{
        Write-Host "`nShell Version - '$shellVersion'"
        Unzip $dbScriptsZipPath $pathToUnzipScripts
    }
    Write-Host "`nFiles extraction successful." -ForegroundColor Green
}
catch
{
    Write-Error -message $_.Exception.Message
}

$files = Get-ChildItem $basePath

$files