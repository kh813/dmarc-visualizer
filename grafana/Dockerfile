FROM grafana/grafana:11.5.2

USER root
RUN mkdir -p /var/lib/grafana/dashboards && chown -R grafana:root /var/lib/grafana/dashboards
USER grafana

COPY --chown=grafana:root grafana-provisioning/ /etc/grafana/provisioning/
COPY --chown=grafana:root dashboards/ /var/lib/grafana/dashboards/
