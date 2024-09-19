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

/**
  * appuio-ns-provisioner role allows to create namespaces
  */
local appuioNsProvisionerRole = kube.ClusterRole('appuio-ns-provisioner') {
  rules: [
    {
      apiGroups: [
        '',
      ],
      resources: [
        'namespaces',
      ],
      verbs: [
        'create',
      ],
    },
  ],
};

/**
  * appuio-ns-provisioners cluster role binding allows authenticated users to create namespaces
  */
local appuioNsProvisionersRoleBinding = kube.ClusterRoleBinding('appuio-ns-provisioners') {
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'appuio-ns-provisioner',
  },
  subjects: [
    {
      kind: 'Group',
      name: 'system:authenticated:oauth',
    },
    {
      kind: 'Group',
      name: 'system:serviceaccounts',
    },
  ],
};

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      labels+: namespaceLabels,
      annotations+: namespaceAnnotations,
    },
  } + common.DefaultLabels,
  '00_secrets': secrets,

  '01_appuio_ns_provisioner_role': appuioNsProvisionerRole + common.DefaultLabels,
  '01_appuio_ns_provisioners_crb': appuioNsProvisionersRoleBinding + common.DefaultLabels,

}
