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

local orgLabelSelector = {
  matchExpressions: [
    {
      key: 'appuio.io/organization',
      operator: 'Exists',
    },
  ],
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

local matchKinds(selector=null, names=null, match='all', kinds) = {
  [match]+: [ {
    resources+: std.prune({
      kinds+: kinds,
      selector+: selector,
      names+: names,
    }),
  } ],
};

local matchNamespaces(selector=null, names=null, match='all') = matchKinds(selector, names, match, kinds=[ 'Namespace' ]);

local matchProjectRequests(selector=null, names=null, match='all') = matchKinds(selector, names, match, kinds=[ 'ProjectRequest' ]);

local matchRoleBindings(selector=null, names=null, match='all') = matchKinds(selector, names, match, kinds=[ 'rbac.authorization.k8s.io/v1/RoleBinding' ]);

local matchOrgNamespaces = matchNamespaces(selector=orgLabelSelector);

local matchNamespacesAndProjectRequests(selector=null, names=null, match='all') =
  matchKinds(selector, names, match, kinds=[ 'Namespace', 'ProjectRequest' ]);

local kyvernoPatternToRegex = function(pattern)
  '^%s$' % std.strReplace(std.strReplace(pattern, '?', '.'), '*', '.*');

local jsonnetFile(filename) =
  local parts = std.split(filename, '/');
  local pcount = std.length(parts);
  '%s/%s' % [ parts[pcount - 2], parts[pcount - 1] ];

{
  DefaultLabels: defaultLabels,
  FlattenSet: flattenSet,
  BypassNamespaceRestrictionsSubjects: bypassNamespaceRestrictionsSubjects,
  MatchNamespaces: matchNamespaces,
  MatchNamespacesAndProjectRequests: matchNamespacesAndProjectRequests,
  MatchOrgNamespaces: matchOrgNamespaces,
  MatchProjectRequests: matchProjectRequests,
  MatchRoleBindings: matchRoleBindings,
  KyvernoPatternToRegex: kyvernoPatternToRegex,
  JsonnetFile: jsonnetFile,
}
