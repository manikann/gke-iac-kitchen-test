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
            ["edge-replurl:"]="Base URL of the artifactory edge for replication"
      )

# CLI parameters are
_MASTER_BASEURL=""
_MASTER_USERID=""
_MASTER_PWD=""
_EDGE_BASEURL=""
_EDGE_REPLURL=""
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
  echo "./setupRepo.sh --master-baseurl 'http://localhost:8081/artifactory' --master-password 'Welcome!23' --edge-baseurl 'http://localhost:8082/artifactory'"
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
                  --edge-replurl) _EDGE_REPLURL=$2; shift 2;;
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
[[ -z "$_EDGE_REPLURL" ]] && _EDGE_REPLURL=${_EDGE_BASEURL}

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
  curl -ksSLf \
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
    echo "Repo ${repoName} already exists at ${site}"
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
  _curl $site api/repositories/${repoName} -X PUT -T $dataFile
}

function isReplicationConfigured() {
  local site=$1
  local repoName=$2
  if _curl $site api/replications/${repoName} 2>/dev/null| jq -Mr '.[].url' | grep -qi "$_EDGE_REPLURL"; then
    echo "Replication for ${repoName} already exists at ${site}"
    return 0
  fi
  return 1
}

function createPushReplication() {
  local site=$1
  local repoName=$2
  local remoteSite=$3
  local remoteRepoName=$4
  local remoteUserid=$(getConfig $remoteSite userid)
  local remotePassword=$(getConfig $remoteSite pwd)

  local dataFile=$(tempFile replication.config)
  cat <<EOF  > $dataFile
  [
    {
      "url": "${_EDGE_REPLURL}/${remoteRepoName}",
      "username": "${remoteUserid}",
      "password": "${remotePassword}",
      "repoKey": "${repoName}",
      "cronExp": "0 0/15 * * * ?",
      "enabled": true,
      "enableEventReplication": true
    }
  ]
EOF
  _curl $site api/replications/${repoName} -X PUT -T $dataFile
  echo "Successfully created replication for ${repoName}"
}

function applyConfig() {
  local configJson=$1
  local site=$(echo "$configJson" | jq -Mr '.site' )
  local repoName=$(echo "$configJson" | jq -Mr '.repoName' )
  local repoType=$(echo "$configJson" | jq -Mr '.repoType' )
  local remoteRepoName=$(echo "$configJson" | jq -Mr '.remoteRepoName? | select (.!=null)' )
  #local repoConfigJson=$(echo "$configJson" | jq '.repoConfig + {key: .repoName, rclass: .repoType}')
  local repoConfigJson=$(echo "$configJson" | jq '.repoConfig + {rclass: .repoType}')


  echo
  echo "About to configure $repoName ($repoType) at $site"

  if ! isRepoExist $site $repoName; then
    createRepo $site $repoName "$repoConfigJson"
  fi

  if echo "$repoType" | grep -iq "remote"; then
    [[ ! -z "$remoteRepoName" ]] && echo "Remote repo can have remote replication. Ignored  $remoteRepoName"
    return 0
  fi

  if [[ -z "$remoteRepoName" ]]; then
    echo "Remote repo not configured. Not required ?"
    return 0
  fi

  if isReplicationConfigured $site $repoName; then
    return 0
  fi

  local remoteSite="edge"
  if [[ "$site" == "edge" ]]; then
    remoteSite="master"
  fi

  if ! isRepoExist $remoteSite $remoteRepoName; then
    createRepo $remoteSite $remoteRepoName "$repoConfigJson"
  fi

  createPushReplication $site $repoName $remoteSite $remoteRepoName
}

init

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/setup.XXXX)
trap "rm -rf $MYTMPDIR" EXIT

for repoName in $(cat setupRepo.json | jq -Mr '.[].repoName'); do
  applyConfig  "$(cat setupRepo.json | jq -Mr --arg repo $repoName '.[] | select (.repoName == $repo )')"
done
echo "Done"
