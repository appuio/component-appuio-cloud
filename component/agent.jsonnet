/*
* Deploys the appuio-cloud-agent
*/
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.appuio_cloud;
local common = import 'common.libsonnet';

local image = params.images.agent;
local loadManifest(manifest) = std.parseJson(kap.yaml_load('appuio-cloud/agent/manifests/' + image.tag + '/' + manifest));

local serviceAccount = loadManifest('rbac/service_account.yaml') {
  metadata+: {
    namespace: params.namespace,
  },
};
local role = com.namespaced(params.namespace, loadManifest('rbac/role.yaml'));
local leaderElectionRole = com.namespaced(params.namespace, loadManifest('rbac/leader_election_role.yaml'));

local webhookCertDir = '/var/run/webhook-service-tls';

local mapSubjects = function(subjMap)
  std.foldl(
    function(subjects, ks)
      local s = subjMap[ks];
      if s.kind == 'Group' then
        subjects { groups+: [ s.name ] }
      else if s.kind == 'User' then
        subjects { users+: [ s.name ] }
      else if s.kind == 'ServiceAccount' then
        local name = 'system:serviceaccount:%s:%s' % [ s.namespace, s.name ];
        subjects { users+: [ name ] }
      else
        subjects,
    std.objectFields(subjMap),
    { groups: [], users: [] }
  );

local configMap = kube.ConfigMap('appuio-cloud-agent-config') {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    'config.yaml': std.manifestYamlDoc(params.agent.config {
      local subjects = mapSubjects(super._subjects),
      _subjects:: null,
      PrivilegedGroups: subjects.groups,
      PrivilegedUsers: subjects.users,
      PrivilegedClusterRoles: common.FlattenSet(super.PrivilegedClusterRoles),
    }),
  },
};

local deployment = loadManifest('manager/manager.yaml') {
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    replicas: params.agent.replicas,
    template+: {
      spec+: {
        containers: [
          if c.name == 'agent' then
            c {
              image: '%(registry)s/%(repository)s:%(tag)s' % image,
              args+: [
                '--webhook-cert-dir=' + webhookCertDir,
              ],
              volumeMounts+: [
                {
                  name: 'webhook-service-tls',
                  mountPath: webhookCertDir,
                  readOnly: true,
                },
              ],
            }
          else
            c
          for c in super.containers
        ],
        volumes+: [
          {
            name: 'webhook-service-tls',
            secret: {
              secretName: params.agent.webhook.tls.certSecretName,
            },
          },
        ],
      },
    },
  },
};

local admissionWebhookTlsSecret =
  assert std.length(params.agent.webhook.tls.certificate) > 0 : 'agent.webhook.tls.certificate is required';
  assert std.length(params.agent.webhook.tls.key) > 0 : 'agent.webhook.tls.key is required';
  kube.Secret(params.agent.webhook.tls.certSecretName) {
    metadata+: {
      namespace: params.namespace,
    },
    type: 'kubernetes.io/tls',
    stringData: {
      'tls.key': params.agent.webhook.tls.key,
      'tls.crt': params.agent.webhook.tls.certificate,
    },
  };

local admissionWebhook = loadManifest('webhook/manifests.yaml') {
  metadata+: {
    name: '%s-validating-webhook' % params.namespace,
  },
  webhooks: [
    w {
      clientConfig+: {
        [if std.length(params.agent.webhook.tls.caCertificate) > 0 then 'caBundle']:
          std.base64(params.agent.webhook.tls.caCertificate),
        service+: {
          namespace: params.namespace,
        },
      },
      namespaceSelector: params.agent.webhook.namespaceSelector,
    }
    for w in super.webhooks
  ],
};

local admissionWebhookService = loadManifest('webhook/service.yaml') {
  metadata+: {
    namespace: params.namespace,
  },
};

local metricsService = loadManifest('manager/service.yaml') {
  metadata+: {
    namespace: params.namespace,
    labels+: {
      'control-plane': 'appuio-cloud-agent',
      service: 'metrics',
    },
  },
};

{
  '01_role': role,
  '01_leader_election_role': leaderElectionRole,
  '01_role_binding': kube.ClusterRoleBinding(role.metadata.name) {
    roleRef: {
      kind: 'ClusterRole',
      apiGroup: 'rbac.authorization.k8s.io',
      name: role.metadata.name,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: serviceAccount.metadata.name,
        namespace: serviceAccount.metadata.namespace,
      },
    ],
  },
  '01_leader_election_role_binding': kube.RoleBinding(role.metadata.name) {
    metadata+: {
      namespace: params.namespace,
    },
    roleRef: {
      kind: 'Role',
      apiGroup: 'rbac.authorization.k8s.io',
      name: leaderElectionRole.metadata.name,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: serviceAccount.metadata.name,
        namespace: serviceAccount.metadata.namespace,
      },
    ],
  },
  '01_service_account': serviceAccount,
  '01_config_map': configMap,
  '02_webhook_cert_secret': admissionWebhookTlsSecret,
  '02_deployment': deployment,
  '10_webhook_config': admissionWebhook,
  '11_webhook_service': admissionWebhookService,
  '20_metrics_service': metricsService,
}
