local common = import 'common.libsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.appuio_cloud;

local metadataPatch = {
  annotations+: {
    'syn.tools/source': 'https://github.com/appuio/component-appuio-cloud.git',
  },
  labels+: {
    'app.kubernetes.io/managed-by': 'espejote',
    'app.kubernetes.io/part-of': 'syn',
    'app.kubernetes.io/component': 'appuio-cloud',
  },
};

// See https://docs.openshift.com/container-platform/4.8/cicd/builds/securing-builds-by-strategy.html#builds-disabling-build-strategy-globally_securing-builds-by-strategy
local patch = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'ClusterRoleBinding',
  metadata: {
    annotations: {
      'rbac.authorization.kubernetes.io/autoupdate': 'false',
    },
    name: 'system:build-strategy-docker-binding',
  },
  subjects: [],
};

local serviceAccount = {
  apiVersion: 'v1',
  kind: 'ServiceAccount',
  metadata: {
    name: 'rbac-clusterrolebinding-system-build-strategy-docker-binding',
    namespace: inv.parameters.espejote.namespace,
  } + metadataPatch,
};

local clusterRole = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'ClusterRole',
  metadata: {
    name: 'syn-espejote:rbac-clusterrolebinding-system-build-strategy-docker-binding',
  } + metadataPatch,
  rules: [
    {
      apiGroups: [ 'rbac.authorization.k8s.io' ],
      resources: [ 'clusterrolebindings' ],
      resourceNames: [ 'system:build-strategy-docker-binding' ],
      verbs: [ '*' ],
    },
  ],
};

local clusterRoleBinding = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'ClusterRoleBinding',
  metadata: {
    name: 'syn-espejote:rbac-clusterrolebinding-system-build-strategy-docker-binding',
  } + metadataPatch,
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: clusterRole.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: serviceAccount.metadata.name,
      namespace: serviceAccount.metadata.namespace,
    },
  ],
};

local managedResource = esp.managedResource('rbac-clusterrolebinding-system-build-strategy-docker-binding', inv.parameters.espejote.namespace) {
  metadata+: metadataPatch,
  spec: {
    applyOptions: {
      force: true,
    },
    serviceAccountRef: {
      name: serviceAccount.metadata.name,
    },
    template: std.manifestJson(patch),
    triggers: [ {
      name: 'clusterrolebinding',
      watchResource: {
        apiVersion: patch.apiVersion,
        kind: patch.kind,
        name: patch.metadata.name,
      },
    } ],
  },
};

{
  [if params.disallowDockerBuildStrategy then '15_disallow_docker_build_strategy_patch']: [
    serviceAccount,
    clusterRole,
    clusterRoleBinding,
    managedResource,
  ],
}
