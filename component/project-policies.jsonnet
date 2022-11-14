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


local commonDocAnnotations = {
  'policies.kyverno.io/category': 'Namespace Ownership',
  'policies.kyverno.io/minversion': 'v1',
  'policies.kyverno.io/subject': 'APPUiO Organizations',
  'policies.kyverno.io/jsonnet': common.JsonnetFile(std.thisFile),
};
/**

  * Organization in ProjectRequests
  * This policy will:
  * - Check that the requesting user has the "appuio.io/default-organization" annotation.
  *   The content of the annotation is not further validated.
  *   It is assumed that the default organization is valid at the user object.
  */
local organizationInProject = kyverno.ClusterPolicy('organization-in-projectrequests') {
  metadata+: {
    annotations+: commonDocAnnotations {
      'policies.kyverno.io/title': "Check the requesting user's default organization for OpenShift ProjectRequests.",
      'policies.kyverno.io/description': |||
        This policy will check that the requesting user has the `appuio.io/default-organization` annotation.
        The content of the annotation isn't validated.
        Instead the policy assumes that any default organization annotations which are present on user objects are valid.

        If the requesting user doesn't have the `appuio.io/default-organization` annotation, the project request is denied.

        Users which match an entry of xref:references/parameters#_bypassnamespacerestrictions[component parameter `bypassNamespaceRestrictions`] are allowed to bypass the policy.
      |||,
    },
  },
  spec: {
    validationFailureAction: 'enforce',
    background: false,
    rules: [
      {
        name: 'user-has-default-organization',
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
        validate: {
          message: 'You cannot create Projects without belonging to an organization',
          deny: {
            conditions: {
              any: [
                // The `||` defaulting doesn't work as expected in this case for kyverno <1.8.0
                // So we first check that the user has an annotation 'appuio.io/default-organization'
                {
                  key: [ 'appuio.io/default-organization' ],
                  operator: 'AllNotIn',
                  value: '{{ocpuser.metadata.annotations.keys(@)}}',

                },
                {
                  key: '{{ocpuser.metadata.annotations."appuio.io/default-organization" || ""}}',
                  operator: 'Equals',
                  value: '',
                },
              ],
            },
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
