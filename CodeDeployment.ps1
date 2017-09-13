# Functions...!

Add-Type -AssemblyName System.IO.Compression.FileSystem
Import-Module WebAdministration

#Global variables...
$basePath = ""
$clientCodePath = ""
$serverCodePath = ""

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
        $con.connectionString = $con.connectionString -replace "{DATABASESERVER}", $dataBaseServerName -replace "{DATABASEINSTANCE}", $dataBaseInstanceName -replace "{USERNAME}", $userName -replace "{PASSWORD}", $password
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
    $serviceName = Read-Host "`nWeb API application name (Ex: Server, Service...,)"
    Write-Host "`nPhysical location of API code : '$serverCodePath'"
    New-WebApplication -Name $serviceName -Site $siteName -PhysicalPath $serverCodePath -ApplicationPool $siteName
 }

 function Update-ClientAppSettingsConfig()
 {
    $clientConfigPath = ($clientCodePath + "\Web.config")
    $clientXml = [xml](Get-Content $clientConfigPath)
    $node = $clientXml.SelectSingleNode('configuration/appSettings/add[@key="WebAPIURL"]')
    $node.Attributes['value'].Value = $serviceEndPoint
    $node = $clientXml.SelectSingleNode('configuration/appSettings/add[@key="AdminDomainPrefix"]')
    $node.Attributes['value'].Value = $adminSitePrefix
    $clientXml.Save($clientConfigPath)
 }

 function Update-ServerWebConfig([string]$nodePrefix,[hashtable]$hashValues)
 {
    $serverXml = [xml](Get-Content $serverWebConfigFile)
    foreach($key in $hashValues.keys)
    {
        $node = $serverXml.SelectSingleNode($nodePrefix+'/add[@key="'+$key+'"]')
        $node.Attributes['value'].Value = $hashValues[$key]  
    }
    $serverXml.Save($serverWebConfigFile)
 }

 function Update-SmtpConfig([string]$configFilePath, [hashtable]$hashValues)
 {
    $configXml = [xml](Get-Content $configFilePath)
    $smtpNode = $configXml.configuration.'system.net'.mailSettings.smtp
    $smtpNode.from = [string]$hashValues["from"]
    $smtpNode.network.host = [string]$hashValues["host"]
    $smtpNode.network.port = [string]$hashValues["port"]
    $smtpNode.network.userName = [string]$hashValues["userName"]
    $smtpNode.network.password = [string]$hashValues["password"]
    $smtpNode.network.enableSsl = [string]$hashValues["enableSsl"]
    $configXml.Save($configFilePath)
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
    
    $pathToUnzipTheFiles = Read-Host "`nEnter path to create the application folder and copy files(Ex: D:\CAP) "
    
    while($pathToUnzipTheFiles -eq "")
    {
        if(-not (Test-Path $pathToUnzipTheFiles -PathType Container)){
            Write-Host "`nEntered path is not available."
            $yesOrNo = Read-host "`nProceeding will create the folder, Would you like to continue (Y/N)?"
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
            $basePath = $pathToUnzipTheFiles
        }
        else
        {
            Write-Host "`nNo folders or files available in '$pathToUnzipTheFiles' to remove"
            $basePath = $publishedZipPath.Substring(0, $file.LastIndexOf('.'))
        }
    }
	else
	{
		$basePath = $pathToUnzipTheFiles
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
    $clientCodePath = $basePath+"\Client"
    $serverCodePath = $basePath+"\Server"
}
catch{
    Write-Error "`nFiles extraction failed..!"
    Undo-Changes $_.Exception.Message
}

Write-Host "`nPlease enter the web site related information to create the site."
$siteName = Read-Host "`nPlease enter website name (Ex: CAP)"
$portNumber = Read-Host "`nPlease enter the port number which the site will run on IIS (Ex: 8011,8012,80..) "
$physicalPathForClinet = $clientCodePath
Write-Host "`nLocal path of client code : '$clientCodePath'"
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

    # Block to update client Web.config file...
    $clientWebConfigFile = $clientCodePath+"\Web.config"
	$dataBaseServerName = Read-Host "`nPlease enter database server name to update connection string in config file"
    $dataBaseInstanceName = Read-Host "`nPlease enter database instance name to update connection string in config file "
    $userName = Read-Host "`nPlease enter database user name to update connection string in config file"
    $password = Read-Host "`nPlease enter database password to update connection string in config file"
    if(Test-Path $clientWebConfigFile)
    {
        Update-ConnectionString -inputFilePath $clientWebConfigFile -connectionStringName "Hangfire_Blog"
    }
    else
    {
        Write-Error "`nPath '$clientWebConfigFile' is not valid. Stopping web deployment..!"
        Undo-Changes "Path to config file is not valid."
    }
}
catch
{
    Write-Error -Message $_.Exception.Message
    Undo-Changes $_.Exception.Message
}

# Block to update server Web.config file...
$serverWebConfigFile = $serverCodePath + "\Web.config"
Write-Host "`nUpdating the configuration file."
try
{
    if(Test-Path $serverWebConfigFile)
    {
        Update-ConnectionString -inputFilePath $serverWebConfigFile -connectionStringName "RapidMobileDB"
    }
    else
    {
        Write-Error "`nPath '$clientWebConfigFile' is not valid."   
    }
}
catch
{
    Write-Error "`nFailed to update the connection string.`nError details as below." 
}

$protocol = Read-Host "`nPlease enter the website protocol (either http or https) "
$domainName = Read-Host "`nPlease enter the domain name which the site will run in the server (Ex: abc.com, rapid.com, domain.com...,)"
$adminSitePrefix = Read-Host "`nPlease enter the adminsite prefix name which the admin site will be identified (Ex: admin)"
$hostName = $adminSitePrefix+"."+$domainName
$serviceEndPoint = $protocol+"://"+$hostName+"/Service/api/v2"
Write-Host "`nApplication service end point URL : '$serviceEndPoint'"

$commonJsFilePath = $clientCodePath + "\Scripts\common-app-bundle.min.js"
$jsContent = (Get-Content $commonJsFilePath)
$jsContent -replace "{ApiBaseUrl}", $serviceEndPoint -replace "{AdminSitePrefix}",$adminSitePrefix | Out-File $commonJsFilePath

New-WebBinding -name $siteName -Protocol $protocol  -HostHeader $hostname -Port $portNumber -SslFlags 1
Update-ClientAppSettingsConfig

#Getting values from users to update the server Web.config file...
Write-Host "`nPlease enter the details below to update the values to the Web.config file."
Write-Host "Please enter the application setting section details as below."
Write-Host "`nPlease enter the below details for communicating with FSV API."
$appSettings = @{}
#FSV related details...
$appSettings["FSVUserName"] = Read-Host "`nFSV user name"
$appSettings["FSVPassword"] = Read-Host "FSV password "
$appSettings["FSVCardRegistrationURL"] = Read-Host "FSV Card Registration URL "

#Sub-Company request to mail id...
Write-Host "`nEnter the below detail for sending sub-company creation request file."
$appSettings["FSVMail"] = Read-Host "`nSub Company creation email id which the file will be send to that id "

#FSV input file details...
Write-Host "`nPlease enter the below section details to send as part of sub company request to FSV"
$appSettings["FSVStreetAddress"] = Read-Host "`nStreet Address "
$appSettings["FSVSuite"] = Read-Host "Suite "
$appSettings["FSVCity"] = Read-Host "City "
$appSettings["FSVState"] = Read-Host "State "
$appSettings["FSVZipCode"] = Read-Host "ZipCode "
$appSettings["FSVCountry"] = Read-Host "Country "
$appSettings["FSVContactMail"] = Read-Host "ContactMail "
$appSettings["FSVContactPhone"] = Read-Host "ContactPhone "

Write-Host "`nPlease enter the below section details to communicate with ATM API"
#ATM Api details...
$appSettings["ClientId"] = Read-Host "`nClient Id "
$appSettings["ClientSecret"] = Read-Host "Client Secret "
$appSettings["ATMUserName"] = Read-Host "ATM User Name "
$appSettings["ATMPassword"] = Read-Host "ATM Password "
$appSettings["ATMAuthenticationURL"] = Read-Host "ATM Authentication URL "
$appSettings["ATMLocatorURL"] = Read-Host "ATM Locator URL "

Write-Host "`nPlease enter the below section details to communicate with FSV SFTP"
#SFTP details...
$appSettings["SFTPServer"] = Read-Host "`nSFTP Server Name "
$appSettings["SFTPPort"] = Read-Host "SFTP Port "
$appSettings["SFTPUserName"] = Read-Host "SFTP User Name "
$appSettings["SFTPPassword"] = Read-Host "SFTP Password "

#Email verification url...
Write-Host "`nPlease enter the below section details to communicate with experian email api"
$appSettings["EmailVerificationURL"] = Read-Host "`nEmail Verification URL "

#Address verification url...
Write-Host "`nPlease enter the below section details to communicate with experian address validation"
$appSettings["QASWSDLUrl"] = Read-Host "`nQAS WSDL Url "

#FSV Sub-Company response mail read settings...
Write-Host "`nPlease enter the below section details to read the sub company respose received from FSV system"
$appSettings["Host"] = Read-Host "`nHost Name "
$appSettings["Port"] = Read-Host "Port "
$appSettings["UseSsl"] = Read-Host "UseSsl "
$appSettings["MailId"] = Read-Host "MailId "
$appSettings["Mailpassword"] = Read-Host "Mail password "

#Write-Host "`nBelow are the details provided to update the appSettings in Web.config file `nMake sure provided details are valid."
#$appSettings
Update-ServerWebConfig -nodePrefix "configuration/appSettings" -hashValues $appSettings
Write-Host "Application settings section updated successfully." -ForegroundColor Green

#SMTP email config...
Write-Host "`nPlease enter the details for SMTP email config section (to send all emails like NewUser,OTP,Password Update.,)."
$smtpSettings = @{}
$smtpSettings["from"] = Read-Host "`nFrom address "
$smtpSettings["host"] = Read-Host "`nHost "
$smtpSettings["port"] = Read-Host "`nPort "
$smtpSettings["userName"] = Read-Host "`nUser Name "
$smtpSettings["password"] = Read-Host "`nPassword "
$smtpSettings["enableSsl"] = Read-Host "`nEnableSsl (either true/false) "

#Write-Host "`nBelow are the details provided to update the SMTP section in Web.config file `nMake sure provided details are valid."
#$smtpSettings
Update-SmtpConfig -configFilePath $serverWebConfigFile -hashValues $smtpSettings
Write-Host "SMTP config section updated successfully." -ForegroundColor Green

#SubCompanyConfig...
Write-Host "`nPlease enter the details for subcompany config section.(These are all static values will be send as part of sub company creation request)"
$subCompanyConfig = @{}
$subCompanyConfig["Company"] = Read-Host "`nCompany "
$subCompanyConfig["Country"] = Read-Host "`nCountry "
$subCompanyConfig["RemitterDescription"] = Read-Host "`nRemitter Description "
$subCompanyConfig["InitialOrderPoint"] = Read-Host "`nInitial Order Point "
$subCompanyConfig["ReorderPoint"] = Read-Host "`nReorder Point "
$subCompanyConfig["ReorderQuantity"] = Read-Host "`nReorder Quantity "
$subCompanyConfig["ContactFirstName"] = Read-Host "`nContact First Name "
$subCompanyConfig["ContactLastName"] = Read-Host "`nContact Last Name "
$subCompanyConfig["ContactMail"] = Read-Host "`nContact  Mail "
$subCompanyConfig["ContactPhone"] = Read-Host "`nContactPhone "
$subCompanyConfig["ShippingMethod"] = Read-Host "`nShipping Method "
$subCompanyConfig["ServiceType"] = Read-Host "`nService Type "
$subCompanyConfig["FulFillmentVendor"] = Read-Host "`nFulFillment Vendor "

#Write-Host "`nBelow are the details provided to update the subCompanyConfig section in Web.config file `nMake sure provided details are valid."
#$subCompanyConfig
Update-ServerWebConfig -nodePrefix "configuration/subCompanyConfig" -hashValues $subCompanyConfig
Write-Host "Sub Company config section updated successfully." -ForegroundColor Green

#SFMC Email Config...
Write-Host "`nPlease enter the details for SFMC EMail relay service config section."
$sfmcConfig = @{}
$sfmcConfig["EmailMode"] = Read-Host "`nEmailMode (SMTP/SFMC)?  "
$sfmcConfig["ClientId"] = Read-Host "`nClient Id "
$sfmcConfig["ClientSecret"] = Read-Host "`nClient Secret "
$sfmcConfig["AccessTokenUrl"] = Read-Host "`nAccess Token Url "
$sfmcConfig["SendDefinitionUrl"] = Read-Host "`nSend Definition Url "

#Write-Host "`nBelow are the details provided to update the sfmcConfig section in Web.config file `nMake sure provided details are valid."
#$sfmcConfig
Update-ServerWebConfig -nodePrefix "configuration/sfmcEmailConfig" -hashValues $sfmcConfig
Write-Host "SFMC config section updated successfully." -ForegroundColor Green

Write-Host "`nStarting web application..."
Start-Website -Name $siteName
Write-Host "`nSite is up and running now...." -ForegroundColor Green
Write-Host "`nDeployment is completed.!" -ForegroundColor Green