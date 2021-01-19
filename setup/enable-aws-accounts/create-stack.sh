#!/bin/bash
#
# Copyright 2020 Appvia Ltd <info@appvia.io>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -o errexit
set -o nounset
set -o pipefail

log()   { (2>/dev/null echo -e "$@"); }
info()  { if [[ ! -z ${QUIET:-} ]]; then return 0; fi; log "[info]  $@"; }
error() { echo "[error] $@" 1>&2; exit 1; }

[[ ${DEBUG:-} == 'true' ]] && set -x

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

shortusage() {
cat <<EOFSH
  --s3-bucket         bucket name to upload the stack during deploy
  --s3-region         region to create the bucket in if it doesn't exist
  --dry-run           will show aws commands (not actualy run them)
  --quiet | -q        will suppress logging messages
  --help | -h         display this usage menu
EOFSH
  if [[ -n $@ ]]; then
    echo "[error] $@"
    exit 1
  fi
  exit 0
}

usage() {
echo "Usage: $(basename $0)"
if [[ "${DIRECT:-}" = true ]]; then
cat <<EOF
  --stack-name        [required] name to give the stack e.g. "kore-stack-feature-a"
  --stack-file        [required] stack file name to use e.g. "./scripts/file-name.json"
  --stack-inputs      [required] stack inputs to use e.g. 'StackParameter="x" StackParameter="y"'
EOF
fi
shortusage $@
}

run-cmd() {
  if [[ ${DRY_RUN:-} == 'true' ]]; then
    info "dry-run:\n$@"
  else
    OUTPUT=$( $@ )
  fi
  return $?
}

describe-stack() {
  aws cloudformation describe-stacks | \
    jq -r ' .Stacks | .[] | select(.StackName=="'${1?"error missing stack name"}'") | '.${2?"missing param for describe"}''
}

print-stack-outputs() {
  stackName=${1?"error missing stack name"}
  aws cloudformation describe-stacks | \
    jq -r ' .Stacks | .[] | select(.StackName=="'${stackName}'") | .Outputs | .[] | .OutputValue'
}

create-bucket-if-required() {
  if ! aws s3 ls ${S3_BUCKET} >/dev/null 2>&1 ; then
    if [[ -z ${S3_REGION:-} ]]; then
      error "--s3-region not set so can't create bucket with correct LocationConstraint"
    fi

    info "bucket ${S3_BUCKET} not found, creating ${S3_BUCKET}..."
    if ! run-cmd aws s3api create-bucket --acl private --bucket ${S3_BUCKET} --create-bucket-configuration LocationConstraint=${S3_REGION}; then
      error "bucket ${S3_BUCKET} does not exist and can't be created"
    fi
  fi
}

deploy-stack() {
  stack_name=${1}
  file_name=${2}
  inputs="--parameter-overrides ${3}"
  info "deploying stack - ${stack_name}"
  info ${inputs}
  run-cmd aws cloudformation deploy \
    --stack-name ${stack_name} \
    --template-file ${file_name} \
    --s3-bucket ${S3_BUCKET} \
    --capabilities CAPABILITY_NAMED_IAM \
    ${inputs} \
    --no-fail-on-empty-changeset
}

wait-on-stack-complete-or-exit() {
  info "waiting for stack to complete"
  for i in {1..30} ; do
    STATUS=$( describe-stack ${STACK_NAME} StackStatus )

    case "${STATUS}" in
      "CREATE_COMPLETE" | "UPDATE_COMPLETE")
        break
        ;;
      "ROLLBACK_COMPLETE")
        error "Unrecoverable stack status ${STATUS}, please review and delete stack and try again"
        ;;
      "CREATE_FAILED" | "ROLLBACK_FAILED" | "ROLLBACK_IN_PROGRESS")
        error "Stack error status ${STATUS} -  back for ${STACK_NAME}"
        ;;
      *)
        sleep 1
        ;;
    esac
  done

  if [[ "${STATUS}" =~ ^(CREATE_COMPLETE|UPDATE_COMPLETE)$ ]]; then
    info "Successfuly created: ${STACK_NAME}"
  else
    error "Stack didn't complete - ${STATUS}. Reveiw cloudformation stack events for ${STACK_NAME}"
  fi
}

check-dependency() {
  bin=${1?"missing name"}
  which ${bin} >/dev/null 2>&1 || \
    error "missing cli tool:${bin}, please install and retry"
}

run() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stack-name)       STACK_NAME=${2};           shift 2; ;;
      --stack-file)       STACK_FILE=${2};           shift 2; ;;
      --stack-inputs)     STACK_INPUTS=${2};         shift 2; ;;
      --s3-bucket)        S3_BUCKET=${2};            shift 2; ;;
      --s3-region)        S3_REGION=${2};            shift 2; ;;
      --dry-run)          DRY_RUN=true;              shift 1; ;;
      -sh|--short-help)   shortusage;                         ;;
      -h|--help)          usage;                              ;;
      -q|-quiet)          QUIET=true;                shift 1; ;;
      *)                                             shift 1; ;;
    esac
  done

  check-dependency jq
  check-dependency aws

  S3_BUCKET=${S3_BUCKET:-${STACK_NAME:-}}
  S3_REGION=$(aws configure get region || true )

  [[ -z ${STACK_NAME:-}   ]] && usage "Missing stack name '${STACK_NAME:-}'"
  [[ -z ${STACK_FILE:-}   ]] && usage "Missing stack file '${STACK_FILE:-}'"
  [[ -z ${STACK_INPUTS:-} ]] && usage "Missing stack inputs '${STACK_INPUTS:-}'"
  [[ -z ${S3_REGION:-}    ]] && usage "Unknown s3 region, please configure aws default or specify"
  [[ ! -f ${STACK_FILE}   ]] && usage "Missing file ${STACK_FILE}! Did you download it?"

  info "stack name: ${STACK_NAME}"
  info "stack file: ${STACK_FILE}"
  info "stack inputs: ${STACK_INPUTS}"
  info "stack bucket: ${S3_BUCKET}"
  info "stack bucket region: ${S3_REGION}"

  # These will conflict and result in endpoint error when uploading stack
  unset AWS_DEFAULT_REGION AWS_REGION

  create-bucket-if-required
  deploy-stack "${STACK_NAME}" "${STACK_FILE}" "${STACK_INPUTS}"
  wait-on-stack-complete-or-exit
  print-stack-outputs ${STACK_NAME}
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  DIRECT=true
  # not sourced so running direct
  run $@
fi
