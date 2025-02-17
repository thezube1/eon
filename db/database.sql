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