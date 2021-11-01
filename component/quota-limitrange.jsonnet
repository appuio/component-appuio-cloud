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
    ] + [
      {
        name: 'generate-quota-' + k,
        match: common.MatchOrgNamespaces,
        generate: {
          kind: 'ResourceQuota',
          synchronize: params.generatedResourceQuota[k].synchronize,
          name: k,
          namespace: '{{request.object.metadata.name}}',
          data: {
            spec: params.generatedResourceQuota[k].spec,
          },
        },
      }
      for k in std.objectFields(params.generatedResourceQuota)
    ],
  },
};

// Define outputs below
{
  '11_generate_quota_limit_range_in_ns': generateQuotaLimitRangeInNsPolicy + common.DefaultLabels,
}
