FROM grafana/grafana:11.5.2

# Dashboards live outside /var/lib/grafana: that path is a persistent volume,
# which would hide (and freeze) whatever the image ships there.
COPY --chown=grafana:root grafana-provisioning/ /etc/grafana/provisioning/
COPY --chown=grafana:root dashboards/ /etc/grafana/dashboards/
