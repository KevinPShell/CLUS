$computer=Read-Host "Enter server name"
copy-item -Path "D:\Sources\Scripts\Maintenance\WSUS_v2-AutoReboot.ps1" -Destination (new-item -type directory -force ("\\$computer\d$\Sources\Scripts\Maintenance"+ $newSub)) -force -ea 0

Invoke-WUInstall -ComputerName $computer -Script {D:\Sources\Scripts\Maintenance\WSUS_v2-AutoReboot.ps1} -Confirm:$False -Verbose
