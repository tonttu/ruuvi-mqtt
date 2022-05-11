# RuuviTag MQTT proxy

This small ad hocly written script reads BLE Advertisements sent by
[RuuviTag](https://ruuvi.com/ruuvitag/) sensors and forwards them to a
MQTT broker. The script uses a message format that works directly with
Home Assistant MQTT Discovery.

The only thing you need to configure is the MQTT URL and credentials.
You don't need to pair the devices, the script will discover all sensors
automatically.

Run ruuvi-mqtt on a Linux box that has a bluetooth adapter, like a
Raspberry Pi 4.

```mermaid
graph LR
    A(Ruuvi Tag 1) -.->|BLE| R(ruuvi-mqtt)
    B(Ruuvi Tag 2) -.->|BLE| R(ruuvi-mqtt)
    C(Ruuvi Tag N) -.->|BLE| R(ruuvi-mqtt)
    R -->|TCP| S[MQTT broker]
    S --- H(Home Assistant)
    style R fill:#e4e,color:white
```

# Installation

Easiest way to use this is with Docker. First install Docker if you don't
already have it:

```sh
apt install docker.io
sudo adduser pi docker
newgrp docker
```

Add a new container running this script, modify the `MQTT_URL` with your
MQTT broker address and credentials.

```sh
docker run -e MQTT_URL=mqtt://username:password@hostname:1883 -d \
  --restart=always -v /var/run/dbus:/var/run/dbus kuplatupsu/ruuvi-mqtt
```

Optionally you can define an offset to all reported pressure values, in hPa.
Use something like *elevation_in_meters/8* if you wish to compensate for
elevation. For example:

```
-e PRESSURE_OFFSET=10.0
```

Your sensors should now be automatically detected by the Home Assistant.
