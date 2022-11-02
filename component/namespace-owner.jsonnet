// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local roleName =
  if std.objectHas(params, 'generatedNamespaceOwnerClusterRole') then
    std.trace(
      (
        '\nParameter `generatedNamespaceOwnerRole` is deprecated.'
      ),
      params.generatedNamespaceOwnerClusterRole.name
    )
  else
    'namespace-owner';

{
  '10_namespace_editor_clusterrole':
    kube.ClusterRole(roleName) {
      rules: [
        {
          apiGroups: [
            '',
          ],
          resources: [
            'namespaces',
          ],
          verbs: [
            'get',
            'watch',
            'edit',
            'patch',
            'delete',
          ],
        },
      ],
    } + common.DefaultLabels,
}
