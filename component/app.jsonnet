local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.appuio_cloud;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('appuio-cloud', params.namespace);

{
  'appuio-cloud': app,
}
