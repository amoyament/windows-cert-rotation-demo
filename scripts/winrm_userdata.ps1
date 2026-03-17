<powershell>
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Enable WinRM HTTP (port 5985) - simple and reliable
winrm quickconfig -q

# Configure WinRM service settings
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service/auth '@{Negotiate="true"}'

# Ensure WinRM is running and set to automatic startup
Set-Service -Name WinRM -StartupType Automatic
Restart-Service -Name WinRM

# Open firewall rules
netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985
netsh advfirewall firewall add rule name="WinRM HTTPS" dir=in action=allow protocol=TCP localport=5986
netsh advfirewall firewall add rule name="HTTPS" dir=in action=allow protocol=TCP localport=443
netsh advfirewall firewall add rule name="HTTP" dir=in action=allow protocol=TCP localport=80

Write-Output "WinRM HTTP configuration complete on port 5985"
</powershell>
