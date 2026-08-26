import re

# List of files to process
#The repos need to be cloned
files = [
    "/Users/andreis/develop/genesis/prod/razee-toolchains-ci-tf-module/razee_toolchains.tf",
    "/Users/andreis/develop/genesis/prod/artifacts-toolchains-ci-tf-module/artifacts_toolchains.tf",
    "/Users/andreis/develop/genesis/prod/globals-toolchains-ci-tf-module/globals_toolchains.tf",
    "/Users/andreis/develop/genesis/prod/one-off-toolchains-ci-tf-module/one_off_toolchains.tf",
    "/Users/andreis/develop/genesis/prod/prod-artifacts-toolchains-ci-tf-module/prod_artifacts_toolchains.tf",
    "/Users/andreis/develop/genesis/prod/release-bundles-toolchains-ci-tf-module/release_bundles_toolchains.tf",
    "/Users/andreis/develop/genesis/prod/sdn-toolchains-ci-tf-module/sdn_components_toolchains.tf",
]
# Output file to store results
output_file = "/Users/andreis/develop/genesis/andreis/testsemver/wokspacelist/CI-workspaces-list.txt"

# Regular expression to match lines starting with 'repo =' with varying spaces
pattern = r"^\s*repo\s*=\s*\"(.*?)\""

# Open the output file for writing
with open(output_file, "w") as out:
    # Process each file and extract matches
    for file in files:
        try:
            with open(file, "r") as f:
                content = f.read()
            matches = re.findall(pattern, content, re.MULTILINE)

            # Write matches to the output file
            #out.write(f"Matches in {file}:\n")
            for match in matches:
                out.write(match + "\n")
            out.write("-" * 40 + "\n")  # Separator for clarity
        except FileNotFoundError:
            out.write(f"File {file} not found. Skipping.\n")

print(f"Output written to {output_file}")
