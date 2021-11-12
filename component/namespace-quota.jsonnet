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
    conditions: [
      {
        key: '{{nsCount}}',
        operator: 'GreaterThanOrEquals',
        value: '{{override || `%s`}}' % params.maxNamespaceQuota,
      },
    ],
  },
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
              jmesPath: 'metadata.annotations."appuio.io/default-organization"',
            },
          },
          overrideContext(varName='{{organization}}'),
          nsCountContext(varName='{{organization}}'),
        ],
        validate: validateRule(varName='{{organization}}'),
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
