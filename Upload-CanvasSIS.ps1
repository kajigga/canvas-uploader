# Pacific Union College, Angwin, California
# Canvas batch upload process powershell script
# Created: 5/31/2011
# Last Updated: 1/13/2012
# Programmer: Ryan Hiebert
# Contact: rhiebert@puc.edu
#
# Known issues: The script is using a now undocumented feature of Canvas and needs to be updated to use
# the new means of authenticating.  6/15/12 rhiebert
#
# .DESCRIPTION
# Uploads files to Canvas.  The script should be run by calling its path (absolute or relative), and not
# by putting it in the path.  This is because it expects that its libraries are in the same directory
# that the script is, and will error if it cannot find them.
#
# .PARAMETER CanvasUser
# The username with which to connect to the Canvas API.
#
# .PARAMETER CanvasPass
# The password of the user specified in CanvasUser.
#
# .PARAMETER WorkingPath
# Alias InputFilePath.  Changes the current directory for the process.  This affects the locations of the
# InputFiles, default BackupFileDirectory, default ErrorDirectory, and default LogFile.
#
# .PARAMETER InputFiles
# A list of filenames to upload to canvas.  CSVs are added to a Zip File that is put in the
# BackupFileDirectory.  Zip Files are assumed to be backups, and are neither backed up, nor put into the zip,
# only uploaded.  Default is @("accounts.csv","terms.csv","courses.csv","sections.csv",
# "xlists.csv","users.csv","enrollments.csv")
#
# .PARAMETER BackupFileDirectory
# Where the backup file is saved. If $null, defaults to $WorkingPath + "\backups".  CSV Files get zipped,
# and the zip file is put in this directory.  Zip files do not get rezipped or backed up, as they are assumed
# to be a re-upload.
#
# .PARAMETER BackupFileName
# The name of the backup file.  Defaults to ((Get-Date).Ticks + '.zip').  Only one backup file is created.
# Adjust the backup Directory with the BackupFileDirectory Parameter.
#
# .PARAMETER DeleteInputFiles
# If present, the Input Files that are CSVs will be deleted.  Zip Files will not be deleted, because they are
# assumed to be backups.
#
# .PARAMETER PowershellZipPath
# The path to the PowershellZip dll.  If this is not set (or set to $null), will use
# ((Split-Path $MyInvocation.MyCommand) + "\Modules\PowershellZip.dll")
#
# .PARAMETER PowershellJSONPath
# The path to the ConvertFrom-JSON.ps1 powershell script.  If this is not set (or set to $null), will
# use ((Split-Path $MyInvocation.MyCommand) + "\ConvertFrom-JSON.ps1")
#
# .PARAMETER CanvasURI
# The https (required ssl) path to your canvas instance.
# 
# .PARAMETER CanvasAccountID
# The ID of your canvas account.  
#
# .PARAMETER CanvasAPIKey
# Your canvas API key.  This is required to do any uploading to the API.
#
# .PARAMETER ErrorDirectory
# The directory set aside for autorecovery on subsequent runs. This is useful if you run this script as a
# scheduled task, and need to make sure that previous uploads are successful before you do another upload.
#
# .PARAMETER BatchMode
# **DEPRECATED** - This flag now does nothing. It exists in order to not break scripts using it.
#
# .PARAMETER BatchModeTermID
# Enables batch mode, and uploads to this TermID. By Default, this is an sis_term_id, but you can choose to 
# use a Canvas Native Term ID by setting the TermIDIsNative flag. Only one term can be specified at a time.
#
# .PARAMETER TermIDIsNative
# If BatchMode is enabled, enabling this switch tells me not to use the BatchModeTermID as an SIS ID, but 
# rather as a Canvas native / internal term ID. It is very unlikely you will need this, as the internal term
# ID is not likely to be known when running this program.

# Version 0.5 - BatchModeNativeTermID
# * Added the TermIDIsNative switch to allow batch mode uploads to Canvas Native term IDs.
# * Batch mode flag is deprecated in favor of checking whether the BatchModeTermID is present.
# * Removed the Deprecated InputFilePath alias. Use WorkingPath.
# * Made CanvasURI, CanvasAccountID, and CanvasAPIKey Mandatory to make sharable.
#
# Version 0.4 - BatchMode
# * Added the BatchMode switch and the BatchModeTermID parameter.
#
# Version 0.3 - ErrorRecovery Addition
# * Now checks for errored files in the error directory, and uploads them first.  If error, the remaining
#   new zips are moved to the error folder. If an error upload is successful, its file will be deleted from 
#   the error folder.
# * Removed the LogFile Parameter, since we are planning to use the Windows Event Log.
# * Changed the Default Paths to be relative to this script's location.
#
# Version 0.2 - Refactor
# * Renamed the InputFilePath Parameter to WorkingPath, to better reflect how it is used.  Made Alias for
#   backward compatibility.
# * Renamed the ErrorFolder Parameter to ErrorDirectory for consistency.
# * Changed Default Backup and Error Directories to be in the WorkingPath.
# * Refactored the Upload Process into a Function
# * Don't throw the error when there is an error uploading, rather print the error and mark errors.
#
# Version 0.1 - Initial Version
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)][string] $CanvasUser,
    [Parameter(Mandatory=$true)][string] $CanvasPass,
	[Parameter(Mandatory=$true)][string] $CanvasURI,
    [Parameter(Mandatory=$true)][string] $CanvasAccountID,
    [Parameter(Mandatory=$true)][string] $CanvasAPIKey,
    [string[]] $InputFiles=@("accounts.csv",
                             "terms.csv",
							 "courses.csv",
							 "sections.csv",
							 "xlists.csv",
							 "users.csv",
							 "enrollments.csv",
							 "teachers.csv"),
    [string] $WorkingPath,
    [switch] $DeleteInputFiles,
    [string] $ErrorDirectory='errors',
    [string] $BackupFileDirectory='backups',
    [string] $BackupFileName=([string](Get-Date).Ticks + '.zip'),
    [string] $PowershellZipPath=((Split-Path $MyInvocation.MyCommand.Definition) + "\Modules\PowershellZip.dll"),
    [string] $PowershellJSONPath=((Split-Path $MyInvocation.MyCommand.Definition) + "\ConvertFrom-JSON.ps1"),
	[string] $ErrorLogName,
	[switch] $BatchMode,
	[string] $BatchModeTermID,
	[switch] $TermIDIsNative
)

# Verify and Separate Input files
$CSVFiles = @()
$ZipFiles = @()
$PosLogMessage = ''
$NegLogMessage = ''

if ($WorkingPath) { Set-Location $WorkingPath }

Foreach ($File in $InputFiles) {
    if ((Test-Path $File) -and ($File.EndsWith(".csv") -or $File.EndsWith(".zip"))) {
        $PosLogMessage += "$File "
        if ($File.EndsWith(".csv")) { 
            $CSVFiles += Get-Item $File
        } else {
            $ZipFiles += Get-Item $File
        }
    } else {
        $NegLogMessage += "$File "
    }
}

# Write Verbose Output based on File Verification
if (($CSVFiles.Length + $ZipFiles.Length) -eq 0) {
    Write-Verbose "None of the Input Files Were found. Quitting."
    Break
} else {
    Write-Verbose ($PosLogMessage + "Found")
    if (($CSVFiles.Length + $ZipFiles.Length) -ne $InputFiles) {
        Write-Verbose ($NegLogMessage + "Not Found")
    }
}

# Import the Powershell Zip Module
try {
    Import-Module $PowershellZipPath
} catch {
    Write-Verbose "The Export-Zip Module was not found in $PowershellZipPath"
    Throw
    Break
}

# Make sure that the Backup Directory exists.  Create if not
if (!(Test-Path $BackupFileDirectory)) {
    mkdir $BackupFileDirectory > $null
    Write-Verbose "The Backup File Directory, $BackupFileDirectory, did not exist, so it was created."
}

# Make sure that I can write to the ErrorDirectory, else I won't be able to tell next time if there was
# a previous error.
# If ErrorDirectory is $null, errors cannot be detected later.
if ($ErrorDirectory) {
    if (!(Test-Path $ErrorDirectory -PathType Container)) {
        try {
            Write-Verbose "Trying to create the ErrorDirectory, because it doesn't exist yet."
            mkdir $ErrorDirectory > $null
        } catch {
            Write-Verbose "Could not create the specified ErrorDirectory.  Exiting to avoid undetectable errors."
            Throw
            Break
        }
    } else {
        try {
            $Guid = [Guid]::NewGuid().Guid
            $exists = Test-Path "$ErrorDirectory\$Guid"
            if ($exists) {
                Write-Verbose "Guid name to test ErrorDirectory already exists in ErrorDirectory."
                Write-Verbose "If this is the only time you see this message, it may be a fluke."
                Break
            }
            # Try to write the Guid file
            "test" > "$ErrorDirectory\$Guid"       
            # Try to read the Guid file
            Get-Content "$ErrorDirectory\$Guid" > $null
            # Try to delete the Guid file
            Remove-Item "$ErrorDirectory\$Guid"
        } catch {
            Write-Verbose "Could not write to the ErrorDirectory.  Exiting to avoid undetectable errors."
            Throw
            Break
        }
    }
}

# Construct Full Backup File Path
$BackupFile = $BackupFileDirectory + '\' + $BackupFileName

# Create the Zip File, Add to the Zip List, Delete Original CSVs if Desired
Write-Verbose "Creating the Zip File $BackupFile."
try {
    $ZipFiles += $CSVFiles | Export-Zip $BackupFile
} catch {
    Throw
    Break
}
if ($DeleteInputFiles) {
    $CSVFiles | Remove-Item
}

# Add Term ID if given
$APIPath = "/api/v1/accounts/$CanvasAccountID/sis_imports.json"
$QueryString = "?api_key=$CanvasAPIKey"
if ($BatchModeTermID) {
	if ($TermIDIsNative) {
		$QueryString += "&batch_mode=1&batch_mode_term_id=$BatchModeTermID"
	} else {
		$QueryString += "&batch_mode=1&batch_mode_term_id=sis_term_id:$BatchModeTermID"
	}
}

# Make sure that the $CanvasURI is secured using SSL
$CanvasURIObj = New-Object System.URI ($CanvasURI + $APIPath + $QueryString)
if (!($CanvasURIObj.Scheme -eq 'https')) {
    Write-Verbose "Upload URL is not secured with SSL or TLS, exiting."
    Break
}
Write-Verbose $CanvasURIObj.AbsoluteUri

# Create Credentials for the HTTP Requests
#$CanvasCredentials = New-Object System.Net.NetworkCredential $CanvasUser, $CanvasPass
# Create a header version of the credentials as a hack.  Detailed at
# http://devproj20.blogspot.com/2008/02/assigning-basic-authorization-http.html
$CanvasHeaderCreds = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($CanvasUser + ":" + $CanvasPass).ToCharArray()))

Function UploadToCanvas($File, $URI, $HTTPCredentials) {
	Write-Verbose "Uploading $File"
	$Request = [System.Net.HttpWebRequest]::Create($URI)
	$Request.Method = 'POST'
	#Request.Credentials = $Credentials
	$Request.Headers.Add('Authorization', 'basic ' + $HTTPCredentials)
	$Request.ContentType = 'application/zip'
	
	$RequestStream = $Request.GetRequestStream()
	$FileStream = New-Object System.IO.FileStream $File.FullName, ([System.IO.FileMode]::Open)
	
	# Copy File into the Request Stream
	$inData = New-Object byte[] 4096
	$bytesRead = $FileStream.Read($inData, 0, $inData.Length)
	while ($bytesRead -gt 0) {
		$RequestStream.Write($inData, 0, $bytesRead)
		$bytesRead = $FileStream.Read($inData, 0, $inData.Length)
	}
	
	$FileStream.Close()
	$RequestStream.Close()
	
	$Response = $Request.GetResponse()
	
    # Process the Response, Write out the Job numbers
    $ResponseReader = New-Object System.IO.StreamReader $Response.GetResponseStream()
    $ResponseData = $ResponseReader.ReadToEnd()
    $ResponseReader.Close()
    Write-Verbose ("Response Data: `n" + $ResponseData)
	if (Test-Path -PathType Leaf $PowershellJSONPath) {
		Write-Output ($ResponseData | & $PowershellJSONPath).id
	} else {
		Write-Output ($ResponseData)
	}
}

# Upload Files that had errored First.
$ErrorFiles = Get-ChildItem $ErrorDirectory
if ($BatchMode) { $ErrorFiles = @() } # Don't do error recovery if currently in batch mode.
if ($ErrorFiles.Length -gt 0 ) {
	# Only use the ones that end in .zip
	$ErrorZips = @()
	$ErrorZipsString = "Previous Errors Detected:"
	foreach ($ErrorFile in $ErrorFiles) {
		if ($ErrorFile.Name.EndsWith('.zip')) {
			$ErrorZips += $ErrorFile
			$ErrorZipsString += " $ErrorFile"
		}
	}
	if ($ErrorZips.Length -gt 0) {
		Write-Verbose $ErrorZipsString
		Write-Verbose "Uploading Error Files."
		foreach ($ErrorZip in $ErrorZips) {
			try {
				UploadToCanvas -File $ErrorZip -URI $CanvasURIObj -HTTPCredentials $CanvasHeaderCreds
			}
			catch {
				Write-Verbose "There was an error uploading the file $ErrorZip"
				# Move to Error Folder all the normal upload zips.
				foreach ($Zip in $ZipFiles) {
					Write-Verbose "Copying $Zip into $ErrorDirectory"
					Copy-Item $Zip $ErrorDirectory
				}
				Throw
				Break
			}
			Remove-Item $ErrorZip.FullName
		}
	}
}

# Upload Zip Files
$errorCaught=$false
ForEach ($Zip in $ZipFiles) {
	if ($Zip) {
		if (!$errorCaught) {
			try {
				UploadToCanvas -File $Zip -URI $CanvasURIObj -HTTPCredentials $CanvasHeaderCreds
			}
			catch {
				$errorCaught = $true
				Write-Verbose "There was an error uploading the file $Zip"
				Write-Output $_ # Write The Error, but don't throw it.  We need record of the error.
				# Don't Break, because we need to move the rest to the error folder as well.
			}
		}
		if ($errorCaught -and (!$BatchMode)) {
			# Not just an else statement because it would change in the first if statement.
			
			# We move every file in the loop after and including the file that errored, in order to ensure
			# upload order.
			Write-Verbose "Copying $Zip into $ErrorDirectory"
			Copy-Item $Zip $ErrorDirectory
		}
	}
}

if ($errorCaught) { Write-Verbose "There were errors uploading some of the files." }
else { Write-Verbose "All Files Uploaded.  Done." }