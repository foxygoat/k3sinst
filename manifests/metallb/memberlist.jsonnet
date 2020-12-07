{
  apiVersion: 'v1',
  kind: 'Secret',
  metadata: {
    namespace: 'metallb-system',
    name: 'memberlist',
  },
  data: {
    secretkey: std.base64(std.extVar('rand')),
  },
}
