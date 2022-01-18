// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

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
    {
      kind: 'Group',
      name: 'system:serviceaccounts',
    },
  ],
};

local matchProjectRequestProjects = {
  all: [ {
    resources: {
      annotations: {
        'openshift.io/requester': '?*',
      },
      kinds: [
        'Project',
      ],
    },
  } ],
};


local setDefaultOrgPolicy(name, match, exclude, preconditions, username) = {
  name: name,
  match: match,
  exclude: exclude,
  preconditions: preconditions,
  context: [
    {
      name: 'ocpuser',
      apiCall: {
        urlPath: '/apis/user.openshift.io/v1/users/%s' % username,
        // We want the full output of the API call. Despite the docs not
        // saying anything, if we omit jmesPath here, we don't get the
        // variable ocpuser in the resulting context at all. Instead, we
        // provide '@' for jmesPath which responds to the current
        // element, giving us the full response as ocpuser.
        jmesPath: '@',
      },
    },
  ],
  mutate: {
    patchStrategicMerge: {
      metadata: {
        labels: {
          '+(appuio.io/organization)':
            '{{ocpuser.metadata.annotations."appuio.io/default-organization"}}',
        },
      },
    },
  },
};

local notServiceAccount = {
  all: [
    {
      key: '{{serviceAccountName}}',
      operator: 'Equals',
      value: '',
    },
  ],
};

local isServiceAccount = {
  all: [
    {
      key: '{{serviceAccountName}}',
      operator: 'NotEquals',
      value: '',
    },
  ],
};


local organizationProjects = kyverno.ClusterPolicy('organization-projects') {
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      setDefaultOrgPolicy(
        'set-default-organization',
        matchProjectRequestProjects,
        {},
        {},
        '{{request.object.metadata.annotations."openshift.io/requester"}}',
      ),
    ],
  },
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
      setDefaultOrgPolicy(
        'set-default-organization',
        common.MatchNamespaces(),
        common.BypassNamespaceRestrictionsSubjects(),
        notServiceAccount,
        '{{request.userInfo.username}}'
      ),
      {
        name: 'has-organization',
        match: common.MatchNamespaces(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        preconditions: notServiceAccount,
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
        match: common.MatchNamespaces(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        preconditions: notServiceAccount {
          all+:
            [
              {
                key: '{{request.object.metadata.labels."appuio.io/organization"}}',
                operator: 'NotEquals',
                value: '',
              },
            ],
        },
        validate: {
          message: 'Creating namespace for {{request.object.metadata.labels."appuio.io/organization"}} but {{request.userInfo.username}} is not in organization',
          deny: {
            conditions: [
              {
                key: '{{request.object.metadata.labels."appuio.io/organization"}}',
                operator: 'NotIn',
                value: '{{request.userInfo.groups}}',
              },
            ],
          },
        },
      },
    ],
  },
};

local organizationSaNamespaces = kyverno.ClusterPolicy('organization-sa-namespaces') {
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'add-organization',
        match: common.MatchNamespaces(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        preconditions: isServiceAccount,
        context: [
          {
            name: 'saNamespace',
            apiCall: {
              urlPath: '/api/v1/namespaces/{{serviceAccountNamespace}}',
              // We want the full output of the API call. Despite the docs not
              // saying anything, if we omit jmesPath here, we don't get the
              // variable ocpuser in the resulting context at all. Instead, we
              // provide '@' for jmesPath which responds to the current
              // element, giving us the full response as ocpuser.
              jmesPath: '@',
            },
          },

        ],
        mutate: {
          patchStrategicMerge: {
            metadata: {
              labels: {
                '+(appuio.io/organization)':
                  '{{saNamespace.metadata.labels."appuio.io/organization"}}',
              },
            },
          },
        },
      },
      {
        name: 'has-organization',
        match: common.MatchNamespaces(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        preconditions: isServiceAccount,
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
        match: common.MatchNamespaces(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        context: [
          {
            name: 'saNamespace',
            apiCall: {
              urlPath: '/api/v1/namespaces/{{serviceAccountNamespace}}',
              // We want the full output of the API call. Despite the docs not
              // saying anything, if we omit jmesPath here, we don't get the
              // variable ocpuser in the resulting context at all. Instead, we
              // provide '@' for jmesPath which responds to the current
              // element, giving us the full response as ocpuser.
              jmesPath: '@',
            },
          },
        ],
        preconditions: isServiceAccount {
          all+:
            [
              {
                key: '{{request.object.metadata.labels."appuio.io/organization"}}',
                operator: 'NotEquals',
                value: '',
              },
            ],
        },
        validate: {
          message: 'Creating namespace for {{request.object.metadata.labels."appuio.io/organization"}} but {{serviceAccountName}} is not in organization',
          deny: {
            conditions: [
              {
                key: '{{request.object.metadata.labels."appuio.io/organization"}}',
                operator: 'NotEquals',
                value: '{{saNamespace.metadata.labels."appuio.io/organization"}}',
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
        match: common.MatchNamespaces(
          names=common.FlattenSet(params.reservedNamespaces),
        ),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        validate: {
          message: 'Changing or creating reserved namespaces is not allowed.',
          deny: {},
        },
      },
    ],
  },
};

/**
  * Disallow auxiliary labels and annottions
  * This policy will:
  * - Check modified annotations and labels against a whitelist.
  * - Deny namespace creation or modification.
  */
local validateNamespaceMetadata = kyverno.ClusterPolicy('validate-namespace-metadata') {
  local validateObject = function(key, whitelist) {
    name: 'validate-%s' % key,
    match: common.MatchNamespaces(),
    exclude: common.BypassNamespaceRestrictionsSubjects(),
    preconditions: {
      all: [
        {
          key: '{{request.operation}}',
          operator: 'In',
          value: [ 'CREATE', 'UPDATE' ],
        },
      ],
    },
    validate: {
      message: (
        'The following %(object)s can be modified:\n    %(whitelist)s.\n'
        + '%(object)s given:\n    {{request.object.metadata.%(object)s}}.\n'
        + '%(object)s before modification:\n    {{request.oldObject.metadata.%(object)s}}.'
      ) % { object: key, whitelist: std.join(', ', whitelist) },
      foreach: [
        {
          list: (
            // Kyverno validates that the expression begins with 'request.object'.
            // Let's get that out the way here. 'request.object' is always true.
            'request.object'
            // Merge the current and the old object to ensure having all keys
            // even if a user delete one.
            + '&& merge('
            + '    not_null(request.object.metadata.%(object)s, `{}`)'
            + '   ,not_null(request.oldObject.metadata.%(object)s, `{}`))'
            // Make an array out of the keys. The map is here because Kyverno
            // only allows an array of objects and not an array of strings.
            + '  | map(&{key: @}, keys(@))'
          ) % { object: key },
          deny: {
            // Deny if:
            conditions: {
              all: [
                // Label has changed
                {
                  key: '{{request.object.metadata.%(object)s."{{element.key}}" != request.oldObject.metadata.%(object)s."{{element.key}}"}}' % { object: key },
                  operator: 'Equals',
                  value: true,
                },
                // AND
                // label is not in whitelist
                // This can be simplified with kyverno 1.6 which supports wildcards for AnyIn and AnyNotIn
                // https://github.com/kyverno/kyverno/pull/2692
                {
                  key: '{{%s}}' % std.join(' || ', std.map(
                    function(w) 'regex_match(`"%s"`, `"{{element.key}}"`)' % common.KyvernoPatternToRegex(w),
                    whitelist
                  )),
                  operator: 'Equals',
                  value: false,
                },
              ],
            },
          },
        },
      ],
    },
  },
  metadata+: {
    annotations+: {
      // Kyverno somehow detects this rule as needing controller autogeneration.
      // https://kyverno.io/docs/writing-policies/autogen/
      // Explicitly disable autogen. Autogen interferes with ArgoCD and we don't need it here
      // since only Namespaces are validated anyway.
      'pod-policies.kyverno.io/autogen-controllers': 'none',
    },
  },
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      validateObject('labels', common.FlattenSet(params.allowedNamespaceLabels)),
      validateObject('annotations', common.FlattenSet(params.allowedNamespaceAnnotations)),
    ],
  },
};

// Define outputs below
{
  '01_appuio_ns_provisioner_role': appuioNsProvisionerRole + common.DefaultLabels,
  '01_appuio_ns_provisioners_crb': appuioNsProvisionersRoleBinding + common.DefaultLabels,
  '02_organization_namespaces': organizationNamespaces + common.DefaultLabels,
  '02_organization_sa_namespaces': organizationSaNamespaces + common.DefaultLabels,
  '02_organization_projects': organizationProjects + common.DefaultLabels,
  '02_disallow_reserved_namespaces': disallowReservedNamespaces + common.DefaultLabels,
  '02_validate_namespace_metadata': validateNamespaceMetadata + common.DefaultLabels,
}
