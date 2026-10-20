FROM python:3.12-slim

RUN pip install --no-cache-dir "parsedmarc[all,postgresql]"

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Default working directories
WORKDIR /
RUN mkdir -p /input /output

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["parsedmarc", "-c", "/etc/parsedmarc.ini", "-r", "/input", "--debug"]
