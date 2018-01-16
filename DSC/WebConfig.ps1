Configuration WebConfig
{

  Node Web
  {

    # map Z: to Azure File share with persistent creds for install bits & remove DVD drive
    Invoke-Command -scriptBlock {$node.CMdKeySB}
    invoke-Command -scriptBlock {$node.NetUseSB}
    Invoke-Command -scriptBlock {$node.dvdSB}

    #Install the IIS Role
    WindowsFeature IIS
    {
        Ensure = “Present”
        Name = “Web-Server”
    }

    #Install ASP.NET 4.5
    WindowsFeature ASP
    {
        Ensure = “Present”
        Name = “Web-Asp-Net45”
    }

    #Install Mgmt Console
    WindowsFeature WebServerManagementConsole
    {
        Ensure = "Present"
        Name = "Web-Mgmt-Console"

    }
  }
} 