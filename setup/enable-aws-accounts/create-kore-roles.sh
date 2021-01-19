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

# **********************************************************************
# THIS SCRIPT WILL BE REPLACED SOON AS THE POLICIES ARE MIGRATED TO CODE
# TODO: ADD policies to code: https://github.com/appvia/kore/issues/1642
#       Role creation set-up: https://github.com/appvia/kore/issues/1669
# **********************************************************************

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
CREATE_STACK_SCRIPT=${SCRIPT_DIR}/create-stack.sh
source ${CREATE_STACK_SCRIPT}

my-usage() {
cat <<EOF
Usage: $(basename $0)
  --kore-trusted-identity-arn     [required] kore user / role to grant accees from e.g. "arn:aws:iam::123456789:user/kore-sa-identity"
  --kore-feature                  [required] the kore feature to create roles for e.g. Provisioning | Costs
  --kore-name                     [required] the unqiue name for the kore instance used for stack and roles
EOF
shortusage $@
exit $?
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kore-trusted-identity-arn)   KORE_IDENTITY_ARN=${2};     shift 2; ;;
    --kore-feature)                KORE_FEATURE=${2};          shift 2; ;;
    --name)                        NAME=${2};                  shift 2; ;;
    -h|--help)                     my-usage;                            ;;
    *)                                                         shift 1; ;;
  esac
done

[[ -z ${KORE_IDENTITY_ARN:-}   ]] && usage "Missing user ARN '${KORE_IDENTITY_ARN:-}'"
[[ -z ${NAME:-}   ]]              && usage "Missing name to use for role and stack '${NAME:-}'"
STACK_NAME=kore-${KORE_FEATURE}-roles-for-${NAME}

info "feature:${KORE_FEATURE}"
info "trusted identity: ${KORE_IDENTITY_ARN}"
info "stack name: ${STACK_NAME}"

# TODO: For testing, replacing with:
#       kore update roles --cloud-account appvia-org --feature sharedAccountRoles|orgAccountsRoles [--dry-run]
case "${KORE_FEATURE}" in
  provisioning)
    run \
      --stack-name ${STACK_NAME} \
      --stack-file ${SCRIPT_DIR}/assets/KoreProvisioningRoles.yaml \
      --stack-inputs "NetworkManager=kore-NetworkManagerFor-${NAME} ClusterManager=kore-ClusterManagerFor-${NAME} DNSZoneManager=kore-DNSZoneManagerFor-${NAME} AllowAssumeFromARN=${KORE_IDENTITY_ARN}" \
      $@
    ;;
  costs)
    run \
      --stack-name ${STACK_NAME} \
      --stack-file ${SCRIPT_DIR}/assets/KoreCostsRoles.yaml \
      --stack-inputs "CostsManager=kore-CostsManagerFor-${NAME} AllowAssumeFromARN=${KORE_IDENTITY_ARN}" \
      $@
    ;;
  *)
    my-usage "must specify valid --kore-feature"
    ;;
esac
