FROM ghcr.io/frappe/lms:stable

USER root

# Copy the Render startup script and normalize line endings
COPY docker/render-entrypoint.sh /usr/local/bin/render-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/render-entrypoint.sh && \
    chmod 755 /usr/local/bin/render-entrypoint.sh

# Overlay repository code into the Frappe bench LMS app directory
COPY --chown=frappe:0 . /home/frappe/frappe-bench/apps/lms

# Sync prebuilt LMS public assets into the baked assets directory if present
RUN if [ -d /home/frappe/frappe-bench/apps/lms/lms/public ] && [ -d /home/frappe/frappe-bench/assets/lms ]; then \
      cp -rn /home/frappe/frappe-bench/apps/lms/lms/public/* /home/frappe/frappe-bench/assets/lms/ 2>/dev/null || true; \
    fi && \
    chown -R frappe:0 /home/frappe/frappe-bench/apps/lms /home/frappe/frappe-bench/assets

USER frappe
WORKDIR /home/frappe/frappe-bench

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/render-entrypoint.sh"]
