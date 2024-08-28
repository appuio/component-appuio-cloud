local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.appuio_cloud;

local dir = std.extVar('output_path');
local disabled = std.prune(params.disable_kyverno_cluster_policies);

local fix = function(o)
  if o.apiVersion == 'kyverno.io/v1' && o.kind == 'ClusterPolicy' && std.length(std.find(o.metadata.name, disabled)) > 0 then
    {}
  else
    o;

com.fixupDir(dir, fix)
