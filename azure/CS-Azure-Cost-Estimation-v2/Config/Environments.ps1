# Environment Classification Configuration Settings

# Environment Categories with name patterns, tag keys, tag values, and visualization colors
$EnvironmentCategories = @{
    Production = @{
        NamePatterns = @("prod", "production", "prd")
        TagKeys = @("Environment", "Env")
        TagValues = @("prod", "production", "prd")
        Color = "#DC3912"  # Red
        Priority = 1       # Higher priority means this category takes precedence when multiple matches
    }
    PreProduction = @{
        NamePatterns = @("preprod", "staging", "stg", "uat")
        TagKeys = @("Environment", "Env")
        TagValues = @("preprod", "staging", "stg", "uat")
        Color = "#FF9900"  # Orange
        Priority = 2
    }
    QA = @{
        NamePatterns = @("qa", "test", "testing")
        TagKeys = @("Environment", "Env")
        TagValues = @("qa", "test", "testing")
        Color = "#109618"  # Green
        Priority = 3
    }
    Development = @{
        NamePatterns = @("dev", "development")
        TagKeys = @("Environment", "Env")
        TagValues = @("dev", "development")
        Color = "#3366CC"  # Blue
        Priority = 4
    }
    Sandbox = @{
        NamePatterns = @("sandbox", "lab", "poc", "demo", "experiment")
        TagKeys = @("Environment", "Env")
        TagValues = @("sandbox", "lab", "poc", "demo", "experiment")
        Color = "#990099"  # Purple
        Priority = 5
    }
    DataModeling = @{
        NamePatterns = @("data", "analytics", "ml", "ai")
        TagKeys = @("Environment", "Env", "Purpose")
        TagValues = @("data", "analytics", "ml", "ai", "datamodeling")
        Color = "#0099C6"  # Cyan
        Priority = 6
    }
    Infrastructure = @{
        NamePatterns = @("infra", "mgmt", "management", "shared", "hub")
        TagKeys = @("Environment", "Env", "Purpose")
        TagValues = @("infra", "infrastructure", "mgmt", "management", "shared", "hub")
        Color = "#DD4477"  # Pink
        Priority = 7
    }
    Personal = @{
        NamePatterns = @("personal", "individual", "user")
        TagKeys = @("Environment", "Env", "Purpose", "Owner")
        TagValues = @("personal", "individual", "research")
        Color = "#66AA00"  # Light green
        Priority = 8
    }
}
