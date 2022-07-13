// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');
local monitoringLabel =
  if isOpenshift then
    {
      'openshift.io/cluster-monitoring': 'true',
    }
  else
    {
      SYNMonitoring: 'main',
    };


{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      labels+: monitoringLabel {
        // Ensure the default network policies are not created in the
        // namespace, as we need to allow access to the validating webhook
        // from various agreggated API servers.
        'network-policies.syn.tools/no-defaults': 'true',
        'network-policies.syn.tools/purge-defaults': 'true',
      },
    },
  } + common.DefaultLabels,
}
