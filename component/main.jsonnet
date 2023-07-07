// main template for appuio-cloud
local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');
local namespaceLabels = (
  if isOpenshift then { 'openshift.io/cluster-monitoring': 'true' }
  else { SYNMonitoring: 'main' }
) + params.namespaceLabels;
local namespaceAnnotations = (
  if isOpenshift then { 'openshift.io/node-selector': '' }
  else {}
) + params.namespaceAnnotations;

local secrets = com.generateResources(params.secrets, function(name) com.namespaced(params.namespace, kube.Secret(name) + common.DefaultLabels));

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      labels+: namespaceLabels,
      annotations+: namespaceAnnotations,
    },
  } + common.DefaultLabels,
  '00_secrets': secrets,
}
