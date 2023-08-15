require 'rack'
require 'rmodbus'
require 'logger'

LOGGER = Logger.new(STDERR)
$error_count = 0

METRIC = lambda do |name, value, station:, type: :gauge|
end

class Array
  def to_32u
    raise "Array requires an even number of elements to pack to 32bits: was #{self.size}" unless self.size.even?
    self.each_slice(2).map { |(msb, lsb)| [msb, lsb].pack('n*').unpack('N')[0] }.tap do
      return [0] if _1.first >= 2<<30
    end
  end

  def to_64u
    self.each_slice(4).map { |(msb, lsb, a, b)| [a, b].pack('n*').unpack('N')[0] }.tap do
      return [0] if _1.first >= 2<<30
    end
  end
end

METRICS = lambda do |data, type|
      metrics = []
      data.each do |name, value|
        if value.is_a?(Array)
          value.each do |val|
            v = val.delete(:value)
            next if v.zero?

            labels = val.map { |k,v| "#{k}=#{v.to_s.inspect}"}.join(",")

            metrics << <<~METRIC
              # TYPE #{name} #{type}
              sma_#{name}{#{labels}} #{v}
            METRIC
          end
          next
        end
        next if value.zero?
        
        metrics << <<~METRIC
          # TYPE #{name} #{type}
          sma_#{name} #{value}
        METRIC
      end
      metrics
end

MODBUS = lambda do
  gauge = {}
  counter = {}
  ModBus::TCPClient.new(ENV.fetch("SMA_ADDRESS"), 502) do |cl|
    cl.with_slave(3) do |slave|
      gauge[:ac_power_kw_total] = slave.read_holding_registers(30775, 2).to_32u.first.to_f / 1000
      gauge[:ac_power_kw] = [
        {phase: 1, value: slave.read_holding_registers(30777, 2).to_32u.first.to_f / 1000},
        {phase: 2, value: slave.read_holding_registers(30779, 2).to_32u.first.to_f / 1000},
        {phase: 3, value: slave.read_holding_registers(30781, 2).to_32u.first.to_f / 1000},
      ]
      counter[:yield_total] = slave.read_holding_registers(30529, 2).to_32u.first.to_f / 1000
      counter[:yield_today_total] = slave.read_holding_registers(30517, 4).to_64u.first.to_f / 1000
    end
  end
  [counter, gauge]
end

app = Rack::Builder.new do
  map '/metrics' do
    block = lambda do |env|
      status = 200
      counter, gauge = MODBUS.call
      metrics = METRICS.call(counter, :counter)
      metrics += METRICS.call(gauge, :gauge)
      [
        status,
        { 'content-type' => 'text/plain' },
        StringIO.new(metrics.join)
      ]
    end
    run block
  end
end.to_app

run app
