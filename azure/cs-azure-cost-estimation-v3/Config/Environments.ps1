# Environment categorization configuration for CrowdStrike Azure Cost Estimation Tool v3

# Return a configuration hashtable defining environment categories
# Each category has name patterns and tag values that identify the environment
@{
    'EnvironmentCategories' = @{
        "Production" = @{
            "NamePatterns" = @("prod", "production", "-p-")
            "TagValues" = @("Production", "PROD", "Prod")
        }
        "PreProduction" = @{
            "NamePatterns" = @("preprod", "pre-prod", "staging", "uat", "-s-")
            "TagValues" = @("PreProduction", "Pre-Production", "Staging", "PREPROD", "UAT")
        }
        "QA" = @{
            "NamePatterns" = @("qa", "test", "testing", "-t-", "-q-")
            "TagValues" = @("QA", "Test", "Testing")
        }
        "Development" = @{
            "NamePatterns" = @("dev", "development", "-d-")
            "TagValues" = @("Development", "DEV", "Dev")
        }
        "Sandbox" = @{
            "NamePatterns" = @("sandbox", "demo", "poc", "lab", "playground")
            "TagValues" = @("Sandbox", "Demo", "POC", "Lab", "Playground")
        }
    }
    
    # Override the default environment names from any in General.ps1
    'EnvironmentTagName' = "Environment"
    'DefaultEnvironment' = "Unknown"
    
    # Production-like environments (for resource planning purposes)
    'ProductionLikeEnvironments' = @("Production", "PreProduction")
    
    # Development-like environments (for resource planning purposes)
    'DevelopmentLikeEnvironments' = @("Development", "QA", "Sandbox")
}
