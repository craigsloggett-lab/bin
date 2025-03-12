#!/bin/sh

# Globally disable globbing and enable exit-on-error.
set -ef

# Check for required tools.
for tool in jq curl zip date; do
  if ! command -v "${tool}" >/dev/null; then
    printf '%s\n' "Error: Please install ${tool} and run the script again."
    exit 1
  fi
done

# Download release files.
temporary_directory="$(mktemp -d)"

(
  cd "${temporary_directory}"

  for product in boundary consul nomad nomad-autoscaler packer terraform vault; do
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
          # shellcheck disable=SC2043
          for arch in amd64; do
            download_url="https://releases.hashicorp.com/${product}/${release}/${product}_${release}_${os}_${arch}.zip"
            printf '%s\n' "-> Downloading ${download_url}..."
            curl -fL --silent -O "${download_url}" || true
          done
        done
      done
  done
)

# Create an archive of the release files.
archive_directory="${XDG_DOWNLOAD_DIR:-${HOME}/Downloads}/hashicorp-releases-$(date +"%Y%m%d%H%M%S").zip"
printf '%s\n' "-> Creating an archive of the releases in '${archive_directory}'..."
zip -jrq "${archive_directory}" "${temporary_directory}"

# Cleanup the temporary directory.
rm -rf "${temporary_directory}"
