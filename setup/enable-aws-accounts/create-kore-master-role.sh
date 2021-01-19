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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
CREATE_STACK_SCRIPT=${SCRIPT_DIR}/create-stack.sh
source ${CREATE_STACK_SCRIPT}

MASTER_ROLE_CF_TEMPLATE_PATH=${SCRIPT_DIR}/assets/KoreMasterOrgRoles.yaml

my-usage() {
cat <<EOF
Usage: $(basename $0)
  --kore-user-arn     [required] kore user to grant accees to the role e.g. "arn:aws:iam::123456789:user/kore-accounts-admin-user"
  --master-role-name  [required] name to give the master role (e.g. - "kore-accounts-role-for-custom-ou")
EOF
shortusage $@
exit $?
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --master-role-name) KORE_MASTER_ROLE_NAME=${2}; shift 2; ;;
    --kore-user-arn)    KORE_USER_ARN=${2};         shift 2; ;;
    -h|--help)          my-usage;                            ;;
    *)                                              shift 1; ;;
  esac
done

[[ -z ${KORE_USER_ARN:-} ]]                  && my-usage "You must specify the ARN of the Kore user identity"
[[ -z ${KORE_MASTER_ROLE_NAME:-} ]]          && my-usage "Please specify master role name (e.g. kore-account-management-role-for-custom-ou)"

info "stack name: ${KORE_MASTER_ROLE_NAME:-} (to create role of same name)"
info "will grant sts permission to user:${KORE_USER_ARN:-}"

run \
  --stack-name ${KORE_MASTER_ROLE_NAME:-} \
  --stack-file ${MASTER_ROLE_CF_TEMPLATE_PATH} \
  --stack-inputs "AllowAssumeFromARN=${KORE_USER_ARN:-} AccountFactory=${KORE_MASTER_ROLE_NAME:-}" \
  $@
