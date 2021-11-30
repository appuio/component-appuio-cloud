local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

/**
  * This policy will:
  * - Generate a RoleBinding to ClusterRole 'admin' for the organization defined in a label of a namespace.
  * - For namespaces created through a project, it mutates the `admin` RoleBinding to reference the organization instead of the creating user.
  * - Generate a RoleBinding and Role 'namespace-owner' for the organization defined in a label of a namespace, which allows the edit and delete the namespace.
  * - Namespaces that do not have the 'appuio.io/organization' label are not affected.
  * - The RoleBinding is only created upon Namespace creation.
  * - Also, the RoleBinding is mutable by the user.
  */
local generateDefaultRolebindingInNsPolicy = kyverno.ClusterPolicy('default-rolebinding-in-ns') {
  metadata+: {
    annotations+: {
      // Kyverno somehow detects this rule as needing controller autogeneration.
      // https://kyverno.io/docs/writing-policies/autogen/
      // Explicitly disable autogen. We don't need it here
      // since only Namespaces and RoleBinding are matched.
      'pod-policies.kyverno.io/autogen-controllers': 'none',
    },
  },
  spec: {
    rules: [
      {
        name: 'default-rolebinding',
        match: common.MatchOrgNamespaces,
        generate: {
          kind: 'RoleBinding',
          synchronize: false,
          name: params.generatedDefaultRoleBindingInNewNamespaces.bindingName,
          namespace: '{{request.object.metadata.name}}',
          data: {
            roleRef: {
              apiGroup: 'rbac.authorization.k8s.io',
              kind: 'ClusterRole',
              name: params.generatedDefaultRoleBindingInNewNamespaces.clusterRoleName,
            },
            subjects: [
              {
                kind: 'Group',
                name: '{{request.object.metadata.labels."appuio.io/organization"}}',
              },
            ],
          },
        },
      },
      {
        name: 'patch-uninitialized-default-rolebinding',
        match: common.MatchRoleBindings(
          names=[ params.generatedDefaultRoleBindingInNewNamespaces.bindingName ],
          selector={
            matchLabels: {
              'appuio.io/uninitialized': 'true',
            },
          },
        ),
        context: [
          {
            name: 'organization',
            apiCall: {
              urlPath: '/api/v1/namespaces/{{request.object.metadata.namespace}}',
              jmesPath: 'metadata.labels."appuio.io/organization"',
            },
          },
        ],
        mutate: {
          patchesJson6902: std.manifestYamlDoc(
            [
              {
                op: 'add',
                path: '/subjects',
                value: [
                  {
                    apiGroup: 'rbac.authorization.k8s.io',
                    kind: 'Group',
                    name: '{{organization}}',
                  },
                ],
                name: 'update-rolebinding',
              },
              {
                op: 'remove',
                path: '/metadata/labels/appuio.io~1uninitialized',
              },
            ]
          ),
        },

      },
      {
        name: 'namespace-edit-role',
        match: common.MatchOrgNamespaces,
        generate: {
          kind: 'Role',
          synchronize: false,
          name: params.generatedNamespaceOwnerRole.name,
          namespace: '{{request.object.metadata.name}}',
          data: {
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
          },
        },
      },
      {
        name: 'namespace-edit-rolebinding',
        match: common.MatchOrgNamespaces,
        generate: {
          kind: 'RoleBinding',
          synchronize: false,
          name: params.generatedNamespaceOwnerRole.name,
          namespace: '{{request.object.metadata.name}}',
          data: {
            roleRef: {
              apiGroup: 'rbac.authorization.k8s.io',
              kind: 'Role',
              name: params.generatedNamespaceOwnerRole.name,
            },
            subjects: [
              {
                kind: 'Group',
                name: '{{request.object.metadata.labels."appuio.io/organization"}}',
              },
            ],
          },
        },
      },
    ],
  },
};

// Define outputs below
{
  '10_generate_default_rolebinding_in_ns': generateDefaultRolebindingInNsPolicy + common.DefaultLabels,
}
