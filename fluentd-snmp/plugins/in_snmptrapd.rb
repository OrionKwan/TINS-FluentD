require 'fluent/plugin/input'
require 'open3'
require 'json'
require 'timeout'

module Fluent
  module Plugin
    class SnmptrapdInput < Input
      Fluent::Plugin.register_input('snmptrapd', self)

      desc 'Tag to apply to events from SNMP traps'
      config_param :tag, :string, default: 'snmp.trap'
      
      desc 'Port for snmptrapd to listen on'
      config_param :port, :integer, default: 1162
      
      desc 'Username for SNMPv3'
      config_param :username, :string, default: nil
      
      desc 'Auth protocol for SNMPv3 (SHA, SHA256, SHA512 or MD5)'
      config_param :auth_protocol, :string, default: nil
      
      desc 'Auth password for SNMPv3'
      config_param :auth_password, :string, default: nil
      
      desc 'Privacy protocol for SNMPv3 (AES, AES192, AES256 or DES)'
      config_param :priv_protocol, :string, default: nil
      
      desc 'Privacy password for SNMPv3'
      config_param :priv_password, :string, default: nil
      
      desc 'SNMP community string for v1/v2c'
      config_param :community, :string, default: 'public'
      
      desc 'Path to MIB files'
      config_param :mib_dir, :string, default: '/usr/share/snmp/mibs'
      
      desc 'MIB files to load (comma-separated)'
      config_param :mibs, :string, default: '+IMAP_NORTHBOUND_MIB-V1'
      
      desc 'Maximum number of reconnection attempts'
      config_param :max_retries, :integer, default: 5
      
      desc 'Delay between reconnection attempts in seconds'
      config_param :retry_interval, :integer, default: 5

      def configure(conf)
        super
        
        # Use environment variables if parameters not set
        @username ||= ENV['SNMPV3_USER']
        @auth_protocol ||= ENV['SNMPV3_AUTH_PROTOCOL']
        @auth_password ||= ENV['SNMPV3_AUTH_PASS']
        @priv_protocol ||= ENV['SNMPV3_PRIV_PROTOCOL']
        @priv_password ||= ENV['SNMPV3_PRIV_PASS']
        
        # Validate SNMPv3 parameters
        if @username
          unless @auth_protocol && @auth_password
            log.warn "SNMPv3 authentication information incomplete. Auth protocol and password should be provided."
          end
          
          if (@priv_protocol && !@priv_password) || (!@priv_protocol && @priv_password)
            log.warn "SNMPv3 privacy information incomplete. Both protocol and password must be provided together."
          end
          
          # Validate auth protocol
          if @auth_protocol && !['MD5', 'SHA', 'SHA256', 'SHA512'].include?(@auth_protocol.upcase)
            log.warn "Invalid auth protocol: #{@auth_protocol}. Should be one of: MD5, SHA, SHA256, SHA512"
          end
          
          # Validate priv protocol
          if @priv_protocol && !['DES', 'AES', 'AES192', 'AES256'].include?(@priv_protocol.upcase)
            log.warn "Invalid privacy protocol: #{@priv_protocol}. Should be one of: DES, AES, AES192, AES256"
          end
        end
        
        log.info "Configured SNMPv3 trap receiver with username: #{@username}"
        log.info "Using SNMPv1/v2c community: #{@community}" if @community
      end

      def start
        super
        
        @running = true
        @retry_count = 0
        
        # Set up environment for MIB loading
        ENV['MIBDIRS'] = @mib_dir
        ENV['MIBS'] = @mibs
        
        start_snmptrapd_with_retry
      end

      def shutdown
        super
        @running = false
        
        cleanup_snmptrapd
        
        log.info "Snmptrapd input plugin has been shutdown"
      end

      private
      
      def start_snmptrapd_with_retry
        @retry_count = 0
        
        while @running && @retry_count < @max_retries
          if start_snmptrapd
            log.info "Successfully started snmptrapd"
            return true
          end
          
          @retry_count += 1
          if @retry_count < @max_retries
            log.warn "Retrying snmptrapd start (attempt #{@retry_count}/#{@max_retries}) in #{@retry_interval} seconds"
            sleep @retry_interval
          else
            log.error "Failed to start snmptrapd after #{@max_retries} attempts"
          end
        end
        
        false
      end
      
      def start_snmptrapd
        begin
          # Create SNMPv3 user if parameters provided
          if @username && @auth_password && @auth_protocol
            create_snmpv3_user
          end
          
          # Generate snmptrapd.conf if it doesn't exist
          ensure_snmptrapd_config
          
          # Launch snmptrapd and directly capture its output
          snmptrapd_cmd = "snmptrapd -f -On -Lf /dev/stdout -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid #{@port}"
          log.info "Starting snmptrapd with command: #{snmptrapd_cmd}"
          
          @pid, @stdin, @stdout, @stderr = Open3.popen3(snmptrapd_cmd)
          
          # Thread to read and process output with better error handling
          @thread = Thread.new do
            buffer = ""
            begin
              while @running
                # Use select with timeout to avoid blocking indefinitely
                ready = IO.select([@stdout], nil, nil, 1)
                next unless ready
                
                # Read available data
                begin
                  line = @stdout.readline
                rescue EOFError => e
                  log.warn "snmptrapd stdout closed unexpectedly: #{e.message}"
                  break
                end
                
                # Process the line
                if line
                  # Traps can span multiple lines, so we need to buffer until we have a complete trap
                  buffer += line
                  
                  # If this is the end of a trap message, process it
                  if line.strip.empty? || line =~ /TRAP|SNMPv2-Trap/i
                    process_trap_message(buffer.strip) unless buffer.strip.empty?
                    buffer = line  # Start new buffer with current line
                  end
                end
              end
            rescue => e
              log.error "Error reading from snmptrapd: #{e.class} - #{e.message}"
              log.error_backtrace e.backtrace
              # Attempt to restart snmptrapd on error
              if @running
                log.info "Attempting to restart snmptrapd after error"
                cleanup_snmptrapd
                sleep 1
                start_snmptrapd_with_retry
              end
            end
            
            # Process any remaining buffer content
            process_trap_message(buffer.strip) unless buffer.strip.empty?
          end
          
          # Monitor stderr for issues with better error handling
          @error_thread = Thread.new do
            begin
              if @stderr.respond_to?(:gets)
                while @running
                  ready = IO.select([@stderr], nil, nil, 1)
                  next unless ready
                  
                  begin
                    line = @stderr.readline
                    if line
                      log.warn "snmptrapd stderr: #{line.chomp}"
                    end
                  rescue EOFError => e
                    log.warn "snmptrapd stderr closed unexpectedly: #{e.message}"
                    break
                  end
                end
              end
            rescue => e
              log.error "Error reading from snmptrapd stderr: #{e.class} - #{e.message}"
              log.error_backtrace e.backtrace
            end
          end
          
          # Quick check to ensure snmptrapd is running
          sleep 0.5
          begin
            Process.kill(0, @pid.pid)
            return true
          rescue
            log.error "snmptrapd process is not running immediately after start"
            return false
          end
        rescue => e
          log.error "Failed to start snmptrapd: #{e.class} - #{e.message}"
          log.error_backtrace e.backtrace
          return false
        end
      end
      
      def cleanup_snmptrapd
        begin
          # Terminate snmptrapd
          Process.kill('TERM', @pid.pid) rescue nil
          
          # Give it a moment to exit
          begin
            Timeout.timeout(5) do
              Process.wait(@pid.pid) rescue nil
            end
          rescue Timeout::Error
            # Force kill if it doesn't exit
            Process.kill('KILL', @pid.pid) rescue nil
          end
          
          # Close all file handles
          @stdin.close rescue nil
          @stdout.close rescue nil
          @stderr.close rescue nil
          
          # Wait for threads to finish with timeout
          [@thread, @error_thread].each do |thread|
            if thread && thread.alive?
              begin
                Timeout.timeout(5) do
                  thread.join
                end
              rescue Timeout::Error
                # Thread is hanging, let's move on
                log.warn "Thread cleanup timed out"
              end
            end
          end
        rescue => e
          log.error "Error during snmptrapd cleanup: #{e.class} - #{e.message}"
          log.error_backtrace e.backtrace
        end
      end

      def ensure_snmptrapd_config
        config_path = "/etc/snmp/snmptrapd.conf"
        
        # Skip if config already exists
        return if File.exist?(config_path)
        
        log.info "Creating snmptrapd.conf configuration"
        
        content = []
        content << "# Auto-generated snmptrapd.conf"
        content << "disableAuthorization yes"
        content << "authCommunity log,execute,net #{@community}" if @community
        
        if @username
          # Create a createUser directive for SNMPv3
          user_entry = "createUser #{@username}"
          
          # Add auth protocol and password if provided
          if @auth_protocol && @auth_password
            auth_proto = @auth_protocol.upcase
            user_entry += " #{auth_proto} #{@auth_password}"
          end
          
          # Add privacy settings if provided
          if @priv_protocol && @priv_password
            priv_proto = @priv_protocol.upcase
            user_entry += " #{priv_proto} #{@priv_password}"
          end
          
          content << user_entry
          
          # Add auth user entry - ensure correct order of parameters
          level = @priv_protocol ? "authPriv" : (@auth_protocol ? "authNoPriv" : "noAuthNoPriv")
          content << "authUser log,execute,net #{@username} #{level}"
        end
        
        # Add output format - improved for better parsing
        content << "format1 TRAP[%T]: %B [%a] -> %b: %N::%W: %V"
        content << "outputOption f"
        
        # Write the configuration
        File.write(config_path, content.join("\n"))
        log.info "Created snmptrapd.conf with SNMPv3 user configuration"
      end
      
      def create_snmpv3_user
        log.info "Setting up SNMPv3 user #{@username}"
        
        begin
          # Check if net-snmp-create-v3-user exists
          `which net-snmp-create-v3-user`
          if $?.success?
            # Use net-snmp utilities to create the user
            cmd_parts = ["net-snmp-create-v3-user"]
            
            # Add -ro for read-only user (typical for trTTIap receivers)
            cmd_parts << "-ro"
            
            # Set authentication options
            auth_flag = case @auth_protocol.to_s.upcase
                        when "MD5" then "-m"
                        when "SHA" then "-a"
                        when "SHA256" then "-a SHA-256"
                        when "SHA512" then "-a SHA-512"
                        else "-a"  # Default to SHA
                        end
            
            cmd_parts << auth_flag << @auth_password
            
            # Add privacy options if provided
            if @priv_protocol && @priv_password
              priv_flag = case @priv_protocol.to_s.upcase
                         when "DES" then "-x DES"
                         when "AES" then "-x AES"
                         when "AES192" then "-x AES-192"
                         when "AES256" then "-x AES-256"
                         else "-x AES"  # Default to AES
                         end
              
              cmd_parts << priv_flag << @priv_password
            end
            
            # Add the username
            cmd_parts << @username
            
            # Build the command
            cmd = cmd_parts.join(" ")
            
            # Log command with masked passwords
            safe_cmd = cmd.gsub(/(#{Regexp.escape(@auth_password)}|#{Regexp.escape(@priv_password)})/, '******')
            log.info "Creating SNMPv3 user with command: #{safe_cmd}"
            
            # Execute the command
            output, status = Open3.capture2e(cmd)
            
            if status.success?
              log.info "SNMPv3 user #{@username} created successfully"
            else
              log.error "Failed to create SNMPv3 user #{@username}: #{output}"
            end
          else
            # net-snmp-create-v3-user not found, create entry in snmptrapd.conf instead
            log.warn "net-snmp-create-v3-user command not found, using snmptrapd.conf for SNMPv3 configuration"
            ensure_snmptrapd_config
          end
        rescue => e
          log.warn "Error creating SNMPv3 user: #{e.message}. Using snmptrapd.conf instead."
          ensure_snmptrapd_config
        end
      end

      def process_trap_message(message)
        begin
          log.debug "Processing SNMP trap: #{message}"
          
          # Initialize the record with basic information
          record = {
            'timestamp' => Time.now.utc.iso8601,
            'raw_message' => message,
            'source_type' => 'snmp'
          }
          
          # Enhanced version detection - more reliable detection of SNMPv3
          if message =~ /TRAP/ && !(message =~ /SNMPv2-Trap/)
            record['version'] = 'SNMPv1'
          elsif message =~ /SNMPv2-Trap/
            record['version'] = 'SNMPv2c'
          else
            # Improved SNMPv3 detection
            if message =~ /\[([^\]]+)\]/
              agent = $1
              if agent =~ /auth/ || agent =~ /priv/ || message =~ /securityLevel=/ || message =~ /securityName=/
                record['version'] = 'SNMPv3'
              else
                # Default to SNMPv2c if we can't determine version
                record['version'] = 'SNMPv2c'
              end
            end
          end
          
          # Extract source IP with improved regex
          if message =~ /\[([\d\.]+)(?:\:\d+)?\]/
            record['source_ip'] = $1
          end
          
          # Enhanced SNMPv3 specific information extraction
          if record['version'] == 'SNMPv3'
            # Extract security name with improved pattern matching
            if message =~ /securityName\s*=\s*([^,\s]+)/i
              record['security_name'] = $1
            elsif message =~ /\[([^\]]+)\]/ && $1.include?(@username)
              record['security_name'] = @username
            end
            
            # Extract security level with improved pattern matching
            if message =~ /securityLevel\s*=\s*([^,\s]+)/i
              record['security_level'] = $1
            elsif message =~ /authPriv/i
              record['security_level'] = 'authPriv'
            elsif message =~ /authNoPriv/i
              record['security_level'] = 'authNoPriv'
            elsif message =~ /noAuthNoPriv/i
              record['security_level'] = 'noAuthNoPriv'
            end
          end
          
          # Improved extraction of variable bindings with more robust pattern matching
          varbinds = {}
          
          # First attempt standard format extraction
          message.scan(/([.\d]+)\s*=\s*([^;\n]+)/).each do |oid, value|
            # Clean up the value - improved parsing
            clean_value = value.strip
            
            # Handle different data types
            case clean_value
            when /STRING:\s*"(.*)"/
              clean_value = $1
            when /STRING:\s*(.*)/
              clean_value = $1
            when /INTEGER:\s*(\d+)/
              clean_value = $1.to_i
            when /OID:\s*(.*)/
              clean_value = $1
            when /Hex-STRING:\s*(.*)/
              clean_value = $1
            when /Timeticks:\s*\(\d+\)\s*(.*)/
              clean_value = $1
            when /Gauge32:\s*(\d+)/
              clean_value = $1.to_i
            when /Counter32:\s*(\d+)/
              clean_value = $1.to_i
            when /Counter64:\s*(\d+)/
              clean_value = $1.to_i
            when /IpAddress:\s*(.*)/
              clean_value = $1
            end
            
            # Add to varbinds
            varbinds[oid.strip] = clean_value
          end
          
          # Add variable bindings to record
          record['varbinds'] = varbinds unless varbinds.empty?
          
          # Enhanced trap type extraction
          if record['version'] == 'SNMPv1'
            # SNMPv1 specific trap extraction with improved pattern matching
            if message =~ /Enterprise\s+Specific\s+Trap\s*\((\d+)\)/i
              record['specific_trap'] = $1.to_i
            end
            if message =~ /Enterprise:\s*([.\d]+)/i
              record['enterprise_oid'] = $1
            end
          else
            # SNMPv2c/v3 trap extraction
            if varbinds.key?('1.3.6.1.6.3.1.1.4.1.0')
              record['trap_oid'] = varbinds['1.3.6.1.6.3.1.1.4.1.0']
            end
          end
          
          # Improved trap classification - add trap type for easier processing
          if record['trap_oid']
            # Known trap OIDs
            case record['trap_oid']
            when '1.3.6.1.6.3.1.1.5.1'
              record['trap_type'] = 'coldStart'
            when '1.3.6.1.6.3.1.1.5.2'
              record['trap_type'] = 'warmStart'
            when '1.3.6.1.6.3.1.1.5.3'
              record['trap_type'] = 'linkDown'
            when '1.3.6.1.6.3.1.1.5.4'
              record['trap_type'] = 'linkUp'
            when '1.3.6.1.6.3.1.1.5.5'
              record['trap_type'] = 'authenticationFailure'
            end
          end
          
          # Emit the record with detailed debug logging
          log.debug "Emitting SNMP trap record: #{record.to_json}"
          router.emit(@tag, Fluent::EventTime.now, record)
        rescue => e
          log.error "Failed to process SNMP trap message: #{message}", error: e.to_s
          log.error_backtrace e.backtrace
        end
      end
    end
  end
end
