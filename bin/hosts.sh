#!/bin/bash
set -e

die() {
  echo "ERROR: $*"
  exit 1
}


help() {
cat << EOF

  Usage is: $0 [-i] [-h] [-r region] [-a <APP> ] [-t <TYPE> ]
    -i info              - print available apps and types in the given region
    -h help              - print this message
    -o output            - output in json|table|text
    -r region            - specify a region, defaults to us-west-2
    -a <APP>             - print type and ip information for <APP>
    -a <APP> -t <TYPE>   - print ip information for <APP> <TYPE> pairs

    <TYPE> is only valid when paired with an <APP>
    Specifying a <TYPE> by itself will produce an error

EOF
  exit 1
}

get_apps() {
  # Don't pull shared stack apps
  set -o pipefail
  ${AWSCLI} \
    --output text \
    --region "${REGION}" \
    ec2 describe-instances \
    --query 'Reservations[].Instances[].[Tags[?Key==`App`]|[0].Value]' \
  | sort -g | uniq | grep -vE "Data-dumper|jenkinsv2|logging|shared"
  unset pipefail
}

get_types() {
  APP=$1
  set -o pipefail
  ${AWSCLI} \
    --output text \
    --region "${REGION}" \
    ec2 describe-instances \
    --query 'Reservations[].Instances[].[Tags[?Key==`Type`]|[0].Value]' \
    --filters "Name=tag:App,Values=${APP}" \
  | sort -g | uniq | grep -vE "rawlogs"
  unset pipefail
}

do_query() {
  if [ $# -ne 2 ]; then
    APP=$1
    FILTER=("Name=tag:App,Values=${APP}")
  else
    APP=$1
    TYPE=$2
    FILTER=("Name=tag:App,Values=${APP}" "Name=tag:Type,Values=${TYPE}")
    fi

  set -o pipefail
  ${AWSCLI} \
    --output "${OUTPUT}" \
    --region "${REGION}" \
    ec2 describe-instances \
    --query 'Reservations[].Instances[].[Tags[?Key==`aws:cloudformation:stack-name`]|[0].Value,PrivateIpAddress]' \
    --filters "${FILTER[@]}" | \
  grep -v None | \
  tr '	' ' ' || exit 1
  unset pipefail
}

display_info() {
  echo "The following apps are available:"
  get_apps
  echo ""
  for i in $(get_apps)
  do
    echo "The following types are available for ${i}:"
    get_types "${i}"
    echo ""
  done
  exit 0
}

if command -v aws > /dev/null 2>&1; then
  AWSCLI=$(command -v aws)
else
   die "awscli couldn't be located"
fi

if [ $# -eq 0 ]; then
  help
fi

while getopts ":a:hio:r:t:" ARGS; do
  case "${ARGS}" in
    "a")
      APP="$OPTARG"
      ;;
    "h")
      help
      ;;
      "i")
      GETINFO="true"
       ;;
    "o")
      if echo "$OPTARG" | grep -Eiq "json|table|text"; then
          OUTPUT_TYPE=$(echo "$OPTARG" | tr "[:upper:]" "[:lower:]")
      else
          die "Invalid output type passed: $OPTARG"
      fi
      ;;
    "r")
      if echo "$OPTARG" | grep -qE '[a-z][a-z]\-[a-z]+\-[0-9]'; then
        #  Make a reasonable effort to match the region name
        REGION="${OPTARG}"
      else
        die "Region must match xx-xxxx-[0-9]"
      fi
      ;;
    "t")
      TYPE="$OPTARG"
      ;;
    "*")
       help
       ;;
  esac
done

OUTPUT="${OUTPUT_TYPE:-table}"
REGION="${REGION:-us-west-2}"

if [ "${GETINFO}" == "true" ]; then
  display_info
fi

if [ -n "$TYPE" ] && [ -z "$APP" ]; then
  die "Can't specify a TYPE without an APP"
fi

if [ -n "$TYPE" ] && [ -n "$APP" ]; then
  do_query "$APP" "$TYPE"
fi

if [ -z "$TYPE" ] && [ -n "$APP" ]; then
  do_query "$APP"
fi
