#!/usr/bin/env bash
#Rsyslog client configuration!
set -e

[ -d /etc/rsyslog.d ] || { echo No found rsyslog && exit; }

flog_conf=/etc/rsyslog.d/forward_flog.conf
flog_server=${SYSLOG_SERVER:-log.logserver.ip}
if [ -n "$SYSLOG_PORT" ];then
  flog_port=$SYSLOG_PORT
else
  if [ "$RAILS_ENV" = 'staging' ];then
    # 将测试环境的和正式的区分开
    flog_port=1524
  else
    flog_port=1514
  fi
fi
flog_facility=${SYSLOG_FACILITY:-local0}

mv /etc/rsyslog.d /etc/rsyslog.d.bak
mkdir -p /etc/rsyslog.d

# use tcp protocol
rule="$flog_facility.*  @@$flog_server:$flog_port"
echo $rule > $flog_conf
echo config rsyslog: update rule $rule into $flog_conf

service rsyslog start
echo ==rsyslog has started
