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
            '{{ocpuser.metadata.annotations."appuio.io/default-organization" || ""}}',
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

local commonDocAnnotations = {
  'policies.kyverno.io/category': 'Namespace Ownership',
  'policies.kyverno.io/minversion': 'v1',
  'policies.kyverno.io/subject': 'APPUiO Organizations',
  'policies.kyverno.io/jsonnet': common.JsonnetFile(std.thisFile),
};

/**
  * Organization Projects
  */
local organizationProjects = kyverno.ClusterPolicy('organization-projects') {
  metadata+: {
    annotations+: commonDocAnnotations {
      'policies.kyverno.io/title': "Ensure that all OpenShift Projects created by users have a label `appuio.io/organization` which isn't empty.",
      'policies.kyverno.io/description': |||
        This policy will:

        - Check that each project created by a user without cluster-admin  permissions has a label appuio.io/organization which isn't empty.
        - Check that the creating user is in the organization they try to create a project for.

        The user's organization membership is checked by:

        - Reading the project's annotation `openshift.io/requester` which contains the username of the user who originally requested the project.
        - Fetching all OpenShift groups
        - Reading the `appuio.io/organization` label of the request and finding a group with the same name

        If a group matching the label value exists, the policy checks that the user which requested the project is a member of that group.

        If the label `appuio.io/organization` is missing or empty or the user isn't a member of the group, the request is denied.
      |||,
    },
  },
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
  */
local organizationNamespaces = kyverno.ClusterPolicy('organization-namespaces') {
  metadata+: {
    annotations+: commonDocAnnotations {
      'policies.kyverno.io/title': "Ensure that all namespaces created by users have a label `appuio.io/organization` which isn't empty.",
      'policies.kyverno.io/description': |||
        This policy will:

        - Check that each namespace created by a user without cluster-admin  permissions has a label appuio.io/organization which isn't empty.
        - Check that the creating user is in the organization it tries to create a namespace for.

        The user's organization membership is checked by:

        - Fetching all OpenShift groups
        - Reading the `appuio.io/organization` label of the request and finding a group with the same name

        If a group matching the label value exists, the policy checks that the user which issued the request is a member of that group.

        If the label `appuio.io/organization` is missing or empty or the user isn't a member of the group, the request is denied.

        Users which match an entry of xref:references/parameters#_bypassnamespacerestrictions[component parameter `bypassNamespaceRestrictions`] are allowed to bypass the policy.
      |||,
    },
  },
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
                key: '{{request.object.metadata.labels."appuio.io/organization" || ""}}',
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
                key: '{{request.object.metadata.labels."appuio.io/organization" || ""}}',
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
  metadata+: {
    annotations+: commonDocAnnotations {
      'policies.kyverno.io/title': "Ensure that all namespaces created by organization serviceaccounts have a label `appuio.io/organization` which isn't empty.",
      'policies.kyverno.io/description': |||
        This policy will:

        - Check that each namespace created by a serviceaccount without cluster-admin permissions has a label appuio.io/organization which isn't empty.
        - Check that the creating serviceaccount is part of the organization it tries to create a namespace for.

        The serviceaccount's organization membership is checked by:

        - Fetching the serviceaccount's namespace
        - Comparing that namespace's `appuio.io/organization` label value with the request's `appuio.io/organization` label value.

        If the label `appuio.io/organization` is missing or empty or the serviceaccount's organization doesn't match the request's organization the request is denied.

        Serviceaccounts which match an entry of xref:references/parameters#_bypassnamespacerestrictions[component parameter `bypassNamespaceRestrictions`] are allowed to bypass the policy.
      |||,
    },
  },
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
                  '{{saNamespace.metadata.labels."appuio.io/organization" || ""}}',
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
                key: '{{request.object.metadata.labels."appuio.io/organization" || ""}}',
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
  */
local disallowReservedNamespaces = kyverno.ClusterPolicy('disallow-reserved-namespaces') {
  metadata+: {
    annotations+: commonDocAnnotations {
      'policies.kyverno.io/title': 'Disallow creation and editing of reserved namespaces',
      'policies.kyverno.io/description': |||
        This policy will:

        - Check if the namespace name of the request matches one of the disallowed namespace patterns.
        - Check if the requesting user/serviceaccount has a cluster role that allows them to create reserved namespaces.

        If the namespace matches a disallowed pattern and the requester doesn't have a cluster role which allows them to bypass the policy, the request is denied.
        The policy is applied for requests to create `Namespace` and `ProjectRequest` resources.
        This ensures that unprivileged users can't use disallowed patterns regardless of whether they use `oc new-project`, `kubectl create ns` or the OpenShift web console.

        The list of reserved namespace patterns is configured with xref:references/parameters#_reservednamespaces[component parameter `reservedNamespaces`].

        Requesters which match an entry of xref:references/parameters#_bypassnamespacerestrictions[component parameter `bypassNamespaceRestrictions`] are allowed to bypass the policy.
      |||,
    },
  },
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'disallow-reserved-namespaces',
        match: common.MatchNamespacesAndProjectRequests(
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
    annotations+: commonDocAnnotations {
      // Kyverno somehow detects this rule as needing controller autogeneration.
      // https://kyverno.io/docs/writing-policies/autogen/
      // Explicitly disable autogen. Autogen interferes with ArgoCD and we don't need it here
      // since only Namespaces are validated anyway.
      'pod-policies.kyverno.io/autogen-controllers': 'none',
      'policies.kyverno.io/title': 'Disallow auxiliary labels and annotations',
      'policies.kyverno.io/description': |||
        This policy will:

        - Check annotations and labels on new and modified namespaces against a whitelist.

        If the namespace has an annotation or label which isn't whitelisted and the requester doesn't have a cluster role which allows them to bypass the policy, the request is denied.

        The list of allowed namespace annotations and labels is configured with xref:references/parameters#_allowednamespaceannotations[component parameter `allowedNamespaceAnnotations`] and xref:references/parameters#_allowednamespacelabels[component parameter `allowedNamespaceLabels`] respectively.

        Requesters which match an entry of xref:references/parameters#_bypassnamespacerestrictions[component parameter `bypassNamespaceRestrictions`] are allowed to bypass the policy.
      |||,
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
