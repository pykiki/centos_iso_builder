#!/usr/bin/env bash
# Copyright (c) 2018-2019 by Alain Maibach
# Licensed under the terms of the GPL v3

set -eu -o pipefail

err_report() {
  printf "$@\n"

  if [ ${!buildir[@]} ]; then
    rm -rf ${buildir}
  fi
  printf "$0 Cleanly exited\n"
  exit 1
}

expandPath() {
  local path
  local -a pathElements resultPathElements
  IFS=':' read -r -a pathElements <<<"$1"
  : "${pathElements[@]}"
  for path in "${pathElements[@]}"; do
    : "$path"
    case $path in
      "~+"/*)
        path=$PWD/${path#"~+/"}
        ;;
      "~-"/*)
        path=$OLDPWD/${path#"~-/"}
        ;;
      "~"/*)
        path=$HOME/${path#"~/"}
        ;;
      "~"*)
        username=${path%%/*}
        username=${username#"~"}
        IFS=: read _ _ _ _ _ homedir _ < <(getent passwd "$username")
        if [[ $path = */* ]]; then
          path=${homedir}/${path#*/}
        else
          path=$homedir
        fi
        ;;
    esac
    resultPathElements+=( "$path" )
  done
  local result
  printf -v result '%s:' "${resultPathElements[@]}"
  printf '%s\n' "${result%:}"
}

dockerImage="centos:latest"
kickstartName=""

usage (){
    local usage="$0 --kickstart [kickstart name or regex]"
    local options="
    --kickstart       [kickstart name or regex]   --> (Mandatory)                         Define the kickstart filename (or path regex) to use. It must be present in kickstarts directory.
    --dest            [/path/to/tarball/dir/]     --> (optional, default: $HOME/ISO)      Local destination where the tarball will be stored.
    --docker-img      [docker image path]         --> (optional, default: $dockerImage)   Allow you to define which docker image to use for the build.
    --help | -h                                   --> (optional)                          Show this help.
    "
    printf "\n$usage\n$options\n" 2>&1
    exit $1
}

trap 'err_report "Build failed."' ERR

if [ $# -lt 1 ]; then
    usage 1
fi

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SELFDIR="$(cd -P "$(dirname "$SOURCE")" && pwd )"

if [ $UID -eq 0 ]; then
	dest="/root/ISO"
else
	if [ "$HOME" != "" ]; then
			dest="${HOME}/ISO"
	else
		dest="~/ISO"
	fi
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kickstart) kickstartName="${2}"; shift 2;;
    --dest) dest="${2}"; shift 2;;
    --docker-img) dockerImage=${2}; shift 2;;
    --help|-h) usage 0 ; shift 2 ;;
    -*) printf "unknown option: $1\n" >&2 ; usage 1;;
    *) printf "unrecognized argument: $1\n" >&2; usage 1; shift 1;;
  esac
done

if [ "$kickstartName" == "" ]; then
	printf "Missing kickstart file name\n"
	exit 1
fi

if [ ${dest: -1} == "/" ]; then
	dest=${dest::-1}
fi
dest=$(expandPath "$dest")

docker images | grep -q "^${dockerImage}[[:space:]].*$" 2>&1 > /dev/null||true
if [ $? -ne 0 ]; then
    printf "Pulling ${dockerImage}\n"
    docker pull ${dockerImage}
fi

buildir="$(mktemp -d -p ./)"
ls -1 -I $(basename $buildir) $SELFDIR | xargs -I {} cp -r $SELFDIR/{} $buildir/
cd $buildir
buildir="$(pwd)"

if [ ${kickstartName: -4} == ".cfg" ]; then
  kickstartName="$(basename $kickstartName | sed 's/.cfg//')"
fi

numberFound=$(find ${buildir}/kickstarts -type f -iregex ".*$kickstartName.*" |wc -l)
if [ $numberFound -gt 1 ]; then
  printf "\n$numberFound files found:\n\n$(find ${buildir}/kickstarts -type f -iregex ".*$kickstartName.*"|xargs -I {} basename {}|grep -F '.cfg')\n\n"
  read -p 'Please enter the good filename > ' kickstartName
  numberFound=$(find ${buildir}/kickstarts -type f -iregex "$kickstartName$" |wc -l)
  if [ $numberFound -gt 1 ]; then
    printf "\nYou entered a bad filename, exiting...\n"
    rm -fr $buildir
    exit 1
  else
    kickstartpath=$(find ${buildir}/kickstarts -type f -iregex ".*$kickstartName.cfg$")
  fi
else
  kickstartpath=$(find ${buildir}/kickstarts -type f -iregex ".*$kickstartName.cfg$")
fi

if [ ! -f "$kickstartpath" ]; then
  printf "Unable to find file $kickstartName\n"
  rm -fr $buildir
  exit 1
fi

kickstartName="$(basename $kickstartpath | sed 's/.cfg//')"

if [ ! -d $dest ]; then
  mkdir -p $dest
fi

printf "Building ISO\n"

isopath="${dest}/${kickstartName}.iso"

if [ -f "${isopath}" ]; then
  printf "Removing current disc ${isopath}\n"
  rm -f "${isopath}"
fi

# define Docker commands to run
dkcmd="export PATH='/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/bin:/usr/sbin' && mkdir -p /root/builder/ /tmp/isoshare/ /root/.ssh && cd /root/builder/ && mknod /dev/loop0 -m0660 b 7 0 &>/dev/null||true && losetup -f &>/dev/null && /bin/bash -c '/root/builder/scripts/make_iso.sh --kickstart \$KICKNAME'"

# run container with privileges to be able to attach a loop device
docker run --privileged=true -e "KICKNAME=${kickstartName}" -v ${dest}/:/tmp/isoshare/ -v "$buildir/":/root/builder/ --rm --name miniso_builder -i ${dockerImage} bash -c "$dkcmd"

rm -fr $buildir

printf "Your iso has been generated in ${isopath}\n"
