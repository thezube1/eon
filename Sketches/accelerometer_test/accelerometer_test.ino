/*
   ESP32 -- GY-521 (MPU-6050) quick test
   Uses the GY521 library by Rob Tillaart
   Serial: 115 200 baud
*/

#include <Wire.h>
#include "GY521.h"

constexpr uint8_t SDA_PIN = 21;          // default pins on most ESP32 dev-boards
constexpr uint8_t SCL_PIN = 22;
constexpr uint8_t MPU_ADDR = 0x68;       // 0x68 (AD0 low) or 0x69 (AD0 high)

GY521 imu(MPU_ADDR);                     // create the sensor object
uint32_t sample = 0;

void setup() {
  Serial.begin(115200);
  delay(400);                            // let USB/Serial come up

  Wire.begin(SDA_PIN, SCL_PIN, 400000);  // 400 kHz I²C for snappy reads

  // Wake-up loop: keep trying until the ESP32 “sees” the chip
  while (!imu.wakeup()) {
    Serial.println("GY-521 not found – check wiring/address!");
    delay(1000);
  }

  imu.setAccelSensitivity(0);            // 0→±2 g, 1→±4 g, 2→±8 g, 3→±16 g
  imu.setGyroSensitivity(0);             // 0→±250 °/s, 1→±500 °/s, 2→±1000 °/s, 3→±2000 °/s
  imu.setThrottle();                     // lets the lib pace itself (≈1 kHz max)

  Serial.println("GY-521 ready!\nax\tay\taz\tgx\tgy\tgz\tT");
}

void loop() {
  if (imu.read() == GY521_OK) {          // grab a fresh sample
    Serial.printf("%lu\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.2f\n",
                  sample++,
                  imu.getAccelX(), imu.getAccelY(), imu.getAccelZ(),
                  imu.getGyroX(),  imu.getGyroY(),  imu.getGyroZ(),
                  imu.getTemperature());
  } else {
    Serial.println("Read error");
  }
  delay(200);                            // 5 Hz print rate – adjust as needed
}
