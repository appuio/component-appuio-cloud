// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

/**
  * Check Namespace Quota
  * This policy will:
  * - Deny the new namespace if the number of existing namespaces is greater or equal a certain number.
  * - This number is either a default defined in this component, or it can be overridden for a specific organization.
  *   To set this override, create a config map in the component namespace with name pattern 'override-<org-name>' with `.data.namespaceOverride` being the number.
  *   For example: kubectl -n appuio-cloud create cm override-foo --from-literal=namespaceQuota=4
  */
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
          {
            name: 'override',
            // We can't use Kyverno's 'configMap' syntactic sugar, as that would fail the rule if the configmap doesn't exist.
            // Also, making an API call to a single configmap fails the rule also if it doesn't exist.
            // Thus, we list all of them and filter by name, in the end the result is either a number or "null".
            apiCall: {
              urlPath: '/api/v1/namespaces/%s/configmaps' % params.namespace,
              jmesPath: 'items[?metadata.name == \'override-{{request.object.metadata.labels."appuio.io/organization"}}\'].data.namespaceQuota | [0]',
            },
          },
          {
            name: 'nsCount',
            apiCall: {
              urlPath: '/api/v1/namespaces',
              // Filter namespaces that have the same label and count them
              jmesPath: 'items[?metadata.labels."appuio.io/organization" == \'{{request.object.metadata.labels."appuio.io/organization"}}\'] | length(@)',
            },
          },
        ],
        validate: {
          message: 'You cannot create more than {{override || `%s`}} namespaces for organization \'{{request.object.metadata.labels."appuio.io/organization"}}\'.\nPlease contact support to have your quota raised.' % params.maxNamespaceQuota,
          deny: {
            conditions: [
              {
                key: '{{nsCount}}',
                operator: 'GreaterThanOrEquals',
                value: '{{override || `%s`}}' % params.maxNamespaceQuota,
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
