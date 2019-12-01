<# 
.SYNOPSIS 
 shared functions for Graph Wrapper scipts and commandlets
 
.DESCRIPTION 
 This contains shared functions for the other Neo4j scripts
 String, registry storage/retrieval, and logging functions 

.NOTES 
┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
│ bg-sharedfunctions.ps1                                                                      │ 
├─────────────────────────────────────────────────────────────────────────────────────────────┤ 
│   DATE        : 11.03.2019 				               									  │ 
│   AUTHOR      : Paul Drangeid 			                   								  │ 
│   SITE        : https://blog.graphcommit.com/                                               │ 
└─────────────────────────────────────────────────────────────────────────────────────────────┘ 
#> 

# Prepare to allow events written to the Windows EventLog.  Create the Eventlog SOURCE if it is missing.

Function Initialize-EventLog{
    #$srccmdline=$($MyInvocation.MyCommand.Name)

    $logFileExists = Get-EventLog -list | Where-Object {$_.logdisplayname -eq $srccmdline} 
    if (! $logFileExists) {
        New-EventLog -LogName Application -Source $srccmdline -erroraction 'silentlycontinue'}
    }

Function update-eventlog {
	  param(
		  [Parameter(Position = 0, Mandatory = $true)]
		  [String]$Message
		  ,	
		  [Parameter(Position = 1, Mandatory = $false)]
		  [String]$EntryType
		  )
  process {
Write-Host "Write-EventLog -LogName Application -Source $srccmdline -EntryType $EntryType -EventId 5980 -Message $Message"
    
  Write-EventLog -LogName Application -Source $srccmdline -EntryType $EntryType -EventId 5980 -Message $Message
  }
  }

Function LogError($e,[String]$mymsg,[String]$section){
    $msg = $e.Message
    while ($e.InnerException) {
      $e = $e.InnerException
      $msg += "`n" + $e.Message
      }
    $warningmessage=$($section)+" - "+$($mymsg)+" - "+$($msg)
    if ($warningmessage -like "*Failed to connect to server*") {
        Write-Warning "Failed to connect to Neo4j server.  Aborting..."
        update-eventlog -message $warningmessage -entrytype "Error"
        BREAK
    }
    Write-Warning $warningmessage
    update-eventlog -message $warningmessage -entrytype "Error"
    }
function Cypherlog([String]$x){
    if (![string]::IsNullOrEmpty($logging)) {
    try {
        $logresult = $logsession.Run($x)
        $logresult | ForEach-Object {
            if (![string]::IsNullOrEmpty($($_["scriptid"]))) {  $global:scriptid=$($_["scriptid"])}
        }
      } # End Try
      Catch{
          LogError $_.Exception "Logging results." "Could not Write Log entry`n $x `nto $logging"
      BREAK
      } # End Catch
    } # End If ($logging)
}

function AmINull([String]$x) {
        if ($x) {return $false} else {return $true}
      }

# Check if registry key and value exist.  If they don't exist and the "DefValue" is not null then create the key/path with the supplied default value. 
      Function Ver-RegistryValue {
        param(
            [Parameter(Position = 0, Mandatory = $true)]
            [String]$RegPath
            ,
            [Parameter(Position = 1, Mandatory = $true)]
            [String]$Name
            ,
            [Parameter(Position = 2, Mandatory = $false)]
            [String]$DefValue
            ,
            [Parameter(Position = 3, Mandatory = $false)]
            [String]$RegValType
        ) 
     process {
        if ([string]::IsNullOrEmpty($RegValType) -or !$RegValType){$RegValType="String"}
     if (Test-Path $RegPath) {
                $Key = Get-Item -LiteralPath $RegPath
                if ($null -ne $Key.GetValue($Name, $null)) {
                    Show-onscreen "(Get-ItemProperty -Path Get-ItemProperty -Path $regpath -Name $Name).$Name" 5
                    return (Get-ItemProperty -Path $regpath -Name $Name).$Name 			
                    } else
                    {
                    if (![string]::IsNullOrEmpty($DefValue)) {
                        Show-onscreen "(New-ItemProperty -Path $RegPath -Name $Name -Value $DefValue -Type $ValType" 5
                    New-ItemProperty -Path $RegPath -Name $Name -Value $DefValue -PropertyType $RegValType -Force | Out-Null
                    return $DefValue
                    } }
            } else {
            if (![string]::IsNullOrEmpty($DefValue)) {
            Show-onscreen "(New-Item $RegPath then:New-ItemProperty -Name $Name -Value $DefValue -Type $ValType -Force " 5
            New-Item $RegPath -Force | New-ItemProperty -Name $Name -Value $DefValue -PropertyType $RegValType -Force | Out-Null
            return $DefValue
            }
        } # End If Test-Path
        return $null 
    } # End Process
    } # End Function

function Test-RegistryValue([String]$TestPath,[String]$TestValue){
    try {
    #Get-ItemProperty -Path $TestPath | Select-Object -ExpandProperty $TestValue -ErrorAction Stop | Out-Null
    Get-ItemProperty -Path $TestPath -Name $TestValue -ErrorAction Stop | Out-Null
        return $true
        }
    catch {
    return $false
    }
    } # End Function (Test-RegistryValue)
# With the supplied registry path and value name, retrieve the secured value, and convert to clear text (for use with URL or API call)
Function Get-SecurePassword([String]$pwpath,[String]$RegValName){
    Try{
    $regsecurestring = Ver-RegistryValue -RegPath $pwpath -Name $RegValName -DefValue $null
    if ($null -eq $regsecurestring){
        Write-Warning "Unable to retrieve securestring from $pwpath"
        return $false
    }
    $securepassword = $regsecurestring | ConvertTo-SecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
    Catch{
    LogError $_.Exception "Sorry, unable to retrieve password from value $RegValName via $pwpath.  Password retrieval requires execution as the same user as when password was stored." "Get-SecurePassword"
    BREAK
    }
    Return $UnsecurePassword
    # End of Function
}
Function Set-SecurePassword([String]$pwpath,[String]$UsrValName,[String]$PWValName,[String]$theusername,[String]$UnsecurePW){
    Set-ItemProperty -Path $pwpath -Name $RegValName -Value $theusername -Force #| Out-Null
    $secure = ConvertTo-SecureString $UnsecurePW -force -asPlainText 
    $bytes = ConvertFrom-SecureString $secure
    Set-ItemProperty -Path $pwpath -Name $PWValName	-Value $bytes -Force #| Out-Null
    Remove-Variable -name unsecurepw | Out-Null
    Remove-Variable -name secure | Out-Null
    Remove-Variable -name bytes | Out-Null
}# End Function Set-SecurePassword
Function Get-Set-Credential {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [String]$CredName
        ,
        [Parameter(Position = 1, Mandatory = $true)]
        [String]$RegPath
        ,
        [Parameter(Position = 2, Mandatory = $true)]
        [String]$UserValName
        ,
        [Parameter(Position = 3, Mandatory = $true)]
        [String]$PWValName
        ,
        [Parameter(Position = 4, Mandatory = $false)]
        [Boolean]$Promptpwchange
        ,
        [Parameter(Position = 5, Mandatory = $false)]
        [String]$DefUserName
        ,
        [Parameter(Position = 6, Mandatory = $false)]
        [String]$DialogPrompt          
        ) 
    
process{
    $defval = if ($DefUserName -eq $null) { "User" } else { $DefUserName }
    $PWUIDialog = if ($DialogPrompt -eq $null) { "Enter your credentials." } else { $DialogPrompt }
    #First see if we already have credentials stored in the registry
    #$RegPath=$($RegPath+"\")
    if ((Test-RegistryValue $RegPath $UserValName) -and (Test-RegistryValue $RegPath $PWValName)){
        if ($Promptpwchange -eq $false){return $true}
        $intsetacct=-1
        if (YesorNo "Would you like to update the credentials used for [$CredName]?" "Update Credentials") {
        $intsetacct=1
        }# End YesorNo
    } # End if (username AND password stored in registry)
    if ($intsetacct -eq -1){
        #$credUser = Ver-RegistryValue -RegPath $Path -Name $UserValName -DefValue $defval
        #$credPW = Get-SecurePassword $RegPath $PWValName 
        Ver-RegistryValue -RegPath $RegPath -Name $UserValName -DefValue $defval
        Get-SecurePassword $RegPath $PWValName 
        }
    if ($intsetacct -ne -1){
        #$credUser = Ver-RegistryValue -RegPath $RegPath -Name $UserValName -DefValue $defval
        Ver-RegistryValue -RegPath $RegPath -Name $UserValName -DefValue $defval
        #write-host "about to get-cred... $PWUIDialog" 
        #$cred = Get-Credential -Credential $defval -Message $($PWUIDialog) -Title $("$CredName credential request")
        $cred = $host.ui.PromptForCredential("$CredName credential request", $PWUIDialog, $defval,"")
        #$justuser=$cred.username
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.password))
        if (AmINull $($password.trim()) -eq $true) {
        Write-Host "$CredName user password cannot be blank."
        return $false
        } # End if provided password was blank/null
        } # End if $intsetacct -ne -1
    if ($intsetacct -ne -1){
        # -1 means we already validated the registry contains the user/password, and the user doesn't want to change them
    
        Set-ItemProperty -Path $regpath -Name $UserValName	-Value $cred.username -Force #| Out-Null
        $secure = ConvertTo-SecureString $password -force -asPlainText 
        $bytes = ConvertFrom-SecureString $secure
        Set-ItemProperty -Path $regpath -Name $PWValName -Value $bytes -Force #| Out-Null
        }
        
        return $true
}#End Process
}#End Function Get-Set-Credential

Function AddRegPath([String]$regpath){
    $testpathresult = Test-Path -Path $regpath
    if($testpathresult -eq $false){
    try{
            New-Item -Path $regpath -ItemType Key -Force #| Out-Null
            }
    Catch{
    LogError $_.Exception "Adding missing key to registry" "Verify Existance of registry key $regpath"
    BREAK
    }
    }
    }

    Function get-portvalidation([string]$hostorip,[int]$tcpport){
        $ErrorActionPreference = 'Silently Continue'
        $tcpobject = new-Object system.Net.Sockets.TcpClient 
        #$connect = $tcpobject.BeginConnect($hostorip,$tcpport,$null,$null) 
        #$wait = $connect.AsyncWaitHandle.WaitOne(1000,$false) 
        
        #$connection = New-Object System.Net.Sockets.TcpClient($hostorip, $tcpport)
        $connect = $tcpobject.BeginConnect($hostorip,$tcpport,$null,$null) 
        $wait = $connect.AsyncWaitHandle.WaitOne(1000,$false) 
        If (-Not $Wait) {
            #'Timeout'
            return $false
        } Else {
            $error.clear()
            $tcpobject.EndConnect($connect) | out-Null 
            If ($Error[0]) {
                return $false
            } Else {
                # port responded!
                return $true
            } # Port responded
        } #End if error
    
    }# End Function get-portvalidation
    Function Show-onscreen([String]$themessage,[int]$verblevel) {
        #write-host "this message req verbosity of $verblevel"
    if ($verbosity -ge $verblevel) {
        Write-Host $themessage
    }
    } #End function Sendto-screen
Function YesorNo([String]$thequestion,[String]$thetitle) {
    Add-Type -AssemblyName System.Windows.Forms
    #$a = new-object -comobject wscript.shell
    #$intAnswer = $a.popup($thequestion,0,$thetitle,4)
    $intAnswer = [System.Windows.Forms.MessageBox]::Show($thequestion, $thetitle, 'YesNo', 'Warning')
    If ($intAnswer -eq 6) {
        return $true
    } else {
        return $false
    }
    }
Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "DLL (*.dll)| *.dll"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

function Get-N4jdriver {
    
    if (!(Get-Command "nuget.exe" -ErrorAction SilentlyContinue) )
        { # We couldn't find nuget.exe - probably need to download it
        $downloadnuget=YesorNo $("We couldn't find the package manager 'NuGet'.  Would you like me to install it for you"+"?") "NuGet Package manager required."
        if ($downloadnuget -eq $false){
            return $false
            }
        if ($downloadnuget -eq $true){
            write-host "NuGet DotNET package manager is a dependency to install the Neo4j driver.`n"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
            }
        }# end if (couldn't find nuget.exe)
    write-host "Installing package 'Neo4j.Driver'.`n"
    install-package Neo4j.Driver -source https://www.nuget.org/api/v2 -skipdependencies

}# End function get-n4jdriver

function GetKEY([String]$pwpath,[String]$RegValName,[String]$UIPrompt){
    if (Test-RegistryValue $pwpath $RegValName){
    Show-onscreen "$pwpath $RegValName is valid, so requesting SecurePassword Retrieval" 4
    $GUID = Get-SecurePassword $($pwpath) $RegValName
    }
        
    # No Key, so we need to prompt for input
    if ([string]::IsNullOrEmpty($GUID))  {
    Show-onscreen "Requesting user to supply $RegValName `n $UIPrompt" 2
    $password=$Host.ui.PromptForCredential("UID Key Request",$UIPrompt,$RegValName,"")
    if ([string]::IsNullOrEmpty($password.password)) {
    Write-Host "No $RegValName provided or dialog cancelled.   Exiting script..."
    BREAK
    }
    $SecureString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password.password))
    $secure = ConvertTo-SecureString $SecureString -force -asPlainText 
    $bytes = ConvertFrom-SecureString $secure
    #write-host "Add to path:$($Path+$tenantdomain) -Name $RegValName -DefValue 'thebytes' registry"
Ver-RegistryValue -RegPath $($Path+$tenantdomain) -Name $RegValName -DefValue $bytes | Out-Null

Remove-Variable bytes
Remove-Variable password
Remove-Variable secure
Remove-Variable securestring
# Now the reg value is NOT empty
}

Try
{
$GUID = Get-SecurePassword $($pwpath) $RegValName
}
Catch
{
$ErrorMessage = $_.Exception.Message
    #$FailedItem = $_.Exception.ItemName
    Write-Host "Retrieve key from registry Failed! We failed to read key from $($pwpath). The error message was '$ErrorMessage'  It is likely that you are not running this script as the original user who saved the secure key value."
    Break
}
return $GUID
# End of Function
}

Function Loadn4jdriver {
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
    $ValName = "N4jDriverpath"
    $Path = "HKCU:\Software\neo4j-wrapper\Datasource"
    $Neo4jdriver = Ver-RegistryValue -RegPath $Path -Name $ValName
    write-host "Loading Neo4J Driver: $Neo4jdriver"
    if (AmINull $($Neo4jdriver) -eq $true){
        write-host "No Path for Neo4j Driver provided.   Exiting setup...`nFor help loading the neo4j dotnet drivers please visit: https://glennsarti.github.io/blog/using-neo4j-dotnet-client-in-ps/"
        BREAK
        }

    Try{
    # Import DLLs
    Add-Type -Path $Neo4jdriver
    }
    Catch{
        LogError $_.Exception "Loading Neo4j drivers." "Could not load Neo4j dlls from $Neo4jdriver.`nFor help please visit: https://glennsarti.github.io/blog/using-neo4j-dotnet-client-in-ps/ 
        `nIf you've already followed these instructions and are receiving an error, you may need to update your dotnet framework: https://dotnet.microsoft.com/download/dotnet-framework-runtime/net47"
    BREAK
    }
}
    
    