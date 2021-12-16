// main template for appuio-cloud
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local kyverno = import 'lib/kyverno.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appuio_cloud;

// NOTES
// https://github.com/kyverno/kyverno/issues/2106 - Failing to substitute variables should not cause rule skipping
// -> This is an important side effect as failed variable substitutions will result in empty strings.


/**
  * Organization in ProjectRequests
  * This policy will:
  * - Check that the requesting user has the "appuio.io/default-organization" annotation.
  *   The content of the annotation is not further validated.
  *   It is assumed that the default organization is valid at the user object.
  */
local organizationInProject = kyverno.ClusterPolicy('organization-in-projectrequests') {
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'set-default-organization',
        match: common.MatchProjectRequests(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        context: [
          {
            name: 'ocpuser',
            apiCall: {
              urlPath: '/apis/user.openshift.io/v1/users/{{request.userInfo.username}}',
              // We want the full output of the API call. Despite the docs not
              // saying anything, if we omit jmesPath here, we don't get the
              // variable ocpuser in the resulting context at all. Instead, we
              // provide '@' for jmesPath which responds to the current
              // element, giving us the full response as ocpuser.
              jmesPath: '@',
            },
          },
        ],
        mutate: {
          patchStrategicMerge: {
            metadata: {
              // In the case of a system user, with Kyverno 1.4.2+ the key will be empty
              // if the annotations object is empty.
              labels: {
                '+(appuio.io/organization)':
                  '{{ocpuser.metadata.annotations."appuio.io/default-organization"}}',
              },
            },
          },
        },
      },
      {
        name: 'user-has-default-organization',
        match: common.MatchProjectRequests(),
        exclude: common.BypassNamespaceRestrictionsSubjects(),
        validate: {
          message: 'You cannot create Projects without belonging to an organization',
          deny: {
            conditions: [
              {
                key: '{{request.object.metadata.labels."appuio.io/organization"}}',
                operator: 'Equals',
                value: '',
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
  '03_projectrequest': organizationInProject + common.DefaultLabels,
}
