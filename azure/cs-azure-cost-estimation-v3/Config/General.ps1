# General configuration settings for CrowdStrike Azure Cost Estimation Tool v3

# Return a configuration hashtable
@{
    # Business unit and environment tag names
    'BusinessUnitTagName' = "BusinessUnit"
    'DefaultBusinessUnit' = "Unassigned"
    'EnvironmentTagName' = "Environment"
    'DefaultEnvironment' = "Unknown"
    
    # Default region if none specified
    'DefaultRegion' = "eastus"
    
    # Log analysis settings
    'DaysToAnalyze' = 7
    'LogRetentionDays' = 30
    'SampleLogSize' = 100
    
    # Activity log settings
    'MaxActivityLogsToRetrieve' = 1000
    'ActivityLogPageSize' = 100
    'DefaultActivityLogSizeKB' = 2.5
    'DefaultEntraIdLogSizeKB' = 2.0
    
    # Performance settings
    'EventsPerInstancePerSecond' = 5000
    'MinimumThroughputUnits' = 1
    'MaximumThroughputUnits' = 20
    'MinimumFunctionInstances' = 1
    'MaximumFunctionInstances' = 10
    'KeyVaultMonthlyOperations' = 100000
}
