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

SA_ROLE_CF_TEMPLATE_PATH=${SCRIPT_DIR}/assets/KoreManagementClusterRole.yaml

my-usage() {
cat <<EOF
Usage: $(basename $0)
  --eks-cluster-name  [required] kore management cluster name e.g. "appvia-prod"
EOF
shortusage $@
exit $?
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --eks-cluster-name) KORE_EKS_CLUSTER_NAME=${2}; shift 2; ;;
    --kore-namespace)   KORE_NAMESPACE=${2};        shift 2; ;;
    -h|--help)          my-usage;                            ;;
    *)                                              shift 1; ;;
  esac
done

[[ -z ${KORE_EKS_CLUSTER_NAME:-} ]] && my-usage "Please specify the EKS cluster name that hosts Kore"
[[ -z ${KORE_NAMESPACE:-} ]]        && my-usage "Please specify the Namespace where kore is installed"

KORE_SA_ROLE_NAME=${KORE_SA_ROLE_NAME:-kore-sa-${KORE_EKS_CLUSTER_NAME}}
OIDC=$( aws eks describe-cluster --name ${KORE_EKS_CLUSTER_NAME} | jq -r .cluster.identity.oidc.issuer |sed 's|https://||' )
ACCOUNT_ID=$( aws sts get-caller-identity | jq -r .Account )

[[ -z ${OIDC:-} ]]       && my-usage "error accessing OIDC provider for --eks-cluster-name ${KORE_EKS_CLUSTER_NAME}"
[[ -z ${ACCOUNT_ID:-} ]] && my-usage "error accessing ACCOUNT_ID from AWS"

info "eks cluster name: ${KORE_EKS_CLUSTER_NAME:-} (that kore is to be run in)"
info "role name: ${KORE_SA_ROLE_NAME:-} (that kore is to be run in)"

run \
  --stack-name ${KORE_SA_ROLE_NAME:-} \
  --stack-file ${SA_ROLE_CF_TEMPLATE_PATH} \
  --stack-inputs "KoreIAMRoleName=${KORE_SA_ROLE_NAME} AWSAccountID=${ACCOUNT_ID} KoreManagemmentClusterOIDCEndpoint=${OIDC} KoreServiceNamespace=${KORE_NAMESPACE} KoreServiceName=kore-admin" \
  $@
