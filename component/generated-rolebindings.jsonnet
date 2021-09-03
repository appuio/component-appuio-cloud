local common = import 'common.libsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
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
        match: {
          resources: {
            kinds: [
              'Namespace',
            ],
            selector: {
              matchExpressions: [
                {
                  key: 'appuio.io/organization',
                  operator: 'Exists',
                },
              ],
            },
          },
        },
        generate: {
          kind: 'RoleBinding',
          synchronize: false,
          name: 'admin',
          namespace: '{{request.object.metadata.name}}',
          data: {
            roleRef: {
              apiGroup: 'rbac.authorization.k8s.io',
              kind: 'ClusterRole',
              name: 'admin',
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
