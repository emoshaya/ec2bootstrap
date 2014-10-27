# Inject this as user-data of a Windows 2012 AMI, like this (edit the userPassword to your needs):
#
# <powershell>
# Set-ExecutionPolicy Unrestricted
# icm $executioncontext.InvokeCommand.NewScriptBlock((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/ebrahim-moshaya/ec2bootstrap/master/Bootstrap-EC2-Windows-chef-client.ps1')) -ArgumentList "AWSAccessKey", "AWSSecretKey"
# </powershell>
#

# Pass in the following Parameters
param(

  [Parameter(Mandatory=$true)]
  [string]
  $AWSAccessKey,
  
  [Parameter(Mandatory=$true)]
  [string]
  $AWSSecretKey
)

Start-Transcript -Path 'c:\bootstrap-transcript.txt' -append -Force 
Set-StrictMode -Version Latest
Set-ExecutionPolicy Unrestricted -force

$log = 'c:\Bootstrap.txt'
$client = new-object System.Net.WebClient
$shell_app = new-object -com shell.application


#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-
#	Function:	Download-Bucket-File
#
#	Comments:	This function is intended to download a specific file from S3.
#
#
#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-
function Download-Bucket-File ($Filename, $Bucket, $Destination)
{
  $status = "Downloading " + $Filename + " from S3 [" + $Bucket + "]"
  
  Log_Status $status
  
  
  $FullPath = $Destination + "\" + $Filename
  
  Read-S3Object -BucketName $Bucket -Key $Filename -File $FullPath -AccessKey $AWSAccessKey -SecretKey $AWSSecretKey
  
  Wait-Until-Downloaded $FullPath
  
  $status = "Downloaded " + $Filename + " from S3 [" + $Bucket + "]"
  
  Log_Status $status
  
}


#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-
#
# Download and Install Chef Client
# https://opscode-omnibus-packages.s3.amazonaws.com/windows/2008r2/x86_64/chef-windows-11.16.2-1.windows.msi
#
#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-

function CHEF
{
  # Create a new chef directory
  $chef_dir = "C:\chef"
  if (!(Test-Path -path $chef_dir))
  {
    mkdir $chef_dir
  }
  SetX Path "${Env:Path};C:\opscode\chef\bin" /m
  $Env:Path += ';C:\opscode\chef\bin'
  Log_Status "Created chef directory" 
  #	Download Chef.rb and validation key
  Download-Bucket-File "client.rb"  "chefbootstrap-jenkins" $chef_dir
  Download-Bucket-File "validation.pem"  "chefbootstrap-jenkins" $chef_dir
  [Environment]::SetEnvironmentVariable("CHEFNODE", "JenkinsSlave-${env:Computername}", "Machine")
  "node_name 'JenkinsSlave-${env:ComputerName}'" | out-file -filepath C:\chef\client.rb -append -Encoding UTF8
  cd $chef_dir
  chef-service-manager -a install
  &sc.exe config chef-client start= auto
  chef-client -r "role[jenkins_windows_slave]"
}


#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-
#	Function:	Log_Status
#
#	Comments:	This function is intended to write a status message to SQS queue and / or local log file
#
#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-

function Log_Status ($message)
{
  Add-Content $log -value $message
  Write-Host $message -ForegroundColor Green
}


#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-
#
#	Section	:	Script begins here
#
#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-

Log_Status "Started bootstrapping EC2 Instance"

Log_Status "Configuring Chef-Client" 
CHEF
Log_Status "Finished configuring chef-client" 


#	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-	-

Log_Status "Finished bootstrapping"

