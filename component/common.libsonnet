local DefaultLabels = {
  metadata+: {
    labels+: {
      'app.kubernetes.io/name': 'appuio-cloud',
      'app.kubernetes.io/component': 'appuio-cloud',
      'app.kubernetes.io/managed-by': 'commodore',
    },
  },
};

{
  DefaultLabels: DefaultLabels,
}
