#!/bin/bash

source os.conf
source admin-openrc
[ -d ./tmp ] || mkdir ./tmp



##### Glance Service #####

cat << _EOF_ > ./tmp/mariadb_glance
mysql -u root -p$PASSWORD -e "CREATE DATABASE glance; GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CTL_MAN_IP < ./tmp/mariadb_glance

openstack user list | grep glance > /dev/null 2>&1 && echo "glance user already exists" || openstack user create --domain default --password $PASSWORD glance
openstack role add --project service --user glance admin
openstack service list | grep glance > /dev/null 2>&1 && echo "glance service already exists" || openstack service create --name glance --description "OpenStack Image service" image
openstack endpoint list | grep public | grep glance > /dev/null 2>&1 && echo "glance public endpoint already exists" || openstack endpoint create --region RegionOne image public http://$CTL_MAN_IP:9292
openstack endpoint list | grep internal | grep glance > /dev/null 2>&1 && echo "glance internal endpoint already exists" || openstack endpoint create --region RegionOne image internal http://$CTL_MAN_IP:9292
openstack endpoint list | grep admin | grep glance > /dev/null 2>&1 && echo "glance admin endpoint already exists" || openstack endpoint create --region RegionOne image admin http://$CTL_MAN_IP:9292

ssh $CTL_MAN_IP zypper -n in --no-recommends openstack-glance openstack-glance-api openstack-glance-registry

ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:$PASSWORD@$CTL_MAN_IP/glance
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken www_authenticate_uri http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers $CTL_MAN_IP:11211
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf keystone_authtoken password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf glance_store stores file,http
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf glance_store default_store file
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/

ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf database connection mysql+pymysql://glance:$PASSWORD@$CTL_MAN_IP/glance
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken www_authenticate_uri http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_url http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken memcached_servers $CTL_MAN_IP:11211
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_type password
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_name service
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken username glance
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf keystone_authtoken password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/glance/glance-registry.conf paste_deploy flavor keystone

ssh $CTL_MAN_IP systemctl enable openstack-glance-api.service openstack-glance-registry.service
ssh $CTL_MAN_IP systemctl restart openstack-glance-api.service openstack-glance-registry.service
ssh $CTL_MAN_IP systemctl status openstack-glance-api.service openstack-glance-registry.service

