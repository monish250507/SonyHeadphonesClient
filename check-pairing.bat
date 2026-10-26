@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$devs = Get-PnpDevice | Where-Object { $_.Class -eq 'Bluetooth' -and $_.FriendlyName -like '*CH520*' -or $_.FriendlyName -like '*Sony*' }; " ^
  "if ($devs) { Write-Host '[FOUND] Sony WH-CH520 is paired in Windows!' -ForegroundColor Green; $devs | Format-Table FriendlyName, Status } " ^
  "else { Write-Host '[NOT PAIRED YET] Windows does not see WH-CH520 paired yet.' -ForegroundColor Red; Write-Host 'Please put your WH-CH520 in pairing mode (hold power button 7 sec) and click Add Device in Windows Bluetooth settings.' -ForegroundColor Yellow }"
pause
