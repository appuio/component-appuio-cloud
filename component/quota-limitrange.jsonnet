local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local quotaAnnotationPrefix = 'resourcequota.appuio.io';

local quotaSpec(rn, rq) =
  local hard = com.getValueOrDefault(rq, 'hard', {});
  local scopes = com.getValueOrDefault(rq, 'scopes', []);
  local scopeSel = com.getValueOrDefault(rq, 'scopeSelector', {});
  local spec = if std.objectHas(rq, 'spec') then
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
  spec {
    hard: std.foldl(function(x, k) x {
      [k]:
        if std.length(std.findSubstr('storageclass.storage.k8s.io', k)) > 0 then
          "{{ parse_json(request.object.metadata.annotations.\"%s/%s.storageclasses\" || '{}').\"%s\" || '%s' }}" % [ quotaAnnotationPrefix, rn, k, x[k] ]
        else
          "{{ request.object.metadata.annotations.\"%s/%s.%s\" || '%s' }}" % [ quotaAnnotationPrefix, rn, std.strReplace(k, '/', '_'), x[k] ],
    }, std.objectFields(spec.hard), spec.hard),
  };


local generateQuotaLimitRangeInNsPolicy = kyverno.ClusterPolicy('quota-and-limit-range-in-ns') {
  metadata+: {
    annotations+: {
      'policies.kyverno.io/title': 'Create ResourceQuota and LimitRange objects in organization namespaces.',
      'policies.kyverno.io/category': 'Resource Quota',
      'policies.kyverno.io/minversion': 'v1',
      'policies.kyverno.io/subject': 'APPUiO Organizations',
      'policies.kyverno.io/jsonnet': common.JsonnetFile(std.thisFile),
      'policies.kyverno.io/description': |||
        This policy generates `ResourceQuota` and `LimitRange` objects in namespaces which have the `appuio.io/organization` label.

        The default values for the generated `ResourceQuota` and `LimitRange` objects are configured in component parameters xref:references/parameters.adoc#_generatedresourcequota[`generatedResourceQuota`] and xref:references/parameters.adoc#_generatedlimitrange[`generatedLimitRange`] respectively.

        Quota entries can be overridden for single namespaces by annotating the namespace, see the xref:references/parameters.adoc#_generatedresourcequota_spec[parameter docs] for an example.

        If field `synchronize` in the `ResourceQuota` or `LimitRange` component parameter is set to `true`, the policy is configured to continuously keep the generated objects in sync with the specification in the policy.
      |||,
    },
  },
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
            spec: quotaSpec(k, params.generatedResourceQuota[k]),
          },
        },
      }
      for k in std.objectFields(params.generatedResourceQuota)
    ],
  },
};

// Define outputs below
common.RemoveDisabledPolicies({
  [if !common.AgentFeatureEnabled('usage-profiles') then '11_generate_quota_limit_range_in_ns']: generateQuotaLimitRangeInNsPolicy + common.DefaultLabels,
})
