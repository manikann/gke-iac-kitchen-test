#!/usr/bin/env bash

set -e
set -u
set -o pipefail

declare -A OPTS=(
          ["master-baseurl:"]="Base URL of the master artifactory"
         ["master-useridid:"]="Master artifactory userid"
         ["master-password:"]="Master artifactory password"
            ["edge-baseurl:"]="Base URL of the artifactory edge"
           ["edge-useridid:"]="Edge artifactory userid"
           ["edge-password:"]="Edge artifactory password"
      )

# CLI parameters are
_MASTER_BASEURL=""
_MASTER_USERID=""
_MASTER_PWD=""
_EDGE_BASEURL=""
_EDGE_USERID=""
_EDGE_PWD=""
MASTER_ACCESS_TOKEN=""
EDGE_ACCESS_TOKEN=""

function usage() {
  echo
  echo "usage $(basename $0)"
  for opt in "${!OPTS[@]}"; do
    local pname=$(echo "$opt" | tr -d ':')
    printf "  %-30s %s\n" "--${pname}" "${OPTS[$opt]}"
  done
  echo
  echo "example"
  echo "./setupRepo.sh --name jcenter --remote-url 'https://jcenter.bintray.com' --master-baseurl 'http://localhost:8081/artifactory' --master-password 'Welcome!23' --edge-baseurl 'http://localhost:8082/artifactory'"
  exit 1
}

function parseArguments() {
  LONG_OPTS=$(echo "${!OPTS[@]}" | tr ' ' ',')

  # Process command line arguments
  TEMP=$(getopt -o h --long $LONG_OPTS -n 'setupRepo.sh' -- "$@")
  if [ $? != 0 ] ; then
     echo "Terminating..." >&2
     exit 2
  fi

  # Note the quotes around `$TEMP': they are essential!
  eval set -- "$TEMP"

  while true ; do
    case "$1" in
                --master-baseurl) _MASTER_BASEURL=$2; shift 2;;
                 --master-userid) _MASTER_USERID=$2; shift 2;;
               --master-password) _MASTER_PWD=$2; shift 2;;
                  --edge-baseurl) _EDGE_BASEURL=$2; shift 2;;
                   --edge-userid) _EDGE_USERID=$2; shift 2;;
                 --edge-password) _EDGE_PWD=$2; shift 2;;
                              --) shift ; break ;;
                               *) echo "Internal error!" ; usage ;;
    esac
  done
}

# Parse the input arguments
parseArguments $@

# Defaults
[[ -z "$_MASTER_USERID" ]] && _MASTER_USERID="admin"
[[ -z "$_EDGE_USERID" ]] && _EDGE_USERID="admin"
[[ -z "$_EDGE_PWD" ]] && _EDGE_PWD=${_MASTER_PWD}

# Validate mandatory input
[[ -z "$_MASTER_BASEURL" || \
   -z "$_MASTER_PWD" || \
   -z "$_EDGE_BASEURL" ]] && usage

declare -A CONFIG_MAP

function getAccessToken() {
  local baseurl=$1
  local user=$2
  local pwd=$3
  curl -ksf -H 'Accept: application/json' -XPOST ${baseurl}/api/security/token \
        -u "${user}:${pwd}" \
        -d "username=${user}"  \
        -d 'scope=member-of-groups:*' \
        -d 'expires_in=300' \
    | jq -Mr '.access_token'
}

function init() {
  CONFIG_MAP["master.baseurl"]=$_MASTER_BASEURL
  CONFIG_MAP["master.userid"]=$_MASTER_USERID
  CONFIG_MAP["master.pwd"]=$_MASTER_PWD
  CONFIG_MAP["master.token"]=$(getAccessToken $_MASTER_BASEURL $_MASTER_USERID $_MASTER_PWD)

  CONFIG_MAP["edge.baseurl"]=$_EDGE_BASEURL
  CONFIG_MAP["edge.userid"]=$_EDGE_USERID
  CONFIG_MAP["edge.pwd"]=$_EDGE_PWD
  CONFIG_MAP["edge.token"]=$(getAccessToken $_EDGE_BASEURL $_EDGE_USERID $_EDGE_PWD)
}

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function getConfig() {
  local site=$1
  local config=$2
  local mapKey="${site}.${config}"
  echo "${CONFIG_MAP[$mapKey]}"
}

function _curl() {
  local site=$1
  local uri=$2
  shift 2
  local token=$(getConfig $site token)
  local baseurl=$(getConfig $site baseurl)
  set -x
  curl -ksSLf -v \
       -H 'Content-Type: application/json' \
       -H "Authorization: Bearer ${token}" \
       ${baseurl}/${uri} \
       $@
}

function isRepoExist() {
  local site=$1
  local repoName=$2
  local repoJson=$(_curl $site api/repositories/${repoName} -XGET 2>/dev/null)
  if [[ ! -z "$repoJson" ]]; then
    echo "repo ${repoName} already exists at ${site}"
    return 0
  fi
  return 1
}

function createRepo() {
  local site=$1
  local repoName=$2
  local repoConfigJson=$3

  local dataFile=$(tempFile repo-config-json)
  echo "$repoConfigJson" > $dataFile
  cp $dataFile /tmp/config.json
  _curl $site api/repositories/${repoName} -X PUT -T $dataFile
}

function applyConfig() {
  local configJson=$1
  local site=$(echo "$configJson" | jq -Mr '.site' )
  local repoName=$(echo "$configJson" | jq -Mr '.repoName' )
  local repoType=$(echo "$configJson" | jq -Mr '.repoType' )
  local remoteRepoName=$(echo "$configJson" | jq -Mr '.remoteRepoName' )
  local repoConfigJson=$(echo "$configJson" | jq '.repoConfig + {key: .repoName, rclass: .repoType}')

  if ! isRepoExist $site $repoName; then
    createRepo $site $repoName "$repoConfigJson"
  fi
}

init

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/setup.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

for repoName in $(cat setupRepo.json | jq -Mr '.[].repoName'); do
  applyConfig  "$(cat setupRepo.json | jq -Mr --arg repo $repoName '.[] | select (.repoName == $repo )')"
done
echo "Done"
