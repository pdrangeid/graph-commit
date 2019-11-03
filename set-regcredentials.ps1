<# 
.SYNOPSIS 
 Configure credentials and (secure-string) store them in the registry.
 
.DESCRIPTION 
 This script must be run as the account that will be used to run tasks that connect and query
 to resources that need credentials. The password is converted into a securestring object and stored in the registry,
 and only retreivable by the same (user) account.

  ***Please be aware, securestring storage is only as secure as the machine and users operating
 (or with access to) it. If you have access to the scripts, and some level of local administrative privilleges,
 it is a trivial task to alter the scripts in order to recover/retrieve the original text of the stored
 securestring values.  As best security practices demand, these stored credentials should only provide the least
 privillege required to accomplish the task.

 Any processes that store/retrieve these values should ONLY be stored and run on a secured and limited-access
 endpoint, with a secured service account.

 
.NOTES 
┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
│ set-regcredentials.ps1                                                                      │ 
├─────────────────────────────────────────────────────────────────────────────────────────────┤ 
│   DATE        : 10.13.2019												     			  │ 
│   AUTHOR      : Paul Drangeid 															  │ 
└─────────────────────────────────────────────────────────────────────────────────────────────┘ 
 
#> 
param (
    [string]$credname,
    [string]$credpath,
    [string]$defaultuser,
    [switch]$n4j,
    [switch]$noui,
    [int]$verbosity
    )

$scriptname=$($MyInvocation.MyCommand.Name)

if ($noui -eq $true -and $null -eq $verbosity){[int]$verbosity=0} #noui switch sets output verbosity level to 0 by default
if ($null -eq $verbosity){[int]$verbosity=1} #verbosity level is 1 by default
if (!([string]::IsNullOrEmpty($credpath))){
$credpath="HKCU:\Software\$credpath\$credname"
$credpath=$credpath.replace('\\','\')
}
if ([string]::IsNullOrEmpty($credpath) -and $n4j -eq $true){[string]$credpath="HKCU:\Software\neo4j-wrapper\Datasource"}
if ([string]::IsNullOrEmpty($credpath)){[string]$credpath="HKCU:\Software\Mycredentials\$credname"}
if ([string]::IsNullOrEmpty($defaultuser) -and $n4j -eq $true){[string]$defaultuser="neo4j"}
if ([string]::IsNullOrEmpty($defaultuser)){[string]$defaultuser="Username"}

write-host "early credpath is $credpath"

Try{. "$PSScriptRoot\bg-sharedfunctions.ps1" | Out-Null}
Catch{
    Write-Warning "I wasn't able to load the sharedfunctions includes (which should live in the same directory as $global:srccmdline). `nWe are going to bail now, sorry 'bout that!"
    Write-Host "Try running them manually, and see what error message is causing this to puke: $PSScriptRoot\bg-sharedfunctions.ps1"
    Unregister-PSVars
    BREAK
    }

    if ($n4j -eq $true){
    Write-Host "`nIf this config has been run before (by this user, on this PC), successful settings will be stored in the registry under:"
    Write-Host "HKEY_CURRENT_USER\Software\neo4j-wrapper\Datasource"
    Write-Host "`nThe wizard will use those values, and give you a chance to modify them if you need."
    
    Write-Host "`nFirst we need to verify that we can load the Neo4j dotnet driver..."
    $ValName = "N4jDriverpath"
    $N4jPath = "HKCU:\Software\neo4j-wrapper\Datasource"
    #$Dllpathdef = Ver-RegistryValue -RegPath $N4jPath -Name $ValName -DefValue "C:\Program Files\Neo4jTools\Neo4j.Driver.1.7.2\lib\net452\Neo4j.Driver.dll"
    $Dllpathdef = Ver-RegistryValue -RegPath $N4jPath -Name $ValName -DefValue "C:\Program Files\PackageManagement\NuGet\Packages\Neo4j.Driver.1.7.2\lib\netstandard1.3\Neo4j.Driver.dll"
    if([System.IO.File]::Exists($Dllpathdef)){	$Neo4jdriver =$Dllpathdef }
    if(![System.IO.File]::Exists($Dllpathdef)){
        # file with path $N4jPath doesn't exist
        $Neo4jdriver = Get-FileName $Dllpathdef
    }

    if (AmINull $($Neo4jdriver) -eq $true){
        $downloadn4jdriver=YesorNo $("We couldn't find the Neo4j DotNET driver. Can I install it for you"+"?") "Neo4j DotNET Driver required."
        if ($download4jdriver -eq $false){
            BREAK
        }
        if ($download4jdriver -eq $true){
            $result=get-n4jdriver
                    }

        write-host "No Path for Neo4j Driver provided.   Exiting setup...`nFor help loading the neo4j dotnet drivers please visit: https://glennsarti.github.io/blog/using-neo4j-dotnet-client-in-ps/"
        BREAK
        }
    
    Try{
    # Import DLLs
    Add-Type -Path $Neo4jdriver
    }
    Catch{
        LogError $_.Exception "Loading Neo4j drivers." "Could not load Neo4j dlls from $PSScriptRoot.  For help please visit: https://glennsarti.github.io/blog/using-neo4j-dotnet-client-in-ps/ 
        `n If you've already followed these instructions and are receiving an error, you may need to update your dotnet framework: https://dotnet.microsoft.com/download/dotnet-framework-runtime/net47"
    BREAK
    }
    Set-ItemProperty -Path $N4jPath -Name $ValName -Value $Neo4jdriver -Force #| Out-Null
    Write-Host "Verified Neo4J Driver!"
    

    if ($null -eq $credname){[string]$credname="N4jDataSource"
    $ValName = "LastDSName"	
    AddRegPath $credpath
    $DSNamedef = Ver-RegistryValue -RegPath $credpath -Name $ValName -DefValue $credname
    if (AmINull $($DSNamedef.Trim()) -eq $true ){$DSNamedef="N4jDataSource"}
    }
    if (![string]::IsNullOrEmpty($credname))  {$DSNamedef=$credname}

    Write-Host ""
    Write-Host "A logical name must be provided for this Neo4j Datasource."
    $DSName = [Microsoft.VisualBasic.Interaction]::InputBox('Enter name for this Neo4j Datasource.', 'Neo4j Datasource Name', $($DSNamedef))
    $DSName=$DSName.Trim()
    if (AmINull $($DSName) -eq $true){
    write-host "No Datasource name provided.   Exiting setup..."
    BREAK
    }

    $ValName = "ServerURL"	
    #$Path = "HKCU:\Software\neo4j-wrapper\Datasource\$DSName"
    #AddRegPath $Path
    $Neo4jServerNamedef = Ver-RegistryValue -RegPath $credpath -Name $ValName -DefValue "bolt://localhost:7687"
    if (AmINull $($Neo4jServerNamedef.Trim()) -eq $true ){$Neo4jServerNamedef="bolt://localhost:7687"}
    Write-Host ""
    Write-Host "Define your Neo4j graphDB. "
    $Neo4jServerName = [Microsoft.VisualBasic.Interaction]::InputBox('Enter fully qualified (or IP) address of Neo4j Server that will host the graphDB.', 'Neo4j Server URL', $($Neo4jServerNamedef))
    $Neo4jServerName=$Neo4jServerName.Trim()
    if (AmINull $($Neo4jServerName) -eq $true){
    write-host "No Neo4j Server provided.   Exiting setup..."
    BREAK
    }

    $credpath = "$credpath\$credname"
    $credpath=$credpath.replace('\\','\')
    write-host "credpath is $credpath"
    } # If $n4j switch is enabled

    $creduser=$($credname+"User")
    $credpw=$($credname+"PW")
    if ($n4j -eq $true){
        $creduser=$("DSUser")
        $credpw=$("DSPW")
    }
    Add-Type -AssemblyName Microsoft.VisualBasic
    AddRegPath $credpath
    $result = (Get-Set-Credential $credname $credpath $creduser $credpw $true $defaultuser)
    
    if ($result -eq $true){
    Write-Host "$credname stored successfully."
    }
    
    if ($n4j -eq $true){
        Try{
            $ipaddress=($Neo4JServerName -split "/")[2]
            $queryport=($ipaddress -split ":")[1]
            $ipaddress=($ipaddress -split ":")[0]
            $ipaddress=$(Resolve-DnsName -Type A -Name $ipaddress -ErrorAction Stop).IPAddress
            }
            Catch{
              LogError $_.Exception "Failed address lookup for $Neo4jServerName.  Please verify DNS or verify the server is running.`n"
            }
            Try{
            show-onscreen $("Validating port connectivity for $ipaddress on $queryport") 2
            $result =  get-portvalidation $ipaddress $queryport
            show-onscreen $("Port connectivity results: $result`n") 4
            if ($result -eq $false){
              LogError $_.Exception "Failed port validation to $Neo4jServerName.  Please verify address and firewall rules.`n"
              exit
            }
            }
            Catch{
              LogError $_.Exception "Failed port validation to $Neo4jServerName.  Please verify address and firewall rules.`n"
            }
        Try {
            write-host "Let's test our connection to Neo4j Server $Neo4jServerName."
            $n4jUser = Ver-RegistryValue -RegPath $credpath -Name $creduser
            $n4juPW = Get-SecurePassword $credpath $credpw 
            $authToken = [Neo4j.Driver.V1.AuthTokens]::Basic($n4jUser,$n4juPW)
            $dbDriver = [Neo4j.Driver.V1.GraphDatabase]::Driver($Neo4jServerName,$authToken)
            $session = $dbDriver.Session()
            $result = $session.Run("call dbms.components() yield name, versions, edition unwind versions as version return name, version, edition;")
            $result | fl
            Set-ItemProperty -Path $credpath -Name "ServerURL" -Value $Neo4jServerName -Force #| Out-Null
            Write-Host "Validated Datasource credentials..."
            }
            Catch{
                LogError $_.Exception "Failed to connect to Neo4j Server."
            BREAK
            }
}