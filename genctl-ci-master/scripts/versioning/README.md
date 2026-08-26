# AutoSemver: Automatic Semantic Versioning
AutoSemver is an automatic semantic versioning and release tagging tool. Upon the successful merge of a pull request, AutoSemver uses the previously tagged version and the conventional commit string to determine what the new version should be. Depending on the conventional commit *type*, it bumps either the major, minor, or patch version. Finally, it creates a lightweight git tag and GitHub release with the new version and the conventional commit message as the release body.

## Conventional Commit Types
Based on which *type* was specified in the conventional commit message, AutoSemver either bumps the patch, minor, or major version. For more information on the conventional commit spec, see [conventionalcommits.org](https://www.conventionalcommits.org/en/v1.0.0/). For more information on semantic versioning, see [semver.org](https://semver.org/).

### Minor Version Bump
Commits of *type* `feat`, `refactor`, `chore`, `vuln`, `fix` or `docs` will initiate a bump of the minor version. A minor version bump indicates added functionality in a backwards compatible manner.
```
feat: ABC-123: Add new feature to api
```

### Major Version Bump
Only feature commits that indicate a breaking change with `!` will initiate a bump of the major version. A major version bump indicates incompatible API changes.
```
feat!: ABC-123: Remove old api methods
```

## Hotfixes
AutoSemver also supports versioning for hotfixes. By passing the environment variable *`HOTFIX_VERSION` as a string with the major minor and patch version (e.g. `v2.6.0`), AutoSemver will determine the latest patch of that version tagged in the repository and bump the patch version.

*`HOTFIX_VERSION` should be a tag such as `X.X.0` (patch versions should always start with 0), patch version bumps are exclusively reserved for hotfixe versions.
