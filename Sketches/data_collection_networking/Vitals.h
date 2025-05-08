#pragma once

#define WINDOW_SIZE 1024  // 8.192 seconds * 125 Hz = 1024 samples
#define SAMPLING_RATE 125 // 125 Hz sampling rate

struct Vitals {
  long irValue = 0;
  float bpm = 0;
  float avgBpm = 0;
  bool isValid = false;
  
  // Buffer for IR values - using pointer for dynamic allocation
  float* irBuffer = nullptr;
  int bufferIndex = 0;
  bool bufferFull = false;
  unsigned long lastSampleTime = 0;

  // Constructor
  Vitals() {
    irBuffer = new float[WINDOW_SIZE]();  // Initialize with zeros
  }

  // Destructor
  ~Vitals() {
    if (irBuffer != nullptr) {
      delete[] irBuffer;
      irBuffer = nullptr;
    }
  }

  // Copy constructor
  Vitals(const Vitals& other) {
    irValue = other.irValue;
    bpm = other.bpm;
    avgBpm = other.avgBpm;
    isValid = other.isValid;
    bufferIndex = other.bufferIndex;
    bufferFull = other.bufferFull;
    lastSampleTime = other.lastSampleTime;
    
    irBuffer = new float[WINDOW_SIZE];
    memcpy(irBuffer, other.irBuffer, WINDOW_SIZE * sizeof(float));
  }

  // Assignment operator
  Vitals& operator=(const Vitals& other) {
    if (this != &other) {
      irValue = other.irValue;
      bpm = other.bpm;
      avgBpm = other.avgBpm;
      isValid = other.isValid;
      bufferIndex = other.bufferIndex;
      bufferFull = other.bufferFull;
      lastSampleTime = other.lastSampleTime;
      
      if (irBuffer != nullptr) {
        delete[] irBuffer;
      }
      irBuffer = new float[WINDOW_SIZE];
      memcpy(irBuffer, other.irBuffer, WINDOW_SIZE * sizeof(float));
    }
    return *this;
  }
};