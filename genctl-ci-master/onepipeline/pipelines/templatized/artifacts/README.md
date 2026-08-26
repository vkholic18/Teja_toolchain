# Artifacts templates


## Basics
- There are two templates:
  - PR
  - merge
  
- These templates should be used for NON production artifacts because it does not support inventory flow

## Key aspects
- Does not have inventory flow
- Uses build.sh for building through generic-workspace-build.sh
- Uses run-unit-tests.sh for unit tests 
- Implements build and unit tests both in PR and merge (Either can be skipped with overrides)
- In the PR pipeline it does not upload images
- Implements auto-semver in merge pipeline (Can be skipped with overrides)

## Repositories that are suitable for using it

#### Non production images

Repositories that build an image that is not deployed in production (For example base images that are used to build other images)

#### Non production binaries

Binaries that are built and uploaded to some location (Note that if the upload is done by our code then it requires defining the artifacts in the build-meta.yaml file according to standard)

#### Libraries

Go libraries

Note that for libraries need to add the following overrides:

1. For PR pipeline

```yaml
skip-build: true
```

2. For merge pipeline

```yaml
create-tag-mode: gomod
skip-build: true
skip-unit-tests: true
```