#!/bin/sh

# Globally disable globbing and enable exit-on-error.
set -ef

is_installed() {
  if ! command -v "${1}" >/dev/null; then
    printf '%s\n' "Please install ${1} and run the script again."
    return 1
  fi
}

# Check if the required tools are installed.
is_installed jq
is_installed curl
is_installed zip

temporary_directory="$(mktemp -d)"

(
  cd "${temporary_directory}"

  for product in boundary consul nomad packer terraform vault; do
    latest_version="$(curl --silent --request GET "https://releases.hashicorp.com/${product}/index.json" |
      jq -r '.versions[].version' |
      sort -Vr |
      grep -v '-' |
      grep -v '+' |
      head -n 1)"

    curl --silent --request GET "https://releases.hashicorp.com/${product}/index.json" |
      jq -r '.versions[].version' |
      sort -Vr |
      grep -v '-' |
      grep -v 'musl' |
      grep -v 'fips1402' |
      grep "${latest_version}" |
      while read -r release; do
        curl -fL --silent -O "https://releases.hashicorp.com/${product}/${release}/${product}_${release}_SHA256SUMS"
        curl -fL --silent -O "https://releases.hashicorp.com/${product}/${release}/${product}_${release}_SHA256SUMS.72D7468F.sig"

        for os in windows linux; do
          curl -fL --silent -O "https://releases.hashicorp.com/${product}/${release}/${product}_${release}_${os}_amd64.zip" || true
        done
      done
  done
)

output_directory="${HOME}/Desktop"
printf '%s\n' "Saving the releases to '${output_directory}/hashicorp_releases.zip'..."

# Create an archive of the release files.
zip -jrq "${output_directory}/hashicorp_releases.zip" "${temporary_directory}"

# Cleanup the temporary directory.
rm -rf "${temporary_directory}"
