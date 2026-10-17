FROM mariadb:10.8

# Frappe Framework requires utf8mb4 character set and collation
CMD [ \
  "mysqld", \
  "--character-set-server=utf8mb4", \
  "--collation-server=utf8mb4_unicode_ci", \
  "--skip-character-set-client-handshake", \
  "--skip-innodb-read-only-compressed" \
]
