#!/bin/sh
set -e
#
# Usage:
# curl -Ls https://$DM_HOST/install.sh | sudo -H sh -s [OmegaUUID] [iface_name]
#

export DEBIAN_FRONTEND=noninteractive
DOCKER_HOST=${DOCKER_HOST:-unix:///var/run/docker.sock}
DM_HOST=${DM_HOST:-wss://streaming.shurenyun.com/}
SUPPORT_URL=https://www.shurenyun.com
FILES_URL=${FILES_URL:-http://agent.shurenyun.com/packages}
REGISTRY_URL=${REGISTRY_URL:-registry.shurenyun.com}
OMEGA_UUID=${OMEGA_UUID:-$1}
TLS_CERT=false
OMEGA_ENV=${OMEGA_ENV:-prod}
OMEGA_AGENT_VERSION=`curl -Ls https://www.shurenyun.com/version/$OMEGA_ENV-omega-agent`
OMEGA_AGENT_NAME="omega-agent-$OMEGA_AGENT_VERSION"
EN_NAME=${EN_NAME:-eth0}
OMEGA_PORTS=${OMEGA_PORTS:-5050 8080}

# if iface name provided for this installation process, with -i option #TODO
# suppose #2 option is the default iface name
if [ ! -z "$2" ]; then EN_NAME="$2"; fi

check_host_arch()
{
  echo "-> Checking host arch ..."
  if [ "$(uname -m)" != "x86_64" ]; then
    cat <<EOF
ERROR: Unsupported architecture: $(uname -m)
Only x86_64 architectures are supported at this time
Learn more: https://dataman.kf5.com/posts/view/110837/
EOF
    exit 1
  fi
}

check_omega_uuid_exists()
{
  echo "-> Making sure Omega UUID exists ..."
  if [ -z "$OMEGA_UUID" ]
  then
      printf "\033[41mERROR:\033[0m you should install omega-agent with OmegaUUID, like:\n"
      echo 'curl -sSL https://dev.dataman.io/install.sh | sh -s [OmegaUUID]'
      exit 1
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
     curl='curl --retry 20 --retry-delay 5 -L -s'
  else
      echo >&2 -e "\033[41mERROR:\033[0m: this installer needs curl. You should install curl first."
      exit 1
  fi
  echo $curl
}

check_omega_agent() {
  echo "-> Checking old version omega agent exists ... "
  if ps ax | grep -v grep | grep "omega-agent" > /dev/null
    then
      printf "\033[41mWraning:\033[0m Continue installation will overwrite the original version\n"
      install_wait=11
          while true
          do
             if [ $install_wait -eq 1 ]
                  then
                  service omega-agent stop > /dev/null 2>&1
                  break
             fi
             install_wait=`expr $install_wait - 1`
             printf "\rNew omega-agent will install in \033[1m ${install_wait} \033[0m seconds"
             sleep 1s
          done
          printf "\n"
  fi
}

check_iptables() {
   echo "-> Checking iptables open..."
   if command_exists iptables; then
          if sudo iptables -L | grep "DOCKER" > /dev/null; then
            true
          else
                  printf "\033[41mERROR:\033[0m Please make sure your iptables nat is open\n"
                  echo "Learn more: https://dataman.kf5.com/posts/view/124302/"
                  exit 1
          fi
  else
         printf "\033[41mERROR:\033[0m Command iptables does not exists\n"
         exit 1
  fi
}

check_selinux() {
  echo "-> Checking selinux by command getenforce..."
  if command_exists getenforce; then
        if getenforce | grep "Disabled" > /dev/null; then
          true
        else
              printf "\033[41mERROR:\033[0m to make this installation proceeding, please make sure selinux disabled\n"
              echo "Learn more: https://dataman.kf5.com/posts/view/124303/"
        exit 1
        fi
  else 
        printf "\033[41mERROR:\033[0m Command \033[1mgetenforce\033[0m not found\n"
        exit 1
  fi 
}

check_omega_ports(){
  echo "-> Checking OMEGA ports [${OMEGA_PORTS}] are available or not..."
  if command_exists netstat; then
    for port in ${OMEGA_PORTS}; do
      if netstat -lant | grep ${port} | grep LISTEN  >/dev/null 2>&1 ; then
        printf "\033[41mERORR:\033[0m port ${port} listening already, which supposed to be reverved for omega.\n"
        exit 1
      fi
    done
  else
    printf "\033[41mERROR\033[0m Command \033[1mnetstat\033[0m does not exists\n"
    exit 1
  fi
}

select_iface()
{
    echo "-> Network interface selection... "
    # ping registry.shurenyun.com
    if ping -q -c 1 -W 1 $REGISTRY_URL >/dev/null; then
      true
    else
        printf "\033[41mERROR:\033[0m The network can not connect to $REGISTRY_URL\n"
        echo "Please check your network"
        exit 1
    fi
    remaining_count=10
    while [ ${remaining_count} -gt 0 ]; do
      printf "\r\033[41mINFO:\033[0m We will use defalut network interface \033[1m${EN_NAME}\033[0m in \033[1m ${remaining_count} \033[0m seconds. Do you want to use another iface \033[41;1m[Y/N](enter)\033[0m"
      if read -t 1 change_ifcae
      then
        printf "\n"
        case $change_ifcae in
          Y|y|YES|yes)
            while true; do
              echo "Please input iface name from the following list: "
              for iface in `ls /sys/class/net/`; do
                printf "\033[1m${iface}\033[0m\n"
              done

              read -p "iface(enter):" iface
              check_cmd="ls /sys/class/net/${iface}"
              if ${check_cmd} > /dev/null 2>&1
              then
                EN_NAME=$iface
                break
              else
                printf "\033[41mERROR:\033[0m Network interface ${iface} not found\n"
              fi
            done
            ;;
          N|n|NO|no)
            echo "Network interface use default ${EN_NAME}"
            ;;
        esac
        break
      fi
      remaining_count=$((remaining_count-1))
    done
    printf "\n"
}

check_iface_exist()
{
  check_cmd="ls /sys/class/net/${EN_NAME}"
  if ! ${check_cmd} > /dev/null 2>&1 ;
  then
    printf "\033[41mERROR:\033[0m Network interface ${EN_NAME} not found\n"
    exit 1
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
  echo "-> Starting omega-agent..."
  service omega-agent restart #> /dev/null 2>&1
  echo "-> Done..."
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
    printf "\033[41mERROR:\033[0m  Docker was not installed or the version is too old"
    echo "Learn more: https://dataman.kf5.com/posts/view/110837/"
    echo "********************************************************"
    exit 1
  fi

  check_docker
}

check_docker() {
  echo "-> Checking wether docker service started or not..."
  if ps ax | grep -v grep | grep "docker " > /dev/null
  then
    true
  else
    printf "\033[41mERROR:\033[0m Docker is not running now. Please start docker.\n"
    exit 1
  fi
}

lsb_version=""
do_install()
{
  local curl
  check_host_arch
  check_omega_uuid_exists
  curl=$(check_curl)
  check_omega_agent

  deploy_docker
  select_iface
  check_iface_exist
  check_iptables
  check_omega_ports

  case "$(get_distribution_type)" in
    gentoo|boot2docker|amzn|linuxmint)
      (
      echo "-> it's unsupported by omega-agent "
      echo "Learn more: https://dataman.kf5.com/posts/view/110837/"
      )
      exit 1
      ;;
    fedora|centos|rhel)
      (
      check_selinux
      if [ -r /etc/os-release ]; then
        lsb_version="$(. /etc/os-release && echo "$VERSION_ID")"
        if [ $lsb_version '<' 7 ]
        then
          printf "\033[41mERROR:\033[0m CentOS version is Unsupported\n"
          echo "Learn more: https://dataman.kf5.com/posts/view/110837/"
          exit 1
        fi
      else
        printf "\033[41mERROR:\033[0m CentOS version is Unsupported\n"
        echo "Learn more: https://dataman.kf5.com/posts/view/110837/"
        exit 1
      fi
      echo "-> Downloading omega-agent from ${FILES_URL}/${OMEGA_AGENT_NAME}.x86_64.rpm..."
      $curl -o /tmp/${OMEGA_AGENT_NAME}.x86_64.rpm ${FILES_URL}/${OMEGA_AGENT_NAME}.x86_64.rpm
      if command_exists /usr/bin/omega-agent; then
        echo "-> Removing old version omega-agent..."
        yum remove -y -q omega-agent
      fi
      echo "-> Installing omega-agent..."
      yum install -y -q /tmp/${OMEGA_AGENT_NAME}.x86_64.rpm

      start_omega_agent
      )
      exit 0
      ;;
    ubuntu|debian)
      (
      echo "-> Downloading omega-agent from ${FILES_URL}/${OMEGA_AGENT_NAME}_amd64.deb..."
      $curl -o /tmp/${OMEGA_AGENT_NAME}_amd64.deb ${FILES_URL}/${OMEGA_AGENT_NAME}_amd64.deb

      echo "-> Installing omega-agent..."
      dpkg -i /tmp/${OMEGA_AGENT_NAME}_amd64.deb > /dev/null 2>&1

      start_omega_agent
      )
      exit 0
      ;;
    *)
      printf "\033[41mERROR\033[0m Unknown Operating System\n"
      echo "Learn more: https://dataman.kf5.com/posts/view/110837/"
      ;;
  esac
}

  # wrapped up in a function so that we have some protection against only getting
  # half the file during "curl | sh"
  do_install
