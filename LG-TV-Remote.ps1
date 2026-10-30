# Run with PowerShell on Windows. No additional modules required.
if($PSVersionTable.PSVersion.Major -lt 7){throw 'This tool requires PowerShell 7. Use Start-LG-TV.cmd or install PowerShell 7.'}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Net.Security;
using System.Net.WebSockets;
using System.Security.Cryptography.X509Certificates;
public class LgConnection {
 public ClientWebSocket Socket = new ClientWebSocket();
 public string CertificateHash;
 public LgConnection() {
  Socket.Options.RemoteCertificateValidationCallback = (s,c,h,e) => {
   CertificateHash = c == null ? null : c.GetCertHashString(); return c != null;
  };
 }
}
'@
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:connection=$null
$script:sequence=0
$script:busy=$false
$script:dataDirectory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LG-TV-Remote'
[void][IO.Directory]::CreateDirectory($script:dataDirectory)
$script:store=Join-Path $script:dataDirectory 'settings.json'
$script:profiles=@{}
if(Test-Path $script:store){
 try { $saved=Get-Content $script:store -Raw|ConvertFrom-Json; foreach($p in $saved.PSObject.Properties){$script:profiles[$p.Name]=$p.Value} } catch {}
}
$form=New-Object Windows.Forms.Form
$form.Text='LG TV Connection'; $form.Size=New-Object Drawing.Size(900,760)
$form.MinimumSize=New-Object Drawing.Size(900,760); $form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Segoe UI',10)
function Label($text,$x,$y,$w=150){$c=New-Object Windows.Forms.Label; $c.Text=$text;$c.SetBounds($x,$y,$w,24);$form.Controls.Add($c);return $c}
function Button($text,$x,$y,$w=120){$c=New-Object Windows.Forms.Button;$c.Text=$text;$c.SetBounds($x,$y,$w,34);$form.Controls.Add($c);return $c}
$null=Label 'TV address' 20 22 95
$address=New-Object Windows.Forms.TextBox;$address.SetBounds(125,18,190,30);$address.Text='';$form.Controls.Add($address)
$connect=Button 'Connect' 330 16
$reconnect=Button 'Reconnect' 460 16
$disconnect=Button 'Disconnect' 590 16
$status=Label 'Disconnected' 20 62 820
$group=New-Object Windows.Forms.GroupBox;$group.Text='Permissions to request when pairing';$group.SetBounds(20,96,840,104);$form.Controls.Add($group)
$checks=@{}
$permissionOptions=@(@('READ_INSTALLED_APPS','App list',15,28,$true),@('READ_SETTINGS','Read settings',200,28,$true),@('READ_RUNNING_APPS','Current app',400,28,$true),@('READ_UPDATE_INFO','Software info',620,28,$false),@('LAUNCH','Launch apps',15,61,$false),@('CONTROL_AUDIO','Volume controls',200,61,$false),@('WRITE_SETTINGS','Change settings',400,61,$false))
foreach($o in $permissionOptions){$c=New-Object Windows.Forms.CheckBox;$c.Text=$o[1];$c.SetBounds($o[2],$o[3],175,27);$c.Checked=$o[4];$group.Controls.Add($c);$checks[$o[0]]=$c}
$pair=Button 'Request pairing' 20 212 160
$forget=Button 'Forget saved key' 190 212 160
$null=Label 'Accept the prompt on the TV. Permission changes require a new pairing.' 365 218 495
$actions=New-Object Windows.Forms.ComboBox;$actions.DropDownStyle='DropDownList';$actions.SetBounds(20,266,285,30)
@('TV information','Installed apps','Home-screen tiles','Current app','Available services','Software version','Volume','Viewing recognition (Live Plus)','Home-screen settings')|ForEach-Object{[void]$actions.Items.Add($_)}
$actions.SelectedIndex=0;$form.Controls.Add($actions)
$run=Button 'Run request' 320 262 140
$apps=New-Object Windows.Forms.ComboBox;$apps.DropDownStyle='DropDownList';$apps.SetBounds(475,266,240,30);$form.Controls.Add($apps)
$launch=Button 'Launch app' 730 262 130
$null=Label 'Custom SSAP address (advanced)' 20 310 350
$uriBox=New-Object Windows.Forms.TextBox;$uriBox.SetBounds(20,338,650,28);$uriBox.Text='ssap://system/getSystemInfo';$form.Controls.Add($uriBox)
$custom=Button 'Send custom' 690 333 170
$null=Label 'JSON parameters (leave {} for requests without parameters)' 20 377 700
$payloadBox=New-Object Windows.Forms.TextBox;$payloadBox.SetBounds(20,405,840,28);$payloadBox.Text='{}';$form.Controls.Add($payloadBox)
$log=New-Object Windows.Forms.RichTextBox;$log.SetBounds(20,450,840,235);$log.ReadOnly=$true;$log.Font=New-Object Drawing.Font('Consolas',9);$log.Anchor='Top,Bottom,Left,Right';$form.Controls.Add($log)
$clear=Button 'Clear log' 20 691 120;$clear.Anchor='Bottom,Left'
$null=Label 'Keys are encrypted for your Windows account. No system components are modified.' 160 697 700
function Log($text){$log.AppendText(('['+(Get-Date -Format HH:mm:ss)+'] '+$text+"`r`n"));$log.SelectionStart=$log.TextLength;$log.ScrollToCaret()}
function Save-Profiles {$script:profiles|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $script:store -Encoding UTF8}
function Await-Task($task,$seconds=12){
 $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
 while(!$task.IsCompleted){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 25;if([DateTime]::UtcNow -gt $deadline){if($script:connection){$script:connection.Socket.Abort()};throw 'Timed out. Reconnect and try again.'}}
 $task.GetAwaiter().GetResult()
}
function Close-TV {
 if($script:connection){$script:connection.Socket.Dispose();$script:connection=$null}
 $status.Text='Disconnected'
}
function Open-TV {
 Close-TV
 $ip=$null
 if(![Net.IPAddress]::TryParse($address.Text.Trim(),[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'Enter the TV IPv4 address, as shown in the TV network settings.'}
 $script:tvAddress=$ip.ToString()
 $script:connection=New-Object LgConnection
 $cancel=New-Object Threading.CancellationTokenSource
 try {Await-Task ($script:connection.Socket.ConnectAsync([uri]("wss://"+$script:tvAddress+':3001'),$cancel.Token)) 10}finally{$cancel.Dispose()}
 $hash=$script:connection.CertificateHash
 $profile=$script:profiles[$script:tvAddress]
 if(!$profile -or $profile.Certificate -ne $hash){
  $answer=[Windows.Forms.MessageBox]::Show($form,"Trust the local certificate for TV $script:tvAddress ?`n`nFingerprint: $hash`n`nConfirm this is your TV address. A changed fingerprint can mean a TV update or a different device.",'Trust TV certificate','YesNo','Question')
  if($answer -ne 'Yes'){Close-TV;throw 'Connection cancelled.'}
  $script:profiles[$script:tvAddress]=[pscustomobject]@{Certificate=$hash;Key=''};Save-Profiles
 }
 $status.Text='Connected; authenticating';Log "Secure connection to $script:tvAddress (certificate pinned)."
}
function Send-Message($message){
 $bytes=[Text.Encoding]::UTF8.GetBytes(($message|ConvertTo-Json -Depth 20 -Compress))
 $cancel=New-Object Threading.CancellationTokenSource
 try {Await-Task ($script:connection.Socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$cancel.Token))}finally{$cancel.Dispose()}
}
function Receive-Message($seconds=12){
 $buffer=New-Object byte[] 65536;$stream=New-Object IO.MemoryStream;$cancel=New-Object Threading.CancellationTokenSource
 try {do {$result=Await-Task ($script:connection.Socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$cancel.Token)) $seconds
 if($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close){throw 'TV closed the connection.'}
 $stream.Write($buffer,0,$result.Count);if($stream.Length -gt 4194304){throw 'TV response exceeds 4 MB.'}
 }while(!$result.EndOfMessage)
 return ([Text.Encoding]::UTF8.GetString($stream.ToArray())|ConvertFrom-Json)
 }finally{$stream.Dispose();$cancel.Dispose()}
}
function Register-TV($newPairing){
 Open-TV
 if($newPairing){
  $permissions=@($checks.Keys|Where-Object{$checks[$_].Checked})
  if(!$permissions.Count){throw 'Select at least one permission.'}
  Log ('Requesting pairing: '+($permissions -join ', '))
  $registration=@{pairingType='PROMPT';manifest=@{manifestVersion=1;appVersion='1.0';permissions=$permissions}}
 }else{
  $encrypted=$script:profiles[$script:tvAddress].Key
  if(!$encrypted){throw 'No saved key. Click Request pairing first.'}
  $secure=ConvertTo-SecureString $encrypted
  $credential=New-Object Management.Automation.PSCredential('tv',$secure)
  $registration=@{'client-key'=$credential.GetNetworkCredential().Password}
 }
 Send-Message @{id='pair';type='register';payload=$registration}
 $deadline=[DateTime]::UtcNow.AddSeconds(65)
 do {
  $message=Receive-Message 65
  if($message.type -eq 'registered'){
   $newKey=$message.payload.'client-key'
   if($newKey){$script:profiles[$script:tvAddress].Key=ConvertFrom-SecureString (ConvertTo-SecureString $newKey -AsPlainText -Force);Save-Profiles}
   $status.Text="Paired and connected to $script:tvAddress";Log 'Pairing authenticated. Key hidden.';return
  }
  if($message.type -eq 'error'){throw ('Pairing rejected: '+$message.error)}
  $status.Text='Waiting for approval on the TV...';Log 'Accept the connection prompt on your TV.'
 }while([DateTime]::UtcNow -lt $deadline)
 throw 'Pairing timed out. Click Request pairing to retry.'
}
function Request-TV($uri,$parameters=@{}){
 if(!$script:connection -or $script:connection.Socket.State -ne 'Open'){throw 'Connect or request pairing first.'}
 $script:sequence++;$id='gui_'+$script:sequence
 Log ('SEND '+$uri+' '+($parameters|ConvertTo-Json -Depth 10 -Compress))
 Send-Message @{id=$id;type='request';uri=$uri;payload=$parameters}
 do {$message=Receive-Message}while($message.id -ne $id)
 if($message.type -eq 'error'){
  if($message.error -like '401*'){throw 'TV denied permission. Request a new pairing with the relevant permission selected. Some firmware blocks protected operations even after approval.'}
  throw $message.error
 }
 return $message.payload
}
function Perform($operation){
 if($script:busy){return};$script:busy=$true
 $buttons=@($connect,$reconnect,$disconnect,$pair,$forget,$run,$launch,$custom)
 foreach($b in $buttons){$b.Enabled=$false};$address.Enabled=$false;$group.Enabled=$false
 try {& $operation}catch {Log ('ERROR: '+$_.Exception.Message);if($script:connection -and $script:connection.Socket.State -ne 'Open'){Close-TV}}
 finally{$script:busy=$false;foreach($b in $buttons){$b.Enabled=$true};$address.Enabled=$true;$group.Enabled=$true}
}
$connect.Add_Click({Perform {Register-TV $false}})
$reconnect.Add_Click({Perform {Register-TV $false}})
$pair.Add_Click({Perform {Register-TV $true}})
$disconnect.Add_Click({Close-TV;Log 'Disconnected.'})
$forget.Add_Click({Perform {
 $target=$address.Text.Trim()
 if($script:profiles.ContainsKey($target)){$script:profiles[$target].Key='';Save-Profiles}
 Close-TV;Log 'Saved local key removed. This does not revoke other clients on the TV.'
}})
$clear.Add_Click({$log.Clear()})
$run.Add_Click({Perform {
 switch($actions.SelectedItem){
 'TV information' {$result=Request-TV 'ssap://system/getSystemInfo'}
 'Available services' {$result=Request-TV 'ssap://api/getServiceList'}
 'Current app' {$result=Request-TV 'ssap://com.webos.applicationManager/getForegroundAppInfo'}
 'Home-screen tiles' {$result=Request-TV 'ssap://com.webos.applicationManager/listLaunchPoints'}
 'Software version' {$result=Request-TV 'ssap://com.webos.service.update/getCurrentSWInformation'}
 'Volume' {$result=Request-TV 'ssap://audio/getVolume'}
 'Viewing recognition (Live Plus)' {$result=Request-TV 'ssap://settings/getSystemSettings' @{category='option';keys=@('livePlus')}}
 'Home-screen settings' {$result=Request-TV 'ssap://settings/getSystemSettings' @{category='general';keys=@('homePromotion','homeAutoLaunch')}}
 'Installed apps' {
  $result=Request-TV 'ssap://com.webos.applicationManager/listApps'
  $script:appList=@($result.apps|Sort-Object title)
  $apps.Items.Clear();foreach($app in $script:appList){[void]$apps.Items.Add($app.title)};if($apps.Items.Count){$apps.SelectedIndex=0}
  Log (($script:appList|Select-Object title,id,removable,systemApp|Format-Table -AutoSize|Out-String).TrimEnd());return
 }
 }
 Log ($result|ConvertTo-Json -Depth 15)
}})
$launch.Add_Click({Perform {
 if($apps.SelectedIndex -lt 0){throw 'Run Installed apps first, then select an app.'}
 $result=Request-TV 'ssap://system.launcher/launch' @{id=$script:appList[$apps.SelectedIndex].id}
 Log ($result|ConvertTo-Json -Depth 10)
}})
$custom.Add_Click({Perform {
 $uri=$uriBox.Text.Trim();if(!$uri.StartsWith('ssap://')){throw 'Custom address must begin ssap://.'}
 $parameters=$payloadBox.Text|ConvertFrom-Json
 if($null -eq $parameters -or $parameters -isnot [pscustomobject]){throw 'Parameters must be a JSON object, such as {}.'}
 if([Windows.Forms.MessageBox]::Show($form,"Send this custom request? It may change TV settings or interrupt playback.`n`n$uri`n$($payloadBox.Text)",'Send custom request','YesNo','Question') -ne 'Yes'){return}
 Log ((Request-TV $uri $parameters)|ConvertTo-Json -Depth 15)
}})
$form.Add_FormClosing({if($script:busy){$_.Cancel=$true;return};Close-TV})
Log 'Ready. First use: Request pairing, trust the TV certificate, and accept the TV prompt.'
Log 'Connect and Reconnect reuse your encrypted key. Permissions are chosen only during new pairing.'
[void]$form.ShowDialog()

