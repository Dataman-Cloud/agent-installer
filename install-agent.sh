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
FILES_URL=${FILES_URL:-https://www.shurenyun.com/files}
OMEGA_UUID=${OMEGA_UUID:-$1}
TLS_CERT=false
OMEGA_AGENT_NAME=${OMEGA_AGENT_NAME:-omega-agent}

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

check_netcat()
{
  if command_exists nc; then
    # Do Nothing
    echo
  else
    echo >&2 'Error: omega agent needs nc. You should install nc first.'
    exit 1
  fi
}

check_omega_agent() {
  if ps ax | grep -v grep | grep "omega-agent" > /dev/null
  then
    echo "Omega Agent service running.Stop omega-agent"
    service omega-agent stop > /dev/null 2>&1
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
    "AgentCert":${TLS_CERT}
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
    echo "Docker was not installed or the version is too old"
    case "$(get_distribution_type)" in
      ubuntu|debian)
        sudo apt-get update
        sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
        if ! [ -f /etc/apt/sources.list.d ]; then
          mkdir -p /etc/apt/sources.list.d
        fi
        echo "deb https://get.docker.com/ubuntu docker main" > /etc/apt/sources.list.d/docker.list
        apt-get update -qq -o Dir::Etc::sourceparts="/dev/null" -o APT::List-Cleanup=0 -o Dir::Etc::sourcelist="sources.list.d/docker.list"
        sudo apt-get install -y  aufs-tools lxc-docker
        sudo service docker restart
      ;;
      fedora|centos)
        sudo yum -y -q update
        sudo yum -y install docker
        sudo systemctl start docker.service
        sudo systemctl enable docker.service
      ;;
      *)
        echo "the os is not supported"
      ;;
    esac
  else
    echo "Docker already installed"
  fi
}

do_install()
{
  local curl
  check_host_arch
  check_omega_uuid_exists
  curl=$(check_curl)
  check_netcat
  check_omega_agent

  deploy_docker

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
