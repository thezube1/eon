#include <time.h>
#include <sys/time.h>

const char* ntpServer = "pool.ntp.org";
const long gmtOffset_sec = -28800;  // PST timezone offset in seconds (-8 hours)
const int daylightOffset_sec = 3600; // Daylight savings time offset (1 hour)

void initTime() {
  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
  
  // Wait for time to be synchronized
  struct tm timeinfo;
  int retry = 0;
  const int maxRetries = 10;
  
  while(!getLocalTime(&timeinfo) && retry < maxRetries) {
    Serial.println("Failed to obtain time, retrying...");
    delay(500);
    retry++;
  }
  
  if (retry >= maxRetries) {
    Serial.println("Failed to obtain time after maximum retries");
  } else {
    Serial.println("Time synchronized successfully");
  }
}

void getISOTimestamp(char* buffer, size_t bufferSize) {
  struct tm timeinfo;
  if(!getLocalTime(&timeinfo)) {
    Serial.println("Failed to obtain time");
    strncpy(buffer, "1970-01-01T00:00:00-08:00", bufferSize - 1); // Default timestamp with PST offset
    return;
  }
  
  // Format: YYYY-MM-DDThh:mm:ss-08:00 (for PST)
  snprintf(buffer, bufferSize, 
           "%04d-%02d-%02dT%02d:%02d:%02d-08:00",
           timeinfo.tm_year + 1900,
           timeinfo.tm_mon + 1,
           timeinfo.tm_mday,
           timeinfo.tm_hour,
           timeinfo.tm_min,
           timeinfo.tm_sec);
}