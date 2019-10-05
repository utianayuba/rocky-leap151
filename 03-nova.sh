#!/bin/bash

source os.conf
source admin-openrc
[ -d ./tmp ] || mkdir ./tmp



##### Nova Service #####

cat << _EOF_ > ./tmp/mariadb_nova
mysql -u root -p$PASSWORD -e "CREATE DATABASE nova; GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';"
mysql -u root -p$PASSWORD -e "CREATE DATABASE nova_api; GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';"
mysql -u root -p$PASSWORD -e "CREATE DATABASE nova_cell0; GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';"
mysql -u root -p$PASSWORD -e "CREATE DATABASE placement; GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CTL_MAN_IP < ./tmp/mariadb_nova

openstack user list | grep nova > /dev/null 2>&1 && echo "nova user already exists" || openstack user create --domain default --password $PASSWORD nova
openstack role add --project service --user nova admin
openstack service list | grep nova > /dev/null 2>&1 && echo "nova service already exists" || openstack service create --name nova --description "OpenStack Compute service" compute
openstack endpoint list | grep public | grep nova > /dev/null 2>&1 && echo "nova public endpoint already exists" || openstack endpoint create --region RegionOne compute public http://$CTL_MAN_IP:8774/v2.1
openstack endpoint list | grep internal | grep nova > /dev/null 2>&1 && echo "nova internal endpoint already exists" || openstack endpoint create --region RegionOne compute internal http://$CTL_MAN_IP:8774/v2.1
openstack endpoint list | grep admin | grep nova > /dev/null 2>&1 && echo "nova admin endpoint already exists" || openstack endpoint create --region RegionOne compute admin http://$CTL_MAN_IP:8774/v2.1
openstack user list | grep placement > /dev/null 2>&1 && echo "placement user already exists" || openstack user create --domain default --password $PASSWORD placement
openstack role add --project service --user placement admin
openstack service list | grep placement > /dev/null 2>&1 && echo "placement service already exists" || openstack service create --name placement --description "Placement API" placement
openstack endpoint list | grep public | grep placement > /dev/null 2>&1 && echo "placement public endpoint already exists" || openstack endpoint create --region RegionOne placement public http://$CTL_MAN_IP:8780
openstack endpoint list | grep internal | grep placement > /dev/null 2>&1 && echo "placement internal endpoint already exists" || openstack endpoint create --region RegionOne placement internal http://$CTL_MAN_IP:8780
openstack endpoint list | grep admin | grep placement > /dev/null 2>&1 && echo "placement admin endpoint already exists" || openstack endpoint create --region RegionOne placement admin http://$CTL_MAN_IP:8780

ssh $CTL_MAN_IP zypper -n in --no-recommends openstack-nova-api openstack-nova-scheduler openstack-nova-conductor openstack-nova-consoleauth openstack-nova-novncproxy openstack-nova-placement-api iptables

ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:$PASSWORD@$CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT my_ip $CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT use_neutron true
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://nova:$PASSWORD@$CTL_MAN_IP/nova_api
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf database connection mysql+pymysql://nova:$PASSWORD@$CTL_MAN_IP/nova
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement_database connection mysql+pymysql://placement:$PASSWORD@$CTL_MAN_IP/placement
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf api auth_strategy keystone
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$CTL_MAN_IP:5000/v3
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $CTL_MAN_IP:11211
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken username nova
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf vnc enabled true
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf vnc server_listen $CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf glance api_servers http://$CTL_MAN_IP:9292
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/run/nova
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement region_name RegionOne
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement project_name service
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement auth_type password
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement auth_url http://$CTL_MAN_IP:5000/v3
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement username placement
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf placement password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf scheduler discover_hosts_in_cells_interval 300
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron url http://$CTL_MAN_IP:9696
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron auth_url http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron auth_type password
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron project_domain_name default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron user_domain_name default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron region_name RegionOne
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron project_name service
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron username neutron
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $PASSWORD


ssh $CTL_MAN_IP nova-manage api_db sync
ssh $CTL_MAN_IP nova-manage cell_v2 map_cell0
ssh $CTL_MAN_IP nova-manage cell_v2 create_cell --name=cell1 --verbose
ssh $CTL_MAN_IP nova-manage db sync
ssh $CTL_MAN_IP nova-manage cell_v2 list_cells

ssh $CTL_MAN_IP chown -R nova:nova /var/log/nova/

ssh $CTL_MAN_IP [ -f /etc/apache2/vhosts.d/nova-placement-api.conf.sample ] && mv /etc/apache2/vhosts.d/nova-placement-api.conf.sample /etc/apache2/vhosts.d/nova-placement-api.conf
ssh $CTL_MAN_IP systemctl reload apache2.service

ssh $CTL_MAN_IP systemctl enable openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
ssh $CTL_MAN_IP systemctl restart openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
ssh $CTL_MAN_IP systemctl status openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service

ssh $CMP_MAN_IP zypper -n in --no-recommends openstack-nova-compute genisoimage qemu-kvm libvirt crudini

ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT compute_driver libvirt.LibvirtDriver
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:$PASSWORD@$CTL_MAN_IP
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT my_ip $CMP_MAN_IP
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT use_neutron true
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf api auth_strategy keystone
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$CTL_MAN_IP:5000/v3
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $CTL_MAN_IP:11211
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name Default
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name Default
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken username nova
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf keystone_authtoken password $PASSWORD
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf vnc enabled true
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf vnc server_listen 0.0.0.0
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $CMP_MAN_IP
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf vnc novncproxy_base_url http://$CTL_MAN_IP:6080/vnc_auto.html
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf glance api_servers http://$CTL_MAN_IP:9292
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/run/nova
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement region_name RegionOne
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement project_domain_name Default
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement project_name service
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement auth_type password
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement user_domain_name Default
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement auth_url http://$CTL_MAN_IP:5000/v3
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement username placement
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf placement password $PASSWORD
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron url http://$CTL_MAN_IP:9696
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron auth_url http://$CTL_MAN_IP:5000
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron auth_type password
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron project_domain_name default
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron user_domain_name default
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron region_name RegionOne
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron project_name service
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron username neutron
ssh $CMP_MAN_IP crudini --set /etc/nova/nova.conf neutron password $PASSWORD

ssh $CMP_MAN_IP modprobe nbd

ssh $CMP_MAN_IP systemctl enable libvirtd.service openstack-nova-compute.service
ssh $CMP_MAN_IP systemctl restart libvirtd.service openstack-nova-compute.service
ssh $CMP_MAN_IP systemctl status libvirtd.service openstack-nova-compute.service

ssh $CTL_MAN_IP nova-manage cell_v2 discover_hosts --verbose

openstack compute service list
openstack catalog list

ssh $CTL_MAN_IP nova-status upgrade check
