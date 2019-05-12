#!/usr/bin/env bash

set -e
set -u
set -o pipefail

declare -A OPTS=(
          ["master-baseurl:"]="Base URL of the master artifactory"
           ["master-userid:"]="Master artifactory userid"
         ["master-password:"]="Master artifactory password"
            ["edge-baseurl:"]="Base URL of the artifactory edge"
             ["edge-userid:"]="Edge artifactory userid"
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
  echo "./setupRepo.sh --master-baseurl 'http://localhost:8081/artifactory' --master-password password --edge-baseurl 'http://localhost:8082/artifactory'"
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

function getRepoJson() {
  local site=$1
  local repoName=$2
  _curl $site api/repositories/${repoName} -XGET 2>/dev/null
}

function getRepoConfigJson() {
  local site=$1
  local configJson=$2
  local isRemote=${3:-false}
  local repoConfigJson=""

  if [[ $isRemote == true ]]; then
    repoConfigJson=$(echo "$configJson" | jq '.remoteRepoConfig? | select (.!=null)')
  fi

  if [[ -z "$repoConfigJson" ]]; then
    repoConfigJson=$(echo "$configJson" | jq '.repoConfig')
  fi
  echo "$repoConfigJson"
}

function createRepo() {
  local site=$1
  local repoName=$2
  local configJson=$3
  local isRemote=${4:-false}

  echo "Creating repo $repoName at $site"
  getRepoConfigJson $site "$configJson" $isRemote | \
    _curl $site api/repositories/${repoName} -X PUT -T -
}

function updateRepo() {
  local site=$1
  local repoName=$2
  local configJson=$3

  echo "Updating repo $repoName at $site"
  echo  "$configJson" | _curl $site api/repositories/${repoName} -X POST -T -
}

function createPullRepoAtMaster() {
  local masterRepoName=$1
  local edgeRepoName=$2
  local configJson=$3

  local edgeUrl="${_EDGE_REPLURL}/${edgeRepoName}"
  local edgeUserid=$(getConfig "edge" userid)
  local edgePassword=$(getConfig "edge" pwd)

  echo "Creating remote repo $masterRepoName at master for $edgeRepoName"
  # Append url, userid and password to config json
  getRepoConfigJson "master" "$configJson" true | \
    jq -Mr \
        --arg edgeUrl "$edgeUrl"  \
        --arg edgeUserid "$edgeUserid"  \
        --arg edgePassword "$edgePassword"  \
        '.rclass = "remote" | .url = $edgeUrl | .username = $edgeUserid | .password = $edgePassword' | \
    _curl "master" api/repositories/${masterRepoName} -X PUT -T -
}

function createPushRepoAtMaster() {
  local masterRepoName=$1
  local configJson=$2

  echo "Creating local repo $masterRepoName for push replication"
  # Delete url and change rclass to local
  getRepoConfigJson "master" "$configJson" true | \
    jq -Mr 'del(.url) | .rclass="local"' | \
    _curl "master" api/repositories/${masterRepoName} -X PUT -T -
}

function isPushReplicationConfigured() {
  local repoName=$1
  if _curl "master" api/replications/${repoName} 2>/dev/null| jq -Mr '.[].url' | grep -qi "$_EDGE_REPLURL"; then
    echo "Push Replication for ${repoName} already exists"
    return 0
  fi
  return 1
}

function createPushReplication() {
  local masterRepoName=$1
  local edgeRepoName=$2
  local edgeUserid=$(getConfig "edge" userid)
  local edgePassword=$(getConfig "edge" pwd)

  echo "Creating PUSH replication between $masterRepoName and $edgeRepoName"

  cat <<EOF | _curl "master" api/replications/${masterRepoName} -X PUT -T -
  [{
      "url": "${_EDGE_REPLURL}/${edgeRepoName}",
      "username": "${edgeUserid}",
      "password": "${edgePassword}",
      "cronExp": "0 0/30 * * * ?",
      "enabled": true,
      "enableEventReplication": true
  }]
EOF

  echo "Successfully created push replication for ${masterRepoName}"
}

function isPullReplicationConfigured() {
  local masterRepoName=$1
  if _curl "master" api/replications/${masterRepoName} 2>/dev/null| grep -q "enabled"; then
    echo "Pull Replication for ${masterRepoName} already exists"
    return 0
  fi
  return 1
}

function createPullReplication() {
  local masterRepoName=$1

  echo "Creating PULL replication $masterRepoName"
  cat <<EOF | _curl "master" api/replications/${masterRepoName} -X PUT -T -
  {
    "enabled": true,
    "cronExp": "0 0/30 * * * ?",
    "syncDeletes": false,
    "syncProperties": false,
    "enableEventReplication": false
  }
EOF

  echo "Successfully created pull replication for ${masterRepoName}"
}

function printJson() {
  local json=$1
  echo "$json" | jq -Cc .
}

function configureLocalRepoAtMaster() {
  local configJson=$1
  local masterRepoName=$(echo "$configJson" | jq -Mr '.repoName' )
  local edgeRepoName=$(echo "$configJson" | jq -Mr '.remoteRepoName? | select (.!=null)' )

  echo
  echo "configureLocalRepoAtMaster: " $(printJson "$configJson")
  echo

  # Create repo at master if required
  if ! isRepoExist "master" $masterRepoName; then
    createRepo "master" $masterRepoName "$configJson"
  fi

  if [[ -z "$edgeRepoName" ]]; then
    echo "configureLocalRepoAtMaster: Edge remote repo not configured. Not required ?"
    return 0
  fi

  # Create repo at edge if required
  if ! isRepoExist "edge" $edgeRepoName; then
    createRepo "edge" $edgeRepoName "$configJson" true
  fi

  # Configure master -> edge push replication
  if ! isPushReplicationConfigured $masterRepoName; then
    createPushReplication $masterRepoName $edgeRepoName
  fi
}

function configureLocalRepoAtEdge() {
  local configJson=$1
  local edgeRepoName=$(echo "$configJson" | jq -Mr '.repoName' )
  local masterRepoName=$(echo "$configJson" | jq -Mr '.remoteRepoName? | select (.!=null)' )

  echo
  echo "configureLocalRepoAtEdge: " $(printJson "$configJson")
  echo

  # Create repo at edge if required
  if ! isRepoExist "edge" $edgeRepoName; then
    createRepo "edge" $edgeRepoName "$configJson"
  fi

  if [[ -z "$masterRepoName" ]]; then
    echo "configureLocalRepoAtEdge: Master remote repo not configured. Not required ?"
    return 0
  fi

  # Create repo at master if required
  if ! isRepoExist "master" $masterRepoName; then

    # Configure edge repo as remote repo and configure pull replication
    # To meet the usecase of all comms need to start at master
    createPullRepoAtMaster $masterRepoName $edgeRepoName "$configJson"
  fi

  if ! isPullReplicationConfigured $masterRepoName; then
    createPullReplication $masterRepoName
  fi
}

function configurRemoteRepoAtMaster() {
  local configJson=$1
  local masterRepoName=$(echo "$configJson" | jq -Mr '.repoName' )
  local edgeRepoName=$(echo "$configJson" | jq -Mr '.remoteRepoName? | select (.!=null)' )

  echo
  echo "configurRemoteRepoAtMaster: " $(printJson "$configJson")
  echo

  # Create repo at master if required
  if ! isRepoExist "master" $masterRepoName; then
    createRepo "master" $masterRepoName "$configJson"
  fi

  if [[ -z "$edgeRepoName" ]]; then
    echo "configurRemoteRepoAtMaster: Edge remote repo not configured. Not required ?"
    return 0
  fi

  # Create a local repo at master to copy artifacts from cache to local repo
  # Local repo will be 'Pushed' to edge
  local masterLocalRepoName="${masterRepoName}-local"

  # Create repo at master if required
  if ! isRepoExist "master" $masterLocalRepoName; then
    createPushRepoAtMaster $masterLocalRepoName "$configJson"
  fi

  # Create repo at edge if required
  if ! isRepoExist "edge" $edgeRepoName; then
    createRepo "edge" $edgeRepoName "$configJson" true
  fi

  # Configure master -> edge push replication
  if ! isPushReplicationConfigured $masterLocalRepoName; then
    createPushReplication $masterLocalRepoName $edgeRepoName
  fi
}

function isRepoAlreadyPresent() {
  local repoConfigJson=$1
  local repoToBeChecked=$2
  local virutalRepo=$3

  local checkStr=$(echo "$repoConfigJson" | \
    jq --arg checkRepo $repoToBeChecked -Mr '.repositories[] | select ( . == $checkRepo )' )
  if  [[ ! -z "$checkStr" ]];  then
    echo "Repo ${repoToBeChecked} already exists in '$virutalRepo' virtual repo"
    return 0
  fi
  return 1
}

function appendRepoToArray() {
  local repoConfigJson=$1
  local repoToBeAdded=$2
  echo "$repoConfigJson" | jq --arg repo $repoToBeAdded -Mr '.repositories += [ $repo ]'
}

function configureVirtualRepo() {
  local configJson=$1
  local site=$(echo "$configJson" | jq -Mr '.site' )
  local repoName=$(echo "$configJson" | jq -Mr '.repoName' )

  local currentRepoConfig=$(getRepoJson $site $repoName)

  if [[ -z "$currentRepoConfig" ]]; then
    # Not there create one now
    createRepo $site $repoName "$configJson"
  else

    # Merge current repositories into existing definition
    local needToUpdate=false
    local toBeConfiguredRepos=( $(echo "$configJson" | jq -Mcr '.repoConfig.repositories | @tsv') )

    for repoToBeConfigured in ${toBeConfiguredRepos[@]}; do
      if ! isRepoAlreadyPresent "$currentRepoConfig" $repoToBeConfigured $repoName; then
        currentRepoConfig=$(appendRepoToArray "$currentRepoConfig" $repoToBeConfigured)
        needToUpdate=true
      fi
    done

    if [[ $needToUpdate == true ]];then
      updateRepo $site $repoName "$currentRepoConfig"
    fi
  fi
}

function applyConfig() {
  local configJson=$1
  local site=$(echo "$configJson" | jq -Mr '.site | ascii_downcase' )
  local repoType=$(echo "$configJson" | jq -Mr '.repoConfig.rclass | ascii_downcase' )
  local repoName=$(echo "$configJson" | jq -Mr '.repoName' )

  echo
  echo "-------------------------------------- $repoName ---------------------------------------------------"
  echo "Repo: $repoName  Site: $site, RepoType: $repoType"
  case "$site-$repoType" in
      master-local) configureLocalRepoAtMaster "$configJson";;
        edge-local) configureLocalRepoAtEdge "$configJson";;
     master-remote) configurRemoteRepoAtMaster "$configJson";;
    master-virtual) configureVirtualRepo "$configJson";;
      edge-virtual) configureVirtualRepo "$configJson";;
                 *) echo "Invalid repoType '$repoType' or site '$site'"; exit 1;;
  esac
}

# Main logic starts here
init

for repoName in $(cat setupRepo.json | jq -Mr '.[].repoName'); do
  applyConfig  "$(cat setupRepo.json | jq -Mr --arg repo $repoName '.[] | select (.repoName == $repo )')"
done

echo "Done"
