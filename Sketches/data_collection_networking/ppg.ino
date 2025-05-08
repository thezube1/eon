#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"
#include "Vitals.h"

MAX30105 particleSensor;

const byte RATE_SIZE = 4; //Increase this for more averaging. 4 is good.
byte rates[RATE_SIZE]; //Array of heart rates
byte rateSpot = 0;
long lastBeat = 0; //Time at which the last beat occurred

void initializePpgSensor() {
  // Initialize sensor
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 was not found. Please check wiring/power.");
    while (1);
  }

  // Configure sensor with specific settings for our use case
  byte ledBrightness = 0x1F; // 6.4mA
  byte sampleAverage = 1;    // No averaging to maintain raw data
  byte ledMode = 2;         // Red + IR
  int sampleRate = 200;     // We'll downsample to 125Hz in software
  int pulseWidth = 411;     // Maximum for better resolution
  int adcRange = 4096;      // Maximum range

  particleSensor.setup(ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange);
}

Vitals readVitals() {
  static Vitals out;  // Keep static to preserve buffer between calls
  static bool isCollecting = false;  // Flag to track if we're in collection mode
  static long minIR = 0x7FFFFFFF;  // Track min IR value during collection
  static long maxIR = 0;           // Track max IR value during collection
  
  // Get the current IR value
  out.irValue = particleSensor.getIR();
  
  // Check for beat and calculate heart rate
  if (checkForBeat(out.irValue)) {
    unsigned long delta = millis() - lastBeat;
    lastBeat = millis();
    
    float bpmNow = 60.0f / (delta / 1000.0f);
    
    if (bpmNow > 20 && bpmNow < 255) {
      rates[rateSpot++] = (byte)bpmNow;
      rateSpot %= RATE_SIZE;
      
      float sum = 0;
      for (byte i = 0; i < RATE_SIZE; ++i) sum += rates[i];
      out.avgBpm = sum / RATE_SIZE;
      out.bpm = bpmNow;
    }
  }
  
  // Handle IR value buffering with consistent sampling rate
  unsigned long currentTime = millis();
  
  // Check if finger is present
  bool fingerPresent = (out.irValue >= 50000);
  out.isValid = fingerPresent;
  
  // Start collecting if finger is present and we're not already collecting
  if (fingerPresent && !isCollecting) {
    isCollecting = true;
    out.bufferIndex = 0;
    out.bufferFull = false;
    minIR = 0x7FFFFFFF;
    maxIR = 0;
    out.lastSampleTime = currentTime;
    Serial.println("Finger detected - starting data collection");
  }
  
  // If we're collecting and it's time for a new sample
  if (isCollecting && (currentTime - out.lastSampleTime >= (1000 / SAMPLING_RATE))) {
    // Store raw IR value
    out.irBuffer[out.bufferIndex] = (float)out.irValue;
    
    // Update min/max
    if (out.irValue < minIR) minIR = out.irValue;
    if (out.irValue > maxIR) maxIR = out.irValue;
    
    out.bufferIndex++;
    out.lastSampleTime = currentTime;
    
    // Check if buffer is full
    if (out.bufferIndex >= WINDOW_SIZE) {
      // Normalize the entire buffer using min/max scaling
      float range = maxIR - minIR;
      if (range > 0) {  // Prevent division by zero
        for (int i = 0; i < WINDOW_SIZE; i++) {
          out.irBuffer[i] = (out.irBuffer[i] - minIR) / range;
        }
      }
      
      out.bufferFull = true;
      isCollecting = false;  // Stop collecting
      Serial.println("Buffer full - data collection complete");
    }
  }
  
  // If finger is removed during collection, abort
  if (isCollecting && !fingerPresent) {
    isCollecting = false;
    out.bufferFull = false;
    out.bufferIndex = 0;
    Serial.println("Finger removed - data collection aborted");
  }
  
  return out;
}
