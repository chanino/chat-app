#!/bin/bash

# Use environment variables to create config.js
envsubst < /usr/share/nginx/config.js.template > /usr/share/nginx/html/js/config.js

# Start Nginx in the foreground, replacing the current shell with `nginx`
exec nginx -g 'daemon off;'
