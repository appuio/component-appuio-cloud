local kube = import 'kube-ssa-compat.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prom = import 'lib/prom.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.appuio_cloud;


local sm =
  prom.ServiceMonitor('appuio-cloud-agent') {
    metadata+: {
      namespace: params.namespace,
      labels+: {
        'control-plane': 'appuio-cloud-agent',
        service: 'metrics',
      },
    },
    spec: {
      endpoints: [ {
        port: 'metrics-port',
      } ],
      namespaceSelector: { matchNames: [ params.namespace ] },
      selector: {
        matchLabels: {
          'control-plane': 'appuio-cloud-agent',
          service: 'metrics',
        },
      },
    },
  };

if params.monitoring.enabled then
  {
    '10_monitoring/00_servicemonitor-appuio-cloud-agent': sm,
  }
else
  {}
