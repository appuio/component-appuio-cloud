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
local bypassNamespaceRestrictionsSubjects() = {
  local bypass = params.bypassNamespaceRestrictions,
  clusterRoles+: flattenSet(bypass.clusterRoles),
  roles+: flattenSet(bypass.roles),
  subjects+: flattenSet(bypass.subjects),
};


{
  DefaultLabels: defaultLabels,
  FlattenSet: flattenSet,
  BypassNamespaceRestrictionsSubjects: bypassNamespaceRestrictionsSubjects,
}
