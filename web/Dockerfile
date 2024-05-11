FROM nginx:alpine

# Install bash and gettext in the container
RUN apk add --no-cache bash gettext

# Copy your new web files into the container
COPY ./public /usr/share/nginx/html
COPY ./src/css /usr/share/nginx/html/css
COPY ./src/js /usr/share/nginx/html/js
COPY ../config.js.template /usr/share/nginx/
COPY ../startup.sh /usr/share/nginx/

# Ensure the startup script is executable
RUN chmod +x /usr/share/nginx/startup.sh

CMD ["/usr/share/nginx/startup.sh"]

# Expose port 80
EXPOSE 80
