from datetime import datetime, timedelta
from typing import Dict, List, Any
import statistics
from collections import defaultdict

def calculate_time_based_averages(data: List[Dict[str, Any]], value_key: str, timestamp_key: str, metric_type: str = None) -> Dict[str, Any]:
    """Helper function to calculate averages for different time periods"""
    now = datetime.utcnow()
    today = now.date()
    yesterday = today - timedelta(days=1)
    day_before_yesterday = today - timedelta(days=2)
    this_month = today.replace(day=1)
    week_ago = today - timedelta(days=7)
    
    # Initialize counters
    monthly_values = []
    this_month_values = []
    this_week_values = []
    today_values = []  # For steps/sleep, this will actually be yesterday's values
    
    if metric_type == 'sleep':
        # Group sleep records by night (using end_time date)
        sleep_by_night = defaultdict(list)
        for record in data:
            end_time = datetime.fromisoformat(record['end_time'].replace('Z', '+00:00'))
            start_time = datetime.fromisoformat(record['start_time'].replace('Z', '+00:00'))
            end_date = end_time.date()
            
            # Store the original record for duration calculation
            sleep_by_night[end_date].append(record)
            
        # Now process the aggregated nightly totals
        for night_date, records in sleep_by_night.items():
            # Calculate total sleep duration for this night
            total_sleep = sum(calculate_sleep_duration(record) for record in records)
            
            if night_date >= today - timedelta(days=30):
                monthly_values.append(total_sleep)
            if night_date >= this_month:
                this_month_values.append(total_sleep)
            if night_date >= week_ago:
                this_week_values.append(total_sleep)
            if night_date == yesterday:
                today_values.append(total_sleep)
    else:
        # Handle non-sleep metrics as before
        for record in data:
            # Convert timestamp to datetime
            if timestamp_key == 'date':
                # Handle date strings (for step counts)
                record_time = datetime.fromisoformat(record[timestamp_key])
                record_date = record_time.date()
            else:
                # Handle timestamps (for heart rate)
                record_time = datetime.fromisoformat(record[timestamp_key].replace('Z', '+00:00'))
                record_date = record_time.date()
            
            value = float(record[value_key])
            
            # Add to appropriate time period lists
            if record_date >= today - timedelta(days=30):
                monthly_values.append(value)
            if record_date >= this_month:
                this_month_values.append(value)
            if record_date >= week_ago:
                this_week_values.append(value)
            if metric_type == 'steps' and record_date == yesterday:
                today_values.append(value)
            elif metric_type != 'steps' and record_date == today:
                today_values.append(value)
    
    # For heart rate, we need multiple readings per day for meaningful averages
    min_readings = {
        'heart_rate': {'monthly': 1000, 'this_month': 500, 'this_week': 100, 'today': 10},
        'steps': {'monthly': 15, 'this_month': 7, 'this_week': 3, 'today': 1},
        'sleep': {'monthly': 15, 'this_month': 7, 'this_week': 3, 'today': 1}
    }.get(metric_type, {'monthly': 1, 'this_month': 1, 'this_week': 1, 'today': 1})
    
    # Calculate averages with data validation
    return {
        'monthly': statistics.mean(monthly_values) if len(monthly_values) >= min_readings['monthly'] else 'not enough data',
        'this_month': statistics.mean(this_month_values) if len(this_month_values) >= min_readings['this_month'] else 'not enough data',
        'this_week': statistics.mean(this_week_values) if len(this_week_values) >= min_readings['this_week'] else 'not enough data',
        'today': sum(today_values) if metric_type == 'sleep' and len(today_values) >= min_readings['today'] 
                else statistics.mean(today_values) if len(today_values) >= min_readings['today']
                else 'no data from today'
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
        timestamp_key='timestamp',
        metric_type='heart_rate'
    )
    
    # Calculate step averages
    step_avgs = calculate_time_based_averages(
        metrics['steps'],
        value_key='step_count',
        timestamp_key='date',
        metric_type='steps'
    )
    
    # Calculate sleep averages - pass the raw sleep records
    sleep_avgs = calculate_time_based_averages(
        metrics['sleep'],
        value_key='duration',  # This won't be used for sleep metrics
        timestamp_key='end_time',
        metric_type='sleep'
    )
    
    # Format the output string
    output = []
    
    # Helper function to format numeric values
    def format_value(value, format_str):
        return format_str.format(value) if isinstance(value, (int, float)) else str(value)
    
    # Cardiovascular metrics
    output.append("Cardiovascular metrics:")
    output.append(f"- Monthly average BPM: {format_value(heart_rate_avgs['monthly'], '{:.0f}')}")
    output.append(f"- BPM average so far this month: {format_value(heart_rate_avgs['this_month'], '{:.0f}')}")
    output.append(f"- BPM average this week: {format_value(heart_rate_avgs['this_week'], '{:.0f}')}")
    output.append(f"- BPM average today: {format_value(heart_rate_avgs['today'], '{:.0f}')}")
    output.append("")
    
    # Sleep metrics
    output.append("Sleep metrics:")
    output.append(f"- Monthly average sleep: {format_value(sleep_avgs['monthly'], '{:.1f} hours / night')}")
    output.append(f"- Sleep average so far this month: {format_value(sleep_avgs['this_month'], '{:.1f} hours / night')}")
    output.append(f"- Sleep average this week: {format_value(sleep_avgs['this_week'], '{:.1f} hours / night')}")
    output.append(f"- Sleep yesterday: {format_value(sleep_avgs['today'], '{:.1f} hours')}")
    output.append("")
    
    # Steps metrics
    output.append("Steps metrics:")
    output.append(f"- Monthly average steps per day: {format_value(step_avgs['monthly'], '{:,.0f}')}")
    output.append(f"- Steps average so far this month: {format_value(step_avgs['this_month'], '{:,.0f}')}")
    output.append(f"- Steps average this week: {format_value(step_avgs['this_week'], '{:,.0f}')}")
    output.append(f"- Steps yesterday: {format_value(step_avgs['today'], '{:,.0f}')}")
    
    return "\n".join(output)