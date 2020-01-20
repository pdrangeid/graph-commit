<# 
.SYNOPSIS 
 Using the supplied .cypher script and pre-configured datasource credentials, Query the graphDB.
 The credentials to access the Neo4J server are stored in the registry specified by the $Datasource
 parameter.  Optionally replace other credentials with stored secure string values.
 
.DESCRIPTION 
 This must be used in conjunction with set-n4jcredentials.ps1 and set-customcredentials.ps1 to store
 sensitive data in the registry using secure string.  The strings can be retrieved by running this script
 by the same user account.  This allows automation and scripting without storing api keys, users, and
 password information in clear-text.

 If a -logging datasource is provided, the statistics for each transaction/script will be logged into
 a Neo4j database using the label (:Cypherlogentry)

 ***Please be aware, securestring storage is only as secure as the machine and users operating
 (or with access to) it. If you have access to the scripts, and some level of local administrative privilleges,
 it is a trivial task to alter the scripts in order to recover/retrieve the original text of the stored
 securestring values.  As best security practices demand, these stored credentials should only provide the least
 privillege required to accomplish the task.  Any processes that store/retrieve these values should ONLY be
 stored and run on a secured and limited-access endpoint, with a well-secured service account.
 
 
.NOTES 
┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
│ get-cypher-results.ps1                                                                      │ 
├─────────────────────────────────────────────────────────────────────────────────────────────┤ 
│   DATE        : 11.06.2019                             	                  								  │ 
│   AUTHOR      : Paul Drangeid 	                                          								  │ 
│   SITE        : https://blog.graphcommit.com/                                               │ 
└─────────────────────────────────────────────────────────────────────────────────────────────┘ 
 
.PARAMETER Datasource 
Name of the Datasource key to lookup.  Stored in the registry under HKEY_CURRENT_USER\Software\neo4j-wrapper\Datasource\$Datasource
 
.PARAMETER cypherscript 
Name of the file containing the .cypher code to be executed.

.PARAMETER creds1(2,3,4)
Name of credentials to replace within the cypher script. Stored in the registry under HKEY_CURRENT_USER\Software\neo4j-wrapper\Credentials\$cred#
within the specified registry key, a key/value pair are stored with which to find/replace values within the cypher code

.PARAMETER findrep
Key/Value pair to replace within the cypher script. Often used to inject a dynamically determined token or sessionid value into your cypher code
The key/value pair should be supplied as a json string to allow proper parsing.  ie: -fndrep1 {"findthisstring":"replacewiththisone","anotherstring":"anotherreplacement"}

.PARAMETER logging
Name of the Datasource to store cypher transaction logging.  The logging will collect info about the results from your CYPHER transactions, and time to run them.
For best results use the following headers in your cypher code to designate unique sections of code:
// Section [name or description of code that follows this tag]
This way you can track runtimes and counts of results to verify your code is running as expected using the logging.  
Log entries will be stored in nodes with :Cypherlogentry as a Label

.PARAMETER verbosity
How much output to the stdout should occur durring execution?

.PARAMETER returnobj
Enable this switch if you want the CYPHER results to be returned as a powershell object.  Otherwise only metadata about the execution results is returned

.EXAMPLE 
get-cypher-results.ps1 -Datasource 'MyN4JDatasource' -cypherscript 'c:\scripts\mycypher.cypher' -creds1 'webappxyz' -creds2 'anotherapp' -logging 'MyN4JDatasource'

#> 

param (
[string]$Datasource = "N4jDataSource",
[Parameter(mandatory=$true)][string]$cypherscript,
[string]$creds1,
[string]$creds2,
[string]$creds3,
[string]$creds4,
[string]$findrep,
[string]$logging,
[switch]$returnobj,
[int]$verbosity
)

$global:srccmdline = $($MyInvocation.MyCommand.Name)

if ($true -eq $returnobj){[int]$verbosity=0} #verbosity level is 0 if $returnobj switch is enabled
if ($null -eq $verbosity){[int]$verbosity=1} #verbosity level is 1 by default


Try{. "$PSScriptRoot\bg-sharedfunctions.ps1" | Out-Null}
Catch{
    Write-Warning "I wasn't able to load the sharedfunctions includes (which should live in the same directory as get-cypher-results.ps1). `nWe are going to bail now, sorry 'bout that!"
    Write-Host "Try running them manually, and see what error message is causing this to puke: $PSScriptRoot\bg-sharedfunctions.ps1"
    BREAK
    }

# Prepare-EventLog
 
 if(![System.IO.File]::Exists($cypherscript)){
    Write-Host "Was unable to access the cypher script '$cypherscript'" -ForegroundColor Yellow
    BREAK
}
 $cyphercontent = [IO.File]::ReadAllText($cypherscript)
 $Path = "HKCU:\Software\neo4j-wrapper\Datasource\$Datasource"
 Show-onscreen $("`nValidate credentials for $Datasource from $Path") 2
 $Neo4jServerName = Ver-RegistryValue -RegPath $Path -Name "ServerURL"
 if ($false -eq $Neo4jServerName){
  Write-Warning "Unable to retrieve (Neo4jServerName value) datasource $Datasource"
  BREAK
}
 $n4jUser = Ver-RegistryValue -RegPath $Path -Name "DSUser"
 if ($false -eq $n4jUser){
  Write-Warning "Unable to retrieve (DSUser value) datasource $Datasource"
  BREAK
}
 $n4juPW = Get-SecurePassword $Path "DSPW" 
  if ($false -eq $n4juPW){
    Write-Warning "Unable to retrieve (DSPW value) datasource $Datasource"
    BREAK
  }

 Try{
  Loadn4jdriver
 }
  
 Catch{
   LogError $_.Exception "Loading Neo4j driver.  Could not Load Driver."
 BREAK
 }
 
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
 $result = get-portvalidation $ipaddress $queryport
 show-onscreen $("Port connectivity results: $result`n") 3
 if ($result -eq $false){
   LogError $_.Exception "Failed port validation to $Neo4jServerName.  Please verify address and firewall rules.`n"
   exit
 }
 }
 Catch{
   LogError $_.Exception "Failed port validation to $Neo4jServerName.  Please verify address and firewall rules.`n"
 }
   Try {
    $session=$null
    $authToken=$null
    $dbDriver=$null
    show-onscreen $("Connecting to Neo4j target server:$Neo4jServerName") 2
   $authToken = [Neo4j.Driver.V1.AuthTokens]::Basic($n4jUser,$n4juPW)
   Show-onscreen $("Authtoken result: $authToken") 3
   $dbDriver = [Neo4j.Driver.V1.GraphDatabase]::Driver($Neo4jServerName,$authToken)
   Show-onscreen $("dbDriver result: $dbDriver") 3
   $session = $dbDriver.Session()
   Show-onscreen $("session result: $session") 3
   }
   Catch{
     LogError $_.Exception "Failed while connecting to $Neo4jServerName.  Could not establish session.`n"
   BREAK
   }
  
  # Collect any supplied -findrep# and store them in a hashtable so we can use find/replace on the transactions to replace placeholders with supplied value
  $Findandreplace=@{}
  $findrepjson=($findrep | ConvertFrom-Json)
foreach ($info in $findrepjson.PSObject.Properties) {
    #$info.Name
    #$info.Value
    $Findandreplace.Add($info.Name,$info.Value)
}

  # Collect any supplied -creds# and store them in a hashtable so we can use find/replace on the transactions to replace placeholders with actual
  # credential information
  $Securecredentials=@{}
    for ($i=1; $i -le 4; $i++){
      $creds=$(Get-Variable -Name "creds$i" -ValueOnly)
  if (![string]::IsNullOrEmpty($creds) -and $creds -ne $true -and $creds -ne $false) {
  $Path = "HKCU:\Software\neo4j-wrapper\Credentials\$creds"
  $Matchstring = Ver-RegistryValue -RegPath $Path -Name "Matchstring"
  $SecureString = Get-SecurePassword $Path "SecureStringValue"
  $Securecredentials.Add($Matchstring,$SecureString)
  }}

  if (![string]::IsNullOrEmpty($logging)) {
    $Path = "HKCU:\Software\neo4j-wrapper\Datasource\$logging"
    $Neo4jServerName = Ver-RegistryValue -RegPath $Path -Name "ServerURL"
    $n4jUser = Ver-RegistryValue -RegPath $Path -Name "DSUser"
    $n4juPW = Get-SecurePassword $Path "DSPW"  

    Try {
        Show-OnScreen $("Connecting to Neo4j logging server: $Neo4jServerName...") 2
        $authToken = [Neo4j.Driver.V1.AuthTokens]::Basic($n4jUser,$n4juPW)
        $dbDriver = [Neo4j.Driver.V1.GraphDatabase]::Driver($Neo4jServerName,$authToken)
        $logsession = $dbDriver.Session()
        }
        Catch{
            LogError $_.Exception "Loading Neo4j driver." "Could not Load Driver"
        BREAK
        }

Show-Onscreen $("Executing Script: $cypherscript") 2

$scriptid = $null
$logentry=-join("CREATE (cle:Cypherlogentry {date:timestamp()}) SET cle.source='",$env:COMPUTERNAME,"',cle.script='",$cypherscript.replace('\','\\'),"',cle.section='BEGIN SCRIPT' RETURN id(cle) as scriptid")
CypherLog $logentry
$logentry=-join("MATCH (x) WHERE ID(x)=",$global:scriptid," set x.executionid=",$global:scriptid)
CypherLog $logentry
  }# if logging was enabled
  $StartMs = (Get-Date)
  $queryfailures=0
  $queryexceptions=0
  # segment the .cypher into transactions.  A transaction is a semicolon ';' followed by any number of spaces, followed by a NEWLINE (or carriage return)
  # If you have comment sections that contain a semicolon, be sure it is NOT the last character before a NEWLINE or it will
  # be treated as a transaction delimiter (welcome to suggestions on how to better detect this)
  $cypherarray=$($cyphercontent -split ";\s*\r?\n")
  $cypherarray = $cypherarray | Where-Object{![string]::IsNullOrEmpty($_.trim())}
 
  if($cypherarray -isnot [system.array])
  {Show-Onscreen "Source cypher contains only one transaction" 1
  $cypherarray = @($cyphercontent)
}

  # Now take the script, and split it into lines, so we can find the line number for each section start.
  # The logging will show the line number for the start of each transaction to assist in debugging
  $global:arrln=@($cyphercontent -split '\r?\n' | Select-String -Pattern '^(?!//).+;\s*$' | Select-Object -ExpandProperty 'LineNumber')
  #write-host $arrln
  $global:txcounter=-1
  $sectiontitle="BEGIN SCRIPT"
  # Loop through each CYPHER transaction for execution and logging (get the line number from the $arrln array)
  foreach ($transaction in $cypherarray){
    $errormsg=""
    if ($global:txcounter -eq -1){
         $global:LineNumber=1}
     else{
    $global:LineNumber=$($global:arrln[$global:txcounter])+1
}
$global:txcounter++

# Set a new .section property anytime a line begins with //section
$fst = $transaction -replace '// section ','//section'
if ($fst -like '*//section*') {
    $sectiontitle=$($fst -split '\r?\n' | Select-String -Pattern "//section")
    $sectiontitle=$($sectiontitle -replace '//','').trim()
    $sectiontitle=$($sectiontitle -replace 'section','').trim()
    $sectiontitle=$($sectiontitle -replace "'",'"')
    $sectiontitle=$($sectiontitle -replace '[^a-zA-Z0-9" _,/.:)(=\\\%-]', '')
}

  try {
      $securetransaction = $($transaction)
# If we supplied -creds on the commandline, then replace the text with the secured value before sending to the neo4j engine
ForEach($item in $Securecredentials.Keys) {$securetransaction = $securetransaction.replace($($item),$($Securecredentials[$item]))}

# If we supplied -findrep on the commandline, then replace the key with the value before sending to the neo4j engine
ForEach($item in $Findandreplace.Keys) {$securetransaction = $securetransaction.replace($($item),$($Findandreplace[$item]))}


# examine transaction, if it contains ONLY //COMMENT or blank spaces, then don't send it on to the neo4j engine
$tnum=0
$vt=(($securetransaction -split '\r?\n' | Select-String -Pattern '^(?!//).+' | Select-String -Pattern '\S' | Where-Object{$_ -ne $null}).Count)
if ($vt -eq 0) {write-host "Transaction in section ["$sectiontitle"] contains only comments or blank lines - not running transaction "($txcounter+1)"/"($cypherarray.GetUpperBound(0)+1) -ForegroundColor Yellow
continue
}
    if ($verbosity -ge 1){}
    Write-Host -NoNewLine "`rExecuting transaction "(($global:txcounter)+1)"/"($cypherarray.GetUpperBound(0)+1) -ForegroundColor Green
}
    $result = $session.Run($securetransaction)
   
    if ($true -eq $returnobj){
      return $result}
   
  }#End Try
  Catch{
      LogError $_.Exception "Running Query." "Could not Execute query." -ForegroundColor Yellow
      $queryfailures++
  BREAK
  }#End Catch
  
  # Parse the results from the CYPHER transaction for logging
  $logentry=-join("CREATE (cle:Cypherlogentry {date:timestamp()}) SET cle.source='",$env:COMPUTERNAME,"',cle.executionid=",$global:scriptid,",cle.linenumber=",$Global:LineNumber,",cle.script='",$cypherscript.replace('\','\\'),"',")
    
  # See if we got valid neo4j object returned, if not capture the error message to add to the logentry
  try {$result | foreach-object{
      $_ | fl | Out-Null
    }
      $errormsg=""
    }
catch {
    $errmsg=$($error[0].ToString() + $error[0].InvocationInfo.PositionMessage).replace("An error occurred while enumerating through a collection:",'')
    $errormsg=$errmsg.split('^')[0]
    $errormsg=$errormsg.replace("'",'"')
    $queryexceptions++
    }

# Parse the return object and collect statistics for the transaction.  Add this data to the logentry
  $result.PSObject.Properties | ForEach-Object {
  If ($_.Name -eq 'Summary') {
      $summary=$($_.Value)
    $arrsummary= $($summary) -split [Environment]::NewLine
    foreach ($entry in $arrsummary){
        #Write-Host $entry
        
        if ($entry -like '*Counters=Counters{*') {
           #$counters=$($entry) -split ' '
           $counters0=($($entry) -split 'Counters=')[1]
           $counters=$($counters0) -split ' '
           #write-Host "we found counters:$counters" -ForegroundColor Red
           foreach ($counter in $counters){
                if ($counter -like '*=*' -and $counter -notlike '*{*' ){
                $countername=$($counter).split('=')[0]
                $countername=$($countername -replace '[^a-zA-Z0-9]', '')
                $countervalue=$($counter.split('=')[1] -replace '}','').replace(',','').replace(')','')
                $countervalue=$($countervalue.replace("'",'"'))
                $countervalue=$($countervalue -replace '[^a-zA-Z0-9" _,/.:)(=\\\%-]', '')
                If ($($counter.split('=')[1] -replace '}','').replace(',','').replace(')','') -match "^\d+$"){
                # The value of this counter is numeric... 
                Show-onscreen $("`nAdding numeric counter value cle.$countername =  $countervalue") 5
                $logentry= -join($logentry,"cle.",$countername,"=",$countervalue,",")
                } else {
                Show-onscreen $("`nAdding alpha counter value cle.$countername =  $countervalue") 5
                $logentry= -join($logentry,"cle.",$countername,"='",$countervalue,"',")
                }# non-numeric value
                #write-host $("CounterName:$countername   and Value=$countervalue")
             } # If $counter -like '*=*'
               if ($counter -like '*Server=ServerInfo{Add*' ){
                Show-onscreen $("`nAdding Server value cle.$countername =  $countervalue") 5
                $logentry=-join($logentry,"cle.server='",$($counter.split('=')[2] -replace ',',''),"',")
               }#If *Server=
           }# foreach counter in counters
        }# $entry -like '*Counters=Counters{*'

    } # $entry in arrsummary
  }# If Summary section
  }# End ForEach-Object $result.PSObject.Properties
  #If we have error messages, cleanup the text in the string (remove invalid characters) so we don't honk-up our logentry syntax
  if (![string]::IsNullOrEmpty($errormsg)) {
      $errtxt=$($errormsg -replace '[^a-zA-Z0-9" _,/.:)(=\\\%-]', '')
      $ms1=$($MyInvocation.MyCommand.Definition)
      $matchstring = -join("*At ",$ms1,"*")
          if ($errtxt -like $matchstring) {
        $errtxt =  $($errtxt -split 'At ')[0]
    }
    $errtxt = $errtxt.replace('\','\\')
      write-host "[Error text start]"$errtxt"[Error text stop]" -ForegroundColor Yellow
    $logentry=-join($logentry,"cle.error='",$errtxt,"',")
    write-host "`nLogging error: `n$logentry `n`n For Transaction:$securetransaction`n" -ForegroundColor Yellow
  }
  $logentry=-join($logentry,"cle.section='",$sectiontitle,"'")
  $logentry=$logentry.TrimEnd(",")
  $errormsg=""
  if (![string]::IsNullOrEmpty($global:scriptid)){
    # Create a [:PART_OF_SCRIPT_EXECUTION] relationship for logentries part of the same script execution.
    $logentry=-join($logentry," WITH * MATCH (x) WHERE ID(x)=",$global:scriptid," MERGE (cle)-[:PART_OF_SCRIPT_EXECUTION]-(x)")
      }
      if (![string]::IsNullOrEmpty($logging)) {Cypherlog $logentry}

  } # End $transaction Loop
  $EndMs = (Get-Date)
  $totaltime=$($EndMs - $StartMs)
  write-host "`nExecuted "($cypherarray.GetUpperBound(0)+1)" transactions"
  write-host "$queryfailures Query Failures"
  write-host "$queryexceptions Queries with exceptions"
  Write-Host "Script execution time: $totaltime"
  if (![string]::IsNullOrEmpty($logging)) {
  $logentry=-join("CREATE (cle:Cypherlogentry {date:timestamp()}) SET cle.executionid=",$global:scriptid," ,cle.source='",$env:COMPUTERNAME,"',cle.script='",$cypherscript.replace('\','\\'),"',cle.section='END SCRIPT',cle.ResultAvailableAfter='",$totaltime,"',cle.transactions=",$cypherarray.GetUpperBound(0))
  if (![string]::IsNullOrEmpty($scriptid)){
    $logentry=-join($logentry," WITH * MATCH (x) WHERE ID(x)=",$global:scriptid," MERGE (cle)-[:PART_OF_SCRIPT_EXECUTION]-(x)")
      }
  CypherLog $logentry

  Write-Host "`nTo view the [tabular] logs for this script run this query:"
  Write-Host "MATCH (cle:Cypherlogentry {executionid:$global:scriptid}) return cle.source,cle.script,cle.section,cle.linenumber,cle.LabelsAdded,cle.LabelsRemoved,cle.PropertiesSet,cle.ResultAvailableAfter,cle.error order by cle.date DESC"
  Write-Host "`nTo view the [tabular] logs for this script if any transaction threw an exception run this query:"
  Write-Host "MATCH (cle:Cypherlogentry {executionid:$global:scriptid}) where exists(cle.error) return cle.source,cle.script,cle.section,cle.linenumber,cle.LabelsAdded,cle.LabelsRemoved,cle.PropertiesSet,cle.ResultAvailableAfter,cle.error order by cle.date DESC"
  Write-Host "`nTo view a graph all of the logs for this script execution:"
  Write-Host "MATCH (cle:Cypherlogentry {executionid:$global:scriptid}) return cle"
  Write-Host "`nTo view a graph of the logs for this script where labels, properties, or relationships were modified:"
  Write-Host "MATCH (cle:Cypherlogentry {executionid:$global:scriptid}) WHERE (cle.LabelsAdded>0 or cle.PropertiesSet>0 or cle.NodesDeleted>0 or cle.LabelsRemoved>0 or cle.RelationshipsCreated>0 or cle.RelationshipsDeleted>0 or cle.section contains 'SCRIPT') return cle"
    }

  #Clean-up
  $session = $null
  $logsession = $null
  $dbDriver = $null

  if ($queryfailures -ge 1){
  Exit 1
}

  if ($queryexceptions -ge 1){
  Exit 1
  }
  Exit 0