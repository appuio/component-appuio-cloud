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
  'to_number(merge(`%s`, metadata.annotations)."%s")' % [
    { [annotationKey]: defaultDeadline },
    annotationKey,
  ];

local policy =
  kyverno.ClusterPolicy('set-runonce-activedeadlineseconds') {
    metadata+: {
      annotations+: {
        'kyverno.syn.tools/policy-description': (
          'This policy ensures that all "runonce" pods have '
          + '`.spec.activeDeadlineSeconds` set. The value for '
          + '`.spec.activeDeadlineSeconds` for a namepsace can '
          + 'be overridden by adding annotation `%s` with the desired '
          + 'default value on a namespace.'
        ) % [ annotationKey ],
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
