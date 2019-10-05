#!/bin/bash

source os.conf
[ -d ./tmp ] || mkdir ./tmp



##### Keystone Service #####

cat << _EOF_ > ./tmp/mariadb_keystone
mysql -u root -p$PASSWORD -e "CREATE DATABASE keystone; GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CTL_MAN_IP < ./tmp/mariadb_keystone

ssh $CTL_MAN_IP zypper -n in --no-recommends openstack-keystone crudini apache2 apache2-mod_wsgi

ssh $CTL_MAN_IP crudini --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:$PASSWORD@$CTL_MAN_IP/keystone
ssh $CTL_MAN_IP crudini --set /etc/keystone/keystone.conf token provider fernet

ssh $CTL_MAN_IP keystone-manage db_sync
ssh $CTL_MAN_IP keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
ssh $CTL_MAN_IP keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
ssh $CTL_MAN_IP keystone-manage bootstrap --bootstrap-password $PASSWORD --bootstrap-admin-url http://$CTL_MAN_IP:5000/v3/ --bootstrap-internal-url http://$CTL_MAN_IP:5000/v3/ --bootstrap-public-url http://$CTL_MAN_IP:5000/v3/ --bootstrap-region-id RegionOne

#ssh $CTL_MAN_IP echo "APACHE_SERVERNAME="$CTL_HOSTNAME"" > /etc/sysconfig/apache2

cat << _EOF_ > ./tmp/etc_apache2_conf.d_wsgi-keystone.conf
Listen 5000

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        Require all granted
    </Directory>
</VirtualHost>
_EOF_

scp ./tmp/etc_apache2_conf.d_wsgi-keystone.conf $CTL_MAN_IP:/etc/apache2/conf.d/wsgi-keystone.conf

ssh $CTL_MAN_IP echo "LoadModule wsgi_module /usr/lib64/apache2/mod_wsgi.so" >> /etc/apache2/loadmodule.conf

ssh $CTL_MAN_IP chown -R keystone:keystone /etc/keystone

ssh $CTL_MAN_IP systemctl enable apache2.service
ssh $CTL_MAN_IP systemctl restart apache2.service
ssh $CTL_MAN_IP systemctl status apache2.service

cat << _EOF_ > ./admin-openrc
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$PASSWORD
export OS_AUTH_URL=http://$CTL_MAN_IP:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
_EOF_

source ./admin-openrc
openstack project list | grep service > /dev/null 2>&1 && echo "service project already exist" || openstack project create --domain default --description "Service Project" service
openstack project list
openstack role list | grep user > /dev/null 2>&1 && echo "user role already exist" || openstack role create user
openstack role list
openstack token issue
