#!/bin/bash

# Find all clusterroles allowed to create and edit namespaces

set -euo pipefail

kubectl --as=cluster-admin get clusterrole -ojson | jq '[ .items[]
        | select(
            .rules[]?
                | select(
                        (.apiGroups[]? == "" or .apiGroups[]? == "*")
                    and
                        (.resources[]? == "namespaces" or .resources[]? == "*")
                    and
                        (.verbs[]? == "create" or .verbs[]? == "update" or .verbs[]? == "patch" or .verbs[]? == "*")
                    )
            > 0
        )
        | .metadata.name
    ] | unique'
