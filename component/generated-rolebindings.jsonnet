local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

/**
  * This policy will:
  * - Generate a RoleBinding to ClusterRole 'admin' for the organization defined in a label of a namespace.
  * - Namespaces that do not have the 'appuio.io/organization' label are not affected.
  * - The RoleBinding is only created upon Namespace creation.
  * - Also, the RoleBinding is mutable by the user.
  */
local generateDefaultRolebindingInNsPolicy = kyverno.ClusterPolicy('default-rolebinding-in-ns') {
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
