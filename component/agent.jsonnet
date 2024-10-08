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
local loadManifests(manifest) = std.parseJson(kap.yaml_load_stream('appuio-cloud/agent/manifests/' + image.tag + '/' + manifest));

local agentVersion =
  if !std.startsWith(image.tag, 'v') then
    // report version which has usageprofiles if not a tag
    {
      major: 0,
      minor: 10,
      patch: 0,
    }
  else
    local verparts = std.map(std.parseInt, std.split(image.tag[1:], '.'));
    if std.length(verparts) >= 3 then
      {
        major: verparts[0],
        minor: verparts[1],
        patch: verparts[2],
      }
    else if std.length(verparts) >= 2 then
      {
        major: verparts[0],
        minor: verparts[1],
        patch: 0,
      };

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


local defaultOrganizationClusterRoles = std.prune(
  params.agent.config.DefaultOrganizationClusterRoles
  + (
    if std.objectHas(params, 'generatedDefaultRoleBindingInNewNamespaces') then
      std.trace(
        '\nParameter "generatedDefaultRoleBindingInNewNamespaces" is deprecated. Please use "agent.config.DefaultOrganizationClusterRoles"',
        { admin: null }
        +
        {
          [params.generatedDefaultRoleBindingInNewNamespaces.bindingName]: params.generatedDefaultRoleBindingInNewNamespaces.clusterRoleName,
        }
      )
    else {}
  )
  + (
    if std.objectHas(params, 'generatedNamespaceOwnerClusterRole') then
      std.trace(
        '\nParameter "generatedNamespaceOwnerClusterRole" is deprecated. Please use "agent.config.DefaultOrganizationClusterRoles"',
        { 'namespace-owner': null }
        +
        {
          [params.generatedNamespaceOwnerClusterRole.name]: params.generatedNamespaceOwnerClusterRole.name,
        }
      )
    else {}
  )
);


local configMap =
  local cleanConfig = {
    [k]: params.agent.config[k]
    for k in std.objectFields(params.agent.config)
    if params.agent.config[k] != null
  };
  kube.ConfigMap('appuio-cloud-agent-config') {
    metadata+: {
      namespace: params.namespace,
    },
    data: {
      'config.yaml': std.manifestYamlDoc(cleanConfig {
        local subjects = mapSubjects(super._subjects),
        _subjects:: null,
        PrivilegedGroups: subjects.groups,
        PrivilegedUsers: subjects.users,
        PrivilegedClusterRoles: common.FlattenSet(super.PrivilegedClusterRoles),
        DefaultOrganizationClusterRoles: defaultOrganizationClusterRoles,

        ReservedNamespaces: common.FlattenSet(super._reservedNamespaces),
        _reservedNamespaces:: null,
        AllowedAnnotations: common.FlattenSet(super._allowedAnnotations),
        _allowedAnnotations:: null,
        AllowedLabels: common.FlattenSet(super._allowedLabels),
        _allowedLabels:: null,

        local legacyDefaultResourceQuotas = super._LegacyDefaultResourceQuotas,
        LegacyDefaultResourceQuotas: std.foldl(function(prev, k) prev { [k]: legacyDefaultResourceQuotas[k] + legacyDefaultResourceQuotas[k].spec { spec:: null } }, std.objectFields(legacyDefaultResourceQuotas), {}),
        _LegacyDefaultResourceQuotas:: null,

        local legacyDefaultLimitRange = super._LegacyDefaultLimitRange,
        LegacyDefaultLimitRange: {
          limits: std.map(function(l) legacyDefaultLimitRange._limits[l] { type: l }, std.objectFields(legacyDefaultLimitRange._limits)),
        },
        _LegacyDefaultLimitRange:: null,
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
      metadata+: {
        annotations+: {
          'checksum/config': std.md5(std.manifestJsonMinified(configMap.data)),
        },
      },
      spec+: {
        containers: [
          if c.name == 'agent' then
            c {
              image: '%(registry)s/%(repository)s:%(tag)s' % image,
              args+: [
                '--webhook-cert-dir=' + webhookCertDir,
              ] + params.agent.extraArgs,
              env+: com.envList(params.agent.extraEnv),
              resources+: com.makeMergeable(params.agent.resources),
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
        nodeSelector: params.agent.nodeSelector,
        tolerations: params.agent.tolerations,
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

local formatWebhookObjectSelector = function(obj)
  if std.objectHas(obj, '_objectSelector') then
    local me = obj._objectSelector.matchExpressions;
    obj {
      objectSelector+: {
        matchExpressions: std.prune([
          if me[name] != null then
            {
              key: name,
            } + me[name]
          for name in std.objectFields(me)
        ]),
      },
      _objectSelector:: null,
    }
  else
    obj
;

local admissionWebhook = std.map(function(webhook) webhook {
  metadata+: {
    name: '%s-%s' % [ params.namespace, webhook.metadata.name ],
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
      // Inject namespace selector for objects that are not namespaces or projects
      [if !(
        std.length(
          std.filter(
            function(r) std.length(
              std.setInter(
                std.set([ 'projects', 'projectrequests', 'namespaces' ]),
                std.set(r.resources),
              )
            ) > 0, w.rules
          )
        ) > 0
      ) then 'namespaceSelector']: params.agent.webhook.namespaceSelector,
    } + com.makeMergeable(formatWebhookObjectSelector(std.get(params.agent.webhook.patches, w.name, {})))
    for w in super.webhooks
  ],
}, loadManifests('webhook/manifests.yaml'));

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
  // TODO(bastjan) we should switch to kustomize
  [if agentVersion.minor >= 10 then
    '00_crds/cloudagent.appuio.io_zoneusageprofiles'
  ]:
    loadManifest('crd/bases/cloudagent.appuio.io_zoneusageprofiles.yaml'),
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
  '01_default_org_role_binding': [
    // The agent needs to have all the permissions it should delegate, so we create a ClusterRoleBinding for every ClusterRole it needs to be able to create
    kube.ClusterRoleBinding('appuio-cloud-agent:%s' % [ cr ]) {
      roleRef: {
        kind: 'ClusterRole',
        apiGroup: 'rbac.authorization.k8s.io',
        name: cr,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: serviceAccount.metadata.name,
          namespace: serviceAccount.metadata.namespace,
        },
      ],
    }
    for cr in std.objectValues(defaultOrganizationClusterRoles)
  ],
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
