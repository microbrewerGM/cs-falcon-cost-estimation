# Capacity and Performance Configuration Settings

# Log size estimation defaults when sampling isn't possible
$DefaultActivityLogSizeKB = 1.0 # Default size estimation for Activity Log entries
$DefaultEntraIdLogSizeKB = 2.0  # Default size estimation for Entra ID log entries

# Throughput estimation defaults
$EventsPerInstancePerSecond = 50 # Events a single Function App instance can process
$MinimumThroughputUnits = 2      # Minimum Event Hub throughput units
$MaximumThroughputUnits = 10     # Maximum Event Hub throughput units

# Storage calculation defaults
$LogRetentionDays = 30           # Number of days logs are retained in storage
$MinimumFunctionInstances = 1    # Minimum Function App instances
$MaximumFunctionInstances = 4    # Maximum Function App instances

# Parallel Execution Configuration
$MaxDegreeOfParallelism = 10     # Maximum number of parallel threads for runspace pool
$ParallelTimeout = 300           # Timeout in seconds for parallel jobs
$ThrottleLimitFactorForSubs = 0.3 # Percentage of subscriptions to process in parallel (prevents throttling)

# Activity log query limits
$MaxActivityLogsToRetrieve = 5000 # Cap on total logs to retrieve per subscription (for performance)
$ActivityLogPageSize = 1000       # Default page size for activity log queries
