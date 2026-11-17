$ErrorActionPreference='Continue'
$path = "C:\Users\user\AppData\Local\PenHelper\import\upload.xlsx"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
  Write-Host "zip ok entries=$($zip.Entries.Count)"
  $e = $zip.GetEntry('xl/sharedStrings.xml')
  Write-Host "ss entry=$e"
  $sr = New-Object System.IO.StreamReader($e.Open())
  $txt = $sr.ReadToEnd(); $sr.Close()
  Write-Host "ss len=$($txt.Length)"
  $xml = New-Object System.Xml.XmlDocument
  $xml.PreserveWhitespace = $true
  $xml.LoadXml($txt)
  $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $ns.AddNamespace('m','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
  $nodes = $xml.SelectNodes('//m:si', $ns)
  Write-Host "si count=$($nodes.Count)"
  $zip.Dispose()
} catch {
  Write-Host ("ERR: " + $_.Exception.GetType().FullName + " :: " + $_.Exception.Message)
  if ($_.Exception.InnerException) { Write-Host ("INNER: " + $_.Exception.InnerException.Message) }
  $_.ScriptStackTrace
}
# also test COM
try {
  $excel = New-Object -ComObject Excel.Application
  Write-Host "excel com ok"
  $excel.Quit()
} catch { Write-Host ("COM ERR: " + $_.Exception.Message) }
