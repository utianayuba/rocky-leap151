#!/bin/bash

source os.conf
source admin-openrc
[ -d ./tmp ] || mkdir ./tmp



##### Neutron Service #####

ssh $CTL_MAN_IP zypper -n in --no-recommends openvswitch
ssh $CTL_MAN_IP systemctl enable openvswitch
ssh $CTL_MAN_IP systemctl restart openvswitch
ssh $CTL_MAN_IP systemctl status openvswitch

cat << _EOF_ > ./tmp/etc_sysconfig_network_ifcfg_br-ex_ctl
BOOTPROTO='none'
NAME='br-ex'
STARTMODE='auto'
OVS_BRIDGE='yes'
OVS_BRIDGE_PORT_DEVICE='$CTL_EXT_INT'
_EOF_

scp ./tmp/etc_sysconfig_network_ifcfg_br-ex_ctl $CTL_MAN_IP:/etc/sysconfig/network/ifcfg-br-ex

cat << _EOF_ > ./tmp/etc_sysconfig_network_ifcfg_ext_ctl
STARTMODE='auto'
BOOTPROTO='none'
_EOF_

scp ./tmp/etc_sysconfig_network_ifcfg_ext_ctl $CTL_MAN_IP:/etc/sysconfig/network/ifcfg-$CTL_EXT_INT

ssh $CTL_MAN_IP wicked ifup all
ssh $CTL_MAN_IP ip link show
ssh $CTL_MAN_IP ovs-vsctl show

cat << _EOF_ > ./tmp/mariadb_neutron
mysql -u root -p$PASSWORD -e "CREATE DATABASE neutron; GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CTL_MAN_IP < ./tmp/mariadb_neutron

openstack user list | grep neutron > /dev/null 2>&1 && echo "neutron user already exists" || openstack user create --domain default --password $PASSWORD neutron
openstack role add --project service --user neutron admin
openstack service list | grep neutron > /dev/null 2>&1 && echo "neutron service already exists" || openstack service create --name neutron --description "OpenStack Networking service" network
openstack endpoint list | grep public | grep neutron > /dev/null 2>&1 && echo "neutron public endpoint already exists" || openstack endpoint create --region RegionOne network public http://$CTL_MAN_IP:9696
openstack endpoint list | grep internal | grep neutron > /dev/null 2>&1 && echo "neutron internal endpoint exists" || openstack endpoint create --region RegionOne network internal http://$CTL_MAN_IP:9696
openstack endpoint list | grep admin | grep neutron > /dev/null 2>&1 && echo "neutron admin endpoint already exists" || openstack endpoint create --region RegionOne network admin http://$CTL_MAN_IP:9696

ssh $CTL_MAN_IP zypper -n in --no-recommends openstack-neutron openstack-neutron-server openstack-neutron-dhcp-agent openstack-neutron-metadata-agent openstack-neutron-l3-agent openstack-neutron-openvswitch-agent

ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:$PASSWORD@$CTL_MAN_IP/neutron
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:$PASSWORD@$CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$CTL_MAN_IP:5000/v3
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $CTL_MAN_IP:11211
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name Default
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova auth_url http://$CTL_MAN_IP:5000
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova auth_type password
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova project_domain_name default
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova user_domain_name default
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova project_name service
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova username nova
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf nova password $PASSWORD
ssh $CTL_MAN_IP crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers vxlan,flat
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan,flat
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch,baremetal
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security,qos
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 path_mtu 0
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks external
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges 1:1000
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vxlan_group 224.0.0.1
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent tunnel_types vxlan
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent vxlan_udp_port 4789
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent l2_population False
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent drop_flows_on_start False
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-int
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_bridge br-tun
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip $CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings external:br-ex
ssh $CTL_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

ssh $CTL_MAN_IP crudini --set /etc/neutron/l3_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver

ssh $CTL_MAN_IP crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
ssh $CTL_MAN_IP crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
ssh $CTL_MAN_IP crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true

ssh $CTL_MAN_IP crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_host $CTL_MAN_IP
ssh $CTL_MAN_IP crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret $PASSWORD

ssh $CTL_MAN_IP ln -s /etc/apparmor.d/usr.sbin.dnsmasq /etc/apparmor.d/disable/
#ssh $CTL_MAN_IP systemctl restart apparmor
ssh $CTL_MAN_IP systemctl status apparmor
ssh $CTL_MAN_IP systemctl enable openstack-neutron.service openstack-neutron-openvswitch-agent.service openstack-neutron-dhcp-agent.service openstack-neutron-metadata-agent.service openstack-neutron-l3-agent.service
ssh $CTL_MAN_IP systemctl restart openstack-neutron.service openstack-neutron-openvswitch-agent.service openstack-neutron-dhcp-agent.service openstack-neutron-metadata-agent.service openstack-neutron-l3-agent.service
ssh $CTL_MAN_IP systemctl status openstack-neutron.service openstack-neutron-openvswitch-agent.service openstack-neutron-dhcp-agent.service openstack-neutron-metadata-agent.service openstack-neutron-l3-agent.service


ssh $CMP_MAN_IP zypper -n in --no-recommends openvswitch
ssh $CMP_MAN_IP systemctl enable openvswitch
ssh $CMP_MAN_IP systemctl restart openvswitch
ssh $CMP_MAN_IP systemctl status openvswitch

cat << _EOF_ > ./tmp/etc_sysconfig_network_ifcfg_br-ex_cmp
BOOTPROTO='none'
NAME='br-ex'
STARTMODE='auto'
OVS_BRIDGE='yes'
OVS_BRIDGE_PORT_DEVICE='$CMP_EXT_INT'
_EOF_

scp ./tmp/etc_sysconfig_network_ifcfg_br-ex_cmp $CMP_MAN_IP:/etc/sysconfig/network/ifcfg-br-ex

cat << _EOF_ > ./tmp/etc_sysconfig_network_ifcfg_ext_cmp
STARTMODE='auto'
BOOTPROTO='none'
_EOF_

scp ./tmp/etc_sysconfig_network_ifcfg_ext_cmp $CMP_MAN_IP:/etc/sysconfig/network/ifcfg-$CMP_EXT_INT

ssh $CMP_MAN_IP wicked ifup all
ssh $CMP_MAN_IP ip link show
ssh $CMP_MAN_IP ovs-vsctl show

ssh $CMP_MAN_IP zypper -n in --no-recommends openstack-neutron-openvswitch-agent

ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:$PASSWORD@$CTL_MAN_IP
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://$CTL_MAN_IP:5000
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$CTL_MAN_IP:5000/v3
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $CTL_MAN_IP:11211
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name Default
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name Default
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf keystone_authtoken password $PASSWORD
ssh $CMP_MAN_IP crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent tunnel_types vxlan
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent vxlan_udp_port 4789
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent l2_population False
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent drop_flows_on_start False
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-int
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_bridge br-tun
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip $CMP_MAN_IP
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings external:br-ex
ssh $CMP_MAN_IP crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

ssh $CMP_MAN_IP echo "NEUTRON_PLUGIN_CONF="/etc/neutron/plugins/ml2/ml2_conf.ini"" > /etc/sysconfig/neutron

ssh $CMP_MAN_IP systemctl enable openstack-neutron-openvswitch-agent.service
ssh $CMP_MAN_IP systemctl restart openstack-neutron-openvswitch-agent.service
ssh $CMP_MAN_IP systemctl status openstack-neutron-openvswitch-agent.service

openstack extension list --network
openstack network agent list
