FROM alpine:3.7


#-----------------------nginx--------------------------------------------------------------
ENV NGINX_VERSION 1.12.0

COPY nginx-module-vts /tmp/nginx-module-vts

RUN GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8 \
        && CONFIG="\
                --prefix=/etc/nginx \
                --sbin-path=/usr/sbin/nginx \
                --modules-path=/usr/lib/nginx/modules \
                --conf-path=/etc/nginx/nginx.conf \
                --error-log-path=/var/log/nginx/error.log \
                --http-log-path=/var/log/nginx/access.log \
                --pid-path=/var/run/nginx.pid \
                --lock-path=/var/run/nginx.lock \
                --http-client-body-temp-path=/var/cache/nginx/client_temp \
                --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
                --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
                --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
                --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
                --user=nginx \
                --group=nginx \
                --with-http_ssl_module \
                --with-http_realip_module \
                --with-http_addition_module \
                --with-http_sub_module \
                --with-http_dav_module \
                --with-http_flv_module \
                --with-http_mp4_module \
                --with-http_gunzip_module \
                --with-http_gzip_static_module \
                --with-http_random_index_module \
                --with-http_secure_link_module \
                --with-http_stub_status_module \
                --with-http_auth_request_module \
                --with-http_xslt_module=dynamic \
                --with-http_image_filter_module=dynamic \
                --with-http_geoip_module=dynamic \
                --with-threads \
                --with-stream \
                --with-stream_ssl_module \
                --with-stream_ssl_preread_module \
                --with-stream_realip_module \
                --with-stream_geoip_module=dynamic \
                --with-http_slice_module \
                --with-mail \
                --with-mail_ssl_module \
                --with-compat \
                --with-file-aio \
                --with-http_v2_module \
                --add-module=/tmp/nginx-module-vts\
        " \
        && addgroup -S nginx \
        && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
        && apk add --no-cache --virtual .build-deps \
                gcc \
                libc-dev \
                make \
                openssl-dev \
                pcre-dev \
                zlib-dev \
                linux-headers \
                curl \
                gnupg \
                libxslt-dev \
                gd-dev \
                geoip-dev \
        && curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
        && curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc  -o nginx.tar.gz.asc \
        && export GNUPGHOME="$(mktemp -d)" \
        && found=''; \
        for server in \
                ha.pool.sks-keyservers.net \
                hkp://keyserver.ubuntu.com:80 \
                hkp://p80.pool.sks-keyservers.net:80 \
                pgp.mit.edu \
        ; do \
                echo "Fetching GPG key $GPG_KEYS from $server"; \
                gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
        done; \
        test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
        gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
        && rm -r "$GNUPGHOME" nginx.tar.gz.asc \
        && mkdir -p /usr/src \
        && tar -zxC /usr/src -f nginx.tar.gz \
        && rm nginx.tar.gz \
        && cd /usr/src/nginx-$NGINX_VERSION \
        && ./configure $CONFIG --with-debug \
        && make -j$(getconf _NPROCESSORS_ONLN) \
        && mv objs/nginx objs/nginx-debug \
        && mv objs/ngx_http_xslt_filter_module.so objs/ngx_http_xslt_filter_module-debug.so \
        && mv objs/ngx_http_image_filter_module.so objs/ngx_http_image_filter_module-debug.so \
        && mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
        && mv objs/ngx_stream_geoip_module.so objs/ngx_stream_geoip_module-debug.so \
        && ./configure $CONFIG \
        && make -j$(getconf _NPROCESSORS_ONLN) \
        && make install \
        && rm -rf /etc/nginx/html/ \
        && mkdir /etc/nginx/conf.d/ \
        && mkdir -p /usr/share/nginx/html/ \
        && install -m644 html/index.html /usr/share/nginx/html/ \
        && install -m644 html/50x.html /usr/share/nginx/html/ \
        && install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
        && install -m755 objs/ngx_http_xslt_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_xslt_filter_module-debug.so \
        && install -m755 objs/ngx_http_image_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_image_filter_module-debug.so \
        && install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
        && install -m755 objs/ngx_stream_geoip_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip_module-debug.so \
        && ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
        && strip /usr/sbin/nginx* \
        && strip /usr/lib/nginx/modules/*.so \
        && rm -rf /usr/src/nginx-$NGINX_VERSION \
        \
        # Bring in gettext so we can get `envsubst`, then throw
        # the rest away. To do this, we need to install `gettext`
        # then move `envsubst` out of the way so `gettext` can
        # be deleted completely, then move `envsubst` back.
        && apk add --no-cache --virtual .gettext gettext \
        && mv /usr/bin/envsubst /tmp/ \
        \
        && runDeps="$( \
                scanelf --needed --nobanner /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
                        | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
                        | sort -u \
                        | xargs -r apk info --installed \
                        | sort -u \
        )" \
        && apk add --no-cache --virtual .nginx-rundeps $runDeps \
        && apk del .build-deps \
        && apk del .gettext \
        && mv /tmp/envsubst /usr/local/bin/ \
        \ 
        # forward request and error logs to docker log collector
        && ln -sf /proc/1/fd/1 /var/log/nginx/access.log \
        && ln -sf /proc/1/fd/1 /var/log/nginx/error.log

#------------------nginx-vts-exporter---------------------------------------------------------------------------------
RUN apk update
RUN apk --update add wget
RUN wget https://github.com/hnlq715/nginx-vts-exporter/releases/download/v0.10.3/nginx-vts-exporter-0.10.3.linux-amd64.tar.gz
RUN tar xzf nginx-vts-exporter-0.10.3.linux-amd64.tar.gz
RUN mv nginx-vts-exporter-0.10.3.linux-amd64/nginx-vts-exporter /bin/
RUN rm -rf nginx-vts-exporter-0.10.3.linux-amd64 nginx-vts-exporter-0.10.3.linux-amd64.tar.gz 

# z reki: nginx-vts-exporter -nginx.scrape_uri=http://localhost:8080/status/format/json

#------------------nginx openshift customization----------------------------------------------------------------------
COPY default.conf /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080
EXPOSE 9913

#https://torstenwalter.de/openshift/nginx/2017/08/04/nginx-on-openshift.html
#By default, OpenShift Container Platform runs containers using an arbitrarily assigned user ID. This provides additional security 
#against processes escaping the container due to a container engine vulnerability and thereby achieving escalated permissions on the host node.
#For an image to support running as an arbitrary user, directories and files that may be written to by processes in the image 
#should be owned by the root group and be read/writable by that group. Files to be executed should also have group execute permissions.
#RUN chmod -R g+rwx /var/cache/nginx /var/run /var/log/nginx

RUN mkdir /var/cache/nginx/client_temp/ && chmod g+rwx /var/cache/nginx/client_temp/
RUN mkdir /var/cache/nginx/proxy_temp && chmod g+rwx /var/cache/nginx/proxy_temp 
RUN mkdir /var/cache/nginx/fastcgi_temp && chmod g+rwx /var/cache/nginx/fastcgi_temp 
RUN mkdir /var/cache/nginx/uwsgi_temp && chmod g+rwx /var/cache/nginx/uwsgi_temp  
RUN mkdir /var/cache/nginx/scgi_temp && chmod g+rwx /var/cache/nginx/scgi_temp 
RUN chmod -R g+rwx /var/run /usr/share/nginx/html

#-----------------------supervisord--------------------------------------------------------------
RUN apk update
RUN apk --update add supervisor 
RUN mkdir /etc/supervisor.d/ && chmod g+rwx /etc/supervisor.d/
RUN mkdir /etc/supervisor.conf && chmod g+rwx /etc/supervisor.conf
ADD supervisord.conf /etc/supervisor.conf/
RUN chmod g+rwx /var/log 
RUN chmod g+rwx /run
ADD nginx.ini /etc/supervisor.d/
ADD vts-exporter.ini /etc/supervisor.d/

#poprawny CMD dla tej sekcji: CMD /usr/bin/supervisord  -n -c /etc/supervisor.conf/supervisord.conf -j /run/supervisord.pid

#-----------------final steps-----------------------------------------------------------------------
STOPSIGNAL SIGQUIT

#klasyczne wywolanie nginx bez supervisora: CMD hostname  > /usr/share/nginx/html/index.html && nginx -g "daemon off;" 
#puste CMD: CMD tail -f /dev/null
# w srodku kontenera obsluga supervisora: supervisorctl -c /etc/supervisor.conf/supervisord.conf

CMD hostname  > /usr/share/nginx/html/index.html && /usr/bin/supervisord  -n -c /etc/supervisor.conf/supervisord.conf -j /run/supervisord.pid
