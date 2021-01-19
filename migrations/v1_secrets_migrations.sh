#!/bin/bash
#
# Copyright (C) 2020 Appvia Ltd <kore@appvia.io>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# @step: retrieve a list of all secrets in kore
KUBECTL=`which kubectl`
JQ=`which jq`

# check we have the kubectl binary
[[ -n ${KUBECTL} ]] || { "unable to find the kubectl binary in path"; exit 1; }
[[ -n ${JQ}      ]] || { "unable to find the jq binary in path"; exit 1; }

cat <<EOF
Migration Task:

The script is used to migrate all the legacy configv1.Secret over to v1.Secret
types. Note we do not delete the legecy secret at present in case they migration
has issues and needs to revert. The migration script can be run multiple times
without issues and once your ran, upgraded the instance you can delete the
old legacy secrets via:

$ while read \${namespace} \${name}; do
  kubectl --namespace \${namespace} delete secrets.config.kore.appvia.io ${name}
done < <(kubectl get secrets.config.kore.appvia.io --all-namespaces --no-headers | awk '{ print $1,$2}')

or just list the team namespaces via '$ kubectl get ns' and delete via

$ kubectl --namespace <name> delete secrets.config.kore.appvia.io --all

# Make sure you have deleted all secrets using the above example before trying to delete the CRD
$ kubectl get crd secrets.config.kore.appvia.io

EOF

KUBE_CONTEXT=$(kubectl config current-context)
if [[ -z "${KUBE_CONTEXT}" ]]; then
  echo "error: no kube context has been set"
  exit 1
fi

echo -n "Kubernetes context is: ${KUBE_CONTEXT}, is this the cluster you wish to migrate? (y/n) "
read -n1 choice
echo
if [[ ! ${choice} =~ ^[Yy]$ ]]; then
  echo "Skipping the migration of Kore secrets"
  exit 0
fi

echo "Retrieving a list of all legacy configv1.Secrets in Kore"

while read namespace name; do
  if kubectl --namespace ${namespace} get secret ${name} >/dev/null 2>&1; then
    printf "%-80s %s\n" "Check if migration required: (${namespace}/${name})" "[skipped]"
  else
    printf "%-80s %s\n" "Check if migration required: (${namespace}/${name})" "[migrating]"

    managed=false
    description=$(kubectl -n ${namespace} get secrets.config.kore.appvia.io ${name} -o json | jq -r .spec.description)
    type=$(kubectl -n ${namespace} get secrets.config.kore.appvia.io ${name} -o json | jq -r .spec.type)
    data=$(kubectl -n ${namespace} get secrets.config.kore.appvia.io ${name} -o json | jq -r .spec.data)

    [[ -n ${description} ]] || { echo "unable to find a spec.description on secret"; exit 1; }
    [[ -n ${type} ]] || { echo "unable to find a spec.type on secret"; exit 1; }
    [[ -n ${data} ]] || { echo "unable to find a spec.data on secret"; exit 1; }
    [[ "${type}" =~ ^((aws|gke|aks)-credentials|kubernetes)$ ]] && managed=true

    [[ "${type}" == "aws-credentials" ]] && type="aws"
    [[ "${type}" == "azure-credentials" ]] && type="azure"
    [[ "${type}" == "gke-credentials" ]] && type="gcp"

    if [[ ${managed} == true ]]; then
      cat <<EOF >/tmp/secret.mirgation
{
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "${name}",
    "namespace": "${namespace}",
    "annotations": {
      "kore.appvia.io/description": "${description}",
      "kore.appvia.io/owner": "true",
      "kore.appvia.io/system": "true",
      "kore.appvia.io/type": "${type}"
    }
  },
  "data": ${data}
}
EOF
    else
      cat <<EOF >/tmp/secret.mirgation
{
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "${name}",
    "namespace": "${namespace}",
    "annotations": {
      "kore.appvia.io/description": "${description}",
      "kore.appvia.io/owner": "true",
      "kore.appvia.io/type": "${type}"
    }
  },
  "data": ${data}
}
EOF
    fi

    if ! cat /tmp/secret.mirgation | ${KUBECTL} -n ${namespace} apply -f -; then
      echo "unable to create the v1.secret: ${namespace}/${name}"
      exit 1
    fi
  fi
done < <(${KUBECTL} get secrets.config.kore.appvia.io --all-namespaces --no-headers | awk '{ print $1,$2}')

