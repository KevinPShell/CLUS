# Reboot-Cluster.ps1
# Posted to practicalpowershell.com
# Edited by : Kevin Cordeiro
Import-Module PSWindowsUpdate
$clustername = ""
$logdate = (get-date).tostring('yyyy-MM-dd')
$log = "C:\ClusterReboot-$clustername-$logdate.log"
#The recipient lists need to be comma delimited strings
#i.e "user@contoso.com"
$emailrecipients = ""
$erroremailrecipients = ""
$emailfrom = ""
$emailserver = ""
#Check if same log name exists. If so, delete.
if(test-path $log)
{
remove-item $log
}
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Starting maintenance for cluster $clustername"
# Make sure the cluster module is loaded
#
$ClusterModLoaded = $FALSE
$CurrentMods = Get-Module

# Check if we need to load the module
foreach ($Mod in $CurrentMods)
{
if ($Mod.Name -eq "FailoverClusters")
    {
    $ClusterModLoaded = $TRUE
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now PS cluster module loaded successfully"
    }
}
if ($ClusterModLoaded -eq $FALSE)
{
    try
    {
    $null = Import-Module FailoverClusters
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now PS cluster module loaded successfully"
    }
    catch
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now Unable to load PS cluster module, terminating script"

    Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
    -Subject "$Clustername patching error" `
    -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
    -attachment $log -priority high

    exit
    }
}
###################
# Make sure the cluster module is loaded
#
$PSWUModLoaded = $FALSE
$CurrentMods = Get-Module

# Check if we need to load the module
foreach ($Mod in $CurrentMods)
{
if ($Mod.Name -eq "PSWindowsUpdate")
    {
    $ClusterModLoaded = $TRUE
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now PS Windows Update module loaded successfully"
    }
}
if ($ClusterModLoaded -eq $FALSE)
{
    try
    {
    $null = Import-Module PSWindowsUpdate
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now PS Windows Update module loaded successfully"
    }
    catch
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now Unable to load PS Windows Update module, terminating script"

    Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
    -Subject "$Clustername patching error" `
    -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
    -attachment $log -priority high

    exit
    }
}
###################
#Get list of cluster groups.
$clustergroup = get-clustergroup -cluster $clustername

#Loop through all groups. Create array for later rebalance.
$groupArray = @()
$groupNum = 0
foreach($group in $clustergroup)
{
$groupArray += ,@($groupNum,$group.name.tostring(),
$group.ownernode.tostring(),$group.state.tostring())
$groupNum++
}

$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Found all cluster groups"

foreach($gA in $groupArray)
{
$now = (get-date).tostring('HH:mm:ss -')
$gAName = $gA[1]
$gAOwner = $gA[2]
$gAState = $gA[3]
add-content $log "$now $gAName found on $gAOwner in state $gAState"
}

#Find all nodes in cluster, begin loop.

$clusternode = get-clusternode -cluster $clustername

foreach($node in $clusternode)
{
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Starting loop for $node"

    #Move all resources off node to be patched.
    foreach($group in $clustergroup)
    {
        if($group.ownernode.tostring() -eq $node.name.tostring())
        {
            try
            {
            $now = (get-date).tostring('HH:mm:ss -')
            add-content $log "$now Moving $group off node $node"
            move-clustergroup -name $group.name.tostring() -cluster $clustername -ev errormsg
            }
            catch
            {
            $now = (get-date).tostring('HH:mm:ss -')
            add-content $log "Error moving $group! Aborting script now and sending alert email"
            add-content $log $errormsg

            Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
            -Subject "$Clustername patching error" `
            -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
            -attachment $log -priority high
            exit
            }
        }
    }

#Verify no groups are still on the node in this loop.
$activecount = $clustergroup |
 where-object {$_.OwnerNode.tostring() -eq $node.name.tostring()}

if($activecount -eq $NULL)
{
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now No more groups on $node"
}
else
{
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Groups are still active on $node, possible script error. Terminating."

Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
-Subject "$Clustername patching error" `
-Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
-attachment $log -priority high
exit
}

#Pause cluster service.
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Pausing cluster service on $node"
    try
    {
    suspend-clusternode -name $node.name.tostring() -cluster $clustername -ev errormsg
    }
    catch
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now Error pausing cluster service on $node. Terminating"
    add-content $log $errormsg
    #email
    }

#######WSUS PART START
#Check for update
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Checking for updates"

#Copy current versions to remote server, overwrite existing
copy-item -Path "D:\Sources\Scripts\Maintenance\WSUS_v2.ps1" -Destination (new-item -type directory -force ("\\$node\d$\Sources\Scripts\Maintenance"+ $newSub)) -force -ea 0

#Run remote Powershell to start update process. Capture output and process.
try
{
[string]$UpdateLaunch = Invoke-WUInstall -ComputerName $node `
-Script {D:\Sources\Scripts\Maintenance\WSUS_v2.ps1} -Confirm:$False -Verbose
}
catch
{
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Error running update launcher"
add-content $log $error
Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
-Subject "$Clustername patching error" `
-Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
-attachment $log -priority high
exit
}
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Updates complete on $node"
add-content $log "$now $updateLaunch"
start-sleep -seconds 120
#if($UpdateLaunch.contains("Completed"))
#{
#Wait for completion
#$now = (get-date).tostring('HH:mm:ss -')
#add-content $log "$now Updates complete on $node"
#add-content $log "$now $updateLaunch"
#}
#elseif($UpdateLaunch.contains("Found [0] Updates in pre search criteria"))
#{
#Move to reboot.
#$now = (get-date).tostring('HH:mm:ss -')
#add-content $log "$now No updates to install on $node"
#}
#else #Assume error condition
#{
#$now = (get-date).tostring('HH:mm:ss -')
#add-content $log "$now Error on update launcher: $UpdateLaunch"

#    Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
#    -Subject "$Clustername patching error" `
#    -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
#    -attachment $log -priority high
#exit
#}
########WSUS PART END

$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Rebooting $node now"
#Reboot node. Use the -force switch as the operation will fail
#if other users are logged on.
restart-computer -computername $node.name.tostring() -force
start-sleep -seconds 300

#Verify node is rebooted.
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Checking status of $node to confirm reboot completion"

#Check every 60 seconds for node state. If reboot has taken longer than
#30 minutes, exit script.
$checkcount=0

while($node.state.tostring() -ne 'Paused')
{
    if($checkcount -lt 25)
    {
    $nodestate = $node.state.tostring()
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now Node status for $node is $nodestate, waiting 30 seconds"
    $checkcount++
    start-sleep -seconds 60
    }
    else
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now Node $node unresponsive after 15 minutes. Terminating script"

    Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
    -Subject "$Clustername patching error" `
    -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
    -attachment $log -priority high

    exit
    }
}
#Resume cluster service.
$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Resuming cluster service on $node"
    try
    {
    resume-clusternode -name $node.name.tostring() -cluster $clustername -ev errormsg
    }
    catch
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now Error resuming cluster service on $node. Terminating"
    add-content $log $errormsg

    Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
    -Subject "$Clustername patching error" `
    -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
    -attachment $log -priority high

    exit
    }
}
#end node loop

#All patching complete. Return groups to original location.

foreach($gA in $groupArray)
{
$gAName = $gA[1]
$gAOwner = $gA[2]
$gAState = $gA[3]

$cg = get-clustergroup -name $gAName -cluster $clustername

if($cg.ownernode.tostring() -eq $gAOwner)
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now $gAName is on original node"
    }
    else
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now $gAName is not on original node, moving to $gAOwner"
        try
        {
        move-clustergroup -name $gAName -cluster $clustername -node $gAOwner -ev errormsg
        }
        catch
        {
        $now = (get-date).tostring('HH:mm:ss -')
        add-content $log "Error moving $gAName! Aborting script now and sending alert email"
        add-content $log $errormsg

        Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
        -Subject "$Clustername patching error" `
        -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
        -attachment $log -priority high

        exit
        }
    }

    #Check group state before exiting.
    if ($cg.state.tostring() -eq $GAState)
    {
    $now = (get-date).tostring('HH:mm:ss -')
    add-content $log "$now $gAName is in the expected state ($gAState)"
    }
    else
    {
    $now = (get-date).tostring('HH:mm:ss -')
    $cgstate = $cg.state.tostring()
    add-content $log "$now $gAName is not in the expected state. Currently '$cgstate', expected '$gAState'"

    Send-MailMessage -to $erroremailrecipients -from $emailfrom -smtpserver $emailserver `
    -Subject "$Clustername patching error" `
    -Body "The automated patching/reboot of $clustername encountered an error. See attached job log." `
    -attachment $log -priority high
    exit
    }
}

$now = (get-date).tostring('HH:mm:ss -')
add-content $log "$now Script complete. Sending email."

Send-MailMessage -to $emailrecipients -from $emailfrom -smtpserver $emailserver `
 -Subject "$Clustername patching complete" `
-Body "The automated patching/reboot of $clustername is complete. See attached job log." `
-attachment $log
