#!/bin/bash
source .env
PGPASSWORD=$DB_PASSWORD pg_dump -h localhost -U $DB_USER -d $DB_NAME -p $DB_PORT --schema-only --no-comments \
  | grep -v '^COMMENT ON' \
  | grep -v '^ *--' \
  | grep -v '^ALTER.*OWNER TO' \
  | sed 's/[[:space:]]*$//' \
  | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n\{3,\}/\n\n/g' \
  > schema/schema.sql
