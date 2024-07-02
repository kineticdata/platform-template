


$Config = Import-LocalizedData -BaseDirectory 'C:\Users\travis.wiese\Source\repos\platform-template\config\' -FileName 'sync.psd1'

$CURRENT_DIR = (&{If([string]::isnullorempty($PSScriptRoot)) {$pwd.path} else {$PSScriptRoot}}) 


$OLDSPACE_SLUG = $config['core'].OLDSPACE_SLUG
$NEWSPACE_SLUG = $config['core'].NEWSPACE_SLUG

$OLDSPACE_PATH = $CURRENT_DIR + '\exports\' + $OLDSPACE_SLUG
$NEWSPACE_PATH = $CURRENT_DIR + '\exports\' + $NEWSPACE_SLUG

$OLDSPACE_Items = Get-ChildItem $OLDSPACE_PATH -Recurse
$NEWSPACE_Items = Get-ChildItem $NEWSPACE_PATH -Recurse

$Missing_Files = compare-object -ReferenceObject $OLDSPACE_Items -DifferenceObject $NEWSPACE_Items -ExcludeDifferent -IncludeEqual


$NewArr = @()
Foreach($obj in $OLDSPACE_Items) {
    $OLDRelPath = $obj.Directoryname.replace("$CURRENT_DIR\exports\$oldspace_slug\",'')
    $New_Items = $NEWSPACE_Items | where-object {$_.Directoryname -like "*$OLDRelPath" -and $_.name -eq $obj.name}
    try{
        $FolderDifference = Compare-object -ReferenceObject $obj -DifferenceObject $New_Items -Property name
    }catch{
        continue
    }
    
    if([string]::isnullorempty($FolderDifference)){
        #Folders match
        continue
    }

    <# This tracks all unequal folder items #>
        $newarr += [pscustomobject] @{
        dir = $OLDRelPath
        OldFiles = $obj
        NewFiles = $New_Items
    }
    


}