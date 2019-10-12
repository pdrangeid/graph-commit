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
    [switch]$noui,
    [int]$verbosity
    )

$scriptname=$($MyInvocation.MyCommand.Name)

if ($noui -and $null -eq $verbosity){[int]$verbosity=0} #noui switch sets output verbosity level to 0 by default
if ($null -eq $verbosity){[int]$verbosity=1} #verbosity level is 1 by default
if (!($null -eq $credpath)){
$credpath="HKCU:\Software\$credpath\$credname"
$credpath=$credpath.replace('\\','\')
}
if ($null -eq $credpath){[string]$credpath="HKCU:\Software\Mycredentials\$credname"}
if ($null -eq $defaultuser){[string]$defaultuser="Username"}

Try{. "$PSScriptRoot\bg-sharedfunctions.ps1" | Out-Null}
Catch{
    Write-Warning "I wasn't able to load the sharedfunctions includes (which should live in the same directory as $global:srccmdline). `nWe are going to bail now, sorry 'bout that!"
    Write-Host "Try running them manually, and see what error message is causing this to puke: $PSScriptRoot\bg-sharedfunctions.ps1"
    Unregister-PSVars
    BREAK
    }

    $creduser=$($credname+"User")
    $credpw=$($credname+"PW")
    Add-Type -AssemblyName Microsoft.VisualBasic
    AddRegPath $credpath
    Get-Set-Credential $credname $credpath $creduser $credpw $true $defaultuser
    Ver-RegistryValue -RegPath $Path -Name $creduser
    Get-SecurePassword $Path $($credname+"PW")