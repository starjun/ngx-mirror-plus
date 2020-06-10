## bash
## version 0.1

version=1.0.0.1
ip=192.168.84.41
if [ "$1" = "mirror-ngx" ];then

    rm -rf /opt/openresty/mirror-ngx.bak
    mv /opt/openresty/mirror-ngx /opt/openresty/mirror-ngx.bak

    cd /opt/openresty/
    wget -N "http://${ip}/mirror-ngx-${version}.zip"
    unzip -o mirror-ngx-${version}.zip -d /opt/openresty/
    mv -f mirror-ngx-${version}/ngxs mirror-ngx


    if [ "$2" = "all" ];then ## conf + json
        cp -Rf /opt/openresty/mirror-ngx.bak/conf_json/* /opt/openresty/mirror-ngx/conf_json/
        cp -Rf /opt/openresty/mirror-ngx.bak/conf/* /opt/openresty/mirror-ngx/conf/
        # cp -Rf /opt/openresty/mirror-ngx.bak/regsn.json /opt/openresty/mirror-ngx/
    elif [ "$2" = "conf" ];then ## conf
        cp -Rf /opt/openresty/mirror-ngx.bak/conf/* /opt/openresty/mirror-ngx/conf/
    else ## json
        cp -Rf /opt/openresty/mirror-ngx.bak/conf_json/* /opt/openresty/mirror-ngx/conf_json/
    fi

elif [ "$1" = "test" ];then

    echo "it is a test!"

else
    echo "./new.sh mirror-ngx"
fi