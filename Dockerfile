FROM ghcr.io/frappe/lms:stable

USER root

# Install system dependencies required to build and run lms Python & C extensions
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      gcc \
      g++ \
      make \
      pkg-config \
      libffi-dev \
      libxml2-dev \
      libxslt1-dev \
      libcairo2 \
      libcairo2-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy the Render startup script and normalize line endings
COPY docker/render-entrypoint.sh /usr/local/bin/render-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/render-entrypoint.sh && \
    chmod 755 /usr/local/bin/render-entrypoint.sh

# Overlay repository code into the Frappe bench LMS app directory
RUN rm -rf /home/frappe/frappe-bench/apps/lms
COPY --chown=frappe:0 . /home/frappe/frappe-bench/apps/lms

USER frappe
WORKDIR /home/frappe/frappe-bench

# 1. Fetch payments app if not already present and install both payments & lms into bench env
RUN if [ ! -d /home/frappe/frappe-bench/apps/payments ]; then \
      git clone --depth 1 https://github.com/frappe/payments /home/frappe/frappe-bench/apps/payments && \
      rm -rf /home/frappe/frappe-bench/apps/payments/.git; \
    fi && \
    /home/frappe/frappe-bench/env/bin/python -m pip install --no-cache-dir \
      -e /home/frappe/frappe-bench/apps/payments \
      -e /home/frappe/frappe-bench/apps/lms && \
    /home/frappe/frappe-bench/env/bin/python -c "import frappe, payments, lms; print('Verified imports: frappe, payments, lms')"

# 2. Build LMS frontend SPA (_lms.html + public/frontend) and bake into /home/frappe/frappe-bench/assets
RUN if [ ! -d /home/frappe/frappe-bench/apps/frappe/ui ]; then \
      git clone --depth 1 --filter=blob:none --sparse --branch develop https://github.com/frappe/frappe /tmp/frappe-ui && \
      cd /tmp/frappe-ui && git sparse-checkout set ui && \
      cp -r /tmp/frappe-ui/ui /home/frappe/frappe-bench/apps/frappe/ui && \
      rm -rf /tmp/frappe-ui; \
    fi && \
    mkdir -p /home/frappe/frappe-bench/sites && \
    echo '{"socketio_port": 9000}' > /home/frappe/frappe-bench/sites/common_site_config.json && \
    cd /home/frappe/frappe-bench/apps/lms && \
    export PATH="/home/frappe/.nvm/current/bin:${PATH}" && \
    yarn install --frozen-lockfile && \
    NODE_OPTIONS="--max-old-space-size=4096" yarn build && \
    rm -rf /home/frappe/frappe-bench/assets/lms && \
    cp -r /home/frappe/frappe-bench/apps/lms/lms/public /home/frappe/frappe-bench/assets/lms && \
    if [ -d /home/frappe/frappe-bench/apps/payments/payments/public ]; then \
      rm -rf /home/frappe/frappe-bench/assets/payments && \
      cp -r /home/frappe/frappe-bench/apps/payments/payments/public /home/frappe/frappe-bench/assets/payments; \
    fi && \
    rm -rf /home/frappe/frappe-bench/apps/lms/node_modules \
           /home/frappe/frappe-bench/apps/lms/frontend/node_modules \
           /home/frappe/.cache

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/render-entrypoint.sh"]
