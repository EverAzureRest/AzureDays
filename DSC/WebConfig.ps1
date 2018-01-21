Configuration WebConfig
{

    # Import the module that defines custom resources

    Import-DscResource -Module xWebAdministration
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName cAzureStorage
    
    $tempdir = 'C:\temp'
    $storagekey = Get-AutomationVariable -Name 'sakey'
    $storageaccountname = Get-AutomationVariable -Name 'saname'
    $destpath = 'C:\inetpub\wwwroot\WebApp'

      Node Web
      {

        #Install the IIS Role
        WindowsFeature IIS
        {
            Ensure = 'Present'
            Name = 'Web-Server'
        }

        #Install ASP.NET 4.5
        WindowsFeature AspNet45
        {
            Ensure = 'Present'
            Name = 'Web-Asp-Net45'
        }

        #Install Mgmt Console
        WindowsFeature WebServerManagementConsole
        {
            Ensure = 'Present'
            Name = 'Web-Mgmt-Console'

        }

        # Stop an existing website (set up in Sample_xWebsite_Default)
        xWebsite DefaultSite 
        {
            Ensure          = 'Present'
            Name            = 'Default Web Site'
            State           = 'Stopped'
            PhysicalPath    = 'C:\inetpub\wwwroot'
            DependsOn       = '[WindowsFeature]IIS'
        }

            File Tempdir
        {
            DestinationPath = $tempdir
            Ensure = 'Present'
            Type = 'Directory'
        }

    # Copy the website content
    cAzureStorage WebDeployFile
        {
            Path = $tempdir
            StorageAccountContainer = 'website-bits'
            StorageAccountKey = $storagekey
            StorageAccountName = $storageaccountname
            DependsOn = '[File]Tempdir'
        }


        Archive ExtractWebsite
        {
            Ensure          = 'Present'
            Destination     = $destpath
            Path            = "$tempdir\azdays-website.zip"
            DependsOn       = '[cAzureStorage]WebDeployFile'

        }
                        
        # Create a new website
        xWebsite AzdaysWebsite 
        {
            Ensure          = 'Present'
            Name            = 'AzdaysWebsite'
            State           = 'Started'
            PhysicalPath    = "$destpath\website"
            DependsOn       = '[xWebsite]Defaultsite', '[Archive]ExtractWebsite'
        }  

      }

    } 