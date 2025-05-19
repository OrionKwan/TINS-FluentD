#!/usr/bin/env ruby
# Simple UDP sender script to replicate Fluentd UDP output behavior

require 'socket'
require 'time'

# Configuration
UDP_HOST = ENV['UDP_FORWARD_HOST'] || '165.202.6.129'
UDP_PORT = (ENV['UDP_FORWARD_PORT'] || '1237').to_i
TEST_ID = "RUBY-UDP-#{Time.now.to_i}"

# Create socket
socket = UDPSocket.new

# Simple log function
def log(msg)
  puts "[#{Time.now}] #{msg}"
end

# Send a message with proper error handling
def send_udp(socket, host, port, message)
  begin
    log "Sending to #{host}:#{port}"
    log "Message: #{message}"
    socket.send(message, 0, host, port)
    log "Message sent successfully!"
    true
  rescue => e
    log "Error sending message: #{e.message}"
    false
  end
end

# Test 1: Basic message
log "Test 1: Basic message"
message1 = "<test><basic>true</basic><id>#{TEST_ID}-BASIC</id></test>"
send_udp(socket, UDP_HOST, UDP_PORT, message1)
puts

# Test 2: SNMP trap format
log "Test 2: SNMP trap format"
message2 = "<snmp_trap><timestamp>#{Time.now}</timestamp><version>SNMPv3</version><data>SNMPTRAP: DISMAN-EVENT-MIB::sysUpTimeInstance \"#{TEST_ID}-TRAP\"</data></snmp_trap>"
send_udp(socket, UDP_HOST, UDP_PORT, message2)
puts

# Test 3: Read from log file and send (simulating Fluentd tail + UDP output)
log "Test 3: Read from log file and send"
log_file = '/var/log/snmptrapd.log'

if File.exist?(log_file)
  log "Reading from #{log_file}"
  last_5_lines = `tail -5 #{log_file}`.split("\n")
  
  last_5_lines.each do |line|
    next if line.empty?
    
    # Format like Fluentd would
    formatted = "<snmp_trap><timestamp>#{Time.now}</timestamp><version>SNMPv3</version><data>#{line}</data></snmp_trap>"
    send_udp(socket, UDP_HOST, UDP_PORT, formatted)
    sleep 0.5  # Small delay between messages
  end
else
  log "Log file #{log_file} not found"
end
puts

# Test 4: Simulate trap and send
log "Test 4: Simulate new trap and send"
timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
simulated_trap = "SNMPTRAP: #{timestamp} DISMAN-EVENT-MIB::sysUpTimeInstance \"#{TEST_ID}-SIMULATED\""
formatted = "<snmp_trap><timestamp>#{timestamp}</timestamp><version>SNMPv3</version><data>#{simulated_trap}</data></snmp_trap>"
send_udp(socket, UDP_HOST, UDP_PORT, formatted)

# Close socket
socket.close
log "Tests completed" 