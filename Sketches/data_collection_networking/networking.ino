#include <ArduinoJson.h>
#include <WiFiClientSecure.h>

const char* ssid = "USC Guest Wireless";
const char* password = "";

const char* serverHost = "eon-550878280011.us-central1.run.app";
const int serverPort = 443;
const char* serverPath = "/api/health/sync";
const char* ppgIrPath = "/api/health/ppg-ir";

void connectToWifi() {
  WiFi.begin(ssid, password);
  Serial.println("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("");
  Serial.print("Connected to WiFi network with IP Address: ");
  Serial.println(WiFi.localIP());
}

void postVitals(Vitals vitals) {
  // Only send data if readings are valid
  if (!vitals.isValid) {
    Serial.println("Invalid readings - finger not detected or poor signal");
    return;
  }

  if (WiFi.status() == WL_CONNECTED) {
    WiFiClientSecure client;
    client.setInsecure();  // For testing only - in production use proper certificate validation
    
    HTTPClient http;
    
    // Your server name would be here
    if (http.begin(client, serverHost, serverPort, serverPath)) {
      http.addHeader("Content-Type", "application/json");
      
      // Create JSON document
      StaticJsonDocument<200> doc;
      
      // Add device info
      JsonObject device_info = doc.createNestedObject("device_info");
      device_info["device_id"] = "esp32";
      device_info["device_name"] = "esp32_health_watch";
      device_info["device_model"] = "Eon Health Watch";
      device_info["os_version"] = "1.0";
      
      // Add heart rate data
      JsonArray heart_rate = doc.createNestedArray("heart_rate");
      JsonObject measurement = heart_rate.createNestedObject();
      
      char timestamp[25];
      getISOTimestamp(timestamp, sizeof(timestamp));
      measurement["timestamp"] = timestamp;
      measurement["bpm"] = vitals.bpm;
      measurement["source"] = "Eon Health Watch";
      measurement["context"] = "resting";
      
      String jsonString;
      serializeJson(doc, jsonString);
      
      Serial.println("Sending JSON:");
      Serial.println(jsonString);
      
      int httpResponseCode = http.POST(jsonString);
      
      Serial.print("HTTP Vitals Upload Response Code: ");
      Serial.println(httpResponseCode);
      
      http.end();
    }
  }
}

void postPpgIrData(Vitals vitals) {
  // Only proceed if buffer is full and readings are valid
  if (!vitals.bufferFull || vitals.irBuffer == nullptr) {
    Serial.println("No complete PPG IR data window available to send");
    return;
  }

  if (WiFi.status() == WL_CONNECTED) {
    WiFiClientSecure client;
    client.setInsecure();  // For testing only - in production use proper certificate validation
    
    HTTPClient http;
    
    if (http.begin(client, serverHost, serverPort, ppgIrPath)) {
      http.addHeader("Content-Type", "application/json");
      
      // Create JSON document - we need a larger buffer for the IR values array
      DynamicJsonDocument doc(16384); // Allocate enough space for the 1024 IR values
      
      // Basic device and window info
      doc["device_id"] = "esp32";
      doc["device_name"] = "esp32_health_watch";
      doc["device_model"] = "Eon Health Watch";
      
      // Get current timestamp
      char timestamp[25];
      getISOTimestamp(timestamp, sizeof(timestamp));
      doc["timestamp"] = timestamp;
      
      // Window parameters
      doc["sampling_rate"] = SAMPLING_RATE;
      doc["window_size"] = WINDOW_SIZE;
      
      // Calculate statistics (these should ideally be pre-calculated and stored in vitals)
      long minRawValue = LONG_MAX;
      long maxRawValue = 0;
      float sumRawValue = 0;
      
      // Add IR values as JSON array
      JsonArray irValues = doc.createNestedArray("ir_values");
      for (int i = 0; i < WINDOW_SIZE; i++) {
        // Add normalized value to array
        irValues.add(vitals.irBuffer[i]);
        
        // Update statistics based on denormalized values (approximate)
        // Note: This is an approximation since we've already normalized the values
        long approxRawValue = vitals.irValue; // Use current IR value as approximation
        if (approxRawValue < minRawValue) minRawValue = approxRawValue;
        if (approxRawValue > maxRawValue) maxRawValue = approxRawValue;
        sumRawValue += approxRawValue;
      }
      
      doc["min_raw_value"] = minRawValue;
      doc["max_raw_value"] = maxRawValue;
      doc["avg_raw_value"] = sumRawValue / WINDOW_SIZE;
      doc["avg_bpm"] = vitals.avgBpm;
      doc["source"] = "Arduino MAX30105";
      doc["context"] = "resting";
      
      String jsonString;
      serializeJson(doc, jsonString);
      
      Serial.println("Sending PPG IR data:");
      Serial.print("JSON Size: ");
      Serial.println(jsonString.length());
      
      int httpResponseCode = http.POST(jsonString);
      
      Serial.print("HTTP PPG IR Upload Response Code: ");
      Serial.println(httpResponseCode);
      
      http.end();
    }
  }
}