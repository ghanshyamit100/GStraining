#Objective:
#This script is to handle
#1- NewRelic agent/extention installation on both slot (production and staging slot) 
#2- Function "NewRelic-AppSettings" can also be used to apply appsettings pertainging to NewRelic on webapp. This function retains the existing appsettings related to application and re-applies them 
    # while applying the NewRelic key,value along with it.
#3- Function "NewRelic-AppSettings" track and handles the Keys marked as sticky and re-applies them while applying the NR keys,values.


<#This function returns the WebAppName of staging slot of webapp. In case of multiple staging slot, it check for existence of slot specific with WebAppName of "staging".
It returns null if multiple slot exist but none of them are with the WebAppName of "staging". This function also returns null value of none of staging slot exist for the webapp#>
Function StagingSlotName
{
Param(
    [Parameter(Mandatory=$True, HelpMessage = "WebAppName")]$WebAppName,
    [Parameter(Mandatory=$True, HelpMessage = "ResourceGroupName")]$ResourceGroupName  
    )

    
    $StagingSlotDetails = Get-AzWebAppSlot -ResourceGroupName $ResourceGroupName -WebAppName $WebAppName
    $StagingSlotName = @()

    if( $StagingSlotDetails.Count -eq 0)
        {        
        Return 0
        }
    ElseIf($StagingSlotDetails.Count -eq 1)
        {
            
            [string]$stg = $StagingSlotDetails.WebAppName
            [string]$StagingSlotName = $stg.split('/')[1]            
            Return $StagingSlotName
        }
    Elseif($StagingSlotDetails.Count -gt 1)
        {
            foreach($slot in $StagingSlotDetails)
                {
                    $StagingSlotName += $slot.WebAppName    
                }
                if ( $StagingSlotName -contains "$("$WebappName/Staging")")
                    {                        
                        Return "Staging"
                    }
                    else{
                        #Write-Host "Multiple staging slot found but none of them matched with WebAppName "Staging". Please identify manually as which one is actual staging slot"
                        Return 0
                        }
        }
}


Function CheckStatus-AfterRestart {

Param (
 [Parameter(Mandatory=$true)] [string]$WebAppName,
 [Parameter(Mandatory=$false)] $SlotName = $null,
 [Parameter(Mandatory=$true, HelpMessage="Enter ResourceGroup WebAppName of webapp")]$ResourceGroupName
    )


           if($SlotName -eq $null)
            {
            $apiEndpoint = "https://$WebAppName.scm.azurewebsites.net/api/processes"
            }
            else
            {
            $apiEndpoint = "http://$WebAppName-$SlotName.scm.azurewebsites.net/api/processes"
            }


# Check the status of the API endpoint in a loop
$retryCount = 0
$maxRetries = 30  # You can adjust this value as needed
$retryInterval = 10  # Retry interval in seconds

while ($retryCount -lt $maxRetries) {
    try {

         # Invoke the API endpoint and check the response
         $token = Get-AzAccessToken
         $kuduApiAuthorisationToken = "Bearer $($token.Token)"
         $response = Invoke-WebRequest -Uri $apiEndpoint -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method Get
        
        # If the API responds with a success code (e.g., 200), break the loop
        if ($response.StatusCode -eq 200) {
            Write-Host "Webapp is accessible after restart."
            break
        }
    } catch {
        # If an error occurs, output the error message
        Write-Host "Error accessing API: $_"
    }
    
    # Wait for the next retry interval
    Start-Sleep -Seconds $retryInterval
    $retryCount++
}

if ($retryCount -ge $maxRetries) {
    Write-Host "API might not be accessible even after restart. Check manually."
}


}

# Function "Get-AzWebAppPublishingCredentials" has been created to get Publishing credentials of a webapp
#Function Get-AzWebAppPublishingCredentials($resourceGroupName, $webAppName, $slotName = $null)
#{
#	if ([string]::IsNullOrWhiteSpace($slotName)){
#		$resourceType = "Microsoft.Web/sites/config"
#		$resourceName = "$webAppName/publishingcredentials"
#	}
#	else{
#		$resourceType = "Microsoft.Web/sites/slots/config"
#		$resourceName = "$webAppName/$slotName/publishingcredentials"
#	}
#	$publishingCredentials = Invoke-AzResourceAction -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName -Action list -ApiVersion 2015-08-01 -Force
#    	return $publishingCredentials
#}

# Function "Get-KuduApiAuthorisationHeaderValue" has been created to get "Authorization Header values"
#Function Get-KuduApiAuthorisationHeaderValue($resourceGroupName, $webAppName, $slotName = $null)
#{
#    $publishingCredentials = Get-AzWebAppPublishingCredentials -resourceGroupName $resourceGroupName -webAppName $webAppName -slotName $slotName
#    return ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $publishingCredentials.Properties.PublishingUserName, $publishingCredentials.Properties.PublishingPassword))))
#}


<#----Installing NewRelic Extension on production slot of webapp----------------------------#>

Function Install-NewrelicExtension-InTo-ProdSlot ($ResourceGroupName, $WebAppName)
{
    #Select-AzSubscription -Subscription $SubscriptionName
    $token = Get-AzAccessToken
    $kuduApiAuthorisationToken = "Bearer $($token.Token)"

    ### Install NewRelic Extension for Azure App###
    write-output "*** Installing New Relic on PROD Site $WebAppName ***"
    $Kudu = "https://" + $WebAppName + ".scm.azurewebsites.net/api/extensionfeed" # Here you can get a list for all Extensions available.
    $InstallNRURI = "https://" + $WebAppName + ".scm.azurewebsites.net/api/siteextensions" # Install API EndPoint
    $invoke = Invoke-RestMethod -Uri $Kudu -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method get ###-InFile $filePath -ContentType "multipart/form-data"
    $id = ($invoke | ? {$_.id -match "NewRelic.Azure.WebSites.Extension"}).id[0]  ### Searching for NewRelic ID Extension
    $InstallNewRelic = Invoke-RestMethod -Uri "$InstallNRURI/$id" -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method Put #Installing NR Extension

    $Status = ($InstallNewRelic.provisioningState).ToString() + "|" + ($InstallNewRelic.installed_date_time).ToString()  ### Status
    Write-Output "NewRelic Installation Status : $Status"
    Restart-AzWebApp -ResourceGroupName $ResourceGroupName -Name $webAppName -Verbose ### Restarting the WebApp
}

<#----Installing NewRelic Extension on staging slot of webapp----------------------------#>
Function Install-NewrelicExtension-InTo-StagingSlot ($SlotName, $ResourceGroupName, $WebAppName)
{
    #Select-AzSubscription -Subscription $SubscriptionName


    $token = Get-AzAccessToken
    $kuduApiAuthorisationToken = "Bearer $($token.Token)"

    ### Install NewRelic Extension for Azure App###
    write-output "*** Installing New Relic on $WebAppName/$SlotName Site"

    $Kudu = "https://" + $WebAppName + "-$SlotName.scm.azurewebsites.net/api/extensionfeed" # Here you can get a list for all Extensions available.
    $InstallNRURI = "https://" + $WebAppName + "-$SlotName.scm.azurewebsites.net/api/siteextensions" # Install API EndPoint

    $invoke = Invoke-RestMethod -Uri $Kudu -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method get ###-InFile $filePath -ContentType "multipart/form-data"

    $id = ($invoke | ? {$_.id -match "NewRelic.Azure.WebSites.Extension"}).id[0]  ### Searching for NewRelic ID Extension

    $InstallNewRelic = Invoke-RestMethod -Uri "$InstallNRURI/$id" -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method Put
    $Status = ($InstallNewRelic.provisioningState).ToString() + "|" + ($InstallNewRelic.installed_date_time).ToString()  ### Status
    Write-Output "NewRelic Installation Status : $Status"
    Restart-AzWebAppSlot -Name $webAppName -ResourceGroupName $resourceGroupName -Slot $SlotName -Verbose ### Restarting staging slot off WebApp

}


# Function "NewRelic-AppSettings" has been created to set "NewRelic specific Application Settings" into webapp.
Function NewRelic-AppSettings
{
 param (
    [Parameter( mandatory = $true, HelpMessage = " Enter Webapp WebAppName")]
    [string]$WebappName,
    
    [Parameter( mandatory = $true, Helpmessage = "Enter ResourceGroupName of webapp")]
    [String]$ResourceGroupName,

    [Parameter(mandatory = $true, Helpmessage = "Enter subscription WebAppName")]
    [String]$SubscriptionName,

    [Parameter(mandatory = $true, Helpmessage = "Enter NewRelic APM WebAppName")]
    [String]$NewRelicAppName
       )
    #    $context = Get-AzContext -ErrorAction SilentlyContinue
    #    if($context.Account -eq $null)
    #            {
    #                Login-AzAccount
    #            }
    #Select-AzSubscription -Subscription $SubscriptionName
    #[string]$ResourceGroupName = (Get-AzWebApp -WebAppName $webAppName).ResourceGroup  # getting resource group WebAppName of webapp from which it belongs.


if($SubscriptionName -eq "COMMONSERVICES-PROD-AZURE"){
#Declaring HashTable for NewRelicAppSettings.
$NewRelicAppSettings = @{

                        NEW_RELIC_LICENSE_KEY = 'd8fd00140342e1f7b5a1bd880d92a3fd99f869c5'
                        NEW_RELIC_APP_NAME = $NewRelicAppName  }

}
elseif ($SubscriptionName -eq "MAGENTA") {

$NewRelicAppSettings = @{
                        NEW_RELIC_LICENSE_KEY = '512f236db768261f141ef02f020466450749NRAL'
                        NEW_RELIC_APP_NAME = $NewRelicAppName  }


}


elseif ($SubscriptionName -eq "HP-PROD-AZURE") {

$NewRelicAppSettings = @{
                        NEW_RELIC_LICENSE_KEY = 'be97376c9596af8d1bddeb9a3938d937d0362beb'
                        NEW_RELIC_APP_NAME = $NewRelicAppName  }


}



    #Lets fetch existing Appsettings of Webapp.
    $WebappDetails = Get-AzWebApp -Name $WebappName -ResourceGroupName $ResourceGroupName
    echo $WebappDetails
    $CurrentAppSettings = $WebappDetails.SiteConfig.AppSettings  # this is "Key"  "Value" pair. now needs to convert it into HashTable.
    
    <#------------Gathering slot stickyness value of app settings are required and this needs to be merged along with NewRelic Keys stickyness.---------#>
        
    $CurrentStickySettings = (Get-AzWebAppSlotConfigName -ResourceGroupName $ResourceGroupName -Name $WebappName).AppSettingNames   #Existing "Sticky" settings of webapp. Mind the word "STIKCY"
    
    <#-----Inserting NewRelic AppSettings into HashTable of pre-existing (current) "STICKY" settings. only if "CurrentStickySettings" not-contains the newrelic keys----#>
    $i = 0    
        $NRKeys = $NewRelicAppSettings.GetEnumerator() | ForEach-Object {$_.Key}    #By using the GetEnumerator() method, we can essentially "convert" the hash table into an array of objects

     if ( $CurrentStickySettings.Count -ne 0)       
     {
        foreach ( $NRKey in $NRKeys)
        {
            echo $NRKey
            
                if( $CurrentStickySettings -notcontains $NRKey)
                {        
                    $CurrentStickySettings +=$NRKey  
                    $i++
                }
        }
      }
      else
      {
        $CurrentStickySettings = @()
                foreach ( $NRKey in $NRKeys)
        {
            echo $NRKey
            
                if( $CurrentStickySettings -notcontains $NRKey)
                {        
                    $CurrentStickySettings +=$NRKey  
                    $i++
                }
        }
         
      }


    <#Inserting value from $CurrentAppSettings PowerShell WebAppName-Value pair into HashTable "$NewAppSettings". Converting these value into HashTable is necesary since Set-AzWebApp excepts 'HashTable' values with parameter '-AppSettings'.#>
    $NewAppSettings = @{}                                       #Declared the HashTable variable. This will be used to store new app-settings which will contain NR app settings as well.
    [int]$dd = $CurrentAppSettings.Count                        #Getting count of WebAppName-Value pair in powershell. This helps us to traverse/enumurate throughout the PowerShell WebAppName-Value pair.
    [int]$d = 0                                                 #An initial pointer variable to run through "$CurrentAppSettings" PowerShell "WebAppName-Vaule" pair. Starting from line-124 upto 139 is special arrangment of copying PowerShell WebAppName-value pair to HashTable($NewAppSettings).
    if ($dd -gt 0)                                              #This clause allow us to go into this conditiontional loop only if webapp have already have app-settings WebAppName,values defined, otherwise no need.
    {
        while ( $d -lt $dd)
            {
                $NewAppSettings.Add($CurrentAppSettings.Item($d).WebAppName, $CurrentAppSettings.Item($d).value)
                #sleep 5
                $d++
            }
    }

                #Comparing every Key of $NewRelicAppSettings HashTable if it these values are already defined in $NewAppSettings (HashTable version of $CurrentAppSettings).
                $Flag2 = 0
                ForEach ( $RelicKey in $NewRelicAppSettings.Keys)      #Running loop for every Key of NewRelic app-settings Key-value (HashTable)
                {
                    #echo $NewRelicAppSettings.Item($RelicKey)
                    #echo $RelicKey
                    sleep 1                    
                    if( $NewAppSettings.Keys -contains $RelicKey)   #Comparing every Key of $NewRelicAppSettings HashTable whether these values are already defined in $NewAppSettings (HashTable version of $CurrentAppSettings).
                        {
                            echo "'$RelicKey' exist in current app settings."
                        }
                    else{
                            $NewAppSettings.Add($RelicKey, $NewRelicAppSettings.Item($RelicKey))
                            $Flag2++                            
                        }
                }
                
                
    <##---------------APPLY-APP-SETTINGS------------------------------------- #
    (Note:- Set-AzWebApp command ommits all previous app-settings. it only applies the current one, Hence inclusion of
    ...all require AppSetting is neccessary in -AppSetting parameter 
    -Now Applying all AppSettings entry into webapp which are present in $NewRelicAppSettings (NewRelic and Application related app settings)#>
    if( $Flag2 -gt 0)
    {
        echo "Applying the NewRelic App settings values to webapp"
        Set-AzWebApp -AppSettings $NewAppSettings -WebAppName $WebappName -ResourceGroupName $ResourceGroupName
    }
    else
        {
            echo "No changes found in app settings. NewRelic app settings are already applied to webapp "
        }

    if( $Flag2 -gt 0 -and $Flag2 -lt 5)
        {
            echo "Few NewRelic app settings were missing. Those has been added."
        }

    <#----------------APPLYING SLOT STICKYNESS-----------------------#> 
    #Catch here to apply slot stickyness for settings which were already using stickyness along with NR values slot stickyness.      
    #Set-AzWebAppSlotConfigName -WebAppName $WebappName -AppSettingNames NEWRELIC_HOME -ResourceGroupName $ResourceGroupName
    if ( $i -gt 6 -or $i -eq 6)  # This clause allow us to apply NewRelicAppSettings Stickyness only if all 6 NR values are not included into stickyness config of webapp. otherwise it will not make any changes to the webapp stickyness config.
        {
            Set-AzWebAppSlotConfigName -WebAppName $WebappName -AppSettingNames $CurrentStickySettings -ResourceGroupName $ResourceGroupName
        }
    elseif($i -gt 0 -and $i -lt 6)
        {
            echo "Only few of NewRelic settings are marked as stikcy. No changes made to stickyness"
        }
    else
        {
            echo "All of the NewRelic AppSettings are already marked as sticky. No changes made to stickyness"
        }

}


# Function "NewRelic-AppSettings" has been created to set "NewRelic specific Application Settings" into webapp.
Function NewRelic-AppSettingsV2
{
 param (
    [Parameter( mandatory = $true, HelpMessage = " Enter WebAppName")]
    [string]$Webappname,
    [Parameter( mandatory = $true, HelpMessage = " Enter ResourceGroup")]
    [string]$ResourceGroup,
    [Parameter( mandatory = $true, HelpMessage = " Enter Sunscription")]
    [string]$SubscriptionName,
    [Parameter(mandatory = $true, Helpmessage = "Enter NewRelic APM WebAppName")]
    [String]$NewRelicAppName
       )



#Declaring HashTable for NewRelicAppSettings.
if($SubscriptionName -eq "COMMONSERVICES-PROD-AZURE"){


az webapp config appsettings set -g $ResourceGroup -n $Webappname --settings "NEW_RELIC_LICENSE_KEY=d8fd00140342e1f7b5a1bd880d92a3fd99f869c5" "NEW_RELIC_APP_NAME=$NewRelicAppName" --only-show-errors

Write-Host "Newrelic Appsettings Added, Values will be hidden on output" -ForegroundColor Green

}


#For testing
elseif($SubscriptionName -eq "COMMONSERVICES-DEV-TEST-AZURE"){
az webapp config appsettings set -g $ResourceGroup -n $Webappname --settings "NEW_RELIC_LICENSE_KEY=dskjuodscxbasixgasoxsanxsaxio" "NEW_RELIC_APP_NAME=$NewRelicAppName" --only-show-errors
Write-Host "Newrelic Appsettings Added, Values will be hidden on output" -ForegroundColor Green
}



elseif ($SubscriptionName -eq "MAGENTA") {


az webapp config appsettings set -g $ResourceGroup -n $Webappname --settings "NEW_RELIC_LICENSE_KEY=512f236db768261f141ef02f020466450749NRAL" "NEW_RELIC_APP_NAME=$NewRelicAppName" --only-show-errors

Write-Host "Newrelic Appsettings Added, Values will be hidden on output" -ForegroundColor Green

}


elseif ($SubscriptionName -eq "HP-PROD-AZURE") {


az webapp config appsettings set -g $ResourceGroup -n $Webappname --settings "NEW_RELIC_LICENSE_KEY=be97376c9596af8d1bddeb9a3938d937d0362beb" "NEW_RELIC_APP_NAME=$NewRelicAppName" --only-show-errors

Write-Host "Newrelic Appsettings Added, Values will be hidden on output" -ForegroundColor Green

}


}



#This function uninstall the NewRelic Agent from production and staging slot of webapp.
Function UnInstall-NewRelicAgent-ProdSlot($WebAppName,$ResourceGroupName)
{

#----------------UnInstall--NewRelic-Agent-from--PROD-slot-----------------------
Write-Host "UnInstalling NewRelic from Production  slot"
$ProdResourceID = (Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/siteextensions -Name $webAppName -ApiVersion 2018-02-01).resourceID
if( $ProdResourceID -ne $null)
    {
             
        Remove-AzResource -ResourceID $ProdResourceID -ApiVersion 2018-02-01 -Force
        Write-Host "Successfully Removed Newrelic Extension from $webAppName"

        
        #$CheckNRfolder = Get-ListFolder-Webapp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName 
        #if($CheckNRfolder -eq $true)
        #{
        #Restart-AzWebApp -ResourceGroupName $ResourceGroupName -WebAppName $webAppName -Verbose ### Restarting the WebApp        
        #Write-Host "Start sleep for 50 sec"
        #Start-Sleep 50
        #AppWarmUp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName
        #Delete-NRFolder -webAppName $WebAppName  -ResourceGroupName $ResourceGroupName     
        #}
    }
    else
        {
            echo "NewRelic Agent is not found on prod slot of $WebAppName. No uninstallation operation performed on prod slot."
        }
  
}


#----------------UnInstall--NewRelic-Agent-from--STAGING-slot--------------------

Function UnInstall-NewRelicAgent-StagingSlot
{
 param (
    [Parameter( mandatory = $true, HelpMessage = " Enter Webapp WebAppName")]
    [string]$WebappName,
    
    [Parameter( mandatory = $true, Helpmessage = "Enter ResourceGroupName of webapp")]
    [String]$ResourceGroupName="$ResourceGroupName"

       )
Write-Host "Uninstalling NewRelic agent from Staging slot"

    $SlotName = StagingSlotName -WebappName $WebappName -ResourceGroupName $ResourceGroupName
    if ($SlotName -ne 0)
    { 
    $StagingResourceID = (Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/slots/siteextensions -WebAppName "$WebappName/$SlotName" -ApiVersion 2018-02-01).ResourceID
                            if( $StagingResourceID -ne $null)
                            {
                            
                            Remove-AzResource -ResourceID $StagingResourceID -ApiVersion 2018-02-01   -Force
                            $CheckNRfolder = Get-ListFolder-Webapp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -slotName $SlotName
                                if($CheckNRfolder -eq $true)
                                {
                                    Restart-AzWebAppSlot -WebAppName $webAppName -ResourceGroupName $resourceGroupName -Slot $slotName -Verbose ### Restarting staging slot off WebApp
                                    Write-Host "Start sleep 50"
                                    Start-Sleep 50
                                    AppWarmUp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -SlotName $SlotName
                                    Delete-NRFolder -webAppName $WebAppName  -ResourceGroupName $ResourceGroupName -slotName $SlotName
                                }
                            #Start-AzWebAppSlot -WebAppName $WebappName -slo $SlotName -ResourceGroupName $ResourceGroupName
                            echo "NR Agent found on $WebappName staging slot $SlotName and has been uninstalled" 

                            }
                            else
                            {
                                    echo "NewRelic Agent is not found on $SlotName  of $WebAppName. No uninstallation operation performed on prod slot."
                            }
    }
    Else{
            Write-Host "Seems staging slot doesn't exist for the webapp $WebAppName or there may be multiple slot but none of exist with WebAppName of "STAGING". `
            Please check the slots and perform operation manually."
        }
}



#----------------UnInstall--NewRelic-Agent-from--Other-slot--------------------

Function UnInstall-NewRelicAgent-OtherSlots
{
 param (
    [Parameter( mandatory = $true, HelpMessage = " Enter Webapp WebAppName")]
    [string]$WebAppName,
    
    [Parameter( mandatory = $true, Helpmessage = "Enter ResourceGroupName of webapp")]
    [String]$ResourceGroupName,
    
    [Parameter( mandatory = $true, Helpmessage = "Enter Slotname of webapp")]
    [String]$SlotName



       )
Write-Host "Uninstalling NewRelic agent from $SlotName slot"

$StagingResourceID = (Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/slots/siteextensions -Name "$WebAppName/$SlotName" -ApiVersion 2018-02-01).ResourceID
                            
                           if( $StagingResourceID -ne $null)
                            {
                            
                            Remove-AzResource -ResourceID $StagingResourceID -ApiVersion 2018-02-01   -Force


                            #Restart-AzWebAppSlot -Name $webAppName -ResourceGroupName $ResourceGroupName -Slot $SlotName -Verbose ### Restarting staging slot off WebApp

                            #Start-AzWebAppSlot -WebAppName $WebappName -slo $SlotName -ResourceGroupName $ResourceGroupName
                            Write-Host "NR Agent found on $WebappName\$SlotName and has been uninstalled" 

                            }
                            else
                            {
                               echo "NewRelic Agent is not found on $SlotName  of $WebAppName. No uninstallation operation performed."
                            }
   
}


#reference https://blog.kloud.com.au/2016/08/30/interacting-with-azure-web-apps-virtual-file-system-using-powershell-and-the-kudu-api/
Function Download-FileFromWebAppV2 ($WebAppName,$ResourceGroupName)
{


$NRFileDownLoadLocation = ".\NR-Backup"

#newrelic.config old Paths
$kuduOldPath1 = "newrelic/newrelic.config"
$kuduOldPath2 = "newrelic_core/newrelic.config"


#newrelic.config New Paths
$kudoNewPath1 = "Core/newrelic.config"
$kudoNewPath2 = "Framework/newrelic.config"


#NR.xml old Paths
$NRxmlOldPath1 = "newrelic/extensions/NR.xml"
$NRxmlOldPath2 = "newrelic_core/extensions/NR.xml"

#NR.xml new Paths
$NRxmlNewPath1 = "Core/extensions/NR.xml"
$NRxmlNewPath2 = "Framework/extensions/NR.xml"


#Context
#Set-AzContext $Subscription | Out-Null

#Token
$token = Get-AzAccessToken
$kuduApiAuthorisationToken = "Bearer $($token.Token)"

#Local Download Path
$localPath = "$NRFileDownLoadLocation\$WebAppName\newrelic.config"
$NRxmlPath = "$NRFileDownLoadLocation\$WebAppName\NR.xml"


$ProdResourceID = (Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/siteextensions -ResourceName $WebappName -ApiVersion 2018-02-01).resourceID

if( $ProdResourceID -ne $null){


        If(!(test-path $NRFileDownLoadLocation))
        {
        New-Item -ItemType Directory -Force -Path $NRFileDownLoadLocation     
        }
        
        sleep 2
        
                  
        If(!(test-path "$NRFileDownLoadLocation\$WebAppName"))
        {
        New-Item -ItemType Directory -Force -Path $NRFileDownLoadLocation\$WebAppName
        }
        
        
        #Download newrelic.config form old location
        Write-Host "Looking to download NewRelic.config file from legacy location in case agent installed is too old" -ForegroundColor Yellow
        try
        {
        $kOldpath = $kuduOldPath1
        $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kOldpath"
        Write-Output " Downloading File from WebApp. Source: '$kuduApiUrl'. Target: '$localPath'..."
        Invoke-RestMethod -Uri $kuduApiUrl `
        -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
        -Method GET `
        -OutFile $localPath `
        -ContentType "multipart/form-data" 
        }
        catch {
        
            try {
            $kOldpath = $kuduOldPath2
            $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kOldpath"
            Write-Output "Downloading File from WebApp. Source: '$kuduApiUrl'. Target: '$localPath'..."
            Invoke-RestMethod -Uri $kuduApiUrl `
            -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
            -Method GET `
            -OutFile $localPath `
            -ContentType "multipart/form-data" 
            }
            catch {
            Write-Host "Newrelic.config not found in Old paths for $WebAppName" -ForegroundColor Red 
            
            }
        }
        
        
        
        #Downloading NewRelic.config file from new location, considering agent is not legacy.
        Write-Host "Looking to download NewRelic.config file from new location" -ForegroundColor Green
        try
        {
        $kNewpath = $kudoNewPath1
        $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/newrelicagent/$kNewpath"
        Write-Output " Downloading File from WebApp. Source: '$kuduApiUrl'. Target: '$localPath'..."
        Invoke-RestMethod -Uri $kuduApiUrl `
        -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
        -Method GET `
        -OutFile $localPath `
        -ContentType "multipart/form-data" 
        }
        catch {
        
            try {
            $kNewpath = $kudoNewPath2
            $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/newrelicagent/$kNewpath"
            Write-Output " Downloading File from WebApp. Source: '$kuduApiUrl'. Target: '$localPath'..."
            Invoke-RestMethod -Uri $kuduApiUrl `
            -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
            -Method GET `
            -OutFile $localPath `
            -ContentType "multipart/form-data" 
            }
            catch {
            
            Write-Host "Newrelic.config not found in New paths for $WebAppName, old configs will be backed" -ForegroundColor Red
            
            }
        }
        
        
        
        #Download NR.xml form old location
        Write-Host "Looking to download NR.xml file from legacy location in case agent installed is too old" -ForegroundColor Yellow
        try
        {
        $NRoldpath = $NRxmlOldPath1
        $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$NRoldpath"
        Write-Output " Downloading File from WebApp. Source: '$kuduApiUrl'. Target: '$NRxmlPath'..."
        Invoke-RestMethod -Uri $kuduApiUrl `
        -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
        -Method GET `
        -OutFile $NRxmlPath `
        -ContentType "multipart/form-data" 
        }
        catch {
        
            try {
            $NRoldpath = $NRxmlOldPath2
            $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$NRoldpath"
            Write-Output " Downloading File from WebApp. Source: '$kuduApiUrl'. Target: '$NRxmlPath'..."
            Invoke-RestMethod -Uri $kuduApiUrl `
            -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
            -Method GET `
            -OutFile $NRxmlPath `
            -ContentType "multipart/form-data" 
            }
            catch {
        
            Write-Host "NR.xml not found in old paths" -ForegroundColor Red
        
            }
        }
        
        
        
        
        #Downloading NR.xml file from new location, considering agent is not legacy.
        Write-Host "Looking to downlaod NR.xml file from new location" -ForegroundColor Green
        try
        {
        $NRnewpath = $NRxmlNewPath1
        $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/newrelicagent/$NRnewpath"
        Write-Output " Downloading File from WebApp. Source: '$NRnewpath'. Target: '$NRxmlPath'..."
        Invoke-RestMethod -Uri $kuduApiUrl `
        -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
        -Method GET `
        -OutFile $NRxmlPath `
        -ContentType "multipart/form-data" 
        }
        catch {
        
            try {
            $NRnewpath = $NRxmlNewPath2
            $kuduApiUrl = "https://$WebAppName.scm.azurewebsites.net/api/vfs/newrelicagent/$NRnewpath"
            Write-Output " Downloading File from WebApp. Source: '$NRnewpath'. Target: '$NRxmlPath'..."
            Invoke-RestMethod -Uri $kuduApiUrl `
            -Headers @{"Authorization"="$kuduApiAuthorisationToken";"If-Match"="*"} `
            -Method GET `
            -OutFile $NRxmlPath `
            -ContentType "multipart/form-data"
            }
            catch {
            
            Write-Host "NR.xml not found in new paths, Maybe not a webjob" -ForegroundColor Red
            
            }
            }
}

else {
Write-Output "NewRelic extenstion is not installed in Production slot (Newrelic). Hence NewRelic.config file not been backed up"
}



#Compress and send to snapshotcsvstr storage account
#$archivepath = "$NRFileDownLoadLocation-$(Get-Date -Format ddMMyyhhmm).zip"
#Compress-Archive -Path $NRFileDownLoadLocation -DestinationPath $archivepath
#Set-AzContext commonservices-dev-test-azure | Out-Null
#$str = Get-AzStorageAccount -ResourceGroupName VM-SNAPSHOT-RG -Name snapshotcsvstr
#Set-AzStorageBlobContent -File $archivepath -Container "nrbackup" -Blob $archivepath -Context $str.Context -Force

}


#Function Download-FileFromWebJob($ResourceGroupName, $WebAppName, $NRFileDownLoadLocation="e:\temp")
#{
#
#$kuduPath = "newrelic/extension/NR.xml"
#$kuduOldPathWebApp = @(
#    @{path = "newrelic/extension/NR.xml"},
#    @{path = "newrelic_core/extension/NR.xml"}
#)
#$kudoNewPathWebApp = @(
#    @{path = "Core/extension/NR.xml"},
#    @{path = "Framework/extension/NR.xml"}
#)
#$localPath = "$NRFileDownLoadLocation\$WebAppName\NR.xml"
#$ProdResourceID = (Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/siteextensions -ResourceName $WebappName -ApiVersion 2018-02-01).resourceID
#
#if( $ProdResourceID -ne $null){
#                    #$path = "e:\temp"                    
#                    #$NRFileDownLoadLocation="e:\temp"
#            If(!(test-path $NRFileDownLoadLocation))
#                {
#                      New-Item -ItemType Directory -Force -Path $NRFileDownLoadLocation     
#                }
#            sleep 2
#
#            #$path = "$NRFileDownLoadLocation\$WebAppName"
#            If(!(test-path "$NRFileDownLoadLocation\$WebAppName"))
#                {
#                      New-Item -ItemType Directory -Force -Path $NRFileDownLoadLocation\$WebAppName
#                }
#
#    $token = Get-AzAccessToken
#    $kuduApiAuthorisationToken = "Bearer $($token.Token)"
#    
#        Write-Host "Production Slot - Looking to download NewRelic.config file from legacy location in case agent installed is too old"
#
#        foreach($kOldpath in $kuduOldPathWebApp)
#        {
#        $kOldpath = $kOldpath.path
#        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kOldpath"
#        $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/wwwroot", "")
#        Write-Host " Downloading File from WebApp. Source: '$virtualPath'. Target: '$localPath'..." -ForegroundColor DarkGray
#        Invoke-RestMethod -Uri $kuduApiUrl `
#        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
#        -Method GET `
#        -OutFile $localPath `
#        -ContentType "multipart/form-data" 
#        }
#        #Downloading NewRelic.config file considering agent is not legacy.
#        foreach($kNewpath in $kudoNewPathWebApp)
#        {
#        $kNewpath = $kNewpath.path
#        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/NewRelicAgent/$kNewpath"
#        $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/NewRelicAgent", "")
#        Write-Host " Downloading File from WebApp. Source: '$virtualPath'. Target: '$localPath'..." -ForegroundColor DarkGray
#        Invoke-RestMethod -Uri $kuduApiUrl `
#        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
#        -Method GET `
#        -OutFile $localPath `
#        -ContentType "multipart/form-data" 
#        }
#    
#}
#
#Else
#    {
#    Write-Output "NewRelic extenstion is not installed in Production slot (Newrelic). Hence NewRelic.config file not been backed up"
#    }
#
#}


Function UpLoad-FileToWebAppV2 ($ResourceGroupName, $WebAppName, $slotName = "")
{

$NRFileDownLoadLocation = ".\NR-Backup"

$kuduUploadPath1 = "Core/newrelic.config"
$kuduUploadPath2 = "Framework/newrelic.config"

$kuduxmlUploadPath1 = "Core/extensions/NR.xml"
$kuduxmlUploadPath2 = "Framework/extensions/NR.xml"


$localPath = "$NRFileDownLoadLocation\$WebappName\newrelic.config"
$localPathNRxml = "$NRFileDownLoadLocation\$WebappName\NR.xml"

#For Producation slot
if ($slotName -eq ""){

if( Test-Path $localPath)

{
$token = Get-AzAccessToken
$kuduApiAuthorisationToken = "Bearer $($token.Token)"

#Upload newrelic.config in Core Folder
$kuduUploadApiUrl = "https://$WebappName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduUploadPath1"
Write-Host " Upload File from Local system to webapp. Source: '$localPath'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPath `
-ContentType "multipart/form-data"

Start-Sleep -Seconds 5

#Upload newrelic.config in Framework Folder
$kuduUploadApiUrl = "https://$WebappName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduUploadPath2"
Write-Host " Upload File from Local system to webapp. Source: '$localPath'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPath `
-ContentType "multipart/form-data"

}
else {

Write-Host "Newrelic.config file not found in local for $WebappName, hence not uploaded"

}

if(Test-Path $localPathNRxml){

$token = Get-AzAccessToken
$kuduApiAuthorisationToken = "Bearer $($token.Token)"

#Upload NR.xml in Core Folder
$kuduUploadApiUrl = "https://$WebappName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduxmlUploadPath1"
Write-Host " Upload File from Local system to webapp. Source: '$localPathNRxml'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPathNRxml `
-ContentType "multipart/form-data"

Start-Sleep -Seconds 5

#Upload newrelic.config in Framework Folder
$kuduUploadApiUrl = "https://$WebappName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduxmlUploadPath2"
Write-Host " Upload File from Local system to webapp. Source: '$localPathNRxml'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPathNRxml `
-ContentType "multipart/form-data"

}

else{

Write-Host "NR.xml file not found in local for $WebappName, hence not uploaded"

}


}








#For Other Slots
else {


if( Test-Path $localPath)

{
$token = Get-AzAccessToken
$kuduApiAuthorisationToken = "Bearer $($token.Token)"

#Upload newrelic.config in Core Folder
$kuduUploadApiUrl = "https://$WebappName-$slotName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduUploadPath1"
Write-Host " Upload File from Local system to webapp. Source: '$localPath'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPath `
-ContentType "multipart/form-data"

Start-Sleep -Seconds 5

#Upload newrelic.config in Framework Folder
$kuduUploadApiUrl = "https://$WebappName-$slotName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduUploadPath2"
Write-Host " Upload File from Local system to webapp. Source: '$localPath'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPath `
-ContentType "multipart/form-data"

}
else {

Write-Host "Newrelic.config file not found in local for $WebappName-$slotName, hence not uploaded"

}

if(Test-Path $localPathNRxml){

$token = Get-AzAccessToken
$kuduApiAuthorisationToken = "Bearer $($token.Token)"

#Upload NR.xml in Core Folder
$kuduUploadApiUrl = "https://$WebappName-$slotName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduxmlUploadPath1"
Write-Host " Upload File from Local system to webapp. Source: '$localPathNRxml'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPathNRxml `
-ContentType "multipart/form-data"

Start-Sleep -Seconds 5

#Upload newrelic.config in Framework Folder
$kuduUploadApiUrl = "https://$WebappName-$slotName.scm.azurewebsites.net/api/vfs/newrelicagent/$kuduxmlUploadPath2"
Write-Host " Upload File from Local system to webapp. Source: '$localPathNRxml'. Target: '$kuduUploadApiUrl'..." -ForegroundColor Green
Invoke-RestMethod -Uri $kuduUploadApiUrl `
-Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
-Method PUT `
-InFile $localPathNRxml `
-ContentType "multipart/form-data"

}

else{

Write-Host "NR.xml file not found in local for $WebappName-$slotName, hence not uploaded"

}

}


}

Function UpLoad-FileToWebApp($ResourceGroupName, $WebAppName, $slotName = "",$NRFileDownLoadLocation)
{
    $kuduUploadPath = @(
        @{path = "NewRelicAgent/Core/newrelic.config"},
        @{path = "NewRelicAgent/Framework/newrelic.config"}
    )

    $localPath = "$NRFileDownLoadLocation\$WebappName\newrelic.config"
    $localPathNRxml = "$NRFileDownLoadLocation\$WebappName\NR.xml"
    if($AppType -eq "")
    {
        If( Test-Path $localPath)
            {
                $token = Get-AzAccessToken
                    $kuduApiAuthorisationToken = "Bearer $($token.Token)"
                if ($slotName -eq "")
                {
                        #$kuduApiUrlCore = "https://$webAppName.scm.azurewebsites.net/api/vfs/$kuduPathCore"
                        #$kuduApiUrlFramework = "https://$webAppName.scm.azurewebsites.net/api/vfs/$kuduPathFramework"       
                    #$virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/wwwroot", "")        
                    foreach($kUploadPath in $kuduUploadPath)
                    {
                    $kUploadPath = $kUploadPath.path
                    $kuduUploadApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/$kUploadPath"
                    Write-Host " Upload File from Local system to webapp. Source: '$localPath'. Target: '$kuduUploadApiUrl'..." -ForegroundColor DarkGray
                    Invoke-RestMethod -Uri $kuduUploadApiUrl `
                                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                                        -Method PUT `
                                        -InFile $localPath `
                                        -ContentType "multipart/form-data"
                    }
                
                }
                else
                {
                    #$kuduApiUrlCore = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/vfs/$kuduPathCore"
                    #$kuduApiUrlFramework = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/vfs/$kuduPathFramework"  
                    #$virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/wwwroot", "")
                    foreach($kUploadPath in $kuduUploadPath)
                    {
                    $kUploadPath = $kUploadPath.path
                    $kuduUploadApiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/vfs/$kUploadPath"
                    Write-Host " Upload File from Local system to webapp. Source: '$localPath'. Target: '$kuduUploadApiUrl'..." -ForegroundColor DarkGray
                    Invoke-RestMethod -Uri $kuduUploadApiUrl `
                                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                                        -Method PUT `
                                        -InFile $localPath `
                                        -ContentType "multipart/form-data"
                    }
                }
            }
        Else
            {
            echo "NewRelic.config not found at the location $localPath"
            }
    }
    elseif ($AppType -eq "webjob") {
        If( Test-Path $localPathNRxml)
        {
            $kuduApiAuthorisationToken = Get-KuduApiAuthorisationHeaderValue -resourceGroupName $ResourceGroupName -webAppName $WebappName -slotName $slotName
            $kuduUploadPath = @(
                @{path = "Core/extension/NR.xml"},
                @{path = "Framework/extension/NR.xml"}
            )
            foreach($kUploadPath in $kuduUploadPath)
            {
            $kUploadPath = $kUploadPath.path
            $kuduUploadApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/$kUploadPath"
            Write-Host " Upload File from Local system to webapp. Source: '$localPath'. Target: '$kuduUploadApiUrl'..." -ForegroundColor DarkGray
            Invoke-RestMethod -Uri $kuduUploadApiUrl `
                                -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                                -Method PUT `
                                -InFile $localPathNRxml `
                                -ContentType "multipart/form-data"
            }
        }
        else{Write-Host "NR.xml not found at the location $localPathNRxml"}
    }
}


#This function uses HashTable to collect Prod and Staging slot running status.
Function SlotRunningStatus
{
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "WebAppName")][string]$WebAppName="TEST127-TEMP",
        [Parameter(Mandatory = $true, HelpMessage = "ResourceGroupName")][string]$ResourceGroupName="DEV-PLAN-RG"
            )

                    $context = Get-AzContext -ErrorAction SilentlyContinue
                    if($context.Account -eq $null)
                    {
                        Login-AzAccount
                    }
                    #Declaring HashTable to store slots(prod,staging) running status.
                    $Status= @{}               
                $ProdDetails = Get-AzWebApp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName
                If($ProdDetails.State -eq "Running")
                    {
                        Write-Host "Webapp is running"
                        $Status.Add("Prod","Running")
                    }
                    else{
                        Write-Host "WebApp is stopped"
                        $Status.Add("Prod","Stopped")                            
                        }
                    $Stg = StagingSlotName -WebappName $WebAppName -ResourceGroupName $ResourceGroupName
                    if($stg -ne 0)
                    {
                        $StagingDetails = Get-AzWebAppSlot -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -Slot $Stg
                        If($StagingDetails.State -eq "Running")
                        {
                         Write-Host "Staging slot is running"
                         $Status.Add("Staging","Running")
                        }
                        Else
                        {
                        Write-Host "Staging slot is stopped"
                        $Status.Add("Staging","Stopped")
                        }
                    }    
                Return $Status                                               
}

Function MinutesSpent
{
# Declare  variable  "$StartTime = get-date"  at the point since when you have to start calculating the time. Call "MinutesSpent" function whereever you have to end the
# interval and have to calculate the time.  As we used thisn "AppWarmUp" function.
$EndTime = Get-Date
$TimeSpent = New-TimeSpan -Start $StartTime -End $EndTime    
Return $TimeSpent.TotalMinutes
}


Function AppWarmUp
{
Param (
 [Parameter(Mandatory=$true)] [string]$WebAppName,
 [Parameter(Mandatory=$false)] $SlotName = $null,
 [Parameter(Mandatory=$true, HelpMessage="Enter ResourceGroup WebAppName of webapp")]$ResourceGroupName
    )
    [int]$i = 0; [int]$j =0
    #$SlotName = $null
    
    #$WebAppName = "TEST127-TEMP"    
           if($SlotName -eq $null)
            {
            $Uri = "http://$WebAppName.azurewebsites.net"
            $ScmUri = "http://$WebAppName.scm.azurewebsites.net"
            }
            else
            {
            $Uri = "http://$WebAppName-$SlotName.azurewebsites.net"
            $ScmUri = "http://$WebAppName-$SlotName.scm.azurewebsites.net"
            }
            $error.Clear()
            
    $StartTime = get-date
    While ( $i -ne 10)
    {   
    $TimeSpent = MinutesSpent
    if( $TimeSpent -gt 5 ) { Write-Host "Application takes more than expected time to get warmed-up"; break} 
    try{
            $Request1 = Invoke-WebRequest -Uri $Uri  -TimeoutSec 10 -ErrorAction SilentlyContinue               
            Write-Host "Warmup is in-progress ("$Request1.StatusCode")"
            Start-Sleep 2
            $Request2 = Invoke-WebRequest -Uri $Uri  -TimeoutSec 10 -ErrorAction SilentlyContinue                      
            Write-Host "Warmup is in-progress ("$Request2.StatusCode")"
            Start-Sleep 2
            $Request3 = Invoke-WebRequest -Uri $Uri  -TimeoutSec 10 -ErrorAction SilentlyContinue
            Write-Host "Warmup is in-progress ("$Request3.StatusCode")" 
            Start-Sleep 2
                
            #Return $Request.StatusCode
            #Write-Host "Warmup is in-progress ("$Request.StatusCode")"           
            $Request1 = $null ;   $Request2 = $null; $Request3 = $null        
            $i++            
            break
        }
    Catch{
            Write-Host "Error occured during warm up http request, Application could not be warmed-up - StatusDescription= '$($Error.Exception.Response.statusDescription)', StatusCode= '$($Error.Exception.Response.statuscode)'"          
            $error.Clear()
            
          }
        #$i++
        #Write-Host "Warmp is in-progress"
    }
    $error.Clear()
    $StartTime = get-date
    While ($j -ne 10)
    {
    $TimeSpent = MinutesSpent
    if( $TimeSpent -gt 5 ) { Write-Host "Application takes more than expected time to get warmed-up"; break}
        Try {
            $ScmRequest1 = Invoke-WebRequest -Uri $ScmUri -TimeoutSec 10 -ErrorAction SilentlyContinue
            Write-Host "Warmup of SCM site is in-progress ("$ScmRequest1.StatusCode")"
            Start-Sleep 2
            $ScmRequest2 = Invoke-WebRequest -Uri $ScmUri -TimeoutSec 10 -ErrorAction SilentlyContinue
            Write-Host "Warmup of SCM site is in-progress ("$ScmRequest2.StatusCode")"
            Start-Sleep 2
            $ScmRequest3 = Invoke-WebRequest -Uri $ScmUri -TimeoutSec 10 -ErrorAction SilentlyContinue
            Write-Host "Warmup of SCM site is in-progress ("$ScmRequest3.StatusCode")"
            Start-Sleep 2
            $ScmRequest1 = $null; $ScmRequest2 = $null; $ScmRequest3 = $null
            $j++
            Start-Sleep 2
            break
            }
       Catch{
            Write-Host "Error occured during warm up http request, Application could not be warmed-up - StatusDescription= '$($Error.Exception.Response.statusDescription)', StatusCode= '$($Error.Exception.Response.statuscode)'"            
            $error.Clear()
            
            }
    }
}


<#This function creates a new webapp as sample Webapp. Function checks available NewRelic version on Azure against this sample webapp.
  It uses current date and time decimal values to create webapp. It gets created in "DEV-PLAN-RG" resource group and subscription "commonservices-dev-test-azure", since 
  Function "New-appcreation" creates webapp by default in mentioned resource group and subscription. Sample webapp also gets deleted at the end of function #>
Function NewRelic-GetVersionAvailable
{    
    Select-AzSubscription -Subscription commonservices-dev-test-azure 
    [string]$SampleAppName = get-date -Format HHmmssddMMyyyy
    new-appcreation -ResourceName $SampleAppName -Kind app 
    #Write-Host $SampleAppName
    $resourceGroupName = (Get-AzWebApp -WebAppName $SampleAppName).ResourceGroup 

    <#----------------------------CHECKING-AVAILABLE-NEWRELIC-EXTENSION-VERSION--ON-AZURE--------------------------------------------------#>
    
    $kuduApiAuthorisationToken = Get-KuduApiAuthorisationHeaderValue -resourceGroupName $resourceGroupName -webAppName $SampleAppName
    ### Install NewRelic Extension for Azure App###
    #write-output "*Checing available version of newrelic for temporary webapp $SampleAppName "
    $Kudu = "https://" + $SampleAppName + ".scm.azurewebsites.net/api/extensionfeed" # Here you can get a list for all Extensions available.
    $InstallNRURI = "https://" + $SampleAppName + ".scm.azurewebsites.net/api/siteextensions" # Install API EndPoint
    $invoke = Invoke-RestMethod -Uri $Kudu -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method get ###-InFile $filePath -ContentType "multipart/form-data"        
    $Version = ($invoke | ? {$_.id -match "NewRelic.Azure.Website*"}).version  ## Searching for installed version. 
    Start-Sleep 20
    Remove-AzWebApp -WebAppName $SampleAppName -ResourceGroupName $resourceGroupName -Force 
    #Write-Host "$SampleAppName has been deleted"  
    #Return $Version 
    <#PowerShell have classical issue where it doesn't return the intended value which it should actually return. Instead it returns all value written in OutPut-buffer of Host.
    refer.  https://stackoverflow.com/questions/24548723/clear-captured-output-return-value-in-a-powershell-function.
    Since "Return" function returns value in return, hence we returned the value in two differnt array below where we first returns all output buffer and then $version .
    Whenever we will call this function inside any other function, we can use [-1] operator to select varialble $version.
    e.g line 87 "$NRAvailableVersion = ( NewRelic-GetVersionAvailble )[-1]"  
    https://powershellstation.com/2011/08/26/powershell%E2%80%99s-problem-with-return/ #>
    Return ,$Version 
}

<#----------------------------CHECKING-INSTALLED-NEWRELIC-EXTENSION-VERSION--ON-WEBAPP--------------------------------------------------#>
Function NewRelic-GetVersionInstalled
{
Param(
[Parameter(Mandatory=$True, HelpMessage= "Enter WebAppName which needs to be compared")][String]$WebAppName,
[Parameter(Mandatory=$True, HelpMessage="Enter SubscriptionName of Webapp")][string]$SubscriptionName,
[Parameter(Mandatory=$False, HelpMessage="Enter ResourceGroup WebAppName of webapp")]$ResourceGroupName=$null
)
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if($context.Account -eq $null)
    {
        Login-AzAccount
        $context = Get-AzContext -ErrorAction SilentlyContinue
    }
    [string]$CurrentSubscription = $context.Subscription.WebAppName
    if($CurrentSubscription -ne $SubscriptionName)
    {
    Select-AzSubscription -Subscription $SubscriptionName
    }


    if($ResourceGroupName -eq $null)
    {
    $resourceGroupName = (Get-AzWebApp -WebAppName $webAppName).ResourceGroup
    }
    $ProdResourceID = (Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/siteextensions -WebAppName $WebappName -ApiVersion 2018-02-01).resourceID


    if($ProdResourceID.count -ne 0)
    {
        #[string]$WebappName = "prod-resumehelp"
        #[string]$ResourceGroupName = "RGRH-PROD-RESOURCEGROUP"
        #Select-AzSubscription -Subscription "HP-PROD-AZURE"
        

        [string]$A = (Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/siteextensions -resourceName $WebappName -ApiVersion 2018-02-01).Properties
        [string]$B = $A.Split(";")[5]
        [string]$c = $B.Split("=")[1]

        Return $c
    }
    Else
    {
        Return "NewRelic Not Installed" 
    }
}


#This script generates report for a particular subscription. $subscription and $path parameter are necessary to supply .
Function NewRelic-GetVersionReport
{
Param(
    [Parameter( Mandatory=$True,Position = 0,
            HelpMessage="SubscriptionName" )]
            [String]$SubscriptionName,
    [Parameter(Mandatory=$True, Position = 1,
            HelpMessage = "Path to a folder where you want to place your report file into")]$Path 
    )
    $requireddata = @()   
    #$NRAvailableVersion = NewRelic-GetVersionAvailble
    $NRAvailableVersion = ( NewRelic-GetVersionAvailable )[-1]  #Since function "NewRelic-GetVersionAvailable" returns two distinct values , hence we used [-1] to select $version
    Select-AzSubscription -Subscription $SubscriptionName 
    $AllWebApp = Get-AzWebApp 
    #$waobject = new-object -TypeName PSobject
    
    foreach ($WebApp in $AllWebApp)
    {
    $ResourceGroupName = $WebApp.ResourceGroup
    $waobject = new-object -TypeName PSobject
    $NRelicInstalledVersion = NewRelic-GetVersionInstalled -WebAppName $WebApp.WebAppName -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $waobject | Add-Member -MemberType NoteProperty -WebAppName "WebappName" -Value $WebApp.WebAppName
    $waobject | Add-Member -MemberType NoteProperty -WebAppName "AvailableVersion" -Value $NRAvailableVersion
    $waobject | Add-Member -MemberType NoteProperty -WebAppName "InstalledVersion" -Value $NRelicInstalledVersion
    $waobject | Add-Member -MemberType NoteProperty -WebAppName "Subscription" -Value $SubscriptionName
    $requireddata += $waobject
    }
    #Return $requireddata
    $requireddata | Export-Csv -Path $path\"NewRelic_AgentInstalledVersionReportWebapp_$SubscriptionName.csv"
}


#This script generates report for all prod subscription.$path parameter is necessary to supply .
Function NewRelic-GetVersionReport-AllSubscription
{
Param(
    [Parameter(Mandatory=$True, Position = 0,
            HelpMessage = "Path to a folder where you want to place your report file into")]$Path 
    )
    $requireddata = @()       
    $NRAvailableVersion = ( NewRelic-GetVersionAvailble )[-1]  #Since function "NewRelic-GetVersionAvailable" returns two distinct values , hence we used [-1] to select $version
    $Allsubscription = Get-AzSubscription | where { $_.WebAppName -like "*prod*"}
    foreach ($Subs in $Allsubscription)
    {
        $SubscriptionName = $Subs.WebAppName
        Select-AzSubscription -Subscription $SubscriptionName
        $AllWebApp = Get-AzWebApp             
        foreach ($WebApp in $AllWebApp)
        {
        $ResourceGroupName = $WebApp.ResourceGroup
        $waobject = new-object -TypeName PSobject
        $NRelicInstalledVersion = NewRelic-GetVersionInstalled -WebAppName $WebApp.WebAppName -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        $waobject | Add-Member -MemberType NoteProperty -WebAppName "WebappName" -Value $WebApp.WebAppName
        $waobject | Add-Member -MemberType NoteProperty -WebAppName "AvailableVersion" -Value $NRAvailableVersion
        $waobject | Add-Member -MemberType NoteProperty -WebAppName "InstalledVersion" -Value $NRelicInstalledVersion
        $waobject | Add-Member -MemberType NoteProperty -WebAppName "Subscription" -Value $SubscriptionName
        $requireddata += $waobject
        }
    }
    #Return $requireddata
    $requireddata | Export-Csv -Path $path\"NewRelic_AgentInstalledVersionReportWebapp_AllSubs.csv"
}



#This script generates report for all prod subscription. and sends report over e-mail.
Function NewRelic-GetVersionReport-AllSubscription-OverEmail
{      
    # Uncomment below "$connection" and "Connect-AzAccount" commands if you tries to run this function from Azure automation account.  
    #$connection = Get-AutomationConnection -WebAppName AzureRunAsConnection
    #Connect-AzAccount -ServicePrincipal -Tenant $connection.TenantID `
    #-ApplicationId $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint

    $NRAvailableVersion = (NewRelic-GetVersionAvailable)[-1]  #Since function "NewRelic-GetVersionAvailable" returns two distinct values , hence we used [-1] to select $version
    $Allsubscription = Get-AzSubscription | where { $_.WebAppName -like "*prod*"}
    #$Allsubscription = "HP-PROD-AZURE"
    foreach ($Subs in $Allsubscription)
    {
        $SubscriptionName = $Subs.WebAppName
        #$SubscriptionName = $Allsubscription
        Select-AzSubscription -Subscription $SubscriptionName

        $htmlcontent = "<html>
                            <body>
	                            <table border=1>
		                            <tr>
			                            <th>WebApp WebAppName</th>			                            
			                            <th>Installed NewRelic Version</th>
			                            <th>Available NewRelic Version </th>
                                        <th>Location </th>
                                        <th>Subscription</th>
		                            </tr>"

        $AllWebApp = Get-AzWebApp             
        foreach ($WebApp in $AllWebApp)
        {
            #$ResourceGroupName = $WebApp.ResourceGroup
            $w = $WebApp.WebAppName
            $L = $WebApp.location
            $NRelicInstalledVersion = NewRelic-GetVersionInstalled -WebAppName $WebApp.WebAppName -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
            if($NRelicInstalledVersion -ne $NRAvailableVersion)
            {
            $htmlcontent += "<tr><td>$w</td><td>$NRelicInstalledVersion</td><td>$NRAvailableVersion</td><td>$L</td><td>$SubscriptionName</td> </tr>"        
            }
        }
        $htmlcontent += "</table></body></html>"
    }
    #Return $requireddata
    #$requireddata | Export-Csv -Path $path\"NewRelic_AgentInstalledVersionReportWebapp_AllSubs.csv"
    $Subject = "NewRelic agent installed version report"
    $Username ="INFRA-NOTIFICATIONS"
    $Password = ConvertTo-SecureString "Jsl+k2R@not@f" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential $Username, $Password
    #Send-MailMessage -To mukul.srivastava@bold.com -From 'Azure Data Centre IP Addresses <INFRA-AUTOMATION@bold.com>' -Body $Body -Subject $Subject -SmtpServer smtp.sendgrid.net -Credential $credential -BodyAsHtml
    
    #Remove-Item -Path ($($file1.Directory.FullName)+"\NewRelicVersionInformation.csv")

    Send-MailMessage -to mukul.srivastava@bold.com -from "AzureRunBookReports@livecareer.com" -body $htmlcontent -Subject $Subject -SmtpServer smtp.sendgrid.net -Credential $credential -BodyAsHtml
}


Function Upgrade-NewRelic
{
    Param( 
        [Parameter(Mandatory = $true, HelpMessage="WebAppName for which NewRelic Agent Needs to upgrade ")][string] $WebAppName,
        #[Parameter(Mandatory = $true, HelpMessage= "ResourceGroupName of Webapp.")][string] $ResourceGroupName, 
        [Parameter(Mandatory = $true, HelpMessage="Subscription WebAppName of Webapp")][string]$SubscriptionName,    
        [Parameter(Mandatory = $true, HelpMessage="NewRelic.config file downLoad location")][string]$NRFileDownLoadLocation,
        [Parameter(Mandatory = $false, HelpMessage="To mention if app is a Webjob")][string]$AppType=""
        )

        $context = Get-AzContext -ErrorAction SilentlyContinue
        if($context.Account -eq $null)
                {
                    Login-AzAccount
                }

        Select-AzSubscription -Subscription $SubscriptionName
        $ResourceGroupName = (Get-AzWebApp -WebAppName $WebAppName).ResourceGroup
        #Checking webapp running status
        $RunningStatus = SlotRunningStatus -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

        #------------------UPGRADE-OPERATION-ON-PROD-SLOT-----------------
    if ($AppType -eq "")
    {
        if( $RunningStatus.prod -eq "Running")
        {
            #Takes Backup of NewRelic.config from prod slot
            Download-FileFromWebApp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName
  
            UnInstall-NewRelicAgent-ProdSlot -WebappName $WebAppName -ResourceGroupName $ResourceGroupName    
            #Start-Sleep 120 
            #AppWarmUp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

            #$CheckNRfolder = Get-ListFolder-Webapp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -slotName $SlotName

            #Delete-NRFolder -webAppName $WebAppName  -ResourceGroupName $ResourceGroupName     
            Install-NewrelicExtension-InTo-ProdSlot -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -SubscriptionName $SubscriptionName

            #Uploading the NewRelic.config file again to prod slot.
            Write-Host "Upload of NewRelic.config file will start after 20 seconds."
            Start-Sleep 20          
            #AppWarmUp -WebAppName $WebAppName
            UpLoad-FileToWebApp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName
        }
        Else
        {
            Write-Host "Webapp is stopped"
        }

        #-------------------UPGRADE-OPERATION-ON-STAGING-SLOT----------------

        [string]$SlotName = StagingSlotName -WebappName $WebAppName -ResourceGroupName $ResourceGroupName
    
        if($SlotName -ne 0)
        {
            if($RunningStatus.staging -eq "Running")
            {
                UnInstall-NewRelicAgent-StagingSlot -WebappName $WebAppName -ResourceGroupName $ResourceGroupName
                #Start-Sleep 120
                #AppWarmUp -WebAppName $WebAppName -SlotName $SlotName -ResourceGroupName $ResourceGroupName                
                #Delete-NRFolder -webAppName $WebAppName -ResourceGroupName $ResourceGroupName -slotName $SlotName
                Install-NewrelicExtension-InTo-StagingSlot -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -SubscriptionName $SubscriptionName
                Write-Host "Upload of NewRelic.config file will start after 20 seconds."
                Start-Sleep 20
                #AppWarmUp -WebAppName $WebAppName -SlotName $SlotName
                UpLoad-FileToWebApp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -slotName $SlotName -NRFileDownLoadLocation $NRFileDownLoadLocation
            }
            Else{
                   Write-Host "Webapp is in Stopped state"
                }
        }
            Else
            {
                Write-Host "Either staging slot doesn't exist or Multiple slot exist but none of them matched with WebAppName "Staging". Please verify it manually"
            }  
    }
    else{
        if($AppType -eq "webjob")
        {
            if( $RunningStatus.prod -eq "Running")
            {
            Write-Host "Upgrading webjob"   
            #Takes Backup of NR.xml from prod slot
            Write-Host "Downloading NR.xml"
            Download-FileFromWebJob -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName
            
            UnInstall-NewRelicAgent-ProdSlot -WebappName $WebAppName -ResourceGroupName $ResourceGroupName    
            #Start-Sleep 120 
            #AppWarmUp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

            #$CheckNRfolder = Get-ListFolder-Webapp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -slotName $SlotName

            #Delete-NRFolder -webAppName $WebAppName  -ResourceGroupName $ResourceGroupName     
            Install-NewrelicExtension-InTo-ProdSlot -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -SubscriptionName $SubscriptionName

            #Uploading the NewRelic.config file again to prod slot.
            Write-Host "Upload of NewRelic.config file will start after 20 seconds."
            Start-Sleep 20          
            #AppWarmUp -WebAppName $WebAppName
            UpLoad-FileToWebApp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -AppType "webjob"
            }
            else{
                Write-Host "Webapp of webjob is stopped"
            }
        }
        else{
            Write-Host "Mentioned AppType in input seems wrong. Please check your input"
        }
    }

}



Function Remove-DeleteLock() {

$sub = Get-AzSubscription

foreach ($eachsub in $sub)
{
    if(($eachsub.State -eq "Enabled" ) -and ($eachsub.Name -ne "COMMONSERVICES-DEV-TEST-AZURE"))
    {
        #$eachsub = $sub[0]
        $Subscription = $eachsub.name

        #$Subscription = "LC-DEV-TEST"
        Select-AzSubscription -SubscriptionName $Subscription


        $allresourcegroup = Get-AzResourceGroup
        #$eachresourcegroup = $allresourcegroup[5]

        foreach ($eachresourcegroup in $allresourcegroup)
        {
            if($eachresourcegroup.ResourceGroupName -ne "VM-SNAPSHOT-RG")
            {   
                $locks = Get-AzResourceLock -ResourceGroupName $eachresourcegroup.ResourceGroupName -LockName DontDelete -ErrorAction Ignore 
                foreach($lock in $locks)
                {
                    if($lock -ne $null)
                    {
                        $lock.ResourceId
                        Remove-AzResourceLock -LockId $lock.LockId -Force
                    }
                }
            }
        }
    }
} 

}




Function Apply-DeleteLock() {


#$sub = convertfrom-csv (Invoke-WebRequest "https://snapshotcsvstr.blob.core.windows.net/snapshotcsv/prod-plan.csv" -UseBasicParsing -ContentType "text/csv" ).ToString() 
$sub = Get-AzSubscription

foreach ($eachsub in $sub)
{
    #$eachsub = $sub[0]
    if(($eachsub.State -eq "Enabled" ) -and ($eachsub.Name -notlike "*DEV*"))
    {
        $Subscription = $eachsub.name

        #$Subscription = "LC-DEV-TEST"
        Select-AzSubscription -SubscriptionName $Subscription


        $allresourcegroup = Get-AzResourceGroup
        #$eachresourcegroup = $allresourcegroup[5]

        foreach ($eachresourcegroup in $allresourcegroup)
        {
            if(($eachresourcegroup.ResourceGroupName -ne "VM-SNAPSHOT-RG") -and ($eachresourcegroup.ResourceGroupName -ne "AUTOMATION-ACCOUNTS-RG") -and ($eachresourcegroup.ResourceGroupName -ne "PROD-IISLOG-RG") -and ($eachresourcegroup.ResourceGroupName -ne "VM-DBA-SNAPSHOT-RESTORE-RG") -and ($eachresourcegroup.ResourceGroupName -ne "MAGENTA-AZURE-DESK-RG"))
            {   
                $lock = Get-AzResourceLock -ResourceGroupName $eachresourcegroup.ResourceGroupName -LockName DontDelete -ErrorAction Ignore 
                if($lock -eq $null)
                {
                    New-AzResourceLock -LockName DontDelete -LockLevel CanNotDelete -LockNotes "Prevented from accidental deletion" -ResourceGroupName $eachresourcegroup.ResourceGroupName -Force
                }
            }
        }
    }

}

}


Function Upgrade-NewRelicV2($WebAppName,$Subscription){


Set-AzContext $Subscription | Out-Null
az account set -s $Subscription



#------------------UPGRADE-OPERATION-ON-PROD-SLOT-----------------

$app = Get-AzWebApp -Name $WebAppName
$WebAppName = $app.Name
$ResourceGroupName = $app.ResourceGroup


$status = $app.State

if ($status -eq "Running"){

#RouteAll settings
$set = az webapp config appsettings list -n $WebAppName --resource-group $ResourceGroupName | ConvertFrom-Json #? name -EQ "WEBSITE_VNET_ROUTE_ALL"
$vnetrouteall = $set | ? Name -EQ "WEBSITE_VNET_ROUTE_ALL"

if($app.SiteConfig.VnetRouteAllEnabled -eq $true -or $vnetrouteall.value -eq "1") {

Write-Host "RouteAll is enabled for $WebAppName, Please upgrade Newrelic manually after disabling RouteAll" -ForegroundColor Red

}

else {

#Download newrelic related configs
Download-FileFromWebAppV2 -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

#Uninstall Newrelic extension from prod slot
UnInstall-NewRelicAgent-ProdSlot -WebappName $WebAppName -ResourceGroupName $ResourceGroupName

#Warm-up time before Installation
Write-Host "Sleeping for 10 second after newrelic uninstallation "
Start-Sleep -Seconds 10


#Install latest extension
Install-NewrelicExtension-InTo-ProdSlot -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

#Pause for some time after Newrelic Installation and Restart
Write-Host "Sleeping for 50 second after Newrelic Installation and Restart"
Start-Sleep -Seconds 50
CheckStatus-AfterRestart -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName


#Uploading of newrelic related config file will start in 10 sec
Write-Host "Upload of NewRelic related config file will start in 10 seconds."
Start-Sleep 10
CheckStatus-AfterRestart -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName 


UpLoad-FileToWebAppV2 -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

}


}

else{

Write-Host "$WebAppName is Stopped, Newrelic Upgrade will be skipped" -ForegroundColor Red

}






#------------------UPGRADE-OPERATION-ON-OTHER-SLOTS-----------------
$slots = Get-AzWebAppSlot -Name $WebAppName -ResourceGroupName $ResourceGroupName

#$slots = Get-AzWebAppSlot -Name "POC-APP-ZK" -ResourceGroupName "POC-RG-ZK"

foreach($slot in $slots){


#Get the current slot name
$currentslot = $slot.Name.Split("/")[1]

#Check Status of the current Slot
$slotstatus = $slot.State

if ($slotstatus -eq "Running"){

$set = az webapp config appsettings list -n $WebAppName --resource-group $ResourceGroupName --slot $currentslot | ConvertFrom-Json #? name -EQ "WEBSITE_VNET_ROUTE_ALL"
$vnetrouteallslot = $set | ? Name -EQ "WEBSITE_VNET_ROUTE_ALL"


if($slot.SiteConfig.VnetRouteAllEnabled -eq $true -or $vnetrouteallslot.value -eq "1") {

Write-Host "RouteAll is enabled for $WebAppName/$currentslot, Please upgrade Newrelic manually after disabling RouteAll" -ForegroundColor Red

}

else {

#Uninstall newrelic from other slots
UnInstall-NewRelicAgent-OtherSlots -WebAppName $WebAppName -SlotName $currentslot -ResourceGroupName $ResourceGroupName


#Warm-up time before Installation
Write-Host "Sleeping for 10 second after newrelic uninstallation "
Start-Sleep -Seconds 10

#Check Status
CheckStatus-AfterRestart -WebAppName $WebappName -ResourceGroupName $ResourceGroupName

#Install newrelic on slots
Install-NewrelicExtension-InTo-StagingSlot -WebAppName $WebAppName -SlotName $currentslot -ResourceGroupName $ResourceGroupName

#Pause for some time after Newrelic Installation and Restart
Write-Host "Sleeping for 50 second after Newrelic installation and Restart"
Start-Sleep -Seconds 50
CheckStatus-AfterRestart -WebAppName $WebAppName -SlotName $SlotName -ResourceGroupName $resourceGroupName


#Uploading of newrelic related config file will start in 10 sec
Write-Host "Upload of NewRelic.config file will start after 10 seconds."
Start-Sleep 10
CheckStatus-AfterRestart -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -SlotName $currentslot



UpLoad-FileToWebAppV2 -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -slotName $currentslot


}
}

else{

Write-Host "$WebAppName/$currentslot is Stopped, Newrelic Upgrade will be skipped" -ForegroundColor Red

}

}

}






Function Install-NewrelicV2($WebAppName,$Subscription,$NewRelicAppName) {


#Context
Set-AzContext $Subscription | Out-Null
az account set -s $Subscription



#------------------INSTALL-OPERATION-ON-PROD-SLOT-----------------

$app = Get-AzWebApp -Name $WebAppName
$WebAppName = $app.Name
$ResourceGroupName = $app.ResourceGroup

$status = $app.State

if ($status -eq "Running"){

#RouteAll settings
$set = az webapp config appsettings list -n $WebAppName --resource-group $ResourceGroupName | ConvertFrom-Json #? name -EQ "WEBSITE_VNET_ROUTE_ALL"
$vnetrouteall = $set | ? Name -EQ "WEBSITE_VNET_ROUTE_ALL"

if($app.SiteConfig.VnetRouteAllEnabled -eq $true -or $vnetrouteall.value -eq "1") {

Write-Host "RouteAll is enabled for $WebAppName, Please upgrade Newrelic manually after disabling RouteAll" -ForegroundColor Red

}

else {

#Set app setings for newrelic app name and licence key
NewRelic-AppSettingsV2 -Webappname $WebAppName -ResourceGroup $ResourceGroupName -SubscriptionName $Subscription -NewRelicAppName $NewRelicAppName



#Install latest extension
Install-NewrelicExtension-InTo-ProdSlot -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

#Pause for some time after Newrelic Installation and Restart
#Write-Host "Sleeping for 50 second after Newrelic Installation and Restart"
#Start-Sleep -Seconds 50
#CheckStatus-AfterRestart -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName

}

}

else{

Write-Host "$WebAppName is Stopped, Newrelic Upgrade will be skipped" -ForegroundColor Red

}






#------------------INSTALL-OPERATION-ON-OTHER-SLOTS-----------------
$slots = Get-AzWebAppSlot -Name $WebAppName -ResourceGroupName $ResourceGroupName

#$slots = Get-AzWebAppSlot -Name "POC-APP-ZK" -ResourceGroupName "POC-RG-ZK"

foreach($slot in $slots){


#Get the current slot name
$currentslot = $slot.Name.Split("/")[1]

#Check Status of the current Slot
$slotstatus = $slot.State

if ($slotstatus -eq "Running"){

$set = az webapp config appsettings list -n $WebAppName --resource-group $ResourceGroupName --slot $currentslot | ConvertFrom-Json #? name -EQ "WEBSITE_VNET_ROUTE_ALL"
$vnetrouteallslot = $set | ? Name -EQ "WEBSITE_VNET_ROUTE_ALL"


if($slot.SiteConfig.VnetRouteAllEnabled -eq $true -or $vnetrouteallslot.value -eq "1") {

Write-Host "RouteAll is enabled for $WebAppName/$currentslot, Please upgrade Newrelic manually after disabling RouteAll" -ForegroundColor Red

}

else {

#Install newrelic on slots
Install-NewrelicExtension-InTo-StagingSlot -WebAppName $WebAppName -SlotName $currentslot -ResourceGroupName $ResourceGroupName


}

}


else{

Write-Host "$WebAppName/$currentslot is Stopped, Newrelic Upgrade will be skipped" -ForegroundColor Red

}

}



}





Function Delete-NRFolder($webAppName,$ResourceGroupName, $slotName = "")
{
#$ResourceGroupName = (Get-AzWebApp -WebAppName $webAppName).ResourceGroup
#UnInstall-NewRelicAgent-ProdSlot -WebappName $webAppName -ResourceGroupName $ResourceGroupName
#$kuduPath = "test"
  
    $apiAuthorizationToken =  Get-KuduApiAuthorisationHeaderValue $resourceGroupName $webAppName $slotName
    if ($slotName -eq "")
    {
        $apiUrl = "https://$webAppName.scm.azurewebsites.net/api/command"
    }
    else{
        $apiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/command"
        }

    $apiCommand = @{
        #command='del *.* /S /Q /F'
        command = 'powershell.exe -command "Remove-Item -path d:\\home\site\\wwwroot\\newrelic\\* -recurse"'
        dir='d:\\home\site\\wwwroot\\newrelic'        
                   }

    Write-Output $apiUrl
    Write-Output $apiAuthorizationToken
    Write-Output $apiCommand
    Invoke-RestMethod -Uri $apiUrl -Headers @{"Authorization"=$apiAuthorizationToken;"If-Match"="*"} -Method POST -ContentType "application/json" -Body (ConvertTo-Json $apiCommand)
        $apiCommand = @{
        #command='del *.* /S /Q /F'
        command = 'powershell.exe -command "Remove-Item -path d:\\home\\site\\wwwroot\\newrelic\\"'
        dir='d:\\home\\site\\wwwroot\\'        
                   }   
    Write-Output $apiUrl
    Write-Output $apiAuthorizationToken
    Write-Output $apiCommand
    Invoke-RestMethod -Uri $apiUrl -Headers @{"Authorization"=$apiAuthorizationToken;"If-Match"="*"} -Method POST -ContentType "application/json" -Body (ConvertTo-Json $apiCommand)
}

Function Get-ListFolder-Webapp ($WebAppName,$ResourceGroupName, $slotName = "" )
{
#$ResourceGroupName = (Get-AzWebApp -WebAppName $webAppName).ResourceGroup
#UnInstall-NewRelicAgent-ProdSlot -WebappName $webAppName -ResourceGroupName $ResourceGroupName
#$kuduPath = "test"
  
    $token = Get-AzAccessToken
    $kuduApiAuthorisationToken = "Bearer $($token.Token)"
    if ($slotName -eq "")
    {
        $apiUrl = "https://$webAppName.scm.azurewebsites.net/api/command"
    }
    else{
        $apiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/command"
        }

    $apiCommand = @{
        #command='del *.* /S /Q /F'
        command = 'powershell.exe -command "Get-Item -path d:\\home\\*"'
        dir='d:\\home\\'        
                   }

    #Write-Output $apiUrl
    #Write-Output $kuduApiAuthorisationToken
    #Write-Output $apiCommand
    $ListFolder = @()
    $ListFolder = Invoke-RestMethod -Uri $apiUrl -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method post -ContentType "application/json" -Body (ConvertTo-Json $apiCommand)     
    #Invoke-RestMethod -Uri $apiUrl -Headers @{"Authorization"=$apiAuthorizationToken;"If-Match"="*"} -Method post -ContentType "application/json" -Body (ConvertTo-Json $apiCommand)        
    Return $ListFolder.Output.Contains("newrelic")    
}

<#Scope of this script to set the default values of certain settings during the webapp/api/resource creation #>
###############################################################################################################
# CREATE "Webapp" 
# creating slot "Staging" 
# Set TLS version to 1.0 on both slot.
# Set ARR affinity = false for both slot

#https://ruslany.net/2016/10/using-powershell-to-manage-azure-web-app-deployment-slots/

#Select-AzSubscription -Subscription COMMONSERVICES-DEV-TEST-AZURE

function set-defaultsettings 
{

param ( $propertiesObject = @{ minTlsVersion=1.0; AlwaysOn = $true; Use32BitWorkerProcess = $false; NetFrameworkVersion = "v4.7"; phpVersion = "off"; managedPipelineMode= "integrated";http20Enabled = $false })
Set-AzResource -PropertyObject $propertiesObject -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/config -ResourceName "$ResourceName/web" -ApiVersion 2016-08-01 -Force
#Set the ARRaffinity to false
Set-AzResource -ResourceType "Microsoft.Web/sites" -ResourceName $resourcename -ResourceGroupName $ResourceGroupName  -Properties @{"ClientAffinityEnabled" = $false} -force
#Doing the required default settings for "staging" slot
Set-AzResource -PropertyObject $propertiesObject -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/slots/config -ResourceName "$ResourceName/staging/web" -ApiVersion 2016-08-01 -Force
Set-AzResource -ResourceType "Microsoft.Web/sites/slots" -ResourceName $resourcename/staging -ResourceGroupName $ResourceGroupName  -Properties @{"ClientAffinityEnabled" = $false} -force

}

function new-appcreation
{

param (
    [Parameter(Mandatory = $false, 
    HelpMessage= "Data center location where resource needs to be created.")]
    [String]$ResourceLocation = "Canada central",

    [Parameter(Mandatory = $true, 
    HelpMessage= "Resource WebAppName which needs to be created e.g Webapp or API app")]
    #[ValidatePattern("[a-z]")]
    [String]$ResourceName,

    [Parameter(Mandatory = $true, 
    HelpMessage= "Input the Kind of app which needs to be created e.g api , app")]
    [String]$Kind,

    [Parameter(Mandatory = $false, 
    HelpMessage= "Enter ResourceGroup WebAppName in which webapp/app needs to be placed")]
    [String]$ResourceGroupName="DEV-PLAN-RG",

    [Parameter(Mandatory = $false, 
    HelpMessage= "Enter Subscription WebAppName in which App/API needs to be created")]
    [String]$SubscriptionName = "COMMONSERVICES-DEV-TEST-AZURE",

    [Parameter(Mandatory = $false, 
    HelpMessage= "Enter App service plan WebAppName which needs to be used")]
    [String]$AppServicePlanName = "DEV-SP-01"

      )
    Select-AzSubscription -Subscription $SubscriptionName
    $Subscription = Get-AzSubscription -SubscriptionName $SubscriptionName
    
    $SubscriptionID = $Subscription.Id             #Fetching the subscription ID.
    $AllAppServicePlan = Get-AzAppServicePlan #Fetching all app service plan of subscription.
    #Below New line has been added
    $AppServicePlanDetails = $AllAppServicePlan | Where {$_.AppServicePlanName -like $AppServicePlanName}    
    #This one has been depricated against above line.
    #$AppServicePlanDetails = $AllAppServicePlan | Where {$_.serverFarmWithRichSkuName -like $AppServicePlanName} #Getting the right collection from which app service plan belongs.
    $ResourceGroupAppServicePlan = $AppServicePlanDetails.ResourceGroup #Getting the actual "ResourceGroup" WebAppName from which app service plan belongs to.
       
    $serverFarmId	=	"/subscriptions/$subscriptionID/resourceGroups/$ResourceGroupAppServicePlan/providers/Microsoft.Web/serverfarms/$AppServicePlanName"
    $PropertiesObjectfarmid = @{"serverFarmId"=$serverFarmId}

    if ( $kind -like "API")
    {
    New-AzResource -Location $ResourceLocation -PropertyObject $PropertiesObjectfarmid -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites -ResourceName $ResourceName -Kind $kind -ApiVersion 2016-08-01 -Force  
    #Creating "Staging" slot of webapp.
    New-AzWebAppSlot -WebAppName $ResourceName -slot staging -ResourceGroupName $ResourceGroupName
    #Get-AzResource -ResourceType microsoft.web/sites/config -ResourceName $ResourceName -ResourceGroupName $ResourceGroupName -ApiVersion 2016-08-01
    #Applying default settings
    set-defaultsettings   
    }
    elseif ( $kind -like "App")
    {
    #Creating webapp.
    New-AzResource -Location $ResourceLocation -PropertyObject $PropertiesObjectfarmid -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites -ResourceName $ResourceName -Kind $kind -ApiVersion 2016-08-01 -Force 
    #Creating "Staging" slot of webapp.
    New-AzWebAppSlot -WebAppName $ResourceName -slot staging -ResourceGroupName $ResourceGroupName
    #Applying default settings
    set-defaultsettings
    #Get-AzResource -ResourceType microsoft.web/sites/config -ResourceName $ResourceName -ResourceGroupName $ResourceGroupName -ApiVersion 2016-08-01
    }
    else {
    Write-Host "Input is incorrect"
         }

    #Writing the error and breaking the script.
    if ( $Error -ne $null)
    {
    Write-host $Error
    $Error.Clear()

    }
}

#12112018-----------------------------------------------------------------------------------------------------------------
#Description
#This script is to list down all azure service bus Topics and Queues details.
function livecareerserviceBusTopicsQueues
{ 
    param (
            [Parameter(Mandatory = $true, HelpMessage = "WebAppName of environment, enter DEV or PROD")]
                [String]$environment,
            [Parameter (Mandatory = $true, 
                        HelpMessage= "Input the path where do you need to save the output file")]
                [String]$path
          )
    #Declaring the array to store results.
    $requireddata = @()
    $requireddata1 = @()
    #Get all Azure subsciption.
    $AllAzuresubscription = Get-AzSubscription
    #Runnning loop across each subscription.
    foreach ( $subscription in $AllAzuresubscription)
            {
            #Storing the "environement" variable value to another variable with "*" prefix/suffix .
            [string]$env=("*"+$environment+"*")
            #If statement to run based on input insert into to $environment variable.
            if($subscription.WebAppName -like $env)
                {
                #Selecting the subscription as mentioned in foreach loop above.
                Select-AzSubscription -Subscription $subscription.WebAppName
                #Extracting the list of service bus exist in subscription.                
                $AllServiceBusNameSpace = Get-AzServiceBusNamespace
                #Running through each service bus to fetch associated details.
                foreach ( $ServiceBusNameSpace in $AllServiceBusNameSpace)
                {
                $QueueDetails = Get-AzServiceBusQueue -ResourceGroupName $ServiceBusNameSpace.ResourceGroup -Namespace $ServiceBusNameSpace.WebAppName
                $TopicDetails = Get-AzServiceBusTopic -ResourceGroupName $ServiceBusNameSpace.ResourceGroup -Namespace $ServiceBusNameSpace.WebAppName
                #A single NameSpace may have multiuple Queues, hence running through each of collection while $QueueDetails is not Null.
                    if($QueueDetails -ne $null)
                    {
                        foreach($queue in $QueueDetails)
                        {
                        $waobj = new-object -TypeName PSobject
                        $waobj | Add-Member -MemberType NoteProperty -WebAppName "ServiceQueue WebAppName" -Value $queue.WebAppName                        
                        $waobj | Add-Member -MemberType NoteProperty -WebAppName "Created On" -Value $queue.CreatedAt
                        $waobj | Add-Member -MemberType NoteProperty -WebAppName "ServiceBusNameSpace" -Value $ServiceBusNameSpace.WebAppName
                        $waobj | Add-Member -MemberType NoteProperty -WebAppName "Location" -Value $ServiceBusNameSpace.Location
                        $waobj | Add-Member -MemberType NoteProperty -WebAppName "Subscription" -Value $subscription.WebAppName
                        $requireddata += $waobj
                        }
                    }
                #A single NameSpace may have multiuple Topics, hence running through each of collection while $TopicDetails is not Null.
                    if($TopicDetails -ne $null)
                    {
                        foreach ( $Topic in $TopicDetails)
                        {
                        $waobj1 = New-Object -TypeName PSobject
                        $waobj1 | Add-Member -MemberType NoteProperty -WebAppName "Topic WebAppName" -Value $Topic.WebAppName
                        $waobj1 | Add-Member -MemberType NoteProperty -WebAppName "Created On" -Value $Topic.CreatedAt
                        $waobj1 | Add-Member -MemberType NoteProperty -WebAppName "ServiceBusNameSpace" -Value $ServiceBusNameSpace.WebAppName
                        $waobj1 | Add-Member -MemberType NoteProperty -WebAppName "Location" -Value $ServiceBusNameSpace.Location
                        $waobj1 | Add-Member -MemberType NoteProperty -WebAppName "Subscription" -Value $subscription.WebAppName
                        $requireddata1 += $waobj1
                        }
                    }
                }
                }
            }
            #Exporting the result to CSV file.
            $requireddata | Export-Csv -Path $path\QueueDetails.csv
            $requireddata1 | Export-Csv -Path $path\TopicDetails.csv

}
    

#12112018--------------------------------------------------------------------------------------------------------------------
<#This scripts list down the outbound IP Addresses of webapps #>
function get-OutboundIpAddresses
{

param (
    [Parameter(Mandatory = $false, 
    HelpMessage= "Enter subscription WebAppName.")]
    [string]$SubscriptionName = "Null",
    [Parameter (Mandatory = $true, 
                HelpMessage= "Input the path where do you need to save the output file")]
    [String]$path
    )

    $requireddata = @()

    if ($SubscriptionName -eq "Null")
    {
        $allsubscription = get-AzSubscription            
        foreach ($subscription in $allsubscription)
        {
            Select-AzSubscription -Subscription $subscription.WebAppName
            $allwebapp = get-AzWebApp 
            foreach ($webapp in $allwebapp)
            {
            [string]$str_id = $webapp.id
            [string]$resourcegroup = $str_id.split('/')[4]

            $webappdetails = Get-AzWebApp -ResourceGroupName $resourcegroup $webapp.WebAppName
            $waobject = new-object -TypeName PSobject
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "WebappName" -Value $webapp.WebAppName
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "OutboundIpAddresses" -Value $webapp.OutboundIpAddresses
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "ResourceGroup" -Value $resourcegroup
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "Subscription" -Value $subscription.WebAppName
            $requireddata +=$waobject
            }
        }
        $requireddata | Export-Csv -Path e:\temp\OutboundIpAddressesDetails.csv
        Write-Host "Please check e:\temp\OutboundIpAddressesDetails.csv "
    }
    else
    {
    Select-AzSubscription -Subscription $subscriptionName
            $allwebapp = get-AzWebApp 
            foreach ($webapp in $allwebapp)
            {
            [string]$str_id = $webapp.id
            [string]$resourcegroup = $str_id.split('/')[4]

            $webappdetails = Get-AzWebApp -ResourceGroupName $resourcegroup $webapp.WebAppName
            $waobject = new-object -TypeName PSobject
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "WebappName" -Value $webapp.WebAppName
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "OutboundIpAddresses" -Value $webapp.OutboundIpAddresses
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "ResourceGroup" -Value $resourcegroup
            $waobject | Add-Member -MemberType NoteProperty -WebAppName "Subscription" -Value $subscriptionName
            $requireddata +=$waobject
            }
            $requireddata | Export-Csv -Path $path\OutboundIpAddressesDetails.csv
            Write-Host "Please check $path\OutboundIpAddressesDetails.csv "
    }
}

#Upgrade-NewRelicV2 -WebAppName "PROD-MPR-CC-01" -Subscription "COMMONSERVICES-PROD-AZURE"

#Install-NewrelicV2 -WebAppName "PROD-COMMON-EVENTSTORE-API-CC" -Subscription "COMMONSERVICES-PROD-AZURE"