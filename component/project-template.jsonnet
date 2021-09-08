local kube = import 'lib/kube.libjsonnet';
local projectTemplate =
  kube._Object('template.openshift.io/v1', 'Template', 'project-request') {
    metadata+: {
      namespace: 'openshift-config',
    },
    objects: [
      {
        apiVersion: 'project.openshift.io/v1',
        kind: 'Project',
        metadata: {
          annotations: {
            'openshift.io/description': '${PROJECT_DESCRIPTION}',
            'openshift.io/display-name': '${PROJECT_DISPLAYNAME}',
            'openshift.io/requester': '${PROJECT_REQUESTING_USER}',
          },
          name: '${PROJECT_NAME}',
        },
      },
    ],
    parameters: [
      { name: 'PROJECT_NAME' },
      { name: 'PROJECT_DISPLAYNAME' },
      { name: 'PROJECT_DESCRIPTION' },
      { name: 'PROJECT_ADMIN_USER' },
      { name: 'PROJECT_REQUESTING_USER' },
    ],
  };

local ocpProjectConfig =
  kube._Object('config.openshift.io/v1', 'Project', 'cluster') {
    spec: {
      projectRequestTemplate: {
        name: projectTemplate.metadata.name,
      },
    },
  };

{
  '20_project_template': [
    ocpProjectConfig,
    projectTemplate,
  ],
}
