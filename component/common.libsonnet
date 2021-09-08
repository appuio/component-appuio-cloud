local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local defaultLabels = {
  metadata+: {
    labels+: {
      'app.kubernetes.io/name': 'appuio-cloud',
      'app.kubernetes.io/component': 'appuio-cloud',
      'app.kubernetes.io/managed-by': 'commodore',
    },
  },
};

local flattenSet(set) = std.flatMap(function(s)
                                      if std.isArray(set[s]) then set[s] else [ set[s] ],
                                    std.objectFields(std.prune(set)));

/**
  * bypassNamespaceRestrictionsSubjects returns an object containing the configured roles and subjects
  * allowed to bypass restrictions.
  */
local bypassNamespaceRestrictionsSubjects() =
  local bypass = params.bypassNamespaceRestrictions;
  // FIXME: We would like to nest excludes under `all`. This doesn't work for
  // clusterRoles in Kyverno 1.4.2, cf. https://github.com/kyverno/kyverno/issues/2301
  {
    clusterRoles+: flattenSet(bypass.clusterRoles),
    roles+: flattenSet(bypass.roles),
    subjects+: flattenSet(bypass.subjects),
  };

local matchNamespaces(selector=null, names=null) = {
  all+: [ {
    resources+: std.prune({
      kinds+: [
        'Namespace',
      ],
      selector+: selector,
      names+: names,
    }),
  } ],
};

local matchOrgNamespaces = {
  resources: {
    kinds: [
      'Namespace',
    ],
    selector: {
      matchExpressions: [
        {
          key: 'appuio.io/organization',
          operator: 'Exists',
        },
      ],
    },
  },
};

{
  DefaultLabels: defaultLabels,
  FlattenSet: flattenSet,
  BypassNamespaceRestrictionsSubjects: bypassNamespaceRestrictionsSubjects,
  MatchNamespaces: matchNamespaces,
  MatchOrgNamespaces: matchOrgNamespaces,
}
