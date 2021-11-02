local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local quotaSpec(rq) =
  local hard = com.getValueOrDefault(rq, 'hard', {});
  local scopes = com.getValueOrDefault(rq, 'scopes', []);
  local scopeSel = com.getValueOrDefault(rq, 'scopeSelector', {});
  if std.objectHas(rq, 'spec') then
    com.makeMergeable(rq.spec) + {
      hard+: hard,
      [if std.length(scopes) > 0 then 'scopes']: (
        if 'scopes' in super then std.set(super.scopes) else
          std.set({})
      ) + std.set(scopes),
      [if std.length(std.objectFields(scopeSel)) > 0 then 'scopeSelector']+: scopeSel,
    }
  else
    {
      hard: rq.hard,
      scopes: rq.scopes,
      scopeSelector: rq.scopeSelector,
    };

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
            spec: quotaSpec(params.generatedResourceQuota[k]),
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
