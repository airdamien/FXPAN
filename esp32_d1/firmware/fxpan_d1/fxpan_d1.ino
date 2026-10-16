// FXPAN Mini D1. BLE Nordic UART, same lines as the Pi Zero on 10.55.0.1:2323.
//
//   PING
//   FIRE
//   FIRE <milliseconds>
//
// Focus goes high for 100 ms, then shutter for the requested time, then both
// drop, then the board answers OK. Pins idle low. GPIO 32 (focus, socket
// pin 38) and GPIO 27 (shutter, socket pin 40) are not boot straps.

#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

static const int FOCUS_PIN = 32;
static const int SHUTTER_PIN = 27;
static const int FOCUS_MS = 100;
static const int DEFAULT_SHUTTER_MS = 300;
static const int MAX_SHUTTER_MS = 120000;

static const char *NAME = "FXPAN-D1";
static const char *SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
static const char *RX_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
static const char *TX_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

static BLECharacteristic *txChar = nullptr;
static BLEAdvertising *advertising = nullptr;
static volatile bool clientUp = false;

static portMUX_TYPE lineMux = portMUX_INITIALIZER_UNLOCKED;
static char lineBuf[160];
static size_t lineLen = 0;
static bool lineReady = false;

static void pinsLow() {
  digitalWrite(FOCUS_PIN, LOW);
  digitalWrite(SHUTTER_PIN, LOW);
}

static void pulse(int shutterMs) {
  pinsLow();
  digitalWrite(FOCUS_PIN, HIGH);
  delay(FOCUS_MS);
  digitalWrite(SHUTTER_PIN, HIGH);
  delay(shutterMs);
  pinsLow();
}

// A new phone link can still only carry 20 bytes per notify. The FIRE answer is
// longer than that, so it goes out in pieces. The phone joins them at the newline.
static void reply(const String &line) {
  if (txChar == nullptr || !clientUp) return;
  const size_t limit = 20;
  size_t off = 0;
  while (off < line.length()) {
    size_t n = line.length() - off;
    if (n > limit) n = limit;
    uint8_t buf[20];
    memcpy(buf, line.c_str() + off, n);
    txChar->setValue(buf, n);
    txChar->notify();
    off += n;
    if (off < line.length()) delay(20);
  }
}

static String handle(const String &raw) {
  String line = raw;
  line.trim();
  if (line.length() == 0) return "";
  int sp = line.indexOf(' ');
  String cmd = (sp < 0 ? line : line.substring(0, sp));
  cmd.toUpperCase();
  if (cmd == "PING" && sp < 0) return "OK";
  if (cmd != "FIRE" || (sp >= 0 && line.indexOf(' ', sp + 1) >= 0)) {
    return "ERR use PING or FIRE [milliseconds]";
  }
  int shutterMs = DEFAULT_SHUTTER_MS;
  if (sp >= 0) {
    String arg = line.substring(sp + 1);
    arg.trim();
    for (unsigned i = 0; i < arg.length(); i++) {
      if (!isDigit(arg[i])) return "ERR use PING or FIRE [milliseconds]";
    }
    shutterMs = arg.toInt();
  }
  if (shutterMs < 1 || shutterMs > MAX_SHUTTER_MS) {
    return String("ERR shutter must be 1..") + MAX_SHUTTER_MS + " ms";
  }
  pulse(shutterMs);
  return String("OK focus_ms=") + FOCUS_MS + " shutter_ms=" + shutterMs;
}

class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer *) override { clientUp = true; }
  void onDisconnect(BLEServer *) override {
    clientUp = false;
    if (advertising != nullptr) advertising->start();
  }
};

class RxCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String chunk = c->getValue();
    if (chunk.length() == 0) return;
    portENTER_CRITICAL(&lineMux);
    if (lineReady) {
      portEXIT_CRITICAL(&lineMux);
      return;
    }
    for (unsigned i = 0; i < chunk.length() && !lineReady; i++) {
      char ch = chunk[i];
      if (ch == '\r') continue;
      if (ch == '\n') {
        lineBuf[lineLen] = 0;
        lineReady = true;
        break;
      }
      if (lineLen + 1 < sizeof(lineBuf)) lineBuf[lineLen++] = ch;
    }
    portEXIT_CRITICAL(&lineMux);
  }
};

void setup() {
  pinMode(FOCUS_PIN, OUTPUT);
  pinMode(SHUTTER_PIN, OUTPUT);
  pinsLow();

  BLEDevice::init(NAME);
  BLEDevice::setMTU(185);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCB());
  BLEService *svc = server->createService(SERVICE_UUID);

  txChar = svc->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());

  BLECharacteristic *rx = svc->createCharacteristic(
      RX_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCB());

  svc->start();
  advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

void loop() {
  char local[sizeof(lineBuf)];
  bool ready = false;
  portENTER_CRITICAL(&lineMux);
  if (lineReady) {
    memcpy(local, lineBuf, lineLen + 1);
    lineLen = 0;
    lineReady = false;
    ready = true;
  }
  portEXIT_CRITICAL(&lineMux);
  if (!ready) {
    delay(5);
    return;
  }
  String answer = handle(String(local));
  if (answer.length() == 0) return;
  answer += "\n";
  reply(answer);
}
