#!/bin/bash

source os.conf
[ -d ./tmp ] || mkdir ./tmp



##### Host Maping #####

cat << _EOF_ > ./tmp/hosts
#
# hosts         This file describes a number of hostname-to-address
#               mappings for the TCP/IP subsystem.  It is mostly
#               used at boot time, when no name servers are running.
#               On small systems, this file can be used instead of a
#               "named" name server.
# Syntax:
#
# IP-Address  Full-Qualified-Hostname  Short-Hostname
#

127.0.0.1	localhost

# special IPv6 addresses
::1             localhost ipv6-localhost ipv6-loopback

fe00::0         ipv6-localnet

ff00::0         ipv6-mcastprefix
ff02::1         ipv6-allnodes
ff02::2         ipv6-allrouters
ff02::3         ipv6-allhosts

$CTL_MAN_IP $CTL_HOSTNAME
$CMP_MAN_IP $CMP_HOSTNAME
$BMT_MAN_IP $BMT_HOSTNAME
_EOF_

scp ./tmp/hosts $CTL_MAN_IP:/etc/hosts
scp ./tmp/hosts $CMP_MAN_IP:/etc/hosts
scp ./tmp/hosts $BMT_MAN_IP:/etc/hosts



##### NTP Service #####

ssh $CTL_MAN_IP zypper -n in --no-recommends chrony
ssh $CTL_MAN_IP systemctl enable chronyd.service
ssh $CTL_MAN_IP systemctl restart chronyd.service
ssh $CTL_MAN_IP systemctl status chronyd.service
ssh $CTL_MAN_IP chronyc sources
ssh $CMP_MAN_IP zypper -n in --no-recommends chrony
ssh $CMP_MAN_IP systemctl enable chronyd.service
ssh $CMP_MAN_IP systemctl restart chronyd.service
ssh $CMP_MAN_IP systemctl status chronyd.service
ssh $CMP_MAN_IP chronyc sources
ssh $BMT_MAN_IP zypper -n in --no-recommends chrony
ssh $BMT_MAN_IP systemctl enable chronyd.service
ssh $BMT_MAN_IP systemctl restart chronyd.service
ssh $BMT_MAN_IP systemctl status chronyd.service
ssh $BMT_MAN_IP chronyc sources



##### OpenStack Packages #####

ssh $CTL_MAN_IP zypper addrepo -f obs://Cloud:OpenStack:Rocky/openSUSE_Leap_15.1 Rocky
ssh $CTL_MAN_IP zypper --gpg-auto-import-keys ref && zypper -n dup
ssh $CTL_MAN_IP zypper -n in --no-recommends python-openstackclient
ssh $CMP_MAN_IP zypper addrepo -f obs://Cloud:OpenStack:Rocky/openSUSE_Leap_15.1 Rocky
ssh $CMP_MAN_IP zypper --gpg-auto-import-keys ref && zypper -n dup
ssh $CMP_MAN_IP zypper -n in --no-recommends python-openstackclient
ssh $BMT_MAN_IP zypper addrepo -f obs://Cloud:OpenStack:Rocky/openSUSE_Leap_15.1 Rocky
ssh $BMT_MAN_IP zypper --gpg-auto-import-keys ref && zypper -n dup
ssh $BMT_MAN_IP zypper -n in --no-recommends python-openstackclient



##### MariaDB Service #####

ssh $CTL_MAN_IP zypper -n in --no-recommends mariadb-client mariadb python-PyMySQL

if ssh $CTL_MAN_IP [ ! -f /etc/my.cnf.d/openstack.cnf ]
  then
cat << _EOF_ > ./tmp/openstack.cnf
[mysqld]
bind-address = $CTL_MAN_IP
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
_EOF_
  scp ./tmp/openstack.cnf $CTL_MAN_IP:/etc/my.cnf.d/openstack.cnf
  ssh $CTL_MAN_IP systemctl enable mariadb.service
  ssh $CTL_MAN_IP systemctl restart mariadb.service
  ssh $CTL_MAN_IP systemctl status mariadb.service
cat << _EOF_ > ./tmp/mysql_secure_installation
mysql -e "UPDATE mysql.user SET Password=PASSWORD('$PASSWORD') WHERE User='root';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"
mysql -e "FLUSH PRIVILEGES;"
_EOF_
  ssh $CTL_MAN_IP < ./tmp/mysql_secure_installation
fi



##### RabbitMQ Service #####

ssh $CTL_MAN_IP zypper -n in --no-recommends rabbitmq-server
ssh $CTL_MAN_IP systemctl enable rabbitmq-server.service
ssh $CTL_MAN_IP systemctl restart rabbitmq-server.service
ssh $CTL_MAN_IP systemctl status rabbitmq-server.service
ssh $CTL_MAN_IP rabbitmqctl add_user openstack $PASSWORD
ssh $CTL_MAN_IP rabbitmqctl set_permissions openstack \".*\" \".*\" \".*\"



##### Memcached Service #####

ssh $CTL_MAN_IP zypper -n in --no-recommends memcached python-python-memcached
cat << _EOF_ > ./tmp/etc_sysconfig_memcached
sed -i 's/MEMCACHED_PARAMS="-l 127.0.0.1"/MEMCACHED_PARAMS="-l $CTL_MAN_IP"/g' /etc/sysconfig/memcached
_EOF_
ssh $CTL_MAN_IP < ./tmp/etc_sysconfig_memcached
ssh $CTL_MAN_IP systemctl enable memcached.service
ssh $CTL_MAN_IP systemctl restart memcached.service
ssh $CTL_MAN_IP systemctl status memcached.service



##### Etcd Service #####

ssh $CTL_MAN_IP zypper addrepo -f obs://devel:kubic/openSUSE_Leap_15.1 kubic
ssh $CTL_MAN_IP zypper --gpg-auto-import-keys ref
ssh $CTL_MAN_IP zypper -n in --no-recommends etcd
ssh $CTL_MAN_IP cp /etc/sysconfig/etcd /etc/sysconfig/etcd.orig
cat << _EOF_ > ./tmp/etc_sysconfig_etcd
ETCD_NAME=$CTL_HOSTNAME
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://$CTL_MAN_IP:2379"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="$CTL_HOSTNAME=http://$CTL_MAN_IP:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$CTL_MAN_IP:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://$CTL_MAN_IP:2379"
_EOF_
scp ./tmp/etc_sysconfig_etcd $CTL_MAN_IP:/etc/sysconfig/etcd
ssh $CTL_MAN_IP systemctl enable etcd.service
ssh $CTL_MAN_IP systemctl restart etcd.service
ssh $CTL_MAN_IP systemctl status etcd.service
