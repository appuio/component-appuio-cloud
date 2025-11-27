local kube = import 'kube-ssa-compat.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appuio_cloud;

local projectTemplate =
  kube._Object('template.openshift.io/v1', 'Template', 'project-request') {
    metadata+: {
      namespace: 'openshift-config',
    },
    objects: [
      params.projectTemplate.objects[o]
      for o in std.objectFields(params.projectTemplate.objects)
      if params.projectTemplate.objects[o] != null
    ],
    parameters: [
      { name: p } + params.projectTemplate.parameters[p]
      for p in std.objectFields(params.projectTemplate.parameters)
      if params.projectTemplate.parameters[p] != null

    ],
  };

local ocpProjectConfig =
  kube._Object('config.openshift.io/v1', 'Project', 'cluster') {
    spec: {
      [if params.projectTemplate.enabled then 'projectRequestTemplate']: {
        name: projectTemplate.metadata.name,
      },
    },
  };

{
  '20_project_template': std.filter(
    function(it) it != null,
    [
      ocpProjectConfig,
      if params.projectTemplate.enabled then projectTemplate,
    ]
  ),
}
