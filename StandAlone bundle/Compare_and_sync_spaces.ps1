#Comparison script to see delta in OldSpace and NewSpace for syncing changes
#Written by Travis Wiese - 6/27/2023


Write-Output "Select Option
1) Export Space
2) Import Space
3) Exit"
do{

  $selection = read-host "Selection"
  switch($selection)
  {
    1 {
      $ExportConfigList = Get-childitem -Path "Config/*" -Filter "*export*" -include *.yml,*.yaml
      for($x=1;$x -ne $ExportConfigList.Length;$x++){Write-Output "$x) $($ExportConfigList[$x].Name)"}
      $Opt = Read-host "Select config"
      ruby './export.rb' -c "Config/$($ExportConfigList[$opt].Name)"
    }
    2 {
      $ImportConfigList = Get-childitem -Path "Config/*" -Filter "*import*" -include *.yml,*.yaml
      for($x=1;$x -ne $ImportConfigList.Length;$x++){Write-Output "$x) $($ImportConfigList[$x].Name)"}
      $Opt = Read-host "Select config"
      # $config_file_path = read-host "Provide relative filepath for configuration(ex: config/export_config_Bluestone.yml)"
      ruby './import.rb' -c "Config/$($ImportConfigList[$opt].Name)"
    }
    3 {Exit}
    default {
      Write-Output $("Select Option
      1) Export Space
      2) Import Space
      3) Exit" -replace "(?m)^\s+")
    }
  } 
}while($true)

