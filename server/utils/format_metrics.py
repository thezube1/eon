from datetime import datetime, timedelta
from typing import Dict, List, Any
import statistics
from collections import defaultdict

def calculate_time_based_averages(data: List[Dict[str, Any]], value_key: str, timestamp_key: str) -> Dict[str, float]:
    """Helper function to calculate averages for different time periods"""
    now = datetime.utcnow()
    today = now.date()
    this_month = today.replace(day=1)
    week_ago = today - timedelta(days=7)
    
    # Initialize counters
    monthly_values = []
    this_month_values = []
    this_week_values = []
    today_values = []
    
    for record in data:
        # Convert timestamp to datetime
        if timestamp_key in ['date', 'end_time']:  # Handle both date strings and timestamps
            record_time = datetime.fromisoformat(record[timestamp_key].replace('Z', '+00:00'))
            record_date = record_time.date()
        else:
            record_time = datetime.fromisoformat(record[timestamp_key].replace('Z', '+00:00'))
            record_date = record_time.date()
        
        value = float(record[value_key])
        
        # Add to appropriate time period lists
        monthly_values.append(value)
        
        if record_date >= this_month:
            this_month_values.append(value)
            
        if record_date >= week_ago:
            this_week_values.append(value)
            
        if record_date == today:
            today_values.append(value)
    
    # Calculate averages, default to 0 if no data
    return {
        'monthly': statistics.mean(monthly_values) if monthly_values else 0,
        'this_month': statistics.mean(this_month_values) if this_month_values else 0,
        'this_week': statistics.mean(this_week_values) if this_week_values else 0,
        'today': statistics.mean(today_values) if today_values else 0
    }

def calculate_sleep_duration(sleep_record: Dict[str, str]) -> float:
    """Calculate sleep duration in hours from a sleep record"""
    start_time = datetime.fromisoformat(sleep_record['start_time'].replace('Z', '+00:00'))
    end_time = datetime.fromisoformat(sleep_record['end_time'].replace('Z', '+00:00'))
    duration = end_time - start_time
    return duration.total_seconds() / 3600  # Convert to hours

def format_metrics(metrics: Dict[str, Any]) -> str:
    """
    Format health metrics into a human-readable string with time-based averages.
    
    Args:
        metrics (dict): Dictionary containing heart rate, steps, and sleep data
        
    Returns:
        str: Formatted string with metrics averages
    """
    if not metrics:
        return "No metrics data available"
    
    # Calculate heart rate averages
    heart_rate_avgs = calculate_time_based_averages(
        metrics['heart_rate'], 
        value_key='bpm',
        timestamp_key='timestamp'
    )
    
    # Calculate step averages
    step_avgs = calculate_time_based_averages(
        metrics['steps'],
        value_key='step_count',
        timestamp_key='date'
    )
    
    # Calculate sleep averages
    sleep_durations = [calculate_sleep_duration(record) for record in metrics['sleep']]
    sleep_data_with_durations = [
        {**record, 'duration': duration} 
        for record, duration in zip(metrics['sleep'], sleep_durations)
    ]
    sleep_avgs = calculate_time_based_averages(
        sleep_data_with_durations,
        value_key='duration',
        timestamp_key='end_time'
    )
    
    # Format the output string
    output = []
    
    # Cardiovascular metrics
    output.append("Cardiovascular metrics:")
    output.append(f"- Monthly average BPM: {heart_rate_avgs['monthly']:.0f}")
    output.append(f"- BPM average so far this month: {heart_rate_avgs['this_month']:.0f}")
    output.append(f"- BPM average this week: {heart_rate_avgs['this_week']:.0f}")
    output.append(f"- BPM average today: {heart_rate_avgs['today']:.0f}")
    output.append("")
    
    # Sleep metrics
    output.append("Sleep metrics:")
    output.append(f"- Monthly average sleep: {sleep_avgs['monthly']:.1f} hours / night")
    output.append(f"- Sleep average so far this month: {sleep_avgs['this_month']:.1f} hours / night")
    output.append(f"- Sleep average this week: {sleep_avgs['this_week']:.1f} hours / night")
    output.append(f"- Sleep last night: {sleep_avgs['today']:.1f} hours")
    output.append("")
    
    # Steps metrics
    output.append("Steps metrics:")
    output.append(f"- Monthly average steps per day: {step_avgs['monthly']:,.0f}")
    output.append(f"- Steps average so far this month: {step_avgs['this_month']:,.0f}")
    output.append(f"- Steps average this week: {step_avgs['this_week']:,.0f}")
    output.append(f"- Steps so-far today: {step_avgs['today']:,.0f}")
    
    return "\n".join(output)