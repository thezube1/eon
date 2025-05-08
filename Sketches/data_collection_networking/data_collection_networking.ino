#include <WiFi.h>
#include <HTTPClient.h>
#include "Vitals.h"
#include "PostData.h"

void setup() {
  // put your setup code here, to run once:
  Serial.begin(115200);
  delay(2000);               // <-- gives you time to open the monitor
  Serial.println("Booting…");
  // initialize wifi connectivity
  connectToWifi();
  Serial.println("WiFi Connection Finalized");
  // initialize time
  initTime();
  Serial.println("Time Synchronized");
  // initialize ppg sensor
  initializePpgSensor();
  Serial.println("PPG Sensor Ready");
}

void loop() {
  static Vitals vitals;  // Keep the Vitals object static to avoid constant reallocation
  static bool lastBufferFull = false;  // Track buffer state changes
  
  // Read new values into the existing vitals object
  vitals = readVitals();

  // Print raw IR value and finger detection
  Serial.print("Raw IR: ");
  Serial.print(vitals.irValue);
  if (vitals.isValid) {
    Serial.println(" (Finger detected)");
  } else {
    Serial.println(" (No finger)");
  }

  // When buffer is newly full, print the window of normalized values
  if (vitals.bufferFull && !lastBufferFull && vitals.irBuffer != nullptr) {
    Serial.println("\nNew window of normalized IR values:");
    // Print first 5 values
    for (int i = 0; i < 5 && i < WINDOW_SIZE; i++) {
      Serial.print(i);
      Serial.print(": ");
      Serial.println(vitals.irBuffer[i], 6);
    }
    Serial.println("...");
    // Print last 5 values
    for (int i = max(0, WINDOW_SIZE - 5); i < WINDOW_SIZE; i++) {
      Serial.print(i);
      Serial.print(": ");
      Serial.println(vitals.irBuffer[i], 6);
    }
    
    // Print some statistics
    float minVal = 1.0, maxVal = 0.0, sum = 0.0;
    for (int i = 0; i < WINDOW_SIZE; i++) {
      float val = vitals.irBuffer[i];
      if (val < minVal) minVal = val;
      if (val > maxVal) maxVal = val;
      sum += val;
    }
    Serial.print("Min: "); Serial.println(minVal, 6);
    Serial.print("Max: "); Serial.println(maxVal, 6);
    Serial.print("Avg: "); Serial.println(sum/WINDOW_SIZE, 6);
    Serial.println();
    
    // Send the PPG IR data to the server when a new buffer is full
    postPpgIrData(vitals);
  }
  
  // Update buffer state
  lastBufferFull = vitals.bufferFull;

  // Original heart rate posting code
  if (vitals.avgBpm > 0) {
    static unsigned long lastPost = 0;
    if (millis() - lastPost > 15000) {
      postVitals(vitals);
      lastPost = millis();
    }
  }

  // Add a small delay to control the loop rate
  delay(5);
}
