# Functions...!

Add-Type -AssemblyName System.IO.Compression.FileSystem
Import-Module WebAdministration

#Global variables...
$global:basePath = ""
$global:clientCodePath = ""
$global:serverCodePath = ""
$global:serviceName = ""
$global:siteName=""
$global:dataBaseServerName = ""
$global:dataBaseInstanceName = ""
$global:userNameForDB=""
$global:passwordForDB=""
$global:serviceEndPoint=""
$global:userName=""
$global:password=""

function Unzip
{
    param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

function Update-ConnectionString ([Parameter(Mandatory=$true)][string]$inputFilePath,[Parameter(Mandatory=$true)][string]$connectionStringName)
{
    $xml = [xml](Get-Content $inputFilePath)
    $con = $xml.configuration.connectionStrings.add|?{$_.name -eq $connectionStringName};
    if($con){
        #$con.connectionString = $con.connectionString -replace "{DATABASESERVER}", $dataBaseServerName -replace "{DATABASEINSTANCE}", $dataBaseInstanceName -replace "{USERNAME}", $userNameForDB -replace "{PASSWORD}", $passwordForDB
        $con.connectionString = $con.connectionString -replace "{DATABASESERVER}", $dataBaseServerName -replace "{DATABASEINSTANCE}", $dataBaseInstanceName
		Write-Host "`nUpdated connection string details...`n"
        $con.connectionString
        $xml.Save($inputFilePath)
        Write-Host "`nConnection with the name '$connectionStringName' is updated successfully."
    }
    else
    {
        Write-Error "`nConnection string not available."
        Undo-Changes "`nConnection string not available."
    }
}

function Undo-Changes ([string]$message)
{
    Write-Host $message
    Write-Host "`nRestoring backups..."
    Restore-WebConfiguration -Name $backUpName
    Remove-WebConfigurationBackup -Name $backUpName
    Exit
}

function Create-WebApplication 
{
    Write-Host "`nPlease enter the details to create web application (Web Api)."
    $global:serviceName = Read-Host "`nWeb API application name (Ex: Server, Service...,) "
    Write-Host "`nPhysical location of API code : '$serverCodePath'"
    New-WebApplication -Name $serviceName -Site $siteName -PhysicalPath $serverCodePath -ApplicationPool $siteName
 }
 
 function Set-Application-Pool-Identity
 {
	$appPool = Get-Item "IIS:\AppPools\$siteName"
    $setCustomAccount = Read-Host "`nWant to set the custom account for application pool identity (y/n) "
    if($setCustomAccount.ToLowerInvariant() -eq "y")
    {
    	$global:userName= Read-Host "`nEnter User Name for Setting Application pool Identity (Ex.Domain\UserName) "    
    	$global:password= Read-Host "Enter Password of given User Name for Set Application pool Identity "
        $appPool.processModel.password = $password
        $appPool.processModel.userName = $userName
	    $appPool.processModel.identityType = 3
    }
    else
    {
        $appPool.processModel.identityType = 4
    }
	$appPool | Set-Item
    if($appPool.state -ne "Stopped")
    {
        $appPool.Stop()
    }
    if($appPool.state -ne "Started")
    {
	    $appPool.Start()
    }
 }
 
 function Create-WebSite([Parameter(Mandatory=$true)][String]$projectName)
{
	Write-Host "`nPlease enter the web site related information to create the site."
	$global:siteName = Read-Host "`nPlease enter website name for $projectName (Ex: IntegTool) "
	$portNumber = Read-Host "`nPlease enter the port number which the site will run on IIS (Ex: 8011,8012,80..) "
	$physicalPathForClinet = $clientCodePath;
	
	Write-Host "`nLocal path of client code : '$physicalPathForClinet'"
	Write-Host "`nCreating application pool for the site '$siteName' in IIS"

	try
	{
		if(Test-Path $physicalPathForClinet)
		{
			if(Test-Path ("IIS:\AppPools\"+$siteName))
			{
				Write-Host "AppPool is already there..!"
			}
			else
			{
				Write-Host "`nAppPool is not present."
				Write-Host "`nCreating new AppPool..."
				New-WebAppPool $siteName -Force
				Write-Host "`nCreating Application pool in IIS is successful."
			}
			
			if(Test-Path ("IIS:\Sites\"+$siteName)){
				Write-Host "`nSite with the name already exist, removing the existing site." -ForegroundColor Red
				Stop-Website -Name $siteName
				Remove-Website -Name $siteName
			}
			
			Write-Host "`nCreating web site based on the provided information..."
			New-Website -Name $siteName -Port $portNumber -PhysicalPath $physicalPathForClinet -ApplicationPool $siteName
			Stop-Website -Name $siteName
			Write-Host "`nWeb site created successfully."
		}
		else
		{
			Write-Error "`nPath '$physicalPathForClinet' is not valid.`nStopping web deployment."
			Undo-Changes "Path to client folder is not valid."
		}
		
		Create-WebApplication
		
		$global:dataBaseServerName = Read-Host "`nPlease enter database server name to update connection string in config file "
		$global:dataBaseInstanceName = Read-Host "`nPlease enter database instance name to update connection string in config file "
		#$global:userNameForDB = Read-Host "`nPlease enter database user name to update connection string in config file"
		#$global:passwordForDB = Read-Host "`nPlease enter database password to update connection string in config file"
        
        $serverWebConfigFile = $serverCodePath + "\Web.config"
		Write-Host "`nUpdating the configuration file."
        if(Test-Path $serverWebConfigFile)
		{
			Update-ConnectionString -inputFilePath $serverWebConfigFile -connectionStringName "IntegrationToolDB"
		}
		else
		{
			Write-Error "`nPath '$serverWebConfigFile' is not valid."   
		}
	}
	catch
	{
		Write-Error -Message $_.Exception.Message
		Undo-Changes $_.Exception.Message
	}
	
	$protocol = Read-Host "`nPlease enter the website protocol (either http or https) for $projectName "
    $setRegisteredDomain = "`nWant to set the domain url (y/n) "
    if($setRegisteredDomain.ToLowerInvariant() -eq "y"){
	    $domainName = Read-Host "`nPlease enter the domain name which the site will run in the server (Ex: abc.com, rapid.com, domain.com...,)  for $projectName "
    }
    else
    {
        $domainName = [System.Net.Dns]::GetHostName().ToLower()
    }
	$hostName = $domainName	
	$global:serviceEndPoint = $protocol+"://"+$hostName+":"+"$portNumber/$serviceName/api"
	
	Write-Host "`nApplication service end point URL : '$serviceEndPoint'"
	
	$commonJsFilePath = $physicalPathForClinet + "\Scripts\commonjs-bundle.min.js"
	
	$jsContent = (Get-Content $commonJsFilePath)
	$jsContent -replace "{ApiBaseUrl}", $serviceEndPoint | Out-File $commonJsFilePath
	
    if($protocol.ToLowerInvariant() -eq "https")
	{
		New-WebBinding -name $siteName -Protocol $protocol -HostHeader $hostname -Port $portNumber -SslFlags 1
	}
	else
	{
		New-WebBinding -name $siteName -Protocol $protocol -HostHeader $hostname -Port $portNumber
	}

    $setIdentity = Read-Host "`nWant to set application pool identity (y/n) "
    if($setIdentity.ToLowerInvariant() -eq "y")
    {
        Set-Application-Pool-Identity
    }
	
    Write-Host "`nStarting web application..."
	Start-Website -Name $siteName
	Write-Host "`nSite is up and running now...." -ForegroundColor Green
	Write-Host "`nDeployment is completed.!" -ForegroundColor Green
}

# Deployment script for Client Acquisition Portal.
Write-Host "`nStarted executing the web deployment script"
Write-Host "`nCreating the existing iis configuration backup (host related only)"

try
{
    $backUpName = "WebConfigurationBackUp"
    Write-Host "`nCreating backup with the name '$backUpName'"
    $backup = Get-WebConfigurationBackup -Name $backUpName
    if($backup)
    {
        Write-Host "`nWeb configuration backup exists with the name $backUpName"
        Write-Host "`nRemoving existing backup..." -ForegroundColor Red
        Remove-WebConfigurationBackup -Name $backUpName
    }
    Backup-WebConfiguration -Name $backUpName
    Write-Host "`nWeb configuration backup created successfully." -ForegroundColor Green
    
    $publishedZipPath = Read-Host "`nEnter the path of the code to be deployed(zip file path with .zip as extension) "
    
    while(-not (($publishedZipPath -ne "") -and (Test-Path $publishedZipPath) -and ([System.IO.Path]::GetExtension("$publishedZipPath") -eq ".zip")))
    {
    
        Write-Host "`nEntered path is invalid..!"
        $publishedZipPath = Read-Host "`nPlease enter valid zip file path "
    }
    
    $pathToUnzipTheFiles = Read-Host "`nEnter path to create the application folder and copy files (Ex: D:\FolderName) "
    while($pathToUnzipTheFiles -eq "")
    {
        if(-not (Test-Path $pathToUnzipTheFiles -PathType Container)){
            Write-Host "`nEntered path is not available."
            $yesOrNo = Read-host "`nProceeding will create the folder, Would you like to continue (Y/N)? "
            if($yesOrNo.ToLowerInvariant() -eq "n"){
                Write-host "`nStopping web deployment script..!"
                Undo-Changes -message "Stopped the deployment process by entering N/n."
            }
        }
    }
    
    Write-Host "`nFile from '$publishedZipPath' will be extracted to '$pathToUnzipTheFiles'"
    $yesOrNo = Read-Host "`nWould you like to continue(Y/N)? "
    if($yesOrNo -eq "n"){
        Write-Host "`nTerminating the deployment process...!"
        return
    }
    
    if(Test-Path $pathToUnzipTheFiles){
        Write-Host "`nFiles in the path '$pathToUnzipTheFiles' will be removed...!"
        if((Get-Item $pathToUnzipTheFiles).Parent.Name)
        {
            Write-Host "`nRemoving folders and files from '$pathToUnzipTheFiles'"
            Remove-Item $pathToUnzipTheFiles -Force -Recurse
            $global:basePath = $pathToUnzipTheFiles
        }
        else
        {
            Write-Host "`nNo folders or files available in '$pathToUnzipTheFiles' to remove"
            $global:basePath = $publishedZipPath.Substring(0, $file.LastIndexOf('.'))
        }
    }
	else
	{
		$global:basePath = $pathToUnzipTheFiles
	}
}
catch
{
    Undo-Changes $_.Exception.Message
}

# Extracting files from published zipped folder.

Write-Host "`nExtracting files from zip folder...!"
$shellVersion = $PSVersionTable.PSVersion.Major
try{
    if($shellVersion -ge 5)
    {
        Expand-Archive $publishedZipPath -DestinationPath $pathToUnzipTheFiles
    }
    else
    {
        Unzip $publishedZipPath $pathToUnzipTheFiles
    }
    Write-Host "`nFile extraction successful." -ForegroundColor Green
	$global:clientCodePath = $basePath+"\Client"
    $global:serverCodePath = $basePath+"\Server"
}
catch{
    Write-Error "`nFiles extraction failed..!"
    Undo-Changes $_.Exception.Message
}

Create-WebSite -projectName "IntegrationTool"