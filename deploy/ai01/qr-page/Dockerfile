FROM nginx:1.27-alpine
# nginx:alpine renders /etc/nginx/templates/*.template with envsubst at start; restrict it to
# the API key so nginx's own $variables are left alone.
ENV NGINX_ENVSUBST_FILTER=^WHATSAPP_API_KEY$
RUN rm -f /etc/nginx/conf.d/default.conf
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 8080
