document.addEventListener('DOMContentLoaded', function() {
    // Get chart data from global variables set in the HTML
    const buChartData = window.buChartData || [];
    const componentChartData = window.componentChartData || [];
    const envChartData = window.envChartData || [];
    
    // Business Unit Pie Chart
    if (document.getElementById('businessUnitChart')) {
        const buCtx = document.getElementById('businessUnitChart').getContext('2d');
        new Chart(buCtx, {
            type: 'pie',
            data: {
                labels: buChartData.map(function(item) { return item.name; }),
                datasets: [{
                    data: buChartData.map(function(item) { return item.value; }),
                    backgroundColor: buChartData.map(function(item) { return item.color; }),
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'right',
                    },
                    title: {
                        display: true,
                        text: 'Cost by Business Unit'
                    }
                }
            }
        });
    }
    
    // Component Pie Chart
    if (document.getElementById('componentChart')) {
        const componentCtx = document.getElementById('componentChart').getContext('2d');
        new Chart(componentCtx, {
            type: 'pie',
            data: {
                labels: componentChartData.map(function(item) { return item.name; }),
                datasets: [{
                    data: componentChartData.map(function(item) { return item.value; }),
                    backgroundColor: componentChartData.map(function(item) { return item.color; }),
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'right',
                    },
                    title: {
                        display: true,
                        text: 'Cost by Component'
                    }
                }
            }
        });
    }
    
    // Environment Pie Chart
    if (document.getElementById('environmentChart')) {
        const envCtx = document.getElementById('environmentChart').getContext('2d');
        new Chart(envCtx, {
            type: 'pie',
            data: {
                labels: envChartData.map(function(item) { return item.name; }),
                datasets: [{
                    data: envChartData.map(function(item) { return item.value; }),
                    backgroundColor: envChartData.map(function(item) { return item.color; }),
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'right',
                    },
                    title: {
                        display: true,
                        text: 'Cost by Environment'
                    }
                }
            }
        });
    }
});
