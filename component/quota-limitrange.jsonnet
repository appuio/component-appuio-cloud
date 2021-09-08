local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;


local generateQuotaLimitRangeInNsPolicy = kyverno.ClusterPolicy('quota-and-limit-range-in-ns') {
  spec: {
    rules: [
      {
        name: 'generate-quota',
        match: common.MatchOrgNamespaces,
        generate: {
          kind: 'ResourceQuota',
          synchronize: params.generatedResourceQuota.synchronize,
          name: params.generatedResourceQuota.name,
          namespace: '{{request.object.metadata.name}}',
          data: {
            spec: {
              hard: params.generatedResourceQuota.hard,
              scopes: params.generatedResourceQuota.scopes,
              scopeSelector: params.generatedResourceQuota.scopeSelector,
            },
          },
        },
      },
      {
        name: 'generate-limit-range',
        match: common.MatchOrgNamespaces,
        generate: {
          kind: 'LimitRange',
          synchronize: params.generatedLimitRange.synchronize,
          name: params.generatedLimitRange.name,
          namespace: '{{request.object.metadata.name}}',
          data: {
            spec: {
              limits: [
                params.generatedLimitRange.limits[k] {
                  type+: k,
                }
                for k in std.objectFields(params.generatedLimitRange.limits)
              ],
            },
          },
        },
      },
    ],
  },
};

// Define outputs below
{
  '20_generate_quota_limit_range_in_ns': generateQuotaLimitRangeInNsPolicy + common.DefaultLabels,
}
