# Low level release bundles templates

- There are two templates:
  - PR
  - PR with smoke
  - merge

- These templates should be used for release bundles such as hostOS, kube

## Key aspects
- Has update inventory flow
- Uses prepare low level release bundles for building the bundles
- Requires build-meta.yaml for the artifacts/inventory flow
- In PR, by default, it performs deploy dal (Can be skipped with override)
- Since it supports different "types" of release bundles, it is mandatory to define override defining the following:

```yaml
component: XXX # possible values: hostos, kube
```

Failure to do this will result in error of UNBOUND variable for COMPONENT in the prepare low level release bundle

## Repositories that are suitable for using it

#### Release bundles

Production release bundles