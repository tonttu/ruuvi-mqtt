require 'dbus'
require 'mqtt'
require 'json'

MANUFACTURER_ID = 0x0499
MQTT_URL = ENV['MQTT_URL']
PRESSURE_OFFSET = ENV['PRESSURE_OFFSET'].to_f

$devices = {}

def is_ruuvi? data
  return false unless data['Name'].to_s.start_with?('Ruuvi')
  md = data['ManufacturerData']
  return md && md[MANUFACTURER_ID]
end

def parse_ruuvi_data data
  # We only support RAWv2
  raise "Unknown data version #{data[0]}" unless data[0] == 5

  version, temp, hum, pressure, ax, ay, az, pwr, move, seq, mac = data.map(&:chr).join.unpack('Cs>nns>s>s>nCnH12')
  p = {
    temp: (0.005 * temp).round(2),
    hum: (0.0025 * hum).round(2),
    press: ((pressure + 50000)/1e2 + PRESSURE_OFFSET).round(2),
    ax: (ax / 1e3).round(3),
    ay: (ay / 1e3).round(3),
    az: (az / 1e3).round(3),
    voltage: (1.6+(pwr>>5)/1e3).round(3),
    tx: -40+(pwr&0x1f)*2,
    move: move,
    seq: seq
  }
  p
end

def publish topic, data, retain
  puts "Publish #{topic.inspect} #{data}#{retain ? " retain" : ""}"
  $stdout.flush
  $mqtt.publish topic, data, retain
end

def publish_ha id, n, var, suffix, cla, unit
  publish "homeassistant/sensor/#{id}_#{var}/config", mqtt_cfg(
    id, n, "#{n} #{suffix}", cla, unit, var).to_json, true
end

def auto_discovery id, data
  n = data['name']
  publish_ha id, n, "temp", "temperature", "temperature", "°C"
  publish_ha id, n, "hum", "humidity", "humidity", "%"
  publish_ha id, n, "press", "pressure", "pressure", "hPa"
  publish_ha id, n, "ax", "acceleration x", nil, "g"
  publish_ha id, n, "ay", "acceleration y", nil, "g"
  publish_ha id, n, "az", "acceleration z", nil, "g"
  publish_ha id, n, "voltage", "voltage", "voltage", "V"
  publish_ha id, n, "tx", "tx power", nil, "dBm"
  publish_ha id, n, "move", "move counter", nil, ""
  publish_ha id, n, "seq", "sequence", nil, ""
  publish_ha id, n, "rssi", "rssi", "signal_strength", "dBm"
end

def send_mqtt data, is_new
  payload = parse_ruuvi_data data['data']
  payload['rssi'] = data['rssi']
  id = "ruuvi_#{data['address'].gsub(':', '').downcase}"

  if is_new
    auto_discovery id, data
    publish "ruuvi/#{id}/avty", 'online', true
  end
  publish "ruuvi/#{id}/stat", payload.to_json, true
end

def update_data path, data
  c = ($devices[path] ||= {})
  changed = false
  new = c.empty?
  if data['Name'] && c['name'] != data['Name']
    c['name'] = data['Name']
    changed = true
  end
  if data['Address'] && c['address'] != data['Address']
    c['address'] = data['Address']
    changed = true
  end
  if data['RSSI'] && c['rssi'] != data['RSSI']
    c['rssi'] = data['RSSI']
    changed = true
  end
  if data['ManufacturerData']
    tmp = data['ManufacturerData'][MANUFACTURER_ID]
    if tmp && c['data'] != tmp
      c['data'] = tmp
      changed = true
    end
  end
  send_mqtt c, new if changed
end

def monitor bt, path, data
  return unless is_ruuvi?(data)
  o = bt.object(path)
  o.introspect

  props = o['org.freedesktop.DBus.Properties']
  props.on_signal('PropertiesChanged') do |interface, data|
    update_data path, data if interface == 'org.bluez.Device1'
  end

  update_data path, data
end

def start_discovery bt, path, data
  o = bt.object(path)
  o.introspect

  adapter = o['org.bluez.Adapter1']
  adapter.StartDiscovery
end

def mqtt_cfg id, dev_name, name, cla, unit, var
  cfg = {
    name: name,
    stat_t: "ruuvi/#{id}/stat",
    avty_t: "ruuvi/#{id}/avty",
    pl_avail: "online",
    pl_not_avail: "offline",
    unit_of_meas: unit,
    val_tpl: "{{ value_json.#{var} }}",
    uniq_id: "#{id}_#{var}",
    obj_id: "#{id}_#{var}",
    exp_aft: 300,
    stat_cla: 'measurement',
    dev: {
      ids: [id],
      name: dev_name,
      manufacturer: 'Ruuvi Innovations',
      model: 'RuuviTag'
    }
  }
  cfg['dev_cla'] = cla unless cla.nil?
  cfg
end

begin
  $mqtt = MQTT::Client.connect(MQTT_URL)
rescue SocketError => e
  $stderr.puts e
  sleep 5
  retry
end

$bt = DBus.system_bus.service('org.bluez')
root = $bt['/']
root.introspect
mgr = root['org.freedesktop.DBus.ObjectManager']

def process_int path, interfaces
  dev_data = interfaces['org.bluez.Device1']
  monitor $bt, path, dev_data if dev_data

  a_data = interfaces['org.bluez.Adapter1']
  start_discovery $bt, path, a_data if a_data
end

mgr.on_signal('InterfacesAdded') {|p, i| process_int p, i}

mgr.GetManagedObjects.each {|p, i| process_int p, i}

loop = DBus::Main.new
loop << DBus::system_bus
loop.run
