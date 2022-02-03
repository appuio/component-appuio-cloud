local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;
local config = params.runOnceActiveDeadlineSeconds;

local defaultDeadline = config.defaultActiveDeadlineSeconds;
local annotationKey = config.overrideAnnotationKey;
local jmesPath =
  'to_number(merge(`%s`, metadata.annotations || `{}`)."%s" ) || `%s`' % [
    { [annotationKey]: defaultDeadline },
    annotationKey,
    defaultDeadline,
  ];

local matchExprs = std.prune([
  if config.podMatchExpressions[name] != null then
    {
      key: name,
    } + config.podMatchExpressions[name]
  for name in std.objectFields(config.podMatchExpressions)
]);

local policy =
  kyverno.ClusterPolicy('set-runonce-activedeadlineseconds') {
    metadata+: {
      annotations+: {
        'policies.kyverno.io/title': 'Set `activeDeadlineSeconds` for run-once pods.',
        'policies.kyverno.io/category': 'Resource Quota',
        'policies.kyverno.io/minversion': 'v1',
        'policies.kyverno.io/subject': 'APPUiO Organizations',
        'policies.kyverno.io/jsonnet': common.JsonnetFile(std.thisFile),
        'policies.kyverno.io/description': |||
          This policy ensures that all "runonce" pods have `.spec.activeDeadlineSeconds` set.

          The value for `.spec.activeDeadlineSeconds` for a namepsace can be overridden by adding annotation `%s` with the desired default value on a namespace.

          Pods can be excluded from the policy by configuring label match expressions in xref:references/parameters.adoc#_runonceactivedeadlineseconds_podmatchexpressions[component parameter `runOnceActiveDeadlineSeconds.podMatchExpressions`].
        ||| % [ annotationKey ],
        // Don't autogenerate policies for pod controllers, as we don't want
        // to inject the activeDeadlineSeconds into controller manifests such
        // as Jobs or CronJobs which may be managed by CD
        'pod-policies.kyverno.io/autogen-controllers': 'none',
      },
    },
    spec: {
      background: false,
      validationFailureAction: 'enforce',
      rules: [
        {
          name: 'set-runonce-activedeadlineseconds',
          context: [ {
            apiCall: {
              jmesPath: jmesPath,
              urlPath: '/api/v1/namespaces/{{request.namespace}}',
            },
            name: 'activeDeadlineSeconds',
          } ],
          match: {
            resources: {
              kinds: [
                'Pod',
              ],
              [if std.length(matchExprs) > 0 then 'selector']: {
                matchExpressions: matchExprs,
              },
            },
          },
          mutate: {
            patchStrategicMerge: {
              spec: {
                '(restartPolicy)': 'Never|OnFailure',
                '+(activeDeadlineSeconds)': '{{activeDeadlineSeconds}}',
              },
            },
          },
        },
      ],
    },
  };

{
  '30_set_runonce_activedeadlineseconds': policy + common.DefaultLabels,
}
