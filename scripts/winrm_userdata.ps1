<powershell>
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = "https://raw.githubusercontent.com/ansible/ansible-documentation/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
$file = "$env:temp\ConfigureRemotingForAnsible.ps1"
(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
& $file -SkipNetworkProfileCheck

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

netsh advfirewall firewall add rule name="WinRM HTTPS" dir=in action=allow protocol=TCP localport=5986
netsh advfirewall firewall add rule name="HTTPS" dir=in action=allow protocol=TCP localport=443
netsh advfirewall firewall add rule name="HTTP" dir=in action=allow protocol=TCP localport=80
</powershell>
