# Reporting Configuration Settings

# Report generation options
$GenerateHtmlReport = $true         # Generate HTML report with visualizations
$IncludeCharts = $true              # Include charts in the HTML report

# For extrapolating Entra ID log volumes based on user count
$SignInsPerUserPerDay = @{
    Small = 2.2  # <1000 users - higher per-user rate due to fewer service accounts
    Medium = 1.8 # 1000-10000 users - average sign-ins per user per day
    Large = 1.5  # >10000 users - lower per-user rate due to more service accounts
}

$AuditsPerUserPerDay = @{
    Small = 0.9  # <1000 users
    Medium = 0.7 # 1000-10000 users
    Large = 0.5  # >10000 users
}

# Chart color palette (hex color codes)
$ChartPalette = @(
    "#3366CC", "#DC3912", "#FF9900", "#109618", "#990099", 
    "#3B3EAC", "#0099C6", "#DD4477", "#66AA00", "#B82E2E"
)

# Default report title
$ReportTitle = "CrowdStrike Azure Cost Estimation Report"
