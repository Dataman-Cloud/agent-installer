#!/bin/sh
set -e
#
# Usage:
# curl -Ls https://$DM_HOST/install.sh | sudo -H sh -s [OmegaUUID]
#

export DEBIAN_FRONTEND=noninteractive
DOCKER_HOST=${DOCKER_HOST:-unix:///var/run/docker.sock}
DM_HOST=${DM_HOST:-wss://streaming.shurenyun.com/}
SUPPORT_URL=https://www.shurenyun.com
FILES_URL=${FILES_URL:-http://agent.shurenyun.com/packages}
OMEGA_UUID=${OMEGA_UUID:-$1}
TLS_CERT=false
OMEGA_ENV=${OMEGA_ENV:-prod}
OMEGA_AGENT_VERSION=`curl -Ls https://www.shurenyun.com/version/$OMEGA_ENV-omega-agent`
OMEGA_AGENT_NAME="omega-agent-$OMEGA_AGENT_VERSION"
EN_NAME=${EN_NAME:-eth0}

check_host_arch()
{
  if [ "$(uname -m)" != "x86_64" ]; then
    cat <<EOF
ERROR: Unsupported architecture: $(uname -m)
Only x86_64 architectures are supported at this time
Learn more: $SUPPORT_URL
EOF
    exit 1
  fi
}

check_omega_uuid_exists()
{
  if [ -z "$OMEGA_UUID" ]
  then
      echo 'ERROR: you should install omega-agent with OmegaUUID, like:'
      echo 'curl -sSL https://dev.dataman.io/install.sh | sh -s [OmegaUUID]'
      exit 0
  fi
}

command_exists() {
  command -v "$@" > /dev/null 2>&1
}

check_curl()
{
  local curl
  curl=''
  if command_exists curl; then
     curl='curl --retry 20 --retry-delay 5 -L'
  else
      echo >&2 'Error: this installer needs curl. You should install curl first.'
      exit 1
  fi
  echo $curl
}

check_omega_agent() {
  if ps ax | grep -v grep | grep "omega-agent" > /dev/null
    then
      echo "Omega Agent service is running now... "
      echo "Wraning!!! Continue installation will overwrite the original version"
      install_wait=11
          while true 
          do
             if [ $install_wait -eq 1 ]
                  then
                  service omega-agent stop > /dev/null 2>&1
                  break
             fi
             install_wait=`expr $install_wait - 1`
             echo "new omega-agent will install after ${install_wait}s" 
             sleep 1s
          done
  fi
}

select_iface()
{
    # check ping registry.shurenyun.com
    if ping -q -c 1 -W 1 registry.shurenyun.com >/dev/null; then
        echo "The network to connect registry.shurenyun.com is good "
    else
        echo "ERROR!!! The network is can not connect to registry.shurenyun.com"
        echo "Please check your network"
        exit 0
    fi

    echo "Omega-agent use default network interface is eth0."
    echo "Do you want to change it? [Y/N]"
    echo "Warnning!!! We will use defalut network interface after 5 second"
    if read -t 5 change_ifcae 
        then
        case $change_ifcae  in 
            Y|y|YES|yes)
            while true; do 
                echo "Please choose network interface from below list: "
                echo `ls /sys/class/net/`
                read iface
                check_cmd="ls /sys/class/net/${iface}"
                if ${check_cmd} > /dev/null
                    then
                    EN_NAME=$iface
                    break
                else
                    echo "Network interface ${iface} not find"
                fi
            done
            ;;
            N|n|NO|no|*)
                echo "Network interface use default eth0"
            ;;
        esac
    else 
        echo "Network interface use default eth0"
    fi
}


get_distribution_type()
{
  local lsb_dist
  lsb_dist=''
  if command_exists lsb_release; then
    lsb_dist="$(lsb_release -si)"
  fi
  if [ -z "$lsb_dist" ] && [ -r /etc/lsb-release ]; then
    lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
  fi
  if [ -z "$lsb_dist" ] && [ -r /etc/debian_version ]; then
    lsb_dist='debian'
  fi
  if [ -z "$lsb_dist" ] && [ -r /etc/fedora-release ]; then
    lsb_dist='fedora'
  fi
  if [ -z "$lsb_dist" ] && [ -r /etc/os-release ]; then
    lsb_dist="$(. /etc/os-release && echo "$ID")"
  fi
  if [ -z "$lsb_dist" ] && [ -r /etc/centos-release ]; then
    lsb_dist="$(cat /etc/*-release | head -n1 | cut -d " " -f1)"
  fi
  if [ -z "$lsb_dist" ] && [ -r /etc/redhat-release ]; then
    lsb_dist="$(cat /etc/*-release | head -n1 | cut -d " " -f1)"
  fi
  lsb_dist="$(echo $lsb_dist | cut -d " " -f1)"
  lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
  echo $lsb_dist
}

start_omega_agent() {
  echo "-> Configuring omega-agent..."
  mkdir -p /etc/omega/agent
  cat > /etc/omega/agent/omega-agent.conf <<EOF
  {
    "DockerHost":"${DOCKER_HOST}",
    "OmegaHost":"${DM_HOST}",
    "OmegaUUID":"${OMEGA_UUID}",
    "AgentCert":${TLS_CERT},
    "Version":"${OMEGA_AGENT_VERSION}",
    "EnName":"${EN_NAME}"
  }
EOF
 cat > /etc/omega/agent/uninstall.sh <<EOF
  service omega-agent stop
EOF
  service omega-agent restart > /dev/null 2>&1
  echo "-> Done!"
  cat <<EOF

  *******************************************************************************
  Omega Agent installed successfully
  *******************************************************************************

  You can view omega-agent log at /var/log/omega/agent.log
  And You can Start or Stop omega-agent with: service omega-agent start/stop/restart/status

EOF
}

deploy_docker() {
  echo "-> Deploying Docker Runtime Environment..."
  if [ -z "$(which docker)" ]  || [ $(docker -v | awk -F ',' '{print $1}'| awk '{print $3}') \< "1.5.0" ]; then
    echo "********************************************************"
    echo "ERROR!!!!  Docker was not installed or the version is too old"
    echo "********************************************************"
    exit 0 
  fi

  check_docker

}

check_docker() {
  if ps ax | grep -v grep | grep "docker " > /dev/null
  then
      echo "Docker service is running now......."
  else
      echo "ERROR!!!! Docker is not running now. Please start docker."
      exit 0
  fi
}

do_install()
{
  local curl
  check_host_arch
  check_omega_uuid_exists
  curl=$(check_curl)
  check_omega_agent

  deploy_docker
  select_iface

  case "$(get_distribution_type)" in
    gentoo|boot2docker|amzn|linuxmint)
    (
      echo "-> it's unsupported by omega-agent "
      echo "Learn more: $SUPPORT_URL"
    )
    exit 1
    ;;
    fedora|centos)
    (
    echo "-> Installing omega-agent..."
    echo "-> Downloading omega-agent from ${FILES_URL}/${OMEGA_AGENT_NAME}.x86_64.rpm"
    $curl -o /tmp/${OMEGA_AGENT_NAME}.x86_64.rpm ${FILES_URL}/${OMEGA_AGENT_NAME}.x86_64.rpm
    if command_exists /usr/bin/omega-agent; then
      yum remove -y -q omega-agent
    fi
    yum install -y -q /tmp/${OMEGA_AGENT_NAME}.x86_64.rpm

    start_omega_agent
    )
    exit 0
    ;;
    ubuntu|debian)
    (
      echo "-> Installing omega-agent..."
      echo "-> Downloading omega-agent from ${FILES_URL}/${OMEGA_AGENT_NAME}_amd64.deb"
      $curl -o /tmp/${OMEGA_AGENT_NAME}_amd64.deb ${FILES_URL}/${OMEGA_AGENT_NAME}_amd64.deb
      dpkg -i /tmp/${OMEGA_AGENT_NAME}_amd64.deb

      start_omega_agent
    )
    exit 0
    ;;
  esac
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
do_install
