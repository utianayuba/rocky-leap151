#!/bin/bash

source os.conf
source admin-openrc
[ -d ./tmp ] || mkdir ./tmp



##### Ironic Service #####

cat << _EOF_ > ./tmp/mariadb_ironic
mysql -u root -p$PASSWORD -e "CREATE DATABASE ironic; GRANT ALL PRIVILEGES ON ironic.* TO 'ironic'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON ironic.* TO 'ironic'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CTL_MAN_IP < ./tmp/mariadb_ironic

ssh $CTL_MAN_IP zypper -n in --no-recommends openstack-ironic-api openstack-ironic-conductor openstack-nova-compute python-ironicclient

ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf database connection mysql+pymysql://ironic:$PASSWORD@$CTL_MAN_IP/ironic
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf DEFAULT transport_url rabbit://openstack:$PASSWORD@$CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf DEFAULT auth_strategy keystone
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken www_authenticate_uri http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken auth_url http://$CTL_MAN_IP:5000/v3
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken memcached_servers $CTL_MAN_IP:11211
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken auth_type password
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken project_name service
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken username ironic
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf keystone_authtoken password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron url http://$CTL_MAN_IP:9696
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron auth_url http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron auth_type password
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron project_domain_name default
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron user_domain_name default
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron region_name RegionOne
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron project_name service
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron username neutron
ssh $CTL_MAN_IP crudini --set /etc/ironic/ironic.conf neutron password $PASSWORD

ssh $CTL_MAN_IP ironic-dbsync --config-file /etc/ironic/ironic.conf create_schema
ssh $CTL_MAN_IP chown -R ironic:ironic /var/log/ironic/

ssh $CTL_MAN_IP systemctl enable openstack-ironic-api openstack-ironic-conductor 
ssh $CTL_MAN_IP systemctl restart openstack-ironic-api openstack-ironic-conductor
ssh $CTL_MAN_IP systemctl status openstack-ironic-api openstack-ironic-conductor

openstack user list | grep ironic > /dev/null 2>&1 && echo "ironic user already exists" || openstack user create --domain default --password $PASSWORD ironic
openstack role add --project service --user ironic admin
openstack service list | grep ironic > /dev/null 2>&1 && echo "ironic service already exists" || openstack service create --name ironic --description "OpenStack baremetal provisioning service" baremetal
openstack endpoint list | grep public | grep ironic > /dev/null 2>&1 && echo "ironic public endpoint already exists" || openstack endpoint create --region RegionOne baremetal public http://$CTL_MAN_IP:6385
openstack endpoint list | grep internal | grep ironic > /dev/null 2>&1 && echo "ironic internal endpoint exists" || openstack endpoint create --region RegionOne baremetal internal http://$CTL_MAN_IP:6385
openstack endpoint list | grep admin | grep ironic > /dev/null 2>&1 && echo "ironic admin endpoint already exists" || openstack endpoint create --region RegionOne baremetal admin http://$CTL_MAN_IP:6385

ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT compute_driver ironic.IronicDriver
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf DEFAULT reserved_host_memory_mb 0
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf filter_scheduler track_instance_changes False
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf scheduler discover_hosts_in_cells_interval 120
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic auth_type password
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic auth_url http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic project_name service
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic username ironic
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/nova/nova.conf ironic region_name RegionOne

ssh $CTL_MAN_IP systemctl enable openstack-nova-compute.service
ssh $CTL_MAN_IP systemctl restart openstack-nova-compute.service openstack-nova-scheduler
ssh $CTL_MAN_IP systemctl status openstack-nova-compute.service openstack-nova-scheduler

wget -c http://mirror.internode.on.net/pub/centos/7.7.1908/cloud/x86_64/openstack-rocky/python2-networking-baremetal-1.2.0-1.el7.noarch.rpm -P ./tmp/
wget -c http://mirror.internode.on.net/pub/centos/7.7.1908/cloud/x86_64/openstack-rocky/python2-ironic-neutron-agent-1.2.0-1.el7.noarch.rpm -P ./tmp/
cd ./tmp/
rpm2cpio /root/leap151-rocky/python2-networking-baremetal-1.2.0-1.el7.noarch.rpm  | cpio -idmv
rpm2cpio /root/leap151-rocky/python2-ironic-neutron-agent-1.2.0-1.el7.noarch.rpm  | cpio -idmv
scp -r usr $CTL_MAN_IP:/
cd ..

ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch,baremetal
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic auth_type password
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic auth_url http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic project_name service
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic username ironic
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ironic_neutron_agent.ini ironic region_name RegionOne
ssh $CTL_MAN_IP systemctl enable ironic-neutron-agent.service
ssh $CTL_MAN_IP systemctl restart ironic-neutron-agent.service
ssh $CTL_MAN_IP systemctl status ironic-neutron-agent.service
