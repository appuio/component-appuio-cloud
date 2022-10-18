local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local resourceLocker = import 'lib/resource-locker.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

// See https://docs.openshift.com/container-platform/4.8/cicd/builds/securing-builds-by-strategy.html#builds-disabling-build-strategy-globally_securing-builds-by-strategy
local bindingToPatch = kube.ClusterRoleBinding('system:build-strategy-docker-binding');

local disallowDockerBuildStrategyPatch = {
  metadata: {
    annotations: {
      'rbac.authorization.kubernetes.io/autoupdate': 'false',
    },
  },
  subjects: [],
};

{
  [if params.disallowDockerBuildStrategy then '15_disallow_docker_build_strategy_patch']:
    resourceLocker.Patch(bindingToPatch, disallowDockerBuildStrategyPatch),
}
