// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;


local namespaceQuotaPolicy = kyverno.ClusterPolicy('validate-namespace-quota') {
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'check-ns-count',
        match: common.MatchOrgNamespaces,
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        context: [
          // {
          //   name: 'override',
          //   configMap: {
          //     // Name of the ConfigMap which will be looked up
          //     name: '{{request.object.metadata.labels."appuio.io/organization"}}',
          //     // Namespace in which this ConfigMap is stored
          //     namespace: params.namespace,
          //   },
          // },
          {
            name: 'nsCount',
            apiCall: {
              urlPath: '/api/v1/namespaces',
              // Filter namespaces that have the same label
              jmesPath: 'items[?metadata.labels."appuio.io/organization" == \'{{request.object.metadata.labels."appuio.io/organization"}}\'] | length(@)',
            },
          },
        ],
        validate: {
          message: 'You cannot create more than {{override.data.namespaceQuota || `%s`}} namespaces for organization \'{{request.object.metadata.labels."appuio.io/organization"}}\'\n
          Please contact support to have your quota raised.' % params.maxNamespaceQuota,
          deny: {
            conditions: [
              {
                key: '{{nsCount}}',
                operator: 'GreaterThanOrEquals',
                value: '{{override.data.namespaceQuota || `%s`}}' % params.maxNamespaceQuota,
              },
            ],
          },
        },
      },
    ],
  },
  metadata+: {
    annotations+: {
      // Workaround for bug in `kyverno-cli test` command.
      // Commodore generates an empty annotation object (`annotations: {}`) which trips up Kyverno.
      // A non empty object or `annotations: null` is valid.
      // Ensure a label to not have an empty object.
      'policies.kyverno.io/category': 'Namespace Management',
    },
  },
};

// Define outputs below
{
  '12_namespace_quota_per_zone': namespaceQuotaPolicy + common.DefaultLabels,
}
