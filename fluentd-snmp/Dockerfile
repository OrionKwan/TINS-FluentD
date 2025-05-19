FROM fluent/fluentd:v1.16-1

# Switch to root user to install packages
USER root

# Install dependencies for SNMPv3 including net-snmp, tcpdump and additional tools
RUN apk add --no-cache \
    net-snmp \
    net-snmp-dev \
    net-snmp-tools \
    perl \
    lsof \
    tcpdump

# Install required gems with specific versions in a single layer
RUN apk add --no-cache build-base ruby-dev && \
    gem install msgpack -v "~> 1.4" && \
    gem install snmp && \
    gem install fluent-plugin-kafka -v 0.19.4 && \
    gem install fluent-plugin-remote_syslog -v 1.1.0 && \
    gem install fluent-plugin-record-modifier -v 2.2.0 && \
    gem install fluent-plugin-tagged_udp && \
    apk del build-base ruby-dev && \
    rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

# Create directories in a single layer
RUN mkdir -p /fluentd/plugins /etc/snmp /fluentd/log /fluentd/buffer /fluentd/etc && \
    chmod -R 755 /fluentd

# Copy configuration files and plugins
COPY plugins/in_snmptrapd.rb /fluentd/plugins/
COPY conf/snmptrapd.conf /etc/snmp/
COPY conf/fluent.conf /fluentd/etc/
COPY trap-capture.sh /trap-capture.sh
COPY entrypoint.sh /entrypoint.sh

# Set permissions
RUN chmod +x /fluentd/plugins/*.rb \
    && chmod +x /trap-capture.sh \
    && chmod +x /entrypoint.sh

# Expose SNMP trap port
EXPOSE 1162/udp

# Run as root to allow binding to port 1162
USER root

# Use our custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Command
CMD ["fluentd", "-p", "/fluentd/plugins", "-c", "/fluentd/etc/fluent.conf"]
