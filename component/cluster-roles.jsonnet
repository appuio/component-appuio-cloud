// main template for appuio-cloud
local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local legacyPatchOwnerRole(clusterRoles) =
  if std.objectHas(params, 'generatedNamespaceOwnerClusterRole') then
    std.trace(
      (
        '\nParameter `generatedNamespaceOwnerRole` is deprecated.'
      ),
      clusterRoles
      { 'namespace-owner': null } +
      {
        [params.generatedNamespaceOwnerClusterRole.name]: super['namespace-owner'],
      },
    )
  else clusterRoles;
local clusterRole(name) = kube.ClusterRole(name) + common.DefaultLabels;

{
  '10_additional_clusterroles': com.generateResources(legacyPatchOwnerRole(params.clusterRoles), clusterRole),
}
