// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local nsCountContext(varName) = {
  name: 'nsCount',
  apiCall: {
    urlPath: '/api/v1/namespaces',
    // Filter namespaces that have the same label and count them
    jmesPath: 'items[?metadata.labels."appuio.io/organization" == \'%s\'] | length(@)' % varName,
  },
};

local overrideContext(varName) = {
  name: 'override',
  // We can't use Kyverno's 'configMap' syntactic sugar, as that would fail the rule if the configmap doesn't exist.
  // Also, making an API call to a single configmap fails the rule also if it doesn't exist.
  // Thus, we list all of them and filter by name, in the end the result is either a number or "null".
  apiCall: {
    urlPath: '/api/v1/namespaces/%s/configmaps' % params.namespace,
    jmesPath: "items[?metadata.name == 'override-%s'].data.namespaceQuota | [0]" % varName,
  },
};

local validateRule(varName) = {
  message: "You cannot create more than {{override || `%s`}} namespaces for organization '%s'.\nPlease contact support to have your quota raised." % [ params.maxNamespaceQuota, varName ],
  deny: {
    conditions: {
      any: [
        {
          key: '{{nsCount}}',
          operator: 'GreaterThanOrEquals',
          value: '{{override || `%s`}}' % params.maxNamespaceQuota,
        },
      ],
    },
  },
};

local operationPrecondition(match='all', ops=[ 'CREATE' ]) = {
  [match]+: [
    {
      key: '{{request.operation}}',
      operator: 'In',
      value: [ 'CREATE' ],
    },
  ],
};

local orgLabelVar = '{{request.object.metadata.labels."appuio.io/organization"}}';

/**
  * Check Namespace Quota
  * This policy will:
  * - Deny the new namespace if the number of existing namespaces is greater or equal a certain number.
  * - This number is either a default defined in this component, or it can be overridden for a specific organization.
  *   To set this override, create a config map in the component namespace with name pattern 'override-<org-name>' with `.data.namespaceOverride` being the number.
  *   For example: kubectl -n appuio-cloud create cm override-foo --from-literal=namespaceQuota=4
  */
local namespaceQuotaPolicy = kyverno.ClusterPolicy('check-namespace-quota') {
  metadata+: {
    annotations+: {
      // Kyverno somehow detects this rule as needing controller autogeneration.
      // https://kyverno.io/docs/writing-policies/autogen/
      // Explicitly disable autogen. Autogen interferes with ArgoCD and we don't need it here
      // since only Namespaces are validated anyway.
      'pod-policies.kyverno.io/autogen-controllers': 'none',
      'policies.kyverno.io/title': 'Check and enforce namespace quotas for organizations',
      'policies.kyverno.io/category': 'Namespace Management',
      'policies.kyverno.io/minversion': 'v1',
      'policies.kyverno.io/subject': 'APPUiO Organizations',
      'policies.kyverno.io/jsonnet': common.JsonnetFile(std.thisFile),
      'policies.kyverno.io/description': |||
        This policy will deny creation of the new namespace if the number of existing namespaces for the requester's organization is greater or equal a certain number.

        The number of allowed namespaces is either the default defined in this component, or it can be overridden for a specific organization.

        To create an override, create a config map in the component namespace with name pattern `override-<organization-name>` with `.data.namespaceOverride` being the number.
        For example, to set the namespace quota for organization foo to `4`:

        [source,bash]
        ----
        kubectl -n appuio-cloud create cm override-foo --from-literal=namespaceQuota=4
        ----

        The default number of allowed namespaces per organization is configured with xref:references/parameters#_maxnamespacequota[component parameter `maxNamespaceQuota`].

        Users which match an entry of xref:references/parameters#_bypassnamespacerestrictions[component parameter `bypassNamespaceRestrictions`] are allowed to bypass this policy.
      |||,
    },
  },
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'check-namespace-count',
        match: common.MatchOrgNamespaces,
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        context: [
          overrideContext(varName=orgLabelVar),
          nsCountContext(varName=orgLabelVar),
        ],
        validate: validateRule(varName=orgLabelVar),
        preconditions: operationPrecondition(),
      },
      {
        name: 'check-project-count',
        match: common.MatchProjectRequests(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        context: [
          {
            name: 'organization',
            apiCall: {
              urlPath: '/apis/user.openshift.io/v1/users/{{request.userInfo.username}}',
              jmesPath: 'metadata.annotations."appuio.io/default-organization" || ""',
            },
          },
          overrideContext(varName='{{organization}}'),
          nsCountContext(varName='{{organization}}'),
        ],
        validate: validateRule(varName='{{organization}}'),
        preconditions: operationPrecondition(),
      },
    ],
  },
};

local namespaceQuotaOverrides = [
  kube.ConfigMap('override-%s' % org) {
    metadata+: {
      labels+: {
        // this label is informational only here
        'appuio.io/organization': org,
      },
    },
    data+: {
      namespaceQuota: '%s' % params.namespaceQuotaOverrides[org],
    },
  } + common.DefaultLabels
  for org in std.filter(function(key) key != null && params.namespaceQuotaOverrides[key] != null, std.objectFields(params.namespaceQuotaOverrides))
];

// Define outputs below
common.RemoveDisabledPolicies({
  [if !common.AgentFeatureEnabled('usage-profiles') then '12_namespace_quota_per_zone']: namespaceQuotaPolicy + common.DefaultLabels,
  [if std.length(namespaceQuotaOverrides) > 0 then '13_namespace_quota_overrides']: namespaceQuotaOverrides,
})
