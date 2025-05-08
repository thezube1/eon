CREATE TABLE IF NOT EXISTS devices (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(255) NOT NULL UNIQUE,
    device_name VARCHAR(255),
    device_model VARCHAR(255),
    os_version VARCHAR(100),
    last_active TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT device_id_check CHECK (LENGTH(device_id) > 0)
);

-- Table for storing heart rate measurements
CREATE TABLE IF NOT EXISTS heart_rate_measurements (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    bpm DECIMAL(5,2) NOT NULL,
    source VARCHAR(100),  -- e.g., "Apple Watch", "iPhone"
    context VARCHAR(50),  -- e.g., "resting", "workout", "sleep"
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_bpm CHECK (bpm > 0 AND bpm < 300)
);

-- Table for storing daily step counts
CREATE TABLE IF NOT EXISTS step_counts (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    date DATE NOT NULL,
    step_count INTEGER NOT NULL,
    source VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_steps CHECK (step_count >= 0),
    UNIQUE(device_id, date)  -- One record per device per day
);

-- Table for storing sleep data
CREATE TABLE IF NOT EXISTS sleep_records (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    sleep_stage VARCHAR(50),  -- e.g., "deep", "rem", "light", "awake"
    source VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_sleep_period CHECK (end_time > start_time)
);

-- Table for tracking last sync status for each metric type
CREATE TABLE IF NOT EXISTS sync_status (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    metric_type VARCHAR(50) NOT NULL,  -- e.g., "heart_rate", "steps", "sleep"
    last_sync_time TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(device_id, metric_type)
);

CREATE TABLE IF NOT EXISTS user_notes (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    note TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS recommendations (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    category VARCHAR(50) NOT NULL, -- e.g. 'Heart_Rate', 'Sleep', 'Steps'
    recommendation TEXT NOT NULL,
    explanation TEXT NOT NULL,
    frequency TEXT NOT NULL,
    risk_cluster TEXT,
    accepted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS risk_analysis_predictions (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    cluster_name VARCHAR(50) NOT NULL,
    risk_level VARCHAR(20) NOT NULL,
    explanation TEXT NOT NULL,
    diseases JSONB NOT NULL, -- Array of objects with icd9_code and description
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Table for storing user characteristics (immutable/rarely changing data)
CREATE TABLE IF NOT EXISTS user_characteristics (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    date_of_birth DATE,
    biological_sex VARCHAR(20),
    blood_type VARCHAR(10),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(device_id)  -- One record per device
);

-- Table for storing body measurements (mutable/time-series data)
CREATE TABLE IF NOT EXISTS body_measurements (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,  -- 'weight', 'height', 'bmi'
    value DECIMAL(8,3) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    source VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_measurement CHECK (value > 0)
);

CREATE TABLE IF NOT EXISTS ppg_ir_windows (
    id SERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    sampling_rate INTEGER NOT NULL,
    window_size INTEGER NOT NULL,
    ir_values JSONB NOT NULL,  -- Array of normalized IR values
    min_raw_value BIGINT,      -- Minimum raw IR value in window
    max_raw_value BIGINT,      -- Maximum raw IR value in window
    avg_raw_value DECIMAL(12,2),  -- Average raw IR value in window
    avg_bpm DECIMAL(5,2),      -- Average heart rate during window
    source VARCHAR(100),       -- e.g., "Eon Health Watch"
    context VARCHAR(50),       -- e.g., "resting", "workout"
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_window CHECK (window_size > 0 AND sampling_rate > 0)
);

CREATE INDEX idx_ppg_ir_windows_timestamp ON ppg_ir_windows (device_id, timestamp);

-- Add new metric types to sync_status
ALTER TABLE sync_status
    DROP CONSTRAINT IF EXISTS sync_status_metric_type_check;

ALTER TABLE sync_status
    ADD CONSTRAINT sync_status_metric_type_check 
    CHECK (metric_type IN ('heart_rate', 'steps', 'sleep', 'characteristics', 'body_measurements'));
