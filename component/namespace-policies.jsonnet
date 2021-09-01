// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local flattenSet(set) = std.flatMap(function(s)
                                      if std.isArray(set[s]) then set[s] else [ set[s] ],
                                    std.objectFields(std.prune(set)));

/**
  * bypassNamespaceRestrictionsSubjects returns an object containing the configured roles and subjects
  * allowed to bypass restrictions.
  */
local bypassNamespaceRestrictionsSubjects() = {
  local bypass = params.bypassNamespaceRestrictions,
  clusterRoles+: flattenSet(bypass.clusterRoles),
  roles+: flattenSet(bypass.roles),
  subjects+: flattenSet(bypass.subjects),
};


/**
  * appuio-ns-provisioner role allows to create namespaces
  */
local appuioNsProvisionerRole = kube.ClusterRole('appuio-ns-provisioner') {
  rules: [
    {
      apiGroups: [
        '',
      ],
      resources: [
        'namespaces',
      ],
      verbs: [
        'create',
      ],
    },
  ],
};

/**
  * appuio-ns-provisioners cluster role binding allows authenticated users to create namespaces
  */
local appuioNsProvisionersRoleBinding = kube.ClusterRoleBinding('appuio-ns-provisioners') {
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'appuio-ns-provisioner',
  },
  subjects: [
    {
      kind: 'Group',
      name: 'system:authenticated:oauth',
    },
  ],
};

/**
  * Organization Namespaces
  * This policy will:
  * - Check that each namespace created by a user/serviceaccount without cluster-admin  permissions has a label appuio.io/organization which is not empty.
  * - Check that the creating user is in the organization it tries to create a namespace for. It does this by:
  * - Fetch all openshift groups
  * - Get the appuio.io/organization label and find a group with the same name
  * - If it exists, check that the creating user is in the user list of this group
  * - Deny if it is not
  */
local organizationNamespaces = kyverno.ClusterPolicy('organization-namespaces') {
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'has-organization',
        match: {
          resources: {
            kinds: [
              'Namespace',
            ],
          },
        },
        exclude: bypassNamespaceRestrictionsSubjects(),
        validate: {
          message: 'Namespace must have organization',
          pattern: {
            metadata: {
              labels: {
                'appuio.io/organization': '?*',
              },
            },
          },
        },
      },
      {
        name: 'is-in-organization',
        match: {
          resources: {
            kinds: [
              'Namespace',
            ],
          },
        },
        exclude: {
          clusterRoles: [
            'cluster-admin',
          ],
        },
        preconditions: [
          {
            key: '{{request.object.metadata.labels."appuio.io/organization"}}',
            operator: 'NotEquals',
            value: '',
          },
        ],
        context: [
          {
            name: 'groups',
            apiCall: {
              urlPath: '/apis/user.openshift.io/v1/groups',
              jmesPath: 'items',
            },
          },
        ],
        validate: {
          message: 'Creating namespace for {{request.object.metadata.labels."appuio.io/organization"}} but {{request.userInfo.username}} is not in organization',
          deny: {
            conditions: [
              {
                key: '{{request.userInfo.username}}',
                operator: 'NotIn',
                value: "{{groups[?metadata.name=='{{request.object.metadata.labels.\"appuio.io/organization\"}}'].users[]}}",
              },
            ],
          },
        },
      },
    ],
  },
};

/**
  * Disallow the creation and edit of reserved namespaces
  * This policy will:
  * - Check if namespace name matches one of the disallowed namespace patterns
  * - Check if user has cluster role that allows them to create reserved namespaces
  * - Deny namespace creation or modification
  */
local disallowReservedNamespaces = kyverno.ClusterPolicy('disallow-reserved-namespaces') {
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'disallow-reserved-namespaces',
        match: {
          resources: {
            kinds: [
              'Namespace',
            ],
            names: flattenSet(params.reservedNamespaces),
          },
        },
        exclude: bypassNamespaceRestrictionsSubjects(),
        validate: {
          message: 'Changing or creating reserved namespaces is not allowed.',
          deny: {},
        },
      },
    ],
  },
};


// Define outputs below
{
  '01_appuio_ns_provisioner_role': appuioNsProvisionerRole + common.DefaultLabels,
  '01_appuio_ns_provisioners_crb': appuioNsProvisionersRoleBinding + common.DefaultLabels,
  '02_organization_namespaces': organizationNamespaces + common.DefaultLabels,
  '02_disallow_reserved_namespaces': disallowReservedNamespaces + common.DefaultLabels,
}