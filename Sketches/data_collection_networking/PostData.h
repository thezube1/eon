#pragma once

struct HeartRateReading {
    char timestamp[25];  // ISO8601 timestamp format: "2024-03-20T10:30:00Z"
    int bpm;
    char source[20];     // Optional source identifier
    char context[20];    // Optional context information
};

// Structure for device information
struct DeviceInfo {
    char device_id[50];      // Required field
    char device_name[50];    // Optional
    char device_model[50];   // Optional
    char os_version[20];     // Optional
};

// Main structure for POST request
struct PostData {
    DeviceInfo device_info;
    HeartRateReading heart_rate;  // Single heart rate reading
};
