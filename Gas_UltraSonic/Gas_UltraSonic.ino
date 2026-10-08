#include <SoftwareSerial.h>

#define MQ2_PIN A0

#define TRIG_PIN 7
#define ECHO_PIN 6

// HC-05
// Arduino D10 = RX  <- HC-05 TX
// Arduino D11 = TX  -> HC-05 RX
SoftwareSerial BTSerial(10, 11);

void setup() {

  Serial.begin(9600);
  BTSerial.begin(9600);

  pinMode(MQ2_PIN, INPUT);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  Serial.println("SafeCook AI Sensor System");
  BTSerial.println("SafeCook AI Sensor System");
}

void loop() {

  // -------------------------
  // MQ-2
  // -------------------------
  int gasValue = analogRead(MQ2_PIN);

  // -------------------------
  // HC-SR04
  // -------------------------
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);

  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);

  digitalWrite(TRIG_PIN, LOW);

  long duration = pulseIn(ECHO_PIN, HIGH, 30000);

  float distance = -1;

  if (duration > 0) {
    distance = duration * 0.0343 / 2.0;
  }

  // -------------------------
  // Build SafeCook message
  // -------------------------

  Serial.print("GAS:");
  Serial.print(gasValue);

  Serial.print(",DIST:");

  BTSerial.print("GAS:");
  BTSerial.print(gasValue);

  BTSerial.print(",DIST:");

  if (distance < 0) {

    Serial.println("NO_ECHO");
    BTSerial.println("NO_ECHO");

  } else {

    Serial.println(distance, 2);
    BTSerial.println(distance, 2);
  }

  delay(1000);
}
