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

  for provider in boundary consul external nomad null tfe vault; do
    curl --silent --request GET "https://releases.hashicorp.com/terraform-provider-${provider}/index.json" |
      jq -r '.versions[].version' |
      sort -Vr |
      head -n 1 |
      while read -r release; do
        curl -fL --silent -O "https://releases.hashicorp.com/terraform-provider-${provider}/${release}/terraform-provider-${provider}_${release}_SHA256SUMS"
        curl -fL --silent -O "https://releases.hashicorp.com/terraform-provider-${provider}/${release}/terraform-provider-${provider}_${release}_SHA256SUMS.72D7468F.sig"
        for os in windows linux; do
          # shellcheck disable=SC2043
          for arch in amd64; do
            download_url="https://releases.hashicorp.com/terraform-provider-${provider}/${release}/terraform-provider-${provider}_${release}_${os}_${arch}.zip"
            printf '%s\n' "-> Downloading ${download_url}..."
            curl -fL --silent -O "${download_url}" || true
          done
        done
      done
  done
)

# Create an archive of the release files.
archive_directory="${XDG_DOWNLOAD_DIR:-${HOME}/Downloads}/hashicorp-providers-$(date +"%Y%m%d%H%M%S").zip"
printf '%s\n' "-> Creating an archive of the releases in '${archive_directory}'..."
zip -jrq "${archive_directory}" "${temporary_directory}"

# Cleanup the temporary directory.
rm -rf "${temporary_directory}"
